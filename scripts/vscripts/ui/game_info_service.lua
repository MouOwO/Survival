local event_bus = require("core/event_bus")
local events = require("core/events")

local M = {}
local providers = {}

local function number(value, fallback)
    local result = tonumber(value)
    return result ~= nil and result or (fallback or 0)
end

local function number_text(value)
    local numeric = number(value)
    if math.abs(numeric - math.floor(numeric)) < 0.001 then
        return tostring(math.floor(numeric))
    end
    return string.format("%.2f", numeric):gsub("0+$", ""):gsub("%.$", "")
end

local function safe_number(entity, method_name, fallback)
    local method = entity and entity[method_name]
    if type(method) ~= "function" then return fallback or 0 end
    local ok, result = pcall(method, entity)
    return ok and number(result, fallback) or (fallback or 0)
end

local function resolve_hero(combat)
    local entindex = tonumber(combat and combat.entindex)
    if not entindex or type(EntIndexToHScript) ~= "function" then return nil end
    local ok, hero = pcall(EntIndexToHScript, entindex)
    if not ok or not hero or (hero.IsNull and hero:IsNull()) then return nil end
    return hero
end

local function field(id, label, value, group, order, options)
    options = options or {}
    return {
        id = id,
        label = label,
        value = value,
        suffix = options.suffix or "",
        group = group,
        order = order,
        visible = (options.visible == false or options.visible == 0) and 0 or 1,
        dynamic_source = options.dynamic_source or "",
    }
end

local function default_fields(context)
    local technology = context.technology.final or {}
    local tower = technology.tower or {}
    local wall = technology.wall or {}
    local combat = context.combat
    local hero = context.hero
    local wall_health_pct = number(wall.health_bonus_pct)
        + number(wall.technology_health_bonus_pct)

    local fields = {
        field("tower_attack_per_second", "防御塔每秒攻击加", "未启用", "building", 10),
        field("tower_attack_flat", "防御塔攻击固定加成",
            number(tower.attack_flat), "building", 20),
        field("tower_attack_bonus_pct", "防御塔攻击百分比加成",
            number(tower.attack_bonus_pct), "building", 30, { suffix = "%" }),
        field("wall_armor_per_second", "城墙护甲每秒加", "未启用", "building", 40),
        field("wall_health_per_second", "城墙血量每秒加", "未启用", "building", 50),
        field("wall_armor_technology_bonus", "城墙当前护甲科技加成",
            number(wall.technology_armor_bonus), "building", 60),
        field("wall_health_technology_bonus", "城墙当前血量科技加成",
            wall_health_pct, "building", 70, { suffix = "%" }),
    }

    if combat then
        fields[#fields + 1] = field(
            "hero_attack_gain_per_attack", "英雄攻击每次加攻击力",
            number(combat.attack_gain_per_attack), "hero", 110
        )
        fields[#fields + 1] = field(
            "hero_attributes", "英雄当前智慧/力量/敏捷",
            number_text(combat.intellect) .. " / "
                .. number_text(combat.strength) .. " / "
                .. number_text(combat.agility),
            "hero", 120
        )
        fields[#fields + 1] = field(
            "hero_current_health", "英雄当前血量",
            number_text(safe_number(hero, "GetHealth", 0)) .. " / "
                .. number_text(safe_number(hero, "GetMaxHealth", 0)),
            "hero", 130, { dynamic_source = "hero_health" }
        )
        local attack_min = number(combat.attack_min)
        local attack_max = number(combat.attack_max, attack_min)
        local attack_text = number_text(attack_min)
        if math.abs(attack_max - attack_min) >= 0.001 then
            attack_text = attack_text .. " - " .. number_text(attack_max)
        end
        fields[#fields + 1] = field(
            "hero_current_attack", "英雄当前攻击力", attack_text, "hero", 140
        )
        fields[#fields + 1] = field(
            "hero_health_regen", "英雄每秒回血",
            safe_number(hero, "GetHealthRegen", 0), "hero", 150
        )
    else
        fields[#fields + 1] = field(
            "hero_unavailable", "英雄信息", "尚未召唤英雄", "hero", 100
        )
    end
    return fields
