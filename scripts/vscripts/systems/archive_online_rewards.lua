local levels = require("config/generated/archive_map_levels")
local work = require("config/generated/archive_work_items")
local M = {}

local function state(archive)
    archive.online = archive.online or { actual_seconds = 0, map_seconds = 0, coins = 0,
        map_level = 0, work_levels = {}, cursors = {} }
    return archive.online
end

function M.apply(command, archive, stats, apply_effects)
    local s = state(archive)
    if command.kind == "online_checkpoint" then
        local raw, weighted = tonumber(command.actual_seconds), tonumber(command.map_seconds)
        if not raw or raw ~= raw or raw < 0 or raw >= math.huge or raw ~= math.floor(raw)
            or not weighted or weighted ~= weighted or weighted < raw or weighted > raw * 2
            or weighted ~= math.floor(weighted) or type(command.session) ~= "string" then
            return false, "online_checkpoint_invalid"
        end
        local previous = s.cursors[command.session] or { actual_seconds = 0, map_seconds = 0 }
        if raw <= previous.actual_seconds then return true end
        local elapsed, map_elapsed = raw - previous.actual_seconds, weighted - previous.map_seconds
        if map_elapsed < elapsed or map_elapsed > elapsed * 2 then return false, "online_checkpoint_invalid" end
        local old_minutes = math.floor(s.actual_seconds / 60)
        s.actual_seconds = s.actual_seconds + elapsed
        s.map_seconds = s.map_seconds + map_elapsed
        s.coins = s.coins + math.floor(s.actual_seconds / 60) - old_minutes
        s.cursors[command.session] = { actual_seconds = raw, map_seconds = weighted }
        for _, item in ipairs(levels.rows) do
            if item.enabled and item.level > s.map_level and s.map_seconds >= item.required_seconds then
                apply_effects(stats, item)
                s.map_level = item.level
            end
        end
        return true
    elseif command.kind == "work_upgrade" then
        local item = work.by_id[command.item_id]
        if not item or not item.enabled then return false, "福利项目不存在" end
        local owned = s.work_levels[item.item_id] or 0
        if owned >= item.max_level then return false, "该福利已激活" end
        if command.expected_level ~= owned then return false, "福利进度已更新，请重试" end
        if s.coins < item.cost then return false, "软妹币不足" end
        s.coins = s.coins - item.cost
        s.work_levels[item.item_id] = owned + 1
        apply_effects(stats, item)
        return true
    end
    return false, "online_command_invalid"
end

function M.info(archive)
    local s = state(archive)
    return { actual_seconds = s.actual_seconds, map_seconds = s.map_seconds,
        coins = s.coins, level = s.map_level, max_level = #levels.rows }
end

function M.rows(archive, category)
    local s, rows = state(archive), {}
    if category == "map_level" then
        for _, item in ipairs(levels.rows) do
            if item.enabled then
                rows[#rows + 1] = { id = item.level_id, name = item.display_name, quality = "N",
                    rune = tostring(item.level), icon_style = "seal",
                    count = math.floor(s.map_seconds / 60), target = item.required_seconds / 60,
                    completed = s.map_level >= item.level and 1 or 0,
                    description = "累计有效在线时长：" .. item.required_seconds / 3600 .. "小时\n"
                        .. (item.level == 1 and "每升一级：城墙初始生命+100；城墙每秒回血+5"
                            or "每升一级：城墙初始生命+100；城墙每秒回血+5\n本级奖励：" .. item.description) }
            end
        end
    else
        for _, item in ipairs(work.rows) do
            if item.enabled then
                local owned = s.work_levels[item.item_id] or 0
                rows[#rows + 1] = { id = item.item_id, name = item.display_name, quality = "N",
                    rune = "薪", icon_style = "seal", count = owned, target = item.max_level,
                    level = owned, cost = item.cost, can_upgrade = owned < item.max_level and s.coins >= item.cost and 1 or 0,
                    completed = owned >= item.max_level and 1 or 0,
                    description = item.description .. "\n激活消耗：" .. item.cost .. "软妹币\n"
                        .. (owned >= item.max_level and "已激活，永久生效" or "点击此格激活；每项可激活一次") }
            end
        end
    end
    return rows
end
return M
