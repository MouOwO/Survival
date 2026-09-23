local json_decoder = require("core/json_decoder")
local json_encoder = require("core/json_encoder")
local rules = require("config/generated/fishing_system_rules")

local M = {}
local active_rule = nil
local logged_in = {}

local function convar(name)
    if Convars and type(Convars.GetStr) == "function" then
        return tostring(Convars:GetStr(name) or "")
    end
    return ""
end

local function request(path, payload, on_success, on_error)
    if not active_rule then on_error("fishing_rule_missing") return end
    local setup = require("systems/match_setup_service")
    if path ~= "/v1/session/authenticate" and not setup.is_mode_selected() then
        on_error("mode_not_selected") return
    end
    local session = setup.get_session_id()
    if type(session) ~= "string" or #session < 8 then on_error("match_session_missing") return end
    local body = {}
    for key, value in pairs(payload) do body[key] = value end
    body.match_session_id = session
    if path == "/v1/session/login" then body.mode = setup.get_mode() end
    local token = convar("survival_fishing_api_token")
    if token == "" then on_error("fishing_api_token_missing") return end
    local http = CreateHTTPRequestScriptVM(
        "POST", tostring(active_rule.api_base_url) .. path
    )
    if not http then on_error("http_request_create_failed") return end
    http:SetHTTPRequestHeaderValue("Authorization", "Bearer " .. token)
    http:SetHTTPRequestRawPostBody(
        "application/json; charset=utf-8", json_encoder.encode(body)
    )
    if type(http.SetHTTPRequestAbsoluteTimeoutMS) == "function" then
        http:SetHTTPRequestAbsoluteTimeoutMS(30000)
    end
    http:Send(function(response)
        local status = tonumber(response and response.StatusCode) or 0
        if status ~= 200 then
            local parsed, body = pcall(json_decoder.decode, tostring(response and response.Body or ""))
            on_error(parsed and type(body) == "table" and type(body.error) == "string"
                and body.error or "http_status_" .. tostring(status), status)
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
    logged_in = {}
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
    local setup = require("systems/match_setup_service")
    local session, mode = setup.get_session_id(), setup.get_mode()
    local path = logged_in[tostring(account_id)] == session and "/v1/profile" or "/v1/session/login"
    request(path, { account_id = tostring(account_id) }, function(snapshot)
        if snapshot.account_id ~= tostring(account_id) or snapshot.match_session_id ~= session
            or snapshot.mode ~= mode or setup.get_session_id() ~= session or setup.get_mode() ~= mode then
            on_error("match_profile_mismatch") return
        end
        logged_in[tostring(account_id)] = session
        on_success(snapshot)
    end, on_error)
end

function M.authenticate(account_id, on_success, on_error)
    -- Entry authentication returns only account/session identity and progression;
    -- it must neither populate logged_in nor let mode-gated requests proceed.
    local setup = require("systems/match_setup_service")
    local session = setup.get_session_id()
    request("/v1/session/authenticate", { account_id = tostring(account_id) }, function(result)
        if result.authenticated ~= true or result.account_id ~= tostring(account_id)
            or result.match_session_id ~= session or setup.get_session_id() ~= session then
            on_error("authentication_identity_mismatch") return
        end
        on_success(result)
    end, on_error)
end

function M.online_checkpoint(payload, on_success, on_error)
    request("/v1/online-time/checkpoint", payload, on_success, on_error)
end

function M.archive_enabled()
    return convar("survival_archive_http_enabled") == "1"
end

function M.archive_submit(payload, on_success, on_error)
    request("/v1/archive/command", payload, on_success, on_error)
end

function M.lottery_snapshot(payload, on_success, on_error)
    request("/v1/lottery/snapshot", payload, on_success, on_error)
end

function M.rule()
    return active_rule
end

return M
