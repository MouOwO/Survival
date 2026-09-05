param(
    [string]$Workbook = 'C:\Users\Administrator\Desktop\通关存档效果.xlsx'
)

$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent $PSScriptRoot
$lotteryRoot = Join-Path $repo 'data\csv\抽奖系统'
$itemOutput = Join-Path $lotteryRoot 'lottery_item_definitions.csv'
$poolOutput = Join-Path $lotteryRoot 'lottery_pool_items.csv'
$catalogOutput = Join-Path $repo 'data\csv\物品系统\content_catalog.csv'
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

$itemIds = @'
lottery_attribute_crystal
lottery_protection_crystal
lottery_nature_crystal
lottery_bombardment_crystal
lottery_recovery_crystal
lottery_resistance_crystal
lottery_expansion_crystal
lottery_shooting_crystal
lottery_wealth_crystal
lottery_lumber_crystal
lottery_recovery_spirit
lottery_life_spirit
lottery_nature_spirit
lottery_sharp_spirit
lottery_divine_spirit
lottery_universal_tool
lottery_gale_bow
lottery_swift_emblem
lottery_quick_dry_cement
lottery_windspeed_bowstring
lottery_hippogryph_onslaught
lottery_soul_devouring_blade
lottery_tower_retrofit
lottery_steel_wall
lottery_gathering_grimoire
lottery_gathering_divine_codex
lottery_aaron_cannon
lottery_darksteel_wall
lottery_lumber_legacy
lottery_titan_shield
lottery_reincarnation_orb
lottery_time_orb
lottery_divine_tower_blessing
lottery_abundance_blessing
lottery_omniscience_blessing
lottery_unbreakable_fortress
lottery_struggle_diary
lottery_chosen_hero
lottery_chief_god_blessing
lottery_ember_of_legacy
lottery_lumber_immortal
lottery_supreme_fishing_rod
lottery_flame_wall
lottery_magical_girl_juggernaut
lottery_forest_burning_edge
lottery_endless_growth_ring
lottery_lumber_fury
lottery_candle_dragon_wing
lottery_oak_bulwark
lottery_seed_of_all_wood
lottery_sharpwood_tower_core
lottery_hero_medal
lottery_monkey_king
lottery_immortal_nirvana
lottery_soul_lock_box
lottery_sky_turning_seal
lottery_heaven_devouring_pill
lottery_heaven_reaching_tower_seal
lottery_sovereign_under_heaven
lottery_greenwood_rampart
lottery_lumber_expert
lottery_woodforged_thousand_arrows
lottery_greenwood_nirvana
lottery_fallen_sky_mine
lottery_jade_purity_sword_immortal
lottery_immortal_slaying_sword_array
lottery_investiture_of_gods
lottery_heavenly_puppet
lottery_mountain_sea_kunpeng
lottery_reincarnation_immortal_stele
lottery_ancient_pine_fortification
lottery_woodcraft_grandmaster
lottery_forestcast_thousand_bolts
lottery_emerald_wood_origin
lottery_dimensional_barrier
lottery_orbital_cannon_core
lottery_dragon_knight_vanguard_mk1
lottery_nano_cluster
lottery_cyber_overlord
lottery_neural_reconstruction_module
lottery_void_signal_terminal
lottery_nitride_alloy_wall
lottery_data_unit
lottery_pulse_conduction_turret
lottery_cybernetic_implant
lottery_crystalline_armor
lottery_signal_hub
lottery_magnetic_disruption_turret
lottery_rift_implant
'@ -split "`r?`n" | Where-Object { $_ -ne '' }

