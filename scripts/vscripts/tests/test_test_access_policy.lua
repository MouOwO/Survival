-- Offline engine fixtures use synthetic identities, never deployment accounts.
package.path = "scripts/vscripts/?.lua;" .. package.path
local original = { IsServer=IsServer, DisconnectClient=DisconnectClient, PlayerResource=PlayerResource }
local original_rules, original_manager = GameRules, CustomGameEventManager
local config_name, module_name = "config/test_access", "core/test_access_policy"
local previous_config, previous_module = package.loaded[config_name], package.loaded[module_name]
local ids = { "76561197960265829", "76561197960265830", "76561197960265831", "76561197960265832" }
local checks = 0
local function check(value, message) checks = checks + 1 assert(value, message or "check failed") end
local kicks, account = {}, 101
local function load(config)
    package.loaded[config_name] = config or { enabled=true, allowed_steamids=ids }
    package.loaded[module_name] = nil
    kicks, account = {}, 101
    IsServer = function() return true end
    DisconnectClient = function(id, force) kicks[#kicks+1]={id=id,force=force} end
    PlayerResource = {
        IsValidPlayerID=function(_,id) return id>=0 and id<4 end,
        GetSteamAccountID=function() return account end,
        GetPlayer=function(_,id) return id==0 and {} or nil end,
    }
    return require(module_name)
end

local p = load()
check(p.init())
for value=101,104 do account=value check(p.allowed(0), "four configured accounts admitted") end
account=105 check(not p.enforce(0)) check(#kicks==1 and kicks[1].id==0 and kicks[1].force==true)
check(not p.enforce(0)) check(#kicks==1, "one pending kick per slot")
account=101 check(p.enforce(0), "allowed reconnect rechecks identity")
account=105 check(not p.enforce(0)) check(#kicks==2)
for _,value in ipairs({0,-1,0/0,math.huge,1.5,4294967296,"101"}) do
    account=value check(not p.allowed(0), "invalid account refused")
end
for _,value in ipairs({-1,0/0,math.huge,0.5,256,"0"}) do check(not p.allowed(value)) end
PlayerResource.GetSteamAccountID=function() error("engine failure") end
check(not p.allowed(0))
PlayerResource.GetSteamAccountID=nil
PlayerResource.GetSteamID=function() return ids[1] end
check(p.allowed(0), "string-only exact SteamID64 fallback")
PlayerResource.GetSteamID=function() return tonumber(ids[1]) end
check(not p.allowed(0), "rounded numeric SteamID64 refused")
PlayerResource.GetSteamID=function() return "" end check(not p.allowed(0))
PlayerResource.GetSteamID=nil check(not p.allowed(0))

for _,configuration in ipairs({
    {enabled=true,allowed_steamids={}},
    {enabled=true,allowed_steamids={ids[1],ids[1],ids[3],ids[4]}},
    {enabled=true,allowed_steamids={tonumber(ids[1]),ids[2],ids[3],ids[4]}},
    {enabled=true,allowed_steamids={"76561197960265728",ids[2],ids[3],ids[4]}},
    {enabled=true,allowed_steamids={"76561202255233024",ids[2],ids[3],ids[4]}},
    {enabled="true",allowed_steamids=ids},
    {allowed_steamids=ids},
}) do p=load(configuration) check(not p.init()) check(not p.allowed(0)) end

p=load() DisconnectClient=nil check(not p.init()) check(not p.allowed(0))
p=load() IsServer=function() return false end check(not p.init())
p=load() IsServer=function() error("engine failure") end check(not p.init())
p=load() PlayerResource.GetSteamAccountID=nil check(not p.init())
p=load() check(p.init()) DisconnectClient=function() error("kick delayed/failed") end
account=105 local admitted,reason=p.enforce(0) check(not admitted and reason=="test_access_disconnect_failed")

p=load() check(p.init()) account=105 check(p.enforce_connected()) check(#kicks==1)
p=load() check(p.init()) PlayerResource.GetPlayer=nil check(not p.enforce_connected())
p=load() check(p.init()) account=0 check(not p.enforce(0)) check(#kicks==0, "unknown Steam identity waits with closed gates")
account=101 check(p.enforce(0)) check(#kicks==0, "identity settling cannot enqueue a stale kick")
account=105 check(not p.enforce(0)) check(#kicks==1, "known nonmember is disconnected")

-- Neighbouring odd/even SteamID64 values would collapse under tonumber(64bit).
p=load({enabled=true,allowed_steamids={"76561197960265729","76561197960265730","76561202255233022","76561202255233023"}})
check(p.init())
for _,value in ipairs({1,2,4294967294,4294967295}) do account=value check(p.allowed(0)) end
account=3 check(not p.allowed(0), "no floating-point neighbour admission")

-- Exercise actual service entrypoints with a denied account while the engine
-- still exposes its player handle: a pending/failed kick cannot grant data.
p=load()
local module_backups = {}
local function replace(name, value)
    if not module_backups[name] then module_backups[name] = {package.loaded[name]} end
    package.loaded[name] = value
end
replace("core/scheduler", {every=function() end, cancel=function() end})
replace("core/logger", {info=function() end, warn=function() end})
replace("systems/player_entitlement_service", {replace_all=function() end})
replace("systems/player_profile_service", nil)
local bus = require("core/event_bus")
bus.reset()
GameRules = {GetGameModeEntity=function() return {} end, GetGameTime=function() return 10 end}
local requests, authenticated = {}, {}
local provider = {
    init=function() end,
    resolve_account_id=function() return tostring(account) end,
    fetch_snapshot=function(id,success,failure) requests[#requests+1]={id=id,success=success,failure=failure} end,
    authenticate=function(id,success,failure) authenticated[#authenticated+1]={id=id,success=success,failure=failure} end,
}
local profiles = require("systems/player_profile_service")
profiles.init({provider=provider})
local events=require("core/events")
local business_calls=0
for _,event in ipairs({events.RESOURCE_ADD_REQUEST,events.MONSTER_REWARD_GRANT_REQUEST,events.SHOP_PURCHASE_REQUEST}) do
    bus.handle_request(event,function() business_calls=business_calls+1 return {ok=true} end)
end
account=105
for _,event in ipairs({events.RESOURCE_ADD_REQUEST,events.MONSTER_REWARD_GRANT_REQUEST,events.SHOP_PURCHASE_REQUEST}) do
    check(bus.request(event,{player_id=0}).error=="test_access_denied")
end
check(business_calls==0, "reward/resource/purchase dispatch closes during kick delay")
account=101
for _,event in ipairs({events.RESOURCE_ADD_REQUEST,events.MONSTER_REWARD_GRANT_REQUEST,events.SHOP_PURCHASE_REQUEST}) do
    check(bus.request(event,{player_id=0}).ok)
end
check(business_calls==3, "allowed reward/resource/purchase paths stay functional")
account=105
check(bus.request(events.RESOURCE_ADD_REQUEST,{player_id=0}).error=="test_access_denied")
check(business_calls==3, "slot changing Steam account cannot retain request admission")
local world_calls=0
bus.handle_request("test_world_request",function() world_calls=world_calls+1 return {ok=true} end)
check(bus.request("test_world_request",{}).ok and world_calls==1, "actorless world requests are preserved")
check(bus.request("test_world_request","world-payload").ok and world_calls==2, "legacy actorless payload contract preserved")
bus.subscribe("test_world_cleanup",function() world_calls=world_calls+1 end)
bus.emit("test_world_cleanup",{player_id=0}) check(world_calls==3, "world cleanup emits remain untouched")
check(profiles.authenticate_player(0).error=="test_access_denied")
check(profiles.load_player(0).error=="test_access_denied")
check(profiles.refresh_player(0).error=="test_access_denied")
check(profiles.apply_snapshot(0,{}).error=="test_access_denied")
check(profiles.update_save_sections(0,{}).error=="test_access_denied")
check(#requests==0 and #authenticated==0, "denial precedes provider/HTTP")
account=101
check(profiles.load_player(0).pending and #requests==1)
account=105
local function snapshot()
    return {schema_version=1,account_id="101",revision=1,entitlements={},achievements={},public={},
        save={gameplay_stats={},content_inventory={}}}
end
requests[1].success(snapshot())
check(profiles.get_profile(0)==nil, "late successful snapshot denied after identity changes")
account=101
check(profiles.load_player(0).pending and #requests==2)
requests[2].success(snapshot())
check(profiles.get_profile(0)~=nil, "allowed profile still loads")
account=105
check(profiles.get_profile(0)==nil and profiles.get_account_profile(0)==nil)
check(profiles.get_public_profile(0)==nil and not profiles.is_loaded_for_account(0,"101"))
check(profiles.update_save_sections(0,{}).error=="test_access_denied", "cached save cannot be updated during kick delay")

replace("systems/multiplayer_player_service", nil)
local multiplayer = require("systems/multiplayer_player_service")
check(not multiplayer.mark_connected(0))
check(#multiplayer.participating_player_ids()==0, "denied player is never marked participating")

-- The real startup human predicate feeds roster discovery, authentication,
-- mode/difficulty selection, and profile release. Inspect its lexical closure
-- only in this offline test; no debug API is used by the runtime policy.
local function upvalue(fn, wanted)
    for index=1,100 do
        local name,value=debug.getupvalue(fn,index)
        if not name then break end
        if name==wanted then return value end
    end
    error("missing test upvalue "..wanted)
end
replace("systems/startup_asset_preload_service", {})
replace("systems/match_setup_service", {})
replace("systems/startup_loading_service", nil)
local startup = require("systems/startup_loading_service")
local human = upvalue(upvalue(startup.tick,"discover"),"human")
check(not human(0), "denied connected handle excluded from startup roster")
account=101 check(human(0), "allowed player remains discoverable")

-- Real UI listener dispatch must reject before any business request even if a
-- stale loading service still claims the slot is ready.
replace("systems/startup_loading_service", {is_player_ready=function() return true end})
for _,name in ipairs({"systems/building_system","ui/weapon_synthesis_snapshot_service",
    "ui/combat_stat_projection","config/asset_catalog","systems/hero_summon_projection",
    "systems/building_batch_upgrade_service","systems/gold_mine_batch_upgrade_service"}) do replace(name,{}) end
replace("config/tree_config", {unit_name="enemy_tree"})
replace("ui/ui_request_router", nil)
local listeners,draws={},0
CustomGameEventManager={RegisterListener=function(_,name,callback) listeners[name]=callback return name end,
    Send_ServerToPlayer=function() end}
bus.reset()
bus.handle_request(events.LOTTERY_DRAW_REQUEST,function() draws=draws+1 return {ok=true} end)
require("ui/ui_request_router").init()
account=105
listeners.ui_lottery_draw_request(200,{PlayerID=0,player_id=1,pool_id="map",count=1,request_id="denied"})
check(draws==0, "UI cannot draw while a denied client is waiting for disconnect")
for name,previous in pairs(module_backups) do package.loaded[name]=previous[1] end
bus.reset()

p=load({enabled=false,allowed_steamids={}})
IsServer=nil DisconnectClient=nil PlayerResource=nil
check(p.init()) check(not p.enabled()) check(p.allowed(nil)) check(p.enforce(nil)) check(p.enforce(0)) check(p.enforce_connected())
package.loaded["core/event_bus"]=nil
local development_bus=require("core/event_bus")
development_bus.handle_request("development_unchanged",function() return {ok=true} end)
check(development_bus.request("development_unchanged",{player_id="legacy actor"}).ok,
    "disabled test gate preserves existing request validation semantics")

IsServer,DisconnectClient,PlayerResource=original.IsServer,original.DisconnectClient,original.PlayerResource
GameRules,CustomGameEventManager=original_rules,original_manager
package.loaded[config_name],package.loaded[module_name]=previous_config,previous_module
print("test_test_access_policy: PASS checks=" .. checks)
