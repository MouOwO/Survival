-- Inert Tools candidate. Four resource-tree native listeners can share one
-- synchronous carrier. No polling, damage mutation or attack frequency changes.
-- Disabling stops NEW registrations only: existing omitted native declarations
-- still require this world-owned route until their modifiers are destroyed.
local M={}
local NAME='modifier_tree_attack_observer'
local HOLDER='survival_tree_attack_observer_holder_v1'
local REGISTRY='survival_tree_attack_observer_registry_v1'
local PROBE='SURVIVAL_TREE_ATTACK_OBSERVER_PROBE'
local METHODS={'HandleAttackStart','HandleAttackFail','HandleAttackRecordDestroy','HandleTakeDamage'}
local function valid(unit) return unit and not unit:IsNull() end
local function world()
    if not GameRules or type(GameRules.GetGameModeEntity)~='function' then return nil end
    local mode=GameRules:GetGameModeEntity()
    return mode and (not mode.IsNull or not mode:IsNull()) and mode or nil
end
local function installed(unit)
    if not valid(unit) or type(unit.HasModifier)~='function' then return false end
    local ok,result=pcall(unit.HasModifier,unit,NAME)
    return ok and result==true and unit.survival_tree_attack_observer_native_version==1
end
local function registry(create)
    local mode=world();if not mode then return nil end
    local r=mode[REGISTRY]
    if r and (r.version~=1 or r.mode~=mode) then return nil end
    if not r and create then
        r={version=1,mode=mode,trees={},pending={},count=0,order=0,
            metrics={native_events={},dispatched={},callback_errors=0,stale_records=0}}
        mode[REGISTRY]=r
    end
    return r
end
function M.is_ready()
    local mode=world()
    return mode~=nil and installed(mode[HOLDER]) and registry(false)~=nil or false
end
function M.is_authoritative(unit)
    local mode=world()
    return mode~=nil and mode[HOLDER]==unit and installed(unit) and registry(false)~=nil or false
end
function M.can_register_new()
    local p=_G[PROBE]
    if type(p)~='table' or p.enabled~=true or not IsServer or not IsServer()
        or not IsInToolsMode or not IsInToolsMode() then return false end
    local mode=world();local guard=_G.SURVIVAL_REAL_GAME_STRESS_ISOLATION
    if not mode or p.mode~=mode or not guard or p.guard~=guard or guard.mode~=mode then return false end
    return M.is_ready()
end
function M.enable_probe(options)
    assert(IsServer and IsServer() and IsInToolsMode and IsInToolsMode(),'Tools server only')
    assert(GetMapName()=='template_map','template_map only')
    options=options or {}
    local mode=assert(world(),'Current GameMode required')
    local guard=_G.SURVIVAL_REAL_GAME_STRESS_ISOLATION
    assert(guard and guard.mode==mode and (options.mode==nil or options.mode==mode)
        and (options.guard==nil or options.guard==guard),'Current match write isolation/mode required')
    local r=assert(registry(true),'Unknown registry version cannot be adopted')
    if not installed(mode[HOLDER]) then
        local ok,unit=pcall(function()
            LinkLuaModifier(NAME,'modifiers/'..NAME,LUA_MODIFIER_MOTION_NONE)
            return CreateModifierThinker(nil,nil,NAME,{},Vector(0,0,-10000),DOTA_TEAM_NEUTRALS,false)
        end)
        if not ok or not installed(unit) or world()~=mode then
            if ok and valid(unit) and UTIL_Remove then pcall(UTIL_Remove,unit) end
            r.last_error=not ok and tostring(unit):sub(1,160) or 'native_carrier_version_not_confirmed'
            _G[PROBE]={enabled=false,mode=mode,guard=guard}
            return {ok=false,error=r.last_error}
        end
        mode[HOLDER]=unit
    end
    _G[PROBE]={enabled=true,mode=mode,guard=guard}
    return M.snapshot()
end
function M.disable_probe()
    local p=_G[PROBE];if type(p)=='table' then p.enabled=false end
    -- Never destroy a required carrier or restore imagined native declarations.
    return M.snapshot()
end
local function unbind_pending(record,attacker)
    local bucket=record.registry.pending[attacker]
    if bucket then bucket[record]=nil;if next(bucket)==nil then record.registry.pending[attacker]=nil end end
    record.pending_attackers[attacker]=nil
