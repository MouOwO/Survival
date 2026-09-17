package.path = "scripts/vscripts/?.lua;scripts/vscripts/?/init.lua;"
    .. package.path

-- The provider now writes its local mock snapshot to disk. Keep this unit test
-- hermetic by replacing file handles with in-memory handles before requiring
-- the provider; a test run must never edit data/mock/player_profiles.json.
local real_io = io
local source_handle = assert(real_io.open(
    "data/mock/player_profiles.json", "rb"
))
local fixture_json = source_handle:read("*a")
source_handle:close()
local written_json = nil
io = {
    open = function(_, mode)
        if mode == "rb" then
            return {
                read = function() return fixture_json end,
                close = function() end,
            }
        end
        if mode == "wb" then
            return {
                write = function(_, value)
                    written_json = value
                    return true
                end,
                close = function() end,
            }
        end
        return nil, "unsupported_test_mode"
    end,
}

local event_bus = require("core/event_bus")
local entitlements = require("systems/player_entitlement_service")
local provider = require("systems/player_profile_providers/local_fixture_provider")
local profile_service = require("systems/player_profile_service")

event_bus.reset()
entitlements.init()
profile_service.init({ provider = provider })
local loaded = profile_service.load_player(0, "isolated_profile_test")
assert(loaded.ok and loaded.pending == false)

local before = profile_service.get_profile(0)
local revision = before.revision
local result = profile_service.apply_incremental({
    schema_version = before.schema_version,
    account_id = before.account_id,
    update_id = "isolated_profile_test:1",
    base_revision = revision,
    revision = revision + 1,
    gameplay_stats_mode = "isolated_test",
    changes = {
        save = {
            gameplay_stats = { hero_attack_armor_reduction = 10 },
        },
    },
})
assert(result.ok)

local after = profile_service.get_profile(0)
assert(after.save.gameplay_stats.hero_attack_armor_reduction == 10)
assert(after.save.gameplay_stats.hero_initial_attack == 0)
assert(after.save.gameplay_stats.hero_basic_attack_growth == 0)
assert(after.save.gameplay_stats.initial_wood == 0)
-- tower_attack_interval is an additive reduction and therefore defaults to 0.
assert(after.save.gameplay_stats.tower_attack_interval == 0)

assert(provider.persist_isolated_gameplay_stat(
    after.account_id,
    "hero_attack_armor_reduction",
    10,
    after.revision
))
assert(type(written_json) == "string"
    and string.find(written_json, '"hero_attack_armor_reduction":10', 1, true))
local reloaded = nil
provider.fetch_snapshot(after.account_id, function(snapshot)
    reloaded = snapshot
end, function(error_code)
    error(error_code)
end)
assert(reloaded.save.gameplay_stats.hero_attack_armor_reduction == 10)
assert(reloaded.save.gameplay_stats.hero_initial_attack == 0)
assert(reloaded.save.gameplay_stats.initial_wood == 0)

local invalid = profile_service.apply_incremental({
    schema_version = before.schema_version,
    account_id = before.account_id,
    update_id = "isolated_profile_test:2",
    base_revision = after.revision,
    revision = after.revision + 1,
    gameplay_stats_mode = "isolated_test",
    changes = {
        save = {
            gameplay_stats = {
                hero_attack_armor_reduction = 10,
                global_attack_armor_reduction = 10,
            },
        },
    },
})
assert(not invalid.ok
    and invalid.error == "isolated_gameplay_stats_requires_one_field")

io = real_io
print("PLAYER_GAMEPLAY_STATS_ISOLATED_PROFILE_PASS")