$effects = @{
    5='hero_initial_attributes=50'; 6='wall_armor=2'; 7='lumberjack_attack_speed_bonus_pct=2'
    8='tower_attack_flat=30'; 9='wall_health_regen_per_second=5'; 10='wall_damage_block=10'
    11='wall_health_per_second=1'; 12='tower_attack_flat=50'; 13='gold_mine_efficiency_pct=2'
    14='initial_wood=30'; 15='wall_health_regen_per_second=10'; 16='wall_initial_health=1000'
    17='wood_per_second=1'; 18='tower_attack_flat=100'; 19='gold_mine_final_output_flat=3'
    20='lumberjack_attack_speed_bonus_pct=3|gold_mine_efficiency_pct=3'
    21='hero_attack_speed_bonus_pct=5|hero_final_damage_bonus_pct=5'
    22='tower_attack_speed_bonus_pct=5|tower_final_damage_bonus_pct=5'
    23='tower_attack_per_second=1|hero_attributes_per_second=1'
    24='hero_attack_speed_bonus_pct=5|tower_attack_speed_bonus_pct=5'
    25='hero_attack_bonus_pct=3|hero_attribute_bonus_pct=3'
    26='hero_damage_attack_growth=2|hero_attributes_per_damage=1'
    27='tower_attack_speed_bonus_pct=20|tower_attack_per_second=2|tower_attack_bonus_pct=5'
    28='wall_initial_health=3000|wall_armor=10|wall_health_per_second=5|wall_health_bonus_pct=5'
    29='lumberjack_efficiency=1|initial_population_cap=1|lumberjack_attack_speed_bonus_pct=5'
    30='gold_per_second=2|lumberjack_efficiency=2|lumberjack_attack_interval_reduction=0.02|wall_health_per_second=30|wall_damage_reduction_pct=3'
    31='lumberjack_efficiency=1|tower_attack_speed_bonus_pct=15|hero_attack_speed_bonus_pct=15|tower_final_damage_bonus_pct=15|hero_final_damage_bonus_pct=15'
    32='wall_initial_health=5000|wall_armor=20|wall_health_per_second=8|wall_armor_per_second=0.1'
    33='lumberjack_efficiency=2|initial_population_cap=2|lumberjack_attack_speed_bonus_pct=8'
    34='hero_initial_health=50000|hero_initial_attributes=3000|hero_initial_armor=100'
    35='lumberjack_efficiency=3|hero_attack_speed_bonus_pct=20|hero_final_damage_bonus_pct=20|tower_attack_bonus_pct=10|wall_health_bonus_pct=10|hero_rebirth_attribute_bonus_pct=2'
    36='lumberjack_efficiency=3|gold_mine_build_cap=1|tower_basic_attack_growth=1|hero_attributes_per_second=30|tower_attack_per_second=30'
    37='wood_per_second=30|tower_attack_bonus_pct=30|tower_basic_attack_growth=3|tower_attack_armor_reduction=0.2|tower_critical_chance_pct=5|tower_critical_damage_bonus_pct=20'
    38='gold_mine_yield_bonus_pct=20|lumberjack_attack_speed_bonus_pct=15|lumberjack_attack_growth=10|lumberjack_efficiency=5|wall_health_per_second=100|initial_population_cap=3'
    39='lumberjack_attack_speed_bonus_pct=20|tower_basic_attack_growth=1|tower_final_damage_bonus_pct=20|tower_attack_bonus_pct=10|wall_damage_reduction_pct=5'
    40='wall_armor=200|wall_armor_per_second=0.1|hero_damage_reduction_pct=5|hero_health_bonus_pct=60|hero_armor_bonus_pct=30'
    41='tower_damage_attack_growth=10|tower_attack_armor_reduction=0.1|tower_critical_chance_pct=20|tower_critical_damage_bonus_pct=50'
    42='hero_attack_bonus_pct=8|hero_attribute_bonus_pct=8|tower_attack_bonus_pct=8'
    43='hero_damage_wood_flat=5|hero_damage_attack_growth=5|hero_attributes_per_damage=5|hero_attack_armor_reduction=2|hero_final_damage_bonus_pct=20'
    44='hero_basic_attack_growth=0.1'
    45='lumberjack_efficiency=5|lumberjack_attack_speed_bonus_pct=20|gold_per_second=100|wood_per_second=100|map_level=1'
    46='tower_damage_attack_growth=10|tower_attack_armor_reduction=0.1|tower_attack_speed_bonus_pct=30|map_level=1'
    47='wall_armor=500|wall_armor_per_second=0.2|wall_health_bonus_pct=30|wall_armor_bonus_pct=30|wall_health_per_second=100|gold_mine_build_cap=1|map_level=1'
    48='hero_attack_armor_reduction=10|hero_basic_attack_growth=10|hero_attribute_growth=20|hero_attack_bonus_pct=10|hero_final_damage_bonus_pct=10|map_level=1'
    49='tower_damage_attack_growth=20|tower_final_damage_bonus_pct=30|tower_attack_armor_reduction=0.5|hero_attack_armor_reduction=10|hero_attribute_growth=10|hero_attribute_bonus_pct=10'
    50='hero_attack_attribute_efficiency_pct=10|hero_final_damage_bonus_pct=10|hero_attack_armor_reduction=10'
    51='lumberjack_harvest_yield_bonus_pct=25|gold_per_second=100|wood_per_second=500|lumberjack_efficiency=10|gold_mine_yield_bonus_pct=10|hero_damage_wood_flat=5'
    52='hero_critical_chance_pct=10|hero_critical_damage_bonus_pct=100|hero_final_damage_bonus_pct=20|hero_attribute_bonus_pct=10|hero_attack_bonus_pct=20|hero_attack_armor_reduction=10|gold_mine_build_cap=1'
    53='wall_armor=30|wall_armor_per_second=0.1|wall_health_bonus_pct=10|wall_armor_bonus_pct=10|wall_health_per_second=10'
    54='gold_mine_efficiency_pct=10|lumberjack_efficiency=2|gold_per_second=10|wood_per_second=10|lumberjack_attack_speed_bonus_pct=10'
    55='tower_attack_speed_bonus_pct=15|tower_final_damage_bonus_pct=15|tower_attack_armor_reduction=0.1|tower_attack_per_second=20|tower_damage_attack_growth=3'
    56='hero_attribute_growth=5|hero_attribute_bonus_pct=8|hero_attack_armor_reduction=4|hero_attack_speed_bonus_pct=10|hero_final_damage_bonus_pct=10'
    57='hero_attack_armor_reduction=10|hero_basic_attack_growth=10|hero_attribute_growth=20|hero_attack_bonus_pct=10|hero_final_damage_bonus_pct=10|map_level=1'
    58='hero_critical_damage_bonus_pct=100|hero_final_damage_bonus_pct=20|hero_attribute_bonus_pct=20|hero_attack_bonus_pct=20|hero_attack_armor_reduction=20'
    59='gold_mine_yield_bonus_pct=30|lumberjack_efficiency=20|lumberjack_attack_speed_bonus_pct=20|gold_mine_build_cap=1|map_level=1'
    60='hero_attributes_per_second=1000|hero_attack_bonus_pct=20|hero_attribute_bonus_pct=15|hero_final_damage_bonus_pct=20|hero_attack_armor_reduction=15'
    61='wall_damage_reduction_pct=10|wall_armor=500|wall_armor_per_second=0.1|gold_per_second=50|wood_per_second=50|lumberjack_attack_speed_bonus_pct=10|lumberjack_efficiency=15|gold_mine_efficiency_pct=15'
    62='hero_final_damage_bonus_pct=20|tower_final_damage_bonus_pct=20|tower_attack_bonus_pct=30|tower_attack_armor_reduction=0.2|tower_damage_attack_growth=10|tower_attack_per_second=50|tower_critical_chance_pct=10|tower_critical_damage_bonus_pct=100'
    63='hero_initial_attributes=1000000|hero_damage_attack_growth=30|hero_critical_damage_bonus_pct=100|hero_attack_armor_reduction=15|hero_attribute_growth=15|hero_attribute_bonus_pct=15|hero_final_damage_bonus_pct=15|hero_attack_interval_reduction=0.03'
    64='wall_armor=30|wall_armor_per_second=0.1|wall_health_bonus_pct=10|wall_armor_bonus_pct=10|wall_health_per_second=10'
    65='gold_mine_efficiency_pct=10|lumberjack_efficiency=2|gold_per_second=10|wood_per_second=10|lumberjack_attack_speed_bonus_pct=10'
    66='tower_attack_speed_bonus_pct=15|tower_final_damage_bonus_pct=15|tower_attack_armor_reduction=0.1|tower_attack_per_second=20|tower_damage_attack_growth=3'
    67='hero_attribute_growth=5|hero_attribute_bonus_pct=8|hero_attack_armor_reduction=4|hero_attack_speed_bonus_pct=10|hero_final_damage_bonus_pct=10'
    68='gold_per_second=60|wood_per_second=60|lumberjack_efficiency=15|gold_mine_efficiency_pct=25|gold_mine_income_interval_reduction=0.1'
    69='hero_attack_armor_reduction=15|hero_basic_attack_growth=15|hero_attribute_growth=15|hero_attack_bonus_pct=15|hero_attribute_bonus_pct=10|hero_final_damage_bonus_pct=10|map_level=1'
    70='hero_critical_damage_bonus_pct=200|hero_attribute_growth=20|hero_attribute_bonus_pct=20|hero_final_damage_bonus_pct=20|hero_attack_armor_reduction_pct=10'
    71='hero_attack_attribute_efficiency_pct=8|tower_attack_bonus_pct=35|tower_final_damage_bonus_pct=35|tower_attack_interval_reduction=0.1|hero_final_damage_bonus_pct=30|hero_attribute_bonus_pct=30|hero_attack_armor_reduction=20'
    72='wall_damage_reduction_pct=10|wall_armor=500|wall_armor_per_second=0.1|hero_final_damage_bonus_pct=10|hero_attribute_bonus_pct=10'
    73='hero_initial_attributes=150000|hero_damage_attack_growth=40|hero_critical_damage_bonus_pct=150|hero_attack_armor_reduction=20|hero_attribute_growth=20|hero_attribute_bonus_pct=20|hero_final_damage_bonus_pct=20'
    74='hero_attributes_per_second=1500|hero_attack_bonus_pct=20|hero_attribute_bonus_pct=20|hero_final_damage_bonus_pct=20|hero_attack_armor_reduction=20'
    75='wall_armor=30|wall_armor_per_second=0.1|wall_health_bonus_pct=10|wall_armor_bonus_pct=10|wall_health_per_second=10'
    76='gold_mine_efficiency_pct=10|lumberjack_efficiency=2|gold_per_second=10|wood_per_second=10|lumberjack_attack_speed_bonus_pct=10'
    77='tower_attack_speed_bonus_pct=15|tower_final_damage_bonus_pct=15|tower_attack_armor_reduction=0.1|tower_attack_per_second=20|tower_damage_attack_growth=3'
    78='hero_attribute_growth=5|hero_attribute_bonus_pct=8|hero_attack_armor_reduction=4|hero_attack_speed_bonus_pct=10|hero_final_damage_bonus_pct=10'
    79='wall_damage_reduction_pct=10|wall_armor=500|wall_armor_per_second=0.12|hero_final_damage_bonus_pct=15|hero_attribute_bonus_pct=15|hero_attribute_growth=15|hero_attack_armor_reduction=15|hero_damage_attack_growth=15|map_level=1'
    80='hero_attack_interval_reduction=0.03|hero_initial_attributes=200000|hero_damage_attack_growth=40|hero_critical_damage_bonus_pct=150|hero_attack_armor_reduction=20|hero_attribute_growth=20|hero_attribute_bonus_pct=20|hero_final_damage_bonus_pct=20'
    82='hero_attack_armor_reduction_pct=8|hero_final_damage_bonus_pct=20|hero_attribute_bonus_pct=20|hero_attribute_growth=20|hero_damage_attack_growth=20|hero_attack_armor_reduction=20'
    83='hero_attack_attribute_efficiency_pct=8|hero_final_damage_bonus_pct=25|hero_attack_armor_reduction=25|hero_attribute_bonus_pct=25|hero_attribute_growth=25|hero_critical_damage_bonus_pct=200'
    84='tower_attack_armor_reduction=1|tower_final_damage_bonus_pct=30|tower_attack_bonus_pct=35|hero_attribute_bonus_pct=15|hero_final_damage_bonus_pct=15|hero_damage_attack_growth=35|hero_attribute_growth=15'
    85='gold_per_second=70|wood_per_second=70|lumberjack_efficiency=15|gold_mine_efficiency_pct=25|hero_attribute_bonus_pct=15|hero_final_damage_bonus_pct=15|hero_attributes_per_second=2000|hero_attack_bonus_pct=20'
    86='wall_armor=30|wall_armor_per_second=0.1|wall_health_bonus_pct=10|wall_armor_bonus_pct=10|wall_health_per_second=10'
    87='gold_mine_efficiency_pct=10|lumberjack_efficiency=2|gold_per_second=10|wood_per_second=10|lumberjack_attack_speed_bonus_pct=10'
    88='tower_attack_speed_bonus_pct=15|tower_final_damage_bonus_pct=15|tower_attack_armor_reduction=0.1|tower_attack_per_second=20|tower_damage_attack_growth=3'
    89='hero_attribute_growth=5|hero_attribute_bonus_pct=8|hero_attack_armor_reduction=4|hero_attack_bonus_pct=10|hero_final_damage_bonus_pct=10'
    90='wall_armor=30|wall_armor_per_second=0.1|wall_health_bonus_pct=10|wall_armor_bonus_pct=10|wall_health_per_second=10|hero_attribute_bonus_pct=8'
    91='gold_mine_efficiency_pct=10|lumberjack_efficiency=2|gold_per_second=10|wood_per_second=10|lumberjack_attack_speed_bonus_pct=10|hero_attribute_bonus_pct=8'
    92='tower_attack_speed_bonus_pct=15|tower_final_damage_bonus_pct=15|tower_attack_armor_reduction=0.1|tower_attack_per_second=20|tower_damage_attack_growth=3|hero_attribute_bonus_pct=8'
    93='hero_attribute_growth=8|hero_attribute_bonus_pct=8|hero_attack_armor_reduction=8|hero_attack_bonus_pct=10|hero_final_damage_bonus_pct=10'
}

