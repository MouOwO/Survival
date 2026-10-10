-- Real relocation/events/visual ownership, with delayed client entity position.
package.path = "scripts/vscripts/?.lua;" .. package.path
local bus, events = require("core/event_bus"), require("core/events")
local scheduler = require("core/scheduler")
package.loaded["systems/tower_skill_runtime"] = {get = function() return {} end}
package.loaded["systems/tower_laser_effect_selector"] = {get = function() end}
PATTACH_ABSORIGIN_FOLLOW, PATTACH_POINT_FOLLOW, PATTACH_WORLDORIGIN = 10, 11, 12
LinkLuaModifier = function() end
LUA_MODIFIER_MOTION_NONE = 0
DOTA_GAMERULES_STATE_POST_GAME = 8
Vector = function(x, y, z) return {x=x, y=y, z=z} end
local deferred, refreshes, blocked = {}, 0, false
local world = {SetContextThink = function(_, key, callback, delay)
    assert(delay == 0.06, "reuse the existing movement network refresh")
    deferred[key] = callback; refreshes = refreshes + 1
end}
GameRules = {GetGameTime = function() return 0 end,
    State_Get = function() return 6 end, GetGameModeEntity = function() return world end}
local particles, next_id, created = {}, 0, 0
local trap_prefix = "particles/units/heroes/hero_templar_assassin/templar_assassin_trap_rings"
ParticleManager = {}
function ParticleManager:CreateParticle(path, attachment, unit)
    next_id = next_id + 1; created = created + 1
    particles[next_id] = {path=path, attachment=attachment, owner=unit,
        controls={}, client_spawn=unit.client_origin}
    return next_id
end
function ParticleManager:SetParticleControlEnt(id, point, unit)
    local p = particles[id]
    p.bindings = p.bindings or {}; p.bindings[point] = unit
end
function ParticleManager:SetParticleControl(id, point, value)
    particles[id].controls[point] = Vector(value.x, value.y, value.z)
end
function ParticleManager:DestroyParticle(id, immediate)
    assert(immediate and not particles[id].destroyed)
    particles[id].destroyed = true
end
function ParticleManager:ReleaseParticleIndex(id)
    assert(particles[id].destroyed and not particles[id].released)
    particles[id].released = true
end
local function live_count()
    local n = 0
    for _, p in pairs(particles) do if not p.released then n=n+1 end end
    return n
end
local function same(a, b) return a.x==b.x and a.y==b.y and a.z==b.z end
local noop = function() end
local state
local relocation = require("systems/building_relocation")
relocation.bind(function(index)
    return state and state.unit:entindex()==index and state or nil
end, function(s) return {unit=s.unit, entindex=s.unit:entindex(), player_id=0,
    building_id=s.building_id, level=s.level, tower_class=s.tower_class} end)
bus.handle_request(events.GRID_CAN_PLACE_REQUEST, function(p)
    return {ok=not blocked, error="occupied", grid_x=1, grid_y=2, world_position=p.position}
end)
bus.handle_request(events.GRID_RELEASE_REQUEST, function() return {ok=true} end)
bus.handle_request(events.GRID_OCCUPY_REQUEST, function() return {ok=true} end)
bus.handle_request(events.BUILDING_LIST_REQUEST, function() return {buildings={}} end)
local visual = require("systems/tower_visual_service")
visual.init()
local initial_tasks = scheduler.task_count()
local function unit(index)
    local u = {index=index, origin=Vector(0,0,128), client_origin=Vector(0,0,128), alive=true}
    function u:entindex() return self.index end
    function u:IsNull() return false end
    function u:IsAlive() return self.alive end
    function u:GetAbsOrigin() return self.origin end
    function u:SetAbsOrigin(position) self.origin=position end -- client stays old
    function u:FindModifierByName() end
    function u:SetRangedProjectileName() end
    function u:Stop() end
    u.RemoveModifierByName, u.AddNewModifier = noop, noop
    return u
end
local cases, moves = 0, 0
local function check(class_id, level)
    cases=cases+1
    local u = unit(cases)
    state={unit=u, building_id="arrow_tower", level=level, tower_class=class_id,
        grid_x=0, grid_y=0, team=2, definition={footprint={x=2,y=2}}}
    assert(visual.apply(state))
    local count=live_count()
    for step=1,3 do
        local old = visual.debug_snapshot(u.index).particle_ids
        local previous_client = u.client_origin
        local position=Vector(step*320, -step*160, 128+step*64)
        local before=created
        assert(relocation.move(u,position)); moves=moves+1
        assert(same(u.client_origin,previous_client) and not same(u.client_origin,position),
            "client must still lag behind the server teleport during particle creation")
        local current=visual.debug_snapshot(u.index).particle_ids
        assert(#current==count and created==before+count and live_count()==count)
        for _, id in ipairs(old) do
            assert(particles[id].destroyed and particles[id].released,
                "no old-position base layer may survive relocation")
        end
        for _, id in ipairs(current) do
            local p=particles[id]
            if p.path:sub(1,#trap_prefix)==trap_prefix then
                assert(p.attachment==PATTACH_WORLDORIGIN and same(assert(p.controls[0]),position),
                    "native ring center must use the server destination despite client position lag")
                assert(not p.bindings or not p.bindings[0], "an entity binding would restore the old client center")
            end
        end
        u.client_origin=Vector(position.x,position.y,position.z)
        local key="building_relocation_refresh_"..u.index
        assert(deferred[key]() == nil); deferred[key]=nil
        for _=1,5 do bus.emit(events.BUILDING_CHANGED,state) end
        assert(created==before+count, "same-position refreshes must not duplicate the bundle")
        blocked=true
        assert(not relocation.move(u,Vector(999,999,999)))
        blocked=false
        assert(same(u.origin,position) and created==before+count,
            "rejected moves must preserve both position and particles")
    end
    u.alive=false;bus.emit(events.ENGINE_ENTITY_KILLED,{victim=u})
    assert(live_count()==0 and not visual.debug_snapshot(u.index).tracked)
end
for level=1,5 do check(nil,level) end
for class=1,7 do for level=6,25 do check("class_"..class,level) end end
assert(refreshes==moves and scheduler.task_count()==initial_tasks,
    "relocation adds no periodic visual work or additional movement timer")
print("TOWER_VISUAL_RELOCATION_PASS: "..cases.." forms, "..moves.." real moves, delayed client position, native world centers, no residue/duplicates/timers")
