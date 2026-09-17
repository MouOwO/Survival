package.path="scripts/vscripts/?.lua;"..package.path
local bus=require("core/event_bus")
local events=require("core/events")
local guard=require("systems/gameplay_phase_guard")
local profile={revision=1,save={gameplay_stats={hero_initial_attack=100,wall_armor=5}}}
package.loaded["systems/player_profile_service"]={get_profile=function() return profile end}
package.loaded["core/scheduler"]={every=function() end}
local effects=require("systems/permanent_reward_effect_service")
effects.init()
bus.emit(events.PLAYER_PROFILE_CHANGED,{player_id=0})
assert(effects.value(0,"hero_initial_attack")==100)
guard.set_post_clear_frozen(true)
profile.save.gameplay_stats.wall_armor=50
bus.emit(events.PLAYER_PROFILE_CHANGED,{player_id=0,reason="archive_challenge"})
assert(effects.value(0,"wall_armor")==5)
profile.save.archive={social_last_draw={id="draw1",effects={hero_initial_attack=10}}}
bus.emit(events.PLAYER_PROFILE_CHANGED,{player_id=0,reason="archive_social_draw"})
assert(effects.value(0,"hero_initial_attack")==110)
assert(effects.value(0,"wall_armor")==5,"only the draw is applied")
bus.emit(events.PLAYER_PROFILE_CHANGED,{player_id=0,reason="archive_social_draw"})
assert(effects.value(0,"hero_initial_attack")==110,"repeated refresh cannot double apply")
profile.save.archive.social_last_draw={id="draw2",effects={hero_initial_attack=10}}
bus.emit(events.PLAYER_PROFILE_CHANGED,{player_id=0,reason="archive_social_draw"})
assert(effects.value(0,"hero_initial_attack")==120)
print("ARCHIVE_LIVE_EFFECTS_PASS")
local clock=1000000
require("systems/archive_calendar").set_clock(function()return clock end)
profile.save.archive.boss_kills=5
profile.entitlements={archive_pass={active=true,expires_at=clock+10}}
bus.emit(events.PLAYER_PROFILE_CHANGED,{player_id=0,reason="archive_boss_refresh"})
assert(effects.value(0,"wall_initial_health")==500)
clock=clock+10
bus.emit(events.PLAYER_PROFILE_CHANGED,{player_id=0,reason="archive_boss_refresh"})
assert(effects.value(0,"wall_initial_health")==0)
assert(effects.value(0,"hero_initial_attack")==120)
profile.save.archive.boss_kills=10
bus.emit(events.PLAYER_PROFILE_CHANGED,{player_id=0,reason="archive_boss_kill"})
assert(effects.value(0,"wall_initial_health")==500)
print("BOSS_PASS_EFFECT_EXPIRY_PASS")
guard.set_post_clear_frozen(false)
profile.save.archive.boss_kills=0
profile.save.gameplay_stats.map_level=2
bus.emit(events.PLAYER_PROFILE_CHANGED,{player_id=0,reason="archive_online_checkpoint"})
assert(effects.value(0,"wall_initial_health")==200,"map level grants flat initial wall health")
assert(effects.value(0,"wall_health_regen_per_second")==10,"map level grants regeneration")
assert(effects.value(0,"wall_health_per_second")==0,"regeneration must not permanently grow max health")
guard.set_post_clear_frozen(true)
profile.save.gameplay_stats.map_level=3
bus.emit(events.PLAYER_PROFILE_CHANGED,{player_id=0,reason="archive_online_checkpoint"})
assert(effects.value(0,"wall_initial_health")==200,"post-clear automatic growth stays frozen")
print("MAP_LEVEL_EFFECTS_PASS")
