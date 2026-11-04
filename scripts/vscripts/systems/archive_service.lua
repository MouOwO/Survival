local bus = require("core/event_bus")
local events = require("core/events")
local profiles = require("systems/player_profile_service")
-- UI/claim eligibility is the real account; combat uses the separate match view.
local function account_profile(id)
    if profiles.get_account_profile then return profiles.get_account_profile(id) end
    return profiles.get_profile(id)
end
local scheduler = require("core/scheduler")
local achievements = require("config/generated/archive_achievements")
local shadow_items = require("config/generated/archive_shadow_items")
local categories = require("config/generated/archive_categories")
local drop_rules = require("config/generated/archive_drop_rules")
local stats_config = require("config/generated/player_gameplay_stats")
local lottery = require("config/lottery_config")
local content_aliases = require("config/content_id_aliases")
local challenge_rewards = require("systems/archive_challenge_rewards")
local challenge_rules = require("config/generated/archive_challenge_rules").by_id.default
local M = {}
local pending, busy, selected, throttles = {}, {}, {}, {}
local reward_notifications = {}
local finalizing = false
local session_id, serial, remote_provider
local server_clock
local daily_viewers, purchase_provider = {}, nil
local daily_delivery, daily_sequences, pass_deadlines = {}, {}, {}
local daily_generation = 0
local compact_daily_transport, compact_daily_factory, compact_daily_lookup
local compact_daily_states, compact_daily_users, compact_daily_tokens = {}, {}, {}
local compact_daily_registered, compact_daily_send = false, nil
local compact_daily_changed
local compact_daily_handlers = {}
local compact_archive_views
local compact_vip,compact_vip_world
local function compact_bound(id)
    return compact_daily_transport and compact_daily_transport.is_bound
        and compact_daily_transport.is_bound(id) or false
end
local vip_viewers = {}
local legacy_vip_players = {}
local archive_players = {}
local sent_pages = {}
local archive_delivery, archive_head, archive_tail = {}, nil, nil
local legacy_archive_players = {}
local archive_queue_scheduled, archive_queue_running, archive_queue_generation = false, false, 0
local archive_renderer_generation = 0
local ui_json = require("core/json_encoder")
local UI_PACKET_JSON_BUDGET, UI_PACKET_ROW_LIMIT, UI_PACKET_ENVELOPE_RESERVE = 6 * 1024, 12, 256
local public_beta_viewers, public_beta_sequences, public_beta_claims = {}, {}, {}
local public_beta_legacy_subscribers={}
local compact_public_beta,compact_public_beta_world
local PUBLIC_BETA_TIER = "public_beta_login"
local ENDLESS_FLUSH_INTERVAL, ENDLESS_BATCH_LIMIT = 5, 32
local endless_due, endless_force = {}, {}
-- Only never-submitted explicit intents enter O(1) ready lists. A completion
-- must not replay a failed payment while waking another authorized operation.
local queue_runtime = {index={},wakes={},generation=0}

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

local function public_beta_command(command)
    return command.kind == "benefit_claim" and command.tier_id == PUBLIC_BETA_TIER
        and command.track == PUBLIC_BETA_TIER
end
local function public_beta_memory_provider()
    -- The exception below belongs solely to the explicitly latched, real
    -- session-memory provider. A read-only HTTP test arena cannot grant gifts.
    return require("debug/offline_logic_test").is_provider(profiles.get_provider())
        and not require("systems/archive_http_adapter").enabled()
end
local function public_beta_writable()
    return not require("debug/mode_unlock_test").is_enabled() or public_beta_memory_provider()
end
local function public_beta_receipt_applied(player_id, result)
    local profile, receipt = account_profile(player_id), result and result.response
    if not profile or type(receipt) ~= "table" or receipt.ok ~= true
        or receipt.tier_id ~= PUBLIC_BETA_TIER or receipt.track ~= PUBLIC_BETA_TIER
        or type(receipt.period_id) ~= "string" or type(receipt.rewards) ~= "table"
        or #receipt.rewards ~= 1 or receipt.rewards[1].id ~= "special_lottery_ticket"
        or receipt.rewards[1].count ~= 2 then return false end
    if remote_provider then
        local received = result.profile
        -- HTTP acceptance alone is insufficient. The adapter must have applied
        -- the authoritative profile before the queue can acknowledge success.
        return type(received) == "table" and integer(received.revision)
            and integer(profile.revision) and profile.revision >= received.revision
            and tostring(profile.account_id) == tostring(received.account_id)
    end
    local benefits = (profile.save.archive or {}).benefits or {}
    local day = (benefits.days or {})[receipt.period_id] or {}
    return (day.claimed or {})[PUBLIC_BETA_TIER] ~= nil
end

-- Correlate UI intent with the existing transaction; this event never grants
-- rewards. Transient provider failures retain the queue and the client lock.
local function social_result(player_id, pool_id, request_id, result)
    if compact_bound(player_id) then
        if compact_archive_views and compact_archive_views.complete then
            compact_archive_views.complete(player_id,pool_id,request_id,result)
        end
        return -- Numeric ACK is owned by the active compact archive view.
    end
    if not PlayerResource or not CustomGameEventManager then return end
    local player = PlayerResource:GetPlayer(player_id)
    if not player then return end
    result = result or {}
    local terminal = result.ok == true and result.pending ~= true or result.terminal == true
    local profile = result.ok == true and terminal and account_profile(player_id)
    local revision = profile and tonumber(profile.revision)
    CustomGameEventManager:Send_ServerToPlayer(player, "survival_archive_social_result", {
        pool_id = tostring(pool_id or ""), request_id = tostring(request_id or ""),
        ok = result.ok == true and terminal, terminal = terminal, pending = not terminal,
        duplicate = result.duplicate == true, error = result.error,
        -- last_draw can already belong to another pool; this authoritative
        -- version lets the matching UI wait for a sufficiently recent page.
        revision = integer(revision) and revision or nil,
    })
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

