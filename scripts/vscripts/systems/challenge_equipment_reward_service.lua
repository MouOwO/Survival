local event_bus = require("core/event_bus")
local events = require("core/events")
local config = require("config/challenge_definitions")

local M = {}
local granted = {}

local function valid_owner(payload)
    local player_id = tonumber(payload.player_id)
    return player_id and player_id >= 0 and player_id or nil
end

local function execute(player_id, key, consume, grant, reason)
    granted[player_id] = granted[player_id] or {}
    if granted[player_id][key] then return { ok = true, idempotent = true } end
    local result = event_bus.request(
        events.INVENTORY_TRANSACTION_EXECUTE_REQUEST,
        {
            player_id = player_id,
            request_id = "challenge:" .. key,
            consume = consume or {},
            grant = grant or {},
            reason = reason or "challenge_equipment_reward",
        }
    )
    if result and result.ok then granted[player_id][key] = true end
    return result or { ok = false, error = "challenge_inventory_unavailable" }
end

local function grant(player_id, content_id, key)
    local result = execute(
        player_id,
        key,
        {},
        { [content_id] = 1 },
        "challenge_equipment_reward"
    )
    if result.ok then
        print("[CHALLENGE_EQUIP_REWARD] player=" .. player_id
            .. " content=" .. content_id)
    end
    return result
end

local function claim(payload)
    local player_id = valid_owner(payload)
    local challenge_id = tostring(payload.challenge_id or "")
    if not player_id then return { ok = false, error = "challenge_player_invalid" } end
    if payload.authoritative ~= true then
        return { ok = false, error = "challenge_authority_required" }
    end

    local key = challenge_id .. ":" .. tostring(payload.completion_id or "default")
    local definition = config.by_id[challenge_id]
    if not definition or definition.review_status == "暂不支持" then
        return { ok = false, error = "challenge_unknown_fail_closed" }
    end
    if not definition.reward_content_id then
        return { ok = false, error = "challenge_no_equipment_reward" }
    end
    return grant(player_id, definition.reward_content_id, key)
end

function M.init()
    granted = {}
    event_bus.handle_request(events.CHALLENGE_EQUIPMENT_REWARD_REQUEST, claim)
    print("[CHALLENGE_EQUIP_INIT] challenge_stages_use_ground_materials=true")
end

return M