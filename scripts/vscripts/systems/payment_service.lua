-- The player submits only an action. Account, session, SKU and amount are server-owned.
local profiles=require('systems/player_profile_service')
local encoder=require('core/json_encoder')
local decoder=require('core/json_decoder')
local M={}
local busy,last,orders,refreshed={},{},{},{}
local initialized=false
local function send(id,result)
    local player=PlayerResource:GetPlayer(id)
    if player then CustomGameEventManager:Send_ServerToPlayer(player,'survival_payment_result',result) end
end
function M.handle(payload)
    -- PlayerID is injected by CustomGameEventManager; never accept a client Steam ID.
    local id=tonumber(payload.PlayerID)
    if not id or id~=math.floor(id) or not PlayerResource:IsValidPlayerID(id) or PlayerResource:IsFakeClient(id) then return end
    local action=tostring(payload.action or '')
    if action~='catalog' and action~='create' and action~='status' then return end
    local now=Time()
    if busy[id] or now-(last[id] or -100)<1 then return end
    local provider=profiles.get_provider()
    local account=provider and provider.resolve_account_id(id)
    if not account or not profiles.get_profile(id) then send(id,{ok=false,error='profile_not_ready'});return end
    local token=tostring(Convars:GetStr('survival_fishing_api_token') or '')
    if token=='' then send(id,{ok=false,error='payment_not_configured'});return end
    local session=require('systems/match_setup_service').get_session_id()
    local body={account_id=account,match_session_id=session}
    if action=='status' then
        if not orders[id] or orders[id].account~=account then return end
        body.order_id=orders[id].order_id
    end
    busy[id]=true;last[id]=now
    local http=CreateHTTPRequestScriptVM('POST','https://pay.xiaofengnet.com/v1/payments/'..action)
    if not http then busy[id]=nil;send(id,{ok=false,error='payment_unavailable'});return end
    http:SetHTTPRequestHeaderValue('Authorization','Bearer '..token)
    http:SetHTTPRequestRawPostBody('application/json; charset=utf-8',encoder.encode(body))
    if http.SetHTTPRequestAbsoluteTimeoutMS then http:SetHTTPRequestAbsoluteTimeoutMS(30000) end
    http:Send(function(response)
        busy[id]=nil
        if provider.resolve_account_id(id)~=account or require('systems/match_setup_service').get_session_id()~=session then return end
        local parsed,result=pcall(decoder.decode,tostring(response and response.Body or ''))
        if not parsed or type(result)~='table' then result={ok=false,error='payment_unavailable'} end
        if tonumber(response and response.StatusCode)~=200 then result.ok=false end
        result.action=action
        if result.ok and type(result.order_id)=='string' then
            orders[id]={account=account,order_id=result.order_id}
            if result.state=='delivered' and not refreshed[result.order_id] then
                -- Refresh through the existing authoritative profile projector,
                -- including the current match's pure/standard mode.
                local request=profiles.load_player(id,'payment_delivered',function()
                    refreshed[result.order_id]=true
                    send(id,result)
                end,function() send(id,{ok=false,error='reward_refresh_pending',state='delivered'}) end)
                if not request.ok then send(id,{ok=false,error='reward_refresh_pending',state='delivered'}) end
                return
            end
        end
        send(id,result)
    end)
end
function M.init()
    if initialized then return end
    initialized=true
    CustomGameEventManager:RegisterListener('survival_payment_request',function(_,payload) M.handle(payload or {}) end)
end
return M
