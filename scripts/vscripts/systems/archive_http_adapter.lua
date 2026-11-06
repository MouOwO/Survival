local profiles=require("systems/player_profile_service")
local bundle=require("config/generated/archive_http_bundle")
local ui_context=require("ui/compact_profile_context")
local daily_projection=require("ui/compact_daily_projection")
local lottery_projection=require("ui/compact_lottery_projection")
local M={}
function M.enabled()
    local p=profiles.get_provider()
    return p and p.archive_enabled and p.archive_enabled() or false
end
function M.submit(player_id,command,complete,lottery_hash,committed_profile_only)
    local provider=profiles.get_provider()
    local account=provider and provider.resolve_account_id(player_id)
    if not account then complete({ok=false,error="account_id_unresolved"});return end
    if not provider or type(provider.archive_submit)~='function' then complete({ok=false,terminal=true,error='http_profile_required'});return end
    local config_hash=bundle.hash
    if tostring(command.kind or ''):match('^lottery_') and lottery_hash~=nil then
        if type(lottery_hash)~='string' or #lottery_hash~=64 or lottery_hash:find('[^0-9a-f]') then
            complete({ok=false,terminal=true,error='lottery_config_hash_invalid'});return
        end
        -- This argument is captured by the game-side lottery service from an
        -- authenticated catalog response, never from a Panorama payload.
        config_hash=lottery_hash
    end
    local payload={account_id=account,config_hash=config_hash,command=command}
    -- Internal server-side capability only, separate from the durable command.
    -- Compact lottery consumers use the committed profile and local catalog;
    -- legacy callers still receive optional full snapshots from the backend.
    if command.kind=='lottery_draw'and committed_profile_only==true then
        payload.response_capabilities={lottery_committed_profile_v1=true}
    end
    provider.archive_submit(payload,function(result,timing)
        result.lottery_profile_applied=false
        if result.profile then
            if tostring(result.profile.account_id)~=tostring(account) then
                complete({ok=false,terminal=true,error="account_id_mismatch"});return
            end
            local function apply()
                return ui_context.with(player_id,{source="archive_command",command=command,response=result.response,
                    profile=result.profile.account_profile or result.profile,
                    compact_daily_changes=daily_projection.command_changes(command,result),
                    compact_lottery_changes=lottery_projection.command_changes(command,result)},function()
                    return profiles.apply_snapshot(player_id,result.profile,"archive_"..command.kind)
                end)
            end
            -- Internal provider argument only; never read timing from the HTTP
            -- response. Includes synchronous profile-change subscribers.
            local applied
            if type(timing)=='table'and type(timing.profile)=='function'then applied=timing.profile(apply)
            else applied=apply()end
            if not applied.ok and applied.error~="snapshot_revision_stale" then complete(applied);return end
            -- Local marker, never trusted from HTTP: stale receipts cannot become cache bases.
            result.lottery_profile_applied=applied.ok==true
        end
        complete(result)
    end,function(error,status)
        complete({ok=false,error=error,terminal=status and status>=400 and status<500 and status~=408 and status~=429 or false})
    end)
end
function M.submit_endless_batch(player_id,commands,complete)
    local provider=profiles.get_provider()
    local account=provider and provider.resolve_account_id(player_id)
    if not account then complete({ok=false,error="account_id_unresolved"});return end
    if not provider or type(provider.archive_submit_endless_batch)~="function" then
        complete({ok=false,error="archive_batch_provider_required"});return
    end
    provider.archive_submit_endless_batch({account_id=account,config_hash=bundle.hash,commands=commands},function(result)
        if result.profile then
            if tostring(result.profile.account_id)~=tostring(account) then
                complete({ok=false,error="account_id_mismatch"});return
            end
            local applied=ui_context.with(player_id,{source="archive_batch",commands=commands,
                profile=result.profile.account_profile or result.profile,
                compact_lottery_changes={headers=true},compact_daily_changes={unrelated=true}},function()
                return profiles.apply_snapshot(player_id,result.profile,"archive_endless_batch")
            end)
            if not applied.ok and applied.error~="snapshot_revision_stale" then complete(applied);return end
        end
        complete(result)
    end,function(error,status)
        -- Unsupported deployments preserve intents for retry after the server
        -- capability is enabled; rejection must not discard earned waves.
        complete({ok=false,error=error,terminal=false})
    end)
end
return M
