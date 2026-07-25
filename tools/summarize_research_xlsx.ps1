param(
    [Parameter(Mandatory = $true)]
    [string]$AuditPath,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath
)

$ErrorActionPreference = "Stop"

function Get-ColumnNumber {
    param([string]$Reference)

    $letters = ($Reference -replace "[^A-Z]", "")
    $number = 0
    foreach ($character in $letters.ToCharArray()) {
        $number = $number * 26 + ([int]$character - [int][char]'A' + 1)
    }
    return $number
}

function Convert-WorksheetRows {
    param($Worksheet)

    $rows = New-Object System.Collections.ArrayList
    foreach ($sourceRow in $Worksheet.rows) {
        $values = @{}
        $maximumColumn = 0
        foreach ($cell in $sourceRow.cells) {
            $column = Get-ColumnNumber ([string]$cell.reference)
            $maximumColumn = [Math]::Max($maximumColumn, $column)
            $values[$column] = $cell.value
        }
        $row = New-Object System.Collections.ArrayList
        for ($column = 1; $column -le $maximumColumn; $column++) {
            [void]$row.Add($values[$column])
        }
        [void]$rows.Add(@($row))
    }
    return @($rows)
}

$audit = Get-Content -LiteralPath $AuditPath -Raw -Encoding UTF8 | ConvertFrom-Json
$result = [ordered]@{
    source_path = $audit.source_path
    worksheet_count = $audit.worksheet_count
    worksheets = @()
}

foreach ($worksheet in $audit.worksheets) {
    $matrix = Convert-WorksheetRows $worksheet
    $result.worksheets += [pscustomobject][ordered]@{
        name = $worksheet.name
        dimension = $worksheet.dimension
        row_count = $matrix.Count
        rows = $matrix
    }
}

$json = [pscustomobject]$result | ConvertTo-Json -Depth 20
[IO.File]::WriteAllText($OutputPath, $json, (New-Object Text.UTF8Encoding($false)))

foreach ($worksheet in $result.worksheets) {
    Write-Output ("SHEET={0}|DIM={1}|ROWS={2}" -f `
        $worksheet.name, $worksheet.dimension, $worksheet.row_count)
}