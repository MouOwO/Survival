local json_decoder = require("core/json_decoder")
local json_encoder = require("core/json_encoder")
local rules = require("config/generated/fishing_system_rules")
local mode_test = require("debug/mode_unlock_test")
local workshop = require("systems/workshop_connection")
local web_auth = require("systems/player_web_auth")
local profile_wire = require("systems/http_profile_wire")

local M = {}
local active_rule = nil
local logged_in = {}
local endless_batch_capability
local operation_timing_serial=0
local timed_commands={lottery_draw=true,daily_claim=true,benefit_claim=true,vip_claim=true,
    commerce_purchase=true,redemption_redeem=true,building_upgrade=true,work_upgrade=true}
local test_read_paths = {
    ["/v1/session/authenticate"] = true, ["/v1/session/login"] = true,
    ["/v1/profile"] = true, ["/v1/lottery/catalog"] = true,
    ["/v1/lottery/snapshot"] = true, ["/v1/archive/config"] = true,
    ["/v1/archive/endless-leaderboard"] = true,
}

local function profile_mode(setup)
    return type(setup.get_profile_mode) == "function"
        and setup.get_profile_mode() or setup.get_mode()
end

local function convar(name)
    if Convars and type(Convars.GetStr) == "function" then
        return tostring(Convars:GetStr(name) or "")
    end
    return ""
end

-- Real user operations only: no polling, profile reads or automatic reward
-- events. Fixed scalar fields, one bounded line per attempt, no identity,
-- tokens, command IDs, error text or response content. These spans nest:
-- profile_ms is inside callback_ms, not an extra part of total_ms.
local function operation_timing(path,payload)
    local command=type(payload)=='table'and payload.command
    local kind=type(command)=='table'and command.kind
    if path~='/v1/archive/command'or not timed_commands[kind]or type(GetSystemTimeMS)~='function'then return nil end
    local function clock()
        local ok,value=pcall(GetSystemTimeMS)
        if ok and type(value)=='number'and value==value and value~=math.huge and value~=-math.huge then return value end
    end
    local started=clock();if not started then return nil end
    local function span(first,last)
        if not first or not last then return 0 end
        return math.min(600000,math.max(0,last-first))
    end
    operation_timing_serial=operation_timing_serial%1000000000+1
    local trace={serial=operation_timing_serial,resolve_ms=0,encode_ms=0,http_ms=0,decode_ms=0,
        callback_ms=0,profile_ms=0,request_bytes=0,response_bytes=0}
    local sent,received,decode_started,emitted
    function trace.resolved()trace.resolve_ms=span(started,clock())end
    function trace.encoded(first,bytes)trace.encode_ms=span(first,clock());trace.request_bytes=bytes end
    function trace.sent()sent=clock()end
    function trace.received(bytes,status)
        received=clock();trace.http_ms=span(sent,received);trace.response_bytes=bytes;decode_started=received;trace.status=status
    end
    function trace.decoded()trace.decode_ms=span(decode_started,clock())end
    function trace.profile(apply)
        local first=clock()
        local ok,value=pcall(apply)
        trace.profile_ms=trace.profile_ms+span(first,clock())
        if not ok then error(value,0)end
        return value
    end
    function trace.complete(callback,status)
        local first=clock()
        local ok,value=pcall(callback)
        trace.callback_ms=span(first,clock())
        if not emitted then
            emitted=true
            status=tonumber(status~=nil and status or trace.status)or 0
            if status~=status or status<0 or status>599 then status=0 end
            local count=kind=='lottery_draw'and(command.count==1 or command.count==10)and command.count or 0
            local line=string.format('[ARCHIVE_HTTP_TIMING] seq=%d kind=%s count=%d status=%d resolve_ms=%.3f encode_ms=%.3f http_ms=%.3f decode_ms=%.3f callback_ms=%.3f profile_ms=%.3f total_ms=%.3f request_bytes=%d response_bytes=%d callback_error=%d',
                trace.serial,kind,count,status,trace.resolve_ms,trace.encode_ms,trace.http_ms,trace.decode_ms,
                trace.callback_ms,math.min(600000,trace.profile_ms),span(started,clock()),
                math.min(33554432,trace.request_bytes),math.min(33554432,trace.response_bytes),ok and 0 or 1)
            if #line<=768 then pcall(print,line)end
        end
        if not ok then error(value,0)end
        return value
    end
    trace.clock=clock
    return trace