local renderers, custom_renderers = {}, {}
renderers.commerce_goods = function(profile) return require("systems/archive_commerce_goods").project(profile) end
renderers.titles = function(_, archive) return require("systems/archive_titles").rows(archive) end
renderers.gift = function(_, archive) return require("systems/archive_welfare_rewards").rows(archive) end
renderers.starjoy_points = function(profile) return require("systems/archive_starjoy_rewards").project(profile) end
renderers.fishing = function(profile) return (require("systems/archive_fishing_view").project(profile)) end
renderers.map_level = function(_, archive) return require("systems/archive_online_rewards").rows(archive, "map_level") end
renderers.building = function(_, archive) return require("systems/archive_building_rewards").rows(archive) end
renderers.work = function(_, archive) return require("systems/archive_online_rewards").rows(archive, "work") end
renderers.friend = function(_, archive) return require("systems/archive_social_rewards").rows(archive, "friend") end
renderers.ex = function(_, archive) return require("systems/archive_social_rewards").rows(archive, "ex") end
renderers.wife = function(_, archive) return require("systems/archive_social_rewards").rows(archive, "wife") end
renderers.concubine = function(_, archive) return require("systems/archive_social_rewards").rows(archive, "concubine") end
renderers.beast = function(_, archive) return require("systems/archive_social_rewards").rows(archive, "beast") end
renderers.boss = function(profile) return (require("systems/archive_boss_rewards").project(profile)) end
renderers.endless = function(_, archive)
    local rows = require("systems/archive_endless_rewards").rows(archive)
    for _, row in ipairs(require("systems/archive_challenge_gear").rows(archive)) do rows[#rows+1] = row end
    return rows
end
renderers.fragment = challenge_rewards.fragment_rows
renderers.pet = challenge_rewards.cage_rows
renderers.clear = function(_, archive)
    return require("systems/archive_clear_progress").rows(archive)
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
    local counts = {}
    for raw_id, value in pairs(profile.save.content_inventory or {}) do
        local amount = tonumber(value)
        if amount and amount == amount and amount > 0 and amount < math.huge then
            local id = content_aliases.canonical(raw_id)
            counts[id] = (counts[id] or 0) + math.floor(amount)
        end
    end
    for _, item in ipairs(lottery.items) do
        if item.item_type == "积分道具" then
            local stackable=require("systems/archive_stackable_items").definition(item.id)
            local cap=stackable and stackable.max_owned or item.max_owned
            local count = counts[content_aliases.canonical(item.id)] or 0
            if cap>0 then count=math.min(count,cap) end
            rows[#rows + 1] = { id = item.id, name = item.name,
                description = stackable and stackable.description or item.description, icon_style = "seal", icon = item.icon, icon_type = item.icon_type,
                quality = item.quality, count = count, target = cap>0 and cap or nil, max_owned = cap,
                item_type = item.item_type, source_kind = stackable and "benefit" or "lottery", unlocked = count > 0 and 1 or 0, count_known = 1,
                duplicate_points = stackable and 0 or item.duplicate_points,
                duplicate_currency = not stackable and "shop_points" or nil, converted_currency = not stackable and "shop_points" or nil }
        end
    end
    local stackables=require("systems/archive_stackable_items")
    local zongzi=stackables.definition("welfare_zongzi")
    if zongzi then
        local count=math.min(stackables.count(profile.save,zongzi.id),zongzi.max_owned)
        rows[#rows+1]={id=zongzi.id,name=zongzi.name,description=zongzi.description,quality=zongzi.quality,
            icon_type="custom",icon_style="seal",count=count,target=zongzi.max_owned,max_owned=zongzi.max_owned,
            item_type="积分道具",source_kind="benefit",unlocked=count>0 and 1 or 0,count_known=1}
    end
    for _, row in ipairs(challenge_rewards.point_rows(profile.save.archive or {})) do rows[#rows+1] = row end
    return rows
end

-- Server extension point: register a projector and enable its CSV category.
function M.register_category(category_id, projector)
    assert(categories.by_id[category_id] and type(projector) == "function")
    renderers[category_id] = projector
    custom_renderers[category_id] = true
    archive_renderer_generation=archive_renderer_generation+1
end

local function upgrade_pending(player_id, category_id)
    local kind = category_id == "work" and "work_upgrade" or category_id == "building" and "building_upgrade"
    if not kind then return 0 end
    for _, command in pairs(pending[player_id] or {}) do
        if command.kind == kind then return 1 end
    end
    return 0
end

-- Header-only projection: no row projector, inventory scan, limits or catalogue.
function M.compact_header(player_id,category_id,profile,header)
    header=header or {}
    header.revision=profile and profile.revision
    header.has_pass=profile and has_pass(profile) and 1 or 0
    header.pending=pending[player_id] and next(pending[player_id])~=nil and 1 or 0
    header.upgrade_pending=upgrade_pending(player_id,category_id)
    header.title_preview=category_id=="titles" and require("systems/title_presentation_service").preview_active(player_id) and 1 or 0
    return header
end

local function snapshot_profile(player_id, category_id, profile)
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
        daily_limits = require("systems/archive_daily_limits").snapshot(profile),
        starjoy = category_id == "starjoy_points" and require("systems/archive_starjoy_rewards").info(profile) or nil,
        upgrade_pending = upgrade_pending(player_id, category_id),
        buildings = category_id == "building" and require("systems/archive_building_rewards").info(saved(profile), require("systems/archive_calendar").day()) or nil,
        categories = enabled_categories(), has_pass = has_pass(profile) and 1 or 0,
        rows = category_id == "titles" and require("systems/title_presentation_service").rows(player_id,saved(profile))
            or projector and projector(profile, saved(profile)) or {},
        title_preview = category_id == "titles" and require("systems/title_presentation_service").preview_active(player_id) and 1 or 0,
        online = (category_id == "map_level" or category_id == "work")
            and require("systems/archive_online_rewards").info(saved(profile)) or nil,
        social = require("systems/archive_social_rewards").info(saved(profile), category_id),
        last_draw = saved(profile).social_last_draw,
        pending = pending[player_id] and next(pending[player_id]) ~= nil and 1 or 0 }
end

function M.snapshot(player_id, category_id)
    return snapshot_profile(player_id, category_id, account_profile(player_id))
end

local function ui_json_bytes(value)
    local ok, encoded = pcall(ui_json.encode, value)
    if ok then return #encoded end
end

local function reject_ui_page(category_id, reason, row_index, bytes)
    -- Fixed diagnostics only: never serialize profile, row, account or payload.
    print(string.format("[ARCHIVE_UI_WIRE] REJECT category=%s reason=%s row=%s json_bytes=%s budget=%s",
        tostring(category_id), reason, tostring(row_index or 0), tostring(bytes or -1),
        tostring(UI_PACKET_JSON_BUDGET)))
    return nil
end

local function ui_page_chunks(category_id, header, rows, sequence)
    local header_bytes = ui_json_bytes(header)
    local fixed = header_bytes and header_bytes + UI_PACKET_ENVELOPE_RESERVE
    if not fixed or fixed > UI_PACKET_JSON_BUDGET then
        return reject_ui_page(category_id, "header_budget", 0, fixed)
    end
    -- Verify the fixed reserve covers the largest sequence/chunk envelope for
    -- this page before sending anything; JSON lengths are not native lengths.
    local envelope = {}
    for key, value in pairs(header) do envelope[key] = value end
    envelope.rows, envelope.sequence = {}, sequence
    envelope.chunk, envelope.chunks = math.max(1, #rows), math.max(1, #rows)
    local envelope_bytes = ui_json_bytes(envelope)
    if not envelope_bytes or envelope_bytes > fixed then
        return reject_ui_page(category_id, "envelope_reserve", 0, envelope_bytes)
    end
    local ranges = { { first = 1, last = 0, bytes = fixed } }
    for index, row in ipairs(rows) do
        local bytes = ui_json_bytes(row)
        -- One byte per row also conservatively covers array separators.
        if not bytes or fixed + bytes + 1 > UI_PACKET_JSON_BUDGET then
            return reject_ui_page(category_id, "row_budget", index, bytes and fixed + bytes + 1)
        end
        local range = ranges[#ranges]
        if range.last >= range.first and (range.last - range.first + 1 >= UI_PACKET_ROW_LIMIT
                or range.bytes + bytes + 1 > UI_PACKET_JSON_BUDGET) then
            range = { first = index, last = index - 1, bytes = fixed }
            ranges[#ranges + 1] = range
        end
        range.last, range.bytes = index, range.bytes + bytes + 1
    end
    return ranges
end

local function log_ui_page(category_id, delta, rows, chunks, max_bytes)
    if type(IsInToolsMode) ~= "function" or not IsInToolsMode() then return end
    local offline = package.loaded["debug/offline_logic_test"]
    if not offline or type(offline.is_provider) ~= "function"
            or not offline.is_provider(profiles.get_provider()) then return end
    print(string.format("[ARCHIVE_UI_WIRE] category=%s mode=%s rows=%s chunks=%s max_json_bytes=%s budget=%s",
        tostring(category_id), delta and "delta" or "full", tostring(rows), tostring(chunks),
        tostring(max_bytes), tostring(UI_PACKET_JSON_BUDGET)))
end

local function build_ui_page(job)
    local player_id,category_id,profile=job.player_id,job.category_id,job.owner.profile
    -- Built-in projectors only read this private per-send account snapshot.
    -- Extensions retain their own copy, as when each page fetched its profile.
    local result = profile and snapshot_profile(player_id, category_id,
        custom_renderers[category_id] and copy(profile) or profile)
        or M.snapshot(player_id, category_id)
    if not result.ok then return end
    -- One shallow UI projection per page. Server snapshots/quotas retain their
    -- complete daily_limits; no UI consumes that large duplicated dictionary.
    -- Rows remain read-only references until only the selected chunk is copied.
    local metadata, wire = {}, { rows = result.rows or {} }
    for key, value in pairs(result) do
        if key ~= "rows" and key ~= "daily_limits" then
            metadata[key], wire[key] = value, value
        end
    end
    sent_pages[player_id] = sent_pages[player_id] or {}
    local previous = not job.force_full and sent_pages[player_id][category_id]
    local changes = previous and require("core/ui_snapshot_delta").diff(previous.data, wire)
    if changes and #changes==0 then return end
    local sequence = (serial or 0) + 1
    local rows = changes or wire.rows
    local header = changes and {ok=true,category_id=category_id,delta=1,base_sequence=previous.sequence} or metadata
    local ranges = ui_page_chunks(category_id, header, rows, sequence)
    if not ranges then return end -- No partial page or new baseline on refusal.
    serial = sequence
    return {header=header,wire=wire,rows=rows,ranges=ranges,sequence=sequence,
        changes=changes,next=1,max_bytes=0}
end
-- Ready nodes and player/category jobs are indexed. There is no periodic scan
-- of the twenty categories or the queued pages. Each dispatch does at most two
-- page/chunk work units and checks the real engine clock between operations.
local function unlink_archive_job(job)
    if not job.queued then return end
    if job.previous then job.previous.following=job.following else archive_head=job.following end
    if job.following then job.following.previous=job.previous else archive_tail=job.previous end
    job.previous,job.following,job.queued=nil,nil,false
    if not archive_head and archive_queue_scheduled and not archive_queue_running then
        scheduler.cancel("archive_ui_queue");archive_queue_scheduled=false
    end
end
local function finish_archive_job(job)
    unlink_archive_job(job)
    if job.owner.jobs[job.category_id]==job then job.owner.jobs[job.category_id]=nil end
end
local function legacy_archive_active(player_id)
    local player=PlayerResource and PlayerResource:GetPlayer(player_id)
    return player~=nil and legacy_archive_players[player_id]==player and not compact_bound(player_id)
end
local function cancel_legacy_archive(player_id)
    legacy_archive_players[player_id]=nil
    local state=archive_delivery[player_id]
    if state then
        -- Indexed cancellation of this player's <=20 category jobs, once on
        -- protocol transition. Never build/project an abandoned legacy page.
        local _,job=next(state.jobs)
        while job do finish_archive_job(job);_,job=next(state.jobs)end
    end
    archive_delivery[player_id]=nil;sent_pages[player_id]=nil
end
local function link_archive_job(job,priority)
    unlink_archive_job(job);job.queued=true
    if priority then
        job.following=archive_head
        if archive_head then archive_head.previous=job else archive_tail=job end
        archive_head=job
    else
        job.previous=archive_tail
        if archive_tail then archive_tail.following=job else archive_head=job end
        archive_tail=job
    end
end
local function archive_job_current(job)
    if not legacy_archive_active(job.player_id) then cancel_legacy_archive(job.player_id);return false end
    return job.generation==archive_queue_generation and archive_delivery[job.player_id]==job.owner
        and job.owner.jobs[job.category_id]==job and job.epoch==job.owner.epoch
        and PlayerResource and PlayerResource:GetPlayer(job.player_id)==job.owner.player
end
local kick_archive_queue
local function flush_archive_queue()
    archive_queue_scheduled=false;archive_queue_running=true
    local clock=type(GetSystemTimeMS)=="function" and GetSystemTimeMS or nil
    local started=clock and clock()
    local units=0
    while archive_head and units<2 do
        if started and clock()-started>=2 then break end
        local job=archive_head;units=units+1
        if not archive_job_current(job) then finish_archive_job(job)
        else
            local ok=pcall(function()
                if not job.page then
                    job.page=build_ui_page(job)
                    if not archive_job_current(job) then return end
                    if not job.page then job.owner.seen[job.category_id]=job.epoch;finish_archive_job(job);return end
                    if started and clock()-started>=2 then return end
                end
                local page=job.page
                local range=page.ranges[page.next]
                local packet=copy(page.header);packet.rows={}
                for index=range.first,range.last do packet.rows[#packet.rows+1]=copy(page.rows[index]) end
                packet.sequence,packet.chunk,packet.chunks=page.sequence,page.next,#page.ranges
                local bytes=ui_json_bytes(packet)
                if not bytes or bytes>UI_PACKET_JSON_BUDGET then
                    reject_ui_page(job.category_id,"packet_budget",range.first,bytes)
                    finish_archive_job(job);return
                end
                if not archive_job_current(job) then return end
                CustomGameEventManager:Send_ServerToPlayer(job.owner.player,"survival_archive_snapshot",packet)
                if not archive_job_current(job) then return end
                page.max_bytes=math.max(page.max_bytes,bytes);page.next=page.next+1
                if page.next>#page.ranges then
                    -- No partially delivered page is ever a delta base.
                    sent_pages[job.player_id][job.category_id]={sequence=page.sequence,data=copy(page.wire)}
                    job.owner.seen[job.category_id]=job.epoch
                    job.owner.failed[job.category_id]=nil
                    log_ui_page(job.category_id,page.changes,#page.rows,#page.ranges,page.max_bytes)
                    finish_archive_job(job)
                end
            end)
            if not ok then
                job.owner.failed[job.category_id]=true
                finish_archive_job(job)
                print("[ARCHIVE_UI_QUEUE] page_send_failed category="..tostring(job.category_id))
            end
        end
    end
    archive_queue_running=false;kick_archive_queue(0.05)
end
kick_archive_queue=function(delay)
    if not archive_head or archive_queue_scheduled or archive_queue_running then return end
    archive_queue_scheduled=true
    local generation=archive_queue_generation
    scheduler.after(delay or 0,function()
        if generation~=archive_queue_generation then return end
        flush_archive_queue()
    end,"archive_ui_queue")
end
local function enqueue_archive_page(state,category_id,priority,force_full)
    local job=state.jobs[category_id]
    if job and job.epoch==state.epoch then
        if force_full and job.page and job.page.changes then finish_archive_job(job);job=nil
        else
            job.force_full=job.force_full or force_full
            if priority then link_archive_job(job,true) end
            return
        end
    end
    if not force_full and state.seen[category_id]==state.epoch then return end
    if job then finish_archive_job(job) end
    job={player_id=state.player_id,category_id=category_id,owner=state,epoch=state.epoch,
        generation=archive_queue_generation,force_full=force_full}
    state.jobs[category_id]=job;link_archive_job(job,priority)
end
local function archive_source(player_id,profile,reuse_profile)
    if not legacy_archive_active(player_id) then return end
    if not CustomGameEventManager or not PlayerResource then return end
    local player=PlayerResource:GetPlayer(player_id)
    if not player then return end
    local state=archive_delivery[player_id]
    if state and state.player~=player then
        for _,job in pairs(state.jobs) do finish_archive_job(job) end
        state=nil;archive_delivery[player_id]=nil;sent_pages[player_id]=nil
    end
    profile=profile or reuse_profile and state and state.profile or account_profile(player_id)
    if not profile then return end
    local day=require("systems/archive_calendar").day()
    local pass=has_pass(profile)
    local pending_state=pending[player_id] and next(pending[player_id])~=nil or false
    local changed=not state or state.revision~=profile.revision or profile.revision==nil
        or state.account~=profile.account_id or state.mode~=profile.mode or state.session~=profile.match_session_id
        or state.day~=day or state.pass~=pass or state.pending~=pending_state
        or state.renderer_generation~=archive_renderer_generation
    if not state then
        state={player_id=player_id,player=player,jobs={},seen={},failed={},epoch=0}
        archive_delivery[player_id]=state
    end
    if changed then
        for _,job in pairs(state.jobs) do finish_archive_job(job) end
        if state.account~=profile.account_id or state.mode~=profile.mode or state.session~=profile.match_session_id then
            sent_pages[player_id]=nil
        end
        state.profile,state.revision,state.account,state.mode,state.session=profile,profile.revision,profile.account_id,profile.mode,profile.match_session_id
        state.failed={}
        state.day,state.pass,state.pending=day,pass,pending_state
        state.renderer_generation=archive_renderer_generation;state.epoch=state.epoch+1
    end
    return state,changed
end
local function send_page(player_id,category_id,profile)
    if compact_bound(player_id) then cancel_legacy_archive(player_id);return end
    if not legacy_archive_active(player_id)then return end
    local state=archive_source(player_id,profile)
    if state then enqueue_archive_page(state,category_id,true,false);kick_archive_queue() end
end
local function send(player_id,priority,profile,resync,reuse_profile)
    if compact_bound(player_id) then
        cancel_legacy_archive(player_id)
        if compact_archive_views then
            compact_archive_views.changed(player_id,profile or account_profile(player_id),{pending_changed=true})
        end
        return
    end
    if not legacy_archive_active(player_id)then return end
    local state,changed=archive_source(player_id,profile,reuse_profile)
    if not state then return end
    priority=priority or selected[player_id]
    if changed then
        for _,category in ipairs(enabled_categories()) do
            if categories.by_id[category.id] then enqueue_archive_page(state,category.id,false,false) end
        end
    else
        for category_id in pairs(state.failed) do
            enqueue_archive_page(state,category_id,false,false)
        end
    end
    if priority then enqueue_archive_page(state,priority,true,resync==true) end
    kick_archive_queue()
end

local function local_settle(player_id, command)
    if public_beta_command(command) and require("debug/mode_unlock_test").is_enabled()
        and public_beta_memory_provider() then
        -- The profile service owns the private, strictly memory-only write
        -- capability and recomputes this fixed gift intent itself.
        return profiles.apply_offline_public_beta_gift(player_id,command)
    end
    local profile = account_profile(player_id)
    if not profile then return { ok = false, error = "profile_not_loaded" } end
    local provider = profiles.get_provider()
    if not provider or type(provider.persist_save) ~= "function" then
        return { ok = false, error = "archive_provider_required" }
    end
    local context
    if command.kind == "clear" or command.kind:match("_clear$") then
        local ok, setup = pcall(require, "systems/match_setup_service")
        local mode = ok and type(setup.get_mode) == "function" and setup.get_mode() or nil
        if require("systems/archive_clear_progress").is_mode(mode) then
            command = copy(command)
            command.mode_id = mode
        end
    end
    if command.kind == "challenge" then
        local policy = require("systems/archive_cooperative_reward_policy")
        if policy.shared_challenge_roll() then
            context = {challenge_random_seed = policy.local_seed(command.id)}
        end
    elseif command.kind == "endless" then
        context = {challenge_random_seed = require("systems/archive_cooperative_reward_policy").local_seed(
            command.id .. ":" .. tostring(player_id))}
    end
    local result = require("systems/archive_settlement").settle(profile, command, has_pass(profile), context)
    if not result.ok or result.duplicate then return result end
    local archive, stats = result.archive, result.gameplay_stats
    -- Only current match IDs are needed locally; completed milestones and
    -- counts are permanent. Remote providers must keep durable grant records.
    local prefix = session_id .. ":"
    for id in pairs(archive.processed) do
        if id:sub(1, #prefix) ~= prefix then archive.processed[id] = nil end
    end
    local sections={archive=archive,gameplay_stats=stats}
    if result.content_inventory then sections.content_inventory=result.content_inventory end
    local committed = require("ui/compact_profile_context").with(player_id,{
        source="archive_command",command=command,response=result.response,
        compact_daily_changes=require("ui/compact_daily_projection").command_changes(command,result)},function()
        return profiles.update_save_sections(player_id,sections,"archive_"..command.kind)
    end)
    if committed and committed.ok and result.response then committed.response = copy(result.response) end
    return committed
end

local flush
local function ready_remove(state,node)
    if not node or not node.ready then return end
    local group=node.group
    if node.previous then node.previous.next=node.next else state.head[group]=node.next end
    if node.next then node.next.previous=node.previous else state.tail[group]=node.previous end
    node.previous,node.next,node.ready=nil,nil,false
end
local function index_add(player_id,command)
    local state=queue_runtime.index[player_id]
    if not state then
        state={nodes={},head={},tail={},endless=0};queue_runtime.index[player_id]=state
    end
    if state.nodes[command.id] then return end
    local node={id=command.id,command=command};state.nodes[command.id]=node
    if command.kind=="endless" then state.endless=state.endless+1;return end
    node.group=(command.kind=="work_upgrade" or command.kind=="building_upgrade") and 1 or 2
    local tail=state.tail[node.group]
    node.previous,node.ready=tail,true
    if tail then tail.next=node else state.head[node.group]=node end
    state.tail[node.group]=node
end
local function index_complete(player_id,id)
    local state=queue_runtime.index[player_id];local node=state and state.nodes[id]
    if not node then return end
    ready_remove(state,node);state.nodes[id]=nil
    if node.command.kind=="endless" then state.endless=state.endless-1 end
end
local function wake_ready(player_id,queue)
    local state=queue_runtime.index[player_id]
    if pending[player_id]~=queue or not state or queue_runtime.wakes[player_id]
        or not (state.head[1] or state.head[2]) then return end
    local token={};queue_runtime.wakes[player_id]=token
    local generation=queue_runtime.generation
    local world=type(bus.get_generation)=="function" and bus.get_generation() or bus
    scheduler.after(0,function()
        if queue_runtime.wakes[player_id]~=token then return end
        queue_runtime.wakes[player_id]=nil
        if generation~=queue_runtime.generation or queue_runtime.index[player_id]~=state
            or pending[player_id]~=queue
            or (type(bus.get_generation)=="function" and bus.get_generation() or bus)~=world then return end
        flush(player_id,true)
    end,"archive_ready:"..player_id)
end
local function endless_pending(player_id)
    local state=queue_runtime.index[player_id]
    return state~=nil and state.endless>0
end
local function schedule_endless(player_id, delay)
    local generation = queue_runtime.generation
    scheduler.after(math.max(0, delay), function()
        if generation == queue_runtime.generation then flush(player_id) end
    end, "archive_endless_flush:" .. player_id)
end
local function submit_endless_batch(provider, player_id, commands, complete)
    if type(provider.submit_endless_batch) == "function" then
        return provider.submit_endless_batch(player_id, commands, complete)
    end
    -- Old/custom providers retain every existing intent. Drain a bounded
    -- five-second batch serially instead of building a one-wave backlog.
    local results, index = {}, 1
    local function next_command()
        local command = commands[index]
        if not command then complete({ok=true,results=results}); return end
        provider.submit(player_id, command, function(result)
            result = result or {ok=false,error="archive_response_invalid"}
            result.id = command.id
            results[#results+1] = result
            if not result.ok and not result.terminal then
                complete({ok=false,error=result.error,results=results}); return
            end
            index = index + 1
            next_command()
        end)
    end
    next_command()
end

flush = function(player_id,ready_only)
    if busy[player_id] then return end
    local queue = pending[player_id]
    if not queue then return end
    -- A retrying background reward must not starve an explicit purchase.
    -- Keep every queued command; serialize purchases through the same provider.
    local ordered = {}
    local held_delay
    local current_time = remote_provider and GameRules:GetGameTime()
    if ready_only then
        local state=queue_runtime.index[player_id]
        local node=state and (state.head[1] or state.head[2])
        if not node then return end
        ordered[1]={id=node.id,command=node.command}
    else
      for id, command in pairs(queue) do
        local held = false
        if remote_provider and command.kind == "endless" and not finalizing and not endless_force[player_id] then
            endless_due[player_id] = endless_due[player_id] or current_time + ENDLESS_FLUSH_INTERVAL
            local delay = endless_due[player_id] - current_time
            if delay > 0 then held_delay = held_delay or delay; held = true end
        end
        if not held then ordered[#ordered+1] = {id=id,command=command} end
      end
    end
    if held_delay then schedule_endless(player_id, held_delay) end
    table.sort(ordered, function(a, b)
        local ap = a.command.kind == "work_upgrade" or a.command.kind == "building_upgrade"
        local bp = b.command.kind == "work_upgrade" or b.command.kind == "building_upgrade"
        if ap ~= bp then return ap end
        if a.command.kind == "endless" and b.command.kind == "endless" then
            return a.command.wave < b.command.wave
        end
        return a.id < b.id
    end)
    for _, entry in ipairs(ordered) do
        local id, command = entry.id, entry.command
        local batch
        if remote_provider and command.kind == "endless" then
            batch = {}
            for _, candidate in ipairs(ordered) do
                if candidate.command.kind == "endless" and #batch < ENDLESS_BATCH_LIMIT then
                    batch[#batch+1] = copy(candidate.command)
                end
            end
            endless_due[player_id] = GameRules:GetGameTime() + ENDLESS_FLUSH_INTERVAL
            if not finalizing and not endless_force[player_id] then schedule_endless(player_id, ENDLESS_FLUSH_INTERVAL) end
        end
        local attempt = {}
        local state=queue_runtime.index[player_id]
        ready_remove(state,state and state.nodes[id])
        busy[player_id] = attempt
        local function complete(result)
            if busy[player_id] ~= attempt then return end
            busy[player_id] = nil
            scheduler.cancel("archive_remote_timeout:" .. player_id)
            if public_beta_command(command) and result and result.ok == true
                and not result.pending and not public_beta_receipt_applied(player_id, result) then
                -- Keep the exact accepted intent for retry/readback. A missing
                -- or unapplied snapshot is not a successful inventory grant.
                result = {ok=false,pending=true,error="public_beta_profile_refresh_pending"}
            end
            local terminal_error
            if batch then
                local submitted = {}
                for _, value in ipairs(batch) do submitted[value.id] = true end
                local acknowledgements = result and type(result.results)=="table" and result.results or {}
                for _, value in ipairs(acknowledgements) do
                    if type(value)=="table" and submitted[value.id]
                        and (value.ok==true or value.terminal==true) then
                        queue[value.id], submitted[value.id] = nil, nil
                        index_complete(player_id,value.id)
                        if value.terminal==true and value.ok~=true then
                            terminal_error = terminal_error or value.error or "存档请求被拒绝"
                        end
                    end
                end
            elseif result and (result.ok or result.terminal) then
                queue[id] = nil;index_complete(player_id,id)
            end
            if (terminal_error or result and result.terminal and not result.ok)
                and not (compact_daily_users[player_id] and (command.kind=="daily_claim" or command.kind=="benefit_claim")) then
                bus.emit(events.UI_NOTIFICATION,{player_id=player_id,level="error",message=terminal_error or result.error or "存档请求被拒绝"})
            end
            if command.kind == "challenge" and result and result.ok == true and not result.pending
                and type(result.response) == "table" then
                -- An accepted intent is not a reward. Only a committed server
                -- receipt may produce a success toast, including a recovered
                -- duplicate receipt after the first response was lost.
                reward_notifications[player_id] = reward_notifications[player_id] or {}
                if not reward_notifications[player_id][id] then
                    local response = result.response
                    local message = require("systems/archive_reward_presentation").message(response)
                    if response.skipped_reason then
                        message = "挑战已完成，本次未获得奖励：" .. tostring(response.skipped_reason)
                        bus.emit(events.UI_NOTIFICATION,{player_id=player_id,level="info",message=message})
                    elseif message then
                        bus.emit(events.UI_NOTIFICATION,{player_id=player_id,level="success",
                            kind="archive_reward",rich_text=true,message=message})
                    end
                    if message then reward_notifications[player_id][id] = true end
                end
            end
            send(player_id)
            if public_beta_command(command) then
                local claim = public_beta_claims[player_id]
                if claim and claim.operation_id == command.id then
                    claim.pending = not (result and (result.ok == true or result.terminal == true))
                    claim.result = {request_id=claim.request_id,ok=result and result.ok == true,
                        pending=claim.pending,terminal=result and (result.ok == true or result.terminal == true),
                        error=result and result.error,
                        day_key=result and result.response and result.response.period_id or claim.day_key}
                    M.send_public_beta_gift(player_id,claim.result)
                elseif public_beta_viewers[player_id] then M.send_public_beta_gift(player_id) end
            end
            if command.kind == "social_draw" then
                -- Keep the trusted backend's strict command schema/fingerprint
                -- unchanged; the client nonce is already encoded in this ID.
                social_result(player_id, command.pool_id, command.id:match(":social_draw:([%w_-]+)$"), result)
            end
            if vip_viewers[player_id] then M.send_vip(player_id,result) end
            if M.send_daily and (daily_viewers[player_id] or daily_delivery[player_id] or compact_daily_users[player_id]) then
                M.send_daily(player_id, command.kind=="daily_claim" and {
                    target_day=command.target_day,ok=result and result.ok==true,
                    error=result and result.error,terminal=result and result.terminal==true
                } or nil,command.kind=="benefit_claim" and {
                    track=command.track,tier_id=command.tier_id,ok=result and result.ok==true,
                    pending=result and result.pending==true,error=result and result.error,
                    terminal=result and result.terminal==true
                } or nil)
            end
            if not endless_pending(player_id) then
                endless_force[player_id] = nil
                scheduler.cancel("archive_endless_flush:" .. player_id)
            elseif (finalizing or endless_force[player_id]) and result and result.ok then
                -- Cross a server frame before the next bounded final batch.
                schedule_endless(player_id, 0)
            end
            -- Drain only a different, never-attempted intent after this reply.
            -- Legacy retry policy retains ownership of uncertain old receipts.
            wake_ready(player_id,queue)
        end
        if remote_provider then
            scheduler.after(35, function()
                complete({ ok = false, error = "archive_provider_timeout" })
            end, "archive_remote_timeout:" .. player_id)
            -- Adapter submits intent to the trusted backend. It must apply
            -- the returned authoritative profile before calling complete.
            local ok, err
            if batch then ok, err = pcall(submit_endless_batch, remote_provider, player_id, batch, complete)
            else ok, err = pcall(remote_provider.submit, player_id, copy(command), complete) end
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
    if require("debug/mode_unlock_test").is_enabled() then
        if not (public_beta_command(command) and public_beta_memory_provider()) then
            return {ok=true, skipped=true, test_only=true}
        end
        -- The verified offline provider persists only this match's memory.
        -- Never retain a previously injected HTTP adapter for this exception.
        remote_provider = nil
    end
    if finalizing then return {ok=false,error="正在保存本局奖励，请等待结算"} end
    local adapter = require("systems/archive_http_adapter")
    if adapter.enabled() then remote_provider = adapter end
    player_id = tonumber(player_id)
    if not integer(player_id) then return { ok = false, error = "player_invalid" } end
    pending[player_id] = pending[player_id] or {}
    if not pending[player_id][command.id] then
        pending[player_id][command.id]=command;index_add(player_id,command)
    end
    return flush(player_id) or { ok = true, pending = true }
end

function M.equip_title(player_id, title_id)
    local profile = account_profile(player_id)
    if not profile then return {ok=false,error="玩家档案尚未加载"} end
    local presentation = require("systems/title_presentation_service")
    -- Ordinary Tools clicks obey account gates too. Only an explicitly started
    -- cosmetic preview may keep using the preview overlay for later choices.
    if presentation.preview_active(player_id) then return presentation.preview(player_id,title_id) end
    if type(title_id)~="string" or title_id~="" and not require("systems/archive_titles").unlocked(saved(profile),title_id) then
        return {ok=false,error="称号未解锁或不存在"}
    end
    if M.has_pending(player_id) then return {ok=false,error="正在保存进度，请稍候再试"} end
    serial=(serial or 0)+1
    return enqueue(player_id,{id=session_id..":title:"..serial,kind="title_equip",title_id=title_id})
end

function M.send_vip(player_id,result)
    if compact_vip and compact_vip.changed(player_id)then return end
    if not PlayerResource or not CustomGameEventManager then return end
    local player=PlayerResource:GetPlayer(player_id)
    if player and legacy_vip_players[player_id]==player then
        local snapshot=require("systems/archive_vip_rewards").snapshot(account_profile(player_id))
        snapshot.pending=M.has_pending(player_id) and 1 or 0
        if result then snapshot.action_result={ok=result.ok==true,error=result.error,terminal=result.terminal==true} end
        CustomGameEventManager:Send_ServerToPlayer(player,"survival_vip_snapshot",snapshot)
    end
end
function M.vip_action(player_id,kind,reward_id)
    local row=require("config/generated/archive_vip_rewards").by_id[tostring(reward_id or "")]
    if not row or not row.enabled then return {ok=false,error="VIP奖励不存在"} end
    if (kind~="vip_claim" or row.group_id~="privileges") and (kind~="vip_purchase" or row.group_id~="packages") then
        return {ok=false,error="VIP领取方式无效"}
    end
    serial=(serial or 0)+1
    return enqueue(player_id,{id=session_id..":"..kind..":"..row.reward_id..":"..serial,kind=kind,reward_id=row.reward_id})
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
function M.daily_snapshot(player_id, profile)
    profile=profile or account_profile(player_id)
    if not profile then return {ok=false,error="档案尚未载入"} end
    local result=require("systems/archive_daily_rewards").snapshot(profile,require("systems/archive_calendar").day(),has_pass(profile))
    result.benefits=require("systems/archive_benefit_rewards").snapshot(profile,has_pass(profile))
    result.ok=true
    result.pending=M.has_pending(player_id) and 1 or 0
    result.purchase_enabled=result.purchase_enabled==1 and purchase_provider and 1 or 0
    return result
end
-- The catalogue is projected only for a changed account/date/pass/pending state,
-- never by the one-second clock. A closed view is not a standing subscription.
-- The wire v2 path transports bounded UTF-8 JSON fragments; JSON byte counts are
-- not an assertion about the engine's native protobuf/KeyValues serialization.
local DAILY_FRAGMENT_BYTES, DAILY_BATCH_PACKETS = 650, 2
local function stop_daily_job(player_id, state)
    if state then state.job=nil end
    scheduler.cancel("archive_daily_wire:"..player_id)
end
local function daily_fragments(encoded)
    local fragments, first = {}, 1
    while first<=#encoded do
        local last=math.min(#encoded,first+DAILY_FRAGMENT_BYTES-1)
        -- Never split a multibyte UTF-8 codepoint between native strings.
        if last<#encoded then
            while last>=first and encoded:byte(last+1)>=128 and encoded:byte(last+1)<192 do last=last-1 end
        end
        assert(last>=first,"daily_wire_invalid_utf8")
        fragments[#fragments+1]=encoded:sub(first,last);first=last+1
    end
    return fragments
end
local function queue_daily_wire(player_id, player, state, snapshot, force_full, changes)
    local previous=not force_full and state.baseline
    if changes and #changes==0 then return false end
    local sequence=snapshot.sequence
    local document=changes or snapshot
    local encoded=ui_json.encode(document)
    local fragments=daily_fragments(encoded)
    local job={generation=daily_generation,player=player,sequence=sequence,
        previous=previous,snapshot=snapshot,fragments=fragments,next=1}
    stop_daily_job(player_id,state);state.job=job
    local function flush_wire()
        if daily_delivery[player_id]~=state or state.job~=job or job.generation~=daily_generation
            or PlayerResource:GetPlayer(player_id)~=player then return end
        for _=1,DAILY_BATCH_PACKETS do
            if job.next>#fragments then break end
            local packet={wire_v=2,view_id=state.view_id,session_id=session_id,
                sequence=sequence,kind=changes and "delta" or "full",
                base_sequence=previous and previous.sequence or nil,
                chunk=job.next,chunks=#fragments,payload_json=fragments[job.next]}
            CustomGameEventManager:Send_ServerToPlayer(player,"survival_daily_wire",packet)
            -- A synchronous send may reenter a close/reopen or reset.
            if daily_delivery[player_id]~=state or state.job~=job or job.generation~=daily_generation then return end
            job.next=job.next+1
        end
        if job.next<=#fragments then
            scheduler.after(0.05,flush_wire,"archive_daily_wire:"..player_id)
        else
            state.job=nil;state.baseline={sequence=sequence,data=snapshot}
        end
    end
    scheduler.after(0,flush_wire,"archive_daily_wire:"..player_id)
    return true
end
local function track_pass_deadline(player_id,profile)
    local entitlement=profile and profile.entitlements and profile.entitlements.archive_pass
    local expires=entitlement and entitlement.active==true and tonumber(entitlement.expires_at)
    local now=require("systems/archive_calendar").now()
    if not expires or expires<=now then expires=nil end
    local previous=pass_deadlines[player_id]
    local account=profile and profile.account_id
    if previous and previous.expires==expires and previous.account==account then return end
    scheduler.cancel("archive_pass_deadline:"..player_id)
    local token={expires=expires,account=account,generation=daily_generation,
        player=PlayerResource and PlayerResource:GetPlayer(player_id)}
    pass_deadlines[player_id]=token
    if not expires then return end
    scheduler.after(math.max(0,expires-now),function()
        if pass_deadlines[player_id]~=token or token.generation~=daily_generation then return end
        pass_deadlines[player_id]=nil
        if not PlayerResource or PlayerResource:GetPlayer(player_id)~=token.player then return end
        local current=account_profile(player_id)
        if not current or current.account_id~=token.account then return end
        if require("systems/archive_calendar").now()<expires then
            track_pass_deadline(player_id,current);return
        end
        bus.emit(events.PLAYER_PROFILE_CHANGED,{player_id=player_id,reason="archive_pass_expired"})
    end,"archive_pass_deadline:"..player_id)
end
local function send_daily_hint(player,state,snapshot)
    if state.wire_v~=2 or tonumber(snapshot.pending)==1 then return end
    if snapshot.ok~=true then
        if state.hint_known==false then return end
        state.hint_known=false;state.hint_sequence=(state.hint_sequence or 0)+1
        CustomGameEventManager:Send_ServerToPlayer(player,"survival_daily_hint",{
            wire_v=2,view_id=state.view_id,session_id=session_id,
            sequence=state.hint_sequence,known=0,claimable=0})
        return
    end
    local claimable=snapshot.ordinary_status=="claimable"
        or snapshot.premium and snapshot.premium.status=="claimable" or false
    for _,track in ipairs({"daily_time","daily_wins","weekly_time"}) do
        for _,row in ipairs(snapshot.benefits and snapshot.benefits[track] and snapshot.benefits[track].rows or {}) do
            if (row.status=="claimable" or row.can_claim==true or tonumber(row.can_claim)==1)
                and row.auto_claim~=true and tonumber(row.auto_claim)~=1 then claimable=true end
        end
    end
    claimable=claimable and 1 or 0
    if state.hint_known==true and state.hint==claimable then return end
    state.hint_known=true;state.hint=claimable;state.hint_sequence=(state.hint_sequence or 0)+1
    CustomGameEventManager:Send_ServerToPlayer(player,"survival_daily_hint",{
        wire_v=2,view_id=state.view_id,session_id=session_id,
        sequence=state.hint_sequence,known=1,claimable=claimable})
end
function M.send_daily(player_id,claim_result,benefit_claim_result,force_full,current_profile)
    if compact_daily_users[player_id] and compact_daily_send then
        return compact_daily_send(player_id,claim_result,benefit_claim_result,force_full,current_profile)
    end
    if not PlayerResource or not CustomGameEventManager then return end
    local player=PlayerResource:GetPlayer(player_id)
    if player then
        local state=daily_delivery[player_id]
        if state and state.player~=player then
            stop_daily_job(player_id,state);daily_delivery[player_id]=nil;daily_viewers[player_id]=nil
            return
        end
        local profile=current_profile or account_profile(player_id)
        if state then
            local account=profile and profile.account_id
            local mode=profile and profile.mode
            local match_session=profile and profile.match_session_id
            if state.identity_known and (state.account~=account or state.mode~=mode or state.match_session~=match_session) then
                stop_daily_job(player_id,state)
                state.baseline,state.projected,state.hint,state.hint_known=nil,nil,nil,nil
            end
            state.identity_known=true
            state.account,state.mode,state.match_session=account,mode,match_session
        end
        track_pass_deadline(player_id,profile)
        local day=require("systems/archive_calendar").day()
        local pass=has_pass(profile) and 1 or 0
        local pending_state=M.has_pending(player_id) and 1 or 0
        local revision=profile and profile.revision
        local cached=state and state.projected
        local unchanged=cached and revision~=nil and state.revision==revision and state.day==day
            and state.pass==pass and state.pending==pending_state
        if unchanged and not force_full and not claim_result and not benefit_claim_result then return end
        local snapshot=unchanged and copy(cached) or M.daily_snapshot(player_id,profile)
        snapshot.sequence=nil
        if state then
            state.projected=copy(snapshot)
            state.revision,state.day,state.pass,state.pending=revision,day,pass,pending_state
            send_daily_hint(player,state,snapshot)
            if daily_delivery[player_id]~=state then return end
            if not daily_viewers[player_id] and not force_full then return end
        end
        snapshot.claim_result=claim_result
        snapshot.benefit_claim_result=benefit_claim_result
        -- Compare business values without a transport counter. A profile
        -- revision unrelated to this page must not cause another wire transfer.
        local previous=state and state.baseline
        local changes
        if previous and not force_full then
            local prior_sequence=previous.data.sequence;previous.data.sequence=nil
            changes=require("core/ui_snapshot_delta").diff(previous.data,snapshot)
            previous.data.sequence=prior_sequence
            if #changes==0 then return end
        end
        daily_sequences[player_id]=(daily_sequences[player_id] or 0)+1
        snapshot.sequence=daily_sequences[player_id]
        if state and state.wire_v==2 then return queue_daily_wire(player_id,player,state,snapshot,force_full,changes) end
        CustomGameEventManager:Send_ServerToPlayer(player,"survival_daily_snapshot",snapshot)
        if state then state.baseline={sequence=snapshot.sequence,data=snapshot} end
    end
end
local function compact_daily_context(id)
    return {now=require("systems/archive_calendar").now(),pending=M.has_pending(id),
        purchase_enabled=purchase_provider~=nil}
end
local function compact_daily_allowed(id)
    if not integer(id) or not PlayerResource or not PlayerResource:IsValidPlayerID(id)
        or not PlayerResource:GetPlayer(id) then return false end
    if PlayerResource.IsFakeClient and PlayerResource:IsFakeClient(id) then return false end
    local loading=package.loaded["systems/startup_loading_service"]
    if not loading or type(loading.is_player_ready)~="function" or not loading.is_player_ready(id) then return false end
    return require("core/test_access_policy").enforce(id)==true
end
local function compact_daily_hint(entry)
    local hint=entry.projection.hint()
    local rec=compact_daily_lookup.by_key["daily:state"];local fields=compact_daily_lookup.field_by_name
    return {{record=rec,field=fields.known,value=hint.known and 1 or 0},
        {record=rec,field=fields.can_claim,value=hint.can_claim and 1 or 0}},hint
end
local function compact_daily_entry(id,profile,changes)
    profile=profile or account_profile(id)
    local player=PlayerResource and PlayerResource:GetPlayer(id)
    if not player or not compact_daily_factory then return nil end
    local entry=compact_daily_states[id]
    local ctx=compact_daily_context(id)
    if not entry or entry.player~=player then
        local projection,error_message=compact_daily_factory.initialize(profile,ctx)
        if not projection then return nil,error_message end
        entry={player=player,projection=projection};compact_daily_states[id]=entry
        compact_daily_tokens[id]={};return entry,entry.projection.full_ops(),true
    end
    if not profile then
        local projection=assert(compact_daily_factory.initialize(nil,ctx))
        entry.projection=projection;compact_daily_tokens[id]={};return entry,projection.full_ops(),true
    end
    if changes==nil then
        changes=entry.projection.inspect().revision==profile.revision and {} or {initialize=true}
    end
    local ops,error_message=entry.projection.update(profile,changes,ctx)
    if not ops and error_message=="daily_identity_changed_reinitialize" then
        local projection,why=compact_daily_factory.initialize(profile,ctx)
        if not projection then return nil,why end
        entry.projection=projection;compact_daily_tokens[id]={};return entry,projection.full_ops(),true
    end
    if not ops then return nil,error_message end
    return entry,ops,changes and changes.initialize==true
end
local function compact_daily_publish(id,entry,ops,full)
    if compact_daily_transport.is_open(id,3) then
        if full then ops=entry.projection.full_ops() end
        if #ops>0 or full then compact_daily_transport.publish(id,3,ops,{full=full==true,priority=true}) end
    else
        local hint_ops,hint=compact_daily_hint(entry)
        if hint.pending then return end
        local key=(hint.known and "1" or "0")..(hint.can_claim and "1" or "0")
        if entry.hint~=key then entry.hint=key;compact_daily_transport.publish(id,3,hint_ops,{priority=true}) end
    end
end
compact_daily_changed=function(id,payload,profile)
    if not compact_daily_users[id] or not compact_daily_allowed(id) then return end
    local metadata=require("ui/compact_profile_context").current(id)
    local changes=payload and payload.compact_daily_changes or metadata and metadata.compact_daily_changes
    if not changes then
        local reason=payload and payload.reason
        if reason=="archive_pass_expired" then changes={entitlement=true}
        elseif reason=="archive_day_reset" then changes={calendar=true}
        elseif compact_daily_states[id] and profile and compact_daily_states[id].projection.inspect().revision==profile.revision then changes={}
        else changes={initialize=true} end -- Actual unclassified full account replacement.
    end
    local entry,ops,full=compact_daily_entry(id,profile,changes)
    if entry then compact_daily_publish(id,entry,ops,full) end
end
compact_daily_send=function(id,claim_result,benefit_result,force_full,profile)
    if not compact_daily_allowed(id) then return end
    profile=profile or account_profile(id)
    local entry,ops,full=compact_daily_entry(id,profile,nil)
    if not entry then return end
    if force_full then full=true end
    local active=compact_daily_tokens[id] or {}
    local function receipt(kind,result)
        local pending_intent=active[kind]
        if not result or not pending_intent then return end
        if kind=="daily" and tonumber(result.target_day)~=pending_intent.target_day then return end
        if kind=="benefit" and tostring(result.tier_id)~=pending_intent.tier_id then return end
        local acknowledged=entry.projection.ack(pending_intent.token,result,profile,{pending=M.has_pending(id)})
        for _,op in ipairs(acknowledged or {}) do ops[#ops+1]=op end
    end
    receipt("daily",claim_result);receipt("benefit",benefit_result)
    compact_daily_publish(id,entry,ops,full)
end
local function setup_compact_daily()
    local transport_ok,transport=pcall(require,"ui/compact_ui_transport")
    local lookup_ok,lookup=pcall(require,"config/generated/ui_static_catalog_lookup")
    if not transport_ok or not lookup_ok then return end -- Existing older installs retain their legacy reader.
    local factory= require("ui/compact_daily_projection").new(lookup)
    if not factory then return end
    compact_daily_transport,compact_daily_lookup,compact_daily_factory=transport,lookup,factory
    local own_world=type(bus.get_generation)=="function" and bus.get_generation()or bus
    if compact_daily_registered==own_world then return end
    local function current_world()
        return (type(bus.get_generation)=="function" and bus.get_generation()or bus)==own_world
    end
    transport.register_view(3,{
        open=function(id)
            if not current_world() or not compact_daily_allowed(id) then return nil end
            compact_daily_users[id]=true
            daily_viewers[id]=nil;stop_daily_job(id,daily_delivery[id]);daily_delivery[id]=nil
            local entry=compact_daily_entry(id,nil,nil)
            return entry and entry.projection.full_ops()
        end,
        snapshot=function(id)
            if not current_world() or not compact_daily_allowed(id) then return nil end
            local entry=compact_daily_entry(id,nil,nil)
            if not entry then return nil end
            if transport.is_open(id,3) then return entry.projection.full_ops() end
            return compact_daily_hint(entry)
        end,
        probe=function(id)
            if not current_world() or not compact_daily_allowed(id) then return nil end
            compact_daily_users[id]=true
            daily_viewers[id]=nil;stop_daily_job(id,daily_delivery[id]);daily_delivery[id]=nil
            local entry=compact_daily_entry(id,nil,nil)
            if not entry then return nil end
            local ops,hint=compact_daily_hint(entry)
            entry.hint=(hint.known and "1" or "0")..(hint.can_claim and "1" or "0")
            return transport.publish(id,3,ops,{full=true,priority=true})
        end,
        close=function(id)
            if not current_world() then return nil end
            local entry=compact_daily_states[id]
            if entry then compact_daily_publish(id,entry,{},false) end
            return true
        end,
        intent=function(id,action,args)
            if not current_world() or not compact_daily_allowed(id) or not transport.is_open(id,3) then return nil end
            if type(args)~="table" or not integer(args.request_token) or args.request_token<1 or args.request_token>16383
                or args.arg_b~=nil and args.arg_b~=0 or args.arg_c~=nil and args.arg_c~=0 then return nil end
            local entry=compact_daily_entry(id,nil,nil)
            if not entry then return nil end
            if action=="pass_purchase" then
                return compact_daily_handlers.purchase and compact_daily_handlers.purchase(nil,{PlayerID=id})
            end
            local intent,payload,kind,handler
            if action=="daily_claim" and integer(args.arg_a) then
                kind="daily";intent={kind=kind,target_day=args.arg_a};payload={PlayerID=id,target_day=args.arg_a}
                handler=compact_daily_handlers.daily
            elseif action=="benefit_claim" and integer(args.arg_a) then
                local row=lookup.records[args.arg_a]
                local definition=row and row.domain=="daily" and row.kind=="benefit"
                    and require("config/generated/archive_benefit_rewards").by_id[row.business_id]
                if not definition or not definition.enabled or (definition.track~="daily_time" and definition.track~="daily_wins" and definition.track~="weekly_time") then return nil end
                kind="benefit";intent={kind=kind,tier_id=definition.reward_id}
                payload={PlayerID=id,track=definition.track,tier_id=definition.reward_id};handler=compact_daily_handlers.benefit
            else return nil end
            if not entry.projection.bind_intent(args.request_token,intent) then return nil end
            compact_daily_tokens[id][kind]={token=args.request_token,target_day=intent.target_day,tier_id=intent.tier_id}
            local result=handler and handler(nil,payload)
            if not result then result={ok=false,terminal=true,error="操作过于频繁，请稍后重试"} end
            if kind=="daily" then
                compact_daily_send(id,{target_day=intent.target_day,ok=result.ok,pending=result.pending,terminal=result.terminal,error=result.error})
            else compact_daily_send(id,nil,{tier_id=intent.tier_id,track=payload.track,ok=result.ok,pending=result.pending,terminal=result.terminal,error=result.error}) end
            return result
        end})
    compact_daily_registered=own_world
end
function M.daily_claim(player_id,target)
    local today=require("systems/archive_calendar").day()
    target=tonumber(target) or today
    if not integer(target) then return {ok=false,error="签到日期无效"} end
    return enqueue(player_id,{id=session_id..":daily:"..target,kind="daily_claim",today=today,target_day=target})
end
function M.benefit_claim(player_id,track,tier_id)
    local row=require("config/generated/archive_benefit_rewards").by_id[tier_id]
    if not row or not row.enabled or row.track~=track then return {ok=false,error="福利档位不存在"} end
    serial=(serial or 0)+1
    return enqueue(player_id,{id=session_id..":benefit:"..serial,kind="benefit_claim",track=track,tier_id=tier_id})
end
function M.public_beta_gift_snapshot(player_id,supplied_profile)
    local profile=supplied_profile or account_profile(player_id)
    local snapshot=require("systems/archive_benefit_rewards").public_beta_snapshot(profile)
    public_beta_sequences[player_id]=(public_beta_sequences[player_id] or 0)+1
    snapshot.ok,snapshot.login_key,snapshot.sequence=profile~=nil,session_id or "",public_beta_sequences[player_id]
    if not profile then snapshot.eligible,snapshot.error=0,"档案尚未载入" end
    snapshot.claim_pending=public_beta_claims[player_id] and public_beta_claims[player_id].pending and 1 or 0
    if not public_beta_writable() then snapshot.eligible,snapshot.read_only=0,1 end
    return snapshot
end
function M.send_public_beta_gift(player_id,result,supplied_profile)
    if compact_public_beta and compact_public_beta.changed(player_id,result,supplied_profile)then return end
    if not PlayerResource or not CustomGameEventManager then return end
    local player=PlayerResource:GetPlayer(player_id)
    if not player or public_beta_legacy_subscribers[player_id]~=player then return end
    local snapshot=M.public_beta_gift_snapshot(player_id,supplied_profile)
    -- Re-query/hot reload can recover a lost ACK without creating a fresh
    -- claim. Keep the nonce and original receipt date from this world.
    result=result or public_beta_claims[player_id] and public_beta_claims[player_id].result
    if result then snapshot.claim_result={request_id=result.request_id,day_key=result.day_key,
        ok=result.ok==true and 1 or 0,pending=result.pending==true and 1 or 0,
        terminal=result.terminal==true and 1 or 0,error=result.error} end
    CustomGameEventManager:Send_ServerToPlayer(player,"survival_public_beta_gift_snapshot",snapshot)
end
function M.subscribe_legacy_public_beta(player_id)
    local player=PlayerResource and PlayerResource:GetPlayer(player_id)
    if not player then return false end
    public_beta_legacy_subscribers[player_id]=player
    public_beta_viewers[player_id]=player
    return true
end
function M.reset_public_beta_legacy()public_beta_legacy_subscribers={}end
function M.disconnect_public_beta(player_id)
    public_beta_legacy_subscribers[player_id],public_beta_viewers[player_id]=nil,nil
    if compact_public_beta then compact_public_beta.disconnect(player_id)end
end
function M.public_beta_gift_claim(player_id,request_id)
    if type(request_id)~="string" or #request_id<8 or #request_id>64
        or request_id:find("[^A-Za-z0-9_-]") then
        return {ok=false,terminal=true,error="领取请求无效"}
    end
    local existing=public_beta_claims[player_id]
    if existing and existing.pending then return copy(existing.result or {
        request_id=existing.request_id,day_key=existing.day_key,ok=true,pending=true}) end
    local snapshot=M.public_beta_gift_snapshot(player_id)
    if not snapshot.ok then return {request_id=request_id,ok=false,terminal=true,error=snapshot.error} end
    if not public_beta_writable() then return {request_id=request_id,ok=false,terminal=true,error="当前测试局仅可查看活动"} end
    if snapshot.active~=1 then return {request_id=request_id,ok=false,terminal=true,error="活动尚未开始或已结束"} end
    if snapshot.claimed==1 then return {request_id=request_id,day_key=snapshot.day_key,
        ok=false,terminal=true,error="今日好礼已领取"} end
    local claim={request_id=request_id,day_key=snapshot.day_key,pending=true,
        operation_id=session_id..":public_beta_gift:"..snapshot.day_key}
    claim.result={request_id=request_id,day_key=claim.day_key,ok=true,pending=true,terminal=false}
    public_beta_claims[player_id]=claim
    local submitted=enqueue(player_id,{id=claim.operation_id,kind="benefit_claim",
        track=PUBLIC_BETA_TIER,tier_id=PUBLIC_BETA_TIER})
    if not submitted.ok and not (pending[player_id] or {})[claim.operation_id] then
        claim.pending=false
        claim.result={request_id=request_id,day_key=claim.day_key,ok=false,
            terminal=true,error=submitted.error}
    end
    return copy(claim.result or {request_id=request_id,day_key=claim.day_key,ok=true,pending=true})
end
function M.set_purchase_provider(provider)
    assert(provider==nil or type(provider.open_checkout)=="function" or type(provider.create_order)=="function")
    purchase_provider=provider
end

function M.record_clear(player_id, difficulty_id, cooperative_win)
    local difficulty = string.lower(tostring(difficulty_id or ""))
    local ok, setup = pcall(require, "systems/match_setup_service")
    local mode = ok and type(setup.get_mode) == "function" and setup.get_mode() or nil
    local rich_capability = type(profiles.supports_rich_mode) == "function" and profiles.supports_rich_mode(player_id)
    local kind = (mode == "rich" or mode == "cold" or mode == "scourge") and (mode .. "_clear")
        or mode == "standard" and rich_capability and "standard_clear" or "clear"
    return enqueue(player_id, { id = session_id .. ":" .. kind, kind = kind,
        difficulty_id = difficulty, count = 1, cooperative_win = cooperative_win == 1 and 1 or 0,
        day_key = tostring(require("systems/archive_calendar").day()) })
end

function M.record_endless_wave(player_id, wave_number, difficulty, variant)
    variant = variant or "endless"
    if variant ~= "endless" and variant ~= "tower" then return {ok=false,error="endless_variant_invalid"} end
    if not integer(wave_number) or wave_number < 1 or not tonumber(difficulty)
        or not require("systems/archive_endless_config").wave(tonumber(difficulty), wave_number) then
        return { ok = false, error = "endless_wave_invalid" }
    end
    local command = { id = session_id .. ":" .. variant .. ":" .. wave_number,
        kind = "endless", wave = wave_number, difficulty = tonumber(difficulty) }
    if variant == "tower" then command.variant = variant end
    return enqueue(player_id, command)
end

function M.flush_endless_rewards(player_id)
    player_id = tonumber(player_id)
    if not integer(player_id) then return {ok=false,error="player_invalid"} end
    if not endless_pending(player_id) then return {ok=true} end
    endless_force[player_id] = true
    scheduler.cancel("archive_endless_flush:" .. player_id)
    return flush(player_id) or {ok=true,pending=true}
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

-- A dispatcher retry must distinguish this reward from unrelated queued work.
function M.has_reward_pending(player_id, kind, reward_id, variant)
    for _, command in pairs(pending[player_id] or {}) do
        if command.kind == kind and (kind == "challenge" and command.challenge_id == reward_id
            or kind == "endless" and command.wave == reward_id
                and (command.variant or "endless") == (variant or "endless")) then return true end
    end
    return false
end

function M.record_challenge(player_id, challenge_id, kill_sequence, difficulty_id)
    if not integer(kill_sequence) then return { ok = false, error = "archive_kill_id_invalid" } end
    local definition = require("config/generated/archive_challenge_definitions").by_id[challenge_id]
    if not definition or not definition.enabled then return {ok=false,error="archive_challenge_unknown"} end
    return enqueue(player_id, { id = session_id .. ":challenge_kind:" .. challenge_id,
        kind = "challenge", challenge_id = challenge_id, kill_sequence = kill_sequence,
        difficulty_id = difficulty_id, day_key = day_key() })
end

function M.social_draw(player_id, pool_id, request_id)
    player_id = tonumber(player_id)
    request_id = tostring(request_id or "")
    if not integer(player_id) then return {ok=false,error="player_invalid",terminal=true} end
    local function reject(message)
        local result = {ok=false,error=message,terminal=true}
        social_result(player_id, pool_id, request_id, result)
        return result
    end
    if not require("config/generated/archive_social_rules").by_id[pool_id] then return reject("奖池无效") end
    if #request_id < 1 or #request_id > 80 or request_id:find("[^%w_-]") then return reject("请求无效") end
    local id = session_id..":social_draw:"..request_id
    local existing = pending[player_id] and pending[player_id][id]
    if existing and existing.pool_id ~= pool_id then return reject("请求奖池不一致") end
    -- A previously accepted request must remain pending until its provider
    -- settles, even if a profile refresh or end-of-match save is in progress.
    if existing then
        social_result(player_id, pool_id, request_id, {pending=true})
        return {ok=true,pending=true}
    end
    if finalizing then return reject("正在保存本局奖励，请等待结算") end
    if not account_profile(player_id) then return reject("玩家档案尚未加载") end
    social_result(player_id, pool_id, request_id, {pending=true})
    return enqueue(player_id, {id=id, kind="social_draw", pool_id=pool_id})
end

function M.zaixian(context)
    if not require("core/release_policy").development_allowed() then
        return false, "release_debug_disabled"
    end
    local args = context.args or {}
    local minutes = tonumber(args[1])
    if #args ~= 1 or not integer(minutes) or minutes < 1 or minutes > 1000000 then
        return false, "用法：zaixian <1..1000000分钟>（累加在线时间）"
    end
    local profile = account_profile(context.player_id)
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

function M.xinyang(context)
    if not require("core/release_policy").development_allowed() then
        return false, "release_debug_disabled"
    end
    local args = context.args or {}
    local amount = tonumber(args[1])
    if #args ~= 1 or not integer(amount) or amount < 1 or amount > 1000000000 then
        return false, "用法：xinyang <1..1000000000整数>（添加信仰值）"
    end
    serial = (serial or 0) + 1
    local result = enqueue(context.player_id, {id=session_id..":xinyang:"..serial,
        kind="faith_cheat",amount=amount})
    if result.ok then
        bus.emit(events.UI_NOTIFICATION, {player_id=context.player_id,level="info",
            message="添加信仰值"..amount.."的请求已提交，请在存档建筑查看余额"})
    end
    return result.ok, result.error
end

function M.yitie(context)
    if not require("core/release_policy").development_allowed() then
        return false, "release_debug_disabled"
    end
    local amount = tonumber(context.args[1])
    local pool = context.args[2] or "friend"
    if #context.args < 1 or #context.args > 2 or not integer(amount) or amount > 1000000
        or not require("config/generated/archive_social_rules").by_id[pool] then return false, "usage: yitie <0..1000000> [friend|ex|wife|beast]" end
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

function M.building_upgrade(player_id, item_id, expected_level)
    local item = require("config/generated/archive_building_items").by_id[tostring(item_id or "")]
    expected_level = tonumber(expected_level)
    if not item or not item.enabled or not integer(expected_level) or expected_level >= item.max_level then
        return {ok=false,error="建筑升级请求无效"}
    end
    -- A failed purchase must remain retryable after earning more faith in the same session.
    serial = (serial or 0) + 1
    return enqueue(player_id, {id=session_id .. ":building:" .. item.item_id .. ":" .. expected_level .. ":" .. serial,
        kind="building_upgrade",item_id=item.item_id,expected_level=expected_level})
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
    if not require("core/release_policy").development_allowed() then
        return false, "release_debug_disabled"
    end
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
        kind = "clear", difficulty_id = difficulty, count = count, day_key = tostring(require("systems/archive_calendar").day()), test_only = true })
    return result.ok, result.error
end

function M.begin_finalization()
    if finalizing then return end
    local clock = require("systems/archive_online_clock")
    for id in pairs(archive_players) do clock.flush(id) end
    finalizing = true
    for id in pairs(pending) do flush(id) end
end

-- Keep this bootstrap outside init: Lua 5.1 limits each closure to 60 upvalues.
function M.setup_compact_public_beta()
    if compact_daily_transport and compact_daily_lookup and compact_daily_lookup.by_key['public_beta:state']then
        local own=type(bus.get_generation)=='function'and bus.get_generation()or bus
        if compact_public_beta_world~=own then
            if compact_public_beta then compact_public_beta.dispose()end
            compact_public_beta=require('ui/compact_public_beta_view').new({lookup=compact_daily_lookup,transport=compact_daily_transport,
                current=function()return(type(bus.get_generation)=='function'and bus.get_generation()or bus)==own end,
                player=function(id)return PlayerResource and PlayerResource:GetPlayer(id)end,
                snapshot=function(id,profile)
                    local snapshot=M.public_beta_gift_snapshot(id,profile)
                    snapshot.claim_result=public_beta_claims[id]and public_beta_claims[id].result
                    return snapshot
                end,claim=M.public_beta_gift_claim,
                config=function()return require('config/generated/archive_benefit_rewards').by_id[PUBLIC_BETA_TIER]end,
                subscribe=function(id,on)
                    if on then public_beta_legacy_subscribers[id]=nil end
                    public_beta_viewers[id]=on and PlayerResource:GetPlayer(id)or nil
                end})
            compact_public_beta_world=own
        else compact_public_beta.reset()end
    end
end

function M.init()
    require("systems/title_presentation_service").init()
    finalizing = false
    sent_pages = {}
    archive_queue_generation=archive_queue_generation+1
    scheduler.cancel("archive_ui_queue")
    archive_delivery,archive_head,archive_tail={},nil,nil
    legacy_archive_players={}
    archive_queue_scheduled,archive_queue_running=false,false
    queue_runtime.generation=queue_runtime.generation+1
    for id in pairs(queue_runtime.wakes) do scheduler.cancel("archive_ready:"..id) end
    queue_runtime.index,queue_runtime.wakes={},{}
    for id in pairs(pending) do scheduler.cancel("archive_endless_flush:" .. id) end
    endless_due, endless_force = {}, {}
    pending, busy, selected, throttles = {}, {}, {}, {}
    reward_notifications = {}
    public_beta_viewers, public_beta_sequences, public_beta_claims = {}, {}, {}
    M.reset_public_beta_legacy()
    daily_generation=daily_generation+1
    for id,state in pairs(daily_delivery) do stop_daily_job(id,state) end
    for id in pairs(pass_deadlines) do scheduler.cancel("archive_pass_deadline:"..id) end
    daily_viewers,daily_delivery,daily_sequences,pass_deadlines={},{},{},{}
    compact_daily_states,compact_daily_users,compact_daily_tokens={},{},{}
    vip_viewers,legacy_vip_players = {},{}
    archive_players = {}
    serial = 0
    session_id = runtime_id()
    local online_clock = require("systems/archive_online_clock")
    online_clock.init(session_id, enqueue)
    local http_adapter = require("systems/archive_http_adapter")
    if http_adapter.enabled() then M.set_provider(http_adapter) end
    bus.subscribe(events.PLAYER_PROFILE_CHANGED, function(payload)
        local id = tonumber(payload.player_id)
        if id then
            archive_players[id]=true
            local profile = account_profile(id)
            online_clock.observe(id, profile)
            track_pass_deadline(id,profile)
            -- The server's saved best floor can unlock newly added milestones.
            -- Never trust a floor/count supplied by the UI or award it on reads.
            if profile and require("systems/archive_starjoy_rewards").needs_reconcile(profile.save.gameplay_stats) then
                enqueue(id, {id=session_id..":starjoy_reconcile", kind="starjoy_reconcile"})
            end
            if profile and require("systems/archive_welfare_rewards").needs_reconcile(profile.save.archive) then
                enqueue(id, {id=session_id..":welfare_reconcile", kind="welfare_reconcile"})
            end
            if profile and (require("systems/archive_endless_rewards").needs_reconcile(profile.save.archive)
                or require("systems/archive_titles").needs_reconcile(profile.save.archive)) then
                enqueue(id, {id=session_id..":endless_reconcile", kind="endless_reconcile"})
            end
            if compact_bound(id) and compact_archive_views then
                local metadata=require("ui/compact_profile_context").current(id)
                compact_archive_views.changed(id,profile,metadata and metadata.compact_archive_changes or {replace=true})
            else send(id,nil,profile) end
            if compact_daily_users[id] then compact_daily_changed(id,payload,profile)
            elseif daily_viewers[id] or daily_delivery[id] then M.send_daily(id,nil,nil,nil,profile) end
            if public_beta_viewers[id] then M.send_public_beta_gift(id,nil,profile) end
            if vip_viewers[id] then M.send_vip(id) end
            if not busy[id] then flush(id) end
        end
    end)
    bus.subscribe(events.PLAYER_DISCONNECTED, function(payload)
        local id = tonumber(payload.player_id)
        if id then
            local state=archive_delivery[id]
            if state then for _,job in pairs(state.jobs) do finish_archive_job(job) end end
            archive_delivery[id]=nil;sent_pages[id]=nil
            legacy_archive_players[id]=nil
            vip_viewers[id],legacy_vip_players[id]=nil,nil
            daily_viewers[id]=nil
            M.disconnect_public_beta(id)
            compact_daily_states[id],compact_daily_users[id],compact_daily_tokens[id]=nil,nil,nil
            if compact_archive_views then compact_archive_views.disconnect(id) end
            stop_daily_job(id,daily_delivery[id]);daily_delivery[id]=nil
            online_clock.disconnect(id); M.flush_endless_rewards(id)
        end
    end)
    scheduler.every(1, function()
        if finalizing or http_adapter.enabled() then return end -- Remote online credit consumes the existing DB checkpoint only.
        -- Iterate valid slots as well as profile events, so reopening the archive is never needed to earn time.
        for id = 0, (DOTA_MAX_TEAM_PLAYERS or 24) - 1 do
            if PlayerResource and PlayerResource:IsValidPlayerID(id) then
                local profile = account_profile(id)
                if profile then
                    archive_players[id] = true
                    online_clock.sample(id, profile)
                end
            end
        end
    end, "archive_online_clock")
    bus.subscribe("archive.wave_boss_killed",function(payload) M.record_boss(payload.player_id,payload.kill_id) end)
    local vip_times={}
    CustomGameEventManager:RegisterListener("survival_vip_request",function(_,payload)
        local id=tonumber(payload.PlayerID)
        if not integer(id) or not PlayerResource:IsValidPlayerID(id) then return end
        local now=GameRules:GetGameTime()
        if vip_times[id] and now-vip_times[id]<0.3 then return end
        vip_times[id]=now;vip_viewers[id]=PlayerResource:GetPlayer(id);legacy_vip_players[id]=vip_viewers[id]
        if payload.action=="claim" or payload.action=="purchase" then
            local result=M.vip_action(id,payload.action=="claim" and "vip_claim" or "vip_purchase",payload.reward_id)
            M.send_vip(id,result)
        else M.send_vip(id) end
    end)
    local daily_times = {}
    local public_beta_times={}
    CustomGameEventManager:RegisterListener("survival_public_beta_gift_request",function(_,payload)
        local id=tonumber(payload.PlayerID)
        if not integer(id) or not PlayerResource:IsValidPlayerID(id) then return end
        if compact_bound(id)then return end
        if not M.subscribe_legacy_public_beta(id)then return end
        M.send_public_beta_gift(id)
    end)
    CustomGameEventManager:RegisterListener("survival_public_beta_gift_claim",function(_,payload)
        local id=tonumber(payload.PlayerID)
        if not integer(id) or not PlayerResource:IsValidPlayerID(id) then return end
        if compact_bound(id)then return end
        local now=GameRules:GetGameTime()
        if public_beta_times[id] and now-public_beta_times[id]<0.3 then return end
        if not M.subscribe_legacy_public_beta(id)then return end
        public_beta_times[id]=now;archive_players[id]=true
        M.send_public_beta_gift(id,M.public_beta_gift_claim(id,payload.request_id))
    end)
    CustomGameEventManager:RegisterListener("survival_daily_request",function(_,payload)
        local id=tonumber(payload.PlayerID)
        if not integer(id) or not PlayerResource:IsValidPlayerID(id) then return end
        local state=daily_delivery[id]
        local v2=tonumber(payload.wire_v)==2
        local view_id=v2 and tostring(payload.view_id or "") or "legacy"
        if v2 and (#view_id<1 or #view_id>96 or view_id:find("[^A-Za-z0-9_.:-]")) then return end
        if payload.open==0 or payload.open==false then
            if state and state.view_id==view_id then
                daily_viewers[id]=nil;stop_daily_job(id,state)
            end
            return
        end
        local player=PlayerResource:GetPlayer(id)
        if not player then return end
        if not state or state.view_id~=view_id or state.player~=player or state.wire_v~=(v2 and 2 or 1) then
            stop_daily_job(id,state)
            state={view_id=view_id,wire_v=v2 and 2 or 1,player=player}
            daily_delivery[id]=state
        end
        daily_viewers[id]=(not v2 or payload.subscribe==1 or payload.open==1) and true or nil
        local profile=account_profile(id)
        if not profile then M.send_daily(id,nil,nil,true);return end
        archive_players[id]=true
        if not (profile.save.archive and profile.save.archive.daily_rewards) then
            enqueue(id,{id=session_id..":daily_init",kind="daily_init",today=require("systems/archive_calendar").day()})
        end
        M.send_daily(id,nil,nil,true,profile)
    end)
    local function daily_claim_request(_,payload)
        local id=tonumber(payload.PlayerID)
        if not integer(id) or not PlayerResource:IsValidPlayerID(id) then return end
        local now=GameRules:GetGameTime()
        if daily_times[id] and now-daily_times[id]<0.3 then return end
        daily_times[id]=now
        local result=M.daily_claim(id,payload.target_day)
        if not result.ok and not compact_daily_users[id] then bus.emit(events.UI_NOTIFICATION,{player_id=id,level="error",message=result.error}) end
        M.send_daily(id,{target_day=payload.target_day,ok=result.ok==true,pending=result.pending==true,error=result.error})
        return result
    end
    compact_daily_handlers.daily=daily_claim_request
    CustomGameEventManager:RegisterListener("survival_daily_claim",daily_claim_request)
    local benefit_times={}
    local function benefit_claim_request(_,payload)
        local id=tonumber(payload.PlayerID)
        if not integer(id) or not PlayerResource:IsValidPlayerID(id) then return end
        local now=GameRules:GetGameTime()
        if benefit_times[id] and now-benefit_times[id]<0.3 then return end
        benefit_times[id]=now
        if not daily_delivery[id] and not compact_daily_users[id] then daily_viewers[id]=true end
        archive_players[id]=true
        local result=M.benefit_claim(id,payload.track,payload.tier_id)
        if not result.ok and not compact_daily_users[id] then bus.emit(events.UI_NOTIFICATION,{player_id=id,level="error",message=result.error}) end
        M.send_daily(id,nil,{track=payload.track,tier_id=payload.tier_id,ok=result.ok==true,
            pending=result.pending==true,error=result.error,terminal=result.terminal==true})
        return result
    end
    compact_daily_handlers.benefit=benefit_claim_request
    CustomGameEventManager:RegisterListener("survival_benefit_claim",benefit_claim_request)
    local purchase_times={}
    local function pass_purchase_request(_,payload)
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
        -- Opening checkout does not create a charge. Legacy adapters retain
        -- their server-generated correlation key; the client cannot pick a SKU.
        local open_checkout=purchase_provider.open_checkout or purchase_provider.create_order
        local ok=pcall(open_checkout,id,{sku=rules.pass_sku or rules.pass_entitlement_id,
            request_id=session_id..":pass_order:"..serial},function(result)
            bus.emit(events.UI_NOTIFICATION,{player_id=id,level="info",message=result and result.message or "订单处理中"})
            M.send_daily(id)
        end)
        if not ok then bus.emit(events.UI_NOTIFICATION,{player_id=id,level="error",message="订单创建失败，请稍后重试"}) end
    end
    compact_daily_handlers.purchase=pass_purchase_request
    CustomGameEventManager:RegisterListener("survival_pass_purchase",pass_purchase_request)
    local clock_day=require("systems/archive_calendar").day()
    scheduler.every(1,function()
        -- Constant-cost wall-clock check. Expiring passes have their own single
        -- deadline; account/benefit progress arrives through profile events.
        local day=require("systems/archive_calendar").day()
        if day==clock_day then return end
        clock_day=day
        for id in pairs(archive_players) do
            bus.emit(events.PLAYER_PROFILE_CHANGED,{player_id=id,reason="archive_day_reset"})
        end
    end,"archive_daily_clock")
    bus.subscribe("archive.final_wave_cleared", function(payload)
        M.record_clear(payload.player_id, payload.difficulty_id, payload.cooperative_win)
    end)
    scheduler.every(2, function()
        for id in pairs(pending) do flush(id) end
    end, "archive_retry")
    CustomGameEventManager:RegisterListener("survival_archive_request", function(_, payload)
        -- PlayerID is injected by Dota. Never accept a client account/player_id.
        local id = tonumber(payload.PlayerID)
        if not integer(id) or not PlayerResource:IsValidPlayerID(id) then return end
        if compact_bound(id)then cancel_legacy_archive(id);return end
        local category = categories.by_id[tostring(payload.category_id or "clear")]
        if not category or not category.enabled then return end
        local player=PlayerResource:GetPlayer(id)
        if not player then return end
        legacy_archive_players[id]=player
        local now = GameRules:GetGameTime()
        -- A real category switch must still reprioritize the final selection
        -- during fast clicking; duplicate requests keep the old throttle.
        if selected[id]==category.category_id and throttles[id] and now-throttles[id]<0.15 then return end
        throttles[id] = now
        selected[id] = category.category_id
        send(id,category.category_id,nil,payload.resync==1,true)
    end)
    local title_times = {}
    CustomGameEventManager:RegisterListener("survival_archive_title_equip",function(_,payload)
        local id=tonumber(payload.PlayerID)
        if not integer(id) or not PlayerResource:IsValidPlayerID(id) then return end
        local now=GameRules:GetGameTime()
        if title_times[id] and now-title_times[id]<0.3 then return end
        title_times[id]=now
        local result=M.equip_title(id,payload.title_id)
        if not result.ok then bus.emit(events.UI_NOTIFICATION,{player_id=id,level="error",message=result.error}) end
        -- Always acknowledge, even when an unchanged snapshot would be suppressed.
        local player=PlayerResource:GetPlayer(id)
        if player then CustomGameEventManager:Send_ServerToPlayer(player,"survival_archive_title_result",
            {ok=result.ok,error=result.error,preview=result.preview and 1 or 0}) end
        sent_pages[id]=nil
        send_page(id,"titles")
    end)
    local promotion_times = {}
    local draw_times = {}
    local building_times = {}
    CustomGameEventManager:RegisterListener("survival_archive_building_upgrade", function(_, payload)
        local id = tonumber(payload.PlayerID)
        if not integer(id) or not PlayerResource:IsValidPlayerID(id) then return end
        local now = GameRules:GetGameTime()
        if building_times[id] and now - building_times[id] < 0.3 then return end
        building_times[id] = now
        local result = M.building_upgrade(id, payload.item_id, payload.expected_level)
        if not result.ok then bus.emit(events.UI_NOTIFICATION, {player_id=id,level="error",message=result.error}) end
        send(id)
    end)
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
        if draw_times[id] and time - draw_times[id] < 0.3 then
            local request_id = tostring(payload.request_id or "")
            local queued = pending[id] and pending[id][session_id..":social_draw:"..request_id]
            if queued and queued.pool_id == payload.pool_id then
                social_result(id, payload.pool_id, request_id, {pending=true})
            else
                social_result(id, payload.pool_id, request_id, {ok=false,terminal=true,error="操作过于频繁，请稍后重试"})
            end
            return
        end
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
    setup_compact_daily()
    M.setup_compact_public_beta()
    if compact_daily_transport and compact_daily_lookup and compact_daily_lookup.by_key['vip:state']then
        local own=type(bus.get_generation)=='function'and bus.get_generation()or bus
        if compact_vip_world~=own then
            if compact_vip then compact_vip.dispose()end
            compact_vip=require('ui/compact_vip_view').new({lookup=compact_daily_lookup,transport=compact_daily_transport,
                current=function()return(type(bus.get_generation)=='function'and bus.get_generation()or bus)==own end,
                player=function(id)return PlayerResource and PlayerResource:GetPlayer(id)end,
                profile=account_profile,rewards=require('systems/archive_vip_rewards'),
                subscribe=function(id,on)
                    vip_viewers[id]=on and PlayerResource:GetPlayer(id)or nil
                    if on then legacy_vip_players[id]=nil end
                end})
            compact_vip_world=own
        else compact_vip.reset()end
    end
    if compact_daily_transport and type(compact_daily_transport.available)=="function" and compact_daily_transport.available() then
        local ok,bridge=pcall(require,"ui/compact_archive_views")
        if ok then
            compact_archive_views=bridge;local active=bridge.init()
            if active and active.reset then active.reset() end
        end
    end
end

M._test = { apply_effects = apply_effects, has_pass = has_pass, flush = flush }
return M
