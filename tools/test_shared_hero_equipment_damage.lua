-- Real production lifesteal/refresh/health guard and native lifecycle simulation.
-- Does not claim actual engine/FPS acceptance.
package.path='scripts/vscripts/?.lua;'..package.path
class=function(t) t.__index=t;return t end
local server,tools,map,world,now=true,true,'template_map',{},0
IsServer=function() return server end;IsInToolsMode=function() return tools end;GetMapName=function() return map end
GameRules={GetGameModeEntity=function() return world end,GetGameTime=function() return now end}
LUA_MODIFIER_MOTION_NONE,DOTA_TEAM_NEUTRALS=0,4
MODIFIER_EVENT_ON_TAKEDAMAGE,MODIFIER_EVENT_ON_ATTACK_START,MODIFIER_EVENT_ON_ATTACK=1,2,3
MODIFIER_EVENT_ON_ATTACK_FAIL,MODIFIER_EVENT_ON_ATTACK_LANDED=4,5
MODIFIER_PROPERTY_PREATTACK_BONUS_DAMAGE,MODIFIER_PROPERTY_ATTACKSPEED_BONUS_CONSTANT=11,12
MODIFIER_PROPERTY_HEALTH_BONUS,MODIFIER_PROPERTY_PHYSICAL_ARMOR_BONUS=13,14
MODIFIER_STATE_INVULNERABLE,MODIFIER_STATE_UNSELECTABLE,MODIFIER_STATE_NO_HEALTH_BAR,MODIFIER_STATE_OUT_OF_GAME=21,22,23,24
DOTA_DAMAGE_CATEGORY_ATTACK,DOTA_DAMAGE_CATEGORY_SPELL=1,0
Vector=function(x,y,z) return {x=x,y=y,z=z} end;LinkLuaModifier=function() end
local bus,events=require('core/event_bus'),require('core/events')
local canonical,stats={},{}
bus.handle_request(events.HERO_SUMMON_GET_REQUEST,function(p) local u=canonical[p.player_id];return u and {ok=true,unit=u,hero_id=u.survival_hero_id} or {ok=false} end)
bus.handle_request(events.EQUIPMENT_STATS_GET_REQUEST,function(p) return {snapshot={values=stats[p.player_id] or {}}} end)
package.loaded['systems/player_context_service']={owner_player_id=function(u) return u.context_owner end,
    is_owned_by=function(id,u) return u.context_owner==id end}