end

local function request(path, payload, on_success, on_error)
    local trace=operation_timing(path,payload)
    if trace then
        local success,failure=on_success,on_error
        on_success=function(value)return trace.complete(function()return success(value,trace)end,200)end
        on_error=function(reason,status)return trace.complete(function()return failure(reason,status)end,status)end
    end
    if not active_rule then on_error("fishing_rule_missing") return end
    if mode_test.is_enabled() and not test_read_paths[path] then
        on_error("mode_unlock_test_read_only") return
    end
    local setup = require("systems/match_setup_service")
    if path ~= "/v1/session/authenticate" and path ~= "/v1/lottery/catalog" and not setup.is_mode_selected() then
        on_error("mode_not_selected") return
    end
    local session = setup.get_session_id()
    if type(session) ~= "string" or #session < 8 then on_error("match_session_missing") return end
    local body = {}
    for key, value in pairs(payload) do body[key] = value end
    if path=='/v1/archive/command'then
        local capabilities={}
        for key,value in pairs(type(body.response_capabilities)=='table'and body.response_capabilities or{})do capabilities[key]=value end
        capabilities.archive_profile_refs_v1=true
        body.response_capabilities=capabilities
    end
    body.match_session_id = session
    if path == "/v1/session/login" then
        -- The durable session keeps the gameplay identity even though advanced
        -- combat/account projections use the ordinary standard profile.
        local game_mode = setup.get_mode()
        body.mode = (game_mode == "rich" or game_mode == "cold" or game_mode == "scourge")
            and game_mode or profile_mode(setup)
        -- Test arenas borrow only the ordinary combat view. They never create
        -- an advanced durable session or submit test clears to the backend.
        if mode_test.is_enabled() then body.mode = profile_mode(setup) end
    end
    local function send(url, token)
        if trace then trace.resolved()end
        if setup.get_session_id() ~= session then on_error("match_session_changed") return end
        if token == "" then on_error("fishing_api_token_missing") return end
        local http = CreateHTTPRequestScriptVM("POST", tostring(url) .. path)
        if not http then on_error("http_request_create_failed") return end
        http:SetHTTPRequestHeaderValue("Authorization", "Bearer " .. token)
        local encode_started=trace and trace.clock()
        local encoded=json_encoder.encode(body)
        if trace then trace.encoded(encode_started,#encoded)end
        http:SetHTTPRequestRawPostBody("application/json; charset=utf-8", encoded)
        if type(http.SetHTTPRequestAbsoluteTimeoutMS) == "function" then
            http:SetHTTPRequestAbsoluteTimeoutMS(30000)
        end
        if trace then trace.sent()end
        http:Send(function(response)
            local status = tonumber(response and response.StatusCode) or 0
            if trace then trace.received(#tostring(response and response.Body or ''),status)end
            if status ~= 200 then
                local parsed, response_body = pcall(json_decoder.decode, tostring(response and response.Body or ""))
                if trace then trace.decoded()end
                on_error(workshop.failure(parsed and response_body or nil, "http_status_" .. tostring(status)), status)
                return
            end
            local ok, decoded = pcall(json_decoder.decode, tostring(response.Body or ""))
            if not ok or type(decoded) ~= "table" then
                if trace then trace.decoded()end
                on_error("http_json_invalid") return
            end
            if path=='/v1/archive/command'then
                decoded=profile_wire.decode(decoded)
                if not decoded then
                    if trace then trace.decoded()end
                    -- A malformed representation may follow a successful grant.
                    -- Do not retry the mutation; the adapter performs one read.
                    on_success({ok=false,terminal=true,error='http_profile_wire_invalid',
                        http_profile_resync=true,recovery_session=session})
                    return
                end
            end
            if trace then trace.decoded()end
            on_success(decoded)
        end)
    end
    if web_auth.enabled() then
        if path == "/v1/lottery/catalog" and body.account_id == nil then
            local account, url, token = web_auth.authorized_account(session)
            if not account then on_error("player_web_auth_pending") return end
            body.account_id = account
            send(url, token)
        else
            web_auth.resolve(body.account_id, session, send, on_error)
        end
    else
        local url, token, connection_error = workshop.resolve(active_rule.api_base_url, convar("survival_fishing_api_token"))
        if connection_error then on_error(connection_error) return end
        send(url, token)
    end
end

function M.init()
    active_rule = nil
    logged_in = {}
    endless_batch_capability = nil
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
    local session, mode = setup.get_session_id(), profile_mode(setup)
    local path = logged_in[tostring(account_id)] == session and "/v1/profile" or "/v1/session/login"
    request(path, { account_id = tostring(account_id) }, function(snapshot)
        if snapshot.account_id ~= tostring(account_id) or snapshot.match_session_id ~= session
            or snapshot.mode ~= mode or setup.get_session_id() ~= session or profile_mode(setup) ~= mode then
            on_error("match_profile_mismatch") return
        end
        local game_mode = setup.get_mode()
        if mode_test.is_enabled() then
            snapshot.game_mode, snapshot.debug_mode_unlock = game_mode, 1
        end
        if (game_mode == "rich" or game_mode == "cold" or game_mode == "scourge")
            and snapshot.game_mode ~= game_mode then
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

function M.endless_leaderboard(payload, on_success, on_error)
    request("/v1/archive/endless-leaderboard", payload, on_success, on_error)
end

function M.archive_submit_endless_batch(payload, on_success, on_error)
    local function send_batch()
        if endless_batch_capability then
            request("/v1/archive/endless-batch",payload,on_success,function(error,status)
                if status==404 then endless_batch_capability=false;send_batch()
                else on_error(error,status) end
            end)
            return
        end
        -- A previous server keeps the single-intent protocol. Submit only
        -- the bounded batch selected by archive_service, then return one
        -- authoritative profile to the game after its final receipt.
        local results, index, profile = {}, 1, nil
        local function submit_next()
            local command=payload.commands[index]
            if not command then on_success({ok=true,results=results,profile=profile});return end
            M.archive_submit({account_id=payload.account_id,config_hash=payload.config_hash,command=command},function(result)
                profile=result.profile or profile
                local terminal=result.terminal==true and result.error~="archive_config_mismatch"
                results[#results+1]={id=command.id,ok=result.ok==true,terminal=terminal,error=result.error}
                if not result.ok and not terminal then
                    on_success({ok=false,error=result.error,results=results,profile=profile});return
                end
                index=index+1;submit_next()
            end,function(error,status)
                on_success({ok=false,error=error,results=results,profile=profile})
            end)
        end
        submit_next()
    end
    if endless_batch_capability~=nil then send_batch();return end
    request("/v1/archive/config",{account_id=payload.account_id},function(result)
        endless_batch_capability=result.capabilities and result.capabilities.endless_batch==1 or false
        send_batch()
    end,on_error)
end

function M.lottery_snapshot(payload, on_success, on_error)
    request("/v1/lottery/snapshot", payload, on_success, on_error)
end

function M.lottery_catalog(payload, on_success, on_error)
    -- Public display metadata is available during admission. Keep the same
    -- authenticated HTTP transport; account snapshots remain mode-gated.
    request("/v1/lottery/catalog", payload, on_success, on_error)
end

function M.rule()
    return active_rule
end

return M
