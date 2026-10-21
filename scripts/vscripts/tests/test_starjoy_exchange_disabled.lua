package.path='scripts/vscripts/?.lua;'..package.path
local touched=0
package.loaded['systems/player_profile_service']={get_profile=function() touched=touched+1;error('exchange_read_profile') end}
package.loaded['systems/player_gameplay_stats_order_service']={order=function() touched=touched+1;error('exchange_debit') end}
local service=require('systems/lottery_service')
local result=service._test.exchange({player_id=0,pool_id='map',item_id='lottery_attribute_crystal',request_id='closed_local_exchange'})
assert(not result.ok and result.error=='starjoy_exchange_disabled' and touched==0,
 'Local exchange must refuse before reading a wallet, granting an item or changing any saved progression')
print('STARJOY_EXCHANGE_DISABLED_PASS: local exchange refuses without profile, debit, grant or reward mutation')
