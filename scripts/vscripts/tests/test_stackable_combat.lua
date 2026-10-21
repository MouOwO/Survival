package.path='scripts/vscripts/?.lua;'..package.path
local bus=require('core/event_bus');local events=require('core/events')
package.loaded['core/scheduler']={every=function() end}
package.loaded['core/logger']={info=function() end,warn=function() end}
GameRules={GetGameTime=function() return 100 end}
Entities={FindAllByClassname=function() return {} end}
local profiles=require('systems/player_profile_service')
require('systems/player_entitlement_service').init()
profiles.init({provider={init=function() end,resolve_account_id=function(id) return tostring(1000+id) end,
    fetch_snapshot=function() error('offline combat test never fetches') end}})
require('systems/permanent_reward_effect_service').init()
local function near(a,b) assert(math.abs((a or 0)-b)<.0000001,tostring(a)..' expected '..b) end
local function totals() return assert(bus.request(events.PERMANENT_REWARD_EFFECTS_GET_REQUEST,{player_id=0})).totals end
local profile={schema_version=1,account_id='1000',revision=1,entitlements={},achievements={},public={},mode='standard',
    save={permanent_effects={},gameplay_stats={},archive={},content_inventory={welfare_zongzi=20,lottery_ember_of_legacy=2}}}
assert(profiles.apply_snapshot(0,profile,'stackable_first_load').ok)
near(totals().hero_basic_attack_growth,1.2)
local before=totals().hero_attack_flat or 0
bus.emit(events.HERO_MAIN_ATTACK_LANDED,{player_id=0})
near(totals().hero_attack_flat,before+1.2)
profile.revision=2
assert(profiles.apply_snapshot(0,profile,'stackable_repeat_refresh').ok)
near(totals().hero_basic_attack_growth,1.2)
near(totals().hero_attack_flat,before+1.2)
bus.emit(events.HERO_MAIN_ATTACK_LANDED,{player_id=0,is_multishot_secondary=true})
near(totals().hero_attack_flat,before+1.2)
bus.emit(events.HERO_MAIN_ATTACK_LANDED,{player_id=0})
near(totals().hero_attack_flat,before+2.4)
near(profile.save.gameplay_stats.hero_basic_attack_growth,0)
print('PASS stackable combat: both inventories contribute real main-attack growth, refresh does not regrant, multishot remains excluded')
