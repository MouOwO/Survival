local ParticleManager = require("systems/combat_effect_visibility").manager()
local scheduler = require("core/scheduler")
local event_bus = require("core/event_bus")
local events = require("core/events")
local armor_balance = require("config/armor_balance")
local cosmetics = require("systems/hero_cosmetic_service")
local stat_projection = require("combat/endless_stat_projection")
local summon_attack_rate = require("systems/hero_summon_attack_rate")

local M = { runners = {} }
M.sound_service = require("core/sound_service")
local deal_group = nil
local exclusive_summons = {}
local shadow_raze_stacks = {}
local summon_sync_task = nil
local summon_corpses = {}
local corpse_sync_task = nil
local sync_sequence = 0
local service_generation = 0
local CORPSE_VISUAL_SECONDS = 4

local blinding_light_visual = require("systems/keeper_blinding_light_visual")
local COUNTER_HELIX_PARTICLE =
    "particles/units/heroes/hero_axe/axe_attack_blur_counterhelix.vpcf"

local function valid(unit)
    return unit and not unit:IsNull()
end

local function alive(unit)
    return valid(unit) and unit.IsAlive and unit:IsAlive()
end

local function unit_key(unit)
    if not valid(unit) or not unit.entindex then return nil end
    return tostring(unit:entindex())
end

local function game_time()
    return GameRules and GameRules.GetGameTime and GameRules:GetGameTime() or 0
end

local function level_value(definition, field, level, fallback)
    local values = definition[field]
    if type(values) == "table" then
        return tonumber(values[level]) or fallback or 0
    end
    return tonumber(values) or fallback or 0
end

local function base_attack_time(attack_speed)
    attack_speed = tonumber(attack_speed) or 0
    if attack_speed <= 0 or attack_speed ~= attack_speed
        or attack_speed == math.huge then return nil end
    return 1 / attack_speed
end

local function current_world()
    return GameRules and GameRules.GetGameModeEntity
        and GameRules:GetGameModeEntity() or GameRules or _G
end

local function copy_attributes(attributes)
    local result = {}
    for key, value in pairs(attributes or {}) do result[key] = value end
    return result
end

local function current_attack_speed(source, fallback)
    return summon_attack_rate.current(source, fallback)
end

local function enemies_in_radius(attacker, position, radius)
    if not valid(attacker) or not FindUnitsInRadius then return {} end
    return FindUnitsInRadius(
        attacker:GetTeamNumber(), position, nil, math.max(1, radius),
        DOTA_UNIT_TARGET_TEAM_ENEMY,
        DOTA_UNIT_TARGET_HERO + DOTA_UNIT_TARGET_BASIC,
        DOTA_UNIT_TARGET_FLAG_MAGIC_IMMUNE_ENEMIES,
        FIND_CLOSEST, false
    ) or {}
end

local function summon_key(attacker, skill_id)
    local key = unit_key(attacker)
    return key and key .. ":" .. tostring(skill_id) or nil
end

local function dispose_summon(state)
    local unit = state.unit
    -- A retained Lua callback must never hide/remove an entity in a new map.
    if state.world == current_world() and valid(unit) then
        if unit.AddNoDraw then unit:AddNoDraw() end
    end
    if state.world == current_world() and alive(unit) then unit:ForceKill(false) end
    -- Cosmetic ownership uses the exact handle and guards its own world, even
    -- when the engine has already deleted the corpse and entindex is unusable.
    if state.mirror_appearance then cosmetics.clear(unit) end
    if state.world == current_world() and valid(unit) then
        if UTIL_Remove then UTIL_Remove(unit)
        elseif unit.RemoveSelf then unit:RemoveSelf() end
    end
end

local function finish_corpse(state)
    if summon_corpses[state.unit] ~= state then return end
    summon_corpses[state.unit] = nil
    dispose_summon(state)
    if next(summon_corpses) == nil and corpse_sync_task then
        scheduler.cancel(corpse_sync_task)
        corpse_sync_task = nil
    end
end

local function retain_corpse(state)
    state.corpse_expires_at = game_time() + CORPSE_VISUAL_SECONDS
    summon_corpses[state.unit] = state
    if corpse_sync_task then return end
    sync_sequence = sync_sequence + 1
    local task = "hero_exclusive_summon_corpses:" .. tostring(sync_sequence)
    corpse_sync_task = task
    scheduler.every(0.1, function()
        if corpse_sync_task ~= task then return false end
        for _, corpse in pairs(summon_corpses) do
            if corpse.world ~= current_world() or not valid(corpse.unit)
                or game_time() >= corpse.corpse_expires_at then
                finish_corpse(corpse)
            end
        end
        return corpse_sync_task == task and next(summon_corpses) ~= nil
    end, task)
