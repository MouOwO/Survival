package.path = "scripts/vscripts/?.lua;" .. package.path
class = function(base) base.__index = base; return base end
local server = true
IsServer = function() return server end
MODIFIER_STATE_ROOTED = 1
MODIFIER_STATE_INVISIBLE = 2
MODIFIER_STATE_STUNNED = 3
MODIFIER_STATE_DISARMED = 4
MODIFIER_STATE_SILENCED = 5
PATTACH_ABSORIGIN_FOLLOW = 6

local parent = {
    survival_movement_type = "flying",
    IsNull = function() return false end,
    GetAbsOrigin = function() return { x = 10, y = 20, z = 200 } end,
}
local created, bound, owned = 0, 0, 0
ParticleManager = {
    CreateParticle = function(_, path, attachment, target)
        assert(path == "particles/units/heroes/hero_siren/siren_net.vpcf")
        assert(attachment == PATTACH_ABSORIGIN_FOLLOW and target == parent)
        created = created + 1
        return 123
    end,
    SetParticleControlEnt = function(_, id, cp, target, attachment, _, position)
        assert(id == 123 and cp == 0 and target == parent)
        assert(attachment == PATTACH_ABSORIGIN_FOLLOW and position.z == 200)
        bound = bound + 1
    end,
}
local net = require("modifiers/modifier_tower_drag_net")
local modifier = setmetatable({
    GetParent = function() return parent end,
    AddParticle = function(_, id, modifier_effect, status_effect, priority, hero_effect, overhead)
        assert(id == 123 and not modifier_effect and not status_effect)
        assert(priority == -1 and not hero_effect and not overhead)
        owned = owned + 1 -- Engine cleans it on expiry, purge, and death.
    end,
}, net)
local states = modifier:CheckState()
assert(states[MODIFIER_STATE_ROOTED] == true)
assert(states[MODIFIER_STATE_INVISIBLE] == false)
assert(states[MODIFIER_STATE_STUNNED] == nil)
assert(states[MODIFIER_STATE_DISARMED] == nil)
assert(states[MODIFIER_STATE_SILENCED] == nil)
assert(modifier:IsDebuff() and modifier:IsPurgable() and not modifier:IsHidden())
assert(modifier:GetTexture() == "naga_siren_ensnare")
modifier:OnCreated()
assert(created == 1 and bound == 1 and owned == 1)
if modifier.OnRefresh then modifier:OnRefresh() end
assert(created == 1 and owned == 1, "refresh must reuse the net")
local anti_air = require("systems/anti_air_rules")
assert(anti_air.is_flying(parent), "ensnare must preserve anti-air targeting")
server = false
modifier:OnCreated()
assert(created == 1, "only the server creates the net")
print("TOWER_DRAG_NET_PASS root, flight, model binding, refresh, engine-owned cleanup")
