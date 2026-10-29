-- Actual authored regions, placement grid and tree events; only native engine
-- terrain/entity operations are supplied by this isolated map fixture.
package.path="scripts/vscripts/?.lua;"..package.path
-- This gameplay fixture starts after account admission, as in a live match.
package.loaded["core/test_access_policy"]={enabled=function() return false end}
GetMapName=function() return "template_map" end
local vector_meta={__add=function(a,b) return Vector(a.x+b.x,a.y+b.y,a.z+b.z) end}
Vector=function(x,y,z) return setmetatable({x=x,y=y,z=z or 0},vector_meta) end
DOTA_TEAM_GOODGUYS,DOTA_TEAM_BADGUYS=2,3
DOTA_UNIT_CAP_NO_ATTACK=0
DOTA_UNIT_TARGET_TEAM_BOTH,DOTA_UNIT_TARGET_HERO,DOTA_UNIT_TARGET_BASIC=3,1,2
DOTA_UNIT_TARGET_BUILDING,DOTA_UNIT_TARGET_FLAG_INVULNERABLE,FIND_ANY_ORDER=4,64,0
package.loaded["systems/match_setup_service"]={get_mode=function() return "rich" end}
package.loaded["core/particle_manager"]={}
package.loaded["core/modifier_registry"]={ensure=function() end}
package.loaded["core/scheduler"]={cancel=function() end,every=function() end}
package.loaded["systems/harvest_feedback_service"]={reset=function() end}
package.loaded["systems/rogue_effect_state_service"]={numeric=function() return 0 end}
local authored=require("config/mode_spawn_config").modes.rich
local court_height=assert(authored.build_ground_height)
local service=require("systems/mode_spawn_service")
local function height(p)
    for id=0,3 do if service.contains(authored.player_bounds[id],p) then return court_height end end
    return 0
end
GetGroundPosition=function(p) return Vector(p.x,p.y,height(p)) end
GetGroundHeight=height
GridNav={IsTraversable=function() return true end,IsBlocked=function() return false end,
    IsNearbyTree=function() return false end}
FindUnitsInRadius=function() return {} end
GameRules={GetGameTime=function() return 0 end}
local created,entities,markers={},{},{}
local function unit(id,p)
    local u={id=id,position=p}
    function u:IsNull() return self.removed==true end
    function u:IsAlive() return not self.removed end
    function u:entindex() return self.id end
    function u:GetAbsOrigin() return self.position end
    function u:SetAbsOrigin(position) self.position=position end
    function u:GetTeamNumber() return 2 end
    function u:HasModifier() return false end
    function u:SetBaseMaxHealth(h) self.max=h end
    function u:SetMaxHealth(h) self.max=h end
    function u:SetHealth(h) self.health=h end
    for _,name in ipairs({"SetPhysicalArmorBaseValue","SetModel","SetOriginalModel","SetModelScale","SetAttackCapability"}) do
        u[name]=function() end
    end
    entities[id]=u;return u
end
markers[authored.center_marker]=unit(1,Vector(-2752,-9984,0))
for id=0,3 do
    local b=authored.player_bounds[id]
    markers[authored.player_markers[id]]=unit(id+2,Vector((b.min_x+b.max_x)/2,(b.min_y+b.max_y)/2,court_height))
end
Entities={FindByName=function(_,_,name) return markers[name] end}
EntIndexToHScript=function(id) return entities[id] end
UTIL_Remove=function(u) u.removed=true end
CreateUnitByName=function(_,p)
    local tree=unit(100+#created,p);created[#created+1]=tree;return tree
end
local bus=require("core/event_bus")
local events=require("core/events")
local grid=require("systems/grid_placement_system")
require("systems/player_context_service")
local regions=require("systems/rich_region_service")
local trees=require("systems/tree_system")
local config=require("config/tree_config")
local directions={"east","south","west","north"}
local snapshots,notices={},{}
local function reset()
    created={};bus.reset();regions.init();grid.init();trees.init();snapshots={};notices={}
    bus.subscribe(events.TREE_CHANGED,function(p) snapshots[p.player_id]=p end)
    bus.subscribe(events.UI_NOTIFICATION,function(p) notices[#notices+1]=p end)
end
local function build(owner,route)
    local p=markers[authored.player_markers[route]]:GetAbsOrigin()
    bus.emit(events.BUILDING_CREATED,{building_id="main_city",player_id=owner,unit=unit(1000+owner,p)})
end
for route=0,3 do
    reset()
    for owner=0,3 do
        build(owner,route)
        assert(#created==owner+1,"each owner sharing a court receives one independent tree")
        local tree,expected=created[owner+1],config.rich_spawn_regions[directions[route+1]][owner+1]
        assert(tree.position.x==expected.x and tree.position.y==expected.y,
            "fixed outer-edge tree sockets follow the physical city court, not the player's spawn assignment")
        assert(tree.survival_tree_owner_id==owner and snapshots[owner].region_id=="rich:"..directions[route+1])
        assert(regions.region_at(tree.position).player_index==route)
    end
    build(0,(route+1)%4)
    assert(#created==4,"a repeated city event cannot duplicate or migrate the owner's existing tree")
    trees._upgrade_tree_for_test(created[3])
    assert(snapshots[2].rich_level2_wood_per_second==20 and snapshots[2].lumber_efficiency_buff==21)
    assert(snapshots[0].rich_level2_wood_per_second==0 and snapshots[1].rich_level2_wood_per_second==0
        and #notices==1 and notices[1].player_id==2,"sharing a physical court cannot share another owner's reward")
    local removed=created[2]
    bus.emit(events.PLAYER_DISCONNECTED,{player_id=1})
    assert(removed.removed,"leaving releases only that owner's tree")
    build(1,route)
    local replacement=created[5]
    assert(replacement and replacement.position.x==removed.position.x and replacement.position.y==removed.position.y,
        "a released socket can be reused while other owners keep their trees")
end
reset()
bus.emit(events.BUILDING_CREATED,{building_id="main_city",player_id=0,unit=unit(1000,Vector(-2752,-9984,0))})
assert(#created==0,"an invalid city on the central road cannot claim an arbitrary tree patch")
print("RICH_SHARED_TREES_PASS: 4 courts x4 personal trees, physical city court, fixed edge sockets, unique occupancy/reuse, duplicate events, private Lv2 reward and invalid-road rejection")
