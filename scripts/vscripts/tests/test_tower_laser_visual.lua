package.path = "scripts/vscripts/?.lua;" .. package.path
local mt = {}
mt.__add = function(a,b) return Vector(a.x+b.x,a.y+b.y,a.z+b.z) end
mt.__sub = function(a,b) return Vector(a.x-b.x,a.y-b.y,a.z-b.z) end
mt.__index = { Length2D = function(a) return math.sqrt(a.x*a.x+a.y*a.y) end }
Vector = function(x,y,z) return setmetatable({x=x,y=y,z=z},mt) end
local visual = require("systems/tower_laser_visual")
local caster = {GetAbsOrigin = function() return Vector(0,0,0) end}
local target = {GetAbsOrigin = function() return Vector(100,0,10) end,
    GetBoundingMaxs = function() return Vector(30,30,200) end,
    GetHullRadius = function() return 40 end}
local p = visual.head_position(caster,target,{})
assert(p.x == 80 and p.z == 186, "bounds fallback must scale with monster height")
target.ScriptLookupAttachment = function(_,name) return name == "attach_head" and 3 or 0 end
target.GetAttachmentOrigin = function() return Vector(100,0,210) end
p = visual.head_position(caster,target,{})
assert(p.x == 80 and p.z == 210, "head socket must take precedence over bounds")
target.GetAttachmentOrigin = function() error("missing attachment") end
p = visual.head_position(caster,target,{})
assert(p.z == 186, "optional socket errors must fall back")
target.GetBoundingMaxs = nil
assert(visual.head_position(caster,target,{target_offset_z=70}).z == 80)
assert(visual.blood_strength(800) < visual.blood_strength(8000))
assert(visual.blood_strength(8000) < visual.blood_strength(80000))
assert(visual.blood_strength(1e15) == 4 and visual.blood_strength(-1) == 1)
local creates, releases, destroys = 0,0,0
PATTACH_WORLDORIGIN = 0
ParticleManager = {
    CreateParticle = function() creates=creates+1; return creates end,
    SetParticleControl = function() end,
    ReleaseParticleIndex = function() releases=releases+1 end,
    DestroyParticle = function() destroys=destroys+1 end,
}
visual.hit(caster,p,{success=false,final_damage=500})
visual.hit(caster,p,{success=true,final_damage=0,engine_damage=500})
assert(creates == 0, "blocked/zero damage must not bleed")
visual.hit(caster,p,{success=true,final_damage=500})
assert(creates == 1 and releases == 1 and destroys == 0)
ParticleManager.SetParticleControl = function() error("injected control error") end
visual.hit(caster,p,{success=true,final_damage=500})
assert(creates == 2 and releases == 2 and destroys == 1, "failed burst must be destroyed and released")
-- A detached tail must need no caster/corpse and must survive handle release.
local tail = {afterglow=true,source_position=Vector(0,0,185),target_position=p,color=Vector(80,160,255)}
local old_create = ParticleManager.CreateParticle
ParticleManager.CreateParticle = function(_, path, attach, owner)
    assert(path:find("laser_afterglow.vpcf",1,true) and attach == PATTACH_WORLDORIGIN and owner == nil)
    return old_create()
end
ParticleManager.SetParticleControl = function() end
assert(visual.afterglow(tail))
assert(creates == 3 and releases == 3 and destroys == 1 and not tail.afterglow)
visual.afterglow(tail)
assert(creates == 3, "repeated death must not duplicate the tail")
tail.afterglow = true
ParticleManager.SetParticleControl = function() error("injected afterglow control failure") end
assert(visual.afterglow(tail) == false)
assert(creates == 4 and releases == 4 and destroys == 2, "failed afterglow is cleaned up")
-- Idle pose belongs to laser capability, not the lifetime of an enemy.
local pose_count, pose_cleared = 0, 0
GameRules = {GetGameTime = function() return 0 end}
caster.IsNull = function() return false end
caster.IsAlive = function() return true end
caster.AddNewModifier = function()
    pose_count = pose_count + 1
    return {IsNull = function() return false end, Destroy = function() pose_cleared = pose_cleared + 1 end}
end
local owner = {GetParent = function() return caster end}
visual.sync_pose(owner,{source_orb=true})
visual.sync_pose(owner,{source_orb=true})
assert(pose_count == 1 and pose_cleared == 0)
visual.sync_pose(owner,nil)
visual.clear_pose(owner)
assert(pose_cleared == 1 and owner.laser_pose == nil, "removing laser capability must clean pose once")
print("TOWER_LASER_VISUAL_PASS: head surface, bounds/socket fallback, actual damage, scaling, finite burst ownership")
