package.path="scripts/vscripts/?.lua;"..package.path
local bus=require("core/event_bus")
local events=require("core/events")
local config=require("config/generated/builder_definitions").by_id.default_builder
local catalog=require("config/asset_catalog")
local sound_config=require("config/generated/building_sound_definitions").by_id
class=function(value) return value end
MODIFIER_STATE_NO_UNIT_COLLISION=9
local phase=require("modifiers/modifier_survival_builder_phase")
assert(phase:CheckState()[MODIFIER_STATE_NO_UNIT_COLLISION])
ACT_DOTA_TAUNT,ACT_DOTA_ATTACK,PATTACH_ABSORIGIN_FOLLOW,ACT_DOTA_CAST_ABILITY_3=10,11,12,13
local clock=0
GameRules={GetGameTime=function() return clock end}
local ids,live,destroyed,released,gestures,fades,created=0,{},{},{},{},{},{}
ParticleManager={
    CreateParticle=function(_,path,attach,owner)
        assert(attach==PATTACH_ABSORIGIN_FOLLOW);ids=ids+1;live[ids]={path=path,owner=owner};return ids
    end,
    DestroyParticle=function(_,id,immediate) assert(immediate);destroyed[id]=(destroyed[id] or 0)+1;live[id]=nil end,
    ReleaseParticleIndex=function(_,id) released[id]=(released[id] or 0)+1 end,
}
local function unit(id)
    local u={id=id,alive=true,model="ogre",sounds={}}
    function u:entindex() return self.id end
    function u:IsNull() return self.removed==true end
    function u:IsAlive() return self.alive end
    function u:GetUnitName() return "npc_survival_builder_proxy" end
    function u:GetTeamNumber() return 2 end
    function u:SetPlayerID(value) self.player_id=value end
    function u:SetOwner(value) self.owner=value end
    function u:SetControllableByPlayer(value) self.control=value end
    function u:SetBaseMoveSpeed(value) self.speed=value end
    function u:SetModel(value) self.model=value end
    function u:SetOriginalModel(value) self.original=value end
    function u:SetModelScale(value) self.scale=value end
    function u:SetHullRadius(value) self.hull=value end
    function u:StartGesture(value) assert(value==ACT_DOTA_CAST_ABILITY_3);gestures[#gestures+1]={unit=self,activity=value} end
    function u:FadeGesture(value) assert(value==ACT_DOTA_CAST_ABILITY_3);fades[#fades+1]=self end
    function u:EmitSound(value) self.sounds[#self.sounds+1]=value end
    return u
end
local registered={}
package.loaded["systems/player_context_service"]={
    is_defeated=function() return false end,
    resolve_builder_spawn=function(id) return {position={x=100*id,y=100,z=256},slot_id=id,marker="test",source="test"} end,
    register_unit=function(id,u,kind) assert(kind=="builder");registered[id]=u;return true end,
    unregister_unit=function() end,
}
package.loaded["core/modifier_registry"]={ensure=function(u,name) assert(name=="modifier_survival_builder_phase");u.phase=true end}
PlayerResource={GetPlayer=function(_,id) return {id=id} end}
CustomGameEventManager={Send_ServerToPlayer=function() end}
CustomNetTables={SetTableValue=function() end}
FindClearSpaceForUnit=function(u,position) u.position=position end
UTIL_Remove=function(u) u.removed=true;u.remove_count=(u.remove_count or 0)+1 end
local wearables={}
SpawnEntityFromTableSynchronous=function(class,data)
    assert(class=="dota_item_wearable" and data.model=="models/items/io/io_ti7/io_ti7.vmdl")
    -- Native wearable creation ignores model in the spawn table.
    local w={model="",sequence=""}
    function w:IsNull() return self.removed==true end
    function w:SetModel(path) self.model=path end
    function w:SetOwner(owner) self.owner=owner end
    function w:FollowEntity(owner,merge) self.parent=owner;self.merge=merge end
    function w:SetSequence(sequence) self.sequence=sequence end
    wearables[#wearables+1]=w;return w
end
CreateUnitByName=function(name,position,_,_,_,team)
    assert(name=="npc_survival_builder_proxy" and team==2)
    local u=unit(100+#created);created[#created+1]=u;return u
end
local presentation=require("systems/builder_presentation_service")
local builders=require("systems/builder_service")
local sounds=require("systems/building_sound_service")
bus.reset();builders.init()
for id=0,1 do bus.emit(events.HERO_READY,{player_id=id,hero=unit(50+id),team=2}) end
local a,b=created[1],created[2]
assert(a.model=="models/heroes/wisp/wisp.vmdl" and a.original==a.model,
    "the clickable NPC must retain the native Io body, never the hitbox-free cosmetic")
assert(#wearables==2 and wearables[1].owner==a and wearables[2].owner==b)
assert(wearables[1].model=="models/items/io/io_ti7/io_ti7.vmdl"
    and wearables[1].parent==a and wearables[1].merge==true
    and wearables[1].sequence=="ti7_io_idle",
    "arcana must explicitly load a real model and follow its selectable owner")
assert(a.hull==0 and a.phase and a.speed==500 and a.control==0)
assert(a.survival_builder_id=="default_builder" and a.survival_player_id==0)
assert(b.control==1 and b.survival_player_id==1 and b.phase)
assert(bus.request(events.BUILDER_GET_REQUEST,{player_id=0}).builder==a)
assert(not bus.request(events.BUILDER_GET_REQUEST,{player_id=1,builder=a}).ok)
local asset=catalog.get(config.visual_asset_id)
assert(asset.portrait_item_def=="9235" or asset.portrait_item_def==9235)
assert(asset.environment_particles[1]=="particles/econ/items/wisp/wisp_ambient_ti7.vpcf")
local first,second=unit(200),unit(201)
assert(presentation.construction_started(a,first) and #gestures==1)
assert(wearables[1].sequence=="ti7_io_taunt")
local old_work=ids
assert(live[old_work].path==config.construction_particle and live[old_work].owner==wearables[1],
    "TI7 particles must keep their cosmetic card attachments")
assert(presentation.construction_started(a,second) and #gestures==2)
assert(destroyed[old_work]==1 and released[old_work]==1)
local new_work=ids
presentation.construction_finished(first)
assert(live[new_work],"old completion must not cancel the next build")
assert(wearables[1].sequence=="ti7_io_taunt","old completion must not stop the new arcana gesture")
assert(presentation.construction_started(b,first))
sounds.construction_started(second,2);clock=1;sounds.construction_completed(second,2)
assert(second.sounds[1]=="Hero_Wisp.Spirits.Cast" and second.sounds[2]=="Hero_Wisp.TeleportIn.Arc")
assert(sound_config.building_construction_start.sound_resources[1]=="soundevents/game_sounds_heroes/game_sounds_wisp.vsndevts")
assert(sound_config.building_construction_start.max_plays_per_window==3)
assert(sound_config.building_construction_complete.max_concurrent==2)
-- Removed building handles still terminate charge using the captured index.
second.removed=true;presentation.construction_finished(second,201)
assert(not live[new_work] and destroyed[new_work]==1 and released[new_work]==1)
assert(wearables[1].sequence=="ti7_io_idle")
presentation.construction_finished(second,201)
bus.emit(events.ENGINE_ENTITY_KILLED,{victim=first,victim_entindex=200})
assert(not live[ids],"destroyed construction must stop another player's own work effect")
local ambient_a=1;assert(live[ambient_a] and live[ambient_a].owner==wearables[1])
bus.emit(events.PLAYER_DISCONNECTED,{player_id=0})
assert(a.removed and not live[ambient_a] and released[ambient_a]==1)
assert(wearables[1].removed and wearables[1].remove_count==1 and not wearables[2].removed)
assert(live[2],"one player's cleanup must preserve the other builder")
-- A unit index can be reused; the previous owner's particle must not linger.
local replacement=unit(b:entindex());replacement.survival_builder_id="default_builder"
presentation.apply(replacement,config)
assert(destroyed[2]==1 and released[2]==1)
assert(wearables[2].removed and wearables[2].remove_count==1)
local replacement_ambient=ids
bus.emit(events.ENGINE_ENTITY_KILLED,{victim=b,victim_entindex=b:entindex()})
assert(live[replacement_ambient],"old death must not clear a new owner at the same index")
presentation.clear(replacement);assert(not live[replacement_ambient])
assert(wearables[3].removed and wearables[3].remove_count==1)
-- Engine cleanup can re-enter the same owner/building cleanup path.
local reentrant, reentrant_building=unit(320),unit(321)
presentation.apply(reentrant,config);local reentrant_ambient=ids;local reentrant_wearable=wearables[#wearables]
presentation.construction_started(reentrant,reentrant_building);local reentrant_charge=ids
local original_destroy, entered=ParticleManager.DestroyParticle,false
ParticleManager.DestroyParticle=function(manager,id,immediate)
    if not entered then
        entered=true;presentation.clear(reentrant)
        presentation.construction_finished(reentrant_building,321)
    end
    original_destroy(manager,id,immediate)
end
presentation.clear(reentrant);ParticleManager.DestroyParticle=original_destroy
assert(entered and destroyed[reentrant_ambient]==1 and released[reentrant_ambient]==1
    and destroyed[reentrant_charge]==1 and released[reentrant_charge]==1,
    "reentrant cleanup must destroy/release each native particle only once")
assert(reentrant_wearable.removed and reentrant_wearable.remove_count==1)
-- Failed ownership/follow attachment must remove the partial cosmetic.
local normal_spawn=SpawnEntityFromTableSynchronous
local partial
SpawnEntityFromTableSynchronous=function(class,data)
    partial=normal_spawn(class,data);partial.FollowEntity=function() return false end;return partial
end
local intact=unit(400)
assert(presentation.apply(intact,config) and partial.removed and partial.remove_count==1)
assert(presentation.construction_started(intact,unit(401)),"cosmetic failure cannot disable builder work")
presentation.clear(intact);assert(partial.remove_count==1)
SpawnEntityFromTableSynchronous=normal_spawn
-- Particle creation failures are presentation-only; gesture and cleanup remain safe.
local original_create=ParticleManager.CreateParticle
ParticleManager.CreateParticle=function() error("missing renderer") end
local fallback=unit(300)
assert(presentation.apply(fallback,config))
assert(presentation.construction_started(fallback,unit(301)))
presentation.clear(fallback);ParticleManager.CreateParticle=original_create
-- A new world must never destroy particle IDs owned by a previous world.
presentation.apply(replacement,config);local previous_world_id=ids;local old_world_wearable=wearables[#wearables]
GameRules={GetGameTime=function() return clock end}
presentation.init();assert(not destroyed[previous_world_id] and not old_world_wearable.removed)
print("BUILDER_IO_PRESENTATION_PASS: native selectable Io body plus owned arcana/model/follow/sequence/cleanup, owner-isolated builder creation, phase/speed, native build gestures/audio, overlap/removal/death/disconnect/index/world/reentrant cleanup and renderer failure")
