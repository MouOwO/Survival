-- Real cosmetics, inventory, equipment and weapon services. Only native
-- entities, particle allocation, profile persistence and the clock are mocks.
package.path = "scripts/vscripts/?.lua;" .. package.path
local bus = require("core/event_bus")
local events = require("core/events")
local weapons = require("config/generated/weapon_definitions")
local tasks, now, task_serial, recurring_calls = {}, 0, 0, 0
package.loaded["core/scheduler"] = {
    every = function(interval, callback, id)
        assert(interval == 0.25 and id == "weapon_visual_lifecycle",
            "weapon cosmetics must use the existing lifecycle")
        recurring_calls=recurring_calls+1
        tasks[id]={callback=callback,recurring=true}
        return id
    end,
    after = function(delay, callback, id)
        task_serial=task_serial+1
        id=id or "after_"..task_serial
        tasks[id]={callback=callback,at=now+delay}
        return id
    end,
    cancel = function(id) tasks[id]=nil end,
}
local function forbidden() error("weapon cosmetics must not change gameplay") end
package.loaded["systems/player_profile_service"] = {
    get_profile=function() return {save={content_inventory={}}} end,
    update_save_section=forbidden,update_save_sections=forbidden,
}
package.loaded["core/logger"]={info=function() end,warn=function() end}
local world={}
GameRules={GetGameTime=function() return now end,GetGameModeEntity=function() return world end}
PlayerResource={IsValidPlayerID=function(_,pid) return pid==0 or pid==1 end}
local vector_mt={}
vector_mt.__add=function(a,b) return Vector(a.x+b.x,a.y+b.y,a.z+b.z) end
vector_mt.__sub=function(a,b) return Vector(a.x-b.x,a.y-b.y,a.z-b.z) end
vector_mt.__mul=function(a,b)
    if type(a)=="number" then return Vector(a*b.x,a*b.y,a*b.z) end
    return Vector(a.x*b,a.y*b,a.z*b)
end
Vector=function(x,y,z) return setmetatable({x=x,y=y,z=z or 0},vector_mt) end
PATTACH_ABSORIGIN_FOLLOW,PATTACH_POINT_FOLLOW,PATTACH_WORLDORIGIN=1,2,3
PATTACH_ABSORIGIN,PATTACH_POINT,PATTACH_CUSTOMORIGIN=4,5,6
EF_NODRAW=32
ApplyDamage,CreateUnitByName=forbidden,forbidden
CustomNetTables={SetTableValue=function() end}

local entities,entity_serial,spawn_count,spawn_by_model={},1000,0,{}
local fail_model,fail_owner_model,fail_follow_model,fail_skin_model,fail_material_model,on_remove,on_remove_entity
local function entity(class_name,model)
    entity_serial=entity_serial+1
    local u={index=entity_serial,class_name=class_name,model=model,skin=0,alpha=255,
        effects=0,removes=0,origin=Vector(0,0,384)}
    entities[u.index]=u
    function u:IsNull() return self.removed or false end
    function u:entindex() return self.index end
    function u:GetClassname() return self.class_name end
    function u:GetModelName() return self.model_unready and "" or self.model end
    function u:GetAbsOrigin() return self.owner and self.owner.origin or self.origin end
    function u:SetModel(value) self.model=value end
    function u:SetOriginalModel(value) self.original_model=value end
    function u:SetSkin(value)
        if fail_skin_model and fail_skin_model==self.model then fail_skin_model=nil;return false end
        self.skin=value
    end
    function u:SetMaterialGroup(value)
        if fail_material_model and fail_material_model==self.model then fail_material_model=nil;return false end
        self.material_group=value
    end
    function u:GetOwner() return self.owner end
    function u:GetOwnerEntity() return self.owner end
    function u:GetParent() return self.parent end
    function u:GetMoveParent() return self.parent end
    function u:SetOwner(value)
        if fail_owner_model and fail_owner_model==self.model then fail_owner_model=nil;return false end
        self.owner=value
    end
    function u:SetParent(value,attachment) self.parent=value;self.parent_attachment=attachment end
    function u:SetLocalOrigin(value) self.local_origin=value end
    function u:SetLocalAngles(x,y,z) self.local_angles={x,y,z} end
    function u:FollowEntity(value,merge)
        assert(merge==true,"native weapon geometry must bone merge")
        if fail_follow_model and fail_follow_model==self.model then fail_follow_model=nil;return false end
        self.parent=value;self.merge=merge
    end
    function u:GetEffects() return self.effects end
    function u:AddEffects(value) self.effects=value end
    function u:RemoveEffects() self.effects=0 end
    function u:AddNoDraw() self.no_draw=true end
    function u:RemoveNoDraw() self.no_draw=false end
    function u:SetRenderAlpha(value) self.alpha=value end
    function u:NextMovePeer()
        if not self.parent then return nil end
        local found=false
        for _,peer in ipairs(self.parent:GetChildren()) do
            if found then return peer end
            if peer==self then found=true end
        end
    end
    function u:ScriptLookupAttachment() return 1 end
    function u:GetAttachmentOrigin(index) return self:GetAbsOrigin()+Vector(index*2,0,20) end
    return u
