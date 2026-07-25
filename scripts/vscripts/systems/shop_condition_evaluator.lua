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

local function exact_series_stage(context, prefix)
    local result = nil
    for id, count in pairs(context.owned_content or {}) do
        if (tonumber(count) or 0) > 0
            and tostring(id):find(prefix, 1, true) == 1 then
            local stage = tonumber(tostring(id):match("_(%d+)$"))
            if stage ~= nil and (result == nil or stage > result) then
                result = stage
            end
        end
    end
    return result
end

local function hero_technology(entry)
    local group = entry.definition
        and entry.definition.technology_group or ""
    return string.match(group, "^researcher_hero_") ~= nil
end

function M.evaluate(player_id, entry, context)
    local count = context.purchased_count[player_id]
        and context.purchased_count[player_id][entry.entryid] or 0
    local resources = context.resources or {}
    local limit = number(entry.purchase_limit)
    local research_authoritative = context.research_service_authoritative == true
        and entry.contenttype == "technology"

    if not context.gold_mine_ability and context.ui_mode == "research" then
        if entry.contenttype ~= "technology"
            and entry.contenttype ~= "technology_service" then
            return false, "该内容不属于研究所", count
        end
        if entry.contenttype == "technology" and hero_technology(entry) then
            return false, "英雄科技请在商店中研究", count
        end
    elseif not context.gold_mine_ability then
        if entry.contenttype == "technology_service" then
            return false, "科技解锁服务请在研究所中使用", count
        end
        if entry.contenttype == "technology" and not hero_technology(entry) then
            return false, "建筑与工人科技请在研究所中研究", count
        end
    end

    if entry.enabled == false and not context.gold_mine_ability then
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
    if entry.contenttype == "technology_service" then
        if entry.contentid == "advanced_researcher_unlock" then
            if context.advanced_researcher_unlocked == true then
                return false, "高级研究员服务已解锁", count
            end
        elseif context.research_unlocked == true then
            return false, "研究所科技服务已解锁", count
        end
    end
    if entry.contenttype == "technology" then
        -- Gold-mine technologies are intentionally purchased from the mine's
        -- W/E abilities. Ownership of the casting mine is validated by the
        -- shop system, so they must not depend on the research service.
        if not context.gold_mine_ability then
            if entry.technology_track == "advanced_researcher" then
                if context.advanced_researcher_unlocked ~= true then
                    return false, "需要先解锁高级研究员服务", count
                end
            elseif context.research_unlocked ~= true then
                return false, "需要先解锁研究所科技服务", count
            end
        end
        local levels = context.technology_levels and context.technology_levels[player_id] or {}
        local current = tonumber(levels[definition.technology_group]) or 0
        local next_level = tonumber(definition.level) or 0
        if not research_authoritative and next_level ~= current + 1 then
            return false, current >= (tonumber(definition.max_level) or 0) and "已达到最高等级" or "请先完成前一级科技", current
        end
        if not research_authoritative and entry.technology_track == "advanced" then
            local basic_level = tonumber(
                levels[entry.unlock_technology_group] or 0
            ) or 0
            local required = tonumber(
                definition.unlock_required_level
            ) or 10
            if basic_level < required then
                return false,
                    "需要对应普通科技达到Lv." .. required
                        .. "（当前Lv." .. basic_level .. "）",
                    current
            end
        elseif entry.technology_track == "advanced_researcher" then
            -- 高级研究员服务已在科技入口处统一校验。
        end
    end
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
    if not research_authoritative
        and context.rebirth_level < entry.required_rebirth_level then
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
        and not context.gold_mine_ability
        and not owned(context, entry.requires_content_id) then
        return false,
            "需要前置内容：" .. entry.requires_content_id,
            count
    end
    if entry.grant_type == "start_encounter"
        and entry.encounter_id == "" then
        return false, "遭遇或出生点尚未配置", count
    end
    if entry.grant_type == "start_encounter"
        and entry.encounter_id == "encounter_challenge_11" then
        local abyss_stage = exact_series_stage(
            context,
            "weapon_legend_abyss_"
        )
        if abyss_stage == nil then
            return false, "需要持有【传说：深渊审判】才能进入罪渊第一层", count
        end
        if abyss_stage >= 10 then
            return false, "【传说：深渊审判】已达到+10，罪渊挑战已完成", count
        end
    end
    if entry.grant_type == "start_encounter"
        and entry.encounter_id == "encounter_challenge_10" then
        local abyss_stage = exact_series_stage(
            context,
            "weapon_legend_abyss_"
        )
        if abyss_stage ~= nil then
            return false, "冰火裁决已升阶，七宗罪入口已关闭", count
        end
    end
    if not research_authoritative and number(resources.wood) < entry.woodcost then
        return false, "木材不足", count
    end
    if not research_authoritative and number(resources.gold) < entry.goldcost then
        return false, "金币不足", count
    end
    return true, "", count
end

return M
