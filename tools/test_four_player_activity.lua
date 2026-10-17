-- Runs the real event bus, resource accounts/spend rules and research discount
-- service. Engine units and normal gameplay transaction endpoints are boundaries.
-- It tests the activity adapter, not four network clients or rendered FPS.
package.path='scripts/vscripts/?.lua;'..package.path
local activity=require('tests/manual_four_player_activity')
assert(_G.SURVIVAL_FOUR_PLAYER_ACTIVITY==nil,'require must be inert')
local mode,at,session={},0,'activity_regression'
local tools=true
IsServer=function() return true end;IsInToolsMode=function() return tools end
GetMapName=function() return 'template_map' end
RealTime=function() return at end
GameRules={GetGameModeEntity=function() return mode end,GetGameTime=function() return at end}
local meta={}
meta.__add=function(a,b) return Vector(a.x+b.x,a.y+b.y,a.z+b.z) end
meta.__sub=function(a,b) return Vector(a.x-b.x,a.y-b.y,a.z-b.z) end
meta.__mul=function(a,b) return Vector(a.x*b,a.y*b,a.z*b) end
meta.__index={Length2D=function(a) return math.sqrt(a.x*a.x+a.y*a.y) end,
    Normalized=function(a) local l=math.sqrt(a.x*a.x+a.y*a.y);return Vector(a.x/l,a.y/l,0) end}
Vector=function(x,y,z) return setmetatable({x=x,y=y,z=z or 0},meta) end
DOTA_UNIT_ORDER_MOVE_TO_POSITION,DOTA_UNIT_ORDER_ATTACK_TARGET=1,4
DOTA_UNIT_ORDER_CAST_POSITION,DOTA_UNIT_ORDER_CAST_TARGET,DOTA_UNIT_ORDER_CAST_NO_TARGET=5,6,8
DOTA_ABILITY_BEHAVIOR_NO_TARGET,DOTA_ABILITY_BEHAVIOR_PASSIVE,DOTA_ABILITY_BEHAVIOR_UNIT_TARGET,DOTA_ABILITY_BEHAVIOR_POINT,DOTA_ABILITY_BEHAVIOR_TOGGLE=4,16,8,32,512
DOTA_UNIT_TARGET_TEAM_ENEMY,DOTA_UNIT_TARGET_HERO,DOTA_UNIT_TARGET_BASIC,DOTA_UNIT_TARGET_FLAG_NONE,FIND_CLOSEST=2,1,2,0,1
UF_SUCCESS=0
GridNav={CanFindPath=function() return true end}
GetGroundPosition=function(p) return p end
local serial=100
local function unit(id,p,hero)
    serial=serial+1
    local u={id=id,index=serial,position=p,survival_level=1,native_id=hero and id or -1,abilities={}}
    function u:IsNull() return self.removed==true end;function u:IsAlive() return self.alive~=false end
    function u:GetPlayerOwnerID() return self.native_id end;function u:entindex() return self.index end
    function u:GetAbsOrigin()
        self.origin_reads=(self.origin_reads or 0)+1
        if self.native_invalid then error('Invalid object passed to GetOrigin') end
        return self.position
    end
    function u:GetTeamNumber() return 2 end
    function u:GetAttackRange() return 800 end;function u:GetLevel() return self.id+1 end
    function u:GetAbilityCount() return #self.abilities end;function u:GetAbilityByIndex(i) return self.abilities[i+1] end
    return u
end
local function ability(name,behavior,range)
    serial=serial+1;local a={index=serial,name=name,behavior=behavior,range=range or 800}
    function a:IsNull() return false end;function a:IsHidden() return false end
    function a:IsActivated() return true end;function a:GetLevel() return 1 end
    function a:IsFullyCastable() return self:GetCooldownTimeRemaining()==0 end;function a:GetAbilityName() return self.name end
    function a:GetBehaviorInt() return self.behavior end;function a:entindex() return self.index end
    function a:GetCastRange() return self.range end
    function a:GetCooldownTimeRemaining() return math.max(0,(self.cooldown_until or 0)-at) end
    function a:CastFilterResultLocation() return 0 end;function a:CastFilterResultTarget() return 0 end
    return a
end
local bus=require('core/event_bus');local events=require('core/events')
local scheduled={}
package.loaded['core/scheduler']={every=function(interval,fn,key) scheduled[key]={interval=interval,fn=fn} end,
    cancel=function(key) scheduled[key]=nil end}
package.loaded['systems/gameplay_phase_guard']={post_clear_frozen=function() return false end}
local defeated_players={}
package.loaded['systems/player_context_service']={is_owned_by=function(id,u) return id==(u.context_id or u.id) end,
    is_defeated=function(id) return defeated_players[id]==true end}
