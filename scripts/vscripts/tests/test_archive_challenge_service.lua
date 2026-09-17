package.path = "scripts/vscripts/?.lua;" .. package.path
local bus = require("core/event_bus")
local events = require("core/events")
local definitions = require("config/generated/archive_challenge_definitions")
local stats = require("config/generated/archive_challenge_stats")
local next_id, now, winner, spawned, granted = 10, 0, 0, {}, {}
local function entity()
    next_id = next_id + 1
    local unit = { id=next_id, abilities={}, alive=true }
    function unit:IsNull() return self.removed == true end
    function unit:entindex() return self.id end
    function unit:IsAlive() return self.alive end
    function unit:SetControllableByPlayer(id) self.owner = id end
    function unit:SetModel() end
    function unit:SetOriginalModel() end
    function unit:SetModelScale() end
    function unit:AddNewModifier() end
    function unit:SetBaseMagicalResistanceValue(v) self.magic = v end
    function unit:AddAbility(name)
        local ability = entity()
        ability.name = name; ability.caster = self
        function ability:SetLevel(n) self.level=n end
        function ability:SetActivated(v) self.activated=v end
        function ability:GetCaster() return self.caster end
        function ability:GetAbilityName() return self.name end
        function ability:StartCooldown(v) self.cooldown=v end
        function ability:EndCooldown() self.cooldown=0 end
        self.abilities[name] = ability
        return ability
    end
    function unit:FindAbilityByName(name) return self.abilities[name] end
    return unit
end
Vector = function(x,y,z) return {x=x,y=y,z=z} end
DOTA_TEAM_GOODGUYS=2
GameRules={GetGameTime=function() return now end, SetGameWinner=function() winner=winner+1 end}
CustomNetTables={SetTableValue=function() end}
UTIL_Remove=function(unit) unit.removed=true end
CreateUnitByName=function(name,position)
    local unit=entity();unit.name=name;unit.position=position;return unit
end
local tasks={}
package.loaded["core/scheduler"]={every=function(_,cb,key) tasks[key]=cb end,
    after=function(_,cb,key) tasks[key]=cb end, cancel=function(key) tasks[key]=nil end}
