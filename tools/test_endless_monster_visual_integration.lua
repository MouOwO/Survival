-- Production resolver, factory, visual assembly, corpse lifecycle and endless
-- scheduler. Only native entities/map placement and archive I/O are replaced.
package.path = "scripts/vscripts/?.lua;" .. package.path

local noop = function() end
local checks, clock, next_index, prop_spawns, world_scans = 0, 0, 100, 0, 0
local bodies, props, rewards = {}, {}, {}
local fail_body_create, fail_body_setter, fail_prop_at, fail_ornament_attach
local function check(value, message)
    checks = checks + 1
    assert(value, message)
end
local function near(actual, expected, message)
    check(type(actual) == "number" and math.abs(actual - expected) <= math.max(1, math.abs(expected)) * 1e-9,
        (message or "numeric value") .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end

DOTA_TEAM_BADGUYS, DOTA_TEAM_GOODGUYS = 3, 2
DOTA_UNIT_CAP_MOVE_GROUND, DOTA_UNIT_CAP_MELEE_ATTACK, DOTA_UNIT_CAP_RANGED_ATTACK = 1, 1, 2
EF_BONEMERGE, SOLID_NONE = 1, 0
Vector = function(x, y, z) return {x = x, y = y, z = z} end
IsValidEntity = function(value) return value and not value.removed end
GameRules = {GetGameTime = function() return clock end}
PlayerResource = {GetPlayer = function() return nil end}
GetGroundHeight = function() return 0 end
FindClearSpaceForUnit = function(body) body.placed = true end
Entities = {FindAllByClassname = function()
    world_scans = world_scans + 1
    error("fresh endless appearances must not scan the world")
end}
ParticleManager = {CreateParticle = function() error("endless outfits must not add ambient particles") end}

local function entity(class, model)
    next_index = next_index + 1
    local value = {class = class, index = next_index, model = model, alive = true,
        position = Vector(0, 0, 0), skin = 0, activities = {}, modifiers = {}, hull = 10}
    function value:IsNull() return self.removed == true end
    function value:IsAlive() return self.alive and not self.removed end
    function value:entindex() return self.index end
    function value:GetUnitName() return self.class end
    function value:GetOwner() return self.owner end
    function value:SetOwner(owner) self.owner = owner end
    function value:SetParent(parent, attachment) self.parent, self.attachment = parent, attachment end
    function value:FollowEntity(parent, merge)
        check(parent == self.parent and merge == true, "native components inherit the owner's skeleton")
        self.bone_merge = true
    end
    function value:AddEffects(effect) self.effect = effect end
    function value:SetSolid(solid) self.solid = solid end
    function value:SetModel(path) self.model = path; self.model_writes = (self.model_writes or 0) + 1 end
    function value:SetOriginalModel(path) self.original_model = path end
    function value:GetModelName() return self.model end
    function value:SetModelScale(scale) self.scale = scale; self.scale_writes = (self.scale_writes or 0) + 1 end
    function value:SetSkin(skin) self.skin = skin end
    function value:GetSkin() return self.skin end
    function value:SetMaterialGroup(group) self.material_group = group end
    function value:AddActivityModifier(name) self.activities[#self.activities + 1] = name end
    function value:ClearActivityModifiers() self.activities = {} end
    function value:ScriptLookupAttachment() return 0 end
    function value:SetLocalOrigin(origin)
        if fail_ornament_attach then error("native ornament transform rejected") end
        self.local_origin = origin
    end
    function value:SetLocalAngles(pitch, yaw, roll) self.local_angles = {pitch, yaw, roll} end
    function value:GetAbsOrigin() return self.position end
    function value:SetAbsOrigin(origin) self.position = origin end
    function value:AddNoDraw() self.hidden = true end
    function value:SetTeam(team) self.team = team end
    value.SetTeamNumber = value.SetTeam
    function value:GetTeamNumber() return self.team end
    function value:GetHullRadius() return self.hull end
    function value:SetHullRadius(radius) self.hull = radius end
    function value:SetMoveCapability(capability) self.move_capability = capability end
    function value:SetBaseMaxHealth(health) self.base_max_health = health end
    function value:SetMaxHealth(health) self.max_health = health end
    function value:SetHealth(health)
        if fail_body_setter then error("native body setter rejected") end
        self.health = health
    end
    function value:SetBaseDamageMin(damage) self.damage_min = damage end
    function value:SetBaseDamageMax(damage) self.damage_max = damage end
    function value:SetPhysicalArmorBaseValue(armor) self.native_armor = armor end
    function value:SetBaseMoveSpeed(speed) self.move_speed = speed end
    function value:SetBaseAttackTime(interval) self.attack_interval = interval end
    function value:Script_SetAttackRange(range) self.attack_range = range end
    function value:SetAttackCapability(capability) self.attack_capability = capability end
    function value:HasModifier(name) return self.modifiers[name] ~= nil end
    function value:AddNewModifier(_, _, name, params) self.modifiers[name] = params end
    function value:FindAbilityByName() return nil end
    function value:SetDeathXP(xp) self.death_xp = xp end
    function value:SetMinimumGoldBounty(gold) self.minimum_gold = gold end
    function value:SetMaximumGoldBounty(gold) self.maximum_gold = gold end
    function value:SetBaseMagicalResistanceValue(resistance) self.magic_resistance = resistance end
    value.ResetSequenceInfo, value.SetPlaybackRate = noop, noop
    return value
end
SpawnEntityFromTableSynchronous = function(class, data)
    prop_spawns = prop_spawns + 1
    check(class == "prop_dynamic" and data.solid == "0" and data.DisableBoneFollowers == "1",
        "all native and custom adornments are nonblocking props")
    if prop_spawns == fail_prop_at then return nil end
    local prop = entity(class, data.model)
    prop.spawn_data = data
    props[#props + 1] = prop
    return prop
end
CreateUnitByName = function(name, position, clear, _, _, team)
    if fail_body_create then return nil end
    check(name == "npc_survival_wave_monster" and clear == false,
        "visual changes use the existing challenge unit and explicit placement")
    local body = entity(name, "native/base.vmdl")
    body.position, body.team = position, team
    bodies[#bodies + 1] = body
    return body
end

local bus, events = require("core/event_bus"), require("core/events")
local scheduler = require("core/scheduler")
local guard = require("systems/gameplay_phase_guard")
UTIL_Remove = function(value)
    check(not value.removed, "native ownership must never remove an entity twice")
    value.removed, value.alive = true, false
    if value.class == "npc_survival_wave_monster" then
        bus.emit(events.ENGINE_ENTITY_KILLED, {victim = value, victim_entindex = value.index})
    end
end
package.loaded["systems/player_context_service"] = {is_defeated = function() return false end}
package.loaded["systems/archive_service"] = {
    record_endless_wave = function(player, number, difficulty)
        rewards[#rewards + 1] = {player = player, wave = number, difficulty = difficulty}
    end,
    flush_endless_rewards = noop,
}

local config = require("systems/archive_endless_config")
local visual_config = require("systems/archive_endless_visual_config")
local visual_service = require("visual/endless_monster_visual_service")
local appearance = require("visual/model_appearance_service")
local corpse = require("systems/monster_corpse_lifecycle_service")
local wave = require("systems/wave_system")
local endless = arg[1] and assert(loadfile(arg[1]))() or require("systems/archive_endless_service")
local rule_rows = require("config/generated/global_rules").by_id
local hull = require("config/global_rules").wave_ground_monster_hull_radius

-- Seed the actual factory's map channel without running normal map waves.
local marker = {GetAbsOrigin = function() return Vector(600, 0, 0) end}
local seeded = false
for index = 1, 100 do
    local name = debug.getupvalue(wave.spawn_challenge_monster, index)
    if not name then break end
    if name == "wave_channels" then
        debug.setupvalue(wave.spawn_challenge_monster, index, {[0] = {marker = marker}})
        seeded = true
        break
    end
end
check(seeded, "actual factory fixture has a player spawn channel")

local function tick(delta)
    clock = clock + delta
    scheduler.think()
end
local function live_props(owner)
    local found = {}
    for _, prop in ipairs(props) do
        if not prop.removed and (not owner or prop.owner == owner) then found[#found + 1] = prop end
    end
    return found
end
local function live_bodies()
    local found = {}
    for _, body in ipairs(bodies) do if body:IsAlive() then found[#found + 1] = body end end
    return found
end
local function reset()
    endless.init()
    corpse.init()
    check(#live_props() == 0, "reset releases all previous bodies and outfits")
    scheduler.clear()
    bus.reset()
    guard.reset()
    guard.set_post_clear_frozen(true)
    bus.handle_request("archive.challenge_state", function() return {expired = 0} end)
    corpse.init()
    endless.init()
    fail_body_create, fail_body_setter, fail_prop_at, fail_ornament_attach = nil, nil, nil, nil
end
local function kill(body)
    body.alive = false
    bus.emit(events.ENGINE_ENTITY_KILLED, {victim = body, victim_entindex = body.index})
end
local function fill_wave()
    while endless.snapshot(0).pending > 0 do tick(config.rules.spawn_interval) end
    local found = live_bodies()
    check(#found == config.rules.monsters_per_wave, "real endless rows retain five monsters per wave")
    return found
end
local function geometry(body)
    local parts = {}
    for _, prop in ipairs(live_props(body)) do
        local origin = prop.local_origin or Vector(0, 0, 0)
        parts[#parts + 1] = table.concat({prop.model, tostring(prop.bone_merge == true),
            tostring(origin.x), tostring(origin.y), tostring(origin.z)}, ":")
    end
    table.sort(parts)
    return body.model .. "|" .. table.concat(parts, "|")
end
local function assert_body(body, number)
    local visual, stats = assert(visual_config.resolve(number)), assert(config.wave(1, number))
    check(body.model == visual.model_path and body.original_model == visual.model_path,
        "factory and visual assembly preserve the configured actual body")
    check(body.survival_endless_monster_visual and body.survival_endless_visual_id == visual.visual_id,
        "real visual service owns the resolved outfit")
    near(body.scale, visual.model_scale * (2 / 3), "authored body scale shrinks exactly once")
    near(body.survival_endless_health, stats.health, "logical health remains authored")
    near(body.survival_endless_attack, stats.attack, "logical attack remains authored")
    near(body.health * body.survival_endless_health_scale, stats.health, "native health projection remains exact")
    near(body.damage_max * body.survival_endless_attack_scale, stats.attack, "native attack projection remains exact")
    near(body.survival_war3_armor, stats.war3_armor, "authored armor remains unchanged")
    near(body.move_speed, config.rules.move_speed, "movement speed")
    near(body.attack_interval, 1 / config.rules.attack_speed, "attack interval")
    near(body.attack_range, config.rules.attack_range, "attack range")
    near(body.magic_resistance, config.rules.magic_resistance, "magic resistance")
    near(body.hull, hull, "visual growth must not enlarge collision")
    check(body.move_capability == DOTA_UNIT_CAP_MOVE_GROUND and body.survival_wave_movement_type == "ground"
            and body.survival_wave_no_unit_collision == false and body.attack_capability == DOTA_UNIT_CAP_MELEE_ATTACK,
        "flying monster appearances retain original ground navigation, melee and physical queue")
    local actual_parts = live_props(body)
    check(#actual_parts == #visual.components + #visual.ornaments, "every declared native component and ornament is present")
    for _, declared in ipairs(visual.components) do
        local actual = body.survival_model_appearance_state.components[declared.component_id]
        check(actual and not actual.removed and actual.model == declared.model_path and actual.bone_merge,
            "complete native outfit contains its exact declared component")
        near(actual.scale, (tonumber(declared.model_scale) or 1) * visual.model_scale * (2 / 3),
            "native wearable scales with its owner's final visual scale")
        local assembled = body.survival_endless_monster_visual.asset.components
        for _, component in ipairs(assembled) do
            if component.component_id == declared.component_id then
                near(component.model_scale, (tonumber(declared.model_scale) or 1) * visual.model_scale,
                    "assembly cache retains an authored component scale")
            end
        end
    end
    for _, prop in ipairs(actual_parts) do
        if prop.survival_is_endless_monster_ornament then
            check(not prop.bone_merge and prop.parent == body and prop.local_origin,
                "custom ornaments use static parent transforms instead of unrelated skeletons")
        end
    end
    return visual
end

reset()
check(endless.start(0, 1), "production endless run starts with configured first monster")
local first_models, first_geometries, default_bodies = {}, {}, {}
local first_base_scale
for number = 1, 401 do
    check(endless.snapshot(0).wave == number, "real wave advancement is sequential")
    local found = fill_wave()
    local expected_geometry, visual
    for _, body in ipairs(found) do
        visual = assert_body(body, number)
        local signature = geometry(body)
        if not expected_geometry then expected_geometry = signature end
        check(signature == expected_geometry, "all five actual assembled monsters have identical geometry")
        check(body.survival_endless_monster_visual.visual == visual,
            "five monsters share the real resolver's cached immutable visual")
    end
    if number <= 50 then first_models[found[1].model] = true end
    if number == 1 or number == 51 or number == 101 or number == 151 then
        check(visual.display_name == "灰鬃狼", "four outfit rounds keep the first monster's identity")
        first_geometries[#first_geometries + 1] = expected_geometry
    end
    if number == 1 then first_base_scale = found[1].scale end
    if number == 201 or number == 401 then
        near(found[1].scale, first_base_scale * 1.5, "both 201 and 401 are fixed 1.5 times the same baseline")
        check(expected_geometry == first_geometries[1], "the 200-wave appearance cycle returns to the original shape")
    end
    if number == 20 or number == 25 then
        default_bodies[number] = found[1]
        check(#visual.components == (number == 20 and 2 or 3), "hero-shaped monsters include all official default wearable slots")
    end
    if number == 175 then
        check(found[1].model == "models/items/nerubian_assassin/nyx_monster/nyx_monster_base.vmdl"
                and #visual.components == 4,
            "Nyx fourth outfit applies its actual hero_model_change body and all four matching parts")
        for _, part in ipairs(live_props(found[1])) do
            check(part.model:find("models/items/nerubian_assassin/nyx_monster/", 1, true) == 1,
                "Nyx transformed body uses its matching native component paths")
        end
    end
    if number == 51 or number == 175 then
        local allocations, body_writes = prop_spawns, found[1].scale_writes
        local signature = geometry(found[1])
        tick(1)
        tick(1)
        check(prop_spawns == allocations and found[1].scale_writes == body_writes
                and geometry(found[1]) == signature,
            "countdown ticks do not resolve or reassemble custom or native appearances")
    end
    for _, body in ipairs(found) do kill(body) end
    if number == 51 or number == 175 then
        check(#live_props(found[1]) == #visual.components + #visual.ornaments,
            "tracked deaths retain the complete original outfit during the hold")
        tick(0.01)
        check(not found[1].hidden and not found[1].removed and geometry(found[1]) == expected_geometry,
            "a queued successor cannot strip the animated previous corpse")
    else
        tick(0.01)
    end
end
local unique_models = 0
for _ in pairs(first_models) do unique_models = unique_models + 1 end
check(unique_models == 50, "all first fifty real factory bodies use distinct model resources")
local distinct_geometry = {}
for _, signature in ipairs(first_geometries) do distinct_geometry[signature] = true end
local geometry_count = 0
for _ in pairs(distinct_geometry) do geometry_count = geometry_count + 1 end
check(geometry_count == 4, "1/51/101/151 use four genuinely different assembled geometries")
check(world_scans == 0, "fresh births and natural corpse cleanup use no world scans")

-- Isolate corpse timing: consume pending births before cancelling the run,
-- leaving only dead tracked bodies and their exact retained adornments.
while endless.snapshot(0).wave < 420 do
    for _, body in ipairs(fill_wave()) do kill(body) end
    tick(0.01)
end
local found = fill_wave()
local native_body = default_bodies[25]
check(native_body.removed, "earlier native corpses have fully completed the real sinking lifecycle")
for _, body in ipairs(found) do kill(body) end
endless.cancel(0, "integration corpse completion")
local dead = found[1]
local before_sink_parts = #live_props(dead)
check(before_sink_parts > 0 and not dead.removed, "dead decorated bodies retain geometry after challenge cancellation")
tick(rule_rows.monster_corpse_hold_seconds.value - 0.01)
check(#live_props(dead) == before_sink_parts and not dead.hidden, "outfit stays through the real hold interval")
tick(0.2)
check(dead.position.z < 32 and #live_props(dead) == before_sink_parts,
    "corpse sinks with its complete adornments attached")
tick(rule_rows.monster_corpse_sink_seconds.value)
check(dead.hidden and #live_props(dead) == 0 and not dead.survival_endless_monster_visual,
    "real sinking completion removes the full outfit when hiding the corpse")
tick(rule_rows.monster_corpse_remove_delay_seconds.value + 0.01)
check(dead.removed and #live_props() == 0, "final corpse removal leaves no native or custom props")

reset()
check(endless.start(0, 1))
for _ = 1, 50 do
    for _, body in ipairs(fill_wave()) do kill(body) end
    tick(0.01)
end
found = fill_wave()
check(endless.snapshot(0).wave == 51 and #live_props(found[1]) == 2, "custom second round is actually decorated")
endless.cancel(0, "manual cancellation")
for _, body in ipairs(found) do
    check(body.removed and #live_props(body) == 0 and not body.survival_endless_monster_visual,
        "cancelling releases each live body and both custom props")
end
tick(2)
tick(0.1)
check(#live_props() == 0, "cancellation plus preceding corpse completion leaves no orphan props")

reset()
fail_body_create = true
check(not endless.start(0, 1) and #live_bodies() == 0 and #live_props() == 0,
    "a native factory creation failure leaks no unit or decoration")
fail_body_create = nil
fail_body_setter = true
check(not endless.start(0, 1) and #live_bodies() == 0 and #live_props() == 0,
    "a real factory setup exception removes its partial body before visual assembly")

-- Native second-slot failure and custom second-prop failure use real assembly
-- rollback, followed by the real run's registered-unit cleanup.
for _, target in ipairs({20, 51}) do
    reset()
    check(endless.start(0, 1))
    for _ = 1, target - 1 do
        for _, body in ipairs(fill_wave()) do kill(body) end
        if endless.snapshot(0).wave == target - 1 then fail_prop_at = prop_spawns + 2 end
        tick(0.01)
    end
    check(not endless.is_running(0), "failing second native/ornament component closes the partial run")
    tick(2)
    tick(0.1)
    check(#live_bodies() == 0 and #live_props() == 0,
        "actual two-component rollback and forced run cleanup leave no orphan entities")
end

reset()
check(endless.start(0, 1))
for _ = 1, 50 do
    for _, body in ipairs(fill_wave()) do kill(body) end
    if endless.snapshot(0).wave == 50 then fail_ornament_attach = true end
    tick(0.01)
end
check(not endless.is_running(0), "native ornament parenting failure closes the partial wave")
tick(2)
tick(0.1)
check(#live_props() == 0 and #live_bodies() == 0, "ornament transform failure retires the spawned partial prop")
reset()
check(#live_props() == 0 and #live_bodies() == 0, "all integration scenarios finish without live leftovers")
print("ENDLESS_MONSTER_VISUAL_INTEGRATION_PASS: " .. checks .. " checks; real 401-wave factory/appearance/corpse flow, 50 unique models, four geometries, fixed 1.5 growth, default/transformed native wearables, cached five births and failure cleanup")
