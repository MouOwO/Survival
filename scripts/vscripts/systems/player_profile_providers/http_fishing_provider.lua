local json_decoder = require("core/json_decoder")
local json_encoder = require("core/json_encoder")
local rules = require("config/generated/fishing_system_rules")

local M = {}
local active_rule = nil

local function convar(name)
    if Convars and type(Convars.GetStr) == "function" then
        return tostring(Convars:GetStr(name) or "")
    end
    return ""
end

local function request(path, payload, on_success, on_error)
    if not active_rule then on_error("fishing_rule_missing") return end
    local token = convar("survival_fishing_api_token")
    if token == "" then on_error("fishing_api_token_missing") return end
    local http = CreateHTTPRequestScriptVM(
        "POST", tostring(active_rule.api_base_url) .. path
    )
    if not http then on_error("http_request_create_failed") return end
    http:SetHTTPRequestHeaderValue("Authorization", "Bearer " .. token)
    http:SetHTTPRequestRawPostBody(
        "application/json; charset=utf-8", json_encoder.encode(payload)
    )
    if type(http.SetHTTPRequestAbsoluteTimeoutMS) == "function" then
        http:SetHTTPRequestAbsoluteTimeoutMS(8000)
    end
    http:Send(function(response)
        local status = tonumber(response and response.StatusCode) or 0
        if status ~= 200 then
            on_error("http_status_" .. tostring(status))
            return
        end
        local ok, decoded = pcall(
            json_decoder.decode, tostring(response.Body or "")
        )
        if not ok or type(decoded) ~= "table" then
            on_error("http_json_invalid")
            return
        end
        on_success(decoded)
    end)
end

function M.init()
    active_rule = nil
    for _, row in ipairs(rules.rows or {}) do
        if row.enabled ~= false then active_rule = row break end
    end
end

function M.resolve_account_id(player_id)
    player_id = tonumber(player_id)
    if player_id == nil or not PlayerResource
        or type(PlayerResource.GetSteamAccountID) ~= "function" then
        return nil
    end
    local account_id = tonumber(PlayerResource:GetSteamAccountID(player_id))
    if not account_id or account_id <= 0 then return nil end
    return string.format("%.0f", account_id)
end

function M.fetch_snapshot(account_id, on_success, on_error)
    request("/v1/profile", { account_id = tostring(account_id) },
        on_success, on_error)
end

function M.online_checkpoint(payload, on_success, on_error)
    request("/v1/online-time/checkpoint", payload, on_success, on_error)
end

function M.heartbeat(payload, on_success, on_error)
    request("/v1/fishing/heartbeat", payload, on_success, on_error)
end

function M.rule()
    return active_rule
end

return M