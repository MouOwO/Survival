-- Explicit, short Tools correctness test. require() is inert. No real save/API.
-- The class route bypasses instance method lookup, so observe the exact receiver
-- with a temporary class wrapper. Never invoke damage callbacks ourselves.
local M = {}
local KEY = 'SURVIVAL_NATIVE_EQUIPMENT_LIFESTEAL_VERIFIER'
local TARGET = 'npc_dota_creep_badguys_melee'
local MASK = 'item_death_mask'
local serial = 0
local unpack = unpack
local function pack(...) return {n=select('#',...),...} end
local function copy(t) if type(t)~='table' then return t end local r={};for k,v in pairs(t) do r[k]=copy(v) end;return r end
local function valid(u) local ok,v=pcall(function() return u and not u:IsNull() end);return ok and v==true end
local function live(u) local ok,v=pcall(function() return valid(u) and u:IsAlive() end);return ok and v==true end
local function finite(n) return type(n)=='number' and n==n and math.abs(n)<math.huge end
local function now() return GameRules:GetGameTime() end
local function inventory(bus,ev,id)
    local r=bus.request(ev.CONTENT_INVENTORY_GET_REQUEST,{player_id=id})
    assert(r and r.ok==true and r.snapshot and type(r.snapshot.counts)=='table','formal_inventory_unavailable')
    return copy(r.snapshot.counts)
end
local function same_counts(a,b)
    for k,v in pairs(a) do if (tonumber(v) or 0)~=(tonumber(b[k]) or 0) then return false end end
    for k,v in pairs(b) do if (tonumber(v) or 0)~=(tonumber(a[k]) or 0) then return false end end
    return true
end
local function stats(s)
    local r=s.bus.request(s.events.EQUIPMENT_STATS_GET_REQUEST,{player_id=s.owner})
    assert(r and r.ok==true and r.snapshot and r.snapshot.values,'formal_equipment_stats_unavailable')
    return tonumber(r.snapshot.values.lifesteal_pct) or 0
end
local function canonical(bus,ev,id)
    local r=bus.request(ev.HERO_SUMMON_GET_REQUEST,{player_id=id})
    assert(r and r.ok==true and live(r.unit),'canonical_hero_unavailable_'..id)
    local u,m=r.unit,r.unit:FindModifierByName('modifier_equipment_effects')
    local context=require('systems/player_context_service')
    assert(u:IsRealHero() and not u:IsIllusion() and (not u.IsClone or not u:IsClone())
        and u.survival_player_id==id and u:GetPlayerOwnerID()==id
        and context.owner_player_id(u,true)==id and context.is_owned_by(id,u),'canonical_owner_mismatch_'..id)
    local reg=m and m.equipment_damage_registration
    assert(valid(m) and m.shared_equipment_damage_observer==true and reg and reg.unit==u and reg.modifier==m
        and m.equipment_damage_registration_token==reg.token
        and u.survival_shared_hero_equipment_damage_registration==reg,'shared_registration_unavailable_'..id)
    return u,m,reg
end
local function current(s)
    local ok,v=pcall(function()
        local setup=require('systems/match_setup_service')
        if _G[KEY]~=s or s.stopped or GameRules:GetGameModeEntity()~=s.world
            or _G.SURVIVAL_REAL_GAME_STRESS_ISOLATION~=s.guard or s.guard.mode~=s.world
            or s.bus.get_generation()~=s.generation or setup.get_session_id()~=s.session
            or setup.get_mode()~=s.match_mode then return false end
        for id=0,3 do local u,m,r=canonical(s.bus,s.events,id)
            if u~=s.heroes[id+1] or m~=s.mods[id+1] or r~=s.registrations[id+1] or r.world~=s.world then return false end
        end
        return true
    end)
    return ok and v==true
end
local function own_target(s,u)
    return valid(u) and u.survival_native_equipment_lifesteal_target_token==s.token
end
local function restore_methods(s)
    s.report.cleanup.class_wrapper_restored=s.class and s.class.HandleTakeDamage==s.handle_wrapper or false
    if s.report.cleanup.class_wrapper_restored then s.class.HandleTakeDamage=s.original_handle end
    if s.heal_installed and valid(s.hero) and s.hero.Heal==s.heal_wrapper then
        local ok=pcall(function() s.hero.Heal=s.heal_restore end)
        s.report.cleanup.heal_wrapper_restored=ok and s.hero.Heal==s.original_heal
    elseif s.heal_installed then s.report.cleanup.heal_wrapper_restored=false end
