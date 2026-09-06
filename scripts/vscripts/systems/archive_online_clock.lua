-- Server-only connected-time observation. No client can submit elapsed time or currency.
local calendar = require("systems/archive_calendar")
local M = {}
local states, submit, session = {}, nil, nil

local function connected(id)
    return PlayerResource and PlayerResource.GetConnectionState
        and PlayerResource:GetConnectionState(id) == (DOTA_CONNECTION_STATE_CONNECTED or 2)
end

local function pass_until(profile)
    local e = profile and profile.entitlements and profile.entitlements.archive_pass
    if not e or e.active ~= true then return 0 end
    if e.expires_at == nil then return math.huge end
    return tonumber(e.expires_at) or 0
end

local function checkpoint(id, s)
    local raw, weighted = math.floor(s.raw), math.floor(s.weighted)
    if raw <= s.sent then return end
    -- Absolute counters make an older retry safe even after a newer checkpoint commits.
    s.sent = raw
    submit(id, { id = session .. ":online:" .. raw, kind = "online_checkpoint", session = session,
        actual_seconds = raw, map_seconds = weighted })
end

function M.observe(id, profile)
    if states[id] then return end
    states[id] = { at = calendar.now(), connected = connected(id), pass_until = pass_until(profile),
        raw = 0, weighted = 0, sent = 0 }
end

function M.sample(id, profile)
    M.observe(id, profile)
    local s, now = states[id], calendar.now()
    local online, elapsed = connected(id), now - states[id].at
    if s.connected and online and elapsed > 0 and elapsed <= 5 then
        -- Split the last second at entitlement expiry; later purchases never double earlier time.
        local bonus = math.max(0, math.min(now, s.pass_until) - s.at)
        s.raw = s.raw + elapsed
        s.weighted = s.weighted + elapsed + bonus
    end
    local disconnected = s.connected and not online
    s.at, s.connected, s.pass_until = now, online, pass_until(profile)
    if s.raw - s.sent >= 60 or disconnected then checkpoint(id, s) end
end

function M.flush(id)
    if states[id] then checkpoint(id, states[id]) end
end

function M.disconnect(id)
    local s = states[id]
    if not s then return end
    s.connected, s.at = false, calendar.now()
    checkpoint(id, s)
end

function M.init(match_session, callback)
    states, session, submit = {}, match_session, callback
end
return M
