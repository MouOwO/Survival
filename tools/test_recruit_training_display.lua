package.path = "scripts/vscripts/?.lua;" .. package.path
require("tests/development_release_profile")
-- Production three-choice selection, native modifier callbacks, selected-unit
-- custom-event routing and building presentation. Only Dota engine boundaries
-- (entities, players, event delivery and NetTables) are simulated.
package.path = "scripts/vscripts/?.lua;" .. package.path
function class(base) base.__index = base; return base end
function LinkLuaModifier() end
function IsServer() return true end
DOTA_TEAM_GOODGUYS, DOTA_TEAM_BADGUYS = 2, 3
MODIFIER_PROPERTY_BASEDAMAGEOUTGOING_PERCENTAGE = 1
MODIFIER_PROPERTY_ATTACKSPEED_PERCENTAGE = 2
MODIFIER_PROPERTY_PREATTACK_BONUS_DAMAGE = 3
MODIFIER_EVENT_ON_ATTACK = 4
local handles = {[0] = {id = 0}, [1] = {id = 1}}
PlayerResource = {
    IsValidPlayerID = function(_, id) return handles[id] ~= nil end,
    GetPlayer = function(_, id) return handles[id] end,
    GetTeam = function() return DOTA_TEAM_GOODGUYS end,
}
GameRules = {GetGameTime = function() return 100 end}
RandomFloat = function() return 0 end
RandomInt = function() return 1 end
local listeners, packets, reward_snapshots = {}, {}, {}
CustomGameEventManager = {
    RegisterListener = function(_, name, handler) listeners[name] = handler end,
    Send_ServerToPlayer = function(_, player, name, payload)
        packets[#packets + 1] = {player = player, name = name, payload = payload}
    end,
}
CustomNetTables = {SetTableValue = function(_, name, key, value)
    if name == "survival_rogue_reward" then reward_snapshots[key] = value end
end}
local entities, roster, states, serial, checks = {}, {[0] = {}, [1] = {}}, {}, 0, 0
EntIndexToHScript = function(index) return entities[index] end
Entities = {FindAllByClassname = function()
    local result = {}; for _, unit in pairs(entities) do result[#result + 1] = unit end
    return result
end}
local bus, events = require("core/event_bus"), require("core/events")
local routes = require("config/tower_route_config")
require("modifiers/modifier_rogue_reward_effects")
local rewards = require("systems/rogue_reward_service")
local runtime = require("systems/rogue_effect_runtime_service")
local display = require("ui/building_stat_display")
local function near(actual, expected, label)
    checks = checks + 1
    actual = tonumber(actual)
    assert(actual and math.abs(actual - expected) < 1e-6,
        label .. ": " .. tostring(actual) .. " != " .. tostring(expected))
end
local function assert_true(value, label)
    checks = checks + 1; assert(value, label)
end
local function tower(player, level, raw_attack, static_bonus)
    serial = serial + 1
    local row = assert(routes.current({level = level}))
    raw_attack = raw_attack or row.base_attack_damage
    local unit = {index = serial, survival_player_id = player,
        survival_building_id = "arrow_tower", survival_level = level,
        survival_tower_record_id = row.record_id, survival_tower_stage_id = row.stage_id,
        survival_attack_min = raw_attack, survival_attack_max = raw_attack,
        survival_hud_stat_bonuses = {attack_bonus = static_bonus or 0}, modifiers = {}}
    function unit:IsNull() return false end
    function unit:IsAlive() return true end
    function unit:entindex() return self.index end
    function unit:GetPlayerOwnerID() return self.survival_player_id end
    function unit:GetTeamNumber() return DOTA_TEAM_GOODGUYS end
    function unit:GetUnitName() return "npc_dota_survival_arrow_tower" end
    function unit:FindModifierByName(name) return self.modifiers[name] end
    function unit:FindAllModifiersByName(name)
        return self.modifiers[name] and {self.modifiers[name]} or {}
    end
    function unit:FindAllModifiers()
        local result = {}; for _, modifier in pairs(self.modifiers) do result[#result + 1] = modifier end
        return result
    end
    function unit:HasModifier(name) return self.modifiers[name] ~= nil end
    function unit:RemoveModifierByName(name) self.modifiers[name] = nil end
    function unit:AddNewModifier(_, _, name, params)
        local modifier = self.modifiers[name]
        if modifier then
            if modifier.OnRefresh then modifier:OnRefresh(params or {}) end
            return modifier
        end
        modifier = setmetatable({}, {__index = _G[name] or {}})
        function modifier:GetParent() return unit end
        function modifier:IsNull() return false end
        function modifier:SetStackCount(value) self.stacks = value end
        function modifier:GetStackCount() return self.stacks or 0 end
        self.modifiers[name] = modifier
        if modifier.OnCreated then modifier:OnCreated(params or {}) end
        return modifier
    end
    -- Engine hosts disagree on whether GetDamageMin/Max include BASE modifiers.
    -- This fixture exposes either behavior while the project cache stays exact.
    function unit:GetAverageTrueAttackDamage()
        local pct, flat = 0, 0
        for _, modifier in pairs(self.modifiers) do
            if modifier.GetModifierBaseDamageOutgoing_Percentage then
                pct = pct + modifier:GetModifierBaseDamageOutgoing_Percentage()
            end
            if modifier.GetModifierPreAttack_BonusDamage then
                flat = flat + modifier:GetModifierPreAttack_BonusDamage()
            end
        end
        return self.survival_attack_max * math.max(0, 1 + pct / 100) + flat
    end
    function unit:GetDamageMin()
        return self.engine_includes_modifiers and self:GetAverageTrueAttackDamage() or self.survival_attack_min
    end
    function unit:GetDamageMax() return self:GetDamageMin() end
    local building = {unit = unit, player_id = player, building_id = "arrow_tower",
        level = level, record_id = row.record_id, entindex = serial, team = DOTA_TEAM_GOODGUYS}
    entities[serial], states[serial] = unit, building
    roster[player][#roster[player] + 1] = building
    return building
end
local base, grown, tech = tower(0, 1), tower(0, 1, 4232.6), tower(0, 1, 872, 800)
local foreign = tower(1, 1)
bus.reset()
bus.handle_request(events.BUILDING_LIST_REQUEST, function(payload)
    return {buildings = roster[payload.player_id] or {}}
end)
bus.handle_request(events.BUILDING_QUERY_REQUEST, function(payload) return states[payload.entindex] end)
bus.handle_request(events.HERO_COMBAT_STATS_GET_REQUEST, function() return {ok = false} end)
rewards.init()
require("ui/ui_request_router").init()
local function last_packet(name)
    for index = #packets, 1, -1 do
        if packets[index].name == name then return packets[index] end
    end
    error("missing packet " .. name)
end
local function selected(building, viewer)
    local player = viewer or building.player_id
    listeners.ui_selected_unit_stats_request(nil, {PlayerID = player, entindex = building.entindex})
    local packet = last_packet("ui_selected_unit_stats_snapshot")
    assert_true(packet.player == handles[player] and packet.payload.success == 1,
        "selected snapshot delivered only to the requesting player")
    assert_true(packet.payload.source == "selected_unit_runtime", "production nonhero snapshot path")
    return packet.payload
end
local function select_card(card)
    local ids = card == "recruit_training" and {card, "tower_growth", "gunpowder_splash"}
        or {card, "recruit_training", "gunpowder_splash"}
    local offer = assert(rewards.debug_offer(0, ids))
    assert_true(offer.ok, "actual reward offer succeeds")
    listeners.ui_rogue_reward_select(nil, {PlayerID = 0, token = offer.token, card_id = card})
    local packet = last_packet("ui_rogue_reward_result")
    assert_true(packet.payload.ok and packet.player == handles[0], "formal three-choice selection succeeds")
    return offer
end
local function reconcile(snapshot, total, green, white, fixed_pct, label)
    local details = assert(snapshot.building_stat_details)
    near(snapshot.attack_min, total, label .. " attack minimum")
    near(snapshot.attack_max, total, label .. " attack maximum")
    near(snapshot.stat_tooltips.attack.maximum, total, label .. " attack tooltip total")
    near(details.attack_bonus, green, label .. " green fixed attack")
    near(tonumber(snapshot.attack_max) - details.attack_bonus, white, label .. " white remaining attack")
    near(details.attack_talent_pct, fixed_pct, label .. " fixed talent percentage")
    near(details.attack_pct, fixed_pct, label .. " red fixed percentage")
    near(white + green, total, label .. " white plus green equals actual damage")
end
local before = selected(base)
reconcile(before, 72, 0, 72, 0, "before recruit")
near(tonumber(before.building_stat_details.attack_recruit_training_pct) or 0, 0,
    "unowned recruit tooltip contribution")
reconcile(selected(grown), 4232.6, 0, 4232.6, 0, "before recruit accumulated attack")
local offer = select_card("recruit_training")
assert_true(base.unit:HasModifier("modifier_rogue_base_tower_attack"), "real grant attaches native modifier")
near(base.unit:GetAverageTrueAttackDamage(), 144, "native damage doubled")
local after = selected(base)
reconcile(after, 144, 72, 72, 100, "after recruit")
near(after.building_stat_details.attack_recruit_training_pct, 100, "owned recruit tooltip contribution")
reconcile(selected(grown), 8465.2, 72, 8393.2, 100, "after recruit accumulated attack")
reconcile(selected(tech), 1744, 1672, 72, 100, "technology attack also doubled once")
local foreign_snapshot = selected(foreign, 0)
reconcile(foreign_snapshot, 72, 0, 72, 0, "another owner's tower unchanged")
near(tonumber(foreign_snapshot.building_stat_details.attack_recruit_training_pct) or 0, 0,
    "another owner has no recruit tooltip contribution")
assert_true(reward_snapshots["0"].history[1].card_id == "recruit_training", "formal history records selected card")
near(#runtime.snapshot(0), 1, "single effect instance")
listeners.ui_rogue_reward_select(nil, {PlayerID = 0, token = offer.token, card_id = "recruit_training"})
assert_true(not last_packet("ui_rogue_reward_result").payload.ok, "replayed selection is rejected")
near(base.unit:GetAverageTrueAttackDamage(), 144, "replayed selection cannot multiply again")
base.unit.engine_includes_modifiers = true
reconcile(selected(base), 144, 72, 72, 100, "engine GetDamage already includes talent")
base.unit.FindAllModifiers = false
reconcile(selected(base), 144, 72, 72, 100, "named-modifier compatibility fallback")
-- New buildings and real lifecycle records preserve the LV1-4 restriction.
for level = 1, 5 do
    local building = tower(0, level)
    bus.emit(events.BUILDING_CREATED, building)
    local row = assert(routes.current(building))
    local multiplier = level <= 4 and 2 or 1
    near(building.unit:GetAverageTrueAttackDamage(), row.base_attack_damage * multiplier,
        "new LV" .. level .. " native attack")
    reconcile(selected(building), row.base_attack_damage * multiplier,
        level <= 4 and row.base_attack_damage or 0, row.base_attack_damage,
        level <= 4 and 100 or 0, "new LV" .. level .. " display")
end
local function upgrade(building, level, reason)
    local row = assert(routes.current({level = level}))
    building.level, building.record_id = level, row.record_id
    building.unit.survival_level = level
    building.unit.survival_tower_record_id = row.record_id
    building.unit.survival_tower_stage_id = row.stage_id
    building.unit.survival_attack_min, building.unit.survival_attack_max = row.base_attack_damage, row.base_attack_damage
    building.reason = reason or "tower_upgraded_one"
    bus.emit(events.BUILDING_CHANGED, building)
end
upgrade(base, 4)
reconcile(selected(base), 602, 301, 301, 100, "upgrade keeps LV4 eligibility")
upgrade(base, 5)
assert_true(not base.unit:HasModifier("modifier_rogue_base_tower_attack"), "upgrade past LV4 removes talent")
local ineligible = selected(base)
reconcile(ineligible, 401, 0, 401, 0, "upgrade to LV5 removes display bonus")
near(tonumber(ineligible.building_stat_details.attack_recruit_training_pct) or 0, 0,
    "ineligible LV5 has no recruit tooltip contribution")
-- Native percentage modifiers add together. Display must not repeatedly
-- multiply the recruit percentage into the separate upgrade-growth percentage.
select_card("tower_growth")
upgrade(base, 2)
near(base.unit:GetAverageTrueAttackDamage(), 151 * 2.1, "native recruit plus one growth stack")
local snapshot = selected(base)
near(snapshot.attack_max, 151 * 2.1, "display follows additive percentage modifiers")
near(snapshot.base_damage_outgoing_pct, 110, "recruit and growth native sum")
near(snapshot.building_stat_details.attack_talent_pct, 100, "growth is excluded from fixed talent tooltip")
near(snapshot.building_stat_details.attack_recruit_training_pct, 100,
    "growth leaves separate recruit tooltip contribution unchanged")
upgrade(base, 2, "technology_changed")
near(selected(base).attack_max, 151 * 2.1, "unrelated refresh never adds upgrade growth")
-- PREATTACK bonuses are applied once after BASE percentages, never doubled.
local flat = base.unit:AddNewModifier(base.unit, nil, "modifier_rogue_sharp_volley_growth", {value = 50})
near(flat:GetModifierPreAttack_BonusDamage(), 50, "actual flat native callback")
near(selected(base).attack_max, 151 * 2.1 + 50, "flat attack added after base percentage")
local fresh = tower(0, 1)
bus.emit(events.BUILDING_CREATED, fresh)
fresh.unit:AddNewModifier(fresh.unit, nil, "modifier_rogue_sharp_volley_growth", {value = 50})
near(selected(fresh).attack_max, 194, "72 doubled plus 50 flat gives 194")
local presentation = display.apply(fresh.unit, {attack_max = 194})
near(presentation.building_stat_details.attack_bonus, 72, "building details match routed green bonus")
print("RECRUIT_TRAINING_DISPLAY_PASS: " .. checks .. " checks; formal choice, native damage, selected HUD/tooltip, owners, LV1-5, upgrades, cache/fallback, growth and flat modifiers")
