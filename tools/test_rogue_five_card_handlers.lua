package.path = "scripts/vscripts/?.lua;scripts/vscripts/?/init.lua;" .. package.path

DOTA_TEAM_GOODGUYS = 2
PlayerResource = { GetTeam = function() return DOTA_TEAM_GOODGUYS end }

local buildings = {}
local workers = {}
local random_request = nil
local last_upgrade_request = nil
local quoted_units = {}
local next_unit_entindex = 0
local builder = { accept_item = true, added_item = nil }
function builder:IsNull() return false end
function builder:AddItem(item)
    if not self.accept_item then return nil end
    self.added_item = item
    return item
end
local removed_item = nil
CreateItem = function(name, owner, purchaser)
    return { name = name, owner = owner, purchaser = purchaser }
end
UTIL_Remove = function(item) removed_item = item end
RandomInt = function() return 1 end
local event_bus = {
    request = function(name, payload)
        if name == "builder.get.request" then return { builder = builder } end
        if name == "building.list.request" then return buildings end
        if name == "building.upgrade_quote.request" then
            quoted_units[payload.building] = true
            return payload.building.quote_ok == true
                and not payload.building.quote_busy
                and { ok = true }
                or { ok = false, error = payload.building.quote_error or "not_upgradeable" }
        end
        if name == "building.upgrade.free.request" then
            last_upgrade_request = payload
            return { ok = true }
        end
        if name == "worker.list.request" then return workers end
        if name == "wave.state.get.request" then
            return {
                next_wave_number = 1,
                next_special_wave_number = 5,
                next_special_role = "assault_boss",
            }
        end
        if name == "rogue_reward.grant_random.request" then
            random_request = payload
            return { ok = true }
        end
        return { ok = true }
    end,
}
package.preload["core/event_bus"] = function() return event_bus end

local function unit(maximum, current)
    local result = { modifiers = {}, maximum = maximum or 100, current = current or maximum or 100 }
    next_unit_entindex = next_unit_entindex + 1
    result._entindex = next_unit_entindex
    function result:IsNull() return false end
    function result:entindex() return self._entindex end
    function result:IsAlive() return true end
    function result:HasModifier(name) return self.modifiers[name] ~= nil end
    function result:AddNewModifier(_, _, name, params)
        local entry = self.modifiers[name] or { count = 0 }
        entry.count = entry.count + 1
        entry.value = tonumber(params.value)
        entry.stacks = tonumber(params.stacks)
        self.modifiers[name] = entry
    end
    function result:RemoveModifierByName(name) self.modifiers[name] = nil end
    function result:GetMaxHealth() return self.maximum end
    function result:GetHealth() return self.current end
    function result:SetBaseMaxHealth(value) self.maximum = value end
    function result:SetMaxHealth(value) self.maximum = value end
    function result:SetHealth(value) self.current = value end
    return result
end

local registry = require("systems/rogue_effect_registry")

local construction_order = registry.get("grant_building_upgrade_action")
assert(construction_order and construction_order.apply({ player_id = 0, params = {} }),
    "construction order item grant failed")
assert(builder.added_item and builder.added_item.name
    == "item_survival_rogue_construction_order",
    "construction order granted the wrong item")
builder.accept_item = false
local granted, grant_error = construction_order.apply({ player_id = 0, params = {} })
assert(granted == false and grant_error == "builder_inventory_full"
    and removed_item and removed_item.name == "item_survival_rogue_construction_order",
    "construction order did not fail closed when builder inventory was full")
builder.accept_item = true

local weakening = registry.get("next_boss_attack_pct")
local weakening_instance = { player_id = 0, params = { value = -50 } }
assert(weakening.apply(weakening_instance), "weakening orb did not skip normal-only waves")
assert(weakening_instance.target_wave_number == 5,
    "weakening orb did not lock the first later special wave")
assert(weakening.on_event(weakening_instance, {
    monster_source = "challenge", wave_number = 5, member_role = "assault_boss", unit = unit(),
}) == false, "challenge monster consumed weakening orb")
assert(weakening.on_event(weakening_instance, {
    monster_source = "wave", wave_number = 4, member_role = "assault_boss", unit = unit(),
}) == false, "wrong wave consumed weakening orb")
local boss = unit()
assert(weakening.on_event(weakening_instance, {
    monster_source = "wave", wave_number = 5, member_role = "wave_leader", unit = unit(),
}) == false, "elite consumed weakening orb in a boss wave")
assert(weakening.on_event(weakening_instance, {
    monster_source = "wave", wave_number = 5, member_role = "assault_boss", unit = boss,
}) == true, "locked boss did not consume weakening orb")
assert(boss.modifiers.modifier_rogue_weakening_attack.value == -50,
    "weakening orb modifier value invalid")
