package.path = "scripts/vscripts/?.lua;" .. package.path

PATTACH_ABSORIGIN_FOLLOW = 1
PATTACH_POINT_FOLLOW = 4
PATTACH_CUSTOMORIGIN = 2
local created, destroyed, released, controls = {}, {}, {}, {}
ParticleManager = {}
function ParticleManager:CreateParticle(path, attach, owner)
    created[#created + 1] = { path = path, attach = attach, owner = owner }
    return #created
end
function ParticleManager:DestroyParticle(index) destroyed[index] = (destroyed[index] or 0) + 1 end
function ParticleManager:ReleaseParticleIndex(index) released[index] = (released[index] or 0) + 1 end
function ParticleManager:SetParticleControlEnt(index, cp, owner, attach, name)
    controls[#controls + 1] = { cp = cp, owner = owner, name = name }
end

local details = require("visual/monster_cosmetic_details")
local unit = { skin = 7, activities = {} }
function unit:GetSkin() return self.skin end
function unit:SetSkin(skin) self.skin = skin end
function unit:AddActivityModifier(name) self.activities[#self.activities + 1] = name end
function unit:ClearActivityModifiers() self.activities = {} end
function unit:GetAbsOrigin() return {} end
local weapon = { GetAbsOrigin = unit.GetAbsOrigin }
local components = { weapon = weapon }
local asset = {
    model_skin = 1,
    activity_modifiers = { { modifier_name = "abysm" } },
    effects = {
        { effect_group_id = "wave_cosmetic_ambient", particle_path = "body.vpcf",
          control_profile = "0=attach_hitloc|1=attach_head" },
        { effect_group_id = "wave_cosmetic_ambient", particle_path = "weapon.vpcf",
          owner_component_id = "weapon", attach_type = "PATTACH_CUSTOMORIGIN" },
        { effect_group_id = "wave_cosmetic_ambient", particle_path = "missing.vpcf",
          owner_component_id = "missing" },
        { effect_group_id = "wave_cosmetic_ambient", particle_path = "disabled.vpcf", enabled = false },
        { effect_group_id = "attack", particle_path = "attack.vpcf" },
    },
}
details.apply(unit, asset, components)
assert(unit.skin == 1 and unit.activities[1] == "abysm")
assert(#created == 2 and created[1].owner == unit and created[2].owner == weapon)
assert(created[2].attach == PATTACH_CUSTOMORIGIN)
assert(#controls == 2 and controls[2].cp == 1 and controls[2].name == "attach_head")
details.apply(unit, asset, components)
assert(#created == 2 and #unit.activities == 1, "repeated apply duplicated visual resources")
details.apply(unit, { model_skin = 0 }, {})
assert(destroyed[1] == 1 and destroyed[2] == 1 and released[1] == 1 and released[2] == 1)
assert(unit.skin == 0 and #unit.activities == 0)
details.clear(unit)
details.clear(unit)
assert(unit.skin == 7 and unit.survival_monster_cosmetic_details == nil)
assert(destroyed[1] == 1 and released[1] == 1, "clear released a particle twice")
print("MONSTER_COSMETIC_DETAILS_PASS")
