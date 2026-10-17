-- Explicit Tools fixture; require() is inert. All assets use normal registries,
-- construction, upgrade, training and research timers. Currency grants and bot
-- admission are match-only simulations. Never claims four networked clients.
-- Console after a normally admitted match:
-- script require('tests/manual_real_game_stress').prepare({player_ids={0}})
-- Four real engine bot/player objects: prepare({player_ids={0,1,2,3},simulate_bot_profiles=true})
-- Central lobby markers are not four build courts. On the approved sanctuary,
-- use region_court_positions=map_court_positions() to derive actual separated
-- cities/wall landings from c6_player_N_turret_2/corner_2 entities. This only
-- guides preparation; the production context/markers/ownership are unchanged.
-- Optional fill_lv8=true fills the population earned by the normal farm flow.
-- Optional hero_ids={[0]='hero_doom',...} builds a normal altar and uses the
-- normal hero summon request. simulated_rebirth_level=0..10 grants only the
-- match-local rank prerequisite through HERO_PROGRESSION_APPLY_REQUEST before
-- normal research. This simulates rank; no Boss completion, attributes, skill
-- rewards, or permanent account records are granted. Explicit
-- simulate_exclusive_skill_rewards=true also claims only legally unlocked
-- configured exclusives through the public skill-grant API. Defaults add no heroes.
-- sr_stage_level=1..5 selects the actual SR stage (default 5); use a new map
-- for a weaker baseline rather than keeping higher-tier user towers nearby.
-- status() reports actual ownership/counts. spawn_wave(15) starts only wave 15;
-- four-owner scenarios use the Tools-only multi-channel wave API.
-- Backlogged wave boundary, separately from ordinary monster15: when ready,
-- hold_tower_attacks(true), spawn_wave(15), wait for normal spawning/arrival,
-- then hold_tower_attacks(false). Only the scene's seven selected towers per
-- owner are held; existing extra towers still attack and are reported by status.
-- Hold before spawning: already fired projectiles can finish. No damage, health,
-- attack speed, wave count, or spawn timer is changed. stop() restores the hold.
-- protect_walls() installs the projection clamp on an existing ready scene.
-- Registered walls also receive a Tools-only minimum-health floor of 1: high
-- armor still permits cumulative damage. This prevents test defeat without
-- changing health/max-health, damage calculations, attack events, or targetability.
-- stop() stops fixture work but preserves write isolation until map restart.
-- Armor projection protection ends on stop or when the engine match changes.
local M = {}
local KEY, GUARD, TASK = 'SURVIVAL_REAL_GAME_STRESS', 'SURVIVAL_REAL_GAME_STRESS_ISOLATION', 'manual_real_game_stress'
local function valid(unit) return unit and not unit:IsNull() and unit:IsAlive() end
local function clock() return GameRules:GetGameTime() end
local function tools()
    assert(IsServer and IsServer() and IsInToolsMode and IsInToolsMode(), 'Tools server only')
    assert(GetMapName() == 'template_map', 'template_map test match only')
end
local function copy(source)
    if type(source) ~= 'table' then return source end
    local result = {}; for key,value in pairs(source) do result[key] = copy(value) end; return result
end
local function bus() return require('core/event_bus') end
local function events() return require('core/events') end
local function request(name, data) return bus().request(events()[name] or name, data) end
local function line(message) print('[REAL_GAME_STRESS] '..message) end
local function owner(id)
    return PlayerResource:IsValidPlayerID(id) and PlayerResource:GetPlayer(id)
        and PlayerResource:GetTeam(id) == DOTA_TEAM_GOODGUYS
end
local function current_guard()
    local guard = _G[GUARD]
    return guard and guard.mode == GameRules:GetGameModeEntity() and guard or nil
end
local function current_scene()
    local scene=_G[KEY]
    return scene and scene.mode==GameRules:GetGameModeEntity() and scene or nil
end
local HOLD_MODIFIER='modifier_manual_real_game_stress_hold'
local WALL_MODIFIER='modifier_manual_real_game_stress_wall'
local function release_wall_survival(scene)
    if not scene or not scene.wall_survival then return end
    for _,modifier in pairs(scene.wall_survival) do
        if modifier and not modifier:IsNull() then modifier:Destroy() end
    end
    scene.wall_survival=nil
end
local function release_attack_hold(scene)
    if not scene or not scene.attack_hold then return 0 end
    local records=scene.attack_hold
    scene.attack_hold=nil
    for _,record in ipairs(records) do
        -- Destroy exactly our handle, preserving unrelated/player disarms.
        if record.modifier and not record.modifier:IsNull() then record.modifier:Destroy() end
        if record.unit and not record.unit:IsNull() then record.unit:SetAttackCapability(record.capability) end
    end
    return #records
end
local function enroll_wall(guard,scene,state)
    local unit=state.units.wall
    if not unit then return end
    if guard.wall_targets[unit]~=scene then
        assert(valid(unit),'Registered stress wall unavailable')
        local registered=request('BUILDING_QUERY_REQUEST',{entindex=unit:entindex(),read_only=true})
        assert(registered and registered.unit==unit and registered.building_id=='wall'
            and tonumber(registered.player_id)==state.id,'Armor protection requires the actual registered owner wall')
        guard.wall_targets[unit]=scene
        require('systems/war3_armor_target').apply(unit,100000,0)
    end
    scene.wall_survival=scene.wall_survival or {}
    local modifier=scene.wall_survival[unit]
    if not modifier or modifier:IsNull() then
        modifier=unit:AddNewModifier(unit,nil,WALL_MODIFIER,{})
        assert(modifier and not modifier:IsNull(),'Tools wall survival modifier unavailable')
        scene.wall_survival[unit]=modifier
    end
    modifier.scene,modifier.guard=scene,guard
    if modifier:GetStackCount()~=1 then modifier:SetStackCount(1) end
end

function M.isolate_writes()
    tools()
    if current_guard() then return current_guard() end
    local guard = {mode=GameRules:GetGameModeEntity(), blocked_http=0, blocked_saves=0, bots={}}
    _G[GUARD] = guard
    local factory = assert(CreateHTTPRequestScriptVM, 'HTTP factory required for write isolation')
    CreateHTTPRequestScriptVM = function(method, url)
        if current_guard() ~= guard then return factory(method,url) end
        local endpoint = (tostring(url):match('^[^?#]+') or ''):match('/v1/.*$')
        -- Allow the real account loading/read flow; deny every other request,
        -- including payment, lottery draws, online credits and match rewards.
        if endpoint == '/v1/session/authenticate' or endpoint == '/v1/session/login'
            or endpoint == '/v1/profile' or endpoint == '/v1/lottery/snapshot' then
            return factory(method,url)
        end
        guard.blocked_http = guard.blocked_http + 1
        return {
            SetHTTPRequestHeaderValue=function() end,
            SetHTTPRequestRawPostBody=function() end,
            SetHTTPRequestGetOrPostParameter=function() end,
            SetHTTPRequestAbsoluteTimeoutMS=function() end,
            SetHTTPRequestNetworkActivityTimeout=function() end,
            Send=function(_,complete)
                if complete then complete({StatusCode=403,Body='{"error":"tools_stress_write_isolated"}'}) end
                return true
            end,
        }
    end
    local profiles = require('systems/player_profile_service')
    for _,name in ipairs({'update_save_sections','update_save_section','apply_update'}) do
        local original = profiles[name]
        if type(original) == 'function' then
            profiles[name] = function(...)
                if current_guard() ~= guard then return original(...) end
                guard.blocked_saves = guard.blocked_saves + 1
                return {ok=false,error='tools_stress_write_isolated'}
            end
        end
    end
    line('write_isolation=active lifetime=until_map_restart')
    return guard
end

