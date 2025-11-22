$ErrorActionPreference = 'Stop'

function Assert-FileContent {
    param($Path, $Pattern, $Message)
    $content = Get-Content -Path $Path -Raw
    if ($content -match $Pattern) {
        Write-Host "[PASS] $Message" -ForegroundColor Green
    } else {
        Write-Host "[FAIL] $Message" -ForegroundColor Red
        throw "Verification failed: $Message"
    }
}

function Assert-FileNotContent {
    param($Path, $Pattern, $Message)
    $content = Get-Content -Path $Path -Raw
    if ($content -notmatch $Pattern) {
        Write-Host "[PASS] $Message" -ForegroundColor Green
    } else {
        Write-Host "[FAIL] $Message" -ForegroundColor Red
        throw "Verification failed: $Message"
    }
}

Write-Host "Verifying WinSysAuto v1.1 Refactor..." -ForegroundColor Cyan

# 1. Security Hardening
$dashboardPath = "c:\Users\austi\Downloads\WinSysAuto-main (4)\WinSysAuto-main\Public\Start-WsaDashboard.ps1"
Assert-FileContent -Path $dashboardPath -Pattern 'http://127\.0\.0\.1:\$Port/' -Message "Listener binds to 127.0.0.1"
Assert-FileContent -Path $dashboardPath -Pattern 'if \(\$filename -notmatch ''\\\.csv\$''\)' -Message "CSV extension validation present"

# 2. Code Modernization
$dashboardDataPath = "c:\Users\austi\Downloads\WinSysAuto-main (4)\WinSysAuto-main\Private\Get-WsaDashboardData.ps1"
Assert-FileNotContent -Path $dashboardDataPath -Pattern 'Get-WmiObject' -Message "No Get-WmiObject in Get-WsaDashboardData.ps1"
Assert-FileContent -Path $dashboardDataPath -Pattern 'Get-CimInstance' -Message "Get-CimInstance used in Get-WsaDashboardData.ps1"
Assert-FileContent -Path $dashboardDataPath -Pattern '\$os\.LastBootUpTime' -Message "Correct DateTime handling for CIM LastBootUpTime"

$initEnvPath = "c:\Users\austi\Downloads\WinSysAuto-main (4)\WinSysAuto-main\Config\Initialize-WsaEnvironment.ps1"
Assert-FileNotContent -Path $initEnvPath -Pattern 'Get-WmiObject' -Message "No Get-WmiObject in Initialize-WsaEnvironment.ps1"
Assert-FileContent -Path $initEnvPath -Pattern 'Get-CimInstance' -Message "Get-CimInstance used in Initialize-WsaEnvironment.ps1"

# 3. Ops & Stability
$logPath = "c:\Users\austi\Downloads\WinSysAuto-main (4)\WinSysAuto-main\Private\Write-WsaLog.ps1"
Assert-FileContent -Path $logPath -Pattern 'Get-ChildItem.*Remove-Item' -Message "Log rotation logic present"
Assert-FileContent -Path $logPath -Pattern '\(Get-Date\)\.AddDays\(-30\)' -Message "Log rotation set to 30 days"

# 4. UX/UI Refinement
$cssPath = "c:\Users\austi\Downloads\WinSysAuto-main (4)\WinSysAuto-main\Dashboard\style.css"
Assert-FileContent -Path $cssPath -Pattern '--text-secondary: #e5e7eb;' -Message "Text secondary contrast increased"
Assert-FileContent -Path $cssPath -Pattern '--text-muted: #9ca3af;' -Message "Text muted contrast increased"

Write-Host "`nAll Verification Checks Passed!" -ForegroundColor Green
