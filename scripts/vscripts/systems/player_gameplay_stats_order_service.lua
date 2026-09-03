-- Local mock of the server-side gameplay-stats delta endpoint.
--
-- The public entry point accepts the same shape that the future HTTP service
-- will send: one account-scoped packet containing a base revision and a
-- single additive operation.  The local fixture provider keeps the resulting
-- snapshot in memory so a profile reload in the same match sees the update.
local json_encoder = require("core/json_encoder")
local json_decoder = require("core/json_decoder")
local logger = require("core/logger")
local gameplay_stats = require("config/generated/player_gameplay_stats")
local profile_service = require("systems/player_profile_service")

local M = {}

-- TODO(HTTP/Supabase integration): order packets currently use the local
-- file-backed JSON provider. Once the service endpoint is approved, replace
-- this persistence call with the HTTP response while retaining apply_packet's
-- schema/revision/idempotency validation.
local sequence = 0

local function copy_table(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do
        result[copy_table(key)] = copy_table(child)
    end
    return result
end

local function finite_number(value)
    value = tonumber(value)
    if value == nil or value ~= value or value == math.huge
        or value == -math.huge then
        return nil
    end
    return value
end

local function next_update_id(player_id, revision)
    sequence = sequence + 1
    return string.format("local_order:%s:%s:%s", tostring(player_id),
        tostring(revision), tostring(sequence))
end

local function valid_field_value(row, field_id, value)
    value = finite_number(value)
    if value == nil then return nil, "gameplay_stat_value_invalid:" .. field_id end
    if row.storage_type == "integer" and value ~= math.floor(value) then
        return nil, "gameplay_stat_requires_integer:" .. field_id
    end
    if row.min_value ~= nil and value < tonumber(row.min_value) then
        return nil, "gameplay_stat_below_min:" .. field_id
    end
    if row.max_value ~= nil and value > tonumber(row.max_value) then
        return nil, "gameplay_stat_above_max:" .. field_id
    end
    return value
end

local function build_packet(player_id, field_id, delta)
    local profile = profile_service.get_profile(player_id)
    if not profile then return nil, "profile_not_loaded" end
    local row = gameplay_stats.by_id[field_id]
    if not row or row.enabled == false then
        return nil, "gameplay_stat_unknown:" .. tostring(field_id)
    end

    local stats = profile.save and profile.save.gameplay_stats
    if type(stats) ~= "table" then return nil, "gameplay_stats_missing" end
    local old_value = finite_number(stats[field_id])
    if old_value == nil then return nil, "gameplay_stat_value_invalid:" .. field_id end
    local next_value = old_value + delta
    local validated, validation_error = valid_field_value(
        row, field_id, next_value
    )
    if validated == nil then return nil, validation_error end
    next_value = validated

    local next_stats = copy_table(stats)
    next_stats[field_id] = next_value
    local revision = tonumber(profile.revision) or 0
    return {
        schema_version = tonumber(profile.schema_version) or 1,
        account_id = tostring(profile.account_id),
        player_id = player_id,
        update_id = next_update_id(player_id, revision + 1),
        base_revision = revision,
        revision = revision + 1,
        operations = {
            { field_id = field_id, delta = delta },
        },
        changes = {
            save = { gameplay_stats = next_stats },
        },
    }, nil, old_value, next_value
end

local function build_isolated_packet(player_id, field_id, value)
    local profile = profile_service.get_profile(player_id)
    if not profile then return nil, "profile_not_loaded" end
    local row = gameplay_stats.by_id[field_id]
    if not row or row.enabled == false then
        return nil, "gameplay_stat_unknown:" .. tostring(field_id)
    end
    local validated, validation_error = valid_field_value(row, field_id, value)
    if validated == nil then return nil, validation_error end
    local revision = tonumber(profile.revision) or 0
    return {
        schema_version = tonumber(profile.schema_version) or 1,
        account_id = tostring(profile.account_id),
        player_id = player_id,
        update_id = next_update_id(player_id, revision + 1),
        base_revision = revision,
        revision = revision + 1,
        gameplay_stats_mode = "isolated_test",
        operations = {
            { field_id = field_id, operation = "set", value = validated },
        },
        -- Keep the simulated server JSON sparse. player_profile_service owns
        -- expansion into the full schema-valid neutral runtime snapshot.
        changes = {
            save = { gameplay_stats = { [field_id] = validated } },
        },
    }, nil, validated
end

local function build_defaults_packet(player_id)
    local profile = profile_service.get_profile(player_id)
    if not profile then return nil, "profile_not_loaded" end
    local defaults = {}
    for _, row in ipairs(gameplay_stats.rows or {}) do
        if row.enabled ~= false then
            defaults[tostring(row.field_id)] = tonumber(row.default_value) or 0
        end
    end
    local revision = tonumber(profile.revision) or 0
    return {
        schema_version = tonumber(profile.schema_version) or 1,
        account_id = tostring(profile.account_id),
        player_id = player_id,
        update_id = next_update_id(player_id, revision + 1),
        base_revision = revision,
        revision = revision + 1,
        operations = { { operation = "reset_defaults" } },
        changes = { save = { gameplay_stats = defaults } },
    }
end

function M.build_packet(player_id, field_id, delta)
    delta = finite_number(delta)
    if delta == nil then return nil, "delta_invalid" end
    return build_packet(tonumber(player_id), tostring(field_id or ""), delta)
end

local function persist_local_snapshot(player_id, packet)
    local provider = profile_service.get_provider()
    if not provider or type(provider.persist_gameplay_stats) ~= "function" then
        return true
    end
    local profile = profile_service.get_profile(player_id)
    if not profile or type(profile.save) ~= "table" then
        return false, "profile_not_loaded"
    end
    if packet and packet.gameplay_stats_mode == "isolated_test"
        and type(provider.persist_isolated_gameplay_stat) == "function" then
        local operation = packet.operations and packet.operations[1] or {}
        return provider.persist_isolated_gameplay_stat(
            profile.account_id,
            operation.field_id,
            operation.value,
            profile.revision
        )
    end
    return provider.persist_gameplay_stats(
        profile.account_id, profile.save.gameplay_stats, profile.revision
    )
end

-- VScript cannot use Lua file I/O in the shipped Dota VM. Emit a dedicated,
-- machine-readable line for the optional local bridge process instead. The
-- bridge tails console.log and writes the same snapshot to the mock JSON;
-- HTTP/Supabase remains the production replacement (TODO below).
local function emit_bridge_packet(packet)
    if type(packet) ~= "table" or type(packet.account_id) ~= "string" then
        return false
    end
    local changes = packet.changes and packet.changes.save
    local stats = changes and changes.gameplay_stats
    if type(stats) ~= "table" then return false end
    local payload = {
        schema_version = tonumber(packet.schema_version) or 1,
        account_id = packet.account_id,
        revision = tonumber(packet.revision) or 0,
        gameplay_stats_mode = packet.gameplay_stats_mode,
        gameplay_stats = stats,
        source = "survival_local_fixture_bridge",
    }
    local ok, encoded = pcall(json_encoder.encode, payload)
    if not ok then
        logger.warn("GameplayStats", "local_fixture_bridge_encode_failed:" .. tostring(encoded))
        return false
    end
    logger.info("LocalFixtureBridge", "PERSIST_BRIDGE " .. tostring(encoded))
    return true
end

function M.apply_packet(packet)
    if type(packet) == "string" then
        local decode_ok, decoded = pcall(json_decoder.decode, packet)
        if not decode_ok then
            return { ok = false, error = "packet_json_invalid" }
        end
        packet = decoded
    end
    if type(packet) ~= "table" then return { ok = false, error = "packet_invalid" } end
    local packet_json
    local ok, encoded = pcall(json_encoder.encode, packet)
    if not ok then return { ok = false, error = "packet_encode_failed" } end
    packet_json = encoded

    -- Route through the JSON decoder path to keep the local mock contract
    -- identical to the future HTTP response body.
    local result = profile_service.apply_incremental(packet_json)
    if not result or result.ok ~= true then
        result = result or { ok = false, error = "profile_update_failed" }
        result.packet_json = packet_json
        return result
    end
    local player_id = tonumber(packet.player_id)
    if player_id ~= nil then
        local persisted, persist_error = persist_local_snapshot(player_id, packet)
        if persisted == false then
            result.persist_error = persist_error
            logger.warn("GameplayStats", string.format(
                "local_fixture_persist_failed player=%s account=%s error=%s",
                tostring(player_id), tostring(packet.account_id),
                tostring(persist_error)))
        end
        result.persisted = persisted ~= false
        result.bridge_queued = emit_bridge_packet(packet)
    end
    result.packet_json = packet_json
    return result
end

local function reward_effect_service()
    local ok, service = pcall(require, "systems/permanent_reward_effect_service")
    return ok and service or nil
end

local function reset_applied_armor_reduction()
    local ok, service = pcall(require, "systems/research_armor_reduction_service")
    if ok and type(service.reset_for_isolated_test) == "function" then
        service.reset_for_isolated_test()
    end
end

function M.order(player_id, field_id, delta)
    player_id = tonumber(player_id)
    field_id = tostring(field_id or "")
    delta = finite_number(delta)
    if player_id == nil or player_id < 0 then
        return { ok = false, error = "player_id_invalid" }
    end
    if field_id == "" then return { ok = false, error = "field_id_invalid" } end
    if delta == nil or delta == 0 then
        return { ok = false, error = "delta_invalid" }
    end
    local packet, error_code, old_value, next_value = build_packet(
        player_id, field_id, delta
    )
    if not packet then return { ok = false, error = error_code } end
    local result = M.apply_packet(packet)
    if not result.ok then return result end
    local rewards = reward_effect_service()
    if rewards and type(rewards.clear_test_isolation) == "function" then
        rewards.clear_test_isolation(player_id)
    end
    -- apply_incremental emits PLAYER_PROFILE_CHANGED.  Resource consumers
    -- therefore refresh immediately (initial_wood/initial_gold included).
    result.field_id = field_id
    result.delta = delta
    result.old_value = old_value
    result.new_value = next_value
    result.revision = packet.revision
    logger.info("GameplayStats", string.format(
        "local_order account=%s field=%s delta=%s old=%s new=%s revision=%s packet=%s",
        tostring(packet.account_id), field_id, tostring(delta),
        tostring(old_value), tostring(next_value), tostring(packet.revision),
        tostring(result.packet_json)))
    return result
end

-- Developer-only single-field mode. Unlike order, value is absolute. The
-- outgoing mock JSON contains only this field; all omitted fields are expanded
-- to neutral values by player_profile_service, and permanent rewards are
-- excluded from the runtime projection until reset/default order mode resumes.
function M.test_order(player_id, field_id, value)
    player_id = tonumber(player_id)
    field_id = tostring(field_id or "")
    value = finite_number(value)
    if player_id == nil or player_id < 0 then
        return { ok = false, error = "player_id_invalid" }
    end
    if field_id == "" then return { ok = false, error = "field_id_invalid" } end
    if value == nil then return { ok = false, error = "value_invalid" } end
    local packet, error_code, isolated_value = build_isolated_packet(
        player_id, field_id, value
    )
    if not packet then return { ok = false, error = error_code } end

    local rewards = reward_effect_service()
    if rewards and type(rewards.set_test_isolation) == "function" then
        local isolation_ok, isolation_error = rewards.set_test_isolation(
            player_id, field_id, true
        )
        if isolation_ok == false then
            return { ok = false, error = isolation_error }
        end
    end
    local result = M.apply_packet(packet)
    if not result.ok then
        if rewards and type(rewards.clear_test_isolation) == "function" then
            rewards.clear_test_isolation(player_id)
        end
        return result
    end
    reset_applied_armor_reduction()
    result.field_id = field_id
    result.value = isolated_value
    result.new_value = isolated_value
    result.revision = packet.revision
    result.isolated = true
    logger.info("GameplayStats", string.format(
        "local_order_test account=%s field=%s value=%s revision=%s packet=%s",
        tostring(packet.account_id), field_id, tostring(isolated_value),
        tostring(packet.revision), tostring(result.packet_json)))
    return result
end

function M.reset_defaults(player_id)
    player_id = tonumber(player_id)
    if player_id == nil or player_id < 0 then
        return { ok = false, error = "player_id_invalid" }
    end
    local packet, error_code = build_defaults_packet(player_id)
    if not packet then return { ok = false, error = error_code } end
    local result = M.apply_packet(packet)
    if not result.ok then return result end
    local rewards = reward_effect_service()
    if rewards and type(rewards.clear_test_isolation) == "function" then
        rewards.clear_test_isolation(player_id)
    end
    reset_applied_armor_reduction()
    result.revision = packet.revision
    logger.info("GameplayStats", string.format(
        "local_order_reset account=%s revision=%s packet=%s",
        tostring(packet.account_id), tostring(packet.revision),
        tostring(result.packet_json)))
    return result
end

function M._test_reset()
    sequence = 0
end

return M
