-- One native attack/hurt listener replaces global listeners on every tower.
-- Keep the exact post-damage event (including native attacks and blocked hits).
local M = {}
local NAME = "modifier_tower_damage_observer"
local HOLDER_KEY = "survival_tower_damage_observer_holder"
local WALL_STATE_KEY = "survival_shared_wall_feedback_state"
local CORROSIVE_STATE_KEY = "survival_shared_corrosive_shield_state"
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

local function wall_state(mode, create)
    if not mode then return nil end
    local state = mode[WALL_STATE_KEY]
    if not state and create then
        state = { enabled = false, counters = {
            registered = 0, active_shared = 0, unregistered = 0,
            landed_seen = 0, landed_matched = 0, damage_seen = 0,
            damage_matched = 0, damage_positive = 0, registration_failed = 0,
        } }
        mode[WALL_STATE_KEY] = state
    end
    return state
end

local function wall_carrier_ready(mode)
    local holder = mode and mode[HOLDER_KEY]
    return installed(holder) and holder.survival_wall_feedback_observer_version == 1
end

-- Opt in explicitly for this isolated Tools world. A surviving flag cannot
-- enable new receivers in the next map. No native declarations change here.
function M.set_wall_feedback_probe(enabled)
    local mode = current_world()
    if not enabled then
        _G.SURVIVAL_SHARED_WALL_FEEDBACK_PROBE = false
        local state = wall_state(mode, false)
        if state then state.enabled = false end
        return true
    end
    local isolation = _G.SURVIVAL_REAL_GAME_STRESS_ISOLATION
    if not IsServer or not IsServer() or not IsInToolsMode or not IsInToolsMode()
        or not GetMapName or GetMapName() ~= "template_map" or not mode
        or not isolation or isolation.mode ~= mode then return false end
    wall_state(mode, true).enabled = true
    _G.SURVIVAL_SHARED_WALL_FEEDBACK_PROBE = true
    return true
end

function M.wall_feedback_probe_enabled()
    if _G.SURVIVAL_SHARED_WALL_FEEDBACK_PROBE ~= true or not IsServer or not IsServer()
        or not IsInToolsMode or not IsInToolsMode()
        or not GetMapName or GetMapName() ~= "template_map" then return false end
    local mode = current_world()
    local isolation = _G.SURVIVAL_REAL_GAME_STRESS_ISOLATION
    local state = wall_state(mode, false)
    return mode ~= nil and isolation and isolation.mode == mode
        and state ~= nil and state.enabled == true or false
end

function M.choose_wall_feedback(unit)
    if not M.wall_feedback_probe_enabled() or not valid(unit)
        or unit.survival_building_id ~= "wall" then return nil end
    local mode = current_world()
    return wall_carrier_ready(mode) and mode or nil
end

function M.register_wall_feedback(unit, modifier, declared_world)
    local mode = current_world()
    -- First native DeclareFunctions has already committed to the shared route.
    -- Turning the opt-in off between Declare and OnCreated must not lose hits.
    local state = wall_state(declared_world, false)
    if not declared_world or mode ~= declared_world or not valid(unit) or not modifier
        or modifier.shared_wall_feedback_observer ~= true
        or modifier.IsNull and modifier:IsNull() or not wall_carrier_ready(mode)
        or not state then
        if state then state.counters.registration_failed = state.counters.registration_failed + 1 end
        return false
    end
    if modifier.wall_feedback_registration then return true end
    unit.survival_shared_wall_sound_owner = modifier
    modifier.wall_feedback_registration = { unit = unit, world = mode, state = state }
    state.counters.registered = state.counters.registered + 1
    state.counters.active_shared = state.counters.active_shared + 1
    return true
end

function M.unregister_wall_feedback(modifier)
    local registration = modifier and modifier.wall_feedback_registration
    if not registration then return end
    local unit, state = registration.unit, registration.state
    if valid(unit) and unit.survival_shared_wall_sound_owner == modifier then
        unit.survival_shared_wall_sound_owner = nil
    end
    modifier.wall_feedback_registration = nil
    state.counters.unregistered = state.counters.unregistered + 1
    state.counters.active_shared = math.max(0, state.counters.active_shared - 1)
