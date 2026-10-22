-- Production contact/queue integration: wide rear goals stay attached to
-- their attack face, including goals outside the 512-unit admission area.
package.path='scripts/vscripts/?.lua;'..package.path
Vector=function(x,y,z) return {x=x,y=y,z=z or 256} end
local clock,paths,nav=0,0,0
GameRules={GetGameTime=function() return clock end}
GetGroundHeight=function() return 256 end
GridNav={IsTraversable=function() nav=nav+1;return true end,
 IsBlocked=function(_,p) nav=nav+1;return math.abs(p.x)<128 and math.abs(p.y)<128 end,
 FindPathLength=function(_,a,b)
  paths=paths+1
  return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2)
 end}
package.loaded['systems/wall_navigation_service']={contact_layout=function() return nil end}
local contact=require('systems/wall_melee_contact')
local function actor(id,x,y,radius)
 local u={p=Vector(x,y),radius=radius or 32}
 function u:entindex() return id end
 function u:IsNull() return false end
 function u:IsAlive() return not self.dead end
 function u:GetAbsOrigin() return self.p end
 function u:GetHullRadius() return self.radius end
 function u:GetPaddedCollisionRadius() return self.radius+10 end
 function u:SetAbsOrigin() error('the allocator must not teleport') end
 function u:SetHullRadius() error('the allocator must not resize native bodies') end
 return u
end
local wall=actor(1,0,0,128)
local fronts={}
for i,along in ipairs({-132,-44,44,132}) do
 local u=actor(i+1,-184,along)
 local plan=assert(contact.resolve(wall,u,1));assert(plan.claimed)
 assert(contact.settle(wall,u,plan.point));fronts[#fronts+1]=u
end
local units,points={},{}
for i=1,60 do units[i]=actor(100+i,-400,(i%9-4)*60) end
for pass=1,24 do
 clock=pass*.5
 local before=paths
 for _,u in ipairs(fronts) do assert(contact.resolve(wall,u,1).claimed) end
 for _,u in ipairs(units) do
  local plan=assert(contact.resolve(wall,u,1));assert(not plan.claimed)
  if not plan.waiting_blocked then points[u]=plan.point end
 end
 assert(paths-before<=16,'front and rear paths must share the original wall budget')
end
local columns,depths,seen={},{},{}
for _,u in ipairs(units) do
 local p=assert(points[u],'a live rear unit never received a reachable goal')
 local key=p.x..':'..p.y
 assert(not seen[key],'rear units still share a destination')
 seen[key]=true;columns[p.y]=true;depths[p.x]=true
 u.p=p -- Model completion of the native MOVE; no production position setter.
end
local count=0;for _ in pairs(columns) do count=count+1 end
assert(count>4,'open rear space was still collapsed into four columns')
local before_paths,before_nav=paths,nav
for pass=1,20 do
 clock=12+pass*.05
 for _,u in ipairs(fronts) do assert(contact.resolve(wall,u,1).claimed) end
 for _,u in ipairs(units) do
  -- Real rich walls may have no recognized gate. Once a destination is
  -- reserved, a wide lateral coordinate must not rotate its queue face.
  local plan=assert(contact.resolve(wall,u))
  assert(not plan.claimed and plan.wait_face==1 and plan.point==points[u],
    'arriving at a wide/deep rear destination changed face or lost its reservation')
 end
end
assert(paths==before_paths and nav==before_nav,'stable rear integration repeated navigation work')
local victim=fronts[2];victim.dead=true;contact.release(1,victim:entindex())
local admitted=0
for _,u in ipairs(units) do
 local plan=assert(contact.resolve(wall,u,1))
 if plan.claimed then
  admitted=admitted+1
  assert(plan.point.x==victim.p.x and plan.point.y==victim.p.y,
    'replacement must use exactly the free front contact')
 end
end
assert(admitted==1,'one front death must admit exactly one replacement')
contact.clear(1)
wall.p=Vector(0,64);wall.survival_wall_relocation_revision=1
local newcomer=actor(500,-400,64)
local plan=assert(contact.resolve(wall,newcomer,1))
assert(plan.claimed,'wall relocation retained an obsolete rear reservation')
print('WALL_COURTYARD_CONTACT_PASS 60_unique_rear_goals more_than_four_columns same_face_after_arrival shared_16_path_budget stable_queries_zero one_death_one_replacement relocated_wall')