$partialRows = @(36,41,42,44,45,46,47,48,49,50,51,57,58,59,60,61,62,68,69,71,72,73,74,79,80,82,83,84,85)
$lowConfidenceRows = @(8,23,25,31,37,49,59,67,72,73,74,75,76)
$displayNameOverrides = @{ 48='魔法少女（剑圣）'; 69='玉清剑仙'; 81='龙骑尖兵1型' }
$specialNotes = @{
    36='进攻Boss击杀后的动态攻击加成待地图Boss事件提供玩家归属。'
    39='地图等级的城墙生命百分比与每秒生命派生效果已由独立规则表接入。'
    40='来源文本重复两次英雄生命加成+30%；按可叠加合计60%实现。'
    44='来源兑换价为58每个或5000每100个；抽奖重复规则下只持有1个且数量阈值暂不生效。'
    48='英雄解锁、双英雄组合加成和开局一转技能需要独立英雄权益规则。'
    52='来源文本英雄攻击加成+10%重复两次；按可叠加合计20%实现。'
    57='英雄解锁、双英雄组合加成和开局一转技能需要独立英雄权益规则。'
    79='来源“012”按0.12解释；周期屏障属于待实现的复杂机制。'
    81='Excel效果单元格为空；为避免抽到无效果道具暂不入池且不可兑换。'
}