end

local function retire_summon(key, state, immediate)
    if exclusive_summons[key] ~= state then return end
    exclusive_summons[key] = nil
    if state.expiry_task then scheduler.cancel(state.expiry_task) end
    if immediate or not valid(state.unit) or state.world ~= current_world() then
        dispose_summon(state)
    else
        -- Free the combat slot now, but keep bone-merged wearables attached
        -- throughout native death. Clearing them before ForceKill exposes the
        -- default body for the entire death animation.
        if state.mirror_appearance then retain_corpse(state) end
        if alive(state.unit) then state.unit:ForceKill(false) end
    end
    if next(exclusive_summons) == nil and summon_sync_task then
        scheduler.cancel(summon_sync_task)
        summon_sync_task = nil
    end
end

function M.summon_locked(attacker, skill_id)
    local key = summon_key(attacker, skill_id)
    local state = key and exclusive_summons[key] or nil
    if not state then return false end
    if not alive(state.unit) or game_time() >= state.expires_at then
        retire_summon(key, state)
        return false
    end
    return true
end

local function inherited_stats(attributes, definition, level)
    attributes = attributes or {}
    local attack_pct = level_value(
        definition, "attack_inherit_pct", level, 100
    ) / 100
    local attack_speed_pct = level_value(
        definition, "attack_speed_inherit_pct", level, 100
    ) / 100
    local health_pct = level_value(
        definition, "health_inherit_pct", level, 100
    ) / 100
    local armor_pct = level_value(
        definition, "armor_inherit_pct", level, 100
    ) / 100
    local fallback_attack = tonumber(attributes.attack) or 0
    local armor = tonumber(attributes.runtime_armor) or 0
    if attributes.armor_unit == "war3_display"
        and tonumber(attributes.armor) ~= nil then
        armor = armor_balance.from_war3(attributes.armor)
    end
    return {
        attack_min = (tonumber(attributes.attack_min) or fallback_attack)
            * attack_pct,
        attack_max = (tonumber(attributes.attack_max) or fallback_attack)
            * attack_pct,
        attack_speed = (tonumber(attributes.attack_speed) or 0)
            * attack_speed_pct,
        max_health = (tonumber(attributes.max_health) or 1) * health_pct,
        armor = armor * armor_pct,
        strength = tonumber(attributes.strength) or 0,
        agility = tonumber(attributes.agility) or 0,
        intellect = tonumber(attributes.intellect) or 0,
    }
end

local function apply_combat_stats(unit, attributes, definition, level,
        preserve_health)
    if not valid(unit) then return false end
    local stats = inherited_stats(attributes, definition, level)
    local previous = unit.survival_exclusive_combat_stats or {}
    -- Native base damage/health are integers: a logical value above 2^31
    -- becomes negative. Reuse the combat filter's bounded projection and
    -- keep logical stats separately for the HUD and subsequent inheritance.
    stats.attack_min = math.max(1, stats.attack_min)
    stats.attack_max = math.max(stats.attack_min, stats.attack_max)
    local projected = stat_projection.prepare(unit, {
        attack = stats.attack_max, health = math.max(1, stats.max_health),
    })
    local attack_min = math.max(1, math.floor(
        stats.attack_min / unit.survival_endless_attack_scale
    ))
    local attack_max = math.max(attack_min, math.floor(projected.attack))
    if previous.attack_min ~= attack_min then unit:SetBaseDamageMin(attack_min) end
    if previous.attack_max ~= attack_max then unit:SetBaseDamageMax(attack_max) end
    local _, attack_time = summon_attack_rate.apply(unit, nil, stats.attack_speed)
    if previous.armor ~= stats.armor then
        unit:SetPhysicalArmorBaseValue(stats.armor)
    end
    local maximum = math.max(1, math.floor(projected.health))
    -- Polling must not heal a damaged infernal or restart its attack animation.
    -- Only changing the maximum health needs to preserve its current fraction.
    if previous.max_health ~= maximum then
        local health_fraction = 1
        if preserve_health and unit.GetMaxHealth and unit.GetHealth then
            local previous_max = math.max(1, tonumber(unit:GetMaxHealth()) or 1)
            health_fraction = math.max(0, math.min(
                1, (tonumber(unit:GetHealth()) or previous_max) / previous_max
            ))
        end
        unit:SetBaseMaxHealth(maximum)
        unit:SetMaxHealth(maximum)
        unit:SetHealth(math.max(1, math.min(
            maximum, math.floor(maximum * health_fraction)
        )))
    end
    unit.survival_exclusive_combat_stats = {
        attack_min = attack_min, attack_max = attack_max,
        attack_time = attack_time, armor = stats.armor, max_health = maximum,
    }
    local snapshot = {
        attack_min = stats.attack_min, attack_max = stats.attack_max,
        attack_speed = unit.survival_attack_speed or stats.attack_speed,
        strength = stats.strength, agility = stats.agility,
        intellect = stats.intellect,
        max_health = math.max(1, stats.max_health), armor = stats.armor,
    }
    local previous_snapshot = unit.survival_exclusive_stat_snapshot or {}
    local changed = false
    for name, value in pairs(snapshot) do
        if previous_snapshot[name] ~= value then changed = true; break end
    end
    unit.survival_exclusive_stat_snapshot = snapshot
    if changed then
        event_bus.emit(events.UNIT_COMBAT_STATS_CHANGED, {
            entindex = unit:entindex(), unit = unit,
            reason = "exclusive_summon_stats_changed",
        })
    end
    return true
