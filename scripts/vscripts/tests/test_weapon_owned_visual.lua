-- Real inventory/equipment/weapon-visual services and generated definitions;
-- only Source entities, particles, persistent profiles and scheduling are mocks.
package.path = "scripts/vscripts/?.lua;" .. package.path
local bus = require("core/event_bus")
local events = require("core/events")
local weapons = require("config/generated/weapon_definitions")
local profiles = require("config/generated/weapon_visual_profiles")
local PATH = "particles/items4_fx/scepter_aura.vpcf"
local tasks, serial, now, every_calls = {}, 0, 0, 0
package.loaded["core/scheduler"] = {
    every = function(interval, callback, id)
        assert(interval == 0.25 and id == "weapon_visual_lifecycle",
            "owned aura must share the one existing lifecycle loop")
        every_calls = every_calls + 1
        tasks[id] = { callback = callback, recurring = true }
        return id
    end,
    after = function() error("owned aura must not allocate an extra timer") end,
    cancel = function(id) tasks[id] = nil end,
}
local function forbidden() error("cosmetic aura must not change gameplay") end
package.loaded["systems/player_profile_service"] = {
    get_profile = function() return {save = {content_inventory = {}}} end,
    update_save_section = forbidden, update_save_sections = forbidden,
}
local world = {}
GameRules = { GetGameTime = function() return now end,
    GetGameModeEntity = function() return world end }
