package.path='scripts/vscripts/?.lua;'..package.path
local items=require('systems/archive_stackable_items')
local function near(actual,expected) assert(math.abs((actual or 0)-expected)<.0000001,tostring(actual)..' expected '..expected) end
local function projection(id,count)
    return items.project({content_inventory={[id]=count}})
end
local ember='lottery_ember_of_legacy';local zongzi='welfare_zongzi'
local checks={
    {zongzi,10,'hero_attributes_per_second',0,100},
    {zongzi,20,'hero_attribute_growth',0,1},
    {zongzi,30,'lumberjack_efficiency',0,1},
    {zongzi,40,'hero_attack_bonus_pct',0,3},
    {zongzi,50,'hero_attribute_bonus_pct',0,3},
    {zongzi,60,'hero_attack_armor_reduction',0,2},
    {zongzi,70,'hero_attribute_growth',1,2},
    {zongzi,80,'hero_final_damage_bonus_pct',0,2},
    {zongzi,90,'hero_attack_armor_reduction',2,3},
    {zongzi,100,'hero_attribute_growth',2,3},
    {ember,10,'hero_attributes_per_second',0,100},
    {ember,50,'hero_attribute_growth',0,100},
    {ember,100,'hero_final_damage_bonus_pct',0,10},
    {ember,200,'hero_attack_bonus_pct',0,30},
    {ember,300,'hero_attribute_bonus_pct',0,30},
    {ember,400,'hero_attack_armor_reduction',0,30},
    {ember,600,'hero_attribute_growth',100,40},
    {ember,800,'hero_final_damage_bonus_pct',10,120},
    {ember,1000,'hero_attack_armor_reduction',30,50},
    {ember,1500,'hero_attribute_growth',40,60},
}
for _,c in ipairs(checks) do
    near(projection(c[1],c[2])[c[3]],c[4])
    near(projection(c[1],c[2]+1)[c[3]],c[5])
end
near(projection(ember,1).hero_basic_attack_growth,.1)
near(projection(ember,2).hero_basic_attack_growth,.2)
near(projection(zongzi,150).hero_basic_attack_growth,7.5)
near(projection(zongzi,999).hero_basic_attack_growth,7.5)
local both=items.project({content_inventory={[zongzi]=150,[ember]=1501}})
near(both.hero_attribute_growth,63);near(both.hero_attack_armor_reduction,53)
near(both.hero_attributes_per_second,200);near(both.hero_basic_attack_growth,157.6)
local save={content_inventory={[zongzi]=149,lottery_ticket=13}}
local archive={commerce={balances={shop_points=19}}};local stats={hero_basic_attack_growth=42}
local accepted,overflow=items.grant(save,archive,stats,zongzi,5)
assert(accepted==1 and overflow==4 and save.content_inventory[zongzi]==150)
assert(save.content_inventory.lottery_ticket==13 and archive.commerce.balances.shop_points==19)
accepted,overflow=items.grant(save,archive,stats,zongzi,2)
assert(accepted==0 and overflow==2 and stats.hero_basic_attack_growth==42)
accepted,overflow=items.grant(save,archive,stats,ember,200000001)
assert(accepted==200000001 and overflow==0,'No former 100-million gameplay cap')
assert(stats.hero_basic_attack_growth==42,'Inventory-derived effects must not rewrite permanent stats')
local fresh={content_inventory={},archive={},gameplay_stats={hero_basic_attack_growth=0}}
items.grant(fresh,fresh.archive,fresh.gameplay_stats,ember,1)
near(items.project(fresh).hero_basic_attack_growth,.1)
items.grant(fresh,fresh.archive,fresh.gameplay_stats,ember,1)
near(items.project(fresh).hero_basic_attack_growth,.2)
for _=1,20 do near(items.project(fresh).hero_basic_attack_growth,.2) end
assert(fresh.gameplay_stats.hero_basic_attack_growth==0)
local legacy={content_inventory={[ember]=1},archive={},gameplay_stats={hero_basic_attack_growth=10},
    lottery_applied_item_effects={[ember]=true}}
near(items.project(legacy).hero_basic_attack_growth,0)
items.grant(legacy,legacy.archive,legacy.gameplay_stats,ember,1)
near(items.project(legacy).hero_basic_attack_growth,.1)
assert(legacy.gameplay_stats.hero_basic_attack_growth==10 and legacy.archive.stackable_items.legacy_ember_growth==.1)
local unproven={content_inventory={[ember]=1},archive={},gameplay_stats={hero_basic_attack_growth=10}}
near(items.project(unproven).hero_basic_attack_growth,.1)
assert(unproven.gameplay_stats.hero_basic_attack_growth==10 and unproven.archive.stackable_items==nil)
for _,value in ipairs({-1,.1,math.huge,9007199254740992}) do
    assert(not pcall(items.grant,{content_inventory={}}, {}, {},zongzi,value))
end
print('PASS stackable items: 20 strict thresholds, highest-tier replacement, per-copy growth, 150 cap and partial grants, unlimited ember, legacy receipt offset, read purity')

-- Real lottery reducer keeps every ember and never credits duplicate points.
local config=require('config/lottery_config')
local pool=config.pools.map;local item=config.by_id[ember]
pool.quality_weights={n=0,r=0,sr=0,ssr=0,ur=10000}
pool.by_quality={ur={item}};item.item_weight=1
RandomInt=function(a) return a end
local lottery=require('systems/lottery_http_settlement')
local profile={save={content_inventory={lottery_ticket=10,[ember]=3,lottery_nature_crystal=2},
    archive={commerce={balances={shop_points=7}}},gameplay_stats={}}}
local result=lottery.settle(profile,{kind='lottery_draw',pool_id='map',count=1,request_id='stackable_draw'})
assert(result.ok and result.content_inventory[ember]==4)
assert(result.archive.commerce.balances.shop_points==12,'Only the other unique duplicate converts at its configured rate')
assert(result.content_inventory.lottery_nature_crystal==1)
assert(not result.response.results[1].duplicate and result.response.results[1].converted_points==0)
assert(result.gameplay_stats.hero_basic_attack_growth==nil)
local snapshot=lottery.snapshots({save={content_inventory={[ember]=1600},archive={},gameplay_stats={}}})
for _,s in ipairs(snapshot) do for _,r in ipairs(s.items) do if r.id==ember then
    assert(r.owned_count==1600 and r.max_owned==0 and r.at_max_owned==false)
end end end
print('PASS lottery stackable: draw adds a copy, no conversion, other unique goods preserved, unlimited public count')
