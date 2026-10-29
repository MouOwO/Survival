-- Real placement/mode bounds/routing; native API fixtures only, no world writes.
-- Run: lua scripts/vscripts/tests/test_archive_four_hub_placement.lua
package.path = "scripts/vscripts/?.lua;" .. package.path
local bus = require("core/event_bus")
local events = require("core/events")
local mode_spawns = require("systems/mode_spawn_service")
local mode_config = require("config/mode_spawn_config")
local layout_file=assert(io.open("art/maps/mode_spawns/layout.json","rb"))
local authored_layout=require("core/json_decoder").decode(layout_file:read("*a"));layout_file:close()
local routing = require("systems/wave_spawn_routing")
local placement = require("systems/archive_hub_placement")
local function vector(x, y, z) return {x=x, y=y, z=z or 128} end
Vector = vector
DOTA_TEAM_GOODGUYS, DOTA_UNIT_TARGET_TEAM_BOTH = 2, 3
DOTA_UNIT_TARGET_HERO, DOTA_UNIT_TARGET_BASIC, DOTA_UNIT_TARGET_BUILDING = 1, 2, 4
DOTA_UNIT_TARGET_FLAG_INVULNERABLE, FIND_ANY_ORDER = 8, 0
local function entity(x, y, z, hull)
    local unit = {position=vector(x,y,z), hull=hull or 80}
    function unit:IsNull() return self.removed == true end
    function unit:IsAlive() return self.dead ~= true end
    function unit:GetAbsOrigin() return self.position end
    function unit:GetHullRadius() return self.hull end
    return unit
end
local fixture, checks = nil, 0
local rule = {building_anchor="wave_portal",building_spacing=240,building_offset_y=360}
local context = {slot=function() error("portal placement must not inspect ordinary slots") end,
    resolve_builder_spawn=function() error("portal placement must not inspect builder spawns") end}
