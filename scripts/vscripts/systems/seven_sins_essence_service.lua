local event_bus = require("core/event_bus")
local events = require("core/events")
local scheduler = require("core/scheduler")
local essences = require("config/seven_sins_essences")
local weapons = require("config/generated/weapon_definitions")

local M = {}
local state_by_player = {}
local use_locked = {}

local function state(player_id)
    state_by_player[player_id] = state_by_player[player_id] or {
        counts = {},
        final_damage_pct = 0,
        attack_interval_flat = 0,
        attributes_per_kill = 0,
        all_attributes_pct = 0,
        attack_bonus_pct = 0,
        attributes_per_attack = 0,
        armor_reduction_per_attack = 0,
        version = 0,
    }
    return state_by_player[player_id]
end

local function snapshot(player_id)
    local current = state(player_id)
    return {
        player_id = player_id,
        counts = current.counts,
        final_damage_pct = current.final_damage_pct,
        attack_interval_flat = current.attack_interval_flat,
        attributes_per_kill = current.attributes_per_kill,
        all_attributes_pct = current.all_attributes_pct,
        attack_bonus_pct = current.attack_bonus_pct,
        attributes_per_attack = current.attributes_per_attack,
        armor_reduction_per_attack = current.armor_reduction_per_attack,
        version = current.version,
    }
end

local function notify(player_id, message, level)
    event_bus.emit(events.UI_NOTIFICATION, {
        player_id = player_id,
        message = message,
        level = level or "info",
    })
end

local function owns_item(caster, item)
    if not caster or caster:IsNull() or not item or item:IsNull() then return false end
    for slot = 0, 8 do
        if caster:GetItemInSlot(slot) == item then return true end
    end
    return false
end

local function current_icefire(player_id)
    local inventory = event_bus.request(
        events.CONTENT_INVENTORY_GET_REQUEST,
        { player_id = player_id }
    )
    local counts = inventory and inventory.snapshot and inventory.snapshot.counts
    if not counts then return nil, "inventory_unavailable" end
    local current = nil
    for _, definition in ipairs(weapons.rows or {}) do
        if definition.series_id == "epic_icefire"
            and (tonumber(counts[definition.content_id]) or 0) > 0
            and (not current or (tonumber(definition.stage) or -1)
                > (tonumber(current.stage) or -1)) then
            current = definition
        end
    end
    if current then return current end
    for content_id, count in pairs(counts) do
        if (tonumber(count) or 0) > 0
            and tostring(content_id):find("weapon_legend_abyss_", 1, true) == 1 then
            return nil, "already_ascended"
        end
    end
    return nil, "icefire_missing"
end

local function consume_physical_item(caster, item)
    local charges = item.GetCurrentCharges and item:GetCurrentCharges() or 0
    if charges > 1 then
        item:SetCurrentCharges(charges - 1)
        return
    end
    item.survival_consume_pending = true
    scheduler.after(0, function()
        if not item or item:IsNull() then return end
        if caster and not caster:IsNull() then
            caster:RemoveItem(item)
        end
        if not item:IsNull() then UTIL_Remove(item) end
    end, "seven_sins_remove_item:" .. tostring(item:entindex()))
end

local function apply_effect(player_id, definition)
    local current = state(player_id)
    current.counts[definition.content_id] =
        (tonumber(current.counts[definition.content_id]) or 0) + 1
    local key = definition.effect_type
    current[key] = (tonumber(current[key]) or 0)
        + (tonumber(definition.effect_value) or 0)
    current.version = current.version + 1
    local data = snapshot(player_id)
    data.reason = "essence_used:" .. definition.content_id
    event_bus.emit(events.SEVEN_SINS_ESSENCE_CHANGED, data)
    return data
end

