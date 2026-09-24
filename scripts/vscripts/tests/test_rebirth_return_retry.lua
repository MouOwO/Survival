-- Integrated shop -> rebirth spawn -> F2 -> retry lifecycle, with engine-only
-- stubs. Run from the addon root with Lua 5.1+.
package.path = "scripts/vscripts/?.lua;" .. package.path
local bus = require("core/event_bus")
local events = require("core/events")
local scheduler = require("core/scheduler")
local now, serial, charges, completions, room_exits = 100, 100, 0, 0, 0
local heroes, created, progression, notices = {}, {}, { [0] = 0, [1] = 1 }, {}
local blocked, failed_teleport = false, false
local noop = function() end
local original_print = print
print = function(value, ...)
    assert(not tostring(value):find("handler error", 1, true), value)
    assert(not tostring(value):find("task failed", 1, true), value)
    original_print(value, ...)
end
local vector = {}
vector.__add = function(a, b) return setmetatable({ x=a.x+b.x, y=a.y+b.y, z=a.z+b.z }, vector) end
Vector = function(x,y,z) return setmetatable({x=x,y=y,z=z or 0}, vector) end
math.atan2 = math.atan2 or function(y,x) return math.atan(y,x) end
GameRules = { GetGameTime = function() return now end }
DOTA_TEAM_GOODGUYS, DOTA_TEAM_BADGUYS, DOTA_TEAM_NEUTRALS = 2,3,4
DOTA_UNIT_TARGET_TEAM_BOTH, DOTA_UNIT_TARGET_HERO, DOTA_UNIT_TARGET_BASIC = 0,1,2
DOTA_UNIT_TARGET_FLAG_NONE, FIND_ANY_ORDER = 0,0
PlayerResource = {
    IsValidPlayerID = function(_,id) return id == 0 or id == 1 end,
    GetTeam = function(_,id) return 2 + id end,
    GetPlayer = function() return nil end,
    GetSelectedHeroEntity = function(_,id) return heroes[id] end,
}
local function unit(owner)
    serial = serial + 1
    local u = { id=serial, owner=owner or -1, origin=Vector(0,0,0), alive=true }
    function u:IsNull() return self.removed == true end
    function u:IsAlive() return self.alive end
    function u:entindex() return self.id end
    function u:GetAbsOrigin() return self.origin end
    function u:SetAbsOrigin(p) self.origin=p end
    function u:GetForwardVector() return Vector(1,0,0) end
    function u:GetPlayerOwnerID() return self.owner end
    function u:GetTeamNumber() return 2 + math.max(0,self.owner) end
    function u:GetHealth() return 1000 end
    function u:HasModifier() return true end
    for _, name in ipairs({"Stop", "SetModel", "SetOriginalModel", "SetModelScale",
        "SetBaseMaxHealth", "SetMaxHealth", "SetHealth", "SetBaseDamageMin",
        "SetBaseDamageMax", "SetPhysicalArmorBaseValue", "SetBaseAttackTime",
        "Script_SetAttackRange", "SetForwardVector"}) do u[name] = noop end
    return u