local wave = {get_player_spawn_marker=function(id)
    fixture.wave_lookups = fixture.wave_lookups + 1
    return fixture.portals[id]
end}
local function check(value, message) checks=checks+1; assert(value, message) end
local function reset(mode)
    fixture = {portals={}, units={}, markers={}, nav_queries=0, wave_lookups=0,
        marker_lookups=0, grid_queries=0, unit_queries=0, reserved={}}
    fixture.height=function() return 128 end
    fixture.blocked=function() return false end
    fixture.walkable=function() return true end
    fixture.tree=function() return false end
    package.loaded["systems/match_setup_service"]={get_mode=function() return mode end}
    GetMapName=function() return mode_config.map_name end
    GetGroundPosition=function(p) return vector(p.x,p.y,fixture.height(p)) end
    GridNav={IsTraversable=function(_,p)
        fixture.nav_queries=fixture.nav_queries+1
        return fixture.walkable(p)
    end, IsBlocked=function(_,p) return fixture.blocked(p) end,
    IsNearbyTree=function(_,p,radius,full_collision)
        check(radius==96 and full_collision==true,"tree check retains native signature")
        return fixture.tree(p)
    end}
    Entities={FindByName=function(_,_,name)
        fixture.marker_lookups=fixture.marker_lookups+1
        return fixture.markers[name]
    end}
    FindUnitsInRadius=function(team,p,_,radius,target_team,target_type,flags,order,cache)
        check(team==2 and radius==608 and target_team==3 and target_type==7
            and flags==8 and order==0 and cache==false,"unit overlap uses native target flags")
        fixture.unit_queries=fixture.unit_queries+1
        local result={}
        for _,unit in ipairs(fixture.units) do
            local at=unit:GetAbsOrigin()
            if (at.x-p.x)^2+(at.y-p.y)^2<=radius^2 then result[#result+1]=unit end
        end
        return result
    end
    FindClearSpaceForUnit=function() error("hub placement cannot invoke native clear-space") end
    bus.reset()
    bus.handle_request(events.GRID_CAN_PLACE_REQUEST,function()
        fixture.grid_queries=fixture.grid_queries+1
        error("portal system spawns cannot use the ordinary construction lawn")
    end)
    package.loaded["systems/building_system"]={wall_for_player=function()
        error("portal placement cannot fall back to a wall")
    end}
end
local function reserve(player,index)
    local position,source=placement.resolve(player,index,rule,context,wave,fixture.reserved)
    check(position and source=="wave_portal","expected safe hub near the routed entrance")
    local unit=entity(position.x,position.y,position.z)
    fixture.units[#fixture.units+1]=unit
    fixture.reserved[#fixture.reserved+1]={unit=unit,position=position,player=player,index=index}
    local anchor=wave.get_player_spawn_marker(player):GetAbsOrigin()
    local distance=(position.x-anchor.x)^2+(position.y-anchor.y)^2
    check(distance>=360^2-0.001 and distance<=840^2+0.001,"default search stays within 360..840")
    for _,portal in pairs(fixture.portals) do
        local p=portal:GetAbsOrigin()
        check((position.x-p.x)^2+(position.y-p.y)^2>=288^2,
            "keep every actual spawn mouth clear, including shared entrances")
    end
    for _,entry in ipairs(fixture.reserved) do
        if entry.unit~=unit then
            local p=entry.position
            check((position.x-p.x)^2+(position.y-p.y)^2>=192^2,
                "cross-player reservations must never overlap")
        end
    end
    local config=mode_spawns.active() and mode_spawns.config()
    if config then check(mode_spawns.contains(config.bounds,position,64,64),"entire hub fits its mode region") end
    return position
end
local function reject()
    local position,reason=placement.resolve(0,1,rule,context,wave,fixture.reserved)
    check(position==nil and reason=="safe_hub_position_missing","unsafe portal must wait safely")
    check(fixture.grid_queries==0,"must not fall back to construction/other mode")
end

-- Real cold routing assigns four owners in the same court to the same actual
-- mode marker. Both the old three-hub layout and new four-hub layout fit.
for _,hub_count in ipairs({3,4}) do
    reset("cold")
    local config=mode_spawns.config()
    local authored=authored_layout.modes.cold.monsters[1]
    local portal=entity(authored[1],authored[2],authored[3],0)
    fixture.markers[config.monster_markers[0]]=portal
    local court=config.player_build_bounds[0]
    package.loaded["systems/building_system"].main_city_for_player=function()
        return entity((court.min_x+court.max_x)/2,(court.min_y+court.max_y)/2,128)
    end
    local channels={}
    for id=0,3 do channels[id]={player_id=id,marker=entity(-9000,-9000,128)} end
    routing.refresh(channels,{})
    for id=0,3 do
        check(channels[id].route_id==0 and channels[id].marker==portal,"cold owners share the actual routed marker")
        fixture.portals[id]=channels[id].marker
    end
    for id=0,3 do for index=1,hub_count do reserve(id,index) end end
    check(#fixture.reserved==hub_count*4,"all owners receive all hubs")
    check(fixture.grid_queries==0,"mode portal terrain bypasses ordinary lawns")
end

-- Four distinct entrances are used in all integrated combat modes. Fixture
-- portals are inside each real authored mode region, not ordinary-map aliases.
for _,mode in ipairs({"standard","pure","rich","cold","scourge"}) do
    reset(mode)
    local config=mode_spawns.active() and mode_spawns.config()
    local bounds=config and config.bounds or {min_x=-6000,max_x=6000,min_y=-6000,max_y=6000}
    for id=0,3 do
        local authored=authored_layout.modes[mode] and authored_layout.modes[mode].monsters[id+1]
        local x=authored and authored[1] or (id%2==0 and bounds.min_x+1200 or bounds.max_x-1200)
        local y=authored and authored[2] or (id<2 and bounds.min_y+1200 or bounds.max_y-1200)
        fixture.portals[id]=entity(x,y,authored and authored[3] or 192,0)
    end
    for id=0,3 do for index=1,4 do reserve(id,index) end end
    check(#fixture.reserved==16 and fixture.marker_lookups==0,"never consult old/other-mode named markers")
end

local function near(p,x,y) return math.abs(p.x-x)<=64 and math.abs(p.y-y)<=64 end
for _,failure in ipairs({"blocked","unwalkable","tree","unit","unit_edge","height","footprint_height","reserved"}) do
    reset("cold")
    fixture.portals[0]=entity(12000,10000,192,0)
    if failure=="blocked" then fixture.blocked=function(p) return near(p,12000,10360) end
    elseif failure=="unwalkable" then fixture.walkable=function(p) return not near(p,12000,10360) end
    elseif failure=="tree" then fixture.tree=function(p) return near(p,12000,10360) end
    elseif failure=="unit" then fixture.units[1]=entity(12000,10360,128,80)
    elseif failure=="unit_edge" then fixture.units[1]=entity(12130,10360,128,80)
    elseif failure=="height" then fixture.height=function(p) return near(p,12000,10360) and 0 or 128 end
    elseif failure=="footprint_height" then
        fixture.height=function(p) return p.x==11936 and p.y==10296 and 256 or 128 end
    elseif failure=="reserved" then
        local unit=entity(12190,10360,128,0)
        fixture.reserved[1]={unit=unit,position=unit.position}
    end
    local result=reserve(0,1)
    check(result.x~=12000 or result.y~=10360,failure.." must reject the preferred site")
end

-- A footprint crossing the real mode border is rejected even when navigation
-- says it is walkable; an out-of-region marker cannot reenter by offsetting.
reset("cold")
local bounds=mode_spawns.config().bounds
fixture.portals[0]=entity(bounds.min_x+63,10000,192,0)
local position=reserve(0,1)
check(position.x>=bounds.min_x+64,"center-only bounds checks miss a crossing footprint")
reset("cold")
fixture.portals[0]=entity(bounds.min_x-1,10000,192,0)
reject()
check(fixture.nav_queries==0,"outside-mode route is rejected before terrain search")

-- Protect a nearby player's actual spawn mouth as well as our own.
reset("standard")
fixture.portals[0],fixture.portals[1]=entity(0,0,128,0),entity(0,360,128,0)
position=reserve(0,1)
check(position.x~=0 or position.y~=360,"another player's mouth cannot hold this hub")

-- Search exhaustion is bounded on every call; no hidden timer/clear-space or
-- stale marker fallback exists. A later normal retry can use restored terrain.
reset("cold")
fixture.portals[0]=entity(12000,10000,128,0)
fixture.walkable=function() return false end
reject()
check(fixture.nav_queries==24,"one failed resolution considers exactly 8 directions x 3 rings")
reject()
check(fixture.nav_queries==48,"each retry remains bounded")
fixture.walkable=function() return true end
reserve(0,1)

for _,failure in ipairs({"missing","null","nil_origin","invalid_origin","ground_nil","ground_error","no_ground","no_nav","nav_error","unit_error","map_mismatch"}) do
    reset("cold")
    fixture.portals[0]=entity(12000,10000,128,0)
    if failure=="missing" then fixture.portals[0]=nil
    elseif failure=="null" then fixture.portals[0].removed=true
    elseif failure=="nil_origin" then fixture.portals[0].position=nil
    elseif failure=="invalid_origin" then fixture.portals[0].position.x=0/0
    elseif failure=="ground_nil" then GetGroundPosition=function() return nil end
    elseif failure=="ground_error" then GetGroundPosition=function() error("terrain not ready") end
    elseif failure=="no_ground" then GetGroundPosition=nil
    elseif failure=="no_nav" then GridNav=nil
    elseif failure=="nav_error" then GridNav.IsTraversable=function() error("navigation not ready") end
    elseif failure=="unit_error" then FindUnitsInRadius=function() error("unit query not ready") end
    elseif failure=="map_mismatch" then GetMapName=function() return "wrong_map" end end
    reject()
    check(fixture.marker_lookups==0,"no ordinary island fallback after "..failure)
end
print("PASS archive four-hub placement: "..checks.." checks; real cold shared routing, 16 hubs, all modes, bounded 24 candidates, terrain/bounds/unit rejection, safe recovery")
