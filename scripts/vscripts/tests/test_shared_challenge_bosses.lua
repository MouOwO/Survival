-- Run with Lua 5.1 from the game addon root. Real service/registry, fake engine.
-- No Dota, network, database, rewards, saved profiles or real accounts are used.
package.path = "scripts/vscripts/?.lua;" .. package.path
local clock, serial, creates, removed, native_queries, force_writes = 0, 0, 0, 0, 0, 0
local teleport_ok = true
local units, heroes, stages, defeated, drops, rewards, emitted = {}, {}, {}, {}, {}, {}, {}
local subscriptions, requests = {}, {}
local vector = {}
vector.__index = vector
function Vector(x, y, z) return setmetatable({x=x or 0,y=y or 0,z=z or 0}, vector) end
function vector.__add(a,b) return Vector(a.x+b.x,a.y+b.y,a.z+b.z) end
function vector.__sub(a,b) return Vector(a.x-b.x,a.y-b.y,a.z-b.z) end
function vector.__mul(a,b) return Vector(a.x*b,a.y*b,a.z*b) end
function vector:Length2D() return math.sqrt(self.x*self.x+self.y*self.y) end
function vector:Normalized() local n=self:Length2D();return n>0 and self*(1/n) or Vector() end
GameRules = {GetGameTime=function() return clock end}
PlayerResource = {GetSelectedHeroEntity=function(_,p) return heroes[p] end,
    GetTeam=function() return 2 end}
DOTA_TEAM_BADGUYS, DOTA_TEAM_GOODGUYS, DOTA_TEAM_NOTEAM = 3, 2, 0
DOTA_UNIT_TARGET_TEAM_BOTH, DOTA_UNIT_TARGET_HERO, DOTA_UNIT_TARGET_BASIC = 3, 1, 2
DOTA_UNIT_TARGET_FLAG_NONE, FIND_ANY_ORDER = 0, 0
GridNav = {IsBlocked=function() return false end,IsTraversable=function() return true end}
GetGroundPosition=function(p) return p end
RandomInt=function(a) return a end
RandomFloat=function(a) return a end
DoUniqueString=function(prefix) serial=serial+1;return prefix..serial end
IsServer=function() return true end
class=function(base) return base or {} end
local function entity(index, owner)
    local unit={index=index,owner=owner,position=Vector(),modifiers={},live=true}
    function unit:IsNull() return self.removed == true end
    function unit:IsAlive() return self.live and not self.removed end
    function unit:entindex() return self.index end
    function unit:GetAbsOrigin() return self.position end
    function unit:GetPlayerOwnerID() return self.owner or -1 end
    function unit:GetTeamNumber() return self.owner ~= nil and 2 or 3 end
    function unit:GetName() return self.name end
    function unit:Stop() end
    function unit:AddNewModifier(_,_,name,params)
        local modifier={params=params,IsNull=function() return false end,Resume=function() return true end}
        self.modifiers[name]=modifier;return modifier
    end
    function unit:RemoveModifierByName(name) self.modifiers[name]=nil end
    function unit:HasModifier(name) return self.modifiers[name] ~= nil end
    function unit:FindModifierByName(name) return self.modifiers[name] end
    function unit:SetForceAttackTarget(target) self.forced=target;force_writes=force_writes+1 end
    function unit:MoveToPosition(position) self.position=position end
    for _,name in ipairs({"SetBaseMaxHealth","SetMaxHealth","SetHealth","SetBaseDamageMin",
        "SetBaseDamageMax","SetPhysicalArmorBaseValue","SetBaseAttackTime","SetModel",
        "SetOriginalModel","SetBaseMoveSpeed","Script_SetAttackRange","SetAcquisitionRange"}) do
        unit[name]=function() end
    end
    return unit
