local M = {}

local initialized = false
local TABLE = "survival_hero_health_bar"
local EXCLUDED_UNIT_NAMES = {
    npc_survival_upgrade_material = true,
}

local function valid_entity(unit)
    return unit and (not unit.IsNull or not unit:IsNull())
end

local function is_excluded(unit)
    if not valid_entity(unit) then
        return false
    end
    local unit_name = unit and unit.GetUnitName and unit:GetUnitName() or nil
    return unit and (
        EXCLUDED_UNIT_NAMES[unit_name]
        or unit.survival_wall_collision_barrier
        or unit.survival_hide_custom_health_bar
        or (unit.HasModifier
            and unit:HasModifier("modifier_survival_placeholder_anchor"))
    )
end

local function is_unit(unit)
    if not valid_entity(unit) or not unit.IsBaseNPC
        or not unit:IsBaseNPC() or not unit.AddNewModifier then
        return false
    end
    -- Ability thinkers are engine-side helper NPCs without a visible unit.
    if unit.GetClassname and unit:GetClassname() == "npc_dota_thinker" then
        return false
    end
    return not is_excluded(unit)
end

local function publish_removed(unit)
    if not CustomNetTables or not valid_entity(unit) or not unit.entindex then
        return
    end
    CustomNetTables:SetTableValue(
        TABLE,
        "unit_" .. tostring(unit:entindex()),
        { removed = 1 }
    )
end

function M.exclude(unit)
    if not valid_entity(unit) then
        return false
    end
    if unit.HasModifier and unit:HasModifier("modifier_single_health_bar")
        and unit.RemoveModifierByName then
        unit:RemoveModifierByName("modifier_single_health_bar")
    end
    publish_removed(unit)
    return true
end

local function attach(unit)
    if not is_unit(unit) then
        return false
    end
    if unit.HasModifier and unit:HasModifier("modifier_single_health_bar") then
        return false
    end
    unit:AddNewModifier(unit, nil, "modifier_single_health_bar", {})
    return true
end

local function clear_excluded_unit(unit)
    if is_unit(unit) then
        return false
    end
    if not is_excluded(unit) then
        return false
    end
    M.exclude(unit)
    return true
end

local function unit_from_spawn_event(keys)
    local entindex = tonumber(keys and keys.entindex)
    if not entindex or not EntIndexToHScript then
        return nil
    end
    return EntIndexToHScript(entindex)
end

local function on_npc_spawned(keys)
    local unit = unit_from_spawn_event(keys)
    if not clear_excluded_unit(unit) then
        attach(unit)
    end
end

local function attach_existing_units()
    if not Entities or not Entities.FindAllByClassname then
        return
    end
    local classes = {
        "npc_dota_hero",
        "npc_dota_creature",
        "npc_dota_building",
    }
    for _, classname in ipairs(classes) do
        for _, unit in ipairs(Entities:FindAllByClassname(classname) or {}) do
            if not clear_excluded_unit(unit) then
                attach(unit)
            end
        end
    end
end

function M.init()
    if initialized then
        return
    end
    initialized = true
    ListenToGameEvent("npc_spawned", on_npc_spawned, nil)
    attach_existing_units()
end

M._attach_for_test = attach
M._clear_excluded_for_test = clear_excluded_unit
M._unit_from_spawn_event_for_test = unit_from_spawn_event

return M