package.path = "scripts/vscripts/?.lua;" .. package.path
Vector = function(x,y,z) return {x=x,y=y,z=z or 0} end
GetMapName = function() return "template_map" end
local mode, reads, nav_reads = "standard", {}, 0
package.loaded["systems/match_setup_service"] = {get_mode=function() return mode end}
local config = {map_name="template_map",modes={}}
package.loaded["config/mode_spawn_config"] = config
local markers = {}
local function marker(x,y,z)
    return {IsNull=function() return false end,GetAbsOrigin=function() return Vector(x,y,z or 16) end}
end
-- Deliberately connected navigation: authored player ownership must not be
-- inferred from disconnected flood-fill components or ordinary map quadrants.
for index,name in ipairs({"rich","cold","scourge"}) do
    local cx,cy=index*8000-16000,-8000
    local row={center_marker=name.."_start",player_markers={},monster_markers={},player_bounds={},
        bounds={min_x=cx-3000,max_x=cx+3000,min_y=cy-3000,max_y=cy+3000}}
    markers[row.center_marker]=marker(cx,cy)
    for id=0,3 do
        local x,y=cx-2048+(id%2)*4096,cy+2048-math.floor(id/2)*4096
        row.player_markers[id]="mode_"..name.."_player_"..id.."_spawn"
        row.monster_markers[id]="mode_"..name.."_monster_"..id.."_spawn"
        row.player_bounds[id]={min_x=x-512,max_x=x+512,min_y=y-512,max_y=y+512}
        markers[row.player_markers[id]]=marker(x+32,y+32)
        markers[row.monster_markers[id]]=marker(cx+(id%2-.5)*192,cy+(math.floor(id/2)-.5)*192)
    end
    config.modes[name]=row
end
Entities={FindByName=function(_,_,name)
    reads[name]=(reads[name] or 0)+1
    assert(name~="monsterborn_player1" and not name:find("builder_spawn",1,true),"dedicated mode must not query normal markers")
    return markers[name]
end}
local blocked={}
local function key(p) return math.floor(p.x/64)..":"..math.floor(p.y/64) end
GridNav={IsTraversable=function() nav_reads=nav_reads+1;return true end,
    IsBlocked=function(_,p) return blocked[key(p)]==true end}
GetGroundPosition=function(p) return Vector(p.x,p.y,128) end
local tasks={}
package.loaded["core/scheduler"]={cancel=function(name) tasks[name]=nil end,
    every=function(_,fn,name) tasks[name]=fn end}
local context=require("systems/player_context_service")
local regions=require("systems/rich_region_service")
local spawns=require("systems/mode_spawn_service")
local routing=require("systems/wave_spawn_routing")
local destinations=require("systems/destination_validation_service")
EntIndexToHScript=function() error("mode routing must not read normal wall quadrants") end
for _,name in ipairs({"rich","cold","scourge"}) do
    mode=name;regions.init();blocked={}
    local row=config.modes[name]
    local channels,builders={},{}
    for id=0,3 do
        local spawn=assert(context.resolve_builder_spawn(id))
        local expected=markers[row.player_markers[id]]:GetAbsOrigin()
        assert(spawn.mode==name and spawn.source=="mode_hammer_marker" and spawn.marker==row.player_markers[id])
        assert(spawn.position.x==expected.x and spawn.position.y==expected.y and spawn.position.z==128)
        assert(regions.validate_position(id,spawn.position))
        assert(not regions.validate_position((id+1)%4,spawn.position),"connected terrain does not merge owners")
        assert(not regions.validate_position(id,markers[row.center_marker]:GetAbsOrigin()),"central monster area is not a player court")
        channels[id]=assert(spawns.wave_marker(id))
        local builder={survival_builder_id="default_builder",survival_player_id=id,position=spawn.position}
        function builder:IsNull() return false end
        function builder:GetAbsOrigin() return self.position end
        function builder:SetOrigin(p) self.position=p end
        function builder:Stop() self.stopped=true end
        assert(regions.attach_builder(id,builder,spawn.slot_id));builders[id]=builder
        assert(destinations.validate_hero_position(spawn.position),"summon/home/respawn uses local navigation instead of the normal whitelist")
    end
    routing.refresh(channels,{[0]=10,[1]=11,[2]=12,[3]=13},1)
    local steady=nav_reads
    for id=0,3 do
        local p=assert(routing.position(channels[id]))
        local expected=markers[row.monster_markers[id]]:GetAbsOrigin()
        assert(p.x==expected.x and p.y==expected.y and p.z==128)
        assert(channels[id].marker_name==row.monster_markers[id] and channels[id].mode==name)
        assert(not regions.validate_position(id,p),"monster spawn must be central, not inside a private player court")
        for _=1,100 do assert(routing.position(channels[id])) end
        p.x=0;assert(routing.position(channels[id]).x==expected.x,"returned vectors cannot move map markers/cache")
    end
    assert(nav_reads==steady,"per-monster routing never rescans map markers/navigation")
    local home=builders[0].position
    builders[0].position=builders[1].position
    assert(regions.guard() and builders[0].stopped and builders[0].position.x==home.x)
    local r=assert(regions.region(0))
    assert(regions.validate_building_footprint(0,home.x-128,home.y-128,home.x+128,home.y+128))
    assert(not regions.validate_building_footprint(0,r.min_x*64-64,r.min_y*64,r.min_x*64+64,r.min_y*64+128))
    blocked[key(home)]=true
    local replacement=assert(context.resolve_builder_spawn(0))
    assert(key(replacement.position)~=key(home) and regions.validate_position(0,replacement.position),"blocked re-entry stays in its authored court")
    blocked={}
    local missing_name=row.monster_markers[2]
    local saved=markers[missing_name];markers[missing_name]=nil
    routing.refresh(channels,{},1)
    assert(not routing.position(channels[2]) and channels[2].route_error:find("mode_spawn_marker_missing",1,true))
    assert(routing.position(channels[0]) and routing.position(channels[1]) and routing.position(channels[3]))
    markers[missing_name]=saved
    routing.refresh(channels,{},1)
    assert(routing.position(channels[2]),"failed channel can recover to the same dedicated marker")
    assert(not spawns.validate_position(Vector(0,10000,128)),"out-of-mode clear-space displacement fails closed")
