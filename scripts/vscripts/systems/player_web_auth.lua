-- Browser approval establishes a player/account/match capability. Neither the
-- private device code nor the resulting bearer is ever sent to a game client.
local config = require("config/player_web_auth")
local encoder = require("core/json_encoder")
local decoder = require("core/json_decoder")
local access = require("core/test_access_policy")
local M = {}
local BASE = "https://pay.xiaofengnet.com/ws4-web"
local DIAGNOSTIC_REVISION = "WS4-WEB-04"
local DIAGNOSTIC_PHASES = { start = true, poll = true }
local DIAGNOSTIC_STAGES = { API = true, create = true, send = true, http = true,
    json = true, fields = true, timeout = true }
local FAILURE_CODES = { player_web_auth_expired = true, player_web_auth_unavailable = true,
    player_web_auth_invalid_response = true, player_web_auth_binding_changed = true,
    player_web_auth_configuration_invalid = true }
local epoch, active_session, records, listener = 0, nil, {}, nil

local function server()
    if type(IsServer) ~= "function" then return false end
    local ok, value = pcall(IsServer)
    return ok and value == true
end

local function now()
    return type(Time) == "function" and Time() or os.clock()
end

local function resource(method, id)
    if not PlayerResource or type(PlayerResource[method]) ~= "function" then return nil end
    local ok, result = pcall(PlayerResource[method], PlayerResource, id)
    return ok and result or nil
end

local function account_for(id)
    local value = tonumber(resource("GetSteamAccountID", id))
    if not value or value < 1 or value > 4294967295 or value ~= math.floor(value) then return nil end
    return string.format("%.0f", value)
end

local function human(id)
    if not resource("IsValidPlayerID", id) or resource("IsFakeClient", id) then return false end
    if resource("GetTeam", id) == (DOTA_TEAM_SPECTATOR or 1) then return false end
    if not access.allowed(id) then return false end
    local state = resource("GetConnectionState", id)
    return resource("GetPlayer", id) ~= nil
        and (state == nil or state == (DOTA_CONNECTION_STATE_CONNECTED or 2))
end

local function find_player(account)
    local found
    for id = 0, (DOTA_MAX_TEAM_PLAYERS or 24) - 1 do
        if human(id) and account_for(id) == account then
            if found then return nil end -- Never bind an account to two slots.
            found = { id = id, player = resource("GetPlayer", id) }
        end
    end
    return found
end

local function current(record)
    return record.epoch == epoch and record.session == active_session
        and records[record.account] == record and human(record.id)
        and resource("GetPlayer", record.id) == record.player
        and account_for(record.id) == record.account
end

local function public_state(record, explicit_snapshot)
    if not current(record) or not CustomGameEventManager
        or type(CustomGameEventManager.Send_ServerToPlayer) ~= "function" then return end
    -- Compare a fixed tuple. Wall-clock expiry countdown is not new state.
    -- No JSON serialization/hash, timer or collection scan occurs here.
    local diagnostic = record.status == "failed" and record.diagnostic or nil
    local status = record.status or "requesting"
    local error = FAILURE_CODES[record.error] and record.error or ""
    local code = status == "pending" and record.user_code or ""
    local uri = status == "pending" and record.verification_uri or ""
    local expiry = record.code_expires or 0
    local revision = diagnostic and DIAGNOSTIC_REVISION or ""
    local phase = diagnostic and diagnostic.phase or ""
    local stage = diagnostic and diagnostic.stage or ""
    local diagnostic_status = diagnostic and diagnostic.status or 0
    local last = record.last_public_state
    local same = last and last.status == status and last.error == error
        and last.code == code and last.uri == uri and last.expiry == expiry
        and last.revision == revision and last.phase == phase and last.stage == stage
        and last.diagnostic_status == diagnostic_status
    local explicit_stamp
    if same then
        if not explicit_snapshot then return end
        -- A fresh private UI request can recover a late subscription. Coalesce
        -- same-second duplicate requests; this never schedules periodic sends.
        local stamp = now()
        if record.last_explicit_snapshot_at
            and stamp - record.last_explicit_snapshot_at < 1 then return end
        explicit_stamp = stamp
    end
    local published = {status=status,error=error,code=code,uri=uri,
        expiry=expiry,revision=revision,phase=phase,stage=stage,diagnostic_status=diagnostic_status}
    -- One sparse, non-sensitive marker per actual native send, so native
    -- review can distinguish recovery input from unsolicited state repeats.
    print("[PLAYER_WEB_AUTH_PUBLIC] reason=" .. (same and "explicit_snapshot" or "state_change")
        .. " status=" .. status)
    CustomGameEventManager:Send_ServerToPlayer(record.player, "survival_player_web_auth_state", {
        session_id = record.session, player_id = record.id,
        status = status, error = error, user_code = code, verification_uri = uri,
        expires_in = math.max(0, math.floor(expiry - now())),
        diagnostic_revision = revision,
        diagnostic_phase = phase, diagnostic_stage = stage,
        diagnostic_status = diagnostic_status,
    })
    -- The native API accepts a void return. A thrown send cannot poison the
    -- memo or consume the explicit recovery allowance.
    record.last_public_state = published
    if explicit_stamp then record.last_explicit_snapshot_at = explicit_stamp end
