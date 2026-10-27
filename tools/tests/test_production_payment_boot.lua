-- Run against an actual frozen production root, with only the reviewed policy
-- file overlaid. No development-directory fallback or generic require mock.
local frozen=assert(arg[1], "frozen production root required")
local policy_path=arg[2] or "scripts/vscripts/core/commerce_release_policy.lua"
package.path=frozen.."/scripts/vscripts/?.lua"
package.cpath=""
local absent=frozen.."/scripts/vscripts/debug/offline_logic_test.lua"
assert(io.open(absent,"rb")==nil,"fixture must really omit the optional offline module")
local release=require("core/release_policy")
assert(release.is_production())
-- This reviewed file is present in the real signed inventory. Load its actual
-- implementation once; production init must never register its chat commands.
local commands=require("debug/payment_test_commands")
assert(type(commands.init)=="function")
local debug_loads=0
table.insert(package.loaders,1,function(name)
    if name:match("^debug/") then
        debug_loads=debug_loads+1
        error("production boot attempted optional debug loading: "..name)
    end
end)
assert(package.loaded["debug/offline_logic_test"]==nil)
assert(package.loaded["debug/mode_unlock_test"]==nil)

local tools=false
IsServer=function()return true end
IsInToolsMode=function()return tools end
GetMapName=function()return "template_map" end
DisconnectClient=function()error("an approved fixture player must not be kicked")end
PlayerResource={GetSteamAccountID=function()return 885195478 end}
local registered,connected,purchase_provider={},{},nil
CustomGameEventManager={RegisterListener=function(_,name,callback)registered[name]=callback end}
ListenToGameEvent=function(name,callback)
    assert(name~="player_chat","production must not register developer payment commands")
    connected[name]=callback
end
CreateHTTPRequestScriptVM=function()error("boot must not create a payment or profile HTTP request")end
-- Named game/storage boundaries only. The policy, release profile, four-account
-- gate, event bus, web auth and payment service come from real production files.
package.loaded["systems/player_profile_service"]={}
package.loaded["systems/commerce_service"]={init=function()end}
package.loaded["systems/archive_service"]={set_purchase_provider=function(value)purchase_provider=value end}
package.loaded["core/scheduler"]={after=function()end,cancel=function()end}
local policy=assert(loadfile(policy_path))()
package.loaded["core/commerce_release_policy"]=policy
tools=true
local payment=require("systems/payment_service")
payment.init()
assert(policy.real_money_allowed() and policy.online_allowed(),"the signed helper opt-in remains valid")
assert(not release.development_allowed())
tools=false
assert(policy.online_allowed(),"the ordinary production gate remains valid")
tools=true
assert(type(registered.survival_payment_request)=="function")
assert(type(registered.survival_payment_capability_request)=="function")
assert(type(purchase_provider.open_checkout)=="function")
assert(connected.player_connect_full and connected.player_disconnect)

local roster=require("config/test_access")
local fourth=roster.allowed_steamids[4]
roster.allowed_steamids[4]=nil
assert(not policy.online_allowed(),"production still requires all four approved accounts")
roster.allowed_steamids[4]=fourth
assert(policy.online_allowed())
for _,name in ipairs({"debug/offline_logic_test","debug/mode_unlock_test","systems/session_multiplayer_test"}) do
    package.loaded[name]={is_enabled=function()return true end}
    assert(not policy.real_money_allowed() and not policy.online_allowed(),"active local isolation must close cash")
    package.loaded[name]=nil
end
assert(policy.online_allowed() and not release.development_allowed())
assert(debug_loads==0,"no optional debug loader may be reached during production policy or payment.init")
assert(package.loaded["debug/offline_logic_test"]==nil)
print("PRODUCTION_PAYMENT_BOOT_PASS: actual frozen production files, missing offline module, all subsequent debug loaders rejected, real payment.init, four-account/helper gates and active local-isolation cash denial")
