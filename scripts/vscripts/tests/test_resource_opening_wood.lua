package.path='scripts/vscripts/?.lua;'..package.path
local bus=require('core/event_bus');local events=require('core/events')
local tasks={}
package.loaded['core/scheduler']={cancel=function(k)tasks[k]=nil end,every=function(_,f,k)tasks[k]=f end}
package.loaded['systems/gameplay_phase_guard']={post_clear_frozen=function()return false end}
local stats={initial_wood=10,initial_gold=0,wood_per_second=0}
package.loaded['systems/player_profile_service']={get_profile=function()return {save={gameplay_stats=stats}} end}
PlayerResource={GetTeam=function()return 2 end}
require('systems/resource_system').init()
local function balance()return bus.request(events.RESOURCE_GET_REQUEST,{player_id=0}).wood end
bus.emit(events.PLAYER_PROFILE_CHANGED,{player_id=0})
assert(balance()==10,'base wood must not be added twice')
for i=1,30 do tasks['resource_income:0']() end
assert(balance()==10,'unearned passive income must stay zero')
bus.request(events.RESOURCE_TRY_SPEND_REQUEST,{player_id=0,wood=3})
bus.emit(events.PLAYER_PROFILE_CHANGED,{player_id=0})
assert(balance()==7,'profile refresh must not refill opening resources')
stats.initial_wood=40;stats.wood_per_second=2
bus.emit(events.PLAYER_PROFILE_CHANGED,{player_id=0})
assert(balance()==37,'earned initial resource bonus is applied once')
tasks['resource_income:0']()
assert(balance()==39,'legitimate earned income remains available')
print('OPENING_WOOD_PASS: 10 once, no default income, refresh idempotent, earned bonuses preserved')
