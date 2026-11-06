package.path='scripts/vscripts/?.lua;'..package.path
local response,applied,callback,sent_payload
package.loaded['systems/player_profile_service']={get_provider=function()return {
    resolve_account_id=function()return 'synthetic' end,
    archive_submit=function(payload,done)sent_payload=payload;done(response)end,
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
assert(sent_payload.response_capabilities==nil,'legacy must keep full response')
local command={kind='lottery_draw'}
adapter.submit(0,command,function()end,nil,true)
assert(sent_payload.response_capabilities.lottery_committed_profile_v1==true)
assert(sent_payload.command==command and command.response_capabilities==nil,'capability must not alter durable command')
for _,invalid in ipairs({false,1,'true'})do
 adapter.submit(0,command,function()end,nil,invalid)
 assert(sent_payload.response_capabilities==nil,'capability requires strict boolean true')
end
adapter.submit(0,{kind='lottery_read'},function()end,nil,true)
assert(sent_payload.response_capabilities==nil,'read must not negotiate a draw capability')
applied={ok=false,error='snapshot_revision_stale'};assert(submit().lottery_profile_applied==false)
response={ok=true,profile={account_id='another'}};assert(submit().error=='account_id_mismatch')
print('LOTTERY_RECEIPT_ADAPTER_PASS: forged marker reset; fresh, stale and foreign profile guards')
