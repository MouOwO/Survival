-- Real loot tables/reducer: no native game, filesystem writes or account IO.
package.path = "scripts/vscripts/?.lua;" .. package.path
local gear = require("systems/archive_challenge_gear")
local items = require("config/generated/archive_challenge_gear_items")
local odds = require("config/generated/archive_challenge_gear_quality_rules")
local save, stats, checks = {}, {}, 0
local function check(value, message) checks = checks + 1; assert(value, message) end
local function apply(target, item)
    for i, field in ipairs(item.effect_ids) do target[field] = (target[field] or 0) + tonumber(item.effect_values[i]) end
end
local function low(a) return a end
local function grant(wave, variant, session)
    return gear.grant_endless({id = (session or "fixture_match_a") .. ":" .. (variant or "endless") .. ":" .. wave,
        wave = wave, variant = variant}, save, stats, apply, low)
end
for wave = 1, 19 do
    local ok, result = grant(wave)
    check(ok and result.awarded == 0, "early ordinary waves cannot drop equipment")
end
local ok, result = grant(20)
check(ok and result.awarded == 1 and result.quality == "N", "first ordinary milestone grants one real item")
check(save.challenge_gear_counts.archive_gear_n_blade == 1 and stats.hero_initial_attributes == 100, "persist inventory and apply actual stat")
ok, result = grant(20)
check(ok and result.awarded == 0, "same milestone cannot grant twice")
ok, result = grant(21)
check(ok and result.awarded == 0, "a new command in the same interval cannot grant twice")
ok, result = grant(101)
check(ok and result.awarded == 1 and save.challenge_gear_counts.archive_gear_n_blade == 2,
    "one actual clear crossing many skipped thresholds grants one, not all skipped loot")
ok, result = grant(40)
check(ok and result.awarded == 0, "older out-of-order wave cannot reverse the reward cursor")
ok, result = grant(15, "tower")
check(ok and result.awarded == 1, "tower has its own fifteen-floor cadence and cursor")
ok, result = grant(20, "tower")
check(ok and result.awarded == 0, "same tower interval is not a second ordinary milestone")
ok, result = grant(21, nil, "fixture_match_b")
check(ok and result.awarded == 1, "skip step twenty can earn one item on its actual cleared target21")
ok, result = grant(41, nil, "fixture_match_b")
check(ok and result.awarded == 1, "next actual twenty-step clear earns next milestone")
ok, result = grant(120, nil, "fixture_match_a")
check(ok and result.awarded == 1, "late old-match progress retains its independent cursor")
ok, result = grant(42, nil, "fixture_match_b")
check(ok and result.awarded == 0, "interleaved match updates cannot reset one another")
local previous_high = -1
for _, row in ipairs(odds.rows) do
    local total = row.weight_n + row.weight_r + row.weight_sr + row.weight_ssr + row.weight_ur
    local high = (row.weight_ssr + row.weight_ur) / total
    check(total == 10000 and high > previous_high, "higher wave band has greater high-quality probability")
    previous_high = high
    for _, quality in ipairs({"N", "R", "SR", "SSR", "UR"}) do
        local before = ({N=0, R=row.weight_n, SR=row.weight_n+row.weight_r,
            SSR=row.weight_n+row.weight_r+row.weight_sr,
            UR=row.weight_n+row.weight_r+row.weight_sr+row.weight_ssr})[quality]
        local isolated = {}
        local accepted, chosen = gear.grant_endless({id="quality_fixture:endless:" .. math.max(20,row.min_wave),
            wave=math.max(20,row.min_wave)}, isolated, {}, apply,
            function(a, b) return b == 10000 and before + 1 or a end)
        check(accepted and chosen.quality == quality, "each quality boundary selects its own actual catalog")
    end
end
local full, full_stats = {challenge_gear_counts = {}}, {}
for _, item in ipairs(items.rows) do full.challenge_gear_counts[item.item_id] = item.max_owned end
ok, result = gear.grant_endless({id="full_fixture:endless:20",wave=20}, full, full_stats, apply, low)
check(ok and result.collection_full and result.awarded == 0, "full collection completes without a retry deadlock")
check(next(full_stats) == nil, "full collection cannot apply hidden effects")
for _, row in ipairs(gear.rows(save)) do
    check(row.count <= row.target and row.description ~= "", "equipment is inspectable in collection")
end
ok, result = gear.grant_endless({id="invalid_fixture:endless:20",wave=20,variant="fake"}, save, stats, apply, low)
check(not ok and result == "endless_variant_invalid", "unknown variants fail before rewards")
print("ARCHIVE_CHALLENGE_GEAR_PASS: " .. checks .. " checks; real effects, cadence, skip crossings, independent cursors, quality boundaries, full inventory, inspectable rows")