end

local function bounded_number(value, minimum, maximum)
    return type(value) == "number" and value == value and value >= minimum and value <= maximum
end

local function secret(value)
    return type(value) == "string" and #value >= 24 and #value <= 512
        and value:match("^[A-Za-z0-9_%.~%-]+$") ~= nil
end

local function verification(code, uri)
    if type(code) ~= "string" or #code < 6 or #code > 16
        or not code:match("^[A-Z0-9%-]+$") then return nil end
    local expected = BASE .. "/authorize?code=" .. code
    if uri == "/authorize?code=" .. code then return expected end
    return uri == expected and expected or nil
end

local function http_status(value)
    local status = tonumber(value)
    if not status or status ~= status or status < 0 or status > 599 or status ~= math.floor(status) then return 0 end
    return status
end

local function fail(record, code, callback, phase, stage, status)
    if not current(record) then return end
    code = FAILURE_CODES[code] and code or "player_web_auth_unavailable"
    record.status, record.error = code == "player_web_auth_expired" and "expired" or "failed", code
    record.diagnostic = nil
    if DIAGNOSTIC_PHASES[phase] and DIAGNOSTIC_STAGES[stage] then
        status = http_status(status)
        record.diagnostic = { phase = phase, stage = stage, status = status }
        local key = phase .. ":" .. stage .. ":" .. tostring(status)
        if record.diagnostic_log_key ~= key or now() - (record.diagnostic_log_at or -100) >= 30 then
            record.diagnostic_log_key, record.diagnostic_log_at = key, now()
            print("[" .. DIAGNOSTIC_REVISION .. "] phase=" .. phase .. " stage=" .. stage .. " status=" .. tostring(status))
        end
    end
    public_state(record)
    callback(code)
end

local function request(record, path, payload, success, failure)
    local phase = path == "/v1/player-auth/start" and "start" or "poll"
    record.request_phase = phase
    if type(CreateHTTPRequestScriptVM) ~= "function" then
        fail(record, "player_web_auth_unavailable", failure, phase, "API", 0) return
    end
    local created, http = pcall(CreateHTTPRequestScriptVM, "POST", BASE .. path)
    if not created or not http then fail(record, "player_web_auth_unavailable", failure, phase, "create", 0) return end
    record.serial = (record.serial or 0) + 1
    local serial = record.serial
    record.inflight, record.deadline = true, now() + 15
    local sent, accepted = pcall(function()
      http:SetHTTPRequestRawPostBody("application/json; charset=utf-8", encoder.encode(payload))
      if type(http.SetHTTPRequestAbsoluteTimeoutMS) == "function" then http:SetHTTPRequestAbsoluteTimeoutMS(10000) end
      return http:Send(function(response)
        if not current(record) or record.serial ~= serial or not record.inflight then return end
        record.inflight = false
        local status = http_status(type(response) == "table" and response.StatusCode or nil)
        if type(response) ~= "table" or status ~= 200 then
            fail(record, "player_web_auth_unavailable", failure, phase, "http", status) return
        end
        local raw = response.Body
        if type(raw) ~= "string" or #raw > 16384 then
            fail(record, "player_web_auth_invalid_response", failure, phase, "json", status) return
        end
        local ok, body = pcall(decoder.decode, raw)
        if not ok or type(body) ~= "table" then
            fail(record, "player_web_auth_invalid_response", failure, phase, "json", status) return
        end
        if body.ok ~= true then
            fail(record, "player_web_auth_invalid_response", failure, phase, "fields", status) return
        end
        success(body)
      end)
    end)
    if (not sent or accepted == false) and current(record) and record.serial == serial and record.inflight then
        record.inflight = false
        fail(record, "player_web_auth_unavailable", failure, phase, "send", 0)
    end
