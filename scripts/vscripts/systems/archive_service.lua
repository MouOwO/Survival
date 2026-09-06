local bus = require("core/event_bus")
local events = require("core/events")
local profiles = require("systems/player_profile_service")
local scheduler = require("core/scheduler")
local achievements = require("config/generated/archive_achievements")
local shadow_items = require("config/generated/archive_shadow_items")
local categories = require("config/generated/archive_categories")
local drop_rules = require("config/generated/archive_drop_rules")
local stats_config = require("config/generated/player_gameplay_stats")
local lottery = require("config/lottery_config")
local challenge_rewards = require("systems/archive_challenge_rewards")
local challenge_rules = require("config/generated/archive_challenge_rules").by_id.default
local M = {}
local pending, busy, selected, throttles = {}, {}, {}, {}
local session_id, serial, remote_provider
local server_clock
local daily_viewers, purchase_provider = {}, nil
local archive_players = {}

local function runtime_id()
    local parts = { "archive" }
    if os and type(os.time) == "function" then
        parts[#parts + 1] = tostring(os.time())
    elseif type(GetSystemDate) == "function" and type(GetSystemTime) == "function" then
        parts[#parts + 1] = tostring(GetSystemDate()) .. tostring(GetSystemTime())
    end
    if type(RandomInt) == "function" then
        for _ = 1, 4 do parts[#parts + 1] = string.format("%08x", RandomInt(0, 2147483647)) end
    end
    parts[#parts + 1] = tostring({})
    return string.gsub(table.concat(parts), "[^0-9A-Za-z]", "")
end

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for k, v in pairs(value) do result[k] = copy(v) end
    return result
end

local function integer(value)
    return type(value) == "number" and value == value and value >= 0
        and value < math.huge and value == math.floor(value)
end

local function saved(profile)
    local result = copy(profile.save.archive or {})
    result.version = 1
    result.clear_counts = result.clear_counts or {}
    result.completed = result.completed or {}
    result.shadow_counts = result.shadow_counts or {}
    result.processed = result.processed or {}
    return result
end

local function has_pass(profile)
    return require("systems/archive_calendar").has_pass(profile)
end

local function apply_effects(stats, item)
    assert(#item.effect_ids == #item.effect_values, "archive_effect_array_mismatch")
    for i, field in ipairs(item.effect_ids) do
        local definition = assert(stats_config.by_id[field], "archive_unknown_stat:" .. field)
        local delta = assert(tonumber(item.effect_values[i]), "archive_invalid_effect")
        local value = (tonumber(stats[field]) or tonumber(definition.default_value) or 0) + delta
        -- Gameplay schema limits (e.g. 100% damage reduction) are hard caps.
        if definition.max_value then value = math.min(value, definition.max_value) end
        if definition.min_value then value = math.max(value, definition.min_value) end
        assert(value == value and value < math.huge, "archive_nonfinite_stat")
        stats[field] = value
    end
end

local function enabled_categories()
    local result = {}
    for _, row in ipairs(categories.rows) do
        if row.enabled then
            result[#result + 1] = { id = row.category_id, name = row.display_name,
                renderer = row.renderer, order = row.sort_order }
        end
    end
    table.sort(result, function(a, b) return a.order < b.order end)
    return result
end

local renderers = {}
renderers.fishing = function(profile) return (require("systems/archive_fishing_view").project(profile)) end
renderers.map_level = function(_, archive) return require("systems/archive_online_rewards").rows(archive, "map_level") end
renderers.work = function(_, archive) return require("systems/archive_online_rewards").rows(archive, "work") end
renderers.friend = function(_, archive) return require("systems/archive_social_rewards").rows(archive, "friend") end
renderers.ex = function(_, archive) return require("systems/archive_social_rewards").rows(archive, "ex") end
renderers.beast = function(_, archive) return require("systems/archive_social_rewards").rows(archive, "beast") end
renderers.boss = function(profile) return (require("systems/archive_boss_rewards").project(profile)) end
renderers.endless = function(profile, archive)
    local rows = {}
    for _, item in ipairs(require("config/generated/archive_endless_achievements").rows) do
        if item.enabled then
            rows[#rows + 1] = { id = item.achievement_id, name = item.display_name .. "（" .. item.required_score .. "分）",
                description = item.description, icon_style = "seal", quality = "gold", rune = "∞",
                count = archive.endless_score or 0, target = item.required_score,
                completed = archive.completed[item.achievement_id] and 1 or 0 }
        end
    end
    return rows
end
renderers.fragment = challenge_rewards.fragment_rows
renderers.pet = challenge_rewards.cage_rows
renderers.clear = function(profile, archive)
    local rows = {}
    for _, item in ipairs(achievements.rows) do
        if item.enabled then
            rows[#rows + 1] = { id = item.achievement_id, name = item.display_name,
                description = item.description, icon_style = item.icon_style,
                rune = string.upper(item.difficulty_id), quality = "gold",
                count = archive.clear_counts[item.difficulty_id] or 0,
                target = item.required_count, completed = archive.completed[item.achievement_id] and 1 or 0 }
        end
    end
    return rows
end
renderers.shadow = function(profile, archive)
    local rows = {}
    for _, item in ipairs(shadow_items.rows) do
        if item.enabled and (tonumber(archive.shadow_counts[item.item_id]) or 0) > 0 then
            rows[#rows + 1] = { id = item.item_id, name = item.display_name,
                description = item.description, icon_style = item.icon_style,
                quality = item.quality, count = archive.shadow_counts[item.item_id], target = item.max_owned }
        end
    end
    return rows
end
renderers.points = function(profile)
    local rows = require("systems/archive_daily_rewards").points(profile)
    local counts = profile.save.content_inventory or {}
    for _, item in ipairs(lottery.items) do
        local count = tonumber(counts[item.id]) or 0
        if count > 0 and item.item_type == "积分道具" then
            rows[#rows + 1] = { id = item.id, name = item.name,
                description = item.description, icon_style = "seal", icon = item.icon, icon_type = item.icon_type,
                quality = item.quality, count = count, target = item.max_owned }
        end
    end
    return rows
end

-- Server extension point: register a projector and enable its CSV category.
function M.register_category(category_id, projector)
    assert(categories.by_id[category_id] and type(projector) == "function")
    renderers[category_id] = projector
end

function M.snapshot(player_id, category_id)
    local profile = profiles.get_profile(player_id)
    if not profile then return { ok = false, error = "profile_not_loaded" } end
    category_id = tostring(category_id or "clear")
    local category = categories.by_id[category_id]
    if not category or not category.enabled then return { ok = false, error = "category_invalid" } end
    local projector = renderers[category_id]
    local fishing
    if category_id == "fishing" then
        local _; _, fishing = require("systems/archive_fishing_view").project(profile)
    end
    return { ok = true, category_id = category_id, revision = profile.revision,
        fishing = fishing,
        categories = enabled_categories(), has_pass = has_pass(profile) and 1 or 0,
        rows = projector and projector(profile, saved(profile)) or {},
        online = (category_id == "map_level" or category_id == "work")
            and require("systems/archive_online_rewards").info(saved(profile)) or nil,
        social = require("systems/archive_social_rewards").info(saved(profile), category_id),
        last_draw = saved(profile).social_last_draw,
        pending = pending[player_id] and next(pending[player_id]) ~= nil and 1 or 0 }
end

local function send(player_id)
    if not CustomGameEventManager or not PlayerResource then return end
    local player = PlayerResource:GetPlayer(player_id)
    if not player then return end
    local result = M.snapshot(player_id, selected[player_id] or "clear")
    serial = (serial or 0) + 1
    local rows = result.rows or {}
    local chunks = math.max(1, math.ceil(#rows / 12))
    for chunk = 1, chunks do
        local packet = copy(result)
        packet.rows = {}
        for index = (chunk - 1) * 12 + 1, math.min(chunk * 12, #rows) do
            packet.rows[#packet.rows + 1] = rows[index]
        end
        packet.sequence, packet.chunk, packet.chunks = serial, chunk, chunks
        CustomGameEventManager:Send_ServerToPlayer(player, "survival_archive_snapshot", packet)
    end
end

local function local_settle(player_id, command)
    local profile = profiles.get_profile(player_id)
    if not profile then return { ok = false, error = "profile_not_loaded" } end
    local provider = profiles.get_provider()
    if not provider or type(provider.persist_save) ~= "function" then
        return { ok = false, error = "archive_provider_required" }
    end
    local archive, stats = saved(profile), copy(profile.save.gameplay_stats)
    if archive.processed[command.id] then return { ok = true, duplicate = true } end
    if command.kind == "online_checkpoint" or command.kind == "work_upgrade" then
        local ok, reason = require("systems/archive_online_rewards").apply(command, archive, stats, apply_effects)
        if not ok then return { ok = false, terminal = true, error = reason } end
    elseif command.kind == "boss_kill" then
        archive.boss_kills=(tonumber(archive.boss_kills) or 0)+1
    elseif command.kind == "daily_init" or command.kind == "daily_claim" then
        local ok,reason=require("systems/archive_daily_rewards").apply(command,archive,stats,has_pass(profile),apply_effects)
        if not ok then return {ok=false,terminal=true,error=reason} end
    elseif command.kind == "clear" then
        local difficulty = command.difficulty_id
        archive.clear_counts[difficulty] = (archive.clear_counts[difficulty] or 0) + command.count
        for _, item in ipairs(achievements.rows) do
            if item.enabled and item.difficulty_id == difficulty
                and archive.clear_counts[difficulty] >= item.required_count
                and not archive.completed[item.achievement_id] then
                apply_effects(stats, item)
                archive.completed[item.achievement_id] = true
            end
        end
    elseif command.kind == "endless" then
        local config = require("systems/archive_endless_config")
        if not config.wave(command.difficulty, command.wave) then return { ok = false, terminal = true, error = "endless_wave_invalid" } end
        archive.endless_score = (tonumber(archive.endless_score) or 0) + config.score(command.wave)
        archive.endless_best_wave = math.max(tonumber(archive.endless_best_wave) or 0, command.wave)
        for _, item in ipairs(require("config/generated/archive_endless_achievements").rows) do
            if item.enabled and archive.endless_score >= item.required_score and not archive.completed[item.achievement_id] then
                apply_effects(stats, item)
                archive.completed[item.achievement_id] = true
            end
        end
    elseif command.kind == "challenge" then
        local ok, reason = challenge_rewards.apply(command, archive, stats, has_pass(profile), apply_effects)
        if not ok then return { ok = false, error = reason } end
    elseif command.kind == "social_draw" or command.kind == "social_ticket_cheat" then
        local ok, reason = require("systems/archive_social_rewards").apply(command, archive, stats, apply_effects)
        if not ok then return { ok=false, error=reason, terminal=true } end
    elseif command.kind == "promotion" then
        local ok, reason = challenge_rewards.promote(command, archive, stats, apply_effects)
        if not ok then return { ok = false, error = reason, terminal = true } end
    else
        return { ok = false, error = "archive_command_invalid" }
    end
    -- Online checkpoints are deduplicated by their cumulative session cursor, without one saved ID per minute.
    if command.kind ~= "online_checkpoint" then archive.processed[command.id] = true end
    -- Only current match IDs are needed locally; completed milestones and
    -- counts are permanent. Remote providers must keep durable grant records.
    local prefix = session_id .. ":"
    for id in pairs(archive.processed) do
        if id:sub(1, #prefix) ~= prefix then archive.processed[id] = nil end
    end
    return profiles.update_save_sections(player_id,
        { archive = archive, gameplay_stats = stats }, "archive_" .. command.kind)
end

local function flush(player_id)
    if busy[player_id] then return end
    local queue = pending[player_id]
    if not queue then return end
    for id, command in pairs(queue) do
        local attempt = {}
        busy[player_id] = attempt
        local function complete(result)
            if busy[player_id] ~= attempt then return end
            busy[player_id] = nil
            scheduler.cancel("archive_remote_timeout:" .. player_id)
            if result and (result.ok or result.terminal) then queue[id] = nil end
            send(player_id)
            if M.send_daily and daily_viewers[player_id] then M.send_daily(player_id) end
        end
        if remote_provider then
            scheduler.after(15, function()
                complete({ ok = false, error = "archive_provider_timeout" })
            end, "archive_remote_timeout:" .. player_id)
            -- Adapter submits intent to the trusted backend. It must apply
            -- the returned authoritative profile before calling complete.
            local ok, err = pcall(remote_provider.submit, player_id, copy(command), complete)
            if not ok then complete({ ok = false, error = tostring(err) }) end
            return
        end
        local ok, result = pcall(local_settle, player_id, command)
        if not ok then result = { ok = false, error = tostring(result) } end
        complete(result)
        if not result.ok then
            print("[Archive] pending player=" .. player_id .. " error=" .. tostring(result.error))
            return result
        end
    end
    return { ok = true }
end

local function enqueue(player_id, command)
    player_id = tonumber(player_id)
    if not integer(player_id) then return { ok = false, error = "player_invalid" } end
    pending[player_id] = pending[player_id] or {}
    pending[player_id][command.id] = pending[player_id][command.id] or command
    return flush(player_id) or { ok = true, pending = true }
end

function M.set_provider(provider)
    assert(provider == nil or type(provider.submit) == "function")
    remote_provider = provider
end

-- A trusted backend adapter can supply its synchronized Unix clock when
-- VScript has no os.time. There is deliberately no client clock event.
function M.set_clock(clock)
    assert(clock == nil or type(clock) == "function")
    server_clock = clock
    require("systems/archive_calendar").set_clock(clock)
end

function M.record_boss(player_id,kill_id)
    archive_players[player_id]=true
    return enqueue(player_id,{id=session_id..":boss:"..tostring(kill_id),kind="boss_kill"})
end
function M.daily_snapshot(player_id)
    local profile=profiles.get_profile(player_id)
    if not profile then return {ok=false,error="档案尚未载入"} end
    local result=require("systems/archive_daily_rewards").snapshot(profile,require("systems/archive_calendar").day(),has_pass(profile))
    result.ok=true
    result.pending=M.has_pending(player_id) and 1 or 0
    result.purchase_enabled=result.purchase_enabled==1 and purchase_provider and 1 or 0
    return result
end
function M.send_daily(player_id)
    if not PlayerResource or not CustomGameEventManager then return end
    local player=PlayerResource:GetPlayer(player_id)
    if player then CustomGameEventManager:Send_ServerToPlayer(player,"survival_daily_snapshot",M.daily_snapshot(player_id)) end
end
function M.daily_claim(player_id,target)
    local today=require("systems/archive_calendar").day()
    target=tonumber(target) or today
    if not integer(target) then return {ok=false,error="签到日期无效"} end
    return enqueue(player_id,{id=session_id..":daily:"..target,kind="daily_claim",today=today,target_day=target})
end
function M.set_purchase_provider(provider)
    assert(provider==nil or type(provider.create_order)=="function")
    purchase_provider=provider
end

function M.record_clear(player_id, difficulty_id)
    local difficulty = string.lower(tostring(difficulty_id or ""))
    return enqueue(player_id, { id = session_id .. ":clear", kind = "clear",
        difficulty_id = difficulty, count = 1 })
end

function M.record_endless_wave(player_id, wave_number, difficulty)
    if not integer(wave_number) or wave_number < 1 or not tonumber(difficulty)
        or not require("systems/archive_endless_config").wave(tonumber(difficulty), wave_number) then
        return { ok = false, error = "endless_wave_invalid" }
    end
    return enqueue(player_id, { id = session_id .. ":endless:" .. wave_number,
        kind = "endless", wave = wave_number, difficulty = tonumber(difficulty) })
end

local function day_key()
    local timestamp = server_clock and server_clock() or (os and os.time and os.time())
    if type(timestamp) == "number" then
        return tostring(math.floor((timestamp + challenge_rules.day_timezone_offset) / 86400))
    end
    -- Local fixture fallback only. Production adapter validates its own date.
    if GetSystemDate then return tostring(GetSystemDate()) end
    return "local_test_day"
end

function M.has_pending(player_id)
    return busy[player_id] ~= nil or (pending[player_id] and next(pending[player_id]) ~= nil) or false
end

function M.record_challenge(player_id, challenge_id, kill_sequence, difficulty_id)
    if not integer(kill_sequence) then return { ok = false, error = "archive_kill_id_invalid" } end
    return enqueue(player_id, { id = session_id .. ":challenge:" .. kill_sequence,
        kind = "challenge", challenge_id = challenge_id, kill_sequence = kill_sequence,
        difficulty_id = difficulty_id, day_key = day_key() })
end

function M.social_draw(player_id, pool_id, request_id)
    if not require("config/generated/archive_social_rules").by_id[pool_id] then return {ok=false,error="奖池无效"} end
    request_id = tostring(request_id or "")
    if #request_id < 1 or #request_id > 80 or request_id:find("[^%w_-]") then return {ok=false,error="请求无效"} end
    return enqueue(player_id, {id=session_id..":social_draw:"..request_id, kind="social_draw", pool_id=pool_id})
end

function M.zaixian(context)
    local allowed = type(IsInToolsMode) == "function" and IsInToolsMode()
        or GameRules and GameRules.IsCheatMode and GameRules:IsCheatMode()
    if not allowed then return false, "tools_mode_or_cheats_required" end
    local args = context.args or {}
    local minutes = tonumber(args[1])
    if #args ~= 1 or not integer(minutes) or minutes < 1 or minutes > 1000000 then
        return false, "用法：zaixian <1..1000000分钟>（累加在线时间）"
    end
    local profile = profiles.get_profile(context.player_id)
    if not profile then return false, "profile_not_loaded" end
    serial = (serial or 0) + 1
    -- A separate cursor per invocation exercises the real settlement without advancing the live clock.
    local id = session_id .. ":zaixian:" .. serial
    local multiplier = has_pass(profile) and 2 or 1
    local result = enqueue(context.player_id, { id = id, kind = "online_checkpoint", session = id,
        actual_seconds = minutes * 60, map_seconds = minutes * 60 * multiplier, test_only = true })
    if result.ok then
        bus.emit(events.UI_NOTIFICATION, { player_id = context.player_id, level = "info",
            message = "模拟在线增加" .. minutes .. "分钟，地图有效时长增加" .. minutes * multiplier
                .. "分钟，软妹币增加" .. minutes .. (result.pending and "（等待保存）" or "") })
    end
    return result.ok, result.error
end

function M.yitie(context)
    local allowed = type(IsInToolsMode) == "function" and IsInToolsMode()
        or GameRules and GameRules.IsCheatMode and GameRules:IsCheatMode()
    if not allowed then return false, "tools_mode_or_cheats_required" end
    local amount = tonumber(context.args[1])
    local pool = context.args[2] or "friend"
    if #context.args < 1 or #context.args > 2 or not integer(amount) or amount > 1000000
        or not require("config/generated/archive_social_rules").by_id[pool] then return false, "usage: yitie <0..1000000> [friend|ex|beast]" end
    serial = (serial or 0) + 1
    local result = enqueue(context.player_id, {id=session_id..":yitie:"..serial, kind="social_ticket_cheat", amount=amount, pool_id=pool})
    return result.ok, result.error
end

function M.promote(player_id, fragment_id, request_id)
    if type(request_id) ~= "string" or #request_id > 80 or not request_id:match("^[%w_%-]+$") then
        return { ok = false, error = "archive_request_invalid" }
    end
    return enqueue(player_id, { id = session_id .. ":promotion:" .. request_id,
        kind = "promotion", fragment_id = tostring(fragment_id or ""), day_key = day_key() })
end

function M.work_upgrade(player_id, item_id, expected_level)
    local item = require("config/generated/archive_work_items").by_id[tostring(item_id or "")]
    expected_level = tonumber(expected_level)
    if not item or not item.enabled or not integer(expected_level) or expected_level >= item.max_level then
        return { ok = false, error = "福利请求无效" }
    end
    -- Identity is the intended level, not a client nonce: repeated clicks cannot charge twice.
    return enqueue(player_id, { id = session_id .. ":work:" .. item.item_id .. ":" .. expected_level,
        kind = "work_upgrade", item_id = item.item_id, expected_level = expected_level })
end

function M.cheat(context)
    local allowed = type(IsInToolsMode) == "function" and IsInToolsMode()
        or GameRules and GameRules.IsCheatMode and GameRules:IsCheatMode()
    if not allowed then return false, "tools_mode_or_cheats_required" end
    local key = string.lower(tostring(context.args[1] or ""))
    local count = tonumber(context.args[2])
    if #context.args ~= 2 or not integer(count) or count < 1 or count > 100000 then
        return false, "usage: tongguan <n1|clear_n1_1> <1..100000>"
    end
    local item = achievements.by_id[key]
    local difficulty = item and item.difficulty_id or key
    local known = false
    for _, row in ipairs(achievements.rows) do if row.difficulty_id == difficulty then known = true end end
    if not known then return false, "archive_difficulty_invalid" end
    serial = (serial or 0) + 1
    local result = enqueue(context.player_id, { id = session_id .. ":cheat:" .. serial,
        kind = "clear", difficulty_id = difficulty, count = count, test_only = true })
    return result.ok, result.error
end

function M.init()
    pending, busy, selected, throttles = {}, {}, {}, {}
    daily_viewers = {}
    archive_players = {}
    serial = 0
    session_id = runtime_id()
    local online_clock = require("systems/archive_online_clock")
    online_clock.init(session_id, enqueue)
    bus.subscribe(events.PLAYER_PROFILE_CHANGED, function(payload)
        local id = tonumber(payload.player_id)
        if id then
            archive_players[id]=true
            online_clock.observe(id, profiles.get_profile(id))
            send(id)
            if daily_viewers[id] then M.send_daily(id) end
            if not busy[id] then flush(id) end
        end
    end)
    bus.subscribe(events.PLAYER_DISCONNECTED, function(payload)
        local id = tonumber(payload.player_id)
        if id then online_clock.disconnect(id) end
    end)
    scheduler.every(1, function()
        -- Iterate valid slots as well as profile events, so reopening the archive is never needed to earn time.
        for id = 0, (DOTA_MAX_TEAM_PLAYERS or 24) - 1 do
            if PlayerResource and PlayerResource:IsValidPlayerID(id) then
                local profile = profiles.get_profile(id)
                if profile then
                    archive_players[id] = true
                    online_clock.sample(id, profile)
                end
            end
        end
    end, "archive_online_clock")
    bus.subscribe("archive.wave_boss_killed",function(payload) M.record_boss(payload.player_id,payload.kill_id) end)
    local daily_times, pass_states = {}, {}
    CustomGameEventManager:RegisterListener("survival_daily_request",function(_,payload)
        local id=tonumber(payload.PlayerID)
        if not integer(id) or not PlayerResource:IsValidPlayerID(id) then return end
        local profile=profiles.get_profile(id)
        if not profile then M.send_daily(id);return end
        daily_viewers[id]=true
        archive_players[id]=true
        if not (profile.save.archive and profile.save.archive.daily_rewards) then
            enqueue(id,{id=session_id..":daily_init",kind="daily_init",today=require("systems/archive_calendar").day()})
        end
        M.send_daily(id)
    end)
    CustomGameEventManager:RegisterListener("survival_daily_claim",function(_,payload)
        local id=tonumber(payload.PlayerID)
        if not integer(id) or not PlayerResource:IsValidPlayerID(id) then return end
        local now=GameRules:GetGameTime()
        if daily_times[id] and now-daily_times[id]<0.3 then return end
        daily_times[id]=now
        local result=M.daily_claim(id,payload.target_day)
        if not result.ok then bus.emit(events.UI_NOTIFICATION,{player_id=id,level="error",message=result.error}) end
        M.send_daily(id)
    end)
    local purchase_times={}
    CustomGameEventManager:RegisterListener("survival_pass_purchase",function(_,payload)
        local id=tonumber(payload.PlayerID)
        if not integer(id) or not PlayerResource:IsValidPlayerID(id) then return end
        local now=GameRules:GetGameTime()
        if purchase_times[id] and now-purchase_times[id]<3 then return end
        purchase_times[id]=now
        local rules=require("config/generated/archive_daily_rules").by_id.default
        if not purchase_provider or not rules.purchase_enabled then
            bus.emit(events.UI_NOTIFICATION,{player_id=id,level="info",message="月卡购买尚未开放"});return
        end
        serial=serial+1
        -- Only a server-selected SKU and server-generated order key reach the payment adapter.
        local ok=pcall(purchase_provider.create_order,id,{sku=rules.pass_entitlement_id,
            request_id=session_id..":pass_order:"..serial},function(result)
            bus.emit(events.UI_NOTIFICATION,{player_id=id,level="info",message=result and result.message or "订单处理中"})
            M.send_daily(id)
        end)
        if not ok then bus.emit(events.UI_NOTIFICATION,{player_id=id,level="error",message="订单创建失败，请稍后重试"}) end
    end)
    scheduler.every(1,function()
        for id in pairs(archive_players) do
            local profile=profiles.get_profile(id)
            if profile then
                local pass=has_pass(profile)
                if pass_states[id]~=pass then
                    pass_states[id]=pass
                    bus.emit(events.PLAYER_PROFILE_CHANGED,{player_id=id,reason="archive_boss_refresh"})
                end
                if daily_viewers[id] then M.send_daily(id) end
            end
        end
    end,"archive_daily_clock")
    bus.subscribe("archive.final_wave_cleared", function(payload)
        M.record_clear(payload.player_id, payload.difficulty_id)
    end)
    scheduler.every(2, function()
        for id in pairs(pending) do flush(id) end
    end, "archive_retry")
    CustomGameEventManager:RegisterListener("survival_archive_request", function(_, payload)
        -- PlayerID is injected by Dota. Never accept a client account/player_id.
        local id = tonumber(payload.PlayerID)
        if not integer(id) or not PlayerResource:IsValidPlayerID(id) then return end
        local now = GameRules:GetGameTime()
        if throttles[id] and now - throttles[id] < 0.15 then return end
        throttles[id] = now
        local category = categories.by_id[tostring(payload.category_id or "clear")]
        if not category or not category.enabled then return end
        selected[id] = category.category_id
        send(id)
    end)
    local promotion_times = {}
    local draw_times = {}
    local work_times = {}
    CustomGameEventManager:RegisterListener("survival_archive_work_upgrade", function(_, payload)
        local id = tonumber(payload.PlayerID)
        if not integer(id) or not PlayerResource:IsValidPlayerID(id) then return end
        local now = GameRules:GetGameTime()
        if work_times[id] and now - work_times[id] < 0.3 then return end
        work_times[id] = now
        online_clock.flush(id)
        local result = M.work_upgrade(id, payload.item_id, payload.expected_level)
        if not result.ok then bus.emit(events.UI_NOTIFICATION, { player_id = id, level = "error", message = result.error }) end
        send(id)
    end)
    CustomGameEventManager:RegisterListener("survival_archive_social_draw", function(_, payload)
        local id = tonumber(payload.PlayerID)
        if not integer(id) or not PlayerResource:IsValidPlayerID(id) then return end
        local time = GameRules:GetGameTime()
        if draw_times[id] and time - draw_times[id] < 0.3 then return end
        draw_times[id] = time
        local result = M.social_draw(id, payload.pool_id, payload.request_id)
        if not result.ok then bus.emit(events.UI_NOTIFICATION, {player_id=id,level="error",message=result.error}) end
    end)
    CustomGameEventManager:RegisterListener("survival_archive_promote", function(_, payload)
        local id = tonumber(payload.PlayerID)
        if not integer(id) or not PlayerResource:IsValidPlayerID(id) then return end
        local time = GameRules:GetGameTime()
        if promotion_times[id] and time - promotion_times[id] < 0.3 then return end
        promotion_times[id] = time
        local result = M.promote(id, payload.fragment_id, payload.request_id)
        if not result.ok then
            bus.emit(events.UI_NOTIFICATION, { player_id = id, level = "error", message = result.error })
        end
    end)
end

M._test = { apply_effects = apply_effects, has_pass = has_pass, flush = flush }
return M
