-- Real archive phase, cooperative dispatcher, eligibility/daily reducer and
-- runtime publisher. Native entities and the in-memory commit are boundaries.
package.path="scripts/vscripts/?.lua;"..package.path
package.loaded["core/test_access_policy"]={enabled=function() return false end,
    enforce=function() return true end,allowed=function() return true end}
local bus,events=require("core/event_bus"),require("core/events")
local scheduler=require("core/scheduler")
local definitions=require("config/generated/archive_challenge_definitions")
local actions=require("config/generated/archive_challenge_actions")
local calendar=require("systems/archive_calendar")
local limits=require("systems/archive_daily_limits")
local clock,serial,winners=100,0,0
local current_tier,current_mode=10,"cold"
local profiles,entities,rows,writes,deliveries={},{},{},{},{}
local pending,finalizations,errors={},0,{}
local endless_running,endless_finished={},nil
local fail_birth,death_visual_failure,spawn_listener=nil,false,nil
local births=0
local function copy(value)
    if type(value)~="table" then return value end
    local result={};for key,child in pairs(value) do result[key]=copy(child) end;return result
end
local function check(value,message) assert(value,message) end
local function same_counts(before,except)
    for key,value in pairs(writes) do
        check(value==(before[key] or 0)+(except[key] or 0),"unexpected runtime writes: "..key)
    end
end
DOTA_TEAM_GOODGUYS=2
Vector=function(x,y,z) return {x=x,y=y,z=z} end
PlayerResource={IsValidPlayerID=function(_,id) return id==0 or id==1 end,
    IsFakeClient=function() return false end,GetTeam=function() return 2 end,
    GetPlayer=function(_,id) return id end}
GameRules={GetGameTime=function() return clock end,
    SetGameWinner=function(_,team) check(team==2);winners=winners+1 end}
CustomNetTables={SetTableValue=function(_,name,key,value)
    if name=="survival_ability_runtime" then
        rows[key]=copy(value);writes[key]=(writes[key] or 0)+1
    end
end}
calendar.set_clock(function() return 1793232000 end)
package.loaded["debug/mode_unlock_test"]={is_enabled=function() return false end}
package.loaded["systems/match_setup_service"]={get_mode=function() return current_mode end}
package.loaded["systems/player_context_service"]={
    active_player_ids=function() return {0,1} end,is_defeated=function() return false end,
    owner_player_id=function(unit) return unit.owner end,
    register_unit=function(id,unit) unit.owner=id end,unregister_unit=function() end}
package.loaded["systems/player_profile_service"]={
    get_account_profile=function(id) return copy(profiles[id]) end,
    get_daily_limit=function(id,key) return limits.snapshot(profiles[id]).by_key[key] end}
local function unit(name,position)
    serial=serial+1
    local body={id=serial,name=name,position=position or Vector(0,0,0),abilities={},alive=true}
    function body:IsNull() return self.removed==true end
    function body:IsAlive() return self.alive end
    function body:entindex() return self.id end
    function body:GetAbsOrigin() return self.position end
    function body:FindAbilityByName(name) return self.abilities[name] end
    function body:GetAbilityCount() local n=0;for _ in pairs(self.abilities) do n=n+1 end;return n end
    function body:AddAbility(name)
        serial=serial+1
        local ability={id=serial,active=true,level=0,activation_writes=0}
        function ability:IsNull() return body.removed==true end
        function ability:entindex() return self.id end
        function ability:GetCaster() return body end
        function ability:GetAbilityName() return name end
        function ability:GetLevel() return self.level end
        function ability:SetLevel(value) self.level=value end
        function ability:IsActivated() return self.active end
        function ability:SetActivated(value) self.active=value;self.activation_writes=self.activation_writes+1 end
        function ability:StartCooldown(value) self.cooldown=value end
        function ability:EndCooldown() self.cooldown=0 end
        self.abilities[name]=ability;return ability
    end
    function body:SetControllableByPlayer(id) self.owner=id end
    local function noop() end
    body.SetModel=noop;body.SetOriginalModel=noop;body.SetModelScale=noop;body.AddNewModifier=noop
    body.SetDeathXP=noop;body.SetMinimumGoldBounty=noop;body.SetMaximumGoldBounty=noop
    body.SetBaseMagicalResistanceValue=noop
    entities[body.id]=body;return body
end
CreateUnitByName=unit
UTIL_Remove=function(body)
    body.removed=true
    bus.emit(events.ENGINE_ENTITY_KILLED,{victim=body,victim_entindex=body.id})
