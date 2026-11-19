local path=arg[1]or'scripts/vscripts/core/test_access_policy.lua'
local ids={'76561198424163156','76561198845461206','76561198104787442','76561198974301984','76561198296534615'}
local checks=0
local function check(v,s)checks=checks+1;assert(v,s)end
local function fixture(public,channel)
 local config={enabled=true,public_release=public,allowed_steamids=ids}
 local s={account=336268888,walks=0,reads=0,valid=0,server=true}
 local e=setmetatable({},{__index=_G})
 e.pairs=function(v)if v==ids then s.walks=s.walks+1 end;return pairs(v)end
 e.require=function(name)if name=='config/test_access'then return config elseif name=='config/release_profile'then return{channel=channel or'production'}end;error(name)end
 e.IsServer=function()return s.server end;e.DisconnectClient=function()end
 e.PlayerResource={IsValidPlayerID=function(_,p)s.valid=s.valid+1;return p==0 end,GetSteamAccountID=function()s.reads=s.reads+1;return s.account end}
 local chunk=assert(loadfile(path));setfenv(chunk,e);return chunk(),s,config
end
local private,s=fixture(false);check(private.init());check(not private.allowed(0));check(not private.is_public())
for _,account in ipairs({463897428,885195478,144521714,1014036256,336268887})do s.account=account;check(private.allowed(0),'all five fallback identities remain valid')end
local public,p,c=fixture(true);check(not public.is_public());check(public.init());check(public.is_public());check(public.allowed(0),'sixth verified native identity admitted')
for _,a in ipairs({1,336268888,4294967295})do p.account=a;check(public.allowed(0))end
for _,a in ipairs({0,-1,4294967296,1.1,0/0,math.huge,'336268888'})do p.account=a;check(not public.allowed(0),'native account must be exact uint32')end
check(not public.allowed(256));check(not public.allowed(-1))
local fast,f=fixture(true);check(fast.init());for i=1,1000 do check(fast.allowed(0))end
check(f.walks==1 and f.reads==1000 and f.valid==1000,'stable O(1), one initial roster census')
local development=fixture(true,'development');check(not development.init())
local invalid=fixture('yes');check(not invalid.init())
local client,cs=fixture(true);cs.server=false;check(not client.init())
print('PUBLIC_PRODUCTION_ADMISSION_PASS checks='..checks..' stable1000_roster_walks=0 account_reads=1000 valid_reads=1000 no_HTTP_no_FPS')

print('PROJECTED_PRODUCTION_FIVE_ADMISSION_PASS public_and_private_compatibility=PASS')
