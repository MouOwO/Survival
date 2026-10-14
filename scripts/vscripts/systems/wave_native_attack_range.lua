-- Default-off Tools experiment for NEW formal births only. No live modifier
-- removal, engine setters, orders, timers, holders or require-time native work.
local M = {}
local context, serial = nil, 0
local function native(object,name,...)
    if not object then return nil end
    local ok,fn=pcall(function() return object[name] end)
    if not ok or type(fn)~="function" then return nil,"unavailable" end
    local succeeded,value=pcall(fn,object,...)
    if succeeded then return value end
    return nil,"read_failed"
end
local function number(value)
    return type(value)=="number" and value==value and math.abs(value)<math.huge and value or nil
end
local function world() return native(GameRules,"GetGameModeEntity") end
local function authority()
    if not IsServer or not IsServer() or not IsInToolsMode or not IsInToolsMode()
        or not GetMapName or GetMapName()~="template_map" then return nil end
    local mode=world();local guard=_G.SURVIVAL_REAL_GAME_STRESS_ISOLATION
    if not mode or type(guard)~="table" or guard.mode~=mode then return nil end
    local bus=require("core/event_bus")
    if type(bus.get_generation)~="function" then return nil end
    local ok,generation=pcall(bus.get_generation)
    if not ok or generation==nil then return nil end
    return mode,guard,bus,generation
end
function M.enabled()
    local ctx=context
    if _G.SURVIVAL_FORMAL_WAVE_NATIVE_RANGE_PROBE~=true or not ctx then return false end
    local mode,guard,bus,generation=authority()
    return context==ctx and mode==ctx.world and guard==ctx.guard and bus==ctx.bus and generation==ctx.bus_generation
end
function M.set_probe_enabled(value)
    if value~=true then _G.SURVIVAL_FORMAL_WAVE_NATIVE_RANGE_PROBE=false;context=nil;return true end
    local mode,guard,bus,generation=authority()
    if not mode then return false,"requires isolated Workshop template_map server" end
    serial=serial+1
    context={world=mode,guard=guard,bus=bus,bus_generation=generation,serial=serial,
        ready={},pending={},failed={},counts={selected_original=0,selected_alias=0,
        birth_proven=0,omitted=0,late_fallback=0,creation_fallback=0,precache_failed=0,
        rejections={}}}
    _G.SURVIVAL_FORMAL_WAVE_NATIVE_RANGE_PROBE=true
    return true
end
local function reject(reason)
    if context then
        local rejected=context.counts.rejections;rejected[reason]=(rejected[reason] or 0)+1
    end
end
local function same(a,b,exclude_range)
    if type(a)~=type(b) then return false end
    if type(a)~="table" then return a==b end
    for key,value in pairs(a) do
        if not (exclude_range and key=="AttackRange") and not same(value,b[key],false) then return false end
    end
    for key in pairs(b) do if not (exclude_range and key=="AttackRange") and a[key]==nil then return false end end
    return true
end
local function load_contract()
    if context.contract then return context.contract end
    local c={definitions=require("config/generated/monster_archetypes"),
        manifest=require("config/generated/wave_native_range_aliases"),formal={},names={}}
    for _,row in ipairs(require("config/generated/wave_definitions").rows) do
        if row.enabled~=false then c.formal[row.archetype_id]=true end
    end
    for _,row in ipairs(c.definitions.rows) do c.names[row.unit_name]=(c.names[row.unit_name] or 0)+1 end
    local ok,kv=pcall(LoadKeyValues,"scripts/npc/npc_units_custom.txt")
    c.kv=ok and type(kv)=="table" and (kv.DOTAUnits or kv) or {}
    c.cap=require("systems/wave_native_attack_cap")
    context.contract=c
    return c
