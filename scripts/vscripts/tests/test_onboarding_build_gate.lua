-- Exercise the new gate through the real construction fixture and event bus.
-- The fixture first proves existing construction behavior is unchanged when
-- no onboarding handler has been registered.
dofile("scripts/vscripts/tests/test_builder_yield_construction.lua")
local bus,events=require("core/event_bus"),require("core/events")
local builder=assert(EntIndexToHScript(1))
local calls,deny,last=0,true,nil
bus.handle_request("onboarding.build_allowed.request",function(payload)
    calls=calls+1;last=payload
    if deny then return {ok=false,error="tutorial_position_rejected"} end
    return nil
end)
local function check(position)
    local result,error=bus.request(events.BUILD_CAN_PLACE_REQUEST,{
        player_id=0,caster=builder,building_id="main_city",position=position})
    assert(not error,error)
    return result
end
local result=check(Vector(510,511,128))
assert(result and not result.ok and result.error=="tutorial_position_rejected")
assert(calls==1 and last.player_id==0 and last.building_id=="main_city"
    and last.position.x==512 and last.position.y==512,
    "guide validates authenticated ownership and the same snapped center as construction")
assert(not builder.survival_build_task,"a denied preview creates no travel task")
result=check(Vector(100000,100000,128))
assert(result and not result.ok and calls==1,"ordinary illegal terrain must be rejected before the guide")
deny=false
result=check(Vector(510,511,128))
assert(result and result.ok and calls==2,"inactive guide preserves existing legal placement")
print("ONBOARDING_BUILD_GATE_PASS: real resource/grid checks precede snapped guide gate; denial and inactive paths preserved")
