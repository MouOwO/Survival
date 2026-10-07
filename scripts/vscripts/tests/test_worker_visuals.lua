package.path = "scripts/vscripts/?.lua;" .. package.path
local visual=require("systems/worker_visual_service")
local definitions=require("config/generated/training_definitions")
local removed=0
UTIL_Remove=function(p) assert(not p.dead);p.dead=true;removed=removed+1 end
EF_BONEMERGE=1
SpawnEntityFromTableSynchronous=function(kind, kv)
    assert(kind=="prop_dynamic" and kv.solid=="0")
    return {model=kv.model,IsNull=function(self)return self.dead end,
        SetOwner=function(self,u)self.owner=u end,SetParent=function(self,u)self.parent=u end,
        FollowEntity=function(self,u,b)assert(b);self.follow=u end,AddEffects=function()end}
end
local unit={SetModel=function(self,m)self.model=m end,SetOriginalModel=function(self,m)self.original=m end,
    SetModelScale=function(self,s)self.scale=s end}
for level=1,8 do
    local row=definitions.by_id[string.format("train_lumberjack_%02d",level)]
    visual.apply(unit,row);assert(unit.scale==row.model_scale)
    visual.apply(unit,row,true);assert(unit.scale==row.model_scale*1.5)
    visual.apply(unit,row,true);assert(unit.scale==row.model_scale*1.5,"refresh cannot compound scaling")
end
for level=1,2 do
    local row=definitions.by_id[string.format("train_repairer_%02d",level)]
    visual.apply(unit,row);assert(unit.model==row.model_name and unit.original==row.model_name)
    assert(unit.scale<1 and #unit.survival_worker_model_parts==(level==1 and 4 or 6))
    for _,p in ipairs(unit.survival_worker_model_parts)do assert(p.parent==unit and p.follow==unit and p.owner==unit)end
    local count=#unit.survival_worker_model_parts;local before=removed
    visual.apply(unit,row);assert(removed==before+count,"reapply removes old parts")
    visual.cleanup(unit);assert(removed==before+count*2)
    visual.cleanup(unit);assert(removed==before+count*2,"cleanup is idempotent")
end
print("PASS worker visuals: normalized 8 levels, fixed 150% fusion, repairer default parts, refresh and cleanup")
