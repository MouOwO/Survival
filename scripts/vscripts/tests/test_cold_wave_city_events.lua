-- Reuse the production wave-system integration fixture, stopping before its
-- independent settlement/population cases. No production callbacks are mocked.
SURVIVAL_WAVE_POPULATION_FIXTURE=function(f)
  for _,mode in ipairs({"cold","rich"}) do
    local config=require("config/mode_spawn_config").modes[mode]
    local physical,cities={},{}
    local spawns=mode=="cold" and {{9600,14080},{14464,11264},{9856,8448},{14208,5632}}
        or {{-2848,-9888},{-2656,-10080},{-2848,-10080},{-2656,-9888}}
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
    f.restart(false,true,{0,1,2,3},mode)
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
    if mode=="rich" then
        -- Real completed-wall registry callbacks drive cross-court routing,
        -- even when the owner keeps its original main city.
        local wall_position=physical[config.player_markers[3]]:GetAbsOrigin()
        local wall={survival_building_id="wall",survival_player_id=0}
        function wall:IsNull() return false end
        function wall:IsAlive() return true end
        function wall:entindex() return 500 end
        function wall:GetAbsOrigin() return wall_position end
        EntIndexToHScript=function(index) return index==500 and wall or nil end
        f.bus.emit(f.events.BUILDING_CREATED,{building_id="wall",player_id=0,entindex=500,unit=wall})
        assert(channels[0].route_id==3,"a completed rich wall overrides the old city court")
        local identity=channels[0]
        wall_position=physical[config.player_markers[0]]:GetAbsOrigin()
        f.bus.emit(f.events.BUILDING_CHANGED,{building_id="wall",player_id=0,entindex=500,unit=wall})
        assert(channels[0]==identity and channels[0].route_id==0,"a relocated wall retains its pending wave channel")
        f.bus.emit(f.events.BUILDING_DESTROYED,{building_id="wall",player_id=0,entindex=500,unit=wall})
        assert(channels[0].route_id==2,"wall destruction falls back to the owner's remaining main city")
    end
  end
end
dofile("scripts/vscripts/tests/test_wave_population_endgame.lua")
SURVIVAL_WAVE_POPULATION_FIXTURE=nil
print("SHARED_CITY_EVENTS_PASS: actual cold/rich wave-system city create/move/destroy; rich wall create/move/destroy and city fallback; owner channels retained")
