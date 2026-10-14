-- Workshop-only, default-off native movement experiment. The wall AI owns a
-- ROOTED-only mode after a stationary native Fired(record)/Landed(record) pair
-- proves a firing
-- position. No movement-capability guess, Stop, attack order or combat change.
local M = {}
local alignment = require("core/team_alignment")
local HOLD_MODE, SAMPLE_LIMIT, PENDING_LIMIT = 6, 32, 16
local bound_world, generation, active_holds = nil, 0, 0
-- Separate, opt-in Tools candidate. Never disable acquisition before native
-- stationary fire is proven. Tokens own only our exact native-unit mutation.
local IDLE_OWNER_LIMIT = 1024
local idle_context, idle_generation, idle_owners, idle_active = nil, 0, {}, 0
local idle_counters, idle_samples, idle_next_sample
local release_reasons = {disabled=true, unit_dead=true, target_changed=true,
    state_changed=true, attack_type_changed=true, move_changed=true,
    team_changed=true, controlled=true, player_controlled=true,
    target_protected=true, not_visible=true, force_target_changed=true,
    attack_target_changed=true, geometry_unavailable=true,
    generation_changed=true, position_changed=true, range_changed=true,
    hull_changed=true, attack_stalled=true, destroyed=true, recovery_order=true,
    external_root=true, unknown_modifier=true, modifier_api_missing=true,
    contact_mode_changed=true, not_formal_ground=true, released=true, other=true}
-- Audited formal-wave modifiers without a CheckState implementation. All
-- other modifiers must expose a readable Lua CheckState; unknown native
-- modifiers reject/release instead of hiding a possible external root.
local SAFE_STATELESS = {modifier_survival_hero_attack_range=true,
    modifier_debug_attack_cap=true, modifier_single_health_bar=true}
local idle_release_reasons={idle_disabled=true,idle_recovery_retry=true,
    idle_ownership_lost=true,idle_generation_changed=true,idle_target_lost=true,
    idle_external_value=true,idle_post_set_stalled=true,idle_set_verification_failed=true,
    getter_missing=true,getter_failed=true,getter_not_boolean=true}
local counters, samples, next_sample
local function reset()
    counters = {entered=0, exited=0, attack_start_held=0, attack_start_free=0,
        attack_fired_held=0, attack_fired_free=0, duplicate_fired=0,
        start_record_present=0, start_record_missing=0,
        fired_record_present=0, fired_record_missing=0,
        landed_record_present=0, landed_record_missing=0,
        attack_landed_held=0, attack_landed_free=0, samples_overwritten=0,
        stationary_pairs=0, pairs_with_record=0, pairs_without_record=0,
        unmatched_landed=0, mismatched_landed_record=0, changed_pair=0,
        pending_overflow=0, pending_geometry_changed=0,
        entry_rejections={}, reasons={}}
    samples, next_sample = {}, 1
    idle_counters = {entered=0, exited=0, admission_checks=0, active_checks=0,
        getter_calls=0, setter_calls=0, set_attempts=0, set_failures=0,
        set_readback_failures=0, original_true=0, original_false=0,
        post_set_fired=0, post_set_landed=0, post_set_pairs=0,
        post_set_record_missing=0, post_set_unmatched_landed=0,
        pre_set_inflight_ignored=0, post_set_pending_overflow=0,
        post_set_stalls=0, aborted_before_entry=0, restore_attempts=0, restore_setter_calls=0,
        restore_getter_calls=0, restore_successes=0, restore_errors=0,
        restore_external_value_preserved=0, restore_invalid_unit=0,
        restore_ownership_lost=0, samples_overwritten=0,
        admission_rejections={}, reasons={}}
    idle_samples, idle_next_sample = {}, 1
end
reset()
local function read(object, name, ...)
    if not object or type(object[name]) ~= "function" then return nil end
    local ok, value = pcall(object[name], object, ...)
    if ok then return value end
end
local function valid(unit) return unit and read(unit,"IsNull") == false end
local function stamp()
    return GameRules and GameRules.GetGameTime and GameRules:GetGameTime() or 0
end
local function current_world()
    return GameRules and GameRules.GetGameModeEntity and GameRules:GetGameModeEntity()
end
local function finite(value)
    value=tonumber(value)
    return value and value==value and math.abs(value)<math.huge and value or nil
end
local function position(unit)
    local p=read(unit,"GetAbsOrigin")
    if not p then return nil end
    local x,y,z=finite(p.x),finite(p.y),finite(p.z)
    if not x or not y or not z then return nil end
    return {x=x,y=y,z=z}
