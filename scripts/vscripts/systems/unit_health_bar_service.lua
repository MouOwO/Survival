local M = {}

local initialized = false

local function valid_entity(unit)
    return unit and (not unit.IsNull or not unit:IsNull())
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
    -- This one-health NPC is a ground pickup model, not a combat unit.
    return not unit.GetUnitName
        or unit:GetUnitName() ~= "npc_survival_upgrade_material"
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

local function unit_from_spawn_event(keys)
    local entindex = tonumber(keys and keys.entindex)
    if not entindex or not EntIndexToHScript then
        return nil
    end
    return EntIndexToHScript(entindex)
end

local function on_npc_spawned(keys)
    attach(unit_from_spawn_event(keys))
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
            attach(unit)
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
M._unit_from_spawn_event_for_test = unit_from_spawn_event

return M