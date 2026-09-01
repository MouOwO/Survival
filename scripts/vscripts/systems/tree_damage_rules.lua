local M = {}
local pending_attacks = {}

local function valid(unit)
    return unit and not unit:IsNull()
end

local function now()
    if GameRules and GameRules.GetGameTime then
        return GameRules:GetGameTime()
    end
    return 0
end

local function entity_index(unit)
    if not valid(unit) or not unit.entindex then return nil end
    return tonumber(unit:entindex())
end

local function attack_key(attacker, victim)
    local attacker_index = entity_index(attacker)
    local victim_index = entity_index(victim)
    if not attacker_index or not victim_index then return nil end
    return tostring(attacker_index) .. ":" .. tostring(victim_index)
end

function M.is_tree(unit)
    return valid(unit) and unit.GetUnitName
        and unit:GetUnitName() == "enemy_tree"
end

function M.is_arrow_tower(unit)
    return valid(unit)
        and tostring(unit.survival_building_id or "") == "arrow_tower"
end

function M.is_lumberjack(unit)
    return valid(unit) and unit.GetUnitName
        and unit:GetUnitName() == "npc_survival_lumberjack"
end

function M.is_real_hero(unit)
    if not valid(unit) or not unit.IsRealHero or not unit:IsRealHero() then
        return false
    end
    return not unit.IsIllusion or not unit:IsIllusion()
end

function M.is_allowed_tree_attacker(unit)
    return M.is_lumberjack(unit) or M.is_real_hero(unit)
end

function M.is_basic_attack_category(category)
    return DOTA_DAMAGE_CATEGORY_ATTACK ~= nil
        and tonumber(category) == tonumber(DOTA_DAMAGE_CATEGORY_ATTACK)
end

function M.mark_basic_attack(attacker, victim, record)
    if not M.is_allowed_tree_attacker(attacker) or not M.is_tree(victim) then
        return false
    end
    local key = attack_key(attacker, victim)
    if not key then return false end
    local entries = pending_attacks[key] or {}
    entries[#entries + 1] = {
        record = record ~= nil and tostring(record) or nil,
        expires_at = now() + 3,
    }
    pending_attacks[key] = entries
    return true
end

function M.consume_basic_attack(attacker, victim)
    local key = attack_key(attacker, victim)
    local entries = key and pending_attacks[key] or nil
    if not entries then return false end
    local current = now()
    while #entries > 0 and entries[1].expires_at < current do
        table.remove(entries, 1)
    end
    if #entries == 0 then
        pending_attacks[key] = nil
        return false
    end
    table.remove(entries, 1)
    if #entries == 0 then pending_attacks[key] = nil end
    return true
end

function M.clear_basic_attack(attacker, victim, record)
    local record_key = record ~= nil and tostring(record) or nil
    local attacker_index = entity_index(attacker)
    if not attacker_index then return end
    local victim_key = victim and attack_key(attacker, victim) or nil
    for key, entries in pairs(pending_attacks) do
        if (victim_key and key == victim_key)
            or (not victim_key and string.match(key, "^" .. attacker_index .. ":")) then
            for index = #entries, 1, -1 do
                if record_key == nil or entries[index].record == record_key then
                    table.remove(entries, index)
                end
            end
            if #entries == 0 then pending_attacks[key] = nil end
        end
    end
end

function M.reset_pending_attacks()
    pending_attacks = {}
end

function M.allows_damage(attacker, victim, damage_category, attack_evidence)
    if not M.is_tree(victim) then return true end
    if not M.is_allowed_tree_attacker(attacker) then return false end
    if M.is_basic_attack_category(damage_category) then return true end
    return attack_evidence == true
end

return M
