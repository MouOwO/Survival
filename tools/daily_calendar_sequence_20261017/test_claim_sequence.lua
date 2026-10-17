-- Exercise the production local/HTTP shared reducer, never write a player save.
package.path = "scripts/vscripts/?.lua;" .. package.path
local daily = require("systems/archive_daily_rewards")
local calendar = require("systems/archive_calendar")
local settlement = require("systems/archive_settlement")
local rules = require("config/generated/archive_daily_rules").by_id.default
local schedule = require("config/generated/archive_daily_schedule")

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}; for key, item in pairs(value) do result[key] = copy(item) end
    return result
end
local function equal(actual, expected, message)
    assert(type(actual) == type(expected), message)
    if type(expected) ~= "table" then assert(actual == expected, message); return end
    for key, value in pairs(expected) do equal(actual[key], value, message) end
    for key in pairs(actual) do assert(expected[key] ~= nil, message) end
end
local clock = 100 * 86400 - 8 * 3600 + 12 * 3600
calendar.set_clock(function() return clock end)
local serial = 0
local function fresh()
    return { save = { archive = {}, gameplay_stats = {} }, entitlements = {} }
end
local function execute(profile, day, target, command_id)
    clock = day * 86400 - 8 * 3600 + 12 * 3600
    serial = serial + 1
    local command = { id = command_id or "sequence:test:" .. serial,
        kind = target and "daily_claim" or "daily_init", today = calendar.day(), target_day = target }
    local result = settlement.settle(profile, command, calendar.has_pass(profile))
    if result.ok then
        profile.save.archive, profile.save.gameplay_stats = result.archive, result.gameplay_stats
    end
    return result
end
local function snapshot(profile, day)
    clock = day * 86400 - 8 * 3600 + 12 * 3600
    return daily.snapshot(profile, calendar.day(), calendar.has_pass(profile))
end
local function assert_position(profile, day, ordinal, count)
    local before = copy(profile)
    local view = snapshot(profile, day)
    assert(view.count == count and view.cycle_mode == "claim_count")
    assert(view.current_day == (ordinal - 1) % 7 + 1)
    assert(view.calendar28[view.calendar_current_day].absolute_count == ordinal)
    assert(view.calendar28[view.calendar_current_day].status == "claimable")
    equal(profile, before, "Snapshot must not advance saved rewards")
    return view
end

-- Missing a real date does not skip the next ordinary reward.
local ordinary = fresh()
assert(execute(ordinary, 100).ok)
assert(execute(ordinary, 100, 100).ok)
local gap = assert_position(ordinary, 102, 2, 1)
assert(#gap.missed == 1 and gap.missed[1] == 101 and gap.has_pass == 0)
local unchanged = copy(ordinary)
local denied = execute(ordinary, 102, 101)
assert(not denied.ok and denied.error:find("月卡", 1, true))
equal(ordinary, unchanged, "A non-pass makeup cannot grant effects or advance progress")
assert(execute(ordinary, 102, 102, "sequence:ordinary:102").ok)
assert(ordinary.save.archive.daily_rewards.count == 2)
assert(ordinary.save.archive.daily_rewards.item_counts.daily_growth_gem == 3)
assert(ordinary.save.archive.daily_rewards.item_counts.daily_regen_shard == 3)
assert(not ordinary.save.archive.daily_rewards.item_counts.daily_attribute_gem,
    "A gap must not jump from reward I to reward III")
local claimed = copy(ordinary)
assert(execute(ordinary, 102, 102, "sequence:ordinary:102").duplicate)
equal(ordinary, claimed, "Retried operation must not award twice")
assert(not execute(ordinary, 102, 102, "sequence:other:102").ok)
equal(ordinary, claimed, "A new operation cannot claim the same date twice")
assert_position(ordinary, 110, 3, 2)
assert(execute(ordinary, 110, 110).ok)
assert(ordinary.save.archive.daily_rewards.item_counts.daily_attribute_gem == 3)

-- An active monthly pass allows the missed date plus the real current date.
local monthly = fresh()
assert(execute(monthly, 100).ok)
assert(execute(monthly, 100, 100).ok)
monthly.entitlements.archive_pass = { active = true, expires_at = 150 * 86400 }
assert(execute(monthly, 102, 101).ok)
local after_makeup = assert_position(monthly, 102, 3, 2)
assert(after_makeup.has_pass == 1 and #after_makeup.missed == 0)
assert(execute(monthly, 102, 102).ok)
assert(monthly.save.archive.daily_rewards.count == 3)
assert(monthly.save.archive.daily_rewards.item_counts.daily_regen_shard == 3)
assert(monthly.save.archive.daily_rewards.item_counts.daily_attribute_gem == 3)
local monthly_claimed = copy(monthly)
assert(not execute(monthly, 102, 101).ok)
equal(monthly, monthly_claimed, "Monthly makeup also deduplicates the original date")

-- The server entitlement must still be active and unexpired at settlement.
for _, entitlement in ipairs({ { active = false }, { active = true, expires_at = clock - 1 } }) do
    local expired = fresh(); assert(execute(expired, 100).ok)
    expired.entitlements.archive_pass = entitlement
    local before = copy(expired)
    assert(not execute(expired, 102, 101).ok)
    equal(expired, before, "Inactive/expired monthly entitlement cannot makeup")
end

-- The configured 30-day window is inclusive, and never includes a future date.
local window = fresh(); assert(execute(window, 100).ok)
window.entitlements.archive_pass = { active = true }
assert(not execute(window, 140, 140 - rules.makeup_days).ok)
assert(execute(window, 140, 140 - rules.makeup_days + 1).ok)
assert(not execute(window, 140, 141).ok)
assert(not execute(window, 140, 99).ok)

-- Seven ordinary claims still form the configured cycle across repeated gaps.
local loop = fresh(); assert(execute(loop, 100).ok)
for ordinal = 1, 9 do
    local day = 100 + (ordinal - 1) * 2
    assert_position(loop, day, ordinal, ordinal - 1)
    assert(execute(loop, day, day).ok)
end
local counts = loop.save.archive.daily_rewards.item_counts
assert(counts.daily_growth_gem == 6 and counts.daily_regen_shard == 6)
assert(counts.daily_attribute_gem == 3 and counts.daily_gold_gem == 3)
for _, id in ipairs(rules.pass_item_ids) do assert(counts[id] == nil) end

calendar.set_clock(nil)
print("DAILY_SEQUENCE_PASS: ordinary gaps retain the next reward; monthly-only makeup; authoritative expiry; duplicate safety; configured window; seven-claim rollover")