end
local next_index
CreateUnitByName=function(_,position)
    serial=serial+1;creates=creates+1
    local unit=entity(next_index or (100+serial));next_index=nil
    unit.position=position;units[#units+1]=unit;return unit
end
UTIL_Remove=function(unit) unit.removed=true;unit.live=false;removed=removed+1 end
FindClearSpaceForUnit=function(unit,p) unit.position=p end
FindUnitsInRadius=function() native_queries=native_queries+1;return {} end
EntIndexToHScript=function(index)
    native_queries=native_queries+1
    for _,unit in pairs(heroes) do if unit:entindex()==index then return unit end end
end
local markers={}
Entities={FindByName=function(_,_,name)
    if not name then return nil end
    if not markers[name] then markers[name]=entity(-1);markers[name].name=name end
    return markers[name]
end}
local events=require("core/events")
local bus={}
function bus.subscribe(name,callback)
    subscriptions[name]=subscriptions[name] or {}
    table.insert(subscriptions[name],callback)
end
function bus.emit(name,payload)
    emitted[name]=(emitted[name] or 0)+1
    for _,callback in ipairs(subscriptions[name] or {}) do callback(payload or {}) end
end
function bus.request(name,payload)
    if requests[name] then return requests[name](payload or {}) end
    return nil,"no_request_handler:"..tostring(name)
end
function bus.after_dispatch(_,callback) callback() end
package.loaded["core/event_bus"]=bus
package.loaded["systems/player_context_service"]={is_defeated=function(p) return defeated[p] == true end}
package.loaded["config/generated/weapon_definitions"]={rows={
    {content_id="abyss0",series_id="legend_abyss",stage=0},
    {content_id="abyss1",series_id="legend_abyss",stage=1},
    {content_id="abyss2",series_id="legend_abyss",stage=2},
}}
requests[events.CONTENT_INVENTORY_GET_REQUEST]=function(p)
    local counts={};if stages[p.player_id] ~= nil then counts["abyss"..stages[p.player_id]]=1 end
    return {ok=true,snapshot={counts=counts}}
end
requests[events.HERO_SUMMON_GET_REQUEST]=function(p) return {ok=true,unit=heroes[p.player_id]} end
requests[events.WAVE_STATE_GET_REQUEST]=function() return {ok=true,difficulty_id="N1",game_mode="standard"} end
requests[events.CHALLENGE_MATERIAL_DROP_REQUEST]=function(p)
    drops[#drops+1]=p;return {ok=true,material_retained=true}
end
requests[events.CHALLENGE_EQUIPMENT_REWARD_REQUEST]=function(p)
    rewards[#rewards+1]=p;return {ok=true}
end
package.loaded["config/challenge_combat_profile_config"]={resolve=function()
    return {health=100,attack=10,war3_armor=1,attack_speed=1}
end}
package.loaded["visual/model_scale"]={apply=function() end}
package.loaded["systems/monster_navigation_policy"]={apply=function() end}
package.loaded["systems/monster_hull_scale"]={apply=function() end}
package.loaded["systems/wave_monster_collision"]={profile=function() return {} end}
package.loaded["systems/challenge_monster_visual_service"]={apply=function() end,clear=function() end,on_death=function() end}
package.loaded["systems/monster_hero_visual_service"]={apply=function() return true end,clear=function() end,on_death=function() end}
package.loaded["systems/destination_validation_service"]={validate=function() return true end,
    teleport=function() return teleport_ok,teleport_ok and nil or "fixture_destination_rejected" end}
package.loaded["systems/hero_return_home_service"]={return_unit=function() return true end}
local scheduler=require("core/scheduler")
local shared=require("systems/shared_challenge_boss_registry")
local members=require("config/generated/encounter_members")
local service=require("systems/challenge_session_service")
for p=0,3 do heroes[p]=entity(10+p,p);stages[p]=0 end
service.init()
for p=0,3 do bus.emit(events.HERO_READY,{player_id=p,team=2}) end
for p=0,3 do bus.emit(events.HERO_SUMMONED,{player_id=p,team=2}) end
assert(creates==10,"four players and replacement notifications create one ten-boss preview set")
assert(native_queries==0,"shared spawn slots need no repeated radius query")
local function slot_for(id) return assert(shared.get(shared.key("encounter_challenge_11",members.by_id[id]))) end
local first=slot_for("boss_ten_sin_01").unit
local second=slot_for("boss_ten_sin_02").unit
local function start(p,id)
    return service.start({player_id=p,team=2,encounter_id="encounter_challenge_"..id,teleport_hero=false})
end
assert(start(0,"11").ok and start(1,"11").ok)
assert(creates==10 and shared.slot_for(first),"eligible players reuse the preview body")
assert(service.query("encounter_challenge_11",0).alive==1)
assert(service.query("encounter_challenge_11",1).alive==1)
stages[2]=1;assert(start(2,"11").ok)
assert(creates==10 and second:IsAlive(),"different personal stages use distinct fixed boss slots")
-- A real hero replacement updates only this player's subscribed target cache.
local replacement=entity(70,0);heroes[0]=replacement
bus.emit(events.HERO_SUMMONED,{player_id=0,team=2})
local seen={}
for _,hero in pairs(slot_for("boss_ten_sin_01").participants) do seen[hero]=true end
assert(seen[replacement] and seen[heroes[1]],"cached eligible heroes follow replacement, not stale builder handles")
local function kill(unit,attacker)
    unit.live=false;bus.emit(events.ENGINE_ENTITY_KILLED,{victim=unit,attacker=attacker})
end
kill(first,heroes[1])
assert(#drops==2,"only the two eligible active stage-zero subscribers receive personal drops")
local owners={};for _,drop in ipairs(drops) do
    assert(drop.required_stage==0);owners[drop.player_id]=true
end
assert(owners[0] and owners[1] and not owners[2] and not owners[3])
assert(drops[1].completion_id~=drops[2].completion_id,"personal claim identities stay separate")
assert(service.query("encounter_challenge_11",2).alive==1 and second:IsAlive())
assert(scheduler.task_count()==1,"one global vacancy owns one one-second respawn timer")
assert(not start(3,"11").ok,"late entry during the existing death cooldown cannot spawn early")
assert(creates==10 and #drops==2)
clock=0.999;scheduler.think();assert(creates==10)
local old_index=first:entindex();next_index=old_index
clock=1;scheduler.think()
local new_first=slot_for("boss_ten_sin_01").unit
assert(creates==11 and new_first~=first and new_first:entindex()==old_index)
bus.emit(events.ENGINE_ENTITY_KILLED,{victim=first,attacker=heroes[1]})
assert(new_first:IsAlive() and shared.slot_for(new_first) and #drops==2,
    "a duplicate old death cannot retire/reward a replacement with the same entity index")
assert(start(3,"11").ok and creates==11 and #drops==2,"late entrants join the new life without retroactive credit")
assert(not start(0,"11").ok,"retained material keeps the original individual stage-clear lock")
stages[0]=1;assert(start(0,"11").ok and creates==11)
-- Defeat detaches one participant, not the shared physical arena or other session.
defeated[0]=true
local before_remove=removed
bus.emit(events.PLAYER_DISCONNECTED,{player_id=0,defeat_cleanup=true})
assert(removed==before_remove and second:IsAlive())
assert(not service.query("encounter_challenge_11",0).active)
assert(service.query("encounter_challenge_11",2).active)
kill(second,heroes[2]);assert(#drops==3 and drops[3].player_id==2)
clock=2;scheduler.think();assert(creates==12)
defeated[0]=nil;stages[0]=0
-- The other authored singleton arenas share one body, while personal rewards
-- retain the pre-existing participant-specific completion request/ownership.
for _,id in ipairs({"05","08","09"}) do
    local before=creates
    for p=0,3 do assert(start(p,id).ok) end
    assert(creates==before+1,"shared singleton arena must not multiply by four players: "..id)
end
local five=assert(shared.get(shared.key("encounter_challenge_05",members.by_id.challenge_05_boss))).unit
-- Shared AI has an O(1) retained target and no EntIndexToHScript/world search.
local ai=require("modifiers/modifier_practice_monster_ai")
local thinker=setmetatable({GetParent=function() return five end,StartIntervalThink=function() end},{__index=ai})
thinker:OnCreated({hero_entindex=heroes[0]:entindex(),aggro_radius=700,leash_radius=1200})
local queries_before,writes_before=native_queries,force_writes
for _=1,20 do thinker:OnIntervalThink() end
assert(native_queries==queries_before and force_writes==writes_before+1)
local previous=five.forced;previous.live=false;thinker:OnIntervalThink()
assert(five.forced and five.forced~=previous and force_writes==writes_before+2)
previous.live=true
-- Keep all seven replenishing room populations, including their multi-unit
-- authored caps. These are not singleton bosses and must not become one unit.
local private_created=creates
for p=0,3 do
    stages[p]=nil
    for _,member in ipairs(members.rows) do
        if member.spawn_mode=="maintain_count" then
            local id=member.encounter_id:match("challenge_(%d+)$")
            assert(start(p,id).ok)
            local query=service.query(member.encounter_id,p)
            assert(query.alive==member.max_alive,"configured private population changed")
        end
    end
end
assert(creates-private_created==296,"four players retain all seven practice-room counts")
-- Reset cancels global vacancies and removes living shared bodies only once.
kill(five,heroes[1])
local callbacks_before_reset=creates
local shared_alive={}
for _,unit in ipairs(units) do if unit.survival_shared_challenge_boss and unit:IsAlive() then
    shared_alive[#shared_alive+1]=unit
end end
subscriptions={};service.init()
for _,unit in ipairs(shared_alive) do assert(unit.removed) end
clock=20;scheduler.think();assert(creates==callbacks_before_reset,"old world callbacks cannot recreate reset slots")
assert(not shared.slot_for(new_first))
-- A rejected entry after checkout must withdraw its own subscription without
-- removing the boss already being fought by another player.
for p=0,3 do stages[p]=0 end
bus.emit(events.HERO_READY,{player_id=0,team=2})
assert(start(1,"11").ok)
local preserved=slot_for("boss_ten_sin_01").unit
local saved_removes=removed
teleport_ok=false
local rejected=service.start({player_id=2,team=2,encounter_id="encounter_challenge_11",teleport_hero=true})
teleport_ok=true
assert(not rejected.ok and preserved:IsAlive() and removed==saved_removes)
local count=0;for session in pairs(slot_for("boss_ten_sin_01").participants) do
    count=count+1;assert(session.player_id==1)
end
assert(count==1 and not service.query("encounter_challenge_11",2).active)
bus.emit(events.PLAYER_DISCONNECTED,{player_id=1})
assert(service.query("encounter_challenge_11",1).active,"ordinary reconnect retains its personal challenge")
local old_session
for session in pairs(slot_for("boss_ten_sin_01").participants) do old_session=session end
local count_before_death=#drops
kill(preserved,heroes[1])
assert(#drops==count_before_death+1)
next_index=preserved:entindex();clock=clock+1;scheduler.think()
local reused=slot_for("boss_ten_sin_01").unit
assert(reused~=preserved and reused:entindex()==preserved:entindex())
assert(start(2,"11").ok)
-- Model a delayed cleanup retaining an old body after index reuse. Its native
-- handle is old; only that exact handle may be cleared from the metadata map.
old_session.monsters[preserved:entindex()]=preserved
old_session.monster_count=1
defeated[1]=true
bus.emit(events.PLAYER_DISCONNECTED,{player_id=1,defeat_cleanup=true})
assert(reused:IsAlive() and service.query("encounter_challenge_11",2).active)
kill(reused,heroes[2])
assert(#drops==count_before_death+2 and drops[#drops].player_id==2,
    "withdrawal of the old session must preserve the replacement's death/reward metadata")
defeated[1]=nil

-- The registry's actual native-creation transaction must clean up a partially
-- created body if a later native setup step throws, including reentrant entry.
local captured, partial_fail, reentered = {}, true, false
shared.configure({
    now=function() return clock end,
    after=function(delay,callback,id) captured[#captured+1]=callback;return scheduler.after(delay,callback,id) end,
    cancel=scheduler.cancel,
    destroy=UTIL_Remove,
    create=function(slot)
        local nested=shared.acquire(slot.key,slot.context,slot.member)
        assert(nested==nil,"a native spawn callback cannot create the same reserved slot again")
        reentered=true
        local unit=CreateUnitByName("fixture",Vector())
        slot.pending_unit=unit
        if partial_fail then partial_fail=false;error("fixture_native_setup_failed") end
        return unit
    end,
})
local member=members.by_id.challenge_05_boss
local key=shared.key(member.encounter_id,member)
local removed_before=removed
local failed=shared.acquire(key,{},member)
assert(failed==nil and removed==removed_before+1 and reentered,
    "failed native setup removes the partial body before any retry")
local body,slot=shared.acquire(key,{},member)
assert(body and body:IsAlive())
local owner_a,owner_b={player_id=0},{player_id=1}
assert(shared.attach(slot,owner_a,heroes[0]) and shared.attach(slot,owner_b,heroes[1]))
shared.detach(owner_a)
body.live=false
local eligible=shared.on_death(body,1)
assert(#eligible==1 and eligible[1]==owner_b,"withdrawn old sessions cannot claim the next death")
local old_callback=captured[#captured]
local before_respawn=creates
old_callback();assert(creates==before_respawn,"manual/duplicate early callback honors the same deadline")
clock=clock+1;scheduler.think()
assert(creates==before_respawn+1)
old_callback();assert(creates==before_respawn+1,"old life callback cannot overfill the occupied slot")
local new_body=slot.unit
new_body.live=false;shared.on_death(new_body,1)
local stale_world_callback=captured[#captured]
shared.reset()
local after_reset=creates
clock=clock+10;stale_world_callback();scheduler.think()
assert(creates==after_reset,"old world and old life callbacks are both invalidated")
print("SHARED_CHALLENGE_BOSSES_PASS: four players/ten previews, mixed eligible stages, personal drops, late entry, "
    .."1s single respawn, reused entity index, replacement/defeat/reconnect, three singleton arenas, AI constant target, "
    .."296 private mobs, failed entry withdrawal, partial native-create rollback, reentry, old callbacks and reset")
