package.path = "scripts/vscripts/?.lua;" .. package.path
local bus, events = require("core/event_bus"), require("core/events")
local scheduler = require("core/scheduler")
local calendar = require("systems/archive_calendar")
local wall_clock, game_clock = 172800, 100
calendar.set_clock(function() return wall_clock end)
local day = tostring(calendar.day())
local noop = function() end
local daily_rows = {
    {limit_id="shadow",storage_key="shadow_count",display_name="虚空",daily_limit=80,pass_daily_limit=80,implemented=true},
    {limit_id="endless",storage_key="endless_count",display_name="无尽",daily_limit=50000,pass_daily_limit=50000,implemented=true},
}
package.loaded["config/generated/archive_daily_limits"] = {rows=daily_rows,by_id={shadow=daily_rows[1],endless=daily_rows[2]}}
local profiles = {
    [0]={save={archive={daily={[day]={shadow_count=0,endless_count=0}}}}},
    [1]={save={archive={daily={[day]={shadow_count=0,endless_count=0}}}}},
}
local quota_reads=0
package.loaded["systems/player_profile_service"] = {get_account_profile=function(id) quota_reads=quota_reads+1;return profiles[id] end}
local definition = {challenge_id="shadow_1",building_id=1,enabled=true,min_difficulty=1,
    reward_kind="shadow",reward_key="n1",description="test",cooldown_seconds=0}
package.loaded["config/generated/archive_challenge_definitions"] = {rows={definition},by_id={shadow_1=definition}}
package.loaded["config/generated/archive_challenge_stats"] = {by_id={shadow_1_N1={enabled=true}}}
local endless_action={action_id="endless",ability_name="ability_archive_endless",building_id=2,
    slot_order=1,display_name="quota fixture",description="quota fixture",min_difficulty=1,enabled=true}
package.loaded["config/generated/archive_challenge_actions"]={rows={endless_action},by_id={endless=endless_action}}
package.loaded["config/generated/archive_challenge_rules"] = {by_id={default={building_unlock_difficulty=1,
    building_spacing=240,building_offset_y=360,building_model="test.vmdl",building_model_scale=1,phase_duration_seconds=1800}}}
package.loaded["systems/player_context_service"] = {register_unit=function(id,u) u.owner=id end,
    unregister_unit=noop,owner_player_id=function(u) return u.owner end}
package.loaded["systems/archive_service"] = {has_pending=function() return false end}
package.loaded["systems/archive_cooperative_reward_service"] = {init=noop,begin=function() return true end,
    matches_session=function() return true end,record_challenge=noop,has_pending=function() return false end}
local endless_starts, spawned, serial = 0, 0, 0
package.loaded["systems/archive_endless_service"] = {init=noop,is_running=function() return false end,cancel=noop,
    start=function() endless_starts=endless_starts+1;return true end}
package.loaded["systems/archive_endless_config"] = {group=function() return {} end}
package.loaded["systems/monster_hero_visual_service"] = {clear=noop,on_death=noop}
Vector=function(x,y,z) return {x=x,y=y,z=z} end
local function unit(name,position)
    serial=serial+1
    local u={id=serial,name=name,position=position,abilities={},alive=true}
    function u:IsNull() return self.removed==true end
    function u:IsAlive() return self.alive end
    function u:entindex() return self.id end
    function u:GetAbsOrigin() return self.position end
    function u:FindAbilityByName(n) return self.abilities[n] end
    function u:AddAbility(n)
        local a={IsNull=function() return false end,SetLevel=noop,StartCooldown=noop,
            GetCaster=function() return u end,GetAbilityName=function() return n end}
        function a:SetActivated(value) self.activated=value end
        function a:IsActivated() return self.activated end
        self.abilities[n]=a;return a
    end
    u.SetModel=noop;u.SetOriginalModel=noop;u.SetModelScale=noop;u.AddNewModifier=noop
    function u:SetControllableByPlayer(id) self.owner=id end
    return u