end
local function contract(definition)
    local c=load_contract()
    if type(definition)~="table" or definition.enabled==false
        or c.definitions.by_id[definition.archetype_id]~=definition
        or not c.formal[definition.archetype_id] then return nil,"not_known_formal" end
    if c.names[definition.unit_name]~=1 then return nil,"shared_native_name" end
    if definition.native_attack_speed_policy~="bat_only_v1"
        or (definition.passive_skill_ids~=nil and (type(definition.passive_skill_ids)~="table"
            or next(definition.passive_skill_ids)~=nil)) then return nil,"unknown_ability_contract" end
    local reach=definition.attack_range==nil and 128 or number(definition.attack_range)
    if not reach or reach<=0 then return nil,"invalid_config_range" end
    reach=math.max(0,math.floor(reach))
    local source=c.kv[definition.unit_name]
    if type(source)~="table" or not c.cap.is_bare_creature(definition.unit_name) then return nil,"source_kv_unknown" end
    local alias=c.manifest.schema=="formal_native_range_v1" and c.manifest.roster_count==44
        and c.manifest.alias_count==19 and c.manifest.by_id[definition.archetype_id]
    if not alias or alias.source_unit_name~=definition.unit_name or alias.attack_range~=reach then
        return nil,"manifest_unknown"
    end
    if tonumber(source.AttackRange)==reach then
        if alias.alias~=false or alias.unit_name~=definition.unit_name then return nil,"manifest_unknown" end
        return definition.unit_name,reach,false
    end
    local kv=alias and c.kv[alias.unit_name]
    if alias.alias~=true or type(kv)~="table" or tonumber(kv.AttackRange)~=reach
        or not same(source,kv,true) or not c.cap.is_bare_creature(alias.unit_name) then
        return nil,"alias_kv_unknown"
    end
    return alias.unit_name,reach,true
end
-- Explicit preparation, outside timed capture. Model-path preload dedup cannot
-- establish a second unit-name definition, so maintain a separate ready set.
function M.prepare_aliases()
    if not M.enabled() then return false,"disabled" end
    local ctx=context;local ok,c=pcall(load_contract)
    if not ok then reject("contract_api_failed");return false,"contract unavailable" end
    local queued,alias_count=0,0
    for _,definition in ipairs(c.definitions.rows) do
        if c.formal[definition.archetype_id] then
            local accepted,name,_,alias=pcall(contract,definition)
            if not accepted then name=nil end
            if name and alias and not ctx.ready[name] and not ctx.pending[name] then
                alias_count=alias_count+1
                if alias_count>19 then reject("alias_limit");return false,"alias bound exceeded" end
                if type(PrecacheUnitByNameAsync)~="function" then
                    ctx.failed[name]=true;ctx.counts.precache_failed=ctx.counts.precache_failed+1
                else
                    ctx.pending[name]=true;queued=queued+1
                    local ok=pcall(PrecacheUnitByNameAsync,name,function()
                        if context~=ctx or not M.enabled() then return end
                        ctx.pending[name]=nil;ctx.ready[name]=true
                    end,-1)
                    if not ok then
                        ctx.pending[name]=nil;ctx.failed[name]=true
                        ctx.counts.precache_failed=ctx.counts.precache_failed+1
                    end
                end
            end
        end
    end
    return true,queued
end
function M.select_for_formal_spawn(definition)
    if not M.enabled() then return definition end
    local ok,name,reach,alias=pcall(contract,definition)
    if not ok or not name then reject(ok and reach or "contract_api_failed");return definition end
    if alias and context.ready[name]~=true then reject("alias_not_ready");return definition end
    local effective=definition
    if alias then
        effective={};for key,value in pairs(definition) do effective[key]=value end
        effective.unit_name=name
    end
    local key=alias and "selected_alias" or "selected_original"
    context.counts[key]=context.counts[key]+1
    return effective,{context=context,source=definition,effective=effective,name=name,range=reach,alias=alias}
end
local SAFE_MODIFIERS={modifier_single_health_bar=true,modifier_debug_attack_cap=true}
function M.bind_birth(unit,ticket,fresh_formal_birth)
    if not M.enabled() or fresh_formal_birth~=true or not ticket or ticket.context~=context
        or ticket.birth_unit~=nil or not unit then return false end
    ticket.birth_unit=unit
    return true
