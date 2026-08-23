local event_bus = require("core/event_bus")
local events = require("core/events")
local production_reward_definitions = require(
    "config/generated/fishing_reward_definitions"
)

local M = {}

local function active_reward_definitions()
    local tools_mode = type(IsInToolsMode) == "function" and IsInToolsMode()
    local fixture = ""
    if tools_mode and Convars and type(Convars.GetStr) == "function" then
        fixture = tostring(Convars:GetStr("survival_fishing_reward_fixture") or "")
    end
    if tools_mode and fixture == "automation_9001" then
        return require("tests/generated_fishing_reward_definitions")
    end
    return production_reward_definitions
end

local function reward_definition(payload)
    local reward_id = tostring(payload and payload.reward_id or "")
    if string.match(reward_id, "^star_blessing_") then return nil end
    local definition_version = tonumber(payload and payload.definition_version)
    for _, row in ipairs(active_reward_definitions().rows or {}) do
        if tostring(row.reward_id or "") == reward_id
            and tonumber(row.definition_version) == definition_version
            and row.enabled == true then
            return row
        end
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

local function announce_grant(payload)
    local definition = reward_definition(payload)
    local player_id = tonumber(payload and payload.player_id)
    local amount = tonumber(payload and payload.amount)
    if not definition or player_id == nil or amount == nil then return end
    event_bus.emit(events.UI_NOTIFICATION, {
        audience = "all",
        message = player_name(player_id) .. " 钓到了："
            .. tostring(definition.display_name) .. "（"
            .. amount_text(amount) .. "）",
        level = "info",
    })
end

-- Database-backed fishing is an out-of-match backend concern. These lifecycle
-- hooks intentionally remain no-ops so legacy addon callbacks cannot create a
-- permanent reward heartbeat while a match is running.
function M.connect(_player_id)
    return false, "out_of_match_fishing_only"
end

function M.disconnect(_player_id)
    return true
end

function M.init()
    event_bus.subscribe(events.FISHING_REWARD_GRANTED, announce_grant)
end

M._test = {
    announce_grant = announce_grant,
    reward_definition = reward_definition,
}

return M