end
package.loaded["systems/archive_hub_placement"]={resolve=function(id,index)
    return Vector(id*2000,index*300,0),"concurrent_fixture"
end}
package.loaded["systems/challenge_guardian_visual_service"]={apply=function() end,clear=function() end}
package.loaded["systems/monster_hero_visual_service"]={clear=function() end,on_death=function()
    if death_visual_failure then error("cosmetic fixture failure") end
end}
package.loaded["systems/wave_system"]={get_difficulty=function() return "N"..current_tier end,
    spawn_challenge_monster=function(row)
        births=births+1
        if fail_birth and births==fail_birth then return nil,"fixture blocked birth" end
        local body=unit("challenge:"..row.challenge_id)
        if spawn_listener then spawn_listener(body,row) end
        return body
    end}
package.loaded["systems/archive_endless_service"]={
    init=function(_,finished) endless_running={};endless_finished=finished end,
    is_running=function(id) return endless_running[id]==true end,
    start=function(id) if endless_running[id] then return false,"already running" end;endless_running[id]=true;return true end,
    cancel=function(id) endless_running[id]=nil end,skip_step=function() return 1 end}
local reducer=require("systems/archive_settlement")
local policy=require("systems/archive_cooperative_reward_policy")
package.loaded["systems/archive_service"]={
    has_pending=function(id) return pending[id]==true end,
    begin_finalization=function() finalizations=finalizations+1 end,
    record_challenge=function(id,challenge,sequence,difficulty)
        local command={id="concurrent-session:challenge_kind:"..challenge,kind="challenge",
            challenge_id=challenge,kill_sequence=sequence,difficulty_id=difficulty,day_key=calendar.day()}
        local result=reducer.settle(profiles[id],command,false,
            {challenge_random_seed=policy.local_seed(command.id)})
        check(result.ok,result.error)
        profiles[id].save.archive=result.archive;profiles[id].save.gameplay_stats=result.gameplay_stats
        deliveries[#deliveries+1]={player=id,challenge=challenge,sequence=sequence,result=result.response}
        bus.emit(events.PLAYER_PROFILE_CHANGED,{player_id=id,reason="committed_challenge"})
        return result
    end}
local service=require("systems/archive_challenge_service")
local original_print=print
print=function(message)
    message=tostring(message)
    if message:find("handler error",1,true) or message:find("task failed",1,true)
        or message:find("hubs pending",1,true) then errors[#errors+1]=message end
end
local function fresh()
    bus.reset();scheduler.clear();require("systems/gameplay_phase_guard").reset()
    require("systems/multiplayer_player_service")._reset_for_test()
    profiles,entities,rows,writes,deliveries,pending={},{},{},{},{},{}
    errors={};births=0;fail_birth=nil;spawn_listener=nil;death_visual_failure=false;finalizations=0
    for id=0,1 do
        profiles[id]={save={archive={social_draw_counts={beast=101,ex=101,friend=id==0 and 100 or 101}},gameplay_stats={}}}
    end
    service.init()
    check(service.begin({difficulty_id="N10",player_ids={0,1}}).keep_running)
    check(#errors==0,table.concat(errors,"\n"))
    return service._test.players()[0],service._test.players()[1]
end
local function entry(state,id)
    local definition=assert(definitions.by_id[id]);local hub=state.hubs[definition.building_id]
    return hub,assert(hub:FindAbilityByName("ability_archive_"..id))
end
local function summon(state,id)
    local hub,ability=entry(state,id);local ok,reason=service.summon(hub,id,ability);check(ok,reason)
    return assert(state.active_groups[id])
end
local function body(group) return assert(group.units[next(group.units)]) end
local function kill(unit)
    unit.alive=false
    bus.emit(events.ENGINE_ENTITY_KILLED,{victim=unit,victim_entindex=unit.id})
end
local function count(id,challenge)
    local total=0;for _,event in ipairs(deliveries) do
        if event.player==id and event.challenge==challenge then total=total+1 end
    end;return total
end

local state,other=fresh()
local wife_currency=require("config/generated/archive_social_rules").by_id.wife.currency_id
limits.grant(profiles[1].save.archive,"watermelon",10,calendar.day(),false)
local chosen={"shadow_1","social_beast","watermelon","social_wife"}
for _,id in ipairs(chosen) do
    local before=copy(writes);local _,ability=entry(state,id)
    local group=summon(state,id)
    check(group.remaining==1 and group.committed and state.used[id],"each entry owns an independent group")
    same_counts(before,{[tostring(ability.id)]=1})
    local hub=entry(state,id)
    check(not service.summon(hub,id,ability),"same entry remains once per match")
end
check(#deliveries==0,"spawning never grants rewards")
for index=#chosen,1,-1 do
    local id=chosen[index];local unit=body(state.active_groups[id])
    death_visual_failure=id=="watermelon"
    kill(unit);kill(unit);death_visual_failure=false
    check(not state.active_groups[id],"only the completed challenge retires")
    check(count(0,id)==1 and count(1,id)==1,"reverse and duplicate kills dispatch each account once")
end
check((profiles[0].save.archive.social_tickets or {})[wife_currency]==nil,"exactly100 draws never gains wife currency")
check(profiles[1].save.archive.social_tickets[wife_currency]==1,"101 draws gains own wife currency")
check(profiles[0].save.archive.challenge_points.watermelon==1 and profiles[1].save.archive.challenge_points.watermelon==0,
    "independent fruit reward survives cosmetic failure while capped recipient gets zero")
local stale=summon(other,"shadow_2")
local before=copy(writes)
service.begin({difficulty_id="N10",player_ids={0,1}})
same_counts(before,{})

-- Other live entries survive a failed football birth and can settle while
-- its five-body group is partially cleared. Source identity stays per group.
local live=summon(state,"shadow_3")
local original_live=body(live)
fail_birth=births+2
local football_hub,football_ability=entry(state,"football")
check(not service.summon(football_hub,"football",football_ability))
check(state.active_groups.shadow_3==live and original_live:IsAlive() and not original_live:IsNull())
check(not state.active_groups.football and not state.used.football,"only failed football rolls back")
fail_birth=nil
local football=summon(state,"football")
check(football.remaining==5,"real football config retains five bodies")
kill(original_live)
check(count(0,"shadow_3")==1 and count(1,"shadow_3")==1 and football.remaining==5)
for _=1,4 do local dead=body(football);kill(dead);kill(dead) end
check(count(0,"football")==0 and count(1,"football")==0 and football.remaining==1)
kill(body(football))
check(count(0,"football")==1 and count(1,"football")==1 and not state.active_groups.football)
check(profiles[0].save.archive.challenge_points.football==10 and profiles[1].save.archive.challenge_points.football==10)

-- Normal monsters and the endless controller no longer lock each other.
local normal=summon(state,"shadow_4")
local endless=assert(actions.by_id.endless)
local endless_hub=state.hubs[endless.building_id]
check(service.start_endless(endless_hub,endless_hub:FindAbilityByName(endless.ability_name)))
check(state.active_groups.shadow_4==normal and endless_running[0])
local during=summon(state,"social_ex")
kill(body(during));check(count(0,"social_ex")==1)
check(state.active_groups.shadow_4==normal,"another completion cannot remove the older live group")
endless_running[0]=nil

-- Existing daily limits stay authoritative for each recipient, even when
-- a teammate's legal challenge is active concurrently with other monsters.
local fruit_hub,fruit_ability=entry(other,"watermelon")
check(service.ability_runtime(fruit_hub,"ability_archive_watermelon").daily_capped==1)
check(not service.summon(fruit_hub,"watermelon",fruit_ability) and not other.used.watermelon,
    "exhausted own quota rejects only that entry without consuming it")
check(profiles[1].save.archive.challenge_points.watermelon==0,"capped recipient gains no extra currency")
check(profiles[0].save.archive.challenge_points.watermelon==1,"shared challenge award remains once")

-- Finish/timeout remove every still-live independent group without awards.
local abandoned=body(normal)
local remaining=body(stale)
local prior=#deliveries
pending[0]=true
check(not service.finish_player(0),"manual finish retains pending-save guard")
pending[0]=false
check(service.finish_player(0) and abandoned:IsNull() and next(state.active_groups)==nil)
kill(abandoned);check(#deliveries==prior,"cleanup deaths cannot gain rewards")
pending[1]=true
clock=service.phase_snapshot().deadline;scheduler.think()
check(remaining:IsNull() and next(other.active_groups)==nil and service.phase_snapshot().saving==1)
check(#deliveries==prior and finalizations==1,"timeout cleans every group and waits for earned saves")
pending[1]=false;clock=clock+1;scheduler.think()
check(service.phase_snapshot().saving==0 and #errors==0,table.concat(errors,"\n"))

-- A native spawn listener ending the phase cannot leak an unregistered body.
state,other=fresh()
spawn_listener=function() service.finish_player(0);service.finish_player(1) end
local hub,ability=entry(state,"shadow_1")
local prior_births=births
check(not service.summon(hub,"shadow_1",ability))
check(births==prior_births+1 and next(state.active_groups)==nil and not state.used.shadow_1)
for _,entity in pairs(entities) do check(entity:IsNull(),"ended phase leaves no in-flight monster or hub") end
check(#deliveries==0 and #errors==0,table.concat(errors,"\n"))

-- Every currently configured normal entry can be opened in one phase. Each
-- actual group completion passes the real reward reducer for both accounts.
state,other=fresh()
profiles[0].save.archive.social_draw_counts.friend=101
bus.emit(events.PLAYER_PROFILE_CHANGED,{player_id=0,reason="fixture_eligible_draws"})
local opened,by_building={},{ }
local definition_count=0
for _,definition in ipairs(definitions.rows) do if definition.enabled then
    local before=copy(writes)
    local _,ability=entry(state,definition.challenge_id)
    local group=summon(state,definition.challenge_id)
    opened[#opened+1]={id=definition.challenge_id,group=group}
    definition_count=definition_count+1
    by_building[definition.building_id]=(by_building[definition.building_id] or 0)+1
    same_counts(before,{[tostring(ability.id)]=1})
end end
local active_count,bodies=0,0
for _,group in pairs(state.active_groups) do active_count=active_count+1;bodies=bodies+group.remaining end
check(definition_count==36 and active_count==36 and bodies==40,"all36 entries and40 actual bodies coexist")
for index=1,4 do check((by_building[index] or 0)>0,"each archive building contributes concurrent monsters") end
for index=#opened,1,-1 do
    local item=opened[index]
    while item.group.remaining>0 do local dead=body(item.group);kill(dead);kill(dead) end
    check(not state.active_groups[item.id] and count(0,item.id)==1 and count(1,item.id)==1,
        "every completed entry independently settles each winning account exactly once")
end
check(#deliveries==72 and next(state.active_groups)==nil,"all36 real reward intents settle for both accounts")
local before_winner=winners
check(service.finish_player(0) and service.finish_player(1) and winners==before_winner+1)
check(#errors==0,table.concat(errors,"\n"))

-- Reentrant births cannot enter the same challenge twice or borrow another
-- group's sequence. A native initialization failure retires only its group.
state,other=fresh()
local nested
spawn_listener=function(_,row)
    if row.challenge_id=="football" then
        spawn_listener=nil
        local hub,ability=entry(state,"football")
        local before_births=births
        check(not service.summon(hub,"football",ability) and births==before_births,
            "in-flight same-entry cast cannot create a second group")
        nested=summon(state,"shadow_1")
    end
end
local outer=summon(state,"football")
check(nested and outer.sequence~=nested.sequence and outer.remaining==5 and nested.remaining==1)
kill(body(nested))
while outer.remaining>0 do kill(body(outer)) end
for _,event in ipairs(deliveries) do
    check(event.sequence==(event.challenge=="football" and outer.sequence or nested.sequence),
        "reentrant creation preserves each authoritative event sequence")
end
local survivor=summon(state,"shadow_2")
local initialization_attempts=0
spawn_listener=function(body,row)
    if row.challenge_id=="watermelon" then
        initialization_attempts=initialization_attempts+1
        body.SetDeathXP=function() error("fixture native initialization rejected") end
        bus.emit(events.PLAYER_PROFILE_CHANGED,{player_id=0,reason="during_native_initialization"})
    end
end
local rejected_hub,rejected_ability=entry(state,"watermelon")
check(not service.summon(rejected_hub,"watermelon",rejected_ability))
check(initialization_attempts==1 and state.active_groups.shadow_2==survivor and not state.active_groups.watermelon
    and not state.used.watermelon and rows[tostring(rejected_ability.id)].available==1,
    "native setup rollback preserves another group and restores only the rejected entry")
spawn_listener=nil
check(service.finish_player(0) and service.finish_player(1) and #errors==0,table.concat(errors,"\n"))
print=original_print
print("ARCHIVE_CONCURRENT_CHALLENGES_PASS: all36 entries/40 bodies/72 real recipient settlements, isolated runtime writes, duplicate kills, football rollback, eligibility/daily limits, endless coexistence and phase cleanup")
