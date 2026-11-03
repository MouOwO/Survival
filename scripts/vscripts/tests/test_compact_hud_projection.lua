package.path="scripts/vscripts/?.lua;"..package.path
local lookup=dofile("scripts/vscripts/config/generated/ui_static_catalog_lookup.lua")
local projector=require("ui/compact_hud_projection")
local wire=require("ui/compact_wire")
local schema=assert(wire.compile_lookup(lookup,1))
local fixture={schema_version=2,player_id=0,team=2,server_time=125.91,
    resources={wood=9007199254740991,gold=4294967297,population=3,max_population=40},
    city_level=3,worker_count=8,shop_unlocked=1,research_unlocked=0,advanced_researcher_unlocked=1,
    wave={current_wave=3,total_waves=30,planned=200,pending=120,spawned=80,alive=15,killed=65,
        failed_spawn=0,alive_limit=100,overflow_grace_seconds=30,countdown_deadline=149.12345,
        overflow_deadline=0,challenge_deadline=0,status="countdown",game_mode="standard",difficulty_id="N3",
        difficulty_selected=true,boss_alive=false,early_final_used=false,victory_settled=false,
        defeat_settled=false,post_clear_frozen=false,overflow_active=false,player_defeated=false,
        defeat_reason="",challenge_saving=0,challenge_player_finished=0,challenge_ended=0}}
local state,operations=assert(projector.new(lookup).initialize(fixture))
local F=lookup.field_by_name
local values={};for _,op in ipairs(operations)do values[op.field]=op.value end
assert(values[F.wood]==4294967295 and values[F.wood_hi]==2097151)
assert(values[F.gold]==1 and values[F.gold_hi]==1 and values[F.countdown_deadline_ms]==149124)
assert(values[F.wave_phase]==5 and values[F.wave_game_mode]==1 and values[F.wave_difficulty]==3)
local full=assert(wire.encode(schema,{schema=1,schema_sha256=lookup.sha256,session=1,epoch=1,view=2},1,operations,{full=true}))
local max=0;for _,packet in ipairs(full)do max=math.max(max,#packet.d+25)end;assert(max<=50)
for index=1,1000 do
    fixture.server_time=125.91+index;fixture.wave.timer=30-index
    local ops,metrics=assert(state.update(fixture));assert(#ops==0 and metrics.catalogue_rows==0)
end
fixture.resources.wood=32
local delta=assert(state.update(fixture));assert(#delta==2,"only low/high resource words changed")
fixture.wave.defeat_reason="wall_destroyed";fixture.wave.player_defeated=true
delta=assert(state.update(fixture));assert(#delta==2)
fixture.wave.defeat_reason="";delta=assert(state.update(fixture));assert(#delta==1 and delta[1].remove)
fixture.wave.game_mode="bad_mode";assert(not state.update(fixture),"unknown enum never guesses another mode")
fixture.wave.game_mode="standard";fixture.resources.wood=0.1
assert(not state.update(fixture),"bad count never silently changes authority/precision")
if os.getenv("COMPACT_HUD_FIXTURE")=="1"then
    fixture.resources.wood=9007199254740991;fixture.wave.defeat_reason="";fixture.wave.player_defeated=false
    local _,ops=assert(projector.new(lookup).initialize(fixture))
    print(require("core/json_encoder").encode({snapshot=fixture,operations=ops,schema_sha256=lookup.sha256}))
else print("COMPACT_HUD_PROJECTION_PASS: real schema, safe integers, deadline only,1000 clock changes0ops,2-field resource delta, removals, invalid enums rejected; max native calibrated="..max)end