function Csv([object]$value) {
    $text = [string]$value
    if ($text.Contains('"')) { $text = $text.Replace('"', '""') }
    if ($text.IndexOfAny([char[]]@(',', '"', "`r", "`n")) -ge 0) { return '"' + $text + '"' }
    return $text
}

function Read-WorksheetRows([string]$path, [string]$sheetName) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead($path)
    try {
        function EntryText([string]$name) {
            $entry = $zip.GetEntry($name)
            if (-not $entry) { return $null }
            $reader = [System.IO.StreamReader]::new($entry.Open())
            try { return $reader.ReadToEnd() } finally { $reader.Dispose() }
        }
        $shared = @()
        $sharedText = EntryText 'xl/sharedStrings.xml'
        if ($sharedText) {
            [xml]$strings = $sharedText
            $ns = [System.Xml.XmlNamespaceManager]::new($strings.NameTable)
            $ns.AddNamespace('m','http://schemas.openxmlformats.org/spreadsheetml/2006/main')
            foreach ($node in $strings.SelectNodes('//m:si', $ns)) {
                $shared += (($node.SelectNodes('.//m:t', $ns) | ForEach-Object InnerText) -join '')
            }
        }
        [xml]$workbookXml = EntryText 'xl/workbook.xml'
        [xml]$relationshipXml = EntryText 'xl/_rels/workbook.xml.rels'
        $workbookNs = [System.Xml.XmlNamespaceManager]::new($workbookXml.NameTable)
        $workbookNs.AddNamespace('m','http://schemas.openxmlformats.org/spreadsheetml/2006/main')
        $relationshipNamespace = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
        $sheet = $workbookXml.SelectNodes('//m:sheets/m:sheet', $workbookNs) |
            Where-Object name -eq $sheetName | Select-Object -First 1
        if (-not $sheet) { throw "worksheet not found: $sheetName" }
        $relationshipId = $sheet.GetAttribute('id', $relationshipNamespace)
        $target = ($relationshipXml.Relationships.Relationship |
            Where-Object Id -eq $relationshipId).Target
        [xml]$sheetXml = EntryText ('xl/' + $target.TrimStart('/'))
        $sheetNs = [System.Xml.XmlNamespaceManager]::new($sheetXml.NameTable)
        $sheetNs.AddNamespace('m','http://schemas.openxmlformats.org/spreadsheetml/2006/main')
        $result = @{}
        foreach ($row in $sheetXml.SelectNodes('//m:sheetData/m:row', $sheetNs)) {
            $values = @{}
            foreach ($cell in $row.SelectNodes('./m:c', $sheetNs)) {
                $column = ($cell.r -replace '[0-9]', '')
                if ($cell.t -eq 's') { $value = $shared[[int]$cell.v] }
                elseif ($cell.t -eq 'inlineStr') {
                    $value = (($cell.SelectNodes('.//m:t', $sheetNs) |
                        ForEach-Object InnerText) -join '')
                } else { $value = [string]$cell.v }
                $values[$column] = $value
            }
            $result[[int]$row.r] = $values
        }
        return $result
    } finally { $zip.Dispose() }
}