end

function M.route_wall_feedback(holder, name, params)
    if not IsServer() or not params then return false end
    local unit = name == "OnAttackLanded" and params.target or params.unit
    local owner = unit and unit.survival_shared_wall_sound_owner
    if not owner or not valid(unit) or owner.shared_wall_feedback_observer ~= true
        or owner.wall_feedback_destroyed or owner.IsNull and owner:IsNull() then return false end
    local registration = owner.wall_feedback_registration
    local mode = current_world()
    if not registration or registration.unit ~= unit or registration.world ~= mode
        or not M.is_authoritative(holder) or not wall_carrier_ready(mode)
        or not owner.GetParent or owner:GetParent() ~= unit then return false end
    -- Existing engine-cached shared declarations remain live after probe off.
    -- Do not apply tower attacker/team/tree eligibility to wall receiver hits.
    local methods = _G.modifier_building_damage_sound
    local callback = methods and methods[name == "OnAttackLanded" and "HandleAttackLanded" or "HandleTakeDamage"]
    if not callback then return false end
    local counters = registration.state.counters
    if name == "OnAttackLanded" then
        counters.landed_matched = counters.landed_matched + 1
    else
        counters.damage_matched = counters.damage_matched + 1
        if (tonumber(params.damage) or 0) > 0 then counters.damage_positive = counters.damage_positive + 1 end
    end
    callback(owner, params)
    return true
end

function M.count_wall_feedback_event(holder, name)
    if _G.SURVIVAL_SHARED_WALL_FEEDBACK_PROBE ~= true or not M.is_authoritative(holder) then return end
    local state = wall_state(current_world(), false)
    if not state or not state.enabled then return end
    local key = name == "OnAttackLanded" and "landed_seen" or "damage_seen"
    state.counters[key] = state.counters[key] + 1
end

function M.wall_feedback_snapshot()
    local mode = current_world()
    local state = wall_state(mode, false)
    local result = { enabled = M.wall_feedback_probe_enabled(), carrier_ready = wall_carrier_ready(mode), counters = {} }
    if state then for key, value in pairs(state.counters) do result.counters[key] = value end end
    return result
end

-- This optional receiver reuses the carrier's existing native OnAttack slot.
-- Its capability marker is written only by a fresh native OnCreated callback.
local function corrosive_state(mode, create)
    if not mode then return nil end
    local state = mode[CORROSIVE_STATE_KEY]
    if not state and create then
        state = { enabled = false, counters = {
            registered = 0, active_shared = 0, unregistered = 0,
            attack_seen = 0, attack_matched = 0, record_present = 0,
            record_missing = 0, duplicate_records = 0,
            armor_reduction_calls = 0, registration_failed = 0,
        } }
        mode[CORROSIVE_STATE_KEY] = state
    end
    return state
end

local function corrosive_carrier_ready(mode)
    local holder = mode and mode[HOLDER_KEY]
    return installed(holder) and holder.survival_corrosive_shield_observer_version == 1
end

function M.set_corrosive_shield_probe(enabled)
    local mode = current_world()
    if not enabled then
        _G.SURVIVAL_SHARED_CORROSIVE_SHIELD_PROBE = false
        local state = corrosive_state(mode, false)
        if state then state.enabled = false end
        return true
    end
    local isolation = _G.SURVIVAL_REAL_GAME_STRESS_ISOLATION
    if not IsServer or not IsServer() or not IsInToolsMode or not IsInToolsMode()
        or not GetMapName or GetMapName() ~= "template_map" or not mode
        or not isolation or isolation.mode ~= mode then return false end
    corrosive_state(mode, true).enabled = true
    _G.SURVIVAL_SHARED_CORROSIVE_SHIELD_PROBE = true
    return true
