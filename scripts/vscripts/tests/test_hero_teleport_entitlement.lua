-- Real profile binding, skill projection and both teleport entry points.
-- Native transport/particles are simulated; no account grants or real network.
package.path = 'scripts/vscripts/?.lua;' .. package.path
package.loaded['config/test_access'] = {enabled=false,allowed_steamids={}}
local bus,events = require('core/event_bus'),require('core/events')
local now,mode,session,world = 0,'standard','synthetic_teleport_match',{}
local accounts,tasks,fetches,after = {[0]='synthetic_account_a',[1]='synthetic_account_b'},{},{},{}
package.loaded['systems/match_setup_service']={get_mode=function()return mode end,
    get_session_id=function()return session end,is_mode_selected=function()return mode~=nil end}
package.loaded['core/logger']={info=function()end,warn=function()end,error=function()end}
package.loaded['core/scheduler']={every=function(_,f,key)tasks[key]=f end,
    after=function(_,f)after[#after+1]=f end,cancel=function()end}
package.loaded['systems/player_entitlement_service']={replace_all=function()end}
package.loaded['systems/player_profile_providers/http_fishing_provider']={init=function()end,
    resolve_account_id=function(id)return accounts[id]end,
    fetch_snapshot=function(account,success,failure)fetches[#fetches+1]={account=account,success=success,failure=failure}end}
package.loaded['systems/player_context_service']={is_defeated=function()return false end,active_player_ids=function()return {0}end}
package.loaded['systems/worker_system']={refresh_commerce_capacity=function()end}
package.loaded['systems/gameplay_phase_guard']={post_clear_frozen=function()return false end}
GameRules={GetGameTime=function()return now end,GetGameModeEntity=function()return world end}
PlayerResource={IsValidPlayerID=function(_,id)return accounts[id]~=nil end,GetSteamAccountID=function(_,id)return accounts[id]end}
local table_writes,last_tables=0,{}
CustomNetTables={SetTableValue=function(_,name,key,value)table_writes=table_writes+1;last_tables[name..key]=value end}
CustomGameEventManager={RegisterListener=function()end}
class=function(t)return t end
IsServer=function()return true end
UF_SUCCESS=0;UF_FAIL_CUSTOM=1;PATTACH_WORLDORIGIN=0
Vector=function(x,y,z)return {x=x,y=y,z=z or 0}end
GetGroundHeight=function()return 0 end
local moves,can_land,particles=0,true,0
package.loaded['systems/blink_destination']={clamp=function(_,target)return target,100 end}
package.loaded['systems/destination_validation_service']={validate=function()return can_land end,
    teleport=function(unit,target)if not can_land then return false,'blocked' end;unit.pos=target;moves=moves+1;return true end}
ParticleManager={CreateParticle=function()particles=particles+1;return particles end,
    SetParticleControl=function()end,DestroyParticle=function()end,ReleaseParticleIndex=function()end}
package.loaded['systems/combat_effect_visibility']={manager=function()return ParticleManager end}
ProjectileManager={ProjectileDodge=function()end}
local profiles=require('systems/player_profile_service')
local effects=require('systems/commerce_effects')
local access=require('systems/hero_teleport_access')
local native=require('abilities/ability_survival_hero_ball_lightning')
local builder_blink=require('abilities/ability_survival_builder_blink')
profiles.init()
local function snapshot(revision,count,inventory)
    inventory=inventory or {};inventory[effects.ids.teleporter]=count
    return {schema_version=1,account_id=accounts[0],revision=revision,mode=mode,match_session_id=session,
        progression={loaded=true,clear_counts={}},entitlements={},achievements={},public={},
        save={gameplay_stats={},archive={},content_inventory=inventory}}
end
local function patch(base,count)
    return {schema_version=1,account_id=accounts[0],mode=mode,match_session_id=session,
        update_id='synthetic_teleport_'..base,base_revision=base,revision=base+1,
        changes={save={content_inventory={[effects.ids.teleporter]=count}}}}
end
local units,index={},100
local function hero(id)
    index=index+1
    local unit={survival_hero_id='hero_axe',survival_player_id=id,index=index,
        abilities={},slots={},pos=Vector(0,0,0),mana=100,writes=0,finds=0,adds=0}
    function unit:IsNull()return self.removed==true end
    function unit:IsAlive()return true end
    function unit:entindex()return self.index end
    function unit:GetPlayerOwnerID()return id end
    function unit:GetAbsOrigin()return self.pos end
    function unit:GetHealth()return 100 end
    function unit:GetMaxHealth()return 100 end
    function unit:CalculateStatBonus()end
    function unit:SetAbilityPoints()end
    function unit:Stop()end
    function unit:EmitSound()end
    function unit:StopSound()end
    function unit:GetAbilityCount()return #self.slots end
    function unit:GetAbilityByIndex(slot)return self.slots[slot+1]end
    function unit:FindAbilityByName(name)self.finds=self.finds+1;return self.abilities[name]end
    function unit:RemoveAbility()error('This receipt must not rebuild unrelated hero skills')end
    function unit:AddAbility(name)
        self.adds=self.adds+1
        local ability=setmetatable({name=name,level=0,hidden=false,active=true,until_time=0,
            native_cooldown_writes=0,refunds=0}, {__index=name==access.ABILITY and native or {}})
        function ability:IsNull()return false end
        function ability:GetAbilityName()return self.name end
        function ability:GetCaster()return unit end
        function ability:GetCursorPosition()return Vector(100,0,0)end
        function ability:GetLevel()return self.level end
        function ability:SetLevel(value)self.level=value;unit.writes=unit.writes+1 end
        function ability:IsHidden()return self.hidden end
        function ability:SetHidden(value)self.hidden=value;unit.writes=unit.writes+1 end
        function ability:IsActivated()return self.active end
        function ability:SetActivated(value)self.active=value;unit.writes=unit.writes+1 end
        function ability:GetCooldownTimeRemaining()return math.max(0,self.until_time-now)end
        function ability:StartCooldown(value)self.until_time=now+value;self.native_cooldown_writes=self.native_cooldown_writes+1 end
        function ability:EndCooldown()self.until_time=now end
        function ability:RefundManaCost()unit.mana=unit.mana+20;self.refunds=self.refunds+1 end
        self.abilities[name],self.slots[#self.slots+1]=ability,ability
        return ability
    end
    return unit
end
local function flush()
    while #after>0 do local current=after;after={};for _,f in ipairs(current)do f()end end
end
assert(profiles.apply_snapshot(0,snapshot(1,0)).ok)
require('systems/hero_skill_system').init()
local unit=hero(0);units[0]=unit
bus.handle_request(events.HERO_SUMMON_GET_REQUEST,function(p)return {unit=units[p.player_id]}end)
bus.emit(events.HERO_SUMMONED,{player_id=0,hero_id='hero_axe',unit=unit});flush()
local ability=assert(unit.abilities[access.ABILITY])
local runtime=require('systems/commerce_runtime');runtime.init()
assert(ability.hidden and not ability.active,'A free hero must not grant the paid utility')
assert(ability:CastFilterResultLocation(Vector(100,0,0))==UF_FAIL_CUSTOM)
local function native_cast()
    -- Simulate the engine starting its declared CD and spending mana before
    -- OnSpellStart; assert Lua rollback against that native lifecycle boundary.
    unit.mana=unit.mana-20;ability.until_time=now+ability:GetCooldown(1);ability:OnSpellStart()
end
native_cast();assert(moves==0 and particles==0 and unit.mana==100 and ability:GetCooldownTimeRemaining()==0)
runtime.action({PlayerID=0,action='blink',x=100,y=0});assert(moves==0)
local adds=unit.adds
assert(profiles.apply_incremental(patch(1,1)).ok and ability.active and not ability.hidden)
assert(last_tables.survival_commerce_actionsplayer_0.blink==1,'The committed grant immediately updates custom D capability')
assert(unit.adds==adds,'Receiving an item must update one utility without rebuilding skills')
local writes,network_writes=unit.writes,table_writes
for i=1,50 do bus.emit(events.PLAYER_PROFILE_CHANGED,{player_id=0,reason='same_state'})end
assert(unit.writes==writes,'Identical profile events must not repeat native setters')
assert(table_writes==network_writes,'Identical profile events must not repeat NetTable setters')
local finds=unit.finds
bus.emit(events.PLAYER_PROFILE_CHANGED,{player_id=1})
assert(unit.finds==finds,'An unrelated player event must not query this hero')
native_cast();assert(moves==1 and unit.mana==80 and access.ready_at(0)==10)
assert(last_tables.survival_commerce_actionsplayer_0.cooldown==10,'The native cast publishes the shared CD immediately')
assert(ability.native_cooldown_writes==0,'The native engine already started the same ten-second cooldown')
runtime.action({PlayerID=0,action='blink',x=100,y=0});assert(moves==1,'Custom action cannot bypass native CD')
native_cast();assert(moves==1 and unit.mana==80 and ability:GetCooldownTimeRemaining()==10,
    'A forced duplicate cast refunds its mana and preserves the prior shared cooldown')
now=10;runtime.action({PlayerID=0,action='blink',x=200,y=0})
assert(moves==2 and ability:GetCooldownTimeRemaining()==10)
assert(ability:CastFilterResultLocation(Vector(100,0,0))==UF_FAIL_CUSTOM,'Native cast cannot bypass custom action CD')
now=21;can_land=false
runtime.action({PlayerID=0,action='blink',x=200,y=0});assert(access.remaining(0)==0 and moves==2)
native_cast();assert(unit.mana==80 and ability:GetCooldownTimeRemaining()==0 and moves==2)
can_land=true;native_cast();assert(moves==3 and unit.mana==60)
assert(profiles.apply_incremental(patch(2,0)).ok and ability.hidden and not ability.active)
assert(last_tables.survival_commerce_actionsplayer_0.blink==0,'Revocation immediately closes the custom D capability')
assert(not access.owned(0),'The paid item need only be owned; revocation must also be immediate')

-- A builder never enters the hero utility boundary or requires this item.
local builder={pos=Vector(0,0,0),IsNull=function()return false end,Stop=function()end,
    GetAbsOrigin=function(self)return self.pos end}
local b=setmetatable({GetCaster=function()return builder end,GetCursorPosition=function()return Vector(100,0,0)end},{__index=builder_blink})
assert(b:CastFilterResultLocation(Vector(100,0,0))==UF_SUCCESS)
b:OnSpellStart();assert(moves==4)

-- Live scalar binding rejects an old account/session without waiting for UI.
now=40
local old_unit,old_ability=unit,ability
bus.emit(events.HERO_REMOVED,{player_id=0,unit=old_unit,entindex=old_unit.index})
unit=hero(0);units[0]=unit
bus.emit(events.HERO_SUMMONED,{player_id=0,hero_id='hero_axe',unit=unit});flush()
ability=assert(unit.abilities[access.ABILITY])
assert(ability.hidden and not ability.active)
local before_moves=moves
old_ability:OnSpellStart()
assert(moves==before_moves,'A retained old hero handle cannot use the replacement hero entitlement')
local old_writes=old_unit.writes
bus.emit(events.HERO_REMOVED,{player_id=0,unit=old_unit,entindex=old_unit.index})
assert(bus.request(events.HERO_SKILL_STATE_GET_REQUEST,{player_id=0}).snapshot.unit_entindex==unit.index,
    'A stale removal cannot erase the replacement hero')
assert(profiles.refresh_player(0,'synthetic_old_fetch').pending)
local stale=snapshot(99,1)
accounts[0]='synthetic_replacement_account'
assert(not access.owned(0))
assert(profiles.load_player(0,'synthetic_new_fetch').pending)
fetches[2].success(snapshot(1,0))
fetches[1].success(stale)
assert(not access.owned(0) and ability.hidden and not ability.active,'Late old-account reply must not unlock the replacement account')
assert(old_unit.writes==old_writes,'Profile receipts must not write to the replaced hero')
local old_session=snapshot(2,1)
session='synthetic_replacement_session'
assert(not access.owned(0))
assert(not profiles.apply_snapshot(0,old_session).ok and not access.owned(0))
mode='pure'
local pure=snapshot(3,0)
pure.account_profile=snapshot(3,1);pure.account_profile.mode=nil;pure.account_profile.match_session_id=nil;pure.account_profile.progression=nil
assert(profiles.apply_snapshot(0,pure).ok and not access.owned(0),'Account/UI ownership cannot bypass the pure combat inventory')

-- 1,000 scalar checks cost the same with 1 or 10,001 inventory entries.
mode='standard';session='synthetic_scaling_session'
local scalar_reads,full_reads=0,0
local scalar,full=profiles.get_content_inventory_count,profiles.get_profile
profiles.get_content_inventory_count=function(...)scalar_reads=scalar_reads+1;return scalar(...)end
profiles.get_profile=function(...)full_reads=full_reads+1;return full(...)end
for _,size in ipairs({0,10000})do
    local inventory={};for i=1,size do inventory['synthetic_item_'..i]=1 end
    assert(profiles.apply_snapshot(0,snapshot(10+size,1,inventory)).ok)
    scalar_reads=0;full_reads=0
    for i=1,1000 do assert(access.owned(0))end
    assert(scalar_reads==1000 and full_reads==0)
end
tasks.commerce_runtime();local before=table_writes
for i=1,10 do tasks.commerce_runtime()end
assert(table_writes==before,'Stable commerce refresh must not resend the same NetTable')
bus.reset();now=0
assert(access.ready_at(0)==0,'A new event generation must discard the previous match cooldown')
print('HERO_TELEPORT_ENTITLEMENT_PASS: real profile binding/receipts, free hero locked, inventory grant/revoke, shared native/custom CD, rollback mana/CD, builder unchanged, stale account/session and pure isolation')
print('HERO_TELEPORT_COST_PASS: inventory=1/10001; checks=1000; scalar_reads=1000; full_profile_reads=0; repeated_profile_setters=0; stable_10_refresh_NetTable_writes=0; native/FPS NOT_MEASURED')