local function use_essence(payload)
    local player_id = tonumber(payload.player_id)
    local definition = essences.by_content_id[tostring(payload.content_id or "")]
    local caster, item = payload.caster, payload.item
    if player_id == nil or player_id < 0 or not definition then
        return { ok = false, error = "essence_request_invalid" }
    end
    if use_locked[player_id] then
        return { ok = false, error = "essence_use_in_progress" }
    end
    if item and item.survival_consume_pending then
        return { ok = false, error = "essence_consume_pending" }
    end
    if not owns_item(caster, item) or caster:GetPlayerOwnerID() ~= player_id
        or item:GetAbilityName() ~= definition.engine_item_name then
        return { ok = false, error = "essence_not_owned" }
    end
    use_locked[player_id] = true
    local current, error_message = current_icefire(player_id)
    if not current then
        use_locked[player_id] = nil
        local text = error_message == "already_ascended"
            and "冰火裁决已完成升阶，精华已保留但不能继续使用。"
            or "需要持有冰火裁决才能使用七宗罪精华。"
        notify(player_id, text, "error")
        return { ok = false, error = error_message }
    end
    local next_content_id = tostring(current.next_content_id or "")
    if next_content_id == "" or not weapons.by_id[next_content_id] then
        use_locked[player_id] = nil
        notify(player_id, "冰火裁决下一阶段配置缺失。", "error")
        return { ok = false, error = "icefire_next_stage_missing" }
    end
    local transaction = event_bus.request(
        events.INVENTORY_TRANSACTION_EXECUTE_REQUEST,
        {
            player_id = player_id,
            request_id = DoUniqueString("seven_sins_essence"),
            consume = { [current.content_id] = 1 },
            grant = { [next_content_id] = 1 },
            reason = "seven_sins_essence:" .. definition.content_id,
        }
    )
    if not transaction or not transaction.ok then
        use_locked[player_id] = nil
        notify(player_id, "强化失败，精华未消耗："
            .. tostring(transaction and transaction.error or "handler_missing"), "error")
        return transaction or { ok = false, error = "transaction_handler_missing" }
    end
    local inventory_after = event_bus.request(
        events.CONTENT_INVENTORY_GET_REQUEST,
        { player_id = player_id }
    )
    local counts_after = inventory_after and inventory_after.snapshot
        and inventory_after.snapshot.counts or {}
    if (tonumber(counts_after[next_content_id]) or 0) <= 0 then
        use_locked[player_id] = nil
        notify(player_id, "强化结果校验失败，精华已保留。", "error")
        return { ok = false, error = "icefire_upgrade_not_committed" }
    end
    consume_physical_item(caster, item)
    local data = apply_effect(player_id, definition)
    local ascended = next_content_id == "weapon_legend_abyss_00"
    notify(player_id, definition.display_name .. "已消耗，对应增益已生效；冰火裁决已强化为"
        .. tostring(weapons.by_id[next_content_id].display_name or next_content_id) .. "。")
    if ascended then
        event_bus.emit(events.SEVEN_SINS_COMPLETED, {
            player_id = player_id,
            hero = caster,
            next_content_id = next_content_id,
        })
    end
    use_locked[player_id] = nil
    return { ok = true, snapshot = data, next_content_id = next_content_id,
        ascended = ascended }
end

local function get_stats(payload)
    local player_id = tonumber(payload.player_id)
    if player_id == nil or player_id < 0 then
        return { ok = false, error = "player_id_invalid" }
    end
    return { ok = true, snapshot = snapshot(player_id) }
end

local function on_hero_summoned(payload)
    local current = state(tonumber(payload.player_id))
    if payload.unit and not payload.unit:IsNull() then
        payload.unit.survival_seven_sins_final_damage_pct =
            tonumber(current.final_damage_pct) or 0
    end
end

local function on_monster_killed(payload)
    local player_id = tonumber(payload.player_id)
    if player_id == nil then return end
    local amount = tonumber(state(player_id).attributes_per_kill) or 0
    if amount <= 0 then return end
    event_bus.request(events.HERO_PROGRESSION_APPLY_REQUEST, {
        player_id = player_id,
        reason = "seven_sins_sloth_kill",
        effects = { { effect_type = "add_all_attributes", value = amount } },
    })
end

local function on_attack_landed(payload)
    local player_id = tonumber(payload.player_id)
    if player_id == nil then return end
    local amount = tonumber(state(player_id).attributes_per_attack) or 0
    if amount > 0 then
        event_bus.request(events.HERO_PROGRESSION_APPLY_REQUEST, {
            player_id = player_id,
            reason = "seven_sins_greed_attack",
            effects = { { effect_type = "add_all_attributes", value = amount } },
        })
    end
end

function M.init()
    state_by_player, use_locked = {}, {}
    event_bus.handle_request(events.SEVEN_SINS_ESSENCE_USE_REQUEST, use_essence)
    event_bus.handle_request(events.SEVEN_SINS_ESSENCE_STATS_GET_REQUEST, get_stats)
    event_bus.subscribe(events.HERO_SUMMONED, on_hero_summoned)
    event_bus.subscribe(events.MONSTER_KILLED, on_monster_killed)
    event_bus.subscribe(events.WEAPON_ATTACK_LANDED, on_attack_landed)
end

return M