end

local function configure_summon(unit, context)
    unit:SetOwner(context.attacker)
    if unit.SetPlayerID then unit:SetPlayerID(context.player_id) end
    unit:SetControllableByPlayer(context.player_id, true)
end

local function snapshot_matches(state, snapshot)
    return type(snapshot) == "table"
        and tonumber(snapshot.entindex) == state.source_entindex
end

local function sync_summon(key, state, snapshot, initial)
    -- A supplied snapshot is a numeric stat event. Appearance has its own
    -- commit event and lifecycle retry, so attacks must not rescan cosmetics.
    local sync_visual = snapshot == nil or initial == true
    if exclusive_summons[key] ~= state then return false end
    if state.world ~= current_world() or not valid(state.source_attacker) then
        retire_summon(key, state, true)
        return false
    end
    if not alive(state.unit) or game_time() >= state.expires_at then
        retire_summon(key, state)
        return false
    end
    local hero = event_bus.request(events.HERO_SUMMON_GET_REQUEST, {
        player_id = state.player_id,
    })
    if hero and hero.ok and hero.unit and hero.unit ~= state.source_attacker then
        retire_summon(key, state, true)
        return false
    end
    if snapshot == nil then
        local response = event_bus.request(events.HERO_COMBAT_STATS_GET_REQUEST, {
            player_id = state.player_id,
        })
        snapshot = response and response.ok and response.snapshot or nil
    end
    -- Requests can emit a stat-change event themselves; a nested cleanup must
    -- not allow this callback to touch a retired/replaced summon afterwards.
    if exclusive_summons[key] ~= state then return false end
    if snapshot_matches(state, snapshot) then
        state.attributes = copy_attributes(snapshot)
    end
    local attributes = copy_attributes(state.attributes)
    attributes.attack_speed = current_attack_speed(
        state.source_attacker, attributes.attack_speed
    )
    apply_combat_stats(
        state.unit, attributes, state.definition, state.level, initial ~= true
    )
    if sync_visual and state.mirror_appearance then
        cosmetics.sync_appearance(state.unit, state.source_attacker)
    end
    return true
end

local function ensure_summon_sync()
    if summon_sync_task then return end
    sync_sequence = sync_sequence + 1
    local task = "hero_exclusive_summon_sync:" .. tostring(sync_sequence)
    summon_sync_task = task
    scheduler.every(0.1, function()
        if summon_sync_task ~= task then return false end
        for key, state in pairs(exclusive_summons) do sync_summon(key, state) end
        return summon_sync_task == task and next(exclusive_summons) ~= nil
    end, task)
end

