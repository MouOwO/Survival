local event_bus = require("core/event_bus")
local events = require("core/events")
local combat_events = require("combat/combat_events")
local scheduler = require("core/scheduler")
local runtime_config = require("config/generated/blademaster_exclusive_runtime")
local phase_guard = require("systems/gameplay_phase_guard")
local hero_cosmetic_service = require("systems/hero_cosmetic_service")
local summon_attack_rate = require("systems/hero_summon_attack_rate")
local stat_projection = require("combat/endless_stat_projection")
local armor_balance = require("config/armor_balance")
local destination_validation = require("systems/destination_validation_service")

local M = {}
local states = {}
local sequence = 0
local storms = {}
local visual_casters = {}
local wall_by_player = {}
local create_clone

local Q_SKILL = "skill_blademaster_exclusive"
local W_SKILL = "skill_blademaster_agility"
local R_SKILL = "skill_blademaster_mobility"
local Q_ABILITY = "ability_survival_blademaster_exclusive"
local E_ABILITY = "ability_survival_blademaster_swiftness"
local Q_VISUAL_UNIT = "npc_dota_hero_legion_commander"
local Q_VISUAL_ABILITY = "legion_commander_overwhelming_odds"
local E_VISUAL_UNIT = "npc_dota_hero_juggernaut"
local E_VISUAL_ABILITY = "juggernaut_blade_fury"

local function row()
    return runtime_config.by_id.blademaster_exclusive or {}
end

local function valid(unit)
    return unit and not unit:IsNull()
end

local function alive(unit)
    return valid(unit) and unit.IsAlive and unit:IsAlive()
end

local function read(unit, method, ...)
    if not valid(unit) or type(unit[method]) ~= "function" then return nil end
    local ok, value = pcall(unit[method], unit, ...)
    return ok and value or nil
end

local function distance_squared(left, right)
    local dx, dy = left.x - right.x, left.y - right.y
    return dx * dx + dy * dy
end

local function skill_active(player_id, skill_id)
    local result = event_bus.request(events.HERO_SKILL_STATE_GET_REQUEST, {
        player_id = player_id,
    })
    for _, skill in ipairs(result and result.snapshot
            and result.snapshot.skills or {}) do
        if skill.skill_id == skill_id then
            return skill.locked ~= 1 and (tonumber(skill.level) or 0) > 0
        end
    end
    return false
end

local function stats(player_id)
    local result = event_bus.request(events.HERO_COMBAT_STATS_GET_REQUEST, {
        player_id = player_id,
    })
    return result and result.snapshot or {}
end

local function state(player_id)
    states[player_id] = states[player_id] or {
        attack_pct = 0,
        clone = nil,
        owned_clones = {},
        clone_respawning = false,
        growth_started = false,
    }
    return states[player_id]
end

local function all_attributes(snapshot)
    return math.max(0, tonumber(snapshot.strength) or 0)
        + math.max(0, tonumber(snapshot.agility) or 0)
        + math.max(0, tonumber(snapshot.intellect) or 0)
end

local function ability(unit, name)
    return valid(unit) and unit:FindAbilityByName(name) or nil
end

local function remove_visual_caster(unit)
    if not unit then return end
    local visual = visual_casters[unit]
    visual_casters[unit] = nil
    if visual and visual.task then scheduler.cancel(visual.task) end
    if not valid(unit) then return end
    unit.survival_blademaster_visual_caster = nil
    if type(UTIL_Remove) == "function" then
        UTIL_Remove(unit)
    elseif unit.RemoveSelf then
        unit:RemoveSelf()
    end
end

