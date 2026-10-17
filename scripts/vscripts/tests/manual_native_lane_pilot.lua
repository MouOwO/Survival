-- Inert raw loader experiment. No formal wave registration, rewards or FPS proof.
-- prepare({enabled=true, archetype_id=..., variant='lane'|'control'}) explicitly
-- precaches one selected unit. create({enabled=true,position={x=...,y=...,z=...}})
-- creates at most ONE raw enemy; it applies no stats, model, abilities or orders.
local M={}
local KEY='SURVIVAL_NATIVE_LANE_PILOT'
local MARK='survival_native_lane_pilot_token'
local serial=0
local CODES={'Tools_server_required','native_loader_api_missing','admitted_match_required','isolated_fixture_required',
    'variant_invalid','manifest_invalid','archetype_not_allowed','formal_source_changed','source_KV_changed',
    'alias_KV_unknown_or_changed','lifetime_out_of_bounds','four_owner_ids_required','four_active_owners_required',
    'four_owner_native_mismatch','isolated_profile_read_mismatch','completed_owned_wall_required'}
local function safe_code(value)
    if type(value)=='string' then
        for _,code in ipairs(CODES) do if value:find(code,1,true) then return code end end
    end
    return 'dependency_or_native_api_failed'
end
local function number(v) return type(v)=='number' and v==v and math.abs(v)~=math.huge end
local function same(a,b)
    if type(a)~=type(b) then return false end
    if type(a)~='table' then return a==b end
    for k,v in pairs(a) do if not same(v,b[k]) then return false end end
    for k in pairs(b) do if a[k]==nil then return false end end
    return true
end
-- LoadKeyValues converts these declared numeric strings into native numbers.
-- Only the three explicitly floating source fields permit float32 rounding;
-- profile equality above remains exact, and no unknown/nested KV is admitted.
local KV_INTEGER={Level=true,ConsideredHero=true,HasInventory=true,StatusHealth=true,StatusMana=true,
    AttackDamageMin=true,AttackDamageMax=true,AttackRange=true,MovementSpeed=true,MagicalResistance=true,
    VisionDaytimeRange=true,VisionNighttimeRange=true}
local KV_FLOAT={ModelScale=true,AttackRate=true,ArmorPhysical=true}
local KV_STRING={BaseClass=true,Model=true,MovementCapabilities=true,AttackCapabilities=true,BoundsHullName=true}
local function numeric(v)
    if type(v)~='number' and type(v)~='string' then return nil end
    local value=tonumber(v)
    return number(value) and value or nil
end
local function kv_same(actual,expected)
    if type(actual)~='table' or type(expected)~='table' then return false end
    for key,value in pairs(expected) do
        local got=actual[key]
        if KV_INTEGER[key] then
            local wanted,read=numeric(value),numeric(got)
            if not wanted or not read or wanted~=math.floor(wanted) or read~=wanted then return false end
        elseif KV_FLOAT[key] then
            local wanted,read=numeric(value),numeric(got)
            local max_float32=(2-2^-23)*2^127
            if not wanted or not read or math.abs(wanted)>max_float32 or math.abs(read)>max_float32 then return false end
            if read~=wanted then
                -- Normal float32 spacing is 2^(frexp-exponent - 24); below
                -- the smallest normal it is fixed at 2^-149. No added epsilon.
                local _,exponent=math.frexp(math.abs(wanted))
                local half_ulp=math.abs(wanted)<2^-126 and 2^-150 or 2^(exponent-25)
                if math.abs(read-wanted)>half_ulp then return false end
            end
        elseif KV_STRING[key] then
            if type(value)~='string' or type(got)~='string' or value~=got then return false end
        else return false end
    end
    for key in pairs(actual) do if expected[key]==nil then return false end end
    return true
end
local function exists(u)
    local ok,value=pcall(function() return u and u:IsNull()==false end)
    return ok and value==true
end
local function error_result(code) return {ok=false,error=code,formal_registration=false,persistent_write=false} end
local function native(u,method,bool)
    if type(u[method])~='function' then return {available=false,error='getter_missing'} end
    local ok,value
    if bool then
        ok,value=pcall(u[method],u,false)
        if not ok and type(value)=='string'
            and value:find(method..' called with 2 arguments - expected 1',1,true) then
            ok,value=pcall(u[method],u)
        end
    else ok,value=pcall(u[method],u) end
    if not ok then return {available=false,error='getter_failed'} end
    if value==nil then return {available=true,is_nil=true} end
    if type(value)=='number' and not number(value) then return {available=false,error='nonfinite'} end
    if type(value)~='number' and type(value)~='string' and type(value)~='boolean' then
        return {available=false,error='non_scalar'}
    end
    return {available=true,value=value}
