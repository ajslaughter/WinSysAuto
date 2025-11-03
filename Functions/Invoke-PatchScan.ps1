function Invoke-PatchScan {
    [CmdletBinding()]
    param(
        [string]$Criteria = "IsInstalled=0 and Type='Software'",

        [switch]$SkipConnectivityCheck
    )

    try {
        $service = Get-Service -Name 'wuauserv' -ErrorAction Stop
    }
    catch {
        Write-Error "Windows Update service is not available. $_"
        return
    }

    if ($service.Status -ne 'Running') {
        Write-Error 'Windows Update service is not running. Start with: Start-Service wuauserv'
        return
    }

    if (-not $SkipConnectivityCheck) {
        $networkAvailable = [System.Net.NetworkInformation.NetworkInterface]::GetIsNetworkAvailable()
        if (-not $networkAvailable) {
            Write-Error 'Cannot connect to Windows Update servers. Check internet/WSUS connectivity'
            return
        }
    }

    try {
        $updateSession = New-Object -ComObject Microsoft.Update.Session -ErrorAction Stop
    }
    catch {
        Write-Error "Failed to initialize Windows Update session. $_"
        return
    }

    try {
        $searcher = $updateSession.CreateUpdateSearcher()
    }
    catch {
        Write-Error "Failed to create Windows Update searcher. $_"
        return
    }

    try {
        $searchResult = $searcher.Search($Criteria)
    }
    catch {
        $hresult = $_.Exception.HResult
        if ($hresult -eq -2145107924) {
            Write-Error 'Windows Update client cannot connect to update servers'
        }
        else {
            Write-Error "Cannot connect to Windows Update servers. Check internet/WSUS connectivity. $_"
        }
        return
    }

    $updates = @()
    if ($searchResult -and $searchResult.Updates -and $searchResult.Updates.Count -gt 0) {
        for ($index = 0; $index -lt $searchResult.Updates.Count; $index++) {
            $update = $searchResult.Updates.Item($index)
            if ($null -eq $update) {
                continue
            }

            $kbList = @()
            if ($update.PSObject.Properties['KBArticleIDs']) {
                foreach ($kb in $update.KBArticleIDs) {
                    if ($kb) {
                        $kbList += $kb
                    }
                }
            }

            $categoryList = @()
            if ($update.PSObject.Properties['Categories']) {
                foreach ($category in $update.Categories) {
                    if ($category -and $category.PSObject.Properties['Name']) {
                        $categoryList += $category.Name
                    }
                }
            }

            $severity = 'Unspecified'
            foreach ($propertyName in 'MsrcSeverity', 'Severity', 'UpdateSeverity') {
                if ($update.PSObject.Properties[$propertyName] -and $update.$propertyName) {
                    $severity = $update.$propertyName
                    break
                }
            }

            $updates += [pscustomobject]@{
                Title        = $update.Title
                KB           = if ($kbList) { $kbList -join ', ' } else { $null }
                Severity     = $severity
                Categories   = if ($categoryList) { ($categoryList | Sort-Object -Unique) -join ', ' } else { 'Unspecified' }
                IsDownloaded = [bool]$update.IsDownloaded
                IsMandatory  = [bool]$update.IsMandatory
            }
        }
    }

    return $updates
}
