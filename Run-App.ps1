<#
.SYNOPSIS
    Unified entry point for WinSysAuto.
    Installs/Imports the module and launches the dashboard.

.DESCRIPTION
    This script serves as the single "Run" button for the entire application.
    It performs the following steps:
    1. Checks if running as Administrator (warns if not, but proceeds for dashboard).
    2. Installs/Imports the WinSysAuto module from the current directory.
    3. Initializes the environment if needed.
    4. Launches the dashboard.
    5. Handles errors gracefully with user-friendly messages.

.EXAMPLE
    .\Run-App.ps1
#>

$ErrorActionPreference = 'Stop'
$currentDir = $PSScriptRoot

function Show-Message {
    param(
        [string]$Message,
        [string]$Color = 'Cyan'
    )
    Write-Host "[WinSysAuto] $Message" -ForegroundColor $Color
}

function Show-Error {
    param(
        [string]$Message,
        [string]$Details
    )
    Write-Host "`n[ERROR] $Message" -ForegroundColor Red
    if ($Details) {
        Write-Host "Details: $Details" -ForegroundColor DarkRed
    }
    Write-Host "`nPress any key to exit..." -NoNewline
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
}

try {
    # 1. Welcome
    Clear-Host
    Write-Host "
    __      __  _         _________              _____          __
    /  \    /  \(_)____   /   _____/__ __  _____\_   \_____  |  | __ __
    \   \/\/   / /    \  \_____  <   |  |/  ___/ /   /\__  \ |  |/  |  \
     \        / |   |  \ /        \___  |\___ \ /    \_/ __ \|  |  |  /
      \__/\  /  |___|  //_______  / ____/____  >\______  (____  /__/____/
           \/        \/         \/\/         \/        \/     \/
    " -ForegroundColor Cyan
    Show-Message "Starting WinSysAuto Management Console..."

    # 2. Check Admin (Optional but recommended)
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Show-Message "Running in User Mode. Some features (User Creation, Security Baseline) will be read-only." 'Yellow'
    }

    # 3. Import Module
    Show-Message "Loading module..."
    $modulePath = Join-Path -Path $currentDir -ChildPath 'WinSysAuto.psd1'
    
    if (-not (Test-Path -Path $modulePath)) {
        throw "Module manifest not found at $modulePath"
    }

    # Force import to ensure latest code is used
    Import-Module -Name $modulePath -Force -ErrorAction Stop

    # 4. Initialize Environment (if config missing)
    $configPath = Join-Path -Path $env:ProgramData -ChildPath 'WinSysAuto\config.json'
    if (-not (Test-Path -Path $configPath)) {
        Show-Message "First run detected. Initializing environment..."
        Initialize-WsaEnvironment -ErrorAction Stop
    }

    # 5. Launch Dashboard
    Show-Message "Launching Dashboard..."
    
    # Start dashboard in a separate process to keep console clean or keep it running here?
    # User requirement: "Dashboard-as-Console". 
    # We'll run it here.
    
    # Open browser automatically
    $dashboardUrl = "http://localhost:8080"
    Show-Message "Opening $dashboardUrl in your default browser..."
    try {
        Start-Process $dashboardUrl
    }
    catch {
        Show-Message "Could not open browser automatically. Please navigate to $dashboardUrl" 'Yellow'
    }

    # Start the dashboard server (blocking call)
    Start-WsaDashboard -Port 8080

}
catch {
    Show-Error -Message "An error occurred while starting the application." -Details $_.Exception.Message
}