local function create_summon(context, definition, unit_name, invulnerable)
    local key = summon_key(context.attacker, context.skill_id)
    if not key or M.summon_locked(context.attacker, context.skill_id) then
        return false
    end
    local duration = level_value(definition, "duration", context.level, 10)
    local position = context.attacker:GetAbsOrigin()
        + context.attacker:GetForwardVector() * 160
    local unit = CreateUnitByName(
        unit_name, position, true, context.attacker, context.attacker,
        context.attacker:GetTeamNumber()
    )
    if not valid(unit) then return false end
    configure_summon(unit, context)
    unit.survival_exclusive_summon = true
    unit.survival_summon_skill_id = context.skill_id
    if invulnerable then
        unit:AddNewModifier(
            context.attacker, nil,
            "modifier_survival_drow_companion_invulnerable", {}
        )
        unit.survival_drow_companion = true
        unit.survival_drow_max_targets = level_value(
            definition, "max_targets", context.level, 5
        )
        unit.survival_drow_attack_range = level_value(
            definition, "attack_range", context.level, 1200
        )
        unit:AddNewModifier(
            unit, nil, "modifier_weapon_attack_tracker",
            { player_id = context.player_id }
        )
    end
    local state = {
        unit = unit,
        expires_at = game_time() + duration,
        player_id = tonumber(context.player_id),
        definition = definition,
        level = context.level,
        source_attacker = context.attacker,
        source_entindex = context.attacker:entindex(),
        attributes = copy_attributes(context.attributes),
        mirror_appearance = invulnerable,
        world = current_world(),
    }
    exclusive_summons[key] = state
    if not sync_summon(key, state, nil, true) then return false end
    state.expiry_task = scheduler.after(duration, function()
        retire_summon(key, state)
    end, "hero_exclusive_summon:" .. key)
    ensure_summon_sync()
    return true, unit
end

function M.runners.skill_doom_infernal(context, definition)
    local created, unit = create_summon(
        context, definition, "npc_survival_doom_infernal", false
    )
    if created then
        M.sound_service.play("hero_doom_infernal_spawn", {
            unit = unit,
            source = context.attacker,
        })
    end
    return created
end

function M.runners.skill_drow_companion(context, definition)
    local created = create_summon(
        context, definition, "npc_survival_drow_companion", true
    )
    return created
end