package.loaded['systems/match_setup_service']={get_mode=function() return 'standard' end,get_session_id=function() return session end}
package.loaded['systems/player_profile_service']={get_profile=function(id) return {save={gameplay_stats={initial_wood=100,initial_gold=100,initial_population_cap=500}}} end}
package.loaded['systems/destination_validation_service']={validate_hero_position=function() return true end}
local def={tech_id='RS-TEST',legacy_group='activity_test',building_id='research_lab',max_level=200,prerequisite={}}
package.loaded['config/research_technology_config']={technologies={def},cost_for_level=function(_,level)
    return level<=200 and {wood=100*level,gold=20*level} or nil
end}
package.loaded['config/buildings_config']={gold_mine={wood=80,gold=30},building_challenge={wood=90,gold=40}}
package.loaded['systems/building_cost_quote']={for_player=function(c) return {wood=c.wood,gold=c.gold} end}
package.loaded['config/generated/rogue_reward_effects']={rows={{card_id='unsafe_spawn',enabled=true,effect_type='spawn_worker'}}}
PlayerResource={GetTeam=function() return 2 end}
local resources=require('systems/resource_system')
local requests,orders,registry,builders,heroes,levels,reserved,offers,discounts
local selection_failure,chain_offer,ui_reads
local native_listeners={};local listener_serial=0
ListenToGameEvent=function(name,fn) listener_serial=listener_serial+1;native_listeners[listener_serial]={name=name,fn=fn};return listener_serial end
StopListeningToGameEvent=function(id) native_listeners[id]=nil end
local function native_event(name,payload) for _,r in pairs(native_listeners) do if r.name==name then r.fn(payload) end end end
local function request(name,p) return bus.request(events[name],p) end
local function register(id,kind,p)
    local u=unit(id,p);local row={unit=u,player_id=id,building_id=kind,level=1}
    registry[id][#registry[id]+1]=row;return u
end
local function reset(scenario)
    at=0;session='activity_regression';scheduled={};requests={};orders={};registry={};builders={};heroes={};levels={};reserved={};offers={};discounts={};native_listeners={}
    selection_failure,chain_offer,ui_reads=nil,nil,0
    defeated_players={}
    _G.SURVIVAL_FOUR_PLAYER_ACTIVITY=nil;bus.reset();resources.init()
    local scene={players={}}
    local fixture={mode=mode,status='ready',scenario=scenario,defender_id=0,defender_scene=scene,owners={},inward=Vector(0,-1,0)}
    fixture.guard={mode=mode};_G.SURVIVAL_FOUR_PLAYER_LIVE_PERF=fixture;_G.SURVIVAL_REAL_GAME_STRESS_ISOLATION=fixture.guard
    for id=0,3 do
        registry[id]={};levels[id]=0;reserved[id]=0;discounts[id]=id==1 and 50 or 0
        builders[id]=unit(id,Vector(id*3000,4000,0))
        local wall=register(id,'wall',Vector(id*3000,4600,0))
        if scenario=='A' or id==0 then
            local city=register(id,'main_city',Vector(id*3000,4000,0))
            register(id,'arrow_tower',Vector(id*3000+64,4000,0));register(id,'building_research_lab',Vector(id*3000+128,4000,0))
            scene.players[#scene.players+1]={id=id,units={wall=wall,main_city=city}}
            local hero=unit(id,Vector(id*3000,4000,0),true)
            hero.abilities={ability('passive_exclusive',16),ability('ordinary_active',4),ability('ordinary_return',4)}
            heroes[id]=hero
        else fixture.owners[id]={wall=wall} end
        offers[id]={active=1,token='offer_'..id,reward_type='talent',cards={
            {card_id='safe_card'},{card_id='unsafe_spawn'}}}
        bus.emit(events.PLAYER_PROFILE_CHANGED,{player_id=id})
    end
    CustomNetTables={GetTableValue=function(_,name,id) assert(name=='survival_rogue_reward');ui_reads=ui_reads+1;return offers[tonumber(id)] end,
        SetTableValue=function() error('Activity must not mutate UI net tables') end}
    FindUnitsInRadius=function(_,p)
        return {unit(99,p+Vector(40,0,0),true)}
    end
    ExecuteOrderFromTable=function(order)
        local found
        for id,h in pairs(heroes) do if h.index==order.UnitIndex then found=h;assert(id==order.PlayerID) end end
        for id,b in pairs(builders) do if b.index==order.UnitIndex then found=b;assert(id==order.PlayerID) end end
        assert(found and (found.native_id==-1 or found.native_id==order.PlayerID),'Cross-owner native order must never reach engine')
        if order.AbilityIndex then
            local active=false;for _,a in ipairs(found.abilities) do if a.index==order.AbilityIndex then
                active=a.name=='ordinary_active' or a.name=='ability_survival_hero_ball_lightning'
                if active then a.cooldown_until=at+5 end
            end end
            assert(active,'Passive/return skills must not be cast by fixture')
        end
        orders[#orders+1]=order
        if order.Position then found.position=order.Position end
        return true
    end
    local function handler(label,fn)
        bus.handle_request(events[label],function(p) requests[#requests+1]={kind=label,player_id=p.player_id};return fn(p) end)
    end
    handler('PERMANENT_REWARD_EFFECTS_GET_REQUEST',function(p) return {ok=true,totals={technology_cost_refund_pct=discounts[p.player_id]}} end)
    handler('BUILDER_GET_REQUEST',function(p) return {ok=true,player_id=p.player_id,builder=builders[p.player_id]} end)
    handler('BUILDING_LIST_REQUEST',function(p) return {buildings=registry[p.player_id]} end)
    handler('BUILDING_QUERY_REQUEST',function(p) for _,rows in pairs(registry) do for _,r in ipairs(rows) do if r.unit.index==p.entindex then return r end end end end)
    handler('HERO_SUMMON_GET_REQUEST',function(p) return {ok=heroes[p.player_id]~=nil,unit=heroes[p.player_id],hero_id=({'hero_monkey_king','hero_blademaster','hero_drow_ranger','hero_doom'})[p.player_id+1]} end)
    handler('HERO_PROGRESSION_GET_REQUEST',function() return {snapshot={rebirth_level=3}} end)
    handler('RESEARCH_STATE_GET_REQUEST',function(p) return {levels={['RS-TEST']=levels[p.player_id]}} end)
    handler('TECHNOLOGY_STATE_GET_REQUEST',function(p) return {levels={activity_test=levels[p.player_id]},research={reserved_levels={activity_test=reserved[p.player_id]}}} end)
    handler('BUILDING_UPGRADE_QUOTE_REQUEST',function() return {ok=true,wood=59,gold=11} end)
    handler('BUILDING_UPGRADE_REQUEST',function(p)
        local r=request('RESOURCE_TRY_SPEND_REQUEST',{player_id=p.player_id,wood=59,gold=11})
        if r.ok then p.building.survival_level=p.building.survival_level+1;bus.emit(events.BUILDING_CHANGED,{player_id=p.player_id,unit=p.building,level=p.building.survival_level}) end
        return r
    end)
    handler('TECHNOLOGY_PURCHASE_NEXT_REQUEST',function(p)
        assert(p.source=='research_lab_ability' and p.technology_group=='activity_test')
        local id=p.player_id;local target=math.max(levels[id],reserved[id])+1
        local quote=require('research/research_cost_service').for_player({wood=100*target,gold=20*target},bus,events,id)
        local r=request('RESOURCE_TRY_SPEND_REQUEST',{player_id=id,wood=quote.wood,gold=quote.gold})
        if r.ok then reserved[id]=target;bus.emit(events.TECHNOLOGY_RESEARCH_STATE_CHANGED,{player_id=id}) end
        return {ok=r.ok,error=r.error,target_level=target,job_id='test:'..target,queued=r.ok,research_started=r.ok}
    end)
    handler('WORKER_TRAINING_GET_REQUEST',function() return {options={{training_id='train_lumberjack_01',available=1,wood_cost=41,gold_cost=7,population_cost=1}}} end)
    handler('WORKER_TRAIN_REQUEST',function(p)
        assert(p.city and p.training_id=='train_lumberjack_01')
        local r=request('RESOURCE_TRY_SPEND_REQUEST',{player_id=p.player_id,wood=41,gold=7,population=1})
        if r.ok then bus.emit(events.WORKER_CHANGED,{player_id=p.player_id,count_delta=1}) end
        return {ok=r.ok,error=r.error,queued=r.ok}
    end)
    handler('BUILD_CAN_PLACE_REQUEST',function(p) return {ok=true,grid={world_position=p.position}} end)
    handler('BUILD_REQUEST',function(p)
        local cost=package.loaded['config/buildings_config'][p.building_id]
        local r=request('RESOURCE_TRY_SPEND_REQUEST',{player_id=p.player_id,wood=cost.wood,gold=cost.gold})
        if r.ok then local u=register(p.player_id,p.building_id,p.position);bus.emit(events.BUILDING_CREATED,{player_id=p.player_id,unit=u}) end
        return {ok=r.ok,error=r.error,pending=r.ok}
    end)
    handler('ROGUE_REWARD_SELECT_REQUEST',function(p)
        assert(p.token==offers[p.player_id].token and p.reward_type=='talent')
        local legal=false;for _,card in ipairs(offers[p.player_id].cards) do if card.card_id==p.card_id then legal=true end end
        assert(legal)
        if selection_failure then return {ok=false,error='test_selection_refused'} end
        offers[p.player_id].active=0
        bus.emit(events.ROGUE_REWARD_CHANGED,{player_id=p.player_id,snapshot=offers[p.player_id]})
        if chain_offer then
            offers[p.player_id]=chain_offer;chain_offer=nil
            bus.emit(events.ROGUE_REWARD_CHANGED,{player_id=p.player_id,snapshot=offers[p.player_id]})
        end
        return {ok=true}
    end)
end
local function tick(time)
    at=time;local t=scheduled.manual_four_player_activity
    if t then local result=t.fn();if result==false then scheduled.manual_four_player_activity=nil end end
end
local function run(scenario,slow)
    reset(scenario)
    local initial=activity.prepare({seed=731,duration_seconds=120,trace_limit=128})
    assert(initial.offers_remaining==0 and initial.clock_source=='RealTime')
    for id=0,3 do
        local account=resources._test.accounts()[id]
        assert(account.debug_mode==false and account.population==0 and account.max_population==500,'Normal population and real spend mode must remain')
        assert(initial.owners[id+1].wallet.wood==1200000+id*500000)
        assert(initial.owners[id+1].wallet.gold==600000+id*250000)
    end
    local plan=activity.report({include_plan=true}).plans
    activity.start()
    local original_print=print;print=function() error('No sampling console spam permitted') end
    local delta=slow and 2.7 or 0.1
    for t=0,120,delta do tick(t) end;tick(120.001)
    local report=activity.report({include_trace=true,include_plan=true})
    print=original_print
    assert(report.status=='stopped' and report.stop_reason=='duration_complete' and not scheduled.manual_four_player_activity)
    local actions=0;for _,owner in ipairs(report.owners) do actions=actions+owner.steps end
    assert(report.schema=='four_player_activity_v2' and report.trace_retained==actions and #report.trace==actions and report.action_trace_dropped==0)
    assert(report.lifecycle_trace_retained<=64 and report.trace_total>actions)
    assert(report.scope=='one_rendered_client_four_engine_owners' and report.network_clients_claimed==false)
    local sequence=0
    for index,row in ipairs(report.trace) do assert(row.sequence>sequence and row.action_sequence==index and row.step and not row.kind:match('^event:'));sequence=row.sequence end
    local by_player={}
    for _,order in ipairs(orders) do by_player[order.PlayerID]=(by_player[order.PlayerID] or 0)+1 end
    for _,owner in ipairs(report.owners) do
        assert(owner.wallet.debug_mode==0)
        assert(owner.wallet.wood<initial.owners[owner.player_id+1].wallet.wood,'Accepted ordinary operations must really debit player wallet')
        assert(owner.stats.actions==owner.steps and owner.stats.actions_accepted>0)
        assert(owner.planned_steps>=owner.steps and owner.unexecuted_steps==owner.planned_steps-owner.steps)
        assert(by_player[owner.player_id]>0,'All four owners must submit genuine engine orders')
        if scenario=='B' and owner.player_id~=0 then
            assert(owner.wall_only and owner.hero_id==nil and owner.counts.wall==1)
            for kind in pairs(owner.counts) do assert(kind=='wall','Wall-only players must keep no combat buildings') end
            for kind in pairs(owner.stats.by_kind) do if not kind:match('^event:') then assert(kind=='upgrade' or kind=='builder_move' or kind=='prepare_wallet' or kind=='select_offer') end end
        end
    end
    -- Stop must remove subscriptions as well as the repeating task.
    local serial_before=report.trace_total;bus.emit(events.BUILDING_CHANGED,{player_id=0,unit=registry[0][1].unit})
    assert(activity.report().trace_total==serial_before)
    return report,plan
end
tools=false;assert(not pcall(activity.prepare),'Non-Tools invocation must reject');tools=true
local fast,plan=run('A',false);local slow,slow_plan=run('A',true)
for id=0,3 do
    assert(fast.owners[id+1].plan_digest==slow.owners[id+1].plan_digest and #plan[id]==#slow_plan[id],'Same seed must define the same complete plan despite slow frames')
    for index,row in ipairs(plan[id]) do local other=slow_plan[id][index];assert(row.at==other.at and row.kind==other.kind and row.selector==other.selector) end
    assert(slow.owners[id+1].steps<fast.owners[id+1].steps and slow.owners[id+1].unexecuted_steps>0,'Slow polls must not flood catch-up operations')
end
local b_fast,b_plan=run('B',false)
reset('A');activity.prepare({seed=731,duration_seconds=120});activity.start()
builders[0].native_id=1;builders[1].context_id=0;heroes[2].native_id=3
for t=0,100,0.1 do tick(t) end
local report=activity.report({include_trace=true})
local rejects=0;for _,row in ipairs(report.trace) do if row.error=='native_actor_ownership_changed' or row.error=='hero_unavailable' then rejects=rejects+1 end end
assert(rejects>0,'Changed formal/native ownership must be audited and rejected before engine orders')
session='new_session';tick(101);assert(activity.report().stop_reason=='fixture_or_session_changed')
reset('A');request('RESOURCE_DEBUG_SET_REQUEST',{player_id=0,amount=50})
assert(not pcall(activity.prepare,{duration_seconds=120}),'Debug wallets bypass normal payment and must be refused')
-- Price admission must include the queued target and the real player discount.
reset('A');local s=activity.prepare({seed=731,duration_seconds=120,trace_limit=1024})
reserved[1]=5;request('RESOURCE_ADD_REQUEST',{player_id=1,wood=350-s.owners[2].wallet.wood,gold=100-s.owners[2].wallet.gold})
activity.start();local checked=false
for t=0,120,0.1 do
    tick(t)
    local r=activity.report({include_trace=true})
    for _,row in ipairs(r.trace) do if row.player_id==1 and row.kind=='research' and row.quoted_target_level==6 then
        assert(row.quote.wood==300 and row.quote.gold==60 and row.accepted,'Affordable discounted queued target must not be falsely rejected at raw cost')
        assert(row.resource_after.wood==row.resource_before.wood-300 and row.resource_after.gold==row.resource_before.gold-60)
        checked=true;break
    end end
    if checked then break end
end
assert(checked,'Deterministic plan must exercise discounted reserved research admission')
activity.stop('regression_complete')
-- Thousands of business notifications cannot evict any planned action, nor
-- trigger full wallet/building readback scans in the diagnostic listener.
reset('A');activity.prepare({seed=731,duration_seconds=120,observe_hero_completion=true});activity.start()
tick(0);local actions_before=#activity.report({include_trace=true}).trace
local requests_before=#requests
for _=1,10000 do bus.emit(events.BUILDING_CHANGED,{player_id=0,level=2}) end
assert(#requests==requests_before,'Lifecycle observation must use its payload without full-state rereads')
local flooded=activity.report({include_trace=true})
assert(#flooded.trace==actions_before and flooded.lifecycle_trace_retained==64 and flooded.owners[1].stats.lifecycle_events.BUILDING_CHANGED>=10000)
bus.emit(events.HERO_MAIN_ATTACK_FIRED,{player_id=0,attacker=heroes[0]})
bus.emit(events.HERO_MAIN_ATTACK_LANDED,{player_id=0,attacker=heroes[0]})
bus.emit(events.HERO_MAIN_ATTACK_FIRED,{player_id=0,attacker=unit(0,Vector(0,0,0),true)})
bus.emit(events.HERO_MAIN_ATTACK_LANDED,{player_id=1,attacker=heroes[0]})
native_event('dota_non_player_used_ability',{caster_entindex=heroes[0].index,abilityname='ordinary_active'})
native_event('dota_player_used_ability',{PlayerID=1,abilityname='ordinary_active'})
local observations=activity.report().owners
assert(observations[1].hero_observations.main_attack_fired==1 and observations[1].hero_observations.main_attack_landed==1)
assert(observations[1].hero_observations.native_used_exact_caster==1 and observations[2].hero_observations.native_used_player_identity_only==1)
local listeners_saved={};for _,r in pairs(native_listeners) do listeners_saved[#listeners_saved+1]=r.fn end
activity.stop('observer_regression_complete');assert(next(native_listeners)==nil)
for _,fn in ipairs(listeners_saved) do fn({PlayerID=0,caster_entindex=heroes[0].index,abilityname='ordinary_active'}) end
assert(activity.report().owners[1].hero_observations.native_used_ability==1,'Stopped observer callbacks must not count stale-world events')
reset('A');heroes[0].abilities={ability('ability_survival_hero_ball_lightning',32,800)}
activity.prepare({seed=731,duration_seconds=120,observe_hero_completion=true});activity.start()
for t=0,120,0.1 do tick(t) end;tick(120.001)
local completion=activity.report().owners[1].hero_observations
assert(completion.cast_orders>0 and completion.cast_effect_verified>0,'Known blink effect needs observed destination relocation plus a new native cooldown')
print('FOUR_PLAYER_ACTIVITY_PASS: real resource debit; four wallets/orders; deterministic complete plans and bounded slow-frame dispatch; finite stop; bounded trace; B wall-only; passive/ownership gates; formal offers; queued discounted research; exact lifecycle unsubscribe')

local function open_offer(id,token)
    offers[id]={active=1,token=token,reward_type='talent',cards={{card_id='zeta_card'},{card_id='alpha_card'}}}
    bus.emit(events.ROGUE_REWARD_CHANGED,{player_id=id,snapshot=offers[id]})
end
local function selections()
    local n=0;for _,r in ipairs(requests) do if r.kind=='ROGUE_REWARD_SELECT_REQUEST' then n=n+1 end end;return n
end
local function last_open(report,token)
    for _,row in ipairs(report.offer_trace) do if row.kind=='offer_opened' and row.token==token then return row end end
    error('Open trace missing '..token)
end
reset('A');activity.prepare({seed=731,duration_seconds=120});activity.start()
open_offer(0,'during_activity')
local opened=last_open(activity.report({include_trace=true}),'during_activity')
assert(opened.planned_reaction_seconds>=0.75 and opened.planned_reaction_seconds<=1.25)
assert(opened.error==nil,'A legal offer must not report the old truthy fallback no_legal_offer_card error')
assert(opened.candidate_ids[1]=='alpha_card' and opened.candidate_ids[2]=='zeta_card')
local selections_before,reads_before=selections(),ui_reads
for time=0,0.7,0.1 do tick(time) end
local modal=activity.report({include_trace=true,include_plan=true})
assert(modal.owners[1].steps==0 and modal.owners[2].steps>0 and modal.offers_remaining==1)
assert(selections()==selections_before and ui_reads==reads_before,'Modal waiting uses event cache, not per-frame UI polling')
for id=0,3 do
    assert(modal.owners[id+1].plan_digest==fast.owners[id+1].plan_digest and #modal.plans[id]==#plan[id])
    for index,row in ipairs(plan[id]) do
        local other=modal.plans[id][index];assert(row.at==other.at and row.kind==other.kind and row.selector==other.selector)
    end
end
bus.emit(events.ROGUE_REWARD_CHANGED,{player_id=0,snapshot=offers[0]})
assert(activity.report().offer_trace_total==1,'Duplicate token must not reroll its card/reaction time')
chain_offer={active=1,token='nested_next_offer',reward_type='talent',cards={{card_id='alpha_card'},{card_id='zeta_card'}}}
tick(opened.due_at+0.001)
modal=activity.report({include_trace=true})
assert(selections()==selections_before+1 and modal.owners[1].steps==0 and offers[0].token=='nested_next_offer')
assert(modal.owners[1].modal_active_observed and modal.offers_remaining==1,'Same-stack next offer must keep this owner blocked')
local nested=last_open(modal,'nested_next_offer')
tick(nested.due_at+0.001)
assert(activity.report().owners[1].steps==0 and offers[0].active==0,'Selecting/closing never executes a planned action in the same poll')
tick(nested.due_at+0.12);assert(activity.report().owners[1].steps==1)
tick(70);assert(activity.report().owners[1].steps==2,'Delayed plan must not catch up in an action flood')
local complete=activity.report({include_trace=true})
local actions=0;for _,owner in ipairs(complete.owners) do actions=actions+owner.steps end
assert(#complete.trace==actions and complete.action_trace_dropped==0)
activity.stop('modal_success_test')

-- A new offer between prepare/start requires another explicit pre-sample drain.
reset('A');activity.prepare({seed=731,duration_seconds=120});open_offer(0,'after_prepare')
assert(not pcall(activity.start),'start must check the actual current offer, not stale prepare summary')
assert(activity.drain_offers()==0);activity.start();activity.stop('start_race_test')

-- Failed formal responses retain the original UI and block inputs after bounded retries.
reset('A');activity.prepare({seed=731,duration_seconds=120});activity.start();open_offer(0,'failure_offer')
selection_failure=true;selections_before=selections()
for time=0,10,0.1 do tick(time) end
modal=activity.report({include_trace=true})
assert(selections()==selections_before+3 and offers[0].active==1 and modal.owners[1].steps==0)
assert(modal.owners[1].offer_block_reason=='offer_selection_attempt_limit' and modal.offers_remaining==1)
for _,row in ipairs(modal.offer_trace) do if row.kind=='offer_selection' then assert(not row.accepted and row.error=='test_selection_refused' and row.visible_offer_active_after) end end
local foreign=0;bus.subscribe(events.ROGUE_REWARD_CHANGED,function() foreign=foreign+1 end)
local guard=_G.SURVIVAL_REAL_GAME_STRESS_ISOLATION
_G.SURVIVAL_REAL_GAME_STRESS_ISOLATION={mode=mode};tick(11)
assert(activity.report().stop_reason=='fixture_or_session_changed' and offers[0].active==1)
local trace_before=activity.report().offer_trace_total
open_offer(0,'after_stop')
assert(foreign==1 and activity.report().offer_trace_total==trace_before,'Stop only unhooks its own observer and never closes the actual UI')
_G.SURVIVAL_REAL_GAME_STRESS_ISOLATION=guard

-- Full profile fixture identity and stats are checked at selection time.
reset('A');activity.prepare({seed=731,duration_seconds=120});activity.start();open_offer(0,'profile_changed')
local state=_G.SURVIVAL_FOUR_PLAYER_ACTIVITY
local profile_api=package.loaded['systems/player_profile_service'].get_profile
state.fixture.memory_profiles={}
for id=0,3 do state.fixture.memory_profiles[id]={account_id='memory_owner_'..id,revision=id+1,save={gameplay_stats={map_level=id*8+1}}} end
package.loaded['systems/player_profile_service'].get_profile=function(id)
    local expected=state.fixture.memory_profiles[id]
    return {account_id=expected.account_id,revision=expected.revision+1,save={gameplay_stats=expected.save.gameplay_stats}}
end
selections_before=selections()
for time=0,3,0.1 do tick(time) end
assert(selections()==selections_before and offers[0].active==1 and activity.report().owners[1].steps==0)
assert(activity.report().owners[1].offer_block_reason=='offer_profile_changed')
for _,row in ipairs(activity.report({include_trace=true}).offer_trace) do if row.kind=='offer_blocked' then
    assert(row.profile_matches==false and row.profile_guard_verified and row.owner_eligible and row.builder_guard_required==false)
end end
package.loaded['systems/player_profile_service'].get_profile=profile_api
activity.stop('profile_guard_test')

-- Offer trace has its own ring; hundreds of events cannot evict scheduled actions.
reset('A');activity.prepare({seed=731,duration_seconds=120,offer_trace_limit=16});activity.start()
for index=1,100 do
    open_offer(0,'bounded_offer_'..index)
    offers[0].active=0;bus.emit(events.ROGUE_REWARD_CHANGED,{player_id=0,snapshot=offers[0]})
    tick(index*0.1)
end
modal=activity.report({include_trace=true})
actions=0;for _,owner in ipairs(modal.owners) do actions=actions+owner.steps end
assert(modal.offer_trace_total==200 and #modal.offer_trace==16 and modal.offer_trace_dropped==184)
assert(#modal.trace==actions and modal.action_trace_dropped==0)
activity.stop('offer_trace_bound_test')

-- Explicit diagnostic controls distinguish an unresolved modal from old bypass behavior.
for _,respect in ipairs({true,false}) do
    reset('A');activity.prepare({seed=731,duration_seconds=120,auto_select_offers=false,respect_reward_modal=respect});activity.start()
    open_offer(0,'diagnostic_offer');selections_before=selections()
    for time=0,3,0.1 do tick(time) end
    modal=activity.report()
    assert(selections()==selections_before and offers[0].active==1)
    assert((modal.owners[1].steps==0)==respect and modal.modal_guard_disabled_diagnostic==not respect)
    activity.stop('diagnostic_control_test')
end
print('FOUR_PLAYER_ACTIVITY_MODAL_PASS: deterministic plan/digest; event cache/no UI polling; delayed same-owner inputs; nested offers/no same-tick bypass/no catch-up; stale-start refusal; failed response/profile/guard retain UI; bounded independent trace; precise stop; explicit diagnostic controls')

local function same_plan(report,expected,baseline)
    for id=0,3 do
        assert(report.owners[id+1].plan_digest==baseline.owners[id+1].plan_digest and #report.plans[id]==#expected[id])
        for index,row in ipairs(expected[id]) do local actual=report.plans[id][index]
            assert(row.at==actual.at and row.kind==actual.kind and row.selector==actual.selector
                and row.interval==actual.interval and row.burst==actual.burst,'Builder lifecycle must not regenerate actions')
        end
    end
end
local function builder_actions(report,id)
    local found={}
    for _,row in ipairs(report.trace) do if row.player_id==id and (row.kind=='builder_move' or row.kind=='build') then found[#found+1]=row end end
    return found
end
-- Replaced native proxy: the stale object still passes IsNull and ownership,
-- but GetOrigin would throw. No action may read or order the old instance.
reset('B');activity.prepare({seed=731,duration_seconds=120})
local old_builder=builders[1];old_builder.native_invalid=true
builders[1]=unit(1,Vector(3000,4000,0));local replacement=builders[1]
activity.start()
for time=0,25,0.1 do tick(time) end
local replacement_report=activity.report({include_trace=true,include_plan=true})
same_plan(replacement_report,b_plan,b_fast)
local observed=builder_actions(replacement_report,1);assert(#observed>0)
for _,row in ipairs(observed) do
    assert(row.accepted and row.builder_owned and row.builder_native_entity_valid and row.profile_matches
        and row.builder_entindex==replacement:entindex() and row.entity==replacement:entindex())
end
assert((old_builder.origin_reads or 0)==0,'Resolve replacement before GetOrigin, even when old IsNull reports false')
for _,order in ipairs(orders) do assert(order.UnitIndex~=old_builder:entindex()) end
activity.stop('builder_replacement_test')

-- Missing current builder is a refusal, not cached fallback. It does not
-- prevent a real owner/profile from consuming their modal or others acting.
reset('B');activity.prepare({seed=731,duration_seconds=120});old_builder=builders[1]
old_builder.native_invalid=true;builders[1]=nil;activity.start();open_offer(1,'missing_builder_offer')
local missing_open=last_open(activity.report({include_trace=true}),'missing_builder_offer')
for time=0,12,0.1 do tick(time) end
local missing_report=activity.report({include_trace=true,include_plan=true})
assert(offers[1].active==0 and not missing_report.owners[2].modal_active_observed,
    'Selecting an account-owned offer does not require an unrelated old builder proxy')
local selected=false
for _,row in ipairs(missing_report.offer_trace) do if row.kind=='offer_selection' and row.token=='missing_builder_offer' then
    assert(row.accepted and row.profile_matches and row.owner_eligible and row.builder_guard_required==false);selected=true
end end
assert(selected and missing_open.error==nil)
observed=builder_actions(missing_report,1);assert(#observed>0)
for _,row in ipairs(observed) do assert(not row.accepted and row.error=='builder_unavailable'
    and row.builder_owned==false and row.profile_matches) end
assert((old_builder.origin_reads or 0)==0)
for _,order in ipairs(orders) do assert(order.PlayerID~=1,'Absent builder submits no native order') end
for id=0,3 do if id~=1 then assert(missing_report.owners[id+1].steps>0) end end
builders[1]=unit(1,Vector(3000,4000,0));replacement=builders[1]
for time=12.1,30,0.1 do tick(time) end
local recovered_report=activity.report({include_trace=true,include_plan=true});same_plan(recovered_report,b_plan,b_fast)
local recovered=false
for _,row in ipairs(builder_actions(recovered_report,1)) do if row.elapsed>12 and row.accepted then
    assert(row.entity==replacement:entindex() and row.builder_owned and row.profile_matches);recovered=true
end end
assert(recovered,'Formal reappearance restores later planned builder operations without restarting the plan')
activity.stop('builder_missing_reappearance_test')

-- Even the current registered handle may have lost native validity. Guard
-- GetOrigin explicitly; IsNull alone must not mark this move successful.
reset('A');activity.prepare({seed=731,duration_seconds=120});old_builder=builders[1]
old_builder.native_invalid=true;activity.start()
for time=0,20,0.1 do tick(time) end
local invalid_report=activity.report({include_trace=true});observed=builder_actions(invalid_report,1)
assert(#observed>0 and (old_builder.origin_reads or 0)>0)
for _,row in ipairs(observed) do assert(not row.accepted and row.error=='builder_native_entity_invalid'
    and row.builder_owned and row.builder_native_entity_valid==false and row.profile_matches) end
for _,order in ipairs(orders) do assert(order.UnitIndex~=old_builder:entindex()) end
local invalid_reads=old_builder.origin_reads;builders[1]=unit(1,Vector(3000,4000,0))
for time=20.1,35,0.1 do tick(time) end
assert(old_builder.origin_reads==invalid_reads,'Once replaced, no later builder action reads the broken native object')
activity.stop('builder_native_validity_test')

-- An unrelated valid owner's current proxy is never accepted or ordered.
reset('B');activity.prepare({seed=731,duration_seconds=120});builders[1]=builders[2];activity.start()
for time=0,12,0.1 do tick(time) end
local wrong_owner=activity.report({include_trace=true});observed=builder_actions(wrong_owner,1);assert(#observed>0)
for _,row in ipairs(observed) do assert(not row.accepted and row.error=='builder_ownership_changed'
    and row.builder_owned==false and row.profile_matches) end
for _,order in ipairs(orders) do assert(order.PlayerID~=1) end
activity.stop('builder_cross_owner_test')

reset('B');activity.prepare({seed=731,duration_seconds=120});activity.start()
state=_G.SURVIVAL_FOUR_PLAYER_ACTIVITY;state.fixture.memory_profiles={}
for id=0,3 do state.fixture.memory_profiles[id]={account_id='builder_memory_'..id,revision=id+1,
    save={gameplay_stats={map_level=id*8+1}}} end
package.loaded['systems/player_profile_service'].get_profile=function(id)
    local expected=state.fixture.memory_profiles[id]
    return {account_id=expected.account_id,revision=expected.revision+(id==1 and 1 or 0),
        save={gameplay_stats=expected.save.gameplay_stats}}
end
for time=0,12,0.1 do tick(time) end
local wrong_profile=activity.report({include_trace=true});observed=builder_actions(wrong_profile,1);assert(#observed>0)
for _,row in ipairs(observed) do assert(not row.accepted and row.error=='builder_profile_changed'
    and row.profile_matches==false and row.profile_guard_verified and row.builder_owned==true,
    'Profile mismatch and legitimate builder ownership are independent evidence') end
package.loaded['systems/player_profile_service'].get_profile=profile_api
activity.stop('builder_profile_independent_audit_test')

reset('B');activity.prepare({seed=731,duration_seconds=120});activity.start();open_offer(1,'defeated_owner_offer')
defeated_players[1]=true;selections_before=selections()
for time=0,3,0.1 do tick(time) end
local ineligible=activity.report({include_trace=true})
assert(selections()==selections_before and offers[1].active==1 and ineligible.owners[2].steps==0
    and ineligible.owners[2].offer_block_reason=='offer_player_ineligible')
for _,row in ipairs(ineligible.offer_trace) do if row.kind=='offer_blocked' then
    assert(row.profile_matches and row.owner_eligible==false and row.builder_guard_required==false)
end end
for id=0,3 do if id~=1 then assert(ineligible.owners[id+1].steps>0) end end
activity.stop('offer_actual_owner_eligibility_test')
print('FOUR_PLAYER_ACTIVITY_BUILDER_LIFECYCLE_PASS: formal current proxy per build/move; replacement/no stale origin; absent/refusal/reappearance; native-invalid and cross-owner gates; independent profile/ownership audit; account modal excludes builder identity but rejects real eligibility failure; unchanged complete plans')
