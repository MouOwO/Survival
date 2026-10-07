-- Real roguelike grants/config, technology totals, combat calculation and native
-- modifier callbacks. Only the engine boundary and unrelated bootstrap are mocked.
package.path = "scripts/vscripts/?.lua;" .. package.path
for _, name in ipairs({"systems/effect_handler_registry", "systems/equipment_effect_service",
    "systems/equipment_stat_aggregation_service", "systems/triggered_proc_service"}) do
    package.loaded[name] = {init = function() end}
end
package.loaded["systems/player_context_service"] = {
    is_defeated = function() return false end,
    is_owned_by = function(id, u) return u.survival_player_id == id end,
}
package.loaded["config/global_rules"] = {number = function(_, fallback) return fallback end,
    hero_strength_health_per_point = 0, hero_intellect_attack_per_point = 0}
package.loaded["systems/hero_stat_adapter"] = {
    configured_max_health = function(d) return d.base_health end,
    apply_configured_health = function(u) return u.maximum, 0, u.maximum end,
    reapply_projectile_stats = function() end,
}
local server = true
function IsServer() return server end
function class(base) base.__index = base; return base end
MODIFIER_PROPERTY_BASE_ATTACK_TIME_CONSTANT = 1
MODIFIER_PROPERTY_ATTACKSPEED_BONUS_CONSTANT = 2
MODIFIER_PROPERTY_PREATTACK_BONUS_DAMAGE = 3
MODIFIER_PROPERTY_DAMAGEOUTGOING_PERCENTAGE = 4
MODIFIER_EVENT_ON_ATTACK_RECORD = 5
MODIFIER_EVENT_ON_TAKEDAMAGE = 6
local now = 0
GameRules = {GetGameTime = function() return now end}
PlayerResource = {GetPlayer = function() return {} end, GetTeam = function() return 2 end}
local original_print = print
print = function(message)
    if tostring(message):find("handler error") or tostring(message):find("task failed") then error(message) end
end
local bus, events = require("core/event_bus"), require("core/events")
local scheduler = require("core/scheduler")
local technology = require("systems/technology_stat_manager")
local rogue = require("systems/rogue_effect_runtime_service")
require("modifiers/modifier_weapon_stat_projection")
local projection = modifier_weapon_stat_projection
local declares_speed = false
for _, property in ipairs(projection:DeclareFunctions()) do
    if property == MODIFIER_PROPERTY_ATTACKSPEED_BONUS_CONSTANT then declares_speed = true end
end
assert(declares_speed, "the engine must invoke the declared attack-speed callback")
require("modifiers/modifier_equipment_effects")
require("modifiers/modifier_rogue_combat_effects")
local heroes = require("config/generated/hero_definitions")
local equipment, permanent, active = {}, {}, {}
local function near(a, b, label)
    assert(type(a) == "number" and math.abs(a-b) < 1e-7,
        (label or "number") .. ": " .. tostring(a) .. " != " .. tostring(b))
end
local function stats(id)
    local result = assert(bus.request(events.HERO_COMBAT_STATS_GET_REQUEST, {player_id = id}))
    assert(result.ok, result.error); return result.snapshot
