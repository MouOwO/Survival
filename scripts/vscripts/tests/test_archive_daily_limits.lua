package.path = "scripts/vscripts/?.lua;" .. package.path
local calendar = require("systems/archive_calendar")
calendar.set_clock(function() return 20000 * 86400 end)
local limits = require("systems/archive_daily_limits")
local function equal(actual, expected, message)
    assert(actual == expected, (message or "") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local save = {daily={['20000']={fragment_01=19,cage_total=59,social_ex=9}},
    buildings={faith=100,earned_by_day={['20000']=2900}}}
equal(limits.remaining(save,"fragment_01","20000",false),1,"legacy fragment")
equal(limits.grant(save,"fragment_01",5,"20000",false),1,"partial batch")
equal(limits.grant(save,"fragment_01",1,"20000",false),0,"at cap")
equal(limits.grant(save,"fragment_01",30,"20000",true),0,"pass cannot raise final account cap")
equal(limits.remaining(save,"fragment_01","20000",false),0,"expired entitlement cannot reset quota")
equal(limits.grant(save,"fragment_02",1,"20000",false),1,"fragments independent")
equal(limits.grant(save,"cage",3,"20000",false),1,"cage last slot")
equal(limits.grant(save,"social_ex",3,"20000",false),1,"social last ticket")
equal(limits.grant(save,"faith",400,"20000",false),100,"legacy faith counter")
equal(save.daily['20000'].faith_total,3000,"faith imported into new bucket")
save.buildings.faith=0
equal(limits.remaining(save,"faith","20000",false),0,"spending never releases quota")
equal(limits.grant(save,"shadow",79,"20000",false),79)
equal(limits.grant(save,"shadow",3,"20000",false),1,"shadow last partial batch")
equal(limits.grant(save,"shadow",3,"20001",false),3,"new day resets only new bucket")
equal(limits.remaining(save,"shadow","20000",false),0,"delayed original day preserved")
equal(limits.grant(save,"coins",9000,"20000",false),8000)
equal(limits.grant(save,"endless",49999,"20000",false),49999)
equal(limits.grant(save,"endless",8,"20000",false),1)
equal(limits.grant(save,"mode_rich",1,"20000",false),1)
equal(limits.remaining(save,"mode_cold","20000",false),10,"different mode counters")
equal(limits.challenge_key({reward_kind="shadow"}),"shadow")
equal(limits.challenge_key({reward_kind="cage"}),"cage")
equal(limits.challenge_key({reward_kind="fragment",reward_key="fragment_01"}),"fragment_01")
equal(limits.challenge_key({reward_kind="social_ticket",reward_key="friend"}),"social_friend")
equal(limits.challenge_key({reward_kind="unknown"}),nil)
for _, invalid in ipairs({-1,0.5,math.huge,"bad"}) do
    assert(not pcall(limits.grant,save,"shadow",invalid,"20001",false),"invalid grant must fail")
end
assert(not pcall(limits.grant,save,"missing",1,"20001",false),"unknown quota must fail")
local profile = {save={archive=save,daily_limits={day_key="20000",by_key={fishing={earned=80}}}},entitlements={}}
local snapshot=limits.snapshot(profile,"20000")
equal(snapshot.by_key.fishing.capped,1,"SQL fishing projection")
equal(snapshot.by_key.shadow.remaining,0)
equal(snapshot.by_key.pet.implemented,0,"reserved sources are not invented")
equal(limits.snapshot(profile,"20001").by_key.fishing.earned,0,"stale SQL day is not reused")
profile.entitlements.archive_pass={active=true,expires_at=calendar.now()+60}
equal(limits.snapshot(profile,"20000").by_key.cage.limit,60,"snapshot final cap includes pass entitlement")
equal(limits.snapshot(save,"20000").by_key.shadow.capped,1,"bare archive projection")

local challenge=require("systems/archive_challenge_rewards")
local shadow=require("config/generated/archive_shadow_items")
local stats, applied = {},0
local state={daily={['20000']={shadow_total=79,cage_total=59,fragment_01=19}}}
local function apply() applied=applied+1 end
local shadow_id
for _, row in ipairs(shadow.rows) do if row.enabled and row.source_boss_difficulty=="n1" then shadow_id=row.item_id; break end end
assert(shadow_id)
assert(challenge.apply({challenge_id="shadow_1",day_key="20000",drops={shadow_id,shadow_id}},state,stats,false,apply))
equal(state.shadow_counts[shadow_id],1,"shadow final slot grants one effect")
equal(applied,1)
assert(challenge.apply({challenge_id="shadow_1",day_key="20000",drops={shadow_id}},state,stats,false,apply))
equal(applied,1,"capped shadow does not apply effects")
local cage=require("config/generated/archive_cage_items")
local cage_id
for _,row in ipairs(cage.rows) do if row.enabled and row.pool_id=="cage_1" then cage_id=row.item_id;break end end
assert(challenge.apply({challenge_id="cage_1",day_key="20000",drops={cage_id,cage_id}},state,stats,false,apply))
equal(state.cage_counts[cage_id],1)
equal(state.daily['20000'].cage_total,60)
assert(challenge.apply({challenge_id="hunt_01",day_key="20000"},state,stats,false,apply))
equal(state.fragment_counts.fragment_01,1)
equal(state.daily['20000'].fragment_01,20)
local social=require("systems/archive_social_rewards")
state.daily['20000'].social_friend=9
assert(social.grant_ticket({day_key="20000"},state,"friend",false))
assert(social.grant_ticket({day_key="20000"},state,"friend",false))
equal(state.social_tickets.yitie,1,"capped challenge returns successful empty reward")
local building=require("systems/archive_building_rewards")
local faith={buildings={faith=0,levels={},earned_by_day={['20000']=2900}}}
building.clear(faith,{day_key="20000",count=2})
equal(faith.buildings.faith,100)
equal(faith.buildings.earned_by_day['20000'],3000)
equal(building.info(faith,"20000").daily_cap,3000)
print("ARCHIVE_DAILY_LIMITS_PASS: legacy counters, partial batches, final account caps, spending, dates, mode isolation, SQL projection and challenge effects")