local function remove_visual_casters_for_owner(owner)
    local pending = {}
    for caster, visual in pairs(visual_casters) do
        if owner == nil or visual.owner == owner then
            pending[#pending + 1] = caster
        end
    end
    for _, caster in ipairs(pending) do
        remove_visual_caster(caster)
    end
end

local function hide_unit_and_wearables(unit)
    if not valid(unit) then return end
    unit:AddNoDraw()
    if not unit.FirstMoveChild then return end
    local child = unit:FirstMoveChild()
    while valid(child) do
        if child.AddNoDraw then child:AddNoDraw() end
        child = child.NextMovePeer and child:NextMovePeer() or nil
    end
end

local function create_visual_caster(unit_name, position, owner, hidden)
    if not position or not alive(owner) then return nil end
    local unit = CreateUnitByName(unit_name, position, false,
        owner, owner, owner:GetTeamNumber())
    if not valid(unit) then return nil end
    unit.survival_visual_only = true
    unit.survival_blademaster_visual_caster = true
    unit:SetControllableByPlayer(owner:GetPlayerOwnerID(), false)
    unit:SetAttackCapability(DOTA_UNIT_CAP_NO_ATTACK)
    unit:SetHullRadius(0)
    if unit.SetDayTimeVisionRange then unit:SetDayTimeVisionRange(0) end
    if unit.SetNightTimeVisionRange then unit:SetNightTimeVisionRange(0) end
    unit:AddNewModifier(unit, nil, "modifier_invulnerable", {})
    unit:AddNewModifier(unit, nil, "modifier_phased", {})
    if hidden then hide_unit_and_wearables(unit) end
    visual_casters[unit] = { owner = owner, player_id = owner:GetPlayerOwnerID() }
    return unit
end

local function native_ability(unit, ability_name)
    if not valid(unit) then return nil end
    local native = unit:FindAbilityByName(ability_name)
        or unit:AddAbility(ability_name)
    if native then
        native:SetLevel(1)
        native:SetHidden(false)
        native:SetActivated(true)
    end
    return native
end

local function q_impact_visual(position, owner, player_id)
    -- A point-target native ability must enter the engine order path. Calling
    -- CastAbilityOnPosition on a non-controllable temporary hero can animate
    -- without executing the native ability effect in Workshop Tools.
    local caster = create_visual_caster(Q_VISUAL_UNIT, position, owner, false)
    local native = native_ability(caster, Q_VISUAL_ABILITY)
    if not native then
        remove_visual_caster(caster)
        return nil
    end
    if ExecuteOrderFromTable and DOTA_UNIT_ORDER_CAST_POSITION then
        ExecuteOrderFromTable({
            UnitIndex = caster:entindex(),
            OrderType = DOTA_UNIT_ORDER_CAST_POSITION,
            AbilityIndex = native:entindex(),
            Position = position,
            Queue = false,
        })
    else
        caster:CastAbilityOnPosition(position, native, player_id)
    end
    hide_unit_and_wearables(caster)
    visual_casters[caster].task = scheduler.after(math.max(1, native:GetCastPoint() + 1), function()
        remove_visual_caster(caster)
    end, "blademaster_q_visual:" .. tostring(caster:entindex()))
    return caster
end

local function create_storm_visual(position, owner, player_id)
    local caster = create_visual_caster(E_VISUAL_UNIT, position, owner, false)
    local native = native_ability(caster, E_VISUAL_ABILITY)
    if not native then
        remove_visual_caster(caster)
        return nil
    end
    caster:CastAbilityNoTarget(native, player_id)
    return caster
end

local function deal(player_id, attacker, target, ability_name, damage, source)
    sequence = sequence + 1
    return event_bus.request(combat_events.DEAL_REQUEST, {
        transaction_id = string.format("blademaster:%s:%d:%d",
            source, player_id, sequence),
        attacker = attacker,
        victim = target,
        ability = ability(attacker, ability_name),
        source_kind = "ability",
        base_damage = math.max(0, tonumber(damage) or 0),
        damage_type = DAMAGE_TYPE_PURE,
        can_crit = false,
        tags = {
            blademaster_exclusive = true,
            source = source,
            non_recursive = true,
        },
    })
end

local function replicate_q_damage(player_id, attacker, target, final_damage)
    local damage = math.max(0, tonumber(final_damage) or 0)
    if damage <= 0 then return false end
    -- The confirmed critical hit may already have killed its primary target.
    -- Its still-valid corpse supplies the impact point; living nearby enemies
    -- receive the same Q copy as when the primary survives.
    local position = target:GetAbsOrigin()
    q_impact_visual(position, attacker, player_id)
    for _, enemy in ipairs(FindUnitsInRadius(
        attacker:GetTeamNumber(), position, nil,
        math.max(1, tonumber(row().q_radius) or 600),
        DOTA_UNIT_TARGET_TEAM_ENEMY,
        DOTA_UNIT_TARGET_HERO + DOTA_UNIT_TARGET_BASIC,
        DOTA_UNIT_TARGET_FLAG_MAGIC_IMMUNE_ENEMIES,
        FIND_ANY_ORDER, false) or {}) do
        if alive(enemy) then
            deal(player_id, attacker, enemy, Q_ABILITY, damage, "q_copy")
        end
    end
    return true
end

local function storm_tick(id)
    local storm = storms[id]
    if not storm or not alive(storm.attacker)
        or GameRules:GetGameTime() >= storm.expires_at then
        if storm then remove_visual_caster(storm.visual_caster) end
        storms[id] = nil
        return false
    end
    local snapshot = storm.snapshot
    local damage = all_attributes(snapshot)
        * math.max(0, tonumber(row().e_attribute_multiplier) or 0)
    for _, enemy in ipairs(FindUnitsInRadius(
        storm.attacker:GetTeamNumber(), storm.position, nil,
        math.max(1, tonumber(row().e_radius) or 600),
        DOTA_UNIT_TARGET_TEAM_ENEMY,
        DOTA_UNIT_TARGET_HERO + DOTA_UNIT_TARGET_BASIC,
        DOTA_UNIT_TARGET_FLAG_MAGIC_IMMUNE_ENEMIES,
        FIND_ANY_ORDER, false) or {}) do
        if alive(enemy) then
            deal(storm.player_id, storm.attacker, enemy, E_ABILITY, damage, "e_tick")
        end
    end
    return true
end

local function start_storm(payload)
    local id = tostring(payload.player_id) .. ":" .. tostring(payload.attacker:entindex())
    if storms[id] then return false end
    local duration = math.max(0.1, tonumber(row().e_duration) or 3)
    storms[id] = {
        player_id = payload.player_id,
        attacker = payload.attacker,
        position = payload.target:GetAbsOrigin(),
        snapshot = stats(payload.player_id),
        expires_at = GameRules:GetGameTime() + duration,
    }
    storms[id].visual_caster = create_storm_visual(
        storms[id].position, payload.attacker, payload.player_id
    )
    local storm = storms[id]
    scheduler.every(math.max(0.1, tonumber(row().e_tick_interval) or 1),
        function()
            if storms[id] ~= storm then return false end
            return storm_tick(id)
        end, "blademaster_storm:" .. id)
    return true
end

local function on_attack_landed(payload)
    local attacker = payload and payload.attacker
    if not alive(attacker) or payload.is_main_attack ~= true
        or attacker.survival_hero_id ~= "hero_blademaster"
        or attacker.survival_blademaster_clone == true
        or payload.is_multishot_secondary == true then return end
    local player_id = tonumber(payload.player_id)
    if player_id == nil then return end
    if skill_active(player_id, "skill_blademaster_swiftness")
        and RollPercentage(tonumber(row().e_proc_chance_pct) or 0) then
        start_storm({ player_id = player_id, attacker = attacker, target = payload.target })
    end
end

local function sync_clone_appearance(current)
    if not current or not alive(current.clone) or not valid(current.source_hero) then return end
    hero_cosmetic_service.sync_appearance(current.clone, current.source_hero)
end

local function q_replicate(payload)
    if not payload or tonumber(payload.player_id) == nil
        or not skill_active(payload.player_id, Q_SKILL)
        or payload.critical ~= true
        or payload.is_main_attack ~= true
        or payload.blademaster_secondary == true then return false end
    local target, attacker = payload.target, payload.attacker
    if not alive(attacker) or not valid(target)
        or attacker.survival_hero_id ~= "hero_blademaster"
        or attacker.survival_blademaster_clone == true
        or target:GetTeamNumber() == attacker:GetTeamNumber() then return false end
    return replicate_q_damage(payload.player_id, attacker, target, payload.final_damage)
end

function M.trigger_clone_q(player_id, clone, target, final_damage)
    player_id = tonumber(player_id)
    local current = player_id and states[player_id]
    if not current or current.clone ~= clone or not alive(clone) or not valid(target)
        or clone.survival_blademaster_clone ~= true
        or target:GetTeamNumber() == clone:GetTeamNumber()
        or not skill_active(player_id, Q_SKILL) then return false end
    return replicate_q_damage(player_id, clone, target, final_damage)
end

local function sync_clone_stats(player_id, current, snapshot, initial)
    if not current or not alive(current.clone) or not valid(current.source_hero) then return end
    local clone, hero = current.clone, current.source_hero
    local summoned = event_bus.request(events.HERO_SUMMON_GET_REQUEST, { player_id = player_id })
    if not summoned or summoned.unit ~= hero then return end
    snapshot = snapshot or stats(player_id)
    -- Snapshot publication can synchronously delete or replace this hero.
    if states[player_id] ~= current or current.clone ~= clone
        or not alive(clone) or not valid(hero) then return end
    if snapshot.entindex ~= nil
        and tonumber(snapshot.entindex) ~= hero:entindex() then return end
    local previous = clone.survival_exclusive_combat_stats or {}
    local attack_min = math.max(1, tonumber(snapshot.attack_min) or 1)
    local attack_max = math.max(attack_min, tonumber(snapshot.attack_max) or attack_min)
    local max_health = math.max(1, tonumber(snapshot.max_health)
        or tonumber(read(hero, "GetMaxHealth")) or 1)
    local projected = stat_projection.prepare(clone, { attack = attack_max, health = max_health })
    local native_min = math.max(1, math.floor(attack_min / clone.survival_endless_attack_scale))
    local native_max = math.max(native_min, math.floor(projected.attack))
    if previous.attack_min ~= native_min then clone:SetBaseDamageMin(native_min) end
    if previous.attack_max ~= native_max then clone:SetBaseDamageMax(native_max) end
    local attack_speed = summon_attack_rate.apply(clone, hero, snapshot.attack_speed)
    local armor = tonumber(read(hero, "GetPhysicalArmorValue", false))
        or tonumber(snapshot.runtime_armor)
        or armor_balance.from_war3(snapshot.armor)
    if previous.armor ~= armor and clone.SetPhysicalArmorBaseValue then
        clone:SetPhysicalArmorBaseValue(armor)
    end
    local attack_range = math.max(1, tonumber(read(hero, "Script_GetAttackRange"))
        or tonumber(hero.survival_attack_range) or tonumber(snapshot.attack_range) or 800)
    if previous.attack_range ~= attack_range then
        if clone.Script_SetAttackRange then clone:Script_SetAttackRange(attack_range) end
        if clone.SetAcquisitionRange then clone:SetAcquisitionRange(attack_range + 200) end
    end
    local range_modifier = clone:FindModifierByName("modifier_survival_hero_attack_range")
    if not range_modifier then
        clone:AddNewModifier(clone, nil, "modifier_survival_hero_attack_range", {
            attack_range = attack_range,
        })
    elseif previous.attack_range ~= attack_range and range_modifier.SetAttackRange then
        range_modifier:SetAttackRange(attack_range)
    end
    clone.survival_attack_range = attack_range
    local move_speed = tonumber(read(hero, "GetIdealSpeed"))
        or tonumber(read(hero, "GetBaseMoveSpeed"))
    if move_speed and move_speed > 0 and previous.move_speed ~= move_speed
        and clone.SetBaseMoveSpeed then clone:SetBaseMoveSpeed(move_speed) end
    local maximum = math.max(1, math.floor(projected.health))
    if previous.max_health ~= maximum and clone.SetBaseMaxHealth and clone.SetMaxHealth then
        local fraction = 1
        if not initial and clone.GetHealth and clone.GetMaxHealth then
            fraction = math.max(0, math.min(1, clone:GetHealth() / math.max(1, clone:GetMaxHealth())))
        end
        clone:SetBaseMaxHealth(maximum)
        clone:SetMaxHealth(maximum)
        clone:SetHealth(math.max(1, math.min(maximum, math.floor(maximum * fraction))))
    end
    clone.survival_exclusive_combat_stats = {
        attack_min = native_min, attack_max = native_max, max_health = maximum,
        armor = armor, attack_range = attack_range, move_speed = move_speed,
    }
    clone.survival_strength = tonumber(snapshot.strength) or 0
    clone.survival_agility = tonumber(snapshot.agility) or 0
    clone.survival_intellect = tonumber(snapshot.intellect) or 0
    clone.survival_critical_chance_pct = math.max(0, tonumber(snapshot.critical_chance_pct) or 0)
    clone.survival_critical_damage_pct = math.max(100, tonumber(snapshot.critical_damage_pct) or 200)
        + math.max(0, tonumber(row().w_clone_critical_damage_bonus_pct) or 0)
    local inherited = {}
    for name, value in pairs(snapshot) do inherited[name] = value end
    inherited.attack_speed = attack_speed
    inherited.critical_chance_pct = clone.survival_critical_chance_pct
    inherited.critical_damage_pct = clone.survival_critical_damage_pct
    local modifier = clone:FindModifierByName("modifier_blademaster_clone")
    if modifier and modifier.SetCombatSnapshot then modifier:SetCombatSnapshot(inherited) end
    local hud = {
        attack_min = attack_min, attack_max = attack_max, attack_speed = attack_speed,
        strength = clone.survival_strength, agility = clone.survival_agility,
        intellect = clone.survival_intellect, max_health = max_health, armor = armor,
    }
    local changed = false
    for name, value in pairs(hud) do
        if (clone.survival_exclusive_stat_snapshot or {})[name] ~= value then changed = true; break end
    end
    clone.survival_exclusive_stat_snapshot = hud
    if changed then
        event_bus.emit(events.UNIT_COMBAT_STATS_CHANGED, {
            unit = clone, entindex = clone:entindex(), reason = "blademaster_clone_stats_changed",
        })
    end
end

local function on_combat_stats_changed(payload)
    local player_id = tonumber(payload and payload.player_id)
    if player_id == nil then return end
    sync_clone_stats(player_id, states[player_id], payload.snapshot)
end

local function on_cosmetics_changed(payload)
    local player_id = tonumber(payload and payload.player_id)
    local current = player_id and states[player_id]
    if not current or current.source_hero ~= payload.unit then return end
    sync_clone_appearance(current)
end

local function guard_point(player_id, current)
    local fallback = current.guard_origin
    local wall = wall_by_player[player_id]
    if not alive(wall) or not fallback then return fallback end
    local position = wall:GetAbsOrigin()
    local dx, dy = fallback.x - position.x, fallback.y - position.y
    local length = math.sqrt(dx * dx + dy * dy)
    if length < 1 then dx, dy, length = 1, 0, 1 end
    local point = Vector(position.x + dx / length * 192,
        position.y + dy / length * 192, position.z)
    if destination_validation.validate(point, current.clone or current.source_hero) then return point end
    return fallback
end

local function guard_clone(player_id, current)
    if phase_guard.post_clear_frozen() or not current or not alive(current.clone) then return end
    local clone = current.clone
    local point = guard_point(player_id, current)
    if not point or not ExecuteOrderFromTable or not FindUnitsInRadius then return end
    if read(clone, "IsChanneling") or read(clone, "IsStunned")
        or read(clone, "IsCommandRestricted") then return end
    local range = tonumber(clone.survival_attack_range) or 800
    local leash = math.max(1000, range + 200)
    local origin = clone:GetAbsOrigin()
    local function attackable(target)
        if not alive(target) or target:GetTeamNumber() == clone:GetTeamNumber()
            or target.survival_visual_only == true or read(target, "IsInvulnerable")
            or read(target, "IsAttackImmune") then return false end
        local position = target:GetAbsOrigin()
        if distance_squared(position, point) > leash * leash then return false end
        -- An enemy beyond the walkable hero area can still be hit from range,
        -- but must never make the guardian chase through a forbidden boundary.
        return distance_squared(position, origin) <= range * range
            or destination_validation.validate(position, clone)
    end
    if distance_squared(origin, point) <= leash * leash then
        local target = read(clone, "GetAttackTarget")
        if attackable(target) then
            current.guard_target, current.guard_returning = target, nil
            return
        end
        if attackable(current.guard_target) and read(clone, "IsIdle") ~= true then return end
        for _, enemy in ipairs(FindUnitsInRadius(clone:GetTeamNumber(), point, nil, leash,
            DOTA_UNIT_TARGET_TEAM_ENEMY, DOTA_UNIT_TARGET_HERO + DOTA_UNIT_TARGET_BASIC,
            DOTA_UNIT_TARGET_FLAG_MAGIC_IMMUNE_ENEMIES, FIND_CLOSEST or FIND_ANY_ORDER, false) or {}) do
            if attackable(enemy) then
                current.guard_target, current.guard_returning = enemy, nil
                ExecuteOrderFromTable({ UnitIndex = clone:entindex(),
                    OrderType = DOTA_UNIT_ORDER_ATTACK_TARGET, TargetIndex = enemy:entindex(), Queue = false })
                return
            end
        end
    end
    local had_target = current.guard_target ~= nil or read(clone, "GetAttackTarget") ~= nil
    current.guard_target = nil
    if distance_squared(origin, point) <= 192 * 192 then
        if had_target and clone.Stop then clone:Stop() end
        current.guard_returning = nil
        return
    end
    if current.guard_returning and distance_squared(current.guard_returning, point) < 16 * 16
        and read(clone, "IsIdle") ~= true then return end
    if not destination_validation.validate(point, clone) then return end
    current.guard_returning = point
    ExecuteOrderFromTable({ UnitIndex = clone:entindex(), OrderType = DOTA_UNIT_ORDER_MOVE_TO_POSITION,
        Position = point, Queue = false })
end

local function on_building(payload)
    local player_id = tonumber(payload and payload.player_id)
    if player_id and payload.building_id == "wall" and valid(payload.unit) then
        wall_by_player[player_id] = payload.unit
    end
end

local function on_building_destroyed(payload)
    local player_id = tonumber(payload and payload.player_id)
    if player_id and payload.building_id == "wall" and wall_by_player[player_id] == payload.unit then
        wall_by_player[player_id] = nil
    end
end

local function prepare_combat_clone(clone, player_id)
    -- The W guardian is a regular attacker. Native Blade Fury belongs only to
    -- the separate, non-attacking E visual caster and must not remain on W.
    local remove = {}
    for index = 0, math.max(0, tonumber(read(clone, "GetAbilityCount")) or 0) - 1 do
        local native = clone:GetAbilityByIndex(index)
        if native and not native:IsNull() and native:GetAbilityName() ~= Q_ABILITY then
            remove[#remove + 1] = native:GetAbilityName()
        end
    end
    for _, name in ipairs(remove) do clone:RemoveAbility(name) end
    local q_ability = clone:FindAbilityByName(Q_ABILITY) or clone:AddAbility(Q_ABILITY)
    if q_ability then
        q_ability:SetLevel(1)
        if q_ability.SetHidden then q_ability:SetHidden(false) end
        if q_ability.SetActivated then q_ability:SetActivated(true) end
    end
    if clone.SetAttackCapability then clone:SetAttackCapability(DOTA_UNIT_CAP_MELEE_ATTACK) end
    if clone.SetMoveCapability then clone:SetMoveCapability(DOTA_UNIT_CAP_MOVE_GROUND) end
    if clone.SetIdleAcquire then clone:SetIdleAcquire(true) end
    for _, setter in ipairs({ "SetBaseStrength", "SetBaseAgility", "SetBaseIntellect",
        "SetStrengthGain", "SetAgilityGain", "SetIntellectGain" }) do
        if clone[setter] then clone[setter](clone, 0) end
    end
    if clone.CalculateStatBonus then clone:CalculateStatBonus(true) end
    clone:AddNewModifier(clone, nil, "modifier_blademaster_clone", { player_id = player_id })
end

create_clone = function(player_id)
    local current = state(player_id)
    local summoned = event_bus.request(events.HERO_SUMMON_GET_REQUEST, { player_id = player_id })
    local hero = summoned and summoned.unit
    if alive(current.clone) or not alive(hero)
        or hero.survival_hero_id ~= "hero_blademaster"
        or not skill_active(player_id, W_SKILL) then return nil end
    current.source_hero = hero
    if not valid(wall_by_player[player_id]) then
        local buildings = event_bus.request(events.BUILDING_LIST_REQUEST, { player_id = player_id })
        for _, building in ipairs(buildings and buildings.buildings or {}) do on_building(building) end
    end
    current.guard_origin = current.guard_origin or hero:GetAbsOrigin()
    local position = guard_point(player_id, current)
    if RandomVector then
        local offset = RandomVector(128)
        local candidate = Vector(position.x + offset.x, position.y + offset.y, position.z)
        if destination_validation.validate(candidate, hero) then position = candidate end
    end
    local clone = CreateUnitByName(hero:GetUnitName(), position, true,
        hero, hero, hero:GetTeamNumber())
    if not valid(clone) then return nil end
    clone:SetPlayerID(player_id)
    clone:SetControllableByPlayer(player_id, true)
    clone.survival_blademaster_clone = true
    clone.survival_permanent_summon = true
    clone.survival_exclusive_summon = true
    clone.survival_hero_id = "hero_blademaster"
    clone.survival_display_name = "剑圣幻象"
    prepare_combat_clone(clone, player_id)
    current.clone = clone
    current.owned_clones[clone] = clone:entindex()
    current.clone_respawning = false
    current.guard_target, current.guard_returning = nil, nil
    sync_clone_stats(player_id, current, nil, true)
    if not alive(clone) or states[player_id] ~= current then return nil end
    sync_clone_appearance(current)
    if FindClearSpaceForUnit then FindClearSpaceForUnit(clone, position, true) end
    guard_clone(player_id, current)
    event_bus.emit(events.HERO_CLONE_CREATED, {
        unit = clone, player_id = player_id, team = clone:GetTeamNumber(),
    })
    return clone
end

local function growth_tick(player_id)
    if phase_guard.post_clear_frozen() then return end
    if not skill_active(player_id, R_SKILL) then return end
    state(player_id).attack_pct = state(player_id).attack_pct
        + math.max(0, tonumber(row().r_growth_pct) or 0)
    event_bus.emit(events.BLADEMASTER_BONUS_STATS_CHANGED, {
        player_id = player_id,
        snapshot = { attack_pct = state(player_id).attack_pct },
        reason = "blademaster_r_growth",
    })
end

local function on_entity_killed(payload)
    local victim = payload and payload.victim
    if not valid(victim) then return end
    if victim.survival_blademaster_visual_caster == true then
        remove_visual_caster(victim)
        return
    end
    remove_visual_casters_for_owner(victim)
    if victim.survival_blademaster_clone ~= true then return end
    local player_id = tonumber(victim:GetPlayerOwnerID())
    if player_id == nil then return end
    local current = states[player_id]
    if not current or current.clone ~= victim then return end
    event_bus.emit(events.HERO_CLONE_REMOVED, {
        unit = victim, entindex = victim:entindex(), player_id = player_id,
    })
    current.clone = nil
    if current.clone_respawning or not skill_active(player_id, W_SKILL) then return end
    current.clone_respawning = true
    scheduler.after(1, function()
        if states[player_id] ~= current then return end
        current.clone_respawning = false
        create_clone(player_id)
    end, "blademaster_clone_respawn:" .. tostring(player_id))
end

local function on_hero_removed(payload)
    local player_id = tonumber(payload and payload.player_id)
    if player_id == nil then return end
    local current = states[player_id]
    if current and current.source_hero and payload.unit
        and current.source_hero ~= payload.unit then return end
    states[player_id] = nil
    scheduler.cancel("blademaster_clone_respawn:" .. tostring(player_id))
    for id, storm in pairs(storms) do
        if tonumber(storm.player_id) == player_id then
            storms[id] = nil
            scheduler.cancel("blademaster_storm:" .. id)
            remove_visual_caster(storm.visual_caster)
        end
    end
    local casters = {}
    for caster, visual in pairs(visual_casters) do
        if tonumber(visual.player_id) == player_id then casters[#casters + 1] = caster end
    end
    for _, caster in ipairs(casters) do remove_visual_caster(caster) end
    for clone, entindex in pairs(current and current.owned_clones or {}) do
        event_bus.emit(events.HERO_CLONE_REMOVED, {
            unit = clone, entindex = entindex, player_id = player_id,
        })
        if valid(clone) then
            clone.survival_blademaster_clone = nil
            if clone.AddNoDraw then clone:AddNoDraw() end
        end
        hero_cosmetic_service.clear(clone)
        if valid(clone) then
            if UTIL_Remove then UTIL_Remove(clone)
            elseif clone.RemoveSelf then clone:RemoveSelf() end
        end
    end
end

function M.init()
    remove_visual_casters_for_owner(nil)
    states = {}
    storms = {}
    visual_casters = {}
    wall_by_player = {}
    sequence = 0
    event_bus.handle_request(events.BLADEMASTER_BONUS_STATS_GET_REQUEST,
        function(payload)
            local current = state(tonumber(payload and payload.player_id))
            return { ok = true, snapshot = { attack_pct = current.attack_pct } }
        end)
    event_bus.subscribe(events.HERO_FINAL_CRITICAL_ATTACK_DAMAGE, q_replicate)
    event_bus.subscribe(events.HERO_MAIN_ATTACK_LANDED, on_attack_landed)
    event_bus.subscribe(events.ENGINE_ENTITY_KILLED, on_entity_killed)
    event_bus.subscribe(events.HERO_REMOVED, on_hero_removed)
    event_bus.subscribe(events.HERO_COMBAT_STATS_CHANGED, on_combat_stats_changed)
    event_bus.subscribe(events.HERO_COSMETICS_CHANGED, on_cosmetics_changed)
    event_bus.subscribe(events.BUILDING_CREATED, on_building)
    event_bus.subscribe(events.BUILDING_CHANGED, on_building)
    event_bus.subscribe(events.BUILDING_DESTROYED, on_building_destroyed)
    event_bus.subscribe(events.HERO_SKILL_CHANGED, function(payload)
        local player_id = tonumber(payload and payload.player_id)
        if player_id and skill_active(player_id, W_SKILL) then create_clone(player_id) end
    end)
    scheduler.every(1, function()
        for player_id, current in pairs(states) do
            if not alive(current.clone) and not current.clone_respawning
                and skill_active(player_id, W_SKILL) then create_clone(player_id) end
            sync_clone_stats(player_id, current)
            -- Mirror on lifecycle retries and committed equipment changes;
            -- stat-only events must not rescan every cosmetic control point.
            sync_clone_appearance(current)
            guard_clone(player_id, current)
            for clone, entindex in pairs(current.owned_clones) do
                if not valid(clone) then
                    event_bus.emit(events.HERO_CLONE_REMOVED, {
                        unit = clone, entindex = entindex, player_id = player_id,
                    })
                    hero_cosmetic_service.clear(clone)
                    current.owned_clones[clone] = nil
                end
            end
            if skill_active(player_id, R_SKILL)
                and GameRules:GetGameTime() % math.max(1, tonumber(row().r_growth_interval) or 150) < 1 then
                if not current._growth_second or current._growth_second ~= math.floor(GameRules:GetGameTime()) then
                    current._growth_second = math.floor(GameRules:GetGameTime())
                    growth_tick(player_id)
                end
            end
        end
        return true
    end, "blademaster_growth")
end

M._test = { q_replicate = q_replicate, start_storm = start_storm, growth_tick = growth_tick,
    guard_clone = function(player_id) guard_clone(player_id, states[player_id]) end }
return M
