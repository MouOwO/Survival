param([string]$Workbook='C:\Users\Administrator\Desktop\通关存档效果.xlsx')
$ErrorActionPreference='Stop'
$root=Join-Path (Split-Path -Parent $PSScriptRoot) 'data/csv/存档系统'
$s=Get-Content (Join-Path $PSScriptRoot 'import_lottery_points_items.ps1') -Raw
$p=$s.IndexOf('function Read-WorksheetRows'); Invoke-Expression $s.Substring($p,$s.IndexOf('function Icon-For')-$p)
$map=@{'墙生命值'='wall_initial_health';'墙生命'='wall_initial_health';'伐木效率'='lumberjack_attack_efficiency';'箭塔攻击'='tower_attack_bonus_pct';'英雄造成伤害加属性'='hero_attributes_per_damage';'初始木材'='initial_wood';'墙生命加成'='wall_health_bonus_pct';'墙护甲加成'='wall_armor_bonus_pct';'初始金币'='initial_gold';'英雄初始属性'='hero_initial_attributes';'英雄造成伤害黄金'='hero_damage_gold_flat';'初始人口'='initial_population_cap';'伐木工攻速'='lumberjack_attack_speed_bonus_pct';'伐木工攻击成长'='lumberjack_attack_growth';'每秒金币'='gold_per_second';'英雄每秒全属性'='hero_attributes_per_second';'英雄生命加成'='hero_health_bonus_pct';'英雄护甲加成'='hero_armor_bonus_pct';'英雄攻击减甲'='hero_attack_armor_reduction';'英雄三围加成'='hero_attribute_bonus_pct';'英雄攻速'='hero_attack_speed_bonus_pct';'英雄伤害减免'='hero_damage_reduction_pct';'英雄最终伤害'='hero_final_damage_bonus_pct'}
function Write-New($file,$rows,$types){
 $csv=@($rows|ConvertTo-Csv -NoTypeInformation)
 $text=@($csv[0].Replace('"',''),('#types:'+$types))+$csv[1..($csv.Count-1)]
 [IO.File]::WriteAllText((Join-Path $root $file),($text -join "`n")+"`n",[Text.UTF8Encoding]::new($false))
}
$rows=Read-WorksheetRows $Workbook 'BOSS存档';$boss=@()
foreach($i in 1..34){
 $row=@($rows.Values|Where-Object {$_.A -eq [string]$i})[0]
 if($row.D -notmatch '^(.+?)\+([\d.]+)%?$'){throw "Invalid boss effect $i"}
 $field=$map[$Matches[1]];$value=$Matches[2];if(-not $field){throw $row.D}
 $boss += [pscustomobject][ordered]@{achievement_id="boss_$i";display_name=$row.B;required_kills=$row.C;pass_required_kills=([int]$row.C/2);description=$row.D;effect_ids=$field;effect_values=$value;enabled=1}
}
Write-New 'archive_boss_achievements.csv' $boss 'string,string,number,number,string,list,list,boolean'
# Daily columns G/H/I are authoritative. The day-21 item references 商城道具.
$daily=Read-WorksheetRows $Workbook '通行证相关'
$shop=Read-WorksheetRows $Workbook '商城道具'
if(-not ($shop.Values | Where-Object {$_.B -eq '森罗本源'})){throw 'Missing 森罗本源'}
$items=@(
 @('growth_gem','成长宝石','英雄每秒攻击+1','hero_attack_per_second','1',999999),
 @('regen_shard','回血碎片','墙每秒回血+2','wall_health_regen_per_second','2',999999),
 @('attribute_gem','攻击宝石','英雄每秒三围+1','hero_attributes_per_second','1',999999),
 @('attack_shard','攻击碎片','塔攻击+5','tower_attack_flat','5',999999),
 @('health_gem','生命宝石','墙生命+50','wall_initial_health','50',999999),
 @('wood_gem','木材宝石','开局木材+3','initial_wood','3',999999),
 @('block_shard','格挡碎片','墙格挡+3','wall_damage_block','3',999999),
 @('attribute_shard','属性碎片','英雄全属性+10','hero_initial_attributes','10',999999),
 @('gold_gem','金币宝石','开局金币+1','initial_gold','1',999999),
 @('wealth_talisman','聚财古符','开局木材+50；开局金币+50；伐木工攻速+3%；伐木效率+1；金矿收益+5%；人口+1','initial_wood|initial_gold|lumberjack_attack_speed_bonus_pct|lumberjack_attack_efficiency|gold_mine_efficiency_pct|initial_population_cap','50|50|3|1|5|1',1),
 @('ancient_tree','古树眷顾','开局木材+300；开局金币+300；伐木效率+3；金矿收益+5%；英雄全属性加成+9%；星悦积分+128','initial_wood|initial_gold|lumberjack_attack_efficiency|gold_mine_efficiency_pct|hero_attribute_bonus_pct|starjoy_points','300|300|3|5|9|128',1),
 @('forest_origin','森罗本源','开局木材+200；开局金币+200；伐木效率+1；金矿收益+5%；人口+1；英雄全属性加成+8%；星悦积分+88','initial_wood|initial_gold|lumberjack_attack_efficiency|gold_mine_efficiency_pct|initial_population_cap|hero_attribute_bonus_pct|starjoy_points','200|200|1|5|1|8|88',1)
) | ForEach-Object {[pscustomobject][ordered]@{item_id=('daily_'+$_[0]);display_name=$_[1];description=$_[2];effect_ids=$_[3];effect_values=$_[4];max_owned=$_[5];quality=$(if($_[5] -eq 1){'SSR'}else{'R'});enabled=1}}
Write-New 'archive_daily_items.csv' $items 'string,string,string,list,list,number,string,boolean'
Write-Output 'ARCHIVE_DAILY_IMPORTED: 34 boss milestones, 12 sign-in items'