end

local function normalize_fields(source)
    local result = {}
    local seen = {}
    for _, entry in ipairs(source or {}) do
        local id = tostring(entry and entry.id or "")
        if id ~= "" and not seen[id] then
            seen[id] = true
            result[#result + 1] = {
                id = id,
                label = tostring(entry.label or id),
                value = entry.value == nil and "" or entry.value,
                suffix = tostring(entry.suffix or ""),
                group = tostring(entry.group or "other"),
                order = number(entry.order, 9999),
                visible = (entry.visible == false or entry.visible == 0) and 0 or 1,
                dynamic_source = tostring(entry.dynamic_source or ""),
            }
        end
    end
    table.sort(result, function(left, right)
        if left.order == right.order then return left.id < right.id end
        return left.order < right.order
    end)
    return result
end

local function build_snapshot(player_id, reason)
    local combat_response = event_bus.request(
        events.HERO_COMBAT_STATS_GET_REQUEST,
        { player_id = player_id }
    )
    local technology_response = event_bus.request(
        events.TECHNOLOGY_STATS_GET_REQUEST,
        { player_id = player_id }
    )
    local combat = combat_response and combat_response.ok
        and combat_response.snapshot or nil
    local technology = technology_response and technology_response.ok
        and technology_response.snapshot or { final = {} }
    local context = {
        player_id = player_id,
        combat = combat,
        technology = technology,
        hero = resolve_hero(combat),
    }
    local fields = default_fields(context)
    for _, provider in ipairs(providers) do
        local ok, provided = pcall(provider.callback, context)
        if ok and type(provided) == "table" then
            for _, entry in ipairs(provided) do fields[#fields + 1] = entry end
        elseif not ok then
            print("[GAME_INFO] provider_error id=" .. provider.id
                .. " error=" .. tostring(provided))
        end
    end
    return {
        version = 1,
        player_id = player_id,
        hero_entindex = combat and number(combat.entindex, -1) or -1,
        reason = reason or "refresh",
        fields = normalize_fields(fields),
    }
end

function M.register_provider(id, callback)
    assert(type(id) == "string" and id ~= "", "provider id must be a string")
    assert(type(callback) == "function", "provider callback must be a function")
    for _, provider in ipairs(providers) do
        assert(provider.id ~= id, "game info provider already registered: " .. id)
    end
    providers[#providers + 1] = { id = id, callback = callback }
end

function M.register_field(entry)
    assert(type(entry) == "table", "game info field must be a table")
    local id = tostring(entry.id or "")
    assert(id ~= "", "game info field id must not be empty")
    M.register_provider("field:" .. id, function()
        return { entry }
    end)
end

function M.publish_player(player_id, reason)
    player_id = tonumber(player_id)
    if player_id == nil or not CustomNetTables then return nil end
    local snapshot = build_snapshot(player_id, reason)
    CustomNetTables:SetTableValue(
        "survival_game_info",
        "player_" .. tostring(player_id),
        snapshot
    )
    return snapshot
end

local function publish_payload(payload)
    local player_id = tonumber(payload and payload.player_id)
    if player_id ~= nil then M.publish_player(player_id, payload.reason) end
end

function M.init()
    event_bus.subscribe(events.HERO_SUMMONED, publish_payload)
    event_bus.subscribe(events.HERO_COMBAT_STATS_CHANGED, publish_payload)
    event_bus.subscribe(events.TECHNOLOGY_STATS_CHANGED, publish_payload)
    event_bus.subscribe(events.EQUIPMENT_STATS_CHANGED, publish_payload)
    CustomGameEventManager:RegisterListener("ui_game_info_request", function(_, payload)
        local player_id = tonumber(payload and payload.PlayerID)
        if player_id == nil or not PlayerResource:IsValidPlayerID(player_id) then return end
        M.publish_player(player_id, "client_request")
    end)
end

M._test = {
    default_fields = default_fields,
    normalize_fields = normalize_fields,
}

return M