end
local function scope(s)
    local ok,result=pcall(function()
        if not IsServer() or not IsInToolsMode() or GetMapName()~='template_map'
            or GameRules:State_Get()~=DOTA_GAMERULES_STATE_GAME_IN_PROGRESS then return false end
        local setup=require('systems/match_setup_service')
        return _G[KEY]==s and not s.stopped and GameRules:GetGameModeEntity()==s.world
            and _G.SURVIVAL_REAL_GAME_STRESS_ISOLATION==s.guard and s.guard.mode==s.world
            and _G.SURVIVAL_FOUR_PLAYER_LIVE_PERF==s.fixture and s.fixture.mode==s.world
            and s.fixture.guard==s.guard and s.fixture.status=='ready'
            and setup.get_mode()==s.match_mode and setup.get_session_id()==s.session
            and s.bus==require('core/event_bus') and s.bus.get_generation()==s.generation
    end)
    return ok and result==true
end
local function four_owners(s)
    local profiles=require('systems/player_profile_service')
    local context=require('systems/player_context_service')
    local events=require('core/events')
    assert(type(s.fixture.ids)=='table' and #s.fixture.ids==4,'four_owner_ids_required')
    local active=context.active_player_ids();assert(#active==4,'four_active_owners_required')
    local found={};for _,id in ipairs(active) do found[id]=true end
    for index=1,4 do
        local id=index-1
        assert(s.fixture.ids[index]==id and found[id] and PlayerResource:IsValidPlayerID(id)
            and PlayerResource:GetPlayer(id) and PlayerResource:GetTeam(id)==DOTA_TEAM_GOODGUYS,'four_owner_native_mismatch')
        local expected=s.fixture.memory_profiles and s.fixture.memory_profiles[id]
        local actual=profiles.get_profile(id)
        assert(expected and actual and actual.account_id==expected.account_id and actual.revision==expected.revision
            and expected.save and actual.save and same(expected.save.gameplay_stats,actual.save.gameplay_stats),
            'isolated_profile_read_mismatch')
        local list=s.bus.request(events.BUILDING_LIST_REQUEST,{player_id=id}) or {}
        local wall
        for _,row in ipairs(list.buildings or list) do
            if row.building_id=='wall' and row.constructing~=true and row.unit and exists(row.unit)
                and row.unit:IsAlive()==true and tonumber(row.player_id)==id then
                local u=row.unit;local owner=u:GetPlayerOwnerID()
                if (owner==id or owner==-1) and context.is_owned_by(id,u) then wall=u end
            end
        end
        assert(wall,'completed_owned_wall_required')
    end
end
local function authority(s)
    if not scope(s) then return false end
    local ok=pcall(four_owners,s)
    return ok
end
local function owned(s)
    local ok,result=pcall(function()
        return GameRules:GetGameModeEntity()==s.world and exists(s.unit)
            and s.unit[MARK]==s.token and s.unit:entindex()==s.entindex
            and EntIndexToHScript(s.entindex)==s.unit
    end)
    return ok and result==true
end
local function remove_owned(s)
    if not s.unit then return true end
    if s.cleanup_requested then
        if not exists(s.unit) then s.removed=true;s.unit=nil end
        return true
    end
    if not owned(s) then s.cleanup_refused=true;return false end
    local ok=pcall(UTIL_Remove,s.unit)
    if ok then
        s.cleanup_requested=true
        if not exists(s.unit) then s.removed=true;s.unit=nil end
    else s.cleanup_refused=true end
    return ok
end
local function stop_state(s,reason)
    s.stopped=true;s.reason=reason or 'explicit_stop'
    if s.timeout_task then require('core/scheduler').cancel(s.timeout_task) end
    if s.precache_task then require('core/scheduler').cancel(s.precache_task) end
    return remove_owned(s)
end
local GETTERS={class_name='GetClassname',unit_name='GetUnitName',model='GetModelName',scale='GetModelScale',
    team='GetTeamNumber',native_owner='GetPlayerOwnerID',base_npc='IsBaseNPC',real_hero='IsRealHero',hero='IsHero',
    creep='IsCreep',creature='IsCreature',other='IsOther',health='GetHealth',max_health='GetMaxHealth',
    mana='GetMana',max_mana='GetMaxMana',damage_min='GetBaseDamageMin',damage_max='GetBaseDamageMax',
    armor='GetPhysicalArmorBaseValue',move_speed='GetBaseMoveSpeed',move_capability='GetMoveCapability',
    attack_capability='GetAttackCapability',attack_range='Script_GetAttackRange',acquisition='GetAcquisitionRange',
    projectile='GetRangedProjectileName',projectile_speed='GetProjectileSpeed',hull='GetHullRadius',
    health_regen='GetHealthRegen',mana_regen='GetManaRegen',bounty_xp='GetDeathXP',
    gold_min='GetMinimumGoldBounty',gold_max='GetMaximumGoldBounty',vision_day='GetDayTimeVisionRange',
    vision_night='GetNightTimeVisionRange',BAT='GetBaseAttackTime',AS='GetAttackSpeed',
    SPA='GetSecondsPerAttack',APS='GetAttacksPerSecond',animation_point='GetAttackAnimationPoint'}
local BOOLEAN={BAT=true,AS=true,SPA=true,APS=true,animation_point=true}
local function readback(s)
    local u=s.unit;local out={entindex=s.entindex,getters={},abilities={},modifiers={}}
    s.partial_readback=out
    for key,method in pairs(GETTERS) do out.getters[key]=native(u,method,BOOLEAN[key]) end
    local count=native(u,'GetAbilityCount')
    assert(count.available and number(count.value) and count.value>=0 and count.value<=64
        and count.value==math.floor(count.value),'native_ability_count_unknown')
    for slot=0,count.value-1 do
        local ability=u:GetAbilityByIndex(slot)
        if ability~=nil then
            assert(exists(ability),'native_ability_handle_unknown')
            out.abilities[#out.abilities+1]={slot=slot,name=native(ability,'GetAbilityName'),
                level=native(ability,'GetLevel'),passive=native(ability,'IsPassive'),
                hidden=native(ability,'IsHidden'),intrinsic=native(ability,'GetIntrinsicModifierName')}
        end
    end
    local mods=u:FindAllModifiers();assert(type(mods)=='table' and #mods<=64,'native_modifier_list_unknown')
    for _,modifier in ipairs(mods) do
        assert(exists(modifier),'native_modifier_handle_unknown')
        out.modifiers[#out.modifiers+1]=native(modifier,'GetName')
    end
    local target=u:GetAttackTarget()
    out.attack_target_entindex=exists(target) and target:entindex() or -1
    out.raw_unregistered=s.unit.survival_is_wave_monster~=true and s.unit.survival_is_challenge_monster~=true
        and s.unit.survival_player_id==nil
    local g=out.getters
    assert(g.class_name.available and g.class_name.value==s.expected_class,'native_class_mismatch')
    assert(g.unit_name.available and g.unit_name.value==s.name,'native_unit_name_mismatch')
    assert(g.base_npc.available and g.base_npc.value==true and g.real_hero.available
        and g.real_hero.value==false and g.hero.available and g.hero.value==false,'native_role_mismatch')
    assert(g.team.available and g.team.value==DOTA_TEAM_BADGUYS,'native_team_mismatch')
    assert(g.model.available and g.model.value==s.contract.source_fields.Model,'native_model_mismatch')
    assert(out.raw_unregistered,'unexpected_formal_registration')
    for _,key in ipairs({'health','max_health','damage_min','damage_max','move_speed','attack_capability','BAT','AS','SPA','APS'}) do
        assert(g[key].available and number(g[key].value),'native_required_numeric_unknown:'..key)
    end
    return out
end
function M.prepare(options)
    if not options or options.enabled~=true then return {ok=false,error='explicit_enable_required',enabled=false} end
    local previous=_G[KEY]
    if previous and not previous.stopped then return error_result('stop_previous_pilot_first') end
    if previous and previous.unit and exists(previous.unit) then return error_result('previous_owned_unit_not_removed') end
    local ok,s=pcall(function()
        assert(IsServer() and IsInToolsMode() and GetMapName()=='template_map','Tools_server_required')
        assert(type(CreateUnitByName)=='function' and type(PrecacheUnitByNameAsync)=='function'
            and type(UTIL_Remove)=='function' and type(EntIndexToHScript)=='function'
            and type(Vector)=='function','native_loader_api_missing')
        local setup=require('systems/match_setup_service');local bus=require('core/event_bus')
        local state={world=GameRules:GetGameModeEntity(),guard=_G.SURVIVAL_REAL_GAME_STRESS_ISOLATION,
            fixture=_G.SURVIVAL_FOUR_PLAYER_LIVE_PERF,bus=bus,generation=bus.get_generation(),
            match_mode=setup.get_mode(),session=setup.get_session_id(),status='preparing',used=0}
        assert(type(state.session)=='string' and #state.session>=8,'admitted_match_required')
        assert(state.guard and state.guard.mode==state.world and state.fixture and state.fixture.mode==state.world
            and state.fixture.guard==state.guard and state.fixture.status=='ready','isolated_fixture_required')
        assert(options.variant==nil or options.variant=='lane' or options.variant=='control','variant_invalid')
        local manifest=require('config/generated/native_lane_pilot_manifest')
        assert(manifest.schema=='native_lane_pilot_v1' and manifest.alias_count==2 and manifest.unit_budget==1,'manifest_invalid')
        state.contract=assert(manifest.by_id[options.archetype_id or 'humanoid_white_melee'],'archetype_not_allowed')
        local definition=require('config/generated/monster_archetypes').by_id[state.contract.archetype_id]
        assert(definition and definition.enabled~=false and definition.considered_boss==false
            and definition.unit_name==state.contract.source_unit_name,'formal_source_changed')
        local kv=LoadKeyValues('scripts/npc/npc_units_custom.txt');kv=kv and (kv.DOTAUnits or kv)
        assert(kv and kv_same(kv[state.contract.source_unit_name],state.contract.source_fields),'source_KV_changed')
        local fields={};for k,v in pairs(state.contract.source_fields) do fields[k]=v end
        fields.BaseClass='npc_dota_creep_lane'
        assert(kv_same(kv[state.contract.alias_unit_name],fields),'alias_KV_unknown_or_changed')
        -- Both names are loaded in the same native KV call. Permit no actual
        -- source/alias numeric drift hidden inside two independent tolerances.
        local loaded_alias={};for k,v in pairs(kv[state.contract.source_unit_name]) do loaded_alias[k]=v end
        loaded_alias.BaseClass='npc_dota_creep_lane'
        assert(same(kv[state.contract.alias_unit_name],loaded_alias),'alias_KV_unknown_or_changed')
        state.variant=options.variant or 'lane'
        state.name=state.variant=='lane' and state.contract.alias_unit_name or state.contract.source_unit_name
        state.expected_class=state.variant=='lane' and 'npc_dota_creep_lane' or 'npc_dota_creature'
        state.lifetime=options.lifetime_seconds or 30
        assert(number(state.lifetime) and state.lifetime>=1 and state.lifetime<=60,'lifetime_out_of_bounds')
        four_owners(state)
        serial=serial+1;state.token={};state.serial=serial
        return state
    end)
    if not ok then local result=error_result('prepare_preflight_rejected');result.reason=safe_code(s);return result end
    _G[KEY]=s
    if not scope(s) then stop_state(s,'scope_changed');return error_result('scope_changed') end
    s.precache_task='native_lane_pilot_precache:'..s.serial
    require('core/scheduler').after(15,function()
        if not s.ready then s.status='failed';stop_state(s,'precache_timeout') end
    end,s.precache_task)
    local ready_called=false
    local queued=pcall(PrecacheUnitByNameAsync,s.name,function()
        if ready_called then return end;ready_called=true
        if not authority(s) then stop_state(s,'precache_scope_changed');return end
        s.ready=true;s.status='ready'
        require('core/scheduler').cancel(s.precache_task)
    end,-1)
    if not queued then stop_state(s,'precache_failed');return error_result('precache_failed') end
    local result=M.snapshot()
    if s.status=='preparing' and scope(s) then result.ok=true;result.waiting=true end
    return result
end
function M.create(options)
    if not options or options.enabled~=true then return error_result('explicit_enable_required') end
    local s=_G[KEY]
    if not s or not authority(s) then return error_result('current_isolated_four_owner_scope_required') end
    if not s.ready then return error_result('precache_not_ready') end
    if s.used~=0 then return error_result('one_unit_budget_exhausted') end
    local p=options.position
    if type(p)~='table' or not number(p.x) or not number(p.y) or not number(p.z)
        or math.abs(p.x)>20000 or math.abs(p.y)>20000 or math.abs(p.z)>10000 then return error_result('position_invalid') end
    local point_ok,point=pcall(Vector,p.x,p.y,p.z)
    if not point_ok then return error_result('native_position_failed') end
    -- No implicit FindClearSpace or setter changes: the loader observes native defaults.
    s.used=1
    local created,u=pcall(CreateUnitByName,s.name,point,false,nil,nil,DOTA_TEAM_BADGUYS)
    if not created or not exists(u) then stop_state(s,'native_create_failed');return error_result('native_create_failed') end
    if u[MARK]~=nil or u.survival_player_id~=nil or u.survival_is_wave_monster==true
        or u.survival_is_challenge_monster==true then
        stop_state(s,'unexpected_creation_registration');return error_result('unexpected_creation_registration')
    end
    s.unit=u;u[MARK]=s.token
    local id_ok,id=pcall(u.entindex,u)
    if id_ok and number(id) then s.entindex=id end
    if not owned(s) or not authority(s) then stop_state(s,'created_identity_or_scope_changed');return error_result('created_identity_or_scope_changed') end
    local read_ok,result=pcall(readback,s)
    if not read_ok then
        s.readback_error='native_readback_rejected';s.status='failed'
        s.readback=s.partial_readback
        local codes={'native_ability_count_unknown','native_ability_handle_unknown','native_modifier_list_unknown',
            'native_modifier_handle_unknown','native_class_mismatch','native_unit_name_mismatch',
            'native_role_mismatch','native_team_mismatch','native_model_mismatch','unexpected_formal_registration'}
        for _,code in ipairs(codes) do
            if type(result)=='string' and result:find(code,1,true) then s.readback_error=code end
        end
        if type(result)=='string' then
            for key in pairs(GETTERS) do
                local code='native_required_numeric_unknown:'..key
                if result:find(code,1,true) then s.readback_error=code end
            end
        end
        -- Save available scalars for native class-failure diagnosis, never raw exception strings.
        s.failure_identity={class_name=native(u,'GetClassname'),unit_name=native(u,'GetUnitName'),model=native(u,'GetModelName')}
        stop_state(s,'native_readback_rejected');return M.snapshot()
    end
    s.readback=result;s.status='created'
    s.timeout_task='native_lane_pilot_timeout:'..s.serial
    require('core/scheduler').after(s.lifetime,function() stop_state(s,'bounded_lifetime_complete') end,s.timeout_task)
    return M.snapshot()
end
function M.snapshot()
    local s=_G[KEY]
    if not s then return {ok=true,enabled=false,formal_registration=false,persistent_write=false} end
    if s.cleanup_requested and s.unit and not exists(s.unit) then s.removed=true;s.unit=nil end
    local result={ok=(s.status=='ready' or s.status=='created') and not s.readback_error,enabled=scope(s),status=s.status,
        stopped=s.stopped==true,reason=s.reason,variant=s.variant,archetype_id=s.contract.archetype_id,
        unit_name=s.name,expected_class=s.expected_class,unit_budget=1,budget_used=s.used,
        precache_ready=s.ready==true,entindex=s.entindex,removed=s.removed==true,
        cleanup_requested=s.cleanup_requested==true,cleanup_refused=s.cleanup_refused==true,
        readback=s.readback,failure_identity=s.failure_identity,
        readback_error=s.readback_error,
        formal_registration=false,persistent_write=false,formal_rewards_verified=false,
        native_basic_attack_verified=false,native_AI_verified=false,FPS_gain_verified=false,
        gameplay_setters_used=0,attack_commands_issued=0,network_clients_verified=false}
    if owned(s) then
        result.current_identity={class_name=native(s.unit,'GetClassname'),health=native(s.unit,'GetHealth'),alive=native(s.unit,'IsAlive')}
    end
    return result
end
function M.stop()
    local s=_G[KEY]
    if not s then return M.snapshot() end
    stop_state(s,'explicit_stop');return M.snapshot()
end
return M
