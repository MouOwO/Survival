package.path = "scripts/vscripts/?.lua;scripts/vscripts/?/init.lua;" .. package.path

DOTA_TEAM_GOODGUYS = 2
PlayerResource = { GetTeam = function() return DOTA_TEAM_GOODGUYS end }

local requests = {}
local buildings = {}
local entities = {}
local event_bus = {
    request = function(name, payload)
        requests[#requests + 1] = { name = name, payload = payload }
        if name == "building.list.request" then return buildings end
        if name == "worker.train.request" then
            return { ok = true, count = payload.count }
        end
        return { ok = true }
    end,
}
package.preload["core/event_bus"] = function() return event_bus end

Entities = { FindAllByClassname = function() return entities end }

local function unit(fields)
    fields = fields or {}
    fields.modifiers = {}
    function fields:IsNull() return false end
    function fields:AddNewModifier(_, _, name, params)
        self.modifiers[name] = tonumber(params.value)
    end
    function fields:HasModifier(name) return self.modifiers[name] ~= nil end
    function fields:RemoveModifierByName(name) self.modifiers[name] = nil end
    return fields
end

local wave = unit({ survival_is_wave_monster = true })
local challenge = unit({ survival_is_challenge_monster = true })
local training = unit({})
entities = { wave, challenge, training }

local lv4 = unit({ survival_tower_record_id = "arrow_tower_lv04" })
local lv5 = unit({ survival_tower_record_id = "arrow_tower_lv05" })
local city = unit({})
buildings = {
    { building_id = "arrow_tower", record_id = "arrow_tower_lv04", unit = lv4 },
    { building_id = "arrow_tower", record_id = "arrow_tower_lv05", unit = lv5 },
    { building_id = "main_city", unit = city },
}

local registry = require("systems/rogue_effect_registry")
local frozen = registry.get("wall_attacker_attack_speed_pct")
local frozen_instance = { player_id = 0, card_id = "frozen_wall", params = { value = -15 } }
assert(frozen.apply(frozen_instance), "frozen wall apply failed")
assert(wave.modifiers.modifier_rogue_enemy_attack_speed == -15,
    "wave monster was not slowed")
assert(challenge.modifiers.modifier_rogue_enemy_attack_speed == -15,
    "building challenge monster was not slowed")
assert(training.modifiers.modifier_rogue_enemy_attack_speed == nil,
    "unrelated training monster was slowed")

local recruit = registry.get("base_tower_attack_bonus_pct")
local recruit_instance = {
    player_id = 0,
    card_id = "recruit_training",
    params = {
        value = 100,
        target_record_ids = table.concat({
            "arrow_tower_lv01", "arrow_tower_lv02",
            "arrow_tower_lv03", "arrow_tower_lv04",
        }, "|"),
    },
}
assert(recruit.apply(recruit_instance), "recruit training apply failed")
assert(lv4.modifiers.modifier_rogue_base_tower_attack == 100,
    "LV4 base tower did not receive attack modifier")
assert(lv5.modifiers.modifier_rogue_base_tower_attack == nil,
    "LV5 base tower incorrectly received attack modifier")
recruit.recompute(recruit_instance, {
    building_id = "arrow_tower",
    record_id = "arrow_tower_lv05",
    unit = lv4,
})
assert(lv4.modifiers.modifier_rogue_base_tower_attack == nil,
    "tower modifier was not removed after leaving eligible records")

local ion = registry.get("wall_hit_damage_cap_pct")
assert(ion.apply({ player_id = 0, params = { value = 20 } }), "ion shield apply failed")
local effect_state = require("systems/rogue_effect_state_service")
assert(effect_state.wall_damage_cap({ survival_player_id = 0 }) == 20,
    "ion shield cap was not registered")

local internship = registry.get("training_capacity_flat")
local request_count_before_internship = #requests
assert(internship.apply({
    player_id = 0,
    card_id = "internship_certificate",
    params = {
        value = 2,
        training_id = "train_repairer_01",
        wood_cost_override = 0,
        gold_cost_override = 0,
    },
}), "internship certificate apply failed")
assert(#requests == request_count_before_internship,
    "internship certificate unexpectedly created repairers")
assert(effect_state.numeric(0, "repairer_training_capacity_flat:train_repairer_01") == 2,
    "internship certificate did not increase primary repairer capacity")
assert(effect_state.numeric(0, "repairer_training_capacity_flat:train_repairer_02") == 0,
    "internship certificate incorrectly increased advanced repairer capacity")

local cards = require("config/generated/rogue_reward_cards").by_id
local effects = require("config/generated/rogue_reward_effects").by_id
for _, card_id in ipairs({
    "frozen_wall", "recruit_training", "ion_shield", "internship_certificate",
}) do
    assert(cards[card_id].enabled == true, card_id .. " card is not enabled")
end
assert(effects.frozen_wall_slow.enabled == true
    and effects.recruit_training_attack.enabled == true
    and effects.ion_shield_cap.enabled == true
    and effects.internship_capacity.enabled == true,
    "one or more four-card effects are not enabled")

print("ROGUE_FOUR_CARD_HANDLERS_LUA51_PASS")