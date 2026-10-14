-- Append only the wave service's private, proven formal lane records. Engine
-- creature results retain their order and dead-valid entities unchanged.
local event_bus = require("core/event_bus")
local M = {}

local function world()
    return GameRules and GameRules.GetGameModeEntity
        and GameRules:GetGameModeEntity() or GameRules or _G
end

local function identity(record)
    local ok, result = pcall(function()
        local unit = record and record.unit
        return unit and not unit:IsNull() and unit:entindex() == record.entindex
            and type(EntIndexToHScript) == "function"
            and EntIndexToHScript(record.entindex) == unit
            and unit:GetClassname() == "npc_dota_creep_lane"
            and unit:IsRealHero() == false
            and unit:GetTeamNumber() == DOTA_TEAM_BADGUYS
            and unit.survival_player_id == record.player_id
    end)
    return ok and result == true
end

-- Only wave_system owns this instance and its registry-proof callback. No
-- caller receives registry metadata or can register a unit through the facade.
function M.new(current_record)
    local owning_world, owning_generation = world(), event_bus.get_generation()
    local active, retired_scope = true, {}
    local history = require("core/target_history").new({
        task_prefix = "registered_lane_corpses", budget = 64, interval = 0.25,
        expired = function(record)
            if not active then return true end
            if world() ~= owning_world or package.loaded["core/event_bus"] ~= event_bus
                or event_bus.get_generation() ~= owning_generation then return true end
            if not active then return true end
            return not identity(record)
        end,
    })
    local view = {}

    function view:reset()
        active = false -- Revoke this view before cancelling its old timer.
        history:reset()
    end

    local function scope()
        if not active then return false end
        if world() ~= owning_world or package.loaded["core/event_bus"] ~= event_bus
            or event_bus.get_generation() ~= owning_generation then
            view:reset()
            return false
        end
        return active == true
    end

    function view:retire(record)
        if not scope() or not identity(record) then return end
        local ok, dead = pcall(function() return record.unit:IsAlive() == false end)
        if not ok or not dead or not scope() then return end
        -- Copy scalars, never retain/export the mutable production meta table.
        local saved = { unit = record.unit, entindex = record.entindex,
            player_id = record.player_id }
        history:bucket(retired_scope)[record.unit] = saved
        history:track(retired_scope, record.unit)
    end

    function view:append(creatures)
        if not scope() then return creatures end
        local record = current_record()
        local values = history:all_values()[retired_scope]
        if not record and (not values or next(values) == nil) then return creatures end
        local additions, seen = {}, {}
        for _, unit in ipairs(creatures) do seen[unit] = true end
        local function include(record)
            if identity(record) and not seen[record.unit] then
                seen[record.unit] = true
                additions[#additions + 1] = record.unit
            end
        end
        include(record)
        if values then for _, retired in pairs(values) do include(retired) end end
        if not scope() then return creatures end
        if #additions == 0 then return creatures end
        local result = {}
        for index, unit in ipairs(creatures) do result[index] = unit end
        for _, unit in ipairs(additions) do result[#result + 1] = unit end
        return result
    end

    function view:snapshot()
        scope()
        return history:snapshot()
    end
    return view
end

function M.append(creatures)
    creatures = creatures or {}
    -- Keep the normal load order; item/tree/rogue modules never load wave_system.
    local wave = package.loaded["systems/wave_system"]
    if wave and type(wave._append_registered_lane_units) == "function" then
        return wave._append_registered_lane_units(creatures)
    end
    return creatures
end

return M