end

function M.enabled()
    -- The independent lobby may authenticate identity without loading profiles
    -- or granting access to cloud saves in the memory-only battle map.
    if type(GetMapName) == "function" then
        local ok, map = pcall(GetMapName)
        if ok and map == "ws4_lobby" then
            local loaded, lobby = pcall(require, "config/hosted_lobby")
            return loaded and type(lobby) == "table" and lobby.enabled == true
                and lobby.expected_map == "ws4_lobby" and lobby.base_url == BASE
        end
    end
    return config.enabled == true
end

function M.authorized_account(session)
    if not server() or not M.enabled() or config.base_url ~= BASE or session ~= active_session then return nil end
    local selected
    for _, record in pairs(records) do
        if current(record) and record.token and now() < record.token_expires
            and (not selected or record.id < selected.id) then selected = record end
    end
    if not selected then return nil end
    -- Only a server-side, read-only metadata caller may consume these extra
    -- return values. Looking up metadata never starts/polls an approval flow.
    return selected.account, BASE, selected.token
end

function M.invalidate(account, session)
    -- Only a server-side owner of this exact binding may discard a rejected
    -- grant. Old asynchronous callbacks fail current(record) after removal.
    if not server() or session ~= active_session then return false end
    local record = records[account]
    if not record or not current(record) then return false end
    records[account] = nil
    return true
end

function M.resolve(account, session, success, failure)
    if not server() or not M.enabled() or config.base_url ~= BASE then
        failure("player_web_auth_configuration_invalid") return
    end
    if type(account) ~= "string" or not account:match("^[1-9]%d*$") or #account > 10
        or type(session) ~= "string" or #session < 8 or #session > 128
        or not session:match("^[A-Za-z0-9_.:%-]+$") or session ~= active_session then
        failure("player_web_auth_binding_changed") return
    end
    local player = find_player(account)
    if not player then failure("player_web_auth_binding_changed") return end
    local record = records[account]
    if not record or not current(record) then
        record = { account = account, session = session, epoch = epoch, id = player.id,
            player = player.player, status = "requesting", next_poll = 0 }
        records[account] = record
    end
    if record.token and now() < record.token_expires then
        success(BASE, record.token) return
    end
    record.token, record.token_expires = nil, nil
    if record.inflight and now() < record.deadline then
        public_state(record) failure("player_web_auth_pending") return
    end
    if record.inflight then
        record.serial, record.inflight = record.serial + 1, false
        fail(record, "player_web_auth_unavailable", failure, record.request_phase, "timeout", 0) return
    end
    if record.device_code and now() >= record.code_expires then
        record.device_code, record.user_code, record.verification_uri = nil, nil, nil
        fail(record, "player_web_auth_expired", failure) return
    end
    if record.device_code then
        if now() < record.next_poll then public_state(record) failure("player_web_auth_pending") return end
        record.next_poll = now() + record.poll_interval
        request(record, "/v1/player-auth/poll", { account_id = account, match_session_id = session,
            device_code = record.device_code }, function(body)
            if body.status == "pending" then
                record.status, record.error, record.diagnostic = "pending", nil, nil
                public_state(record) failure("player_web_auth_pending") return
            end
            if body.status ~= "approved" or body.account_id ~= account or body.match_session_id ~= session
                or not secret(body.access_token) or not bounded_number(body.expires_in, 5, 86400) then
                fail(record, "player_web_auth_invalid_response", failure, "poll", "fields", 200) return
            end
            record.token, record.token_expires = body.access_token, now() + body.expires_in - 2
            record.device_code, record.user_code, record.verification_uri = nil, nil, nil
            record.status, record.error, record.diagnostic = "approved", nil, nil
            public_state(record)
            success(BASE, record.token)
        end, failure)
        return
    end
    if now() < (record.next_start or 0) then public_state(record) failure("player_web_auth_pending") return end
    record.next_start = now() + 3
    record.status, record.error, record.diagnostic = "requesting", nil, nil
    public_state(record)
    request(record, "/v1/player-auth/start", { account_id = account, match_session_id = session }, function(body)
        local uri = verification(body.user_code, body.verification_uri)
        if body.status ~= "pending" or not secret(body.device_code) or not uri
            or not bounded_number(body.expires_in, 10, 3600)
            or not bounded_number(body.poll_interval, 1, 30) then
            fail(record, "player_web_auth_invalid_response", failure, "start", "fields", 200) return
        end
        record.device_code, record.user_code, record.verification_uri = body.device_code, body.user_code, uri
        record.code_expires, record.poll_interval = now() + body.expires_in, math.max(3, body.poll_interval)
        record.next_poll, record.status, record.diagnostic = now() + record.poll_interval, "pending", nil
        public_state(record)
        failure("player_web_auth_pending")
    end, failure)
