-- require() is inert. Explicit Tools fixture, not a network-client emulator.
-- Prepare normal four-owner construction/heroes first, then prepare(), then
-- start(). prepare() rebalances only match wood/gold via RESOURCE_ADD and drains
-- current legal offers; start() never replenishes funds or writes real saves.
-- All gameplay pays through normal transactions. Native orders are submitted
-- orders, not asserted spell/damage completion. Report contains bounded trace.
local M={}
local KEY,TASK='SURVIVAL_FOUR_PLAYER_ACTIVITY','manual_four_player_activity'
local function valid(u)
    local ok,live=pcall(function() return u and not u:IsNull() and u:IsAlive() end)
    return ok and live==true
end
local function copy(v)
    if type(v)~='table' then return v end
    local t={};for k,c in pairs(v) do t[k]=copy(c) end;return t
end
local function bus() return require('core/event_bus') end
local function events() return require('core/events') end
local function req(name,data) return bus().request(events()[name] or name,data) end
local function game_now() return GameRules:GetGameTime() end
local function tools()
    assert(IsServer and IsServer() and IsInToolsMode and IsInToolsMode(),'Tools server only')
    assert(GetMapName()=='template_map','template_map only')
end
local function current()
    local s=_G[KEY];return s and s.mode==GameRules:GetGameModeEntity() and s or nil
end
local function guard_current(s)
    local setup=require('systems/match_setup_service')
    return current()==s and s.fixture==_G.SURVIVAL_FOUR_PLAYER_LIVE_PERF and s.fixture.status=='ready'
        and s.guard==_G.SURVIVAL_REAL_GAME_STRESS_ISOLATION and s.guard.mode==s.mode
        and setup.get_mode()==s.match_mode and setup.get_session_id()==s.session
end
local function clock_source()
    for _,entry in ipairs({{'GetSystemTimeMS',1000},{'RealTime',1}}) do
        local fn=_G[entry[1]]
        if type(fn)=='function' then
            local ok,value=pcall(fn)
            if ok and type(value)=='number' and value==value and math.abs(value)<math.huge then
                return function() return fn()/entry[2] end,entry[1]
            end
        end
    end
    return game_now,'GameRules_GetGameTime_fallback'
end
local function random(owner)
    owner.rng=(owner.rng*48271)%2147483647
    return owner.rng
end
local function wallet(id)
    local response=req('RESOURCE_GET_REQUEST',{player_id=id})
    local r=response or {}
    return {wood=tonumber(r.wood) or 0,gold=tonumber(r.gold) or 0,population=tonumber(r.population) or 0,
        max_population=tonumber(r.max_population) or 0,debug_mode=tonumber(r.debug_mode) or 0,
        ok=response~=nil and r.ok~=false and type(r.wood)=='number' and type(r.gold)=='number'}
end
local function buildings(id)
    local rows=(req('BUILDING_LIST_REQUEST',{player_id=id,handles_only=true}) or {}).buildings or {}
    table.sort(rows,function(a,b) return a.unit:entindex()<b.unit:entindex() end)
    return rows
end
local function counts(id)
    local result={}
    for _,r in ipairs(buildings(id)) do if valid(r.unit) then result[r.building_id]=(result[r.building_id] or 0)+1 end end
    return result
end
local function owned_unsafe(u,id,kind)
    if not valid(u) or not require('systems/player_context_service').is_owned_by(id,u) then return false end
    local native=u:GetPlayerOwnerID()
    if native~=id and native~=-1 then return false end
    if kind=='builder' then
        local r=req('BUILDER_GET_REQUEST',{player_id=id,caster=u})
        return r and r.ok and r.builder==u and tonumber(r.player_id)==id
    end
    if kind=='hero' then
        local r=req('HERO_SUMMON_GET_REQUEST',{player_id=id})
        return r and r.ok and r.unit==u and native==id
    end
    local r=req('BUILDING_QUERY_REQUEST',{entindex=u:entindex(),read_only=true})
    return r and r.unit==u and tonumber(r.player_id)==id and r.building_id==kind
end
local function owned(u,id,kind)
    local ok,matched=pcall(owned_unsafe,u,id,kind)
    return ok and matched==true
end
local profile_matches
local function current_builder(owner,entry)
    -- Builder proxies can be replaced while the match remains active. Resolve
    -- the registered current actor without passing the stale cached candidate.
    local response=req('BUILDER_GET_REQUEST',{player_id=owner.id})
    local candidate=response and response.ok==true and response.builder or nil
    owner.builder=nil
    entry.builder_source='formal_current_request'
    entry.builder_owned=candidate~=nil and tonumber(response.player_id)==owner.id and owned(candidate,owner.id,'builder') or false
    entry.profile_matches,entry.profile_guard_verified=profile_matches(current(),owner)
    if not entry.profile_matches then return nil,'builder_profile_changed' end
    if not candidate then return nil,'builder_unavailable' end
    if not entry.builder_owned then
        return nil,'builder_ownership_changed'
    end
    local ok,origin=pcall(function()
        local p=candidate:GetAbsOrigin()
        assert(p and type(p.x)=='number' and type(p.y)=='number' and type(p.z)=='number'
            and p.x==p.x and p.y==p.y and p.z==p.z
            and math.abs(p.x)<math.huge and math.abs(p.y)<math.huge and math.abs(p.z)<math.huge)
        return p
    end)
    entry.builder_native_entity_valid=ok
    if not ok then return nil,'builder_native_entity_invalid' end
    owner.builder=candidate
    entry.builder_entindex=candidate:entindex()
    return candidate,nil,origin
