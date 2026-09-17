package.path="scripts/vscripts/?.lua;"..package.path
local success,failure,sent,applied,completed
local provider={archive_enabled=function()return true end,resolve_account_id=function()return "123" end,
 archive_submit=function(payload,ok,fail)sent=payload;success=ok;failure=fail end}
local apply_result={ok=true}
package.loaded["systems/player_profile_service"]={get_provider=function()return provider end,
 apply_snapshot=function(id,profile,reason)applied={id=id,profile=profile,reason=reason};return apply_result end}
local adapter=require("systems/archive_http_adapter")
assert(adapter.enabled())
local function submit()
 completed=nil;applied=nil
 adapter.submit(0,{id="match:draw:1",kind="social_draw",pool_id="friend"},function(r)completed=r end)
end
submit();assert(sent.account_id=="123" and #sent.config_hash==64 and sent.command.pool_id=="friend")
success({ok=true,profile={account_id="456"}})
assert(not completed.ok and completed.terminal and applied==nil,"cross-account response rejected before apply")
submit();success({ok=true,profile={account_id="123",revision=5}})
assert(completed.ok and applied.reason=="archive_social_draw")
apply_result={ok=false,error="snapshot_revision_stale"}
submit();success({ok=true,profile={account_id="123",revision=4}})
assert(completed.ok,"already superseded committed reply still acknowledges operation")
submit();failure("network",503);assert(not completed.terminal)
submit();failure("busy",429);assert(not completed.terminal)
submit();failure("archive_command_fields_invalid",400);assert(completed.terminal)
print("ARCHIVE_HTTP_ADAPTER_PASS")
