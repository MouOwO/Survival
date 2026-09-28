package.path = "scripts/vscripts/?.lua;" .. package.path
local pending = {}
package.loaded["core/logger"] = {info=function() end, warn=function() end}
package.loaded["core/scheduler"] = {after=function(_, callback) pending[#pending+1]=callback end}
local catalog = require("config/asset_catalog")
local archetypes = require("config/generated/monster_archetypes")
local visual = require("systems/monster_hero_visual_service")
local appearance = require("visual/model_appearance_service")
local id = 0
local function entity(model)
    id=id+1
    local e={index=id,model=model,skin=0,activities={}}
    function e:IsNull() return self.removed == true end
    function e:entindex() return self.index end
    function e:GetUnitName() return "test_ten_sin" end
    function e:SetModel(value) self.model=value end
    e.SetOriginalModel=e.SetModel
    function e:GetModelName() return self.model end
    function e:SetOwner(value) self.owner=value end
    function e:GetOwner() return self.owner end
    function e:SetParent(value) self.parent=value end
    function e:FollowEntity(value, merge) assert(merge);self.follow=value end
    function e:SetSkin(value) self.skin=value end
    function e:GetSkin() return self.skin end
    function e:SetModelScale(value) self.scale=value end
    function e:AddActivityModifier(value) self.activities[value]=true end
    function e:ClearActivityModifiers() self.activities={} end
    function e:ResetSequence(value) self.sequence=value end
    function e:SetSolid() end
    function e:SetPlaybackRate() end
    return e
end
SpawnEntityFromTableSynchronous=function(class, data)
    assert(class == "prop_dynamic")
    assert(data.DefaultAnim == nil, "bone-merged pieces must not start a missing idle sequence")
    return entity(data.model)
end
UTIL_Remove=function(e) e.removed=true end

package.loaded["systems/asset_preload_service"]={is_ready=function() return true end}
ParticleManager={
    CreateParticle=function() return 1 end,
    DestroyParticle=function() end,
    ReleaseParticleIndex=function() end,
    SetParticleControlEnt=function() end,
}
local challenge=require("systems/challenge_monster_visual_service")
local definition=assert(archetypes.by_id.challenge_10_terrorblade_fractal)
local asset=assert(catalog.resolve(definition.model_asset_id))
local pieces={head="horns_arcana",back="wings",weapon="weapon",armor="armor"}
assert(#asset.components==4, "seven sins is missing default armor, wings or weapons")
for _, component in ipairs(asset.components) do
    assert(component.model_path=="models/heroes/terrorblade/"..assert(pieces[component.component_id])..".vmdl")
end
local unit=entity(definition.model_path)
function unit:GetAbsOrigin() return {} end
assert(challenge.apply(unit,definition))
assert(unit.model==asset.primary_model and unit.scale==1.15)
assert(unit.activities.abysm, "Arcana activity must remain active")
assert(appearance._count_for_test(unit)==4)
assert(unit.survival_model_asset_id==asset.asset_id)
local get_portrait=require("ui/portrait_metadata").apply
local snapshot=get_portrait(unit,{})
assert(snapshot.model_asset_id==asset.asset_id)
assert(snapshot.portrait_unit_name=="npc_dota_hero_terrorblade")
assert(snapshot.portrait_item_def=="", "portrait uses the complete native hero")
assert(challenge.clear(unit))
assert(appearance._count_for_test(unit)==0)
print("SEVEN_SINS_VISUAL_PASS: four world pieces, inherited pose, Arcana activity, portrait identity, cleanup")

for _, name in ipairs({"ten_sin_07","ten_sin_09","ten_sin_10"}) do
    local row=assert(archetypes.by_id[name])
    local boss=entity(row.model_path)
    assert(visual.apply(boss,row))
    assert(boss.sequence==nil, "hero body must use its activity graph: "..name)
    visual.clear(boss)
end
LinkLuaModifier=function() end
class=function(value) return value end
for i,key in ipairs({"INVULNERABLE","STUNNED","DISARMED","SILENCED","MUTED","ROOTED","COMMAND_RESTRICTED"}) do
    _G["MODIFIER_STATE_"..key]=i
end
local states=require("modifiers/modifier_challenge_11_staging"):CheckState()
assert(states[MODIFIER_STATE_STUNNED]~=true)
assert(states[MODIFIER_STATE_INVULNERABLE] and states[MODIFIER_STATE_ROOTED] and states[MODIFIER_STATE_COMMAND_RESTRICTED])
assert(states[MODIFIER_STATE_DISARMED] and states[MODIFIER_STATE_SILENCED] and states[MODIFIER_STATE_MUTED])
print("TEN_SINS_IDLE_PASS: WK/QOP/Mars activity graph, inherited wearables, staging remains invulnerable and restricted")
