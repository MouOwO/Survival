-- Real HUD projector and real difficulty catalogue, synthetic engine/account.
-- Byte counts below are JSON measurements; native packet sizes/FPS are not.
package.path="scripts/vscripts/?.lua;"..package.path
package.loaded["core/test_access_policy"]={enabled=function()return false end}
local bus=require("core/event_bus")
local events=require("core/events")
package.loaded["ui/boss_warning_ui_service"]={init=function()end}
GameRules={GetGameTime=function()return 123 end}
local queries=0
bus.handle_request(events.RESOURCE_GET_REQUEST,function(p)
    return {player_id=p.player_id,team=2,wood=100,gold=10,population=2,max_population=10}
end)
bus.handle_request(events.BUILDING_LIST_REQUEST,function()return {buildings={}}end)
bus.handle_request(events.WAVE_STATE_GET_REQUEST,function(p)
    queries=queries+1
    return {ok=true,player_id=p.player_id,alive=11,overflow_active=false}
end)
require("ui/ui_projection").init()
local choices=require("config/difficulty_config").client_options()
assert(#choices>=10,"use actual released difficulty definitions")
local wave={current_wave=3,total_waves=30,status="countdown",timer=26,
    countdown_deadline=149,difficulty_id="N3",difficulty_selected=true,
    difficulty_options=choices,hud_player_id=0}
bus.emit(events.WAVE_CHANGED,wave)
local encode=require("core/json_encoder").encode
local snapshot=bus.request("ui.projection.build_snapshot",{player_id=0,team=2})
assert(snapshot.wave.difficulty_options==nil,"catalogue must never ride on recurring HUD messages")
assert(snapshot.wave.countdown_deadline==149 and snapshot.wave.difficulty_id=="N3")
assert(snapshot.wave.alive==11 and snapshot.wave.player_id==0)
assert(wave.difficulty_options==choices and #choices>=10,"authoritative catalogue must remain intact")
local thin=#encode(snapshot)
snapshot.wave.difficulty_options=choices
local previous=#encode(snapshot)
assert(previous>thin+1500,"real catalogue explains a substantial recurring payload")
local changed=0
for n=1,1000 do
    bus.emit(events.RESOURCE_CHANGED,{player_id=0,team=2,wood=n,gold=10,population=2,max_population=10})
    local next=bus.request("ui.projection.build_snapshot",{player_id=0,team=2})
    assert(next.wave.difficulty_options==nil and next.resources.wood==n)
    changed=changed+1
end
assert(queries==1001)
print(encode({status="REAL_PRIVATE_HUD_CATALOG_EXCLUDED",catalogue_rows=#choices,
    before_json_bytes=previous,after_json_bytes=thin,changed_projections=changed,
    catalogue_serializations_in_1000_updates=0,personal_wave_queries=queries,
    native_packet_bytes_measured=false,native_fps_measured=false}))
