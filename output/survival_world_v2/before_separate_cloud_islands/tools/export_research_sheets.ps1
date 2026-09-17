param(
    [Parameter(Mandatory = $true)]
    [string]$TablesPath,

    [Parameter(Mandatory = $true)]
    [string]$OutputDirectory
)

$ErrorActionPreference = "Stop"
$tables = Get-Content -LiteralPath $TablesPath -Raw -Encoding UTF8 |
    ConvertFrom-Json
$exports = @(
    @{ Index = 9; FileName = "dota2_research_config.tsv" },
    @{ Index = 6; FileName = "research_cost_model.tsv" },
    @{ Index = 2; FileName = "research_prerequisites.tsv" },
    @{ Index = 0; FileName = "research_master.tsv" },
    @{ Index = 3; FileName = "dota2_effect_mapping.tsv" },
    @{ Index = 8; FileName = "all_level_costs.tsv" }
)

[IO.Directory]::CreateDirectory($OutputDirectory) | Out-Null
foreach ($export in $exports) {
    $sheet = $tables.worksheets[$export.Index]
    if ($null -eq $sheet) { throw "Worksheet index not found: $($export.Index)" }

    $lines = New-Object System.Collections.ArrayList
    foreach ($row in $sheet.rows) {
        $values = foreach ($value in $row) {
            ([string]$value) -replace "`r?`n", " / " -replace "`t", " "
        }
        [void]$lines.Add(($values -join "`t").TrimEnd())
    }
    $path = Join-Path $OutputDirectory $export.FileName
    [IO.File]::WriteAllLines(
        $path,
        @($lines),
        (New-Object Text.UTF8Encoding($false))
    )
    Write-Output "EXPORTED=$path|LINES=$($lines.Count)"
}