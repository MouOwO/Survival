local profiles=require("systems/player_profile_service")
local bundle=require("config/generated/archive_http_bundle")
local M={}
function M.enabled()
    local p=profiles.get_provider()
    return p and p.archive_enabled and p.archive_enabled() or false
end
function M.submit(player_id,command,complete)
    local provider=profiles.get_provider()
    local account=provider and provider.resolve_account_id(player_id)
    if not account then complete({ok=false,error="account_id_unresolved"});return end
    provider.archive_submit({account_id=account,config_hash=bundle.hash,command=command},function(result)
        if result.profile then
            if tostring(result.profile.account_id)~=tostring(account) then
                complete({ok=false,terminal=true,error="account_id_mismatch"});return
            end
            local applied=profiles.apply_snapshot(player_id,result.profile,"archive_"..command.kind)
            if not applied.ok and applied.error~="snapshot_revision_stale" then complete(applied);return end
        end
        complete(result)
    end,function(error,status)
        complete({ok=false,error=error,terminal=status and status>=400 and status<500 and status~=408 and status~=429 or false})
    end)
end
return M
