package.path="scripts/vscripts/?.lua;"..package.path
local clock, created, moved, removed = 0,0,0,0
GameRules={GetGameTime=function() return clock end}
DOTA_UNIT_CAP_MOVE_FLY=2
Vector=function(x,y,z) return {x=x,y=y,z=z} end
package.loaded["config/grid_placement_config"]={cell_size=64,build_ground_height=384}
package.loaded["config/buildings_config"]={wall={levels={{model_name="wall.vmdl",model_scale=2}}}}
package.loaded["systems/building_visual_service"]={resolve=function(data) return data.model_name end}
package.loaded["systems/unit_health_bar_service"]={exclude=function(u) u.hidden_health=true end}
local unit
CreateUnitByName=function(name,position,clear)
    assert(name=="npc_survival_grid_preview_proxy" and clear==false)
    created=created+1
    unit={}
    function unit:IsNull() return self.removed end
    function unit:SetMoveCapability(cap) self.movement=cap end
    function unit:SetHullRadius(r) self.hull=r end
    function unit:AddNewModifier(_,_,name) self.modifier=name end
    function unit:SetOriginalModel(path) self.original=path end
    function unit:SetModel(path) self.model=path end
    function unit:SetModelScale(scale) self.scale=scale end
    function unit:SetAngles() end
    function unit:SetSkin(skin) self.skin=skin end
    function unit:SetRenderAlpha(a) self.alpha=a end
    function unit:SetAbsOrigin(p) self.position=p; moved=moved+1 end
    return unit
end
UTIL_Remove=function(u) u.removed=true;removed=removed+1 end
local caster={IsNull=function() return false end,IsAlive=function() return true end,
    GetTeamNumber=function() return 2 end}
local profile={building_id="wall",grid_footprint_x=4,grid_footprint_y=4}
local model=require("systems/grid_preview_model_service")
local scheduler=require("core/scheduler")
model.update(0,caster,profile,Vector(10,10,-512))
assert(created==1 and moved==1 and unit.position.x==0 and unit.position.y==0 and unit.position.z==384)
assert(unit.hull==0 and unit.hidden_health and unit.survival_is_grid_preview and unit.movement==DOTA_UNIT_CAP_MOVE_FLY)
assert(unit.model=="wall.vmdl" and unit.scale==2 and unit.alpha==125)
assert(unit.modifier=="modifier_grid_building_preview")
for i=1,20 do model.update(0,caster,profile,Vector(i,i,-512)) end
assert(created==1 and moved==1,"same grid cell never recreates or moves a model")
model.update(0,caster,profile,Vector(2200,1400,-512))
assert(created==1 and moved==2 and unit.position.x==2176 and unit.position.y==1408)
clock=1.9;model.update(0,caster,profile,Vector(2200,1400,-512));scheduler.think()
assert(removed==0,"heartbeat retains stationary preview")
clock=5;scheduler.think()
assert(removed==1,"abandoned preview expires")
model.update(0,caster,profile,Vector(0,0,384));model.clear(0);model.clear(0)
assert(created==2 and removed==2 and scheduler.task_count()==0,"cancel is idempotent and releases its timer")
print("GRID_PREVIEW_MODEL_PASS reuse, snap, fixed-plane height, no collision, expiry, cleanup")

caster.GetModelName=function() return "existing_sr_tower.vmdl" end
caster.GetModelScale=function() return 1.7 end
caster.GetSkin=function() return 2 end
caster.GetAngles=function() return {y=90} end
profile.placement_action="relocate"
model.update(0,caster,profile,Vector(192,256,384))
assert(unit.model=="existing_sr_tower.vmdl" and unit.scale==1.7,
    "relocation ghost must match the current tower, not the level-one construction model")
assert(unit.skin==2)
local next_tower={}
for k,v in pairs(caster) do next_tower[k]=v end
next_tower.GetModelName=function() return "ultimate_tower.vmdl" end
local count=created
model.update(0,next_tower,profile,Vector(192,256,384))
assert(created==count+1 and unit.model=="ultimate_tower.vmdl",
    "changing towers rebuilds ghost even if building profile is unchanged")
model.clear(0)
assert(scheduler.task_count()==0)
print("GRID_RELOCATION_MODEL_PASS current tower appearance, entity change, cleanup")

-- The real Dota NPC API can have SetSkin with no matching GetSkin getter.
caster.GetSkin=nil
caster.survival_model_asset_id="active_sr_asset"
package.loaded["config/asset_catalog"]={resolve=function(id)
    assert(id=="active_sr_asset");return {model_skin=3}
end}
model.update(0,caster,profile,Vector(192,256,384))
assert(unit.skin==3 and unit.model=="existing_sr_tower.vmdl",
    "missing engine getter uses current SR asset skin")
model.clear(0)
caster.survival_model_asset_id=nil
model.update(0,caster,profile,Vector(192,256,384))
assert(unit.skin==0,"legacy model without getter or asset uses default skin")
model.clear(0)
local create=CreateUnitByName
CreateUnitByName=function(...)
    local proxy=create(...)
    proxy.SetModel=function() error("engine model setup failed") end
    return proxy
end
local before_created,before_removed=created,removed
model.update(0,caster,profile,Vector(192,256,384))
assert(created==before_created+1 and removed==before_removed+1 and unit.removed,
    "failed proxy configuration never leaks an untracked entity")
assert(scheduler.task_count()==0,"failure leaves no heartbeat")
CreateUnitByName=create
model.update(0,caster,profile,Vector(192,256,384))
assert(not unit.removed and unit.skin==0,"next update recovers after engine failure")
model.clear_all()
assert(scheduler.task_count()==0)
print("GRID_PREVIEW_ENGINE_API_PASS missing GetSkin, asset fallback, failed setup cleanup, recovery")