end
local function restore_inventory(s)
    if not s.mask_added then s.report.cleanup.inventory_restored=true;return end
    if GameRules:GetGameModeEntity()~=s.world or _G.SURVIVAL_REAL_GAME_STRESS_ISOLATION~=s.guard then
        s.report.cleanup.inventory_restored=false;s.report.cleanup.inventory_error='world_or_guard_changed';return
    end
    local counts=inventory(s.bus,s.events,s.owner)
    local expected=copy(s.original_inventory);expected[MASK]=(expected[MASK] or 0)+1
    if not same_counts(counts,expected) then
        s.report.cleanup.inventory_restored=false;s.report.cleanup.inventory_error='concurrent_inventory_change_not_overwritten';return
    end
    local r=s.bus.request(s.events.CONTENT_INVENTORY_TRANSACTION_REQUEST,
        {player_id=s.owner,consume={[MASK]=1},grant={},reason='tools_native_lifesteal_restore'})
    s.report.cleanup.inventory_restored=r and r.ok==true and same_counts(inventory(s.bus,s.events,s.owner),s.original_inventory) or false
    if s.report.cleanup.inventory_restored then s.mask_added=false end
end
local function finish(s,reason)
    if s.stopped then return end
    s.stopped=true;s.report.status=reason=='completed' and 'completed' or 'failed';s.report.reason=reason;s.report.finished_at=now()
    if s.task then require('core/scheduler').cancel(s.task) end
    if s.watchdog then require('core/scheduler').cancel(s.watchdog) end
    restore_methods(s)
    local ok,err=pcall(restore_inventory,s)
    if not ok then s.report.cleanup.inventory_restored=false;s.report.cleanup.inventory_error='restore_request_failed' end
    if valid(s.hero) and GameRules:GetGameModeEntity()==s.world and s.hero.survival_player_id==s.owner
        and live(s.hero) then
        local restored=pcall(function()
            require('core/hero_health_guard').allow_healing(s.hero)
            s.hero:SetHealth(math.min(s.original_health,s.hero:GetMaxHealth()))
            s.report.cleanup.health_after=s.hero:GetHealth()
            s.report.cleanup.health_restored=math.abs(s.report.cleanup.health_after-s.original_health)<=1
            local p=s.hero:GetAbsOrigin();local b=s.original_position
            s.report.cleanup.position_unchanged=math.abs(p.x-b.x)<.01 and math.abs(p.y-b.y)<.01 and math.abs(p.z-b.z)<.01
        end)
        if not restored then s.report.cleanup.health_restored=false end
    else s.report.cleanup.health_restored=false end
    s.report.cleanup.targets_removed=0
    for _,u in ipairs(s.targets or {}) do if own_target(s,u) then
        local removed=pcall(UTIL_Remove,u);if removed then s.report.cleanup.targets_removed=s.report.cleanup.targets_removed+1 end
    end end
    local all=true
    for _,p in ipairs(s.report.phases) do if p.passed~=true then all=false end end
    s.report.native_passed=reason=='completed' and #s.report.phases==4 and all
        and s.report.cleanup.inventory_restored==true and s.report.cleanup.health_restored==true
        and s.report.cleanup.position_unchanged==true and s.report.cleanup.class_wrapper_restored==true
        and s.report.cleanup.heal_wrapper_restored==true
