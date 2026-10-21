package.path = "scripts/vscripts/?.lua;" .. package.path
require("tests/development_release_profile")
-- Real reward selection -> lifecycle targeting -> native modifier -> selected
-- HUD and tooltip. Only Dota engine entities and event transport are simulated.
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
local now, serial, checks, special_wave, special_role = 100, 0, 0, 6, "assault_boss"
GameRules = {GetGameTime = function() return now end}
RandomFloat = function() return 0 end
RandomInt = function() return 1 end
local listeners, packets, reward_snapshots, entities = {}, {}, {}, {}
CustomGameEventManager = {
    RegisterListener = function(_, name, handler) listeners[name] = handler end,
    Send_ServerToPlayer = function(_, player, name, payload)
        packets[#packets + 1] = {player = player, name = name, payload = payload}
    end,
}
CustomNetTables = {SetTableValue = function(_, name, key, value)
    if name == "survival_rogue_reward" then reward_snapshots[key] = value end
end}
EntIndexToHScript = function(index) return entities[index] end
Entities = {FindAllByClassname = function()
    local result = {}; for _, unit in pairs(entities) do result[#result + 1] = unit end
    return result
end}
local bus, events = require("core/event_bus"), require("core/events")
local scheduler = require("core/scheduler")
require("modifiers/modifier_rogue_reward_effects")
local rewards = require("systems/rogue_reward_service")
local runtime = require("systems/rogue_effect_runtime_service")
local function near(actual, expected, label)
    checks = checks + 1
    actual = tonumber(actual)
    assert(actual and math.abs(actual - expected) < 1e-6,
        label .. ": " .. tostring(actual) .. " != " .. tostring(expected))
end
local function check(value, label) checks = checks + 1; assert(value, label) end
local function creature(minimum, maximum)
    serial = serial + 1
    local unit = {index = serial, native_min = minimum or 100,
        native_max = maximum or minimum or 100, modifiers = {},
        survival_is_wave_monster = true, survival_player_id = -1}
    function unit:IsNull() return false end
    function unit:IsAlive() return true end
    function unit:IsRealHero() return false end
    function unit:entindex() return self.index end
    function unit:GetPlayerOwnerID() return -1 end
    function unit:GetTeamNumber() return DOTA_TEAM_BADGUYS end
    function unit:GetUnitName() return "npc_dota_survival_wave_creature" end
    function unit:GetBaseDamageMin() return self.native_min end
    function unit:GetBaseDamageMax() return self.native_max end
    function unit:FindModifierByName(name) return self.modifiers[name] end
    function unit:FindAllModifiersByName(name)
        return self.modifiers[name] and {self.modifiers[name]} or {}
    end
    function unit:FindAllModifiers()
        local result = {}; for _, modifier in pairs(self.modifiers) do result[#result + 1] = modifier end
        if self.repeat_modifier then result[#result + 1] = self.repeat_modifier end
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
    function unit:resolved(endpoint)
        local pct, flat = 0, 0
        for _, modifier in pairs(self.modifiers) do
            if modifier.GetModifierBaseDamageOutgoing_Percentage then
                pct = pct + modifier:GetModifierBaseDamageOutgoing_Percentage()
            end
            if modifier.GetModifierPreAttack_BonusDamage then
                flat = flat + modifier:GetModifierPreAttack_BonusDamage()
            end
        end
        return endpoint * math.max(0, 1 + pct / 100) + flat
    end
    -- Both engine getter behaviors must produce the same logical HUD value.
    function unit:GetDamageMin()
        return self.engine_includes_modifiers and self:resolved(self.native_min) or self.native_min
    end
    function unit:GetDamageMax()
        return self.engine_includes_modifiers and self:resolved(self.native_max) or self.native_max
    end
    entities[serial] = unit
    return unit
end
bus.reset()
bus.handle_request(events.BUILDING_LIST_REQUEST, function() return {buildings = {}} end)
bus.handle_request(events.HERO_COMBAT_STATS_GET_REQUEST, function() return {ok = false} end)
bus.handle_request(events.WAVE_STATE_GET_REQUEST, function()
    return {next_special_wave_number = special_wave, next_special_role = special_role}
end)
rewards.init()
require("ui/ui_request_router").init()
local function last_packet(name)
    for index = #packets, 1, -1 do if packets[index].name == name then return packets[index] end end
    error("missing packet " .. name)
end
local function selected(unit, viewer)
    viewer = viewer or 0
    listeners.ui_selected_unit_stats_request(nil, {PlayerID = viewer, entindex = unit.index})
    local packet = last_packet("ui_selected_unit_stats_snapshot")
    check(packet.player == handles[viewer] and packet.payload.success == 1,
        "selected snapshot delivered to requesting player")
    check(packet.payload.source == "selected_unit_runtime", "production creature selected HUD path")
    return packet.payload
end
local function damage(snapshot, minimum, maximum, label)
    near(snapshot.attack_min, minimum, label .. " HUD minimum")
    near(snapshot.attack_max, maximum, label .. " HUD maximum")
    near(snapshot.stat_tooltips.attack.minimum, minimum, label .. " tooltip minimum")
    near(snapshot.stat_tooltips.attack.maximum, maximum, label .. " tooltip maximum")
end
local function select_card(player)
    local offer = rewards.debug_offer(player, {"weakening_orb", "tower_growth", "gunpowder_splash"})
    check(offer and offer.ok, "actual reward offer succeeds")
    listeners.ui_rogue_reward_select(nil, {PlayerID = player, token = offer.token, card_id = "weakening_orb"})
    local packet = last_packet("ui_rogue_reward_result")
    check(packet.payload.ok and packet.player == handles[player], "formal three-choice selection succeeds")
    check(reward_snapshots[tostring(player)].history[1].card_id == "weakening_orb", "formal history records card")
    return offer
end
local function spawn(unit, player, wave, role, source)
    bus.emit(events.MONSTER_SPAWNED, {unit = unit, player_id = player, wave_number = wave,
        member_role = role, monster_source = source or "wave"})
end
local boss = creature()
damage(selected(boss), 100, 100, "before grant")
local offer = select_card(0)
damage(selected(boss), 100, 100, "grant does not weaken existing units")
spawn(boss, 0, 6, "normal")
spawn(boss, 0, 6, "wave_leader")
check(not boss:HasModifier("modifier_rogue_weakening_attack"), "wave leader cannot consume a locked assault boss target")
spawn(boss, 1, 6, "assault_boss")
spawn(boss, 0, 5, "assault_boss")
spawn(boss, 0, 6, "assault_boss", "challenge")
check(not boss:HasModifier("modifier_rogue_weakening_attack"), "only matching owner, wave and special role consume")
check(runtime.snapshot(0)[1].status == "active", "nonmatching spawn leaves effect pending")
selected(boss, 1)
local before_spawn_packets = #packets
spawn(boss, 0, 6, "assault_boss")
check(boss:HasModifier("modifier_rogue_weakening_attack"), "formal lifecycle attaches native weakening")
near(boss:resolved(100), 50, "native hit is halved")
damage(selected(boss), 50, 50, "selected HUD includes independent native weakening")
near(last_packet("ui_selected_unit_stats_snapshot").payload.base_damage_outgoing_pct, -50,
    "HUD carries actual native percentage")
now = now + 0.11; scheduler.think()
local pushed = {}
for index = before_spawn_packets + 1, #packets do
    local packet = packets[index]
    if packet.name == "ui_selected_unit_stats_snapshot" and packet.payload.reason == "rogue_weakening_orb" then
        pushed[packet.player.id] = packet.payload
    end
end
check(pushed[0] and pushed[1], "native change automatically pushes both viewers of the same selected monster")
damage(pushed[0], 50, 50, "owner viewer realtime push")
damage(pushed[1], 50, 50, "other viewer realtime push")
check(runtime.snapshot(0)[1].status == "completed", "matching spawn consumes card")
spawn(boss, 0, 6, "assault_boss")
damage(selected(boss), 50, 50, "repeat event never weakens twice")
local second = creature()
spawn(second, 0, 6, "assault_boss")
damage(selected(second), 100, 100, "consumed card leaves second boss unchanged")
listeners.ui_rogue_reward_select(nil, {PlayerID = 0, token = offer.token, card_id = "weakening_orb"})
check(not last_packet("ui_rogue_reward_result").payload.ok, "replayed card selection rejected")
damage(selected(boss), 50, 50, "replay leaves original modifier unchanged")
boss.engine_includes_modifiers = true
damage(selected(boss), 50, 50, "GetDamage already includes weakening once")
boss.native_max = 200
damage(selected(boss), 50, 100, "native range retains both endpoints")
local all_modifiers, all_named = boss.FindAllModifiers, boss.FindAllModifiersByName
boss.FindAllModifiers = false
damage(selected(boss), 50, 100, "named-modifier lookup fallback")
boss.FindAllModifiersByName = false
damage(selected(boss), 50, 100, "single named-modifier lookup fallback")
-- Endless scaling is restored after the native debuff, exactly once.
boss.survival_endless_attack_scale = 10000
damage(selected(boss), 500000, 1000000, "endless native-to-logical restore")
-- Independent BASE percentages add; PREATTACK flat damage is added after
-- that sum, and the native component is scaled alongside the base damage.
boss:AddNewModifier(boss, nil, "modifier_rogue_tower_attack_projection", {value = 20})
local flat = boss:AddNewModifier(boss, nil, "modifier_rogue_sharp_volley_growth", {value = 100000})
near(flat:GetModifierPreAttack_BonusDamage(), 10, "logical PRE bonus projects to native component")
damage(selected(boss), 800000, 1500000, "BASE -50 plus 20 percent, then PRE +10")
boss.FindAllModifiers, boss.FindAllModifiersByName = all_modifiers, all_named
boss.repeat_modifier = boss.modifiers.modifier_rogue_weakening_attack
damage(selected(boss), 800000, 1500000, "duplicate modifier handle is counted once")
local clean = creature(100, 200)
damage(selected(clean), 100, 200, "unmodified native range")
local challenge = creature(100, 200)
challenge.survival_is_wave_monster, challenge.survival_is_challenge_monster = false, true
challenge.engine_includes_modifiers = true
challenge:AddNewModifier(challenge, nil, "modifier_rogue_weakening_attack", {value = -50})
damage(selected(challenge), 50, 100, "challenge creature uses the same native projection")
-- A separate owner receives the next-wave first-elite fallback, without
-- refreshing or reusing the already-consumed first player's transaction.
special_wave, special_role = 7, "wave_leader"
select_card(1)
local elite = creature(100, 200)
spawn(elite, 1, 7, "normal")
spawn(elite, 1, 7, "assault_boss")
check(not elite:HasModifier("modifier_rogue_weakening_attack"), "elite fallback keeps expected role")
spawn(elite, 1, 7, "wave_leader")
damage(selected(elite, 1), 50, 100, "first elite fallback is halved")
local next_elite = creature()
spawn(next_elite, 1, 7, "wave_leader")
damage(selected(next_elite, 1), 100, 100, "only first matching elite consumes")
print("WEAKENING_ORB_DISPLAY_PASS: " .. checks .. " checks; formal choice, matching lifecycle, native damage, HUD/tooltip, getter/fallback compatibility and endless projection")
