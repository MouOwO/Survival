param([string]$Workbook='C:\Users\Administrator\Desktop\通关存档效果.xlsx')
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$root=Join-Path $repo 'data/csv/存档系统'
$source=Get-Content (Join-Path $PSScriptRoot 'import_lottery_points_items.ps1') -Raw
$start=$source.IndexOf('function Read-WorksheetRows')
Invoke-Expression $source.Substring($start,$source.IndexOf('function Icon-For')-$start)
function Write-Table($name,$rows,$types) {
    $csv=@($rows|ConvertTo-Csv -NoTypeInformation)
    $text=@($csv[0].Replace('"',''),('#types:'+$types))+$csv[1..($csv.Count-1)]
    [IO.File]::WriteAllText((Join-Path $root $name),($text -join "`n")+"`n",[Text.UTF8Encoding]::new($false))
}
$rows=Read-WorksheetRows $Workbook '无尽存档'
$waves=@();$rewards=@()
$map=@{'伐木效率'='lumberjack_efficiency';'英雄攻击加成'='hero_attack_bonus_pct';'箭塔每秒攻击'='tower_attack_per_second';'墙减伤'='wall_damage_reduction_pct';'箭塔攻速'='tower_attack_speed_bonus_pct';'英雄攻击成长'='hero_basic_attack_growth';'墙生命加成'='wall_health_bonus_pct';'箭塔攻击加成'='tower_attack_bonus_pct';'英雄攻击属性成长'='hero_attribute_growth';'英雄全属性加成'='hero_attribute_bonus_pct';'每秒木材'='wood_per_second';'金矿效率'='gold_mine_yield_bonus_pct';'英雄攻击减甲'='hero_attack_armor_reduction';'英雄初始属性'='hero_initial_attributes';'墙每秒护甲'='wall_armor_per_second';'墙每秒生命'='wall_health_per_second';'箭塔暴击几率'='tower_critical_chance_pct';'箭塔暴击伤害'='tower_critical_damage_bonus_pct';'伐木工攻速'='lumberjack_attack_speed_bonus_pct';'英雄攻击间隔'='hero_attack_interval_reduction';'墙护甲'='wall_armor';'墙护甲加成'='wall_armor_bonus_pct';'英雄最终伤害'='hero_final_damage_bonus_pct';'箭塔最终伤害'='tower_final_damage_bonus_pct';'人口'='initial_population_cap'}
foreach($i in ($rows.Keys|Sort-Object)) {
    $row=$rows[$i]
    if($row.E -match '^\d+$') {
        foreach($key in @('F','G','H')) {if($row[$key] -notmatch '^\d+(\.\d+)?$'){throw "Invalid wave $i stat $key"}}
        $waves += [pscustomobject][ordered]@{wave_id=('tier1_'+$row.E);group_id='tier1';wave_number=$row.E;health=$row.F;attack=$row.G;war3_armor=$row.H;enabled=1}
    }
    if($row.B -match '^无尽存档\d+$') {
        if($row.D -notmatch '^(.+?)[+-]([\d.]+)%?$'){throw "Unknown effect $($row.D)"}
        $field=$map[$Matches[1]];$value=$Matches[2]
        if(-not $field){throw "Unknown field $($row.D)"}
        $threshold=[regex]::Match($row.C,'\d+').Value
        $rewards += [pscustomobject][ordered]@{achievement_id=('endless_'+$row.A);display_name=$row.B;required_score=$threshold;description=$row.D;effect_ids=$field;effect_values=$value;enabled=1}
    }
}
if($waves.Count -ne 1000 -or $rewards.Count -ne 50){throw 'Workbook count changed, review before import'}
Write-Table 'archive_endless_waves.csv' $waves 'string,string,number,number,number,number,boolean'
Write-Table 'archive_endless_achievements.csv' $rewards 'string,string,number,string,list,list,boolean'
& (Join-Path $PSScriptRoot 'build_archive_configs.ps1')
