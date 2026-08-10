local event_bus = require("core/event_bus")
local events = require("core/events")
local scheduler = require("core/scheduler")
local destination_validation = require("systems/destination_validation_service")

local M = {}
local tracked = {}
local INTERVAL = 0.05

local function valid(unit)
    return unit and not unit:IsNull()
end

local function register(payload)
    local unit = payload and payload.unit
    if not valid(unit) or not destination_validation.is_constrained_hero(unit) then
        return
    end
    local position = unit:GetAbsOrigin()
    local legal, reason = destination_validation.validate(position, unit)
    if not legal then
        print("[HERO_BOUNDARY_GUARD] registration_failed reason=" .. tostring(reason))
        return
    end
    unit.survival_hero_last_legal_position = Vector(
        position.x, position.y, position.z
    )
    tracked[unit] = true
end

local function think()
    for unit in pairs(tracked) do
        if not valid(unit) then
            tracked[unit] = nil
        elseif unit:IsAlive() then
            local position = unit:GetAbsOrigin()
            local legal = destination_validation.validate(position, unit)
            if legal then
                unit.survival_hero_last_legal_position = Vector(
                    position.x, position.y, position.z
                )
            else
                local fallback = unit.survival_hero_last_legal_position
                if fallback then
                    unit:Stop()
                    unit:SetAbsOrigin(fallback)
                end
            end
        end
    end
end

function M.init()
    tracked = {}
    event_bus.subscribe(events.HERO_SUMMONED, register)
    scheduler.every(INTERVAL, think, "hero_boundary_guard")
end

M._register_for_test = register
M._think_for_test = think
M._tracked_for_test = function() return tracked end

return M