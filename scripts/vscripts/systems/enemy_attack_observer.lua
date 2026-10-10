-- Native attack/death notifications route to the owning enemy AI. A wall
-- death visits only its registered targets; no polling or map scans.
local M = {}
local NAME = "modifier_enemy_attack_observer"
local HOLDER_KEY = "survival_enemy_attack_observer_holder"
local DEATH_KEY = "survival_enemy_death_observer_registry"
local function valid(unit) return unit and not unit:IsNull() end
local function current_world()
    if not GameRules or type(GameRules.GetGameModeEntity) ~= "function" then return nil end
    local mode = GameRules:GetGameModeEntity()
    if mode and (not mode.IsNull or not mode:IsNull()) then return mode end
end
local function installed(unit)
    if not valid(unit) or type(unit.HasModifier) ~= "function" then return false end
    local ok, result = pcall(unit.HasModifier, unit, NAME)
    return ok and result == true
end

function M.is_ready()
    local mode = current_world()
    return mode ~= nil and installed(mode[HOLDER_KEY]) or false
end

function M.is_authoritative(unit)
    local mode = current_world()
    return mode ~= nil and mode[HOLDER_KEY] == unit and installed(unit) or false
end

function M.can_route_death()
    local mode=current_world();local holder=mode and mode[HOLDER_KEY]
    -- A service/class reload cannot upgrade an old native event declaration.
    local registry=mode and mode[DEATH_KEY]
    return mode~=nil and installed(holder) and holder.survival_enemy_death_observer_version==1
        and (not registry or registry.version==1) or false
end
local function unlink(record)
    local bucket=record.bucket;if not bucket then return end
    if record.previous then record.previous.next=record.next else bucket.first=record.next end
    if record.next then record.next.previous=record.previous else bucket.last=record.previous end
    if not bucket.first then record.registry.walls[record.wall]=nil end
    record.previous,record.next,record.bucket,record.wall=nil,nil,nil,nil
end
function M.unregister_death(owner)
    local record=owner and owner.enemy_death_record
    if not record or record.owner~=owner then return end
    unlink(record)
    if record.registry.units[record.unit]==record then record.registry.units[record.unit]=nil end
    owner.enemy_death_record=nil
end
function M.bind_death_wall(owner,wall)
    local record=owner and owner.enemy_death_record
    if not record or record.owner~=owner or current_world()~=record.mode then return false end
    if not valid(wall) then wall=nil end
    if record.wall==wall then return true end
    unlink(record);if not wall then return true end
    local bucket=record.registry.walls[wall]
    if not bucket then bucket={};record.registry.walls[wall]=bucket end
    record.wall,record.bucket=wall,bucket
    -- Preserve instance registration order across rebinds; normal new spawns
    -- append in O(1). Unlink/cleanup is O(1), with no accumulated array holes.
    local before=bucket.last
    while before and before.order>record.order do before=before.previous end
    record.previous=before
    if before then record.next=before.next else record.next=bucket.first end
    if record.next then record.next.previous=record else bucket.last=record end
    if before then before.next=record else bucket.first=record end
    return true
end
function M.register_death(unit,owner,wall)
    if not M.can_route_death() or not valid(unit) or not owner or owner:GetParent()~=unit then return false end
    local mode=current_world();local registry=mode[DEATH_KEY]
    if registry and registry.version~=1 then return false end
    if not registry then registry={version=1,units={},walls={},order=0};mode[DEATH_KEY]=registry end
    local existing=registry.units[unit]
    if existing and existing.owner==owner then return M.bind_death_wall(owner,wall) end
    if existing then M.unregister_death(existing.owner) end
    M.unregister_death(owner)
    registry.order=registry.order+1
    local record={unit=unit,owner=owner,registry=registry,mode=mode,order=registry.order}
    registry.units[unit]=record;owner.enemy_death_record=record
    return M.bind_death_wall(owner,wall)
end
function M.dispatch_death(holder,params,callback)
    if not params or not valid(params.unit) or not M.is_authoritative(holder) or not M.can_route_death() then return end
    local mode=current_world();local registry=mode[DEATH_KEY];if not registry then return end
    local own=registry.units[params.unit]
    local bucket=registry.walls[params.unit]
    local snapshot={}
    if own then snapshot[#snapshot+1]=own end
    local record=bucket and bucket.first
    while record do if record~=own then snapshot[#snapshot+1]=record end;record=record.next end
    -- A wall callback clears its own binding. Snapshot only this wall's bucket
    -- before callbacks so mutation cannot skip later relevant native owners.
    for _,candidate in ipairs(snapshot) do
        local owner=candidate.owner;local unit=candidate.unit
        if registry.units[unit]==candidate and owner.enemy_death_record==candidate
            and (candidate==own or candidate.wall==params.unit) and valid(unit)
            and (not owner.IsNull or not owner:IsNull()) and owner.shared_death_observer==true
            and unit.survival_enemy_attack_owner==owner and owner:GetParent()==unit then
            local ok,err=pcall(callback,owner,params)
            if not ok then print('[EnemyDeathObserver] handler failed: '..tostring(err)) end
        end
    end
end

function M.init()
    local current = current_world()
    if not current then return false end
    -- The authoritative handle survives a Lua module reload on this map.
    if installed(current[HOLDER_KEY]) then return true end
    current[HOLDER_KEY] = nil
    local ok, unit = pcall(function()
        LinkLuaModifier(NAME, "modifiers/modifier_enemy_attack_observer", LUA_MODIFIER_MOTION_NONE)
        return CreateModifierThinker(nil, nil, NAME, {}, Vector(0, 0, -10000), DOTA_TEAM_NEUTRALS, false)
    end)
    if ok and installed(unit) and current_world() == current then
        current[HOLDER_KEY] = unit
        return true
    end
    if ok and valid(unit) and type(UTIL_Remove) == "function" then pcall(UTIL_Remove, unit) end
    print("[EnemyAttackObserver] unavailable; retaining per-enemy attack callbacks")
    return false
end

return M
