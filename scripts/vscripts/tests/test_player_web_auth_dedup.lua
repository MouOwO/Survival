-- Real module; only engine/HTTP/account fixture seams are deterministic.
-- No native interaction, online request, credentials or account transaction.
local f=assert(io.open("scripts/vscripts/tests/test_player_web_auth.lua","rb"))
local original=f:read("*a");f:close()
local marker='local web = require("systems/player_web_auth")'
local prefix=original:sub(1,assert(original:find(marker,1,true))-1)
local body=[=[
local web=assert(loadfile(arg[1]or"scripts/vscripts/systems/player_web_auth.lua"))()
local native_print,public_markers,request_markers=print,{},{ }
local explicit_request_pending=false
local failed_native_attempts=0
print=function(value)
 if value:find("[PLAYER_WEB_AUTH_REQUEST]",1,true)==1 then
  assert(value:match("^%[PLAYER_WEB_AUTH_REQUEST%] accepted=1 generation=%d+ slot=%d+ mode=state_change$")
   or value:match("^%[PLAYER_WEB_AUTH_REQUEST%] accepted=1 generation=%d+ slot=%d+ mode=explicit_snapshot$"),"request marker leaked extra fields")
  request_markers[#request_markers+1]=value
  if value:find("mode=explicit_snapshot",1,true)then explicit_request_pending=true end
 elseif value:find("[PLAYER_WEB_AUTH_PUBLIC]",1,true)==1 then
  assert(value:match("^%[PLAYER_WEB_AUTH_PUBLIC%] reason=state_change status=%a+$")
   or value:match("^%[PLAYER_WEB_AUTH_PUBLIC%] reason=explicit_snapshot status=%a+$"),"public marker leaked extra fields")
  local status=value:match(" status=(%a+)$")
  assert(({requesting=true,pending=true,approved=true,failed=true,expired=true})[status],"public marker status outside safe enum")
  if value:find("reason=explicit_snapshot",1,true)then
   assert(explicit_request_pending,"explicit snapshot lacks actual accepted UI request boundary")
   explicit_request_pending=false
  end
  public_markers[#public_markers+1]=value
 else native_print(value)end
end
local checks=0
local function check(v,why)assert(v,why);checks=checks+1 end
local successes,failures=0,0
local function failure()failures=failures+1 end
local function success()successes=successes+1 end
local function resolve()web.resolve("1001",session,success,failure)end
local function reply(index,value,status)requests[index].complete({StatusCode=status or 200,Body=json.encode(value)})end
local function pending(code)
 code=code or"ABCD2345"
 return {ok=true,status="pending",device_code="device_fixture_abcdefghijklmnopqrstuvwxyz",
  user_code=code,verification_uri=config.base_url.."/authorize?code="..code,expires_in=600,poll_interval=3}
end
local function approved()
 return{ok=true,status="approved",account_id="1001",match_session_id=session,access_token="pwa1_"..string.rep("a",64),expires_in=14400}
end
local function explicit(payload,source)
 listeners.survival_player_web_auth_request(source or 200,payload or{session_id=session})
end
web.init(session);resolve()
check(#requests==1 and #events==1 and events[1].body.status=="requesting","initial requesting exactly once")
local cold_markers=#request_markers
for _=1,1000 do explicit()end
check(#requests==1 and #events==1 and #request_markers==cold_markers,"successful automatic requesting state coalesces an immediate second UI component")
for _=1,1000 do resolve()end
check(#requests==1 and #events==1,"1000 inflight resolver repeats must send zero duplicate snapshots")
reply(1,pending())
check(#events==2 and events[2].body.status=="pending","initial pending exactly once")
local transition_markers=#request_markers
for _=1,1000 do explicit()end
check(#events==2 and #request_markers==transition_markers,"new pending state sends immediately but its same-clock explicit replay is suppressed")
for _,stamp in ipairs({0.25,0.75,1.25,2.75})do clock=stamp;resolve()end
check(#events==2 and #requests==1,"expiry countdown changes are not public state changes or early HTTP polls")
clock=3;resolve();check(#requests==2,"original 3s HTTP poll deadline retained")
reply(2,{ok=true,status="pending"})
clock=6;resolve();check(#requests==3,"second real authorization poll remains on deadline")
reply(3,{ok=true,status="pending"})
check(#events==2,"two HTTP pending receipts do not repeat the unchanged private DTO")
-- A new listener can explicitly recover the retained current snapshot.
clock=6.25;explicit()
check(#events==3 and events[3].body.status=="pending"and events[3].body.expires_in<600,"late subscriber explicit snapshot recovery")
for _=1,1000 do explicit()end
check(#events==3 and #requests==3,"same-second explicit request burst coalesces with zero extra HTTP")
clock=7.5;explicit()
check(#events==4 and #requests==3,"later explicit recovery remains available and bounded")
local before=#events
player(1,1001);clock=8.75;explicit()
check(#events==before,"duplicate account binding rejection cannot be bypassed by explicit snapshot recovery")
player(1,1002)
explicit({session_id="wrong_match"});explicit({session_id=session,PlayerID=0,account_id="1001"},999)
check(#events==before,"wrong world and invalid source never bypass identity admission")
clock=9;resolve();check(#requests==4,"approval poll remains on original deadline")
reply(4,approved())
check(#events==5 and events[5].body.status=="approved"and successes==1,"approved transition publishes immediately, outside explicit debounce")
for _=1,1000 do resolve()end
check(#requests==4 and #events==5,"authorized account cache causes zero HTTP or native repeats")
authenticated[0]=true;explicit();check(#events==5,"already authenticated client cannot reopen private auth stream")
authenticated[0]=false
-- World reset discards memo and invalidates all old asynchronous callbacks.
session="web_auth_fixture_match_2";web.init(session);clock=0;resolve()
check(#events==6 and events[6].body.status=="requesting","new world initial snapshot is not suppressed by old memo")
local old_request=#requests
session="web_auth_fixture_match_3";web.init(session);resolve()
local new_request=#requests;before=#events
reply(old_request,pending())
check(#events==before and #requests==new_request,"old world completion cannot publish into new world")
reply(new_request,pending());before=#events
-- A new native player handle in the same slot is a new private owner.
player(0,1001);resolve();local rebound=#requests
check(#events==before+1 and events[#events].body.status=="requesting","same-slot player-handle replacement resets memo")
before=#events;reply(new_request,pending("OTHER234"))
check(#events==before,"replaced player callback is inert")
reply(rebound,pending("FRESH234"));before=#events
clock=601;resolve()
check(#events==before+1 and events[#events].body.status=="expired","expiry emits immediately")
resolve();local rotated=#requests
check(events[#events].body.status=="requesting","expiry recovery uses unchanged real authorization state machine")
reply(rotated,pending("NEWC2345"))
check(events[#events].body.status=="pending"and events[#events].body.user_code=="NEWC2345","new approval code publishes immediately")
-- Safe diagnostic changes are semantic state and must stay observable.
session="web_auth_fixture_match_4";web.init(session);clock=0;resolve();local failed_request=#requests
reply(failed_request,{},500);before=#events
check(events[#events].body.status=="failed"and events[#events].body.diagnostic_status==500,"safe HTTP failure publishes immediately")
clock=0.5;resolve();check(#events==before,"unchanged failure during start cooldown does not resend")
clock=3;resolve();reply(#requests,{},502)
check(events[#events].body.status=="failed"and events[#events].body.diagnostic_status==502,"changed diagnostic status publishes immediately")
-- Snapshot reply listener still enforces admission and source identity.
admitted=true;before=#events;explicit();check(#events==before,"completed admission rejects private UI reopening")
-- The real startup caller retries on five-second boundaries. Native send
-- deduplication must not postpone those HTTP polls or the approval callback.
admitted=false;session="web_auth_fixture_match_5";web.init(session);clock=0
resolve();reply(#requests,pending());local pending_events=#events
for _,stamp in ipairs({5,10})do
 clock=stamp;local count=#requests;resolve()
 check(#requests==count+1,"5s startup retry must submit its real authorization poll immediately")
 reply(#requests,{ok=true,status="pending"})
end
check(#events==pending_events,"5s HTTP pending receipts must not resend private countdown data")
clock=15;local success_before=successes;resolve();reply(#requests,approved())
check(successes==success_before+1 and events[#events].body.status=="approved","15s approval immediately resumes the waiting caller")
-- A first UI input may cause a new state rather than a replay. Its accepted
-- ordinal must be recorded so a later replay cannot masquerade as bootstrap.
session="web_auth_fixture_match_6";web.init(session);clock=0
local first_request=#request_markers+1;before=#events;explicit()
check(#events==before+1 and #request_markers==first_request
 and request_markers[first_request]:find("mode=state_change",1,true),"first UI request state change must record its input ordinal")
reply(#requests,pending());clock=2;before=#events;explicit()
check(#events==before+1 and #request_markers==first_request+1
 and request_markers[first_request+1]:find("mode=explicit_snapshot",1,true),"later snapshot must count as second accepted input, never cold bootstrap")
local accepted=#request_markers;before=#events
for _=1,1000 do explicit()end
check(#events==before and #request_markers==accepted,"debounced stable inputs must not print accepted markers")
-- A thrown native send cannot commit a memo or consume the recovery allowance.
clock=4;local native_send=CustomGameEventManager.Send_ServerToPlayer
CustomGameEventManager.Send_ServerToPlayer=function()error("fixture_native_send_failed")end
local ok=pcall(explicit);failed_native_attempts=failed_native_attempts+1
CustomGameEventManager.Send_ServerToPlayer=native_send
check(not ok and #events==before,"native send failure must not fabricate delivery")
explicit();check(#events==before+1,"same-clock recovery is still allowed after native send failure")
-- Complete the synthetic in-flight poll before simulating a much later UI
-- refresh. This models the real pending response rather than a timed-out poll.
reply(#requests,{ok=true,status="pending"})
clock=133;before=#events;local requests_before_late=#requests
explicit()
check(#events==before+1 and events[#events].body.status=="pending"and events[#events].body.expires_in>0,"129-second later genuine subscriber snapshot remains available")
check(#requests==requests_before_late+1,"late explicit recovery preserves the overdue real authorization poll")
-- A failed first state-change send also leaves the same-clock allowance free.
session="web_auth_fixture_match_7";web.init(session);clock=0;before=#events
CustomGameEventManager.Send_ServerToPlayer=function()error("fixture_initial_native_send_failed")end
ok=pcall(resolve);failed_native_attempts=failed_native_attempts+1
CustomGameEventManager.Send_ServerToPlayer=native_send
check(not ok and #events==before,"initial state-change send failure cannot fabricate delivery or memo")
explicit()
check(#events==before+1 and events[#events].body.status=="requesting","same-clock retry remains available after a failed state-change send")
local recovered_markers=#request_markers;explicit()
check(#events==before+1 and #request_markers==recovered_markers,"successful recovered state then coalesces immediate second UI replay")
check(#public_markers==#events+failed_native_attempts,"one sparse safe marker per actual native send attempt")
local explicit_markers=0;for _,value in ipairs(public_markers)do if value:find("reason=explicit_snapshot",1,true)then explicit_markers=explicit_markers+1 end end
local accepted_snapshots=0;for _,value in ipairs(request_markers)do if value:find("mode=explicit_snapshot",1,true)then accepted_snapshots=accepted_snapshots+1 end end
check(explicit_markers==accepted_snapshots and not explicit_request_pending,"accepted explicit inputs must map one-to-one to snapshot attempts")
print=native_print
print("PLAYER_WEB_AUTH_DEDUP_PASS checks="..checks.." fixed-tuple O(1); stable resolver1000=0sends; explicit burst1000=0extra sends; original HTTP poll deadlines preserved; all online/native/transaction operations0")
]=]
assert(loadstring(prefix.."\n"..body,"@real_player_web_auth_dedup"))()
