package.path="scripts/vscripts/?.lua;"..package.path
local daily=require("systems/archive_daily_rewards")
local defs=require("config/generated/archive_daily_items")
local lottery=require("config/lottery_config")
local profile={save={archive={daily_rewards={item_counts={daily_growth_gem=1}}}}}
local encoded=require("core/json_encoder").encode(profile)
local rows=daily.points(profile)
assert(#rows==12 and #rows==#defs.rows)
assert(rows[1].id=="daily_growth_gem" and rows[1].count==1)
for i=2,#rows do assert(rows[i].count==0 and rows[i].count_known==1) end
local extra=0;for _,item in ipairs(lottery.items) do if item.item_type=="积分道具" then extra=extra+1 end end
assert(#rows+extra==109)
assert(require("core/json_encoder").encode(profile)==encoded,"read projection mutated save")
assert(#daily.points({save={archive={}}})==12)
print("ARCHIVE_POINTS_CATALOG_PASS: 12 daily + "..extra.." lottery = 109; unowned visible; no save writes")
