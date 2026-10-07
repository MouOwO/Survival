package.path = "scripts/vscripts/?.lua;" .. package.path
local bus, events = require("core/event_bus"), require("core/events")
local tick
package.loaded["core/scheduler"] = {every=function(_, callback) tick=callback end}
local profiles = {
    [0]={mode="pure", save={permanent_effects={tower_health_regen_per_second=5}}},
    [1]={mode="pure", save={permanent_effects={tower_health_regen_per_second=10}}},
}
package.loaded["systems/player_profile_service"] = {get_profile=function(id) return profiles[id] end}
GameRules = {GetGameTime=function() return 10 end}
Entities = {FindAllByClassname=function() error("world scans forbidden in tower healing") end}
local errors, old_print = {}, print
print = function(message)
    if tostring(message):find("[EventBus] handler error",1,true) then errors[#errors+1]=message end
end
local all, queries = {}, 0
local function unit(owner, health)
    local result={health=health or 50, writes=0, owner=owner}
    function result:IsNull() return self.removed == true end
    function result:IsAlive() return self.dead ~= true end
    function result:GetHealth() return self.health end
    function result:GetMaxHealth() return 100 end
    function result:SetHealth(value) self.writes=self.writes+1;self.health=value end
    all[#all+1]={unit=result, player_id=owner, building_id="arrow_tower"}
    return result
end
local own = {}
for i=1,100 do own[i]=unit(0) end
local teammate, full, near_full = unit(1), unit(0,100), unit(0,99)
local dead, removed, destroyed = unit(0), unit(0), unit(0)
dead.dead, removed.removed, destroyed.survival_building_destroyed = true, true, true
bus.handle_request(events.BUILDING_LIST_REQUEST,function(payload)
    assert(payload.handles_only and payload.building_id=="arrow_tower")
    queries=queries+1
    -- Even a stale/malformed response must not heal a teammate/dead unit.
    return {ok=true,buildings=all}
end)
local rewards=require("systems/permanent_reward_effect_service")
rewards.init()
bus.emit(events.PLAYER_PROFILE_CHANGED,{player_id=0})
assert(tick())
for _, tower in ipairs(own) do assert(tower.health==55 and tower.writes==1) end
assert(teammate.health==50 and full.writes==0 and near_full.health==100)
assert(dead.writes==0 and removed.writes==0 and destroyed.writes==0 and queries==1)
bus.emit(events.PLAYER_PROFILE_CHANGED,{player_id=1})
assert(tick())
assert(teammate.health==60 and own[1].health==60 and queries==3)
local scopes = {}
bus.subscribe(events.PERMANENT_REWARD_EFFECTS_CHANGED,function(payload)
    if payload.reason=="gameplay_stats_tower_attack_growth"
        or payload.reason=="tower_actual_damage_growth"
        or payload.reason=="star_blessing_tower_attack_per_second" then
        assert(payload.changed_section=="tower", "tower growth must not refresh unrelated systems")
        scopes[payload.reason]=true
    end
end)
profiles[0].save.permanent_effects.tower_attack_per_second=2
profiles[0].save.permanent_effects.tower_basic_attack_growth=3
profiles[0].save.permanent_effects.tower_damage_attack_growth=4
bus.emit(events.PLAYER_PROFILE_CHANGED,{player_id=0})
own[1].survival_player_id=0
bus.emit(events.TOWER_ATTACK_LANDED,{tower=own[1]})
bus.emit("commerce.tower_damage",{tower=own[1],damage=100})
assert(tick() and queries==5)
assert(scopes.gameplay_stats_tower_attack_growth and scopes.tower_actual_damage_growth
    and scopes.star_blessing_tower_attack_per_second)
require("systems/gameplay_phase_guard").set_post_clear_frozen(true)
assert(tick() and queries==5, "frozen phase performs no healing queries")
require("systems/gameplay_phase_guard").reset()
profiles[0].save.permanent_effects.tower_health_regen_per_second=0
profiles[1].save.permanent_effects.tower_health_regen_per_second=0
bus.emit(events.PLAYER_PROFILE_CHANGED,{player_id=0})
bus.emit(events.PLAYER_PROFILE_CHANGED,{player_id=1})
assert(tick() and queries==5, "zero regen performs no building enumeration")
assert(#errors==0,table.concat(errors,"\n"))
print=old_print
print("TOWER_REGEN_REGISTRY_PASS: 100 towers, zero world scans, same-team owner isolation, scoped combat growth, full HP/death/removal/clamping/freeze/zero regen")