end
local function same_position(a,b)
    return a and b and a.x==b.x and a.y==b.y and a.z==b.z
end
local function range(unit)
    local value=finite(read(unit,"Script_GetAttackRange") or read(unit,"GetAttackRange"))
    return value and value>0 and value or nil
end
local function hull(unit)
    local value=finite(read(unit,"GetHullRadius"))
    return value and value>=0 and value or nil
end
local function attack_grace(unit)
    local rate=finite(read(unit,"GetAttacksPerSecond",false))
    return rate and rate>0 and math.max(3,2/rate+.5) or 3
end
local function own_root(owner)
    return owner and owner.ranged_stationary_hold~=nil and owner.contact_mode==HOLD_MODE
end
function M.owns_root(owner) return own_root(owner) end
local function controlled(owner,parent)
    for _,name in ipairs({"IsStunned","IsCommandRestricted","IsDisarmed",
        "IsCurrentlyHorizontalMotionControlled","IsCurrentlyVerticalMotionControlled"}) do
        if read(parent,name)==true then return true,"controlled" end
    end
    if read(parent,"IsRooted")==true and not own_root(owner) then return true,"external_root" end
    local modifiers=read(parent,"FindAllModifiers")
    if type(modifiers)~="table" or #modifiers>64 then return true,"modifier_api_missing" end
    for _,modifier in pairs(modifiers) do
        if modifier~=owner then
            local name=read(modifier,"GetName")
            if not SAFE_STATELESS[name] then
                if type(modifier.CheckState)~="function" then return true,"unknown_modifier" end
                local ok,states=pcall(modifier.CheckState,modifier)
                if not ok or type(states)~="table" then return true,"unknown_modifier" end
                if states[MODIFIER_STATE_ROOTED]==true then return true,"external_root" end
            end
        end
    end
    return false
end
function M.enabled()
    if _G.SURVIVAL_RANGED_STATIONARY_PROBE~=true
        or not IsInToolsMode or not IsInToolsMode() then return false end
    local world=current_world()
    if not world then return false end
    -- A retained flag cannot opt the next map/VM world into this experiment.
    if not bound_world then bound_world=world;generation=generation+1 end
    return bound_world==world
end
function M.set_probe_enabled(value)
    if not IsServer or not IsServer() or not IsInToolsMode or not IsInToolsMode() then
        return false,"requires Workshop server"
    end
    if value==true and not current_world() then return false,"world unavailable" end
    if value~=true and M.stop_idle_acquire_probe
        and (_G.SURVIVAL_RANGED_IDLE_ACQUIRE_STABLE_PROBE==true or idle_active>0) then
        M.stop_idle_acquire_probe()
    end
    _G.SURVIVAL_RANGED_STATIONARY_PROBE=value==true
    bound_world=value==true and current_world() or nil
    generation=generation+1
    return true
end
function M.reset_counters() reset() end
local function sample_enter(owner,parent,evidence)
    local index=next_sample
    if samples[index] then counters.samples_overwritten=counters.samples_overwritten+1 end
    next_sample=index%SAMPLE_LIMIT+1
    local sample={sequence=counters.entered,unit_index=read(parent,"entindex"),
        wall_index=owner.wall_entindex,entered_at=stamp(),hold_mode=HOLD_MODE,
        proof_start_at=evidence.start_at,proof_fired_at=evidence.start_at,proof_landed_at=evidence.at,
        pair_source="native_fired_record",
        proof_has_record=evidence.has_record,
        bat_before=read(parent,"GetBaseAttackTime",false),rate_before=read(parent,"GetAttacksPerSecond",false),
        attack_start_held=0,attack_fired_held=0,attack_landed_held=0}
    samples[index]=sample
    return sample
end
local function idle_method(object,name)
    if not object then return nil end
    local ok,fn=pcall(function() return object[name] end)
    return ok and type(fn)=="function" and fn or nil
end
local function idle_boolean(parent,restoring)
    local key=restoring and "restore_getter_calls" or "getter_calls"
    idle_counters[key]=idle_counters[key]+1
    local fn=idle_method(parent,"ShouldIdleAcquire")
    if not fn then return nil,"getter_missing" end
    local ok,value=pcall(fn,parent)
    if not ok then return nil,"getter_failed" end
    if type(value)~="boolean" then return nil,"getter_not_boolean" end
    return value
