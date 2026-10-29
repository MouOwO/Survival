-- Explicit native fixture. Never loaded by addon startup or an online match.
if not IsInToolsMode or not IsInToolsMode()
    or not require("debug/offline_logic_test").is_enabled() then
    print("ARCHIVE_NATIVE_PROBE_REFUSED: requires session-memory offline Tools")
    return
end
local bus, events = require("core/event_bus"), require("core/events")
local setup = require("systems/match_setup_service")
local wave = require("systems/wave_system")
local service = require("systems/archive_challenge_service")
local definitions = require("config/generated/archive_challenge_definitions")
local actions = require("config/generated/archive_challenge_actions")
local expected = require("config/generated/archive_challenge_rules").by_id.default
assert(expected.building_count == 4, "four-building generated config missing")
assert(#definitions.rows == 36 and #actions.rows == 7, "archive catalog not rebuilt")
assert(not definitions.by_id.pet, "Pal was excluded by the user")
assert(PlayerResource:IsValidPlayerID(0) and not PlayerResource:IsFakeClient(0), "native human player missing")
if not setup.is_mode_selected() then
    require("debug/mode_unlock_test").enable(0)
    local selected = setup.select_mode(0, "rich", setup.get_session_id())
    assert(selected.ok, selected.error)
    wave.refresh_selection("archive_native_fixture_mode")
end
local difficulty = wave.selection_snapshot().difficulty_id
if difficulty == "" then
    local ok, reason = wave.set_difficulty(setup.get_mode() == "rich" and "N15" or "N10")
    assert(ok, reason)
    difficulty = wave.selection_snapshot().difficulty_id
end
local result = service.begin({player_ids = {0}, difficulty_id = difficulty})
assert(result.ok and result.keep_running, result.error)
local state = assert(service._test.players()[0])
local marker = assert(wave.get_player_spawn_marker(0)):GetAbsOrigin()
local count = 0
for index = 1, 4 do
    local unit = assert(state.hubs[index], "missing native archive building " .. index)
    assert(not unit:IsNull() and unit:GetUnitName() == "npc_archive_challenge_" .. index)
    local position = unit:GetAbsOrigin()
    local distance = math.sqrt((position.x - marker.x)^2 + (position.y - marker.y)^2)
    assert(distance >= 288 and distance <= 841, "archive building outside portal rings")
    local occupied = {}
    local function check(name, slot)
        local ability = assert(unit:FindAbilityByName(name), "native ability missing: " .. name)
        assert(ability:GetLevel() == 1)
        local runtime = service.ability_runtime(unit, name)
        assert(runtime.slot_order == slot and runtime.owner_entindex == unit:entindex())
        assert(runtime.ability_entindex == ability:entindex() and runtime.player_id == 0)
        assert(runtime.upgrade_description and runtime.upgrade_description ~= "")
        assert(not occupied[slot], "duplicate archive grid slot")
        occupied[slot], count = true, count + 1
    end
    for _, row in ipairs(definitions.rows) do
        if row.building_id == index then check("ability_archive_" .. row.challenge_id, row.slot_order) end
    end
    for _, row in ipairs(actions.rows) do
        if row.building_id == index then check(row.ability_name, row.slot_order) end
    end
    print(string.format("ARCHIVE_NATIVE_HUB index=%d entindex=%d distance=%.3f position=%s",
        index, unit:entindex(), distance, tostring(position)))
end
assert(count == #definitions.rows + #actions.rows, "native archive entries missing")
local name = "ability_archive_shadow_1"
local ability = assert(state.hubs[1]:FindAbilityByName(name))
if not state.used.shadow_1 then
    local ok, reason = service.summon(state.hubs[1], "shadow_1", ability)
    assert(ok, reason)
end
local group = assert(state.active_groups.shadow_1)
local boss = assert(group.units[next(group.units)])
local authored = require("config/human_challenge_balance").archive("shadow_1", difficulty)
assert(boss.survival_exact_stat_projection == true)
assert(boss.survival_endless_health == authored.health and boss.survival_endless_attack == authored.attack)
print(string.format("ARCHIVE_NATIVE_STATS difficulty=%s health=%.17g attack=%.17g native_health=%d",
    difficulty, boss.survival_endless_health, boss.survival_endless_attack, boss:GetMaxHealth()))
local player = PlayerResource:GetPlayer(0)
CustomGameEventManager:Send_ServerToPlayer(player, "survival_archive_return", {entindex = state.hubs[4]:entindex()})
bus.emit(events.UI_SNAPSHOT_REQUESTED, {player_id = 0})
print("ARCHIVE_NATIVE_PROBE_PASS: 4 native hubs, configured abilities, exact runtime slots, portal placement, fixed shadow values; no kills or rewards")
