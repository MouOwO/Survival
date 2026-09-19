package.path = "scripts/vscripts/?.lua;" .. package.path
local settle = require("systems/archive_settlement").settle
local buildings = require("systems/archive_building_rewards")
local p = {save={archive={},gameplay_stats={}}}
local function command(c, pass)
    local r = settle(p,c,pass)
    if r.ok then p.save.archive=r.archive; p.save.gameplay_stats=r.gameplay_stats end
    return r
end
for n=1,12 do assert(command({id="clear"..n,kind="clear",difficulty_id="n1",count=1,day_key="1"},true).ok) end
assert(buildings.info(p.save.archive,1).faith==4000, "daily cap, no pass bonus")
local buy={id="buy1",kind="building_upgrade",item_id="building_01",expected_level=0}
assert(command(buy).ok)
assert(p.save.archive.buildings.faith==1000)
assert(p.save.gameplay_stats.technology_wood_cost_refund_pct==5)
assert(command(buy).duplicate)
assert(not command({id="stale",kind="building_upgrade",item_id="building_01",expected_level=0}).ok)
assert(not command({id="poor",kind="building_upgrade",item_id="building_01",expected_level=1}).ok)
assert(command({id="clear13",kind="clear",difficulty_id="n1",count=1,day_key="1"}).ok)
assert(p.save.archive.buildings.faith==1000, "spending does not reset daily allowance")
assert(command({id="tomorrow",kind="clear",difficulty_id="n1",count=10,day_key="2"}).ok)
assert(p.save.archive.buildings.faith==5000, "balance accumulates across days")
assert(command({id="late",kind="clear",difficulty_id="n1",count=1,day_key="1"}).ok)
assert(p.save.archive.buildings.faith==5000, "late operation cannot reset day cap")
p.save.archive.buildings.faith=134000
for _,item in ipairs(require("config/generated/archive_building_items").rows) do
    for level=p.save.archive.buildings.levels[item.item_id] or 0,4 do
        assert(command({id=item.item_id..level,kind="building_upgrade",item_id=item.item_id,expected_level=level}).ok)
    end
    assert(not command({id=item.item_id.."max",kind="building_upgrade",item_id=item.item_id,expected_level=5}).ok)
end
assert(p.save.archive.buildings.faith==2000)
assert(p.save.gameplay_stats.technology_wood_cost_refund_pct==25)
assert(p.save.gameplay_stats.technology_gold_cost_refund_pct==25)
assert(p.save.gameplay_stats.wall_wave_boss_stun_seconds==10)
assert(p.save.gameplay_stats.hero_attack_pct_per_minute==5)
assert(p.save.gameplay_stats.hero_attributes_pct_per_minute==10)
local cost=require("research/research_cost_service").discount({wood=1000,gold=400},p.save.gameplay_stats)
assert(cost.wood==750 and cost.gold==300, "building technology effects reduce actual costs")
print("ARCHIVE_BUILDINGS_PASS")
