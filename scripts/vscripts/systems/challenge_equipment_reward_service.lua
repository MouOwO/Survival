local event_bus = require("core/event_bus")
local events = require("core/events")
local config = require("config/generated/challenge_definitions")
local catalog = require("config/generated/content_catalog")
local items = require("config/generated/item_definitions")
local content_id_aliases = require("config/content_id_aliases")
local molten_core_rules = require("config/molten_core_challenge_rules")

local M = {}
local granted = {}

local function valid(entity)
    return entity and not entity:IsNull()
end

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

local function drop(player_id, content_id, key, position)
    content_id = content_id_aliases.canonical(content_id)
    granted[player_id] = granted[player_id] or {}
    if granted[player_id][key] then
        print(string.format(
            "[CHALLENGE_REWARD_DROP] player=%s key=%s content=%s action=idempotent_skip",
            tostring(player_id), tostring(key), tostring(content_id)))
        return { ok = true, idempotent = true }
    end
    local summoned = event_bus.request(
        events.HERO_SUMMON_GET_REQUEST,
        { player_id = player_id }
    )
    local hero = summoned and summoned.unit
        or PlayerResource:GetSelectedHeroEntity(player_id)
    local definition = catalog.by_id[content_id]
    local item_definition = items.by_id[content_id]
    local engine_item_name = tostring(
        item_definition and item_definition.engine_item_name or ""
    )
    if not valid(hero) or not position or not definition then
        return { ok = false, error = "challenge_ground_reward_invalid" }
    end
    if engine_item_name == "" then
        return { ok = false, error = "challenge_ground_reward_item_mapping_missing" }
    end
    local item = CreateItem(engine_item_name, hero, hero)
    if not valid(item) then
        return { ok = false, error = "challenge_ground_reward_create_failed" }
    end
    local actual_engine_item_name = item.GetAbilityName and item:GetAbilityName()
        or engine_item_name
    item.survival_content_id = content_id
    item.survival_owner_player_id = player_id
    item.survival_reward_key = key
    item.survival_ground_reward = true
    if item.SetPurchaser then item:SetPurchaser(hero) end
    local container = CreateItemOnPositionSync(position, item)
    if not valid(container) then
        UTIL_Remove(item)
        return { ok = false, error = "challenge_ground_reward_container_failed" }
    end
    CustomNetTables:SetTableValue(
        "survival_inventory_item_identity",
        tostring(item:entindex()),
        { content_id = content_id, removed = 0 }
    )
    granted[player_id][key] = true
    print(string.format(
        "[CHALLENGE_REWARD_DROP] player=%s key=%s content=%s requested_item=%s actual_item=%s entindex=%s action=created",
        tostring(player_id), tostring(key), tostring(content_id),
        tostring(engine_item_name), tostring(actual_engine_item_name),
        tostring(item:entindex())))
    event_bus.emit(events.UI_NOTIFICATION, {
        player_id = player_id,
        message = "挑战奖励已掉落：" .. tostring(definition.name or content_id)
            .. "（拾取后保存在装备栏，满足配方时自动合成）",
    })
    return {
        ok = true,
        dropped = true,
        content_id = content_id,
        engine_item_name = actual_engine_item_name,
        entindex = item:entindex(),
    }
end

local function drop_content(payload)
    local player_id = valid_owner(payload)
    local challenge_id = tostring(payload.challenge_id or "")
    local content_id = content_id_aliases.canonical(payload.content_id)
    if not player_id then return { ok = false, error = "challenge_player_invalid" } end
    if payload.authoritative ~= true then
        return { ok = false, error = "challenge_authority_required" }
    end
    -- This endpoint exists for per-monster molten-core drops. Keep the
    -- accepted challenge/content pair fail-closed so callers cannot turn it
    -- into an arbitrary inventory material generator.
    if challenge_id ~= molten_core_rules.challenge_id
        or content_id ~= molten_core_rules.content_id then
        return { ok = false, error = "challenge_content_drop_not_allowed" }
    end
    local drop_id = tostring(payload.drop_id or "")
    if drop_id == "" then return { ok = false, error = "challenge_drop_id_missing" } end
    return drop(
        player_id,
        content_id,
        challenge_id .. ":monster_drop:" .. drop_id,
        payload.position
    )
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
    if payload.position
        and (challenge_id == "challenge_05"
            or challenge_id == "challenge_08"
            or challenge_id == "challenge_09") then

        return drop(
            player_id,
            definition.reward_content_id,
            key,
            payload.position
        )
    end
    return grant(player_id, definition.reward_content_id, key)
end

function M.init()
    granted = {}
    event_bus.handle_request(events.CHALLENGE_EQUIPMENT_REWARD_REQUEST, claim)
    event_bus.handle_request(events.CHALLENGE_CONTENT_DROP_REQUEST, drop_content)
    print("[CHALLENGE_EQUIP_INIT] challenge_stages_use_ground_materials=true")
end

return M