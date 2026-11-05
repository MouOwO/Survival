-- Real growth producer and encounter UI bridge. No game/client/network IO.
package.path='scripts/vscripts/?.lua;'..package.path
if arg[1]then package.preload['ui/monster_encounter_ui_service']=function()return assert(loadfile(arg[1]))()end end
package.loaded['core/test_access_policy']={enabled=function()return false end}
local bus,events=require('core/event_bus'),require('core/events')
bus.reset()
local timers,listeners,sends={},{},{}
local native={valid=0,player=0,send=0}
package.loaded['core/scheduler']={every=function(_,callback,key)timers[key]=callback end}
local profile={mode='pure',revision=1,entitlements={},save={archive={},permanent_effects={},match_boss_effects={},
    gameplay_stats={hero_attributes_per_second=2.5,hero_attack_per_second=0.25}}}
package.loaded['systems/player_profile_service']={get_profile=function()return profile end}
local hero={IsNull=function()return false end,IsAlive=function()return true end}
bus.handle_request(events.HERO_SUMMON_GET_REQUEST,function(payload)assert(payload.player_id==0);return {hero=hero}end)
local player={}
PlayerResource={IsValidPlayerID=function(_,id)native.valid=native.valid+1;return id==0 end,
    GetPlayer=function(_,id)native.player=native.player+1;return id==0 and player or nil end,
    GetTeam=function()return 2 end}
CustomGameEventManager={RegisterListener=function(_,name,callback)listeners[name]=callback end,
    Send_ServerToPlayer=function(_,target,name,payload)
        native.send=native.send+1;assert(target==player)
        sends[#sends+1]={name=name,payload=payload}
    end}
local effects=require('systems/permanent_reward_effect_service')
local bridge=require('ui/monster_encounter_ui_service')
effects.init();bridge.init()
bus.emit(events.PLAYER_PROFILE_CHANGED,{player_id=0,reason='fixture_growth'})
assert(effects.value(0,'hero_attributes_per_second')==2.5 and effects.value(0,'hero_attack_per_second')==0.25,'actual configured growth rates must be initialized')
local valid_before,player_before,send_before=native.valid,native.player,native.send
local internal=0
bus.subscribe(events.HERO_PROGRESSION_CHANGED,function(payload)
    if payload.reason~='star_blessing_attributes_per_second'then return end
    internal=internal+1
    assert(payload.amount==2.5 and payload.attack_amount==0.25 and payload.tick==internal,
        'equal deltas at successive ticks remain distinct real rewards')
    local result=assert(bus.request(events.PERMANENT_REWARD_EFFECTS_GET_REQUEST,{player_id=0}))
    assert(result.totals.hero_all_attributes_flat==internal*2.5 and result.totals.hero_attack_flat==internal*0.25,
        'every real internal consumer sees the exact authoritative accumulated growth')
end)
for _=1,97 do timers.star_blessing_effect_ticks()end
assert(internal==97 and #sends==0 and native.send==send_before and native.valid==valid_before and native.player==player_before,
    '97 legal growth events must cause zero unused player/native network bridge calls: '..internal..'/'..native.valid..'/'..native.player..'/'..native.send..' baseline '..valid_before..'/'..player_before..'/'..send_before)
for _=1,4096 do timers.star_blessing_effect_ticks()end
assert(internal==4193 and #sends==0 and native.send==send_before and native.valid==valid_before and native.player==player_before,
    'larger growth history cannot increase unused network work or discard any delta')
local guard=require('systems/gameplay_phase_guard')
guard.set_post_clear_frozen(true);timers.star_blessing_effect_ticks()
assert(internal==4193 and #sends==0,'existing post-clear reward freeze remains intact')
guard.reset()

-- Other monster encounter messages still have their existing consumers and
-- operation contracts; retiring growth forwarding must not silence them.
bus.handle_request(events.MONSTER_ENCOUNTER_START_REQUEST,function(payload)
    assert(payload.player_id==0 and payload.team==2 and payload.encounter_id=='fixture')
    return {ok=true,started=true}
end)
bus.handle_request(events.MONSTER_ENCOUNTER_QUERY_REQUEST,function(payload)
    assert(payload.player_id==0 and payload.encounter_id=='fixture')
    return {ok=true,available=true}
end)
listeners.ui_monster_encounter_start_request(nil,{PlayerID=0,encounter_id='fixture'})
listeners.ui_monster_encounter_query_request(nil,{PlayerID=0,encounter_id='fixture'})
assert(#sends==2 and sends[1].name=='ui_monster_encounter_operation_result'and sends[1].payload.started
    and sends[2].payload.available)
local encounter={player_id=0,state='complete'};local reward={player_id=0,reward_id='synthetic'}
bus.emit(events.MONSTER_ENCOUNTER_CHANGED,encounter);bus.emit(events.MONSTER_REWARD_GRANTED,reward)
assert(#sends==4 and sends[3].name=='ui_monster_encounter_state'and sends[3].payload==encounter
    and sends[4].name=='ui_monster_reward_granted'and sends[4].payload==reward)
local final={player_id=0,reason='reward_applied',all_attributes=42,pending_skill_rewards={}}
bus.emit(events.HERO_PROGRESSION_CHANGED,final)
assert(#sends==4 and final.all_attributes==42,'other internal progression shapes remain local and unmodified')
print('HERO_GROWTH_UI_BRIDGE_PASS: 4193 true growth rewards preserved; zero unused native/UI calls; encounter/reward contracts intact; no online/native/FPS acceptance claimed')
