local count=0
local function check(value) count=count+1;assert(value,"check "..count) end
local config={enabled=true,expected_map="ws4_lobby",match_build_sha256=string.rep("a",64),connect_addresses={"127.0.0.1:27025"}}
local map,server,client="ws4_lobby",false,true
local commands,listener={},nil
local env=setmetatable({},{__index=_G});env._G=env
env.require=function(name) check(name=="config/hosted_lobby");return config end
env.GetMapName=function() return map end
env.IsServer=function() return server end;env.IsClient=function() return client end
env.ListenToGameEvent=function(name,callback) check(name=="survival_lobby_connect_local");listener=callback end
env.SendToConsole=function(command) commands[#commands+1]=command end
env.print=function() end
local chunk=assert(loadfile("scripts/vscripts/systems/hosted_lobby_client.lua"));setfenv(chunk,env)
local module=chunk()
check(module.init() and type(listener)=="function")
local function event(address,match) return {address=address,match_id=match or "match_test_1",build_sha256=config.match_build_sha256} end
for _,address in ipairs({"127.0.0.1:27025;quit","127.0.0.1:27025\nquit","evil.com:27025","127.00.0.1:27025",
    "127.0.0.1:027025","256.0.0.1:27025","127.0.0.1:1023","127.0.0.1:65536","26.34.7.221:27015"}) do
    check(not module.connect(event(address)))
end
local bad=event("127.0.0.1:27025");bad.build_sha256=string.rep("b",64);check(not module.connect(bad))
for _,value in ipairs({";quit","short","evil\nquit"}) do check(not module.connect(event("127.0.0.1:27025",value))) end
check(#commands==0)
map="template_map";check(not module.connect(event("127.0.0.1:27025")))
map="ws4_lobby";server=true;check(not module.connect(event("127.0.0.1:27025")))
server=false;config.enabled=false;check(not module.connect(event("127.0.0.1:27025")))
config.enabled=true;check(module.connect(event("127.0.0.1:27025")))
check(#commands==1 and commands[1]=="connect 127.0.0.1:27025")
check(not module.connect(event("127.0.0.1:27025")) and #commands==1)
env.SendToConsole=function(command) commands[#commands+1]=command;error("native failure") end
check(not module.connect(event("127.0.0.1:27025","match_test_2")))
check(not module.connect(event("127.0.0.1:27025","match_test_2")) and #commands==2)
env.SendToConsole=function(command) commands[#commands+1]=command end
map="maps/ws4_lobby.vpk"
check(module.connect(event("127.0.0.1:27025","match_test_3")) and #commands==3)
for _,invalid in ipairs({"maps/../maps/ws4_lobby.vpk","prefix/maps/ws4_lobby.vpk","maps/ws4_lobby.vpk.bak"}) do
    map=invalid;check(not module.connect(event("127.0.0.1:27025","match_test_4")))
end
print("HOSTED_LOBBY_CLIENT_PASS: "..count.." checks, pinned endpoints/builds, injection rejection, duplicate/error latch")
