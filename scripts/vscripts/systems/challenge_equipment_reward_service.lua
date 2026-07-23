local event_bus = require("core/event_bus")
local events = require("core/events")
local config = require("config/challenge_definitions")
local weapons = require("config/generated/weapon_definitions")

local M = {}
local ice_counts = {}
local granted = {}

local SERIES_BY_CHALLENGE = {
    challenge_10 = "epic_icefire",
    challenge_11 = "legend_abyss",
}

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

local function upgrade_series(player_id, series_id, key)
    local inventory = event_bus.request(
        events.CONTENT_INVENTORY_GET_REQUEST,
        { player_id = player_id }
    )
    local counts = inventory and inventory.snapshot and inventory.snapshot.counts
    if not counts then return { ok = false, error = "challenge_inventory_unavailable" } end

    local current = nil
    for _, definition in ipairs(weapons.rows or {}) do
        local count = tonumber(counts[definition.content_id]) or 0
        if definition.enabled ~= false and definition.series_id == series_id
            and count > 0
            and (not current
                or (tonumber(definition.stage) or 0) > (tonumber(current.stage) or 0)) then
            current = definition
        end
    end
    if not current then
        return { ok = false, error = "challenge_required_weapon_missing:" .. series_id }
    end
    local next_id = tostring(current.next_content_id or "")
    local next_definition = weapons.by_id[next_id]
    if next_id == "" or not next_definition or next_definition.enabled == false then
        return { ok = false, error = "challenge_weapon_max_stage:" .. current.content_id }
    end

    local result = execute(
        player_id,
        key,
        { [current.content_id] = 1 },
        { [next_id] = 1 },
        "challenge_weapon_upgrade"
    )
    if result.ok then
        result.upgrade_from = current.content_id
        result.upgrade_to = next_id
        print("[CHALLENGE_WEAPON_UPGRADE] player=" .. player_id
            .. " from=" .. current.content_id .. " to=" .. next_id)
    end
    return result
end

local function on_kill(payload)
    local player_id = valid_owner(payload)
    if not player_id then return end
    local archetype_id = tostring(
        payload.archetype_id
        or (payload.encounter and payload.encounter.archetype_id)
        or ""
    )
    local encounter_id = tostring(payload.encounter_id or "")
    if archetype_id == "" and encounter_id == "" then return end
    if archetype_id ~= "ice_soul" and archetype_id ~= "ice_spirit"
        and not encounter_id:find("ice", 1, true) then return end
    ice_counts[player_id] = (ice_counts[player_id] or 0) + 1
    if ice_counts[player_id] >= 200 then
        grant(player_id, "item_large_polar_crystal", "ice_soul_200")
    end
end

local function claim(payload)
    local player_id = valid_owner(payload)
    local challenge_id = tostring(payload.challenge_id or "")
    if not player_id then return { ok = false, error = "challenge_player_invalid" } end
    if payload.authoritative ~= true then
        return { ok = false, error = "challenge_authority_required" }
    end

    local key = challenge_id .. ":" .. tostring(payload.completion_id or "default")
    local series_id = SERIES_BY_CHALLENGE[challenge_id]
    if series_id then return upgrade_series(player_id, series_id, key) end

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
    ice_counts = {}
    granted = {}
    event_bus.subscribe(events.MONSTER_KILLED, on_kill)
    event_bus.handle_request(events.CHALLENGE_EQUIPMENT_REWARD_REQUEST, claim)
    print("[CHALLENGE_EQUIP_INIT] ice_soul_target=200 staged_weapon_upgrade=true")
end

return M