end

function M.corrosive_shield_probe_enabled()
    if _G.SURVIVAL_SHARED_CORROSIVE_SHIELD_PROBE ~= true
        or not IsServer or not IsServer() or not IsInToolsMode or not IsInToolsMode()
        or not GetMapName or GetMapName() ~= "template_map" then return false end
    local mode = current_world()
    local isolation = _G.SURVIVAL_REAL_GAME_STRESS_ISOLATION
    local state = corrosive_state(mode, false)
    return mode ~= nil and isolation and isolation.mode == mode
        and state ~= nil and state.enabled == true or false
end

function M.choose_corrosive_shield(unit)
    if not M.corrosive_shield_probe_enabled() then return nil end
    -- Unknown/native hero roles retain their original declaration. Classification
    -- is admission-only; an already registered receiver never changes its mode.
    local ok, eligible = pcall(function()
        return valid(unit) and type(unit.GetClassname) == "function"
            and unit:GetClassname() == "npc_dota_creature"
            and type(unit.IsRealHero) == "function" and unit:IsRealHero() == false
            and (unit.survival_is_wave_monster == true
                or unit.survival_is_challenge_monster == true)
    end)
    local mode = current_world()
    return ok and eligible and corrosive_carrier_ready(mode) and mode or nil
end

function M.register_corrosive_shield(unit, modifier, declared_world)
    local mode = current_world()
    local state = corrosive_state(declared_world, false)
    -- Disabling admission between first Declare and OnCreated cannot undo an
    -- engine-cached empty event list. Preserve the committed route after off.
    if not declared_world or mode ~= declared_world or not valid(unit) or not modifier
        or modifier.shared_corrosive_shield_observer ~= true
        or modifier.IsNull and modifier:IsNull() or not corrosive_carrier_ready(mode)
        or not state then
        if state then state.counters.registration_failed = state.counters.registration_failed + 1 end
        return false
    end
    if modifier.corrosive_shield_registration then return true end
    unit.survival_shared_corrosive_shield_owner = modifier
    modifier.corrosive_shield_registration = { unit = unit, world = mode, state = state }
    state.counters.registered = state.counters.registered + 1
    state.counters.active_shared = state.counters.active_shared + 1
    return true
end

function M.unregister_corrosive_shield(modifier)
    local registration = modifier and modifier.corrosive_shield_registration
    if not registration then return end
    local unit, state = registration.unit, registration.state
    if valid(unit) and unit.survival_shared_corrosive_shield_owner == modifier then
        unit.survival_shared_corrosive_shield_owner = nil
    end
    modifier.corrosive_shield_registration = nil
    state.counters.unregistered = state.counters.unregistered + 1
    state.counters.active_shared = math.max(0, state.counters.active_shared - 1)
end

function M.count_corrosive_shield_event(holder)
    if _G.SURVIVAL_SHARED_CORROSIVE_SHIELD_PROBE ~= true
        or not M.is_authoritative(holder) then return end
    local state = corrosive_state(current_world(), false)
    if state and state.enabled then state.counters.attack_seen = state.counters.attack_seen + 1 end
end

function M.route_corrosive_shield(holder, params)
    if not IsServer() or not params then return false end
    local unit = params.attacker
    local owner = unit and unit.survival_shared_corrosive_shield_owner
    if not owner or not valid(unit) or owner.shared_corrosive_shield_observer ~= true
        or owner.corrosive_shield_destroyed or owner.IsNull and owner:IsNull() then return false end
    local registration = owner.corrosive_shield_registration
    local mode = current_world()
    if not registration or registration.unit ~= unit or registration.world ~= mode
        or not M.is_authoritative(holder) or not corrosive_carrier_ready(mode)
        or not owner.GetParent or owner:GetParent() ~= unit then return false end
    local methods = _G.modifier_rogue_corrosive_shield_attack
    local callback = methods and methods.HandleAttack
    if type(callback) ~= "function" then return false end
    local counters = registration.state.counters
    counters.attack_matched = counters.attack_matched + 1
    local key = tonumber(params.record) ~= nil and "record_present" or "record_missing"
    counters[key] = counters[key] + 1
    callback(owner, params)
    return true