local function live_raze_layers(target, duration, maximum)
    local key = unit_key(target)
    if not key then return nil end
    local now = game_time()
    local layers = shadow_raze_stacks[key] or {}
    local kept = {}
    for _, expires_at in ipairs(layers) do
        if expires_at > now then kept[#kept + 1] = expires_at end
    end
    kept[#kept + 1] = now + duration
    while #kept > maximum do table.remove(kept, 1) end
    shadow_raze_stacks[key] = kept
    return kept
end

local function particle_at(name, owner, position)
    local ok, particle = pcall(
        ParticleManager.CreateParticle,
        ParticleManager,
        name,
        PATTACH_WORLDORIGIN,
        owner
    )
    if not ok then return end
    ParticleManager:SetParticleControl(particle, 0, position)
    ParticleManager:ReleaseParticleIndex(particle)
end

function M.runners.skill_shadow_fiend_raze(context, definition)
    -- Retain the existing skill/save ID and combat math for the replaced hero.
    local radius = level_value(definition, "radius", context.level, 250)
    local duration = level_value(definition, "stack_duration", context.level, 3)
    local maximum = level_value(definition, "max_stacks", context.level, 5)
    local layers = live_raze_layers(context.target, duration, maximum)
    if not layers then return false end
    local base = level_value(definition, "damage_multiplier", context.level, 25)
    local bonus = level_value(
        definition, "damage_per_stack_pct", context.level, 10
    )
    local position = context.target:GetAbsOrigin()
    blinding_light_visual.play(position, radius)
    M.sound_service.play("hero_shadow_raze_impact", {
        source = context.attacker,
        position = position,
    })
    deal_group(
        context,
        enemies_in_radius(context.attacker, position, radius),
        base * (1 + #layers * bonus / 100)
    )
    return true
end

function M.runners.skill_axe_counter_helix(context, definition)
    local position = context.target:GetAbsOrigin()
    particle_at(COUNTER_HELIX_PARTICLE, context.attacker, position)
    M.sound_service.play("hero_axe_counter_helix_impact", {
        source = context.attacker,
        position = position,
    })
    deal_group(
        context,
        enemies_in_radius(
            context.attacker, position,
            level_value(definition, "radius", context.level, 400)
        ),
        level_value(definition, "damage_multiplier", context.level, 30)
    )
    return true
end

function M.on_drow_companion_attack_fired(attacker, primary_target)
    if not alive(attacker) or not alive(primary_target)
        or attacker.survival_drow_companion ~= true then return false end
    M.sound_service.play("hero_drow_companion_volley", {
        unit = attacker,
        source = attacker,
    })
    local origin = attacker:GetAbsOrigin()
    local candidates = enemies_in_radius(
        attacker, origin, tonumber(attacker.survival_drow_attack_range) or 1200
    )
    table.sort(candidates, function(left, right)
        local lp, rp = left:GetAbsOrigin(), right:GetAbsOrigin()
        local ldx, ldy = lp.x - origin.x, lp.y - origin.y
        local rdx, rdy = rp.x - origin.x, rp.y - origin.y
        return ldx * ldx + ldy * ldy < rdx * rdx + rdy * rdy
    end)
    local fired = 1
    local maximum = math.max(1, tonumber(attacker.survival_drow_max_targets) or 5)
    for _, target in ipairs(candidates) do
        if fired >= maximum then break end
        if target ~= primary_target and alive(target) then
            attacker.survival_next_drow_secondary = true
            attacker:PerformAttack(
                target, false, false, true, false, true, false, false
            )
            attacker.survival_next_drow_secondary = nil
            fired = fired + 1
        end
    end
    return true
end

local function on_hero_combat_stats_changed(payload)
    local player_id = tonumber(payload and payload.player_id)
    local snapshot = payload and payload.snapshot
    if player_id == nil or type(snapshot) ~= "table" then return end
    for key, state in pairs(exclusive_summons) do
        if state.player_id == player_id and snapshot_matches(state, snapshot) then
            sync_summon(key, state, snapshot)
        end
    end
end

local function on_hero_cosmetics_changed(payload)
    local player_id = tonumber(payload and payload.player_id)
    local source = payload and payload.unit
    if player_id == nil or not valid(source) then return end
    for _, state in pairs(exclusive_summons) do
        if state.player_id == player_id and state.source_attacker == source
            and state.mirror_appearance and state.world == current_world()
            and alive(state.unit) and game_time() < state.expires_at then
            cosmetics.sync_appearance(state.unit, source)
        end
    end
end

local function on_hero_summoned(payload)
    local player_id = tonumber(payload and payload.player_id)
    if player_id == nil or not payload.unit then return end
    for key, state in pairs(exclusive_summons) do
        if state.player_id == player_id and state.source_attacker ~= payload.unit then
            retire_summon(key, state, true)
        end
    end
    for _, state in pairs(summon_corpses) do
        if state.player_id == player_id and state.source_attacker ~= payload.unit then
            finish_corpse(state)
        end
    end
end

local function on_player_removed(payload)
    local player_id = tonumber(payload and payload.player_id)
    if player_id == nil then return end
    for key, state in pairs(exclusive_summons) do
        if state.player_id == player_id then retire_summon(key, state, true) end
    end
    for _, state in pairs(summon_corpses) do
        if state.player_id == player_id then finish_corpse(state) end
    end
end

local function on_hero_removed(payload)
    local player_id = tonumber(payload and payload.player_id)
    if player_id == nil then return end
    for key, state in pairs(exclusive_summons) do
        if state.player_id == player_id and state.source_attacker == payload.unit then
            retire_summon(key, state, true)
        end
    end
    for _, state in pairs(summon_corpses) do
        if state.player_id == player_id and state.source_attacker == payload.unit then
            finish_corpse(state)
        end
    end
end

function M.init(dependencies)
    assert(type(dependencies and dependencies.deal_group) == "function")
    deal_group = dependencies.deal_group
    for key, state in pairs(exclusive_summons) do retire_summon(key, state, true) end
    for _, state in pairs(summon_corpses) do finish_corpse(state) end
    exclusive_summons = {}
    summon_corpses = {}
    shadow_raze_stacks = {}
    service_generation = service_generation + 1
    local generation = service_generation
    local function subscribe(event, handler)
        -- EventBus.reset reuses subscription IDs. Guard old callbacks instead
        -- of unsubscribing a token that may now belong to another service.
        event_bus.subscribe(event, function(payload)
            if generation == service_generation then handler(payload) end
        end)
    end
    subscribe(events.HERO_COMBAT_STATS_CHANGED, on_hero_combat_stats_changed)
    subscribe(events.HERO_COSMETICS_CHANGED, on_hero_cosmetics_changed)
    subscribe(events.HERO_SUMMONED, on_hero_summoned)
    subscribe(events.HERO_REMOVED, on_hero_removed)
    subscribe(events.PLAYER_DEFEATED, on_player_removed)
    subscribe(events.PLAYER_DISCONNECTED, on_player_removed)
end

M._test = {
    base_attack_time = base_attack_time,
    inherited_stats = inherited_stats,
    apply_combat_stats = apply_combat_stats,
    on_hero_combat_stats_changed = on_hero_combat_stats_changed,
    live_raze_layers = live_raze_layers,
    active_summons = function() return exclusive_summons end,
}

return M
