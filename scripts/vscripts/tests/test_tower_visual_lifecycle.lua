-- SIMULATION + CSV CONTRACT: real event bus/projection/profiles, mocked renderer.
-- Verifies particle ownership and does not claim visual appearance in Workshop.
package.path = "scripts/vscripts/?.lua;" .. package.path
local bus, events = require("core/event_bus"), require("core/events")
local scheduler = require("core/scheduler")
local profiles = require("config/generated/tower_visual_profiles")
-- Windows Lua 5.1 uses ANSI fopen; the runner supplies an ASCII-path copy of
-- the exact UTF-8 source CSV without changing its contents.
local csv = assert(io.open(arg and arg[1] or "data/csv/资源系统/tower_visual_profiles.csv", "rb"))
local headers, records = nil, 0
for line in csv:lines() do
    line = line:gsub("\r$", "")
    if line ~= "" and line:sub(1, 1) ~= "#" then
        local fields = {}
        for value in (line .. ","):gmatch("(.-),") do fields[#fields + 1] = value end
        if not headers then headers = fields
        else
            records = records + 1
            local row = assert(profiles.by_id[fields[1]], "generated profile missing")
            for i, key in ipairs(headers) do
                if key == "enabled" then assert(row[key] == (fields[i] == "1"))
                elseif key == "color" or key:find("^color_") then assert(table.concat(row[key] or {}, "|") == fields[i])
                elseif key:find("^radius_") or key == "alpha" then assert(row[key] == tonumber(fields[i]))
                else assert((row[key] or "") == fields[i], "CSV/generated mismatch: " .. key) end
            end
            assert(row.radius_r > 0 and row.radius_r < row.radius_sr and row.radius_sr < row.radius_ssr)
            assert(row.alpha > 0 and row.alpha <= 1)
        end
    end
end
csv:close()
assert(records == 8 and #profiles.rows == records)

PATTACH_ABSORIGIN_FOLLOW = 10
PATTACH_POINT_FOLLOW = 11
DOTA_GAMERULES_STATE_POST_GAME = 8
Vector = function(x, y, z) return { x = x, y = y, z = z } end
local world, phase = {}, 6
GameRules = { GetGameTime = function() return 0 end,
    State_Get = function() return phase end,
    GetGameModeEntity = function() return world end }
local function forbidden() error("presentation must not issue orders or damage") end
ApplyDamage, ExecuteOrderFromTable, CreateUnitByName = forbidden, forbidden, forbidden
local next_id, created, destroyed, released = 0, 0, {}, {}
local particles, precached, listed = {}, {}, {}
local invalid_create_at, fail_control_at, fail_destroy_id
ParticleManager = {}
function ParticleManager:CreateParticle(name, attach, unit)
    created = created + 1
    if created == invalid_create_at then return nil end
    assert(attach == PATTACH_ABSORIGIN_FOLLOW and unit)
    local id = next_id; next_id = next_id + 1
    particles[id] = { name = name, unit = unit, controls = {}, world = world }
    return id
end
function ParticleManager:SetParticleControlEnt(id, cp, unit, attach, attachment)
    assert((cp == 0 and attach == PATTACH_ABSORIGIN_FOLLOW)
        or (cp == 1 and attach == PATTACH_ABSORIGIN_FOLLOW and attachment == "")
        or (cp == 1 and attach == PATTACH_POINT_FOLLOW and attachment == "attach_hitloc"))
    particles[id].bound_unit = unit
    particles[id].bindings = particles[id].bindings or {}
    particles[id].bindings[cp] = { unit = unit, attachment = attachment }
end
function ParticleManager:SetParticleControl(id, cp, value)
    if created == fail_control_at then error("injected control failure") end
    assert(cp == 1 or cp == 2 or cp == 62, "only size/alpha, color and native HSV are constant CPs")
    particles[id].controls[cp] = value
end
function ParticleManager:DestroyParticle(id, immediate)
    local effect = assert(particles[id], "destroying nonexistent ID")
    assert(effect.world == world, "must not destroy old-world reused particle IDs")
    assert(immediate and not effect.destroyed, "exactly one destroy per ID")
    effect.destroyed = true
    destroyed[#destroyed + 1] = id
    if id == fail_destroy_id then error("injected destroy failure") end
end
function ParticleManager:ReleaseParticleIndex(id)
    local effect = assert(particles[id])
    assert(effect.world == world and not effect.released)
    effect.released = true
    released[#released + 1] = id
end
PrecacheResource = function(kind, name)
    assert(kind == "particle" and not precached[name], "deduplicate precache")
    precached[name] = true
end
local function unit(index)
    local u = { index = index, alive = true, origin = Vector(0, 0, 128), projectile = "row_default" }
    function u:entindex() return self.index end
    function u:IsNull() return self.null == true end
    function u:IsAlive() return self.alive end
    function u:GetAbsOrigin() return self.origin end
    function u:SetRangedProjectileName(value) self.projectile = value end
    u.SetBaseDamageMin, u.SetBaseDamageMax, u.SetProjectileSpeed, u.SetBaseAttackTime = forbidden, forbidden, forbidden, forbidden
    return u
end
local function state(u, level, class_id)
    return { unit = u, entindex = u.index, player_id = u.player_id or 0,
        building_id = "arrow_tower", level = level, tower_class = class_id }
end
local function live_count()
    local count = 0
    for _, effect in pairs(particles) do
        if effect.world == world and not effect.released then count = count + 1 end
    end
    return count
end
bus.handle_request(events.BUILDING_LIST_REQUEST, function(payload)
    assert(payload.player_id == nil, "recover all participants, not only player zero")
    return { buildings = listed }
end)
local service = require("systems/tower_visual_service")
service.precache({})
local expected_precache = {["particles/base_attacks/ranged_goodguy.vpcf"] = true}
expected_precache["particles/units/heroes/hero_clinkz/clinkz_searing_arrow_linear_proj.vpcf"] = true
local trial_base_paths = {
    [1] = "particles/survival/towers/amber_portal/ground.vpcf",
    [2] = "particles/survival/towers/trial/mystery_ground.vpcf",
    [3] = "particles/survival/towers/trial/lightning_ground.vpcf",
    [5] = "particles/survival/towers/trial/multi_ground.vpcf",
    [6] = "particles/survival/towers/ice_portal/ground.vpcf",
}
for _, path in pairs(trial_base_paths) do expected_precache[path] = true end
local old_death_path = "particles/survival/towers/death_willow/shadow_ground.vpcf"
expected_precache[old_death_path] = true
for _, portal in ipairs({"ice_portal", "amber_portal"}) do
    for _, layer in ipairs({"dark_center", "interior", "sparkles"}) do
        expected_precache["particles/survival/towers/" .. portal .. "/" .. layer .. ".vpcf"] = true
    end
end
expected_precache["particles/survival/towers/trial/death_ground.vpcf"] = true -- compatible old-profile transition
expected_precache["particles/survival/towers/trial/frost_ground.vpcf"] = true -- compatible old frost profile
for _, name in ipairs({"dark", "durable", "evil"}) do expected_precache["particles/survival/towers/trial/valley_" .. name .. ".vpcf"] = true end
local shadow_path = "particles/units/heroes/hero_slark/slark_shadow_dance_dummy.vpcf"
expected_precache[shadow_path] = true
local machine_base_paths = {
    "particles/units/heroes/hero_spirit_breaker/spirit_breaker_haste_owner_dark.vpcf",
    "particles/units/heroes/hero_spirit_breaker/spirit_breaker_haste_owner_timer.vpcf",
}
for _, path in ipairs(machine_base_paths) do expected_precache[path] = true end
local anti_air_base_paths = {
    "particles/units/heroes/hero_templar_assassin/templar_assassin_trap_rings.vpcf",
    "particles/units/heroes/hero_templar_assassin/templar_assassin_trap_rings_inner.vpcf",
}
for _, path in ipairs(anti_air_base_paths) do expected_precache[path] = true end
expected_precache["particles/survival/towers/laser_charge.vpcf"] = true
expected_precache["particles/survival/towers/laser_blood.vpcf"] = true
expected_precache["particles/survival/towers/laser_afterglow.vpcf"] = true
for _, profile in ipairs(profiles.rows) do
    for _, field in ipairs({"core", "detail", "detail_ssr", "crown"}) do
        if profile[field] and profile[field] ~= "" then
            expected_precache["particles/survival/towers/" .. profile[field] .. ".vpcf"] = true
        end
    end
end
for name in pairs(expected_precache) do assert(precached[name], "missing profile precache: " .. name) end
for name in pairs(precached) do assert(expected_precache[name], "unexpected profile precache: " .. name) end
service.init()
assert(service.debug_snapshot().particles == 0 and live_count() == 0)

local base = unit(1)
bus.emit(events.BUILDING_CREATED, state(base, 1))
assert(live_count() == 0 and base.projectile == "particles/base_attacks/ranged_goodguy.vpcf")
base.projectile = "upgraded_csv_row_projectile"
bus.emit(events.BUILDING_CHANGED, state(base, 5))
assert(live_count() == 0 and base.projectile == "particles/base_attacks/ranged_goodguy.vpcf",
    "N upgrades must restore the chosen art after apply_tower_level")
base:SetRangedProjectileName(base.survival_projectile_model) -- deferred D refresh
assert(base.projectile == "particles/base_attacks/ranged_goodguy.vpcf")
service.remove(1)
-- Native Tinker mode has no Io orb/model overhead, including after upgrades.
local laser_skills = require("systems/tower_skill_runtime")
laser_skills.apply(base, { "laser_lv01" })
service.apply(state(base, 1, "class_2"))
assert(live_count() == 0)
laser_skills.apply(base, { "laser_lv03" })
service.apply(state(base, 3, "class_2"))
assert(live_count() == 0)
service.remove(1)
laser_skills.apply(base, {})
assert(live_count() == 0)

-- One attached Shadow Realm ground root replaces every legacy death layer.
-- Tier changes rebuild once; stars, relocation and the red-star band do not.
local death, death_profile = unit(9), profiles.by_id.class_1
assert(death_profile.native_base == "io_amber_portal")
local saved_death = {}
for _, field in ipairs({"native_base", "color", "color_r", "color_sr", "color_ssr"}) do saved_death[field] = death_profile[field] end
-- Exercise the transferred legacy sigil too, including compatible hot reloads.
death_profile.native_base = "willow_shadow_realm"
death_profile.color = {25,219,241}
death_profile.color_r, death_profile.color_sr, death_profile.color_ssr = {25,219,241}, {180,95,255}, {255,52,83}
assert(death_profile.native_base == "willow_shadow_realm")
local tier_colors = {r = {25, 219, 241}, sr = {180, 95, 255}, ssr = {255, 52, 83}}
local previous_id, previous_tier
for level = 6, 25 do
    local tier = level <= 10 and "r" or level <= 15 and "sr" or "ssr"
    local before_created = created
    assert(service.apply(state(death, level, "class_1")))
    local ids = service.debug_snapshot(death.index).particle_ids
    assert(#ids == 1 and live_count() == 1, "death has one root, including red-star levels")
    local effect = particles[ids[1]]
    assert(effect.name == old_death_path)
    assert(effect.bindings[0].unit == death and effect.bindings[0].attachment == "")
    assert(effect.controls[1].x == death_profile["radius_" .. tier] and effect.controls[1].z == 0.95)
    local color = effect.controls[2]
    assert(color.x == tier_colors[tier][1] and color.y == tier_colors[tier][2] and color.z == tier_colors[tier][3])
    if tier == previous_tier then
        assert(created == before_created and ids[1] == previous_id, "same-tier stars must retain the root")
    else
        assert(created == before_created + 1, "entering a tier creates exactly one root")
        if previous_id then assert(particles[previous_id].destroyed and particles[previous_id].released) end
    end
    previous_id, previous_tier = ids[1], tier
    death.origin = Vector(level * 100, -level * 10, 384)
    bus.emit(events.BUILDING_CHANGED, state(death, level, "class_1"))
    assert(service.debug_snapshot(death.index).particle_ids[1] == previous_id, "attached ground follows relocation")
end

-- Same-tier live configuration changes must not retain stale colors/size/alpha.
local saved_sr, saved_radius, saved_alpha = death_profile.color_sr, death_profile.radius_sr, death_profile.alpha
local function refresh_death(expected_color, radius, alpha)
    local old_id = service.debug_snapshot(death.index).particle_ids[1]
    local before_created, before_destroyed, before_released = created, #destroyed, #released
    assert(service.apply(state(death, 11, "class_1")))
    local id = service.debug_snapshot(death.index).particle_ids[1]
    assert(id ~= old_id and created == before_created + 1)
    assert(#destroyed == before_destroyed + 1 and #released == before_released + 1)
    local effect = particles[id]
    assert(effect.controls[1].x == radius and effect.controls[1].z == alpha)
    local color = effect.controls[2]
    assert(color.x == tonumber(expected_color[1]) and color.y == tonumber(expected_color[2]) and color.z == tonumber(expected_color[3]))
end
death_profile.color_sr = nil
refresh_death(death_profile.color, saved_radius, saved_alpha)
local fallback_id, before_created = service.debug_snapshot(death.index).particle_ids[1], created
death_profile.color_sr = {}
assert(service.apply(state(death, 11, "class_1")))
assert(created == before_created and service.debug_snapshot(death.index).particle_ids[1] == fallback_id,
    "missing and empty tier colors share the legacy profile color")
death_profile.color_sr = saved_sr
refresh_death(saved_sr, saved_radius, saved_alpha)
death_profile.color_sr = {181, 96, 254}
refresh_death(death_profile.color_sr, saved_radius, saved_alpha)
death_profile.radius_sr = saved_radius + 1
refresh_death(death_profile.color_sr, saved_radius + 1, saved_alpha)
death_profile.alpha = 0.9
refresh_death(death_profile.color_sr, saved_radius + 1, 0.9)
death_profile.color_sr, death_profile.radius_sr, death_profile.alpha = saved_sr, saved_radius, saved_alpha
refresh_death(saved_sr, saved_radius, saved_alpha)

-- Compatible old native rings and all three former image layers are retired.
death_profile.native_base = "dazzle_weave"
assert(service.apply(state(death, 11, "class_1")))
local old_native = service.debug_snapshot(death.index).particle_ids[1]
assert(particles[old_native].name == "particles/survival/towers/trial/death_ground.vpcf")
death_profile.native_base = "willow_shadow_realm"
assert(service.apply(state(death, 11, "class_1")))
assert(particles[old_native].destroyed and particles[old_native].released and live_count() == 1)
local external = ParticleManager:CreateParticle("particles/econ/items/shadow_fiend/sf_fire_arcana/sf_fire_arcana_ambient.vpcf",
    PATTACH_ABSORIGIN_FOLLOW, death)
local saved_layers = {}
for _, field in ipairs({"core", "detail", "detail_ssr", "crown"}) do saved_layers[field] = death_profile[field] or "" end
death_profile.native_base = ""
death_profile.core, death_profile.detail, death_profile.detail_ssr, death_profile.crown =
    "bases/ultimate", "bases/detail_ultimate", "bases/detail_ultimate", "bases/detail_motes"
assert(service.apply(state(death, 21, "class_1")))
local legacy_ids = service.debug_snapshot(death.index).particle_ids
assert(#legacy_ids == 3 and live_count() == 4)
death_profile.native_base = "willow_shadow_realm"
for field, value in pairs(saved_layers) do death_profile[field] = value end
assert(service.apply(state(death, 21, "class_1")))
assert(#service.debug_snapshot(death.index).particle_ids == 1 and live_count() == 2)
for _, id in ipairs(legacy_ids) do assert(particles[id].destroyed and particles[id].released) end
service.remove(death.index)
assert(not particles[external].destroyed and not particles[external].released and live_count() == 1,
    "base replacement and removal must preserve separately owned hero ornaments")
ParticleManager:DestroyParticle(external, true)
ParticleManager:ReleaseParticleIndex(external)

invalid_create_at = created + 1
assert(not service.apply(state(death, 6, "class_1")) and live_count() == 0)
invalid_create_at = nil
fail_control_at = created + 1
assert(not service.apply(state(death, 6, "class_1")) and live_count() == 0)
fail_control_at = nil
assert(service.apply(state(death, 6, "class_1")) and live_count() == 1)
service.remove(death.index)
assert(live_count() == 0)
for field, value in pairs(saved_death) do death_profile[field] = value end

-- The initial Fireline Sentinel receives the old sigil; promotion retires it
-- and creates only the native purple ring, without glyph or dark foot layers.
local sentinel = unit(8)
local route_config = require("config/tower_route_config")
for level = 6, 10 do
    local actual_row = route_config.current(state(sentinel, level, "class_4"))
    assert(actual_row.name == "火线哨兵" and actual_row.rarity == "R",
        "real Fireline CSV matches presentation R at levels 6–10")
    assert(service.apply(state(sentinel, level, "class_4")))
    local ids = service.debug_snapshot(sentinel.index).particle_ids
    assert(#ids == 1 and live_count() == 1 and particles[ids[1]].name == old_death_path)
    assert(particles[ids[1]].controls[2].x == 25 and particles[ids[1]].controls[2].y == 219)
end
local old_sigil = service.debug_snapshot(sentinel.index).particle_ids[1]
assert(route_config.current(state(sentinel, 11, "class_4")).name ~= "火线哨兵")
assert(service.apply(state(sentinel, 11, "class_4")))
local sentinel_ids = service.debug_snapshot(sentinel.index).particle_ids
assert(#sentinel_ids == 1 and particles[sentinel_ids[1]].name == machine_base_paths[2])
assert(particles[old_sigil].destroyed and particles[old_sigil].released and live_count() == 1)
service.remove(sentinel.index)

-- A late failure in one portal layer must retire every layer already created.
local portal_failure = unit(6)
fail_control_at = created + 4
assert(not service.apply(state(portal_failure, 6, "class_6")))
assert(live_count() == 0 and not service.debug_snapshot(portal_failure.index).tracked)
fail_control_at = nil

-- First profession forms use R in both CSV and presentation.
-- Test the real row/position mapping rather than an impossible class-at-N state.
for _, class_id in ipairs({"class_1", "class_6"}) do
    local initial = unit(7)
    local previous
    for level = 6, 10 do
        local before_created = created
        assert(service.apply(state(initial, level, class_id)))
        local ids = service.debug_snapshot(initial.index).particle_ids
        assert(#ids == 4 and live_count() == 4)
        assert(route_config.current(state(initial, level, class_id)).rarity == "R")
        assert(initial.projectile == "row_default", "R towers retain their authored attack projectile")
        if previous then assert(created == before_created and ids[1] == previous) end
        previous = ids[1]
    end
    service.remove(initial.index)
    assert(live_count() == 0)
end

local cases = {{6,1}, {10,1}, {11,2}, {15,2}, {16,2}, {20,2}, {21,3}, {25,3}}
for class_number = 1, 7 do
    local u = unit(10 + class_number)
    for _, case in ipairs(cases) do
        local payload = state(u, case[1], "class_" .. class_number)
        local applied = service.apply(payload)
        assert(applied)
        local replaced = true
        local expected_count = (class_number == 1 or class_number == 6) and 4 or class_number == 7 and 3 or 1
        assert(live_count() == expected_count and service.debug_snapshot().particles == expected_count)
        local profile = profiles.by_id[payload.tower_class]
        local rarity = case[1] <= 10 and "r" or case[1] <= 15 and "sr" or "ssr"
        local snapshot = service.debug_snapshot(u.index)
        local ids = snapshot and snapshot.particle_ids or {}
        if replaced then
            for _, field in ipairs({"core", "detail", "detail_ssr", "crown"}) do
                assert(not profile[field] or profile[field] == "", "replaced base must remove all old image layers")
            end
            for _, id in ipairs(ids) do
                assert(not particles[id].name:find("/bases/", 1, true), "old base must never stack with replacement")
            end
        end
        if class_number == 4 then
            local expected_path = rarity == "r" and old_death_path or machine_base_paths[2]
            assert(profile.enabled and #ids == 1 and particles[ids[1]].name == expected_path,
                "Fireline uses the transferred sigil; promoted machine gun keeps only the purple ring")
        end
        if class_number == 7 then
            for offset, path in ipairs(anti_air_base_paths) do
                local effect = particles[ids[offset+1]]
                assert(effect.name == path and effect.bindings[0].unit == u)
                assert(effect.bindings[0].attachment == "")
                local hsv = effect.controls[62]
                assert(hsv.x == 0 and hsv.y == 1 and hsv.z == 1, "trap rings need neutral HSV")
            end
        end
        local radius = profile["radius_" .. rarity]
        if expected_count > 0 and trial_base_paths[class_number] then
        assert(particles[ids[1]].name == trial_base_paths[class_number])
        assert(particles[ids[1]].controls[1].x == radius, "core keeps the profile radius")
        if expected_count == 4 then
            local portal = class_number == 1 and "amber_portal" or "ice_portal"
            for offset, layer in ipairs({"ground", "dark_center", "interior", "sparkles"}) do
                local effect = particles[ids[offset]]
                assert(effect.name == "particles/survival/towers/" .. portal .. "/" .. layer .. ".vpcf")
                assert(effect.bindings[0].unit == u and effect.bindings[0].attachment == "")
                assert(effect.controls[1].x == radius and effect.controls[1].z == profile.alpha,
                    "every portal layer receives its own size and alpha, without child inheritance")
                assert(effect.controls[2], "every portal layer receives its own color")
            end
        end
        end
        local before_created, before_destroyed = created, #destroyed
        bus.emit(events.BUILDING_CHANGED, payload)
        assert(created == before_created, "unchanged state must not duplicate base effects")
        u.origin = Vector(u.origin.x + 300, u.origin.y - 400, 384)
        bus.emit(events.BUILDING_CHANGED, payload)
        if class_number == 7 then
            assert(created == before_created + expected_count and #destroyed == before_destroyed + expected_count,
                "relocation must replace stationary native trap rings and retire old positions")
            assert(live_count() == expected_count)
        else
            assert(created == before_created and #destroyed == before_destroyed, "D must not rebuild attached effects")
        end
        for _, effect in pairs(particles) do
            if effect.world == world and not effect.released
                and effect.name ~= mystery_base_path
                and effect.name ~= machine_base_paths[1] and effect.name ~= machine_base_paths[2]
                and effect.name ~= anti_air_base_paths[1] and effect.name ~= anti_air_base_paths[2] then
                assert(effect.bound_unit == u and effect.controls[1].x > 0)
                assert(effect.controls[1].z > 0 and effect.controls[1].z <= 1)
                local color = profile["color_" .. rarity] or profile.color
                assert(effect.controls[2].x == tonumber(color[1]) and effect.controls[2].y == tonumber(color[2])
                    and effect.controls[2].z == tonumber(color[3]))
            end
        end
    end
    service.remove(u.index)
    assert(live_count() == 0)
end

local u = unit(30)
service.apply(state(u, 21, "class_1"))
local before_destroyed = #destroyed
service.apply(state(u, 21, "class_3"))
assert(#destroyed == before_destroyed + 4 and live_count() == 1, "cross-route swap must retire every old portal layer")
before_destroyed = #destroyed
service.apply(state(u, 21, "class_2"))
assert(#destroyed == before_destroyed + 1 and live_count() == 1,
    "replacement base retires core, detail and red-star layers")
assert(particles[service.debug_snapshot(u.index).particle_ids[1]].name == trial_base_paths[2])
service.apply(state(u, 21, "class_4"))
assert(live_count() == 1, "machine gun retains only the purple ring after a route change")
local replacement = unit(30)
service.apply(state(replacement, 11, "class_6"))
assert(live_count() == 4)
u.alive = false
bus.emit(events.ENGINE_ENTITY_KILLED, { victim = u })
assert(live_count() == 4, "late death of reused entindex must not clear replacement")
replacement.alive = false
bus.emit(events.ENGINE_ENTITY_KILLED, { victim = replacement })
assert(live_count() == 0)
replacement.alive = true
service.apply(state(replacement, 16, "class_6"))
bus.emit(events.BUILDING_DESTROYED, { entindex = 30, unit = replacement })
assert(live_count() == 0)
service.remove(30)

local ultimate = unit(40)
local ultimate_state = {unit = ultimate, entindex = 40, building_id = "ultimate_tower", level = 1, player_id = 1}
bus.emit(events.TOWER_FUSION_RUNTIME_CHANGED, ultimate_state)
assert(live_count() == 4)
local shadow_id = service.debug_snapshot(40).particle_ids[4]
assert(particles[shadow_id].name == shadow_path)
assert(particles[shadow_id].bindings[1].unit == ultimate)
assert(particles[shadow_id].bindings[1].attachment == "attach_hitloc")
local shadow_created = created
ultimate.origin = Vector(700, -200, 384)
for _ = 1, 20 do
    bus.emit(events.TOWER_FUSION_RUNTIME_CHANGED, ultimate_state)
    service._sweep_for_test()
end
assert(created == shadow_created and live_count() == 4,
    "persistent smoke survives idle/move/refresh without recreating")
bus.emit(events.TOWER_FUSION_RUNTIME_REMOVED, { entindex = 40 })
assert(live_count() == 0)
assert(particles[shadow_id].destroyed and particles[shadow_id].released)

-- A failed setup rolls back partial ownership; cleanup continues if one
-- renderer destroy throws, including releasing that same index.
invalid_create_at = created + 2
assert(not service.apply(state(replacement, 21, "class_7")))
assert(live_count() == 0 and service.debug_snapshot().towers == 0)
invalid_create_at = nil
fail_control_at = created + 2
assert(not service.apply(state(replacement, 21, "class_7")))
assert(live_count() == 0)
fail_control_at = nil
service.apply(state(replacement, 21, "class_7"))
fail_destroy_id = next_id - 2
service.remove(30)
assert(live_count() == 0 and #destroyed == #released)
fail_destroy_id = nil

service.apply(state(replacement, 6, "class_6"))
replacement.null = true
service._sweep_for_test()
assert(live_count() == 0)
replacement.null = false
listed = {state(replacement, 11, "class_6"), ultimate_state}
service.init()
assert(live_count() == 8 and service.debug_snapshot().towers == 2)
before_destroyed = #destroyed
service.init()
assert(#destroyed == before_destroyed + 8 and live_count() == 8,
    "same-world init must destroy all old layers including smoke before rebuilding")
assert(scheduler.task_count() == 1)
local before_created = created
bus.emit(events.BUILDING_CHANGED, state(replacement, 21, "class_6"))
assert(created == before_created + 4, "old generation subscriptions must stay inactive")
assert(live_count() == 8)

before_destroyed = #destroyed
world, next_id, listed = {}, 0, {}
service.init()
assert(#destroyed == before_destroyed and live_count() == 0,
    "new world init must forget the old world's particle IDs")
service.apply(ultimate_state)
assert(live_count() == 4)
phase = DOTA_GAMERULES_STATE_POST_GAME
assert(service._sweep_for_test() == false and live_count() == 0)
assert(service.debug_snapshot().towers == 0)
print("TOWER_VISUAL_LIFECYCLE_SIMULATION_PASS: CSV, 7 routes, N projectile, tiers, move, replacement, teardown, failures, restart")
