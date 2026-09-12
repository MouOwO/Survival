$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$dataRoot = Join-Path $repo 'data\csv'
$currencyCsv = Get-ChildItem -LiteralPath $dataRoot -Recurse -File `
    -Filter 'lottery_currency_definitions.csv' | Select-Object -First 1
if ($null -eq $currencyCsv) {
    throw 'LOTTERY_CONTRACT_FAIL: lottery CSV directory not found'
}
$csvRoot = $currencyCsv.DirectoryName

function Rows([string]$name, [string]$key) {
    @(Import-Csv (Join-Path $csvRoot $name) | Where-Object {
        $value = [string]$_.$key
        $value -ne '' -and -not $value.StartsWith('#')
    })
}

function Check([bool]$condition, [string]$message) {
    if (-not $condition) { throw "LOTTERY_CONTRACT_FAIL: $message" }
}

$currencies = Rows 'lottery_currency_definitions.csv' 'currency_id'
$pools = Rows 'lottery_pool_definitions.csv' 'pool_id'
$weights = Rows 'lottery_quality_weights.csv' 'weight_id'
$pity = Rows 'lottery_pity_rules.csv' 'rule_id'
$items = Rows 'lottery_item_definitions.csv' 'item_id'
$members = Rows 'lottery_pool_items.csv' 'membership_id'
$gameplayStatsPath = Get-ChildItem -LiteralPath $dataRoot -Recurse -File `
    -Filter 'player_gameplay_stats.csv' | Select-Object -First 1
Check ($null -ne $gameplayStatsPath) 'player_gameplay_stats.csv not found'
$gameplayStats = @(Import-Csv $gameplayStatsPath.FullName | Where-Object {
    $value = [string]$_.field_id
    $value -ne '' -and -not $value.StartsWith('#')
})
$mapLevelRulesPath = Get-ChildItem -LiteralPath $dataRoot -Recurse -File `
    -Filter 'map_level_effect_rules.csv' | Select-Object -First 1
Check ($null -ne $mapLevelRulesPath) 'map_level_effect_rules.csv not found'
$mapLevelRules = @(Import-Csv $mapLevelRulesPath.FullName | Where-Object {
    $_.rule_id -and -not $_.rule_id.StartsWith('#')
})

Check ($pools.Count -eq 4) 'expected exactly four pools'
Check (($pools.pool_id | Sort-Object) -join ',' -eq
    'cultivation,dragon_knight,map,summer') 'pool ids changed unexpectedly'

$specialTicket = $currencies | Where-Object currency_id -eq 'special_lottery_ticket'
Check ($null -ne $specialTicket) 'special ticket definition missing'
Check ($specialTicket.acquisition_policy -eq 'external_purchase_only') `
    'special ticket must remain external_purchase_only'

$contentCatalogPath = (Get-ChildItem -LiteralPath $dataRoot -Recurse -File `
    -Filter 'content_catalog.csv' | Select-Object -First 1).FullName
$contentCatalog = Get-Content $contentCatalogPath -Raw
$contentRows = @(Import-Csv $contentCatalogPath | Where-Object {
    $_.content_id -and -not $_.content_id.StartsWith('#')
})
$shopEntriesPath = (Get-ChildItem -LiteralPath $dataRoot -Recurse -File `
    -Filter 'shop_entries.csv' | Select-Object -First 1).FullName
$shopEntries = Get-Content $shopEntriesPath -Raw
Check ($contentCatalog.Contains('special_lottery_ticket')) `
    'special ticket missing from content catalog'
Check (-not $shopEntries.Contains('special_lottery_ticket')) `
    'special ticket must not be sold by the wood/gold shop'