package.loaded["systems/player_context_service"]={
    register_unit=function(id,u) u.owner=id end, unregister_unit=function() end,
    owner_player_id=function(u) return u.owner end,
}
local marker={IsNull=function() return false end,GetAbsOrigin=function() return Vector(100,200,0) end}
package.loaded["systems/wave_system"]={
    get_player_spawn_marker=function() return marker end,
    spawn_challenge_monster=function(row,def,id)
        assert(row.health>0 and row.war3_armor>=0 and def.move_speed==280)
        local unit=entity();unit.owner=id;spawned[#spawned+1]=unit;return unit
    end,
}
package.loaded["systems/monster_hero_visual_service"]={clear=function() end}
local pending=false
package.loaded["systems/archive_service"]={
    record_challenge=function(id,challenge,seq) granted[#granted+1]={id=id,challenge=challenge,seq=seq} end,
    has_pending=function() return pending end,
}
local service=require("systems/archive_challenge_service")
service.init()
assert(not service.begin({difficulty_id="N2",player_ids={0}}).keep_running)
assert(service.begin({difficulty_id="N5",player_ids={0,1}}).keep_running)
local p=service._test.players()[0]
assert(#p.hubs==3 and p.hubs[1].position.x==-140 and p.hubs[2].position.x==100 and p.hubs[3].position.x==340)
local hub=p.hubs[1]
assert(not hub.abilities.ability_archive_endless, "no endless entry on hub1")
assert(p.hubs[2].abilities.ability_archive_endless, "endless entry on hub2")
assert(not p.hubs[3].abilities.ability_archive_endless, "no endless entry on hub3")
assert(not service.start_endless(hub,p.hubs[2].abilities.ability_archive_endless), "wrong hub rejected")
local count=0;for _ in pairs(hub.abilities) do count=count+1 end
assert(count==11)
assert(hub.abilities.ability_archive_hunt_01.activated)
assert(not hub.abilities.ability_archive_hunt_02.activated)
assert(not hub.abilities.ability_archive_cage_1.activated)
local function summon(id)
    return service.summon(hub,id,hub.abilities["ability_archive_"..id])
end
assert(not summon("hunt_02"), "N6 gate")
assert(summon("hunt_01"))
assert(not summon("shadow_1"), "one active boss per player")
local other=service._test.players()[1].hubs[1]
assert(service.summon(other,"shadow_1",other.abilities.ability_archive_shadow_1))
assert(not service.summon(hub,"shadow_1",other.abilities.ability_archive_shadow_1), "caster mismatch")
bus.emit(events.ENGINE_ENTITY_KILLED,{victim=spawned[1],victim_entindex=spawned[1].id})
bus.emit(events.ENGINE_ENTITY_KILLED,{victim=spawned[1],victim_entindex=spawned[1].id})
assert(#granted==1 and granted[1].id==0 and granted[1].challenge=="hunt_01")
assert(not summon("hunt_01"), "server cooldown")
now=400;assert(not summon("hunt_01"), "used challenge never unlocks after cooldown")
assert(not hub.abilities.ability_archive_hunt_01.activated, "used button stays disabled")
assert(summon("shadow_1"), "unused challenge still available")
pending=true;assert(not service.finish(p.hubs[3]));pending=false
assert(service.finish(p.hubs[3]) and winner==0)
assert(#granted==1, "finish cleanup grants no rewards")
bus.emit(events.PLAYER_DISCONNECTED,{player_id=1})
assert(winner==1)
assert(#granted==1, "disconnect cleanup grants no rewards")
assert(service.begin({difficulty_id="N10",player_ids={0}}).keep_running)
local expanded = service._test.players()[0]
for _, challenge in ipairs({"hunt_05","hunt_06","hunt_07","hunt_08","hunt_09","hunt_10","hunt_11","hunt_12","cage_4","cage_5","cage_6"}) do
    local definition = definitions.by_id[challenge]
    local owner = expanded.hubs[definition.building_id]
    local ability = assert(owner.abilities["ability_archive_" .. challenge])
    assert(ability.activated, challenge .. " enabled at N10")
    local before = #spawned
    assert(service.summon(owner, challenge, ability))
    assert(#spawned == before+1 and not ability.activated, "one boss and immediate disable")
    local boss = spawned[#spawned]
    bus.emit(events.ENGINE_ENTITY_KILLED,{victim=boss,victim_entindex=boss.id})
    assert(granted[#granted].challenge == challenge, "correct reward route")
    now = now + 100
    assert(not service.summon(owner,challenge,ability), "one attempt for expanded skills")
end
for _, row in ipairs(definitions.rows) do
    local template=assert(stats.by_id[row.challenge_id.."_N5"])
    for n=6,10 do
        local other=assert(stats.by_id[row.challenge_id.."_N"..n])
        for _, field in ipairs({"health","attack","war3_armor","attack_speed","move_speed","attack_range","magic_resistance"}) do
            assert(other[field]==template[field])
        end
    end
end
local waves=require("config/generated/wave_definitions")
local builder=require("systems/wave_difficulty_builder")
local n5=assert(builder.build(waves.rows,"N5"))
for n=6,10 do
    local result=assert(builder.build(waves.rows,"N"..n))
    assert(#result.rows==#n5.rows and result.total_waves==30)
    for i,row in ipairs(result.rows) do
        for field,value in pairs(n5.rows[i]) do
            if field~="wave_id" and field~="difficulty_id" then assert(row[field]==value, field) end
        end
    end
end
local current = service._test.players()[0]
local endless_entry = current.hubs[2].abilities.ability_archive_endless
assert(service.start_endless(current.hubs[2], endless_entry))
assert(not current.hubs[1].abilities.ability_archive_shadow_4.activated)
assert(require("systems/archive_endless_service").on_wall_destroyed(0))
assert(not endless_entry.activated, "endless cannot restart after wall destruction")
assert(current.hubs[1].abilities.ability_archive_shadow_4.activated, "other challenges reactivate")
assert(service.summon(current.hubs[1], "shadow_4", current.hubs[1].abilities.ability_archive_shadow_4))
local boss = spawned[#spawned]
bus.emit(events.ENGINE_ENTITY_KILLED,{victim=boss,victim_entindex=boss.id})
for _, id in ipairs({"social_friend","social_ex","social_beast"}) do
    assert(not current.hubs[1].abilities["ability_archive_"..id])
    assert(not current.hubs[2].abilities["ability_archive_"..id])
    local hub3=current.hubs[3]
    local before=#spawned
    assert(service.summon(hub3,id,hub3.abilities["ability_archive_"..id]))
    assert(#spawned==before+1, "one social boss")
    local unit=spawned[#spawned]
    bus.emit(events.ENGINE_ENTITY_KILLED,{victim=unit,victim_entindex=unit.id})
    assert(granted[#granted].challenge==id)
    assert(not service.summon(hub3,id,hub3.abilities["ability_archive_"..id]), "social challenge once per match")
end
print("ARCHIVE_CHALLENGE_SERVICE_PASS: hubs, gates, cooldown, multiplayer, death dedup, finish, N5 copies, wall destruction recovery")
