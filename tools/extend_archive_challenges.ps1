param([string]$Workbook = 'C:\Users\Administrator\Desktop\通关存档效果.xlsx', [double]$LateHuntAttack = 5500002)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$root = Join-Path $repo 'data/csv/存档系统'
$source = Get-Content (Join-Path $PSScriptRoot 'import_lottery_points_items.ps1') -Raw
$start = $source.IndexOf('function Read-WorksheetRows')
Invoke-Expression $source.Substring($start, $source.IndexOf('function Icon-For') - $start)
function Read-Table($name) {
    @(Import-Csv (Join-Path $root $name) | Where-Object { -not ([string]@($_.PSObject.Properties)[0].Value).StartsWith('#') })
}
function Write-Table($name, $rows) {
    $path = Join-Path $root $name
    $header = @(Get-Content $path -TotalCount 3)
    $csv = @($rows | ConvertTo-Csv -NoTypeInformation)
    [IO.File]::WriteAllText($path, (($header + $csv[1..($csv.Count-1)]) -join "`n") + "`n", [Text.UTF8Encoding]::new($false))
}
function Number-FromCell($text) {
    $match = [regex]::Match($text, '(\d+(?:\.\d+)?)(亿)?')
    if (-not $match.Success) { throw "Invalid stat: $text" }
    $value = [double]::Parse($match.Groups[1].Value, [Globalization.CultureInfo]::InvariantCulture)
    if ($match.Groups[2].Success) { $value *= 100000000 }
    return $value
}
$defs = @(Read-Table 'archive_challenge_definitions.csv')
$stats = @(Read-Table 'archive_challenge_stats.csv')
$items = @(Read-Table 'archive_cage_items.csv')
$fragments = Read-WorksheetRows $Workbook '神兵碎片'
foreach ($i in 5..12) {
    $id = 'hunt_{0:d2}' -f $i
    $def = $defs | Where-Object challenge_id -eq $id
    $def.enabled = '1'
    $def.slot_order = [string](($i-1)%4+1)
    $row = $fragments.Values | Where-Object { $_.A -eq [string]$i }
    $parts = @($row.C -split '\r?\n' | Where-Object { $_.Trim() })
    foreach ($stat in ($stats | Where-Object challenge_id -eq $id)) {
        $stat.health = [string](Number-FromCell $parts[0])
        $stat.attack = [string]$(if ($i -ge 9) { $LateHuntAttack } else { Number-FromCell $parts[1] })
        $stat.war3_armor = [string](Number-FromCell $parts[2])
        $stat.notes = '神兵碎片sheet第' + $i + '项；生命攻击护甲采用工作簿，其余沿用测试配置；各难度相同。'
        if ($i -ge 9) { $stat.notes += '原表攻击5500002亿存在疑似单位笔误，当前采用' + $LateHuntAttack + '，待确认。' }
    }
}
$effects = @{ '木材'='initial_wood'; '金币'='initial_gold'; '墙生命'='wall_initial_health';
    '每秒木材'='wood_per_second'; '墙生命加成'='wall_health_bonus_pct';
    '箭塔攻击加成'='tower_attack_bonus_pct'; '英雄每秒属性'='hero_attributes_per_second';
    '英雄攻击加成'='hero_attack_bonus_pct'; '英雄攻击全属性'='hero_attribute_growth' }
$cages = Read-WorksheetRows $Workbook '秘法牢笼'
foreach ($i in 28..54) {
    $row = $cages.Values | Where-Object { $_.A -eq [string]$i }
    if (-not $row -or $row.D -notmatch '^(.+?)\+([\d.]+)%?$') { throw "Missing cage item $i" }
    $field = $effects[$Matches[1]]; $value = $Matches[2]
    if (-not $field) { throw "Unknown effect $($row.D)" }
    $id = 'cage_{0:d2}' -f $i
    $items = @($items | Where-Object item_id -ne $id)
    $items += [pscustomobject][ordered]@{item_id=$id;display_name=$row.B;pool_id=('cage_'+([int][math]::Floor(($i-1)/9)+1));max_owned=149;description=$row.D;effect_ids=$field;effect_values=$value;enabled=1}
}
foreach ($i in 4..6) {
    $id = "cage_$i"
    $row = $cages.Values | Where-Object { $_.A -eq [string](($i-1)*9+1) }
    if ($row.F -ne 'N10') { throw "Expected N10 for $id" }
    $parts = @($row.E.Trim() -split '\s+')
    $defs = @($defs | Where-Object challenge_id -ne $id)
    $defs += [pscustomobject][ordered]@{challenge_id=$id;building_id=3;slot_order=($i+1);display_name="秘法牢笼-$i";min_difficulty=10;reward_kind='cage';reward_key=$id;model_path='models/heroes/visage/visage.vmdl';model_scale=1.5;ability_icon='visage_summon_familiars';cooldown_seconds=3;enabled=1;description='击败BOSS随机掉落本池9种材料之一；通行证额外1件。每局仅可挑战一次。'}
    $stats = @($stats | Where-Object challenge_id -ne $id)
    foreach ($n in 1..10) {
        $stats += [pscustomobject][ordered]@{stats_id="${id}_N$n";challenge_id=$id;difficulty_id="N$n";health=(Number-FromCell $parts[0]);attack=(Number-FromCell $parts[1]);war3_armor=(Number-FromCell $parts[2]);attack_speed=1;move_speed=280;attack_range=160;magic_resistance=0;enabled=1;notes='秘法牢笼sheet N10对应BOSS；生命攻击护甲采用工作簿，其余沿用测试配置。'}
    }
}
Write-Table 'archive_challenge_definitions.csv' @($defs | Sort-Object {[int]$_.building_id},{[int]$_.slot_order})
Write-Table 'archive_challenge_stats.csv' $stats
Write-Table 'archive_cage_items.csv' $items
& (Join-Path $PSScriptRoot 'build_archive_configs.ps1')