end
local function idle_authority()
    if not IsServer or not IsServer() or not IsInToolsMode or not IsInToolsMode()
        or not GetMapName or GetMapName()~="template_map" then return nil end
    local world=current_world()
    local guard=_G.SURVIVAL_REAL_GAME_STRESS_ISOLATION
    if not world or type(guard)~="table" or guard.mode~=world then return nil end
    local bus=package.loaded["core/event_bus"] or require("core/event_bus")
    if type(bus)~="table" or type(bus.get_generation)~="function" then return nil end
    local ok,bus_generation=pcall(bus.get_generation)
    if not ok or bus_generation==nil then return nil end
    return world,guard,bus,bus_generation
end
function M.idle_acquire_probe_enabled()
    if _G.SURVIVAL_RANGED_IDLE_ACQUIRE_STABLE_PROBE~=true or not M.enabled() then return false end
    local world,guard,bus,bus_generation=idle_authority()
    if not world then return false end
    if not idle_context then
        idle_generation=idle_generation+1
        idle_context={world=world,guard=guard,bus=bus,bus_generation=bus_generation,generation=idle_generation}
    end
    return idle_context.world==world and idle_context.guard==guard
        and idle_context.bus==bus and idle_context.bus_generation==bus_generation
end
local function idle_forget(token)
    if idle_owners[token.owner]==token then
        idle_owners[token.owner]=nil;idle_active=math.max(0,idle_active-1)
    end
    if token.owner.ranged_idle_acquire_hold==token then token.owner.ranged_idle_acquire_hold=nil end
    if token.parent and token.parent.survival_ranged_idle_acquire_owner==token then
        token.parent.survival_ranged_idle_acquire_owner=nil
    end
end
local function idle_owned(token,parent)
    return parent==token.parent and idle_owners[token.owner]==token
        and token.owner.ranged_idle_acquire_hold==token
        and parent.survival_ranged_idle_acquire_owner==token
        and read(token.owner,"GetParent")==parent
end
local function restore_idle(owner,parent,reason)
    local token=idle_owners[owner]
    if not token then return true end
    reason=(release_reasons[reason] or idle_release_reasons[reason]) and reason or "other"
    if not token.released then
        token.released=true
        local key=token.entered and "exited" or "aborted_before_entry"
        idle_counters[key]=idle_counters[key]+1
        idle_counters.reasons[reason]=(idle_counters.reasons[reason] or 0)+1
        token.sample.exited_at=stamp();token.sample.reason=reason
    end
    idle_counters.restore_attempts=idle_counters.restore_attempts+1
    if not IsServer or not IsServer() then
        idle_counters.restore_errors=idle_counters.restore_errors+1
        token.sample.restored=false;token.sample.restore_error="server_unavailable"
        return false
    end
    if not valid(parent) then
        idle_counters.restore_invalid_unit=idle_counters.restore_invalid_unit+1
        idle_counters.restore_errors=idle_counters.restore_errors+1
        token.sample.restored=false;token.sample.restore_error="unit_invalid"
        idle_forget(token);return false
    end
    if not idle_owned(token,parent) then
        idle_counters.restore_ownership_lost=idle_counters.restore_ownership_lost+1
        idle_counters.restore_errors=idle_counters.restore_errors+1
        token.sample.restored=false;token.sample.restore_error="ownership_lost"
        idle_forget(token);return false
    end
    -- Direct native reference plus the token is used even on world/bus exit;
    -- never resolve a recycled entindex in the next world. A changed bool is
    -- external state and already equals the only original value we changed.
    local observed=idle_boolean(parent,true)
    if observed==token.original then
        idle_counters.restore_external_value_preserved=idle_counters.restore_external_value_preserved+1
        idle_counters.restore_successes=idle_counters.restore_successes+1
        token.sample.restored=true;token.sample.restore_wrote=false
        idle_forget(token);return true
    end
    local setter=idle_method(parent,"SetIdleAcquire")
    if not setter then
        idle_counters.restore_errors=idle_counters.restore_errors+1
        token.sample.restored=false;token.sample.restore_error="setter_missing"
        return false -- keep the bounded owned token for explicit stop/retry
    end
    idle_counters.restore_setter_calls=idle_counters.restore_setter_calls+1
    local ok=pcall(setter,parent,token.original)
    local readback,read_error=idle_boolean(parent,true)
    if idle_owned(token,parent) and readback==token.original then
        idle_counters.restore_successes=idle_counters.restore_successes+1
        token.sample.restored=true;token.sample.restore_wrote=true
        if not ok then
            idle_counters.restore_errors=idle_counters.restore_errors+1
            token.sample.restore_error="setter_threw_but_readback_restored"
        end
        idle_forget(token);return true
    end
    if not idle_owned(token,parent) then
        idle_counters.restore_ownership_lost=idle_counters.restore_ownership_lost+1
        idle_counters.restore_errors=idle_counters.restore_errors+1
        token.sample.restored=false;token.sample.restore_error="ownership_lost"
        idle_forget(token);return false
    end
    idle_counters.restore_errors=idle_counters.restore_errors+1
    token.sample.restored=false
    token.sample.restore_error=not ok and "setter_failed" or read_error or "readback_mismatch"
    return false
