-- Read-only, requester-only transport. Scores always come from the archive API.
local profiles = require("systems/player_profile_service")
local M = {}
local inflight, requested_at, generation = {}, {}, 0
local MAX_INTEGER = 9007199254740991

local function integer(value, minimum, maximum)
    return type(value) == "number" and value == value and value >= minimum
        and value <= maximum and value == math.floor(value)
end

local function steam_id(account)
    local value = tonumber(account)
    if not integer(value, 1, 4294967295) then return nil end
    -- Split into decimal limbs; adding a SteamID64 as a Lua double loses bits.
    local low = 960265728 + value
    return string.format("%d%09d", 76561197 + math.floor(low / 1000000000), low % 1000000000)
end

local function digest(value)
    return type(value) == "string" and #value == 64 and not value:find("[^0-9a-f]")
end

local function entry_id(value)
    return type(value) == "string" and #value == 36 and not value:find("[^0-9a-f%-]")
        and value:sub(9, 9) == "-" and value:sub(14, 14) == "-"
        and value:sub(19, 19) == "-" and value:sub(24, 24) == "-"
        and select(2, value:gsub("%-", "")) == 4
end

local function now()
    if type(Time) == "function" then return Time() end
    return GameRules and GameRules:GetGameTime() or 0
end

local function send(player_id, packet)
    local player = PlayerResource and PlayerResource:GetPlayer(player_id)
    if player and CustomGameEventManager then
        CustomGameEventManager:Send_ServerToPlayer(player, "survival_leaderboard_result", packet)
    end
end

local function fail(player_id, request_id, message)
    send(player_id, { request_id = request_id, phase = "error", message = message })
end

local function validate(result, account, known)
    local own = steam_id(account)
    if type(result) ~= "table" or result.ok ~= true or not digest(result.revision)
        or not own or result.self_steam_id ~= own then return nil end
    if result.unchanged == true then
        if result.revision ~= known or not integer(result.total, 0, 100)
            or type(result.self) ~= "table" or type(result.self.listed) ~= "boolean" then return nil end
        return { revision = result.revision, total = result.total, self_steam_id = own,
            listed = result.self.listed and 1 or 0, unchanged = true }
    end
    if type(result.entries) ~= "table" or #result.entries > 100 then return nil end
    local rows, seen, seen_steam, listed, previous = {}, {}, {}, false, nil
    for index, row in ipairs(result.entries) do
        if type(row) ~= "table" or row.rank ~= index
            or not entry_id(row.entry_id) or seen[row.entry_id]
            or type(row.steam_id) ~= "string"
            or row.steam_id ~= "" and not row.steam_id:match("^%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d$")
            or row.steam_id ~= "" and seen_steam[row.steam_id] or not integer(row.best_floor, 1, MAX_INTEGER)
            or not integer(row.endless_score, 0, MAX_INTEGER)
            or row.vip_level ~= nil and not integer(row.vip_level, 0, 12)
            or row.vip_medal_level ~= nil and not integer(row.vip_medal_level, 0, 10) then return nil end
        if previous and (row.best_floor > previous.best_floor
            or row.best_floor == previous.best_floor and row.endless_score > previous.endless_score
            or row.best_floor == previous.best_floor and row.endless_score == previous.endless_score
                and row.entry_id <= previous.entry_id) then return nil end
        seen[row.entry_id] = true
        if row.steam_id ~= "" then seen_steam[row.steam_id] = true end
        if row.steam_id == own then listed = true end
        local item = { rank = index, entry_id = row.entry_id, steam_id = row.steam_id,
            display_name = row.steam_id == "" and "玩家资料待同步" or "",
            -- Preserve large counters across the native event value boundary.
            best_floor = string.format("%.0f", row.best_floor),
            endless_score = string.format("%.0f", row.endless_score) }
        item.vip_level, item.vip_medal_level = row.vip_level or 0, row.vip_medal_level or 0
        rows[index], previous = item, row
    end
    return { revision = result.revision, total = #rows, self_steam_id = own,
        listed = listed and 1 or 0, rows = rows }
end

function M.request(payload)
    if type(payload) ~= "table" then return end
    -- PlayerID is injected by Dota, never take a client-supplied account identity.
    local player_id, request_id = tonumber(payload.PlayerID), payload.request_id
    if not integer(player_id, 0, 63) or not PlayerResource
        or not PlayerResource:IsValidPlayerID(player_id) then return end
    if type(request_id) ~= "string" or #request_id < 8 or #request_id > 96
        or request_id:find("[^%w_.:%-]") then return end
    local known = digest(payload.known_revision) and payload.known_revision or ""
    local provider = profiles.get_provider()
    local account = provider and provider.resolve_account_id and provider.resolve_account_id(player_id)
    if not account or not steam_id(account) then
        fail(player_id, request_id, "当前玩家身份尚未就绪，请稍后重新打开") return
    end
    if not provider or type(provider.endless_leaderboard) ~= "function" then
        fail(player_id, request_id, "排行榜需要连接在线存档服务") return
    end
    if inflight[player_id] and inflight[player_id].account ~= tostring(account) then
        inflight[player_id], requested_at[player_id] = nil, nil
    end
    if inflight[player_id] or requested_at[player_id] and now() - requested_at[player_id] < 0.3 then
        fail(player_id, request_id, "排行榜正在查询，请稍后重新打开") return
    end
    requested_at[player_id] = now()
    local epoch, token = generation, { account = tostring(account) }
    inflight[player_id] = token
    local function current()
        return generation == epoch and inflight[player_id] == token
            and tostring(provider.resolve_account_id(player_id)) == tostring(account)
    end
    local function error()
        if not current() then return end
        inflight[player_id] = nil
        fail(player_id, request_id, "排行榜暂时无法连接，请稍后重新打开")
    end
    local ok = pcall(provider.endless_leaderboard, { account_id = tostring(account), revision = known }, function(result)
        if not current() then return end
        local data = validate(result, account, known)
        if not data then error() return end
        inflight[player_id] = nil
        local function packet(phase)
            return { request_id = request_id, phase = phase, revision = data.revision,
                total = data.total, self_steam_id = data.self_steam_id, listed = data.listed }
        end
        if data.unchanged then send(player_id, packet("unchanged")) return end
        send(player_id, packet("begin"))
        for _, row in ipairs(data.rows) do
            local part = packet("row");part.row = row;send(player_id, part)
        end
        send(player_id, packet("end"))
    end, error)
    if not ok then error() end
end

function M.init()
    generation = generation + 1
    inflight, requested_at = {}, {}
    CustomGameEventManager:RegisterListener("survival_leaderboard_request", function(_, payload) M.request(payload) end)
end

return M