function M.protect_walls()
    tools()
    local scene=assert(current_scene(),'Current match scene required')
    assert(scene.status=='preparing' or scene.status=='ready','Wall protection requires a preparing/ready test scene')
    local guard=M.isolate_writes()
    if not guard.wall_modifier_linked then
        LinkLuaModifier(WALL_MODIFIER,'tests/modifier_manual_real_game_stress_wall',LUA_MODIFIER_MOTION_NONE)
        require('tests/modifier_manual_real_game_stress_wall')
        guard.wall_modifier_linked=true
    end
    local target=require('systems/war3_armor_target')
    if target.apply~=guard.armor_wrapper then
        local original=target.apply
        guard.armor_original=original
        guard.wall_targets=guard.wall_targets or {}
        guard.armor_wrapper=function(unit,base,bonus)
            -- Non-walls pay only a table lookup; no scan, timer, or event payload.
            local selected=guard.wall_targets[unit]
            if selected and current_guard()==guard and current_scene()==selected
                and (selected.status=='preparing' or selected.status=='ready') then
                guard.forced_wall_refreshes=(guard.forced_wall_refreshes or 0)+1
                return original(unit,100000,0)
            end
            return original(unit,base,bonus)
        end
        target.apply=guard.armor_wrapper
    end
    if guard.armor_subscription then
        if type(bus().unsubscribe)=='function' then bus().unsubscribe(guard.armor_subscription) end
        guard.armor_subscription=nil
    end
    for _,state in ipairs(scene.players) do enroll_wall(guard,scene,state) end
    line('wall_armor_protection=active registered_walls_only=1 value=100000 refresh=normal_production_apply wall_min_health=1 native_attack_events=retained')
    return true
end

function M.admit_bots(player_ids)
    tools()
    local guard = M.isolate_writes()
    local profiles, loading = require('systems/player_profile_service'), require('systems/startup_loading_service')
    assert(loading.is_gameplay_ready(), 'Finish normal human admission/mode/difficulty before bot admission')
    if not guard.bot_hooks then
        guard.bot_hooks = true
        for _,name in ipairs({'get_profile','get_account_profile','get_progression'}) do
            local original = profiles[name]
            profiles[name] = function(id,...)
                local profile = current_guard() == guard and guard.bots[tonumber(id)]
                if profile then return copy(name == 'get_progression' and profile.progression or profile) end
                return original(id,...)
            end
        end
        local original_ready = loading.is_player_ready
        loading.is_player_ready = function(id)
            id = tonumber(type(id)=='table' and (id.player_id or id.PlayerID) or id)
            if current_guard() == guard and guard.bots[id] then return owner(id) and true or false end
            return original_ready(id)
        end
    end
    if not guard.bot_content_count_hook and type(profiles.get_content_inventory_count)=='function' then
        guard.bot_content_count_hook = true
        local setup=require('systems/match_setup_service')
        local admitted_mode,admitted_session=setup.get_mode(),setup.get_session_id()
        local original = profiles.get_content_inventory_count
        profiles.get_content_inventory_count = function(id,content_id)
            id = tonumber(id)
            local profile = current_guard() == guard and guard.bots[id]
            if profile and setup.get_mode()==admitted_mode and setup.get_session_id()==admitted_session
                and owner(id) and (tonumber(PlayerResource:GetSteamAccountID(id)) or 0)<=0 then
                if type(content_id)~='string' or content_id=='' then return nil end
                local count=tonumber((profile.save.content_inventory or {})[content_id]) or 0
                return count==count and count<math.huge and math.max(0,math.floor(count)) or 0
            end
            return original(id,content_id)
        end
    end
    for _,id in ipairs(player_ids or {}) do
        id = tonumber(id)
        assert(id and id>=0 and id<require('systems/player_context_service').max_players() and owner(id),
            'Bot requires a real valid Radiant PlayerResource object in configured slots')
        if (tonumber(PlayerResource:GetSteamAccountID(id)) or 0) <= 0 then
            local hero = PlayerResource:GetSelectedHeroEntity(id)
            assert(valid(hero) and hero:GetPlayerOwnerID()==id, 'Bot requires its own real selected hero')
            if guard.bots[id] then
                local registered=request('BUILDER_GET_REQUEST',{player_id=id})
                assert(registered and registered.ok and valid(registered.builder)
                    and require('systems/player_context_service').is_owned_by(id,registered.builder),
                    'Previously admitted bot lost its formal owned builder')
                line('simulated_owner='..id..' admission=reused real_player=1 real_builder=1 network_client=0')
            else
                local stats = {}
                for _,row in ipairs(require('config/generated/player_gameplay_stats').rows) do
                    if row.enabled ~= false then stats[row.field_id] = row.default_value or 0 end
                end
                guard.bots[id] = {account_id='tools_stress_bot_'..id,revision=0,schema_version=1,
                    entitlements={},achievements={},public={},save={gameplay_stats=stats,archive={}},
                    progression={loaded=true,highest_difficulty=1,clear_counts={}}}
                require('systems/multiplayer_player_service').mark_connected(id)
                bus().emit(events().PLAYER_PROFILE_CHANGED, {player_id=id,reason='tools_stress_memory_bot_profile'})
                hero:SetAttackCapability(DOTA_UNIT_CAP_NO_ATTACK)
                require('systems/hero_anchor_service').register_placeholder(id,hero)
                bus().emit(events().HERO_READY, {player_id=id,hero=hero,team=DOTA_TEAM_GOODGUYS})
                local registered = request('BUILDER_GET_REQUEST',{player_id=id})
                assert(registered and registered.ok and valid(registered.builder), 'Formal bot builder registration failed')
                line('simulated_owner='..id..' real_player=1 real_hero=1 real_builder=1 network_client=0 persistent_profile=0')
            end
        end
    end
    return true
end

