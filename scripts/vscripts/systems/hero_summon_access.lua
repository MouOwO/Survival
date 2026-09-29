local event_bus = require("core/event_bus")
local events = require("core/events")

local M = {}

-- Item ownership unlocks this hero only; it never grants global VIP rights.
local unlock_items = { hero_monkey_king = "lottery_monkey_king" }

function M.context(player_id, entitlement)
    local result = event_bus.request(events.PLAYER_PROFILE_GET_REQUEST, {
        player_id = player_id,
    })
    local profile = result and result.ok and result.profile or nil
    local inventory = profile and profile.save and profile.save.content_inventory
    return {
        vip = entitlement and entitlement.vip == 1,
        -- Use the authenticated match view, preserving pure-mode filtering.
        inventory = type(inventory) == "table" and inventory or {},
    }
end

function M.check(definition, context)
    if not definition or definition.enabled == false then
        return false, "英雄配置不存在"
    end
    context = context or {}
    if definition.vip_required ~= true or context.vip == true then
        return true, ""
    end
    local item_id = unlock_items[definition.hero_id]
    if item_id then
        local quantity = (context.inventory or {})[item_id]
        if type(quantity) == "number" and quantity >= 1
            and quantity < math.huge and quantity == math.floor(quantity) then
            return true, ""
        end
        return false, "需要拥有齐天大圣存档道具或VIP权限"
    end
    return false, "需要VIP权限"
end

return M
