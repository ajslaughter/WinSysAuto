$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Resolve-Path (Join-Path $here '..')
$functionPath = Join-Path $repoRoot 'functions' 'Export-InventoryReport.ps1'
. $functionPath

Describe 'Export-InventoryReport' {
    $sampleInventory = @(
        [pscustomobject]@{
            Name = 'Server01'
            OperatingSystem = 'Windows Server 2022'
            Environment = 'Production'
            Location = 'DataCenterA'
            Status = 'Online'
            Role = 'Hyper-V'
            IPAddress = '10.0.0.10'
        },
        [pscustomobject]@{
            Name = 'Server02'
            OperatingSystem = 'Windows Server 2019'
            Environment = 'Production'
            Location = 'DataCenterB'
            Status = 'Online'
            Role = 'SQL'
            IPAddress = '10.0.0.11'
        },
        [pscustomobject]@{
            Name = 'Server03'
            OperatingSystem = 'Windows Server 2019'
            Environment = 'Development'
            Location = 'DataCenterB'
            Status = 'Maintenance'
            Role = 'Web'
            IPAddress = '10.0.0.12'
        }
    )

    It 'creates an HTML report with expected sections' {
        $outputFile = Join-Path $TestDrive 'inventory-report.html'
        $result = $sampleInventory | Export-InventoryReport -OutputPath $outputFile -CompanyName 'Contoso'

        $result | Should -Not -BeNullOrEmpty
        Test-Path $outputFile | Should -BeTrue

        $content = Get-Content -Path $outputFile -Raw
        $content | Should -Match '<h2>Summary Statistics</h2>'
        $content | Should -Match 'Inventory Detail'
        $content | Should -Match 'Contoso Branding Placeholder'
        $content | Should -Match 'Generated on '
        $content | Should -Match '<table id=\'inventory-table\'>'
    }

    It 'includes Chart.js visualization when supported data exists' {
        $outputFile = Join-Path $TestDrive 'inventory-report-chart.html'
        $sampleInventory | Export-InventoryReport -OutputPath $outputFile
        $content = Get-Content -Path $outputFile -Raw

        $content | Should -Match 'cdn.jsdelivr.net/npm/chart.js'
        $content | Should -Match 'Inventory Distribution by OperatingSystem|Environment|Location|Status|Role'
        $content | Should -Match 'new Chart\(ctx'
    }

    It 'throws when no inventory objects are provided' {
        { @() | Export-InventoryReport -OutputPath (Join-Path $TestDrive 'empty.html') } | Should -Throw
    }
}