end

function M.init(session)
    epoch, active_session, records = epoch + 1, session, {}
    if listener and CustomGameEventManager and type(CustomGameEventManager.UnregisterListener) == "function" then
        CustomGameEventManager:UnregisterListener(listener)
    end
    listener = nil
    if not server() or not M.enabled() or not CustomGameEventManager
        or type(CustomGameEventManager.RegisterListener) ~= "function" then return end
    local generation = epoch
    listener = CustomGameEventManager:RegisterListener("survival_player_web_auth_request", function(source, payload)
        if epoch ~= generation or type(payload) ~= "table" or payload.session_id ~= active_session then return end
        local startup = package.loaded["systems/startup_loading_service"]
        if not startup or startup.is_ready() then return end
        local index = tonumber(source)
        if not index or index < 0 or index ~= math.floor(index) or type(EntIndexToHScript) ~= "function" then return end
        local ok, entity = pcall(EntIndexToHScript, index)
        if not ok or not entity or type(entity.GetPlayerID) ~= "function"
            or type(entity.IsNull) == "function" and entity:IsNull() then return end
        local resolved, id = pcall(entity.GetPlayerID, entity)
        if not resolved or type(id) ~= "number" or not human(id) or resource("GetPlayer", id) ~= entity then return end
        local account = account_for(id)
        local profiles = package.loaded["systems/player_profile_service"]
        if not account or profiles and profiles.is_authenticated_for_account(id, account) then return end
        -- Payload PlayerID/account fields never participate in identity resolution.
        local record = records[account]
        local last = record and record.last_public_state
        local rejected = false
        M.resolve(account, active_session, function() end, function(reason)
            rejected = reason == "player_web_auth_binding_changed"
                or reason == "player_web_auth_configuration_invalid"
        end)
        local resolved_record = records[account]
        if rejected or not resolved_record or resolved_record.id ~= id
            or resolved_record.player ~= entity or not current(resolved_record) then return end
        -- Count a validated UI input that actually caused an immediate state
        -- publication. This consumes its input ordinal, never a replay grant.
        if resolved_record.last_public_state and (resolved_record ~= record
            or resolved_record.last_public_state ~= last) then
            print("[PLAYER_WEB_AUTH_REQUEST] accepted=1 generation=" .. tostring(epoch)
                .. " slot=" .. tostring(id) .. " mode=state_change")
        -- Only a stable retained record needs a bounded subscriber snapshot.
        elseif last and (not record.last_explicit_snapshot_at
            or now() - record.last_explicit_snapshot_at >= 1) then
            -- Slot/epoch are local numbers, never account or session values.
            print("[PLAYER_WEB_AUTH_REQUEST] accepted=1 generation=" .. tostring(epoch)
                .. " slot=" .. tostring(id) .. " mode=explicit_snapshot")
            public_state(record, true)
        end
    end)
end

return M
