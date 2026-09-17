param([string]$Workbook='C:\Users\Administrator\Desktop\通关存档效果.xlsx')
$ErrorActionPreference='Stop'
$root=Join-Path (Split-Path -Parent $PSScriptRoot) 'data/csv/存档系统'
$s=Get-Content (Join-Path $PSScriptRoot 'import_lottery_points_items.ps1') -Raw
$p=$s.IndexOf('function Read-WorksheetRows')
Invoke-Expression $s.Substring($p,$s.IndexOf('function Icon-For')-$p)
$fields=@{'英雄生命加成'='hero_health_bonus_pct';'英雄护甲加成'='hero_armor_bonus_pct';'英雄攻击间隔'='hero_attack_interval_reduction';
'初始金币'='initial_gold';'初始木材'='initial_wood';'每秒金币'='gold_per_second';'每秒木材'='wood_per_second';'英雄每秒属性'='hero_attributes_per_second';'英雄初始属性'='hero_initial_attributes';'箭塔攻击'='tower_attack_flat';'墙生命'='wall_initial_health';'墙每秒回血'='wall_health_regen_per_second';'墙每秒生命'='wall_health_per_second';'墙护甲'='wall_armor';'伐木工攻速'='lumberjack_attack_speed_bonus_pct';'英雄最终伤害'='hero_final_damage_bonus_pct';'英雄全属性加成'='hero_attribute_bonus_pct';'伐木效率'='lumberjack_attack_efficiency';'箭塔每秒攻击'='tower_attack_per_second';'箭塔攻击减甲'='tower_attack_armor_reduction';'箭塔造成伤害攻击'='tower_damage_attack_growth';'箭塔暴击几率'='tower_critical_chance_pct';'箭塔攻击加成'='tower_attack_bonus_pct';'英雄造成伤害攻击'='hero_damage_attack_growth';'英雄造成伤害加属性'='hero_attributes_per_damage';'英雄造成伤害属性'='hero_attributes_per_damage';'金矿效率'='gold_mine_efficiency_pct';'墙每秒护甲'='wall_armor_per_second';'墙生命加成'='wall_health_bonus_pct';'墙护甲加成'='wall_armor_bonus_pct';'英雄三围加成'='hero_attribute_bonus_pct';'英雄攻击减甲'='hero_attack_armor_reduction';'箭塔最终伤害'='tower_final_damage_bonus_pct';'金矿最终产量'='gold_mine_final_output_flat';'英雄攻击加成'='hero_attack_bonus_pct';'伐木工攻击成长'='lumberjack_attack_growth';'墙减伤'='wall_damage_reduction_pct';'箭塔暴击伤害'='tower_critical_damage_bonus_pct';'英雄全属性'='hero_attribute_bonus_pct';'人口'='initial_population_cap'
}
$schema=@(Import-Csv (Join-Path (Split-Path -Parent $root) '玩家档案系统/player_gameplay_stats.csv'))
$items=@()
foreach($pool in @('friend','ex','beast')) {
 $sheet=if($pool -eq 'friend'){'我的好基友'}elseif($pool -eq 'ex'){'我的前女友'}else{'怪兽纳福'}
 $rows=Read-WorksheetRows $Workbook $sheet
 foreach($i in 1..40) {
  $row=@($rows.Values | Where-Object { $_.A -eq [string]$i -and $_.B })
  if($row.Count -ne 1){throw "Missing $sheet item $i"}
  $effect=($row[0].D -replace '可叠加','').Trim()
  if($effect -notmatch '^(.+?)[+-]([\d.]+)%?$'){throw "Invalid effect $effect"}
  $field=$fields[$Matches[1]]; $value=$Matches[2]
  if(-not $field -or $field -notin $schema.field_id){throw "Unknown effect $effect -> $field"}
  $items += [pscustomobject][ordered]@{item_id=('{0}_{1:d2}' -f $pool,$i);pool_id=$pool;display_name=$row[0].B;max_owned=$row[0].C;quality='N';description=$effect;effect_ids=$field;effect_values=$value;enabled=1}
 }
}
$csv=@($items|ConvertTo-Csv -NoTypeInformation)
[IO.File]::WriteAllText((Join-Path $root 'archive_social_items.csv'), (($csv[0].Replace('"',''), '#types:string,string,string,number,string,string,list,list,boolean')+$csv[1..($csv.Count-1)] -join "`n")+"`n",[Text.UTF8Encoding]::new($false))
Write-Output 'ARCHIVE_SOCIAL_ITEMS_IMPORTED: 120'
