package.path = "scripts/vscripts/?.lua;scripts/vscripts/?/init.lua;" .. package.path

class = function(definition) return definition or {} end
MODIFIER_ATTRIBUTE_PERMANENT = 1
MODIFIER_EVENT_ON_ATTACK_LANDED = 2
IsServer = function() return true end

local played = {}
package.loaded["core/sound_service"] = {
    play = function(cue_id, options)
        played[#played + 1] = { cue_id = cue_id, options = options }
        return true
    end,
}

local event_bus = require("core/event_bus")
local events = require("core/events")
event_bus.reset()
local hits = {}
event_bus.subscribe(events.TREE_HIT, function(payload)
    hits[#hits + 1] = payload
end)

package.loaded["modifiers/modifier_lumberjack_ai"] = nil
local lumberjack_ai = require("modifiers/modifier_lumberjack_ai")

local parent = { index = 501 }
function parent:IsNull() return false end
function parent:entindex() return self.index end
function parent:GetTeamNumber() return 2 end

local tree = { index = 701 }
function tree:IsNull() return false end
function tree:entindex() return self.index end

local wrong_tree = { index = 702 }
function wrong_tree:IsNull() return false end
function wrong_tree:entindex() return self.index end

local other_attacker = { index = 502 }
function other_attacker:IsNull() return false end
function other_attacker:entindex() return self.index end

local instance = setmetatable({
    tree_entindex = tree:entindex(),
    player_id = 0,
    base_lumber_efficiency = 1,
    technology_lumber_efficiency = 0,
    technology_crit_chance = 0,
    technology_armor_reduction = 0,
}, { __index = lumberjack_ai })
function instance:GetParent() return parent end

instance:OnAttackLanded({ attacker = other_attacker, target = tree })
instance:OnAttackLanded({ attacker = parent, target = wrong_tree })
assert(#played == 0 and #hits == 0,
    "invalid lumberjack attacks unexpectedly played or granted resources")

instance:OnAttackLanded({ attacker = parent, target = tree })
assert(#played == 1, "valid lumberjack impact did not play exactly once")
assert(played[1].cue_id == "worker_lumberjack_tree_impact",
    "lumberjack impact used the wrong configured cue")
assert(played[1].options.unit == tree and played[1].options.source == tree,
    "lumberjack impact was not attached and limited by the resource tree")
assert(#hits == 1 and hits[1].attacker == parent and hits[1].target == tree,
    "sound integration changed the authoritative TREE_HIT payload")

print("LUMBERJACK_SOUND_PASS")