local carrier_service=require('systems/tower_damage_observer')
require('modifiers/modifier_tower_damage_observer');local carrier_class=modifier_tower_damage_observer
require('modifiers/modifier_equipment_effects');local gear_class=modifier_equipment_effects
assert(package.loaded['systems/hero_equipment_damage_observer']==nil,'Disabled equipment/carrier module load is lazy')
local shared=require('systems/hero_equipment_damage_observer')
local created,fresh,serial=0,true,0
local function native(holder) return setmetatable({GetParent=function() return holder end},carrier_class) end
CreateModifierThinker=function(_,_,name)
    created=created+1
    local holder={IsNull=function(self) return self.removed==true end,HasModifier=function(self,n) return n==name and not self.empty end}
    local mod=native(holder);assert(#mod:DeclareFunctions()==5,'No additional native carrier declarations')
    if fresh then mod:OnCreated() end;return holder
end
local function fixture(marker)
    world={};fresh=marker~=false;canonical={};stats={}
    _G.SURVIVAL_SHARED_HERO_EQUIPMENT_DAMAGE_PROBE=nil
    _G.SURVIVAL_REAL_GAME_STRESS_ISOLATION={mode=world}
    assert(carrier_service.init());local holder=world.survival_tower_damage_observer_holder
    return holder,native(holder)
end
local function hero(id)
    serial=serial+1
    local u={id=serial,survival_player_id=id,context_owner=id,native_owner=id,survival_hero_id='hero_'..id,
        health=20,max=100,alive=true,real=true,team=2,heal_calls={},survival_endless_health_scale=10}
    function u:IsNull() return self.removed==true end;function u:IsAlive() return self.alive end
    function u:entindex() return self.id end;function u:GetPlayerOwnerID() return self.native_owner end
    function u:IsRealHero() return self.real end;function u:IsIllusion() return self.illusion==true end;function u:IsClone() return self.clone==true end
    function u:GetTeamNumber() return self.team end;function u:GetHealth() return self.health end;function u:GetMaxHealth() return self.max end
    function u:SetHealth(v) self.health=v end
    function u:Heal(v,ability) self.heal_calls[#self.heal_calls+1]={amount=v,ability=ability};if self.alive then self.health=math.min(self.max,self.health+v) end end
    canonical[id]=u;stats[id]={lifesteal_pct=10,attack_flat=1000,attack_speed_pct=50,health_flat=150,armor_flat=60}
    return u
end
local function gear(u,declare)
    local mod=setmetatable({GetParent=function() return u end,IsNull=function(self) return self.removed==true end},gear_class)
    function mod:SetHasCustomTransmitterData(v) self.transmitter=v end
    function mod:SendBuffRefreshToClients() self.refreshes=(self.refreshes or 0)+1 end
    function mod:StartIntervalThink(v) self.interval=v end
    if declare~=false then mod.native_slots=mod:DeclareFunctions() end
    return mod
end
local function equal_props(slots)
    for i,v in ipairs({11,12,13,14}) do assert(slots[i]==v,'Original property order/value changed') end
end
local enemy={survival_endless_health_scale=20,IsNull=function() return false end,GetTeamNumber=function() return 3 end}
local friendly={IsNull=function() return false end,GetTeamNumber=function() return 2 end}
local stale={IsNull=function() return true end}
local function event(u,v,damage,category) return {attacker=u,unit=v or enemy,damage=damage or 20,damage_category=category or 1} end
local function deliver(native_mod,mod,p) mod:OnTakeDamage(p);native_mod:OnTakeDamage(p) end
local holder,global=fixture()
assert(world.survival_hero_equipment_damage_state==nil and #gear_class:DeclareFunctions()==5
    and gear_class.equipment_damage_mode_decided==nil,'Class/default-off query cannot alter native modes')
local u=hero(0);local legacy=gear(u);legacy:OnCreated({player_id=0});equal_props(legacy.native_slots)
assert(#legacy.native_slots==5 and not u.survival_shared_hero_equipment_damage_registration)
deliver(global,legacy,event(u));assert(#u.heal_calls==1 and u.heal_calls[1].amount==4)
assert(shared.set_probe(true));legacy:OnRefresh();assert(#legacy:DeclareFunctions()==5,'No old/refresh migration')
local early=gear(hero(1));assert(#early.native_slots==4 and early.shared_equipment_damage_observer)
local reg=early.equipment_damage_registration;assert(reg and reg.modifier==early,'First declaration registers before omission')
assert(shared.set_probe(false));early:OnCreated({player_id=1});assert(#early:DeclareFunctions()==4)
deliver(global,early,event(early:GetParent()));assert(#early:GetParent().heal_calls==1,'Off between Declare/Created retains route')
_G.SURVIVAL_REAL_GAME_STRESS_ISOLATION=nil;deliver(global,early,event(early:GetParent()))
assert(#early:GetParent().heal_calls==2,'Existing route survives removed guard in same world')
early:OnDestroy();early:OnDestroy();assert(reg.state.counters.unregistered==1 and not early:GetParent().survival_shared_hero_equipment_damage_registration)
holder,global=fixture();assert(shared.set_probe(true))
local units,mods={},{}
for id=0,3 do
    units[id+1]=hero(id);stats[id].lifesteal_pct=({10,25,50,100})[id+1]
    local mod=gear(units[id+1]);mod:OnCreated({player_id=id});mods[id+1]=mod;equal_props(mod.native_slots)
    assert(#mod.native_slots==4 and mod.interval==.25 and mod:GetModifierPreAttack_BonusDamage()==1000
        and mod:GetModifierAttackSpeedBonus_Constant()==50 and mod:GetModifierHealthBonus()==150
        and mod:GetModifierPhysicalArmorBonus()==require('config/armor_balance').from_war3(60))
end
for id=0,3 do
    local u,mod=units[id+1],mods[id+1]
    deliver(global,mod,event(u));assert(#u.heal_calls==1 and u.heal_calls[1].amount==({4,10,20,40})[id+1])
    -- Victim-based routing must not heal a hero merely because it is hit.
    global:OnTakeDamage({attacker=enemy,unit=u,damage=20,damage_category=1});assert(#u.heal_calls==1)
    deliver(global,mod,event(u,enemy,20,0));deliver(global,mod,event(u,friendly));deliver(global,mod,event(u,stale))
    deliver(global,mod,event(u,enemy,-10));assert(#u.heal_calls==1)
end
assert(shared.snapshot().counters.registered==4 and shared.snapshot().counters.active_registrations==4)
local changed=units[2];stats[1].lifesteal_pct=0;mods[2]:OnRefresh();deliver(global,mods[2],event(changed));assert(#changed.heal_calls==1)
stats[1].lifesteal_pct=100;mods[2]:OnRefresh()
local health_guard=require('core/hero_health_guard');changed.health=20
health_guard.protect_value(changed,20,'equipment_test')
deliver(global,mods[2],event(changed,enemy,100));assert(changed.health==100)
now=now+.2;require('core/scheduler').think();assert(changed.health==100,'Intentional lifesteal invalidates real deferred health rollback')
local deceased=units[3];deceased.alive=false;deceased.health=0
local before=#deceased.heal_calls;deliver(global,mods[3],event(deceased));assert(#deceased.heal_calls==before+1 and deceased.health==0,
    'No extra IsAlive filter: original dead-hero native Heal attempt remains unchanged')
local other_holder={IsNull=function() return false end,HasModifier=function() return true end,survival_hero_equipment_damage_observer_version=1}
native(other_holder):OnTakeDamage(event(units[1]));assert(#units[1].heal_calls==1,'Foreign native holder cannot duplicate dispatch')
local exact_token=mods[4].equipment_damage_registration_token;mods[4].equipment_damage_registration_token={}
local token_heals=#units[4].heal_calls;global:OnTakeDamage(event(units[4]));assert(#units[4].heal_calls==token_heals)
assert(not shared.unregister(mods[4]),'Unknown generation token cannot retire a legitimate registration')
mods[4].equipment_damage_registration_token=exact_token
local old=mods[1];local old_reg=old.equipment_damage_registration
local replacement=gear(units[1]);replacement:OnCreated({player_id=0});local replacement_reg=replacement.equipment_damage_registration
assert(replacement_reg~=old_reg);old:OnDestroy();assert(units[1].survival_shared_hero_equipment_damage_registration==replacement_reg)
deliver(global,replacement,event(units[1]));assert(#units[1].heal_calls==2)
local old_world=world;local old_count=old_world.survival_hero_equipment_damage_state.counters.routed
holder,global=fixture();global:OnTakeDamage(event(units[1]));assert(old_world.survival_hero_equipment_damage_state.counters.routed==old_count)
replacement:OnDestroy();assert(old_world.survival_hero_equipment_damage_state.counters.active_registrations==3,'Exact old-world teardown stays in stored state')
-- Upfront unavailable/old carrier, unknown role/owner and failures stay legacy.
holder,global=fixture(false);assert(shared.set_probe(true));local created_before=created
local old_holder_mod=gear(hero(0));assert(#old_holder_mod.native_slots==5 and created==created_before)
package.loaded['systems/hero_equipment_damage_observer']=nil;local reload=require('systems/hero_equipment_damage_observer')
assert(not reload.snapshot().carrier_ready,'Service reload must not fabricate native capability');shared=reload
holder,global=fixture();assert(shared.set_probe(true))
for _,kind in ipairs({'clone','illusion','creature','unknown_native','wrong_context','wrong_canonical','read_error'}) do
    local h=hero(0)
    if kind=='clone' then h.clone=true elseif kind=='illusion' then h.illusion=true elseif kind=='creature' then h.real=false
    elseif kind=='unknown_native' then h.native_owner=-1 elseif kind=='wrong_context' then h.context_owner=1
    elseif kind=='wrong_canonical' then canonical[0]=hero(1) elseif kind=='read_error' then h.IsRealHero=function() error('native unavailable') end end
    local mod=gear(h);assert(#mod.native_slots==5 and not h.survival_shared_hero_equipment_damage_registration,kind)
end
local lost=hero(0);holder.empty=true;local failed=gear(lost);holder.empty=false
failed:OnCreated({player_id=0});deliver(global,failed,event(lost));assert(#failed.native_slots==5 and #lost.heal_calls==1,
    'Registration failure keeps working original native lifesteal')
local commit_failure=hero(0)
setmetatable(commit_failure,{__newindex=function(t,k,v)
    if k=='survival_shared_hero_equipment_damage_registration' then error('native field assignment failed') end
    rawset(t,k,v)
end})
local uncommitted=gear(commit_failure);uncommitted:OnCreated({player_id=0})
deliver(global,uncommitted,event(commit_failure))
assert(#uncommitted.native_slots==5 and uncommitted.equipment_damage_registration==nil
    and uncommitted.equipment_damage_registration_token==nil and #commit_failure.heal_calls==1,
    'Failed atomic commit removes partial own pointers before keeping the native callback')
local oncreated=gear(hero(2),false);oncreated:OnCreated({player_id=2});assert(#oncreated:DeclareFunctions()==5,'Created-before-first-Declare locks legacy')
local refreshed=gear(hero(3),false);refreshed:OnRefresh();assert(#refreshed:DeclareFunctions()==5,'Unknown refreshed instance never migrates')
package.loaded['systems/hero_equipment_damage_observer']={register_new=function() return false end}
assert(#gear(hero(0)).native_slots==5,'Unknown false-returning service cannot commit an omitted declaration')
package.loaded['systems/hero_equipment_damage_observer']=shared
server=false;local client=gear(hero(0));equal_props(client.native_slots);assert(#client.native_slots==5 and client.equipment_damage_mode_decided==nil);server=true
tools=false;local production=gear(hero(0));assert(#production.native_slots==5 and production.equipment_damage_mode_decided==nil and not shared.set_probe(true));tools=true
map='other_map';assert(not shared.set_probe(true));map='template_map'
local before_snap=shared.snapshot();before_snap.counters.registered=999;assert(shared.snapshot().counters.registered~=999)
print('SHARED_HERO_EQUIPMENT_DAMAGE_PASS: default-off/lazy; same existing carrier five events; first Declare atomic registration or legacy; four unchanged properties; real scaled lifesteal/refresh/health guard; four exact attackers; spell/friendly/stale/negative filters; no native+shared duplicate; dead in-flight Heal attempt; off/guard persistence; old-marker/failure/class/client/production fallback; token replacement cleanup; cross-world refusal; no native/FPS claim')