foreach ($item in $items) {
    Check ($contentRows.content_id -contains $item.item_id) `
        "lottery item $($item.item_id) missing from content catalog"
}
$gatheringGrimoire = $items | Where-Object item_id -eq 'lottery_gathering_grimoire'
Check ($null -ne $gatheringGrimoire) '采集秘典定义缺失'
Check ($gatheringGrimoire.effect_ids -eq
    'lumberjack_efficiency|initial_population_cap|lumberjack_attack_speed_bonus_pct') `
    '采集秘典增益ID数组不完整或顺序异常'
Check ($gatheringGrimoire.effect_values -eq '1|1|5') `
    '采集秘典增益数值数组应为1/1/5'

Check ($gameplayStats.field_id -contains 'map_level') `
    'player gameplay stats lack the permanent map_level field'
$mapLevelGrantItems = @($items | Where-Object {
    ('|' + $_.effect_ids + '|') -like '*|map_level|*'
})
Check ($mapLevelGrantItems.Count -eq 8) `
    'exactly eight lottery items should grant one map level'
foreach ($item in $mapLevelGrantItems) {
    $ids = @([string]$item.effect_ids -split '\|')
    $values = @([string]$item.effect_values -split '\|')
    $index = [Array]::IndexOf($ids, 'map_level')
    Check ($index -ge 0 -and $values[$index] -eq '1') `
        "lottery item $($item.item_id) must grant map_level +1"
}
$mapHealthPct = $mapLevelRules | Where-Object {
    $_.target_field_id -eq 'wall_health_bonus_pct'
}
$mapHealthPerSecond = $mapLevelRules | Where-Object {
    $_.target_field_id -eq 'wall_health_per_second'
}
Check ($mapHealthPct.source_field_id -eq 'map_level' `
    -and [decimal]$mapHealthPct.value_per_level -eq 1) `
    'each map level must grant 1% wall health'
Check ($mapHealthPerSecond.source_field_id -eq 'map_level' `
    -and [decimal]$mapHealthPerSecond.value_per_level -eq 5) `
    'each map level must grant 5 wall health per second'
$omniscience = $items | Where-Object item_id -eq 'lottery_omniscience_blessing'
Check (('|' + $omniscience.effect_ids + '|') -notlike `
    '*|wall_health_per_second|*') `
    'omniscience still grants an incorrect unconditional wall growth value'

Check ($items.Count -eq 89) '积分道具工作表应完整导入89条定义'
Check (@($items | Where-Object enabled -eq '1').Count -eq 88) `
    '应启用88条；缺少效果的龙骑尖兵1型必须保持禁用'
Check (@($items | Where-Object { [int]$_.max_owned -ne 1 }).Count -eq 0) `
    'current lottery item maximum ownership must be one for every definition'
$enabledByQuality = @{}
foreach ($group in ($items | Where-Object enabled -eq '1' | Group-Object quality)) {
    $enabledByQuality[$group.Name] = $group.Count
}
foreach ($expected in @{ n=11; r=4; sr=5; ssr=30; ur=38 }.GetEnumerator()) {
    Check ($enabledByQuality[$expected.Key] -eq $expected.Value) `
        "enabled $($expected.Key) item count is incorrect"
}
Check ((@($items.source_row | ForEach-Object { [int]$_ } | Sort-Object) -join ',') -eq
    ((5..93) -join ',')) 'source rows must cover every workbook item row from 5 through 93'
$rarityByCost = @{ '188'='n'; '588'='r'; '1288'='sr'; '2388'='ssr'; '5000'='ur' }
$duplicatePointsByQuality = @{ n=5; r=25; sr=100; ssr=400; ur=1000 }
foreach ($item in $items) {
    $expected = $rarityByCost[[string]$item.exchange_points]
    Check ($item.quality -eq $expected) `
        "lottery item $($item.item_id) quality does not match exchange points"
    Check ([int]$item.duplicate_points -eq
        [int]$duplicatePointsByQuality[$item.quality]) `
        "lottery item $($item.item_id) duplicate conversion points are incorrect"
    if ($item.enabled -eq '1') {
        $effectIds = @(([string]$item.effect_ids -split '\|') |
            Where-Object { $_ -ne '' })
        $effectValues = @(([string]$item.effect_values -split '\|') |
            Where-Object { $_ -ne '' })
        Check ($effectIds.Count -gt 0) `
            "enabled lottery item $($item.item_id) has no gameplay effect id"
        Check ($effectIds.Count -eq $effectValues.Count) `
            "lottery item $($item.item_id) effect arrays have different lengths"
        foreach ($field in $effectIds) {
            Check ($gameplayStats.field_id -contains $field) `
                "lottery item $($item.item_id) references unknown stat $field"
        }
    }
}

foreach ($pool in $pools) {
    Check ($currencies.currency_id -contains $pool.ticket_content_id) `
        "pool $($pool.pool_id) references an unknown currency"
    $sum = ($weights | Where-Object pool_id -eq $pool.pool_id |
        Measure-Object weight -Sum).Sum
    Check ([int]$sum -eq 10000) "pool $($pool.pool_id) weights sum to $sum"
}

$mapUr = $weights | Where-Object { $_.pool_id -eq 'map' -and $_.quality -eq 'ur' }
Check ([int]$mapUr.weight -eq 10) 'map UR weight must be 0.1% (10/10000)'
foreach ($poolId in @('cultivation', 'dragon_knight', 'summer')) {
    $urWeight = $weights | Where-Object { $_.pool_id -eq $poolId -and $_.quality -eq 'ur' }
    Check ([int]$urWeight.weight -gt [int]$mapUr.weight) `
        "$poolId UR weight must be higher than map UR weight"
    Check ([int]$urWeight.weight -eq 1000) `
        "$poolId provisional UR weight must remain unchanged at 10%"
    $urPity = $pity | Where-Object { $_.pool_id -eq $poolId -and $_.target_quality -eq 'ur' }
    Check ($null -ne $urPity -and [int]$urPity.threshold -eq 10) `
        "$poolId must have a ten-draw UR guarantee"
    Check (($pools | Where-Object pool_id -eq $poolId).ticket_content_id -eq
        'special_lottery_ticket') "$poolId must consume special tickets"
}

Check ($pity.Count -eq 4) 'expected one batch guarantee per pool'
$mapGuarantee = $pity | Where-Object pool_id -eq 'map'
Check ($mapGuarantee.target_quality -eq 'sr') `
    'map ten-pull guarantee must be SR'
foreach ($rule in $pity) {
    Check ($rule.trigger_mode -eq 'batch_only') `
        "pity rule $($rule.rule_id) must be batch_only"
    Check ([int]$rule.threshold -eq 10) `
        "pity rule $($rule.rule_id) must apply to a ten-pull request"
}
foreach ($item in $items) {
    Check ($item.item_type -ne '') "lottery item $($item.item_id) has no type"
    Check ($item.duration_type -ne '') `
        "lottery item $($item.item_id) has no duration type"
    Check ($item.duration_text -ne '') `
        "lottery item $($item.item_id) has no duration display"
    Check ($item.icon_type -in @('item', 'ability', 'image')) `
        "lottery item $($item.item_id) has invalid icon type"
}

