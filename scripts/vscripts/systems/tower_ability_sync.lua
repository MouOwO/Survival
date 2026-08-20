local logger = require("core/logger")
local tower_skills = require("systems/tower_skill_runtime")
local event_bus = require("core/event_bus")
local events = require("core/events")
local tower_utility_abilities = require("systems/tower_utility_ability_sync")
local scheduler = require("core/scheduler")
local tower_routes = require("config/tower_route_config")

local M = {}
local pending_by_entindex = {}
local pending_queue = {}
local next_generation = 0
local drain_scheduled = false

local function valid_entity(entity)
    return entity and not entity:IsNull()
end

local function list_signature(values)
    local result = {}
    for index, value in ipairs(values or {}) do
        result[index] = tostring(value or "")
    end
    return table.concat(result, ",")
end

local function ability_signature(state, row, fusion_enabled)
    return table.concat({
        tostring(state.tower_class or "base"),
        tostring(state.level or 0),
        tostring(row and row.record_id or ""),
        list_signature(row and row.active_skill_ids),
        list_signature(row and row.skill_ids),
        fusion_enabled and "fusion" or "normal",
    }, "|")
end

local function debug_time()
    if not GameRules or type(GameRules.GetGameTime) ~= "function" then return 0 end
    local ok, value = pcall(function() return GameRules:GetGameTime() end)
    return ok and tonumber(value) or 0
end

local function add_ability(unit, ability_name)
    local ability = unit:FindAbilityByName(ability_name)
        or unit:AddAbility(ability_name)
    if not ability then
        logger.error(
            "TowerAbilities",
            "AddAbility failed: " .. tostring(ability_name)
                .. " tower=" .. tostring(unit:entindex())
        )
        return
    end
    ability:SetLevel(1)
    ability:SetActivated(true)
end

local function mark_row_abilities(managed, row)
    for _, ability_name in ipairs(row and row.active_skill_ids or {}) do
        if ability_name and ability_name ~= "" then managed[ability_name] = true end
    end
    for _, skill_id in ipairs(row and row.skill_ids or {}) do
        if skill_id and skill_id ~= "" then managed[skill_id] = true end
    end
end

local function mark_configured_route_abilities(state, managed)
    local level = 1
    while true do
        local row = tower_routes.arrow(level)
        if not row then break end
        mark_row_abilities(managed, row)
        level = level + 1
    end
    for _, class_data in ipairs(state.definition.class_options or {}) do
        for _, row in ipairs(tower_routes.get_route(class_data.id) or {}) do
            mark_row_abilities(managed, row)
        end
    end
end

local function remove_managed_abilities(state, row)
    local unit = state.unit
    local managed = {}
    local upgrade_abilities = {
        ability_upgrade_tower = true,
        ability_upgrade_tower_lv01 = true,
        ability_upgrade_tower_max = true,
    }
    local function mark(ability_name)
        if ability_name and ability_name ~= "" then managed[ability_name] = true end
    end
    mark_row_abilities(managed, row)
    mark_configured_route_abilities(state, managed)
    for ability_name, _ in pairs(unit.survival_tower_managed_ability_names or {}) do
        mark(ability_name)
    end
    for _, ability_name in ipairs({
        "ability_tower_fusion",
        "ability_upgrade_tower", "ability_upgrade_tower_lv01",
        "ability_upgrade_tower_max",
        tower_utility_abilities.MOVE_ABILITY,
        tower_utility_abilities.DESTROY_ABILITY,
    }) do
        mark(ability_name)
    end
    for _, class_data in ipairs(state.definition.class_options or {}) do
        mark(class_data.ability)
    end
    for ability_name, _ in pairs(tower_skills.get(unit)) do
        mark(ability_name)
    end
    for ability_name, _ in pairs(managed) do
        -- Keep a still-configured upgrade Ability instance. The batch W path
        -- uses ability_upgrade_tower_max and requires its live entity to stay
        -- visible, activated and castable across tower state refreshes.
        if not upgrade_abilities[ability_name]
            and unit:FindAbilityByName(ability_name) then
            unit:RemoveAbility(ability_name)
        end
    end
end