function Icon-For([string]$description) {
    if ($description -match '墙') { return 'item_crimson_guard' }
    if ($description -match '箭塔|防御塔') { return 'item_mjollnir' }
    if ($description -match '伐木|木材|金矿|金币') { return 'item_ogre_axe' }
    if ($description -match '暴击|攻击|英雄') { return 'item_daedalus' }
    return 'item_ultimate_scepter'
}

$rarityByCost = @{ '188'='n'; '588'='r'; '1288'='sr'; '2388'='ssr'; '5000'='ur' }
$duplicateByRarity = @{ n=5; r=25; sr=100; ssr=400; ur=1000 }
$rows = Read-WorksheetRows $Workbook '积分道具'
$items = [Collections.Generic.List[object]]::new()
for ($sourceRow = 5; $sourceRow -le 93; $sourceRow++) {
    $source = $rows[$sourceRow]
    $rawCost = ([string]$source.D).Trim()
    $exchangePoints = if ($sourceRow -eq 44) { 5000 } else { [int]$rawCost }
    $rarity = if ($sourceRow -eq 44) { 'ur' } else { $rarityByCost[$rawCost] }
    if (-not $rarity) { throw "unsupported exchange cost at row ${sourceRow}: $rawCost" }
    $name = if ($displayNameOverrides.ContainsKey($sourceRow)) {
        $displayNameOverrides[$sourceRow]
    } else { ([string]$source.B).Trim() }
    $description = (([string]$source.C) -replace '\s+', ' ').Trim()
    if ($sourceRow -eq 81 -and $description -eq '') { $description = '效果待策划补充' }
    $enabled = $sourceRow -ne 81
    $effectStatus = if (-not $enabled) { 'missing_source' }
        elseif ($partialRows -contains $sourceRow) { 'partial' } else { 'implemented' }
    $reviewStatus = if ($lowConfidenceRows -contains $sourceRow -or -not $enabled) {
        'needs_confirmation'
    } else { 'ok' }
    $note = if ($specialNotes.ContainsKey($sourceRow)) { $specialNotes[$sourceRow] }
        elseif ($effectStatus -eq 'partial') { '静态数值已实现；来源中的复杂条件或解锁机制待独立规则接入。' }
        elseif ($reviewStatus -eq 'needs_confirmation') { '原表标记低置信；名称与静态数值已按当前工作簿录入。' }
        else { '' }
    $effectTokens = @(([string]$effects[$sourceRow]) -split '\|' |
        Where-Object { $_ -ne '' })
    $effectIds = @($effectTokens | ForEach-Object { ($_ -split '=', 2)[0] })
    $effectValues = @($effectTokens | ForEach-Object { ($_ -split '=', 2)[1] })
    $items.Add([pscustomobject]@{
        item_id=$itemIds[$sourceRow - 5]; display_name=$name; item_type='积分道具'
        duration_type='permanent'; duration_text='永久'; description=$description
        quality=$rarity; icon_type='item'; icon=(Icon-For $description)
        duplicate_points=$duplicateByRarity[$rarity]; exchange_points=$exchangePoints
        exchange_enabled=$(if ($enabled) { 1 } else { 0 })
        effect_ids=($effectIds -join '|'); effect_values=($effectValues -join '|')
        effect_status=$effectStatus
        source_row=$sourceRow; enabled=$(if ($enabled) { 1 } else { 0 })
        review_status=$reviewStatus; notes=$note
    })
}
if ($items.Count -ne 89 -or $itemIds.Count -ne 89) {
    throw "item count mismatch: rows=$($items.Count) ids=$($itemIds.Count)"
}