end
heroes[0], heroes[1] = unit(0), unit(1)
local city = unit(0)
city.origin = Vector(8000,4000,0)
Entities = { FindByName = function(_,_,name)
    local marker = unit()
    marker.origin = Vector(-6000, tonumber(name:match("(%d+)_")) or 0, 0)
    return marker
end }
CreateUnitByName = function(_, origin)
    local u=unit(); u.origin=origin; created[#created+1]=u; return u
end
FindClearSpaceForUnit = function(u,p) u.origin=p end
UTIL_Remove = function(u)
    -- Simulate a reentrant engine death event before the handle becomes null.
    u.alive=false
    bus.emit(events.ENGINE_ENTITY_KILLED, {victim=u, attacker=heroes[0]})
    u.removed=true
end
GridNav = {IsBlocked=function() return blocked end, IsTraversable=function() return not blocked end}
GetGroundHeight = function() return 0 end
FindUnitsInRadius = function() return {} end
ProjectileManager = {ProjectileDodge=noop}
package.loaded["systems/building_system"] = {main_city_for_team=function() return city end}
package.loaded["systems/destination_validation_service"] = {
    validate=function() return not blocked, "destination_not_traversable" end,
    teleport=function(u,p)
        if failed_teleport then return false, "destination_not_traversable" end
        u.origin=p; return true
    end,
}
package.loaded["systems/challenge_session_service"] = {handles=function() return false end}
package.loaded["systems/monster_hero_visual_service"] = {apply=noop, clear=noop, on_death=noop}
package.loaded["systems/monster_hull_scale"] = {apply=noop}
package.loaded["systems/monster_navigation_policy"] = {apply=noop}
package.loaded["debug/technology_cheat_handler"] = {register=noop}
local spawn = require("systems/monster_spawn_service")
local shop = require("systems/shop_system")
local home = require("systems/hero_return_home_service")
local catalog = require("systems/shop_catalog")
bus.reset(); scheduler.clear(); spawn.init(); shop.init()
bus.handle_request(events.WAVE_STATE_GET_REQUEST, function() return {ok=true,difficulty_id="N1"} end)
bus.handle_request(events.HERO_SUMMON_GET_REQUEST, function(p) return {unit=heroes[p.player_id]} end)
bus.handle_request(events.HERO_SUMMON_SNAPSHOT_REQUEST, function() return {snapshot={hero_summoned=1}} end)
bus.handle_request(events.HERO_PROGRESSION_GET_REQUEST, function(p) return {snapshot={rebirth_level=progression[p.player_id]}} end)
bus.handle_request(events.RESOURCE_GET_REQUEST, function() return {wood=1000000,gold=1000000} end)
bus.handle_request(events.RESOURCE_TRY_SPEND_REQUEST, function() charges=charges+1; return {ok=true} end)
bus.handle_request(events.RESOURCE_ADD_REQUEST, function() error("unexpected refund") end)
bus.handle_request(events.TRAINING_ROOM_EXIT_REQUEST, function() room_exits=room_exits+1; return {ok=true} end)
bus.subscribe(events.MONSTER_ENCOUNTER_COMPLETED, function(p)
    completions=completions+1
    progression[p.player_id]=p.encounter.rebirth_level
end)
bus.subscribe(events.UI_NOTIFICATION, function(p) notices[#notices+1]=p.message end)
for id=0,1 do
    bus.emit(events.BUILDING_CREATED, {building_id="main_city",team=2+id,player_id=id,level=3})
    bus.emit(events.BUILDING_CREATED, {building_id="hero_altar",team=2+id,player_id=id,level=1})
end
local function request(name,p)
    local result,err=bus.request(name,p)
    assert(result, tostring(err)); return result
end
local function buy(id,level,token)
    return request(events.SHOP_PURCHASE_REQUEST, {player_id=id,
        entry_id=string.format("shop_rebirth_challenge_%02d",level),request_id=token})
end
local function status(id,level)
    return request(events.MONSTER_ENCOUNTER_QUERY_REQUEST, {player_id=id,
        encounter_id=string.format("encounter_rebirth_%02d",level)})
end
local function view(id)
    return request(events.SHOP_OPEN_REQUEST,{player_id=id,mode="challenge"}).snapshot
end
local function entry(snapshot,level)
    for _, row in ipairs(snapshot.entries) do
        if row.entry_id == string.format("shop_rebirth_challenge_%02d",level) then return row end
    end
    error("missing projected rebirth entry")
end
local function advance(seconds)
    now=now+seconds; scheduler.think()
end

view(0); view(1)
local started = buy(0,1,"attempt1")
assert(started.ok, started.error)
local first = created[#created]
assert(status(0,1).active and charges==1)
assert(buy(0,1,"attempt1").ok and charges==1, "duplicate purchase charged twice")
assert(buy(1,2,"other_player").ok)
local other = created[#created]
assert(status(1,2).active)

-- Neither an unsafe home nor an engine teleport failure may cancel a fight.
blocked=true
assert(not home.return_unit(heroes[0],0).ok)
assert(status(0,1).active and not first.removed and room_exits==0)
blocked=false; failed_teleport=true
assert(not home.return_unit(heroes[0],0).ok)
assert(status(0,1).active and not first.removed and room_exits==0)
failed_teleport=false
assert(home.return_unit(heroes[0],0).ok)
assert(room_exits==1 and first.removed and not status(0,1).active)
assert(completions==0 and progression[0]==0, "F2/removal granted rebirth reward")
assert(not other.removed and status(1,2).active, "F2 removed another player's boss")
assert(status(0,1).retry_cooldown_remaining==2)
local row=entry(view(0),1)
assert(row.purchasable==0 and row.purchase_cooldown_remaining==2, "UI must display retry cooldown")
assert(row.purchase_limit==0 and row.purchase_cooldown_seconds==2,
    "retry cooldown must not be presented as permanently sold out")
local before=charges
assert(not buy(0,1,"too_soon").ok and charges==before)
assert(not request(events.MONSTER_ENCOUNTER_START_REQUEST,
    {player_id=0,encounter_id="encounter_rebirth_01"}).ok, "direct start bypassed retry cooldown")
advance(1.9)
assert(not buy(0,1,"still_waiting").ok and charges==before)
advance(0.1)
assert(entry(view(0),1).purchasable==1, "attempt count permanently locked challenge")
assert(buy(0,1,"attempt2").ok and charges==before+1)
local second=created[#created]
assert(second~=first and status(0,1).active, "retry must create a fresh boss")

-- Hero death is also an unsuccessful attempt; no stale boss or reward remains.
heroes[0].alive=false
bus.emit(events.ENGINE_ENTITY_KILLED,{victim=heroes[0],attacker=second})
assert(second.removed and not status(0,1).active and completions==0)
assert(status(0,1).retry_cooldown_remaining==2)
heroes[0].alive=true; advance(2)
assert(buy(0,1,"attempt3").ok)
local winner=created[#created]
winner.alive=false
bus.emit(events.ENGINE_ENTITY_KILLED,{victim=winner,attacker=heroes[0]})
assert(completions==1 and progression[0]==1)
assert(home.return_unit(heroes[0],0).ok)
assert(status(0,1).retry_cooldown_remaining==0, "successful completion started failure cooldown")
bus.emit(events.ENGINE_ENTITY_KILLED,{victim=winner,attacker=heroes[0]})
assert(completions==1, "duplicate death granted completion twice")
local result=buy(0,1,"repeat_completed")
assert(not result.ok and result.error=="该转职挑战已完成", "completed rebirth became repeatable")
assert(status(1,2).active and not other.removed)

-- Non-challenge purchases keep their configured one-time limit.
local evaluate=require("systems/shop_condition_evaluator").evaluate
local ok,reason=evaluate(0,{entryid="once",purchase_limit=1,contenttype="item"},
    {purchased_count={[0]={once=1}},resources={}})
assert(not ok and reason=="已达到购买上限")
print("REBIRTH_RETURN_RETRY_PASS: F2/death, 2s retry, UI cooldown, player isolation, idempotency and one-time completion")
