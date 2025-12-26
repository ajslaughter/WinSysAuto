function Get-WsaDrift {
    <#
    .SYNOPSIS
        Checks for configuration drift and significant changes in the environment.

    .DESCRIPTION
        Compares the current state of users, GPOs, and disk usage against a stored snapshot.
        Returns a list of changes detected "today" (since the last snapshot or within 24h).
        Updates the snapshot after running.

    .EXAMPLE
        Get-WsaDrift
        Returns a list of drift items.

    .OUTPUTS
        PSCustomObject
    #>
    [CmdletBinding()]
    param()

    $config = Get-WsaConfig
    $driftPath = Join-Path -Path $env:ProgramData -ChildPath 'WinSysAuto\drift_snapshot.json'
    
    # Current State Collection
    $currentState = @{
        Timestamp = (Get-Date)
        Users = @{}
        GPOs = @{}
        Disks = @{}
    }

    # 1. Users (Count and List if small enough, or just count/last modified)
    if ($config.hasAdModule -and $config.isDomainJoined) {
        try {
            # Get users created in last 24 hours
            $newUsers = Get-ADUser -Filter { whenCreated -ge $((Get-Date).AddHours(-24)) } -Properties whenCreated | Select-Object SamAccountName, whenCreated
            $currentState.NewUsers = $newUsers
            $currentState.UserCount = (Get-ADUser -Filter *).Count
        }
        catch {
            Write-WsaLog -Component 'Get-WsaDrift' -Message "Failed to query AD users: $($_.Exception.Message)" -Level 'WARN'
        }
    }

    # 2. GPOs
    if (Get-Command -Name Get-GPO -ErrorAction SilentlyContinue) {
        try {
            $gpos = Get-GPO -All
            $currentState.GPOs = $gpos | Select-Object DisplayName, ModificationTime, Id
            $currentState.GPOCount = $gpos.Count
        }
        catch {
            Write-WsaLog -Component 'Get-WsaDrift' -Message "Failed to query GPOs: $($_.Exception.Message)" -Level 'WARN'
        }
    }

    # 3. Disks
    try {
        $drives = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Used -or $_.Free }
        foreach ($drive in $drives) {
            $currentState.Disks[$drive.Name] = @{
                UsedGB = [math]::Round($drive.Used / 1GB, 2)
                FreeGB = [math]::Round($drive.Free / 1GB, 2)
            }
        }
    }
    catch {
        Write-WsaLog -Component 'Get-WsaDrift' -Message "Failed to query disks: $($_.Exception.Message)" -Level 'WARN'
    }

    # Load Previous Snapshot
    $driftItems = @()
    
    if (Test-Path -Path $driftPath) {
        try {
            $lastSnapshot = Get-Content -Path $driftPath -Raw | ConvertFrom-Json
            
            # Compare Users
            if ($currentState.NewUsers) {
                foreach ($user in $currentState.NewUsers) {
                    $driftItems += [pscustomobject]@{
                        Type = 'User'
                        Message = "New user created: $($user.SamAccountName)"
                        Timestamp = $user.whenCreated
                        Severity = 'Info'
                    }
                }
            }

            # Compare GPOs
            if ($currentState.GPOs -and $lastSnapshot.GPOs) {
                foreach ($gpo in $currentState.GPOs) {
                    $lastGpo = $lastSnapshot.GPOs | Where-Object { $_.Id -eq $gpo.Id }
                    if ($lastGpo) {
                        # Check modification time
                        $currentMod = [DateTime]$gpo.ModificationTime
                        $lastMod = [DateTime]$lastGpo.ModificationTime
                        if ($currentMod -gt $lastMod) {
                            $driftItems += [pscustomobject]@{
                                Type = 'GPO'
                                Message = "GPO modified: $($gpo.DisplayName)"
                                Timestamp = $currentMod
                                Severity = 'Warning'
                            }
                        }
                    }
                    else {
                        $driftItems += [pscustomobject]@{
                            Type = 'GPO'
                            Message = "New GPO detected: $($gpo.DisplayName)"
                            Timestamp = $gpo.ModificationTime
                            Severity = 'Info'
                        }
                    }
                }
            }

            # Compare Disks (Significant change > 10%)
            foreach ($driveName in $currentState.Disks.Keys) {
                if ($lastSnapshot.Disks.$driveName) {
                    $currentUsed = $currentState.Disks.$driveName.UsedGB
                    $lastUsed = $lastSnapshot.Disks.$driveName.UsedGB
                    $diff = $currentUsed - $lastUsed
                    
                    if ($diff -gt 5) { # More than 5GB growth
                         $driftItems += [pscustomobject]@{
                            Type = 'Disk'
                            Message = "Disk $driveName usage increased by $diff GB"
                            Timestamp = (Get-Date)
                            Severity = 'Warning'
                        }
                    }
                }
            }
        }
        catch {
             Write-WsaLog -Component 'Get-WsaDrift' -Message "Failed to compare snapshots: $($_.Exception.Message)" -Level 'WARN'
        }
    }
    else {
        # First run, just report current state summary
        $driftItems += [pscustomobject]@{
            Type = 'System'
            Message = "Drift baseline established."
            Timestamp = (Get-Date)
            Severity = 'Info'
        }
    }

    # Save new snapshot
    try {
        $currentState | ConvertTo-Json -Depth 5 | Out-File -FilePath $driftPath -Encoding UTF8 -Force
    }
    catch {
        Write-WsaLog -Component 'Get-WsaDrift' -Message "Failed to save snapshot: $($_.Exception.Message)" -Level 'ERROR'
    }

    return $driftItems
}
