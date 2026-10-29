-- Reuse the production wave-system integration fixture, stopping before its
-- independent settlement/population cases. No production callbacks are mocked.
SURVIVAL_WAVE_POPULATION_FIXTURE=function(f)
    local config=require("config/mode_spawn_config").modes.cold
    local physical,cities={},{}
    local spawns={{9600,14080},{14464,11264},{9856,8448},{14208,5632}}
    for id=0,3 do
        local b=config.player_bounds[id]
        local p=Vector((b.min_x+b.max_x)/2,(b.min_y+b.max_y)/2,128)
        physical[config.player_markers[id]]={IsNull=function() return false end,GetAbsOrigin=function() return p end}
        local a=spawns[id+1];local point=Vector(a[1],a[2],128)
        physical[config.monster_markers[id]]={IsNull=function() return false end,GetAbsOrigin=function() return point end}
    end
    GetMapName=function() return "template_map" end
    Entities.FindByName=function(_,_,name) return physical[name] end
    GridNav={IsTraversable=function() return true end,IsBlocked=function() return false end,
        CanFindPath=function() return true end}
    local city_reads=0
    package.loaded["systems/building_system"]={main_city_for_player=function(id)
        city_reads=city_reads+1;return cities[id]
    end}
    f.restart(false,true,{0,1,2,3},"cold")
    f.prepare_lanes()
    local channels=f.upvalue("wave_channels")
    for id=0,3 do assert(channels[id].route_id==id) end
    for id=0,3 do
        cities[id]=physical[config.player_markers[2]]
        f.bus.emit(f.events.BUILDING_CREATED,{building_id="main_city",player_id=id,entindex=200+id})
    end
    for id=0,3 do assert(channels[id].route_id==2 and channels[id].player_id==id) end
    local reads=city_reads
    f.bus.emit(f.events.BUILDING_CHANGED,{building_id="main_city",player_id=1,entindex=201,stats_only=true})
    assert(city_reads==reads,"stat-only city refreshes must not rescan bases or routes")
    cities[1]=physical[config.player_markers[0]]
    f.bus.emit(f.events.BUILDING_CHANGED,{building_id="main_city",player_id=1,entindex=201})
    assert(channels[1].route_id==0 and channels[0].route_id==2)
    cities[1]=nil
    f.bus.emit(f.events.BUILDING_DESTROYED,{building_id="main_city",player_id=1,entindex=201})
    assert(channels[1].route_id==1)
end
dofile("scripts/vscripts/tests/test_wave_population_endgame.lua")
SURVIVAL_WAVE_POPULATION_FIXTURE=nil
print("COLD_CITY_EVENTS_PASS: actual wave-system init/event bus refresh on city create/move/destroy; four owner channels retained")
