param([string]$Workbook = 'C:\Users\Administrator\Desktop\通关存档效果.xlsx')
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$root=Join-Path $repo 'data/csv/存档系统'
$source=Get-Content (Join-Path $PSScriptRoot 'import_lottery_points_items.ps1') -Raw
$start=$source.IndexOf('function Read-WorksheetRows')
Invoke-Expression $source.Substring($start,$source.IndexOf('function Icon-For')-$start)
function Write-ArchiveTable($name,$rows,$types,$labels) {
    $csv=@($rows | ConvertTo-Csv -NoTypeInformation)
    $text=@($csv[0].Replace('"',''),('#中文表头:'+$labels),('#types:'+$types))+$csv[1..($csv.Count-1)]
    [IO.File]::WriteAllText((Join-Path $root $name),($text -join "`n")+"`n",[Text.UTF8Encoding]::new($false))
}
$fields=@{
    '英雄生命加成'='hero_health_bonus_pct'; '英雄护甲加成'='hero_armor_bonus_pct'
    '英雄初始属性'='hero_initial_attributes';'英雄每秒属性'='hero_attributes_per_second'
    '英雄攻击加成'='hero_attack_bonus_pct';'英雄三围加成'='hero_attribute_bonus_pct'
    '英雄伤害减免'='hero_damage_reduction_pct';'英雄最终伤害'='hero_final_damage_bonus_pct'
    '英雄造成伤害加木材'='hero_damage_wood_flat';'英雄造成伤害攻击'='hero_damage_attack_growth'
    '英雄攻击减甲'='hero_attack_armor_reduction';'英雄造成伤害属性'='hero_attributes_per_damage'
    '木材'='initial_wood';'金币'='initial_gold';'塔生命'='wall_initial_health'
    '每秒木材'='wood_per_second';'塔生命加成'='wall_health_bonus_pct'
    '墙生命加成'='wall_health_bonus_pct';'箭塔攻击加成'='tower_attack_bonus_pct'
}
function Effect($text) {
    if($text.Trim() -notmatch '^(.+?)\+([0-9.]+)%?$'){throw "Unmapped effect: $text"}
    $field=$fields[$Matches[1]]; $value=$Matches[2]
    if(-not $field){throw "Unmapped effect field: $text"}
    return @($field,$value)
}
$bosses=@('sven','mars','doom_bringer','spectre','faceless_void','antimage','kunkka','pudge','weaver','legion_commander','clinkz','rubick')
$models=@('sven/sven','mars/mars','doom/doom','spectre/spectre','faceless_void/faceless_void','antimage/antimage','kunkka/kunkka','pudge/pudge','weaver/weaver','legion_commander/legion_commander','clinkz/clinkz','rubick/rubick')
$fragments=@();$levels=@();$definitions=@();$stats=@()
$rows=Read-WorksheetRows $Workbook '神兵碎片'
foreach($i in ($rows.Keys | Sort-Object)) {
    $row=$rows[$i]
    if($row.B -notmatch '^(神兵-.+?)\s+N(\d+)解锁'){continue}
    $name=$Matches[1];$minimum=[int]$Matches[2];$ordinal=[int]$row.A
    $id='fragment_{0:d2}' -f $ordinal; $hub=[int][math]::Floor(($ordinal-1)/4)+1
    $slot=($ordinal-1)%4+1
    $maxLevel=0
    foreach($line in ($row.E -split "`n")) {
        if($line.Trim() -notmatch '^Lv(\d+)\s+(.+)$'){continue}
        $level=[int]$Matches[1];$description=$Matches[2];$effect=Effect $description
        $maxLevel=[math]::Max($maxLevel,$level)
        $levels += [pscustomobject][ordered]@{level_id="${id}_lv$level";fragment_id=$id;level=$level;required_total=20*$level;description=$description;effect_ids=$effect[0];effect_values=$effect[1];enabled=1}
    }
    $fragments += [pscustomobject][ordered]@{
        fragment_id=$id;display_name=$name;challenge_building=$hub;challenge_order=$slot
        min_difficulty=$minimum;max_owned=999;fragments_per_level=20;max_level=$maxLevel
        daily_limit=20;pass_daily_limit=40;drop_count=1
        promotion_target=$(if($ordinal -le 4){'fragment_{0:d2}' -f ($ordinal+4)}else{''})
        promotion_required_total=201;promotion_cost=10;source_boss=$bosses[$ordinal-1]
        source_boss_stats=($row.C -replace "\r?\n",' / ');source_method=($row.D.Trim());enabled=1
    }
    $definitions += [pscustomobject][ordered]@{
        challenge_id=('hunt_{0:d2}' -f $ordinal);building_id=$hub;slot_order=4+$slot
        display_name="神兽狩猎-$ordinal";min_difficulty=$minimum;reward_kind='fragment';reward_key=$id
        model_path=('models/heroes/'+$models[$ordinal-1]+'.vmdl');model_scale=1.2
        ability_icon=($bosses[$ordinal-1]+'_');cooldown_seconds=3;enabled=$(if($hub -eq 1){1}else{0})
        description="击败对应神兽获得$name 碎片；每20片晋升1级。"
    }
}
$icons=@('sven_gods_strength','mars_arena_of_blood','doom_bringer_doom','spectre_haunt','faceless_void_chronosphere','antimage_mana_void','kunkka_ghostship','pudge_dismember','weaver_time_lapse','legion_commander_duel','clinkz_death_pact','rubick_spell_steal')
for($i=0;$i -lt $definitions.Count;$i++){$definitions[$i].ability_icon=$icons[$i]}
$colors=@('white','blue','purple','green');$names=@('白色','蓝色','紫色','绿色')
for($i=1;$i -le 4;$i++) {
    $description=$(if($i -le 3){"从工作簿虚空之影N${i}对应物品池独立随机2次，允许重复，最终固定2件。"}else{"击败BOSS随机获得2件$($names[$i-1])虚空道具；通行证额外1件，同品质内等概率。"})
    $definitions += [pscustomobject][ordered]@{challenge_id="shadow_$i";building_id=1;slot_order=$i;display_name="虚空之影$i";min_difficulty=$i;reward_kind='shadow';reward_key="n$i";model_path='models/heroes/nevermore/nevermore.vmdl';model_scale=1.1;ability_icon='nevermore_shadowraze1';cooldown_seconds=3;enabled=1;description=$description}
}
$cage=@();$rows=Read-WorksheetRows $Workbook '秘法牢笼'
foreach($i in ($rows.Keys | Sort-Object)) {
    $row=$rows[$i];$ordinal=0
    if(-not [int]::TryParse([string]$row.A,[ref]$ordinal) -or $ordinal -lt 1 -or $ordinal -gt 27){continue}
    $effect=Effect $row.D
    $cage += [pscustomobject][ordered]@{item_id=('cage_{0:d2}' -f $ordinal);display_name=$row.B;pool_id=('cage_'+([int][math]::Floor(($ordinal-1)/9)+1));max_owned=149;description=$row.D;effect_ids=$effect[0];effect_values=$effect[1];enabled=1}
}
for($i=1;$i -le 3;$i++) {
    $definitions += [pscustomobject][ordered]@{challenge_id="cage_$i";building_id=1;slot_order=8+$i;display_name="秘法牢笼-$i";min_difficulty=6+$i;reward_kind='cage';reward_key="cage_$i";model_path='models/heroes/visage/visage.vmdl';model_scale=1.5;ability_icon='visage_summon_familiars';cooldown_seconds=3;enabled=1;description='击败BOSS随机掉落本池9种材料之一；通行证额外1件。'}
}
$definitions=@($definitions | Sort-Object building_id,slot_order)
foreach($def in $definitions){for($n=1;$n -le 10;$n++){
    $stats += [pscustomobject][ordered]@{stats_id=($def.challenge_id+"_N$n");challenge_id=$def.challenge_id;difficulty_id="N$n";health=1000;attack=10;war3_armor=0;attack_speed=1;move_speed=280;attack_range=160;magic_resistance=0;enabled=1;notes='测试数值；N5-N10一致，后续在本表逐行调整。'}
}}
Write-ArchiveTable 'archive_fragment_definitions.csv' $fragments 'string,string,number,number,number,number,number,number,number,number,number,string,number,number,string,string,string,boolean' '碎片ID,神兵名称,建筑序号,狩猎顺序,解锁难度,持有上限,每级所需碎片,已配置最高等级,每日上限,通行证每日上限,每次掉落,晋升目标,晋升累计门槛,晋升消耗,来源BOSS,参考原始属性,来源晋升说明,启用'
Write-ArchiveTable 'archive_fragment_levels.csv' $levels 'string,string,number,number,string,list,list,boolean' '等级ID,碎片ID,等级,所需累计碎片,本级新增效果,词条ID,数值,启用'
Write-ArchiveTable 'archive_cage_items.csv' $cage 'string,string,string,number,string,list,list,boolean' '材料ID,名称,所属BOSS池,持有上限,单件效果,词条ID,数值,启用'
Write-ArchiveTable 'archive_challenge_definitions.csv' $definitions 'string,number,number,string,number,string,string,string,number,string,number,boolean,string' '挑战ID,建筑序号,技能顺序,技能名称,解锁难度,奖励种类,奖励ID或品质,模型,模型缩放,技能图标,冷却秒,启用,说明'
Write-ArchiveTable 'archive_challenge_stats.csv' $stats 'string,string,string,number,number,number,number,number,number,number,boolean,string' '属性ID,挑战ID,当前关卡,生命,攻击,魔兽护甲,每秒攻击次数,移速,攻击距离,魔抗百分比,启用,备注'
$shadowRules=for($i=1;$i -le 4;$i++){
    [pscustomobject][ordered]@{challenge_id="shadow_$i";source_boss_difficulty="n$i";drop_count=2;pass_extra_count=$(if($i -le 3){0}else{1});allow_duplicates=1;enabled=1;notes=$(if($i -le 3){"从工作簿虚空之影N$i 对应物品池独立随机2次，允许重复，最终固定2件。"}else{'沿用既有虚空之影4规则；基础2件，通行证额外1件。'})}
}
Write-ArchiveTable 'archive_shadow_challenge_drop_rules.csv' $shadowRules 'string,string,number,number,boolean,boolean,string' '挑战ID,工作簿物品池难度,固定掉落数量,通行证额外数量,允许重复,启用,说明'
& (Join-Path $PSScriptRoot 'build_archive_configs.ps1')