end
package.loaded["systems/wave_system"] = {
    get_player_spawn_marker=function() return {IsNull=function() return false end,GetAbsOrigin=function() return Vector(0,0,0) end} end,
    spawn_challenge_monster=function() spawned=spawned+1;return unit("boss",Vector(0,0,0)) end}
GameRules={GetGameTime=function() return game_clock end,SetGameWinner=noop}
CreateUnitByName=unit;Entities=nil;CustomNetTables=nil;UTIL_Remove=function(u) u.removed=true end
bus.reset();scheduler.clear();require("systems/gameplay_phase_guard").reset()
local service=require("systems/archive_challenge_service");service.init()
assert(service.begin({difficulty_id="N1",player_ids={0,1}}).keep_running)
local state=service._test.players()[0]
local hub,other=state.hubs[1],service._test.players()[1].hubs[1]
local ability=hub:FindAbilityByName("ability_archive_shadow_1")
assert(ability.activated and service.ability_runtime(hub,"ability_archive_shadow_1").available==1)
profiles[0].save.archive.daily[day].shadow_count=80
bus.emit(events.PLAYER_PROFILE_CHANGED,{player_id=0})
assert(ability.activated==false,"settled profile events immediately disable the native ability")
local runtime=service.ability_runtime(hub,"ability_archive_shadow_1")
assert(runtime.available==0 and runtime.prerequisite_met==0 and runtime.status_text=="今日奖励已达上限")
assert(runtime.daily_remaining==0 and runtime.daily_limit==80)
assert(service.ability_runtime(other,"ability_archive_shadow_1").available==1,"quotas belong to each account")
local ok,reason=service.summon(hub,"shadow_1",ability)
assert(not ok and reason=="今日奖励已达上限" and spawned==0,"direct/stale requests cannot spawn a capped challenge")
assert(not state.used.shadow_1,"a rejected request does not consume the per-match entry")
profiles[0].save.archive.daily[day].shadow_count=79
bus.emit(events.PLAYER_PROFILE_CHANGED,{player_id=0})
assert(ability.activated==true,"updated remaining quota restores the ability")
local endless_hub=state.hubs[2]
profiles[0].save.archive.daily[day].endless_count=50000
bus.emit(events.PLAYER_PROFILE_CHANGED,{player_id=0})
local endless=endless_hub:FindAbilityByName("ability_archive_endless")
assert(endless.activated==false)
ok,reason=service.start_endless(endless_hub,endless)
assert(not ok and reason=="今日奖励已达上限" and endless_starts==0)
profiles[0].save.archive.daily[day].shadow_count=80
bus.emit(events.PLAYER_PROFILE_CHANGED,{player_id=0})
local previous_reads=quota_reads
game_clock=105;scheduler.think()
assert(ability.activated==false and endless.activated==false,"same-day watch does not reset any quota")
assert(quota_reads==previous_reads,"the five-second watch does not republish unchanged daily permissions")
wall_clock=wall_clock+86400
game_clock=110;scheduler.think()
assert(ability.activated==true and endless.activated==true,
    "the server's day rollover restores native activation without a profile-change event")
assert(service.ability_runtime(hub,"ability_archive_shadow_1").daily_remaining==80)
assert(service.ability_runtime(state.hubs[3],"ability_archive_finish").available==1,"finish is always independent of reward quotas")
assert(service.finish(state.hubs[3]))
assert(service.finish(service._test.players()[1].hubs[3]))
assert(scheduler.task_count()==0,"finishing cancels the lightweight rollover watch")
bus.reset();service.init()
assert(service.begin({difficulty_id="N1",player_ids={0,1}}).keep_running)
assert(scheduler.task_count()>=2)
bus.reset();service.init()
assert(scheduler.task_count()==0,"init cancels any watch left by the previous session")
print("DAILY_CAP_ENTRY_GUARDS_PASS: authority refresh, engine grey state, direct summon/endless guard, per-account isolation and finish")
