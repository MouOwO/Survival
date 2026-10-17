-- API simulations exercise the real production lifesteal handler; no claim of
-- actual Dota engine execution. Root must run the explicit Tools verifier.
package.path='scripts/vscripts/?.lua;'..package.path
class=function(t) t.__index=t;return t end
IsServer=function() return true end;IsInToolsMode=function() return true end;GetMapName=function() return 'template_map' end
DOTA_DAMAGE_CATEGORY_ATTACK,DOTA_DAMAGE_CATEGORY_SPELL=1,0
DOTA_TEAM_GOODGUYS,DOTA_TEAM_BADGUYS=2,3
DOTA_UNIT_CAP_NO_ATTACK,DOTA_UNIT_CAP_MOVE_NONE,DAMAGE_TYPE_MAGICAL=0,0,2
Vector=function(x,y,z) return {x=x,y=y,z=z} end
local now,world,units,mods,counts,tasks,serial=0,{}, {},{},{},{},0
GameRules={GetGameTime=function() return now end,GetGameModeEntity=function() return world end}
local scheduler={}
function scheduler.after(delay,fn,id) id=id or 'unnamed';tasks[id]={at=now+delay,fn=fn};return id end
function scheduler.cancel(id) tasks[id]=nil end
package.loaded['core/scheduler']=scheduler
package.loaded['systems/match_setup_service']={get_session_id=function() return 'session' end,get_mode=function() return 'standard' end}
package.loaded['systems/player_context_service']={owner_player_id=function(u) return u.owner end,is_owned_by=function(id,u) return id==u.owner end}
local bus,ev=require('core/event_bus'),require('core/events')
require('modifiers/modifier_equipment_effects');local C=modifier_equipment_effects;local actual_handle=C.HandleTakeDamage
local q=require('tests/manual_native_equipment_lifesteal')
local created,removed,grants,transactions,native_attacks,native_spells=0,0,0,0,0,0
local options={}
local function method(u,key) u[key]=function(self,v) self[key..'_value']=v end end
local function entity(owner,team)
    serial=serial+1
    local u={owner=owner,survival_player_id=owner,team=team,health=900,max=1000,position=Vector(100,200,300),id=serial,
        survival_endless_health_scale=owner~=nil and 10 or 20,heals={}}
    function u:IsNull() return self.removed==true end;function u:IsAlive() return not self.removed end
    function u:IsRealHero() return self.owner~=nil end;function u:IsIllusion() return false end;function u:IsClone() return false end
    function u:GetPlayerOwnerID() return self.owner end;function u:GetTeamNumber() return self.team end
    function u:FindModifierByName() return mods[self.owner] end
    function u:GetHealth() return self.health end;function u:GetMaxHealth() return self.max end
    function u:SetHealth(hp) self.health=hp end;function u:SetMaxHealth(hp) self.max=hp end
    function u:GetAbsOrigin() return self.position end
    function u:IsChanneling() return false end;function u:GetAttackTarget() return nil end
    function u:CanEntityBeSeenByMyTeam() return options.invisible~=true end
    function u:Heal(amount,...)
        self.heals[#self.heals+1]={amount=amount,args=select('#',...)}
        if options.bad_heal~=true then self.health=math.min(self.max,self.health+amount) end
        return 'native_heal_return',nil,7
    end
    for _,k in ipairs({'SetIdleAcquire','SetAcquisitionRange','SetAttackCapability','SetMoveCapability','SetBaseDamageMin',
        'SetBaseDamageMax','SetBaseMaxHealth','SetDeathXP','SetMinimumGoldBounty','SetMaximumGoldBounty'}) do method(u,k) end
    function u:PerformAttack(target,orb,procs,skip,ignore,projectile,fake,nevermiss)
        assert(orb==false and procs==false and skip==true and ignore==true and projectile==false and fake==false and nevermiss==true)
        native_attacks=native_attacks+1
        if options.missing_event or target.team==self.team and options.friendly_blocked then return end
        local damage=options.damage or 75;target.health=target.health-damage
        -- This is the simulated native dispatcher, not a verifier shortcut.
        C.HandleTakeDamage(mods[self.owner],{attacker=self,unit=target,damage=damage,damage_category=DOTA_DAMAGE_CATEGORY_ATTACK})
    end
    return u
end
bus.handle_request(ev.HERO_SUMMON_GET_REQUEST,function(p) return {ok=true,unit=units[p.player_id],hero_id='fixture_hero_'..p.player_id} end)
bus.handle_request(ev.EQUIPMENT_STATS_GET_REQUEST,function(p)
    return {ok=true,snapshot={values={lifesteal_pct=(counts[p.player_id].item_death_mask or 0)*50}}}
end)
bus.handle_request(ev.CONTENT_INVENTORY_GET_REQUEST,function(p) return {ok=true,snapshot={counts=counts[p.player_id]}} end)
bus.handle_request(ev.CONTENT_INVENTORY_GRANT_REQUEST,function(p)
    assert(p.content_id=='item_death_mask' and p.count==1 and p.gameplay_stat_effects==nil)
    grants=grants+1;counts[p.player_id].item_death_mask=(counts[p.player_id].item_death_mask or 0)+1
    mods[p.player_id]:OnRefresh();return {ok=true}
end)
bus.handle_request(ev.CONTENT_INVENTORY_TRANSACTION_REQUEST,function(p)
    assert(p.consume.item_death_mask==1 and next(p.grant)==nil)
    transactions=transactions+1;counts[p.player_id].item_death_mask=counts[p.player_id].item_death_mask-1
    mods[p.player_id]:OnRefresh();return {ok=true}
end)
local precache_callback
PrecacheUnitByNameAsync=function(name,callback,player)
    assert(name=='npc_dota_creep_badguys_melee' and player==-1);precache_callback=callback
    if not options.delayed_precache then scheduler.after(.05,callback,'mock_precache') end
end
CreateUnitByName=function(name,pos,clear,owner1,owner2,team)
    assert(name=='npc_dota_creep_badguys_melee' and owner1==nil and owner2==nil)
    created=created+1;local u=entity(nil,team);u.position=pos;return u
end
AddFOWViewer=function(team,position,radius,duration) assert(team==2 and radius==400 and duration==12) end
UTIL_Remove=function(u) assert(u.survival_native_equipment_lifesteal_target_token);removed=removed+1;u.removed=true end
ApplyDamage=function(p)
    native_spells=native_spells+1;assert(p.damage_type==DAMAGE_TYPE_MAGICAL and p.damage==100)
    p.victim.health=p.victim.health-25
    C.HandleTakeDamage(mods[p.attacker.owner],{attacker=p.attacker,unit=p.victim,damage=25,damage_category=DOTA_DAMAGE_CATEGORY_SPELL})
    return 25
end
local function fresh(opts)
    if _G.SURVIVAL_NATIVE_EQUIPMENT_LIFESTEAL_VERIFIER and not _G.SURVIVAL_NATIVE_EQUIPMENT_LIFESTEAL_VERIFIER.stopped then q.stop() end
    _G.SURVIVAL_NATIVE_EQUIPMENT_LIFESTEAL_VERIFIER=nil
    options=opts or {};now=0;world={};tasks={};units={};mods={};counts={};created=0;removed=0;grants=0;transactions=0;native_attacks=0;native_spells=0
    C.HandleTakeDamage=actual_handle
    _G.SURVIVAL_REAL_GAME_STRESS_ISOLATION={mode=world}
    for id=0,3 do
        local u=entity(id,2);units[id]=u;counts[id]={weapon_growth_sword_01=1}
        local m=setmetatable({GetParent=function() return u end,IsNull=function() return false end,shared_equipment_damage_observer=true,
            server_values={lifesteal_pct=0},player_id=id,equipment_damage_mode_decided=true},C)
        function m:SendBuffRefreshToClients() end
        local r={unit=u,modifier=m,world=world,token={}}
        m.equipment_damage_registration=r;m.equipment_damage_registration_token=r.token;u.survival_shared_hero_equipment_damage_registration=r
        mods[id]=m
    end
end
local function advance(seconds)
    local until_time=now+seconds
    while now<until_time do now=now+.05;local due={}
        for key,t in pairs(tasks) do if t.at<=now then due[#due+1]={key=key,task=t} end end
        table.sort(due,function(a,b) return a.key<b.key end)
        for _,d in ipairs(due) do if tasks[d.key]==d.task then tasks[d.key]=nil;d.task.fn() end end
    end
end
local checks=0
local function check(condition,why) checks=checks+1;assert(condition,why) end
fresh();check(q.snapshot().status=='not_started' and q.start().default_off and created==0 and grants==0,'require/default inert')
for owner=0,3 do
    fresh();local hero=units[owner];local old_heal=hero.Heal;local old_handle=C.HandleTakeDamage
    q.start({enabled=true,owner=owner});advance(2)
    local r=q.snapshot()
    check(r.status=='completed' and r.native_passed,'simulated native sequence')
    check(#r.phases==4 and r.phases[1].actual_equipment_heals==1 and r.phases[1].events[1].heals[1].amount==75,'real production scale-aware lifesteal')
    check(r.phases[2].actual_equipment_heals==0 and r.phases[3].actual_equipment_heals==0 and r.phases[4].actual_equipment_heals==0,'spell/friendly/removal no heal')
    check(native_attacks==3 and native_spells==1 and created==2 and removed==2,'bounded true-operation API requests')
    check(grants==1 and transactions==1 and counts[owner].item_death_mask==0 and hero.health==900,'own match inventory and HP restore')
    check(hero.Heal==old_heal and C.HandleTakeDamage==old_handle and next(tasks)==nil,'exact own method shape restoration and tasks canceled')
    for id=0,3 do if id~=owner then check(units[id].health==900 and #units[id].heals==0 and counts[id].item_death_mask==nil,'other owners untouched') end end
    check(r.phases[1].target==nil and r.original_position.x==100 and r.cleanup.position_unchanged,'no native handles and no actor orders/position writes')
end
fresh({damage=2000});q.start({enabled=true});advance(2)
check(q.snapshot().native_passed and q.snapshot().phases[1].events[1].heals[1].amount==2000
    and q.snapshot().phases[1].events[1].heals[1].health_after==1000,'native Heal amount vs missing-health cap are separate')
fresh({friendly_blocked=true});q.start({enabled=true,owner=1});advance(2)
check(q.snapshot().status=='completed' and not q.snapshot().native_passed
    and q.snapshot().phases[3].reason=='friendly_blocked_upstream_branch_unverified','no fake friendly branch acceptance')
fresh({missing_event=true});q.start({enabled=true});advance(2)
check(q.snapshot().status=='failed' and not q.snapshot().native_passed and q.snapshot().cleanup.inventory_restored,'no callback cannot pass, cleanup complete')
fresh({bad_heal=true});q.start({enabled=true});advance(2)
check(q.snapshot().status=='failed' and q.snapshot().phases[1].reason=='actual_heal_amount_or_hp_mismatch','route/Heal invocation is insufficient without real HP delta')
fresh({invisible=true});q.start({enabled=true});advance(2)
check(native_attacks==0 and native_spells==0 and q.snapshot().reason=='native_targets_not_visible','not visible never attacks')
fresh({delayed_precache=true});q.start({enabled=true});q.stop();precache_callback();advance(15)
check(created==0 and grants==1 and transactions==1 and q.snapshot().reason=='explicit_stop','late callback inert after stop')
fresh({delayed_precache=true});q.start({enabled=true});local callback=precache_callback;world={};callback()
check(created==0 and q.snapshot().cleanup.inventory_error=='world_or_guard_changed','cross-world no spawn or foreign inventory restore')
fresh({delayed_precache=true});q.start({enabled=true});advance(13)
check(q.snapshot().reason=='bounded_timeout' and q.snapshot().cleanup.inventory_restored and C.HandleTakeDamage==actual_handle,'bounded timeout restores own changes')
fresh({delayed_precache=true});q.start({enabled=true});counts[0].concurrent_item=2;q.stop()
check(counts[0].concurrent_item==2 and q.snapshot().cleanup.inventory_error=='concurrent_inventory_change_not_overwritten','concurrent changes never overwritten')
fresh({delayed_precache=true});q.start({enabled=true});local foreign=function() return 'foreign' end;C.HandleTakeDamage=foreign;q.stop()
check(C.HandleTakeDamage==foreign and q.snapshot().cleanup.class_wrapper_restored==false,'foreign wrapper never clobbered')
fresh();counts[0].weapon_growth_sword_max=1;local accepted=pcall(q.start,{enabled=true})
check(not accepted and grants==0 and created==0,'auto-synthesis unsafe baseline rejected before mutation')
fresh();counts[0].item_death_mask=1;mods[0].server_values.lifesteal_pct=50;accepted=pcall(q.start,{enabled=true})
check(not accepted and grants==0,'preexisting positive lifesteal rejected without inventory corruption')
fresh();mods[2].equipment_damage_registration_token={};accepted=pcall(q.start,{enabled=true})
check(not accepted and grants==0,'all four canonical tokens required')
-- Preserve arbitrary original returns, explicit nils and exact error objects on
-- an unrelated callback through the live class wrapper.
fresh({delayed_precache=true});local marker={};C.HandleTakeDamage=function() return 1,nil,3 end
q.start({enabled=true});local a,b,c=C.HandleTakeDamage({},{});check(a==1 and b==nil and c==3,'callback multiple returns/nils preserved');q.stop()
fresh({delayed_precache=true});C.HandleTakeDamage=function() error(marker,0) end
q.start({enabled=true});local ok,err=pcall(C.HandleTakeDamage,{},{});check(not ok and err==marker,'original error object preserved');q.stop()
fresh({delayed_precache=true});q.start({enabled=true});a,b,c=units[0]:Heal(1,nil)
check(a=='native_heal_return' and b==nil and c==7 and #q.snapshot().phases==0,'native Heal returns/nils preserved and unrelated heal not attributed');q.stop()
fresh({delayed_precache=true});units[0].Heal=function() error(marker,0) end;q.start({enabled=true})
ok,err=pcall(units[0].Heal,units[0],1,nil);check(not ok and err==marker,'native Heal original error object preserved');q.stop()
check(q.snapshot().native_execution_required==true and q.snapshot().network_clients_verified==false,'offline is not engine/network acceptance')
print('PASS native equipment lifesteal verifier '..checks..' checks (simulated APIs only)')
