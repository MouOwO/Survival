package.path="scripts/vscripts/?.lua;"..package.path
local rules=require("config/challenge_runtime_rules")
local members=require("config/generated/encounter_members")
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
