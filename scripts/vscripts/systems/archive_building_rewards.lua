local items = require("config/generated/archive_building_items")
local rules = require("config/generated/archive_building_rules").by_id.default
local M = {}
local function state(archive)
    archive.buildings = archive.buildings or { faith = 0, levels = {}, earned_by_day = {} }
    return archive.buildings
end
function M.clear(archive, command)
    local s = state(archive)
    local day = tostring(assert(command.day_key or command.today, "archive_faith_day_missing"))
    local earned = s.earned_by_day[day] or 0
    local gain = math.max(0, math.min(rules.faith_per_clear * command.count, rules.faith_daily_cap - earned))
    s.faith = s.faith + gain
    s.earned_by_day[day] = earned + gain
end
function M.apply(command, archive, stats, apply_effects)
    if command.kind == "faith_cheat" then
        local amount = command.amount
        if type(amount) ~= "number" or amount ~= amount or amount < 1
            or amount > 1000000000 or amount ~= math.floor(amount) then
            return false, "信仰值数量无效"
        end
        local s = state(archive)
        if s.faith + amount > 9007199254740991 then return false, "信仰值超出可保存范围" end
        -- Test grants bypass daily acquisition limits without consuming/resetting them.
        s.faith = s.faith + amount
        return true
    end
    local item = items.by_id[command.item_id]
    if not item or not item.enabled then return false, "存档建筑不存在" end
    local s = state(archive)
    local level = s.levels[item.item_id] or 0
    if level >= item.max_level then return false, "存档建筑已满级" end
    if command.expected_level ~= level then return false, "建筑等级已更新，请重试" end
    if s.faith < item.cost then return false, "信仰值不足" end
    s.faith = s.faith - item.cost
    s.levels[item.item_id] = level + 1
    apply_effects(stats, item)
    return true
end
function M.info(archive, day)
    local s = state(archive)
    return { faith = s.faith, earned_today = s.earned_by_day[tostring(day)] or 0,
        daily_cap = rules.faith_daily_cap, per_clear = rules.faith_per_clear }
end
function M.rows(archive)
    local s, rows = state(archive), {}
    for _, item in ipairs(items.rows) do
        if item.enabled then
            local level = s.levels[item.item_id] or 0
            rows[#rows + 1] = { id = item.item_id, name = item.display_name, quality = "N",
                rune = string.sub(item.display_name, 1, 3), icon_style = "seal", count = level,
                level = level, target = item.max_level, cost = item.cost,
                completed = level >= item.max_level and 1 or 0,
                can_upgrade = level < item.max_level and s.faith >= item.cost and 1 or 0,
                description = item.description .. "\n当前等级：" .. level .. "/" .. item.max_level
                    .. "\n每级消耗：" .. item.cost .. "信仰值\n"
                    .. (level >= item.max_level and "已满级" or level == 0 and "点击激活" or "点击升级") }
        end
    end
    return rows
end
return M
