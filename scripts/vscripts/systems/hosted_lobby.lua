-- A single-player entry VM brokers its own authenticated lobby actions.
-- It never loads gameplay, archive, payment, or a client-selected destination.
local config = require("config/hosted_lobby")
local access = require("core/test_access_policy")
local auth = require("systems/player_web_auth")
local encoder = require("core/json_encoder")
local decoder = require("core/json_decoder")
local M = {}
local BASE = "https://pay.xiaofengnet.com/ws4-web"
local initialized, session, record, serial = false, nil, nil, 0
local phases = { OPEN="open", ALLOCATING="starting", READY="started", RUNNING="running",
    INTERRUPTED="interrupted", CLOSED="closed" }
local errors = { no_ready_worker="worker_unavailable", room_version_conflict="revision_conflict",
    room_not_found="room_not_found", room_owner_required="not_host", room_not_ready="not_ready",
    lobby_identity_required="unauthenticated", lobby_identity_unavailable="unauthenticated",
    lobby_rate_limited="service_unavailable", invite_invalid_or_expired="invite_invalid_or_expired" }

local function now() return type(Time)=="function" and Time() or os.clock() end
local function active()
    if config.enabled ~= true or config.expected_map ~= "ws4_lobby" or config.base_url ~= BASE then return false end
    if type(IsServer)~="function" or type(GetMapName)~="function" then return false end
    local ok, server=pcall(IsServer)
    local map_ok, map=pcall(GetMapName)
    return ok and server==true and map_ok and map==config.expected_map
end
local function valid_id(value)
    return type(value)=="string" and #value>=8 and #value<=128 and value:match("^[A-Za-z0-9_%-]+$")~=nil
end
local function resource(name,id)
    if not PlayerResource or type(PlayerResource[name])~="function" then return nil end
    local ok,value=pcall(PlayerResource[name],PlayerResource,id)
    return ok and value or nil
end
local function current(owner)
    return active() and record==owner and access.enforce(owner.id)
        and resource("GetPlayer",owner.id)==owner.player
        and resource("GetSteamAccountID",owner.id)==owner.account_number
