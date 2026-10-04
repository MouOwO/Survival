-- Only the authenticated game server submits account/session/order identities.
local profiles = require("systems/player_profile_service")
local encoder = require("core/json_encoder")
local decoder = require("core/json_decoder")
local bus = require("core/event_bus")
local events = require("core/events")
local M = {}
local busy, last, orders, refreshed, resets = {}, {}, {}, {}, {}
local catalogs = {}
local serial, initialized = 0, false
-- Catalog membership and all prices/rewards are checked by the payment server.
local function valid_sku(sku)
    return type(sku)=="string" and #sku>=4 and #sku<=64 and sku:match("^[a-z0-9_]+$")~=nil
end
local function send(id, result)
    if not id or not PlayerResource:IsValidPlayerID(id) then return end
    if result.ok then
        local profile=profiles.get_profile(id)
        local projection=bus.request(events.PERMANENT_REWARD_EFFECTS_GET_REQUEST,{player_id=id})
        local stats=projection and projection.totals or (profile and profile.save and profile.save.gameplay_stats) or {}
        result.game_values={}
        for _,field in ipairs({"initial_wood","initial_gold","wall_armor","wall_initial_health","tower_attack_flat"}) do
            result.game_values[field]=tonumber(stats[field]) or 0
        end
        for field in pairs(result.effects or {}) do
            if tonumber(stats[field]) then result.game_values[field]=tonumber(stats[field]) end
        end
        for _,product in pairs(result.products or {}) do
            for _,effect in pairs(product.stat_preview or {}) do
                if tonumber(stats[effect.field_id]) then result.game_values[effect.field_id]=tonumber(stats[effect.field_id]) end
            end
        end
        result.game_entitlements={}
        for _,key in ipairs({"vip","archive_pass"}) do
            result.game_entitlements[key]=profile and profile.entitlements and profile.entitlements[key] or {active=false}
        end
        local wallet=bus.request(events.RESOURCE_GET_REQUEST,{player_id=id})
        if wallet then result.wallet={wood=wallet.wood,gold=wallet.gold} end
        result.match_frozen=require("systems/gameplay_phase_guard").post_clear_frozen()
    end
    local player = PlayerResource:GetPlayer(id)
    if player then CustomGameEventManager:Send_ServerToPlayer(player, "survival_payment_result", result) end
end
local function notify(id, message, level)
    bus.emit(events.UI_NOTIFICATION, {player_id=id, message=message, level=level or "info"})
