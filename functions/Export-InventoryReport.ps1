function Export-InventoryReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [psobject]$InputObject,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$OutputPath,

        [string]$CompanyName = "Your Company"
    )

    begin {
        $items = New-Object System.Collections.Generic.List[psobject]
    }

    process {
        if ($null -eq $InputObject) {
            return
        }

        if ($InputObject -is [System.Collections.IEnumerable] -and -not ($InputObject -is [string])) {
            foreach ($entry in $InputObject) {
                if ($null -ne $entry) {
                    $items.Add($entry)
                }
            }
        }
        else {
            $items.Add($InputObject)
        }
    }

    end {
        if ($items.Count -eq 0) {
            throw "No inventory objects were provided."
        }

        $parentPath = Split-Path -Path $OutputPath -Parent
        if ([string]::IsNullOrEmpty($parentPath)) {
            $parentPath = (Get-Location).ProviderPath
        }

        if (-not (Test-Path -Path $parentPath)) {
            $null = New-Item -ItemType Directory -Path $parentPath -Force
        }

        $resolvedParent = (Resolve-Path -Path $parentPath).ProviderPath
        $leafName = Split-Path -Path $OutputPath -Leaf
        $targetPath = Join-Path -Path $resolvedParent -ChildPath $leafName

        $timestamp = Get-Date

        $properties = New-Object System.Collections.Generic.List[string]
        foreach ($item in $items) {
            foreach ($prop in $item.PSObject.Properties.Name) {
                if (-not $properties.Contains($prop)) {
                    $properties.Add($prop)
                }
            }
        }

        if ($properties.Count -eq 0) {
            throw "Inventory objects do not contain any properties to render."
        }

        [array]$itemsForTable = $items | Select-Object -Property $properties

        $summaryData = [System.Collections.Generic.List[psobject]]::new()
        $summaryData.Add([pscustomobject]@{ Metric = 'Total Inventory Items'; Value = $items.Count })

        $knownDimensions = 'OperatingSystem', 'Environment', 'Location', 'Status', 'Role'
        $availableProperties = $itemsForTable[0].PSObject.Properties.Name

        foreach ($dimension in $knownDimensions) {
            if ($availableProperties -contains $dimension) {
                $values = $itemsForTable | Where-Object {
                    $value = $_.$dimension
                    $null -ne $value -and $value -ne ''
                } | Select-Object -ExpandProperty $dimension -Unique

                $summaryData.Add([pscustomobject]@{
                    Metric = "Distinct $dimension"
                    Value  = ($values | Measure-Object).Count
                })
            }
        }

        $summaryHtml = $summaryData | ConvertTo-Html -Property Metric, Value -Fragment -PreContent '<h2>Summary Statistics</h2>'

        $tableId = 'inventory-table'
        $tablePreContent = "<h2>Inventory Detail</h2><div class='table-controls'><label for='inventory-search'>Quick Filter:</label><input id='inventory-search' type='search' placeholder='Type to filter rows...' /></div>"
        $inventoryTableHtml = $itemsForTable | ConvertTo-Html -Property $properties -Fragment -PreContent $tablePreContent
        $inventoryTableHtml = $inventoryTableHtml -replace '<table>', "<table id='${tableId}'>"

        $chartScript = ''
        $chartContainer = ''

        $chartDimension = $null
        foreach ($dimension in $knownDimensions) {
            if ($availableProperties -contains $dimension) {
                $values = $itemsForTable | Where-Object {
                    $value = $_.$dimension
                    $null -ne $value -and $value -ne ''
                }

                if ($values) {
                    $chartDimension = $dimension
                    break
                }
            }
        }

        if ($chartDimension) {
            $groupedData = $itemsForTable | Where-Object {
                $value = $_.$chartDimension
                $null -ne $value -and $value -ne ''
            } | Group-Object -Property $chartDimension | Sort-Object -Property Count -Descending

            if ($groupedData.Count -gt 0) {
                $labels = $groupedData | ForEach-Object { $_.Name }
                $counts = $groupedData | ForEach-Object { $_.Count }
                $labelsJson = ($labels | ConvertTo-Json -Compress)
                $countsJson = ($counts | ConvertTo-Json -Compress)

                $chartContainer = @"
<section class='chart-section'>
    <h2>Inventory Distribution by $chartDimension</h2>
    <canvas id='inventory-chart'></canvas>
</section>
"@
                $chartScript = @"
<script>
    document.addEventListener('DOMContentLoaded', function () {
        const ctx = document.getElementById('inventory-chart');
        if (!ctx) { return; }
        new Chart(ctx, {
            type: 'bar',
            data: {
                labels: $labelsJson,
                datasets: [{
                    label: '$chartDimension',
                    data: $countsJson,
                    backgroundColor: '#4f46e5'
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                scales: {
                    y: {
                        beginAtZero: true,
                        ticks: {
                            precision: 0
                        }
                    }
                }
            }
        });
    });
</script>
"@
            }
        }

        $css = @"
:root {
    color-scheme: light;
    font-family: 'Segoe UI', Tahoma, sans-serif;
    background-color: #f9fafb;
    color: #111827;
}
body {
    margin: 0;
    padding: 0 2rem 3rem;
    background-color: var(--background-color, #f9fafb);
}
header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 2rem 0 1.5rem;
    border-bottom: 3px solid #e5e7eb;
}
.branding {
    font-size: 1.25rem;
    font-weight: 600;
    color: #6366f1;
    border: 2px dashed #c7d2fe;
    padding: 1rem 1.5rem;
    border-radius: 0.75rem;
}
.meta h1 {
    margin: 0 0 0.5rem;
    font-size: 2rem;
}
.meta p {
    margin: 0;
    color: #4b5563;
}
section {
    margin-top: 2rem;
}
.table-controls {
    display: flex;
    gap: 0.5rem;
    align-items: center;
    margin-bottom: 1rem;
}
#inventory-search {
    padding: 0.5rem 0.75rem;
    border: 1px solid #cbd5f5;
    border-radius: 0.5rem;
    min-width: 220px;
}
table {
    width: 100%;
    border-collapse: collapse;
    background-color: white;
    box-shadow: 0 10px 25px rgba(15, 23, 42, 0.08);
    border-radius: 0.75rem;
    overflow: hidden;
}
thead {
    background-color: #312e81;
    color: white;
}
th, td {
    padding: 0.75rem 1rem;
    border-bottom: 1px solid #e5e7eb;
    text-align: left;
    vertical-align: top;
}
tbody tr:nth-child(odd) {
    background-color: #eef2ff;
}
tbody tr.hide {
    display: none;
}
th.sortable {
    cursor: pointer;
    position: relative;
}
th.sortable::after {
    content: '\u2195';
    font-size: 0.75rem;
    position: absolute;
    right: 0.75rem;
}
.chart-section {
    height: 420px;
    margin-top: 2rem;
    position: relative;
}
.chart-section canvas {
    width: 100% !important;
    height: 100% !important;
}
footer {
    margin-top: 3rem;
    text-align: center;
    color: #6b7280;
    font-size: 0.875rem;
}
"@

        $script = @"
<script>
    (function () {
        const searchInput = document.getElementById('inventory-search');
        const table = document.getElementById('$tableId');
        if (!searchInput || !table) { return; }

        searchInput.addEventListener('input', function () {
            const term = this.value.toLowerCase();
            table.querySelectorAll('tbody tr').forEach(function (row) {
                const text = row.innerText.toLowerCase();
                row.classList.toggle('hide', !text.includes(term));
            });
        });

        table.querySelectorAll('thead th').forEach(function (header, index) {
            header.classList.add('sortable');
            header.addEventListener('click', function () {
                const tbody = table.querySelector('tbody');
                const rows = Array.from(tbody.querySelectorAll('tr'));
                const direction = header.dataset.sortDirection === 'asc' ? 'desc' : 'asc';
                header.dataset.sortDirection = direction;

                const comparer = function (rowA, rowB) {
                    const cellA = rowA.children[index].innerText.trim().toLowerCase();
                    const cellB = rowB.children[index].innerText.trim().toLowerCase();
                    const numericA = Number(cellA);
                    const numericB = Number(cellB);

                    if (!isNaN(numericA) && !isNaN(numericB)) {
                        return (numericA - numericB) * (direction === 'asc' ? 1 : -1);
                    }

                    if (cellA < cellB) { return direction === 'asc' ? -1 : 1; }
                    if (cellA > cellB) { return direction === 'asc' ? 1 : -1; }
                    return 0;
                };

                rows.sort(comparer).forEach(function (row) { tbody.appendChild(row); });
            });
        });
    })();
</script>
"@

        $html = @"
<!DOCTYPE html>
<html lang='en'>
<head>
    <meta charset='utf-8' />
    <title>Inventory Report</title>
    <style>$css</style>
    <script src='https://cdn.jsdelivr.net/npm/chart.js'></script>
</head>
<body>
    <header>
        <div class='branding'>$CompanyName Branding Placeholder</div>
        <div class='meta'>
            <h1>Inventory Report</h1>
            <p>Generated on $($timestamp.ToString('yyyy-MM-dd HH:mm:ss'))</p>
        </div>
    </header>
    <main>
        <section>
            $summaryHtml
        </section>
        $chartContainer
        <section>
            $inventoryTableHtml
        </section>
    </main>
    $script
    $chartScript
    <footer>
        <p>Inventory report generated by WinSysAuto Export-InventoryReport.</p>
    </footer>
</body>
</html>
"@

        $html | Set-Content -Path $targetPath -Encoding UTF8

        return Get-Item -Path $targetPath
    }
}
