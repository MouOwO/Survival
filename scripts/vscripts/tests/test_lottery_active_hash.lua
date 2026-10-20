package.path='scripts/vscripts/?.lua;'..package.path
local calls={}
package.loaded['config/generated/archive_http_bundle']={hash='immutable-other-systems'}
package.loaded['systems/player_profile_service']={get_provider=function()return {
    resolve_account_id=function()return '123' end,
    archive_submit=function(payload,done)calls[#calls+1]=payload;done({ok=true})end,
}end}
local adapter=require('systems/archive_http_adapter')
local result
adapter.submit(0,{kind='lottery_draw'},function(value)result=value end,string.rep('a',64))
assert(result.ok and calls[1].config_hash==string.rep('a',64))
adapter.submit(0,{kind='lottery_read'},function(value)result=value end,'from_ui')
assert(not result.ok and result.error=='lottery_config_hash_invalid' and #calls==1)
adapter.submit(0,{kind='challenge'},function(value)result=value end,string.rep('b',64))
assert(result.ok and calls[2].config_hash=='immutable-other-systems','lottery updates cannot change another subsystem reducer')
print('LOTTERY_ACTIVE_HASH_PASS: validated-trusted-lottery-hash/unchanged-other-commands')
