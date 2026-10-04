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
    if action~='catalog' and action~='purchase' then return end
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
    local function same_player() return provider.resolve_account_id(id)==account and setup.get_session_id()==session end
    local command={id='commerce:'..token,kind='commerce_'..action}
    if action=='purchase' then
        if type(payload.sku)~='string' or #payload.sku>64 or not payload.sku:match('^[a-z][a-z0-9_]+$') then
            reply({ok=false,terminal=true,error='product_unavailable'});return
        end
        command.sku=payload.sku;command.request_id=token
    end
    local job={};busy[id]=job;last[id]=Time()
    local attempts=0
    local function finish(result)
        if busy[id]~=job then return end
        busy[id]=nil
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
                currency=response.currency,balance=response.balance})
        end
    end
    local function attempt()
        if not same_player() then busy[id]=nil;return end
        attempts=attempts+1
        if action=='catalog' then
            provider.archive_submit({account_id=account,config_hash=bundle.hash,command=command},finish,
                function(error) finish({ok=false,error=error}) end)
        else
            adapter.submit(id,command,function(result)
                if not result.ok and not result.terminal and attempts<3 then
                    scheduler.after(1,attempt,'commerce_retry_'..id)
                else finish(result) end
            end)
        end
    end
    attempt()
end
function M.init()
    if initialized then return end;initialized=true
    require('systems/commerce_runtime').init()
    CustomGameEventManager:RegisterListener('survival_commerce_request',function(_,payload) M.handle(payload or {}) end)
end
return M