$headers = @('item_id','display_name','item_type','duration_type','duration_text',
    'description','quality','icon_type','icon','duplicate_points','exchange_points',
    'exchange_enabled','effect_ids','effect_values','effect_status','source_row','enabled',
    'review_status','notes')
$itemLines = [Collections.Generic.List[string]]::new()
$itemLines.Add($headers -join ',')
$itemLines.Add('#中文名:道具ID,显示名称,类型,期限类型,期限显示,效果简介,品质,图标类型,图标,重复分解积分,兑换积分,允许积分兑换,增益字段ID数组,增益数值数组,效果实现状态,来源行,是否启用,审核状态,备注')
$itemLines.Add('#types:string,string,string,string,string,string,string,string,string,number,number,boolean,list,list,string,number,boolean,string,string')
foreach ($item in $items) {
    $values = @(foreach ($header in $headers) { Csv $item.$header })
    $itemLines.Add($values -join ',')
}
[IO.File]::WriteAllText($itemOutput, ($itemLines -join "`n") + "`n", $utf8NoBom)

$poolLines = @(
    'membership_id,pool_id,item_id,item_weight,enabled,review_status,notes'
    '#中文名:成员ID,奖池ID,道具ID或通配符,同品质内权重,是否启用,审核状态,备注'
    '#types:string,string,string,number,boolean,string,string'
    'map_all,map,*,1,1,ok,自动纳入全部已启用积分道具并按品质分组等权抽取。'
    'cultivation_all,cultivation,*,1,1,needs_confirmation,特殊池暂时共用全部已启用积分道具。'
    'dragon_knight_all,dragon_knight,*,1,1,needs_confirmation,特殊池暂时共用全部已启用积分道具。'
    'summer_all,summer,*,1,1,needs_confirmation,特殊池暂时共用全部已启用积分道具。'
)
[IO.File]::WriteAllText($poolOutput, ($poolLines -join "`n") + "`n", $utf8NoBom)

