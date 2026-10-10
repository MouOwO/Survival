package.path = "scripts/vscripts/?.lua;" .. package.path
local no_op = function() end
package.loaded["core/logger"] = {info=no_op,warn=no_op}
local current_time, next_index, total_spawns, total_scans = 0, 0, 0, 0
GameRules = {GetGameTime=function() return current_time end}
Vector = function(x,y,z) return {x=x,y=y,z=z} end
SOLID_NONE, PATTACH_ABSORIGIN_FOLLOW, PATTACH_POINT_FOLLOW = 0, 1, 4
local removed, invalid_native_calls = {}, 0
UTIL_Remove = function(entity)
    removed[entity] = (removed[entity] or 0) + 1
    assert(removed[entity]==1, "same prop cannot be removed twice")
    entity.removed = true
end
IsValidEntity = function(entity) return not entity.removed end
local all_entities = setmetatable({}, {__mode="v"})
local function make_entity(model, forced_index)
    next_index = next_index + 1
    local value={index=forced_index or next_index,model=model,origin=Vector(10,20,100),skin=0,activities={},bodygroups={}}
    function value:IsNull() return self.removed == true end
    function value:IsAlive() return self.dead ~= true end
    function value:entindex() assert(not self.removed,"entindex must never be called on a null owner"); return self.index end
    function value:GetUnitName() return "npc_test" end
    function value:GetClassname() return self.class or "npc_dota_creature" end
    function value:GetAbsOrigin() assert(not self.removed); return self.origin end
    function value:SetAbsOrigin(origin) assert(not self.removed); self.origin=origin end
    function value:SetModel(path) self.model=path end
    value.SetOriginalModel=value.SetModel
    function value:GetModelName() return self.model end
    function value:SetOwner(owner) self.owner=owner end
    function value:GetOwner() return self.owner end
    function value:SetParent(parent) self.parent=parent end
    function value:FollowEntity(parent,merge) assert(merge and parent==self.parent); self.follow=parent end
    function value:SetSkin(skin) self.skin=skin end
    function value:GetSkin() return self.skin end
    function value:AddActivityModifier(name) self.activities[name]=true end
    function value:ClearActivityModifiers() self.activities={} end
    function value:SetBodygroupByName(name,number) self.bodygroups[name]=number end
    function value:AddNoDraw() self.hidden=true end
    function value:RemoveNoDraw() self.hidden=false end
    for _,method in ipairs({"SetModelScale","SetSolid","SetPlaybackRate","SetAngles","ResetSequenceInfo","ResetSequence","SetAttackCapability","SetRangedProjectileName","AddEffects"}) do value[method]=no_op end
    for name,method in pairs(value) do
        if type(method)=="function" and name~="IsNull" then
            local native=method
            value[name]=function(self,...)
                if self.removed then invalid_native_calls=invalid_native_calls+1;error("native method called on null entity: "..name) end
                return native(self,...)
            end
        end
    end
    all_entities[#all_entities+1]=value
    return value
end
SpawnEntityFromTableSynchronous=function(class,data)
    total_spawns=total_spawns+1
    local value=make_entity(data.model); value.class=class; return value
end
Entities={FindAllByClassname=function(_,class)
    total_scans=total_scans+1
    local found={}
    for _,entity in pairs(all_entities) do if entity.class==class and not entity.removed then found[#found+1]=entity end end
    return found
end}
local particle_serial, particles = 0, {}
ParticleManager={
    CreateParticle=function(_,path,attach,owner)
        assert(owner and not owner.removed)
        particle_serial=particle_serial+1
        particles[particle_serial]={path=path,owner=owner,destroy=0,release=0}
        return particle_serial
    end,
    DestroyParticle=function(_,index,immediate)
        local state=assert(particles[index]); state.destroy=state.destroy+1; state.immediate=immediate
        assert(state.destroy==1,"particle destroyed twice")
        if state.fail_destroy then error("mock native destroy failure") end
    end,
    ReleaseParticleIndex=function(_,index)
        local state=assert(particles[index]); state.release=state.release+1
        assert(state.release==1,"particle released twice")
    end,
    SetParticleControlEnt=no_op,SetParticleControl=no_op,
}
package.loaded["systems/combat_effect_visibility"]={manager=function() return ParticleManager end}
package.loaded["systems/asset_preload_service"]={is_ready=function() return true end,STATE={FAILED="failed",RETIRED="retired"}}
package.loaded["visual/native_wearable_carrier_service"]={Clear=no_op}
package.loaded["systems/challenge_guardian_visual_service"]={apply=no_op,clear=no_op}
package.loaded["systems/unit_health_bar_service"]={exclude=no_op}
local handlers={}
package.loaded["core/event_bus"]={subscribe=function(event,fn)
    handlers[event]=handlers[event] or {}; handlers[event][#handlers[event]+1]=fn
end}
local events=require("core/events")
local scheduler=require("core/scheduler")
local catalog=require("config/asset_catalog")
local generic=require("systems/monster_visual_service")
local hero=require("systems/monster_hero_visual_service")
local challenge=require("systems/challenge_monster_visual_service")
local appearance=require("visual/model_appearance_service")
local building=require("systems/building_visual_service")
local lifecycle=require("systems/monster_corpse_lifecycle_service")
local defaults=assert(catalog.resolve("monster_wave_demon_purple_melee"))
local molten=assert(catalog.resolve("challenge_monster_ember_searing_path"))
local neutral={primary_model="neutral.vmdl",model_path="neutral.vmdl",visual_asset_id="test_neutral",components={{model_path="neutral_head.vmdl"},{model_path="neutral_back.vmdl"}},effects={{particle_path="neutral_ambient.vpcf",max_per_unit=2}}}
assert(#molten.components==6 and #molten.environment_particles==7,"fixture must use real molten outfit and all seven ambient effects")
-- Also verify death keeps activity/bodygroup setup until visual disposal.
defaults.activity_modifiers[#defaults.activity_modifiers+1]={enabled=true,modifier_name="test_cosmetic"}
molten.activity_modifiers[#molten.activity_modifiers+1]={enabled=true,modifier_name="test_cosmetic"}
molten.bodygroups[#molten.bodygroups+1]={bodygroup_name="test_cosmetic",value=1}
local function count(table) local result=0;for _ in pairs(table) do result=result+1 end;return result end
local function find_upvalue(module,wanted)
    local seen={}
    local function visit(fn)
        if type(fn)~="function" or seen[fn] then return end
        seen[fn]=true
        for index=1,math.huge do
            local name,value=debug.getupvalue(fn,index)
            if not name then break end
            if name==wanted then return value end
            if type(value)=="function" then local found=visit(value); if found~=nil then return found end end
        end
    end
    for _,fn in pairs(module) do local found=visit(fn); if found~=nil then return found end end
end
local function clean_caches()
    assert(invalid_native_calls==0,"cleanup called native methods on removed entity")
    for _,attempts in pairs(removed) do assert(attempts==1,"cleanup repeated native removal") end
    for _,name in ipairs({"states_by_unit","generation_by_unit","verification_retries_by_unit"}) do
        local state=find_upvalue(appearance,name)
        if state then assert(count(state)==0,"appearance cache accumulates after corpse disposal: "..name) end
    end
    for _,name in ipairs({"activity_modifiers_by_unit","particles_by_unit","bodygroups_by_unit","visual_owners_by_unit","deaths_by_unit"}) do
        local state=find_upvalue(building,name)
        if state then assert(count(state)==0,"building visual cache accumulates after corpse disposal: "..name) end
    end
    assert(generic.active_state_count()==0,"generic monster cache accumulates after corpse disposal")
    local corpse_cache=assert(find_upvalue(lifecycle,"corpses"))
    assert(count(corpse_cache)==0,"corpse tracker accumulates after disposal")
    assert(scheduler.task_count()==0,"scheduled visual work accumulates after corpse disposal")
end
local function emit_death(unit)
    for _,handler in ipairs(handlers[events.ENGINE_ENTITY_KILLED] or {}) do handler({victim=unit}) end
end
local function advance(delta)
    current_time=current_time+delta
    scheduler.think()
end
local function make_monster(kind,track,forced_index)
    local birth_queries=total_scans
    local asset=kind=="default" and defaults or kind=="molten" and molten or neutral
    local unit=make_entity(asset.primary_model,forced_index)
    local first=particle_serial+1
    if kind=="default" then
        assert(hero.apply(unit,{default_wearable_asset_id=asset.asset_id,model_path=asset.primary_model},
            {allow_outside_formal_wave=true,fresh_unit=true}))
    elseif kind=="neutral" then
        assert(generic.apply(unit,neutral))
        unit.activities.test_cosmetic=true
    else
        assert(challenge.apply(unit,{model_asset_id=asset.asset_id,model_path=asset.primary_model,attack_type="melee"},{fresh_unit=true}))
    end
    assert(total_scans==birth_queries,"new monsters must not scan the world for old outfits")
    local components={}
    local registry=assert(find_upvalue(appearance,"states_by_unit"))
    for _,component in ipairs(kind=="neutral" and generic._state_for_test(unit.index).attachments or assert(registry[unit.index]).wearables) do components[#components+1]=component end
    assert(#components==#asset.components and unit.activities.test_cosmetic)
    if track~=false then assert(lifecycle.track(unit,"test")) end
    local ids={};for id=first,particle_serial do ids[#ids+1]=id end
    assert(#ids==(kind=="default" and 1 or kind=="molten" and 7 or 2),"all ambient particle handles must be created")
    return unit,components,ids
end
local function assert_particles_stopped(ids)
    for _,index in ipairs(ids) do
        local state=particles[index]
        assert(state.destroy==1 and state.immediate==true and state.release==1,"death must immediately destroy and release particle once: "..index)
    end
end
local function on_death(kind,unit)
    unit.dead=true
    if kind=="default" then assert(hero.on_death(unit)) elseif kind=="molten" then assert(challenge.on_death(unit)) else assert(generic.on_death(unit)) end
    emit_death(unit)
end
local function clear(kind,unit)
    if kind=="default" then assert(hero.clear(unit)) elseif kind=="molten" then assert(challenge.clear(unit)) else generic.cleanup(unit) end
end
lifecycle.init()
for _,kind in ipairs({"default","molten","neutral"}) do
    local unit,components,ids=make_monster(kind)
    local initial_skin=unit.skin
    local before_spawns, before_queries=total_spawns,total_scans
    on_death(kind,unit)
    on_death(kind,unit)
    assert_particles_stopped(ids)
    assert(scheduler.task_count()<=2,"death must use one shared corpse task and original verification only")
    for _,component in ipairs(components) do assert(not component.removed,"death immediately stripped the outfit") end
    assert(unit.skin==initial_skin and unit.activities.test_cosmetic,"death erased skin/activity setup")
    advance(0.3)
    assert(unit.origin.z==100 and not unit.hidden,"corpse must hold its original pose/position")
    advance(0.4)
    assert(unit.origin.z<100 and unit.origin.z>-60,"corpse must sink gradually")
    for _,component in ipairs(components) do assert(not component.removed,"sinking stripped the outfit early") end
    assert(unit.skin==initial_skin and unit.activities.test_cosmetic)
    advance(0.8)
    assert(unit.hidden,"completed corpse must be hidden")
    for _,component in ipairs(components) do assert(component.removed and removed[component]==1,"final disposal must remove each prop once") end
    advance(0.1)
    assert(unit.removed,"hidden corpse must leave the world")
    clear(kind,unit);clear(kind,unit)
    assert_particles_stopped(ids)
    assert(total_spawns==before_spawns,"death/disposal must not recreate outfit components")
    assert(total_scans==before_queries,"death/final/repeated cleanup must never scan world entities")
    clean_caches()
end
print("MONSTER_DEATH_RETENTION_PASS default outfit + real molten outfit, immediate seven-particle disposal, dressed hold/sink, exact final cleanup")
for _,kind in ipairs({"default","molten","neutral"}) do
    -- Forced cleanup on a tracked corpse must release immediately.
    local unit,components,ids=make_monster(kind)
    unit.survival_wave_cleanup=true
    on_death(kind,unit)
    assert_particles_stopped(ids)
    for _,component in ipairs(components) do assert(component.removed) end
    clear(kind,unit);advance(0.1);clean_caches()
    -- An untracked body cannot leave props/handles without a corpse task.
    unit,components,ids=make_monster(kind,false)
    on_death(kind,unit)
    assert_particles_stopped(ids)
    for _,component in ipairs(components) do assert(component.removed) end
    clear(kind,unit);advance(0.1);clean_caches()
    -- Engine-side removal before visual tick must use owner identity safely.
    unit,components,ids=make_monster(kind)
    on_death(kind,unit)
    unit.removed=true
    advance(0.1)
    for _,component in ipairs(components) do assert(component.removed) end
    assert_particles_stopped(ids)
    clear(kind,unit);clean_caches()
end
print("MONSTER_DEATH_BOUNDARIES_PASS forced cleanup, no corpse tracker, null owner, repeated cleanup")
for _,kind in ipairs({"default","molten","neutral"}) do
    local old,old_components,old_ids=make_monster(kind,true,90000)
    local task=find_upvalue(scheduler,"tasks")["appearance_verify_"..old.index]
    local old_verification=task and task.callback
    on_death(kind,old)
    old.removed=true
    local replacement,new_components,new_ids=make_monster(kind,true,90000)
    if old_verification then old_verification() end
    clear(kind,old)
    clear(kind,old)
    emit_death(old)
    advance(0.1)
    for _,component in ipairs(old_components) do assert(component.removed,"index reuse must retire original outfit") end
    for _,component in ipairs(new_components) do assert(not component.removed,"old corpse cleanup must not strip reused entity index") end
    for _,index in ipairs(new_ids) do assert(particles[index].destroy==0 and particles[index].release==0,"old corpse cleanup stopped successor particles") end
    on_death(kind,replacement)
    advance(1.5);advance(0.1)
    assert(replacement.removed)
    assert_particles_stopped(old_ids);assert_particles_stopped(new_ids)
    clean_caches()
end
print("MONSTER_DEATH_INDEX_REUSE_PASS invalid old handles and duplicate cleanup preserve live successors")
for _,kind in ipairs({"default","molten","neutral"}) do
    local unit,components,ids=make_monster(kind)
    particles[ids[1]].fail_destroy=true
    on_death(kind,unit)
    assert_particles_stopped(ids)
    advance(1.5);advance(0.1)
    assert(unit.removed)
    clean_caches()
end
print("MONSTER_DEATH_RELEASE_FAILURE_PASS native destroy failures still release all particle indices once")
-- Purging per-index generations must still reject callbacks from a prior
-- attachment transaction on the same engine handle.
local unit=make_entity("generation.vmdl")
local asset_a={asset_id="generation_a",components={{component_id="head",model_path="a.vmdl",attach_mode="bone_merge"}}}
local asset_b={asset_id="generation_b",components={{component_id="head",model_path="b.vmdl",attach_mode="bone_merge"}}}
assert(appearance.Apply(unit,asset_a,{fresh_unit=true}))
local old_verification=assert(find_upvalue(scheduler,"tasks")["appearance_verify_"..unit.index]).callback
assert(appearance.Clear(unit))
local ok,_,new_components=appearance.Apply(unit,asset_b,{fresh_unit=true})
assert(ok)
new_components.head.removed=true
local before=total_spawns
old_verification()
assert(total_spawns==before,"retired generation must never refresh its old outfit on the same handle")
assert(appearance.Clear(unit))
advance(0.1);clean_caches()
print("MONSTER_DEATH_GENERATION_PASS retired callbacks cannot revive old appearances after registry purge")
local resetting={}
for _,kind in ipairs({"default","molten","neutral"}) do
    local unit,components,ids=make_monster(kind)
    resetting[#resetting+1]={unit=unit,components=components,ids=ids}
    on_death(kind,unit)
end
resetting[2].unit.removed=true
handlers={}
lifecycle.init()
for _,state in ipairs(resetting) do
    assert(state.unit.removed,"map reset must retire both valid and expired old corpses")
    assert_particles_stopped(state.ids)
    for _,component in ipairs(state.components) do assert(component.removed) end
end
advance(0.1);clean_caches()
print("MONSTER_DEATH_WORLD_RESET_PASS pending dead bodies, invalid owner handles, old visual tasks all retired")
for round=1,100 do
    local batch={}
    for index=1,10 do
        local kind=index%3==0 and "neutral" or index%3==1 and "default" or "molten"
        local unit,components,ids=make_monster(kind)
        batch[#batch+1]={kind=kind,unit=unit,components=components,ids=ids}
        if index%2==0 then unit.dead=true;emit_death(unit) else on_death(kind,unit) end
        assert_particles_stopped(ids)
    end
    assert(scheduler.task_count()<=11,"batch must share one corpse updater")
    advance(1.5);advance(0.1)
    for _,state in ipairs(batch) do
        assert(state.unit.removed)
        assert_particles_stopped(state.ids)
        for _,component in ipairs(state.components) do assert(component.removed) end
    end
    clean_caches()
end
print("MONSTER_DEATH_RESOURCE_PASS 1,000 repeated monsters: zero retained props, particle handles, corpse entries, visual caches, scheduled tasks")