end

function M.corrosive_shield_snapshot()
    local mode = current_world()
    local state = corrosive_state(mode, false)
    local result = { enabled = M.corrosive_shield_probe_enabled(),
        carrier_ready = corrosive_carrier_ready(mode), counters = {},
        count_definitions = {
            attack_seen = "authoritative global OnAttack while admission enabled",
            attack_matched = "registered attacker route, including duplicate/invalid target callbacks; survives off",
            armor_reduction_calls = "actual AddArmorReduction calls, not proof of a positive armor delta",
        } }
    if state then for key, value in pairs(state.counters) do result.counters[key] = value end end
    return result
end

-- The existing global OnAttack already contains a native release record. It
-- is a safer pairing source than OnAttackStart, whose native params may not
-- contain that record. This route never calls tower effects or emits damage.
function M.route_enemy_fired(holder, params)
    if _G.SURVIVAL_RANGED_STATIONARY_PROBE~=true or not IsServer or not IsServer()
        or not IsInToolsMode or not IsInToolsMode() or not params
        or not M.is_authoritative(holder) then return false end
    local unit=params.attacker
    if not valid(unit) or unit.survival_is_wave_monster~=true
        or type(unit.GetClassname)~="function" or unit:GetClassname()~="npc_dota_creature" then return false end
    local owner=unit.survival_enemy_attack_owner
    if not owner or owner.shared_attack_observer~=true
        or owner.IsNull and owner:IsNull()
        or type(owner.GetParent)~="function" or owner:GetParent()~=unit then return false end
    local probe=require("systems/enemy_ranged_stationary")
    if not probe.enabled() then return false end
    local methods=_G.modifier_enemy_wall_ai
    if not methods or type(methods.HandleAttackFired)~="function" then return false end
    methods.HandleAttackFired(owner,params)
    return true
end

function M.can_route_auto_attack()
    local mode = current_world()
    local holder = mode and mode[HOLDER_KEY]
    -- Only the real modifier's creation callback advertises its native route.
    -- Reloading this Lua service cannot upgrade an existing engine-cached holder.
    return mode ~= nil and installed(holder)
        and holder.survival_tower_auto_attack_observer_version == 1 or false
end

function M.register_auto_attack(unit, modifier)
    if not valid(unit) or not modifier or (modifier.IsNull and modifier:IsNull())
        or not M.can_route_auto_attack() then return false end
    -- A targeting-only tower needs no attack-effects modifier to receive the
    -- same native events. Keep its current owner on the attacker itself.
    unit.survival_tower_auto_attack_owner = modifier
    return true
end

function M.unregister_auto_attack(unit, modifier)
    if valid(unit) and unit.survival_tower_auto_attack_owner == modifier then
        unit.survival_tower_auto_attack_owner = nil
    end
end

function M.init()
    local current = current_world()
    if not current then return false end
    -- Reuse this GameMode's exact entity across module reloads. Do not recover
    -- a previous map's entity by index, and do not trust an empty thinker.
    if installed(current[HOLDER_KEY]) then return true end
    current[HOLDER_KEY] = nil
    local ok, unit = pcall(function()
        LinkLuaModifier(NAME, "modifiers/modifier_tower_damage_observer", LUA_MODIFIER_MOTION_NONE)
        return CreateModifierThinker(nil, nil, NAME, {}, Vector(0, 0, -10000), DOTA_TEAM_NEUTRALS, false)
    end)
    if ok and installed(unit) and current_world() == current then
        current[HOLDER_KEY] = unit
        return true
    end
    if ok and valid(unit) and type(UTIL_Remove) == "function" then pcall(UTIL_Remove, unit) end
    print("[TowerDamageObserver] unavailable; retaining per-tower native damage callbacks")
    return false
end
return M
