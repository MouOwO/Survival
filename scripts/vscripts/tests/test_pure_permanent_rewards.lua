package.path = "scripts/vscripts/?.lua;" .. package.path
local bus = require("core/event_bus")
local events = require("core/events")
local guard = require("systems/gameplay_phase_guard")
package.loaded["core/scheduler"] = { every = function() end }
local profile = { mode = "pure", revision = 1, entitlements = {}, save = {
    gameplay_stats = {}, permanent_effects = {}, archive = {boss_kills=10000}, match_boss_effects = {} } }
package.loaded["systems/player_profile_service"] = { get_profile = function() return profile end }
local effects = require("systems/permanent_reward_effect_service")
effects.init()
local function changed(reason)
    bus.emit(events.PLAYER_PROFILE_CHANGED, {player_id=0, reason=reason})
end
local function totals()
    return bus.request(events.PERMANENT_REWARD_EFFECTS_GET_REQUEST, {player_id=0}).totals
end
changed("pure_login")
assert((totals().wall_initial_health or 0) == 0, "pure must never rederive old boss awards")
profile.save.archive.boss_kills = 1
profile.save.match_boss_effects = {wall_initial_health=500}
profile.save.permanent_effects = {cooldown_percent=-2}
changed("archive_boss_kill")
assert(totals().wall_initial_health == 500, "crossing 9 to 10 account kills grants the new threshold")
assert(totals().cooldown_percent == -2, "signed newly earned effects remain intact")
changed("archive_online_checkpoint")
assert(totals().wall_initial_health == 500, "refresh must replace rather than stack the same threshold")

guard.set_post_clear_frozen(true)
profile.save.archive.social_last_draw = {id="draw_one", effects={hero_basic_attack=2}}
changed("archive_social_draw")
assert(totals().hero_basic_attack == 2 and totals().wall_initial_health == 500)
changed("archive_social_draw")
assert(totals().hero_basic_attack == 2, "replaying the committed draw does not apply its effects twice")
profile.save.archive.social_last_draw = {id="draw_two", effects={hero_basic_attack=2}}
changed("archive_social_draw")
assert(totals().hero_basic_attack == 4, "a second draw with the same effect remains a distinct reward")
guard.reset()
profile.mode = "standard"
profile.save.archive.boss_kills = 10
profile.save.match_boss_effects = {wall_initial_health=999999}
changed("standard_load")
assert(totals().wall_initial_health == 500, "standard mode keeps native full-account boss projection")
print("PURE_PERMANENT_REWARDS_PASS: no old boss effects, new thresholds, signed effects, frozen social rewards and replay")

profile.save.gameplay_stats={tower_attack_flat=7,tower_basic_attack_growth=2,tower_damage_attack_growth=0.5}
changed("growth_scoping_test")
local seen,global=0,0
local attacker={survival_player_id=0}
local idle
idle={survival_player_id=0}
bus.subscribe("tower.personal_attack_changed",function(p)
 seen=seen+1;assert(p.tower==attacker)
 assert(p.tower.survival_tower_personal_attack_growth==seen*2.5)
end)
bus.subscribe(events.PERMANENT_REWARD_EFFECTS_CHANGED,function() global=global+1 end)
local start=totals().tower_attack_flat or 0
for i=1,100 do bus.emit(events.TOWER_ATTACK_LANDED,{tower=attacker}) end
assert(seen==100 and global==0 and totals().tower_attack_flat==start)
assert(idle.survival_tower_personal_attack_growth==nil)
print("PERSONAL_TOWER_GROWTH_PASS: 100 hits grow attacker only; no shared pool/global notifications")