local original_request = event_bus.request
event_bus.request = function(name, payload)
    if name == "wave.state.get.request" then
        return { next_special_wave_number = 8, next_special_role = "wave_leader" }
    end
    return original_request(name, payload)
end
local elite_instance = { player_id = 0, params = { value = -50 } }
assert(weakening.apply(elite_instance), "weakening orb did not lock elite fallback wave")
local leader = unit()
assert(weakening.on_event(elite_instance, {
    monster_source = "wave", wave_number = 8, member_role = "wave_leader", unit = leader,
}) == true and leader.modifiers.modifier_rogue_weakening_attack.value == -50,
    "wave leader fallback did not receive weakening orb")
event_bus.request = original_request
event_bus.request = function(name, payload)
    if name == "wave.state.get.request" then return { next_wave_number = nil } end
    return original_request(name, payload)
end
local empty_instance = { player_id = 0, params = { value = -50 } }
assert(weakening.apply(empty_instance) and empty_instance.complete_on_apply == true,
    "weakening orb did not become an empty completed effect without later special waves")
event_bus.request = original_request

local divine = registry.get("grant_random_cards")
assert(divine.apply({
    player_id = 0, card_id = "divine_wish", grant_id = "parent:1", params = { count = 3 },
}), "divine wish request failed")
assert(random_request.parent_card_id == "divine_wish"
    and random_request.parent_grant_id == "parent:1" and random_request.count == 3,
    "divine wish request contract invalid")

local growth = registry.get("tower_upgrade_attack_bonus_pct")
local tower = unit()
local growth_instance = { player_id = 0, params = { value = 10 } }
growth.recompute(growth_instance, {
    building_id = "arrow_tower", reason = "technology_stats_changed", unit = tower,
})
assert(tower.modifiers.modifier_rogue_tower_growth == nil,
    "technology refresh incorrectly counted as tower upgrade")
growth.recompute(growth_instance, {
    building_id = "arrow_tower", reason = "tower_upgraded_one", unit = tower,
})
growth.recompute(growth_instance, {
    building_id = "arrow_tower", reason = "tower_upgraded_max", unit = tower,
})
assert(tower.modifiers.modifier_rogue_tower_growth.count == 2,
    "successful tower upgrades did not accumulate two projections")

local wall = unit(1000, 250)
buildings = {{ building_id = "wall", unit = wall }}
local feast = registry.get("wall_health_multiplier")
local effect_state = require("systems/rogue_effect_state_service")
effect_state.reset()
assert(feast.apply({ player_id = 0, params = { multiplier = 2 } }), "feast failed")
assert(wall.maximum == 2000 and wall.current == 500,
    "feast did not double wall health while preserving percentage")
assert(effect_state.wall_health_flat(0) == 1000,
    "feast did not record its fixed health increase")
local upgraded_normal_max = 1500 + effect_state.wall_health_flat(0)
assert(upgraded_normal_max == 2500,
    "feast fixed health increase was not additive after wall upgrade")
assert(effect_state.wall_health_flat(0) == 1000,
    "reading feast state changed the fixed health increase")

