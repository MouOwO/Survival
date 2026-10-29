-- Authenticated server transport. Balances and rewards never originate in Panorama.
local profiles=require('systems/player_profile_service')
local adapter=require('systems/archive_http_adapter')
local bundle=require('config/generated/archive_http_bundle')
local scheduler=require('core/scheduler')
local M={}
local busy,last={},{}
local initialized=false
local function send(id,result)
    local player=PlayerResource:GetPlayer(id)
    if player then CustomGameEventManager:Send_ServerToPlayer(player,'survival_commerce_result',result) end
end
function M.handle(payload)
    local id=tonumber(payload.PlayerID)
    if not id or not PlayerResource:IsValidPlayerID(id) or PlayerResource:IsFakeClient(id) then return end
    local action=payload.action;local token=payload.request_id
    if action~='catalog' and action~='purchase' and action~='redeem' then return end
    if type(token)~='string' or #token<8 or #token>96 or token:find('[^%w_.-]') then return end
    local function reply(result)
        result.request_id=token;result.action=action;send(id,result)
    end
    if busy[id] or Time()-(last[id] or -10)<1 then reply({ok=false,terminal=false,error='commerce_busy'});return end
    local provider=profiles.get_provider();local account=provider and provider.resolve_account_id(id)
    if not account or not profiles.get_profile(id) or not adapter.enabled() then
        reply({ok=false,terminal=true,error='profile_not_ready'});return
    end
    local setup=require('systems/match_setup_service');local session=setup.get_session_id()
    local function same_player()
        local account_ok,current_account=pcall(provider.resolve_account_id,id)
        local session_ok,current_session=pcall(setup.get_session_id)
        return account_ok and session_ok and current_account==account and current_session==session
    end
    local command={id='commerce:'..token,kind='commerce_'..action}
    if action=='redeem' then
        if type(payload.code)~='string' or #payload.code<6 or #payload.code>80 then
            reply({ok=false,terminal=true,error='redeem_code_invalid'});return
        end
        command={id='redeem:'..token,kind='redemption_redeem',code=payload.code,request_id=token}
    end
    if action=='purchase' then
        if type(payload.sku)~='string' or #payload.sku>64 or not payload.sku:match('^[a-z][a-z0-9_]+$') then
            reply({ok=false,terminal=true,error='product_unavailable'});return
        end
        command.sku=payload.sku;command.request_id=token
    end
    local job={};busy[id]=job;last[id]=Time()
    local attempts=0
    local timeout_key,retry_key='commerce_transport_'..id,'commerce_retry_'..id
    local function finish(result)
        if busy[id]~=job then return end
        busy[id]=nil
        scheduler.cancel(timeout_key);scheduler.cancel(retry_key)
        if not same_player() then return end
        if action=='catalog' and result.ok then
            -- Bounded packets; swap the client catalog only after every row arrives.
            reply({ok=true,part='begin',count=#(result.products or {}),balances=result.balances,categories=result.categories})
            for i,p in ipairs(result.products or {}) do reply({ok=true,part='product',index=i,product=p}) end
            reply({ok=true,part='end'})
        else
            local response=result.response or {}
            reply({ok=result.ok==true,terminal=result.terminal==true or result.done==true,
                sku=command.sku,error=result.error,title=response.title,price=response.price,
                currency=response.currency,balance=response.balance,granted=response.granted,skipped=response.skipped})
        end
    end
    local function attempt()
        if busy[id]~=job then return end
        if not same_player() then finish({ok=false,error='profile_not_ready'});return end
        attempts=attempts+1
        local completed=false
        local function settled(result)
            if completed or busy[id]~=job then return end
            completed=true;scheduler.cancel(timeout_key)
            if not same_player() then finish({ok=false,error='profile_not_ready'});return end
            if type(result)~='table' then result={ok=false,error='commerce_busy'} end
            if action~='catalog' and not result.ok and not result.terminal and attempts<3 then
                scheduler.after(1,attempt,retry_key)
            else finish(result) end
        end
        -- Each provider attempt already has a 30s HTTP limit. Bound missing
        -- callbacks without cutting short the existing same-ID recovery tries.
        scheduler.after(32,function() settled({ok=false,terminal=false,error='commerce_busy'}) end,timeout_key)
        local called,submitted=pcall(function()
            if action=='catalog' then
                return provider.archive_submit({account_id=account,config_hash=bundle.hash,command=command},settled,
                    function(error) settled({ok=false,error=error}) end)
            end
            return adapter.submit(id,command,settled)
        end)
        if not called or submitted==false then settled({ok=false,terminal=false,error='commerce_busy'}) end
    end
    attempt()
end
function M.init()
    if initialized then return end;initialized=true
    require('systems/commerce_runtime').init()
    require('systems/commerce_titan_aura_service').init()
    CustomGameEventManager:RegisterListener('survival_commerce_request',function(_,payload) M.handle(payload or {}) end)
end
return M
