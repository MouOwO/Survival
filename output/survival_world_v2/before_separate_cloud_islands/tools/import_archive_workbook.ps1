param([string]$Workbook = 'C:\Users\Administrator\Desktop\通关存档效果.xlsx')
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$source = Get-Content (Join-Path $PSScriptRoot 'import_lottery_points_items.ps1') -Raw
$start = $source.IndexOf('function Read-WorksheetRows')
Invoke-Expression $source.Substring($start, $source.IndexOf('function Icon-For') - $start)
$root = Join-Path $repo 'data/csv/存档系统'
[IO.Directory]::CreateDirectory($root) | Out-Null
$mapping = @{
    '木材'='initial_wood'; '金币'='initial_gold'; '墙伤害抵挡'='wall_damage_block'
    '墙伤害格挡'='wall_damage_block'; '墙减伤'='wall_damage_reduction_pct'
    '每秒木材'='wood_per_second'; '人口'='initial_population_cap'
    '伐木数量'='lumberjack_attack_efficiency'; '伐木效率'='lumberjack_efficiency'
    '伐木工攻击成长'='lumberjack_attack_growth'; '英雄造成伤害攻击'='hero_damage_attack_growth'
    '英雄每级全属性'='hero_attributes_per_level'; '墙每秒生命'='wall_health_per_second'
    '英雄初始属性'='hero_initial_attributes'; '英雄每秒属性'='hero_attributes_per_second'
    '金矿效率'='gold_mine_efficiency_pct'; '墙生命'='wall_initial_health'
    '英雄生命加成'='hero_health_bonus_pct'; '英雄护甲加成'='hero_armor_bonus_pct'
    '墙护甲加成'='wall_armor_bonus_pct'; '墙护甲'='wall_armor'
    '伐木工攻速'='lumberjack_attack_speed_bonus_pct'; '英雄攻击减甲'='hero_attack_armor_reduction'
    '英雄三维加成'='hero_attribute_bonus_pct'; '英雄攻击加成'='hero_attack_bonus_pct'
    '英雄最终伤害'='hero_final_damage_bonus_pct'; '箭塔攻击加成'='tower_attack_bonus_pct'
    '箭塔攻速'='tower_attack_speed_bonus_pct'; '防御塔攻击'='tower_attack_bonus_pct'
    '英雄攻击'='hero_attack_bonus_pct'
}
function Effect([string]$text) {
    if ($text -notmatch '^(.+?)\+([0-9.]+)(%?)$') { throw "Unmapped effect: $text" }
    $name=$Matches[1]; $value=$Matches[2]; $percent=$Matches[3]
    $field=$mapping[$name]
    if ($name -eq '箭塔攻击') { $field=if($percent){'tower_attack_bonus_pct'}else{'tower_attack_flat'} }
    if (-not $field) { throw "Unmapped effect: $text" }
    return @($field,$value)
}
function Write-Table($name,$rows,$types,$labels) {
    $csv=@($rows | ConvertTo-Csv -NoTypeInformation)
    $lines=@($csv[0].Replace('"',''),('#中文表头:'+$labels),('#types:'+$types)) + $csv[1..($csv.Count-1)]
    [IO.File]::WriteAllText((Join-Path $root $name),($lines -join "`n")+"`n",[Text.UTF8Encoding]::new($false))
}
$clear=Read-WorksheetRows $Workbook '通关存档'
$rows=@()
foreach($index in ($clear.Keys | Sort-Object)) {
    $row=$clear[$index]
    if($row.B -ne '常规' -or $row.C -notmatch 'N(\d+)' -or -not $row.D){continue}
    $difficulty='n'+$Matches[1]; $count=[int]$row.D; $effect=Effect $row.E
    $rows += [pscustomobject][ordered]@{
        achievement_id="clear_${difficulty}_$count"; category_id='clear'; difficulty_id=$difficulty
        required_count=$count; display_name="$($difficulty.ToUpper())（$($count)次）"; description=$row.E
        effect_ids=$effect[0]; effect_values=$effect[1]; icon_style='scroll'; enabled=1
        source_row=$index; notes=$row.H
    }
}
Write-Table 'archive_achievements.csv' $rows 'string,string,string,number,string,string,list,list,string,boolean,number,string' '成就ID,分页ID,难度ID,所需通关次数,名称,效果,词条ID数组,数值数组,自制图标样式,启用,来源行,来源备注'
$shadow=Read-WorksheetRows $Workbook '虚空之影'; $rows=@(); $difficulty='n1'
$qualities=@{'白色'='white';'蓝色'='blue';'紫色'='purple';'绿色'='green'}
foreach($index in ($shadow.Keys | Sort-Object)) {
    $row=$shadow[$index]
    if($row.B -notmatch '^(.+)-([白蓝紫绿]色)$'){continue}
    $name=$Matches[1]; $quality=$qualities[$Matches[2]]
    if($row.F){$difficulty=$row.F.ToLower()}
    $effect=Effect $row.D
    $rows += [pscustomobject][ordered]@{
        item_id=('shadow_{0:d2}' -f [int]$row.A); display_name=$name; quality=$quality
        max_owned=[int]$row.C; description=$row.D; effect_ids=$effect[0]; effect_values=$effect[1]
        icon_style='shard'; enabled=1; source_row=$index; source_boss_difficulty=$difficulty
    }
}
Write-Table 'archive_shadow_items.csv' $rows 'string,string,string,number,string,list,list,string,boolean,number,string' '道具ID,名称,品质,持有上限,单件效果,词条ID数组,数值数组,自制图标样式,启用,来源行,参考表原BOSS难度'
& (Join-Path $PSScriptRoot 'build_archive_configs.ps1')
