local logger = require("core/logger")

local M = {}

local modifiers = {
    {
        name = "modifier_building_blink_move",
        path = "modifiers/modifier_building_blink_move",
    },
    {
        name = "modifier_building_stationary",
        path = "modifiers/modifier_building_stationary",
    },
    {
        name = "modifier_building_no_health_bar",
        path = "modifiers/modifier_building_no_health_bar",
    },
    {
        name = "modifier_building_under_construction",
        path = "modifiers/modifier_building_under_construction",
    },
    {
        name = "modifier_building_damage_sound",
        path = "modifiers/modifier_building_damage_sound",
    },
    {
        name = "modifier_grid_building_preview",
        path = "modifiers/modifier_grid_building_preview",
    },
    {
        name = "modifier_survival_placeholder_anchor",
        path = "modifiers/modifier_survival_placeholder_anchor",
    },
    {
        name = "modifier_lumberjack_ai",
        path = "modifiers/modifier_lumberjack_ai",
    },
    {
        name = "modifier_tree_progression",
        path = "modifiers/modifier_tree_progression",
    },
    {
        name = "modifier_repair_worker_ai",
        path = "modifiers/modifier_repair_worker_ai",
    },
    {
        name = "modifier_enemy_wall_ai",
        path = "modifiers/modifier_enemy_wall_ai",
    },
    {
        name = "modifier_survival_hero_skill",
        path = "modifiers/modifier_survival_hero_skill",
    },
    {
        name = "modifier_hero_passive_skill_effect",
        path = "modifiers/modifier_hero_passive_skill_effects",
    },
    {
        name = "modifier_hero_poison_cloud_armor",
        path = "modifiers/modifier_hero_poison_cloud_armor",
    },
    {
        name = "modifier_weapon_attack_tracker",
        path = "modifiers/modifier_weapon_attack_tracker",
    },
    {
        name = "modifier_monkey_king_clone",
        path = "modifiers/modifier_monkey_king_clone",
    },
    {
        name = "modifier_weapon_stat_projection",
        path = "modifiers/modifier_weapon_stat_projection",
    },
    {
        name = "modifier_equipment_effects",
        path = "modifiers/modifier_equipment_effects",
    },
    {
        name = "modifier_survival_hero_base_health",
        path = "modifiers/modifier_survival_hero_base_health",
    },
    {
        name = "modifier_survival_hero_mana_standard",
        path = "modifiers/modifier_survival_hero_mana_standard",
    },
    {
        name = "modifier_survival_hero_ball_lightning",
        path = "modifiers/modifier_survival_hero_ball_lightning",
        motion_type = LUA_MODIFIER_MOTION_HORIZONTAL,
    },
    {
        name = "modifier_survival_hero_attack_range",
        path = "modifiers/modifier_survival_hero_attack_range",
    },
    {
        name = "modifier_survival_drow_companion_invulnerable",
        path = "modifiers/modifier_survival_drow_companion_invulnerable",
    },
    {
        name = "modifier_debug_fixed_attack_rate",
        path = "modifiers/modifier_debug_fixed_attack_rate",
    },
    {
        name = "modifier_debug_attack_cap",
        path = "modifiers/modifier_debug_attack_cap",
    },
    {
        name = "modifier_debug_move_speed_cap",
        path = "modifiers/modifier_debug_move_speed_cap",
    },
    {
        name = "modifier_debug_attack_bonus",
        path = "modifiers/modifier_debug_combat_bonus",
    },
    {
        name = "modifier_debug_armor_bonus",
        path = "modifiers/modifier_debug_combat_bonus",
    },
    {
        name = "modifier_tower_auto_attack",
        path = "modifiers/modifier_tower_auto_attack",
    },
    {
        name = "modifier_tower_attack_effects",
        path = "modifiers/modifier_tower_attack_effects",
    },
    {
        name = "modifier_survival_managed_buff",
        path = "modifiers/modifier_survival_managed_buff",
    },
    {
        name = "modifier_survival_managed_aura",
        path = "modifiers/modifier_survival_managed_buff",
    },
    {
        name = "modifier_practice_monster_ai",
        path = "modifiers/modifier_practice_monster_ai",
    },
    {
        name = "modifier_endless_training_target",
        path = "modifiers/modifier_endless_training_target",
    },
    {
        name = "modifier_research_technology",
        path = "modifiers/modifier_research_technology",
    },
    {
        name = "modifier_research_armor_reduction",
        path = "modifiers/modifier_research_technology",
    },
    {
        name = "modifier_single_health_bar",
        path = "modifiers/modifier_single_health_bar",
    },
}

