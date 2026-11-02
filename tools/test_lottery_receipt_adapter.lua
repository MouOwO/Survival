package.path='scripts/vscripts/?.lua;'..package.path
local response,applied,callback
package.loaded['systems/player_profile_service']={get_provider=function()return {
    resolve_account_id=function()return 'synthetic' end,
    archive_submit=function(_,done)done(response)end,
}end,apply_snapshot=function()return applied end}
package.loaded['config/generated/archive_http_bundle']={hash=string.rep('a',64)}
local adapter=require('systems/archive_http_adapter')
local function submit()
    callback=nil;adapter.submit(0,{kind='lottery_draw'},function(value)callback=value end)
    assert(callback);return callback
end
response={ok=true,lottery_profile_applied=true};assert(submit().lottery_profile_applied==false)
response={ok=true,profile={account_id='synthetic',revision=2}};applied={ok=true}
assert(submit().lottery_profile_applied==true)
applied={ok=false,error='snapshot_revision_stale'};assert(submit().lottery_profile_applied==false)
response={ok=true,profile={account_id='another'}};assert(submit().error=='account_id_mismatch')
print('LOTTERY_RECEIPT_ADAPTER_PASS: forged marker reset; fresh, stale and foreign profile guards')