end
local function install_observers(s)
    local u,c=s.hero,_G.modifier_equipment_effects
    assert(type(c)=='table' and type(c.HandleTakeDamage)=='function','production_handle_unavailable')
    s.class=c;s.original_handle=c.HandleTakeDamage;s.original_heal=u.Heal
    assert(type(s.original_heal)=='function','native_heal_unavailable')
    -- Restore the original own/inherited field shape. Native handles must prove
    -- that clearing a temporary field re-exposes exactly the original method.
    if type(u)=='table' then s.heal_restore=rawget(u,'Heal') else
        local ok=pcall(function() u.Heal=nil end)
        local inherited=ok and u.Heal==s.original_heal
        u.Heal=s.original_heal
        assert(inherited,'native_heal_shadow_not_restorable');s.heal_restore=nil
    end
    s.heal_wrapper=function(receiver,amount,...)
        local observe=receiver==u and s.in_handle and not s.stopped
        local read,before=pcall(function() return observe and u:GetHealth() or nil end)
        local result=pack(pcall(s.original_heal,receiver,amount,...))
        if observe then
            local p=s.in_handle
            local after_ok,after=pcall(u.GetHealth,u)
            if #p.heals<8 then p.heals[#p.heals+1]={amount=amount,health_before=read and before or nil,
                health_after=after_ok and after or nil,succeeded=result[1],native_health_read=read and after_ok} end
        end
        if not result[1] then error(result[2],0) end
        return unpack(result,2,result.n)
    end
    u.Heal=s.heal_wrapper;s.heal_installed=true;assert(u.Heal==s.heal_wrapper,'native_heal_shadow_failed')
    s.handle_wrapper=function(receiver,params,...)
        local observe=not s.stopped and receiver==s.mod and type(params)=='table' and params.attacker==u
            and s.phase and params.unit==s.phase.target and own_target(s,params.unit)
        local previous=s.in_handle;local event
        if observe and #s.phase.events<16 then
            local read_ok,read_event=pcall(function()
                local pct=tonumber(receiver.server_values and receiver.server_values.lifesteal_pct) or 0
                local eligible=params.unit:GetTeamNumber()~=u:GetTeamNumber() and tonumber(params.damage_category)==DOTA_DAMAGE_CATEGORY_ATTACK
                local amount=eligible and require('combat/lifesteal_amount').calculate(u,params.unit,params.damage,pct) or 0
                return {damage=params.damage,category=params.damage_category,lifesteal_pct=pct,expected_amount=amount,
                    health_before=u:GetHealth(),maximum=u:GetMaxHealth(),heals={},game_time=now()}
            end)
            if read_ok then event=read_event;s.phase.events[#s.phase.events+1]=event;s.in_handle=event
            else s.phase.observation_read_failed=true end
        end
        local result=pack(pcall(s.original_handle,receiver,params,...))
        if event then local read,hp=pcall(u.GetHealth,u);event.health_after=read and hp or nil;event.handler_succeeded=result[1] end
        s.in_handle=previous
        if not result[1] then error(result[2],0) end
        return unpack(result,2,result.n)
    end
    c.HandleTakeDamage=s.handle_wrapper;assert(c.HandleTakeDamage==s.handle_wrapper,'handle_wrapper_failed')
end
local function make_target(s,team,offset)
    local b=s.original_position
    local u=CreateUnitByName(TARGET,Vector(b.x+offset,b.y,b.z),true,nil,nil,team)
    assert(live(u),'own_native_target_creation_failed')
    u.survival_native_equipment_lifesteal_target_token=s.token;s.targets[#s.targets+1]=u
    u:SetIdleAcquire(false);u:SetAcquisitionRange(0);u:SetAttackCapability(DOTA_UNIT_CAP_NO_ATTACK)
    u:SetMoveCapability(DOTA_UNIT_CAP_MOVE_NONE);u:SetBaseDamageMin(0);u:SetBaseDamageMax(0)
    u:SetBaseMaxHealth(2000000000);u:SetMaxHealth(2000000000);u:SetHealth(2000000000)
    u:SetDeathXP(0);u:SetMinimumGoldBounty(0);u:SetMaximumGoldBounty(0)
    return u
end
local function check_phase(p)
    local count,heals,attacks=0,0,0
    if p.observation_read_failed then return false,'native_observation_read_failed' end
    for _,e in ipairs(p.events) do
        count=count+1;heals=heals+#e.heals
        local basic=tonumber(e.category)==DOTA_DAMAGE_CATEGORY_ATTACK and finite(e.damage) and e.damage>0
        if basic then attacks=attacks+1 end
        if not e.handler_succeeded then return false,'production_handler_error' end
        if p.kind=='positive_attack' and basic then
            if e.expected_amount<=0 or #e.heals~=1 then return false,'positive_native_attack_or_heal_missing' end
            local h=e.heals[1]
            if not h.native_health_read or not finite(h.health_before) or not finite(h.health_after) then return false,'native_health_read_failed' end
            local cap=math.min(e.expected_amount,math.max(0,e.maximum-h.health_before))
            if h.succeeded~=true or not finite(h.amount) or math.abs(h.amount-e.expected_amount)>.01
                or math.abs((h.health_after-h.health_before)-cap)>1.01 then return false,'actual_heal_amount_or_hp_mismatch' end
            if p.hero_health_after and p.hero_health_after<h.health_after-1.01 then return false,'post_heal_health_rollback_or_external_damage' end
        elseif #e.heals~=0 then return false,'unexpected_equipment_heal' end
        if p.kind=='spell_enemy' and tonumber(e.category)==DOTA_DAMAGE_CATEGORY_ATTACK then return false,'spell_reported_as_attack' end
        if p.kind=='removed_attack' and e.lifesteal_pct~=0 then return false,'removed_stats_or_basic_damage_missing' end
    end
    p.actual_handler_events=count;p.actual_equipment_heals=heals;p.actual_basic_damage_events=attacks
    if count==0 then return false,p.kind=='friendly_attack' and 'friendly_blocked_upstream_branch_unverified' or 'native_damage_callback_missing' end
    if (p.kind=='positive_attack' or p.kind=='removed_attack' or p.kind=='friendly_attack') and attacks==0 then return false,'native_basic_damage_not_observed' end
    return true
end
local function queue(s,delay,fn)
    require('core/scheduler').after(delay,function()
        if s.stopped then return end
        if not current(s) then finish(s,'current_world_guard_or_canonical_changed');return end
        if now()>s.deadline then finish(s,'bounded_timeout');return end
        local ok,err=pcall(fn);if not ok then s.report.error='test_operation_failed:'..tostring(err);finish(s,'operation_failed') end
    end,s.task)
end
local function run_phase(s,index)
    if index>4 then finish(s,'completed');return end
    local kinds={'positive_attack','spell_enemy','friendly_attack','removed_attack'}
    if index==4 then
        restore_inventory(s)
        assert(s.report.cleanup.inventory_restored==true and stats(s)==0,'formal_mask_removal_failed')
        assert((tonumber(s.mod.server_values.lifesteal_pct) or 0)==0,'native_modifier_mask_removal_refresh_missing')
    end
    local target=index==3 and s.friendly or s.enemy
    assert(live(target) and own_target(s,target),'own_target_lost')
    require('core/hero_health_guard').allow_healing(s.hero)
    s.hero:SetHealth(math.max(1,math.floor(s.hero:GetMaxHealth()*.5)))
    local p={kind=kinds[index],events={},target=target,target_health_before=target:GetHealth(),started_at=now()}
    s.phase=p;s.report.phases[#s.report.phases+1]=p
    if index==2 then
        p.submitted_kind='native_ApplyDamage_spell'
        p.applied_damage=ApplyDamage({attacker=s.hero,victim=target,damage=100,damage_type=DAMAGE_TYPE_MAGICAL})
    else
        p.submitted_kind='native_PerformAttack';p.process_procs=false;p.projectile=false;p.skip_cooldown=true
        s.hero:PerformAttack(target,false,false,true,true,false,false,true)
    end
    queue(s,.25,function()
        p.target_health_after=target:GetHealth();p.hero_health_after=s.hero:GetHealth();p.finished_at=now();p.passed,p.reason=check_phase(p)
        p.target=nil;s.phase=nil
        if not p.passed and p.reason~='friendly_blocked_upstream_branch_unverified' then finish(s,'phase_failed_'..p.kind);return end
        run_phase(s,index+1)
    end)
end
function M.start(opts)
    opts=opts or {};if opts.enabled~=true then return {default_off=true,started=false} end
    assert(IsServer() and IsInToolsMode() and GetMapName()=='template_map','Tools template_map only')
    assert(not _G[KEY] or _G[KEY].stopped,'Existing lifesteal verifier active')
    local owner=tonumber(opts.owner or 0);assert(owner and owner==math.floor(owner) and owner>=0 and owner<=3,'owner_0_to_3_required')
    local bus,ev=require('core/event_bus'),require('core/events');local world=GameRules:GetGameModeEntity()
    local guard=_G.SURVIVAL_REAL_GAME_STRESS_ISOLATION;assert(guard and guard.mode==world,'Current write isolation required')
    local setup=require('systems/match_setup_service');serial=serial+1
    local s={owner=owner,bus=bus,events=ev,world=world,guard=guard,generation=bus.get_generation(),
        session=setup.get_session_id(),match_mode=setup.get_mode(),token={},heroes={},mods={},registrations={},targets={},
        task='native_equipment_lifesteal_'..serial,deadline=now()+math.max(3,math.min(12,tonumber(opts.timeout_seconds) or 8)),
        report={schema='native_equipment_lifesteal_v1',status='preflight',owner=owner,started_at=now(),
            native_passed=false,native_execution_required=true,scope='one_of_four_canonical_engine_heroes',
            network_clients_verified=false,phases={},cleanup={},no_real_save=true,
            synthetic_missing_hp=true,process_procs=false,projectile=false,normal_attack_cadence_not_tested=true,
            attack_progression_may_advance_in_match=true,deadline_clock='game_time'}}
    for id=0,3 do local u,m,r=canonical(bus,ev,id);assert(r.world==world,'registration_world_mismatch')
        s.heroes[id+1]=u;s.mods[id+1]=m;s.registrations[id+1]=r end
    s.hero,s.mod=s.heroes[owner+1],s.mods[owner+1]
    s.original_inventory=inventory(bus,ev,owner)
    assert((tonumber(s.original_inventory[MASK]) or 0)==0 and (tonumber(s.original_inventory.weapon_growth_sword_max) or 0)==0
        and (tonumber(s.original_inventory.weapon_growth_sword_04) or 0)==0,'mask_or_near_max_growth_recipe_not_safely_restorable')
    assert(stats(s)==0 and (tonumber(s.mod.server_values.lifesteal_pct) or 0)==0,'zero_equipment_lifesteal_baseline_required')
    local u=s.hero;assert(type(u.PerformAttack)=='function' and type(u.Heal)=='function' and type(u.SetHealth)=='function','required_native_methods_missing')
    assert(not u:IsChanneling() and (not u.GetCurrentActiveAbility or u:GetCurrentActiveAbility()==nil)
        and (not u.GetAttackTarget or u:GetAttackTarget()==nil),'idle_hero_required_no_order_state_writes')
    s.original_health=u:GetHealth();local pos=u:GetAbsOrigin();s.original_position={x=pos.x,y=pos.y,z=pos.z}
    s.report.original_health=s.original_health;s.report.original_position=copy(s.original_position);s.report.original_lifesteal=0
    assert(finite(s.original_health) and s.original_health>0 and u:GetMaxHealth()>1,'finite_live_health_required')
    _G[KEY]=s
    local ok,err=pcall(function()
        install_observers(s)
        local r=bus.request(ev.CONTENT_INVENTORY_GRANT_REQUEST,{player_id=owner,content_id=MASK,count=1,reason='tools_native_lifesteal_grant'})
        local expected=copy(s.original_inventory);expected[MASK]=1
        -- Set cleanup ownership before post-request assertions: a successful
        -- synchronous grant may already have changed the match inventory.
        s.mask_added=r and r.ok==true or false
        assert(s.mask_added and same_counts(inventory(bus,ev,owner),expected),'grant_or_automatic_synthesis_changed_inventory')
        assert(stats(s)>0 and (tonumber(s.mod.server_values.lifesteal_pct) or 0)>0,'formal_positive_lifesteal_refresh_missing')
        s.report.granted_lifesteal=stats(s);s.report.status='awaiting_native_precache'
        assert(type(PrecacheUnitByNameAsync)=='function','native_precache_api_required')
        PrecacheUnitByNameAsync(TARGET,function()
            if s.stopped then return end
            if not current(s) then finish(s,'late_precache_world_or_owner_changed');return end
            local prepared,why=pcall(function()
                local team=u:GetTeamNumber();assert(team~=DOTA_TEAM_BADGUYS,'friendly_badguys_owner_unsupported')
                s.enemy=make_target(s,DOTA_TEAM_BADGUYS,140);s.friendly=make_target(s,team,200)
                assert(type(AddFOWViewer)=='function','native_visibility_api_required')
                AddFOWViewer(team,Vector(pos.x+170,pos.y,pos.z),400,12,false)
                s.report.status='running';s.visibility_deadline=now()+1
                local function visible()
                    assert(live(s.enemy) and live(s.friendly),'native_targets_lost')
                    if u:CanEntityBeSeenByMyTeam(s.enemy) and u:CanEntityBeSeenByMyTeam(s.friendly) then run_phase(s,1)
                    elseif now()<s.visibility_deadline then queue(s,.1,visible)
                    else finish(s,'native_targets_not_visible') end
                end
                queue(s,.1,visible)
            end)
            if not prepared then s.report.error='preparation_failed:'..tostring(why);finish(s,'preparation_failed') end
        end,-1)
    end)
    if not ok then s.report.error='start_failed:'..tostring(err);finish(s,'start_failed') end
    if not s.stopped then
        s.watchdog=s.task..'_watchdog'
        require('core/scheduler').after(s.deadline-now(),function() if not s.stopped then finish(s,'bounded_timeout') end end,s.watchdog)
    end
    return M.snapshot()
end
function M.snapshot()
    local s=_G[KEY];if not s then return {default_off=true,status='not_started',native_passed=false} end
    local r={};for k,v in pairs(s.report) do if k~='phases' then r[k]=copy(v) end end;r.phases={}
    -- No live handles/registration tokens, account identity or save data output.
    for _,p in ipairs(s.report.phases) do local entry={};for k,v in pairs(p) do if k~='target' then entry[k]=copy(v) end end;r.phases[#r.phases+1]=entry end
    return r
end
function M.stop()
    local s=_G[KEY];if not s or s.stopped then return M.snapshot() end
    assert(IsServer() and IsInToolsMode() and GetMapName()=='template_map','Tools template_map only')
    finish(s,'explicit_stop');if s.watchdog then require('core/scheduler').cancel(s.watchdog) end
    return M.snapshot()
end
return M
