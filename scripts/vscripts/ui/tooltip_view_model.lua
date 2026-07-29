local M = {}

local function field(fields, label, value)
    if value == nil or value == "" then return end
    fields[#fields + 1] = { label = label, value = value }
end

local function item_view(content_id, quantity)
    return {
        content_id = tostring(content_id or ""),
        quantity = math.max(0, math.floor(tonumber(quantity) or 0)),
        fields = {},
    }
end

function M.weapon_snapshot(equipment, growth, instances, equipment_growth)
    equipment = equipment or {}
    growth = growth or {}
    instances = instances or {}
    equipment_growth = equipment_growth or {}

    local view = { version = 1, items = {} }
    for content_id, instance in pairs(instances) do
        local quantity = type(instance) == "table"
            and instance.quantity or instance
        if (tonumber(quantity) or 0) > 0 then
            view.items[content_id] = item_view(content_id, quantity)
        end
    end

    local main_id = tostring(equipment.main_hand_content_id or "")
    if main_id == "" then return view end
    local item = view.items[main_id] or item_view(main_id, 1)
    view.items[main_id] = item

    local target = math.max(0, tonumber(growth.stage_attack_target) or 0)
    local current = math.max(0, tonumber(growth.stage_attack_count) or 0)
    if target > 0 then
        field(item.fields, "当前进度",
            tostring(math.min(current, target)) .. " / " .. tostring(target))
        field(item.fields, "剩余进度", math.max(0, target - current))
    else
        local compatibility_progress = math.max(
            0,
            tonumber(equipment_growth[main_id]) or 0
        )
        if compatibility_progress > 0 then
            field(item.fields, "当前进度", compatibility_progress)
        end
    end

    local growth_attack = tonumber(growth.growth_attack) or 0
    if growth_attack ~= 0 then
        field(item.fields, "累计成长攻击", "+" .. tostring(growth_attack))
    end
    local progress_per_attack = tonumber(growth.progress_per_attack) or 1
    if progress_per_attack > 1 then
        field(item.fields, "每次攻击进度", "+" .. tostring(progress_per_attack))
    end
    local hammer_count = math.max(
        0,
        math.floor(tonumber(growth.forging_hammer_count) or 0)
    )
    if hammer_count > 0 then
        field(item.fields, "锻造锤", tostring(hammer_count) .. " / 4")
    end
    return view
end

return M