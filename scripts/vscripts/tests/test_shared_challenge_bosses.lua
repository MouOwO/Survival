-- Run with Lua 5.1 from the game addon root. Real service/registry, fake engine.
-- No Dota, network, database, rewards, saved profiles or real accounts are used.
package.path = "scripts/vscripts/?.lua;" .. package.path
local clock, serial, creates, removed, native_queries, force_writes = 0, 0, 0, 0, 0, 0
local teleport_ok = true
local teleport_calls, home_attempts, teleport_targets, hero_requests = 0, {}, {}, 0
local home_mode, material_mode, material_hook, summon_ok = "ok", "legacy_fixture", nil, true
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
    local stage=tonumber(name:match("^challenge_11_stage_(%d+)_entry$"))
    if stage then markers[name].position=Vector(stage*1000,0,0) end
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
    if name==events.HERO_SUMMON_GET_REQUEST then hero_requests=hero_requests+1 end
    if requests[name] then return requests[name](payload or {}) end
    return nil,"no_request_handler:"..tostring(name)
end
function bus.after_dispatch(_,callback) callback() end
package.loaded["core/event_bus"]=bus
package.loaded["systems/player_context_service"]={is_defeated=function(p) return defeated[p] == true end}
local weapon_rows={}
for stage=0,10 do weapon_rows[#weapon_rows+1]={content_id="abyss"..stage,series_id="legend_abyss",stage=stage} end
package.loaded["config/generated/weapon_definitions"]={rows=weapon_rows}
requests[events.CONTENT_INVENTORY_GET_REQUEST]=function(p)
    local counts={};if stages[p.player_id] ~= nil then counts["abyss"..stages[p.player_id]]=1 end
    return {ok=true,snapshot={counts=counts}}
end
requests[events.HERO_SUMMON_GET_REQUEST]=function(p) return {ok=summon_ok,unit=heroes[p.player_id]} end
requests[events.WAVE_STATE_GET_REQUEST]=function() return {ok=true,difficulty_id="N1",game_mode="standard"} end
requests[events.CHALLENGE_MATERIAL_DROP_REQUEST]=function(p)
    drops[#drops+1]=p
    if material_hook then material_hook(p) end
    if material_mode=="retained" then return {ok=false,material_retained=true,error="fixture_synthesis_failed"} end
    if material_mode=="failed" then return {ok=false,error="fixture_material_create_failed"} end
    if material_mode=="success" then stages[p.player_id]=p.required_stage+1;return {ok=true} end
    return {ok=true,material_retained=true}
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
    teleport=function(hero,position)
        teleport_calls=teleport_calls+1;teleport_targets[#teleport_targets+1]={hero=hero,position=position}
        return teleport_ok,teleport_ok and nil or "fixture_destination_rejected"
    end}
package.loaded["systems/hero_return_home_service"]={return_unit=function(hero,player)
    assert(hero==heroes[player] and hero:IsAlive(),"only the current living formal hero may reach the home boundary")
    home_attempts[#home_attempts+1]={hero=hero,player_id=player,stage=stages[player]}
    if home_mode=="throw" then error("fixture native home failure") end
    if home_mode=="reject" then return {ok=false,error="fixture_home_destination_blocked"} end
    hero.position=Vector(-10000-player*1000,0,0)
    bus.emit(events.HERO_RETURNED_HOME,{player_id=player,hero=hero})
    return {ok=true}
end}
local scheduler=require("core/scheduler")
local shared=require("systems/shared_challenge_boss_registry")
local members=require("config/generated/encounter_members")
local service=require("systems/challenge_session_service")
local member_enumerations=0
for index=1,100 do
    local name,reader=debug.getupvalue(service.start,index)
    if not name then break end
    if name=="members_for" then
        debug.setupvalue(service.start,index,function(...)
            member_enumerations=member_enumerations+1;return reader(...)
        end)
        break
    end
end
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

-- Foreground victory-to-home uses the real service and shared registry. The
-- return boundary above is a spy; own-city/native movement has its own suite.
local authored=require("config/generated/challenge_definitions").by_id.challenge_11
assert(authored.completion_teleport_policy=="reset_to_stage_entry","ten sins advances automatically until the final victory")
local function fresh_return()
    subscriptions={};service.init();scheduler.clear()
    clock=clock+10;drops,rewards,home_attempts={},{},{}
    teleport_calls=0;teleport_targets={};hero_requests=0;teleport_ok=true;home_mode="ok";material_mode="success";material_hook=nil;summon_ok=true
    heroes,stages,defeated={},{},{}
    for p=0,3 do heroes[p]=entity(10000+serial*4+p,p);stages[p]=0 end
    bus.emit(events.HERO_READY,{player_id=0,team=2})
end
local function enter(p)
    return service.start({player_id=p,team=2,encounter_id="encounter_challenge_11",teleport_hero=true})
end
local function front(p,encounter)
    bus.emit(events.MONSTER_ENCOUNTER_CHANGED,{player_id=p,status="active",foreground_entry=true,
        encounter={encounter_id=encounter}})
end
local function check_return_owner_set(...)
    local expected={};for _,p in ipairs({...}) do expected[p]=true end
    for _,attempt in ipairs(home_attempts) do
        assert(expected[attempt.player_id],"wrong/nonparticipant player returned")
        expected[attempt.player_id]=nil
    end
    assert(next(expected)==nil,"eligible foreground winner did not return")
end

-- Current authored behavior: real personal sessions + shared boss registry,
-- material upgrades and scheduled teleports, without manually entering again.
fresh_return();local reads_before=member_enumerations;assert(enter(0).ok)
assert(teleport_targets[1].position.x==1000 and teleport_targets[1].hero==heroes[0])
local idle_queries=native_queries
for index=1,10000 do assert(service.query("encounter_challenge_11",0).active) end
assert(member_enumerations==reads_before+1 and native_queries==idle_queries
    and teleport_calls==1 and #home_attempts==0,"idle queries add no list/native/movement work")
for stage=0,9 do
    local boss=slot_for(string.format("boss_ten_sin_%02d",stage+1)).unit
    local before_tasks=scheduler.task_count()
    kill(boss,heroes[0])
    assert(stages[0]==stage+1 and #drops==stage+1 and #rewards==0)
    local q=service.query("encounter_challenge_11",0)
    if stage<9 then
        assert(#home_attempts==0 and q.status=="waiting_respawn" and q.stage==stage+2)
        assert(q.active and not q.resume_without_charge and teleport_calls==stage+1)
        assert(scheduler.task_count()==before_tasks+2,"one global vacancy and one personal next-layer task")
        clock=clock+.999;scheduler.think();assert(teleport_calls==stage+1)
        clock=clock+.001;scheduler.think()
        q=service.query("encounter_challenge_11",0)
        assert(q.status=="active" and q.stage==stage+2 and q.alive==1 and teleport_calls==stage+2)
        assert(teleport_targets[stage+2].position.x==(stage+2)*1000
            and teleport_targets[stage+2].hero==heroes[0],"each advance uses that exact next layer's entry marker")
        local next_slot=slot_for(string.format("boss_ten_sin_%02d",stage+2))
        local enrolled=false
        for session in pairs(next_slot.participants) do enrolled=enrolled or session.player_id==0 end
        assert(enrolled,"the same paid session subscribes to the correct next shared boss")
    else
        check_return_owner_set(0)
        assert(q.status=="completed" and not q.active and not q.resume_without_charge)
        assert(home_attempts[1].stage==10 and teleport_calls==10)
    end
    bus.emit(events.ENGINE_ENTITY_KILLED,{victim=boss,attacker=heroes[0]})
    assert(#drops==stage+1 and #home_attempts==(stage==9 and 1 or 0))
end
clock=clock+1;scheduler.think()
assert(#home_attempts==1 and #drops==10 and not enter(0).ok)
assert(member_enumerations==reads_before+2,"one list at entry, none during nine automatic advances; final denied entry reads once")
print("TEN_SINS_CHAIN all_ten_layers_one_entry_nine_next_teleports_one_final_home PASS idle_queries=10000 member_lists_during_advances=0")
print("TEN_SINS_CHAIN_COUNTS hero_requests="..hero_requests.." native_world_queries="..native_queries.." entry_teleports="..teleport_calls.." home_attempts="..#home_attempts)

for starting_stage=0,9 do
    fresh_return();stages[0]=starting_stage;assert(enter(0).ok)
    for stage=starting_stage,9 do
        kill(slot_for(string.format("boss_ten_sin_%02d",stage+1)).unit,heroes[0])
        clock=clock+1;scheduler.think()
    end
    assert(stages[0]==10 and #drops==10-starting_stage and #home_attempts==1)
    assert(teleport_calls==10-starting_stage,"resume from the owned weapon stage, never restart earlier layers")
end
print("TEN_SINS_CHAIN ten_owned_starting_stages_finish_once PASS")

fresh_return();assert(enter(0).ok and enter(1).ok);stages[2]=1;assert(enter(2).ok)
kill(slot_for("boss_ten_sin_01").unit,heroes[1]);clock=clock+1;scheduler.think()
assert(#drops==2 and #home_attempts==0 and stages[2]==1 and stages[3]==0)
kill(slot_for("boss_ten_sin_02").unit,heroes[2])
assert(#drops==5 and stages[0]==2 and stages[1]==2 and stages[2]==2 and stages[3]==0)
clock=clock+1;scheduler.think();assert(#home_attempts==0 and teleport_calls==8)
print("TEN_SINS_CHAIN shared_winners_advance_independently_mixed_stages_no_spectator_rewards PASS")

for _,change in ipairs({"home","other_room","dead","replacement","unregistered","cancelled"}) do
    fresh_return();assert(enter(0).ok)
    kill(slot_for("boss_ten_sin_01").unit,heroes[0])
    if change=="home" then bus.emit(events.HERO_RETURNED_HOME,{player_id=0,hero=heroes[0]})
    elseif change=="other_room" then front(0,"encounter_challenge_05")
    elseif change=="dead" then heroes[0].live=false
    elseif change=="replacement" then heroes[0]=entity(99000,0);bus.emit(events.HERO_SUMMONED,{player_id=0,team=2})
    elseif change=="unregistered" then summon_ok=false
    else defeated[0]=true;bus.emit(events.PLAYER_DISCONNECTED,{player_id=0,defeat_cleanup=true}) end
    clock=clock+1;scheduler.think()
    assert(teleport_calls==1 and #drops==1 and #home_attempts==0,"do not pull a departed/replaced hero forward: "..change)
    local next_slot=slot_for("boss_ten_sin_02")
    for session in pairs(next_slot.participants) do assert(session.player_id~=0) end
    if change~="cancelled" then
        assert(service.query("encounter_challenge_11",0).resume_without_charge,"a settled interrupted chain retains free explicit continuation")
    end
    stages[1]=1;assert(enter(1).ok);kill(next_slot.unit,heroes[1])
    assert(#drops==2 and drops[2].player_id==1 and stages[0]==1,"interrupted player cannot receive the next boss reward from home")
end
print("TEN_SINS_CHAIN waiting_callback_identity_room_death_cancel_guards_no_background_rewards PASS")

for _,change in ipairs({"home","other_room","dead","replacement","unregistered"}) do
    fresh_return();assert(enter(0).ok)
    material_hook=function()
        if change=="home" then bus.emit(events.HERO_RETURNED_HOME,{player_id=0,hero=heroes[0]})
        elseif change=="other_room" then front(0,"encounter_challenge_05")
        elseif change=="dead" then heroes[0].live=false
        elseif change=="replacement" then heroes[0]=entity(99001,0)
        else summon_ok=false end
    end
    kill(slot_for("boss_ten_sin_01").unit,heroes[0])
    clock=clock+1;scheduler.think()
    assert(teleport_calls==1 and #home_attempts==0 and #drops==1 and service.query("encounter_challenge_11",0).resume_without_charge)
    for session in pairs(slot_for("boss_ten_sin_02").participants) do assert(session.player_id~=0) end
end
fresh_return();stages[0]=9;assert(enter(0).ok);material_mode="legacy_fixture"
kill(slot_for("boss_ten_sin_10").unit,heroes[0])
assert(stages[0]==9 and #home_attempts==0 and #drops==1,"final material must really upgrade the weapon before returning home")
print("TEN_SINS_CHAIN reward_reentrancy_and_final_inventory_confirmation PASS")

fresh_return();assert(enter(0).ok);kill(slot_for("boss_ten_sin_01").unit,heroes[0])
teleport_ok=false;clock=clock+1;scheduler.think()
assert(not service.query("encounter_challenge_11",0).active and service.query("encounter_challenge_11",0).resume_without_charge)
for session in pairs(slot_for("boss_ten_sin_02").participants) do assert(session.player_id~=0) end
teleport_ok=true;assert(enter(0).ok);kill(slot_for("boss_ten_sin_02").unit,heroes[0])
assert(stages[0]==2 and #drops==2 and #home_attempts==0)
for _,failure in ipairs({"failed","retained"}) do
    fresh_return();assert(enter(0).ok);material_mode=failure
    local boss=slot_for("boss_ten_sin_01").unit;kill(boss,heroes[0])
    clock=clock+1;scheduler.think()
    assert(stages[0]==0 and #drops==1 and teleport_calls==1 and #home_attempts==0)
    assert(not service.query("encounter_challenge_11",0).resume_without_charge)
end
for _,failure in ipairs({"reject","throw"}) do
    fresh_return();stages[0]=9;stages[1]=9;assert(enter(0).ok and enter(1).ok);home_mode=failure
    kill(slot_for("boss_ten_sin_10").unit,heroes[1]);check_return_owner_set(0,1)
    assert(stages[0]==10 and stages[1]==10 and #drops==2)
end
print("TEN_SINS_CHAIN failed_next_teleport_can_resume_material_failure_stays_final_home_isolated PASS")

-- Retain coverage for the legacy optional per-layer home policy explicitly;
-- the production CSV above uses the continuous chain, never this override.
authored.completion_teleport_policy="return_home"
for stage=0,9 do
    fresh_return();stages[0]=stage;assert(enter(0).ok)
    local boss=slot_for(string.format("boss_ten_sin_%02d",stage+1)).unit
    kill(boss,heroes[0]);check_return_owner_set(0)
    assert(#drops==1 and drops[1].required_stage==stage and stages[0]==stage+1
        and home_attempts[1].stage==stage+1 and #rewards==0,
        "material success must precede exactly one home attempt for every layer")
    local q=service.query("encounter_challenge_11",0)
    assert(q.status=="completed")
    assert(q.active==false and q.resume_without_charge==(stage<9),
        "settled lower layers retain free manual continuation, while +10 remains closed")
    local callbacks=scheduler.task_count()
    assert(callbacks==1,"only the existing global boss vacancy task is allowed; no personal auto-reentry")
    bus.emit(events.ENGINE_ENTITY_KILLED,{victim=boss,attacker=heroes[0]})
    clock=clock+1;scheduler.think()
    assert(#home_attempts==1 and #drops==1 and teleport_calls==1,
        "duplicate death/respawn cannot issue another reward, home call or entry teleport")
end
print("TEN_SINS_HOME ten_layers_including_plus10_once_after_material_no_extra_timers PASS")

fresh_return();assert(enter(0).ok and enter(1).ok);stages[2]=1;assert(enter(2).ok)
local peer_stage=slot_for("boss_ten_sin_02").unit
kill(slot_for("boss_ten_sin_01").unit,heroes[1]);check_return_owner_set(0,1)
assert(#drops==2 and peer_stage:IsAlive() and service.query("encounter_challenge_11",2).alive==1
    and stages[3]==0 and #rewards==0,"other layers and nonparticipants are unaffected")
clock=clock+1;scheduler.think();assert(teleport_calls==3 and #home_attempts==2 and #drops==2)
print("TEN_SINS_HOME shared_winners_only_other_stage_and_nonparticipant_untouched PASS")

fresh_return();assert(enter(0).ok)
assert(service.query("encounter_challenge_11",0).resume_without_charge==false
    and service.query("encounter_challenge_11",3).resume_without_charge==false
    and service.query("encounter_challenge_05",0).resume_without_charge==false,
    "active sessions, never-entered players and other encounters have no completed continuation qualification")
kill(slot_for("boss_ten_sin_01").unit,heroes[0])
clock=clock+1;scheduler.think()
local next_slot=slot_for("boss_ten_sin_02")
assert(next(next_slot.participants)==nil and service.query("encounter_challenge_11",0).status=="completed",
    "a completed winner must not attach to the next shared boss after the old respawn delay")
assert(service.query("encounter_challenge_11",0).resume_without_charge==true)
teleport_ok=false
assert(not enter(0).ok,"the failed-entry fixture must reject its native teleport")
teleport_ok=true
assert(service.query("encounter_challenge_11",0).resume_without_charge==true
    and service.query("encounter_challenge_11",0).active==false and next(next_slot.participants)==nil,
    "failed explicit entry retains free qualification without attaching to the boss")
stages[1]=1;assert(enter(1).ok)
kill(next_slot.unit,heroes[1])
assert(#drops==2 and drops[2].player_id==1 and stages[0]==1 and #home_attempts==2,
    "teammate killing the next layer cannot award or return the previous completed winner")
clock=clock+1;scheduler.think()
assert(enter(0).ok,"explicit entry can enroll the completed winner in the next eligible layer")
assert(service.query("encounter_challenge_11",0).active==true
    and service.query("encounter_challenge_11",0).resume_without_charge==false,
    "successful explicit entry consumes the completed continuation by replacing its session")
local enrolled=false
for session in pairs(slot_for("boss_ten_sin_02").participants) do enrolled=enrolled or session.player_id==0 end
assert(enrolled)
kill(slot_for("boss_ten_sin_02").unit,heroes[0])
assert(#drops==3 and drops[3].player_id==0 and stages[0]==2 and #home_attempts==3)
print("TEN_SINS_HOME no_next_layer_auto_subscription_or_reward_until_explicit_entry PASS")

for _,change in ipairs({"left_before_death","other_room_before_death","dead_before_death","left_during_reward",
    "other_room_during_reward","death_during_reward","replacement_during_reward","unregistered_during_reward","session_cancelled_during_reward"}) do
    fresh_return();assert(enter(0).ok)
    if change=="left_before_death" then bus.emit(events.HERO_RETURNED_HOME,{player_id=0,hero=heroes[0]})
    elseif change=="other_room_before_death" then front(0,"encounter_challenge_05")
    elseif change=="dead_before_death" then heroes[0].live=false
    else material_hook=function(p)
        if change=="left_during_reward" then bus.emit(events.HERO_RETURNED_HOME,{player_id=0,hero=heroes[0]})
        elseif change=="other_room_during_reward" then front(0,"encounter_challenge_05")
        elseif change=="death_during_reward" then heroes[0].live=false
        elseif change=="replacement_during_reward" then heroes[0]=entity(90000,0);bus.emit(events.HERO_SUMMONED,{player_id=0,team=2})
        elseif change=="unregistered_during_reward" then summon_ok=false
        else defeated[0]=true;bus.emit(events.PLAYER_DISCONNECTED,{player_id=0,defeat_cleanup=true}) end
    end end
    kill(slot_for("boss_ten_sin_01").unit,heroes[1])
    assert(#drops==1 and #home_attempts==0,"stale/nonforeground/dead hero must not be pulled home: "..change)
end
fresh_return();assert(enter(0).ok);summon_ok=false
kill(slot_for("boss_ten_sin_01").unit,heroes[1]);assert(#home_attempts==0 and #drops==1)
fresh_return();assert(enter(0).ok);heroes[0]=entity(90001,0);bus.emit(events.HERO_SUMMONED,{player_id=0,team=2})
kill(slot_for("boss_ten_sin_01").unit,heroes[1]);check_return_owner_set(0)
assert(home_attempts[1].hero==heroes[0],"replacement registered before victory is the current participant")
fresh_return();assert(enter(0).ok)
kill(slot_for("boss_ten_sin_01").unit,entity(90002,99)) -- Same-team remains authorized under existing rules.
check_return_owner_set(0)
fresh_return();assert(enter(0).ok)
local hostile=entity(90003,99);hostile.GetTeamNumber=function() return 3 end
kill(slot_for("boss_ten_sin_01").unit,hostile)
assert(#home_attempts==0 and #drops==0,"unauthorized hostile kill must neither settle a material nor return a hero")
print("TEN_SINS_HOME foreground_formal_identity_death_replacement_and_cancel_boundaries PASS")

for _,failure in ipairs({"failed","retained"}) do
    fresh_return();assert(enter(0).ok);material_mode=failure
    local boss=slot_for("boss_ten_sin_01").unit
    kill(boss,heroes[0]);assert(#home_attempts==0 and #drops==1 and stages[0]==0)
    assert(service.query("encounter_challenge_11",0).resume_without_charge==false,
        "failed or retained material cannot create free next-stage eligibility")
    if failure=="retained" then assert(not enter(0).ok,"retained material still owns the existing stage lock") end
    bus.emit(events.ENGINE_ENTITY_KILLED,{victim=boss,attacker=heroes[0]})
    clock=clock+1;scheduler.think()
    assert(#home_attempts==0 and #drops==1 and teleport_calls==1,
        "failed synthesis preserves location/material and does not grant twice or teleport on respawn")
end
for _,failure in ipairs({"reject","throw"}) do
    fresh_return();assert(enter(0).ok and enter(1).ok);home_mode=failure
    local boss=slot_for("boss_ten_sin_01").unit
    kill(boss,heroes[1]);check_return_owner_set(0,1)
    assert(#drops==2 and stages[0]==1 and stages[1]==1,"one failed home native call cannot abort another winner's reward")
    assert(service.query("encounter_challenge_11",0).resume_without_charge==true
        and service.query("encounter_challenge_11",1).resume_without_charge==true,
        "native home failure must preserve both successfully settled winners' free manual continuation")
    bus.emit(events.ENGINE_ENTITY_KILLED,{victim=boss,attacker=heroes[1]})
    clock=clock+1;scheduler.think()
    assert(#home_attempts==2 and #drops==2 and teleport_calls==2,
        "failed home does not retry rewards/teleport or auto-pull back into next layer")
end
print("TEN_SINS_HOME synthesis_retained_and_home_failure_no_extra_reward_or_reentry PASS")
authored.completion_teleport_policy="reset_to_stage_entry"
