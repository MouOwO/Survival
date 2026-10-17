package.path='scripts/vscripts/?.lua;'..package.path
local probe=require('tests/manual_builder_lifecycle_probe')
assert(_G.SURVIVAL_BUILDER_LIFECYCLE_PROBE==nil and probe.start().error=='probe_default_off')
local bus,events=require('core/event_bus'),require('core/events')
local mode,clock={},0
local tasks,builders,logs,context_owners={},{},{},{}
local real_print=print;print=function(message) logs[#logs+1]=message end
IsServer=function() return true end;IsInToolsMode=function() return true end
GetMapName=function() return 'template_map' end
GameRules={GetGameModeEntity=function() return mode end,GetGameTime=function() return clock end,State_Get=function() return 10 end}
package.loaded['core/scheduler']={every=function(interval,fn,key) tasks[key]={interval=interval,fn=fn} end,cancel=function(key) tasks[key]=nil end}
package.loaded['systems/player_context_service']={owner_player_id=function(u) return context_owners[u] end,
    is_defeated=function() return false end}
local function unit(index,name)
    local u={index=index,name=name,alive=true,health=1000,position={x=100,y=200,z=128}}
    function u:IsNull() return self.removed==true end
    function u:IsAlive() return self.alive end
    function u:entindex() return self.index end
    function u:GetUnitName() return self.name end
    function u:GetHealth() return self.health end
    function u:GetMaxHealth() return 1000 end
    function u:GetPlayerOwnerID() return -1 end
    function u:GetAbsOrigin() if self.invalid then error('Invalid object passed to GetOrigin') end;return self.position end
    function u:IsInvulnerable() return false end
    function u:ForceKill() error('Probe cannot kill') end
    function u:SetHealth() error('Probe cannot change health') end
    return u
end
local function reset()
    probe.stop('reset');bus.reset();clock=0;tasks,builders,logs,context_owners={},{},{},{}
    _G.SURVIVAL_BUILDER_LIFECYCLE_PROBE=nil;_G.SURVIVAL_REAL_GAME_STRESS_ISOLATION={mode=mode}
    bus.handle_request(events.BUILDER_GET_REQUEST,function(p)
        assert(p.caster==nil)
        return {ok=builders[p.player_id]~=nil,builder=builders[p.player_id],error=builders[p.player_id]==nil and 'builder_unavailable' or nil}
    end)
end
reset();local started=probe.start({enabled=true,duration_seconds=10})
assert(started.ok and started.interval_seconds==1 and started.no_attack_observation and started.native_removal_hook==false)
assert(tasks.manual_builder_lifecycle_probe.interval==1 and not next(builders),'Start before preparation must not create any builder')
local builder=unit(2263,'npc_survival_builder_proxy');builders[1]=builder;context_owners[builder]=1
bus.emit(events.BUILDER_READY,{player_id=1,builder=builder,auth_token='MUST_NOT_COPY'})
local s=probe.snapshot()
assert(s.event_total==1 and s.owners[2].registered_entindex==2263 and s.owners[2].formal_ok)
assert(s.owners[2].last_alive.health==1000 and s.owners[2].cached_body.invulnerable==false)
clock=1;builder.health=23;tasks.manual_builder_lifecycle_probe.fn()
assert(probe.snapshot().event_total==1,'Unchanged body identity/status does not spam periodic logs')
local enemy=unit(999,'npc_survival_wave_monster');context_owners[enemy]=2
builder.alive,builder.health=false,0
bus.emit(events.ENGINE_ENTITY_KILLED,{victim=builder,victim_entindex=2263,attacker=enemy,keys={auth_token='MUST_NOT_COPY'}})
s=probe.snapshot()
assert(s.owners[2].events.builder_native_death==1 and s.events[2].attacker.entindex==999
    and s.events[2].attacker.context_owner==2 and s.events[2].last_alive.health==23)
assert(s.events[2].native_keys_present==true and s.events[2].keys==nil)
clock=2;builder.removed=true;builders[1]=nil;tasks.manual_builder_lifecycle_probe.fn()
s=probe.snapshot()
assert(s.owners[2].events.body_transition==1 and not s.owners[2].formal_ok
    and s.owners[2].formal_error=='builder_unavailable' and s.owners[2].last_alive.health==23)
clock=3;tasks.manual_builder_lifecycle_probe.fn();assert(probe.snapshot().event_total==3)
local replacement=unit(3000,'npc_survival_builder_proxy');builders[1]=replacement;context_owners[replacement]=1
bus.emit(events.BUILDER_READY,{player_id=1,builder=replacement})
assert(probe.snapshot().owners[2].events.builder_replaced==1 and probe.snapshot().owners[2].registered_entindex==3000)
replacement.invalid=true;clock=4;tasks.manual_builder_lifecycle_probe.fn()
s=probe.snapshot();assert(s.owners[2].cached_body.native_origin_valid==false and s.owners[2].last_alive.native_origin_valid)
bus.emit(events.PLAYER_DISCONNECTED,{player_id=1,defeat_cleanup=true,auth_token='MUST_NOT_COPY'})
bus.emit(events.BUILDING_DESTROYED,{player_id=1,building_id='main_city',entindex=4000})
s=probe.snapshot();assert(s.owners[2].events.player_disconnected==1 and s.owners[2].events.building_destroyed==1)
local function private_free(v)
    if type(v)=='table' then for k,c in pairs(v) do assert(k~='auth_token' and k~='account_id' and k~='save' and k~='keys');private_free(c) end
    elseif type(v)=='string' then assert(not v:find('MUST_NOT_COPY',1,true)) end
end
private_free(s)
local external=0;bus.subscribe(events.PLAYER_DISCONNECTED,function() external=external+1 end)
local count=s.event_total;probe.stop('done');bus.emit(events.PLAYER_DISCONNECTED,{player_id=1})
assert(external==1 and probe.snapshot().event_total==count and tasks.manual_builder_lifecycle_probe==nil)
-- Native victim handle may be gone by dispatch; the previously registered
-- exact index still provides useful death evidence without inferring slot 0.
reset();probe.start({enabled=true,print_events=false,duration_seconds=10})
builder=unit(88,'npc_survival_builder_proxy');builders[2]=builder;context_owners[builder]=2
bus.emit(events.BUILDER_READY,{player_id=2,builder=builder})
bus.emit(events.ENGINE_ENTITY_KILLED,{victim_entindex=88})
assert(probe.snapshot().owners[3].events.builder_native_death==1)
for i=1,270 do bus.emit(events.BUILDING_DESTROYED,{player_id=2,building_id='wall',entindex=100+i}) end
s=probe.snapshot();assert(#s.events==256 and s.trace_dropped==16)
local old_callback=tasks.manual_builder_lifecycle_probe.fn
probe.stop('replace_world_observer');probe.start({enabled=true,print_events=false,duration_seconds=10})
assert(old_callback()==false and probe.snapshot().status=='running','Stale callback cannot stop the new observer')
_G.SURVIVAL_REAL_GAME_STRESS_ISOLATION={mode=mode};tasks.manual_builder_lifecycle_probe.fn()
assert(probe.snapshot().status=='stopped' and not probe.snapshot().current_world)
reset();probe.start({enabled=true,print_events=false,duration_seconds=10});clock=10
assert(tasks.manual_builder_lifecycle_probe.fn()==false and probe.snapshot().stop_reason=='duration_complete')
probe.stop('all_done');print=real_print
print('BUILDER_LIFECYCLE_PROBE_PASS: inert/before-prep; 1s transition-only diagnostics; registered actor/native death attacker and last alive HP; absent/replacement/invalid native; no spawn/damage/delete hooks; privacy/bounded ring; exact own stop; finite/current-world guards')