$catalogLines = [Collections.Generic.List[string]]::new()
foreach ($line in [IO.File]::ReadAllLines($catalogOutput)) {
    if ($line -notmatch '^lottery_(?!ticket,)') { $catalogLines.Add($line) }
}
foreach ($item in $items) {
    $catalogValues = @(
        $item.item_id, '', 'item', 'lottery_reward', $item.display_name,
        $item.description, $item.icon, $item.enabled, '积分道具', $item.source_row,
        0, $item.review_status, '抽奖系统持久化内容ID；品质与效果由抽奖定义表维护。'
    ) | ForEach-Object { Csv $_ }
    $catalogLines.Add($catalogValues -join ',')
}
[IO.File]::WriteAllText($catalogOutput, ($catalogLines -join "`n") + "`n", $utf8NoBom)

# build_configs.py normally generates this projection, but Workshop machines
# are not guaranteed to have Python installed. Keep this focused importer
# self-contained so the catalog used by server code cannot lag behind the CSV.
$generatedCatalog = Join-Path $repo 'scripts\vscripts\config\generated\content_catalog.lua'
$catalogHeaders = @(([IO.File]::ReadLines($catalogOutput) | Select-Object -First 1) -split ',')
$catalogTypeLine = [IO.File]::ReadLines($catalogOutput) |
    Where-Object { $_.StartsWith('#types:') } | Select-Object -First 1
