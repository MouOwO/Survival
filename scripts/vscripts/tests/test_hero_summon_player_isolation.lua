-- Real hero summon service/anchor and event bus; mock only engine/resource boundaries.
package.path = "scripts/vscripts/?.lua;" .. package.path
local bus = require("core/event_bus")
local events = require("core/events")
local definition = assert(require("config/generated/hero_definitions").by_id.hero_doom)
local ctx, anchor
local scheduler=require("core/scheduler")
GameRules={GetGameTime=function() return 0 end}
ProjectileManager={ProjectileDodge=function() end}
local noop = function() end
Vector = function(x,y,z) return {x=x,y=y,z=z or 0} end
DOTA_UNIT_CAP_NO_ATTACK, DOTA_UNIT_CAP_MOVE_NONE = 0, 0
package.loaded["systems/unit_health_bar_service"] = {exclude=noop}
package.loaded["core/modifier_registry"] = {ensure=function(unit,name,args)
    return unit:AddNewModifier(unit,nil,name,args)
end}
package.loaded["systems/hero_stat_adapter"] = {apply=noop}
package.loaded["systems/hero_cosmetic_service"] = {apply=noop,clear=noop}
package.loaded["systems/multiplayer_player_service"] = {
    is_defeated=function(id) return ctx.defeated[id] == true end,
    reject_defeated_unit=function(unit)
        if not ctx.defeated[unit.owner_id] then return false end
        unit.hidden,unit.respawns_disabled,unit.controllable = true,true,false
        return true
    end,
}
package.loaded["systems/hero_summon_projection"] = {
    entitlements=function() return {vip=1} end,
    update_altar=function(id,altar) if altar then assert(altar.owner_id == id) end end,
    build=function(id,altar,city,summoned)
        return {player_id=id, altar=altar, city_level=city, hero_summoned=summoned and 1 or 0,
            shop_unlocked=summoned and 1 or 0}
    end,
}
package.loaded["systems/hero_summon_destination"] = {resolve=function(altar,_,id,moving)
    assert(altar == ctx.altars[id] or (altar==nil and moving and moving.owner_id==id), "must resolve from this player's altar or own-city return policy")
    ctx.last_resolved=id
    return Vector(id*1000+(ctx.home_offset or 0),0,32)
end}
package.loaded["systems/destination_validation_service"] = {teleport=function(unit,position)
    unit.position=position; return true
end}
package.loaded["systems/hero_asset_preload_service"] = {
    is_ready=function() return ctx.assets_ready end,
    request=function(_,callbacks) ctx.preloads[ctx.last_resolved]=callbacks; return true,"loading" end,
}
local function entity(name,id)
    ctx.serial=ctx.serial+1
    local unit={name=name,owner_id=id,index=ctx.serial,modifiers={},unhide_calls=0}
    function unit:IsNull() return self.removed == true end
    function unit:IsAlive() return not self.dead end
    function unit:Stop() self.stop_calls=(self.stop_calls or 0)+1 end
    function unit:SetRespawnPosition(value) self.respawn_position=value end
    function unit:entindex() return self.index end
    function unit:GetUnitName() return self.name end
    function unit:GetPlayerOwnerID() return self.owner_id end
    function unit:SetPlayerID(id) self.owner_id=id end
    function unit:SetOwner(owner) self.owner=owner end
    function unit:SetControllableByPlayer(_,value) self.controllable=value end
    function unit:AddNoDraw() self.hidden=true end
    function unit:RemoveNoDraw() self.hidden=false; self.unhide_calls=self.unhide_calls+1 end
    function unit:SetAbsOrigin(value) self.position=value end
    function unit:GetAbsOrigin() return self.position or Vector(0,0,0) end
    function unit:GetAbilityCount() return 0 end
    function unit:HasModifier(name) return self.modifiers[name] ~= nil end
    function unit:AddNewModifier(_,_,name,args) self.modifiers[name]=args; return args end
    unit.SetAttackCapability,unit.SetMoveCapability,unit.SetAbilityPoints=noop,noop,noop
    return unit
end
local function defeat(id)
    ctx.defeated[id]=true
    bus.emit(events.PLAYER_DEFEATED,{player_id=id,reason="monster_limit_exceeded"})
    bus.emit(events.PLAYER_DISCONNECTED,{player_id=id,reason="monster_limit_exceeded",defeat_cleanup=true})
