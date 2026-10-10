package.path="scripts/vscripts/?.lua;"..package.path
local rules=require("config/challenge_runtime_rules")
local members=require("config/generated/encounter_members")
assert(rules.rebirth_retry_seconds==2, "failed one-time rebirth attempt is not a monster respawn")
for _,id in ipairs({"challenge_01","challenge_02","challenge_03","challenge_04","challenge_05",
 "challenge_06","challenge_07","challenge_08","challenge_09","challenge_10","challenge_11"}) do
 assert(rules.by_id[id].respawn_seconds==1, id .. " repeatable monster respawns after one second")
end
for _,id in ipairs({"challenge_06","challenge_07","challenge_11"}) do
 assert(rules.by_id[id].respawn_seconds==1)
 for _,m in ipairs(members.rows)do if m.encounter_id=="encounter_"..id then
  assert(m.respawn_seconds==1 and m.spawn_delay_seconds==1)
 end end
end
assert(require("config/molten_core_challenge_rules").respawn_seconds==1)
local f=assert(io.open("scripts/vscripts/systems/challenge_session_service.lua","rb"));local source=f:read("*a");f:close()
local first=assert(source:find("local function complete_session",1,true))
local last=assert(source:find("function M.handles",first,true))
local pending, activated, teleported, session = nil,0,0,nil
local env=setmetatable({
 scheduler={after=function(delay,fn)assert(delay==1);pending=fn end},
 owned_series_stage=function()return 1 end,
 abyss_cleared_stage_by_player={[0]=0},
 members_for=function()return {{member_id="old"},{member_id="next",spawn_mode="single"}}end,
 publish=function()end,
 DoUniqueString=function()return "generation"end,
 get_session=function()return session end,
 fill_initial=function()activated=activated+1;return true end,
 should_teleport_after_completion=function()return true end,
 teleport_to_current=function()teleported=teleported+1;return true end,
 block_session=function(_,err)error(err)end,
},{__index=_G})
local chunk=assert(loadstring(source:sub(first,last-1).."\nreturn complete_session"));setfenv(chunk,env);local complete=chunk()
local function fresh()session={status="active",player_id=0,encounter_id="encounter_challenge_11",challenge={challenge_id="challenge_11",repeatable=true,respawn_seconds=1,completion_limit=10}}end
fresh();complete(session)
assert(session.status=="waiting_respawn" and activated==0 and teleported==0)
pending();assert(session.status=="active" and activated==1 and teleported==1)
fresh();complete(session);session.status="cancelled";pending();assert(activated==1)
fresh();complete(session);session.generation="replaced";pending();assert(activated==1)
print("CHALLENGE_RESPAWN_PACING_PASS: 1s source data, staged abyss delay, teleport, cancellation/generation guards")

local encounters = require("config/generated/monster_encounters")
local practice_count = 0
for _, member in ipairs(members.rows) do
 if member.spawn_mode == "maintain_count" then
  local encounter = assert(encounters.by_id[member.encounter_id])
  assert(member.max_alive == 10 and member.spawn_count == 10 and member.respawn_seconds == 1)
  assert(encounter.max_alive == 10 and encounter.respawn_seconds == 1)
  practice_count = practice_count + 1
 end
end
assert(practice_count == 7, "all replenishing room types retain their configured monsters")

