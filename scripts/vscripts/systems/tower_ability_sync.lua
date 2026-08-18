local logger = require("core/logger")
local tower_skills = require("systems/tower_skill_runtime")
local event_bus = require("core/event_bus")
local events = require("core/events")
local tower_utility_abilities = require("systems/tower_utility_ability_sync")

local M = {}

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
    for _, ability_name in ipairs(row and row.active_skill_ids or {}) do
        mark(ability_name)
    end
    for _, skill_id in ipairs(row and row.skill_ids or {}) do
        mark(skill_id)
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
    if state.tower_class then
        for _, class_data in ipairs(state.definition.class_options or {}) do
            mark(class_data.ability)
        end
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

function M.sync(state, row)
    local wanted = {}
    local base_tower_is_full = not state.tower_class and state.level >= 5
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
    if state.unit.survival_tower_ability_signature == signature then
        print(string.format(
            "[TowerAbilitySync] skip entindex=%s signature=%s time=%.3f",
            tostring(state.unit:entindex()), signature, debug_time()
        ))
        return
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
    state.unit.survival_tower_ability_signature = signature
    print(string.format(
        "[TowerAbilitySync] end entindex=%s signature=%s elapsed=%.3f",
        tostring(state.unit:entindex()), signature, debug_time() - started_at
    ))
end

return M
