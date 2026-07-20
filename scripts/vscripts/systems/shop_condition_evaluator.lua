local M = {}

local function number(value)
    return tonumber(value) or 0
end

local function owned(context, content_id)
    return context.owned_content
        and (context.owned_content[content_id] == true or (tonumber(context.owned_content[content_id]) or 0) > 0)
end

local function series_stage(context, series_id)
    local stage = 0
    for id, count in pairs(context.owned_content or {}) do
        if (tonumber(count) or 0) > 0 and string.find(id, series_id, 1, true) then
            local n = string.match(id, "_max$") and 99
                or tonumber(string.match(id, "_(%d+)$")) or 0
            if n > stage then stage = n end
        end
    end
    return stage
end

function M.evaluate(player_id, entry, context)
    local count = context.purchased_count[player_id]
        and context.purchased_count[player_id][entry.entryid] or 0
    local resources = context.resources or {}
    local limit = number(entry.purchase_limit)

    if entry.enabled == false then
        return false,
            entry.disabled_reason_text ~= ""
                and entry.disabled_reason_text
                or "该内容暂不可购买",
            count
    end
    if entry.requires_hero_summoned
        and context.hero_summoned ~= true then
        return false, "请先在英雄祭坛召唤英雄", count
    end
    if limit > 0 and count >= limit then
        return false, "已达到购买上限", count
    end
    local definition = entry.definition or {}
    if definition.progression_type == "repeat_purchase"
        and definition.series_id and definition.series_id ~= "" then
        local current_stage = series_stage(context, definition.series_id)
        if current_stage >= 99 then
            return false, "已达到最高等级", count
        end
    end
    if context.city_level < entry.min_city_level then
        return false,
            "需要主城达到Lv." .. tostring(entry.min_city_level),
            count
    end
    if entry.requires_vip and context.vip ~= true then
        return false, "需要VIP权限", count
    end
    if context.rebirth_level < entry.required_rebirth_level then
        return false,
            "需要完成" ..
            tostring(entry.required_rebirth_level) .. "转",
            count
    end
    if entry.requires_building_id ~= ""
        and (context.building_counts[entry.requires_building_id] or 0) < 1 then
        return false,
            "需要建筑：" .. entry.requires_building_id,
            count
    end
    if entry.requires_content_id ~= ""
        and not owned(context, entry.requires_content_id) then
        return false,
            "需要前置内容：" .. entry.requires_content_id,
            count
    end
    if entry.grant_type == "start_encounter"
        and entry.encounter_id == "" then
        return false, "遭遇或出生点尚未配置", count
    end
    if number(resources.wood) < entry.woodcost then
        return false, "木材不足", count
    end
    if number(resources.gold) < entry.goldcost then
        return false, "金币不足", count
    end
    return true, "", count
end

return M