foreach ($member in $members) {
    Check ($pools.pool_id -contains $member.pool_id) `
        "membership $($member.membership_id) references unknown pool"
    Check ($member.item_id -eq '*' -or $items.item_id -contains $member.item_id) `
        "membership $($member.membership_id) references unknown item"
}
Check ($members.Count -eq 4) 'each pool should use one all-items wildcard membership'
foreach ($pool in $pools) {
    Check ($null -ne ($members | Where-Object {
        $_.pool_id -eq $pool.pool_id -and $_.item_id -eq '*'
    })) "pool $($pool.pool_id) does not include the enabled item catalog"
}

$dotaRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $repo))
$service = Get-Content (Join-Path $repo `
    'scripts\vscripts\systems\lottery_service.lua') -Raw
Check ($service.Contains('local guarantee = batch_guarantee(pool, count)')) `
    'server does not select guarantees from the current batch size'
Check ($service.Contains('if guarantee and draw_index == count')) `
    'server does not enforce the batch guarantee inside the same request'
Check ($service.Contains('forced_quality = guarantee.target_quality')) `
    'batch guarantee must supply its configured quality exactly'
Check (-not $service.Contains('random_quality_at_least')) `
    'batch guarantee can still upgrade map SR guarantee into UR'
Check ($service.Contains('local function item_at_limit')) `
    'server does not compare owned count with the item ownership limit'
Check ($service.Contains('if item_at_limit(counts, item) then')) `
    'draw grants do not convert items after reaching max_owned'
Check ($service.Contains('if item_at_limit(inventory.counts or {}, item) then')) `
    'points exchange does not enforce max_owned'
Check ($service.Contains('local function item_effect_marker(item_id, copy_index)')) `
    'allowed extra copies do not use independent effect markers'
Check ($service.Contains('marker = marker .. ":copy:" .. tostring(copy_index)')) `
    'effect markers cannot distinguish multiple allowed copies'
Check ($service.Contains('local copy_index = item_owned_count(counts, item) + 1')) `
    'draw grants do not apply effects for the next allowed copy'
Check ($service.Contains(
    'counts[item.id] = (counts[item.id] or 0) + (grant.duplicate and 0 or 1)')) `
    'ten-pull ownership counts are not updated between results'
Check ($service.Contains('guarantee_satisfied = guarantee == nil or guarantee_hit')) `
    'server response does not expose whether its ten-pull guarantee was satisfied'
Check (-not $service.Contains('count + 1 >= rule.threshold')) `
    'server still contains cumulative single-draw pity logic'

$importer = Get-Content (Join-Path $repo `
    'tools\import_lottery_points_items.ps1') -Raw
Check ($importer.Contains('$existingMaxOwned')) `
    'workbook import does not preserve configured ownership limits'
Check ($importer.Contains('$maxOwned = if ($existingMaxOwned.ContainsKey($itemId))')) `
    'workbook import resets max_owned instead of defaulting only new items to one'

$client = Get-Content (Join-Path $dotaRoot `
    'content\dota_addons\Survival\panorama\scripts\custom_game\lottery_ui.js') `
    -Raw -ErrorAction SilentlyContinue
if ($client) {
    Check (-not $client.Contains('quality_weights')) 'client contains server weight table name'
    Check (-not $client.Contains('pity_counts')) 'client contains raw pity counter name'
    Check ($client.Contains('pool_id: selectedPoolId')) 'client does not submit selected pool id'
    Check ($client.Contains('function rows(value)')) `
        'client does not normalize Lua numeric-key tables'
    foreach ($unsafeIteration in @(
        '(pools || []).forEach',
        '(items || []).forEach',
        '(payload.results || []).forEach',
        'var rows = pity || []'
    )) {
        Check (-not $client.Contains($unsafeIteration)) `
            "client iterates a Lua table directly: $unsafeIteration"
    }
    Check (-not $client.Contains('payload.ok !== true')) `
        'client does not accept Panorama numeric success values'
    Check ($client.Contains('icon.hittest = false')) `
        'lottery icons can still trigger the native Dota tooltip'
    Check ($client.Contains('LotteryItemTooltip')) `
        'custom lottery tooltip is not wired'
    Check ($client.Contains('[SURVIVAL_LOTTERY_UI] result_count=')) `
        'client does not log its actual rendered result count'
    Check ($client.Contains('$.CreatePanel("Label", iconFrame, "")')) `
        'duplicate conversion notice is not mounted inside the reward icon'
    Check ($client.Contains('重复物品，已转化为')) `
        'duplicate conversion notice does not use the required wording'
    Check (-not $client.Contains('LotteryResultOverlay')) `
        'draw results still open a separate overlay'
}

$inventoryService = Get-Content (Join-Path $repo `
    'scripts\vscripts\systems\content_inventory_service.lua') -Raw
Check ($inventoryService.Contains('lottery_applied_item_effects')) `
    'lottery gameplay effects lack a durable idempotency marker'
Check ($inventoryService.Contains('update_save_sections')) `
    'lottery ownership and gameplay stats are not committed atomically'
Check ($inventoryService.Contains('events.UI_DIRTY')) `
    'lottery gameplay-stat commits do not request a HUD refresh'
$profileService = Get-Content (Join-Path $repo `
    'scripts\vscripts\systems\player_profile_service.lua') -Raw
Check ($profileService.Contains('function M.update_save_sections')) `
    'player profile service lacks an atomic multi-section update method'
$fixtureProvider = Get-Content (Join-Path $repo `
    'scripts\vscripts\systems\player_profile_providers\local_fixture_provider.lua') -Raw
Check ($fixtureProvider.Contains('return true, "fixture_memory_only"')) `
    'Dota VScript cannot fall back to same-session fixture persistence'
$lotteryConfig = Get-Content (Join-Path $repo `
    'scripts\vscripts\config\lottery_config.lua') -Raw
Check ($lotteryConfig.Contains('parse_effect_arrays')) `
    'lottery definitions are not parsed as effect arrays'
$lotteryService = $service
Check ($lotteryService.Contains('sync_owned_item_effects')) `
    'legacy owned lottery items are not migrated into base gameplay stats'
Check ($lotteryService.Contains('gameplay_stat_effects = item.effects')) `
    'lottery grant does not submit the item effect array'
$permanentService = Get-Content (Join-Path $repo `
    'scripts\vscripts\systems\permanent_reward_effect_service.lua') -Raw
Check (-not $permanentService.Contains('lottery_inventory_effects')) `
    'lottery effects would be counted twice through inventory projection'
Check ($permanentService.Contains('map_level_effect_rules')) `
    'permanent effects do not load map-level scaling rules'
Check ($permanentService.Contains('level * value_per_level')) `
    'map-level effects are not scaled proportionally by current level'
$contentInventoryService = $inventoryService
Check ($contentInventoryService.Contains('additional_effect_marker_ids')) `
    'new map-level effects cannot be marked during the original item grant'
Check ($lotteryService.Contains('lottery_map_level_effect_migration')) `
    'existing lottery owners will not receive the versioned map-level migration'
$resourceService = Get-Content (Join-Path $repo `
    'scripts\vscripts\systems\resource_system.lua') -Raw
Check ($resourceService.Contains('on_permanent_projection_changed')) `
    'initial resources and per-second income do not refresh after a lottery grant'
$buildingUpgradeService = Get-Content (Join-Path $repo `
    'scripts\vscripts\systems\building_upgrade_system.lua') -Raw
Check ($buildingUpgradeService.Contains(
    '+ (tonumber(permanent.tower_attack_flat) or 0)')) `
    'tower runtime damage does not include permanent flat attack'
Check ($buildingUpgradeService.Contains('[TOWER_PERMANENT_APPLIED]')) `
    'lottery tower attack projection lacks a runtime verification log'
$gameInfoService = Get-Content (Join-Path $repo `
    'scripts\vscripts\ui\game_info_service.lua') -Raw
Check ($gameInfoService.Contains(
    'number(tower.attack_flat) + number(permanent.tower_attack_flat)')) `
    'game info omits permanent tower attack from its displayed total'
Check ($gameInfoService.Contains(
    'event_bus.subscribe(events.PERMANENT_REWARD_EFFECTS_CHANGED, publish_payload)')) `
    'game info does not refresh when a lottery effect changes'
$layout = Get-Content (Join-Path $dotaRoot `
    'content\dota_addons\Survival\panorama\layout\custom_game\survival_hud.xml') `
    -Raw -ErrorAction SilentlyContinue
if ($layout) {
    Check ($layout.Contains('id="LotteryItemTooltip"')) `
        'custom lottery tooltip panel is missing'
    Check ($layout.Contains('class="LotteryChestMode"')) `
        'initial lottery chest stage is missing'
    Check (-not $layout.Contains('id="LotteryResultOverlay"')) `
        'lottery result overlay must not return'
}

$style = Get-Content (Join-Path $dotaRoot `
    'content\dota_addons\Survival\panorama\styles\custom_game\lottery.css') `
    -Raw -ErrorAction SilentlyContinue
if ($style) {
    Check ($style.Contains('width: 1040px;')) `
        'ten-pull result container lacks horizontal overflow slack'
    Check ($style.Contains('height: 474px;')) `
        'ten-pull result container lacks vertical overflow slack'
}

Write-Host "LOTTERY_CONTRACT_PASS pools=$($pools.Count) items=$($items.Count) memberships=$($members.Count)"
