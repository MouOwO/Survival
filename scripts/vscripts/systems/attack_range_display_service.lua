local global_rules = require("config/global_rules")

local M = {}
local active = {}
local registered = false
local PARTICLE = "particles/ui_mouseactions/range_finder_tower_aoe.vpcf"

local function positive(value)
    value = tonumber(value)
    return value and value > 0 and value or nil
end

local function entity(entindex)
    entindex = tonumber(entindex)
    if not entindex or not EntIndexToHScript then return nil end
    local unit = EntIndexToHScript(entindex)
    return unit and not unit:IsNull() and unit or nil
end

local function owner_id(unit)
    local survival_id = tonumber(unit.survival_player_id)
    if survival_id ~= nil and survival_id >= 0 then return survival_id end
    if unit.GetPlayerOwnerID then
        local ok, player_id = pcall(unit.GetPlayerOwnerID, unit)
        player_id = tonumber(player_id)
        if ok and player_id ~= nil and player_id >= 0 then return player_id end
    end
    if unit.GetPlayerOwner then
        local ok, player = pcall(unit.GetPlayerOwner, unit)
        if ok and player and player.GetPlayerID then
            local player_ok, player_id = pcall(player.GetPlayerID, player)
            player_id = tonumber(player_id)
            if player_ok and player_id ~= nil and player_id >= 0 then
                return player_id
            end
        end
    end
    return nil
end

local function is_tower(unit)
    return unit.survival_building_id == "arrow_tower"
        or (unit.HasModifier and unit:HasModifier("modifier_tower_auto_attack"))
end

local function is_hero(unit)
    if unit.survival_hero_id ~= nil then return true end
    if not unit.IsHero then return false end
    local ok, result = pcall(unit.IsHero, unit)
    return ok and result == true
end

local function attack_range(unit)
    local result = positive(unit.survival_attack_range)
    for _, method_name in ipairs({ "Script_GetAttackRange", "GetAttackRange" }) do
        local method = unit[method_name]
        if type(method) == "function" then
            local ok, value = pcall(method, unit)
            if ok then result = math.max(result or 0, positive(value) or 0) end
        end
    end
    if is_tower(unit) then
        local base = positive(global_rules.tower_attack_range) or 0
        local bonus = tonumber(unit.survival_attack_range_bonus) or 0
        result = math.max(result or 0, base + bonus)
    end
    return positive(result)
end

local function destroy(player_id)
    local particle = player_id ~= nil and active[player_id] or nil
    if not particle then return end
    ParticleManager:DestroyParticle(particle, true)
    ParticleManager:ReleaseParticleIndex(particle)
    active[player_id] = nil
end

local function show(player_id, payload)
    destroy(player_id)
    local unit = entity(payload and payload.entindex)
    if not unit then
        print(string.format("[ATTACK_RANGE_HIDE] player=%s reason=entity_missing entindex=%s",
            tostring(player_id), tostring(payload and payload.entindex)))
        return
    end
    local unit_owner = owner_id(unit)
    if unit_owner ~= player_id then
        print(string.format("[ATTACK_RANGE_HIDE] player=%s reason=owner_mismatch entindex=%s owner=%s",
            tostring(player_id), tostring(payload and payload.entindex), tostring(unit_owner)))
        return
    end
    if not (is_hero(unit) or is_tower(unit)) then
        print(string.format("[ATTACK_RANGE_HIDE] player=%s reason=unsupported_unit entindex=%s",
            tostring(player_id), tostring(payload and payload.entindex)))
        return
    end
    local range = attack_range(unit)
    if not range then
        print(string.format("[ATTACK_RANGE_HIDE] player=%s reason=range_missing entindex=%s",
            tostring(player_id), tostring(payload and payload.entindex)))
        return
    end
    local particle = ParticleManager:CreateParticle(PARTICLE, PATTACH_ABSORIGIN_FOLLOW, unit)
    ParticleManager:SetParticleControl(particle, 1, Vector(range, range, range))
    active[player_id] = particle
end

function M.init()
    if registered then return true end
    registered = true
    CustomGameEventManager:RegisterListener("survival_attack_range_visibility", function(source_player_id, payload)
        local player_id = tonumber(source_player_id)
            or tonumber(payload and payload.PlayerID)
        if player_id == nil then return end
        if tonumber(payload.visible) == 1 then show(player_id, payload)
        else destroy(player_id) end
    end)
    ListenToGameEvent("player_disconnect", function(keys)
        destroy(tonumber(keys and keys.PlayerID))
    end, nil)
    return true
end

function M.reset_for_test()
    active = {}
    registered = false
end

M._attack_range_for_test = attack_range
M._is_tower_for_test = is_tower

return M