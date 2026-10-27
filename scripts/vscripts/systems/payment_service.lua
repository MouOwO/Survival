-- Only the authenticated game server submits account/session/order identities.
local profiles = require("systems/player_profile_service")
local encoder = require("core/json_encoder")
local decoder = require("core/json_decoder")
local bus = require("core/event_bus")
local events = require("core/events")
local scheduler = require("core/scheduler")
local cash_policy = require("core/commerce_release_policy")
local web_auth = require("systems/player_web_auth")
local M = {}
local busy, orders, resets, catalogs, bindings = {}, {}, {}, {}, {}
local serial, initialized = 0, false
local WEB_BASE = "https://pay.xiaofengnet.com/ws4-web"
local ONLINE_ACTIONS = {catalog=true,create=true,status=true,cancel=true}
local function session_id() return require("systems/match_setup_service").get_session_id() end
local function resource(method, id)
    if not PlayerResource or type(PlayerResource[method]) ~= "function" then return nil end
    local ok, value = pcall(PlayerResource[method], PlayerResource, id)
    if ok then return value end
end
local function human(id)
    if type(id) ~= "number" or id ~= id or id < 0 or id > 255 or id ~= math.floor(id)
        or resource("IsValidPlayerID", id) ~= true or resource("IsFakeClient", id) ~= false then return nil end
    local state = resource("GetConnectionState", id)
    if state ~= nil and state ~= (DOTA_CONNECTION_STATE_CONNECTED or 2) then return nil end
    if resource("GetTeam", id) == (DOTA_TEAM_SPECTATOR or 1) then return nil end
    return resource("GetPlayer", id)
end
local function actor(source)
    local index = tonumber(source)
    if not index or index < 0 or index ~= math.floor(index) or type(EntIndexToHScript) ~= "function" then return nil end
    local ok, entity = pcall(EntIndexToHScript, index)
    if not ok or not entity or type(entity.GetPlayerID) ~= "function"
        or type(entity.IsNull) == "function" and entity:IsNull() then return nil end
    local resolved, id = pcall(entity.GetPlayerID, entity)
    if resolved and human(id) == entity then return id end
end
local function clear_binding(id)
    bindings[id], busy[id], orders[id], resets[id], catalogs[id] = nil, nil, nil, nil, nil
end
local function binding_for(id)
    local player = human(id)
    if not player then clear_binding(id); return nil end
    local provider = profiles.get_provider()
    local account = provider and provider.resolve_account_id(id)
    local session = session_id()
    if not account or type(session) ~= "string" or #session < 8 then clear_binding(id); return nil end
    local old = bindings[id]
    if old and (old.player ~= player or old.provider ~= provider or old.account ~= account or old.session ~= session) then
        clear_binding(id); old = nil
    end
    if not old then
        serial = serial + 1
        old = {id=id,player=player,provider=provider,account=account,session=session,generation=serial,
            last={},refreshed={},capability_serial=0}
        bindings[id] = old
    end
    return old
end
local function current(bound)
    return bound and bindings[bound.id] == bound and human(bound.id) == bound.player
        and profiles.get_provider() == bound.provider
        and bound.provider.resolve_account_id(bound.id) == bound.account and session_id() == bound.session
end
local function profile_ready(bound, online)
    if not current(bound) or not profiles.get_profile(bound.id) then return false end
    if not online then return true end
    local account = tonumber(resource("GetSteamAccountID", bound.id))
    return account and account > 0 and account <= 4294967295 and account == math.floor(account)
        and string.format("%.0f", account) == bound.account
        and require("core/test_access_policy").allowed(bound.id) == true
        and bound.provider == require("systems/player_profile_providers/http_fishing_provider")
        and profiles.is_authenticated_for_account(bound.id, bound.account) == true
end
local function correlation(value)
    return type(value) == "string" and #value > 0 and #value <= 96
        and value:match("^[a-zA-Z0-9_%-]+$") and value or nil
