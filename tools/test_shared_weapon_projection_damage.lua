-- Real original projection, native carrier, event bus, resource wallet,
-- permanent damage rewards and weapon damage-growth consumers. Native dispatch
-- is simulated; native correctness/performance requires root's fresh-map run.
package.path='scripts/vscripts/?.lua;'..package.path
class=function(t) t.__index=t;return t end
local server,tools,map,world,now=true,true,'template_map',{},0
IsServer=function() return server end;IsInToolsMode=function() return tools end;GetMapName=function() return map end
GameRules={GetGameModeEntity=function() return world end,GetGameTime=function() return now end}
LUA_MODIFIER_MOTION_NONE,DOTA_TEAM_NEUTRALS=0,4
MODIFIER_EVENT_ON_TAKEDAMAGE,MODIFIER_EVENT_ON_ATTACK_START,MODIFIER_EVENT_ON_ATTACK=1,2,3
MODIFIER_EVENT_ON_ATTACK_FAIL,MODIFIER_EVENT_ON_ATTACK_LANDED,MODIFIER_EVENT_ON_ATTACK_RECORD=4,5,6
MODIFIER_PROPERTY_PREATTACK_BONUS_DAMAGE,MODIFIER_PROPERTY_BASE_ATTACK_TIME_CONSTANT=11,12
MODIFIER_PROPERTY_ATTACKSPEED_BONUS_CONSTANT,MODIFIER_PROPERTY_DAMAGEOUTGOING_PERCENTAGE=13,14
DOTA_DAMAGE_CATEGORY_ATTACK,DOTA_DAMAGE_CATEGORY_SPELL,DAMAGE_TYPE_PHYSICAL=1,0,1
OVERHEAD_ALERT_CRITICAL,OVERHEAD_ALERT_BONUS_SPELL_DAMAGE,OVERHEAD_ALERT_DAMAGE=21,22,23
Vector=function(x,y,z) return {x=x,y=y,z=z} end;LinkLuaModifier=function() end
local scheduler={after=function() end,every=function() end,cancel=function() end}
package.loaded['core/scheduler']=scheduler
local profiles={}
package.loaded['systems/player_profile_service']={get_profile=function(id) return profiles[id] end}
package.loaded['systems/technology_stat_manager']={training_room_multiplier=function() return 1 end}
local bus,ev=require('core/event_bus'),require('core/events')
local context=require('systems/player_context_service')
local carrier_service=require('systems/tower_damage_observer')
require('modifiers/modifier_tower_damage_observer');local Carrier=modifier_tower_damage_observer
require('modifiers/modifier_weapon_stat_projection');local C=modifier_weapon_stat_projection
assert(package.loaded['systems/weapon_projection_damage_observer']==nil,'Default class/carrier load remains lazy')
local probe=require('systems/weapon_projection_damage_observer')
local resources=require('systems/resource_system')
local permanent=require('systems/permanent_reward_effect_service')
local growth=require('systems/weapon_growth_service')
local defaults=require('config/generated/player_gameplay_stats')
local canonical,stats,created,serial,overheads,packets,crit_packets={},{},0,0,{},{},{}
PlayerResource={IsValidPlayerID=function(_,id) return id>=0 and id<=3 end,
    GetPlayer=function(_,id) return 'player'..id end}
