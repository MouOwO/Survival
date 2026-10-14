-- Both hero UI transports start with the same authoritative frequency.
-- Only project live effects absent from that snapshot; native attack-speed
-- reads can still belong to a different stat-recalculation frame.
local M = {}

local function number(value)
    local result = tonumber(value)
    if result and result == result and math.abs(result) < math.huge then return result end
end

local function call(target, method_name, ...)
    local method = target and target[method_name]
    if type(method) ~= "function" then return nil end
    local ok, result = pcall(method, target, ...)
    return ok and result or nil
end

local function copy(source)
    local result = {}
    for key, value in pairs(source) do result[key] = value end
    return result
end

local function temporary_bonuses(unit)
    local flat, percentage = 0, 0
    -- These families own live skill IAS and temporary IAS/slow effects.
    -- Equipment and weapon projection are already included in the snapshot.
    for _, name in ipairs({"modifier_survival_managed_buff", "modifier_hero_passive_skill_effect",
        "modifier_survival_hero_skill"}) do
        local modifiers = call(unit, "FindAllModifiersByName", name)
        if type(modifiers) == "table" then
            for _, modifier in ipairs(modifiers) do
                if modifier and call(modifier, "IsNull") ~= true then
                    flat = flat + (number(call(modifier, "GetModifierAttackSpeedBonus_Constant")) or 0)
                    percentage = percentage + (number(call(modifier, "GetModifierAttackSpeedPercentage")) or 0)
                end
            end
        end
    end
    return flat, percentage
end

function M.for_ui(snapshot, unit)
    if not snapshot or not unit or unit.survival_monkey_king_clone == true then return snapshot end
    local detail = snapshot.attack_cadence
    local rate = number(snapshot.attack_speed)
    local reduced = detail and number(detail.reduced_interval)
    if not reduced or reduced <= 0 or not rate or rate <= 0 then return snapshot end
    if (number(snapshot.debug_attack_speed_override) or 0) > 0 then return snapshot end
    local fixed = call(unit, "FindModifierByName", "modifier_debug_fixed_attack_rate")
    local fixed_interval = number(call(fixed, "GetModifierFixedAttackRate"))
    if fixed_interval and fixed_interval > 0 then return snapshot end

    local old_cheer = number(detail.cheer_bonus) or 0
    local current_cheer = number(unit.survival_cheer_attack_speed_pct) or 0
    local flat, temporary_pct = temporary_bonuses(unit)
    if current_cheer == old_cheer and flat == 0 and temporary_pct == 0 then return snapshot end
    -- Preserve the snapshot's complete equipment/technology calculation.
    -- Older snapshots use engine_interval for a different quantity, so never
    -- divide by it or multiply their already accelerated frequency again.
    local baseline_pct = rate * reduced * 100 / math.max(0.01, 1 + old_cheer / 100)
    local actual_pct = math.max(1, baseline_pct + flat)
        * math.max(0.01, 1 + (current_cheer + temporary_pct) / 100)
    local projected = copy(snapshot)
    projected.attack_speed = actual_pct / (reduced * 100)
    projected.attack_cadence = copy(detail)
    projected.attack_cadence.cheer_bonus = current_cheer
    projected.attack_cadence.engine_interval = 1 / projected.attack_speed
    -- Keep temporary effects separate for the existing runtime-bonus tooltip.
    projected.attack_cadence.percentage = baseline_pct
        * math.max(0.01, 1 + current_cheer / 100)
    if current_cheer ~= old_cheer then
        local rows = {}
        for index, row in ipairs(detail.speed_bonuses or {}) do
            rows[index] = copy(row)
            if row.label == "欢呼光环" then rows[index].value = current_cheer end
        end
        projected.attack_cadence.speed_bonuses = rows
    end
    return projected
end

return M
