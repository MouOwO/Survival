local bus = require("core/event_bus")
local events = require("core/events")
local definitions = require("config/generated/lumberjack_fusion_definitions")
local M = {}
local by_ability = {}
for _, row in ipairs(definitions.rows or {}) do
    if row.enabled ~= false then by_ability[row.ability_id] = row end
end

function M.definition(name) return by_ability[name] end

-- Used by both the button projection and the actual material transaction.
function M.is_material(state, player_id, team, level)
    local unit = state and state.unit
    return unit and not unit:IsNull() and unit:IsAlive()
        and state.worker_type == "lumberjack" and state.team == team
        and tonumber(state.player_id) == tonumber(player_id)
        and tonumber(unit.survival_player_id) == tonumber(player_id)
        and unit.survival_super_lumberjack ~= true
        and not unit.survival_lumberjack_fusion_pending
        and tonumber(unit.survival_lumberjack_level) == tonumber(level)
end

-- A flush shares this snapshot across all of one player's worker buttons.
-- Never cache it across events or use it to spend resources.
function M.snapshot(player_id, team)
    local result = {city_level = 0, counts = {}, eligible = {}}
    local buildings = bus.request(events.BUILDING_LIST_REQUEST, {player_id = player_id})
    for _, state in ipairs((buildings and buildings.buildings) or {}) do
        if state.building_id == "main_city" then
            result.city_level = tonumber(state.level) or 0
            break
        end
    end
    for _, state in ipairs(bus.request(events.WORKER_LIST_REQUEST, {player_id = player_id}) or {}) do
        local level = state.unit and tonumber(state.unit.survival_lumberjack_level)
        if level and M.is_material(state, player_id, team, level) then
            result.counts[level] = (result.counts[level] or 0) + 1
            result.eligible[state.unit:entindex()] = true
        end
    end
    return result
end

function M.prerequisite_error(row, city_level, count)
    if city_level < (tonumber(row.required_city_level) or 0) then
        return "fusion_city_level_not_enough"
    end
    if count < (tonumber(row.required_count) or 0) then
        return "fusion_material_not_enough"
    end
end

function M.runtime(name, state, resources, snapshot)
    local row = by_ability[name]
    if not row then return nil end
    local caster = state and state.unit
    local result = {available = 0, prerequisite_met = 0, can_afford = 1,
        resource_check_on_cast = 1, lumberjack_fusion = 1,
        cost_wood = row.wood_cost, cost_gold = row.gold_cost,
        status_text = "当前伐木工不能合体"}
    if not caster or caster:IsNull() or not caster:IsAlive()
        or caster.survival_worker_type ~= "lumberjack"
        or tonumber(caster.survival_player_id) == nil
        or caster.survival_super_lumberjack
        or tonumber(caster.survival_lumberjack_level) ~= tonumber(row.level) then return result end
    if caster.survival_lumberjack_fusion_pending then
        result.status_text = "伐木工正在合体中"
        return result
    end
    snapshot = snapshot or M.snapshot(caster.survival_player_id, caster:GetTeamNumber())
    local count = snapshot.counts[tonumber(row.level)] or 0
    result.fields = {
        {label = "合体前置", value = "主城LV" .. tostring(row.required_city_level)},
        {label = "自己的普通同级伐木工", value = tostring(count) .. "/" .. tostring(row.required_count)},
    }
    local error_code = M.prerequisite_error(row, snapshot.city_level, count)
    if error_code == "fusion_city_level_not_enough" then
        result.status_text = "主城达到LV" .. tostring(row.required_city_level) .. "后才能合体"
    elseif error_code == "fusion_material_not_enough" then
        result.status_text = "合体需要" .. tostring(row.required_count) .. "个自己的普通LV"
            .. tostring(row.level) .. "伐木工（当前" .. tostring(count) .. "个）"
    elseif not snapshot.eligible[caster:entindex()] then
        result.status_text = "当前伐木工不能作为合体材料"
    else
        -- The cast transaction checks the current wallet. Resource ticks must
        -- not change the prerequisite projection or re-scan the worker roster.
        result.available, result.prerequisite_met = 1, 1
        result.status_text = "可合体为" .. tostring(row.display_name)
    end
    return result
end

return M