end
PlayerResource={
    IsValidPlayerID=function(_,id) return type(id)=="number" and id>=0 and id<4 end,
    GetTeam=function() return 2 end,
    GetPlayer=function(_,id) return ctx.players[id] end,
    ReplaceHeroWithNoTransfer=function(_,id,name)
        ctx.replacements[id]=(ctx.replacements[id] or 0)+1
        ctx.selected[id].removed=true
        local result=entity(name,id)
        ctx.selected[id]=result
        if ctx.defeat_during_replace[id] then defeat(id) end
        return result
    end,
}
CustomGameEventManager={Send_ServerToPlayer=function(_,player,name)
    ctx.client_events[#ctx.client_events+1]={player_id=player.id,name=name}
end}
anchor=require("systems/hero_anchor_service")
local service=require("systems/hero_summon_system")
local function building(id,kind,unit,level)
    bus.emit(events.BUILDING_CREATED,{player_id=id,team=2,building_id=kind,unit=unit,level=level})
end
local function fixture()
    ctx={serial=0,defeated={},assets_ready=true,preloads={},altars={},selected={},players={},
        replacements={},defeat_during_replace={},summoned={},notifications={},client_events={}}
    scheduler.clear(); bus.reset(); anchor.init(); service.init()
    for id=0,3 do
        ctx.players[id]={id=id}
        ctx.selected[id]=entity("npc_dota_hero_wisp",id)
        assert(anchor.register_placeholder(id,ctx.selected[id]))
        ctx.altars[id]=entity("altar",id)
        bus.emit(events.BUILDER_READY,{player_id=id,team=2,builder=entity("builder",id)})
        building(id,"main_city",entity("city",id),10)
        building(id,"hero_altar",ctx.altars[id])
    end
    bus.subscribe(events.HERO_SUMMONED,function(p) ctx.summoned[#ctx.summoned+1]=p.player_id end)
    bus.subscribe(events.UI_NOTIFICATION,function(p) ctx.notifications[#ctx.notifications+1]=p end)
end
local function request(id,callback,debug_bypass)
    return assert(bus.request(events.HERO_SUMMON_REQUEST,{player_id=id,hero_id=definition.hero_id,
        on_completed=callback,debug_bypass=debug_bypass}))
end
local function snapshot(id)
    return assert(bus.request(events.HERO_SUMMON_SNAPSHOT_REQUEST,{player_id=id})).snapshot
end

-- All four players share team 2, but city requirements and altar destinations are private.
fixture()
bus.emit(events.BUILDING_CHANGED,{player_id=0,team=2,building_id="main_city",level=2})
assert(snapshot(0).city_level==2 and snapshot(1).city_level==10)
assert(snapshot(0).altar==ctx.altars[0] and snapshot(1).altar==ctx.altars[1])
assert(not request(0).ok and request(1).ok)
bus.emit(events.BUILDING_DESTROYED,{player_id=0,team=2,building_id="hero_altar",unit=ctx.altars[0]})
bus.emit(events.BUILDING_DESTROYED,{player_id=0,team=2,building_id="main_city"})
assert(snapshot(0).altar==nil and snapshot(0).city_level==0)
assert(snapshot(1).altar==ctx.altars[1] and snapshot(1).city_level==10 and snapshot(1).hero_summoned==1)
assert(request(2).ok and request(3).ok)

-- Defeat cancels only the owner's pending request and settles its callback once.
fixture(); ctx.assets_ready=false
local completions={}
for id=0,1 do
    local owner=id
    assert(request(id,function(result)
        completions[owner]=completions[owner] or {}
        completions[owner][#completions[owner]+1]=result
    end).pending)
end
local lost_callback,other_callback=ctx.preloads[0],ctx.preloads[1]
defeat(0)
assert(#completions[0]==1 and completions[0][1].error=="player_defeated")
assert(completions[1]==nil and snapshot(1).altar==ctx.altars[1])
local notifications=#ctx.notifications
ctx.assets_ready=true
lost_callback.on_ready(); lost_callback.on_failed("late_old_failure")
assert(ctx.replacements[0]==nil and #completions[0]==1 and #ctx.notifications==notifications)
other_callback.on_ready()
assert(ctx.replacements[1]==1 and #completions[1]==1 and completions[1][1].ok)
assert(request(0,nil,true).error=="player_defeated", "debug bypass must not restore an eliminated player")
building(0,"hero_altar",ctx.altars[0]); building(0,"main_city",entity("late_city",0),10)
bus.emit(events.BUILDER_READY,{player_id=0,team=2,builder=entity("late_builder",0)})
bus.emit(events.BUILDING_CHANGED,{player_id=0,team=2,building_id="main_city",level=10})
assert(snapshot(0).altar==nil and snapshot(0).city_level==0 and snapshot(0).hero_summoned==0)

-- Engine replacement callbacks can cause defeat synchronously before the new hero returns.
fixture(); ctx.defeat_during_replace[0]=true
local result=request(0)
assert(not result.ok and result.error=="player_defeated")
assert(ctx.replacements[0]==1 and ctx.selected[0].hidden and ctx.selected[0].respawns_disabled)
assert(ctx.selected[0].unhide_calls==0 and #ctx.summoned==0 and #ctx.client_events==0)
assert(not bus.request(events.HERO_SUMMON_GET_REQUEST,{player_id=0}).ok)
assert(request(1).ok and #ctx.summoned==1 and ctx.summoned[1]==1)

-- A synchronous post-commit subscriber cannot select or report success after defeat.
fixture()
bus.subscribe(events.HERO_SUMMONED,function(payload)
    if payload.player_id==0 then defeat(0) end
end)
result=request(0)
assert(not result.ok and result.error=="player_defeated")
assert(ctx.selected[0].hidden and ctx.selected[0].respawns_disabled and #ctx.client_events==0)
assert(snapshot(0).hero_summoned==0 and request(1).ok)

-- Callbacks from a previous Tools session must not resolve the new pending request.
fixture(); ctx.assets_ready=false
assert(request(0).pending)
local stale=ctx.preloads[0]
fixture(); ctx.assets_ready=false
local completion_count=0
assert(request(0,function() completion_count=completion_count+1 end).pending)
local current=ctx.preloads[0]
notifications=#ctx.notifications
ctx.assets_ready=true
stale.on_ready(); stale.on_failed("stale_session")
assert(ctx.replacements[0]==nil and completion_count==0 and #ctx.notifications==notifications)
current.on_ready()
assert(ctx.replacements[0]==1 and completion_count==1)

-- Removing an older altar cannot clear a replacement, and disconnect clears only its owner.
fixture()
local old_altar=ctx.altars[0]
ctx.altars[0]=entity("new_altar",0)
building(0,"hero_altar",ctx.altars[0])
bus.emit(events.BUILDING_DESTROYED,{player_id=0,team=2,building_id="hero_altar",unit=old_altar})
assert(snapshot(0).altar==ctx.altars[0])
ctx.assets_ready=false
local disconnected_result
assert(request(1,function(value) disconnected_result=value end).pending)
local disconnected_callback=ctx.preloads[1]
bus.emit(events.PLAYER_DISCONNECTED,{player_id=1,reason="disconnect"})
ctx.assets_ready=true; disconnected_callback.on_ready()
assert(disconnected_result.error=="player_disconnected" and ctx.replacements[1]==nil)
assert(snapshot(0).altar==ctx.altars[0] and request(0).ok)
-- Deleting player zero's hero leaves the other three players, all cities and
-- altars intact. Both players can continue independent summon transactions.
fixture()
assert(request(0).ok and request(1).ok)
local other_hero = ctx.selected[1]
local deletions = {}
bus.subscribe(events.HERO_REMOVED, function(payload)
    deletions[#deletions + 1] = payload.player_id
end)
local deleted = bus.request(events.HERO_DELETE_REQUEST, {player_id = 0})
assert(deleted.ok and deleted.removed and #deletions == 1 and deletions[1] == 0)
assert(snapshot(0).hero_summoned == 0 and snapshot(0).city_level == 10
    and snapshot(0).altar == ctx.altars[0])
assert(snapshot(1).hero_summoned == 1 and ctx.selected[1] == other_hero
    and not other_hero:IsNull())
assert(request(0).ok and request(2).ok and request(3).ok)
assert(not bus.request(events.HERO_DELETE_REQUEST, {player_id = -1}).ok)
assert(not bus.request(events.HERO_DELETE_REQUEST, {player_id = 99}).ok)
assert(#deletions == 1)

print("PASS hero summon player isolation: four same-team cities/altars, owner-only deletion and pending cancellation, stale callbacks, reentrant defeat, late events, survivor continuation")
print("PASS hero summon player isolation: four same-team cities/altars, owner-only pending cancellation, stale callbacks, reentrant defeat, late events, survivor continuation")
-- Death and native respawn share the actual F2 return path, owner and camera.
fixture(); assert(request(0).ok and request(1).ok)
local hero0,hero1=ctx.selected[0],ctx.selected[1]
assert(hero0.respawn_position.x==0 and hero1.respawn_position.x==1000)
local returned={}
bus.subscribe(events.HERO_RETURNED_HOME,function(p) returned[#returned+1]=p end)
ctx.home_offset=75; hero1.dead=true
bus.emit(events.ENGINE_ENTITY_KILLED,{victim=hero1})
assert(hero1.respawn_position.x==1075 and hero0.respawn_position.x==0)
hero1.dead=false; hero1.position=Vector(-999,-999,0)
service.on_npc_spawned(hero1); service.on_npc_spawned(hero1)
ctx.home_offset=120 -- Landing occupancy may change while the hero is dead.
local notes=#ctx.notifications
scheduler.think()
assert(hero1.position.x==1120 and hero1.respawn_position.x==1120)
assert(hero0.position.x==0 and #returned==1 and returned[1].player_id==1)
assert(hero1.stop_calls==1 and #ctx.notifications==notes, "respawn must not send the manual F2 success toast")
assert(ctx.client_events[#ctx.client_events].name=="ui_camera_follow_hero")
service.on_npc_spawned(hero1); scheduler.think(); assert(#returned==1)
-- Foreign units, delayed duplicate spawns and eliminated owners must not move.
local stranger=entity("npc_dota_hero_doom_bringer",1)
bus.emit(events.ENGINE_ENTITY_KILLED,{victim=stranger})
service.on_npc_spawned(stranger); scheduler.think(); assert(stranger.position==nil)
hero1.dead=true; bus.emit(events.ENGINE_ENTITY_KILLED,{victim=hero1})
hero1.dead=false; hero1.position=Vector(-500,0,0); service.on_npc_spawned(hero1)
defeat(1); scheduler.think()
assert(hero1.position.x==-500 and #returned==1)
print("HERO_RESPAWN_HOME_PASS: actual F2 service, owner isolation, refreshed landing, camera, duplicate/foreign/defeated guards")
