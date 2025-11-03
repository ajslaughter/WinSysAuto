function Resolve-BaselinePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$ScriptRoot
    )

    if (Test-Path -LiteralPath $Path) {
        return (Resolve-Path -LiteralPath $Path).Path
    }

    $baselineDirectory = Join-Path -Path $ScriptRoot -ChildPath '..'
    $baselineDirectory = Join-Path -Path (Resolve-Path -LiteralPath $baselineDirectory).Path -ChildPath 'baselines'
    $candidate = Join-Path -Path $baselineDirectory -ChildPath $Path

    if (-not (Test-Path -LiteralPath $candidate)) {
        throw "Baseline definition '$Path' was not found in '$baselineDirectory'."
    }

    return (Resolve-Path -LiteralPath $candidate).Path
}

function Import-BaselineDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $extension = [System.IO.Path]::GetExtension($Path)
    $raw = Get-Content -LiteralPath $Path -Raw

    switch ($extension.ToLowerInvariant()) {
        '.json' { return $raw | ConvertFrom-Json }
        '.yml' { break }
        '.yaml' { break }
        default { throw "Unsupported baseline format '$extension'. Use JSON or YAML." }
    }

    $converter = Get-Command -Name ConvertFrom-Yaml -ErrorAction SilentlyContinue
    if (-not $converter) {
        throw "Baseline '$Path' is YAML but ConvertFrom-Yaml is unavailable. Install PowerShell 7+ or the powershell-yaml module."
    }

    return $raw | ConvertFrom-Yaml
}

function Compare-ObjectProperties {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Current,
        [Parameter(Mandatory = $true)]
        [psobject]$Desired
    )

    $differences = @()
    foreach ($property in $Desired.PSObject.Properties) {
        $name = $property.Name
        $expected = $property.Value
        $actualProperty = $Current.PSObject.Properties[$name]
        $actual = if ($actualProperty) { $actualProperty.Value } else { $null }

        if ($actual -is [array]) {
            $actual = ($actual -join ',')
        }

        if ($expected -is [array]) {
            $expected = ($expected -join ',')
        }

        if ($actual -ne $expected) {
            $differences += [pscustomobject]@{
                Property = $name
                Current  = $actual
                Desired  = $expected
            }
        }
    }

    return $differences
}

function Get-PasswordPolicy {
    [CmdletBinding()]
    param()

    $temp = Join-Path -Path $env:TEMP -ChildPath ("policy-" + [guid]::NewGuid() + '.inf')
    try {
        & secedit.exe /export /cfg $temp /quiet | Out-Null
        $content = Get-Content -LiteralPath $temp
    }
    finally {
        if (Test-Path -LiteralPath $temp) {
            Remove-Item -LiteralPath $temp -ErrorAction SilentlyContinue
        }
    }

    $policy = @{}
    $section = ''
    foreach ($line in $content) {
        if ($line -match '^\s*#') { continue }
        if ($line -match '^\[(.+)\]') {
            $section = $Matches[1]
            continue
        }

        if ($section -ne 'System Access') { continue }

        if ($line -match '^(?<key>[^=]+)=(?<value>.+)$') {
            $key = $Matches['key'].Trim()
            $value = $Matches['value'].Trim()
            $policy[$key] = $value
        }
    }

    return [pscustomobject]$policy
}

