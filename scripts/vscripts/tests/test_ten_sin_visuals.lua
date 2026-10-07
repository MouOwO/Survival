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
    return entity(data.model)
end
UTIL_Remove=function(e) e.removed=true end
local expected={5,6,9,2,4,7,6,4,5,4}
for i=1,10 do
    local definition=assert(archetypes.by_id[string.format("ten_sin_%02d",i)])
    local asset=assert(catalog.resolve(definition.default_wearable_asset_id))
    assert(asset.primary_model==definition.model_path)
    assert(#asset.components==expected[i], "incomplete ten-sin outfit "..i)
    local unit=entity(asset.primary_model)
    assert(visual.apply(unit,definition,{challenge=true,allow_outside_formal_wave=true,model_path=definition.model_path}))
    assert(appearance._count_for_test(unit)==expected[i])
    if i==6 then assert(unit.skin==1 and unit.activities.arcana and unit.activities.arcana_back) end
    if i==9 then assert(unit.activities.arcana) end
    assert(visual.clear(unit))
    assert(appearance._count_for_test(unit)==0)
end
-- A body can be shared by another outfit. Challenge preload must resolve the
-- explicitly declared bundle rather than the inverse body lookup.
local original=catalog.for_model
catalog.for_model=function() error("ambiguous inverse body lookup") end
local preload=require("systems/challenge_asset_preload_service")
local seen={}
for _, asset_id in ipairs(preload.asset_ids_for_test()) do seen[asset_id]=true end
for i=1,10 do
    local definition=archetypes.by_id[string.format("ten_sin_%02d",i)]
    assert(seen[definition.default_wearable_asset_id], "outfit missing from preload")
end
catalog.for_model=original
for _, callback in ipairs(pending) do callback() end
print("TEN_SIN_VISUALS_PASS: ten complete outfits, 52 attached parts, Arcana state, cleanup, exact-bundle preload")