PlayerResource = { IsValidPlayerID = function(_, id) return id == 0 or id == 1 end }
Vector = function(x,y,z) return {x=x,y=y,z=z or 0} end
PATTACH_ABSORIGIN_FOLLOW, PATTACH_POINT_FOLLOW, PATTACH_WORLDORIGIN = 1, 2, 3
ApplyDamage, CreateUnitByName = forbidden, forbidden
CustomNetTables = { SetTableValue = function() end }
local item_names, item_serial = {}, 1000
CreateItem = function(name)
    assert(not name:find("scepter", 1, true) and not name:find("aghanim", 1, true),
        "visual acquisition must not give a Scepter item")
    item_names[#item_names+1] = name
    item_serial = item_serial+1
    local item = {index=item_serial}
    function item:IsNull() return self.removed or false end
    function item:entindex() return self.index end
    function item:SetCurrentCharges(n) self.charges=n end
    return item
end
UTIL_Remove = function(item) item.removed = true end
local particles, particle_serial, foot_allocations, last_foot_id = {}, 0, 0, nil
local fault_create, fault_control, fault_destroy, fault_release, on_destroy
ParticleManager = {
    CreateParticle = function(_, path, attach, unit)
        if path == PATH then
            foot_allocations = foot_allocations+1
            local failure = fault_create
            fault_create = nil
            if failure == "throw" then error("injected aura allocation failure") end
            if failure == "nil" then return nil end
            if failure == "negative" then return -1 end
        end
        particle_serial = particle_serial+1
        particles[particle_serial] = {path=path,attach=attach,unit=unit,cp={},
            destroys=0,releases=0}
        if path==PATH then last_foot_id=particle_serial end
        return particle_serial
    end,
    SetParticleControl = function(_, id, cp, value)
        assert(particles[id], "invalid particle ID reached CP setup")
        assert(particles[id].path ~= PATH, "native aura needs only its attached CP0")
        particles[id].cp[cp] = value
    end,
    SetParticleControlEnt = function(_, id, cp, unit, attach, anchor, origin)
        local p = assert(particles[id], "invalid particle ID reached attached CP setup")
        if p.path == PATH then
            assert(cp == 0 and attach == PATTACH_ABSORIGIN_FOLLOW
                and (anchor == nil or anchor == ""), "aura must follow feet, never a weapon bone")
            if fault_control then fault_control=nil;error("injected aura CP0 failure") end
        end
        p.cp[cp] = {unit=unit,attach=attach,anchor=anchor,origin=origin}
    end,
    DestroyParticle = function(_, id)
        local p = assert(particles[id], "invalid particle ID reached Destroy")
        p.destroys=p.destroys+1
        assert(p.destroys == 1, "particle destroyed twice")
        p.destroyed=true
        if on_destroy then local callback=on_destroy;on_destroy=nil;callback(id,p) end
        if p.path == PATH and fault_destroy then fault_destroy=nil;error("injected aura destroy failure") end
    end,
    ReleaseParticleIndex = function(_, id)
        local p = assert(particles[id], "invalid particle ID reached Release")
        p.releases=p.releases+1
        assert(p.releases == 1, "particle released twice")
        assert(p.destroyed, "owned persistent effects must be destroyed before release")
        p.released=true
        if p.path == PATH and fault_release then fault_release=nil;error("injected aura release failure") end
    end,
}
local function hero(index,pid)
    local u={index=index,survival_player_id=pid,model="models/heroes/juggernaut/juggernaut.vmdl",
        origin=Vector(index*100,0,384),bone=2,items={},stats={health=1000,attack=50,strength=20}}
    function u:IsNull() return self.removed or false end
    function u:IsAlive() return not self.dead end
    function u:entindex() return self.index end
    function u:GetPlayerOwnerID() return self.survival_player_id end
    function u:GetAbsOrigin() return self.origin end
    function u:GetModelName() return self.model end
    function u:ScriptLookupAttachment(name) return name == "attach_sword" and self.bone or 0 end
    function u:AddItem(item) self.items[#self.items+1]=item end
    function u:RemoveItem(item) item.removed=true end
    u.AddNewModifier,u.SetHealth,u.SetBaseDamageMin,u.SetBaseDamageMax = forbidden,forbidden,forbidden,forbidden
    return u
end
local inventory = require("systems/content_inventory_service")
local equipment = require("systems/weapon_equipment_service")
local service = require("systems/weapon_visual_service")
local owned = require("systems/weapon_owned_visual")
local summoned = {}
local function boot()
    -- A fresh logical match also has a fresh native world. Retire effects in
    -- the previous live world first, then let production discard its states.
    service.init()
    world={}
    bus.reset()
    inventory.init()
    equipment.init()
    service.init()
    summoned={}
    -- The real addon also registers hero queries after weapon visuals init.
    bus.handle_request(events.HERO_SUMMON_GET_REQUEST,function(payload)
        local unit=summoned[tonumber(payload.player_id)]
        return unit and {ok=true,unit=unit,hero_id="hero_test",unit_name="npc_dota_hero_juggernaut"}
            or {ok=false,error="hero_not_summoned"}
    end)
end
local function tick()
    now=now+0.25
    local count=0
    for key in pairs(tasks) do count=count+1;assert(key=="weapon_visual_lifecycle") end
    assert(count == 1, "only the existing recurring lifecycle task may be live")
    assert(tasks.weapon_visual_lifecycle.callback() ~= false)
end
local function summon(u,pid)
    pid=pid or u.survival_player_id
    summoned[tonumber(pid)]=u
    bus.emit(events.HERO_SUMMONED,{player_id=pid,unit=u,entindex=u:entindex(),
        hero_id="hero_test",unit_name="npc_dota_hero_juggernaut",team=2})
end
local function counts(pid)
    return assert(bus.request(events.CONTENT_INVENTORY_GET_REQUEST,{player_id=pid})).snapshot.counts
end
local function grant(pid,id,n)
    local result=bus.request(events.CONTENT_INVENTORY_GRANT_REQUEST,
        {player_id=pid,content_id=id,count=n or 1,reason="owned_visual_test"})
    assert(result and result.ok)
    return result
end
local function transaction(pid,consume,grant_map)
    local result=bus.request(events.CONTENT_INVENTORY_TRANSACTION_REQUEST,
        {player_id=pid,consume=consume,grant=grant_map or {},reason="owned_visual_test_atomic_upgrade"})
    assert(result and result.ok)
    return result
end
local function main_hand(pid)
    return assert(bus.request(events.WEAPON_EQUIPMENT_GET_REQUEST,{player_id=pid})).snapshot.main_hand_content_id
end
local function foot_ids(u)
    local result={}
    for id,p in pairs(particles) do
        if p.path == PATH and not p.destroyed and not p.released and (not u or p.unit == u) then
            result[#result+1]=id
        end
    end
    table.sort(result)
    return result
end
local function foot(u,expected)
    local ids=foot_ids(u)
    assert(#ids == expected, "wrong persistent aura count: "..#ids.." expected "..expected)
    if expected == 1 then
        local p=particles[ids[1]]
        assert(p.unit == u and p.cp[0] and p.cp[0].unit == u
            and p.cp[0].attach == PATTACH_ABSORIGIN_FOLLOW)
        return ids[1]
    end
end
local function stable(u,id)
    assert(foot(u,1)==id, "same owned series must preserve its original aura handle")
end

local legend_by_stage={}
for _,definition in ipairs(weapons.rows) do
    if definition.series_id == "legend_abyss" then
        assert(definition.enabled ~= false and definition.auto_equip == true)
        legend_by_stage[tonumber(definition.stage)]=definition.content_id
    end
end
for stage=0,10 do assert(legend_by_stage[stage], "missing real legend stage "..stage) end
local legend_profile=assert(profiles.by_id.legend_abyss)
assert(legend_profile.owned_particle==PATH, "legend aura must come from the real generated profile")
for _,profile in ipairs(profiles.rows) do
    if profile.series_id ~= "legend_abyss" then
        assert(not profile.owned_particle or profile.owned_particle=="", "other weapon series unexpectedly grants aura")
    end
end
local precached={}
PrecacheResource=function(kind,path,context)
    assert((kind=="particle" or (kind=="model" and path:match("%.vmdl$")))
        and context==precached)
    precached[path]=(precached[path] or 0)+1
end
service.precache(precached)
assert(precached[PATH]==1, "native aura is precached once by the actual weapon service")

boot()
local a,b=hero(10,0),hero(20,1)
grant(0,legend_by_stage[0]);foot(nil,0)
assert(main_hand(0)==legend_by_stage[0], "real inventory grant auto-equips legend")
summon(a,"0");local a_id=foot(a,1)
local original_allocations=foot_allocations
for stage=1,10 do
    transaction(0,{[legend_by_stage[stage-1]]=1},{[legend_by_stage[stage]]=1})
    assert(counts(0)[legend_by_stage[stage]]==1 and main_hand(0)==legend_by_stage[stage])
    stable(a,a_id);tick();stable(a,a_id)
end
assert(foot_allocations==original_allocations, "all ten atomic upgrades must avoid aura interruption")
grant(0,"weapon_growth_sword_01")
assert(main_hand(0)=="weapon_growth_sword_01" and counts(0)[legend_by_stage[10]]==1,
    "real auto-equip can change main hand while the legend is still owned")
stable(a,a_id)
a.model="models/items/juggernaut/custom_body.vmdl";a.bone=9;a.origin=Vector(777,888,384)
tick();stable(a,a_id)
assert(particles[a_id].cp[0].unit==a, "attached aura retains moving hero ownership")
for _=1,12 do tick();stable(a,a_id) end
assert(a.stats.health==1000 and a.stats.attack==50 and a.stats.strength==20)
grant(0,legend_by_stage[10]);stable(a,a_id)
transaction(0,{[legend_by_stage[10]]=1});stable(a,a_id)
grant(0,legend_by_stage[0]);stable(a,a_id)
transaction(0,{[legend_by_stage[10]]=1});stable(a,a_id)
transaction(0,{[legend_by_stage[0]]=1});foot(a,0)
assert(particles[a_id].destroys==1 and particles[a_id].releases==1)

-- The reverse acquisition order and all eleven real stage entries.
summon(b,1);foot(b,0)
for stage=0,10 do
    grant(1,legend_by_stage[stage]);local id=foot(b,1)
    transaction(1,{[legend_by_stage[stage]]=1});foot(b,0)
    assert(particles[id].released)
end
grant(0,legend_by_stage[4]);grant(1,legend_by_stage[8])
a_id=foot(a,1);local b_id=foot(b,1)
assert(a_id~=b_id, "players independently own their aura")
bus.emit(events.HERO_SUMMONED,{player_id=0,unit=b})
stable(a,a_id);stable(b,b_id)
summon(a,0) -- Restore the real equipment service after the deliberately invalid event.
a_id=foot(a,1)
a.dead=true;tick();foot(a,0);stable(b,b_id)
a.dead=false;tick();local revived_id=foot(a,1)
assert(revived_id~=a_id and particles[a_id].released)
tick();stable(a,revived_id)
local replacement=hero(30,0)
local replace_allocations=foot_allocations
local replace_loop=tasks.weapon_visual_lifecycle.callback
local replace_reentered, replace_callback_id, replace_after_allocations
on_destroy=function(id,p)
    replace_reentered=true;replace_callback_id=id
    assert(p.path==PATH, "hero transition must retire its owned root first")
    replace_loop()
    replace_after_allocations=foot_allocations
end
summon(replacement,0);foot(a,0);local replacement_id=foot(replacement,1)
assert(replace_reentered and replace_callback_id==revived_id,
    "replacement must exercise the real old-hero Destroy callback")
assert(replace_after_allocations==replace_allocations and foot_allocations==replace_allocations+1,
    "cleanup reentry must not recreate the old hero's owned aura")
assert(particles[revived_id].destroys==1 and particles[revived_id].releases==1)
assert(owned.debug_snapshot(0).hero==replacement:entindex()
    and owned.debug_snapshot(0).particle_id==replacement_id)
stable(b,b_id)
replacement.removed=true;tick();foot(replacement,0)
assert(particles[replacement_id].released)
local delayed=hero(31,0);delayed.model=""
summon(delayed,0);foot(delayed,0)
for _=1,4 do tick();foot(delayed,0) end
delayed.model="models/heroes/juggernaut/juggernaut.vmdl";tick();local delayed_id=foot(delayed,1)
tick();stable(delayed,delayed_id)

-- Defeat and final disconnect clear immediately while the engine entity is
-- still alive, and duplicated/late events cannot recreate that player's aura.
bus.emit(events.PLAYER_DEFEATED,{player_id="0",reason="test_defeat"});foot(delayed,0)
bus.emit(events.PLAYER_DISCONNECTED,{player_id=0,reason="test_defeat",defeat_cleanup=true})
assert(particles[delayed_id].destroys==1 and particles[delayed_id].releases==1)
grant(0,legend_by_stage[1]);summon(delayed,0);tick();foot(delayed,0);stable(b,b_id)
bus.emit(events.PLAYER_DISCONNECTED,{player_id=1,reason="disconnect_timeout"});foot(b,0)
summon(b,1);tick();foot(b,0)

-- Same-world hot init retires owned handles; generation guards leave one loop
-- and one effective set of listeners even without resetting the event bus.
boot();a=hero(40,0);grant(0,legend_by_stage[0]);summon(a,0);a_id=foot(a,1)
local old_loop=tasks.weapon_visual_lifecycle.callback
on_destroy=function() old_loop() end
service.init();foot(a,0)
assert(particles[a_id].destroys==1 and particles[a_id].releases==1)
tick();a_id=foot(a,1)
summon(a,0);stable(a,a_id)
for _=1,3 do service.init();foot(a,0);summon(a,0);a_id=foot(a,1) end
local stable_allocations=foot_allocations
grant(0,legend_by_stage[0]);tick();stable(a,a_id)
assert(foot_allocations==stable_allocations, "inactive old listeners must not duplicate creation")

-- A new Tools world can reuse the old integer ID for somebody else's effect.
local reused=a_id
for _,p in pairs(particles) do p.destroyed=true end
local foreign={path="particles/foreign_world_effect.vpcf",unit=hero(90,1),cp={},destroys=0,releases=0}
particles[reused]=foreign;world={}
service.init()
assert(foreign.destroys==0 and foreign.releases==0, "new-world reset must not retire reused foreign ID")
local new_a=hero(41,0);summon(new_a,0);foot(new_a,1)
assert(foreign.destroys==0 and foreign.releases==0)

-- Setup and independent cleanup failures cannot leak IDs or suppress the
-- original main-hand visual. The existing loop retries a missing aura.
for _,mode in ipairs({"throw","nil","negative","control"}) do
    boot();local u=hero(50,0);summon(u,0)
    local control_reentered, control_callback_id, control_before_allocations, control_after_allocations
    if mode=="control" then
        fault_control=true
        local failure_loop=tasks.weapon_visual_lifecycle.callback
        on_destroy=function(id,p)
            control_reentered=true;control_callback_id=id
            assert(p.path==PATH, "CP0 failure must clean its allocated owned root")
            control_before_allocations=foot_allocations
            failure_loop()
            control_after_allocations=foot_allocations
        end
    else fault_create=mode end
    grant(0,legend_by_stage[3]);foot(u,0)
    if mode=="control" then
        assert(particles[last_foot_id] and particles[last_foot_id].released,
            "CP failure must retire its already allocated aura")
        assert(control_reentered and control_callback_id==last_foot_id,
            "CP0 failure must exercise its real Destroy callback")
        assert(control_before_allocations==control_after_allocations,
            "CP0 cleanup reentry must wait for the next ordinary lifecycle poll")
        assert(particles[last_foot_id].destroys==1 and particles[last_foot_id].releases==1)
    end
    assert(service.debug_snapshot(0).particle_count==3, "optional aura failure must preserve main-hand visuals")
    tick();local recovered=foot(u,1);tick();stable(u,recovered)
    transaction(0,{[legend_by_stage[3]]=1});foot(u,0)
end
for _,mode in ipairs({"destroy","release","reenter"}) do
    boot();local u=hero(60,0);grant(0,legend_by_stage[9]);summon(u,0);local id=foot(u,1)
    if mode=="destroy" then fault_destroy=true end
    if mode=="release" then fault_release=true end
    if mode=="reenter" then on_destroy=function() tick() end end
    transaction(0,{[legend_by_stage[9]]=1});foot(u,0)
    assert(particles[id].destroys==1 and particles[id].releases==1,
        "independent cleanup and reentry must attempt Destroy/Release exactly once")
    tick();foot(u,0)
end
tick()
for name in pairs(tasks) do assert(name=="weapon_visual_lifecycle") end
assert(every_calls>1, "hot init coverage must include repeated init calls")
for _,name in ipairs(item_names) do assert(not name:find("scepter",1,true)) end
assert(type(owned.debug_snapshot)=="function")
print("WEAPON_OWNED_VISUAL_PASS real inventory/equipment/service events, 11 legend stages, atomic0-10 stable handle, main-hand switch, last removal, player isolation")
print("WEAPON_OWNED_LIFECYCLE_PASS death/revive, replacement+cleanup reentry, pending model, final disconnect, late events, same/new-world init+poll restoration, shared single0.25s loop")
print("WEAPON_OWNED_FAILURE_PASS native CP0 feet binding, allocation/CP faults+cleanup reentry, independent cleanup/reentry, original main visuals retained, no Scepter/gameplay mutation")

boot()
local deleting, survivor = hero(900,0), hero(901,1)
grant(0,legend_by_stage[3]); grant(1,legend_by_stage[3])
summon(deleting,0); summon(survivor,1)
local removed_aura, survivor_aura = foot(deleting,1), foot(survivor,1)
deleting.removed=true
bus.emit(events.HERO_REMOVED,{player_id=0,unit=deleting,entindex=900})
foot(deleting,0); stable(survivor,survivor_aura)
assert(particles[removed_aura].released and not owned.debug_snapshot(0).unavailable)
local resummoned=hero(902,0);summon(resummoned,0)
local replacement_aura=foot(resummoned,1)
bus.emit(events.HERO_REMOVED,{player_id=0,unit=deleting,entindex=900})
tick();stable(resummoned,replacement_aura);stable(survivor,survivor_aura)
print("WEAPON_OWNED_REMOVAL_PASS invalid handle, retained inventory, resummon, no permanent unavailability, player and identity isolation")