end
local function publish(owner, error)
    if not current(owner) then return end
    local room=owner.room
    local state={ok=owner.authorized==true and owner.service_ready==true,authenticated=owner.authorized==true,error=error or "",
        phase=room and phases[room.state] or "idle",room_id=room and room.room_id or "",
        revision=room and room.version or 0,capacity=4,players={},rooms={},
        worker_available=owner.worker_available==true,self_is_host=false,self_ready=false,
        invite_code=owner.invite_code or ""}
    for _,item in ipairs(owner.rooms or {}) do
        if type(item)=="table" and valid_id(item.room_id) and type(item.members)=="table" then
            state.rooms[#state.rooms+1]={id=item.room_id,name="我的测试房间",count=#item.members,capacity=4}
        end
    end
    if room and type(room.members)=="table" then
        for index,member in ipairs(room.members) do
            if index<=4 and type(member)=="table" then
                local self=member.member_id==room.self_member_id
                state.players[#state.players+1]={name=self and "我" or "测试玩家 "..tostring(index),
                    ready=member.ready==true,is_host=member.owner==true}
                if self then state.self_is_host,state.self_ready=member.owner==true,member.ready==true end
            end
        end
    end
    CustomGameEventManager:Send_ServerToPlayer(owner.player,"survival_lobby_state",state)
end
local function accept_room(value)
    return type(value)=="table" and valid_id(value.room_id) and phases[value.state]~=nil
        and type(value.version)=="number" and value.version>=1 and value.version==math.floor(value.version)
        and value.max_players==4 and value.mode=="session_memory_only"
        and value.cloud_archive_enabled==false and value.commerce_enabled==false
        and type(value.members)=="table" and #value.members>=1 and #value.members<=4
        and type(value.self_member_id)=="string"
end
local function request_id()
    serial=serial+1
    local unique=type(DoUniqueString)=="function" and DoUniqueString("lobby") or tostring(now())
    return ("lobby_"..tostring(serial).."_"..tostring(unique):gsub("[^A-Za-z0-9_%-]","")):sub(1,128)
end
local function post(owner,action,data,complete)
    if not current(owner) or owner.inflight or not owner.token then return false end
    if type(CreateHTTPRequestScriptVM)~="function" then owner.service_ready=false;publish(owner,"service_unavailable") return false end
    local ok,http=pcall(CreateHTTPRequestScriptVM,"POST",BASE.."/v1/lobby/"..action)
    if not ok or not http then owner.service_ready=false;publish(owner,"service_unavailable") return false end
    data.account_id,data.match_session_id=owner.account,session
    if action~="rooms" and action~="room" then data.request_id=request_id() end
    local generation=(owner.generation or 0)+1
    owner.generation,owner.inflight,owner.deadline=generation,true,now()+15
    local sent,accepted=pcall(function()
        http:SetHTTPRequestHeaderValue("Authorization","Bearer "..owner.token)
        http:SetHTTPRequestRawPostBody("application/json; charset=utf-8",encoder.encode(data))
        if type(http.SetHTTPRequestAbsoluteTimeoutMS)=="function" then http:SetHTTPRequestAbsoluteTimeoutMS(10000) end
        return http:Send(function(response)
            if not current(owner) or owner.generation~=generation or not owner.inflight then return end
            owner.inflight=false
            if type(response)=="table" and response.StatusCode==401 then
                owner.token,owner.authorized,owner.service_ready=nil,false,false
                auth.invalidate(owner.account,session)
                publish(owner,"unauthenticated") return
            end
            if type(response)~="table" or type(response.Body)~="string" or #response.Body>32768 then
                owner.service_ready=false;publish(owner,"service_unavailable") return
            end
            local decoded,body=pcall(decoder.decode,response.Body)
            if not decoded or type(body)~="table" then owner.service_ready=false;publish(owner,"service_unavailable") return end
            if response.StatusCode~=200 or body.ok~=true then
                if response.StatusCode==401 or body.error=="lobby_identity_required" then
                    owner.token,owner.authorized=nil,false
                    auth.invalidate(owner.account,session)
                end
                if body.error=="room_not_found" then
                    owner.room,owner.invite_code,owner.connect_sent=nil,nil,nil
                    owner.rooms,owner.worker_available={},false
                end
                publish(owner,errors[body.error] or "service_unavailable") return
            end
            owner.authorized,owner.worker_available,owner.service_ready=true,body.worker_available==true,true
            if body.room~=nil then
                if not accept_room(body.room) then publish(owner,"service_unavailable") return end
                owner.room=body.room
                if body.room.state=="CLOSED" then owner.room,owner.invite_code=nil,nil end
            end
            if body.rooms~=nil then
                if type(body.rooms)~="table" or #body.rooms>32 then owner.service_ready=false;publish(owner,"service_unavailable") return end
                for _,room in ipairs(body.rooms) do
                    if not accept_room(room) then owner.service_ready=false;publish(owner,"service_unavailable") return end
                end
                owner.rooms=body.rooms
                if not owner.room then
                    for _,room in ipairs(body.rooms) do
                        if accept_room(room) and room.state~="CLOSED" then owner.room=room break end
                    end
                end
            end
            if body.left==true then owner.room,owner.invite_code=nil,nil end
            if valid_id(body.invite_code) then owner.invite_code=body.invite_code end
            publish(owner)
            if complete then complete(body) end
        end)
    end)
    if not sent or accepted==false then owner.inflight,owner.service_ready=false,false;publish(owner,"service_unavailable");return false end
    return true
end
local function connect(owner,reconnecting)
    if not owner.room or not (owner.room.state=="READY" or owner.room.state=="RUNNING") then return end
    local room_id,match_id=owner.room.room_id,owner.room.match_id
    if not valid_id(match_id) then publish(owner,"service_unavailable") return end
    local function same_match()
        return current(owner) and owner.room and owner.room.room_id==room_id and owner.room.match_id==match_id
            and (owner.room.state=="READY" or owner.room.state=="RUNNING")
    end
    post(owner,reconnecting and "reconnect" or "ticket",{room_id=room_id},function(ticket)
        if not same_match() or not valid_id(ticket.ticket) or ticket.match_id~=match_id
            or ticket.build_sha256~=config.match_build_sha256 then
            publish(owner,"service_unavailable") return
        end
        post(owner,"redeem",{room_id=room_id,ticket=ticket.ticket},function(result)
            local allowed=false
            for _,address in ipairs(config.connect_addresses or {}) do
                if result.connect_address==address then allowed=true break end
            end
            if not same_match() or not allowed or result.build_sha256~=config.match_build_sha256
                or result.match_id~=match_id or result.native_connection_verified~=false then
                publish(owner,"service_unavailable") return
            end
            -- Fields only: neither UI nor backend may provide executable text.
            owner.connect_sent=result.match_id
            CustomGameEventManager:Send_ServerToPlayer(owner.player,"survival_lobby_connect",{
                address=result.connect_address,match_id=result.match_id,build_sha256=result.build_sha256})
        end)
    end)
end
local function actor(source)
    if not record or type(EntIndexToHScript)~="function" then return nil end
    local index=tonumber(source)
    if not index or index<0 or index~=math.floor(index) then return nil end
    local ok,entity=pcall(EntIndexToHScript,index)
    return ok and entity==record.player and current(record) and record or nil
end
local function receive(source,payload)
    local owner=actor(source)
    if not owner or type(payload)~="table" or owner.inflight then return end
    local at=now()
    if at<(owner.next_action or 0) then return end
    owner.next_action=at+0.5
    if not owner.authorized then publish(owner,"unauthenticated") return end
    local action=payload.action
    if action=="refresh" then
        post(owner,owner.room and "room" or "rooms",owner.room and {room_id=owner.room.room_id} or {}) return
    end
    if action=="create" and not owner.room then post(owner,"create",{}) return end
    if action=="join" and not owner.room and valid_id(payload.invite_code) then
        post(owner,"join",{invite_code=payload.invite_code}) return
    end
    local room=owner.room
    if not room or payload.room_id~=room.room_id or payload.revision~=room.version then
        publish(owner,"revision_conflict") return
    end
    if action=="reconnect" then connect(owner,true) return end
    if action=="leave" then
        for _,member in ipairs(room.members) do
            if member.member_id==room.self_member_id and member.owner==true then action="close" break end
        end
    end
    if action~="ready" and action~="start" and action~="invite" and action~="leave" and action~="close" then return end
    local data={room_id=room.room_id,expected_version=room.version}
    if action=="ready" then
        for _,member in ipairs(room.members) do
            if member.member_id==room.self_member_id then data.ready=member.ready~=true end
        end
        if type(data.ready)~="boolean" then return end
    end
    post(owner,action,data)
end
local function tick()
    if not active() then return nil end
    access.enforce_connected()
    local owner=record
    if owner and not current(owner) then record=nil;owner=nil end
    if not owner then
        for id=0,(DOTA_MAX_TEAM_PLAYERS or 24)-1 do
            local player,account=resource("GetPlayer",id),resource("GetSteamAccountID",id)
            if player and access.enforce(id) and type(account)=="number" and account>0 then
                owner={id=id,player=player,account_number=account,account=string.format("%.0f",account),next_poll=0}
                record=owner;break
            end
        end
    end
    if not owner then return 0.5 end
    if owner.inflight and now()>=owner.deadline then
        owner.inflight,owner.service_ready=false,false;owner.generation=owner.generation+1;publish(owner,"service_unavailable")
    end
    if not owner.authorized and now()>=(owner.next_auth or 0) then
        owner.next_auth=now()+3
        auth.resolve(owner.account,session,function(_,token)
            if current(owner) then owner.authorized,owner.token=true,token;publish(owner) end
        end,function() if current(owner) then publish(owner,"unauthenticated") end end)
    end
    if owner.authorized and not owner.inflight and now()>=owner.next_poll then
        owner.next_poll=now()+4
        if owner.room and (owner.room.state=="READY" or owner.room.state=="RUNNING")
            and owner.connect_sent~=owner.room.match_id then connect(owner,false)
        else post(owner,owner.room and "room" or "rooms",owner.room and {room_id=owner.room.room_id} or {}) end
    end
    return 0.5
end
function M.activate()
    if not active() then return false,"hosted_lobby_disabled_or_wrong_map" end
    if initialized then return true end
    if not access.enabled() or not access.init() or not auth.enabled() then return false,"hosted_lobby_identity_unavailable" end
    if not GameRules or not CustomGameEventManager or type(CustomGameEventManager.RegisterListener)~="function"
        or type(CustomGameEventManager.Send_ServerToPlayer)~="function" then return false,"hosted_lobby_engine_unavailable" end
    local mode=GameRules:GetGameModeEntity()
    if not mode or type(mode.SetContextThink)~="function" then return false,"hosted_lobby_engine_unavailable" end
    session=("lobby_"..request_id()):sub(1,128)
    GameRules:SetCustomGameTeamMaxPlayers(DOTA_TEAM_GOODGUYS or 2,1)
    GameRules:SetCustomGameTeamMaxPlayers(DOTA_TEAM_BADGUYS or 3,0)
    GameRules:SetHeroSelectionTime(0);GameRules:SetStrategyTime(0);GameRules:SetShowcaseTime(0)
    GameRules:SetCustomGameSetupTimeout(1);GameRules:EnableCustomGameSetupAutoLaunch(true)
    auth.init(session)
    CustomGameEventManager:RegisterListener("survival_lobby_request",receive)
    initialized=true
    mode:SetContextThink("SurvivalHostedLobby",tick,0.5)
    print("[WS4-LOBBY-01] entry_ready gameplay=false cloud_archive=false commerce=false")
    return true
end
return M
