package.path = "scripts/vscripts/?.lua;scripts/vscripts/?/init.lua;"
    .. package.path

local captured_packet = nil
local captured_bridge_payload = nil
local persisted_isolated = nil
local persisted_full = nil
local isolation_field = nil
local armor_reset_count = 0

package.loaded["core/json_encoder"] = {
    encode = function(packet)
        if type(packet) == "table" and packet.source
            == "survival_local_fixture_bridge" then
            captured_bridge_payload = packet
        else
            captured_packet = packet
        end
        return "encoded_packet"
    end,
}
package.loaded["core/json_decoder"] = { decode = function() return captured_packet end }
package.loaded["core/logger"] = { info = function() end }

local generated = require("config/generated/player_gameplay_stats")
local profile = {
    schema_version = 1,
    account_id = "test_account",
    revision = 7,
    save = { gameplay_stats = {} },
}
for _, row in ipairs(generated.rows) do
    if row.enabled ~= false then
        profile.save.gameplay_stats[row.field_id] = tonumber(row.default_value) or 0
    end
end

local provider = {
    persist_isolated_gameplay_stat = function(account_id, field_id, value, revision)
        persisted_isolated = {
            account_id = account_id,
            field_id = field_id,
            value = value,
            revision = revision,
        }
        return true
    end,
    persist_gameplay_stats = function(account_id, stats, revision)
        persisted_full = { account_id = account_id, stats = stats, revision = revision }
        return true
    end,
}

package.loaded["systems/player_profile_service"] = {
    get_profile = function() return profile end,
    get_provider = function() return provider end,
    apply_incremental = function()
        profile.revision = captured_packet.revision
        if captured_packet.gameplay_stats_mode ~= "isolated_test" then
            profile.save.gameplay_stats = captured_packet.changes.save.gameplay_stats
        end
        return { ok = true, revision = profile.revision }
    end,
}
package.loaded["systems/permanent_reward_effect_service"] = {
    set_test_isolation = function(_, field_id)
        isolation_field = field_id
        return true
    end,
    clear_test_isolation = function()
        isolation_field = nil
        return true
    end,
}
package.loaded["systems/research_armor_reduction_service"] = {
    reset_for_isolated_test = function()
        armor_reset_count = armor_reset_count + 1
    end,
}

local service = require("systems/player_gameplay_stats_order_service")
local result = service.test_order(0, "hero_attack_armor_reduction", 10)
assert(result.ok and result.isolated and result.value == 10)
assert(isolation_field == "hero_attack_armor_reduction")
assert(captured_packet.gameplay_stats_mode == "isolated_test")
assert(captured_bridge_payload
    and captured_bridge_payload.account_id == "test_account")
assert(captured_packet.operations[1].operation == "set")
assert(captured_packet.operations[1].value == 10)
local sparse = captured_packet.changes.save.gameplay_stats
assert(sparse.hero_attack_armor_reduction == 10)
local sparse_count = 0
for _ in pairs(sparse) do sparse_count = sparse_count + 1 end
assert(sparse_count == 1, "isolated JSON must contain exactly one gameplay stat")
assert(persisted_isolated.field_id == "hero_attack_armor_reduction")
assert(persisted_isolated.value == 10)
assert(armor_reset_count == 1)

local reset = service.reset_defaults(0)
assert(reset.ok)
assert(isolation_field == nil)
assert(persisted_full and persisted_full.stats.initial_wood == 10)
assert(persisted_full.stats.hero_initial_attack == 100)
assert(armor_reset_count == 2)

print("GAMEPLAY_STATS_ORDER_ISOLATION_PASS")
