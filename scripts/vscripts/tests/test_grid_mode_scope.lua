package.path = "scripts/vscripts/?.lua;" .. package.path

-- Exercise the real router, event bus and cooperative scheduler. Only engine
-- objects and terrain queries are fixtures; no router internals are exposed.
local listeners, sent, state = {}, {}, {}
local clock = 0
GameRules = {GetGameTime=function() return clock end}
Vector = function(x,y,z) return {x=x,y=y,z=z} end
PlayerResource = {
    IsValidPlayerID=function(_,id) return id==0 or id==1 end,
    GetPlayer=function(_,id) return id end,
}
local ordinary_bounds = {min_x=-4096,max_x=2048,min_y=1024,max_y=7168}
local display_bounds = {min_x=-16384,max_x=16384,min_y=-16384,max_y=16384}
package.loaded["config/grid_placement_config"] = {
    cell_size=64, footprint_subdivision=1, build_ground_height=384,
    build_bounds=ordinary_bounds, grid_display_bounds=display_bounds,
}
package.loaded["config/buildings_config"] = {
    house={id="house",display_name="House",footprint={x=2,y=2},levels={}},
}
package.loaded["config/generated/building_definitions"] = {
    rows={{building_id="house",builder_ability="ability_build_house"}},
}
package.loaded["systems/player_context_service"] = {is_defeated=function() return false end}
package.loaded["systems/grid_preview_model_service"] = {
    clear=function() state.model_clears=state.model_clears+1 end,
    clear_all=function() end,
}
package.loaded["systems/match_setup_service"] = {
    get_mode=function() return state.mode end,
    get_session_id=function() return state.match_session end,
}
local regions = {
    rich={min_x=140,max_x=151,min_y=100,max_y=113,position={z=128}},
    cold={min_x=188,max_x=199,min_y=120,max_y=133,position={z=256}},
    scourge={min_x=-200,max_x=-189,min_y=-12,max_y=1,position={z=-128}},
}
local cold_bounds={min_x=8448,max_x=15872,min_y=3584,max_y=15360}
package.loaded["systems/mode_spawn_service"]={config=function() return {bounds=cold_bounds} end}
package.loaded["systems/rich_region_service"] = {region=function(player_id)
    assert(player_id==0 or player_id==1)
    if state.region_pending then return nil,"mode_spawn_layout_pending" end
    return regions[state.mode]
end}
package.loaded["systems/grid_placement_system"] = {
    static_preview=function(options)
        assert(options.yield_after==128 and options.time_budget==0.002)
        state.static_steps=state.static_steps+1
        coroutine.yield()
        state.static_steps=state.static_steps+1
        return "ordinary-atlas"
    end,
    preview_area=function(options)
        assert(options.yield_after==128 and options.time_budget==0.002)
        local mode = state.mode
        state.area_calls[#state.area_calls+1]={mode=mode,cache=options.terrain_cache}
        state.area_steps=state.area_steps+1
        coroutine.yield(mode.."-partial")
        state.area_steps=state.area_steps+1
        coroutine.yield(mode.."-middle")
        state.area_steps=state.area_steps+1
        return mode.."-complete"
    end,
}
CustomGameEventManager = {
    RegisterListener=function(_,name,callback) listeners[name]=callback end,
    Send_ServerToPlayer=function(_,player_id,name,payload)
        local expected_scope=tostring(state.match_session)..":"..state.mode..":"..player_id
        assert(payload.grid_scope==expected_scope,"every reply belongs to the current match/mode/player")
        local version=payload.grid_scope_version
        assert(type(version)=="number" and version>=1 and version==math.floor(version),
            "every reply carries a positive integer scope version")
        local previous=state.sent_scopes[player_id]
        if previous then
            local expected=previous.version+(previous.scope~=expected_scope and 1 or 0)
            assert(version==expected,"scope versions advance once per observed scope change")
        end
        state.sent_scopes[player_id]={scope=expected_scope,version=version}
        sent[#sent+1]={player_id=player_id,name=name,payload=payload}
    end,
}

local bus=require("core/event_bus")
local events=require("core/events")
local scheduler=require("core/scheduler")
local router=require("ui/grid_placement_router")
local own={entindex=function() return 10 end,IsNull=function() return false end,
    GetTeamNumber=function() return 2 end}
local ability={entindex=function() return 20 end,IsNull=function() return false end,
    GetCaster=function() return own end,GetAbilityName=function() return "ability_build_house" end,
    GetLevel=function() return 1 end,IsActivated=function() return true end}
own.FindAbilityByName=function() return ability end
EntIndexToHScript=function(index) return ({[10]=own,[20]=ability})[index] end

local function fixture()
    scheduler.clear()
    bus.reset()
    listeners,sent={},{}
    clock=0
    state={mode="standard",match_session=41,region_pending=false,static_steps=0,
        area_steps=0,area_calls={},model_clears=0,sent_scopes={}}
    bus.handle_request(events.BUILDER_GET_REQUEST,function() return {ok=true,builder=own} end)
    bus.handle_request(events.BUILD_CAN_PLACE_REQUEST,function(payload)
        return {ok=true,grid={ok=true,world_position=payload.position,
            cells={{x=32,y=32,z=payload.position.z,ok=true}}}}
    end)
    router.init()
end
local function advance()
    clock=clock+0.06
    scheduler.think()
end
local function request_profiles(player_id)
    listeners.ui_grid_placement_profiles_request(nil,{PlayerID=player_id or 0})
end
local function message(name,after,player_id)
    for index=#sent,(after or 0)+1,-1 do
        local item=sent[index]
        if item.name==name and (player_id==nil or item.player_id==player_id) then return item.payload end
    end
    error("missing reply: "..name)
end
local function count(name,after)
    local result=0
    for index=(after or 0)+1,#sent do if sent[index].name==name then result=result+1 end end
    return result
end
local function builder_ready()
    bus.emit(events.BUILDER_READY,{player_id=0,builder=own})
end
local function assert_region(payload,mode)
    local region=regions[mode]
    local grid=assert(payload.static_grid,"ready layout supplies geometry")
    assert(payload.layout_ready==1 and #payload.profiles==1)
    assert(grid.height==region.position.z,"arena replaces ordinary construction Z")
    local expected=mode=="cold" and cold_bounds or {min_x=region.min_x*64,min_y=region.min_y*64,
        max_x=(region.max_x+1)*64,max_y=(region.max_y+1)*64}
    assert(grid.build_bounds.min_x==expected.min_x and grid.build_bounds.min_y==expected.min_y
        and grid.build_bounds.max_x==expected.max_x
        and grid.build_bounds.max_y==expected.max_y,"cold previews all shared courts; other arenas retain private bounds")
    assert(grid.bounds.min_x==display_bounds.min_x and grid.bounds.max_x==display_bounds.max_x,
        "global white-grid display extent remains separate from placement permission")
end
local function validate(request_id)
    listeners.ui_grid_placement_validate(nil,{PlayerID=0,session_id=1,request_id=request_id,
        ability_name="ability_build_house",entindex=10,ability_entindex=20,x=128,y=256,z=384})
end

-- Every dedicated arena replaces geometry preloaded before mode selection.
for _,mode in ipairs({"rich","cold","scourge"}) do
    fixture()
    request_profiles()
    local ordinary=message("ui_grid_placement_profiles")
    assert(ordinary.layout_ready==1 and ordinary.static_grid.height==384
        and ordinary.static_grid.build_bounds.min_x==ordinary_bounds.min_x)
    advance();advance()
    assert(message("ui_grid_placement_static_area").area=="ordinary-atlas")
    local before=#sent
    state.mode=mode
    builder_ready()
    local arena=message("ui_grid_placement_profiles",before)
    assert_region(arena,mode)
    assert(arena.grid_scope~=ordinary.grid_scope
        and arena.grid_scope_version==ordinary.grid_scope_version+1)
    request_profiles()
    assert_region(message("ui_grid_placement_profiles",before),mode)
    assert(count("ui_grid_placement_static_area",before)==0,"ordinary atlas is never replayed into an arena")
end

-- A late native marker must remain visibly pending, without ordinary fallback.
fixture()
request_profiles()
state.mode="cold";state.region_pending=true
local before=#sent
builder_ready()
local pending=message("ui_grid_placement_profiles",before)
assert(pending.layout_ready==0 and #pending.profiles==0 and pending.static_grid==nil
    and pending.error=="mode_spawn_layout_pending","missing arena markers cannot authorize the ordinary island")
request_profiles()
assert(message("ui_grid_placement_profiles",before).static_grid==nil)
state.region_pending=false
builder_ready()
local ready=message("ui_grid_placement_profiles",before)
assert_region(ready,"cold")
assert(ready.grid_scope==pending.grid_scope and ready.grid_scope_version==pending.grid_scope_version,
    "marker readiness alone does not invent a new match scope")

-- An in-flight ordinary scan is cancelled by arena readiness. The scope guard
-- also blocks it when mode changes before BUILDER_READY has arrived.
for _,emit_ready in ipairs({true,false}) do
    fixture()
    request_profiles()
    advance()
    assert(state.static_steps==1,"ordinary atlas scan genuinely started")
    state.mode="scourge"
    before=#sent
    if emit_ready then builder_ready() end
    advance();advance()
    assert(state.static_steps==1 and count("ui_grid_placement_static_area",before)==0,
        "in-flight ordinary atlas cannot complete or broadcast into an arena")
end

-- Ordinary builders retain the independent preload and late join replay.
fixture()
request_profiles()
advance()
builder_ready()
advance()
assert(state.static_steps==2 and message("ui_grid_placement_static_area").area=="ordinary-atlas")
before=#sent
request_profiles(1)
assert(message("ui_grid_placement_static_area",before,1).area=="ordinary-atlas")

-- A background area cannot resume after its mode scope changes. A fresh scan
-- must use a new terrain cache, even before the arena's ready event arrives.
for _,emit_ready in ipairs({true,false}) do
    fixture()
    validate(1)
    assert(message("ui_grid_placement_validation").area=="standard-partial" and state.area_steps==1)
    local ordinary_cache=state.area_calls[1].cache
    before=#sent
    state.mode="cold"
    if emit_ready then builder_ready() end
    advance();advance()
    assert(state.area_steps==1 and count("ui_grid_placement_area",before)==0,
        "old-scope preview coroutine is not resumed or delivered")
    validate(2)
    local cold=message("ui_grid_placement_validation",before)
    assert(cold.area=="cold-partial" and cold.area_complete==0,
        "new arena cannot reuse an old partial or completed overlay")
    assert(state.area_calls[2].cache~=ordinary_cache,"terrain cache is isolated across mode scopes")
    advance();advance()
    local completed=message("ui_grid_placement_area",before)
    assert(completed.area=="cold-complete" and completed.complete==1
        and completed.grid_scope==cold.grid_scope,"current-scope background scan still completes normally")
end

print("GRID_MODE_SCOPE_PASS: three arena refreshes, pending layouts, atlas isolation, scoped asynchronous previews")