end
local function unit(id, hero_id)
    local d = assert(heroes.by_id[hero_id])
    local u = {id = id, survival_player_id = id, modifiers = {}, health = 200,
        maximum = d.base_health, bat = 1 / d.attack_speed, refreshes = 0, level = 1}
    function u:IsNull() return false end
    function u:IsAlive() return true end
    function u:IsRealHero() return true end
    function u:entindex() return self.id + 100 end
    function u:GetPlayerOwnerID() return self.id end
    function u:GetHealth() return self.health end
    function u:SetHealth(n) self.health = n end
    function u:GetMaxHealth() return self.maximum end
    function u:GetLevel() return self.level end
    function u:GetBaseAttackTime() return self.bat end
    function u:SetBaseAttackTime(n) self.bat = n end
    function u:FindModifierByName(name) return self.modifiers[name] end
    function u:AddNewModifier(_, _, name, params)
        local m = self.modifiers[name]
        if m then if m.OnRefresh then m:OnRefresh(params) end; return m end
        m = setmetatable({}, {__index = _G[name] or {}})
        function m:GetParent() return u end
        function m:SetHasCustomTransmitterData() end
        function m:SendBuffRefreshToClients() self.transmitted = self:AddCustomTransmitterData() end
        function m:StartIntervalThink() end
        function m:ForceRefresh() u.refreshes = u.refreshes + 1; if self.OnRefresh then self:OnRefresh() end end
        self.modifiers[name] = m
        if m.OnCreated then m:OnCreated(params or {}) end
        return m
    end
    function u:CalculateStatBonus() end
    function u:GetAttackSpeed()
        local hero, gear = self.modifiers.modifier_weapon_stat_projection, self.modifiers.modifier_equipment_effects
        return 1 + ((hero and hero.GetModifierAttackSpeedBonus_Constant
            and hero:GetModifierAttackSpeedBonus_Constant() or 0)
            + (gear and gear:GetModifierAttackSpeedBonus_Constant() or 0)) / 100
    end
    function u:attack_rate()
        local m = self.modifiers.modifier_weapon_stat_projection
        return self:GetAttackSpeed() / (m and m:GetModifierBaseAttackTimeConstant() or self.bat)
    end
    return u
end
package.loaded["core/modifier_registry"] = {ensure = function(u, name, params)
    return u:FindModifierByName(name) or u:AddNewModifier(u, nil, name, params)
end}
technology.init()
require("systems/hero_combat_stat_service").init()
rogue.init()
bus.handle_request(events.EQUIPMENT_STATS_GET_REQUEST, function(p)
    return {ok = true, snapshot = {values = equipment[p.player_id] or {}}}
end)
bus.handle_request(events.PERMANENT_REWARD_EFFECTS_GET_REQUEST, function(p)
    return {totals = permanent[p.player_id] or {}}
end)
bus.handle_request(events.HERO_SUMMON_GET_REQUEST, function(p) return {unit = active[p.player_id]} end)
local function summon(id, hero_id)
    local u = unit(id, hero_id); active[id] = u
    bus.emit(events.HERO_SUMMONED, {player_id = id, unit = u, hero_id = hero_id})
    return u
end
local function grant(id, card, kind)
    local result = rogue.grant(id, card, "test:" .. id .. ":" .. card, kind or "builder_start")
    assert(result.ok, result.error); return result
end
local function synchronized(u, expected)
    near(stats(u.id).attack_speed, expected, "panel attack rate")
    near(u:attack_rate(), expected, "native modifier attack rate")
    near(u.survival_attack_speed, expected, "entity cached rate")
    local source = u.modifiers.modifier_weapon_stat_projection
    local client = setmetatable({}, {__index = projection})
    client:HandleCustomTransmitterData(source:AddCustomTransmitterData())
    server = false
    near(client:GetModifierBaseAttackTimeConstant(), source.server_snapshot.base_attack_time, "client BAT")
    near(client:GetModifierAttackSpeedBonus_Constant(), source.server_snapshot.hero_attack_speed_bonus_pct,
        "client attack speed")
    server = true
end
local base = 1 / 0.7
-- The exact report: pick before any hero exists, then summon at ~3.6 attacks/s.
grant(0, "wind_strategy")
near(technology.get(0).final.hero.attack_speed_bonus_pct, 400)
local first = summon(0, "hero_shadow_fiend")
synchronized(first, 5 / (base - 0.03))
-- Late selection, every configured hero, and untouched neighboring players.
for index, hero in ipairs({"hero_drow_ranger", "hero_monkey_king", "hero_blademaster", "hero_doom", "hero_axe"}) do
    local id = index <= 3 and index or index + 2
    local u = summon(id, hero); synchronized(u, 0.7)
    grant(id, "wind_strategy"); synchronized(u, 5 / (base - 0.03))