local function sync_now(state, row, force)
    if not state or not valid_entity(state.unit) then return false end
    local wanted = {}
    local base_tower_is_full = not state.tower_class and state.level >= 5
    if base_tower_is_full then
        for _, class_data in ipairs(state.definition.class_options or {}) do
            local snapshot = event_bus.request(events.TOWER_CLASS_SLOT_REQUEST, {
                operation = "snapshot",
                player_id = state.player_id,
                class_id = class_data.id,
            }) or {}
            local count = tonumber(snapshot.count) or 0
            local pending = tonumber(snapshot.pending) or 0
            local maximum = tonumber(snapshot.maximum) or 5
            if maximum <= 0 or count + pending < maximum then
                wanted[class_data.ability] = true
            end
        end
    end
    for _, ability_name in ipairs(row and row.active_skill_ids or {}) do
        local allowed = not base_tower_is_full
            and (ability_name ~= "ability_upgrade_tower_max"
                or not row.rarity or row.rarity == "" or row.rarity == "N")
        if allowed then wanted[ability_name] = true end
    end
    for _, skill_id in ipairs(row and row.skill_ids or {}) do
        wanted[skill_id] = true
    end
    local fusion = state.tower_class and row
        and tonumber(row.level) == tonumber(row.max_level)
        and state.fusion_participated ~= true
        and event_bus.request(events.TOWER_FUSION_ELIGIBILITY_REQUEST, {
            player_id = state.player_id,
        })
    if fusion and fusion.eligible == true then
        wanted.ability_tower_fusion = true
        wanted.ability_upgrade_tower = nil
        wanted.ability_upgrade_tower_lv01 = nil
        wanted.ability_upgrade_tower_max = nil
    end

    local signature = ability_signature(state, row, wanted.ability_tower_fusion)
    if not force
        and type(state.unit.survival_tower_managed_ability_names) == "table"
        and state.unit.survival_tower_ability_signature == signature then
        print(string.format(
            "[TowerAbilitySync] skip entindex=%s signature=%s time=%.3f",
            tostring(state.unit:entindex()), signature, debug_time()
        ))
        state.unit.survival_tower_ability_sync_pending = nil
        event_bus.emit(events.TOWER_ABILITY_SYNC_COMPLETED, {
            unit = state.unit,
            entindex = state.unit:entindex(),
            signature = signature,
        })
        return false
    end

    local started_at = debug_time()
    print(string.format(
        "[TowerAbilitySync] start entindex=%s signature=%s time=%.3f",
        tostring(state.unit:entindex()), signature, started_at
    ))

    -- Dynamic abilities on npc_dota_creature do not reliably accept
    -- SetAbilityIndex(). Rebuild only the managed tower abilities instead, so
    -- AddAbility() receives the explicit visible order below.
    tower_utility_abilities.clear(state.unit)
    remove_managed_abilities(state, row)

    for _, ability_name in ipairs({
        "ability_upgrade_tower", "ability_upgrade_tower_lv01",
        "ability_upgrade_tower_max",
    }) do
        if state.unit:FindAbilityByName(ability_name)
            and not wanted[ability_name] then
            state.unit:RemoveAbility(ability_name)
        end
    end
    if wanted.ability_tower_fusion then
        for _, ability_name in ipairs({
            "ability_upgrade_tower", "ability_upgrade_tower_lv01",
            "ability_upgrade_tower_max",
        }) do
            if state.unit:FindAbilityByName(ability_name) then
                state.unit:RemoveAbility(ability_name)
            end
        end
    end

    if wanted.ability_tower_fusion then
        add_ability(state.unit, "ability_tower_fusion")
    end
    for _, class_data in ipairs(state.definition.class_options or {}) do
        if wanted[class_data.ability] then
            add_ability(state.unit, class_data.ability)
        end
    end
    for _, ability_name in ipairs(row and row.active_skill_ids or {}) do
        if wanted[ability_name]
            and ability_name ~= tower_utility_abilities.MOVE_ABILITY
            and ability_name ~= tower_utility_abilities.DESTROY_ABILITY then
            add_ability(state.unit, ability_name)
        end
    end
    for _, skill_id in ipairs(row and row.skill_ids or {}) do
        add_ability(state.unit, skill_id)
    end
    if not wanted.ability_tower_fusion
        and state.unit:FindAbilityByName("ability_tower_fusion") then
        state.unit:RemoveAbility("ability_tower_fusion")
    end
    tower_utility_abilities.sync(state, row)
    state.unit.survival_tower_managed_ability_names = wanted
    state.unit.survival_tower_ability_signature = signature
    state.unit.survival_tower_ability_sync_pending = nil
    event_bus.emit(events.TOWER_ABILITY_SYNC_COMPLETED, {
        unit = state.unit,
        entindex = state.unit:entindex(),
        signature = signature,
    })
    print(string.format(
        "[TowerAbilitySync] end entindex=%s signature=%s elapsed=%.3f",
        tostring(state.unit:entindex()), signature, debug_time() - started_at
    ))
    return true
end

local function schedule_drain()
    if drain_scheduled then return end
    drain_scheduled = true
    scheduler.after(0, function()
        drain_scheduled = false
        local item = table.remove(pending_queue, 1)
        if item then
            pending_by_entindex[item.entindex] = nil
            if valid_entity(item.state and item.state.unit)
                and item.state.unit:entindex() == item.entindex
                and item.state.tower_ability_sync_generation == item.generation then
                local ok, error_message = pcall(
                    sync_now,
                    item.state,
                    item.row,
                    item.force
                )
                if not ok then
                    item.state.unit.survival_tower_ability_sync_pending = nil
                    print("[TowerAbilitySync] queued sync failed entindex="
                        .. tostring(item.entindex) .. " error="
                        .. tostring(error_message))
                end
            end
        end
        if #pending_queue > 0 then schedule_drain() end
    end, "tower_ability_sync_drain")
end

function M.sync(state, row, force)
    if not state or not valid_entity(state.unit) then return false end
    local entindex = state.unit:entindex()
    next_generation = next_generation + 1
    state.tower_ability_sync_generation = next_generation
    state.unit.survival_tower_ability_sync_pending = true
    local item = pending_by_entindex[entindex]
    if item then
        item.state = state
        item.row = row
        item.force = item.force or force == true
        item.generation = next_generation
    else
        item = {
            state = state,
            row = row,
            force = force == true,
            entindex = entindex,
            generation = next_generation,
        }
        pending_by_entindex[entindex] = item
        pending_queue[#pending_queue + 1] = item
    end
    schedule_drain()
    return { queued = true, generation = next_generation }
end

function M.reset()
    for _, item in ipairs(pending_queue) do
        if valid_entity(item.state and item.state.unit) then
            item.state.unit.survival_tower_ability_sync_pending = nil
        end
    end
    pending_by_entindex = {}
    pending_queue = {}
    next_generation = 0
    drain_scheduled = false
end

M._pending_count_for_test = function()
    return #pending_queue
end

return M