local REGISTERED_GENERATION_KEY =
    "__survival_modifier_registry_linked_generation"

local function link(definition)
    LinkLuaModifier(
        definition.name,
        definition.path,
        definition.motion_type or LUA_MODIFIER_MOTION_NONE
    )
    require(definition.path)
end

local function relink_path(path)
    for _, definition in ipairs(modifiers) do
        if definition.path == path then
            LinkLuaModifier(
                definition.name,
                definition.path,
                definition.motion_type or LUA_MODIFIER_MOTION_NONE
            )
        end
    end
end

function M.register(generation)
    generation = tonumber(generation)
    if not generation then
        return false, "modifier registry generation is required"
    end

    local linked_generation = rawget(_G, REGISTERED_GENERATION_KEY)
    if linked_generation ~= generation then
        for _, definition in ipairs(modifiers) do
            link(definition)
        end
        rawset(_G, REGISTERED_GENERATION_KEY, generation)
        print("[ModifierRegistry] startup linked generation="
            .. tostring(generation) .. " count=" .. tostring(#modifiers))
        logger.info(
            "ModifierRegistry",
            "startup linked generation=" .. tostring(generation)
                .. " modifiers=" .. tostring(#modifiers)
        )
    end
    local valid, detail = M.ensure_available()
    if not valid then return false, detail end
    return true, detail.checked
end

function M.ensure_available()
    local missing_path_set = {}
    local missing_paths = {}
    local missing_before = {}
    for _, definition in ipairs(modifiers) do
        if _G[definition.name] == nil then
            missing_before[#missing_before + 1] = definition.name
            if not missing_path_set[definition.path] then
                missing_path_set[definition.path] = true
                missing_paths[#missing_paths + 1] = definition.path
            end
        end
    end

    if #missing_before == 0 then
        return true, {
            checked = #modifiers,
            recovered = 0,
        }
    end

    local reload_errors = {}
    local reloaded = 0
    local relinked = 0
    for _, path in ipairs(missing_paths) do
        package.loaded[path] = nil
        local ok, error_message = pcall(require, path)
        reloaded = reloaded + 1
        if not ok then
            reload_errors[#reload_errors + 1] = path .. ": "
                .. tostring(error_message)
        end
        local links_before = relinked
        for _, definition in ipairs(modifiers) do
            if definition.path == path then
                relinked = relinked + 1
            end
        end
        if relinked > links_before then
            relink_path(path)
        end
    end

    local valid, detail = M.validate()
    if not valid then
        local message = "missing=" .. tostring(detail)
        if #reload_errors > 0 then
            message = message .. " reload_errors="
                .. table.concat(reload_errors, " | ")
        end
        logger.error("ModifierRegistry", "targeted recovery failed " .. message)
        return false, message
    end

    logger.warn(
        "ModifierRegistry",
        "targeted recovery restored=" .. tostring(#missing_before)
            .. " modules=" .. tostring(reloaded)
            .. " relinked=" .. tostring(relinked)
            .. " names=" .. table.concat(missing_before, ",")
    )
    return true, {
        checked = #modifiers,
        recovered = #missing_before,
        reloaded = reloaded,
        relinked = relinked,
        names = missing_before,
    }
end

function M.validate()
    local missing = {}
    for _, definition in ipairs(modifiers) do
        if _G[definition.name] == nil then
            missing[#missing + 1] = definition.name
        end
    end
    if #missing > 0 then
        return false, table.concat(missing, ",")
    end
    return true, #modifiers
end

return M
