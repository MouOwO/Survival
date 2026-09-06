param([string]$Workbook = 'C:\Users\Administrator\Desktop\通关存档效果.xlsx')
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$source = Get-Content (Join-Path $PSScriptRoot 'import_lottery_points_items.ps1') -Raw
$start = $source.IndexOf('function Read-WorksheetRows')
Invoke-Expression $source.Substring($start, $source.IndexOf('function Icon-For') - $start)
function Parse-Stats([string]$text) {
    $matches = [regex]::Matches($text, '(\d+(?:\.\d+)?)\s*(亿|万)?')
    if ($matches.Count -ne 3) { throw "Expected health/attack/armor: $text" }
    @($matches | ForEach-Object {
        $value = [decimal]::Parse($_.Groups[1].Value, [Globalization.CultureInfo]::InvariantCulture)
        if ($_.Groups[2].Value -eq '亿') { $value *= 100000000 }
        if ($_.Groups[2].Value -eq '万') { $value *= 10000 }
        $value.ToString('0.################', [Globalization.CultureInfo]::InvariantCulture)
    })
}
$mapping = @{}
$fragments = Read-WorksheetRows $Workbook '神兵碎片'
foreach ($i in 1..12) {
    $rows = @($fragments.Values | Where-Object { $_.A -eq [string]$i })
    if ($rows.Count -ne 1) { throw "Expected one fragment row $i" }
    $mapping[('hunt_{0:d2}' -f $i)] = @{
        values = Parse-Stats $rows[0].C
        note = '神兵碎片sheet序号' + $i + '，boss属性原文：' + ($rows[0].C -replace '\r?\n', ' / ')
    }
}
$cages = Read-WorksheetRows $Workbook '秘法牢笼'
foreach ($i in 1..6) {
    $ordinal = ($i - 1) * 9 + 1
    $rows = @($cages.Values | Where-Object { $_.A -eq [string]$ordinal })
    if ($rows.Count -ne 1) { throw "Expected one cage row $ordinal" }
    $mapping["cage_$i"] = @{
        values = Parse-Stats $rows[0].E
        note = '秘法牢笼sheet序号' + $ordinal + '，怪物属性原文：' + $rows[0].E
    }
}
$path = Join-Path $repo 'data/csv/存档系统/archive_challenge_stats.csv'
$header = @(Get-Content $path -TotalCount 3)
$stats = @(Import-Csv $path | Where-Object { -not $_.stats_id.StartsWith('#') })
foreach ($id in $mapping.Keys) {
    $targets = @($stats | Where-Object challenge_id -eq $id)
    if ($targets.Count -ne 10) { throw "Expected 10 difficulty rows for $id" }
    foreach ($row in $targets) {
        $row.health = $mapping[$id].values[0]
        $row.attack = $mapping[$id].values[1]
        $row.war3_armor = $mapping[$id].values[2]
        $row.notes = $mapping[$id].note + '；按原表单位换算，各难度共用，其余属性保持现值。'
    }
}
$csv = @($stats | ConvertTo-Csv -NoTypeInformation)
[IO.File]::WriteAllText($path, (($header + $csv[1..($csv.Count-1)]) -join "`n") + "`n", [Text.UTF8Encoding]::new($false))
& (Join-Path $PSScriptRoot 'build_archive_configs.ps1')
Write-Output 'ARCHIVE_BOSS_STATS_SYNC_PASS: 12 hunts, 6 cages, 180 difficulty rows'