local infrastructure = registry.get("random_building_upgrade_count")
local infrastructure_wall = unit()
local infrastructure_base_tower = unit()
local infrastructure_routed_tower = unit()
local infrastructure_full_wall = unit()
local infrastructure_base_waiting_route = unit()
local infrastructure_full_tower = unit()
local infrastructure_construction = unit()
local infrastructure_busy = unit()
infrastructure_wall.quote_ok = true -- wall level 8 (3-2) has a level 9 quote
infrastructure_base_tower.quote_ok = true -- base tower level 4
infrastructure_routed_tower.quote_ok = true -- completed route, not at route max
infrastructure_full_wall.quote_ok = false -- wall level 30
infrastructure_base_waiting_route.quote_ok = false -- base tower level 5
infrastructure_full_tower.quote_ok = false
infrastructure_construction.quote_ok = true
infrastructure_construction.modifiers.modifier_building_under_construction = true
infrastructure_busy.quote_ok = true
infrastructure_busy.survival_upgrade_in_progress = true
buildings = {
    { entindex = infrastructure_wall:entindex(), building_id = "wall", unit = infrastructure_wall },
    { entindex = infrastructure_base_tower:entindex(), building_id = "arrow_tower", unit = infrastructure_base_tower },
    { entindex = infrastructure_routed_tower:entindex(), building_id = "arrow_tower", unit = infrastructure_routed_tower },
    { entindex = infrastructure_full_wall:entindex(), building_id = "wall", unit = infrastructure_full_wall },
    { entindex = infrastructure_base_waiting_route:entindex(), building_id = "arrow_tower", unit = infrastructure_base_waiting_route },
    { entindex = infrastructure_full_tower:entindex(), building_id = "arrow_tower", unit = infrastructure_full_tower },
    { entindex = infrastructure_construction:entindex(), building_id = "wall", unit = infrastructure_construction },
    { entindex = infrastructure_busy:entindex(), building_id = "wall", unit = infrastructure_busy },
}
local infrastructure_instance = { player_id = 0, params = { count = 3 } }
assert(infrastructure.apply(infrastructure_instance), "infrastructure maniac apply failed")
assert(last_upgrade_request.building == infrastructure_wall,
    "upgradeable wall was not selected")
assert(quoted_units[infrastructure_wall]
    and quoted_units[infrastructure_base_tower]
    and quoted_units[infrastructure_routed_tower],
    "upgradeable wall or tower did not receive an authoritative quote")
assert(not quoted_units[infrastructure_construction]
    and not quoted_units[infrastructure_busy],
    "construction or active upgrade entered the quote candidate pool")
local remaining_after_apply = infrastructure_instance.upgrade_remaining
infrastructure.recompute(infrastructure_instance, {
    player_id = 0, entindex = infrastructure_base_tower:entindex(), reason = "wall_upgraded",
})
assert(infrastructure_instance.upgrade_remaining == remaining_after_apply,
    "unrelated building upgrade advanced infrastructure maniac")
infrastructure_wall.quote_ok = false
infrastructure.recompute(infrastructure_instance, {
    player_id = 0, entindex = infrastructure_wall:entindex(), reason = "wall_upgraded",
})
assert(last_upgrade_request.building == infrastructure_base_tower,
    "upgradeable base tower was not selected")
infrastructure_base_tower.quote_ok = false
infrastructure.recompute(infrastructure_instance, {
    player_id = 0, entindex = infrastructure_base_tower:entindex(), reason = "tower_upgraded_one",
})
assert(last_upgrade_request.building == infrastructure_routed_tower,
    "upgradeable routed tower was not selected")
assert(infrastructure_full_wall.quote_ok == false
    and infrastructure_base_waiting_route.quote_ok == false
    and infrastructure_full_tower.quote_ok == false,
    "full or route-pending buildings were not represented as ineligible")

local lumberjack = unit()
local repairer = unit()
workers = {
    { player_id = 0, worker_type = "lumberjack", unit = lumberjack },
    { player_id = 0, worker_type = "repairer", unit = repairer },
}
local promise = registry.get("lumberjack_attack_speed_bonus_pct")
local promise_instance = { player_id = 0, params = { value = 100 } }
assert(promise.apply(promise_instance), "boss promise apply failed")
assert(lumberjack.modifiers.modifier_rogue_lumberjack_attack_speed.value == 100,
    "existing lumberjack did not receive boss promise")
assert(repairer.modifiers.modifier_rogue_lumberjack_attack_speed == nil,
    "repairer incorrectly received boss promise")
local new_lumberjack = unit()
promise.recompute(promise_instance, {
    player_id = 0, worker_type = "lumberjack", unit = new_lumberjack,
})
assert(new_lumberjack.modifiers.modifier_rogue_lumberjack_attack_speed.value == 100,
    "new lumberjack did not receive boss promise")
promise.remove(promise_instance)
assert(lumberjack.modifiers.modifier_rogue_lumberjack_attack_speed == nil,
    "boss promise did not clean existing lumberjack at expiry")

local cards = require("config/generated/rogue_reward_cards").by_id
for _, card_id in ipairs({
    "weakening_orb", "divine_wish", "tower_growth", "feast", "boss_promise",
}) do assert(cards[card_id].enabled == true, card_id .. " card is not enabled") end

print("ROGUE_FIVE_CARD_HANDLERS_LUA51_PASS")