SendOverheadEventMessage=function(player,style,target,amount) overheads[#overheads+1]={player=player,style=style,target=target,amount=amount} end
local rolls=0
RandomFloat=function(a,b) assert(a==0 and b==100);rolls=rolls+1;return 0 end
local secondary={}
modifier_weapon_attack_tracker={IsSecondaryAttackRecord=function(record) return secondary[record]==true end}
local function native(holder) return setmetatable({GetParent=function() return holder end},Carrier) end
local fresh_carrier=true
CreateModifierThinker=function(_,_,name)
    created=created+1
    local holder={IsNull=function(self) return self.removed==true end,
        HasModifier=function(self,n) return n==name and not self.empty end}
    local mod=native(holder);local slots=mod:DeclareFunctions()
    assert(#slots==5 and slots[1]==1 and slots[2]==2 and slots[3]==3 and slots[4]==4 and slots[5]==5,'Carrier remains exact five native slots')
    if fresh_carrier then mod:OnCreated() end
    return holder
end
local function actor(id,kind)
    serial=serial+1
    local u={id=serial,team=2,native_owner=id or -1,survival_player_id=id,real=kind=='hero',kind=kind,
        alive=true,survival_hero_id=kind=='hero' and 'hero_'..id or nil}
    function u:IsNull() return self.removed==true end;function u:IsAlive() return self.alive end
    function u:entindex() return self.id end;function u:GetPlayerOwnerID() if self.native_throw then error('native owner unknown') end return self.native_owner end
    function u:IsRealHero() return self.real end;function u:IsIllusion() return self.illusion==true end;function u:IsClone() return self.clone==true end
    function u:GetTeamNumber() return self.team end;function u:IsBuilding() return self.kind=='tower' end
    function u:GetOwnerEntity() return self.owner_entity end
    function u:GetPhysicalArmorValue(boolean) assert(boolean==false);return 9 end
    function u:AddNewModifier() return {} end
    function u:GetHealth() return self.health or 100 end;function u:GetMaxHealth() return self.max or 100 end
    return u
end
local function projection(u,declare)
    local m=setmetatable({GetParent=function() return u end,IsNull=function(self) return self.removed==true end},C)
    function m:SetHasCustomTransmitterData() end;function m:SendBuffRefreshToClients() end
    if declare~=false then m.native_slots=m:DeclareFunctions() end
    return m
end
local function init_fixture(marker)
    world={};now=0;canonical={};stats={};profiles={};packets={};overheads={};crit_packets={};secondary={};rolls=0
    server=true;tools=true;map='template_map';fresh_carrier=marker~=false
    _G.SURVIVAL_SHARED_WEAPON_PROJECTION_DAMAGE_PROBE=nil
    _G.SURVIVAL_REAL_GAME_STRESS_ISOLATION={mode=world}
    bus.reset()
    bus.handle_request(ev.HERO_SUMMON_GET_REQUEST,function(p) local u=canonical[p.player_id];return u and {ok=true,unit=u,hero_id=u.survival_hero_id} or {ok=false} end)
    bus.handle_request(ev.HERO_COMBAT_STATS_GET_REQUEST,function(p) return {ok=true,snapshot=stats[p.player_id] or {}} end)
    bus.handle_request(ev.CONTENT_INVENTORY_GET_REQUEST,function() return {ok=true,snapshot={counts={}}} end)
    require('systems/gameplay_phase_guard').reset()
    resources.init();permanent.init();growth.init()
    bus.subscribe(ev.COMBAT_DAMAGE_RESOLVED,function(p) packets[#packets+1]=p end)
    bus.subscribe(ev.HERO_FINAL_CRITICAL_ATTACK_DAMAGE,function(p) crit_packets[#crit_packets+1]=p end)
    for id=0,3 do
        local values={};for _,row in ipairs(defaults.rows) do values[row.field_id]=row.default_value end
        values.map_level=({1,9,17,24})[id+1];values.hero_damage_wood_flat=2+id;values.hero_damage_gold_flat=3+id
        values.hero_damage_wood_bonus_pct=0;values.hero_damage_attack_growth=5+id;values.hero_attributes_per_damage=10+id
        values.hero_execute_health_threshold_pct=0
        profiles[id]={mode='standard',revision=id+1,entitlements={},save={gameplay_stats=values,permanent_effects={},archive={completed={}}}}
        bus.emit(ev.PLAYER_PROFILE_CHANGED,{player_id=id,reason='test'})
    end
    assert(carrier_service.init());local h=world.survival_tower_damage_observer_holder
    return h,native(h)
end
local function hero(id)
    local u=actor(id,'hero');canonical[id]=u;stats[id]={critical_chance_pct=100,critical_damage_pct=200,
        base_attack_time=1.2,hero_attack_speed_bonus_pct=35,native_weapon_attack_bonus=50,native_research_attack_bonus=75}
    return u
end
local function initialize(m,id)
    m:OnCreated({player_id=id});m:OnRefresh()
    bus.emit(ev.HERO_SUMMONED,{player_id=id,unit=m:GetParent(),hero_id=m:GetParent().survival_hero_id})
    bus.emit(ev.WEAPON_EQUIPPED_CHANGED,{player_id=id,slot='main_hand',content_id='weapon_ice_blade_01',reason='test'})
end
local function equal_slots(m,shared)
    local expect={11,12,13,14,6};if not shared then expect[#expect+1]=1 end
    assert(#m.native_slots==#expect)
    for i,v in ipairs(expect) do assert(m.native_slots[i]==v,'Projection property/Record order preserved') end
end
local function delivery(native_mod,mods,p)
    -- Simulate only declared native slots, plus the one original carrier slot.
    for _,m in ipairs(mods) do
        for _,slot in ipairs(m.native_slots) do if slot==MODIFIER_EVENT_ON_TAKEDAMAGE then m:OnTakeDamage(p) end end
    end
    native_mod:OnTakeDamage(p)
end
local function damage(attacker,victim,extras)
    local p={attacker=attacker,unit=victim,damage=101,damage_category=DOTA_DAMAGE_CATEGORY_ATTACK,
        damage_type=DAMAGE_TYPE_PHYSICAL,record=100+attacker.id}
    for k,v in pairs(extras or {}) do p[k]=v end
    return p
end
local function wallet(id) return bus.request(ev.RESOURCE_GET_REQUEST,{player_id=id}) end
local function totals(id) return bus.request(ev.PERMANENT_REWARD_EFFECTS_GET_REQUEST,{player_id=id}).totals end
local function weapon(id) return bus.request(ev.WEAPON_GROWTH_GET_REQUEST,{player_id=id}).snapshot end
local checks=0
local function check(v,msg) checks=checks+1;assert(v,msg) end
local h,n=init_fixture();local enemy=actor(nil,'enemy');enemy.team=3
local legacy=projection(hero(0));initialize(legacy,0);equal_slots(legacy,false)
check(world.survival_weapon_projection_damage_state==nil and #C:DeclareFunctions()==6
    and C.weapon_projection_damage_mode_decided==nil,'class/default-off does not enable candidate')
delivery(n,{legacy},damage(canonical[0],enemy));check(#packets==1,'legacy original event still fires')
check(probe.set_probe(true),'explicit isolated opt-in')
legacy:OnRefresh();check(#legacy:DeclareFunctions()==6,'old instance never migrates')
local before_created=created
local units,mods={},{}
for id=0,3 do local u=hero(id);local m=projection(u);initialize(m,id);units[id+1]=u;mods[id+1]=m;equal_slots(m,true)
    check(m.shared_weapon_projection_damage_observer and m.weapon_projection_damage_route_reason=='shared_registered_at_first_declare','first declaration registered')
    check(m:GetModifierBaseAttackTimeConstant()==1.2 and m:GetModifierAttackSpeedBonus_Constant()==35
        and m:GetModifierPreAttack_BonusDamage()==125,'all original properties')
    local reg=m.weapon_projection_damage_registration;local registered=probe.snapshot().counters.registered
    m:DeclareFunctions();m:OnRefresh()
    check(#m:DeclareFunctions()==5 and m.weapon_projection_damage_registration==reg
        and probe.snapshot().counters.registered==registered,'Declare-Created-Refresh-Declare immutable registration exactly once')
end
check(created==before_created and probe.snapshot().counters.registered==4,'no extra native holder')
for id=0,3 do
    packets={};overheads={};crit_packets={};local u,m=units[id+1],mods[id+1]
    local old=wallet(id);local bonus=totals(id).hero_attack_flat;local w=weapon(id).growth_attack
    local p=damage(u,enemy);m:OnAttackRecord({attacker=u,record=p.record})
    check(m:GetModifierDamageOutgoing_Percentage()==100 and m:GetModifierDamageOutgoing_Percentage()==0,'native Record/one-time outgoing consumption unchanged')
    delivery(n,mods,p)
    check(#packets==1 and packets[1].player_id==id and packets[1].owner_hero==u and packets[1].attacker==u,'four known owners isolate notifications')
    local row=packets[1]
    check(row.attacker_entindex==u.id and row.victim_entindex==enemy.id and row.damage_kind=='attack' and row.damage_type==1
        and row.final_damage==101 and row.victim_armor==9 and row.ability_name=='' and row.target==enemy and row.damage_category==1,'full COMBAT payload unchanged')
    check(#overheads==1 and overheads[1].style==OVERHEAD_ALERT_CRITICAL and #crit_packets==1 and crit_packets[1].is_main_attack,'real critical overhead and public crit event')
    check(wallet(id).wood==old.wood+2+id and wallet(id).gold==old.gold+3+id
        and totals(id).hero_attack_flat==bonus+5+id and weapon(id).growth_attack==w+12,'real resource/permanent/weapon consumers advance exactly once')
    local pkt=#packets;delivery(n,mods,p)
    check(#packets==pkt+1 and #overheads==1 and #crit_packets==1,'real duplicate damage retains telemetry/rewards; only original overhead/crit dedup')
    for other=0,3 do if other~=id then check(probe.snapshot().owners[tostring(other)]==1,'other owner registration preserved') end end
end
check(rolls==4,'shared damage does not reroll critical records')
local u,m=units[1],mods[1]
packets={};overheads={};crit_packets={};secondary[987]=true;m:OnAttackRecord({attacker=u,record=987});m:GetModifierDamageOutgoing_Percentage()
delivery(n,mods,damage(u,enemy,{record=987}));check(#overheads==1 and #crit_packets==0,'secondary critical does not create main-attack proc')
local ability={IsNull=function() return false end,GetAbilityName=function() return 'fixture_fireball' end}
packets={};overheads={};delivery(n,mods,damage(u,enemy,{record=988,damage_category=0,inflictor=ability,damage_type=2}))
check(#packets==1 and packets[1].damage_kind=='ability' and packets[1].ability_name=='fixture_fireball'
    and packets[1].damage_category==0 and #overheads==1 and overheads[1].style==OVERHEAD_ALERT_DAMAGE,'SPELL zero category and valid inflictor ability overhead unchanged')
packets={};overheads={};delivery(n,mods,damage(u,enemy,{record=989,damage_category=0}))
check(#packets==1 and packets[1].damage_kind=='attack' and #overheads==0,'ability-less spell preserves original telemetry spelling and no ability overhead')
for _,kind in ipairs({'tower','worker','clone'}) do
    local owned=actor(2,kind);if kind=='clone' then owned.clone=true;owned.survival_monkey_king_clone=true end
    local before=weapon(2).growth_attack;local before_wallet=wallet(2);packets={};overheads={}
    delivery(n,mods,damage(owned,enemy))
    check(#packets==1 and packets[1].player_id==2 and packets[1].owner_hero==units[3] and #overheads==0,'nonhero owned '..kind..' telemetry preserved')
    check(wallet(2).wood==before_wallet.wood and wallet(2).gold==before_wallet.gold,'nonhero does not get exact-hero resource reward')
    check(weapon(2).growth_attack==before+(kind=='clone' and 12 or 0),'real clone damage-growth attribution; tower/worker excluded')
end
for _,case in ipairs({'unknown','native_error','conflict','invalid_player'}) do
    local a=actor(nil,'worker')
    if case=='native_error' then a.native_throw=true
    elseif case=='conflict' then check(context.register_unit(0,a),'formal register for conflict');a.survival_player_id=1
    elseif case=='invalid_player' then a.native_owner=8 end
    packets={};local before={};for id=0,3 do before[id]=wallet(id).wood end
    delivery(n,mods,damage(a,enemy))
    check(#packets==4,'unknown ownership retains four same-team notifications '..case)
    local got={};for _,p in ipairs(packets) do got[p.player_id]=(got[p.player_id] or 0)+1 end
    for id=0,3 do check(got[id]==1 and wallet(id).wood==before[id],'unknown own packet once/no fabricated hero rewards') end
end
packets={};local native_only=actor(nil,'worker');native_only.native_owner=1
delivery(n,mods,damage(native_only,enemy));check(#packets==1 and packets[1].player_id==1,'original native owner fallback is retained')
packets={};local friendly=actor(nil,'friendly');delivery(n,mods,damage(u,friendly));check(#packets==0,'same-team victim exclusion')
delivery(n,mods,damage(enemy,u));check(#packets==0,'enemy attacker exclusion')
delivery(n,mods,damage(u,enemy,{damage=0}));check(#packets==0,'zero damage exclusion')
u.alive=false;packets={};delivery(n,mods,damage(u,enemy));check(#packets==1,'death in-flight hit keeps original notification');u.alive=true
check(probe.set_probe(false),'disable new admission');_G.SURVIVAL_REAL_GAME_STRESS_ISOLATION={mode=world}
packets={};delivery(n,mods,damage(u,enemy));check(#packets==1,'off/changed guard cannot silence cached shared declaration')
local old=mods[1];local oldreg=old.weapon_projection_damage_registration;check(probe.set_probe(true),'rearm current guard')
local replacement=projection(u);initialize(replacement,0);check(replacement.shared_weapon_projection_damage_observer,'replacement generation registered')
old:OnDestroy();old:OnDestroy();check(u.survival_shared_weapon_projection_damage_registration==replacement.weapon_projection_damage_registration
    and oldreg.state.counters.unregistered==1,'old double destroy cannot erase replacement token')
mods[1]=replacement;packets={};delivery(n,mods,damage(u,enemy));check(#packets==1,'replacement emits once')
local stored=world;world={};packets={};n:OnTakeDamage(damage(u,enemy));check(#packets==0,'old world route refused')
replacement:OnDestroy();check(stored.survival_weapon_projection_damage_state.counters.active_shared==3,'old-world teardown exact stored state')
-- First-declaration failures permanently retain the complete native contract.
h,n=init_fixture(false);check(probe.set_probe(true),'old carrier explicit admission allowed but cannot register')
local no_marker=projection(hero(0));initialize(no_marker,0);equal_slots(no_marker,false)
delivery(n,{no_marker},damage(canonical[0],enemy));check(#packets==1,'old-marker fallback original handler')
h,n=init_fixture();check(probe.set_probe(true),'new candidate world')
for _,case in ipairs({'native_unknown','illusion','clone','wrong_canonical','read_failure','created_first'}) do
    local a=hero(0);if case=='native_unknown' then a.native_owner=-1 elseif case=='illusion' then a.illusion=true
    elseif case=='clone' then a.clone=true elseif case=='wrong_canonical' then canonical[0]=hero(1)
    elseif case=='read_failure' then a.IsRealHero=function() error('unknown role') end end
    local mod=projection(a,case~='created_first')
    if case=='created_first' then mod:OnCreated({player_id=0});mod.native_slots=mod:DeclareFunctions() end
    equal_slots(mod,false);mod:OnRefresh();check(#mod:DeclareFunctions()==6,'failure stays legacy '..case)
end
local a=hero(0);local commit=setmetatable(a,{__newindex=function(t,k,v)
    if k=='survival_shared_weapon_projection_damage_registration' then error('native field write rejected') end;rawset(t,k,v) end})
local failed=projection(commit);equal_slots(failed,false);check(not failed.weapon_projection_damage_registration,'atomic commit failure keeps native callback')
local state_before=probe.snapshot().counters.registered
server=false;local client=projection(hero(0));equal_slots(client,false);check(client.weapon_projection_damage_mode_decided==nil,'client props/Record/TakeDamage exactly original')
server=true;tools=false;local prod=projection(hero(0));equal_slots(prod,false);check(prod.weapon_projection_damage_mode_decided==nil,'nonTools never candidate');tools=true
check(probe.snapshot().counters.registered==state_before,'no hidden client/production admission')
-- Stable unknown-owner dispatch survives replacement/removal during synchronous
-- public-event delivery and never delivers to a newly registered generation.
h,n=init_fixture();check(probe.set_probe(true),'reentrant fixture')
mods={};for id=0,3 do mods[id+1]=projection(hero(id));initialize(mods[id+1],id) end
local captured_old=mods[3];local new_mod
local subscription=bus.subscribe(ev.COMBAT_DAMAGE_RESOLVED,function(p)
    if p.player_id==0 and not new_mod then local newest=hero(2);new_mod=projection(newest);initialize(new_mod,2);captured_old:OnDestroy() end
end)
packets={};delivery(n,mods,damage(actor(nil,'worker'),enemy));bus.unsubscribe(subscription)
check(#packets==3 and new_mod.shared_weapon_projection_damage_observer,'mid-dispatch new receiver not appended; removed old one not revived')
mods[3]=new_mod;packets={};delivery(n,mods,damage(actor(nil,'worker'),enemy));check(#packets==4,'subsequent unknown event sees new generation')
-- A failed receiver must not swallow other independent legacy notifications.
local broken_parent=mods[1]:GetParent();local original_team=broken_parent.GetTeamNumber;local err_token={}
broken_parent.GetTeamNumber=function() error(err_token,0) end
packets={};local ok,err=pcall(n.OnTakeDamage,n,damage(actor(nil,'worker'),enemy))
check(not ok and err==err_token and #packets==3,'original error object raised after other receivers delivered')
broken_parent.GetTeamNumber=original_team
local generation_state=world.survival_weapon_projection_damage_state;bus.reset()
packets={};n:OnTakeDamage(damage(actor(nil,'worker'),enemy));check(#packets==0 and probe.set_probe(true)==false
    and generation_state.counters.route_rejected>0,'same-world bus reset cannot borrow another session; reload required')
-- Mixed legacy/shared populations must not duplicate either route.
h,n=init_fixture();mods={};mods[1]=projection(hero(0));initialize(mods[1],0)
check(probe.set_probe(true),'mixed receiver fixture')
for id=1,3 do mods[id+1]=projection(hero(id));initialize(mods[id+1],id) end
packets={};delivery(n,mods,damage(canonical[0],enemy));check(#packets==1 and packets[1].player_id==0,'legacy known owner delivered only by native instance')
packets={};delivery(n,mods,damage(canonical[2],enemy));check(#packets==1 and packets[1].player_id==2,'shared known owner delivered only by carrier')
packets={};delivery(n,mods,damage(actor(nil,'worker'),enemy));check(#packets==4,'mixed unknown ownership exactly four independent original notifications')
local wrong=mods[2].weapon_projection_damage_registration_token
mods[2].weapon_projection_damage_registration_token={};packets={}
delivery(n,mods,damage(actor(nil,'worker'),enemy));check(#packets==3 and not probe.unregister(mods[2]),'foreign token cannot deliver or destroy a real registration')
mods[2].weapon_projection_damage_registration_token=wrong
local impostor={IsNull=function() return false end,HasModifier=function() return true end,
    survival_weapon_projection_damage_observer_version=1}
packets={};native(impostor):OnTakeDamage(damage(canonical[2],enemy));check(#packets==0,'non-authoritative holder cannot double-route')
-- Preserve the actual execution consumer behind COMBAT_DAMAGE_RESOLVED.
profiles[2].save.gameplay_stats.hero_execute_health_threshold_pct=25
bus.emit(ev.PLAYER_PROFILE_CHANGED,{player_id=2,reason='test_execution'})
local wounded=actor(nil,'enemy');wounded.team=3;wounded.health=10;wounded.max=100;local kills=0
function wounded:Kill(ability,killer) assert(ability==nil and killer==canonical[2]);kills=kills+1;self.alive=false end
packets={};delivery(n,mods,damage(canonical[2],wounded,{record=7777}))
check(kills==1 and not wounded:IsAlive() and #packets==1,'real threshold execution invoked once through unchanged public payload')
local guard=_G.SURVIVAL_REAL_GAME_STRESS_ISOLATION;_G.SURVIVAL_REAL_GAME_STRESS_ISOLATION=nil
check(probe.set_probe(true)==false,'missing guard never admits');_G.SURVIVAL_REAL_GAME_STRESS_ISOLATION=guard
map='other_map';check(probe.set_probe(true)==false,'other map never admits');map='template_map'
print('SHARED_WEAPON_PROJECTION_DAMAGE_PASS '..checks..' checks: real callbacks/resources/permanent/weapon growth; no native or FPS claim')
