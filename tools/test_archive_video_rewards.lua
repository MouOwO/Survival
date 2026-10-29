package.path = "./scripts/vscripts/?.lua;./scripts/vscripts/?/init.lua;" .. package.path
local eligibility = require("systems/archive_challenge_reward_eligibility")
local rewards = require("systems/archive_challenge_rewards")
local social = require("systems/archive_social_rewards")
local settlement = require("systems/archive_settlement")
local challenges = require("config/generated/archive_challenge_definitions")
local fragments = require("config/generated/archive_fragment_definitions")
local levels = require("config/generated/archive_fragment_levels")
local cage = require("config/generated/archive_cage_items")
local quota = require("systems/archive_daily_limits")
local checks = 0
local function eq(actual, expected, note)
    checks = checks + 1
    assert(actual == expected, (note or "check") .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end
local function apply(stats, row)
    for index, field in ipairs(row.effect_ids or {}) do
        stats[field] = (stats[field] or 0) + assert(tonumber(row.effect_values[index]))
    end
end
local function command(id, day)
    return {challenge_id=id, day_key=day or "2026-10-29"}
end
local function run(id, save, pass)
    local ok, result = rewards.apply(command(id), save, {}, pass == true, apply, function(a) return a end)
    eq(ok, true, id)
    return result
end
local function prerequisite(pool)
    return {reward_requirement_pool=pool, reward_requirement_count=100}
end

local missing, message = eligibility.check(nil, prerequisite("beast"))
eq(missing, false); eq(message, "存档尚未就绪")
for _, pool in ipairs({"beast", "ex", "friend"}) do
    eq(eligibility.check({social_draw_counts={[pool]=100}}, prerequisite(pool)), false, "strict 100")
    eq(eligibility.check({social_draw_counts={[pool]=101}}, prerequisite(pool)), true, "strict 101")
end
eq(eligibility.check({social_tickets={blessing_ticket=999999}, social_unlocks={ex_100=true}}, prerequisite("beast")), false,
    "balance and old boolean are not draw history")
eq(eligibility.total_draws({social_counts={beast_01=60,beast_02=41},social_tickets={blessing_ticket=0}}, "beast"), 101)
eq(eligibility.check({social_counts={beast_01=60,beast_02=40}}, prerequisite("beast")), false)

local archive = {social_counts={beast_01=60,beast_02=40}, social_tickets={blessing_ticket=1}}
local ok = social.apply({kind="social_draw", pool_id="beast", roll=0, id="draw101"}, archive, {}, apply)
eq(ok, true); eq(archive.social_draw_counts.beast, 101, "migrate then increment once")
eq(archive.social_tickets.blessing_ticket, 0)
eq(eligibility.check(archive, prerequisite("beast")), true)
local blocked = run("social_ex", {})
eq(blocked.awarded, 0); eq(type(blocked.skipped_reason), "string")
local eligible = run("social_ex", archive)
eq(eligible.awarded, 1); eq(archive.social_tickets.invitation, 1)

archive = {social_draw_counts={friend=101}}
for index=1,10 do
    local result = run("social_concubine", archive, true)
    eq(result.awarded, 1, "salary is one even with pass")
end
local capped = run("social_concubine", archive, true)
eq(capped.awarded, 0); eq(archive.social_tickets.salary, 10)
eq(archive.daily["2026-10-29"].salary_total, 10)
ok = social.apply({kind="social_draw",pool_id="concubine",roll=0,id="salarydraw"}, archive, {}, apply)
eq(ok, true); eq(archive.social_tickets.salary, 9)
eq(archive.social_draw_counts.concubine, 1)
eq(archive.social_counts.concubine_01, 1)

archive = {}
for index=1,10 do eq(run("football", archive).awarded, 10) end
eq(run("football", archive).awarded, 0)
eq(archive.challenge_points.football, 100)
eq(quota.earned(archive, "football", "2026-10-29"), 100)
for index=1,10 do eq(run("watermelon", archive).awarded, 1) end
eq(run("watermelon", archive).awarded, 0)
eq(archive.challenge_points.watermelon, 10)
eq(quota.earned(archive, "watermelon", "2026-10-29"), 10)
local point_rows = rewards.point_rows(archive)
eq(point_rows[1].count,100); eq(point_rows[2].count,10)
local fresh_ok, fresh = rewards.apply(command("football","2026-10-30"),archive,{},false,apply)
eq(fresh_ok,true); eq(fresh.awarded,10); eq(archive.challenge_points.football,110)

archive = {}
for index=13,16 do
    local result = run(string.format("hunt_%02d",index),archive)
    eq(result.awarded,1)
    local key = string.format("fragment_%02d", index)
    eq(archive.fragment_counts[key],1)
    eq(fragments.by_id[key].max_level,18)
    local count = 0
    for _,row in ipairs(levels.rows) do if row.fragment_id==key then count=count+1 end end
    eq(count,18)
end
for pool=7,9 do
    local count = 0
    for _,item in ipairs(cage.rows) do
        if item.pool_id=="cage_"..pool then
            count=count+1; eq(item.evidence_origin,"project_authored_20261029")
        end
    end
    eq(count,9)
    local result = run("cage_"..pool,archive)
    assert(result.awarded>0)
end
eq(challenges.by_id.pet,nil,"user excluded palu")
eq(quota.definition("pet").implemented,false,"unrelated historic reserved quota stays reserved")

local profile={save={archive={social_counts={beast_01=60,beast_02=40},social_tickets={blessing_ticket=1}},gameplay_stats={}}}
local draw = {kind="social_draw",id="dedup101",pool_id="beast",roll=0}
local first=settlement.settle(profile,draw,false)
eq(first.ok,true); eq(first.archive.social_draw_counts.beast,101)
local second=settlement.settle({save={archive=first.archive,gameplay_stats=first.gameplay_stats}},draw,false)
eq(second.ok,true); eq(second.duplicate,true); eq(second.archive.social_draw_counts.beast,101)
print("ARCHIVE_VIDEO_REWARDS_PASS " .. checks .. " checks")
