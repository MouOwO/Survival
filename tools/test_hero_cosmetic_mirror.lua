-- Real cosmetic/weapon-slot code and Drow asset catalog; native APIs are mocked.
package.path = "scripts/vscripts/?.lua;" .. package.path
local tasks, entities, particles, world = {}, {}, {}, {}
local serial, particle_serial, spawns = 0, 0, 0
local fail_model, fail_particle, fail_cp, on_create, on_destroy
package.loaded["core/logger"] = {info=function() end,warn=function() end}
package.loaded["core/scheduler"] = {
    after=function(_,callback,id) tasks[id]=callback;return id end,
    cancel=function(id) tasks[id]=nil end,
}
GameRules = {GetGameModeEntity=function() return world end}
PATTACH_ABSORIGIN_FOLLOW,PATTACH_POINT_FOLLOW,PATTACH_WORLDORIGIN = 1,2,3
PATTACH_ABSORIGIN,PATTACH_POINT,PATTACH_CUSTOMORIGIN = 4,5,6
EF_NODRAW = 32
Vector=function(x,y,z) return {x=x,y=y,z=z} end
local function forbidden() error("appearance must not change gameplay or equipment") end
CreateUnitByName,CreateItem,ApplyDamage = forbidden,forbidden,forbidden
local function entity(class_name,model)
    serial=serial+1
    local unit={index=serial,class_name=class_name,model=model,scale=1,skin=0,origin=Vector(0,0,0)}
    entities[#entities+1]=unit
    function unit:IsNull() return self.removed==true end
    function unit:entindex() return self.index end
    function unit:GetClassname() return self.class_name end
    function unit:GetModelName() return self.model end
    function unit:GetModelScale() return self.scale end
    function unit:GetSkin() return self.skin end
    function unit:GetMaterialGroup() return self.material_group end
    function unit:GetMaterialGroupHash() return self.material_hash end
    function unit:GetAbsOrigin() return self.origin end
    function unit:GetOwner() return self.owner end
    function unit:GetOwnerEntity() return self.owner end
    function unit:GetParent() return self.parent end
    function unit:GetMoveParent() return self.parent end
    function unit:SetOwner(value) self.owner=value end
    function unit:FollowEntity(value,merge) assert(merge);self.parent=value end
    function unit:SetParent(value,attachment) self.parent=value;self.attachment=attachment end
    function unit:SetLocalOrigin(value) self.offset=value end
    function unit:SetModel(value) self.model=value end
    function unit:SetOriginalModel(value) self.original_model=value end
    function unit:SetModelScale(value) self.scale=value end
    function unit:SetSkin(value) self.skin=value end
    function unit:SetMaterialGroup(value) self.material_group=value end
    function unit:SetMaterialGroupHash(value) self.material_hash=value end
    function unit:GetEffects() return self.hidden and 32 or 0 end
    function unit:AddEffects() self.hidden=true end
    function unit:RemoveEffects() self.hidden=false end
    function unit:AddNoDraw() self.hidden=true end
    function unit:RemoveNoDraw() self.hidden=false end
    function unit:SetRenderAlpha(value) self.alpha=value end
    function unit:AddActivityModifier(value) self.activity=value end
    function unit:ScriptLookupAttachment() return 1 end
    function unit:GetChildren()
        local result={};for _,child in ipairs(entities) do
            if child.parent==self and not child:IsNull() then result[#result+1]=child end
        end;return result
    end
    function unit:FirstMoveChild() return self:GetChildren()[1] end
    function unit:NextMovePeer()
        if not self.parent then return nil end
        local found=false;for _,child in ipairs(self.parent:GetChildren()) do
            if found then return child end;if child==self then found=true end
        end
    end
    unit.AddItem,unit.AddNewModifier,unit.SetBaseDamageMin,unit.SetBaseAttackTime=forbidden,forbidden,forbidden,forbidden
    return unit
end
SpawnEntityFromTableSynchronous=function(class_name,values)
    if fail_model==values.model then fail_model=nil;error("injected model failure") end
    spawns=spawns+1;return entity(class_name,values.model)
end
UTIL_Remove=function(unit) assert(not unit.removed,"double entity removal");unit.removed=true end
Entities={FindAllByClassname=function(_,name)
    local result={};for _,unit in ipairs(entities) do
        if unit.class_name==name and not unit:IsNull() then result[#result+1]=unit end
    end;return result
end}
ParticleManager={
    CreateParticle=function(_,path,attach,owner)
        if fail_particle==path then fail_particle=nil;error("injected particle failure") end
        particle_serial=particle_serial+1
        particles[particle_serial]={path=path,attach=attach,owner=owner,cp={}}
        local id=particle_serial
        if on_create then local callback=on_create;on_create=nil;callback() end
        return id
    end,
    SetParticleControl=function(_,id,cp,value) particles[id].cp[cp]=value end,
    SetParticleControlEnt=function(_,id,cp,owner,attach,point,origin)
        if fail_cp then fail_cp=false;error("injected CP failure") end
        particles[id].cp[cp]={owner=owner,attach=attach,point=point,origin=origin}
    end,
    DestroyParticle=function(_,id)
        assert(not particles[id].destroyed,"double particle destroy");particles[id].destroyed=true
        if on_destroy then local callback=on_destroy;on_destroy=nil;callback(id) end
    end,
    ReleaseParticleIndex=function(_,id) assert(not particles[id].released,"double particle release");particles[id].released=true end,
}
local service=require("systems/hero_cosmetic_service")
local function hero()
    local unit=entity("npc_dota_hero_drow_ranger","models/heroes/drow/drow_base.vmdl")
    unit.survival_hero_id="hero_drow_ranger";return unit
end
local function owned(unit)
    local result={};for _,entry in ipairs(entities) do
        if entry.owner==unit and not entry:IsNull()
            and (entry.class_name=="prop_dynamic" or entry.class_name=="dota_item_wearable") then result[#result+1]=entry end
    end;return result
end
local function active_particles(unit)
    local result={};for id,p in pairs(particles) do
        if not p.destroyed and (p.owner==unit or p.owner.owner==unit) then result[#result+1]=id end
    end;return result
end
local source=hero();assert(service.apply(source,"hero_drow_ranger"))
source:SetModelScale(1.25);source:SetSkin(2);source:SetMaterialGroup("blue");source.material_hash=123
local original=owned(source);assert(#original==7 and #active_particles(source)==5)
local original_particles=active_particles(source)
local target=entity("npc_dota_creature","models/heroes/drow/drow_base.vmdl");target:SetOwner(source)
local native=entity("dota_item_wearable","default.vmdl");native.parent=target;native.owner=target
assert(service.sync_appearance(target,source))
assert(target.model==source.model and target.scale==1.25 and target.skin==2)
assert(target.material_group=="blue" and target.material_hash==123)
assert(native.hidden and #active_particles(target)==5)
local initial=owned(target);assert(#initial==8)
local initial_spawns,initial_particles=spawns,particle_serial
for _=1,100 do assert(service.sync_appearance(target,source)) end
assert(spawns==initial_spawns and particle_serial==initial_particles,"unchanged polls must reuse all visuals")
for _,entry in ipairs(original) do assert(not entry:IsNull() and not entry.hidden and entry.parent==source) end
for _,id in ipairs(original_particles) do assert(not particles[id].destroyed) end

-- Actual body changes invalidate the cache without changing the main hero.
source:SetModel("models/heroes/drow/current_body.vmdl");source:SetModelScale(1.5)
assert(service.sync_appearance(target,source));assert(target.model==source.model and target.scale==1.5)
for _,entry in ipairs(initial) do if entry~=native then assert(entry.removed) end end

-- Current weapon declaration, unavailable skin getter, and full CP/offset data.
local weapon_id="wandering_isles_weapon"
local appearance={hero_id="hero_drow_ranger",component_id=weapon_id,key="current_bow",
    model="models/current_bow.vmdl",skin=1,material_group="frost",particles={{
        id="bow",path="particles/current_bow.vpcf",owner=weapon_id,attach_type="PATTACH_ABSORIGIN_FOLLOW",
        control_points={{cp=0,entity="self",attach_type="PATTACH_POINT_FOLLOW",attachment="attack"},
            {cp=1,entity="parent",attach_type="PATTACH_ABSORIGIN_FOLLOW"},
            {cp=2,entity="self",attach_type="PATTACH_POINT_FOLLOW",attachment="attack",offset={0,20,0}}}}}}
assert(service.apply_weapon(source,appearance))
local source_weapon=service.weapon_snapshot(source,weapon_id).wearable
source_weapon.GetSkin=false
assert(service.sync_appearance(target,source))
local copied=service.weapon_snapshot(target,weapon_id).wearable
assert(copied~=source_weapon and copied.model==appearance.model and copied.skin==1 and copied.material_group=="frost")
local bow_particle
for _,id in ipairs(active_particles(target)) do if particles[id].path=="particles/current_bow.vpcf" then bow_particle=particles[id] end end
assert(bow_particle and bow_particle.cp[0].owner==copied and bow_particle.cp[1].owner==target)
assert(bow_particle.cp[2].owner~=copied and bow_particle.cp[2].owner.owner==target)
assert(bow_particle.cp[2].owner.parent==copied and bow_particle.cp[2].owner.offset.y==20)
assert(source_weapon.parent==source and not source_weapon.hidden)

-- Failed allocation/CP binding keeps the previous target visuals and source.
source:SetModelScale(1.6);fail_model=appearance.model
local before=owned(target)
assert(not service.sync_appearance(target,source))
for _,entry in ipairs(before) do assert(not entry.removed) end
assert(target.scale==1.5 and not source_weapon.removed)
fail_cp=true;assert(not service.sync_appearance(target,source))
assert(target.scale==1.5 and not source_weapon.removed)
for _,entry in ipairs(before) do assert(not entry.removed) end
assert(service.sync_appearance(target,source) and target.scale==1.6)

-- A source transaction during allocation must not commit stale appearances.
source:SetModelScale(1.7)
on_create=function() service.clear(source) end
assert(not service.sync_appearance(target,source))
assert(service.apply(source,"hero_drow_ranger"));source:SetModelScale(1.8)
assert(service.sync_appearance(target,source))
local final=owned(target);local final_particles=active_particles(target)
service.clear(target);service.clear(target)
for _,entry in ipairs(final) do if entry~=native then assert(entry.removed) end end
for _,id in ipairs(final_particles) do assert(particles[id].destroyed and particles[id].released) end
assert(#owned(source)==7 and #active_particles(source)==5)
assert(service.sync_appearance(target,source),"clear must invalidate the mirror cache")

local fallback=hero();local fallback_target=entity("npc_dota_creature",fallback.model)
fallback.GetSkin=false
assert(service.sync_appearance(fallback_target,fallback))
assert(#owned(fallback_target)==7 and #active_particles(fallback_target)==5)
-- A removed handle must still retire independent props/particles. A newer
-- target reusing the same integer entity index keeps its separate ownership.
local removed=entity("npc_dota_creature",fallback.model)
assert(service.sync_appearance(removed,fallback))
local removed_parts,removed_particles=owned(removed),active_particles(removed)
local reused=entity("npc_dota_creature",fallback.model);reused.index=removed.index
removed.removed=true;removed.entindex=function() error("deleted entity") end
assert(service.sync_appearance(reused,fallback))
local reused_parts,reused_particles=owned(reused),active_particles(reused)
service.clear(removed);service.clear(removed)
for _,entry in ipairs(removed_parts) do assert(entry.removed) end
for _,id in ipairs(removed_particles) do assert(particles[id].destroyed and particles[id].released) end
for _,entry in ipairs(reused_parts) do assert(not entry.removed) end
for _,id in ipairs(reused_particles) do assert(not particles[id].destroyed) end
local reused_spawns=spawns;assert(service.sync_appearance(reused,fallback));assert(spawns==reused_spawns)
service.clear(reused)
assert(not service.sync_appearance(source,source))
source.removed=true;assert(not service.sync_appearance(target,source))
service.clear(target);service.clear(fallback_target)
local world_target=entity("npc_dota_creature",fallback.model)
assert(service.sync_appearance(world_target,fallback))
local old_world_particles=active_particles(world_target);local old_world_parts=owned(world_target)
on_destroy=function()
    world={}
    for _,id in ipairs(old_world_particles) do particles[id]={path="new_world",cp={},owner=fallback} end
end
service.clear(world_target)
for _,id in ipairs(old_world_particles) do assert(not particles[id].destroyed and not particles[id].released) end
for _,entry in ipairs(old_world_parts) do assert(not entry.removed,"old world cleanup must stop before entity removal") end

-- MK/Blade must mirror committed native weapon effects, including an empty
-- effect list. This exercises actual weapon selection/slot/mirror code; the
-- gameplay clone services have their own event/lifecycle regression fixtures.
local bus = require("core/event_bus")
local events = require("core/events")
local weapon_cosmetic = require("systems/hero_weapon_cosmetic_service")
local weapons = require("config/generated/weapon_definitions")
local clone_by_source, notifications = {}, {}
weapon_cosmetic.reset(false)
bus.subscribe(events.HERO_COSMETICS_CHANGED, function(payload)
    local clone = clone_by_source[payload.unit]
    if not clone then return end
    assert(payload.player_id == payload.unit.survival_player_id)
    local component = payload.unit.survival_hero_id == "hero_monkey_king"
        and "demon_trickster_staff" or "weapon"
    local committed = assert(service.weapon_snapshot(payload.unit, component))
    assert(not committed.busy, "mirror notification must run after slot unlock")
    assert(service.sync_appearance(clone, payload.unit), "committed appearance must be immediately readable")
    notifications[payload.unit] = (notifications[payload.unit] or 0) + 1
end)
local function content_for(series)
    for _, row in ipairs(weapons.rows) do
        if row.series_id == series and row.equipment_slot == "main_hand"
            and row.enabled ~= false then return row.content_id end
    end
    error("missing real weapon series " .. series)
end
for index, hero_id in ipairs({"hero_monkey_king", "hero_blademaster"}) do
    local model = hero_id == "hero_monkey_king"
        and "models/heroes/monkey_king/monkey_king.vmdl"
        or "models/heroes/juggernaut/juggernaut.vmdl"
    local owner = entity("npc_dota_hero", model)
    owner.survival_hero_id, owner.survival_player_id = hero_id, index - 1
    function owner:IsAlive() return not self.dead end
    local clone = entity("npc_dota_hero", model)
    assert(service.apply(owner, hero_id))
    assert(service.sync_appearance(clone, owner))
    clone_by_source[owner] = clone
    weapon_cosmetic.on_hero_summoned({player_id = index - 1, unit = owner, hero_id = hero_id})
    local component = hero_id == "hero_monkey_king" and "demon_trickster_staff" or "weapon"
    for _, series in ipairs({"ice_blade", "epic_icefire",
        hero_id == "hero_monkey_king" and "growth_sword" or "frost_blade", "ice_blade"}) do
        local old_clone_weapon = service.weapon_snapshot(clone, component).wearable
        local old_particle_ids = active_particles(clone)
        local before = notifications[owner]
        local content = content_for(series)
        weapon_cosmetic.on_equipped({player_id = index - 1, slot = "main_hand", content_id = content})
        assert(notifications[owner] == before + 1, "one real slot commit must notify once")
        local source_slot = assert(service.weapon_snapshot(owner, component))
        local clone_slot = assert(service.weapon_snapshot(clone, component))
        local empty = (hero_id == "hero_monkey_king" and series == "growth_sword")
            or (hero_id == "hero_blademaster" and series == "frost_blade")
        assert(source_slot.particle_count == (empty and 0 or 1))
        assert(clone_slot.particle_count == source_slot.particle_count,
            "no-effect equipment must clear the previous clone weapon effects")
        assert(clone_slot.wearable.model == source_slot.wearable.model
            and clone_slot.wearable.skin == source_slot.wearable.skin)
        assert(old_clone_weapon.removed)
        for _, id in ipairs(old_particle_ids) do assert(particles[id].destroyed and particles[id].released) end
        before = notifications[owner]
        local allocations = particle_serial
        weapon_cosmetic.on_equipped({player_id = index - 1, slot = "main_hand", content_id = content})
        weapon_cosmetic.poll()
        assert(notifications[owner] == before and particle_serial == allocations,
            "unchanged equipment must not notify or recreate mirror effects")
    end
    local before = notifications[owner]
    assert(service.clear_weapon(owner, component))
    assert(notifications[owner] == before + 1)
    assert(service.weapon_snapshot(clone, component).particle_count == 0)
    assert(service.weapon_snapshot(clone, component).wearable == nil)
    service.clear(clone); service.clear(owner)
    clone_by_source[owner] = nil
end
print("HERO_COSMETIC_MIRROR_PASS Drow7+5 body cache current_weapon CP_offsets rollback removed_target reused_entindex reused_world cleanup fallback source_isolation")
print("CLONE_WEAPON_EFFECT_MIRROR_PASS MK/Blade committed native weapon effects, changed effects, empty effects, clear, stable polling and source isolation")
