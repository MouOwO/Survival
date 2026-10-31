-- One server-owned permission/cooldown boundary for both hero D entry points.
-- No inventory copies, timers, scene scans or client-supplied ownership.
local bus = require("core/event_bus")
local events = require("core/events")
local effects = require("systems/commerce_effects")
local M = { ABILITY = "ability_survival_hero_ball_lightning", COOLDOWN = 10,
    CHANGED = "hero.teleport.cooldown.changed" }
local deadlines, generation, world = {}, nil, nil

local function player_id(value)
    value = tonumber(value)
    if value and value == value and value >= 0 and value <= 255
        and value == math.floor(value) then return value end
end

local function current_world()
    return GameRules and GameRules.GetGameModeEntity
        and GameRules:GetGameModeEntity() or GameRules
end

local function current_deadlines()
    local next_generation, next_world = bus.get_generation(), current_world()
    if generation ~= next_generation or world ~= next_world then
        deadlines, generation, world = {}, next_generation, next_world
    end
    return deadlines
end

function M.owned(id)
    id = player_id(id)
    return id ~= nil and effects.owned(id, "teleporter") == true
end

function M.ready_at(id)
    id = player_id(id)
    return id ~= nil and (current_deadlines()[id] or 0) or 0
end

function M.remaining(id)
    return math.max(0, M.ready_at(id) - GameRules:GetGameTime())
end

function M.restore_cooldown(id, ability)
    local remaining = M.remaining(id)
    if remaining > 0 and ability:GetCooldownTimeRemaining() + 0.05 < remaining then
        ability:StartCooldown(remaining)
    end
end

function M.check(id)
    if not M.owned(id) then return false, "需拥有侏儒传送器才能使用英雄传送" end
    if M.remaining(id) > 0 then return false, "侏儒传送器冷却中" end
    return true
end

function M.caster_player(unit)
    if not unit or unit:IsNull() or not unit.survival_hero_id then return nil end
    local id = player_id(unit.survival_player_id)
    if id == nil then return nil end
    if unit.GetPlayerOwnerID and unit:GetPlayerOwnerID() ~= id then return nil end
    local current = bus.request(events.HERO_SUMMON_GET_REQUEST, {player_id=id})
    if not current or (current.unit or current.hero) ~= unit then return nil end
    return id
end

function M.synchronize(id, unit, ability)
    if not unit or unit:IsNull() then return end
    ability = ability or unit:FindAbilityByName(M.ABILITY)
    if not ability or ability:IsNull() then return end
    local owned = M.owned(id)
    if ability:GetLevel() ~= 1 then ability:SetLevel(1) end
    if ability:IsHidden() ~= not owned then ability:SetHidden(not owned) end
    if ability:IsActivated() ~= owned then ability:SetActivated(owned) end
    if owned then M.restore_cooldown(id, ability) end
end

-- Call only after destination_validation.teleport has succeeded. Failed casts
-- do not reserve the cooldown, so native and custom paths can both retry.
function M.commit(id, unit)
    id = player_id(id)
    if id == nil then return end
    current_deadlines()[id] = GameRules:GetGameTime() + M.COOLDOWN
    if unit and not unit:IsNull() then
        local ability = unit:FindAbilityByName(M.ABILITY)
        if ability and not ability:IsNull()
            and ability:GetCooldownTimeRemaining() + 0.05 < M.COOLDOWN then
            ability:StartCooldown(M.COOLDOWN)
        end
    end
    bus.emit(M.CHANGED, {player_id=id})
end

return M