end
function M.unregister(owner)
    local record=owner and owner.tree_attack_observer_record
    if not record or record.owner~=owner then return end
    local attackers={};for attacker in pairs(record.pending_attackers) do attackers[#attackers+1]=attacker end
    for _,attacker in ipairs(attackers) do unbind_pending(record,attacker) end
    if record.registry.trees[record.unit]==record then
        record.registry.trees[record.unit]=nil;record.registry.count=record.registry.count-1
    end
    owner.tree_attack_observer_record=nil
end
function M.register(unit,owner,callbacks)
    if not M.can_register_new() or not valid(unit) or not owner or owner:GetParent()~=unit
        or (owner.IsNull and owner:IsNull()) then return false end
    for _,method in ipairs(METHODS) do if type(callbacks and callbacks[method])~='function' then return false end end
    local r=registry(false);local previous=r.trees[unit]
    if previous then return previous.owner==owner end
    r.order=r.order+1
    local record={registry=r,unit=unit,owner=owner,callbacks=callbacks,order=r.order,pending_attackers={}}
    r.trees[unit]=record;r.count=r.count+1;owner.tree_attack_observer_record=record
    return true
end
local function active(record,r)
    return record and record.registry==r and r.trees[record.unit]==record
        and record.owner.tree_attack_observer_record==record and record.owner.shared_tree_observer==true
        and (not record.owner.IsNull or not record.owner:IsNull()) and valid(record.unit)
        and record.owner:GetParent()==record.unit
end
local function update_pending(record,attacker)
    if not attacker then return end
    local token=record.owner.tree_attackers and record.owner.tree_attackers[attacker]
    if token then
        local r=record.registry;local bucket=r.pending[attacker]
        if not bucket then bucket={};r.pending[attacker]=bucket end
        bucket[record]=true;record.pending_attackers[attacker]=true
    else unbind_pending(record,attacker) end
end
local function call(record,method,params,r)
    if not active(record,r) then r.metrics.stale_records=r.metrics.stale_records+1;return end
    local ok,error_text=pcall(record.callbacks[method],record.owner,params)
    r.metrics.dispatched[method]=(r.metrics.dispatched[method] or 0)+1
    if not ok then
        r.metrics.callback_errors=r.metrics.callback_errors+1
        r.last_error=tostring(error_text):sub(1,160)
    end
    if method~='HandleTakeDamage' and r.trees[record.unit]==record then update_pending(record,params.attacker) end
end
function M.dispatch(holder,method,params)
    if not IsServer() or not params or not M.is_authoritative(holder) then return end
    local r=registry(false);r.metrics.native_events[method]=(r.metrics.native_events[method] or 0)+1
    if method=='HandleAttackRecordDestroy' then
        -- Target-less record destruction visits only trees with this attacker's
        -- pending evidence. Snapshot preserves native creation/registration order
        -- while callbacks remove bindings, die or consume records synchronously.
        local bucket=r.pending[params.attacker];if not bucket then return end
        local snapshot={};for record in pairs(bucket) do snapshot[#snapshot+1]=record end
        table.sort(snapshot,function(a,b) return a.order<b.order end)
        for _,record in ipairs(snapshot) do call(record,method,params,r) end
    else
        local target=method=='HandleTakeDamage' and params.unit or params.target
        local record=target and r.trees[target]
        if record then call(record,method,params,r) end
    end
end
function M.snapshot()
    local r=registry(false);local p=_G[PROBE]
    local result={ok=true,default_enabled=false,experimental_not_production=true,
        enabled_for_new_instances=M.can_register_new(),carrier_ready=M.is_ready(),
        registered_trees=r and r.count or 0,pending_attackers=0,pending_bindings=0,
        requires_map_reload_to_restore_native_tree_declarations=r and r.count>0 or false,
        disable_preserves_existing_routes=true,synchronous_native_dispatch=true,
        worker_observer_unchanged=true,scope='new_formal_resource_tree_modifiers_only',trees={},metrics={}}
    if r then
        for _,record in pairs(r.trees) do
            result.trees[#result.trees+1]={order=record.order,owner_id=record.unit.survival_tree_owner_id,
                shared=record.owner.shared_tree_observer==true}
        end
        table.sort(result.trees,function(a,b) return a.order<b.order end)
        for _,bucket in pairs(r.pending) do
            result.pending_attackers=result.pending_attackers+1
            for _ in pairs(bucket) do result.pending_bindings=result.pending_bindings+1 end
        end
        for key,value in pairs(r.metrics) do
            if type(value)=='table' then result.metrics[key]={};for k,v in pairs(value) do result.metrics[key][k]=v end
            else result.metrics[key]=value end
        end
        result.last_error=r.last_error
    end
    return result
end
return M