function M.select_opening_reward(player_id)
    tools()
    M.isolate_writes()
    local snapshot=CustomNetTables:GetTableValue('survival_rogue_reward',tostring(player_id)) or {}
    if snapshot.builder_talent and snapshot.builder_talent.card_id then return snapshot.builder_talent.card_id end
    local opened=request('ROGUE_REWARD_OPEN_REQUEST',{player_id=player_id,source='builder',reward_type='builder_start'})
    assert(opened and opened.ok,'Normal opening reward unavailable: '..tostring(opened and opened.error))
    if opened.selected then return opened.selected end
    snapshot=CustomNetTables:GetTableValue('survival_rogue_reward',tostring(player_id)) or {}
    assert(snapshot.active==1 and snapshot.token and snapshot.reward_type=='builder_start','Real opening offer is not visible')
    local candidates={}
    for _,card in pairs(snapshot.cards or {}) do candidates[#candidates+1]=card end
    table.sort(candidates,function(a,b) return a.card_id<b.card_id end)
    local instant={instant_wood=true,radiant_sapling=true,fiscal_subsidy=true,infrastructure_outsourcing=true}
    local selected=candidates[1]
    for _,card in ipairs(candidates) do if instant[card.card_id] then selected=card;break end end
    assert(selected,'Opening offer contains no real candidates')
    local result=request('ROGUE_REWARD_SELECT_REQUEST',{player_id=player_id,token=snapshot.token,
        card_id=selected.card_id,reward_type=snapshot.reward_type})
    assert(result and result.ok,'Real opening choice failed: '..tostring(result and result.error))
    line('opening_reward player='..player_id..' card='..selected.card_id..' instant_resource='..tostring(instant[selected.card_id]==true)
        ..' fallback=lexicographic_first_real_candidate no_reroll=1')
    return selected.card_id
end

function M.map_court_positions()
    tools()
    local result={}
    for id=0,require('systems/player_context_service').max_players()-1 do
        local prefix='c6_player_'..id
        local turret=assert(Entities:FindByName(nil,prefix..'_turret_2'),'Actual court turret marker missing: '..id)
        local corner=assert(Entities:FindByName(nil,prefix..'_corner_2'),'Actual upper landing marker missing: '..id)
        local start,landing=turret:GetAbsOrigin(),corner:GetAbsOrigin()
        local delta=landing-start
        -- tools/map_c6/sanctuary.cjs: turret2=(1408,624), corner2=(2432,912).
        -- Recover its actual orthogonal rotation from the two live markers;
        -- no dependence on the central lobby builder/wave marker direction.
        assert(math.abs(delta:Length2D()-math.sqrt(1024*1024+288*288))<64,'Court marker geometry differs from the approved sanctuary: '..id)
        local xaxis=(Vector(delta.x,delta.y,0)*1024+Vector(delta.y,-delta.x,0)*288):Normalized()
        local yaxis=Vector(-xaxis.y,xaxis.x,0)
        local city=start+yaxis*864
        local wall=landing-xaxis*128
        result[id]={position=city,city=city,wall=wall,source='actual_c6_court_markers',
            turret_marker=prefix..'_turret_2',landing_marker=prefix..'_corner_2'}
    end
    return result
end

local function court_point(value,label)
    assert(value and tonumber(value.x) and tonumber(value.y),label..' requires world x/y')
    local x,y,z=tonumber(value.x),tonumber(value.y),tonumber(value.z) or 400
    assert(x==x and y==y and z==z and math.abs(x)<math.huge and math.abs(y)<math.huge and math.abs(z)<math.huge,
        label..' requires finite coordinates')
    return Vector(x,y,z)
end

local function buildings(state, id)
    local result = {}
    for _,entry in ipairs((request('BUILDING_LIST_REQUEST',{player_id=state.id}) or {}).buildings or {}) do
        if entry.building_id==id and tonumber(entry.player_id)==state.id and valid(entry.unit) then result[#result+1]=entry.unit end
    end
    table.sort(result,function(a,b) return a:entindex()<b:entindex() end)
    return result
end
local function desired(state, id, index)
    local d,p,b=state.direction,state.perpendicular,state.base
    if state.court and (id=='main_city' or id=='wall') then return state.court[id=='wall' and 'wall' or 'city'] end
    if state.units.main_city and state.units.wall and id~='main_city' and id~='wall' then
        local city=state.units.main_city:GetAbsOrigin()
        local delta=city-state.units.wall:GetAbsOrigin()
        local inward=Vector(delta.x,delta.y,0):Normalized()
        local across=Vector(-inward.y,inward.x,0)
        if id=='building_farm' then return city+inward*128+across*384 end
        if id=='building_research_lab' then return city+inward*320+across*256 end
        if id=='building_advanced_research_lab' then return city+inward*320-across*256 end
        if id=='hero_altar' then return city+inward*64-across*384 end
    end
    if id=='wall' then return b+d*320 end
    if id=='main_city' then return b-d*256 end
    if id=='building_farm' then return b-d*384+p*384 end
    if id=='building_research_lab' then return b-d*640+p*256 end
    if id=='building_advanced_research_lab' then return b-d*640-p*256 end
    if id=='hero_altar' then return b-d*384-p*384 end
    local wall=state.units.wall and state.units.wall:GetAbsOrigin() or b+d*320
    local city=state.units.main_city and state.units.main_city:GetAbsOrigin() or b-d*256
    local delta=city-wall
    local inward=Vector(delta.x,delta.y,0):Normalized()
    local across=Vector(-inward.y,inward.x,0)
    -- Four towers in the front row and three behind, all inside the wall.
    local prepared_range=require('config/tower_combat_rules').attack_range()
    local depth=index<=4 and 224 or math.min(480,prepared_range-256)
    local lateral=index<=4 and (index-2.5)*192 or (index-6)*192
    return wall+inward*depth+across*lateral
end
local function interior(state)
    if not state.units.wall or not state.units.main_city then return nil end
    local wall=state.units.wall:GetAbsOrigin()
    local delta=state.units.main_city:GetAbsOrigin()-wall
    assert(delta:Length2D()>64,'Main city and wall cannot define a safe interior')
    return wall,Vector(delta.x,delta.y,0):Normalized()
end
local function legal_region(state,point)
    local anchor=state.units.main_city and state.units.main_city:GetAbsOrigin() or state.base
    if (point-anchor):Length2D()>1280 then return false,'outside_owner_base_radius' end
    local own_distance=(point-anchor):Length2D()
    for id,position in pairs(state.regions or {}) do
        if id~=state.id and (point-position):Length2D()+128<own_distance then return false,'nearer_other_player_region' end
    end
    return true
end
local function legal_tower_position(state,point,range)
    local ok,reason=legal_region(state,point);if not ok then return false,reason end
    local wall,inward=interior(state);if not wall then return false,'wall_city_interior_missing' end
    local delta=point-wall
    local depth=delta.x*inward.x+delta.y*inward.y
    if depth<224 then return false,'outside_wall_interior_clearance' end
    -- Cover an enemy center just beyond the wall's 128-unit footprint.
    range=range or require('config/tower_combat_rules').attack_range()
    if (point-(wall-inward*192)):Length2D()>range-16 then return false,'outside_wall_combat_range' end
    return true
end
local function candidate_list(state,id,index)
    local target=desired(state,id,index);local result={}
    for dx=-10,10 do for dy=-10,10 do
        result[#result+1]={point=target+Vector(dx*64,dy*64,0),distance=dx*dx+dy*dy}
    end end
    table.sort(result,function(a,b)
        if a.distance~=b.distance then return a.distance<b.distance end
        if a.point.x~=b.point.x then return a.point.x<b.point.x end;return a.point.y<b.point.y
    end)
    return result
end
local function prep_teleport(state,point,reason)
    assert(type(FindClearSpaceForUnit)=='function','Engine clear-space helper required for preparation')
    local ok,why=legal_region(state,point);if not ok then return false,why end
    local wall,inward=interior(state)
    if wall then
        local delta=point-wall
        if delta.x*inward.x+delta.y*inward.y<160 then return false,'builder_work_outside_wall' end
    end
    local regions=require('systems/forbidden_region_service')
    local allowed,region_error=regions.validate_hero_position(point)
    if not allowed then return false,region_error end
    FindClearSpaceForUnit(state.builder,point,true)
    local distance=(state.builder:GetAbsOrigin()-point):Length2D()
    state.prep_builder_teleports=(state.prep_builder_teleports or 0)+1
    line('prep_builder_teleport player='..state.id..' reason='..reason..' distance_to_work='..string.format('%.1f',distance)..' normal_build_queue=1')
    return distance<=16,distance>16 and 'engine_clear_space_displaced_builder' or nil
end
local function build_failure(state,pending,reason)
    state.placement_failures=state.placement_failures or {}
    local entry={building_id=pending.id,reason=reason,elapsed=clock()-pending.at,
        x=pending.point.x,y=pending.point.y,task_constructing=pending.task and pending.task.constructing==true,
        task_timeout_at=pending.task and pending.task.timeout_at,prep_teleport_error=pending.teleport_error,
        work_x=pending.task and pending.task.work_position and pending.task.work_position.x,
        work_y=pending.task and pending.task.work_position and pending.task.work_position.y}
    state.placement_failures[#state.placement_failures+1]=entry
    line('build_retry player='..state.id..' id='..pending.id..' reason='..reason..' x='..entry.x..' y='..entry.y..' registered_replacement=0')
    state.pending=nil
    local maximum=state.placement_retries or 8
    assert(#state.placement_failures<=maximum,'Preparation construction retry limit reached: '..reason)
end
local function ensure_build(state,id,index,position_index)
    index=index or 1
    local listed=buildings(state,id)
    if id=='wall' and state.units.wall then
        for _,unit in ipairs(listed) do if unit==state.units.wall then return unit end end
    end
    if listed[index] then state.units[id]=listed[index];return listed[index] end
    local builder = state.builder
    local task=builder.survival_build_task
    if state.pending then
        local pending=state.pending
        if task then
            assert(clock()<(tonumber(task.timeout_at) or pending.at+60)+5,'Production construction task exceeded its own timeout')
            return nil
        end
        if pending.task and not pending.task.constructing then
            build_failure(state,pending,'moving_task_cleared_before_construction');return nil
        end
        pending.handoff_at=pending.handoff_at or clock()
        local grace=(require('config/buildings_config')[id].build_time or 3)+3
        if clock()-pending.handoff_at<grace then return nil end
        build_failure(state,pending,'construction_handoff_without_registered_building');return nil
    end
    if task then return nil end
    if not state.candidates then
        state.candidates=candidate_list(state,id,position_index or index);state.candidate_index=1
    end
    for _=1,8 do
        local candidate=state.candidates[state.candidate_index];state.candidate_index=state.candidate_index+1
        assert(candidate,'No reachable legal construction cell for '..id..' player='..state.id..' reason='..tostring(state.last_placement_error))
        local allowed,reason=legal_region(state,candidate.point)
        if allowed and id=='arrow_tower' then allowed,reason=legal_tower_position(state,candidate.point) end
        local check=allowed and request('BUILD_CAN_PLACE_REQUEST',{player_id=state.id,caster=builder,building_id=id,position=candidate.point}) or {ok=false,error=reason}
        if check and check.ok then
            local point=check.grid.world_position
            if id=='arrow_tower' then allowed,reason=legal_tower_position(state,point) end
            local definition=require('config/buildings_config')[id]
            local _,inward=interior(state);inward=inward or state.direction*-1
            local footprint=definition.footprint or {x=2,y=2}
            local hull=builder.GetHullRadius and builder:GetHullRadius() or 32
            if allowed then allowed,reason=prep_teleport(state,point+inward*(math.max(footprint.x,footprint.y)*32+hull+16),'near_candidate') end
            local result=allowed and request('BUILD_REQUEST',{player_id=state.id,caster=builder,building_id=id,position=point}) or {ok=false,error=reason}
            if result and result.ok then
                local accepted=builder.survival_build_task
                state.pending={id=id,at=clock(),point=point,task=accepted}
                if accepted and accepted.work_position then
                    local moved,error_code=prep_teleport(state,accepted.work_position,'production_work_position')
                    if not moved then state.pending.teleport_error=error_code;line('prep_work_position_rejected player='..state.id..' reason='..tostring(error_code)) end
                end
                line('build_queued player='..state.id..' id='..id..' index='..index)
                return nil
            end
            state.last_placement_error=result and result.error or 'build_request_missing_response'
        else
            state.last_placement_error=check and check.error or 'placement_missing_response'
        end
    end
    return nil
end
local function tower_target(index,options)
    local target
    for route_index,row in ipairs(require('config/tower_route_config').get_route('class_'..index)) do
        if row.rarity=='SR' and row.level==options.sr_stage_level then target=route_index+5;break end
    end
    assert(target and target>5,'SR stage '..options.sr_stage_level..' target missing for class_'..index)
    return options.tower_level and math.max(target,options.tower_level) or target
end
local function ensure_route_tower(state,index,target)
    -- Existing user construction can be in any order. Reuse the matching
    -- formal route, then an unclassified tower; never switch another route.
    local listed=buildings(state,'arrow_tower')
    for _,unit in ipairs(listed) do
        if unit.survival_tower_class=='class_'..index and (tonumber(unit.survival_level) or 1)<=target then return unit end
    end
    for _,unit in ipairs(listed) do if not unit.survival_tower_class then return unit end end
    return ensure_build(state,'arrow_tower',#listed+1,index)
end
local function ensure_tower_position(state,unit,index)
    local range=require('config/tower_combat_rules').current_attack_range(unit)
    if legal_tower_position(state,unit:GetAbsOrigin(),range) then state.relocation=nil;return true end
    if require('systems/building_upgrade_process').is_active(unit) then return false end
    if not state.relocation or state.relocation.unit~=unit then
        state.relocation={unit=unit,candidates=candidate_list(state,'arrow_tower',index),index=1}
    end
    local relocation=state.relocation
    local service=require('systems/tower_relocation_service')
    for _=1,8 do
        local candidate=relocation.candidates[relocation.index]
        assert(candidate,'Existing route cannot move into wall interior through its normal blink: '..tostring(state.last_placement_error))
        local allowed,reason=legal_tower_position(state,candidate.point,range)
        if allowed then
            local grid=service.validate(state.id,unit:entindex(),candidate.point,nil,false)
            if grid and grid.ok then allowed,reason=legal_tower_position(state,grid.world_position,range)
            else allowed,reason=false,grid and grid.error or 'tower_relocation_missing_validation' end
            local result=allowed and service.move(state.id,unit:entindex(),grid.world_position,nil,false) or {ok=false,error=reason}
            if result and result.ok then
                state.tower_relocations=(state.tower_relocations or 0)+1
                line('tower_relocated player='..state.id..' class='..tostring(unit.survival_tower_class)..' entindex='..unit:entindex()..' normal_blink=1')
                state.relocation=nil
                return legal_tower_position(state,unit:GetAbsOrigin(),range)
            end
            reason=result and result.error or 'tower_relocation_missing_response'
            if reason=='move_ability_cooldown' then return false end
        end
        state.last_placement_error=reason
        relocation.index=relocation.index+1
    end
    return false
end
local function ensure_level(state,unit,level)
    if (tonumber(unit.survival_level) or 1)>=level then return true end
    if require('systems/building_upgrade_process').is_active(unit) then return false end
    local result=request('BUILDING_UPGRADE_REQUEST',{player_id=state.id,building=unit,upgrade_mode='one',silent_notification=true})
    assert(result and result.ok,'Upgrade failed player='..state.id..' error='..tostring(result and result.error))
    return false
end
local function clear_build(state) state.pending=nil;state.candidates=nil end
local function grant_currency(state,options)
    local wallet=request('RESOURCE_GET_REQUEST',{player_id=state.id}) or {}
    local floor=tonumber(options.currency_floor) or 1000000000
    if (tonumber(wallet.wood) or 0)<floor/2 or (tonumber(wallet.gold) or 0)<floor/2 then
        local result=request('RESOURCE_ADD_REQUEST',{player_id=state.id,wood=math.max(0,floor-(wallet.wood or 0)),
            gold=math.max(0,floor-(wallet.gold or 0)),reason='tools_real_stress_match_currency'})
        assert(result and result.ok,'Match wallet unavailable: '..tostring(result and result.error))
    end
end
local function validate_hero_scene(scene)
    tools()
    assert(current_scene()==scene and scene.status=='preparing' and current_guard()==scene.hero_guard,
        'Hero preparation requires its current write-isolated scene')
    local match=require('systems/match_setup_service')
    assert(match.get_mode()==scene.hero_match_mode and match.get_session_id()==scene.hero_session_id,
        'Hero preparation match/session changed')
    local context=require('systems/player_context_service')
    for _,state in ipairs(scene.players) do
        local current=request('BUILDER_GET_REQUEST',{player_id=state.id})
        local native_owner=valid(state.builder) and state.builder:GetPlayerOwnerID()
        assert(owner(state.id) and require('systems/startup_loading_service').is_player_ready(state.id)
            and current and current.ok and current.builder==state.builder
            and valid(state.builder) and context.is_owned_by(state.id,state.builder)
            and (native_owner==state.id or native_owner==-1),'Hero preparation owner/builder unavailable')
    end
    return context
end
local function enter_research(state)
    state.phase='research';state.research_index=1
end
-- Explicit Tools refresh for an existing scene; no private skill/progression
-- fields are modified. Native ability level 1 is a locked placeholder, so only
-- the formal skill snapshot can prove that a reward was actually claimed.
function M.refresh_simulated_hero_skills(options)
    tools();options=options or {};assert(options.enabled==true,'Explicit simulated skill refresh required')
    local scene=assert(current_scene(),'Current test scene required')
    assert(scene.status=='ready' or scene.status=='preparing','Active test scene required')
    local guard=assert(current_guard(),'Current write isolation required')
    assert(scene.hero_guard==guard,'Scene write-isolation guard changed')
    local match=require('systems/match_setup_service')
    assert(match.get_mode()==scene.hero_match_mode and match.get_session_id()==scene.hero_session_id,'Scene match/session changed')
    local generation=bus().get_generation()
    assert(scene.hero_bus_generation==generation or scene.hero_bus_generation==nil and options.allow_legacy_scene==true,
        'Scene bus generation missing/changed; legacy refresh must be explicit')
    local id=tonumber(options.player_id)
    assert(id and id==math.floor(id) and id>=0 and owner(id),'Valid current scene player required')
    local selected
    for _,state in ipairs(scene.players) do if state.id==id then selected=state end end
    assert(selected and selected.desired_hero_id,'Selected scene owner has no combat hero; wall-only refresh rejected')
    local expected=(guard.four_live_profiles or {})[id] or (guard.bots or {})[id]
    assert(expected and expected.save and expected.save.gameplay_stats,'In-memory profile overlay required')
    local profiles=require('systems/player_profile_service');local profile=profiles.get_profile(id)
    assert(profile and profile.account_id==expected.account_id and profile.revision==expected.revision,
        'Profile overlay fell through to another account')
    for field,value in pairs(expected.save.gameplay_stats) do
        assert(profile.save and profile.save.gameplay_stats and profile.save.gameplay_stats[field]==value,'Profile gameplay baseline changed')
    end
    local summoned=request('HERO_SUMMON_GET_REQUEST',{player_id=id})
    local context=require('systems/player_context_service')
    assert(summoned and summoned.ok and summoned.hero_id==selected.desired_hero_id and valid(summoned.unit)
        and summoned.unit==selected.combat_hero and context.is_owned_by(id,summoned.unit)
        and summoned.unit:GetPlayerOwnerID()==id,'Current formal combat hero changed')
    local progression=request('HERO_PROGRESSION_GET_REQUEST',{player_id=id})
    local rank=progression and progression.ok and progression.snapshot and tonumber(progression.snapshot.rebirth_level)
    assert(rank and rank==math.floor(rank) and rank>=0 and rank<math.huge,'Formal hero rank unavailable')
    local target=options.rebirth_level~=nil and options.rebirth_level or rank
    assert(type(target)=='number' and target==math.floor(target) and target>=0 and target<=10,'Simulated skill target must be 0..10')
    if rank<target then return {ok=false,error='formal_rebirth_prerequisite_not_met',player_id=id,rebirth_level=rank,target=target} end
    local skill=request('HERO_SKILL_STATE_GET_REQUEST',{player_id=id})
    assert(skill and skill.ok and skill.snapshot,'Formal skill interface missing')
    if skill.snapshot.hero_ready~=1 then return {ok=false,waiting=true,error='formal_hero_skills_initializing'} end
    assert(skill.snapshot.hero_id==summoned.hero_id and skill.snapshot.unit_entindex==summoned.unit:entindex(),
        'Formal skill snapshot belongs to another hero')
    if scene.hero_bus_generation==nil then scene.hero_bus_generation=generation end
    if options.refresh_profile~=false then
        bus().emit(events().PLAYER_PROFILE_CHANGED,{player_id=id,reason='tools_simulated_rebirth_skill_refresh'})
    end
    local by_id={};for _,row in ipairs(skill.snapshot.skills or {}) do by_id[row.skill_id]=row end
    local definitions=require('config/generated/hero_definitions').by_id
    local group=assert(definitions[summoned.hero_id],'Configured hero required').exclusive_skill_group_id or ''
    local granted,eligible={},{}
    for _,row in ipairs(require('config/generated/hero_exclusive_skills').rows or {}) do
        if row.enabled~=false and row.guaranteed==true and row.hero_id==summoned.hero_id
            and (group=='' or row.exclusive_group_id==group) and target>=(tonumber(row.unlock_rebirth_level) or 1) then
            eligible[#eligible+1]=row.skill_id
            local item=by_id[row.skill_id]
            assert(item,'Configured exclusive missing from formal skill layout')
            local level=tonumber(item.level) or 0
            assert(level==0 or item.locked~=1,'Formal skill has inconsistent owned/locked state')
            if level==0 then
                -- Same public grant API used by choice_service.grant_exclusive;
                -- eligibility was checked above against the actual rank and CSV.
                local result=request('HERO_SKILL_GRANT_REQUEST',{player_id=id,skill_id=row.skill_id,
                    levels=tonumber(row.initial_level) or 1,source='tools_simulated_rebirth_exclusive'})
                assert(result and result.ok,'Formal exclusive skill reward failed: '..row.skill_id)
                granted[#granted+1]=row.skill_id
            end
        end
    end
    local actual=request('HERO_SKILL_STATE_GET_REQUEST',{player_id=id})
    assert(actual and actual.ok and actual.snapshot and actual.snapshot.unit_entindex==summoned.unit:entindex(),'Formal skill refresh lost current hero')
    local after={};for _,row in ipairs(actual.snapshot.skills or {}) do after[row.skill_id]=row end
    for _,skill_id in ipairs(eligible) do local row=after[skill_id]
        assert(row and (tonumber(row.level) or 0)>0 and row.locked==0,'Exclusive did not unlock through formal service: '..skill_id)
    end
    selected.rebirth_level=rank
    selected.simulated_exclusive_skills={target=target,rank=rank,granted=copy(granted),eligible=copy(eligible),
        profile_map_level=profile.save.gameplay_stats.map_level,game_time=clock(),public_grant_verified=true}
    return {ok=true,player_id=id,hero_id=summoned.hero_id,rebirth_level=rank,target=target,granted=granted,
        eligible=eligible,skills=copy(actual.snapshot.skills),map_level=profile.save.gameplay_stats.map_level,
        memory_only=true,persistent_write=false,boss_completed=false,attribute_rewards=false}
end
local function step_hero(state,scene)
    local context=validate_hero_scene(scene)
    if state.phase=='hero_altar' then
        local altar=ensure_build(state,'hero_altar');if not altar then return end
        local registered=request('BUILDING_QUERY_REQUEST',{entindex=altar:entindex(),read_only=true})
        assert(registered and registered.unit==altar and registered.building_id=='hero_altar'
            and tonumber(registered.player_id)==state.id and context.is_owned_by(state.id,altar)
            and (altar:GetPlayerOwnerID()==state.id or altar:GetPlayerOwnerID()==-1),'Formal owned hero altar required')
        clear_build(state);state.phase='hero_summon'
    elseif state.phase=='hero_summon' then
        local existing=request('HERO_SUMMON_GET_REQUEST',{player_id=state.id})
        if existing and existing.ok then
            assert(valid(existing.unit) and context.is_owned_by(state.id,existing.unit)
                and existing.unit:GetPlayerOwnerID()==state.id,'Formal summoned hero ownership invalid')
            assert(existing.hero_id==state.desired_hero_id,'Existing summoned hero conflicts with requested hero')
            state.combat_hero,state.combat_hero_id=existing.unit,existing.hero_id
            if scene.options.simulated_rebirth_level~=nil then state.phase='simulated_rebirth' else enter_research(state) end
            return
        end
        if state.summon_result then assert(state.summon_result.ok,'Hero summon completion failed: '..tostring(state.summon_result.error)) end
        if state.summon_requested_at then
            assert(clock()-state.summon_requested_at<=120,'Normal hero summon did not register within 120 seconds')
            return
        end
        state.summon_requested_at=clock()
        local result=request('HERO_SUMMON_REQUEST',{player_id=state.id,hero_id=state.desired_hero_id,source='altar_ability',
            on_completed=function(final_result)
                if current_scene()==scene and scene.status=='preparing' then state.summon_result=final_result end
            end})
        assert(result and result.ok,'Normal hero summon failed: '..tostring(result and result.error))
    elseif state.phase=='simulated_rebirth' then
        if state.desired_hero_id then
            local existing=request('HERO_SUMMON_GET_REQUEST',{player_id=state.id})
            assert(existing and existing.ok and existing.unit==state.combat_hero and valid(existing.unit)
                and context.is_owned_by(state.id,existing.unit) and existing.unit:GetPlayerOwnerID()==state.id
                and existing.hero_id==state.desired_hero_id,'Summoned hero changed before simulated rank')
        end
        local progression=request('HERO_PROGRESSION_GET_REQUEST',{player_id=state.id})
        local rank=progression and progression.snapshot and tonumber(progression.snapshot.rebirth_level)
        assert(rank and rank>=0,'Formal hero progression snapshot required')
        state.rebirth_level=rank
        if rank>=scene.options.simulated_rebirth_level then
            if scene.options.simulate_exclusive_skill_rewards==true and state.desired_hero_id then
                local skills=M.refresh_simulated_hero_skills({enabled=true,player_id=state.id,
                    rebirth_level=scene.options.simulated_rebirth_level,refresh_profile=false})
                if skills.waiting then return end
                assert(skills.ok,'Formal simulated exclusives failed')
            end
            enter_research(state);return
        end
        assert(not state.simulated_rank_requested,'Simulated rank reward did not update formal progression')
        state.simulated_rank_requested=true
        local result=request('HERO_PROGRESSION_APPLY_REQUEST',{player_id=state.id,
            effects={{effect_type='set_rebirth_level',value=scene.options.simulated_rebirth_level}},
            reason='tools_stress_simulated_rebirth_prerequisite'})
        assert(result and result.ok,'Simulated rank request failed: '..tostring(result and result.error))
        line('owner='..state.id..' rebirth_rank=Tools_simulated target='..scene.options.simulated_rebirth_level
            ..' boss_completed=false attribute_rewards=false skill_rewards=false')
    end
end
local function step_player(state,scene)
    assert(owner(state.id) and valid(state.builder),'Stress player/builder became unavailable')
    grant_currency(state,scene.options)
    local phase=state.phase
    if phase=='city' then
        local unit=ensure_build(state,'main_city');if not unit then return end;clear_build(state)
        if ensure_level(state,unit,5) then state.phase='wall' end
    elseif phase=='wall' then
        local unit=ensure_build(state,'wall');if not unit then return end;clear_build(state)
        if ensure_level(state,unit,scene.options.wall_level or 1) then state.phase='farm' end
    elseif phase=='farm' then
        local unit=ensure_build(state,'building_farm');if not unit then return end;clear_build(state)
        if ensure_level(state,unit,5) then state.phase='population';state.population_trains=0 end
    elseif phase=='population' then
        -- The real farm progression is team-wide. Do not simulate an independent
        -- quota for each owner: subsequent players report the shared maximum.
        -- Wait for all real farms so one early player cannot consume the shared
        -- training quotas before the other owners can earn their normal capacity.
        for _,other in ipairs(scene.players) do
            if other.phase=='city' or other.phase=='wall' or other.phase=='farm' then return end
        end
        local result=request('WORKER_TRAIN_REQUEST',{player_id=state.id,city=state.units.building_farm,training_id='train_population_auto'})
        state.population_result=result
        if result and result.ok then state.population_trains=state.population_trains+1
        elseif result and result.error=='人口训练已完成' then state.phase='labs';state.lab_index=1
        else error('Population training failed: '..tostring(result and result.error)) end
    elseif phase=='labs' then
        local ids={'building_research_lab','building_advanced_research_lab'}
        if ensure_build(state,ids[state.lab_index]) then
            clear_build(state);state.lab_index=state.lab_index+1
            if state.lab_index>2 then state.phase='towers';state.tower_index=1 end
        end
    elseif phase=='towers' then
        local index=state.tower_index
        local target=tower_target(index,scene.options)
        local unit=ensure_route_tower(state,index,target);if not unit then return end;clear_build(state)
        local class_id='class_'..index
        if not unit.survival_tower_class then
            if not ensure_level(state,unit,5) then return end
            if require('systems/building_upgrade_process').is_active(unit) then return end
            local result=request('TOWER_CLASS_REQUEST',{player_id=state.id,tower=unit,class_index=index})
            assert(result and result.ok,'Tower class failed: '..tostring(result and result.error));return
        end
        assert(unit.survival_tower_class==class_id,'Existing tower order conflicts with seven-route fixture')
        if ensure_level(state,unit,target) then
            if not ensure_tower_position(state,unit,index) then return end
            state.towers[index]=unit;state.tower_index=index+1
            if state.tower_index>7 then state.phase='workers' end
        end
    elseif phase=='workers' then
        local progress=request('WORKER_TRAINING_GET_REQUEST',{player_id=state.id,source_entindex=state.units.main_city:entindex()}) or {}
        if (progress.queue_count or 0)>0 then return end
        for _,option in ipairs(progress.options or {}) do
            local target=option.max_count>=0 and option.max_count or math.max(3,scene.options.ordinary_lv8 or 3)
            if option.max_count<0 and scene.options.fill_lv8 then
                local wallet=request('RESOURCE_GET_REQUEST',{player_id=state.id})
                target=option.count+math.floor(math.max(0,wallet.max_population-wallet.population)/math.max(1,option.population_cost))
            end
            if option.count<target then
                local result=request('WORKER_TRAIN_REQUEST',{player_id=state.id,city=state.units.main_city,training_id=option.training_id})
                assert(result and result.ok,'Worker training failed: '..tostring(result and result.error));return
            end
        end
        if state.desired_hero_id then state.phase='hero_altar'
        elseif scene.options.simulated_rebirth_level~=nil then state.phase='simulated_rebirth'
        else enter_research(state) end
    elseif phase=='hero_altar' or phase=='hero_summon' or phase=='simulated_rebirth' then
        step_hero(state,scene)
    elseif phase=='research' then
        local definitions=require('config/research_technology_config').technologies
        local definition=definitions[state.research_index]
        if not definition then state.phase='ready';return end
        local snapshot=request('RESEARCH_STATE_GET_REQUEST',{player_id=state.id}) or {}
        local current=tonumber((snapshot.levels or {})[definition.tech_id]) or 0
        local target=scene.options.research_levels and math.min(definition.max_level,scene.options.research_levels) or definition.max_level
        if current>=target then state.research_index=state.research_index+1;state.research_pending=nil;return end
        local prerequisite=definition.prerequisite or {}
        local hero=request('HERO_PROGRESSION_GET_REQUEST',{player_id=state.id}) or {}
        if (tonumber(hero.snapshot and hero.snapshot.rebirth_level) or 0)<(prerequisite.reincarnation_level or 0) then
            state.skipped_research[definition.tech_id]='normal_rebirth_prerequisite';state.research_index=state.research_index+1;return
        end
        if prerequisite.tech_id and (tonumber((snapshot.levels or {})[prerequisite.tech_id]) or 0)<prerequisite.required_level then
            state.skipped_research[definition.tech_id]='normal_technology_prerequisite';state.research_index=state.research_index+1;return
        end
        if state.research_pending and current>state.research_pending.old_level then state.research_pending=nil end
        if state.research_pending then
            if clock()-state.research_pending.at>30 then error('Normal research did not complete: '..definition.tech_id) end
            return
        end
        local lab=definition.building_id=='advanced_research_lab' and state.units.building_advanced_research_lab or state.units.building_research_lab
        local result=request('TECHNOLOGY_PURCHASE_NEXT_REQUEST',{player_id=state.id,technology_group=definition.legacy_group,
            source_entindex=lab:entindex(),source='research_lab_ability',request_id='real_stress:'..state.id..':'..definition.tech_id..':'..current})
        assert(result and result.ok,'Research enqueue failed: '..tostring(result and result.error))
        state.research_pending={at=clock(),old_level=current}
    end
end

function M.status()
    local scene=current_scene()
    if not scene then line('status=not_started');return nil end
    local result={status=scene.status,error=scene.error,elapsed=clock()-scene.started,owners={},network_clients_claimed=false,
        tower_tier=scene.options.tower_level and 'explicit_higher_tier_stress' or 'SR',fill_lv8=scene.options.fill_lv8==true,
        sr_stage_level=scene.options.sr_stage_level or 5,attack_hold=scene.attack_hold~=nil,
        attack_hold_towers=scene.attack_hold and #scene.attack_hold or 0,
        attack_hold_used=scene.attack_hold_used==true,
        wave_scenario=scene.attack_hold and 'backlogged_wave_boundary' or scene.wave_scenario or 'ordinary_monster15'}
    for _,state in ipairs(scene.players) do
        local worker_counts={}
        for _,entry in ipairs(request('WORKER_LIST_REQUEST',{player_id=state.id}) or {}) do
            if valid(entry.unit) and entry.worker_type=='lumberjack' then
                local level=tonumber(entry.unit.survival_lumberjack_level) or 0
                worker_counts[level]=(worker_counts[level] or 0)+1
            end
        end
        local tower_details={}
        for _,unit in ipairs(state.towers) do
            local position=unit:GetAbsOrigin()
            local actual_range=require('config/tower_combat_rules').current_attack_range(unit)
            local inside,reason=legal_tower_position(state,position,actual_range)
            tower_details[#tower_details+1]={entindex=unit:entindex(),class_id=unit.survival_tower_class,level=unit.survival_level,
                x=position.x,y=position.y,attack_range=actual_range,inside_wall_and_in_range=inside,placement_error=reason}
        end
        local total_towers=#buildings(state,'arrow_tower')
        local formal_spawn=state.formal_spawn or state.base
        local wall=state.units.wall
        local wall_floor=scene.wall_survival and scene.wall_survival[wall]
        result.owners[#result.owners+1]={player_id=state.id,slot=state.slot.slot_id,phase=state.phase,simulated_bot=current_guard().bots[state.id]~=nil,
            builder=state.builder:entindex(),towers=#state.towers,total_owned_towers=total_towers,tower_details=tower_details,
            extra_owned_towers=math.max(0,total_towers-7),workers=worker_counts,skipped_research=copy(state.skipped_research),
            population_trains=state.population_trains,population_result=state.population_result,
            prep_builder_teleports=state.prep_builder_teleports or 0,tower_relocations=state.tower_relocations or 0,
            placement_failures=copy(state.placement_failures or {}),last_placement_error=state.last_placement_error,
            wallet=request('RESOURCE_GET_REQUEST',{player_id=state.id}),research=request('RESEARCH_STATE_GET_REQUEST',{player_id=state.id}),
            wall_armor=state.units.wall and state.units.wall.survival_effective_war3_armor,opening_reward=state.opening_reward,
            wall_health=wall and wall.GetHealth and wall:GetHealth(),wall_max_health=wall and wall.GetMaxHealth and wall:GetMaxHealth(),
            wall_min_health=wall_floor and not wall_floor:IsNull() and wall_floor:GetMinHealth() or 0,
            requested_hero_id=state.desired_hero_id,hero_id=state.combat_hero_id,
            hero_entindex=valid(state.combat_hero) and state.combat_hero:entindex() or nil,
            simulated_rebirth_target=scene.options.simulated_rebirth_level,rebirth_level=state.rebirth_level,
            simulated_rank_applied=state.simulated_rank_requested,
            simulated_exclusive_skills=copy(state.simulated_exclusive_skills),
            court_source=state.court and state.court.source or 'formal_builder_spawn',
            court_position={x=state.base.x,y=state.base.y},
            formal_builder_spawn={x=formal_spawn.x,y=formal_spawn.y}}
        local counts={};for level=1,8 do counts[#counts+1]=level..':'..(worker_counts[level] or 0) end
        line('owner='..state.id..' slot='..state.slot.slot_id..' phase='..state.phase..' towers='..#state.towers
            ..' total_owned_towers='..total_towers..' population_trains='..(state.population_trains or 0)
            ..' ordinary_workers='..table.concat(counts,',')..' elapsed='..string.format('%.1f',result.elapsed))
    end
    local guard=current_guard();result.blocked_http=guard.blocked_http;result.blocked_saves=guard.blocked_saves
    result.forced_wall_refreshes=guard.forced_wall_refreshes or 0
    return result
end

function M.prepare(options)
    tools();options=copy(options or {})
    options.sr_stage_level=options.sr_stage_level or 5
    assert(type(options.sr_stage_level)=='number' and options.sr_stage_level==math.floor(options.sr_stage_level)
        and options.sr_stage_level>=1 and options.sr_stage_level<=5,'sr_stage_level must be an integer from 1 to 5')
    assert(GameRules:State_Get()==DOTA_GAMERULES_STATE_GAME_IN_PROGRESS,'Running match required')
    assert(not current_scene() or current_scene().status~='preparing','Fixture already preparing')
    M.isolate_writes()
    local ids=options.player_ids or {0};assert(#ids==1 or #ids==4,'Choose one owner or four real owners')
    if options.simulated_rebirth_level~=nil then
        local rank=options.simulated_rebirth_level
        assert(type(rank)=='number' and rank==math.floor(rank) and rank>=0 and rank<=10,
            'simulated_rebirth_level must be an integer from 0 to 10; no Boss rewards are simulated')
    end
    if options.simulate_exclusive_skill_rewards~=nil then
        assert(type(options.simulate_exclusive_skill_rewards)=='boolean','simulate_exclusive_skill_rewards must be boolean')
    end
    if options.hero_ids~=nil then
        assert(type(options.hero_ids)=='table','hero_ids must map selected player IDs to configured hero IDs')
        local definitions=require('config/generated/hero_definitions').by_id
        for id,hero_id in pairs(options.hero_ids) do
            local selected=false;for _,candidate in ipairs(ids) do if candidate==id then selected=true end end
            assert(selected and type(hero_id)=='string' and definitions[hero_id] and definitions[hero_id].enabled~=false,
                'hero_ids requires selected owners and enabled configured hero IDs')
        end
    end
    if options.simulate_bot_profiles then M.admit_bots(ids) end
    local context=require('systems/player_context_service')
    local scene={options=options,status='preparing',started=clock(),mode=GameRules:GetGameModeEntity(),players={}}
    if options.hero_ids or options.simulated_rebirth_level~=nil then
        local match=require('systems/match_setup_service')
        scene.hero_guard=current_guard();scene.hero_match_mode=match.get_mode();scene.hero_session_id=match.get_session_id()
        scene.hero_bus_generation=bus().get_generation()
    end
    local seen,positions={},{}
    local regions,courts={},{}
    for id=0,context.max_players()-1 do
        local region=context.resolve_builder_spawn(id)
        if region then regions[id]=region.position end
        local override=options.region_court_positions and options.region_court_positions[id]
        if override then
            local city=court_point(override.city,'Court city '..id)
            local wall=court_point(override.wall,'Court wall '..id)
            assert((city-wall):Length2D()>64,'Court city and wall must define a safe interior')
            courts[id]={city=city,wall=wall,position=court_point(override.position or override.city,'Court center '..id),
                source=override.source or 'explicit_tools_court_override'}
            regions[id]=courts[id].position
        end
    end
    for _,id in ipairs(ids) do
        assert(type(id)=='number' and id==math.floor(id) and id>=0 and id<context.max_players() and not seen[id], 'Distinct configured player IDs required')
        seen[id]=true
        assert(owner(id) and require('systems/startup_loading_service').is_player_ready(id),'Player is not ready; real bot simulation must be explicit')
        local spawn=assert(context.resolve_builder_spawn(id),'Configured builder region marker required')
        if options.region_court_positions then assert(courts[id],'Court override missing for selected owner '..id) end
        local slot=assert(context.slot(id));local marker=assert(Entities:FindByName(nil,slot.wave_spawn_marker),'Configured wave marker missing')
        local registered=request('BUILDER_GET_REQUEST',{player_id=id})
        assert(registered and registered.ok and valid(registered.builder) and context.is_owned_by(id,registered.builder),'Formal owned builder required')
        local base=regions[id]
        for _,position in ipairs(positions) do assert((base-position):Length2D()>1280,'Player regions overlap; cannot label four-region simulation') end
        positions[#positions+1]=base
        local delta=courts[id] and (courts[id].wall-courts[id].city) or (marker:GetAbsOrigin()-spawn.position)
        local direction=Vector(delta.x,delta.y,0):Normalized()
        scene.players[#scene.players+1]={id=id,slot=slot,builder=registered.builder,base=base,direction=direction,
            perpendicular=Vector(-direction.y,direction.x,0),units={},towers={},phase='city',skipped_research={},
            court=courts[id],formal_spawn=spawn.position,
            desired_hero_id=options.hero_ids and options.hero_ids[id],
            regions=regions,placement_retries=options.placement_retries or 8,
            opening_reward=M.select_opening_reward(id)}
    end
    local previous=_G[KEY]
    local guard=current_guard()
    local old_owners={}
    if previous and previous.mode==scene.mode then
        for _,state in ipairs(previous.players) do old_owners[state.id]=state end
    end
    scene.wall_survival={}
    for _,state in ipairs(scene.players) do
        local old=old_owners[state.id]
        local wall=old and old.units.wall
        if valid(wall) and wall.survival_building_id=='wall' and context.is_owned_by(state.id,wall) then
            local registered=request('BUILDING_QUERY_REQUEST',{entindex=wall:entindex(),read_only=true})
            if registered and registered.unit==wall and registered.building_id=='wall'
                and tonumber(registered.player_id)==state.id then
                state.units.wall=wall
                local modifier=previous.wall_survival and previous.wall_survival[wall]
                if modifier and not modifier:IsNull() and modifier:GetParent()==wall
                    and wall:FindModifierByName(WALL_MODIFIER)==modifier then
                    scene.wall_survival[wall]=modifier
                end
            end
        end
    end
    release_attack_hold(previous)
    -- Commit validated ownership using only Lua field writes before invoking
    -- any engine/modifier callbacks. HP-1 walls retain their exact floor handle
    -- across the scene switch; no preparation tick or construction phase waits.
    _G[KEY]=scene
    guard.wall_targets={}
    for _,state in ipairs(scene.players) do
        local wall=state.units.wall
        if wall then
            guard.wall_targets[wall]=scene
            local modifier=scene.wall_survival[wall]
            if modifier then
                modifier.scene,modifier.guard=scene,guard
                previous.wall_survival[wall]=nil
            end
        end
    end
    release_wall_survival(previous)
    require('systems/wave_system').set_dev_mode(true)
    -- Clamp the production projection for actual owned walls, including later
    -- star/growth/research refreshes after preparation has stopped scheduling.
    M.protect_walls()
    -- A stopped/older scene can retain registered walls without the old clamp.
    -- Restore their projection now as well, before any preparation timer runs.
    local target=require('systems/war3_armor_target')
    for _,state in ipairs(scene.players) do
        if state.units.wall then target.apply(state.units.wall,100000,0) end
    end
    require('core/scheduler').every(0.2,function()
        if current_scene()~=scene or scene.status~='preparing' then return false end
        if clock()-scene.started>(options.timeout or 3600) then scene.status='failed';scene.error='preparation_timeout';M.status();return false end
        local ready=true
        for _,state in ipairs(scene.players) do
            local ok,err=pcall(step_player,state,scene)
            if not ok then scene.status='failed';scene.error=tostring(err);line('failed='..scene.error);return false end
            if state.units.wall then enroll_wall(guard,scene,state) end
            if state.phase~='ready' then ready=false end
        end
        if ready then scene.status='ready';M.status();line('ready=1 owners='..#scene.players..' wave_not_started=1');return false end
        if not scene.last_report or clock()-scene.last_report>=10 then scene.last_report=clock();M.status() end
        return true
    end,TASK)
    line('preparing owners='..#scene.players..' currency=simulated population=normal_farm workers=ordinary_all_tiers')
    return scene
end
M.start=M.prepare

function M.hold_tower_attacks(on)
    tools();assert(type(on)=='boolean','hold_tower_attacks expects true or false')
    if not on then
        local count=release_attack_hold(_G[KEY])
        line('tower_attack_hold=off restored='..count)
        return true
    end
    local scene=assert(current_scene(),'Current match scene required')
    assert(scene.status=='ready','Tower attack hold requires normal preparation to finish')
    if scene.attack_hold then return true end
    local records,seen={},{}
    for _,state in ipairs(scene.players) do
        assert(#state.towers==7,'Hold requires exactly seven selected route towers per owner')
        for index,unit in ipairs(state.towers) do
            assert(valid(unit),'Selected tower unavailable')
            local registered=request('BUILDING_QUERY_REQUEST',{entindex=unit:entindex(),read_only=true})
            assert(registered and registered.unit==unit and registered.building_id=='arrow_tower'
                and tonumber(registered.player_id)==state.id and unit.survival_tower_class=='class_'..index
                and require('systems/player_context_service').is_owned_by(state.id,unit)
                and not seen[unit],'Hold requires distinct actual registered route towers')
            assert(not require('systems/building_upgrade_process').is_active(unit),'Wait for tower upgrades before holding attacks')
            assert(unit.GetAttackCapability and unit.SetAttackCapability and unit.AddNewModifier,'Native tower attack/modifier API required')
            local capability=unit:GetAttackCapability()
            assert(type(capability)=='number','Native tower attack capability unavailable')
            seen[unit]=true
            records[#records+1]={unit=unit,capability=capability}
        end
    end
    -- Validate every region first; register/load this Tools-only modifier only
    -- when explicitly holding. Its independent disarm survives the tower AI's
    -- normal auto-attack unlock and repeated orders without a polling timer.
    LinkLuaModifier(HOLD_MODIFIER,'tests/modifier_manual_real_game_stress_hold',LUA_MODIFIER_MOTION_NONE)
    require('tests/modifier_manual_real_game_stress_hold')
    scene.attack_hold=records
    local ok,err=pcall(function()
        for _,record in ipairs(records) do
            local unit=record.unit
            record.modifier=unit:AddNewModifier(unit,nil,HOLD_MODIFIER,{original_capability=record.capability})
            assert(record.modifier and not record.modifier:IsNull(),'Tools attack hold modifier unavailable')
            unit:SetAttackCapability(DOTA_UNIT_CAP_NO_ATTACK)
            if unit.SetForceAttackTarget then unit:SetForceAttackTarget(nil) end
            local effects=unit.FindModifierByName and unit:FindModifierByName('modifier_tower_attack_effects')
            if effects and effects.ResetAfterRelocation then effects:ResetAfterRelocation() end
            if unit.Stop then unit:Stop() end
        end
    end)
    if not ok then release_attack_hold(scene);error(err,0) end
    scene.attack_hold_used=true
    line('tower_attack_hold=on towers='..#records..' scenario=backlogged_wave_boundary wave_spawn=normal')
    return true
end

function M.spawn_wave(number)
    tools();local scene=assert(current_scene(),'Prepare fixture first');assert(scene.status=='ready','Wait for normal preparation to finish')
    number=tonumber(number) or 15;assert(number==15,'Baseline is exactly monster15; other waves require a separately named stress scenario')
    scene.wave_scenario=scene.attack_hold and 'backlogged_wave_boundary' or 'ordinary_monster15'
    line('wave='..number..' scenario='..scene.wave_scenario
        ..' sr_stage_level='..(scene.options.sr_stage_level or 5))
    local wave=require('systems/wave_system')
    if #scene.players==1 then return wave.debug_spawn_wave(number) end
    assert(type(wave.debug_spawn_wave_for_players)=='function','Tools multi-player wave entry is required; do not substitute private/challenge monsters')
    local ids={};for _,state in ipairs(scene.players) do ids[#ids+1]=state.id end
    return wave.debug_spawn_wave_for_players(number,ids)
end
function M.stop()
    tools();require('core/scheduler').cancel(TASK)
    release_attack_hold(_G[KEY])
    release_wall_survival(_G[KEY])
    local scene=current_scene();if scene then scene.status='stopped' end
    local guard=current_guard()
    if guard then
        local target=require('systems/war3_armor_target')
        if target.apply==guard.armor_wrapper then target.apply=guard.armor_original end
        guard.armor_wrapper=nil;guard.armor_original=nil;guard.wall_targets={}
    end
    line('stopped fixture_work=1 armor_protection=restored write_isolation=retained restart_map_to_reset_match_assets')
    return scene
end
return M
