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
                elseif key == "color" then assert(table.concat(row[key], "|") == fields[i])
                elseif key:find("^radius_") or key == "alpha" then assert(row[key] == tonumber(fields[i]))
                else assert(row[key] == fields[i], "CSV/generated mismatch: " .. key) end
            end
            assert(row.radius_r > 0 and row.radius_r < row.radius_sr and row.radius_sr < row.radius_ssr)
            assert(row.alpha > 0 and row.alpha <= 1)
        end
    end
end
csv:close()
assert(records == 8 and #profiles.rows == records)

PATTACH_ABSORIGIN_FOLLOW = 10
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
function ParticleManager:SetParticleControlEnt(id, cp, unit, attach)
    assert(cp == 0 and attach == PATTACH_ABSORIGIN_FOLLOW)
    particles[id].bound_unit = unit
end
function ParticleManager:SetParticleControl(id, cp, value)
    if created == fail_control_at then error("injected control failure") end
    assert(cp == 1 or cp == 2, "only size/alpha and color are constant CPs")
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
local precache_count = 0
for _ in pairs(precached) do precache_count = precache_count + 1 end
assert(precache_count == 11, "eight cores, two shared layers and native projectile")
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
local cases = {{6,1}, {10,1}, {11,2}, {15,2}, {16,2}, {20,2}, {21,3}, {25,3}}
for class_number = 1, 7 do
    local u = unit(10 + class_number)
    for _, case in ipairs(cases) do
        local payload = state(u, case[1], "class_" .. class_number)
        assert(service.apply(payload))
        assert(live_count() == case[2] and service.debug_snapshot().particles == case[2])
        local before_created, before_destroyed = created, #destroyed
        u.origin = Vector(300, -400, 384) -- D moves this same entity and style.
        bus.emit(events.BUILDING_CHANGED, payload)
        assert(created == before_created and #destroyed == before_destroyed, "D must not rebuild attached effects")
        for _, effect in pairs(particles) do
            if effect.world == world and not effect.released then
                assert(effect.bound_unit == u and effect.controls[1].x > 0)
                assert(effect.controls[1].z > 0 and effect.controls[1].z <= 1)
                assert(effect.controls[2].x == tonumber(profiles.by_id[payload.tower_class].color[1]))
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
assert(#destroyed == before_destroyed + 3 and live_count() == 3, "cross-route swap must retire every old layer")
local replacement = unit(30)
service.apply(state(replacement, 11, "class_6"))
assert(live_count() == 2)
u.alive = false
bus.emit(events.ENGINE_ENTITY_KILLED, { victim = u })
assert(live_count() == 2, "late death of reused entindex must not clear replacement")
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
assert(live_count() == 3)
bus.emit(events.TOWER_FUSION_RUNTIME_REMOVED, { entindex = 40 })
assert(live_count() == 0)

-- A failed setup rolls back partial ownership; cleanup continues if one
-- renderer destroy throws, including releasing that same index.
invalid_create_at = created + 2
assert(not service.apply(state(replacement, 21, "class_6")))
assert(live_count() == 0 and service.debug_snapshot().towers == 0)
invalid_create_at = nil
fail_control_at = created + 2
assert(not service.apply(state(replacement, 21, "class_6")))
assert(live_count() == 0)
fail_control_at = nil
service.apply(state(replacement, 21, "class_6"))
fail_destroy_id = next_id - 3
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
assert(live_count() == 5 and service.debug_snapshot().towers == 2)
before_destroyed = #destroyed
service.init()
assert(#destroyed == before_destroyed + 5 and live_count() == 5,
    "same-world init must destroy the old five layers before rebuilding")
assert(scheduler.task_count() == 1)
local before_created = created
bus.emit(events.BUILDING_CHANGED, state(replacement, 21, "class_6"))
assert(created == before_created + 3, "old generation subscriptions must stay inactive")
assert(live_count() == 6)

before_destroyed = #destroyed
world, next_id, listed = {}, 0, {}
service.init()
assert(#destroyed == before_destroyed and live_count() == 0,
    "new world init must forget the old world's particle IDs")
service.apply(ultimate_state)
assert(live_count() == 3)
phase = DOTA_GAMERULES_STATE_POST_GAME
assert(service._sweep_for_test() == false and live_count() == 0)
assert(service.debug_snapshot().towers == 0)
print("TOWER_VISUAL_LIFECYCLE_SIMULATION_PASS: CSV, 7 routes, N projectile, tiers, move, replacement, teardown, failures, restart")
