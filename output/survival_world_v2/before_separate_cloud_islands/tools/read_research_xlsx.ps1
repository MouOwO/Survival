param(
    [Parameter(Mandatory = $true)]
    [string]$InputPath,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.IO.Compression

function Read-ZipXml {
    param($Archive, [string]$EntryName)

    $entry = $Archive.GetEntry($EntryName)
    if ($null -eq $entry) { return $null }
    $reader = New-Object IO.StreamReader($entry.Open())
    try {
        [xml]$reader.ReadToEnd()
    }
    finally {
        $reader.Dispose()
    }
}

function Get-CellText {
    param($Cell, $SharedStrings)

    $cellType = [string]$Cell.t
    if ($cellType -eq "inlineStr") {
        return [string]$Cell.is.InnerText
    }

    $raw = [string]$Cell.v
    if ($cellType -eq "s" -and $raw -ne "") {
        $index = [int]$raw
        if ($index -ge 0 -and $index -lt $SharedStrings.Count) {
            return $SharedStrings[$index]
        }
    }
    if ($cellType -eq "b") {
        return $(if ($raw -eq "1") { $true } else { $false })
    }
    return $raw
}

if (-not (Test-Path -LiteralPath $InputPath -PathType Leaf)) {
    throw "Excel file not found: $InputPath"
}

$stream = [IO.File]::Open(
    $InputPath,
    [IO.FileMode]::Open,
    [IO.FileAccess]::Read,
    [IO.FileShare]::ReadWrite
)
$archive = New-Object IO.Compression.ZipArchive(
    $stream,
    [IO.Compression.ZipArchiveMode]::Read,
    $false
)

try {
    $workbook = Read-ZipXml $archive "xl/workbook.xml"
    $relations = Read-ZipXml $archive "xl/_rels/workbook.xml.rels"
    if ($null -eq $workbook -or $null -eq $relations) {
        throw "Invalid xlsx: workbook metadata is missing"
    }

    $relationTargets = @{}
    foreach ($relation in $relations.Relationships.Relationship) {
        $relationTargets[[string]$relation.Id] = [string]$relation.Target
    }

    $sharedStrings = New-Object System.Collections.ArrayList
    $sharedXml = Read-ZipXml $archive "xl/sharedStrings.xml"
    if ($null -ne $sharedXml) {
        foreach ($item in $sharedXml.sst.si) {
            [void]$sharedStrings.Add([string]$item.InnerText)
        }
    }

    $worksheets = New-Object System.Collections.ArrayList
    foreach ($sheet in $workbook.workbook.sheets.sheet) {
        $relationshipId = [string]$sheet.GetAttribute(
            "id",
            "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
        )
        $target = $relationTargets[$relationshipId] -replace "\\", "/"
        if ($target -notmatch "^xl/") {
            $target = "xl/" + $target.TrimStart("/")
        }
        $sheetXml = Read-ZipXml $archive $target
        if ($null -eq $sheetXml) { continue }

        $rows = New-Object System.Collections.ArrayList
        foreach ($row in $sheetXml.worksheet.sheetData.row) {
            $cells = New-Object System.Collections.ArrayList
            foreach ($cell in $row.c) {
                $item = [ordered]@{
                    reference = [string]$cell.r
                    value = Get-CellText $cell $sharedStrings
                }
                if ($null -ne $cell.f) {
                    $item.formula = [string]$cell.f
                }
                [void]$cells.Add([pscustomobject]$item)
            }
            [void]$rows.Add([pscustomobject][ordered]@{
                number = [int]$row.r
                cells = @($cells)
            })
        }

        [void]$worksheets.Add([pscustomobject][ordered]@{
            name = [string]$sheet.name
            dimension = [string]$sheetXml.worksheet.dimension.ref
            rows = @($rows)
        })
    }

    $result = [pscustomobject][ordered]@{
        source_path = (Resolve-Path -LiteralPath $InputPath).Path
        file_length = (Get-Item -LiteralPath $InputPath).Length
        worksheet_count = $worksheets.Count
        worksheets = @($worksheets)
    }
    $json = $result | ConvertTo-Json -Depth 10
    [IO.File]::WriteAllText($OutputPath, $json, (New-Object Text.UTF8Encoding($false)))
    Write-Output "READ_XLSX_OK worksheets=$($worksheets.Count) output=$OutputPath"
}
finally {
    $archive.Dispose()
    $stream.Dispose()
}