function Set-PasswordPolicy {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$DesiredPolicy
    )

    $current = Get-PasswordPolicy

    $mapping = @{
        MinimumPasswordLength        = 'MinimumPasswordLength'
        MaximumPasswordAgeDays       = 'MaximumPasswordAge'
        MinimumPasswordAgeDays       = 'MinimumPasswordAge'
        PasswordHistorySize          = 'PasswordHistorySize'
        ComplexityEnabled            = 'PasswordComplexity'
        LockoutThreshold             = 'LockoutBadCount'
        LockoutDurationMinutes       = 'LockoutDuration'
        ResetLockoutCounterMinutes   = 'ResetLockoutCount'
    }

    $changes = @{}
    foreach ($property in $DesiredPolicy.PSObject.Properties) {
        $desiredValue = $property.Value
        $policyKey = $mapping[$property.Name]
        if (-not $policyKey) { continue }

        switch ($property.Name) {
            'ComplexityEnabled' {
                $desiredValue = if ($property.Value) { '1' } else { '0' }
            }
            default {
                $desiredValue = [string][int]$property.Value
            }
        }

        $currentProperty = $current.PSObject.Properties[$policyKey]
        $currentValue = if ($currentProperty) { $currentProperty.Value } else { $null }
        if ($currentValue -ne $desiredValue) {
            $changes[$policyKey] = $desiredValue
        }
    }

    if ($changes.Count -eq 0) {
        return [pscustomobject]@{
            Changed              = $false
            Differences          = @()
            RemainingDifferences = @()
        }
    }

    $differenceList = $changes.GetEnumerator() | ForEach-Object {
        $existing = $current.PSObject.Properties[$_.Key]
        [pscustomobject]@{ Property = $_.Key; Desired = $_.Value; Previous = if ($existing) { $existing.Value } else { $null } }
    }

    if (-not $PSCmdlet.ShouldProcess('Local Security Policy', 'Apply password policy changes')) {
        return [pscustomobject]@{
            Changed              = $false
            Differences          = $differenceList
            RemainingDifferences = $differenceList
        }
    }

    $infContent = "[Unicode]`r`nUnicode=yes`r`n[Version]`r`nsignature=`"$CHICAGO$`"`r`nRevision=1`r`n[System Access]`r`n"
    foreach ($entry in $changes.GetEnumerator()) {
        $infContent += "{0} = {1}`r`n" -f $entry.Key, $entry.Value
    }

    $infPath = Join-Path -Path $env:TEMP -ChildPath ("baseline-" + [guid]::NewGuid() + '.inf')
    $dbPath = Join-Path -Path $env:TEMP -ChildPath ("baseline-" + [guid]::NewGuid() + '.sdb')
    try {
        Set-Content -LiteralPath $infPath -Value $infContent -Encoding Unicode
        & secedit.exe /configure /db $dbPath /cfg $infPath /quiet | Out-Null
    }
    finally {
        foreach ($path in @($infPath, $dbPath)) {
            if (Test-Path -LiteralPath $path) {
                Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
            }
        }
    }

    $postState = Get-PasswordPolicy
    $remaining = @()
    foreach ($change in $changes.GetEnumerator()) {
        $policyKey = $change.Key
        $desiredValue = $change.Value
        $postProperty = $postState.PSObject.Properties[$policyKey]
        $postValue = if ($postProperty) { $postProperty.Value } else { $null }
        if ($postValue -ne $desiredValue) {
            $remaining += [pscustomobject]@{ Property = $policyKey; Desired = $desiredValue; Actual = $postValue }
        }
    }

    return [pscustomobject]@{
        Changed              = $true
        Differences          = $differenceList
        RemainingDifferences = $remaining
    }
}

function Set-FirewallBaseline {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Settings
    )

    $results = @()
    foreach ($profileName in @('Domain', 'Private', 'Public')) {
        if (-not $Settings.PSObject.Properties[$profileName]) { continue }
        $desired = $Settings.$profileName
        $current = Get-NetFirewallProfile -Profile $profileName
        $differences = Compare-ObjectProperties -Current $current -Desired $desired

        if ($differences.Count -eq 0) {
            $results += [pscustomobject]@{
                Profile             = $profileName
                Changed             = $false
                Differences         = @()
                RemainingDifferences = @()
            }
            continue
        }

        if ($PSCmdlet.ShouldProcess("Firewall profile '$profileName'", 'Update firewall settings')) {
            $params = @{ Profile = $profileName }
            foreach ($property in $desired.PSObject.Properties) {
                $params[$property.Name] = $property.Value
            }
            Set-NetFirewallProfile @params | Out-Null
            $current = Get-NetFirewallProfile -Profile $profileName
            $remaining = Compare-ObjectProperties -Current $current -Desired $desired
            $results += [pscustomobject]@{
                Profile             = $profileName
                Changed             = $true
                Differences         = $differences
                RemainingDifferences = $remaining
            }
        }
        else {
            $results += [pscustomobject]@{
                Profile             = $profileName
                Changed             = $false
                Differences         = $differences
                RemainingDifferences = $differences
            }
        }
    }

    return $results
}

function Set-RdpBaseline {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Settings
    )

    $regPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server'
    $tcpPath = Join-Path -Path $regPath -ChildPath 'WinStations\RDP-Tcp'

    $changes = @()
    $applied = $false
    $remaining = @()

    if ($Settings.PSObject.Properties['Enable']) {
        $desiredValue = if ($Settings.Enable) { 0 } else { 1 }
        $currentValue = (Get-ItemProperty -Path $regPath -Name 'fDenyTSConnections' -ErrorAction SilentlyContinue).fDenyTSConnections
        if ($null -eq $currentValue -or $currentValue -ne $desiredValue) {
            $changes += [pscustomobject]@{ Key = 'fDenyTSConnections'; Desired = $desiredValue; Previous = $currentValue }
            if ($PSCmdlet.ShouldProcess('Remote Desktop', "Set fDenyTSConnections to $desiredValue")) {
                Set-ItemProperty -Path $regPath -Name 'fDenyTSConnections' -Value $desiredValue -Type DWord
                $applied = $true
            }
        }
    }

    if ($Settings.PSObject.Properties['AllowOnlySecureConnections']) {
        $desiredSecure = if ($Settings.AllowOnlySecureConnections) { 1 } else { 0 }
        $currentSecure = (Get-ItemProperty -Path $tcpPath -Name 'UserAuthentication' -ErrorAction SilentlyContinue).UserAuthentication
        if ($null -eq $currentSecure -or $currentSecure -ne $desiredSecure) {
            $changes += [pscustomobject]@{ Key = 'UserAuthentication'; Desired = $desiredSecure; Previous = $currentSecure }
            if ($PSCmdlet.ShouldProcess('Remote Desktop', "Set UserAuthentication to $desiredSecure")) {
                Set-ItemProperty -Path $tcpPath -Name 'UserAuthentication' -Value $desiredSecure -Type DWord
                $applied = $true
            }
        }
    }

    if ($applied) {
        foreach ($change in $changes) {
            $actual = switch ($change.Key) {
                'fDenyTSConnections' { (Get-ItemProperty -Path $regPath -Name 'fDenyTSConnections' -ErrorAction SilentlyContinue).fDenyTSConnections }
                'UserAuthentication' { (Get-ItemProperty -Path $tcpPath -Name 'UserAuthentication' -ErrorAction SilentlyContinue).UserAuthentication }
            }
            if ($actual -ne $change.Desired) {
                $remaining += [pscustomobject]@{ Key = $change.Key; Desired = $change.Desired; Actual = $actual }
            }
        }
    }
    else {
        $remaining = $changes | ForEach-Object {
            [pscustomobject]@{ Key = $_.Key; Desired = $_.Desired; Actual = $_.Previous }
        }
    }

    return [pscustomobject]@{
        Changed    = $applied
        Differences = $changes
        RemainingDifferences = $remaining
    }
}

function Set-DefenderBaseline {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Settings
    )

    if (-not (Get-Command -Name Get-MpPreference -ErrorAction SilentlyContinue)) {
        throw 'Windows Defender cmdlets are not available on this system.'
    }

    $current = Get-MpPreference
    $changes = @()

    if ($Settings.PSObject.Properties['RealTimeMonitoring']) {
        $desiredDisable = -not [bool]$Settings.RealTimeMonitoring
        if ($current.DisableRealtimeMonitoring -ne $desiredDisable) {
            $changes += [pscustomobject]@{ Property = 'DisableRealtimeMonitoring'; Desired = $desiredDisable; Previous = $current.DisableRealtimeMonitoring }
            if ($PSCmdlet.ShouldProcess('Windows Defender', "Set DisableRealtimeMonitoring to $desiredDisable")) {
                Set-MpPreference -DisableRealtimeMonitoring $desiredDisable
                $applied = $true
            }
        }
    }

    if ($Settings.PSObject.Properties['CloudProtection']) {
        $map = @{
            'Disabled' = 0
            'Basic'    = 1
            'Advanced' = 2
            'Enabled'  = 2
        }
        $desiredMap = $map[[string]$Settings.CloudProtection]
        if ($null -eq $desiredMap) {
            throw "Unsupported CloudProtection value '$($Settings.CloudProtection)'. Use Disabled, Basic, or Advanced."
        }
        if ($current.MAPSReporting -ne $desiredMap) {
            $changes += [pscustomobject]@{ Property = 'MAPSReporting'; Desired = $desiredMap; Previous = $current.MAPSReporting }
            if ($PSCmdlet.ShouldProcess('Windows Defender', "Set MAPSReporting to $desiredMap")) {
                Set-MpPreference -MAPSReporting $desiredMap
                $applied = $true
            }
        }
    }

    if ($Settings.PSObject.Properties['SampleSubmission']) {
        $submissionMap = @{
            'Always'        = 2
            'Never'         = 0
            'Prompt'        = 1
            'SafeSamples'   = 3
            'Automatic'     = 2
        }
        $desiredSubmission = $submissionMap[[string]$Settings.SampleSubmission]
        if ($null -eq $desiredSubmission) {
            throw "Unsupported SampleSubmission value '$($Settings.SampleSubmission)'."
        }
        if ($current.SubmitSamplesConsent -ne $desiredSubmission) {
            $changes += [pscustomobject]@{ Property = 'SubmitSamplesConsent'; Desired = $desiredSubmission; Previous = $current.SubmitSamplesConsent }
            if ($PSCmdlet.ShouldProcess('Windows Defender', "Set SubmitSamplesConsent to $desiredSubmission")) {
                Set-MpPreference -SubmitSamplesConsent $desiredSubmission
                $applied = $true
            }
        }
    }

    if ($Settings.PSObject.Properties['SignatureUpdateIntervalHours']) {
        $desiredInterval = [int]$Settings.SignatureUpdateIntervalHours
        if ($current.SignatureScheduleInterval -ne $desiredInterval) {
            $changes += [pscustomobject]@{ Property = 'SignatureScheduleInterval'; Desired = $desiredInterval; Previous = $current.SignatureScheduleInterval }
            if ($PSCmdlet.ShouldProcess('Windows Defender', "Set SignatureScheduleInterval to $desiredInterval")) {
                Set-MpPreference -SignatureScheduleInterval $desiredInterval
                $applied = $true
            }
        }
    }

    if ($applied) {
        $current = Get-MpPreference
        foreach ($change in $changes) {
            $actual = $current.PSObject.Properties[$change.Property]
            $actualValue = if ($actual) { $actual.Value } else { $null }
            if ($actualValue -ne $change.Desired) {
                $remaining += [pscustomobject]@{ Property = $change.Property; Desired = $change.Desired; Actual = $actualValue }
            }
        }
    }
    else {
        $remaining = $changes | ForEach-Object {
            [pscustomobject]@{ Property = $_.Property; Desired = $_.Desired; Actual = $_.Previous }
        }
    }

    return [pscustomobject]@{
        Changed     = $applied
        Differences = $changes
        RemainingDifferences = $remaining
    }
}

function Set-SecurityBaseline {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Baseline
    )

    if ($IsLinux -or $IsMacOS) {
        throw 'Set-SecurityBaseline must run on Windows.'
    }

    $resolvedPath = Resolve-BaselinePath -Path $Baseline -ScriptRoot $PSScriptRoot
    $profile = Import-BaselineDefinition -Path $resolvedPath

    $summary = @()

    if ($profile.PSObject.Properties['Firewall']) {
        $firewallResult = Set-FirewallBaseline -Settings $profile.Firewall -WhatIf:$WhatIfPreference
        $summary += [pscustomobject]@{
            Area       = 'Firewall'
            Compliant  = ($firewallResult | Where-Object { $_.RemainingDifferences.Count -gt 0 }).Count -eq 0
            Changed    = ($firewallResult | Where-Object { $_.Changed }).Count -gt 0
            Details    = $firewallResult
        }
    }

    if ($profile.PSObject.Properties['RemoteDesktop']) {
        $rdpResult = Set-RdpBaseline -Settings $profile.RemoteDesktop -WhatIf:$WhatIfPreference
        $summary += [pscustomobject]@{
            Area      = 'RemoteDesktop'
            Compliant = $rdpResult.RemainingDifferences.Count -eq 0
            Changed   = $rdpResult.Changed
            Details   = [pscustomobject]@{
                Pending   = $rdpResult.Differences
                Remaining = $rdpResult.RemainingDifferences
            }
        }
    }

    if ($profile.PSObject.Properties['PasswordPolicy']) {
        $passwordResult = Set-PasswordPolicy -DesiredPolicy $profile.PasswordPolicy -WhatIf:$WhatIfPreference
        $summary += [pscustomobject]@{
            Area      = 'PasswordPolicy'
            Compliant = $passwordResult.RemainingDifferences.Count -eq 0
            Changed   = $passwordResult.Changed
            Details   = [pscustomobject]@{
                Pending   = $passwordResult.Differences
                Remaining = $passwordResult.RemainingDifferences
            }
        }
    }

    if ($profile.PSObject.Properties['Defender']) {
        $defenderResult = Set-DefenderBaseline -Settings $profile.Defender -WhatIf:$WhatIfPreference
        $summary += [pscustomobject]@{
            Area      = 'Defender'
            Compliant = $defenderResult.RemainingDifferences.Count -eq 0
            Changed   = $defenderResult.Changed
            Details   = [pscustomobject]@{
                Pending   = $defenderResult.Differences
                Remaining = $defenderResult.RemainingDifferences
            }
        }
    }

    return $summary
}

Export-ModuleMember -Function Set-SecurityBaseline
