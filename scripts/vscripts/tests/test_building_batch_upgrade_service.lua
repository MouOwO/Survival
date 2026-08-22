package.path = "scripts/vscripts/?.lua;scripts/vscripts/?/init.lua;" .. package.path

local events = require("core/events")
local entities = {}
local quotes = { one = {}, max = {} }
local attempts = {}
local notifications = {}
local resources = { wood = 0, gold = 0 }

local function ability(name, caster, ready)
    local result = {
        name = name,
        caster = caster,
        ready = ready ~= false,
        cooldown_starts = 0,
        cooldown_ends = 0,
    }
    function result:IsNull() return false end
    function result:GetAbilityName() return self.name end
    function result:GetCaster() return self.caster end
    function result:IsPassive() return false end
    function result:IsHidden() return false end
    function result:IsActivated() return self.ready end
    function result:IsFullyCastable() return self.ready end
    function result:GetCooldown() return 1 end
    function result:GetLevel() return 1 end
    function result:StartCooldown() self.cooldown_starts = self.cooldown_starts + 1 end
    function result:EndCooldown() self.cooldown_ends = self.cooldown_ends + 1 end
    return result
end

local function tower(entindex, owner, tower_class, options)
    options = options or {}
    local result = {
        alive = options.alive ~= false,
        survival_player_id = owner,
        survival_building_id = options.building_id or "arrow_tower",
        survival_tower_class = tower_class,
        abilities = {},
    }
    function result:IsNull() return false end
    function result:IsAlive() return self.alive end
    function result:entindex() return entindex end
    function result:GetPlayerOwnerID() return owner end
    function result:FindAbilityByName(name) return self.abilities[name] end
    if options.q ~= false then
        result.abilities.ability_upgrade_tower_lv01 = ability(
            "ability_upgrade_tower_lv01",
            result,
            options.q_ready
        )
    end
    if options.w ~= false then
        result.abilities.ability_upgrade_tower_max = ability(
            "ability_upgrade_tower_max",
            result,
            options.w_ready
        )
    end
    entities[entindex] = result
    return result
end

EntIndexToHScript = function(entindex) return entities[tonumber(entindex)] end

