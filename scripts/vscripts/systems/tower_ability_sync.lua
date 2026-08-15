local logger = require("core/logger")
local tower_skills = require("systems/tower_skill_runtime")
local event_bus = require("core/event_bus")
local events = require("core/events")
local tower_utility_abilities = require("systems/tower_utility_ability_sync")

local M = {}

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
    end

    -- Free the utility slots before route abilities are added. Source 2 fills
    -- lower vacant ability indexes first, so clearing them only at the end
    -- leaves move and destroy ahead of newly inherited route skills.
    tower_utility_abilities.clear(state.unit)

    for _, ability_name in ipairs({
        "ability_upgrade_tower", "ability_upgrade_tower_lv01",
        "ability_upgrade_tower_max",
    }) do
        if state.unit:FindAbilityByName(ability_name)
            and not wanted[ability_name] then
            state.unit:RemoveAbility(ability_name)
        end
    end
    for skill_id, _ in pairs(tower_skills.get(state.unit)) do
        if not wanted[skill_id] and state.unit:FindAbilityByName(skill_id) then
            state.unit:RemoveAbility(skill_id)
        end
    end
    if state.tower_class then
        for _, class_data in ipairs(state.definition.class_options or {}) do
            if state.unit:FindAbilityByName(class_data.ability) then
                state.unit:RemoveAbility(class_data.ability)
            end
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
    if wanted.ability_tower_fusion then
        add_ability(state.unit, "ability_tower_fusion")
    elseif state.unit:FindAbilityByName("ability_tower_fusion") then
        state.unit:RemoveAbility("ability_tower_fusion")
    end
    tower_utility_abilities.sync(state, row)
end

return M
