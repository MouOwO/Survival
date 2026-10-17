-- Real relocation, navigation and contact modules. Engine primitives and the
-- authoritative grid request handlers are the only fakes in this regression.
package.path = "scripts/vscripts/?.lua;" .. package.path
local bus, events = require("core/event_bus"), require("core/events")
Vector = function(x, y, z) return {x=x, y=y, z=z or 0} end
local function copy(p) return Vector(p.x, p.y, p.z) end
local function same(a, b) return a.x==b.x and a.y==b.y and a.z==b.z end
local obstacles, next_obstacle, fail_spawn_at = {}, 0, nil
local changes, releases, occupations, context_thinks = 0, 0, 0, {}
local reject_grid, fail_occupy = false, false
local clock = 0
local function obstacle_covers(o, p)
    return not o.deleted and not o.disabled
        and p.x>=o.position.x-64 and p.x<o.position.x+64
        and p.y>=o.position.y-64 and p.y<o.position.y+64
end
GridNav = {
    IsTraversable = function() return true end,
    IsBlocked = function(_, p)
        for _, o in ipairs(obstacles) do if obstacle_covers(o,p) then return true end end
        return false
    end,
    FindPathLength = function(_, a, b)
        return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2)
    end,
}
GetGroundHeight = function() return 384 end
FindUnitsInRadius = function() return {} end
SpawnEntityFromTableSynchronous = function(name, kv)
    assert(name=="point_simple_obstruction")
    next_obstacle=next_obstacle+1
    if fail_spawn_at==next_obstacle then
        fail_spawn_at=nil -- fail one new obstacle; allow rollback to rebuild.
        error("injected wall obstruction creation failure")
    end
    local o={position=copy(kv.origin), IsNull=function(self) return self.deleted end}
    obstacles[#obstacles+1]=o
    return o
end
DoEntFireByInstanceHandle = function(o, input)
    assert(input=="Disable");o.disabled=true
end
UTIL_Remove = function(o) assert(not o.deleted);o.deleted=true end
GameRules = {
    GetGameTime=function() return clock end,
    GetGameModeEntity=function()
        return {SetContextThink=function(_, key, callback)
            context_thinks[key]=callback
        end}
    end,
}
local wall={index=101, position=Vector(0,0,384), health=11400, max_health=20000,
    survival_level=10, survival_player_id=0, survival_building_id="wall",
    survival_grid_x=0, survival_grid_y=0, survival_grid_footprint={x=4,y=4},
    survival_fixed_position=Vector(0,0,384), modifiers={}}
function wall:entindex() return self.index end
function wall:IsNull() return false end
function wall:IsAlive() return true end
function wall:GetAbsOrigin() return self.position end
function wall:SetAbsOrigin(p) self.position=copy(p) end
function wall:GetTeamNumber() return 2 end
function wall:GetHealth() return self.health end
function wall:GetMaxHealth() return self.max_health end
function wall:SetSize() end
function wall:Stop() end
function wall:SetForceAttackTarget() end
function wall:FindModifierByName(name) return self.modifiers[name] end
function wall:HasModifier(name) return self.modifiers[name]~=nil end
function wall:RemoveModifierByName(name) self.modifiers[name]=nil end
function wall:AddNewModifier(_, _, name, params)
    self.modifiers[name]={params=params}
end
local state={unit=wall, building_id="wall", player_id=0, team=2, level=10,
    grid_x=0, grid_y=0, constructing=false, definition={footprint={x=4,y=4}}}
local occupied={x=0,y=0,index=wall.index}
bus.handle_request(events.GRID_CAN_PLACE_REQUEST,function(p)
    assert(p.ignore_entindex==wall.index and p.footprint.x==4 and p.footprint.y==4)
    return {ok=not reject_grid,error=reject_grid and "occupied" or nil,
        world_position=copy(p.position),grid_x=math.floor(p.position.x/64),
        grid_y=math.floor(p.position.y/64)}
end)
bus.handle_request(events.GRID_RELEASE_REQUEST,function(p)
    releases=releases+1
    if occupied and occupied.x==p.grid_x and occupied.y==p.grid_y then occupied=nil end
    return true
end)
bus.handle_request(events.GRID_OCCUPY_REQUEST,function(p)
    occupations=occupations+1
    if fail_occupy then fail_occupy=false;return false end
    occupied={x=p.grid_x,y=p.grid_y,index=p.entindex};return true
end)
local nav=require("systems/wall_navigation_service")
local contact=require("systems/wall_melee_contact")
local relocation=require("systems/building_relocation")
relocation.bind(function(index) return index==wall.index and state or nil end,
    function(s) return {unit=s.unit,entindex=s.unit:entindex(),building_id=s.building_id,
        player_id=s.player_id,level=s.level} end)
local old_position=copy(wall.position)
bus.subscribe(events.BUILDING_CHANGED,function(p)
    assert(p.unit==wall and p.entindex==101 and p.building_id=="wall")
    assert(not GridNav:IsBlocked(old_position),"publish only after old wall obstruction is removed")
    assert(GridNav:IsBlocked(wall.position),"publish only after new wall obstruction is installed")
    assert(occupied and occupied.x==state.grid_x and occupied.y==state.grid_y)
    changes=changes+1
end)
local function active_obstacles()
    local n=0;for _,o in ipairs(obstacles) do if not o.deleted then n=n+1 end end;return n
end
local function flush_network_refresh()
    local pending=context_thinks;context_thinks={}
    for _,callback in pairs(pending) do assert(callback()==nil) end
end
local function assert_preserved()
    assert(state.unit==wall and state.player_id==0 and state.level==10 and not state.constructing)
    assert(wall.survival_level==10 and wall.survival_player_id==0)
    assert(wall.health==11400 and wall.max_health==20000,"moving cannot heal or recreate a wall")
    assert(wall.survival_grid_x==state.grid_x and wall.survival_grid_y==state.grid_y)
    assert(occupied and occupied.x==state.grid_x and occupied.y==state.grid_y and occupied.index==wall.index)
    assert(same(wall.position,wall.survival_fixed_position))
    assert(active_obstacles()==4,"one square footprint must own exactly four native obstacles")
end
local function reserve_front()
    local origin=wall:GetAbsOrigin()
    local monster={radius=32,position=Vector(origin.x-184,origin.y-96,384)}
    function monster:IsNull() return false end
    function monster:IsAlive() return true end
    function monster:entindex() return 202 end
    function monster:GetAbsOrigin() return self.position end
    function monster:GetHullRadius() return self.radius end
    function monster:GetPaddedCollisionRadius() return self.radius+10 end
    function monster:SetHullRadius(radius) self.radius=radius end
    function monster:SetAbsOrigin(p) self.position=copy(p) end
    local plan=contact.resolve(wall,monster,1)
    assert(plan and plan.claimed and monster.radius==32,
        'reserving a contact must keep the native collision hull')
    return monster
end
nav.create(wall)
local front=reserve_front()
assert(relocation.move(wall,Vector(640,0,384)))
assert(front.radius==32,"wall relocation must release old claims without changing monster collision")
assert(not GridNav:IsBlocked(Vector(0,0,384)),"old wall position must be walkable after moving")
assert(GridNav:IsBlocked(Vector(640,0,384)),"new wall position must block movement")
assert(changes==1);assert_preserved();flush_network_refresh();assert_preserved()
assert(wall.survival_wall_relocation_revision==1)
old_position=copy(wall.position)
front=reserve_front()
assert(relocation.move(wall,Vector(640,640,384)))
assert(front.radius==32 and changes==2)
assert_preserved();flush_network_refresh();assert_preserved()
assert(wall.survival_wall_relocation_revision==2)

-- Authoritative placement rejects before any release, displacement or event.
local saved=copy(wall.position)
local release_before,occupation_before=releases,occupations
reject_grid=true
assert(not relocation.move(wall,Vector(1280,640,384)))
reject_grid=false
assert(same(saved,wall.position) and releases==release_before and occupations==occupation_before)
assert(changes==2);assert_preserved();flush_network_refresh();assert_preserved()
assert(wall.survival_wall_relocation_revision==2,"rejected placement must not invalidate monster goals")

-- Failure after a partial native-nav rebuild must not strand an open hole,
-- leak new blockers, publish a false wall move, or leave a delayed teleport.
old_position=copy(wall.position)
front=reserve_front()
fail_spawn_at=next_obstacle+2
local ok,reason=relocation.move(wall,Vector(-640,640,384))
assert(ok==false and reason,"native obstacle creation failure must be returned to the caster")
assert(same(saved,wall.position) and not GridNav:IsBlocked(Vector(-640,640,384)))
assert(GridNav:IsBlocked(saved) and changes==2)
assert(front.radius==32,"rollback must not resurrect old contact reservations")
assert_preserved();flush_network_refresh();assert_preserved()
assert(wall.survival_wall_relocation_revision==2,"rolled-back native navigation must not publish a relocation revision")

-- Grid handlers return a boolean. An explicit false must not be mistaken for
-- successful occupancy, and rollback must restore the previous occupied area.
fail_occupy=true
ok,reason=relocation.move(wall,Vector(0,-640,384))
assert(ok==false and reason,"failed grid occupancy must abort wall relocation")
assert(same(saved,wall.position) and not GridNav:IsBlocked(Vector(0,-640,384)))
assert(GridNav:IsBlocked(saved) and changes==2)
assert_preserved();flush_network_refresh();assert_preserved()
assert(wall.survival_wall_relocation_revision==2,"rolled-back occupancy must not publish a relocation revision")
nav.clear(wall)
assert(active_obstacles()==0)
print("WALL_RELOCATION_LIFECYCLE_PASS real navigation/contact, identity and health, grid rejection, partial rebuild rollback, occupancy rollback, no stale delayed teleport")
