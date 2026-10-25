-- Real controller + real four-account admission. Only engine/auth/wire are faked.
package.path = "scripts/vscripts/?.lua;" .. package.path
local checked_in = require("config/hosted_lobby")
assert(checked_in.enabled == false, "ordinary builds must keep the lobby gate closed")
local BASE, BUILD = "https://pay.xiaofengnet.com/ws4-web", string.rep("a",64)
local ACCOUNT, TOKEN, TICKET = "885195478", "pwa1_fictional_private_test_capability", "fictional_private_join_ticket_12345"
local passed, failures = 0, {}

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}; for key, child in pairs(value) do result[key] = copy(child) end
    return result
end
local function ends(value, suffix) return value:sub(-#suffix) == suffix end
local function test(name, callback)
    local ok, reason = pcall(callback)
    if ok then passed = passed + 1 else failures[#failures+1] = name .. ": " .. tostring(reason) end
end

local function environment(settings)
    settings = settings or {}
    local env = { now=0, server=true, map="ws4_lobby", requests={}, auth_requests={}, invalidations={},
        packets={}, listeners={}, disconnected={}, unique=0, auth_enabled=true, init_calls=0 }
    env.config = { enabled=settings.enabled ~= false, base_url=BASE, expected_map="ws4_lobby",
        match_build_sha256=BUILD, connect_addresses={"127.0.0.1:27025"} }
    if settings.server ~= nil then env.server = settings.server end
    if settings.map ~= nil then env.map = settings.map end
    env.identities = {[0]=885195478,[1]=463897428,[2]=144521714,[3]=1014036256,[4]=7}
    env.players = {[0]={id=0},[1]={id=1}}
    for _, player in pairs(env.players) do player.GetPlayerID=function(self) return self.id end end
    env.entities = {[100]=env.players[0],[101]=env.players[1],[999]={id=0}}
    local wire, wire_serial = {}, 0
    local function encode(value)
        wire_serial = wire_serial + 1
        local text = "fixture_json_" .. wire_serial
        wire[text] = copy(value)
        return text
    end
    local function decode(text)
        assert(wire[text], "invalid JSON wire fixture")
        return copy(wire[text])
    end
    package.loaded["core/json_encoder"] = {encode=encode}
    package.loaded["core/json_decoder"] = {decode=decode,null={}}
    package.loaded["config/hosted_lobby"] = env.config
    package.loaded["config/test_access"] = {
        enabled = true,
        allowed_steamids = {"76561198845461206","76561198424163156","76561198104787442","76561198974301984"},
    }
    package.loaded["core/test_access_policy"] = nil
    package.loaded["systems/player_web_auth"] = {
        enabled=function() return env.auth_enabled end,
        init=function(session) env.session=session; env.init_calls=env.init_calls+1 end,
        resolve=function(account,session,success,failure)
            env.auth_requests[#env.auth_requests+1]={account=account,session=session,success=success,failure=failure}
        end,
        invalidate=function(account,session)
            env.invalidations[#env.invalidations+1]={account=account,session=session}
            return true
        end,
    }
    IsServer=function() if env.server_error then error("unavailable VM") end; return env.server end
    GetMapName=function() return env.map end
    Time=function() return env.now end
    DoUniqueString=function() env.unique=env.unique+1; return "fixture_unique_"..env.unique end
    DisconnectClient=function(id,forced) assert(forced==true); env.disconnected[id]=true end
    PlayerResource={
        GetSteamAccountID=function(_,id) return env.identities[id] end,
        GetPlayer=function(_,id) return env.players[id] end,
        IsValidPlayerID=function(_,id) return env.identities[id] ~= nil end,
    }
    EntIndexToHScript=function(index) return env.entities[index] end
    local mode={SetContextThink=function(_,name,callback,delay)
        assert(name=="SurvivalHostedLobby" and delay>0); env.think=callback
    end}
    GameRules={GetGameModeEntity=function() return mode end}
    for _,name in ipairs({"SetCustomGameTeamMaxPlayers","SetHeroSelectionTime","SetStrategyTime",
        "SetShowcaseTime","SetCustomGameSetupTimeout","EnableCustomGameSetupAutoLaunch"}) do
        GameRules[name]=function() end
    end
    CustomGameEventManager={
        RegisterListener=function(_,name,callback) env.listeners[name]=callback; return 1 end,
        Send_ServerToPlayer=function(_,player,event,payload)
            env.packets[#env.packets+1]={player=player,event=event,payload=copy(payload)}
        end,
    }
    CreateHTTPRequestScriptVM=function(method,url)
        env.factory_calls=(env.factory_calls or 0)+1
        if env.factory_throws then error("fictional unavailable factory") end
        if env.factory_nil then return nil end
        assert(method=="POST" and url:sub(1,#BASE)==BASE, "HTTP destination must be fixed")
        local request={url=url,headers={}}
        function request:SetHTTPRequestHeaderValue(key,value) self.headers[key]=value end
        function request:SetHTTPRequestRawPostBody(kind,text)
            assert(kind=="application/json; charset=utf-8"); self.data=decode(text)
        end
        function request:SetHTTPRequestAbsoluteTimeoutMS(value) self.timeout=value end
        function request:Send(callback)
            self.callback=callback
            env.requests[#env.requests+1]=self
            if env.send_throws then error("fictional send failure") end
            if env.send_false then return false end
            return true
        end
        return request
    end
    CreateHTTPRequest=function() error("legacy HTTP is not a lobby fallback") end
    package.loaded["systems/hosted_lobby"] = nil
    env.controller=require("systems/hosted_lobby")
    function env.tick(seconds)
        env.now=env.now+(seconds or 0)
        assert(env.think, "controller did not register its think")
        return env.think()
    end
    function env.grant(token,index)
        local auth=assert(env.auth_requests[index or #env.auth_requests])
        auth.success({},token or TOKEN)
    end
    function env.respond(index,body,status)
        assert(env.requests[index]).callback({StatusCode=status or 200,Body=encode(body)})
    end
    function env.request(suffix)
        local request=assert(env.requests[#env.requests],"missing outgoing request")
        assert(ends(request.url,"/"..suffix), "expected request "..suffix..", got "..request.url)
        return request
    end
    function env.emit(payload,source)
        env.now=env.now+0.6
        assert(env.listeners.survival_lobby_request)(source or 100,payload)
    end
    function env.state()
        for i=#env.packets,1,-1 do
            if env.packets[i].event=="survival_lobby_state" then return env.packets[i].payload end
        end
        error("missing lobby state")
    end
    function env.connects()
        local values={}
        for _,packet in ipairs(env.packets) do if packet.event=="survival_lobby_connect" then values[#values+1]=packet end end
        return values
    end
    function env.bootstrap()
        assert(env.controller.activate())
        env.tick(); assert(#env.auth_requests==1 and env.auth_requests[1].account==ACCOUNT)
        env.grant()
        assert(env.state().authenticated==true and env.state().ok==false,
            "browser authentication alone must not advertise a healthy lobby service")
        env.tick(); env.request("rooms")
        env.respond(#env.requests,{ok=true,rooms={}})
        assert(env.state().authenticated==true and env.state().ok==true and env.state().room_id=="")
    end
    return env
end

local function room(version,state,host,identifier,match)
    return {room_id=identifier or "room_alpha_1234",version=version or 1,state=state or "OPEN",max_players=4,
        mode="session_memory_only",cloud_archive_enabled=false,commerce_enabled=false,build_sha256=BUILD,
        self_member_id="member_alpha_1234",match_id=match or ((state=="READY" or state=="RUNNING") and "match_alpha_1234" or nil),
        members={{member_id="member_alpha_1234",owner=host~=false,ready=false},
                 {member_id="member_beta_12345",owner=host==false,ready=true}}}
end
local function create(env,value)
    env.emit({action="create",PlayerID=1})
    env.request("create")
    env.respond(#env.requests,{ok=true,room=value or room(1)})
end
local function action(env,name,extra)
    local current=env.state()
    local payload={action=name,room_id=current.room_id,revision=current.revision}
    for key,value in pairs(extra or {}) do payload[key]=value end
    env.emit(payload)
end
local function ready_connection()
    local env=environment(); env.bootstrap()
    local value=room(7,"READY")
    value.token,value.lease_id=TOKEN,"fictional_private_lease"
    value.members[1].display_name,value.members[1].steam_id=TOKEN,TICKET
    create(env,value)
    env.tick(5); env.request("ticket")
    return env
end
local function ticket_response(match,build)
    return {ok=true,ticket=TICKET,match_id=match or "match_alpha_1234",build_sha256=build or BUILD,
        lease_id="fictional_private_lease",account_id="fictional_private_account"}
end
local function redeemed(address,match,build)
    return {ok=true,connect_address=address or "127.0.0.1:27025",match_id=match or "match_alpha_1234",
        build_sha256=build or BUILD,native_connection_verified=false,ticket=TICKET,token=TOKEN,
        lease_id="fictional_private_lease"}
end

test("default gate and invalid map/VM never authenticate or send HTTP",function()
    for _,settings in ipairs({{enabled=false},{map="template_map"},{server=false}}) do
        local env=environment(settings)
        assert(env.controller.activate()==false)
        assert(#env.requests==0 and #env.auth_requests==0 and env.init_calls==0 and env.think==nil)
    end
    local env=environment(); env.server_error=true
    assert(env.controller.activate()==false and #env.requests==0)
end)

test("missing identity and unexpected base stay closed",function()
    local env=environment(); env.auth_enabled=false
    assert(env.controller.activate()==false and #env.requests==0)
    env=environment(); package.loaded["config/test_access"].enabled=false
    assert(env.controller.activate()==false and #env.requests==0)
    env=environment(); env.config.base_url="https://client-selected.invalid"
    assert(env.controller.activate()==false and #env.requests==0)
end)

test("source entity owns account; payload PlayerID never selects actor",function()
    local env=environment(); env.bootstrap()
    local count=#env.requests
    for _,source in ipairs({101,999,0,-1,100.5}) do env.emit({action="create",PlayerID=0},source) end
    assert(#env.requests==count, "forged or another player's source must not act")
    env.emit({action="create",PlayerID=1,account_id="7",match_session_id="invented_session"},100)
    local sent=env.request("create")
    assert(sent.data.account_id==ACCOUNT and sent.data.match_session_id==env.session)
    assert(sent.data.PlayerID==nil and sent.headers.Authorization=="Bearer "..TOKEN)
    assert(type(sent.data.request_id)=="string" and #sent.data.request_id>=8)
    env.identities[0]=7
    env.respond(#env.requests,{ok=true,room=room(1)})
    assert(env.state().room_id=="" and #env.connects()==0 and env.disconnected[0],
        "late success for a disallowed engine identity is rejected and enforced")
end)

test("create invite ready start CAS and host leave/close",function()
    local env=environment(); env.bootstrap(); create(env)
    action(env,"invite"); assert(env.request("invite").data.expected_version==1)
    env.respond(#env.requests,{ok=true,invite_code="invite_alpha_1234",room=room(1)})
    assert(env.state().invite_code=="invite_alpha_1234")
    action(env,"ready",{ready=false})
    assert(env.request("ready").data.ready==true, "ready toggles server-known self, not client input")
    local updated=room(2); updated.members[1].ready=true
    env.respond(#env.requests,{ok=true,room=updated})
    local before=#env.requests
    action(env,"start",{revision=1})
    assert(#env.requests==before and env.state().error=="revision_conflict")
    action(env,"start")
    assert(env.request("start").data.expected_version==2)
    env.respond(#env.requests,{ok=false,error="room_not_ready"},409)
    assert(env.state().error=="not_ready" and env.state().revision==2)
    action(env,"leave")
    assert(env.request("close").data.expected_version==2, "host leave closes instead of abandoning ownership")
    env.respond(#env.requests,{ok=true,room=room(3,"CLOSED")})
    assert(env.state().room_id=="" and env.state().invite_code=="")
end)

test("join sends only validated invite; guest leave remains leave",function()
    local env=environment(); env.bootstrap()
    local before=#env.requests
    env.emit({action="join",invite_code="x;connect 203.0.113.1"})
    assert(#env.requests==before)
    env.emit({action="join",invite_code="invite_guest_1234",PlayerID=1,address="203.0.113.9:27015"})
    local sent=env.request("join")
    assert(sent.data.invite_code=="invite_guest_1234" and sent.data.address==nil)
    env.respond(#env.requests,{ok=true,room=room(5,"OPEN",false)})
    action(env,"leave"); assert(env.request("leave").data.expected_version==5)
    env.respond(#env.requests,{ok=true,left=true})
    assert(env.state().room_id=="")
end)

test("backend CAS conflicts refresh version and allocation never connects early",function()
    local env=environment(); env.bootstrap(); create(env)
    action(env,"start")
    env.respond(#env.requests,{ok=false,error="room_version_conflict"},409)
    assert(env.state().error=="revision_conflict" and env.state().revision==1)
    env.emit({action="refresh"}); env.request("room")
    local latest=room(3); latest.members[1].ready=true
    env.respond(#env.requests,{ok=true,room=latest})
    action(env,"start")
    assert(env.request("start").data.expected_version==3, "new action must use the refreshed server version")
    env.respond(#env.requests,{ok=true,room=room(4,"ALLOCATING")})
    assert(env.state().phase=="starting" and #env.connects()==0)
    env.tick(5); env.request("room")
    env.respond(#env.requests,{ok=true,room=room(5,"READY")})
    env.tick(5); assert(env.request("ticket").data.room_id=="room_alpha_1234")
    assert(#env.connects()==0, "READY alone is insufficient before a valid ticket and redeem")
end)

test("pending requests coalesce and timed-out late successes cannot replace newer state",function()
    local env=environment(); env.bootstrap()
    env.emit({action="create"}); local old=#env.requests
    env.emit({action="create"}); env.emit({action="refresh"})
    assert(#env.requests==old, "UI spam cannot create parallel requests")
    env.tick(16); local fresh=#env.requests
    assert(fresh==old+1); env.request("rooms")
    env.respond(fresh,{ok=true,rooms={}})
    local count=#env.packets
    env.respond(old,{ok=true,room=room(100,"READY")})
    assert(#env.packets==count and env.state().room_id=="" and #env.connects()==0)
end)

test("old player entity and wrong map invalidate outstanding callbacks",function()
    local env=environment(); env.bootstrap(); env.emit({action="create"})
    local count=#env.packets
    env.players[0]={id=0}
    env.respond(#env.requests,{ok=true,room=room(1)})
    assert(#env.packets==count, "reused slot cannot receive its prior entity's HTTP result")
    env=environment(); env.bootstrap(); env.emit({action="create"}); count=#env.packets
    env.map="template_map"
    assert(env.tick(1)==nil)
    env.respond(#env.requests,{ok=true,room=room(1,"READY")})
    assert(#env.packets==count and #env.connects()==0)
end)

test("404 dead room resets selection and returns to own-room discovery",function()
    local env=environment(); env.bootstrap(); create(env)
    action(env,"invite"); env.respond(#env.requests,{ok=true,invite_code="invite_old_12345"})
    env.emit({action="refresh"}); env.request("room")
    env.respond(#env.requests,{ok=false,error="room_not_found"},404)
    assert(env.state().room_id=="" and env.state().invite_code=="", "404 must discard the dead selected room")
    env.tick(5); env.request("rooms")
end)

test("401 invalidates cached browser capability before fresh authorization",function()
    local env=environment(); env.bootstrap()
    env.emit({action="refresh"})
    env.respond(#env.requests,{ok=false,error="lobby_identity_required"},401)
    assert(env.state().authenticated==false and env.state().error=="unauthenticated")
    assert(#env.invalidations==1 and env.invalidations[1].account==ACCOUNT
        and env.invalidations[1].session==env.session, "rejected auth token must be invalidated at its owner")
    local before=#env.requests
    env.emit({action="create"}); assert(#env.requests==before)
    env.tick(4); assert(#env.auth_requests==2)
    env.grant("pwa1_fictional_replacement_capability"); env.tick(4)
    assert(env.request("rooms").headers.Authorization=="Bearer pwa1_fictional_replacement_capability")
end)

test("non-JSON 401 still invalidates the rejected capability",function()
    local env=environment(); env.bootstrap(); env.emit({action="refresh"})
    env.requests[#env.requests].callback({StatusCode=401,Body="gateway authentication rejected"})
    assert(#env.invalidations==1 and env.state().authenticated==false,
        "an HTTP 401 must revoke authorization before attempting JSON decoding")
    local before=#env.requests
    env.emit({action="create"})
    assert(#env.requests==before, "unparseable 401 cannot leave the old token authorized")
end)

test("malformed room-list rows do not throw out of the asynchronous callback",function()
    for _,bad in ipairs({false,7,"invalid_room"}) do
        local env=environment(); env.bootstrap(); env.emit({action="refresh"})
        local ok=pcall(env.respond,#env.requests,{ok=true,rooms={bad}})
        assert(ok, "backend room-list data must not escape as a Lua callback exception")
        assert(env.state().room_id=="" and #env.connects()==0)
    end
end)

test("factory/send failures and malformed responses fail without parallel retries",function()
    for _,kind in ipairs({"factory_nil","factory_throws","send_false","send_throws"}) do
        local env=environment(); env.bootstrap(); env[kind]=true
        env.emit({action="create"})
        assert(env.state().error=="service_unavailable" and env.state().room_id=="")
    end
    local env=environment(); env.bootstrap(); env.emit({action="create"})
    env.requests[#env.requests].callback({StatusCode=200,Body="invalid fixture JSON"})
    assert(env.state().error=="service_unavailable")
    env.emit({action="create"})
    env.requests[#env.requests].callback({StatusCode=200,Body=string.rep("x",32769)})
    assert(env.state().room_id=="" and #env.connects()==0)
end)

test("successful connect is fixed endpoint/build/current room and never publishes credentials",function()
    local env=ready_connection()
    env.respond(#env.requests,ticket_response())
    local request=env.request("redeem")
    assert(request.data.room_id=="room_alpha_1234" and request.data.ticket==TICKET)
    env.respond(#env.requests,redeemed())
    local connections=env.connects()
    assert(#connections==1 and connections[1].player==env.players[0])
    local value=connections[1].payload
    assert(value.address=="127.0.0.1:27025" and value.match_id=="match_alpha_1234" and value.build_sha256==BUILD)
    local forbidden={token=true,ticket=true,lease_id=true,authorization=true,account_id=true,steam_id=true}
    local function safe(payload)
        for key,child in pairs(payload) do
            assert(not forbidden[tostring(key):lower()], "credential key leaked to Panorama")
            assert(child~=TOKEN and child~=TICKET and child~="fictional_private_lease", "secret value leaked to Panorama")
            if type(child)=="table" then safe(child) end
        end
    end
    for _,packet in ipairs(env.packets) do safe(packet.payload) end
    env.tick(5); env.request("room")
    assert(#env.connects()==1, "polling a connected match cannot issue another ticket automatically")
end)

test("client-selected or unpinned endpoint and changed build never connect",function()
    for _,address in ipairs({"203.0.113.5:27025","127.0.0.1:27025;quit","127.0.0.1:27015"}) do
        local env=ready_connection(); env.respond(#env.requests,ticket_response())
        env.respond(#env.requests,redeemed(address))
        assert(#env.connects()==0 and env.state().error=="service_unavailable")
    end
    local env=ready_connection(); env.respond(#env.requests,ticket_response(nil,string.rep("b",64)))
    assert(not ends(env.requests[#env.requests].url,"/redeem") and #env.connects()==0)
    env=ready_connection(); env.respond(#env.requests,ticket_response())
    env.respond(#env.requests,redeemed(nil,nil,string.rep("b",64)))
    assert(#env.connects()==0)
end)

test("different ticket or redeemed match cannot cross the selected room",function()
    local env=ready_connection(); local before=#env.requests
    env.respond(before,ticket_response("match_other_1234"))
    assert(#env.requests==before and #env.connects()==0, "ticket match must equal the selected room match")
    env=ready_connection(); env.respond(#env.requests,ticket_response())
    env.respond(#env.requests,redeemed(nil,"match_other_1234"))
    assert(#env.connects()==0, "redeemed match must equal ticket and selected room")
end)

test("room replacement in either response cannot race into an obsolete connection",function()
    local env=ready_connection(); local before=#env.requests
    local body=ticket_response()
    body.room=room(8,"READY",false,"room_beta_12345","match_beta_12345")
    env.respond(before,body)
    assert(#env.requests==before and #env.connects()==0,
        "ticket completion must recheck the current room after any room update")
    env=ready_connection(); env.respond(#env.requests,ticket_response())
    body=redeemed(); body.room=room(8,"READY",false,"room_beta_12345","match_beta_12345")
    env.respond(#env.requests,body)
    assert(#env.connects()==0, "redeem completion must recheck the current room after any room update")
end)

test("late redeem after timeout and reauthorization cannot launch an obsolete match",function()
    local env=ready_connection(); env.respond(#env.requests,ticket_response())
    local old=#env.requests
    env.tick(16)
    local fresh=#env.requests
    assert(fresh==old+1)
    env.respond(old,redeemed())
    assert(#env.connects()==0, "expired HTTP generation cannot emit client connect")
    env.respond(fresh,ticket_response())
    env.respond(#env.requests,redeemed())
    assert(#env.connects()==1)
end)

for _,failure in ipairs(failures) do print("HOSTED_LOBBY_TEST_FAIL: "..failure) end
assert(#failures==0,tostring(#failures).." hosted lobby behavioral tests failed")
print("HOSTED_LOBBY_TEST_PASS: "..passed.." cases; real admission; source binding; CAS; async/timeout/404/401; pinned connections; no credential events")
