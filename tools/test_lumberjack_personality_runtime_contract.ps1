$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$dotaRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $root))
$content = Join-Path $dotaRoot `
    "content\dota_addons\survival"
$csvPath = [System.IO.Directory]::EnumerateFiles(
    (Join-Path $root "data\csv"),
    "lumberjack_personality_definitions.csv",
    [System.IO.SearchOption]::AllDirectories
) | Select-Object -First 1
if (-not $csvPath) { throw "LUMBERJACK_PERSONALITY_CSV_MISSING" }
$csv = Get-Content -Raw -Encoding UTF8 $csvPath
$generated = Get-Content -Raw -Encoding UTF8 (Join-Path $root `
    "scripts\vscripts\config\generated\lumberjack_personality_definitions.lua")
$ai = Get-Content -Raw -Encoding UTF8 (Join-Path $root `
    "scripts\vscripts\modifiers\modifier_lumberjack_ai.lua")
$tree = Get-Content -Raw -Encoding UTF8 (Join-Path $root `
    "scripts\vscripts\systems\tree_system.lua")
$worker = Get-Content -Raw -Encoding UTF8 (Join-Path $root `
    "scripts\vscripts\systems\worker_system.lua")
$events = Get-Content -Raw -Encoding UTF8 (Join-Path $root `
    "scripts\vscripts\core\events.lua")
$router = Get-Content -Raw -Encoding UTF8 (Join-Path $root `
    "scripts\vscripts\ui\ui_request_router.lua")
$cheer = Get-Content -Raw -Encoding UTF8 (Join-Path $root `
    "scripts\vscripts\modifiers\modifier_lumberjack_cheer.lua")
$runtime = Get-Content -Raw -Encoding UTF8 (Join-Path $root `
    "scripts\vscripts\ui\ability_runtime_service.lua")
$hud = Get-Content -Raw -Encoding UTF8 (Join-Path $content `
    "panorama\scripts\custom_game\hud_takeover.js")
$combat = Get-Content -Raw -Encoding UTF8 (Join-Path $content `
    "panorama\scripts\custom_game\combat_stats.js")

function Check([bool]$condition, [string]$message) {
    if (-not $condition) { throw $message }
}

Check ($csv.Contains("tree_damage_chance_pct,1,1") -and
    $csv.Contains("1%")) `
    "HEAVY_HAND_CSV_PERCENT_MISSING"
Check ($generated.Contains('effect_type = "tree_damage_chance_pct"') -and
    $generated.Contains('effect_value = 1')) `
    "HEAVY_HAND_GENERATED_CONFIG_MISSING"
Check ($ai.Contains('tree_damage_chance_pct = self.tree_damage_chance_pct')) `
    "HEAVY_HAND_TREE_HIT_PAYLOAD_MISSING"
Check ($ai.Contains('if target:GetHealth() <= 1 then') -and
    $ai.Contains('event_bus.emit(events.TREE_DEPLETED')) `
    "NORMAL_TREE_DEPLETION_EVENT_REGRESSED"
Check ($tree.Contains('if not result or result.ok ~= true then return end') -and
    $tree.Contains('current_tree:GetMaxHealth() * tree_damage_pct / 100') -and
    $tree.Contains('math.max(1, math.floor(') -and
    $tree.Contains('current_tree.survival_tree_depleted_callback') -and
    $tree.Contains('event_bus.emit(events.TREE_DEPLETED')) `
    "HEAVY_HAND_POST_COLLECTION_LIFECYCLE_MISSING"

Check ($runtime.Contains('local function on_worker_changed(payload)') -and
    $runtime.Contains('payload.removed_entindexes or {}') -and
    $runtime.Contains('clear_unit({ entindex = tonumber(entindex) })') -and
    $runtime.Contains('worker_payload.building_id = payload.worker_type or "lumberjack"') -and
    $runtime.Contains('publish_unit(worker_payload)')) `
    "FUSION_ABILITY_RUNTIME_REPUBLISH_MISSING"

Check ($worker.Contains('state.unit.survival_attack_speed = 1 / final_attack_interval') -and
    $worker.Contains('event_bus.emit(events.UNIT_COMBAT_STATS_CHANGED, {') -and
    $worker.Contains('reason = "lumberjack_fusion_completed"') -and
    $events.Contains('UNIT_COMBAT_STATS_CHANGED = "unit.combat_stats.changed"') -and
    $router.Contains('event_bus.subscribe(events.UNIT_COMBAT_STATS_CHANGED, on_unit_combat_stats_changed)') -and
    $router.Contains('send_to_player("ui_selected_unit_stats_snapshot", player_id, snapshot)')) `
    "FUSION_COMBAT_STATS_REFRESH_MISSING"
Check ($runtime.Contains('ability_count = math.max(0, tonumber(unit:GetAbilityCount()) or 0)') -and
    $runtime.Contains('clear_removed(unit_key, current)')) `
    "FUSION_ABILITY_COUNT_OR_REMOVAL_MISSING"
Check ($worker.Contains('removed_entindexes = removed_entindexes') -and
    $worker.Contains('removed = true')) `
    "WORKER_RUNTIME_REMOVAL_EVENT_MISSING"

foreach ($source in @($hud, $combat)) {
    Check ($source.Contains('(behavior & 2) !== 0')) `
        "PASSIVE_HOTKEY_FILTER_MISSING"
    Check ($source.Contains('? -1 : standardHotkeyIndex++')) `
        "PASSIVE_CONSUMES_ACTIVE_HOTKEY_SLOT"
}

Check ($worker.Contains('personality_value(') -and
    $worker.Contains('state.unit, "owner_attack_speed_pct"') -and
    $worker.Contains('local worker_state = unit.entindex and workers[unit:entindex()] or nil') -and
    $worker.Contains('worker_state and worker_state.worker_type == "lumberjack"') -and
    (-not $worker.Contains('worker_state and worker_state.worker_type == "repairer"')) -and
    $worker.Contains('unit_player_id ~= player_id then return') -and
    $worker.Contains('modifier:SetStackCount(math.floor(bonus_pct + 0.5))')) `
    "CHEERLEADER_CSV_OR_OWNER_PROJECTION_MISSING"
Check ($worker.Contains('event_bus.request(events.BUILDING_LIST_REQUEST') -and
    $worker.Contains('building.building_id == "arrow_tower"') -and
    $worker.Contains('pcall(EntIndexToHScript, entindex)') -and
    $worker.Contains('apply_cheer_buff(unit, player_id, bonus_pct)')) `
    "CHEERLEADER_EXISTING_ARROW_TOWER_RECOVERY_MISSING"
Check ($cheer.Contains('function modifier_lumberjack_cheer:IsHidden() return false end') -and
    $cheer.Contains('MODIFIER_PROPERTY_ATTACKSPEED_PERCENTAGE') -and
    $cheer.Contains('return self:GetStackCount()')) `
    "CHEERLEADER_VISIBLE_PERCENT_MODIFIER_MISSING"

Write-Output "LUMBERJACK_PERSONALITY_RUNTIME_CONTRACT_PASS"