end
local before = first.refreshes
grant(0, "wind_strategy") -- Retry of the same grant must not double bonuses.
assert(first.refreshes == before)
grant(0, "allround_tempering")
synchronized(first, 6 / (base - 0.03))
near(stats(0).strength, heroes.by_id.hero_shadow_fiend.base_strength + 3)
near(stats(0).agility, heroes.by_id.hero_shadow_fiend.base_agility + 3)
near(stats(0).intellect, heroes.by_id.hero_shadow_fiend.base_intellect + 3)
equipment[0] = {attack_speed_pct = 100}
bus.emit(events.EQUIPMENT_STATS_CHANGED, {player_id = 0})
synchronized(first, 7 / (base - 0.03)) -- Additive 500 + 100, not multiplicative.
permanent[0] = {hero_attack_speed_bonus_pct = 25, hero_attack_interval_reduction = 0.02}
bus.emit(events.PERMANENT_REWARD_EFFECTS_CHANGED, {player_id = 0})
synchronized(first, 7.25 / (base - 0.05))
bus.emit(events.HERO_REMOVED, {player_id = 0, unit = first})
local replacement = summon(0, "hero_blademaster")
synchronized(replacement, 7.25 / (base - 0.05))
replacement.level = 2; synchronized(replacement, 7.25 / (base - 0.05))
local unchanged = replacement.refreshes
for _ = 1, 100 do bus.emit(events.TECHNOLOGY_STATS_CHANGED, {player_id = 0}) end
assert(replacement.refreshes == unchanged, "unchanged totals cannot refresh native modifiers every frame")
grant(8, "allround_tempering")
local tempered = summon(8, "hero_axe")
synchronized(tempered, 1.4)
near(stats(8).strength, heroes.by_id.hero_axe.base_strength + 3, "attributes granted before summon")
-- Other hero effects retain early/late summon bindings and phase changes.
grant(4, "high_morale", "boss"); grant(4, "bloodthirst_potion", "boss")
local later = summon(4, "hero_drow_ranger")
assert(later:FindModifierByName("modifier_rogue_combat_bonus"))
near(later.modifiers.modifier_rogue_combat_bonus:GetModifierBaseDamageOutgoing_Percentage(), 30)
now = 61; scheduler.think()
near(require("systems/rogue_effect_state_service").numeric(4, "hero_lifesteal_pct"), 20)
local later_replacement = summon(4, "hero_monkey_king")
assert(later_replacement:FindModifierByName("modifier_rogue_combat_bonus"))
near(later_replacement.modifiers.modifier_rogue_combat_bonus:GetModifierBaseDamageOutgoing_Percentage(), 30)
-- Hero-linked tower bonuses must read actual snapshot fields, including growth.
grant(5, "in_step", "boss")
local tower = unit(5, "hero_shadow_fiend"); tower.survival_building_id = "arrow_tower"
bus.emit(events.BUILDING_CREATED, {player_id = 5, unit = tower, building_id = "arrow_tower"})
local tower_bonus = assert(tower.modifiers.modifier_rogue_combat_bonus)
near(tower_bonus:GetModifierPreAttack_BonusDamage(), 0, "no hero projection before summon")
local linked = summon(5, "hero_shadow_fiend")
local linked_stats = stats(5)
near(tower_bonus:GetModifierPreAttack_BonusDamage(),
    (linked_stats.attack_min + linked_stats.attack_max) * 0.05, "linked hero attack")
local initial_bonus = tower_bonus:GetModifierPreAttack_BonusDamage()
permanent[5] = {hero_attack_flat = 20}
bus.emit(events.PERMANENT_REWARD_EFFECTS_CHANGED, {player_id = 5})
near(tower_bonus:GetModifierPreAttack_BonusDamage(), initial_bonus + 2, "live hero growth projection")
local attack_time_writes, original_attack_time = 0, linked.SetBaseAttackTime
linked.SetBaseAttackTime = function(self, value)
    attack_time_writes = attack_time_writes + 1
    original_attack_time(self, value)
end
for i=1,200 do
    bus.emit(events.PERMANENT_REWARD_EFFECTS_CHANGED,
        {player_id=5,changed_section="tower",reason="gameplay_stats_tower_attack_growth"})
end
assert(attack_time_writes == 0, "tower growth never rewrites the hero attack timer")
print = original_print
print("HERO_ROGUE_PROJECTION_PASS early/late summon; 6 heroes; additive equipment/permanent; client callbacks; replacement; idempotence; stable refresh; morale/lifesteal lifecycle; linked tower growth")