end
local function birth_proof(unit,definition,ticket)
    if not M.enabled() or not ticket or ticket.context~=context or ticket.effective~=definition then return false,"ticket_stale" end
    local configured=definition.attack_range==nil and 128 or number(definition.attack_range)
    if definition.unit_name~=ticket.name or not configured or configured<=0
        or math.floor(configured)~=ticket.range then return false,"definition_changed" end
    if ticket.birth_unit~=unit or ticket.unit and ticket.unit~=unit then return false,"unit_identity_changed" end
    if native(unit,"IsNull")~=false or native(unit,"IsAlive")~=true
        or native(unit,"GetClassname")~="npc_dota_creature" or native(unit,"IsRealHero")~=false
        or native(unit,"GetTeamNumber")~=DOTA_TEAM_BADGUYS
        or native(unit,"GetUnitName")~=ticket.name then return false,"native_identity_unknown" end
    if native(unit,"HasModifier","modifier_survival_hero_attack_range")~=false then return false,"existing_override" end
    local capability=native(unit,"GetAttackCapability")
    local expected=definition.attack_type=="ranged" and DOTA_UNIT_CAP_RANGED_ATTACK or DOTA_UNIT_CAP_MELEE_ATTACK
    -- Candidate proof runs after final native capability/model setup, before
    -- passive/appearance effects and then again immediately before AI.
    if not expected or capability~=expected then return false,"native_capability_mismatch" end
    local modifiers=native(unit,"FindAllModifiers")
    if type(modifiers)~="table" or #modifiers>16 then return false,"modifier_list_unknown" end
    for _,modifier in pairs(modifiers) do
        if not SAFE_MODIFIERS[native(modifier,"GetName")] then return false,"unknown_modifier" end
    end
    local count=number(native(unit,"GetAbilityCount"))
    if not count or count<0 or count>64 or count~=math.floor(count) then return false,"ability_list_unknown" end
    for slot=0,count-1 do
        local ability,ability_error=native(unit,"GetAbilityByIndex",slot)
        if ability_error or ability~=nil and type(ability)~="table" and type(ability)~="userdata" then
            return false,"ability_list_unknown"
        end
        if ability then
            if native(ability,"IsNull")~=false or not load_contract().cap.is_inert_native_warp(ability,slot) then
                return false,"unknown_native_ability"
            end
        end
    end
    local getter=type(unit.Script_GetAttackRange)=="function" and "Script_GetAttackRange" or "GetAttackRange"
    local actual=number(native(unit,getter))
    if not actual or actual~=ticket.range then return false,"native_range_mismatch" end
    return true
end
function M.can_omit_override(unit,definition,ticket)
    local ok,accepted,reason=pcall(birth_proof,unit,definition,ticket)
    if not ok or not accepted then reject(ok and reason or "native_proof_api_failed");return false end
    ticket.unit=unit;ticket.birth_proven=true
    context.counts.birth_proven=context.counts.birth_proven+1
    return true
end
function M.finalize(unit,definition,ticket)
    if not ticket or not ticket.birth_proven or ticket.finalized then return false end
    local ok,accepted,reason=pcall(birth_proof,unit,definition,ticket)
    if not ok or not accepted then
        reject(ok and reason or "native_proof_api_failed")
        if context==ticket.context then context.counts.late_fallback=context.counts.late_fallback+1 end
        return false
    end
    ticket.finalized=true;context.counts.omitted=context.counts.omitted+1
    return true
end
function M.alias_creation_failed(ticket)
    if ticket and context==ticket.context then context.counts.creation_fallback=context.counts.creation_fallback+1 end
end
function M.snapshot()
    local result={enabled=M.enabled(),generation=serial,ready_aliases=0,pending_aliases=0,
        failed_aliases=0,alias_limit=19,formal_roster_limit=44,actual_native_behavior_verified=false,
        removes_existing_modifiers=false,orders_issued=0,rejections={}}
    if not context then return result end
    for _ in pairs(context.ready) do result.ready_aliases=result.ready_aliases+1 end
    for _ in pairs(context.pending) do result.pending_aliases=result.pending_aliases+1 end
    for _ in pairs(context.failed) do result.failed_aliases=result.failed_aliases+1 end
    for key,value in pairs(context.counts) do if type(value)~="table" then result[key]=value end end
    for key,value in pairs(context.counts.rejections) do result.rejections[key]=value end
    return result
end
return M
