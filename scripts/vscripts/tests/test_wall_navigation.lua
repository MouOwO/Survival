package.path="scripts/vscripts/?.lua;"..package.path
Vector=function(x,y,z) return {x=x,y=y,z=z or 0} end
local obstacles,created,removed={},0,0
local function covered(o,p)
    return not o.deleted and p.x>=o.p.x-64 and p.x<o.p.x+64
        and p.y>=o.p.y-64 and p.y<o.p.y+64
end
GridNav={IsTraversable=function() return true end,IsBlocked=function(_,p)
    for _,o in ipairs(obstacles) do if covered(o,p) then return true end end
    return false
end}
SpawnEntityFromTableSynchronous=function(name,kv)
    assert(name=="point_simple_obstruction" and kv.block_fow==0)
    local o={p=kv.origin,IsNull=function(self) return self.deleted end}
    obstacles[#obstacles+1]=o;created=created+1;return o
end
DoEntFireByInstanceHandle=function(_,input) assert(input=="Disable") end
UTIL_Remove=function(o) assert(not o.deleted);o.deleted=true;removed=removed+1 end
local function wall(i)
    return {IsNull=function() return false end,entindex=function() return i end,
        GetAbsOrigin=function() return Vector(0,0,384) end}
end
local nav=require("systems/wall_navigation_service")
local w=wall(1)
local bounds,protection_clears=0,0
function w:SetSize(lo,hi)
    assert(lo.x==-128 and lo.y==-128 and hi.x==128 and hi.y==128)
    bounds=bounds+1
end
function w:RemoveModifierByName(name)
    assert(name=="modifier_invulnerable","construction protection must be preserved")
    protection_clears=protection_clears+1
end
assert(#nav.create(w)==4 and #nav.create(w)==4 and created==4)
assert(bounds==2 and protection_clears==2,"completion reapplies bounds and clears delayed native protection")
local attacker={IsNull=function() return false end,GetAbsOrigin=function() return Vector(-900,0,384) end}
nav.approach(w,attacker);assert(created==4)
attacker.GetAbsOrigin=function() return Vector(-400,0,384) end
nav.approach(w,attacker);nav.approach(w,attacker)
assert(created==4,"approach direction never creates protruding obstacles")
assert(not GridNav:IsBlocked(Vector(32,224,384)))
assert(not GridNav:IsBlocked(Vector(-160,32,384)),"approach face remains at model edge")
local traversable,blocked=nav.original_nav(Vector(32,32,384))
assert(traversable and blocked==false,"shoulder does not become forbidden building terrain")
assert(nav.original_nav(Vector(900,900,384))==nil,"unrelated blockers are never masked")
-- Overlapping navigation ownership must survive either wall's destruction.
local second=wall(2);nav.create(second);nav.clear(w)
assert(GridNav:IsBlocked(Vector(32,32,384)))
assert(select(2,nav.original_nav(Vector(32,32,384)))==false)
assert(nav.original_nav(Vector(32,224,384))==nil)
nav.clear(second);nav.clear(second)
assert(removed==created and nav.original_nav(Vector(32,32,384))==nil)
assert(not GridNav:IsBlocked(Vector(32,32,384)))
local expired=wall(3);nav.create(expired)
expired.IsNull=function() return true end
expired.entindex=function() error("native handle already deleted") end
require("systems/wall_collision_barrier_service").clear(expired)
assert(removed==created,"late cleanup must remove blockers after native wall deletion")
print("WALL_NAVIGATION_PASS square body, no protruding shoulders, no duplicate creation, terrain separation, overlap release")

local clock,particles,released=0,0,0
GameRules={GetGameTime=function() return clock end}
PATTACH_WORLDORIGIN=0
ParticleManager={CreateParticle=function(_,path)
    assert(path=="particles/units/heroes/hero_rattletrap/rattletrap_cog_attack_impact.vpcf")
    particles=particles+1;return particles
end,SetParticleControl=function(_,_,cp,p)
    assert(cp==0 and p.x==-124 and p.y==0 and p.z==448,"impact stays on visible face")
end,ReleaseParticleIndex=function() released=released+1 end}
local hit=require("systems/wall_hit_effect")
hit.play(w,attacker);hit.play(w,attacker);assert(particles==1 and released==1)
clock=.1;hit.play(w,attacker);assert(particles==2 and released==2)
print("WALL_METAL_HIT_PASS official asset, face position, burst limit, particle release")