local limit_start = assert(source:find("local function maintain_count_limit", 1, true))
local limit_end = assert(source:find("local function fill_current", limit_start, true))
local respawn_start = assert(source:find("local function schedule_maintain_respawn", 1, true))
local respawn_end = assert(source:find("local function on_killed", respawn_start, true))
local clock, sessions, created, callbacks, notices, failures_remaining, spawn_attempts = 0, {}, 0, {}, {}, 0, 0
GameRules = {GetGameTime = function() return clock end}
local timer = require("core/scheduler")
local function key(player, encounter) return tostring(player) .. ":" .. encounter end
local spawn_environment = setmetatable({
 scheduler = {after = function(delay, fn, id)
  callbacks[#callbacks + 1] = fn
  return timer.after(delay, fn, id)
 end, cancel = timer.cancel},
 get_session = function(player, encounter) return sessions[key(player, encounter)] end,
 remove_dead = function(s) s.monster_count = #s.world end,
 spawn_member = function(s, member)
  spawn_attempts=spawn_attempts+1
  if failures_remaining>0 then
   failures_remaining=failures_remaining-1;return nil, "spawn_failed_for_test"
  end
  local cap = math.max(1, math.floor(math.min(10, member.max_alive or 10, s.encounter.max_alive or 10)))
  assert(#s.world < cap, "actual living population can never exceed its member/room cap")
  created = created + 1
  local unit = {spawned_at = clock, serial = created}
  s.world[#s.world + 1] = unit;s.monster_count = #s.world
  return unit
 end,
 publish = function(s, state, extra) notices[#notices + 1] = {session=s,state=state,extra=extra} end,
 block_session = function(s, err) s.status="blocked";s.blocked_reason=err end,
},{__index = _G})
local load_respawn = assert(loadstring(source:sub(limit_start, limit_end - 1)
 .. source:sub(respawn_start, respawn_end - 1) .. "\nreturn schedule_maintain_respawn"))
setfenv(load_respawn, spawn_environment)
local replenish = load_respawn()
local function tick(value) clock=value;timer.think() end
local function reset()
 timer.clear();clock=0;sessions={};created=0;callbacks={};notices={};failures_remaining=0;spawn_attempts=0
end
local function fresh(member, player, maximum)
 local s={player_id=player or 0,encounter_id=member.encounter_id,status="active",generation="generation-1",
  encounter={max_alive=maximum or 10},monsters={},world={},monster_count=0}
 local cap=math.max(1,math.floor(math.min(10, member.max_alive or 10,s.encounter.max_alive)))
 for index=1,cap do s.world[index]={original=true} end
 s.monster_count=#s.world;sessions[key(s.player_id,s.encounter_id)]=s
 return s
end
local function kill(s, member, count)
 for _=1,count or 1 do
  assert(#s.world>0,"cannot schedule a death without a live victim")
  table.remove(s.world,1);s.monster_count=#s.world
  replenish(s, member)
 end
end
local member=members.by_id.practice_wood
reset()
local current=fresh(member)
kill(current,member,10)
assert(timer.task_count()==1,"same-deadline deaths share one room timer while retaining separate tickets")
tick(0.999);assert(created==0 and #current.world==0,"no victim revives before its own one-second deadline")
tick(1);assert(created==10 and #current.world==10,
 "ten simultaneous deaths must all revive together one second later")
tick(2);assert(created==10 and #current.world==10,"completed tickets do not keep refilling a full room")
assert(timer.task_count()==0,"a full room with no pending death has no respawn timer")

reset();current=fresh(member)
kill(current,member)
tick(0.4);kill(current,member)
tick(0.999);assert(created==0)
tick(1);assert(created==1 and #current.world==9,"first death revives at death+1, not at second death+1")
tick(1.399);assert(created==1,"later death cannot inherit earlier death's respawn deadline")
tick(1.4);assert(created==2 and #current.world==10,"second death retains its independent deadline")
kill(current,member);tick(2.399);assert(created==2)
tick(2.4);assert(created==3,"a new death receives a new independent ticket")

-- A delayed scheduler tick consumes all due deaths together instead of
-- serializing already expired tickets into another one-second chain.
reset();current=fresh(member)
kill(current,member,4);tick(0.3);kill(current,member,3)
tick(5);assert(created==7 and #current.world==10,"all overdue deaths revive on the next server tick")
tick(6);assert(created==7)

-- Re-entry and external fills can repair the room first. Its old tickets
-- expire harmlessly and cannot resurrect a later death before its deadline.
reset();current=fresh(member);kill(current,member,10)
for index=1,10 do current.world[index]={external=true} end
current.monster_count=10
tick(1);assert(created==0 and #current.world==10,"delayed tickets recount the live population")
tick(1.1);kill(current,member)
tick(2.099);assert(created==0 and #current.world==9,"expired old tickets cannot revive a new death early")
tick(2.1);assert(created==1 and #current.world==10)

-- The old dead slot may be externally restored before its deadline. A new
-- victim then owns death+1 rather than inheriting that cancelled old slot.
reset();current=fresh(member);kill(current,member)
tick(0.2);current.world[#current.world+1]={external=true};current.monster_count=#current.world
assert(#current.world==10)
tick(0.4);kill(current,member)
tick(0.999);assert(created==0 and #current.world==9)
tick(1);assert(created==0 and #current.world==9,
 "external repair before the old deadline cannot lend that deadline to a new death")
assert(timer.task_count()==1,"the new death retains exactly one pending room wake-up")
tick(1.399);assert(created==0)
tick(1.4);assert(created==1 and #current.world==10 and timer.task_count()==0,
 "the replacement death revives at its own independent one-second deadline")

reset()
local smaller={encounter_id=member.encounter_id,member_id=member.member_id,max_alive=3,respawn_seconds=1}
current=fresh(smaller);kill(current,smaller,3);tick(1)
assert(created==3 and #current.world==3,"configured lower member cap is preserved")
reset();current=fresh(member,0,4);kill(current,member,4);tick(1)
assert(created==4 and #current.world==4,"configured lower encounter cap is preserved")

for _,reason in ipairs({"cancelled","replaced","generation_changed"}) do
 reset();current=fresh(member);kill(current,member,10)
 if reason=="cancelled" then current.status="cancelled"
 elseif reason=="replaced" then sessions[key(0,member.encounter_id)]={status="active"}
 else current.generation="generation-2" end
 tick(1);assert(created==0,reason.." session cannot consume old death tickets")
end
reset();current=fresh(member);kill(current,member,10);failures_remaining=1
tick(1)
assert(created==9 and #current.world==9 and current.status=="active" and spawn_attempts==10,
 "one failed death ticket cannot stop its nine simultaneous neighbours")
assert(timer.task_count()==1,"only the failed ticket retains a retry timer")
tick(1.999);assert(created==9 and spawn_attempts==10,"failed ticket retry still waits its full second")
tick(2)
assert(created==10 and #current.world==10 and spawn_attempts==11 and timer.task_count()==0,
 "only the failed monster retries at the next one-second deadline")

-- A callback that was already consumed cannot alter a fresh death's deadline
-- or replace the single pending room timer when invoked again.
reset();current=fresh(member);kill(current,member)
local old_callback=callbacks[1]
tick(1);assert(created==1 and timer.task_count()==0)
kill(current,member);assert(timer.task_count()==1)
old_callback()
assert(created==1 and timer.task_count()==1,"duplicate callback leaves the new death ticket and timer intact")
tick(1.999);assert(created==1)
tick(2);assert(created==2 and timer.task_count()==0)

-- Four independent player regions and all seven replenishing room types:
-- same-frame death deadlines must not collide through a shared scheduler ID.
reset()
local owned={}
for player=0,3 do
 for _,room in ipairs(members.rows) do if room.spawn_mode=="maintain_count" then
  local s=fresh(room,player);owned[#owned+1]=s;kill(s,room,10)
 end end
end
assert(#owned==28 and timer.task_count()==28,"one pending timer per player room, not per monster")
tick(0.999);assert(created==0)
tick(1);assert(created==280,"four owners x seven rooms x ten deaths revive together")
for _,s in ipairs(owned) do assert(#s.world==10 and s.monster_count==10) end
tick(2);assert(created==280 and timer.task_count()==0,"all player/room death tickets are consumed exactly once and rooms return idle")
print("PRACTICE_RESPAWN_LIMIT_PASS: seven room types, independent death+1s, AoE and staggered/overdue deaths, 4 owners, exact live caps, re-entry, cancellation/replacement/generation, independent failed-ticket retry, duplicate callbacks and idle timers")
