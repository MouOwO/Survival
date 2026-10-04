package.path='scripts/vscripts/?.lua;'..package.path
package.loaded['systems/player_context_service']={}
package.loaded['core/scheduler']={}
local owned=true
package.loaded['systems/commerce_effects']={owned=function()return owned end}
local defs={rows={
    {reward_id='ordinary',rarity='C',weight=80,effect_key='immediate_wood',value_min=1},
    {reward_id='rare_s',rarity='S',weight=10,effect_key='immediate_wood',value_min=1},
    {reward_id='rare_ur',rarity='UR',weight=10,effect_key='immediate_wood',value_min=1},
},by_id={}}
package.loaded['config/generated/fishing_reward_definitions']=defs
local bus=require('core/event_bus');local events=require('core/events')
bus.handle_request(events.RESOURCE_ADD_REQUEST,function()return {ok=true}end)
PlayerResource={GetTeam=function()return 2 end,GetPlayer=function()return nil end}
local rolls={}
RandomFloat=function(min,max) local n=table.remove(rolls,1);assert(n and n>=min and n<=max);return n end
local fishing=require('systems/fishing_service')
rolls={.399,19};assert(fishing.grant(0,'random').reward_id=='rare_ur','UR participates in the doubled group')
rolls={.401,1};assert(fishing.grant(0,'random').reward_id=='ordinary','rare total rises from 20% to 40%, not a normalized 33%')
owned=false;rolls={81};assert(fishing.grant(0,'random').reward_id=='rare_s')
owned=true;defs.rows[1].weight=0;rolls={20};assert(fishing.grant(0,'random').reward_id=='rare_ur','100% cap cannot choose empty ordinary group')
print('COMMERCE_FISHING_PASS: exact group probability, UR, non-owner distribution and 100% cap')
