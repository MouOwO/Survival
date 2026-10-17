-- Explicit Tools-only fixture. require() does not install hooks or run a timer.
-- One rendered client plus three engine bots is NOT four network clients.
-- Finish ordinary host login/mode/difficulty selection, populate three native
-- bots, then prepare('A', opts) or prepare('B', opts) on a fresh template_map.
-- A reuses the normal four-region fixture. B keeps three owners wall-only and
-- prepares one normal defender; every wall uses production BUILD_REQUEST/grid.
-- No registered wall is moved and no real account/save write is permitted.
local M={}
local KEY='SURVIVAL_FOUR_PLAYER_LIVE_PERF'
local TASK='manual_four_player_live_perf'
local function copy(value)
    if type(value)~='table' then return value end
    local result={};for k,v in pairs(value) do result[k]=copy(v) end;return result
end
local function json_safe(value)
    if type(value)~='table' then return value end
    local maximum,count,array=0,0,true
    for key in pairs(value) do
        count=count+1
        if type(key)~='number' or key~=math.floor(key) or key<1 then array=false
        else maximum=math.max(maximum,key) end
    end
    array=array and maximum==count
    local result={}
    for key,child in pairs(value) do result[array and key or tostring(key)]=json_safe(child) end
    return result
end
local function valid(unit) return unit and not unit:IsNull() and unit:IsAlive() end
local function now() return GameRules:GetGameTime() end
local function line(message) print('[FOUR_PLAYER_LIVE_PERF] '..message) end
local function print_payload(tag,payload,report_id)
    local encoder=require('core/json_encoder')
    local encoded=encoder.encode(json_safe(payload))
    if #encoded<=2500 then line(tag..' '..encoded);return end
    -- Encoded data is already printable JSON. Re-encoding its quotes/backslashes
    -- can double the byte count, so 1400-byte chunks remain below 3 KB in normal
    -- console packets (and always below the 8192-byte transport bound).
    local parts,first={},1
    while first<=#encoded do
        local last=math.min(#encoded,first+1399)
        -- Do not cut the UTF-8 of a Chinese technology/name between packets.
        while last<#encoded do
            local next_byte=encoded:byte(last+1)
            if next_byte<128 or next_byte>191 then break end
            last=last-1
        end
        assert(last>=first,'Invalid UTF-8 status boundary')
        parts[#parts+1]=encoded:sub(first,last);first=last+1
    end
    local count=#parts
    for index=1,count do
        local chunk=encoder.encode({protocol='four_live_compact_chunk_v1',report_id=report_id,tag=tag,owner_id=payload.player_id,
            index=index,count=count,bytes=#encoded,data=parts[index]})
        assert(#chunk+#'[FOUR_PLAYER_LIVE_PERF] status_chunk '<=8192,'Compact status chunk exceeds console safety bound')
        line('status_chunk '..chunk)
    end
end
local function compact_wave(wave)
    local result={}
    for _,key in ipairs({'difficulty_id','current_wave','total_waves','player_id','alive','alive_limit','status','player_defeated','overflow_active'}) do
        if type(wave)=='table' then result[key]=wave[key] end
    end
    return result
end
local function print_compact_status(result,state)
    state.status_report_serial=(state.status_report_serial or 0)+1
    local report_id=state.status_report_serial
    print_payload('status',{report_id=report_id,scenario=result.scenario,status=result.status,
        error=result.error and tostring(result.error):sub(1,256),elapsed=result.elapsed,owner_count=#result.owners,
        network_clients_claimed=false,blocked_http=result.blocked_http,blocked_saves=result.blocked_saves,
        normal_fixture_status=result.normal_fixture_status,wave=compact_wave(result.wave),
        benchmark_keep_towers_alive=result.benchmark_keep_towers_alive,protected_tower_count=result.protected_tower_count,
        tower_min_health_floor=result.tower_min_health_floor,tower_survival_scope=result.tower_survival_scope},report_id)
    for _,owner in ipairs(result.owners) do
        local totals=(owner.permanent_effects or {}).totals or {}
        local selected={}
        for _,key in ipairs({'map_level','tower_attack_bonus_pct','tower_attack_flat','tower_attack_speed_bonus_pct',
            'wall_health_bonus_pct','wall_initial_health','wall_armor','lumberjack_attack_speed_bonus_pct','hero_attack_bonus_pct'}) do
            if type(totals[key])=='number' then selected[key]=totals[key] end
        end
        local native_minus_one,native_owner_match=0,0
        for _,building in ipairs(owner.buildings) do
            if building.native_owner==-1 then native_minus_one=native_minus_one+1
            elseif building.native_owner==owner.player_id then native_owner_match=native_owner_match+1 end
        end
        local research=owner.research or {}
        print_payload('owner',{report_id=report_id,player_id=owner.player_id,counts=owner.counts,workers=owner.workers,
            profile_revision=owner.profile_revision,map_level=owner.simulated_map_level,
            fake_engine_client=owner.fake_engine_client,steam_account_present=owner.steam_account_present,
            wall_only=owner.wall_only,native_ownership_valid=true,formal_context_audited=#owner.buildings,
            native_minus_one=native_minus_one,native_owner_match=native_owner_match,
            research_levels=research.levels or (research.snapshot and research.snapshot.levels) or {},
            selected_permanent=selected,permanent_baseline=owner.permanent_baseline,wave=compact_wave(owner.wave)},report_id)
    end
end
local function fixture() return require('tests/manual_real_game_stress') end
local function bus() return require('core/event_bus') end
local function events() return require('core/events') end
local function request(name,payload) return bus().request(events()[name] or name,payload) end
local function tools()
    assert(IsServer and IsServer() and IsInToolsMode and IsInToolsMode(),'Tools server only')
    assert(GetMapName()=='template_map','Only template_map is supported')
end
local function current()
    local state=_G[KEY]
    return state and state.mode==GameRules:GetGameModeEntity() and state or nil
end
local function state_required()
    tools();return assert(current(),'No current four-player live fixture')
end
local function rows(id)
    return (request('BUILDING_LIST_REQUEST',{player_id=id}) or {}).buildings or {}
end
local function owned(unit,id,kind)
    if not valid(unit) then return false end
    local row=request('BUILDING_QUERY_REQUEST',{entindex=unit:entindex(),read_only=true})
    -- Production buildings may retain native -1 while their immutable formal
    -- registration/context owns them. A different valid native ID is never OK.
    local native_owner=unit:GetPlayerOwnerID()
    return row and not row.constructing and row.unit==unit and row.building_id==kind
        and tonumber(row.player_id)==id and (native_owner==id or native_owner==-1)
        and require('systems/player_context_service').is_owned_by(id,unit)
end
local function owned_builder(unit,id)
    if not valid(unit) then return false end
    local row=request('BUILDER_GET_REQUEST',{player_id=id,caster=unit})
    local native_owner=unit:GetPlayerOwnerID()
    return row and row.ok and row.builder==unit and tonumber(row.player_id)==id
        and (native_owner==id or native_owner==-1)
        and require('systems/player_context_service').is_owned_by(id,unit)
end
local TOWER_MODIFIER='modifier_manual_four_player_live_perf_tower'
local function release_tower_survival(state)
    local records=state.tower_survival or {}
    state.tower_survival={}
    for _,modifier in pairs(records) do
        if modifier and not modifier:IsNull() then modifier:Destroy() end
    end
end
local function protect_selected_towers(state,require_complete)
    local scene=assert(state.defender_scene,'Normal fixture required for tower protection')
    assert(scene==_G.SURVIVAL_REAL_GAME_STRESS and scene.mode==state.mode,'Tower protection cannot bind a stale normal fixture')
    local targets={}
    for _,owner in ipairs(scene.players) do
        if require_complete then assert(#owner.towers==7,'Tower protection requires all seven prepared route towers') end
        for _,tower in ipairs(owner.towers) do
            assert(owned(tower,owner.id,'arrow_tower'),'Tower protection cannot revive or bind a dead/foreign/unregistered tower')
            targets[#targets+1]=tower
        end
    end
    -- Validate the complete selected set before adding any modifier. A fixture
    -- with dead towers cannot quietly masquerade as the 28-tower peak case.
    if require_complete then
        assert(#targets==(state.scenario=='A' and 28 or 7),'Prepared peak tower count changed')
    end
    if not state.tower_modifier_linked then
        LinkLuaModifier(TOWER_MODIFIER,'tests/'..TOWER_MODIFIER,LUA_MODIFIER_MOTION_NONE)
        require('tests/'..TOWER_MODIFIER)
        state.tower_modifier_linked=true
    end
    state.tower_survival=state.tower_survival or {}
    for _,tower in ipairs(targets) do
        local modifier=state.tower_survival[tower]
        if not modifier or modifier:IsNull() then
            modifier=tower:AddNewModifier(tower,nil,TOWER_MODIFIER,{})
            assert(modifier and not modifier:IsNull(),'Tools tower floor modifier unavailable')
            state.tower_survival[tower]=modifier
        end
        modifier.state,modifier.guard=state,state.guard
        if modifier:GetStackCount()~=1 then modifier:SetStackCount(1) end
    end
end
local function read_profiles(state)
    local profiles=require('systems/player_profile_service')
    local result={}
    for _,id in ipairs(state.ids) do
        local profile=profiles.get_profile(id)
        assert(profile and profile.save and profile.save.gameplay_stats,'In-memory profile missing for owner '..id)
        local expected=assert(state.memory_profiles[id],'Expected owner profile missing')
        assert(profile.account_id==expected.account_id and profile.revision==expected.revision,'Memory profile read fell through to a real account for '..id)
        for field,value in pairs(expected.save.gameplay_stats) do
            assert(profile.save.gameplay_stats[field]==value,'Actual profile read diverged for '..id..':'..field)
        end
        result[id]=copy(profile)
    end
    return result
end
local function install_profile_reads(state)
    local profiles=require('systems/player_profile_service')
    local match=require('systems/match_setup_service')
    state.match_mode,state.session=match.get_mode(),match.get_session_id()
    assert(type(state.session)=='string' and #state.session>=8,'Normally admitted match session required')
    state.profile_hooks={}
    state.original_profiles={}
    state.original_account_profiles={}
    state.profile_accounts={}
    state.profile_blocks={load_player=0,apply_snapshot=0,apply_incremental=0}
    for _,id in ipairs(state.ids) do
        state.original_profiles[id]=copy(profiles.get_profile(id))
        state.original_account_profiles[id]=copy(profiles.get_account_profile(id))
        local source=state.original_profiles[id]
        if source and source.account_id then state.profile_accounts[tostring(source.account_id)]=id end
        state.profile_accounts[tostring(state.memory_profiles[id].account_id)]=id
    end
    local function selected(id)
        if current()~=state or state.status=='stopped' or state.mode~=GameRules:GetGameModeEntity()
            or state.guard~=_G.SURVIVAL_REAL_GAME_STRESS_ISOLATION
            or match.get_mode()~=state.match_mode or match.get_session_id()~=state.session then return nil end
        return state.memory_profiles[tonumber(id)]
    end
    for _,name in ipairs({'get_profile','get_account_profile','get_progression','get_content_inventory_count'}) do
        local reader_name=name
        local original=profiles[name]
        assert(type(original)=='function','Formal profile reader missing: '..name)
        local wrapped
        if name=='get_content_inventory_count' then
            wrapped=function(id,content_id)
                local profile=selected(id)
                if not profile then return original(id,content_id) end
                if type(content_id)~='string' or content_id=='' then return nil end
                local count=tonumber(profile.save.content_inventory[content_id]) or 0
                return count==count and count<math.huge and math.max(0,math.floor(count)) or 0
            end
        else
            wrapped=function(id,...)
                local profile=selected(id)
                if not profile then return original(id,...) end
                return copy(reader_name=='get_progression' and profile.progression or profile)
            end
        end
        state.profile_hooks[#state.profile_hooks+1]={name=name,original=original,wrapped=wrapped}
        profiles[name]=wrapped
    end
    -- Late HTTP completions invoke these public functions dynamically. Keep
    -- the private/account/auth snapshots unchanged while overlay reads are live.
    -- Entry preflight refuses an already-pending load, because load_player
    -- invalidates the private snapshot before issuing its async request.
    for _,name in ipairs({'load_player','apply_snapshot','apply_incremental'}) do
        local entry_name=name
        local original=assert(profiles[name],'Formal async profile entry missing: '..name)
        assert(type(original)=='function','Formal async profile entry invalid: '..name)
        local wrapped=function(...)
            local args={...}
            local id=args[1]
            if entry_name=='apply_incremental' then
                local update=id
                if type(update)=='string' then
                    local ok,decoded=pcall(require('core/json_decoder').decode,update)
                    update=ok and decoded or nil
                end
                id=type(update)=='table' and state.profile_accounts[tostring(update.account_id)] or nil
            end
            if selected(id) then
                state.profile_blocks[entry_name]=state.profile_blocks[entry_name]+1
                local result={ok=false,pending=false,error='tools_four_profile_overlay_active'}
                if entry_name=='load_player' and type(args[4])=='function' then args[4](result.error) end
                return result
            end
            return original(...)
        end
        state.profile_hooks[#state.profile_hooks+1]={name=name,original=original,wrapped=wrapped}
        profiles[name]=wrapped
    end
end
local function restore_profile_reads(state)
    local profiles=require('systems/player_profile_service')
    for _,hook in ipairs(state.profile_hooks or {}) do
        if profiles[hook.name]==hook.wrapped then profiles[hook.name]=hook.original end
    end
end
local function configure_profiles(state,options)
    local guard=state.guard
    local defaults={}
    for _,row in ipairs(require('config/generated/player_gameplay_stats').rows or {}) do
        if row.enabled~=false then defaults[row.field_id]=row.default_value or 0 end
    end
    state.memory_profiles={}
    state.previous_guard_profiles=guard.four_live_profiles
    guard.four_live_profiles=state.memory_profiles
    local levels=options.map_levels or {[0]=1,[1]=9,[2]=17,[3]=24}
    for _,id in ipairs(state.ids) do
        local level=levels[id]
        assert(type(level)=='number' and level==math.floor(level) and level>=0 and level<=100,'map_levels must use explicit 0..3 keys and bounded nonnegative integers')
        local stats=copy(defaults)
        stats.map_level=level
        stats.online_seconds_total=(id+1)*3600
        stats.tower_attack_bonus_pct=id*7
        stats.wall_health_bonus_pct=id*5
        stats.lumberjack_attack_speed_bonus_pct=id*3
        stats.hero_attack_bonus_pct=id*4
        -- These are gameplay/stat projections, not an invented server inventory.
        local profile={account_id='tools_four_perf_owner_'..id,revision=id+1,schema_version=1,
            entitlements={},achievements={},public={},save={gameplay_stats=stats,archive={},content_inventory={}},
            progression={loaded=true,highest_difficulty=1,clear_counts={}}}
        if options.simulate_hero_unlock_items==true then
            local hero_id=options.hero_ids and options.hero_ids[id]
            if hero_id=='hero_monkey_king' then profile.save.content_inventory.lottery_monkey_king=1 end
            if hero_id=='hero_blademaster' then profile.save.content_inventory.commerce_p012=1 end
        end
        state.memory_profiles[id]=profile
    end
    install_profile_reads(state)
    if options.reset_permanent_runtime==true then
        local permanent=require('systems/permanent_reward_effect_service')
        assert(type(permanent.set_test_isolation)=='function' and type(permanent.clear_test_isolation)=='function',
            'Formal volatile-growth reset interfaces required')
        state.permanent_reset_game_time=now()
        state.permanent_reset_scope='fresh_benchmark_volatile_growth_only_not_persistent_profile'
        for _,id in ipairs(state.ids) do
            assert(permanent.set_test_isolation(id,'tower_attack_flat',true),'Tools growth reset failed for '..id)
            assert(permanent.clear_test_isolation(id,true),'Tools growth isolation release failed for '..id)
        end
    end
    for _,id in ipairs(state.ids) do
        bus().emit(events().PLAYER_PROFILE_CHANGED,{player_id=id,
            reason=options.reset_permanent_runtime and 'gameplay_stats_test_reset' or 'tools_four_live_memory_profile'})
    end
    state.permanent_baseline_started_game_time=now()
    state.permanent_baseline={}
    for _,id in ipairs(state.ids) do
        local projected=request('PERMANENT_REWARD_EFFECTS_GET_REQUEST',{player_id=id}) or {}
        local static,totals=projected.display_totals or {},projected.totals or {}
        local baseline={game_time=state.permanent_baseline_started_game_time,static=copy(static),totals=copy(totals),
            tower_attack_runtime_delta=(tonumber(totals.tower_attack_flat) or 0)-(tonumber(static.tower_attack_flat) or 0),
            reset_requested=options.reset_permanent_runtime==true,formal_projection_known=projected.ok==true}
        state.permanent_baseline[id]=baseline
        if options.reset_permanent_runtime==true then
            assert(projected.ok==true and type(projected.display_totals)=='table' and type(projected.totals)=='table',
                'Formal baseline projection unavailable for '..id)
            assert(baseline.tower_attack_runtime_delta==0,'Volatile tower attack growth survived fresh reset for '..id)
            assert(projected.test_isolation~=true,'Fresh baseline must keep every permanent stat, not single-field isolation')
        end
    end
    state.profile_inputs=read_profiles(state)
    line('profiles=memory_only owners=4 human_read_override=match_only persistent_write=blocked')
end
local function grant_currency(state,id)
    local wallet=request('RESOURCE_GET_REQUEST',{player_id=id}) or {}
    local floor=state.options.currency_floor
    if (tonumber(wallet.wood) or 0)<floor/2 or (tonumber(wallet.gold) or 0)<floor/2 then
        local result=request('RESOURCE_ADD_REQUEST',{player_id=id,wood=math.max(0,floor-(wallet.wood or 0)),
            gold=math.max(0,floor-(wallet.gold or 0)),reason='tools_four_live_match_currency'})
        assert(result and result.ok,'Match wallet grant rejected for '..id)
    end
end
local function candidates(target)
    local result={}
    for dx=-8,8 do for dy=-8,8 do
        result[#result+1]={point=target+Vector(dx*64,dy*64,0),distance=dx*dx+dy*dy}
    end end
    table.sort(result,function(a,b)
        if a.distance~=b.distance then return a.distance<b.distance end
        if a.point.x~=b.point.x then return a.point.x<b.point.x end
        return a.point.y<b.point.y
    end)
    return result
end
local function teleport_for_preparation(state,owner,point)
    assert(state.status=='preparing','Builder preparation teleport outside setup')
    local allowed,reason=require('systems/forbidden_region_service').validate_hero_position(point)
    if not allowed then return false,reason end
    FindClearSpaceForUnit(owner.builder,point,true)
    if (owner.builder:GetAbsOrigin()-point):Length2D()>48 then return false,'native_clear_space_displacement' end
    owner.preparation_teleports=owner.preparation_teleports+1
    return true
end
local function protect_extra_wall(state,owner)
    local scene=state.defender_scene
    local wall=owner.wall
    assert(owned(wall,owner.id,'wall'),'Extra wall is not a completed native owned wall')
    state.guard.wall_targets[wall]=scene
    scene.wall_survival=scene.wall_survival or {}
    local modifier=scene.wall_survival[wall]
    if not modifier or modifier:IsNull() then
        modifier=wall:AddNewModifier(wall,nil,'modifier_manual_real_game_stress_wall',{})
        assert(modifier and not modifier:IsNull(),'Tools wall lifetime protection unavailable')
        scene.wall_survival[wall]=modifier
    end
    modifier.scene,modifier.guard=scene,state.guard
    -- Existing fixture clamp/floor keep the test alive without replacing walls,
    -- changing spawn cadence, attack events, or collision footprints.
    require('systems/war3_armor_target').apply(wall,100000,0)
end
local function step_extra_wall(state,owner)
    grant_currency(state,owner.id)
    if owner.wall then return true end
    for _,row in ipairs(rows(owner.id)) do
        if row.building_id=='wall' and not row.constructing and owned(row.unit,owner.id,'wall') then
            owner.wall=row.unit;owner.phase='ready';protect_extra_wall(state,owner)
            line('wall_ready owner='..owner.id..' entindex='..owner.wall:entindex()..' native_owner='..owner.wall:GetPlayerOwnerID())
            return true
        end
    end
    if owner.builder.survival_build_task then return false end
    if owner.pending then
        owner.pending.handoff=owner.pending.handoff or now()
        if now()-owner.pending.handoff<6 then return false end
        owner.failures[#owner.failures+1]={reason='normal_construction_handoff_failed',point={x=owner.pending.point.x,y=owner.pending.point.y}}
        owner.pending=nil
        assert(#owner.failures<=8,'Production wall construction repeatedly failed for '..owner.id)
    end
    for _=1,8 do
        local candidate=owner.candidates[owner.candidate_index]
        owner.candidate_index=owner.candidate_index+1
        assert(candidate,'No legal shared-court wall cell for owner '..owner.id..': '..tostring(owner.last_error))
        if (candidate.point-state.court.wall):Length2D()<=1536 then
            local check=request('BUILD_CAN_PLACE_REQUEST',{player_id=owner.id,caster=owner.builder,building_id='wall',position=candidate.point})
            if check and check.ok then
                local point=check.grid.world_position
                local hull=owner.builder.GetHullRadius and owner.builder:GetHullRadius() or 32
                local moved,reason=teleport_for_preparation(state,owner,point+state.inward*(128+hull+32))
                local result=moved and request('BUILD_REQUEST',{player_id=owner.id,caster=owner.builder,building_id='wall',position=point}) or {ok=false,error=reason}
                if result and result.ok then
                    owner.pending={at=now(),point=point}
                    local task=owner.builder.survival_build_task
                    if task and task.work_position then teleport_for_preparation(state,owner,task.work_position) end
                    line('wall_queued owner='..owner.id..' x='..point.x..' y='..point.y..' production_grid=1')
                    return false
                end
                owner.last_error=result and result.error or 'normal_build_response_missing'
            else owner.last_error=check and check.error or 'normal_grid_response_missing' end
        end
    end
    return false
end
local function normalize(options)
    options=copy(options or {})
    options.research_levels=options.research_levels==nil and 1 or options.research_levels
    options.sr_stage_level=options.sr_stage_level or 1
    options.currency_floor=options.currency_floor or 1000000000
    options.timeout=options.timeout or 3600
    if options.simulate_hero_unlock_items~=nil then assert(type(options.simulate_hero_unlock_items)=='boolean','simulate_hero_unlock_items must be boolean') end
    if options.benchmark_keep_towers_alive==nil then options.benchmark_keep_towers_alive=false end
    assert(type(options.benchmark_keep_towers_alive)=='boolean','benchmark_keep_towers_alive must be boolean')
    if options.reset_permanent_runtime==nil then options.reset_permanent_runtime=false end
    assert(type(options.reset_permanent_runtime)=='boolean','reset_permanent_runtime must be boolean')
    for key,bounds in pairs({research_levels={0,100},sr_stage_level={1,5},currency_floor={100000,1000000000000},timeout={60,7200}}) do
        local value=options[key]
        assert(type(value)=='number' and value==math.floor(value) and value>=bounds[1] and value<=bounds[2],key..' out of range')
    end
    local levels=options.map_levels or {[0]=1,[1]=9,[2]=17,[3]=24}
    assert(type(levels)=='table','map_levels must be a table keyed 0..3')
    for id=0,3 do
        local value=levels[id]
        assert(type(value)=='number' and value==math.floor(value) and value>=0 and value<=100,'map_levels must contain four bounded integer values under 0..3 keys')
    end
    options.map_levels=copy(levels)
    if options.simulated_rebirth_level~=nil then
        local rank=options.simulated_rebirth_level
        assert(type(rank)=='number' and rank==math.floor(rank) and rank>=0 and rank<=10,'simulated_rebirth_level must be 0..10')
    end
    if options.simulate_exclusive_skill_rewards~=nil then
        assert(type(options.simulate_exclusive_skill_rewards)=='boolean','simulate_exclusive_skill_rewards must be boolean')
    end
    if options.defender_id~=nil then
        assert(options.defender_id==0 or options.defender_id==1 or options.defender_id==2 or options.defender_id==3,'defender_id must be 0..3')
    end
    return options
end
-- Explicit activity preparation. Hero-specific ownership is an in-memory
-- match profile fixture; the ordinary hero access/altar/summon path still runs.
function M.prepare_activity_fixture(scenario,options)
    options=copy(options or {})
    -- An activity benchmark starts a new scenario baseline; retain an explicit
    -- opt-out for older read-only fixture/diagnostic comparisons.
    if options.reset_permanent_runtime==nil then options.reset_permanent_runtime=true end
    if not options.hero_ids then
        if scenario=='A' then
            options.hero_ids={[0]='hero_monkey_king',[1]='hero_blademaster',[2]='hero_drow_ranger',[3]='hero_doom'}
        else options.hero_ids={[options.defender_id or 0]='hero_monkey_king'} end
    end
    options.simulate_hero_unlock_items=true
    options.simulated_rebirth_level=options.simulated_rebirth_level or 3
    if options.simulate_exclusive_skill_rewards==nil then options.simulate_exclusive_skill_rewards=true end
    return M.prepare(scenario,options)
end
function M.prepare(scenario,options)
    tools();assert(scenario=='A' or scenario=='B','scenario must be A (four regions) or B (one defender/three wall-only)')
    assert(GameRules:State_Get()==DOTA_GAMERULES_STATE_GAME_IN_PROGRESS,'Finish normal login/mode/difficulty first')
    assert(not current() or current().status=='stopped','Stop previous wrapper; B additionally requires a fresh map')
    local previous=_G.SURVIVAL_REAL_GAME_STRESS
    assert(not previous or previous.mode~=GameRules:GetGameModeEntity() or previous.status~='preparing','Normal fixture already preparing')
    options=normalize(options)
    if scenario=='B' and options.hero_ids~=nil then
        assert(type(options.hero_ids)=='table','hero_ids must be a table')
        for id in pairs(options.hero_ids) do assert(id==(options.defender_id or 0),'B permits combat heroes only for the defender') end
    end
    local ids={0,1,2,3}
    local profiles=require('systems/player_profile_service')
    assert(type(profiles.is_loading)=='function','Formal profile load status required')
    local pending={}
    for _,id in ipairs(ids) do
        if (tonumber(PlayerResource:GetSteamAccountID(id)) or 0)>0 and profiles.is_loading(id) then
            pending[#pending+1]=id
        end
    end
    if #pending>0 then
        return {ok=false,waiting=true,status='waiting_profile_load',reason='human_profile_load_pending',
            pending_player_ids=pending,auth_changed=false,profile_hooks_installed=false}
    end
    assert(require('systems/startup_loading_service').is_gameplay_ready(),'Normal host admission is not complete')
    if options.reset_permanent_runtime==true then
        assert(not current() or current().mode~=GameRules:GetGameModeEntity(),
            'Volatile growth reset requires a fresh benchmark world; do not reset/recover an old scenario')
    end
    for _,id in ipairs(ids) do
        assert(PlayerResource:IsValidPlayerID(id) and PlayerResource:GetPlayer(id) and PlayerResource:GetTeam(id)==DOTA_TEAM_GOODGUYS,'Four actual engine player objects required; missing '..id)
        if scenario=='B' then
            assert(#rows(id)==0,'B requires fresh owned building state; walls cannot be moved or rebuilt to fake this layout')
            assert(#(request('WORKER_LIST_REQUEST',{player_id=id}) or {})==0,'B requires a fresh match without prior player workers')
        end
    end
    local f=fixture()
    -- Resolve/validate actual map markers before installing profile overrides.
    local courts=f.map_court_positions()
    local guard=f.isolate_writes()
    f.admit_bots(ids)
    local actual_builders={}
    for _,id in ipairs(ids) do
        local row=request('BUILDER_GET_REQUEST',{player_id=id})
        assert(row and row.ok and owned_builder(row.builder,id),'Formal/context/native owned builder required for '..id)
        actual_builders[id]=row.builder
    end
    local state={mode=GameRules:GetGameModeEntity(),scenario=scenario,status='preparing',started=now(),ids=ids,guard=guard,
        options=options,owners={},network_clients_claimed=false,write_isolated=true}
    _G[KEY]=state
    local configured,configuration_error=pcall(configure_profiles,state,options)
    if not configured then
        state.status='stopped'
        restore_profile_reads(state)
        if guard.four_live_profiles==state.memory_profiles then guard.four_live_profiles=state.previous_guard_profiles end
        error(configuration_error)
    end
    local selected=ids
    if scenario=='B' then
        local defender=options.defender_id or 0
        assert(defender==0 or defender==1 or defender==2 or defender==3,'defender_id must be 0..3')
        state.defender_id=defender;selected={defender}
        state.court=courts[defender]
        state.inward=(state.court.city-state.court.wall):Normalized()
        local across=Vector(-state.inward.y,state.inward.x,0)
        local offsets={-384,384,768};local index=0
        for _,id in ipairs(ids) do if id~=defender then
            index=index+1
            local builder={builder=actual_builders[id]}
            local target=state.court.wall+across*offsets[index]
            state.owners[id]={id=id,builder=builder.builder,phase='wall',candidates=candidates(target),candidate_index=1,
                preparation_teleports=0,failures={}}
            f.select_opening_reward(id)
        end end
    end
    state.defender_scene=f.prepare({player_ids=selected,simulate_bot_profiles=true,research_levels=options.research_levels,
        sr_stage_level=options.sr_stage_level,wall_level=options.wall_level or 1,timeout=options.timeout,
        currency_floor=options.currency_floor,ordinary_lv8=options.ordinary_lv8 or 3,fill_lv8=options.fill_lv8==true,
        region_court_positions=courts,hero_ids=options.hero_ids,simulated_rebirth_level=options.simulated_rebirth_level,
        simulate_exclusive_skill_rewards=options.simulate_exclusive_skill_rewards})
    require('core/scheduler').every(0.25,function()
        if current()~=state or state.status~='preparing' then return false end
        local ok,reason=pcall(function()
            assert(now()-state.started<=options.timeout,'Four-player preparation timed out')
            assert(state.defender_scene.status~='failed',state.defender_scene.error or 'Normal defender preparation failed')
            local ready=state.defender_scene.status=='ready'
            if scenario=='B' then
                for _,owner in pairs(state.owners) do if not step_extra_wall(state,owner) then ready=false end end
            end
            if state.options.benchmark_keep_towers_alive then protect_selected_towers(state,ready) end
            if ready then state.status='ready';line('ready scenario='..scenario..' owners=4 network_clients_claimed=false');M.status();return false end
            return true
        end)
        if not ok then state.status='failed';state.error=tostring(reason);line('failed '..state.error);return false end
        return reason
    end,TASK)
    line('preparing scenario='..scenario..' owners=4 research_levels='..options.research_levels..' sr_stage_level='..options.sr_stage_level..' normal_timers=1')
    return state
end
-- Explicit current-world repair of an older rank-only fixture. It refreshes
-- only the isolated profile view and claims already-eligible formal rewards.
function M.refresh_simulated_hero_skills(options)
    options=options or {};assert(options.enabled==true,'Explicit simulated skill refresh required')
    local state=state_required()
    assert(state.status=='ready' or state.status=='preparing','Active four-owner fixture required')
    assert(state.guard==_G.SURVIVAL_REAL_GAME_STRESS_ISOLATION,'Current isolation required')
    local match=require('systems/match_setup_service')
    assert(match.get_mode()==state.match_mode and match.get_session_id()==state.session,'Fixture match/session changed')
    assert(state.defender_scene==_G.SURVIVAL_REAL_GAME_STRESS and state.defender_scene.mode==state.mode,'Formal defender scene changed')
    read_profiles(state)
    local id=tonumber(options.player_id)
    assert(id and id==math.floor(id) and id>=0 and id<=3 and state.options.hero_ids and state.options.hero_ids[id],
        'Only configured defending combat heroes can refresh; wall-only players rejected')
    local result=fixture().refresh_simulated_hero_skills(options)
    read_profiles(state)
    if result.ok then
        state.simulated_skill_refreshes=state.simulated_skill_refreshes or {}
        state.simulated_skill_refreshes[id]={target=result.target,rank=result.rebirth_level,granted=copy(result.granted),
            game_time=now(),map_level=result.map_level}
    end
    return result
end
function M.status(options)
    options=options or {};assert(type(options)=='table','status options must be a table')
    local state=state_required()
    local profiles=require('systems/player_profile_service')
    local result={scenario=state.scenario,status=state.status,error=state.error,elapsed=now()-state.started,
        network_clients_claimed=false,measurement_scope='one_rendered_client_four_engine_owners',defender_id=state.defender_id,
        options=copy(state.options),write_isolated=true,blocked_http=state.guard.blocked_http,blocked_saves=state.guard.blocked_saves,
        normal_fixture_status=state.defender_scene and state.defender_scene.status,owners={},wave=copy(request('WAVE_STATE_GET_REQUEST',{})),
        wall_survival_protection='existing_tools_armor_clamp_and_min_health_floor',preparation_teleports_only=true,
        benchmark_keep_towers_alive=state.options.benchmark_keep_towers_alive==true,
        tower_survival_scope='selected_normal_fixture_towers_only',tower_min_health_floor=state.options.benchmark_keep_towers_alive and 1 or 0,
        protected_tower_count=0}
    result.profile_blocks=copy(state.profile_blocks)
    result.permanent_baseline_started_game_time=state.permanent_baseline_started_game_time
    result.permanent_reset_game_time=state.permanent_reset_game_time
    result.permanent_reset_scope=state.permanent_reset_scope
    for _,modifier in pairs(state.tower_survival or {}) do
        if modifier and not modifier:IsNull() then result.protected_tower_count=result.protected_tower_count+1 end
    end
    for _,id in ipairs(state.ids) do
        local counts,buildings={},{}
        for _,row in ipairs(rows(id)) do
            local unit=row.unit
            if valid(unit) then
                assert(tonumber(row.player_id)==id and owned(unit,id,row.building_id),'Building formal/context/native ownership diverged for '..id)
                counts[row.building_id]=(counts[row.building_id] or 0)+1
                local point=unit:GetAbsOrigin()
                buildings[#buildings+1]={kind=row.building_id,entindex=unit:entindex(),native_owner=unit:GetPlayerOwnerID(),
                    level=unit.survival_level,constructing=row.constructing==true,x=point.x,y=point.y,
                    health=unit:GetHealth(),max_health=unit:GetMaxHealth()}
            end
        end
        local profile=profiles.get_profile(id)
        local worker_list=request('WORKER_LIST_REQUEST',{player_id=id}) or {}
        local fake_client=nil
        if PlayerResource.IsFakeClient then fake_client=PlayerResource:IsFakeClient(id) end
        local live_permanent=copy(request('PERMANENT_REWARD_EFFECTS_GET_REQUEST',{player_id=id}))
        local permanent_baseline=state.permanent_baseline[id] or {}
        local live_static=(live_permanent or {}).display_totals or {}
        local live_totals=(live_permanent or {}).totals or {}
        local row={player_id=id,fake_engine_client=fake_client,
            steam_account_present=(tonumber(PlayerResource:GetSteamAccountID(id)) or 0)>0,
            counts=counts,buildings=buildings,workers=#worker_list,profile_revision=profile and profile.revision,
            simulated_map_level=profile and profile.save and profile.save.gameplay_stats.map_level,
            permanent_effects=live_permanent,permanent_baseline={started_game_time=permanent_baseline.game_time,
                reset_requested=permanent_baseline.reset_requested,formal_projection_known=permanent_baseline.formal_projection_known,
                static_tower_attack_flat=tonumber(live_static.tower_attack_flat) or 0,
                total_tower_attack_flat=tonumber(live_totals.tower_attack_flat) or 0,
                tower_attack_runtime_delta=(tonumber(live_totals.tower_attack_flat) or 0)-(tonumber(live_static.tower_attack_flat) or 0),
                initial_static_tower_attack_flat=tonumber((permanent_baseline.static or {}).tower_attack_flat) or 0,
                initial_total_tower_attack_flat=tonumber((permanent_baseline.totals or {}).tower_attack_flat) or 0},
            research=copy(request('RESEARCH_STATE_GET_REQUEST',{player_id=id})),wallet=copy(request('RESOURCE_GET_REQUEST',{player_id=id})),
            wave=copy(request('WAVE_STATE_GET_REQUEST',{player_id=id}))}
        local summoned=request('HERO_SUMMON_GET_REQUEST',{player_id=id})
        if summoned and summoned.ok and valid(summoned.unit) then
            row.hero={hero_id=summoned.hero_id,entindex=summoned.unit:entindex(),native_owner=summoned.unit:GetPlayerOwnerID(),
                level=summoned.unit.GetLevel and summoned.unit:GetLevel() or nil,
                progression=copy(request('HERO_PROGRESSION_GET_REQUEST',{player_id=id}))}
            local skills=request('HERO_SKILL_STATE_GET_REQUEST',{player_id=id})
            row.hero.formal_skill_state_known=skills and skills.ok==true and skills.snapshot
                and skills.snapshot.hero_ready==1 and skills.snapshot.unit_entindex==summoned.unit:entindex() or false
            row.hero.exclusive_skills={}
            local allowed={};for _,definition in ipairs(require('config/generated/hero_exclusive_skills').rows or {}) do
                if definition.hero_id==summoned.hero_id and definition.enabled~=false then allowed[definition.skill_id]=true end
            end
            for _,skill in ipairs(skills and skills.snapshot and skills.snapshot.skills or {}) do
                if allowed[skill.skill_id] then row.hero.exclusive_skills[#row.hero.exclusive_skills+1]={
                    skill_id=skill.skill_id,level=skill.level,locked=skill.locked} end
            end
            row.hero.simulated_exclusive_rewards_enabled=state.options.simulate_exclusive_skill_rewards==true
        end
        if state.scenario=='B' and id~=state.defender_id then
            row.wall_only=true;row.preparation=copy(state.owners[id].failures)
            if state.status=='ready' then
                assert(counts.wall==1 and #buildings==1 and #worker_list==0,'Wall-only owner gained unintended gameplay assets '..id)
            end
        end
        result.owners[#result.owners+1]=row
    end
    result=json_safe(result)
    if options.quiet~=true then print_compact_status(result,state) end
    return result
end
-- Recover only a fully prepared, still-owned fixture after an audit/report
-- failure. This does not build, move, upgrade, re-register, or reschedule assets.
function M.recover_ready(options)
    local state=state_required()
    assert(state.status=='failed' or state.status=='ready','Recovery is only for a completed fixture audit')
    local scene=assert(state.defender_scene,'Underlying normal fixture missing')
    assert(scene==_G.SURVIVAL_REAL_GAME_STRESS and scene.mode==state.mode and scene.status=='ready','Underlying normal fixture is not ready/current')
    assert(state.guard==_G.SURVIVAL_REAL_GAME_STRESS_ISOLATION and state.guard.mode==state.mode,'Write-isolation guard changed')
    read_profiles(state)
    local result=M.status({quiet=true})
    assert(#result.owners==4,'Recovery requires four audited owners')
    for _,owner in ipairs(result.owners) do
        assert(owner.counts.wall==1,'Recovery requires every completed wall')
        if state.scenario=='A' or owner.player_id==state.defender_id then
            assert(owner.counts.arrow_tower==7,'Recovery requires the normal seven-tower defender')
        else assert(#owner.buildings==1 and owner.workers==0,'Wall-only ownership changed before recovery') end
    end
    state.status='ready';state.error=nil
    line('recovered_ready scenario='..state.scenario..' native_minus_one_formal_context_audited=1 assets_changed=0')
    return M.status(options)
end
function M.spawn_wave(number)
    local state=state_required();assert(state.status=='ready','Wait until all four owners are ready')
    number=number or 15;assert(number==15,'Use the documented wave-15 baseline')
    local ok,reason=require('systems/wave_system').debug_spawn_wave_for_players(number,state.ids)
    assert(ok,'Four production wave channels rejected: '..tostring(reason))
    state.wave_started=now();line('spawn_wave=15 channels=4 scenario='..state.scenario)
    return ok
end
function M.hold_tower_attacks(enabled)
    state_required();return fixture().hold_tower_attacks(enabled)
end
function M.set_keep_towers_alive(enabled)
    local state=state_required();assert(type(enabled)=='boolean','set_keep_towers_alive expects boolean')
    assert(state.status=='preparing' or state.status=='ready','Active fixture required')
    if not enabled then
        state.options.benchmark_keep_towers_alive=false
        release_tower_survival(state)
        line('tower_min_health_floor=off removed_exact_handles=1')
        return true
    end
    local previous=state.options.benchmark_keep_towers_alive
    state.options.benchmark_keep_towers_alive=true
    local ok,reason=pcall(protect_selected_towers,state,state.status=='ready')
    if not ok then
        state.options.benchmark_keep_towers_alive=previous
        if not previous then release_tower_survival(state) end
        error(reason)
    end
    line('tower_min_health_floor=1 scope=selected_normal_fixture_towers_only stats_changed=0 attack_events_retained=1')
    return true
end
function M.stop()
    local state=state_required()
    local activity=package.loaded['tests/manual_four_player_activity']
    if activity and activity.stop then activity.stop('wrapper_stopped') end
    require('core/scheduler').cancel(TASK)
    fixture().stop()
    state.status='stopped'
    release_tower_survival(state)
    restore_profile_reads(state)
    if state.guard.four_live_profiles==state.memory_profiles then
        state.guard.four_live_profiles=state.previous_guard_profiles
    end
    for _,id in ipairs(state.ids) do
        bus().emit(events().PLAYER_PROFILE_CHANGED,{player_id=id,reason='tools_four_live_profile_restored'})
    end
    line('stopped profiles_restored=1 built_assets_retained=1 write_isolation_retained_until_map_restart=1')
    return state
end
return M
