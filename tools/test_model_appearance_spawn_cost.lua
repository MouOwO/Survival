-- Run from the addon root with Lua 5.1. Optional baseline module path measures
-- the same 90-unit spawn fixture before applying the regression assertions.
package.path = "scripts/vscripts/?.lua;" .. package.path
package.loaded["core/logger"] = {info=function() end, warn=function() end}
local tasks, entities, scans, visits, spawns = {}, {}, 0, 0, 0
local bulk_queries, iterator_queries = 0, 0
package.loaded["core/scheduler"] = {
    after=function(_, callback, id) tasks[id]=callback end,
    cancel=function(id) tasks[id]=nil end,
}
IsValidEntity = function(entity) return not entity.removed end
UTIL_Remove = function(entity) entity.removed=true end
local function entity(class, index, model)
    local value = {class=class, index=index, model=model}
    function value:IsNull() return self.removed == true end
    function value:entindex() return self.index end
    function value:GetOwner() return self.owner end
    function value:SetOwner(owner) self.owner=owner end
    function value:SetParent(parent) self.parent=parent end
    function value:FollowEntity(parent, merge) assert(parent==self.parent and merge) end
    function value:SetModel(path) self.model=path end
    function value:SetOriginalModel() end
    function value:GetModelName() return self.model end
    function value:SetSolid() end
    function value:SetSkin() end
    function value:SetModelScale() end
    entities[#entities+1]=value
    return value
end
Entities = {
    FindAllByClassname=function(_, class)
        scans=scans+1
        bulk_queries=bulk_queries+1
        local result={}
        for _, value in ipairs(entities) do
            if value.class==class and not value.removed then
                result[#result+1]=value;visits=visits+1
            end
        end
        return result
    end,
    FindByClassname=function(_, previous, class)
        scans=scans+1
        iterator_queries=iterator_queries+1
        local past=previous==nil
        for _, value in ipairs(entities) do
            if past and value.class==class and not value.removed then visits=visits+1;return value end
            if value==previous then past=true end
        end
    end,
}
SpawnEntityFromTableSynchronous = function(class, data)
    spawns=spawns+1
    return entity(class, 1000+spawns, data.model)
end
local asset={asset_id="test_bundle", components={
    {component_id="head",model_path="head.vmdl",attach_mode="bone_merge"},
    {component_id="back",model_path="back.vmdl",attach_mode="bone_merge"},
}}
local module = arg[1] and assert(loadfile(arg[1]))() or require("visual/model_appearance_service")
local units, parts = {}, {}
for index=1,90 do
    local unit=entity("npc_dota_creature", index, "body.vmdl")
    units[index]=unit
    local ok,_, components=module.Apply(unit,asset,{fresh_unit=true})
    assert(ok)
    parts[index]=components
end
print(string.format("APPEARANCE_SPAWN_COST units=90 props=%d world_queries=%d bulk_queries=%d iterator_queries=%d entity_visits=%d",spawns,scans,bulk_queries,iterator_queries,visits))
if arg[1] then return end
assert(scans==0 and visits==0 and spawns==180,"fresh units must not scan the world")
for _, callback in pairs(tasks) do callback() end
for index=1,90 do
    local ok,_, components=module.Apply(units[index],asset)
    assert(ok and components==parts[index],"stable reapply must retain component identity")
end
assert(scans==0 and spawns==180,"verification and stable reapply must not scan or allocate")
-- Failed swaps keep the original complete outfit, successful swaps remove it.
local original_spawn=SpawnEntityFromTableSynchronous
SpawnEntityFromTableSynchronous=function() return nil end
local replacement={asset_id="replacement",components=asset.components}
assert(not module.Apply(units[1],replacement))
assert(not parts[1].head.removed and module.Matches(units[1],asset))
SpawnEntityFromTableSynchronous=original_spawn
assert(module.Apply(units[1],replacement))
assert(parts[1].head.removed and parts[1].back.removed and scans==0)
-- An old delayed verification must not recreate an outfit after cleanup.
local delayed=tasks.appearance_verify_1
assert(module.Clear(units[1]))
local before=spawns;delayed()
assert(spawns==before and scans==0)
-- Cold reload discovers existing components, removes duplicates and legacy
-- carriers, but keeps the original prop identity instead of respawning it.
local duplicate=entity("prop_dynamic", 9000, "head.vmdl")
for key,value in pairs(parts[2].head) do if type(value)~="function" then duplicate[key]=value end end
duplicate.index=9000
local legacy=entity("npc_dota_creature",9001)
legacy.survival_is_native_wearable_visual=true;legacy.owner=units[2]
local legacy_piece=entity("dota_item_wearable",9002)
legacy_piece.survival_is_native_wearable=true;legacy_piece.owner=legacy
package.loaded["visual/model_appearance_service"]=nil
module=require("visual/model_appearance_service")
-- Even if a caller repeats a fresh hint, the existing asset marker must keep
-- cold recovery active instead of duplicating the original outfit.
local ok,_, recovered=module.Apply(units[2],asset,{fresh_unit=true})
assert(ok and recovered.head==parts[2].head and recovered.back==parts[2].back)
assert(duplicate.removed and legacy.removed and legacy_piece.removed and spawns==before)
assert(scans==4,"cold discovery uses each class API once without a second iterator pass")
local queries=scans
assert(module.Apply(units[2],asset) and scans==queries)
-- Cold replacement cannot retain pieces from the previous asset, and it must
-- not remove a different unit's components while filtering the world.
package.loaded["visual/model_appearance_service"]=nil
module=require("visual/model_appearance_service")
assert(module.Apply(units[4],replacement))
assert(parts[4].head.removed and parts[4].back.removed)
assert(not recovered.head.removed and not recovered.back.removed)
assert(scans==queries+5,"cold replacement retains the bounded legacy discovery path")
-- Clear can be the first call after a hot reload (death/map cleanup). There
-- is no Apply to rebuild the registry first; owned orphan props still go away.
package.loaded["visual/model_appearance_service"]=nil
module=require("visual/model_appearance_service")
queries=scans
assert(module.Clear(units[5]))
assert(parts[5].head.removed and parts[5].back.removed and scans==queries,
    "a captured outfit survives module reload and retires without cold scanning")
assert(not parts[6].head.removed and not recovered.head.removed)
assert(module.Apply(units[2],asset))
-- A reused engine index cannot remove the previous owner's components.
local reused=entity("npc_dota_creature",2,"body.vmdl")
assert(module.Apply(reused,asset,{fresh_unit=true}))
assert(not recovered.head.removed and not recovered.back.removed)
assert(module.Clear(units[2]),"old owner must retire its own captured outfit")
assert(recovered.head.removed and recovered.back.removed)
assert(module.Matches(reused,asset),"old owner cleanup must preserve the new owner's state")
assert(module.Clear(reused))
-- A fresh module without FindAllByClassname retains the older engine fallback.
Entities.FindAllByClassname=nil
package.loaded["visual/model_appearance_service"]=nil
module=require("visual/model_appearance_service")
assert(module.Apply(units[3],asset))
assert(module.Clear(units[3]) and parts[3].head.removed and parts[3].back.removed)
print("APPEARANCE_SPAWN_LIFECYCLE_PASS stable allocation, rollback, cleanup, cold recovery, index reuse, fallback")