end
mode="cold";regions.init()
local missing=config.modes.cold.player_markers[0]
local saved=markers[missing];markers[missing]=nil
local spawn,reason=context.resolve_builder_spawn(0)
assert(not spawn and reason=="mode_spawn_marker_missing:"..missing,"missing player marker cannot use ordinary/legacy coordinates")
markers[missing]=saved;regions.init()
GetMapName=function() return "wrong_map" end
assert(select(2,context.resolve_builder_spawn(0))=="mode_spawn_map_mismatch:cold")
GetMapName=function() return "template_map" end
package.loaded["config/grid_placement_config"]={cell_size=64,
    build_bounds={min_x=-64,max_x=64,min_y=-64,max_y=64}}
package.loaded["systems/wall_melee_contact"]={}
local targets=require("systems/wall_target_service")
DOTA_UNIT_TARGET_TEAM_BOTH,DOTA_UNIT_TARGET_HERO,DOTA_UNIT_TARGET_BASIC=3,1,2
DOTA_UNIT_TARGET_BUILDING,DOTA_UNIT_TARGET_FLAG_INVULNERABLE,FIND_ANY_ORDER=4,16,0
GetGroundHeight=function() return 128 end
GridNav.CanFindPath=function() return true end
local work=require("systems/builder_work_position_service")
for _,name in ipairs({"rich","cold","scourge"}) do
    mode=name;targets.reset();regions.init()
    local row=config.modes[name]
    local position=markers[row.player_markers[0]]:GetAbsOrigin()
    local wall={survival_building_id="wall",survival_grid_footprint={x=4,y=4}}
    function wall:IsNull() return false end
    function wall:IsAlive() return true end
    function wall:GetAbsOrigin() return position end
    assert(targets.register({building_id="wall",player_id=0,entindex=100,unit=wall}))
    assert(targets.preferred_wall(0)==100,"AI must accept a dedicated-mode wall outside ordinary-island bounds")
    position=Vector(0,10000,128)
    targets.register({building_id="wall",player_id=0,entindex=100,unit=wall})
    assert(not targets.preferred_wall(0),"AI cannot acquire a wall in another mode region")
    local spawn=assert(context.resolve_builder_spawn(0))
    local caster={survival_builder_id="default_builder",survival_player_id=0}
    function caster:IsNull() return false end
    function caster:IsAlive() return true end
    function caster:GetAbsOrigin() return spawn.position end
    function caster:GetTeamNumber() return 2 end
    function caster:GetHullRadius() return 0 end
    FindUnitsInRadius=function() return {caster} end
    local point=assert(work.find(caster,{footprint={x=2,y=2},hull_radius=48},spawn.position))
    assert(regions.validate_position(0,point),"construction/repair work points use the local court instead of ordinary bounds")
end
mode="pure";regions.init()
assert(regions.validate_position(0,nil) and regions.validate_building_footprint(nil),"normal/pure policy remains untouched")
assert(not spawns.active())
print("MODE_SPAWN_REGIONS_PASS: 3 dedicated modes x4 owners, connected terrain, exact player/central monster markers, no normal fallbacks, guard/build/hero destinations, cached routes and missing-marker safety")
