-- Test the actual projected3102 policy, with its old preview helper explicitly
-- false in production. This is logical engine-I/O simulation, not Steam login.
local path=assert(arg[1],"explicit projected policy source path required")
local ids={"76561198424163156","76561198845461206","76561198104787442","76561198974301984","76561198296534615"}
local checks=0
local function check(v,s) checks=checks+1;assert(v,s or "projected policy assertion") end
local function fixture(roster)
 local state={account=336268887,reads=0,valid=0,walks=0}
 local config={enabled=true,allowed_steamids=roster or ids}
 local env=setmetatable({},{__index=_G})
 env.pairs=function(value)if value==config.allowed_steamids then state.walks=state.walks+1 end;return pairs(value) end
 env.require=function(name)
  if name=="config/test_access" then return config end
  if name=="debug/offline_onboarding_test" then return {requested=function()return false end,is_human=function()error("production preview branch must stay inactive")end} end
  error("unexpected projected dependency "..name)
 end
 env.IsServer=function()return true end;env.DisconnectClient=function()end
 env.PlayerResource={IsValidPlayerID=function(_,p)state.valid=state.valid+1;return p==0 end,
  GetSteamAccountID=function()state.reads=state.reads+1;return state.account end}
 local chunk=assert(loadfile(path));setfenv(chunk,env)
 return chunk(),state
end
local policy,state=fixture();check(policy.init())
for _,account in ipairs({463897428,885195478,144521714,1014036256,336268887})do state.account=account;check(policy.allowed(0),"all five retain production admission")end
state.account=336268888;check(not policy.allowed(0),"unapproved adjacent sixth denied")
local fast,s=fixture();check(fast.init())
for _=1,500 do check(fast.allowed(0))end
check(s.walks==1 and s.reads==500 and s.valid==500,"stable original preview helper adds no roster/native scans")
local old={ids[1],ids[2],ids[3],ids[4]};local legacy,l=fixture(old);check(legacy.init());check(not legacy.allowed(0),"old list cannot grant added identity")
for _,bad in ipairs({{ids[1],ids[2],ids[3],ids[4],ids[4]},
 {[1]=ids[1],[2]=ids[2],[3]=ids[3],[5]=ids[5]},
 {ids[1],ids[2],ids[3],ids[4],ids[5],"76561198296534616"}})do local invalid=fixture(bad);check(not invalid.init() and not invalid.allowed(0))end
print("PROJECTED_PRODUCTION_FIVE_ADMISSION_PASS checks="..checks.." stable500 roster_walks=1 account_calls=500 valid_calls=500; simulated no HTTP/FPS")
