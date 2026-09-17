param([string]$Workbook='C:\Users\Administrator\Desktop\通关存档效果.xlsx')
$ErrorActionPreference='Stop'
$root=Join-Path (Split-Path -Parent $PSScriptRoot) 'data/csv/存档系统'
$reader=Get-Content (Join-Path $PSScriptRoot 'import_lottery_points_items.ps1') -Raw
$start=$reader.IndexOf('function Read-WorksheetRows')
Invoke-Expression $reader.Substring($start,$reader.IndexOf('function Icon-For')-$start)
$fields=@{
 '木材'='initial_wood';'金币'='initial_gold';'人口'='initial_population_cap'
 '伐木效率'='lumberjack_attack_efficiency';'墙护甲加成'='wall_armor_bonus_pct'
 '墙生命加成'='wall_health_bonus_pct';'每秒木材'='wood_per_second';'墙每秒护甲'='wall_armor_per_second'
 '英雄最终伤害'='hero_final_damage_bonus_pct';'英雄全属性加成'='hero_attribute_bonus_pct'
 '英雄攻击减甲'='hero_attack_armor_reduction';'英雄攻击全属性'='hero_attribute_growth'
 '英雄造成伤害加攻击'='hero_damage_attack_growth';'伐木工攻速'='lumberjack_attack_speed_bonus_pct'
 '箭塔攻击'='tower_attack_flat';'英雄攻速'='hero_attack_speed_bonus_pct';'墙生命'='wall_initial_health'
 '墙护甲'='wall_armor';'金矿收益'='gold_mine_efficiency_pct';'墙每秒生命'='wall_health_per_second'
 '英雄生命加成'='hero_health_bonus_pct';'英雄护甲加成'='hero_armor_bonus_pct'
 '英雄攻击间隔'='hero_attack_interval_reduction';'练功房收益'='training_room_income_bonus_pct'
 '箭塔攻速'='tower_attack_speed_bonus_pct';'英雄造成伤害'='hero_damage_bonus_flat'
 '英雄每秒全属性'='hero_attributes_per_second';'英雄攻击加成'='hero_attack_bonus_pct'
}
function Effects([string]$text){
 $ids=@();$values=@()
 foreach($part in ($text -split '[；;\s]+' | Where-Object {$_})){
  if($part -notmatch '^(.+?)([+-])([\d.]+)%?$'){throw "Invalid effect: $part"}
  $field=$fields[$Matches[1]];if(-not $field){throw "Unknown effect: $part"}
  if($Matches[2] -eq '-' -and $field -ne 'hero_attack_interval_reduction'){throw "Unexpected negative: $part"}
  $ids+=$field;$values+=$Matches[3]
 }
 return @{ids=($ids -join '|');values=($values -join '|')}
}
function Write-Table($name,$rows,$types){
 $csv=@($rows|ConvertTo-Csv -NoTypeInformation)
 $lines=@($csv[0].Replace('"',''),('#types:'+$types))+$csv[1..($csv.Count-1)]
 [IO.File]::WriteAllText((Join-Path $root $name),($lines -join "`n")+"`n",[Text.UTF8Encoding]::new($false))
}
$sheet=Read-WorksheetRows $Workbook '地图等级';$levels=@()
foreach($i in 1..34){
 $r=$sheet[$i+4];if([int]$r.B -ne $i -or $r.D -notmatch '^([\d.]+)H$'){throw "Invalid map level $i"}
 $seconds=[double]$Matches[1]*3600
 # Per-level base bonuses are projected by map_level_effect_rules, not granted twice here.
 $e=if($i -eq 1){@{ids='map_level';values='1'}}else{Effects $r.C}
 if($i -gt 1){$e.ids+='|map_level';$e.values+='|1'}
 $levels+=[pscustomobject][ordered]@{level_id=('map_{0:d2}' -f $i);level=$i;display_name="地图等级$i";required_seconds=$seconds;description=$r.C;effect_ids=$e.ids;effect_values=$e.values;enabled=1}
}
Write-Table 'archive_map_levels.csv' $levels 'string,number,string,number,string,list,list,boolean'
$sheet=Read-WorksheetRows $Workbook '上班福利';$items=@()
foreach($i in 1..34){
 $r=$sheet[$i+4];$e=Effects $r.E
 if($r.F -notmatch '(\d+)'){throw "Missing work cost $i"};$cost=[int]$Matches[1]
 $name=$r.C -replace '（基础项，文字被遮挡）',''
 $items+=[pscustomobject][ordered]@{item_id=('work_{0:d2}' -f $i);display_name=$name;cost=$cost;max_level=1;description=$r.E;effect_ids=$e.ids;effect_values=$e.values;enabled=1}
}
Write-Table 'archive_work_items.csv' $items 'string,string,number,number,string,list,list,boolean'
Write-Output 'ARCHIVE_ONLINE_IMPORTED: 34 map levels, 34 work benefits'
