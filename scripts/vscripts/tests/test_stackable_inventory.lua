package.path='scripts/vscripts/?.lua;'..package.path
local bus=require('core/event_bus');local events=require('core/events')
package.loaded['core/scheduler']={every=function() end}
package.loaded['core/logger']={info=function() end,warn=function() end}
PlayerResource={IsValidPlayerID=function(_,id) return id==0 end,GetTeam=function() return 2 end}
local profiles=require('systems/player_profile_service')
require('systems/player_entitlement_service').init()
profiles.init({provider={init=function() end,resolve_account_id=function() return '1000' end,
    fetch_snapshot=function() error('offline inventory test never fetches') end}})
require('systems/content_inventory_service').init()
local profile={schema_version=1,account_id='1000',revision=1,entitlements={},achievements={},public={},mode='standard',
    save={permanent_effects={},gameplay_stats={},archive={keep=true},content_inventory={welfare_zongzi=149}}}
assert(profiles.apply_snapshot(0,profile,'stackable_inventory_load').ok)
local out=assert(bus.request(events.CONTENT_INVENTORY_GRANT_REQUEST,{player_id=0,content_id='welfare_zongzi',count=5,
    effect_marker_id='must_not_apply',gameplay_stat_effects={{field_id='hero_basic_attack_growth',value=999}}}))
assert(out.ok and out.granted_count==1 and out.overflow_count==4)
local saved=profiles.get_profile(0).save
assert(saved.content_inventory.welfare_zongzi==150 and saved.archive.keep==true)
assert(saved.gameplay_stats.hero_basic_attack_growth==0,'Stackables ignore static grant effects')
out=bus.request(events.CONTENT_INVENTORY_TRANSACTION_REQUEST,{player_id=0,grant={welfare_zongzi=9,lottery_ember_of_legacy=7}})
assert(out.ok and out.snapshot.counts.welfare_zongzi==150 and out.snapshot.counts.lottery_ember_of_legacy==7)
assert(out.changes.welfare_zongzi==0 and out.changes.lottery_ember_of_legacy==7)
assert(profiles.get_profile(0).save.archive.stackable_items.legacy_ember_growth==0)
print('PASS local stackable inventory: capped partial grants, atomic mixed reward transaction, no permanent stat reapplication')