end
function M.stop_idle_acquire_probe()
    _G.SURVIVAL_RANGED_IDLE_ACQUIRE_STABLE_PROBE=false
    local owners={}
    for owner,token in pairs(idle_owners) do owners[#owners+1]={owner=owner,parent=token.parent} end
    local failures,errors_before=0,idle_counters.restore_errors
    for _,entry in ipairs(owners) do
        M.release(entry.owner,entry.parent,"idle_disabled")
        if idle_owners[entry.owner] then failures=failures+1 end
    end
    idle_context=nil;idle_generation=idle_generation+1
    return failures==0 and idle_counters.restore_errors==errors_before,
        {remaining_owned_mutations=failures,restore_errors=idle_counters.restore_errors-errors_before}
end
function M.set_idle_acquire_probe_enabled(value)
    if value~=true then return M.stop_idle_acquire_probe() end
    if not M.enabled() or not idle_authority() then return false,"requires isolated Workshop v3 world" end
    if idle_active>0 then return false,"restore existing owned mutations first" end
    idle_context=nil
    _G.SURVIVAL_RANGED_IDLE_ACQUIRE_STABLE_PROBE=true
    return M.idle_acquire_probe_enabled()
end
function M.release(owner,parent,reason)
    -- Every v3 exit (including death/recovery/order/world/controls) restores
    -- only our acquisition mutation before relinquishing the ROOTED mode.
    restore_idle(owner,parent,reason or "released")
    local hold=owner.ranged_stationary_hold
    if not hold then return false end
    owner.ranged_stationary_hold=nil
    owner.ranged_stationary_evidence=nil
    owner.ranged_stationary_pending=nil
    owner.ranged_stationary_fired_seen=nil
    reason=release_reasons[reason or "released"] and (reason or "released") or "other"
    active_holds=math.max(0,active_holds-1)
    counters.exited=counters.exited+1
    counters.reasons[reason]=(counters.reasons[reason] or 0)+1
    -- Clear only this experiment's own mode. An external modifier/root or a
    -- replacement contact mode remains owned by its original system.
    local restored=false
    if owner.contact_mode==HOLD_MODE and type(owner.SetContactMode)=="function" then
        owner:SetContactMode(0)
        restored=true
    end
    hold.sample.exited_at=stamp()
    hold.sample.reason=reason
    hold.sample.restored=restored
    hold.sample.bat_after=valid(parent) and read(parent,"GetBaseAttackTime",false) or nil
    hold.sample.rate_after=valid(parent) and read(parent,"GetAttacksPerSecond",false) or nil
    return true
end
local function legal(owner,parent,wall,holding)
    if not M.enabled() then return false,"disabled" end
    if not valid(parent) or read(parent,"IsAlive")~=true then return false,"unit_dead" end
    if parent.survival_is_wave_monster~=true or parent.survival_wave_movement_type~="ground"
        or read(parent,"GetClassname")~="npc_dota_creature" then return false,"not_formal_ground" end
    if not valid(wall) or read(wall,"IsAlive")~=true
        or read(wall,"entindex")~=owner.wall_entindex then return false,"target_changed" end
    if owner.ai_state~="chase" or owner.goal_wall~=wall then return false,"state_changed" end
    if DOTA_UNIT_CAP_RANGED_ATTACK==nil or read(parent,"GetAttackCapability")~=DOTA_UNIT_CAP_RANGED_ATTACK
        then return false,"attack_type_changed" end
    if type(owner.SetContactMode)~="function"
        or owner.contact_mode~=(holding and HOLD_MODE or 0) then return false,"contact_mode_changed" end
    if read(parent,"GetTeamNumber")~=DOTA_TEAM_BADGUYS
        or not alignment.are_enemies(parent,wall) then return false,"team_changed" end
    local blocked,reason=controlled(owner,parent)
    if blocked then return false,reason end
    if read(parent,"IsControllableByAnyPlayer")==true then return false,"player_controlled" end
    if read(wall,"IsInvulnerable")==true or read(wall,"IsAttackImmune")==true
        then return false,"target_protected" end
    if read(parent,"CanEntityBeSeenByMyTeam",wall)~=true then return false,"not_visible" end
    if read(parent,"GetForceAttackTarget")~=wall then return false,"force_target_changed" end
    local native_target=read(parent,"GetAttackTarget")
    -- Native target may be nil during windup/cooldown, including a real
    -- release/landed callback. Force/goal wall plus the exact Fired/Landed
    -- record supply firing proof; an explicit foreign native target rejects.
    if native_target and native_target~=wall
        then return false,"attack_target_changed" end
    local p,w,reach,ph,wh=position(parent),position(wall),range(parent),hull(parent),hull(wall)
    if not p or not w or not reach or not ph or not wh then return false,"geometry_unavailable" end
    if holding then
        local hold=owner.ranged_stationary_hold
        if hold.generation~=generation then return false,"generation_changed" end
        if not same_position(hold.position,p) or not same_position(hold.wall_position,w)
            then return false,"position_changed" end
        if hold.range~=reach then return false,"range_changed" end
        if hold.parent_hull~=ph or hold.wall_hull~=wh then return false,"hull_changed" end
    end
    return true,nil,p,w,reach,ph,wh
end
local function same_geometry(e,p,w,reach,ph,wh)
    return same_position(e.position,p) and same_position(e.wall_position,w)
        and e.range==reach and e.parent_hull==ph and e.wall_hull==wh
end
local function attack_record(params)
    local record=params and params.record
    if type(record)=="number" and record==record and record>=0 and record<math.huge
        and record==math.floor(record) then return record end
end
local function duplicate_fired(owner,record)
    if record==nil then return false end
    local seen=owner.ranged_stationary_fired_seen
    if not seen or seen.generation~=generation then
        seen={generation=generation,records={},next=1}
        owner.ranged_stationary_fired_seen=seen
    end
    for _,previous in ipairs(seen.records) do if previous==record then return true end end
    seen.records[seen.next]=record
    seen.next=seen.next%SAMPLE_LIMIT+1
    return false
end
local function idle_reject(reason)
    idle_counters.admission_rejections[reason]=(idle_counters.admission_rejections[reason] or 0)+1
end
local function idle_sample(owner,parent,evidence,original)
    local index=idle_next_sample
    if idle_samples[index] then idle_counters.samples_overwritten=idle_counters.samples_overwritten+1 end
    idle_next_sample=index%SAMPLE_LIMIT+1
    local sample={sequence=idle_counters.set_attempts,unit_index=read(parent,"entindex"),
        wall_index=owner.wall_entindex,set_at=stamp(),original_idle_acquire=original,
        proof_fired_record=evidence.record,proof_fired_at=evidence.start_at,proof_landed_at=evidence.at,
        bat_before=read(parent,"GetBaseAttackTime",false),rate_before=read(parent,"GetAttacksPerSecond",false),
        post_set_fired=0,post_set_landed=0,post_set_pairs=0,
        fire_interval_count=0,fire_interval_sum=0,land_interval_count=0,land_interval_sum=0}
    idle_samples[index]=sample
    return sample
end
local function idle_before(owner,parent,wall,evidence)
    local token=idle_owners[owner]
    if token then
        idle_counters.active_checks=idle_counters.active_checks+1
        local reason
        if not M.idle_acquire_probe_enabled() then reason="idle_disabled"
        elseif not idle_owned(token,parent) then reason="idle_ownership_lost"
        elseif token.context~=idle_context or token.v3_generation~=generation then reason="idle_generation_changed"
        elseif read(parent,"GetAttackTarget")~=wall then reason="idle_target_lost"
        else
            local observed,error_kind=idle_boolean(parent,false)
            if observed~=false then reason=error_kind or "idle_external_value" end
        end
        local grace=not reason and attack_grace(parent) or nil
        if not reason and stamp()-(token.last_pair_at or token.set_at)>grace then
            reason="idle_post_set_stalled"
            owner.ranged_idle_acquire_failed_context=token.context
            idle_counters.post_set_stalls=idle_counters.post_set_stalls+1
        end
        if reason then M.release(owner,parent,reason);return false end
        return true,false,grace
    end
    -- No native idle API is even read unless BOTH flags authorize an existing
    -- v3 hold. FSM 'chase' here is the old label, not unproven moving pursuit.
    if not M.idle_acquire_probe_enabled() then return true end
    idle_counters.admission_checks=idle_counters.admission_checks+1
    if owner.ranged_idle_acquire_failed_context==idle_context then
        idle_reject("previous_failure_this_generation");return true
    end
    local hold=owner.ranged_stationary_hold
    if not own_root(owner) or not hold.sample or hold.sample.pair_source~="native_fired_record"
        or hold.sample.proof_has_record~=true or not evidence or evidence.has_record~=true
        or evidence.record==nil or evidence.generation~=generation or evidence.wall~=wall then
        idle_reject("proof_incomplete");return true
    end
    if read(owner,"GetParent")~=parent or owner.ranged_idle_acquire_hold~=nil
        or parent.survival_ranged_idle_acquire_owner~=nil then
        idle_reject("ownership_unavailable");return true
    end
    if read(parent,"GetAttackTarget")~=wall then idle_reject("native_target_not_wall");return true end
    if idle_active>=IDLE_OWNER_LIMIT then idle_reject("owner_limit");return true end
    local setter=idle_method(parent,"SetIdleAcquire")
    if not setter then idle_reject("setter_missing");return true end
    local original,error_kind=idle_boolean(parent,false)
    if original==nil then idle_reject(error_kind);return true end
    local key=original and "original_true" or "original_false"
    idle_counters[key]=idle_counters[key]+1
    if not original then idle_reject("already_false_unowned");return true end
    idle_counters.set_attempts=idle_counters.set_attempts+1
    token={owner=owner,parent=parent,wall=wall,context=idle_context,v3_generation=generation,
        original=original,set_at=stamp(),pending={},preexisting={},
        sample=idle_sample(owner,parent,evidence,original)}
    for _,pending in ipairs(owner.ranged_stationary_pending or {}) do token.preexisting[pending.record]=true end
    owner.ranged_idle_acquire_hold=token;parent.survival_ranged_idle_acquire_owner=token
    idle_owners[owner]=token;idle_active=idle_active+1
    idle_counters.setter_calls=idle_counters.setter_calls+1
    local ok=pcall(setter,parent,false)
    local readback=idle_boolean(parent,false)
    local allowed,reason=legal(owner,parent,wall,true)
    if not ok or readback~=false or read(parent,"GetAttackTarget")~=wall
        or not allowed or not idle_owned(token,parent) or not M.idle_acquire_probe_enabled() then
        if not ok then idle_counters.set_failures=idle_counters.set_failures+1 end
        if readback~=false then idle_counters.set_readback_failures=idle_counters.set_readback_failures+1 end
        owner.ranged_idle_acquire_failed_context=token.context
        token.sample.entered=false;token.sample.set_readback_false=readback==false
        M.release(owner,parent,reason or "idle_set_verification_failed")
        return false
    end
    token.entered=true;token.sample.entered=true;token.sample.set_readback_false=true
    idle_counters.entered=idle_counters.entered+1
    return true,true -- this triggering event happened BEFORE the setter
end
local function interval_sample(sample,prefix,t)
    local last=sample[prefix.."_last_at"]
    if last and t>=last then
        local interval=t-last
        sample[prefix.."_interval_count"]=sample[prefix.."_interval_count"]+1
        sample[prefix.."_interval_sum"]=sample[prefix.."_interval_sum"]+interval
        local minimum,maximum=sample[prefix.."_interval_min"],sample[prefix.."_interval_max"]
        sample[prefix.."_interval_min"]=minimum and math.min(minimum,interval) or interval
        sample[prefix.."_interval_max"]=maximum and math.max(maximum,interval) or interval
    end
    sample[prefix.."_last_at"]=t
end
local function idle_event(owner,parent,wall,event,params,matched,grace)
    local token=idle_owners[owner]
    if not token or token.released or token.wall~=wall then return end
    local record,t=attack_record(params),stamp()
    if event~="fired" and event~="landed" then return end
    if record==nil then idle_counters.post_set_record_missing=idle_counters.post_set_record_missing+1;return end
    for i=#token.pending,1,-1 do
        if t-token.pending[i].at>grace then table.remove(token.pending,i) end
    end
    if event=="fired" then
        if #token.pending>=PENDING_LIMIT then
            idle_counters.post_set_pending_overflow=idle_counters.post_set_pending_overflow+1
            table.remove(token.pending,1)
        end
        token.pending[#token.pending+1]={record=record,at=t}
        idle_counters.post_set_fired=idle_counters.post_set_fired+1
        token.sample.post_set_fired=token.sample.post_set_fired+1
        interval_sample(token.sample,"fire",t)
    else
        local selected
        for i,pending in ipairs(token.pending) do
            if pending.record==record and matched and matched.record==record and matched.at==pending.at
                and matched.generation==token.v3_generation then selected=i;break end
        end
        if not selected then
            if token.preexisting[record] then
                token.preexisting[record]=nil
                idle_counters.pre_set_inflight_ignored=idle_counters.pre_set_inflight_ignored+1
            else idle_counters.post_set_unmatched_landed=idle_counters.post_set_unmatched_landed+1 end
            return
        end
        table.remove(token.pending,selected)
        token.last_pair_at=t
        idle_counters.post_set_landed=idle_counters.post_set_landed+1
        idle_counters.post_set_pairs=idle_counters.post_set_pairs+1
        token.sample.post_set_landed=token.sample.post_set_landed+1
        token.sample.post_set_pairs=token.sample.post_set_pairs+1
        token.sample.last_landed_record=record
        interval_sample(token.sample,"land",t)
    end
end
local function observe_pair(owner,parent,wall,event,params,p,w,reach,ph,wh)
    local pending=owner.ranged_stationary_pending or {}
    owner.ranged_stationary_pending=pending
    local t=stamp()
    -- Only actual native releases can create pending records. Start is merely
    -- windup, and missing/asymmetric records never fall back to FIFO matching.
    for i=#pending,1,-1 do
        if pending[i].generation~=generation or t-pending[i].at>attack_grace(parent) then
            table.remove(pending,i)
        end
    end
    local record=attack_record(params)
    if event=="fired" and record~=nil then
        if #pending>=PENDING_LIMIT then
            counters.pending_overflow=counters.pending_overflow+1
            owner.ranged_stationary_evidence=nil
            table.remove(pending,1)
        end
        pending[#pending+1]={wall=wall,at=t,record=record,generation=generation,
            position=p,wall_position=w,range=reach,parent_hull=ph,wall_hull=wh}
    elseif event=="landed" then
        local selected
        for i,start in ipairs(pending) do
            if record~=nil and start.wall==wall and start.record==record then
                selected=i;break
            end
        end
        if not selected then
            counters.unmatched_landed=counters.unmatched_landed+1
            if record~=nil and #pending>0 then
                counters.mismatched_landed_record=counters.mismatched_landed_record+1
            end
            return
        end
        local start=table.remove(pending,selected)
        if not same_geometry(start,p,w,reach,ph,wh) then
            counters.changed_pair=counters.changed_pair+1
            owner.ranged_stationary_evidence=nil
            return
        end
        counters.stationary_pairs=counters.stationary_pairs+1
        counters.pairs_with_record=counters.pairs_with_record+1
        owner.ranged_stationary_evidence={wall=wall,at=t,start_at=start.at,record=record,has_record=true,generation=generation,
            position=p,wall_position=w,range=reach,parent_hull=ph,wall_hull=wh}
        return start
    end
end
function M.observe(owner,parent,wall,event,params)
    if not owner then return end
    local hold=owner.ranged_stationary_hold
    if not hold and idle_owners[owner] then
        restore_idle(owner,parent,"idle_recovery_retry")
        return -- a recovery callback cannot establish a new hold/fire proof
    end
    if not hold and not M.enabled() then return end
    if not hold and read(parent,"GetAttackCapability")~=DOTA_UNIT_CAP_RANGED_ATTACK then return end
    local observed_target=wall
    local duplicate=event=="fired" and duplicate_fired(owner,attack_record(params))
    if duplicate then counters.duplicate_fired=counters.duplicate_fired+1 end
    if event and not duplicate then
        local key=(event=="landed" and "attack_landed_" or event=="fired" and "attack_fired_" or "attack_start_")
            ..(hold and "held" or "free")
        counters[key]=counters[key]+1
        if hold then hold.sample[key]=(hold.sample[key] or 0)+1 end
        local record_key=event.."_record_"..(attack_record(params)~=nil and "present" or "missing")
        counters[record_key]=counters[record_key]+1
    end
    if not wall and owner.wall_entindex and owner.wall_entindex>=0 and EntIndexToHScript then
        wall=EntIndexToHScript(owner.wall_entindex)
    end
    local allowed,reason,p,w,reach,ph,wh=legal(owner,parent,wall,hold~=nil)
    if not allowed then
        if not hold then counters.entry_rejections[reason]=(counters.entry_rejections[reason] or 0)+1 end
        M.release(owner,parent,reason)
        owner.ranged_stationary_evidence=nil;owner.ranged_stationary_pending=nil
        owner.ranged_stationary_fired_seen=nil
        return
    end
    -- Observe pending release geometry on the existing think and native events.
    -- A changed observed position cannot become valid merely by moving back
    -- to the original point before its projectile lands.
    local pending=owner.ranged_stationary_pending
    if pending then
        for i=#pending,1,-1 do
            local start=pending[i]
            if start.generation~=generation or start.wall~=wall or not same_geometry(start,p,w,reach,ph,wh) then
                table.remove(pending,i)
                counters.pending_geometry_changed=counters.pending_geometry_changed+1
            end
        end
    end
    local matched
    if event and not duplicate and observed_target==wall then
        matched=observe_pair(owner,parent,wall,event,params,p,w,reach,ph,wh)
    end
    local evidence=owner.ranged_stationary_evidence
    if not evidence or evidence.generation~=generation or evidence.wall~=wall
        or stamp()-evidence.at>attack_grace(parent) then
        M.release(owner,parent,"attack_stalled");return
    end
    if not same_geometry(evidence,p,w,reach,ph,wh) then
        M.release(owner,parent,"position_changed")
        owner.ranged_stationary_evidence=nil;owner.ranged_stationary_pending=nil
        return
    end
    if hold then
        local idle_allowed,just_set,idle_grace=idle_before(owner,parent,wall,evidence)
        if idle_allowed and not just_set and event and not duplicate and observed_target==wall then
            idle_event(owner,parent,wall,event,params,matched,idle_grace)
        end
        return
    end
    counters.entered=counters.entered+1
    active_holds=active_holds+1
    owner.ranged_stationary_hold={position=p,wall_position=w,range=reach,
        parent_hull=ph,wall_hull=wh,generation=generation,
        sample=sample_enter(owner,parent,evidence)}
    owner:SetContactMode(HOLD_MODE)
end
function M.snapshot()
    local result={enabled=M.enabled(),generation=generation,active_holds=active_holds,
        hold_mode=HOLD_MODE,movement_capability_mutations=false,
        observation_interval_seconds=.5,sample_limit=SAMPLE_LIMIT,pending_limit=PENDING_LIMIT,
        native_attack_continuity_verified=false,reasons={},entry_rejections={},bat_samples={}}
    for key,value in pairs(counters) do
        if key~="reasons" and key~="entry_rejections" then result[key]=value end
    end
    for key,value in pairs(counters.reasons) do result.reasons[key]=value end
    for key,value in pairs(counters.entry_rejections) do result.entry_rejections[key]=value end
    for _,sample in ipairs(samples) do
        local copy={};for key,value in pairs(sample) do copy[key]=value end
        result.bat_samples[#result.bat_samples+1]=copy
    end
    table.sort(result.bat_samples,function(a,b) return a.sequence<b.sequence end)
    local idle={enabled=M.idle_acquire_probe_enabled(),generation=idle_generation,
        active_owned_mutations=idle_active,owner_limit=IDLE_OWNER_LIMIT,
        pending_limit=PENDING_LIMIT,sample_limit=SAMPLE_LIMIT,recovery_pending=0,
        requires_strict_native_wall_target=true,post_set_native_continuity_verified=false,
        uses_should_idle_acquire=true,attack_orders_issued=0,
        original_false_is_never_mutated=true,admission_rejections={},reasons={},samples={}}
    for _,token in pairs(idle_owners) do
        if token.released then idle.recovery_pending=idle.recovery_pending+1 end
    end
    for key,value in pairs(idle_counters) do
        if type(value)~="table" then idle[key]=value end
    end
    for key,value in pairs(idle_counters.admission_rejections) do idle.admission_rejections[key]=value end
    for key,value in pairs(idle_counters.reasons) do idle.reasons[key]=value end
    for _,sample in ipairs(idle_samples) do
        local copy={};for key,value in pairs(sample) do copy[key]=value end
        idle.samples[#idle.samples+1]=copy
    end
    table.sort(idle.samples,function(a,b) return a.sequence<b.sequence end)
    result.idle_acquire=idle
    return result
end
return M
