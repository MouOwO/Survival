package.path = "scripts/vscripts/?.lua;scripts/vscripts/?/init.lua;" .. package.path

local event_bus = require("core/event_bus")
local events = require("core/events")
event_bus.reset()

class = function(definition)
    definition.__index = definition
    return definition
end

local summon_result
event_bus.handle_request(events.BUILDING_CHALLENGE_SUMMON_REQUEST, function()
    return summon_result
end)

package.loaded["abilities/building_challenge_ability_factory"] = nil
local Ability = require("abilities/building_challenge_ability_factory").create(
    "challenge_monster_01"
)
local caster = { entindex = function() return 101 end }
local ability = setmetatable({ cooldown_ended = 0 }, { __index = Ability })
function ability:GetCaster() return caster end
function ability:EndCooldown()
    self.cooldown_ended = self.cooldown_ended + 1
end

summon_result = { ok = false, error = "challenge_monster_already_alive" }
ability:OnSpellStart()
assert(ability.cooldown_ended == 1,
    "ordinary rejected summon did not refund cooldown")

summon_result = {
    ok = false,
    error = "challenge_failed_wall_health",
    cast_consumed = true,
}
ability:OnSpellStart()
assert(ability.cooldown_ended == 1,
    "consumed immediate failure incorrectly refunded cooldown")

summon_result = { ok = true }
ability:OnSpellStart()
assert(ability.cooldown_ended == 1,
    "successful summon incorrectly refunded cooldown")

print("BUILDING_CHALLENGE_ABILITY_FACTORY_LUA51_PASS")