package.path = "scripts/vscripts/?.lua;scripts/vscripts/?/init.lua;" .. package.path

local events = require("core/events")
local entities = {}
local requests = {}
local notifications = {}
local technology_levels = {
    gold_mine_efficiency = 0,
    gold_mine_crit = 0,
}
local technology_purchases = 0
local technology_failure_group = nil

local function ability(name, caster, ready)
    local result = {
        name = name,
        caster = caster,
        ready = ready ~= false,
        cooldown_starts = 0,
    }
    function result:IsNull() return false end
    function result:GetAbilityName() return self.name end
    function result:GetCaster() return self.caster end
    function result:IsPassive() return false end
    function result:IsHidden() return not self.ready end
    function result:IsActivated() return self.ready end
    function result:IsFullyCastable() return self.ready end
    function result:GetCooldown() return 1 end
    function result:GetLevel() return 1 end
    function result:StartCooldown() self.cooldown_starts = self.cooldown_starts + 1 end
    return result
end

local function mine(entindex, owner, options)
    options = options or {}
    local result = {
        alive = options.alive ~= false,
        survival_player_id = owner,
        survival_building_id = options.building_id or "gold_mine",
        survival_upgrade_in_progress = options.upgrading == true,
        auto_enabled = options.auto == true,
        level = options.level or 1,
        abilities = {},
    }
    function result:IsNull() return false end
    function result:IsAlive() return self.alive end
    function result:entindex() return entindex end
    function result:GetPlayerOwnerID() return owner end
    function result:FindAbilityByName(name) return self.abilities[name] end

    local names = {
        "ability_upgrade_gold_mine",
        "ability_upgrade_gold_mine_efficiency",
        "ability_upgrade_gold_mine_crit",
        "ability_gold_mine_auto_upgrade",
        "ability_gold_mine_stop_auto_upgrade",
    }
    for _, name in ipairs(names) do
        local ready = options[name] ~= false
        result.abilities[name] = ability(name, result, ready)
    end
    entities[entindex] = result
    return result
end

EntIndexToHScript = function(entindex) return entities[tonumber(entindex)] end

