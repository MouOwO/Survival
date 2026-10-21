package.path='scripts/vscripts/?.lua;'..package.path
local items=require('systems/archive_stackable_items')
local save={stackable_projection_applied=true,content_inventory={lottery_ember_of_legacy=1,welfare_zongzi=2},
    gameplay_stats={hero_basic_attack_growth=.2,hero_attribute_growth=100},
    archive={stackable_items={legacy_ember_growth=.1}}}
assert(next(items.project(save))==nil,'Pure signed account deltas were already applied to stats by the trusted backend')
save.stackable_projection_applied=false
local result=items.project(save)
assert(math.abs(result.hero_basic_attack_growth-.1)<.0000001,'Standard views continue deriving full inventory effects')
assert(result.hero_attribute_growth==nil)
print('PASS pure stackable flag: trusted projected stats are not derived twice; standard full inventory remains active')