end
SpawnEntityFromTableSynchronous=function(class_name,definition)
    if fail_model and fail_model==definition.model then fail_model=nil;error("injected weapon model allocation failure") end
    spawn_count=spawn_count+1
    spawn_by_model[definition.model]=(spawn_by_model[definition.model] or 0)+1
    return entity(class_name,definition.model)
end
UTIL_Remove=function(u)
    if u:IsNull() then return end
    u.removes=u.removes+1
    assert(u.removes==1,"wearable removed twice")
    u.removed=true
    if on_remove and (not on_remove_entity or on_remove_entity==u) then
        local callback=on_remove;on_remove=nil;on_remove_entity=nil;callback(u)
    end
end
Entities={FindAllByClassname=function(_,class_name)
    local result={}
    for _,u in pairs(entities) do
        if not u:IsNull() and u.class_name==class_name then result[#result+1]=u end
    end
    return result
end}
CreateItem=function(name)
    assert(not name:find("scepter",1,true) and not name:find("aghanim",1,true))
    local u=entity("item",name)
    function u:SetCurrentCharges(value) self.charges=value end
    return u
end

local particles,particle_serial={},0
local fail_particle_path,fail_control_path,fail_control_id,on_destroy,on_destroy_owner,on_create,on_create_path
ParticleManager={
    CreateParticle=function(_,path,attach,owner)
        if fail_particle_path==path then fail_particle_path=nil;error("injected weapon ambient allocation failure") end
        particle_serial=particle_serial+1
        local id=particle_serial
        particles[id]={path=path,attach=attach,owner=owner,cp={},destroys=0,releases=0}
        if on_create and (not on_create_path or on_create_path==path) then
            local callback=on_create;on_create=nil;on_create_path=nil;callback(id,particles[id])
        end
        return id
    end,
    SetParticleControl=function(_,id,cp,value) assert(particles[id]).cp[cp]=value end,
    SetParticleControlEnt=function(_,id,cp,owner,attach,anchor,origin)
        local p=assert(particles[id])
        if fail_control_path==p.path or fail_control_id==id then
            fail_control_path=nil;fail_control_id=nil;error("injected weapon ambient CP failure")
        end
        p.cp[cp]={owner=owner,attach=attach,anchor=anchor,origin=origin}
    end,
    SetParticleControlOffset=function(_,id,cp,offset)
        local p=assert(particles[id]);p.offsets=p.offsets or {};p.offsets[cp]=offset
    end,
    SetParticleControlTransformForward=function(_,id,cp,origin,forward)
        assert(particles[id]).cp[cp]={origin=origin,forward=forward}
    end,
    SetParticleControlFallback=function(_,id,cp,origin) assert(particles[id]).fallback=origin end,
    SetParticleControlParticleSnapshot=function(_,id,cp,path)
        local p=assert(particles[id]);p.snapshots=p.snapshots or {};p.snapshots[cp]=path
    end,
    DestroyParticle=function(_,id)
        local p=assert(particles[id]);p.destroys=p.destroys+1
        assert(p.destroys==1,"particle destroyed twice")
        p.destroyed=true
        if on_destroy and (not on_destroy_owner or on_destroy_owner==p.owner) then
            local callback=on_destroy;on_destroy=nil;on_destroy_owner=nil;callback(id,p)
        end
    end,
    ReleaseParticleIndex=function(_,id)
        local p=assert(particles[id]);p.releases=p.releases+1
        assert(p.releases==1,"particle released twice")
        assert(p.destroyed,"persistent cosmetic must destroy before releasing")
        p.released=true
    end,
}
local function hero(pid,hero_id)
    local native=hero_id=="hero_monkey_king" and "monkey_king" or "juggernaut"
    local u=entity("npc_dota_hero_"..native,"models/heroes/"..native.."/"..native..".vmdl")
    u.survival_player_id=pid;u.survival_hero_id=hero_id
    u.origin=Vector(100+pid*500,200,384);u.items={};u.activities={}
    u.stats={health=1000,attack=50,strength=20}
    function u:GetPlayerOwnerID() return self.survival_player_id end
    function u:GetUnitName() return "npc_dota_hero_"..native end
    function u:IsAlive() return not self.dead end
    function u:IsHero() return true end
    function u:GetChildren()
        local result={}
        for _,child in pairs(entities) do
            if child.parent==self and not child:IsNull() then result[#result+1]=child end
        end
        table.sort(result,function(a,b) return a.index<b.index end)
        return result
    end
    function u:FirstMoveChild() return self:GetChildren()[1] end
    function u:ScriptLookupAttachment(name)
        local native_anchors={attach_sword=2,blade_attachment=3,attach_attack1=4,
            attach_hitloc=5,attach_weapon_top=6,attach_weapon_bot=7}
        return native_anchors[name] or 0
    end
    function u:GetForwardVector() return Vector(1,0,0) end
    function u:AddActivityModifier(value) self.activities[value]=true end
    function u:AddItem(item) self.items[#self.items+1]=item end
    function u:RemoveItem(item) UTIL_Remove(item) end
    u.AddNewModifier,u.SetHealth,u.SetBaseDamageMin,u.SetBaseDamageMax=forbidden,forbidden,forbidden,forbidden
    local native_weapon=entity("dota_item_wearable","models/native_default_"..native.."_weapon.vmdl")
    native_weapon.owner=u;native_weapon.parent=u
    local native_body=entity("dota_item_wearable","models/native_default_"..native.."_body.vmdl")
    native_body.owner=u;native_body.parent=u
    u.native_weapon,u.native_body=native_weapon,native_body
    return u
end

local inventory=require("systems/content_inventory_service")
local equipment=require("systems/weapon_equipment_service")
local cosmetic=require("systems/hero_cosmetic_service")
local service=require("systems/weapon_visual_service")
local weapon_cosmetic=require("systems/hero_weapon_cosmetic_service")
local appearances=require("config/generated/hero_weapon_cosmetics")
local summoned={}
local function boot()
    service.init()
    world={};bus.reset();inventory.init();equipment.init();service.init();summoned={}
    bus.handle_request(events.HERO_SUMMON_GET_REQUEST,function(payload)
        local u=summoned[tonumber(payload.player_id)]
        return u and {ok=true,unit=u,hero_id=u.survival_hero_id,unit_name=u:GetUnitName()}
            or {ok=false,error="hero_not_summoned"}
    end)
end
local function tick()
    now=now+0.25
    local recurring=0
    for id,task in pairs(tasks) do
        if task.recurring then recurring=recurring+1;assert(id=="weapon_visual_lifecycle") end
    end
    assert(recurring==1,"cosmetics must not create another recurring task")
    assert(tasks.weapon_visual_lifecycle.callback()~=false)
    local due={}
    for id,task in pairs(tasks) do
        if not task.recurring and task.at<=now then due[#due+1]={id=id,task=task} end
    end
    table.sort(due,function(a,b) return a.task.at<b.task.at end)
    for _,entry in ipairs(due) do
        if tasks[entry.id]==entry.task then tasks[entry.id]=nil;entry.task.callback() end
    end
end
local function announce(u)
    summoned[u.survival_player_id]=u
    bus.emit(events.HERO_SUMMONED,{player_id=u.survival_player_id,unit=u,entindex=u:entindex(),
        hero_id=u.survival_hero_id,unit_name=u:GetUnitName(),team=2})
end
local function summon(u)
    assert(cosmetic.apply(u,u.survival_hero_id),"real selected hero costume must apply")
    announce(u)
end
local function grant(pid,id)
    local result=bus.request(events.CONTENT_INVENTORY_GRANT_REQUEST,
        {player_id=pid,content_id=id,count=1,reason="hero_weapon_cosmetic_test"})
    assert(result and result.ok)
end
local function transaction(pid,consume,grant_map)
    local result=bus.request(events.CONTENT_INVENTORY_TRANSACTION_REQUEST,
        {player_id=pid,consume=consume,grant=grant_map or {},reason="hero_weapon_atomic_upgrade"})
    assert(result and result.ok)
end

-- Independent expected models/styles from the native item audit, rather than
-- using the production mapping itself to decide what a rendered slot is.
local native_expected={
    hero_monkey_king={
        default={item=609,model="models/heroes/monkey_king/monkey_king_base_weapon.vmdl",skin=0,material="default"},
        frost_blade={item=13546,model="models/items/monkey_king/mk_ti9_immortal_weapon/mk_ti9_immortal_weapon.vmdl",skin=0},
        ice_blade={item=9212,model="models/items/monkey_king/monkey_king_immortal_weapon/monkey_king_immortal_weapon.vmdl",skin=0,material="default"},
        epic_icefire={item=9453,model="models/items/monkey_king/monkey_king_immortal_weapon/monkey_king_immortal_weapon.vmdl",skin=2,material="2"},
        legend_abyss={item=29347,model="models/items/monkey_king/monkey_king_immortal_weapon/monkey_king_immortal_weapon.vmdl",skin=3,material="3"},
    },
    hero_blademaster={
        default={item=7,model="models/heroes/juggernaut/jugg_sword.vmdl",skin=0},
        frost_blade={item=23327,model="models/items/juggernaut/disciple_of_the_skadi_weapon/disciple_of_the_skadi_weapon.vmdl",skin=0},
        ice_blade={item=13185,model="models/items/juggernaut/susano_os_descendant_weapon/susano_os_descendant_weapon.vmdl",skin=0},
        epic_icefire={item=9984,model="models/items/juggernaut/jugg_ti8/jugg_ti8_sword.vmdl",skin=0,material="0"},
        legend_abyss={item=12417,model="models/items/juggernaut/jugg_ti8/jugg_ti8_sword.vmdl",skin=2,material="2"},
    },
}
local slot_ids={hero_monkey_king="demon_trickster_staff",hero_blademaster="weapon"}
local function slot(u)
    return assert(cosmetic.weapon_snapshot(u,slot_ids[u.survival_hero_id]),"selected costume must retain slot metadata")
end
local function expected(u,series)
    return native_expected[u.survival_hero_id][series=="growth_sword" and "default" or series]
end
local function assert_weapon(u,series)
    local state=slot(u);local w=assert(state.wearable);local target=expected(u,series)
    assert(state.live and not w:IsNull(),"mapped weapon must exist")
    assert(w.model==target.model,"wrong native weapon model for "..u.survival_hero_id..":"..series
        .." actual="..tostring(w.model).." error="..tostring((weapon_cosmetic.debug_snapshot(u.survival_player_id) or {}).error))
    assert(w.skin==target.skin,"wrong native weapon skin style")
    if target.material then assert(w.material_group==target.material,"wrong native material group") end
    assert(w.owner==u and w.parent==u and w.merge==true,"weapon must follow its own selected hero")
    assert(not w.no_draw and w.alpha==255,"native-hide passes must preserve the replacement weapon")
    local visible=0
    for _,child in ipairs(u:GetChildren()) do
        if not child.no_draw and child.class_name=="prop_dynamic" then
            for _,appearance in pairs(native_expected[u.survival_hero_id]) do
                if child.model==appearance.model then visible=visible+1;break end
            end
        end
    end
    assert(visible==1,"hero must display exactly one native weapon, excluding hidden CP anchors")
    return w,state
end
local function attached_particles(w)
    local ids={}
    for id,p in pairs(particles) do
        if p.owner==w and not p.destroyed then ids[#ids+1]=id end
    end
    table.sort(ids)
    return ids
end
local function capture_body(u)
    local w=slot(u).wearable
    local result={hero=u,model=u.model,skin=u.skin,material=u.material_group,parts={},ambient={}}
    for _,part in ipairs(u:GetChildren()) do
        if part.class_name=="prop_dynamic" and part~=w and not part.no_draw then result.parts[part.index]=part end
    end
    for id,p in pairs(particles) do
        if not p.destroyed and (p.owner==u or (p.owner and result.parts[p.owner.index]))
            and p.path:find("particles/econ/",1,true)==1
            and not p.path:find("loadout_spawn",1,true) then result.ambient[id]=p end
    end
    assert(next(result.parts),"real selected costume must expose body parts")
    assert(next(result.ambient),"real selected costume must expose persistent body ambient")
    return result
end
local function stable_body(snapshot)
    local u=snapshot.hero
    assert(u.model==snapshot.model and u.skin==snapshot.skin and u.material_group==snapshot.material,
        "weapon replacement must preserve selected body/arcana style")
    for _,part in pairs(snapshot.parts) do assert(not part:IsNull() and part.parent==u) end
    for id,p in pairs(snapshot.ambient) do
        assert(particles[id]==p and not p.destroyed and p.releases==0,
            "weapon replacement must retain existing body/armor/shoulder/arcana ambient IDs")
    end
    assert(u.stats.health==1000 and u.stats.attack==50 and u.stats.strength==20)
end
local function retired_weapon(w,ids)
    assert(w:IsNull() and w.removes==1,"old weapon must be retired exactly once")
    for _,id in ipairs(ids) do
        assert(particles[id].destroys==1 and particles[id].releases==1,
            "old weapon ambient must retire exactly once")
    end
end
local series_order={"growth_sword","frost_blade","ice_blade","epic_icefire","legend_abyss"}
local grouped={}
for _,definition in ipairs(weapons.rows) do
    if definition.equipment_slot=="main_hand" then
        grouped[definition.series_id]=grouped[definition.series_id] or {}
        table.insert(grouped[definition.series_id],definition)
    end
end
local expected_sizes={growth_sword=5,frost_blade=5,ice_blade=5,epic_icefire=7,legend_abyss=11}
for series,size in pairs(expected_sizes) do
    assert(#grouped[series]==size,"missing real weapon strengthening stages")
    table.sort(grouped[series],function(a,b) return tonumber(a.stage)<tonumber(b.stage) end)
end

local precached={}
PrecacheResource=function(kind,path,context)
    assert(context==precached)
    local key=kind..":"..path
    precached[key]=(precached[key] or 0)+1
end
service.precache(precached)
for _,map in pairs(native_expected) do
    for _,row in pairs(map) do
        assert(precached["model:"..row.model]==1,"all native weapon models must be precached once")
    end
end

boot()
local a,b=hero(0,"hero_blademaster"),hero(1,"hero_monkey_king")
summon(a);summon(b)
local a_default,b_default=assert_weapon(a,"default"),assert_weapon(b,"default")
local a_body,b_body=capture_body(a),capture_body(b)
for _=1,4 do tick() end
assert_weapon(a,"default");assert_weapon(b,"default")
assert(a.native_body.no_draw and b.native_body.no_draw,
    "default weapon must not reveal the player's whole native outfit")
assert(a.native_weapon.no_draw and b.native_weapon.no_draw,
    "original native weapon must stay hidden beside the explicit replacement")

local matrix_cases=0
for _,u in ipairs({a,b}) do
    local body=u==a and a_body or b_body
    local previous
    local previous_weapon=assert_weapon(u,"default")
    local previous_particles=attached_particles(previous_weapon)
    local last_series="default"
    for _,series in ipairs(series_order) do
        for _,definition in ipairs(grouped[series]) do
            local before_spawn=spawn_count
            if previous then transaction(u.survival_player_id,{[previous]=1},{[definition.content_id]=1})
            else grant(u.survival_player_id,definition.content_id) end
            local w=assert_weapon(u,series)
            stable_body(body)
            local same_series=(series==last_series) or (series=="growth_sword" and last_series=="default")
            if same_series then
                assert(w==previous_weapon and spawn_count==before_spawn,
                    "default/growth or same-series strengthening must preserve the native weapon entity")
                local ids=attached_particles(w)
                assert(#ids==#previous_particles)
                for i,id in ipairs(ids) do assert(id==previous_particles[i],"strengthening must preserve native weapon ambient IDs") end
            else
                assert(w~=previous_weapon,"changing series must commit a new native weapon")
                retired_weapon(previous_weapon,previous_particles)
            end
            previous,previous_weapon,last_series=definition.content_id,w,series
            previous_particles=attached_particles(w)
            tick();assert_weapon(u,series);stable_body(body)
            matrix_cases=matrix_cases+1
        end
    end
    transaction(u.survival_player_id,{[previous]=1})
    local default_weapon=assert_weapon(u,"default")
    assert(default_weapon~=previous_weapon,"losing the last main hand must restore the explicit default weapon")
    retired_weapon(previous_weapon,previous_particles);stable_body(body)
end
assert(matrix_cases==66,"both heroes must exercise all 33 real main-hand definitions")

local fault_cases=0
for _,hero_id in ipairs({"hero_blademaster","hero_monkey_king"}) do
    for _,mode in ipairs({"model","owner","follow","skin","material","ambient","control"}) do
        boot();local u=hero(0,hero_id);summon(u)
        grant(0,grouped.ice_blade[1].content_id)
        local old=assert_weapon(u,"ice_blade");local old_particles=attached_particles(old)
        local body=capture_body(u);local target=expected(u,"epic_icefire")
        if mode=="model" then fail_model=target.model end
        if mode=="owner" then fail_owner_model=target.model end
        if mode=="follow" then fail_follow_model=target.model end
        if mode=="skin" then fail_skin_model=target.model end
        if mode=="material" then fail_material_model=target.model end
        if mode=="ambient" or mode=="control" then
            local path=hero_id=="hero_blademaster"
                and "particles/econ/items/juggernaut/jugg_ti8_sword/jugg_ti8_sword_ambient.vpcf"
                or "particles/econ/items/monkey_king/ti7_weapon/mk_ti7_golden_immortal_weapon_ambient.vpcf"
            if mode=="ambient" then fail_particle_path=path else fail_control_path=path end
        end
        transaction(0,{[grouped.ice_blade[1].content_id]=1},{[grouped.epic_icefire[1].content_id]=1})
        assert(assert_weapon(u,"ice_blade")==old,"optional slot failure must preserve the visible old weapon")
        for _,id in ipairs(old_particles) do assert(not particles[id].destroyed) end
        stable_body(body)
        tick();assert_weapon(u,"epic_icefire");retired_weapon(old,old_particles);stable_body(body)
        fault_cases=fault_cases+1
    end
end

local reentry_cases=0
for _,hero_id in ipairs({"hero_blademaster","hero_monkey_king"}) do
    for _,mode in ipairs({"ambient_destroy","weapon_remove"}) do
        boot();local u=hero(0,hero_id);summon(u)
        grant(0,grouped.ice_blade[1].content_id)
        local old=assert_weapon(u,"ice_blade");local old_particles=attached_particles(old)
        local body=capture_body(u)
        local existing_loop=tasks.weapon_visual_lifecycle.callback
        local reentered,inside_spawn,inside_weapon,inside_before
        local function callback()
            reentered=true
            inside_before=spawn_count
            existing_loop()
            inside_spawn=spawn_count;inside_weapon=slot(u).wearable
        end
        if mode=="ambient_destroy" then on_destroy=callback;on_destroy_owner=old
        else on_remove=callback;on_remove_entity=old end
        transaction(0,{[grouped.ice_blade[1].content_id]=1},{[grouped.epic_icefire[1].content_id]=1})
        local new=assert_weapon(u,"epic_icefire")
        assert(reentered and inside_weapon==new and inside_spawn==inside_before,
            "cleanup callback must observe one committed replacement and never rebuild another")
        retired_weapon(old,old_particles);stable_body(body)
        tick();assert(assert_weapon(u,"epic_icefire")==new)
        reentry_cases=reentry_cases+1
    end
end

boot();a,b=hero(0,"hero_blademaster"),hero(1,"hero_monkey_king")
summon(a);summon(b)
grant(0,grouped.legend_abyss[4].content_id);grant(1,grouped.frost_blade[3].content_id)
local a_weapon=assert_weapon(a,"legend_abyss");local a_native_particles=attached_particles(a_weapon)
local b_weapon=assert_weapon(b,"frost_blade")
a_body,b_body=capture_body(a),capture_body(b)
a.dead=true;tick()
assert(slot(a).wearable==a_weapon,"ordinary death must retain its native weapon entity")
for _,id in ipairs(a_native_particles) do assert(not particles[id].destroyed) end
assert(assert_weapon(b,"frost_blade")==b_weapon)
a.dead=false;tick();assert(assert_weapon(a,"legend_abyss")==a_weapon)
stable_body(a_body);stable_body(b_body)

-- A main-hand change while dead commits its desired series on revival.
a.dead=true
transaction(0,{[grouped.legend_abyss[4].content_id]=1},{[grouped.ice_blade[2].content_id]=1})
tick();assert(slot(a).wearable==a_weapon)
a.dead=false;tick();local ice_weapon=assert_weapon(a,"ice_blade")
retired_weapon(a_weapon,a_native_particles);stable_body(a_body)
assert(assert_weapon(b,"frost_blade")==b_weapon)

-- The original hero cosmetic service can reapply a skin without emitting a
-- summon event. The shared poll must see its new metadata token and restore
-- the equipped series on that new costume, not revive old entity IDs.
assert(cosmetic.apply(a,"hero_blademaster"))
assert(ice_weapon:IsNull())
local fresh_costume_slot=slot(a).wearable
tick();a_weapon=assert_weapon(a,"ice_blade")
assert(a_weapon~=fresh_costume_slot and a_weapon~=ice_weapon)
a_body=capture_body(a);stable_body(a_body)

-- A removed weapon or CP-offset carrier invalidates the slot's completeness.
UTIL_Remove(a_weapon);tick();local restored_weapon=assert_weapon(a,"ice_blade")
assert(restored_weapon~=a_weapon);stable_body(a_body)
grant(0,grouped.epic_icefire[2].content_id)
a_weapon=assert_weapon(a,"epic_icefire")
local native_cp15
for _,id in ipairs(attached_particles(a_weapon)) do native_cp15=particles[id].cp[15] end
local carrier=assert(native_cp15 and native_cp15.owner,"native CP15 must have a registered offset carrier")
assert(carrier~=a_weapon and carrier.no_draw and carrier.parent==a_weapon
    and carrier.parent_attachment=="attach_smoketwist"
    and carrier.local_origin.x==0 and carrier.local_origin.y==20 and carrier.local_origin.z==0,
    "string CSV offsets must become the native 0/20/0 bone-space carrier")
UTIL_Remove(carrier);tick();local restored_epic=assert_weapon(a,"epic_icefire")
assert(restored_epic~=a_weapon);stable_body(a_body)

-- Model readiness is queried separately from the chosen skin identity.
local waiting=hero(0,"hero_blademaster");waiting.model_unready=true
summon(waiting)
local waiting_original=slot(waiting).wearable
for _=1,4 do tick();assert(slot(waiting).wearable==waiting_original) end
waiting.model_unready=false;tick();assert_weapon(waiting,"epic_icefire")
local waiting_body=capture_body(waiting)
assert(slot(a).wearable==nil,"replacement must revoke the old hero's weapon slot")
stable_body(a_body);stable_body(b_body)

-- Duplicate and wrong-owner events do not transfer either player's slot.
local current=assert_weapon(waiting,"epic_icefire")
announce(waiting);assert(assert_weapon(waiting,"epic_icefire")==current)
weapon_cosmetic.on_hero_summoned({player_id=0,unit=b,hero_id="hero_monkey_king"})
assert(assert_weapon(waiting,"epic_icefire")==current)
assert(assert_weapon(b,"frost_blade")==b_weapon)

-- A monkey clone has its own ordinary costume. Changing the main hero's
-- equipment must not globally scan native hero names and replace that clone.
local clone=hero(1,"hero_monkey_king");clone.survival_monkey_king_clone=true
assert(cosmetic.apply(clone,"hero_monkey_king"))
local clone_original=slot(clone).wearable
grant(1,grouped.legend_abyss[2].content_id)
assert_weapon(b,"legend_abyss");assert(slot(clone).wearable==clone_original)

-- Defeat/disconnect clear only the owned weapon slot even when the engine
-- entity still exists. Late real inventory/hero/equipment events stay blocked.
local blocked_weapon=assert_weapon(waiting,"epic_icefire")
local blocked_particles=attached_particles(blocked_weapon)
bus.emit(events.PLAYER_DEFEATED,{player_id="0",reason="hero_weapon_test"})
retired_weapon(blocked_weapon,blocked_particles)
assert(slot(waiting).wearable==nil and weapon_cosmetic.debug_snapshot(0).unavailable)
bus.emit(events.PLAYER_DISCONNECTED,{player_id=0,reason="hero_weapon_test",defeat_cleanup=true})
grant(0,grouped.legend_abyss[7].content_id);announce(waiting);tick()
assert(slot(waiting).wearable==nil,"late events must not reattach the defeated player's weapon")
stable_body(waiting_body);stable_body(b_body)
local disconnected=assert_weapon(b,"legend_abyss")
local disconnected_particles=attached_particles(disconnected)
bus.emit(events.PLAYER_DISCONNECTED,{player_id=1,reason="disconnect_timeout"})
retired_weapon(disconnected,disconnected_particles)
announce(b);tick();assert(slot(b).wearable==nil)
stable_body(b_body)

-- Same-world hot init keeps physical native slots and restores its metadata
-- from real equipment on the next existing poll, without another summon.
boot();a=hero(0,"hero_blademaster");summon(a);grant(0,grouped.legend_abyss[1].content_id)
a_weapon=assert_weapon(a,"legend_abyss");a_native_particles=attached_particles(a_weapon)
a_body=capture_body(a)
local hot_spawn=spawn_count
for _=1,3 do
    service.init();tick();assert(assert_weapon(a,"legend_abyss")==a_weapon)
    assert(spawn_count==hot_spawn,"same-world init must not respawn native weapon or carrier")
    for _,id in ipairs(a_native_particles) do assert(not particles[id].destroyed) end
    stable_body(a_body)
end

-- A new Tools world can reuse a native entity handle. Reset must not remove
-- an object now owned by that different world.
local foreign=a_weapon;a_weapon.model="models/foreign_world_prop.vmdl"
local foreign_removes=foreign.removes;local old_particle=particles[a_native_particles[1]]
local old_destroys,old_releases=old_particle.destroys,old_particle.releases
world={};service.init()
assert(foreign.removes==foreign_removes and old_particle.destroys==old_destroys
    and old_particle.releases==old_releases,"new-world reset must discard stale ownership without cleanup")
local fresh=hero(0,"hero_blademaster");summon(fresh);assert_weapon(fresh,"legend_abyss")
assert(foreign.removes==foreign_removes and old_particle.destroys==old_destroys)

-- An unrelated hero retains its original complete costume and hand effects.
boot();local other=hero(0,"hero_axe")
function other:GetUnitName() return "npc_dota_hero_axe" end
assert(cosmetic.apply(other,"hero_axe"))
local other_parts=other:GetChildren()
announce(other);grant(0,grouped.legend_abyss[1].content_id);tick()
for _,part in ipairs(other_parts) do assert(not part:IsNull()) end
assert(weapon_cosmetic.debug_snapshot(0).cosmetic_id==nil)
assert(recurring_calls>1)
assert(fault_cases==14 and reentry_cases==4)

-- Destroy callbacks can enter a new Tools world and immediately reuse the
-- very same particle ID; the old closure must not Release its new owner.
boot();local world_hero=hero(0,"hero_blademaster");summon(world_hero)
grant(0,grouped.ice_blade[1].content_id)
local world_weapon=assert_weapon(world_hero,"ice_blade")
local world_particle_id=assert(attached_particles(world_weapon)[1])
local old_record=particles[world_particle_id]
local foreign_record,reused_callback
on_destroy_owner=world_weapon
on_destroy=function(id)
    reused_callback=true;assert(id==world_particle_id)
    world={}
    foreign_record={path="particles/foreign_reused_id.vpcf",cp={},destroys=0,releases=0}
    particles[id]=foreign_record
end
transaction(0,{[grouped.ice_blade[1].content_id]=1},{[grouped.epic_icefire[1].content_id]=1})
assert(reused_callback and old_record.destroys==1 and old_record.releases==0)
assert(foreign_record.destroys==0 and foreign_record.releases==0,
    "world change inside Destroy must prevent Release of the reused native ID")
service.init()
assert(foreign_record.destroys==0 and foreign_record.releases==0)

-- A defeat/replacement arriving while the slot lock is held must retire the
-- just-committed old hero result after unlock, preserving body/other slots.
local transaction_boundary_cases=0
for _,mode in ipairs({"defeat_during_allocation","replacement_during_cleanup"}) do
    boot();local u=hero(0,"hero_blademaster");summon(u)
    grant(0,grouped.ice_blade[1].content_id)
    local old=assert_weapon(u,"ice_blade");local old_ids=attached_particles(old)
    local body=capture_body(u);local entered,pending_weapon,replacement
    if mode=="defeat_during_allocation" then
        on_create_path="particles/econ/items/juggernaut/jugg_ti8_sword/jugg_ti8_sword_ambient.vpcf"
        on_create=function(_,p)
            entered=true;pending_weapon=p.owner
            bus.emit(events.PLAYER_DEFEATED,{player_id=0,reason="during_native_weapon_transaction"})
        end
    else
        replacement=hero(0,"hero_blademaster")
        assert(cosmetic.apply(replacement,"hero_blademaster"))
        on_destroy_owner=old
        on_destroy=function()
            entered=true;pending_weapon=slot(u).wearable
            announce(replacement)
        end
    end
    transaction(0,{[grouped.ice_blade[1].content_id]=1},{[grouped.epic_icefire[1].content_id]=1})
    assert(entered and pending_weapon and pending_weapon~=old)
    assert(slot(u).wearable==nil and pending_weapon:IsNull() and pending_weapon.removes==1,
        "a locked late defeat/replacement must not leave the committed old-hero weapon behind")
    retired_weapon(old,old_ids);stable_body(body)
    if replacement then
        local live=assert_weapon(replacement,"epic_icefire")
        assert(live~=pending_weapon and weapon_cosmetic.debug_snapshot(0).hero==replacement:entindex())
        tick();assert(assert_weapon(replacement,"epic_icefire")==live)
    else
        assert(weapon_cosmetic.debug_snapshot(0).unavailable)
        announce(u);tick();assert(slot(u).wearable==nil)
    end
    transaction_boundary_cases=transaction_boundary_cases+1
end
assert(transaction_boundary_cases==2)

-- The same busy-lock boundary also occurs when the pending native CP fails:
-- rollback keeps the old slot, which must still be cleared for the old hero.
local failed_boundary_cases=0
for _,mode in ipairs({"defeat","replacement"}) do
    boot();local u=hero(0,"hero_blademaster");summon(u)
    grant(0,grouped.ice_blade[1].content_id)
    local old=assert_weapon(u,"ice_blade");local old_ids=attached_particles(old)
    local body=capture_body(u);local replacement,pending,entered
    if mode=="replacement" then
        replacement=hero(0,"hero_blademaster")
        assert(cosmetic.apply(replacement,"hero_blademaster"))
    end
    on_create_path="particles/econ/items/juggernaut/jugg_ti8_sword/jugg_ti8_sword_ambient.vpcf"
    on_create=function(id,p)
        entered=true;pending=p.owner
        if replacement then announce(replacement)
        else bus.emit(events.PLAYER_DEFEATED,{player_id=0,reason="failed_locked_native_transaction"}) end
        -- The replacement can successfully build its own effect inside the
        -- event. Fail this original in-flight allocation by its precise ID.
        fail_control_id=id
    end
    transaction(0,{[grouped.ice_blade[1].content_id]=1},{[grouped.epic_icefire[1].content_id]=1})
    assert(entered and pending and pending:IsNull() and pending.removes==1)
    assert(slot(u).wearable==nil,"failed locked transition must also clear the rollback-retained old weapon")
    retired_weapon(old,old_ids);stable_body(body)
    if replacement then
        local replacement_weapon=assert_weapon(replacement,"epic_icefire")
        tick();assert(assert_weapon(replacement,"epic_icefire")==replacement_weapon)
    else
        assert(weapon_cosmetic.debug_snapshot(0).unavailable)
        announce(u);tick();assert(slot(u).wearable==nil)
    end
    failed_boundary_cases=failed_boundary_cases+1
end

-- ReplaceHeroWith invalidates the old hero before HERO_SUMMONED arrives.
-- Cleanup must use its cached cosmetic token/index, not a live entindex call.
boot();local removed_hero=hero(0,"hero_blademaster");summon(removed_hero)
grant(0,grouped.ice_blade[1].content_id)
local removed_weapon=assert_weapon(removed_hero,"ice_blade")
local removed_ids=attached_particles(removed_weapon)
local removed_body=capture_body(removed_hero)
removed_hero.removed=true
function removed_hero:entindex() error("removed native hero has no callable entindex") end
local replacement_hero=hero(0,"hero_monkey_king");summon(replacement_hero)
retired_weapon(removed_weapon,removed_ids);stable_body(removed_body)
assert_weapon(replacement_hero,"ice_blade")
assert(failed_boundary_cases==2)
print("HERO_WEAPON_MATRIX_PASS two selected heroes, 66 real main-hand definitions, five series+default, exact native models/styles, same-series entity/ambient reuse")
print("HERO_WEAPON_SLOT_PASS body and arcana/armor/shoulder ambient preserved, delayed native hide, offset carrier, 14 failure rollbacks+poll recovery, 4 cleanup reentries")
print("HERO_WEAPON_LIFECYCLE_PASS model readiness, death/revive, replacement, skin reapply, missing carrier/weapon, default restoration, defeat/disconnect+late events, two players, clone isolation, same/new-world init, one existing loop, no gameplay mutations")
print("HERO_WEAPON_TRANSACTION_BOUNDARY_PASS reused world ID after Destroy not Released, successful+failed locked defeat/replacement clean old slot, invalid old hero cleans by cached token/index")