end
local function selected_building(owner,kind)
    local result={}
    for _,r in ipairs(buildings(owner.id)) do if r.building_id==kind and owned(r.unit,owner.id,kind) then result[#result+1]=r.unit end end
    if #result==0 then return nil end
    return result[owner.selector%#result+1]
end
local function scalar_position(p) return p and {x=p.x,y=p.y,z=p.z} or nil end
local function record(s,owner,entry)
    s.serial=s.serial+1;entry.sequence=s.serial;entry.player_id=owner.id;entry.game_time=game_now()
    entry.elapsed=s.started and s.clock()-s.started or 0
    if entry.error then entry.error=tostring(entry.error):sub(1,180) end
    if entry.step then
        -- A finite plan has a strict upper bound. Lifecycle bursts must never
        -- evict an action's acceptance, refusal or resource-before/after data.
        assert(#s.action_trace<s.action_trace_limit,'Finite action trace bound exceeded')
        entry.action_sequence=#s.action_trace+1;s.action_trace[#s.action_trace+1]=entry
    else
        s.setup_total=s.setup_total+1
        s.setup_trace[(s.setup_total-1)%s.setup_trace_limit+1]=entry
    end
    local stats=owner.stats;stats.total=stats.total+1
    if entry.accepted then stats.accepted=stats.accepted+1 else stats.rejected=stats.rejected+1 end
    stats.by_kind[entry.kind]=(stats.by_kind[entry.kind] or 0)+1
    if entry.step then
        stats.actions=stats.actions+1
        if entry.accepted then stats.actions_accepted=stats.actions_accepted+1 else stats.actions_rejected=stats.actions_rejected+1 end
        local detail=stats.action_by_kind[entry.kind] or {accepted=0,rejected=0,net_wood_debit=0,net_gold_debit=0}
        stats.action_by_kind[entry.kind]=detail
        detail[entry.accepted and 'accepted' or 'rejected']=detail[entry.accepted and 'accepted' or 'rejected']+1
        detail.net_wood_debit=detail.net_wood_debit+(entry.net_wood_debit or 0)
        detail.net_gold_debit=detail.net_gold_debit+(entry.net_gold_debit or 0)
    end
    owner.last_wallet=copy(entry.resource_after or entry.resource_before)
end
local function lifecycle(s,owner,label,payload)
    s.serial=s.serial+1;s.lifecycle_total=s.lifecycle_total+1
    owner.stats.completed_events=owner.stats.completed_events+1
    owner.stats.lifecycle_events[label]=(owner.stats.lifecycle_events[label] or 0)+1
    -- Counter updates use the supplied formal payload only: no wallet query,
    -- full building-list scan or copying of every BUILDING_CHANGED payload.
    if s.lifecycle_trace_limit>0 then
        s.lifecycle_trace[(s.lifecycle_total-1)%s.lifecycle_trace_limit+1]={
            sequence=s.serial,player_id=owner.id,kind='event:'..label,game_time=game_now(),
            entity=payload.entindex,level=payload.level,count_delta=payload.count_delta,
            training_queue_changed=payload.training_queue_changed}
    end
end
local function funds(owner,cost)
    local r=req('RESOURCE_CAN_SPEND_REQUEST',{player_id=owner.id,wood=cost.wood or 0,gold=cost.gold or 0,population=cost.population or 0})
    return r and r.ok==true,r and r.error or 'resource_precheck_missing'
end
local function finish(entry,result)
    entry.accepted=result and result.ok==true or false
    entry.error=result and result.error or (not result and 'formal_response_missing' or nil)
    entry.pending=result and (result.pending==true or result.queued==true) or false
    if result then
        entry.target_level=result.target_level;entry.job_id=result.job_id
        entry.research_started=result.research_started;entry.error_code=result.error_code
    end
    entry.outcome=entry.accepted and 'formal_request_accepted' or 'formal_request_rejected'
    return entry
end
local function upgrade(owner,entry)
    local unit=selected_building(owner,owner.wall_only and 'wall' or (owner.selector%3==0 and 'wall' or 'arrow_tower'))
    if not unit then return finish(entry,{ok=false,error='upgrade_asset_unavailable'}) end
    entry.entity=unit:entindex();entry.before_level=unit.survival_level
    local quote=req('BUILDING_UPGRADE_QUOTE_REQUEST',{player_id=owner.id,building=unit,upgrade_mode='one'})
    if not quote or not quote.ok then return finish(entry,quote) end
    entry.quote={wood=quote.wood or 0,gold=quote.gold or 0,population=quote.population or 0}
    local affordable,why=funds(owner,entry.quote)
    if not affordable then return finish(entry,{ok=false,error=why}) end
    return finish(entry,req('BUILDING_UPGRADE_REQUEST',{player_id=owner.id,building=unit,upgrade_mode='one',silent_notification=true}))
end
local function research(owner,entry)
    local config=require('config/research_technology_config')
    local state=req('RESEARCH_STATE_GET_REQUEST',{player_id=owner.id}) or {}
    local defs=config.technologies or {};if #defs==0 then return finish(entry,{ok=false,error='research_config_empty'}) end
    local def=defs[owner.selector%#defs+1];local level=tonumber((state.levels or {})[def.tech_id]) or 0
    entry.tech_id=def.tech_id;entry.before_level=level
    local prerequisite=def.prerequisite or {}
    if prerequisite.tech_id and (tonumber((state.levels or {})[prerequisite.tech_id]) or 0)<(prerequisite.required_level or 0) then
        return finish(entry,{ok=false,error='research_prerequisite_unmet'})
    end
    local progression=req('HERO_PROGRESSION_GET_REQUEST',{player_id=owner.id}) or {}
    if (tonumber(progression.snapshot and progression.snapshot.rebirth_level) or 0)<(prerequisite.reincarnation_level or 0) then
        return finish(entry,{ok=false,error='research_rank_unmet'})
    end
    local lab=selected_building(owner,def.building_id=='advanced_research_lab' and 'building_advanced_research_lab' or 'building_research_lab')
    if not lab then return finish(entry,{ok=false,error='research_lab_unavailable'}) end
    local lane=req('TECHNOLOGY_STATE_GET_REQUEST',{player_id=owner.id,source_entindex=lab:entindex()}) or {}
    local target=math.max(level,tonumber(lane.levels and lane.levels[def.legacy_group]) or 0,
        tonumber(lane.research and lane.research.reserved_levels and lane.research.reserved_levels[def.legacy_group]) or 0)+1
    local base_cost=config.cost_for_level(def,target)
    if not base_cost then return finish(entry,{ok=false,error='research_max_level'}) end
    local cost=require('research/research_cost_service').for_player(base_cost,bus(),events(),owner.id)
    entry.entity=lab:entindex();entry.quote=copy(cost)
    entry.quoted_target_level=target
    local affordable,why=funds(owner,cost);if not affordable then return finish(entry,{ok=false,error=why}) end
    return finish(entry,req('TECHNOLOGY_PURCHASE_NEXT_REQUEST',{player_id=owner.id,technology_group=def.legacy_group,
        source_entindex=lab:entindex(),source='research_lab_ability',silent_notification=true,
        request_id='tools_activity:'..owner.run_id..':'..owner.id..':'..owner.step}))
end
local function train(owner,entry)
    local city=selected_building(owner,'main_city');if not city then return finish(entry,{ok=false,error='training_city_unavailable'}) end
    local state=req('WORKER_TRAINING_GET_REQUEST',{player_id=owner.id,source_entindex=city:entindex()}) or {}
    local options={};for _,r in ipairs(state.options or {}) do if r.available==1 or r.available==true then options[#options+1]=r end end
    if #options==0 then return finish(entry,{ok=false,error='no_trainable_option'}) end
    local option=options[owner.selector%#options+1]
    entry.training_id=option.training_id;entry.entity=city:entindex()
    entry.quote={wood=option.wood_cost or option.cost_wood or 0,gold=option.gold_cost or option.cost_gold or 0,population=option.population_cost or option.population or 0}
    local affordable,why=funds(owner,entry.quote);if not affordable then return finish(entry,{ok=false,error=why}) end
    entry.payment_note='Normal queue reserves/pays at actual job start; an accepted waiting job may pay later.'
    return finish(entry,req('WORKER_TRAIN_REQUEST',{player_id=owner.id,city=city,training_id=option.training_id}))
end
local function safe_point(owner,offset)
    local wall=selected_building(owner,'wall');if not wall then return nil,'wall_unavailable' end
    local scene=owner.scene
    local inward=owner.inward
    local across=Vector(-inward.y,inward.x,0)
    local p=wall:GetAbsOrigin()+inward*(640+(offset%3)*64)+across*((math.floor(offset/3)%7-3)*64)
    if GetGroundPosition then p=GetGroundPosition(p,owner.builder) end
    local ok,why=require('systems/destination_validation_service').validate_hero_position(p)
    return ok and p or nil,why
end
local function build(owner,entry)
    local builder,why=current_builder(owner,entry)
    if not builder then return finish(entry,{ok=false,error=why}) end
    if builder.survival_build_task then return finish(entry,{ok=false,error='builder_already_constructing'}) end
    local kinds={'gold_mine','building_challenge'};local kind=kinds[owner.selector%#kinds+1]
    local definition=require('config/buildings_config')[kind]
    if not definition then return finish(entry,{ok=false,error='building_config_missing'}) end
    local cost=require('systems/building_cost_quote').for_player(definition,owner.id)
    entry.building_id=kind;entry.quote=copy(cost)
    local affordable,why=funds(owner,cost);if not affordable then return finish(entry,{ok=false,error=why}) end
    local center,reason=safe_point(owner,owner.selector)
    if not center then return finish(entry,{ok=false,error=reason}) end
    local across=Vector(-owner.inward.y,owner.inward.x,0)
    for attempt=1,4 do
        local p=center+across*((owner.selector%2==0 and 1 or -1)*(256+attempt*64))
        local check=req('BUILD_CAN_PLACE_REQUEST',{player_id=owner.id,caster=builder,building_id=kind,position=p})
        if check and check.ok then
            entry.position=scalar_position(check.grid.world_position)
            return finish(entry,req('BUILD_REQUEST',{player_id=owner.id,caster=builder,building_id=kind,position=check.grid.world_position}))
        end
        entry.error=check and check.error or 'formal_grid_check_missing'
    end
    return finish(entry,{ok=false,error=entry.error or 'no_legal_construction_cell'})
end
local function actor_enabled(actor,casting)
    if not valid(actor) then return false end
    for _,method in ipairs({'IsStunned','IsHexed','IsOutOfGame','IsChanneling'}) do if actor[method] and actor[method](actor) then return false end end
    if casting and actor.IsSilenced and actor:IsSilenced() then return false end
    return true
end
local function native_order(owner,entry,actor,order)
    if not actor_enabled(actor,entry.kind=='hero_cast') then return finish(entry,{ok=false,error='actor_disabled_or_unavailable'}) end
    local kind=entry.kind=='builder_move' and 'builder' or 'hero'
    if not owned(actor,owner.id,kind) then return finish(entry,{ok=false,error='native_actor_ownership_changed'}) end
    order.UnitIndex=actor:entindex();order.PlayerID=owner.id;order.Queue=false
    local ok,value=pcall(ExecuteOrderFromTable,order)
    entry.entity=actor:entindex();entry.accepted=ok and value~=false
    entry.outcome=entry.accepted and 'native_order_submitted_not_completion_verified' or 'native_order_rejected'
    entry.error=not ok and tostring(value) or value==false and 'engine_rejected_order' or nil
    return entry
end
local function prepare_cast_observation(owner,entry,actor,ability,position)
    local s=current();if not s or s.options.observe_hero_completion~=true then return end
    local probe={owner=owner,actor=actor,ability=ability,name=ability:GetAbilityName(),
        issued=s.clock(),expires=s.clock()+2,origin=actor:GetAbsOrigin(),step=entry.step}
    -- This is the one known normal active ability used by the four passives-
    -- based heroes. Its OnSpellStart moves atomically and starts a cooldown.
    -- Unknown abilities remain native-used observations, never fake completion.
    if probe.name=='ability_survival_hero_ball_lightning' and position then
        probe.expected=require('systems/blink_destination').clamp(probe.origin,position,800)
        probe.cooldown_before=ability.GetCooldownTimeRemaining and ability:GetCooldownTimeRemaining() or 0
        probe.effect='ball_lightning_destination_and_cooldown'
    end
    return probe
end
local function hero(owner)
    if owner.wall_only then return nil end
    local r=req('HERO_SUMMON_GET_REQUEST',{player_id=owner.id})
    return r and r.ok and owned(r.unit,owner.id,'hero') and r.unit or nil
end
local function move(owner,entry,use_hero)
    local actor,why,origin
    if use_hero then actor=hero(owner) else actor,why,origin=current_builder(owner,entry) end
    if not actor then return finish(entry,{ok=false,error=why or 'hero_unavailable'}) end
    if not use_hero and actor.survival_build_task then return finish(entry,{ok=false,error='builder_already_constructing'}) end
    local p,why=safe_point(owner,owner.selector)
    if not p then return finish(entry,{ok=false,error=why}) end
    if GridNav and GridNav.CanFindPath and not GridNav:CanFindPath(origin or actor:GetAbsOrigin(),p) then return finish(entry,{ok=false,error='native_route_unreachable'}) end
    entry.position=scalar_position(p)
    return native_order(owner,entry,actor,{OrderType=DOTA_UNIT_ORDER_MOVE_TO_POSITION,Position=p})
end
local function enemy(owner,actor)
    if not actor or not FindUnitsInRadius then return nil end
    local range=actor.GetAttackRange and actor:GetAttackRange() or 800
    local list=FindUnitsInRadius(actor:GetTeamNumber(),actor:GetAbsOrigin(),nil,range+64,
        DOTA_UNIT_TARGET_TEAM_ENEMY,DOTA_UNIT_TARGET_HERO+DOTA_UNIT_TARGET_BASIC,DOTA_UNIT_TARGET_FLAG_NONE,FIND_CLOSEST,false)
    for _,unit in ipairs(list or {}) do if valid(unit) and not (unit.IsInvulnerable and unit:IsInvulnerable()) then return unit end end
    return nil
end
local function attack(owner,entry)
    local actor=hero(owner);local target=enemy(owner,actor)
    if not target then return finish(entry,{ok=false,error='no_enemy_in_attack_range'}) end
    entry.target=target:entindex()
    if actor.GetAttackTarget and actor:GetAttackTarget()==target then
        entry.accepted=true;entry.outcome='existing_attack_target_retained_no_order';return entry
    end
    return native_order(owner,entry,actor,{OrderType=DOTA_UNIT_ORDER_ATTACK_TARGET,TargetIndex=target:entindex()})
end
local function flag(behavior,value) return value and value>0 and behavior%(value*2)>=value end
local function cast(owner,entry)
    local actor=hero(owner);if not actor_enabled(actor,true) then return finish(entry,{ok=false,error='hero_disabled_or_unavailable'}) end
    local abilities={}
    for index=0,(actor:GetAbilityCount() or 0)-1 do
        local ability=actor:GetAbilityByIndex(index)
        if ability and not ability:IsNull() and not ability:IsHidden() and ability:IsActivated() and ability:GetLevel()>0
            and ability:IsFullyCastable() and not ability:GetAbilityName():match('reward')
            and not ability:GetAbilityName():match('return') and not ability:GetAbilityName():match('pickup') then
            local behavior=ability.GetBehaviorInt and ability:GetBehaviorInt() or ability:GetBehavior()
            if type(behavior)=='number' and not flag(behavior,DOTA_ABILITY_BEHAVIOR_PASSIVE) and not flag(behavior,DOTA_ABILITY_BEHAVIOR_TOGGLE)
                and (flag(behavior,DOTA_ABILITY_BEHAVIOR_POINT) or flag(behavior,DOTA_ABILITY_BEHAVIOR_UNIT_TARGET) or flag(behavior,DOTA_ABILITY_BEHAVIOR_NO_TARGET)) then
                abilities[#abilities+1]={ability=ability,behavior=behavior}
            end
        end
    end
    if #abilities==0 then return finish(entry,{ok=false,error='no_legal_active_ability'}) end
    local chosen=abilities[owner.selector%#abilities+1];local ability=chosen.ability
    entry.ability=ability:GetAbilityName();local order={AbilityIndex=ability:entindex()}
    if flag(chosen.behavior,DOTA_ABILITY_BEHAVIOR_POINT) then
        local p,why=safe_point(owner,owner.selector);if not p then return finish(entry,{ok=false,error=why}) end
        local range=ability.GetCastRange and ability:GetCastRange(actor:GetAbsOrigin(),nil) or 800
        if range>0 and (p-actor:GetAbsOrigin()):Length2D()>range then return finish(entry,{ok=false,error='spell_destination_out_of_range'}) end
        if ability.CastFilterResultLocation and ability:CastFilterResultLocation(p)~=(UF_SUCCESS or 0) then return finish(entry,{ok=false,error='spell_location_filter_rejected'}) end
        order.OrderType=DOTA_UNIT_ORDER_CAST_POSITION;order.Position=p;entry.position=scalar_position(p)
    elseif flag(chosen.behavior,DOTA_ABILITY_BEHAVIOR_UNIT_TARGET) then
        local target=enemy(owner,actor);if not target then return finish(entry,{ok=false,error='spell_enemy_unavailable'}) end
        local range=ability.GetCastRange and ability:GetCastRange(actor:GetAbsOrigin(),target) or 0
        if range>0 and (target:GetAbsOrigin()-actor:GetAbsOrigin()):Length2D()>range then return finish(entry,{ok=false,error='spell_target_out_of_range'}) end
        if ability.CastFilterResultTarget and ability:CastFilterResultTarget(target)~=(UF_SUCCESS or 0) then return finish(entry,{ok=false,error='spell_target_filter_rejected'}) end
        order.OrderType=DOTA_UNIT_ORDER_CAST_TARGET;order.TargetIndex=target:entindex();entry.target=target:entindex()
    else order.OrderType=DOTA_UNIT_ORDER_CAST_NO_TARGET end
    local probe=prepare_cast_observation(owner,entry,actor,ability,order.Position)
    local result=native_order(owner,entry,actor,order)
    if probe and result.accepted then
        owner.hero_observations.cast_orders=owner.hero_observations.cast_orders+1
        local s=current()
        if #s.cast_probes>=16 then owner.hero_observations.cast_probe_overflow=owner.hero_observations.cast_probe_overflow+1
        else s.cast_probes[#s.cast_probes+1]=probe end
    end
    return result
end
local handlers={upgrade=upgrade,research=research,train=train,build=build,hero_move=function(o,e) return move(o,e,true) end,
    builder_move=function(o,e) return move(o,e,false) end,hero_attack=attack,hero_cast=cast}
local function execute(s,owner,planned)
    local kind=planned.kind
    local entry={kind=kind,step=owner.step,selector=owner.selector,planned_elapsed=planned.at,
        dispatch_delay_seconds=math.max(0,s.clock()-s.started-planned.at),
        resource_before=wallet(owner.id),owner_counts_before=counts(owner.id)}
    if not entry.resource_before.ok or entry.resource_before.debug_mode~=0 then
        finish(entry,{ok=false,error='normal_resource_account_lost'});entry.resource_after=copy(entry.resource_before)
        record(s,owner,entry);M.stop('normal_resource_account_lost');return
    end
    local ok,result=pcall(handlers[kind],owner,entry)
    if not ok then finish(entry,{ok=false,error='action_error:'..tostring(result)}) end
    entry.resource_after=wallet(owner.id);entry.owner_counts_after=counts(owner.id)
    entry.net_wood_debit=entry.resource_before.wood-entry.resource_after.wood
    entry.net_gold_debit=entry.resource_before.gold-entry.resource_after.gold
    record(s,owner,entry)
end
local function make_plan(owner,duration)
    local at=owner.id*0.1
    local kinds=owner.wall_only and {'upgrade','builder_move'} or {'upgrade','research','build','train','hero_attack','hero_move','hero_cast','builder_move'}
    owner.plan={};owner.plan_digest=0
    while at<duration do
        local draw=random(owner);local selector=random(owner);local delay_draw=random(owner)
        local phase=at%45;local burst=phase>=30 and phase<32
        local interval=burst and 0.25 or (1+(delay_draw%1001)/1000)
        local index=draw%#kinds+1
        owner.plan[#owner.plan+1]={at=at,kind=kinds[index],selector=selector,interval=interval,burst=burst}
        owner.plan_digest=(owner.plan_digest*131+index+selector%10007)%2147483647
        at=at+interval
    end
end
local function active_offer(id)
    return CustomNetTables and CustomNetTables:GetTableValue('survival_rogue_reward',tostring(id)) or {}
end
local function legal_offer_cards(owner,offer)
    local cards={}
    for _,card in pairs(type(offer.cards)=='table' and offer.cards or {}) do
        local allowed=type(card)=='table' and type(card.card_id)=='string' and card.card_id~=''
        if allowed and owner.wall_only then
            for _,effect in ipairs(require('config/generated/rogue_reward_effects').rows or {}) do
                if effect.enabled~=false and effect.card_id==card.card_id then
                    local kind=tostring(effect.effect_type or '')
                    if kind=='grant_random_cards' or kind=='training_dummy_attack_gain' or kind:match('spawn') or kind:match('summon') then allowed=false end
                end
            end
        end
        if allowed then cards[#cards+1]={card_id=card.card_id} end
    end
    table.sort(cards,function(a,b) return a.card_id<b.card_id end)
    return cards
end
local function drain(s,limit)
    local remaining=0
    for _,owner in ipairs(s.owners) do
        for _=1,limit do
            local offer=active_offer(owner.id);if offer.active~=1 then break end
            local cards=legal_offer_cards(owner,offer)
            if #cards==0 then break end
            local chosen=cards[(s.options.seed+owner.id+owner.offer_count)%#cards+1]
            owner.offer_count=owner.offer_count+1
            local entry={kind='select_offer',card_id=chosen.card_id,reward_type=offer.reward_type,resource_before=wallet(owner.id)}
            local result=req('ROGUE_REWARD_SELECT_REQUEST',{player_id=owner.id,token=offer.token,card_id=chosen.card_id,reward_type=offer.reward_type})
            finish(entry,result);entry.resource_after=wallet(owner.id);entry.owner_counts_after=counts(owner.id);record(s,owner,entry)
            if not entry.accepted then break end
        end
        if active_offer(owner.id).active==1 then remaining=remaining+1 end
    end
    return remaining
end
local function offer_record(s,owner,entry)
    s.offer_trace_total=s.offer_trace_total+1
    entry.sequence=s.offer_trace_total;entry.player_id=owner.id;entry.game_time=game_now()
    entry.elapsed=s.started and s.clock()-s.started or 0
    s.offer_trace[(s.offer_trace_total-1)%s.options.offer_trace_limit+1]=entry
end
local function offer_random(owner)
    owner.offer_rng=(owner.offer_rng*48271)%2147483647
    return owner.offer_rng
end
local function observe_offer(s,owner,snapshot)
    local active=snapshot.active==1 or snapshot.active==true
    if active~=owner.modal_active then s.offers_remaining=math.max(0,(s.offers_remaining or 0)+(active and 1 or -1)) end
    owner.modal_active=active
    owner.offer_snapshot={active=active and 1 or 0,token=snapshot.token,reward_type=snapshot.reward_type}
    if not active then
        if owner.pending_offer or owner.blocked_offer_token then
            offer_record(s,owner,{kind='offer_closed',token=owner.pending_offer and owner.pending_offer.token or owner.blocked_offer_token})
        end
        owner.pending_offer=nil;owner.blocked_offer_token=nil;owner.offer_block_reason=nil
        return
    end
    local token=snapshot.token
    if type(token)~='string' or token=='' or #token>256 then
        if owner.offer_block_reason~='invalid_offer_token' then offer_record(s,owner,{kind='offer_blocked',error='invalid_offer_token'}) end
        owner.pending_offer=nil;owner.offer_block_reason='invalid_offer_token';return
    end
    if owner.pending_offer and owner.pending_offer.token==token then return end
    if owner.blocked_offer_token==token then return end
    local cards=legal_offer_cards(owner,snapshot)
    local candidates={};for _,card in ipairs(cards) do candidates[#candidates+1]=card.card_id end
    local at=s.clock()
    local delay=s.options.offer_choice_min_seconds+(offer_random(owner)/2147483647)
        *(s.options.offer_choice_max_seconds-s.options.offer_choice_min_seconds)
    local choice=#cards>0 and cards[offer_random(owner)%#cards+1].card_id or nil
    if snapshot.pending_card_id then
        choice=nil;for _,card in ipairs(cards) do if card.card_id==snapshot.pending_card_id then choice=card.card_id end end
    end
    owner.pending_offer={token=token,reward_type=snapshot.reward_type,card_id=choice,
        opened_at=at,due_at=at+delay,delay=delay,attempts=0,candidates=candidates}
    if choice then owner.offer_block_reason=nil else owner.offer_block_reason='no_legal_offer_card' end
    if not choice then owner.blocked_offer_token=token;owner.pending_offer=nil end
    offer_record(s,owner,{kind='offer_opened',token=token,reward_type=snapshot.reward_type,card_id=choice,
        candidate_ids=candidates,opened_at=at,due_at=at+delay,planned_reaction_seconds=delay,error=owner.offer_block_reason})
end
local function subscribe_offers(s)
    if s.options.auto_select_offers~=true and s.options.respect_reward_modal~=true then return end
    s.subscriptions[#s.subscriptions+1]=bus().subscribe(events().ROGUE_REWARD_CHANGED,function(payload)
        if s.status~='running' or not guard_current(s) then return end
        local id=tonumber(payload and payload.player_id);local owner=id and s.owners[id+1]
        if not owner or owner.id~=id then return end
        observe_offer(s,owner,type(payload.snapshot)=='table' and payload.snapshot or active_offer(id))
    end)
end
profile_matches=function(s,owner)
    if not s or not owner then return false,false end
    local expected=s.fixture.memory_profiles and s.fixture.memory_profiles[owner.id]
    if not expected then return true,false end -- Small isolated adapter tests have no whole-profile fixture.
    local ok,profile=pcall(function() return require('systems/player_profile_service').get_profile(owner.id) end)
    if not ok then return false,true end
    if not profile or profile.account_id~=expected.account_id or profile.revision~=expected.revision
        or not profile.save or not profile.save.gameplay_stats then return false,true end
    for field,value in pairs(expected.save.gameplay_stats) do if profile.save.gameplay_stats[field]~=value then return false,true end end
    return true,true
end
local function offer_owner_eligible(s,owner)
    if type(owner.id)~='number' or owner.id<0 or owner.id>3 or owner.id~=math.floor(owner.id)
        or s.owners[owner.id+1]~=owner then return false end
    local context=require('systems/player_context_service')
    if type(context.is_defeated)~='function' then return false end
    local ok,defeated=pcall(context.is_defeated,owner.id)
    return ok and defeated==false
end
local function choose_due_offer(s,owner,at)
    local pending=owner.pending_offer
    if s.options.auto_select_offers~=true or not pending or at<pending.due_at then return end
    if not guard_current(s) then return end
    local matches,verified=profile_matches(s,owner)
    local eligible=offer_owner_eligible(s,owner)
    if not matches or not eligible then
        owner.offer_block_reason=not matches and 'offer_profile_changed' or 'offer_player_ineligible'
        owner.blocked_offer_token=pending.token;owner.pending_offer=nil
        offer_record(s,owner,{kind='offer_blocked',token=pending.token,error=owner.offer_block_reason,
            profile_matches=matches,profile_guard_verified=verified,owner_eligible=eligible,builder_guard_required=false});return
    end
    local actual=active_offer(owner.id)
    if actual.active~=1 or actual.token~=pending.token then observe_offer(s,owner,actual);return end
    local legal=false
    for _,card in ipairs(legal_offer_cards(owner,actual)) do if card.card_id==pending.card_id then legal=true end end
    if not legal then
        owner.offer_block_reason='selected_offer_card_changed';owner.blocked_offer_token=pending.token;owner.pending_offer=nil
        offer_record(s,owner,{kind='offer_blocked',token=pending.token,error=owner.offer_block_reason});return
    end
    pending.attempts=pending.attempts+1
    local result=req('ROGUE_REWARD_SELECT_REQUEST',{player_id=owner.id,token=pending.token,
        card_id=pending.card_id,reward_type=pending.reward_type}) or {}
    local after=active_offer(owner.id)
    -- Formal publish callbacks may synchronously close/promote another offer.
    -- Read this one owner's current visible row after the transaction only.
    observe_offer(s,owner,after)
    offer_record(s,owner,{kind='offer_selection',token=pending.token,reward_type=pending.reward_type,card_id=pending.card_id,
        opened_at=pending.opened_at,due_at=pending.due_at,selected_at=at,actual_reaction_seconds=at-pending.opened_at,
        lateness_seconds=math.max(0,at-pending.due_at),attempt=pending.attempts,accepted=result.ok==true,
        error=result.error and tostring(result.error):sub(1,180),visible_offer_active_after=owner.modal_active,
        visible_token_after=after.token,profile_matches=matches,profile_guard_verified=verified,
        owner_eligible=eligible,builder_guard_required=false})
    owner.next_at=math.max(owner.next_at or at,at+0.1)
    if owner.pending_offer==pending then
        if pending.attempts>=s.options.offer_max_attempts then
            owner.offer_block_reason='offer_selection_attempt_limit';owner.blocked_offer_token=pending.token;owner.pending_offer=nil
        else pending.due_at=at+1 end
    end
end
local function subscribe_lifecycle(s)
    s.subscriptions={}
    for _,name in ipairs({'BUILDING_CREATED','BUILDING_CHANGED','WORKER_CHANGED','RESEARCH_LEVEL_CHANGED','TECHNOLOGY_RESEARCH_STATE_CHANGED','HERO_SUMMONED'}) do
        local event_name=events()[name]
        if event_name then
            local label=name
            s.subscriptions[#s.subscriptions+1]=bus().subscribe(event_name,function(payload)
                if current()~=s or s.status~='running' then return end
                local id=tonumber(payload and payload.player_id);local owner=id and s.owners[id+1]
                if not owner then return end
                lifecycle(s,owner,label,payload)
                if label=='HERO_SUMMONED' and s.options.observe_hero_completion==true then owner.observed_hero=hero(owner) end
            end)
        end
    end
end
local function subscribe_hero_observations(s)
    if s.options.observe_hero_completion~=true then return end
    for _,owner in ipairs(s.owners) do owner.observed_hero=hero(owner) end
    for _,name in ipairs({'HERO_MAIN_ATTACK_FIRED','HERO_MAIN_ATTACK_LANDED'}) do
        local event_name=events()[name];local key=name=='HERO_MAIN_ATTACK_FIRED' and 'main_attack_fired' or 'main_attack_landed'
        s.subscriptions[#s.subscriptions+1]=bus().subscribe(event_name,function(payload)
            if current()~=s or s.status~='running' then return end
            local id=tonumber(payload and payload.player_id);local owner=id and s.owners[id+1]
            if not owner or not payload.attacker or payload.attacker~=owner.observed_hero
                or payload.attacker:GetPlayerOwnerID()~=id then return end
            owner.hero_observations[key]=owner.hero_observations[key]+1
        end)
    end
    s.native_listeners={};s.native_listener_errors={};s.native_event_examples={}
    if type(ListenToGameEvent)~='function' or type(StopListeningToGameEvent)~='function' then
        s.native_listener_errors[1]='Native event listener API unavailable';return
    end
    for _,name in ipairs({'dota_player_used_ability','dota_non_player_used_ability'}) do
        local label=name
        local ok,handle=pcall(ListenToGameEvent,label,function(payload)
            if current()~=s or s.status~='running' then return end
            payload=payload or {}
            if #s.native_event_examples<8 then
                local sample={event=label};local count=0
                for key,value in pairs(payload) do
                    if (type(value)=='string' or type(value)=='number' or type(value)=='boolean') and count<12 then
                        sample[tostring(key):sub(1,64)]=type(value)=='string' and value:sub(1,120) or value;count=count+1
                    end
                end
                s.native_event_examples[#s.native_event_examples+1]=sample
            end
            local id=tonumber(payload.PlayerID or payload.playerid or payload.player_id)
            local caster=tonumber(payload.caster_entindex or payload.entindex_caster or payload.caster)
            local ability=tostring(payload.abilityname or payload.ability_name or payload.ability or ''):sub(1,120)
            for _,owner in ipairs(s.owners) do
                local actor=owner.observed_hero
                if actor and not actor:IsNull() and actor:GetPlayerOwnerID()==owner.id then
                    local exact=caster and caster==actor:entindex()
                    local player_only=not caster and id==owner.id
                    if exact or player_only then
                        local obs=owner.hero_observations
                        obs.native_used_ability=obs.native_used_ability+1
                        local counter=exact and 'native_used_exact_caster' or 'native_used_player_identity_only'
                        obs[counter]=obs[counter]+1
                        if not obs.used_by_ability[ability] and obs.used_ability_name_count>=64 then ability='__other_names_over_cap' end
                        if not obs.used_by_ability[ability] then obs.used_ability_name_count=obs.used_ability_name_count+1 end
                        obs.used_by_ability[ability]=(obs.used_by_ability[ability] or 0)+1
                    end
                end
            end
        end,nil)
        if ok and handle then s.native_listeners[#s.native_listeners+1]=handle
        else s.native_listener_errors[#s.native_listener_errors+1]=label..':'..tostring(handle):sub(1,120) end
    end
end
local function check_cast_probes(s)
    for index=#s.cast_probes,1,-1 do
        local probe=s.cast_probes[index];local observed=false
        if probe.effect and valid(probe.actor) and probe.ability and not probe.ability:IsNull() then
            local cooldown=probe.ability.GetCooldownTimeRemaining and probe.ability:GetCooldownTimeRemaining() or 0
            observed=(probe.actor:GetAbsOrigin()-probe.expected):Length2D()<=64
                and (probe.actor:GetAbsOrigin()-probe.origin):Length2D()>=1
                and cooldown>math.max(0,probe.cooldown_before)
        end
        if observed or s.clock()>=probe.expires then
            local obs=probe.owner.hero_observations
            local key=observed and 'cast_effect_verified' or probe.effect and 'cast_effect_not_observed' or 'cast_effect_unknown'
            obs[key]=obs[key]+1
            table.remove(s.cast_probes,index)
        end
    end
end
function M.prepare(options)
    tools();options=copy(options or {})
    local fixture=assert(_G.SURVIVAL_FOUR_PLAYER_LIVE_PERF,'Prepare the normal four-owner fixture first')
    assert(fixture.mode==GameRules:GetGameModeEntity() and fixture.status=='ready','Four-owner fixture must be current and ready')
    assert(not current() or current().status~='running','Activity already running')
    options.seed=options.seed or 12037;options.duration_seconds=options.duration_seconds or 150
    assert(type(options.seed)=='number' and options.seed==math.floor(options.seed) and options.seed>=1 and options.seed<2147483647,'Bounded integer seed required')
    assert(type(options.duration_seconds)=='number' and options.duration_seconds>=120 and options.duration_seconds<=180,'Duration must be 120..180 seconds')
    options.trace_limit=options.trace_limit or 512;assert(options.trace_limit>=128 and options.trace_limit<=1024 and options.trace_limit==math.floor(options.trace_limit),'Trace limit must be 128..1024')
    assert(options.require_heroes==nil or type(options.require_heroes)=='boolean','require_heroes must be boolean')
    assert(options.observe_hero_completion==nil or type(options.observe_hero_completion)=='boolean','observe_hero_completion must be boolean')
    options.lifecycle_trace_limit=options.lifecycle_trace_limit or 64
    assert(type(options.lifecycle_trace_limit)=='number' and options.lifecycle_trace_limit>=0 and options.lifecycle_trace_limit<=128
        and options.lifecycle_trace_limit==math.floor(options.lifecycle_trace_limit),'Lifecycle trace limit must be 0..128')
    if options.auto_select_offers==nil then options.auto_select_offers=true end
    if options.respect_reward_modal==nil then options.respect_reward_modal=true end
    assert(type(options.auto_select_offers)=='boolean' and type(options.respect_reward_modal)=='boolean','Offer controls must be boolean')
    options.offer_choice_min_seconds=options.offer_choice_min_seconds or 0.75
    options.offer_choice_max_seconds=options.offer_choice_max_seconds or 1.25
    assert(type(options.offer_choice_min_seconds)=='number' and type(options.offer_choice_max_seconds)=='number'
        and options.offer_choice_min_seconds>=0.25 and options.offer_choice_max_seconds<=5
        and options.offer_choice_min_seconds<=options.offer_choice_max_seconds,'Bounded ordered offer reaction interval required')
    options.offer_trace_limit=options.offer_trace_limit or 256
    assert(type(options.offer_trace_limit)=='number' and options.offer_trace_limit>=16 and options.offer_trace_limit<=1024
        and options.offer_trace_limit==math.floor(options.offer_trace_limit),'Offer trace limit must be 16..1024')
    options.offer_max_attempts=options.offer_max_attempts or 3
    assert(type(options.offer_max_attempts)=='number' and options.offer_max_attempts>=1 and options.offer_max_attempts<=3
        and options.offer_max_attempts==math.floor(options.offer_max_attempts),'Offer attempts must be 1..3')
    local clock,name=clock_source();local setup=require('systems/match_setup_service')
    local s={mode=GameRules:GetGameModeEntity(),fixture=fixture,guard=fixture.guard,match_mode=setup.get_mode(),session=setup.get_session_id(),
        options=options,clock=clock,clock_source=name,status='preparing',trace_limit=options.trace_limit,serial=0,owners={},network_clients_claimed=false,
        action_trace={},action_trace_limit=math.ceil(4*options.duration_seconds/0.25),
        setup_trace={},setup_trace_limit=64,setup_total=0,lifecycle_trace={},lifecycle_trace_limit=options.lifecycle_trace_limit,lifecycle_total=0,cast_probes={},
        offer_trace={},offer_trace_total=0}
    _G[KEY]=s;assert(guard_current(s),'Current write isolation/session required')
    for id=0,3 do
        local r=req('BUILDER_GET_REQUEST',{player_id=id});assert(r and r.ok and owned(r.builder,id,'builder'),'Owned native builder required')
        local scene
        for _,row in ipairs(fixture.defender_scene.players) do if row.id==id then scene=row;break end end
        local wall=scene and scene.units.wall or fixture.owners[id] and fixture.owners[id].wall
        assert(valid(wall),'Every owner requires its own live completed wall')
        local inward=scene and (scene.units.main_city:GetAbsOrigin()-wall:GetAbsOrigin()):Normalized() or fixture.inward
        local owner={id=id,builder=r.builder,scene=scene,inward=inward,wall_only=fixture.scenario=='B' and id~=fixture.defender_id,
            rng=(options.seed+id*104729)%2147483647,step=0,selector=0,offer_count=0,plan_digest=0,
            offer_rng=(options.seed+id*314159+17)%2147483646+1,modal_active=false,modal_deferred_polls=0,
            executed_plan_digest=0,run_id=tostring(options.seed)..':'..tostring(game_now()),
            stats={total=0,accepted=0,rejected=0,actions=0,actions_accepted=0,actions_rejected=0,by_kind={},action_by_kind={},completed_events=0,lifecycle_events={}},
            hero_observations={main_attack_fired=0,main_attack_landed=0,native_used_ability=0,native_used_exact_caster=0,
                native_used_player_identity_only=0,cast_orders=0,cast_effect_verified=0,cast_effect_unknown=0,cast_effect_not_observed=0,
                cast_probe_overflow=0,used_by_ability={},used_ability_name_count=0}}
        s.owners[#s.owners+1]=owner
        make_plan(owner,options.duration_seconds)
        local summoned=req('HERO_SUMMON_GET_REQUEST',{player_id=id})
        if owner.wall_only then assert(not (summoned and summoned.unit and valid(summoned.unit)),'Wall-only B owner must not have a combat hero')
        elseif options.require_heroes~=false then
            assert(hero(owner),'Prepare ordinary summoned heroes before activity (or explicitly require_heroes=false for a construction-only diagnostic)')
        end
        local before=wallet(id);assert(before.ok and before.debug_mode==0,'Real deduction requires a non-debug loaded match wallet')
        local requested=options.wallets and options.wallets[id] or {wood=1200000+id*500000,gold=600000+id*250000}
        assert(type(requested.wood)=='number' and requested.wood>=0 and requested.wood<=1000000000 and type(requested.gold)=='number' and requested.gold>=0 and requested.gold<=1000000000,'Bounded explicit match wallet balances required')
        owner.preparation_wallet=before;owner.requested_wallet=copy(requested)
    end
    -- All four actors, accounts and requested balances are checked before any
    -- wallet is modified. A thrown prepare stays 'preparing' and cannot start.
    for _,owner in ipairs(s.owners) do
        local id,before,requested=owner.id,owner.preparation_wallet,owner.requested_wallet
        local result=req('RESOURCE_ADD_REQUEST',{player_id=id,wood=requested.wood-before.wood,gold=requested.gold-before.gold,reason='tools_activity_match_wallet_rebalance'})
        local entry=finish({kind='prepare_wallet',resource_before=before,resource_after=wallet(id),requested=copy(requested)},result)
        record(s,owner,entry);assert(entry.accepted and entry.resource_after.debug_mode==0
            and entry.resource_after.wood==requested.wood and entry.resource_after.gold==requested.gold,'Match-only wallet rebalance failed')
        owner.initial_counts=counts(id)
    end
    s.offers_remaining=drain(s,8)
    s.status='prepared'
    return M.report()
end
function M.drain_offers()
    tools();local s=assert(current(),'Prepare activity first');assert(s.status~='running','Drain legal offers before the timed sample')
    s.offers_remaining=drain(s,8);return s.offers_remaining
end
function M.start()
    tools();local s=assert(current(),'Prepare activity first');assert(s.status=='prepared','Activity requires a freshly prepared deterministic run')
    assert(guard_current(s) and s.offers_remaining==0,'Current write isolation and all existing offers consumed required')
    assert(#s.owners==4,'All four players must be prepared')
    for _,owner in ipairs(s.owners) do assert(active_offer(owner.id).active~=1,'An offer opened after prepare; drain before starting') end
    for _,owner in ipairs(s.owners) do local account=wallet(owner.id);assert(account.ok and account.debug_mode==0,'Real loaded resource account required before starting') end
    s.started=s.clock();s.status='running'
    subscribe_lifecycle(s)
    subscribe_hero_observations(s)
    subscribe_offers(s)
    for _,owner in ipairs(s.owners) do owner.next_at=s.started+owner.id*0.1 end
    require('core/scheduler').every(0.1,function()
        if current()~=s or s.status~='running' then return false end
        if not guard_current(s) then M.stop('fixture_or_session_changed');return false end
        local at=s.clock();local elapsed=at-s.started
        if s.options.observe_hero_completion==true then check_cast_probes(s) end
        if elapsed>=s.options.duration_seconds then M.stop('duration_complete');return false end
        for _,owner in ipairs(s.owners) do
            local planned=owner.plan[owner.step+1]
            local had_modal=owner.modal_active==true
            if had_modal then choose_due_offer(s,owner,at) end
            -- A selection and its synchronous callbacks occupy this whole
            -- owner's poll, even if they close one offer or open the next one.
            if s.options.respect_reward_modal and had_modal then owner.modal_deferred_polls=owner.modal_deferred_polls+1
            elseif planned and elapsed>=planned.at and at>=owner.next_at then
            owner.step=owner.step+1
            owner.selector=planned.selector
            owner.executed_plan_digest=(owner.executed_plan_digest*131+owner.step+owner.selector%10007)%2147483647
            execute(s,owner,planned)
            if s.status~='running' then return false end
            -- The complete seed plan is fixed before sampling. Engine stalls
            -- can delay its prefix but cannot reroll it or create a catch-up
            -- flood: one action per owner per poll, with its normal interval
            -- enforced against actual dispatch time. Unexecuted work is shown.
            owner.next_at=at+planned.interval
            end
        end
        return true
    end,TASK)
    return {ok=true,seed=s.options.seed,duration_seconds=s.options.duration_seconds,clock_source=s.clock_source,network_clients_claimed=false}
end
function M.stop(reason)
    local s=current();if not s then return false end
    require('core/scheduler').cancel(TASK)
    for _,subscription in ipairs(s.subscriptions or {}) do bus().unsubscribe(subscription) end
    s.subscriptions={}
    for _,handle in ipairs(s.native_listeners or {}) do pcall(StopListeningToGameEvent,handle) end
    s.native_listeners={}
    for _,owner in ipairs(s.owners) do
        if owner.pending_offer then
            offer_record(s,owner,{kind='offer_private_selection_cancelled',token=owner.pending_offer.token,
                reason=reason or 'explicit_stop',original_ui_unchanged=true})
            owner.pending_offer=nil
        end
    end
    if s.status=='running' or s.status=='prepared' or s.status=='preparing' then s.status='stopped';s.stopped=s.clock();s.stop_reason=reason or 'explicit_stop' end
    return true
end
function M.report(options)
    tools();local s=assert(current(),'No current activity');options=options or {}
    local result={status=s.status,seed=s.options.seed,duration_seconds=s.options.duration_seconds,clock_source=s.clock_source,
        elapsed=s.started and ((s.stopped or s.clock())-s.started) or 0,stop_reason=s.stop_reason,trace_total=s.serial,
        trace_retained=#s.action_trace,trace_limit=s.action_trace_limit,offers_remaining=s.offers_remaining,
        schema='four_player_activity_v2',trace_kind='complete_scheduled_actions_only',action_trace_dropped=0,
        setup_trace_total=s.setup_total,setup_trace_retained=math.min(s.setup_total,s.setup_trace_limit),
        lifecycle_total=s.lifecycle_total,lifecycle_trace_retained=math.min(s.lifecycle_total,s.lifecycle_trace_limit),
        offer_trace_total=s.offer_trace_total,offer_trace_retained=math.min(s.offer_trace_total,s.options.offer_trace_limit),
        offer_trace_dropped=math.max(0,s.offer_trace_total-s.options.offer_trace_limit),
        auto_select_offers=s.options.auto_select_offers,respect_reward_modal=s.options.respect_reward_modal,
        offer_reaction_seconds={s.options.offer_choice_min_seconds,s.options.offer_choice_max_seconds},
        offer_observation=(s.options.auto_select_offers or s.options.respect_reward_modal)
            and 'formal_event_payload_and_selection_time_single_owner_readback_no_per_tick_ui_poll' or 'disabled_modal_bypass_diagnostic',
        modal_guard_disabled_diagnostic=s.options.respect_reward_modal~=true,
        hero_completion_observation_enabled=s.options.observe_hero_completion==true,
        scope='one_rendered_client_four_engine_owners',network_clients_claimed=false,
        real_account_writes_isolated=true,native_order_completion_not_asserted=true,
        deterministic_plan_timing=true,slow_frames_delay_plan_without_catchup=true,
        scheduler_poll_seconds=0.1,normal_action_interval_seconds={1,2},bounded_burst_interval_seconds=0.25,owners={}}
    for _,owner in ipairs(s.owners) do
        local unit=hero(owner);local r=req('HERO_SUMMON_GET_REQUEST',{player_id=owner.id})
        local details={};for _,building in ipairs(buildings(owner.id)) do
            details[#details+1]={kind=building.building_id,entindex=building.unit:entindex(),level=building.unit.survival_level}
        end
        result.owners[#result.owners+1]={player_id=owner.id,wall_only=owner.wall_only,steps=owner.step,plan_digest=owner.plan_digest,
            planned_steps=#owner.plan,unexecuted_steps=#owner.plan-owner.step,executed_plan_digest=owner.executed_plan_digest,
            stats=copy(owner.stats),wallet=wallet(owner.id),counts=counts(owner.id),initial_counts=copy(owner.initial_counts),
            hero_observations=s.options.observe_hero_completion==true and copy(owner.hero_observations) or nil,
            buildings=details,
            hero_id=unit and r.hero_id or nil,hero_level=unit and unit:GetLevel() or nil,
            research=copy(req('RESEARCH_STATE_GET_REQUEST',{player_id=owner.id}))}
        local reported=result.owners[#result.owners]
        reported.modal_active_observed=owner.modal_active==true;reported.modal_deferred_polls=owner.modal_deferred_polls
        reported.pending_offer_token=owner.pending_offer and owner.pending_offer.token
        reported.offer_block_reason=owner.offer_block_reason
    end
    if options.include_plan==true then
        result.plans={};for _,owner in ipairs(s.owners) do result.plans[owner.id]=copy(owner.plan) end
    end
    if options.include_trace==true then
        result.trace=copy(s.action_trace)
        result.setup_trace={};for serial=math.max(1,s.setup_total-s.setup_trace_limit+1),s.setup_total do result.setup_trace[#result.setup_trace+1]=copy(s.setup_trace[(serial-1)%s.setup_trace_limit+1]) end
        result.lifecycle_trace={};if s.lifecycle_trace_limit>0 then
            for serial=math.max(1,s.lifecycle_total-s.lifecycle_trace_limit+1),s.lifecycle_total do result.lifecycle_trace[#result.lifecycle_trace+1]=copy(s.lifecycle_trace[(serial-1)%s.lifecycle_trace_limit+1]) end
        end
        result.offer_trace={}
        for serial=math.max(1,s.offer_trace_total-s.options.offer_trace_limit+1),s.offer_trace_total do
            result.offer_trace[#result.offer_trace+1]=copy(s.offer_trace[(serial-1)%s.options.offer_trace_limit+1])
        end
    end
    if s.options.observe_hero_completion==true then
        result.hero_observation_scope={attack_start='unavailable: no formal windup-start bus event; main_attack_fired means native OnAttack release',
            hit='formal HERO_MAIN_ATTACK_LANDED, exact owned summoned hero only',
            native_used='native used-ability event; player-only identity is explicitly separate from exact caster identity',
            effect='only ball_lightning destination plus new cooldown verifies effect; unknown abilities remain unverified',
            pending_cast_probes=#s.cast_probes,native_listener_count=#(s.native_listeners or {}),
            native_listener_errors=copy(s.native_listener_errors),native_event_examples=copy(s.native_event_examples)}
    end
    return result
end
return M
