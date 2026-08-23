local event_bus = require("core/event_bus")
local events = require("core/events")
local production_definitions = require("config/generated/star_blessing_reward_definitions")

local M = {}

local function active_definitions()
    local tools_mode = type(IsInToolsMode) == "function" and IsInToolsMode()
    local fixture = ""
    if tools_mode and Convars and type(Convars.GetStr) == "function" then
        fixture = tostring(Convars:GetStr("survival_fishing_reward_fixture") or "")
    end
    if tools_mode and fixture == "automation_9001" then
        return require("tests/generated_fishing_reward_definitions")
    end
    return production_definitions
end

local function reward_definition(payload)
    local reward_id = tostring(payload and payload.reward_id or "")
    local version = tonumber(payload and payload.definition_version)
    local row = active_definitions().by_id[reward_id]
    if row and tonumber(row.definition_version) == version
        and row.enabled == true and row.effect_scope == "permanent" then
        return row
    end
    return nil
end

local function player_name(player_id)
    if PlayerResource and type(PlayerResource.GetPlayerName) == "function" then
        local value = tostring(PlayerResource:GetPlayerName(player_id) or "")
        value = value:gsub("[%c]", " "):gsub("^%s+", ""):gsub("%s+$", "")
        if value ~= "" then return value end
    end
    return "玩家" .. tostring(player_id)
end

local function amount_text(amount)
    amount = tonumber(amount) or 0
    if amount == math.floor(amount) then return string.format("%.0f", amount) end
    return tostring(amount)
end

local function announce(payload)
    local row = reward_definition(payload)
    local player_id = tonumber(payload and payload.player_id)
    local amount = tonumber(payload and payload.amount)
    if not row or player_id == nil or amount == nil or amount < 0 then return end
    event_bus.emit(events.UI_NOTIFICATION, {
        audience = "all",
        message = player_name(player_id) .. " 获得星之庇佑："
            .. tostring(row.display_name) .. "（" .. amount_text(amount) .. "）",
        level = "info",
    })
    print("[StarBlessing] reward_announced player_id=" .. tostring(player_id)
        .. " reward_id=" .. tostring(row.reward_id)
        .. " amount=" .. tostring(amount))
end

function M.init()
    event_bus.subscribe(events.FISHING_REWARD_GRANTED, announce)
end

M._test = { announce = announce, reward_definition = reward_definition }

return M