end
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
local function request(id, action, sku, kind, channel, request_id, quantity)
    if not id or id ~= math.floor(id) or not PlayerResource:IsValidPlayerID(id)
        or PlayerResource:IsFakeClient(id) then return false, "player_id_invalid" end
    local bound = binding_for(id)
    if not bound then return false, "player_binding_unavailable" end
    local function reply(result, request_correlation)
        if not current(bound) then return end
        local copy={};for key,value in pairs(result) do copy[key]=value end
        copy.request_id=request_correlation or request_id
        send(id,copy)
    end
    -- The public/test release keeps free play and in-game wallet commerce,
    -- without requesting cash catalogues, orders, QR codes or checkout URLs.
    if not cash_policy.real_money_allowed() then
        if action=="catalog" then
            reply({ok=true,action=action,real_money_enabled=false,catalog_hash="noncommercial_test",
                products={},categories={},wechat=false,alipay=false})
            return true
        end
        reply({ok=false,action=action,error="real_money_disabled"})
        return false,"real_money_disabled"
    end
    local now = Time()
    local online = cash_policy.online_allowed()
    local provider, account, session = bound.provider, bound.account, bound.session
    if not profile_ready(bound, online) then
        catalogs[id]=nil
        reply({ok=false,action=action,error="profile_not_ready"}); return false,"profile_not_ready"
    end
    if online and not ONLINE_ACTIONS[action] then return false, "payment_action_disabled" end
    local token
    if not online then
        token = tostring(Convars:GetStr("survival_fishing_api_token") or "")
        if token=="" then reply({ok=false,action=action,error="payment_not_configured"}); return false,"payment_not_configured" end
    end
    local cached=catalogs[id]
    if cached and cached.binding~=bound then catalogs[id]=nil;cached=nil end
    local pending=busy[id]
    if pending and pending.binding~=bound then busy[id]=nil;pending=nil end
    if action=="catalog" and pending and pending.action=="catalog" then
        -- A reopened/reloaded HUD shares the existing read, not another HTTP request.
        local key=request_id or ""
        for _,waiter in ipairs(pending.waiters) do if waiter==key then return true end end
        if #pending.waiters<8 then pending.waiters[#pending.waiters+1]=key;return true end
    end
    if pending then reply({ok=false,action=action,error="payment_busy"});return false,"payment_busy" end
    if action=="catalog" and cached and now-cached.at<2 then reply(cached.result);return true end
    if now-(bound.last[action] or -100)<1 then
        reply({ok=false,action=action,error="payment_busy"}); return false,"payment_busy"
    end
    local body = {account_id=account,match_session_id=session}
    if action=="create" then
        body.sku=sku
        if quantity~=nil then body.quantity=quantity end
        if channel then body.provider=channel end
    end
    if action=="status" or action=="cancel" then
        local order=orders[id] and orders[id][sku]
        if not order or order.binding~=bound then
            reply({ok=false,action=action,error="order_not_in_session",sku=sku}); return false,"order_not_in_session"
        end
        body.order_id=order.order_id
    end
    if action=="reset" then
        local old=resets[id]
        if old and old.binding==bound then
            if old.kind~=kind then return false,"reset_in_progress" end
        else
            serial=serial+1
            resets[id]={binding=bound,kind=kind,
                request_id="reset:"..tostring(id)..":"..tostring(math.floor(now*1000))..":"..serial..":"..tostring(RandomInt(1,999999999))}
        end
        body.kind=kind; body.request_id=resets[id].request_id
    end
    local job={binding=bound,action=action,waiters={request_id or ""}}
    busy[id]=job; bound.last[action]=now
    if action~="catalog" then catalogs[id]=nil end
    local transport_done,transport_failed=false,false
    local transport_timeout="payment_transport:"..tostring(id)..":"..bound.generation
    local function fail_transport()
        if transport_done or busy[id]~=job then return end
        transport_done,transport_failed=true,true;busy[id]=nil;scheduler.cancel(transport_timeout)
        if not current(bound) then return end
        local result={ok=false,action=action,sku=sku,
            error=cash_policy.real_money_allowed() and "payment_unavailable" or "real_money_disabled"}
        if action=="catalog" then
            for _,waiter in ipairs(job.waiters) do reply(result,waiter~="" and waiter or nil) end
        else reply(result) end
    end
    local function received(response)
        if transport_done or busy[id]~=job then return end
        transport_done=true;scheduler.cancel(transport_timeout)
        busy[id]=nil
        if not cash_policy.real_money_allowed() then
            reply({ok=false,action=action,error="real_money_disabled"});return
        end
        if not profile_ready(bound, online) or cash_policy.online_allowed()~=online then return end
        local status=tonumber(response and response.StatusCode)
        if online and (status==401 or status==403) then
            web_auth.invalidate(account,session)
            if bound.capability_request then M.publish_capability(id,bound.capability_request) end
        end
        local parsed,result=pcall(decoder.decode,tostring(response and response.Body or ""))
        if not parsed or type(result)~="table" then result={ok=false,error="payment_unavailable"} end
        if tonumber(response and response.StatusCode)~=200 then result.ok=false end
        result.action=action; result.sku=result.sku or sku
        if action=="catalog" then
            if result.ok then catalogs[id]={binding=bound,at=Time(),result=result} end
            for _,waiter in ipairs(job.waiters) do reply(result,waiter~="" and waiter or nil) end
            return
        end
        catalogs[id]=nil
        if not result.ok then
            if action=="reset" then notify(id,"清理尚未完成，请稍后再次输入同一命令重试。未确认的付款会先核对并关闭。","error") end
            reply(result); return
        end
        if result.state=="delivered" and (type(result.order_id)~="string" or #result.order_id==0) then
            reply({ok=false,action=action,error="payment_invalid_response",sku=sku});return
        end
        if type(result.order_id)=="string" and valid_sku(result.sku) then
            orders[id]=orders[id] or {}
            orders[id][result.sku]={binding=bound,order_id=result.order_id}
        end
        local needs_refresh = action=="reset" or (result.state=="delivered" and not bound.refreshed[result.order_id])
        if needs_refresh then
            local reason=action=="reset" and "payment_test_reset" or "payment_delivered"
            -- Keep the operation busy until the authoritative profile commits.
            -- Repeated status polls cannot supersede its load generation.
            busy[id]=job
            local settled=false
            local timeout_key="payment_profile_refresh:"..tostring(id)..":"..bound.generation
            local function finish_refresh(ok)
                if settled then return end
                settled=true
                if busy[id]~=job then return end
                busy[id]=nil
                scheduler.cancel(timeout_key)
                if not current(bound) or cash_policy.online_allowed()~=online then return end
                if not cash_policy.real_money_allowed() then
                    reply({ok=false,action=action,error="real_money_disabled"});return
                end
                catalogs[id]=nil
                if not ok or not profile_ready(bound, online) then
                    reply({ok=false,action=action,error="reward_refresh_pending",state=result.state,sku=sku})
                    return
                end
                if action=="reset" then
                    orders[id]={}; resets[id]=nil
                    notify(id,kind=="refreshdata" and "测试存档已恢复新号初始状态，远端已更新。已生成的本局单位需重开对局。"
                        or "购买内容及对应属性已清理，远端已更新，可以重新购买。")
                else bound.refreshed[result.order_id]=true end
                reply(result)
            end
            -- Another authoritative load may supersede this generation. Its
            -- discarded callback must not pin payment busy forever; retry the
            -- existing immutable order without acknowledging stale rewards.
            scheduler.after(35,function() finish_refresh(false) end,timeout_key)
            local loading=profiles.refresh_player(id,reason,
                function() finish_refresh(true) end,function() finish_refresh(false) end)
            if not loading or not loading.ok then finish_refresh(false) end
            return
        end
        reply(result)
    end
    -- Native Send may return void; explicit false or an exception means no
    -- callback is guaranteed. A separate deadline also retires lost requests.
    -- Cancel it before waiting for the authoritative profile refresh below.
    scheduler.after(32,fail_transport,transport_timeout)
    local function submit(base, player_token)
        if transport_done or busy[id]~=job or not profile_ready(bound, online)
            or not cash_policy.real_money_allowed() or cash_policy.online_allowed()~=online then return end
        if online and (base~=WEB_BASE or type(player_token)~="string" or #player_token~=69
            or not player_token:match("^pwa1_[a-f0-9]+$")) then
            fail_transport(); return
        end
        local created,http=pcall(CreateHTTPRequestScriptVM,"POST",base.."/v1/payments/"..action)
        if not created or not http then fail_transport(); return end
        local submitted,send_result=pcall(function()
        http:SetHTTPRequestHeaderValue("Authorization","Bearer "..player_token)
        http:SetHTTPRequestRawPostBody("application/json; charset=utf-8",encoder.encode(body))
        if http.SetHTTPRequestAbsoluteTimeoutMS then http:SetHTTPRequestAbsoluteTimeoutMS(30000) end
        return http:Send(received)
        end)
        if (not submitted or send_result==false) and not transport_done then fail_transport() end
    end
    if online then
        local resolved = pcall(web_auth.resolve, account, session, submit, function() fail_transport() end)
        if not resolved then fail_transport() end
    else
        submit("https://pay.xiaofengnet.com", token)
    end
    if transport_failed then return false,"payment_unavailable" end
    return true
end
function M.publish_capability(id, request_id)
    local bound=binding_for(id)
    if not bound then return false end
    bound.capability_serial=bound.capability_serial+1
    local generation=bound.capability_serial
    request_id=correlation(request_id)
    bound.capability_request=request_id
    local function publish(enabled)
        if not current(bound) or bound.capability_serial~=generation then return end
        CustomGameEventManager:Send_ServerToPlayer(bound.player,"survival_payment_capability",{
            enabled=enabled==true, account_id=bound.account, match_session_id=bound.session,
            player_id=id, request_id=request_id,
        })
    end
    local online=cash_policy.online_allowed()
    if not cash_policy.real_money_allowed() or not profile_ready(bound, online) then publish(false);return false end
    if not online then publish(true);return true end
    local settled=false
    local function ready(base, token)
        settled=true
        publish(base==WEB_BASE and type(token)=="string" and #token==69
            and token:match("^pwa1_[a-f0-9]+$")~=nil
            and cash_policy.online_allowed() and profile_ready(bound,true))
    end
    local ok=pcall(web_auth.resolve,bound.account,bound.session,ready,function()settled=true;publish(false)end)
    if not ok or not settled then publish(false) end
    return ok
end
function M.handle(source, payload)
    local id=actor(source)
    if id==nil or type(payload)~="table" then return false,"player_id_invalid" end
    local action=tostring(payload.action or "")
    if action~="catalog" and action~="create" and action~="status" and action~="cancel" then return end
    local sku=tostring(payload.sku or "")
    -- Correlation is echoed only to this player; never forwarded as an identity or payment field.
    local request_id=correlation(payload.request_id)
    if action~="catalog" and not valid_sku(sku) then
        send(id,{ok=false,action=action,error="product_unavailable",request_id=request_id});return
    end
    local channel=payload.provider
    if action=="create" and channel~=nil and channel~="wechat" and channel~="alipay" then
        send(id,{ok=false,action=action,error="payment_channel_unavailable",request_id=request_id});return
    end
    local quantity=payload.quantity
    if action=="create" then
        if quantity==nil then quantity=1 end
        -- Only the dedicated recharge SKU accepts large quantities. The
        -- authenticated payment server still owns its price and U-coin grant.
        local maximum=sku=="u_coin_recharge" and 999999 or 100
        if type(quantity)~="number" or quantity~=math.floor(quantity) or quantity<1 or quantity>maximum then
            send(id,{ok=false,action=action,error="quantity_invalid",request_id=request_id});return
        end
    end
    return request(id,action,sku,nil,channel,request_id,quantity)
end
function M.reset_player(context, kind)
    -- TODO(PAYMENT_TEST_ONLY): remove chat reset entry points before public release.
    -- Tools check + authenticated account + remote config + DB allowlist are required.
    if not require("core/release_policy").development_allowed() then
        return false,"test_reset_disabled"
    end
    if #context.args~=0 then return false,"usage: "..kind end
    if kind~="refreshdata" and kind~="refreshmoney" then return false,"reset_invalid" end
    local ok,err=request(tonumber(context.player_id),"reset",nil,kind)
    if ok then notify(context.player_id,"正在核对订单并清理远端测试数据，请等待完成提示…") end
    return ok,err
end
function M.open_pass_checkout(id, selection, done)
    local function finish(ok,message)
        if done then done({ok=ok,message=message}) end
        return ok
    end
    if not cash_policy.real_money_allowed() then
        return finish(false,"测试版未开放月卡开通")
    end
    if not id or id~=math.floor(id) or not PlayerResource:IsValidPlayerID(id) or PlayerResource:IsFakeClient(id) then
        return finish(false,"玩家尚未进入对局")
    end
    local rules=require("config/generated/archive_daily_rules").by_id.default
    if not rules.purchase_enabled or not valid_sku(rules.pass_sku) or not selection or selection.sku~=rules.pass_sku then
        return finish(false,"月卡商品尚未开放")
    end
    local provider=profiles.get_provider()
    if not provider or not provider.resolve_account_id(id) or not profiles.get_profile(id) or not session_id() then
        return finish(false,"请先进入对局，等待存档加载")
    end
    local bound=binding_for(id)
    if not bound or not profile_ready(bound,cash_policy.online_allowed()) then
        return finish(false,"请先完成账号认证并等待云端存档加载")
    end
    if not cash_policy.online_allowed() and tostring(Convars:GetStr("survival_fishing_api_token") or "")=="" then
        return finish(false,"支付服务尚未配置")
    end
    local player=PlayerResource:GetPlayer(id)
    if not player then return finish(false,"玩家连接已断开，请重试") end
    -- The catalog supplies the authenticated price. A financial order is only
    -- created by the player's subsequent purchase action in this confirmation.
    CustomGameEventManager:Send_ServerToPlayer(player,"survival_payment_open",{sku=rules.pass_sku})
    return finish(true,"请核对月卡价格并选择支付方式")
end
function M.init()
    if initialized then return end
    initialized=true
    require("systems/commerce_service").init()
    require("systems/archive_service").set_purchase_provider(cash_policy.real_money_allowed()
        and {open_checkout=M.open_pass_checkout} or nil)
    CustomGameEventManager:RegisterListener("survival_payment_request",M.handle)
    CustomGameEventManager:RegisterListener("survival_payment_capability_request",function(source,payload)
        local id=actor(source)
        if id~=nil and type(payload)=="table" then M.publish_capability(id,payload.request_id) end
    end)
    bus.subscribe(events.PLAYER_DISCONNECTED,function(payload)
        local id=payload and tonumber(payload.player_id)
        if id then clear_binding(id) end
    end)
    bus.subscribe(events.PLAYER_PROFILE_CHANGED,function(payload)
        local id=payload and tonumber(payload.player_id)
        local bound=id and bindings[id]
        if bound and bound.capability_request then M.publish_capability(id,bound.capability_request) end
    end)
    if type(ListenToGameEvent)=="function" then
        local function connection_changed(payload)
            local id=type(payload)=="table" and tonumber(payload.PlayerID or payload.playerid) or nil
            local players=package.loaded["systems/multiplayer_player_service"]
            if not id and players and type(players.resolve_player_id)=="function" then
                local ok,value=pcall(players.resolve_player_id,payload)
                if ok then id=value end
            end
            if id then clear_binding(id)
            else
                -- An unresolved engine disconnect must never preserve a slot
                -- capability which could later be inherited by a new player.
                for player_id in pairs(bindings) do clear_binding(player_id) end
            end
        end
        ListenToGameEvent("player_disconnect",connection_changed,nil)
        ListenToGameEvent("player_connect_full",connection_changed,nil)
    end
    require("debug/payment_test_commands").init()
end
return M