package.loaded["core/event_bus"] = {
    request = function(event_name, payload)
        requests[#requests + 1] = { name = event_name, payload = payload }
        if event_name == events.GOLD_MINE_LEVEL_UPGRADE_QUOTE_REQUEST then
            local level = payload.entindex == 101 and 1
                or payload.entindex == 102 and 2 or 3
            return {
                ok = payload.entindex ~= 106,
                wood = level * 100,
                gold = level == 3 and 50 or 0,
                error = payload.entindex == 106 and "金矿正在升级中" or nil,
            }
        end
        if event_name == events.GOLD_MINE_LEVEL_UPGRADE_REQUEST then
            if payload.entindex == 102 then
                return { ok = false, error = "资源不足" }
            end
            return { ok = true, pending = true }
        end
        if event_name == events.TECHNOLOGY_PURCHASE_NEXT_REQUEST then
            assert(payload.silent_notification == true,
                "gold mine batch technology purchase was not silent")
            if technology_failure_group == payload.technology_group then
                return { ok = false, error = "资源不足" }
            end
            technology_purchases = technology_purchases + 1
            technology_levels[payload.technology_group] =
                technology_levels[payload.technology_group] + 1
            return { ok = true, level = technology_levels[payload.technology_group] }
        end
        if event_name == events.GOLD_MINE_AUTO_STATE_REQUEST then
            local unit = entities[payload.entindex]
            return {
                ok = true,
                enabled = unit.auto_enabled == true,
            }
        end
        if event_name == events.GOLD_MINE_AUTO_UPGRADE_REQUEST then
            local unit = entities[payload.entindex]
            unit.auto_enabled = payload.enabled == true
            return { ok = true, changed = true, enabled = unit.auto_enabled }
        end
        error("unexpected gold mine batch request: " .. tostring(event_name))
    end,
    emit = function(event_name, payload)
        if event_name == events.UI_NOTIFICATION then
            notifications[#notifications + 1] = payload
            return
        end
        error("unexpected gold mine batch event: " .. tostring(event_name))
    end,
}

package.loaded["systems/gold_mine_batch_upgrade_service"] = nil
local service = require("systems/gold_mine_batch_upgrade_service")

local mine_a = mine(101, 0)
local mine_b = mine(102, 0)
local mine_c = mine(103, 0, { auto = true })
local upgrading = mine(106, 0, { upgrading = true })
local foreign = mine(107, 1)
local wall = mine(108, 0, { building_id = "wall" })
local disabled = mine(109, 0, { ability_upgrade_gold_mine = false })
entities[110] = { IsNull = function() return false end }

local forged = service.execute({
    player_id = 0,
    primary = disabled,
    primary_ability = disabled.abilities.ability_upgrade_gold_mine,
    ability_name = "ability_upgrade_gold_mine",
})
assert(not forged.ok and forged.error == "金矿批量请求技能无效",
    "gold mine batch accepted a hidden or uncastable primary ability")

local selected = { 107, 106, 103, 102, 101, 108, 110, 103 }
local q = service.execute({
    player_id = 0,
    primary = mine_b,
    primary_ability = mine_b.abilities.ability_upgrade_gold_mine,
    ability_name = "ability_upgrade_gold_mine",
    selected_entindexes = selected,
})
assert(q.ok and q.success_count == 2 and q.skipped_count == 5,
    "gold mine Q did not skip invalid, upgrading, and unaffordable mines")
local q_attempts = {}
for _, request in ipairs(requests) do
    if request.name == events.GOLD_MINE_LEVEL_UPGRADE_REQUEST then
        q_attempts[#q_attempts + 1] = request.payload.entindex
    end
end
assert(#q_attempts == 3 and q_attempts[1] == 101
    and q_attempts[2] == 102 and q_attempts[3] == 103,
    "gold mine Q did not sort or continue after an intermediate failure")
assert(mine_a.abilities.ability_upgrade_gold_mine.cooldown_starts == 1
    and mine_c.abilities.ability_upgrade_gold_mine.cooldown_starts == 1
    and mine_b.abilities.ability_upgrade_gold_mine.cooldown_starts == 0,
    "gold mine Q cooldowns did not follow accepted upgrades")

requests = {}
local w = service.execute({
    player_id = 0,
    primary = mine_a,
    primary_ability = mine_a.abilities.ability_upgrade_gold_mine_efficiency,
    ability_name = "ability_upgrade_gold_mine_efficiency",
    selected_entindexes = { 101, 102, 103 },
})
assert(w.ok and w.success_count == 3 and technology_purchases == 1
    and technology_levels.gold_mine_efficiency == 1,
    "gold mine W batch purchased more than one shared technology level")
assert(mine_a.abilities.ability_upgrade_gold_mine_efficiency.cooldown_starts == 1
    and mine_b.abilities.ability_upgrade_gold_mine_efficiency.cooldown_starts == 1
    and mine_c.abilities.ability_upgrade_gold_mine_efficiency.cooldown_starts == 1,
    "gold mine W did not synchronize cooldowns")

local e = service.execute({
    player_id = 0,
    primary = mine_a,
    primary_ability = mine_a.abilities.ability_upgrade_gold_mine_crit,
    ability_name = "ability_upgrade_gold_mine_crit",
    selected_entindexes = { 101, 102, 103 },
})
assert(e.ok and e.success_count == 3 and technology_purchases == 2
    and technology_levels.gold_mine_crit == 1,
    "gold mine E did not purchase exactly one shared technology level")
local e_cooldowns = mine_a.abilities.ability_upgrade_gold_mine_crit.cooldown_starts
    + mine_b.abilities.ability_upgrade_gold_mine_crit.cooldown_starts
    + mine_c.abilities.ability_upgrade_gold_mine_crit.cooldown_starts
technology_failure_group = "gold_mine_crit"
local failed_e = service.execute({
    player_id = 0,
    primary = mine_a,
    primary_ability = mine_a.abilities.ability_upgrade_gold_mine_crit,
    ability_name = "ability_upgrade_gold_mine_crit",
    selected_entindexes = { 101, 102, 103 },
})
assert(not failed_e.ok and technology_purchases == 2,
    "failed gold mine technology purchase changed the shared level")
assert(e_cooldowns == mine_a.abilities.ability_upgrade_gold_mine_crit.cooldown_starts
        + mine_b.abilities.ability_upgrade_gold_mine_crit.cooldown_starts
        + mine_c.abilities.ability_upgrade_gold_mine_crit.cooldown_starts,
    "failed gold mine technology purchase started cooldowns")
technology_failure_group = nil

local auto = service.execute({
    player_id = 0,
    primary = mine_a,
    primary_ability = mine_a.abilities.ability_gold_mine_auto_upgrade,
    ability_name = "ability_gold_mine_auto_upgrade",
    selected_entindexes = { 101, 102, 103, 107, 108 },
})
assert(auto.ok and auto.success_count == 2 and auto.unchanged_count == 1
    and auto.skipped_count == 2,
    "gold mine auto-start did not use explicit idempotent target state")
assert(mine_a.auto_enabled and mine_b.auto_enabled and mine_c.auto_enabled,
    "gold mine auto-start did not enable eligible mines")

mine_c.auto_enabled = false
local stop = service.execute({
    player_id = 0,
    primary = mine_a,
    primary_ability = mine_a.abilities.ability_gold_mine_stop_auto_upgrade,
    ability_name = "ability_gold_mine_stop_auto_upgrade",
    selected_entindexes = { 101, 102, 103 },
})
assert(stop.ok and stop.success_count == 2 and stop.unchanged_count == 1,
    "gold mine auto-stop did not idempotently preserve an already stopped mine")
assert(not mine_a.auto_enabled and not mine_b.auto_enabled and not mine_c.auto_enabled,
    "gold mine auto-stop left a selected mine enabled")

print("GOLD_MINE_BATCH_UPGRADE_LUA51_PASS")
