-- Real account/commerce policy modules, simulated engine I/O only.
-- Initialization: A<=5 identities *17 digits, O(A) space. Stable admission:
-- O(1), one account getter +one validity call; no repeated roster enumeration.
-- Existing native/commerce config checks grow only4->5 pure-Lua rows; no added
-- timers, scene queries, player-slot sweeps, network calls or native APIs.
local checks = 0
local function check(value, message) checks=checks+1;assert(value,message or "check failed") end
local function load(path,env) local f=assert(loadfile(path));setfenv(f,env);return f() end
local actual=dofile("scripts/vscripts/config/test_access.lua")
check(actual.enabled==true and #actual.allowed_steamids==5 and actual.allowed_steamids[5]=="76561198296534615")
local function copy(count)
    local ids={};for index=1,count or 5 do ids[index]=actual.allowed_steamids[index] end
    return {enabled=true,allowed_steamids=ids}
end
local function fixture(roster)
    local s={roster=roster or copy(),account=336268887,valid_reads=0,account_reads=0,roster_enumerations=0,kicks=0}
    local e=setmetatable({},{__index=_G});e._G=e;e.package={loaded={}}
    e.pairs=function(value) if value==s.roster.allowed_steamids then s.roster_enumerations=s.roster_enumerations+1 end;return pairs(value) end
    e.require=function(name) check(name=="config/test_access","access requires only server-owned config");return s.roster end
    e.IsServer=function()return true end
    e.DisconnectClient=function()s.kicks=s.kicks+1 end
    e.PlayerResource={IsValidPlayerID=function(_,id)s.valid_reads=s.valid_reads+1;return id==0 end,
        GetSteamAccountID=function()s.account_reads=s.account_reads+1;return s.account end}
    return e,s,load("scripts/vscripts/core/test_access_policy.lua",e)
end
local e,s,p=fixture();check(p.init())
for _,account in ipairs({463897428,885195478,144521714,1014036256,336268887}) do s.account=account;check(p.allowed(0),"all approved identities admitted") end
s.account=336268888;check(not p.enforce(0) and s.kicks==1,"adjacent unlisted identity refused")
s.account=0;check(not p.enforce(0) and s.kicks==1,"unknown Steam identity waits without new kick or grant")
e.PlayerResource.GetSteamAccountID=nil;e.PlayerResource.GetSteamID=function()return "76561198296534615" end
check(p.allowed(0),"new odd SteamID64 accepted as exact decimal string")
e.PlayerResource.GetSteamID=function()return tonumber("76561198296534615") end
check(not p.allowed(0),"rounded numeric SteamID64 cannot impersonate new tester")
local _,old,old_policy=fixture(copy(4));check(old_policy.init());old.account=336268887;check(not old_policy.allowed(0),"legacy four-account config remains restricted")
for _,change in ipairs({
    function(c)c.allowed_steamids[5]=c.allowed_steamids[4] end,
    function(c)c.allowed_steamids[4]=nil end,
    function(c)c.allowed_steamids[6]="76561198296534616" end,
    function(c)c.allowed_steamids[5]=tonumber(c.allowed_steamids[5]) end,
}) do local c=copy();change(c);local _,_,bad=fixture(c);check(not bad.init() and not bad.allowed(0),"invalid/duplicate/sparse/six-member config fails closed") end
local _,stable,fast=fixture();check(fast.init())
for _=1,500 do check(fast.allowed(0)) end
check(stable.roster_enumerations==1 and stable.account_reads==500 and stable.valid_reads==500,
    "stable indexed admission has exactly500 account+500 valid native calls and one initialization roster walk")

local function commerce(roster)
    local _,state,access=fixture(roster);check(access.init())
    local env=setmetatable({},{__index=_G});env.package={loaded={}}
    env.IsServer=function()return true end;env.IsInToolsMode=function()return false end;env.GetMapName=function()return "template_map" end
    local config={enabled=true,connection_helper=false,expected_map="template_map",base_url="https://pay.xiaofengnet.com/ws4-web"}
    env.require=function(name)
        if name=="core/release_policy" then return {is_production=function()return true end} end
        if name=="config/commerce_payment_access" then return config end
        if name=="config/player_web_auth" then return {enabled=true,base_url=config.base_url} end
        if name=="config/test_access" then return state.roster end
        if name=="core/test_access_policy" then return access end
        error("unexpected dependency: "..name)
    end
    env.CreateHTTPRequestScriptVM=function()error("policy must not authenticate, send HTTP or grant rewards") end
    return env,state,access,load("scripts/vscripts/core/commerce_release_policy.lua",env)
end
for _,count in ipairs({4,5}) do
    local env,state,access,policy=commerce(copy(count));check(policy.online_allowed(),"old/new approved roster retains existing production commerce policy")
    state.account=336268888;check(not access.allowed(0),"commerce release eligibility does not authenticate an unknown actor")
    env.package.loaded["debug/offline_logic_test"]={is_enabled=function()return true end}
    check(not policy.online_allowed(),"offline arena cannot gain online payment access")
end
local _,state,_,policy=commerce(copy());check(policy.online_allowed())
state.roster.allowed_steamids[5]="76561198296534616"
check(not policy.online_allowed(),"same-world roster mutation cannot replace the reviewed fingerprint")
print(string.format("PASS fifth-player policies: %d checks; stable500 account_calls=500 valid_calls=500 roster_walks=1; simulated counters, no native FPS/HTTP",checks))