package.loaded["core/event_bus"] = {
    request = function(event_name, payload)
        assert(event_name == events.BUILDING_UPGRADE_QUOTE_REQUEST,
            "unexpected batch request: " .. tostring(event_name))
        local mode = payload.upgrade_mode
        local quote = quotes[mode] and quotes[mode][payload.building:entindex()]
        return quote or { ok = false, error = "no_quote" }
    end,
    emit = function(event_name, payload)
        if event_name == events.UI_NOTIFICATION then
            notifications[#notifications + 1] = payload
            return
        end
        assert(event_name == events.BUILDING_UPGRADE_REQUEST,
            "unexpected batch event: " .. tostring(event_name))
        local entindex = payload.building:entindex()
        local quote = assert(quotes[payload.upgrade_mode][entindex])
        attempts[#attempts + 1] = {
            entindex = entindex,
            mode = payload.upgrade_mode,
            wood = quote.wood,
            gold = quote.gold,
        }
        if resources.wood < quote.wood or resources.gold < quote.gold then
            payload.result = { ok = false, error = "资源不足" }
            return
        end
        resources.wood = resources.wood - quote.wood
        resources.gold = resources.gold - quote.gold
        payload.result = { ok = true, pending = true }
    end,
}

package.loaded["systems/building_batch_upgrade_service"] = nil
local service = require("systems/building_batch_upgrade_service")

local base = tower(101, 0, nil)
local frost = tower(102, 0, "class_6")
local death = tower(103, 0, "class_1")
local lightning = tower(104, 0, "class_3")
local foreign = tower(105, 1, "class_2")
local ordinary = tower(106, 0, nil, { building_id = "wall" })
local disabled = tower(107, 0, "class_4", { q_ready = false, w_ready = false })
local tied = tower(108, 0, "class_5")
ordinary.abilities.ability_upgrade_wall = ability(
    "ability_upgrade_wall",
    ordinary,
    true
)

quotes.one[101] = { ok = true, wood = 100, gold = 0, target_level = 2 }
quotes.one[102] = { ok = true, wood = 500, gold = 100, target_level = 7 }
quotes.one[103] = { ok = true, wood = 1000, gold = 50, target_level = 7 }
quotes.one[104] = { ok = true, wood = 1000, gold = 20, target_level = 7 }
quotes.one[108] = { ok = true, wood = 1000, gold = 20, target_level = 7 }
quotes.max[101] = { ok = true, wood = 850, gold = 0, target_level = 5 }
quotes.max[102] = { ok = true, wood = 3000, gold = 700, target_level = 10 }
quotes.max[103] = { ok = true, wood = 3000, gold = 900, target_level = 10 }
quotes.max[104] = { ok = true, wood = 5000, gold = 200, target_level = 10 }
quotes.max[108] = { ok = true, wood = 5000, gold = 200, target_level = 10 }
quotes.one[106] = { ok = true, wood = 75, gold = 10, target_level = 2 }

local selected = { 103, 105, 108, 102, 106, 104, 107, 101, 103 }
resources = { wood = 2500, gold = 500 }
local q_result = service.execute({
    player_id = 0,
    primary = death,
    primary_ability = death.abilities.ability_upgrade_tower_lv01,
    ability_name = "ability_upgrade_tower_lv01",
    selected_entindexes = selected,
})
assert(q_result.ok and q_result.success_count == 3 and q_result.skipped_count == 5,
    "mixed-route Q batch did not aggregate successful and skipped towers")
assert(#attempts == 5
    and attempts[1].entindex == 101
    and attempts[2].entindex == 102
    and attempts[3].entindex == 104
    and attempts[4].entindex == 108
    and attempts[5].entindex == 103,
    "Q batch was not sorted by wood, then gold, then entindex")
assert(attempts[1].mode == "one" and attempts[5].mode == "one",
    "Q batch did not preserve single-level mode")
assert(base.abilities.ability_upgrade_tower_lv01.cooldown_starts == 1
    and frost.abilities.ability_upgrade_tower_lv01.cooldown_starts == 1
    and lightning.abilities.ability_upgrade_tower_lv01.cooldown_starts == 1
    and death.abilities.ability_upgrade_tower_lv01.cooldown_starts == 0,
    "Q batch started cooldown for a failed tower or missed a successful tower")
assert(foreign.abilities.ability_upgrade_tower_lv01.cooldown_starts == 0
    and ordinary.abilities.ability_upgrade_tower_lv01.cooldown_starts == 0
    and disabled.abilities.ability_upgrade_tower_lv01.cooldown_starts == 0,
    "Q batch affected an ineligible tower")

attempts = {}
resources = { wood = 6700, gold = 2000 }
local w_result = service.execute({
    player_id = 0,
    primary = frost,
    primary_ability = frost.abilities.ability_upgrade_tower_max,
    ability_name = "ability_upgrade_tower_max",
    selected_entindexes = selected,
})
assert(w_result.ok and w_result.success_count == 2 and w_result.skipped_count == 6,
    "mixed-route W batch did not aggregate successful and skipped towers")
assert(#attempts == 5
    and attempts[1].entindex == 101
    and attempts[2].entindex == 102
    and attempts[3].entindex == 103
    and attempts[4].entindex == 104
    and attempts[5].entindex == 108,
    "W batch was not sorted by cumulative wood, then cumulative gold")
assert(attempts[1].mode == "max" and attempts[5].mode == "max",
    "W batch did not preserve maximum-stage mode")
assert(base.abilities.ability_upgrade_tower_max.cooldown_starts == 1
    and frost.abilities.ability_upgrade_tower_max.cooldown_starts == 1
    and death.abilities.ability_upgrade_tower_max.cooldown_starts == 0
    and lightning.abilities.ability_upgrade_tower_max.cooldown_starts == 0,
    "W batch cooldowns did not match authoritative upgrade results")

local tower_routes = require("config/tower_route_config")
local base_state = { level = 1, tower_class = nil, population_occupied = 0 }
local base_q = assert(tower_routes.cost_to(base_state, 2))
local base_w = assert(tower_routes.cost_to(base_state, 5))
assert(base_q.wood == 100 and base_q.gold == 0,
    "base tower Q cost did not use the next CSV level")
assert(base_w.wood == 850 and base_w.gold == 0,
    "base tower W cost did not accumulate to its stage maximum")
local death_state = { level = 6, tower_class = "class_1", population_occupied = 1 }
local death_q = assert(tower_routes.cost_to(death_state, 7))
local death_w = assert(tower_routes.cost_to(death_state, 10))
assert(death_q.wood == 1500 and death_q.gold == 50,
    "class tower Q cost did not use its own next route row")
assert(death_w.wood == 9000 and death_w.gold == 1750,
    "class tower W cost did not accumulate its own current stage")

assert(#notifications == 2
    and string.find(notifications[1].message, "成功3栋", 1, true)
    and string.find(notifications[2].message, "成功2栋", 1, true),
    "batch upgrade did not publish one aggregate notification per request")

attempts = {}
resources = { wood = 75, gold = 10 }
local wall_result = service.execute({
    player_id = 0,
    primary = ordinary,
    primary_ability = ordinary.abilities.ability_upgrade_wall,
    ability_name = "ability_upgrade_wall",
})
assert(wall_result.ok and wall_result.success_count == 1
    and wall_result.skipped_count == 0 and #attempts == 1
    and attempts[1].entindex == 106 and attempts[1].mode == "one"
    and ordinary.abilities.ability_upgrade_wall.cooldown_starts == 1,
    "ordinary building single-selection upgrade regressed")
local forged_tower_result = service.execute({
    player_id = 0,
    primary = ordinary,
    primary_ability = ordinary.abilities.ability_upgrade_tower_lv01,
    ability_name = "ability_upgrade_tower_lv01",
})
assert(not forged_tower_result.ok and forged_tower_result.success_count == nil,
    "non-tower primary was accepted by the tower batch path")

print("BUILDING_BATCH_UPGRADE_LUA51_PASS")