$catalogTypes = @($catalogTypeLine.Substring(7) -split ',')
$generatedLines = [Collections.Generic.List[string]]::new()
$generatedLines.Add('-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.')
$generatedLines.Add('-- Source: content_catalog.csv')
$generatedLines.Add('local M = {}')
$generatedLines.Add('M.rows = {')
foreach ($row in (Import-Csv $catalogOutput | Where-Object {
    $_.content_id -and -not $_.content_id.StartsWith('#')
})) {
    $parts = [Collections.Generic.List[string]]::new()
    for ($index = 0; $index -lt $catalogHeaders.Count; $index++) {
        $key = $catalogHeaders[$index]
        $raw = ([string]$row.$key).Trim()
        if ($raw -eq '') { continue }
        $type = $catalogTypes[$index].Trim()
        if ($type -eq 'number') { $converted = $raw }
        elseif ($type -eq 'boolean') {
            $converted = if ($raw.ToLowerInvariant() -in @('1','true','yes','y','on')) {
                'true'
            } else { 'false' }
        } else {
            $converted = '"' + $raw.Replace('\','\\').Replace('"','\"').Replace("`r",'\r').Replace("`n",'\n') + '"'
        }
        $parts.Add("$key = $converted")
    }
    $generatedLines.Add('    { ' + ($parts -join ', ') + ' },')
}
$generatedLines.Add('}')
$generatedLines.Add('M.by_id = {}')
$generatedLines.Add('for _, row in ipairs(M.rows) do')
$generatedLines.Add('    local key = row["content_id"]')
$generatedLines.Add('    if key ~= nil then M.by_id[key] = row end')
$generatedLines.Add('end')
$generatedLines.Add('return M')
$generatedLines.Add('')
[IO.File]::WriteAllText($generatedCatalog, ($generatedLines -join "`n"), $utf8NoBom)

Write-Host "LOTTERY_POINTS_IMPORT_PASS items=$($items.Count) enabled=$(@($items | Where-Object enabled -eq 1).Count)"