end
local function session_id() return require("systems/match_setup_service").get_session_id() end
local function request(id, action, sku, kind, channel, request_id)
    if not id or id ~= math.floor(id) or not PlayerResource:IsValidPlayerID(id)
        or PlayerResource:IsFakeClient(id) then return false, "player_id_invalid" end
    local function reply(result, correlation)
        local copy={};for key,value in pairs(result) do copy[key]=value end
        copy.request_id=correlation or request_id
        send(id,copy)
    end
    local now = Time()
    local rate_key = tostring(id)..":"..action
    local provider = profiles.get_provider()
    local account = provider and provider.resolve_account_id(id)
    if not account or not profiles.get_profile(id) then
        catalogs[id]=nil
        reply({ok=false,action=action,error="profile_not_ready"}); return false,"profile_not_ready"
    end
    local token = tostring(Convars:GetStr("survival_fishing_api_token") or "")
    if token=="" then reply({ok=false,action=action,error="payment_not_configured"}); return false,"payment_not_configured" end
    local session = session_id()
    local cached=catalogs[id]
    if cached and (cached.account~=account or cached.session~=session) then catalogs[id]=nil;cached=nil end
    local pending=busy[id]
    if pending and (pending.account~=account or pending.session~=session) then busy[id]=nil;pending=nil end
    if action=="catalog" and pending and pending.action=="catalog" then
        -- A reopened/reloaded HUD shares the existing read, not another HTTP request.
        local key=request_id or ""
        for _,waiter in ipairs(pending.waiters) do if waiter==key then return true end end
        if #pending.waiters<8 then pending.waiters[#pending.waiters+1]=key;return true end
    end
    if pending then reply({ok=false,action=action,error="payment_busy"});return false,"payment_busy" end
    if action=="catalog" and cached and now-cached.at<2 then reply(cached.result);return true end
    if now-(last[rate_key] or -100)<1 then
        reply({ok=false,action=action,error="payment_busy"}); return false,"payment_busy"
    end
    local body = {account_id=account,match_session_id=session}
    if action=="create" then
        body.sku=sku
        if channel then body.provider=channel end
    end
    if action=="status" or action=="cancel" then
        local order=orders[id] and orders[id][sku]
        if not order or order.account~=account or order.session~=session then
            reply({ok=false,action=action,error="order_not_in_session",sku=sku}); return false,"order_not_in_session"
        end
        body.order_id=order.order_id
    end
    if action=="reset" then
        local old=resets[id]
        if old and old.account==account and old.session==session then
            if old.kind~=kind then return false,"reset_in_progress" end
        else
            serial=serial+1
            resets[id]={account=account,session=session,kind=kind,
                request_id="reset:"..tostring(id)..":"..tostring(math.floor(now*1000))..":"..serial..":"..tostring(RandomInt(1,999999999))}
        end
        body.kind=kind; body.request_id=resets[id].request_id
    end
    local http=CreateHTTPRequestScriptVM("POST","https://pay.xiaofengnet.com/v1/payments/"..action)
    if not http then reply({ok=false,action=action,error="payment_unavailable"});return false,"payment_unavailable" end
    local job={account=account,session=session,action=action,waiters={request_id or ""}}
    busy[id]=job; last[rate_key]=now
    if action~="catalog" then catalogs[id]=nil end
    http:SetHTTPRequestHeaderValue("Authorization","Bearer "..token)
    http:SetHTTPRequestRawPostBody("application/json; charset=utf-8",encoder.encode(body))
    if http.SetHTTPRequestAbsoluteTimeoutMS then http:SetHTTPRequestAbsoluteTimeoutMS(30000) end
    http:Send(function(response)
        if busy[id]~=job then return end
        busy[id]=nil
        if provider.resolve_account_id(id)~=account or session_id()~=session then return end
        local parsed,result=pcall(decoder.decode,tostring(response and response.Body or ""))
        if not parsed or type(result)~="table" then result={ok=false,error="payment_unavailable"} end
        if tonumber(response and response.StatusCode)~=200 then result.ok=false end
        result.action=action; result.sku=result.sku or sku
        if action=="catalog" then
            if result.ok then catalogs[id]={account=account,session=session,at=Time(),result=result} end
            for _,waiter in ipairs(job.waiters) do reply(result,waiter~="" and waiter or nil) end
            return
        end
        catalogs[id]=nil
        if not result.ok then
            if action=="reset" then notify(id,"清理尚未完成，请稍后再次输入同一命令重试。未确认的付款会先核对并关闭。","error") end
            reply(result); return
        end
        if type(result.order_id)=="string" and valid_sku(result.sku) then
            orders[id]=orders[id] or {}
            orders[id][result.sku]={account=account,session=session,order_id=result.order_id}
        end
        local needs_refresh = action=="reset" or (result.state=="delivered" and not refreshed[result.order_id])
        if needs_refresh then
            local reason=action=="reset" and "payment_test_reset" or "payment_delivered"
            local loading=profiles.load_player(id,reason,function()
                if action=="reset" then
                    orders[id]={}; resets[id]=nil
                    notify(id,kind=="refreshdata" and "测试存档已恢复新号初始状态，远端已更新。已生成的本局单位需重开对局。"
                        or "购买内容及对应属性已清理，远端已更新，可以重新购买。")
                else refreshed[result.order_id]=true end
                catalogs[id]=nil
                if provider.resolve_account_id(id)==account and session_id()==session then reply(result) end
            end,function() reply({ok=false,action=action,error="reward_refresh_pending",state=result.state,sku=sku}) end)
            if not loading.ok then reply({ok=false,action=action,error="reward_refresh_pending",state=result.state,sku=sku}) end
            return
        end
        reply(result)
    end)
    return true
end
function M.handle(payload)
    local action=tostring(payload.action or "")
    if action~="catalog" and action~="create" and action~="status" and action~="cancel" then return end
    local sku=tostring(payload.sku or "")
    -- Correlation is echoed only to this player; never forwarded as an identity or payment field.
    local request_id=payload.request_id
    if type(request_id)~="string" or #request_id>96 or not request_id:match("^[a-zA-Z0-9_%-]+$") then request_id=nil end
    if action~="catalog" and not valid_sku(sku) then
        send(tonumber(payload.PlayerID),{ok=false,action=action,error="product_unavailable",request_id=request_id});return
    end
    local channel=payload.provider
    if action=="create" and channel~=nil and channel~="wechat" and channel~="alipay" then
        send(tonumber(payload.PlayerID),{ok=false,action=action,error="payment_channel_unavailable",request_id=request_id});return
    end
    return request(tonumber(payload.PlayerID),action,sku,nil,channel,request_id)
end
function M.reset_player(context, kind)
    -- TODO(PAYMENT_TEST_ONLY): remove chat reset entry points before public release.
    -- Tools check + authenticated account + remote config + DB allowlist are required.
    if not IsInToolsMode or not IsInToolsMode() then return false,"test_reset_disabled" end
    if #context.args~=0 then return false,"usage: "..kind end
    if kind~="refreshdata" and kind~="refreshmoney" then return false,"reset_invalid" end
    local ok,err=request(tonumber(context.player_id),"reset",nil,kind)
    if ok then notify(context.player_id,"正在核对订单并清理远端测试数据，请等待完成提示…") end
    return ok,err
end
function M.init()
    if initialized then return end
    initialized=true
    CustomGameEventManager:RegisterListener("survival_payment_request",function(_,payload) M.handle(payload or {}) end)
    require("debug/payment_test_commands").init()
end
return M
