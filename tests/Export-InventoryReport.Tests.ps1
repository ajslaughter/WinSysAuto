Import-Module (Join-Path -Path $PSScriptRoot -ChildPath '..\WinSysAuto.psd1') -Force

Describe 'Export-InventoryReport' {
    BeforeEach {
        Mock -CommandName Get-Inventory -MockWith {
            [pscustomobject]@{
                ComputerName    = 'TestHost'
                OperatingSystem = [pscustomobject]@{ Caption = 'Windows'; Version = '10'; BuildNumber = '19045' }
                MemoryGB        = 8
                Uptime          = [TimeSpan]::FromHours(12)
                Processors      = @([pscustomobject]@{ Name = 'CPU'; NumberOfCores = 4; NumberOfLogicalProcessors = 8; MaxClockSpeedMHz = 3200 })
                Disks           = @([pscustomobject]@{ Name = 'C:'; SizeGB = 100; FreeGB = 50; PercentFree = 50 })
                Last5Patches    = @([pscustomobject]@{ HotFixID = 'KB1'; InstalledOn = (Get-Date); Description = 'Patch' })
            }
        }
        Mock -CommandName Write-Host
    }

    It 'creates the report and returns the file object' {
        $outputDirectory = Join-Path -Path $TestDrive -ChildPath 'Reports'
        $result = Export-InventoryReport -ComputerName 'TestHost' -OutputDirectory $outputDirectory

        $result | Should -Not -BeNullOrEmpty
        $result | Should -BeOfType 'System.IO.FileInfo'
        $result.FullName | Should -Match 'TestHost-Inventory.html'
        (Test-Path -LiteralPath $result.FullName) | Should -BeTrue

        Assert-MockCalled -CommandName Write-Host -Times 1
    }
}
