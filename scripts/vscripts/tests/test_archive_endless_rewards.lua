package.path = "scripts/vscripts/?.lua;" .. package.path
local definitions = require("config/generated/archive_endless_achievements")
local stats = require("config/generated/player_gameplay_stats")
local rewards = require("systems/archive_endless_rewards")
local settlement = require("systems/archive_settlement")
assert(#definitions.rows == 82)
local function profile()
    local p = {save={archive={completed={}},gameplay_stats={}}}
    for _, row in ipairs(stats.rows) do p.save.gameplay_stats[row.field_id] = row.default_value end
    return p
end
local function apply(p, id)
    local result = settlement.settle(p,{kind="endless_reconcile",id=id},false)
    assert(result.ok)
    p.save.archive,p.save.gameplay_stats=result.archive,result.gameplay_stats
    return result
end
-- Every screenshot condition is strict: threshold does not unlock, threshold+1 does.
for index = 51,82 do
    local item=definitions.rows[index]
    assert(item.achievement_id=="endless_"..index and item.required_score==nil)
    assert(stats.by_id[item.effect_ids[1]],item.effect_ids[1])
    local p=profile()
    for _, other in ipairs(definitions.rows) do
        if other~=item then p.save.archive.completed[other.achievement_id]=true end
    end
    p.save.archive.endless_best_wave=item.required_wave-1
    assert(not rewards.needs_reconcile(p.save.archive))
    local field=item.effect_ids[1]
    local before=p.save.gameplay_stats[field]
    apply(p,"below:"..index)
    assert(not p.save.archive.completed[item.achievement_id])
    p.save.archive.endless_best_wave=item.required_wave
    assert(rewards.needs_reconcile(p.save.archive))
    apply(p,"at:"..index)
    assert(p.save.archive.completed[item.achievement_id])
    assert(p.save.gameplay_stats[field]==before+tonumber(item.effect_values[1]))
    local after=p.save.gameplay_stats[field]
    assert(apply(p,"at:"..index).duplicate)
    apply(p,"new_session:"..index)
    assert(p.save.gameplay_stats[field]==after)
    local view=rewards.rows(p.save.archive)[index]
    assert(view.count==item.required_wave and view.target==item.required_wave)
    assert(view.progress_kind=="wave" and view.unlock_condition:find(tostring(item.required_wave-1),1,true))
end
-- Existing high floor, zero score: backfill all 32 new entries, no score rewards.
local old=profile();old.save.archive.endless_best_wave=461
apply(old,"old_archive")
for i=1,82 do assert((old.save.archive.completed["endless_"..i]==true)==(i>=51)) end
local totals={lumberjack_efficiency=1,lumberjack_attack_speed_bonus_pct=5,
 hero_attribute_growth=2,hero_damage_wood_flat=2,hero_attribute_bonus_pct=52,
 hero_attack_armor_reduction=36,gold_mine_yield_bonus_pct=20,wall_health_bonus_pct=42,
 tower_final_damage_bonus_pct=12,hero_final_damage_bonus_pct=54,training_room_income_bonus_pct=20,
 tower_attack_bonus_pct=24,tower_critical_chance_pct=5,tower_critical_damage_bonus_pct=10,
 hero_critical_chance_pct=5,hero_critical_damage_bonus_pct=10,wall_damage_reduction_pct=5,
 hero_attributes_per_damage=13,hero_attack_bonus_pct=15,hero_damage_bonus_flat=20}
for field,delta in pairs(totals) do
 assert(old.save.gameplay_stats[field]==stats.by_id[field].default_value+delta,field)
end
assert(not rewards.needs_reconcile(old.save.archive))
-- High accumulated score alone must never unlock a floor achievement.
local score=profile();score.save.archive.endless_score=1e10
apply(score,"score_only")
for i=51,82 do assert(not score.save.archive.completed["endless_"..i]) end
assert(rewards.rows(score.save.archive)[1].progress_kind=="score")
print("ARCHIVE_ENDLESS_FLOORS_PASS: 32 strict boundaries, effect totals, saved-floor backfill, score isolation, dedup")

-- Exercise real gameplay projection and hero damage callbacks with awarded stats.
local bus=require("core/event_bus")
local events=require("core/events")
require("systems/gameplay_phase_guard").reset()
package.loaded["core/scheduler"]={every=function() end}
old.mode="standard";old.revision=1;old.entitlements={};old.save.permanent_effects={}
package.loaded["systems/player_profile_service"]={get_profile=function(id) return id==0 and old or nil end}
local effects=require("systems/permanent_reward_effect_service")
effects.init()
bus.emit(events.PLAYER_PROFILE_CHANGED,{player_id=0,reason="archive_endless_reconcile"})
local function active() return bus.request(events.PERMANENT_REWARD_EFFECTS_GET_REQUEST,{player_id=0}).totals end
for field in pairs(totals) do assert(active()[field]==old.save.gameplay_stats[field],"runtime:"..field) end
local wood=0
bus.handle_request(events.RESOURCE_ADD_REQUEST,function(payload)
 assert(payload.player_id==0);wood=wood+(payload.wood or 0);return {ok=true}
end)
local hero={}
local before=active().hero_all_attributes_flat or 0
bus.emit(events.COMBAT_DAMAGE_RESOLVED,{player_id=0,owner_hero=hero,attacker=hero})
assert(wood==2 and active().hero_all_attributes_flat==before+13)
bus.emit(events.COMBAT_DAMAGE_RESOLVED,{player_id=0,owner_hero=hero,attacker={}})
assert(wood==2 and active().hero_all_attributes_flat==before+13,"other attackers must not trigger hero reward")
print("ARCHIVE_ENDLESS_RUNTIME_PASS: all effect fields projected, real damage grants wood/attributes, owner-only")
