package.path = "scripts/vscripts/?.lua;scripts/vscripts/?/init.lua;" .. package.path

local START = "particles/items2_fx/teleport_start_l_flash.vpcf"
local LOOP = "particles/items2_fx/teleport_start.vpcf"
local LEGACY = "particles/test/legacy_build.vpcf"

package.loaded["config/generated/building_construction_rules"] = {
    rows = {
        {
            enabled = true,
            build_start_particle = START,
            build_loop_particle = LOOP,
        },
        {
            enabled = true,
            build_start_particle = START,
            build_particle = LEGACY,
        },
        {
            enabled = false,
            build_loop_particle = "particles/test/disabled.vpcf",
        },
    },
}

PATTACH_WORLDORIGIN = 0
Vector = function(x, y, z) return { x = x, y = y, z = z } end

local created = {}
local controls = {}
local destroyed = {}
local released = {}
local lifecycle = {}
local next_particle = 100
ParticleManager = {
    CreateParticle = function(_, path, attach, owner)
        lifecycle[#lifecycle + 1] = "particle:" .. path
        next_particle = next_particle + 1
        created[#created + 1] = {
            id = next_particle,
            path = path,
            attach = attach,
            owner = owner,
        }
        return next_particle
    end,
    SetParticleControl = function(_, particle, cp, value)
        controls[#controls + 1] = {
            particle = particle,
            cp = cp,
            value = value,
        }
    end,
    DestroyParticle = function(_, particle, immediate)
        destroyed[#destroyed + 1] = {
            particle = particle,
            immediate = immediate,
        }
    end,
    ReleaseParticleIndex = function(_, particle)
        released[#released + 1] = particle
    end,
}

local function unit(entindex, x)
    local result = { origin = Vector(x, 20, 30), no_draw = false }
    function result:IsNull() return false end
    function result:entindex() return entindex end
    function result:GetAbsOrigin() return self.origin end
    function result:AddNoDraw()
        self.no_draw = true
        self.add_no_draw_count = (self.add_no_draw_count or 0) + 1
        lifecycle[#lifecycle + 1] = "hide:" .. tostring(entindex)
    end
    function result:RemoveNoDraw()
        self.no_draw = false
        self.remove_no_draw_count = (self.remove_no_draw_count or 0) + 1
        lifecycle[#lifecycle + 1] = "show:" .. tostring(entindex)
    end
    function result:SetRenderAlpha(alpha)
        self.render_alpha = alpha
    end
    return result
end

local function count_created(path)
    local count = 0
    for _, row in ipairs(created) do
        if row.path == path then count = count + 1 end
    end
    return count
end

package.loaded["systems/building_construction_visual_service"] = nil
local visual = require("systems/building_construction_visual_service")

local first = unit(701, 10)
local first_state = assert(visual.start(first, {
    build_start_particle = START,
    build_loop_particle = LOOP,
    build_visual_scale = 1,
}))
assert(count_created(START) == 1 and count_created(LOOP) == 1,
    "single construction did not create its start and loop stages")
assert(#controls == 3 and controls[1].cp == 0 and controls[2].cp == 0
        and controls[3].cp == 7 and controls[3].value.x == 3,
    "construction particles lost their anchors or channel duration CP")
assert(visual._active_count_for_test() == 1,
    "single construction visual was not registered")
assert(first.no_draw and first.add_no_draw_count == 1,
    "construction did not hide the building model")
assert(lifecycle[1] == "hide:701" and lifecycle[2] == "particle:" .. START,
    "building model was not hidden before construction particles were created")

local second = unit(702, 200)
local second_state = assert(visual.start(second, {
    build_start_particle = START,
    build_particle = LEGACY,
}))
assert(count_created(LEGACY) == 1,
    "legacy build_particle did not act as the loop fallback")
assert(visual._active_count_for_test() == 2,
    "parallel construction visuals overwrote each other")

assert(visual.complete(first_state, first, nil),
    "normal completion did not retire the first visual")
assert(#destroyed == 1 and destroyed[1].immediate == false,
    "normal completion did not preserve the falling-ring End Cap")
assert(#created == 4,
    "normal completion unexpectedly created a full teleport-end burst")
assert(not first.no_draw and first.remove_no_draw_count == 1,
    "normal completion did not reveal the building model")
assert(first.render_alpha == 255,
    "normal completion did not clear legacy construction opacity")
assert(not visual.complete(first_state, first, nil),
    "normal completion was not idempotent")
assert(visual._active_count_for_test() == 1,
    "normal completion removed the wrong parallel state")

assert(visual.cancel(second), "entity cancellation did not retire its visual")
assert(#destroyed == 2 and destroyed[2].immediate == true,
    "cancellation did not remove the loop particle immediately")
assert(second.no_draw and second.remove_no_draw_count == nil,
    "cancellation revealed a dead or discarded construction model")
assert(not visual.cancel(second_state), "cancellation was not idempotent")
assert(visual._active_count_for_test() == 0,
    "cancellation left an active visual state")

local wall = unit(703, 500)
local wall_created_before = #created
assert(visual.start(wall, {
    build_start_particle = START,
    build_loop_particle = LOOP,
    build_visual_scale = 2,
}))
assert(#created - wall_created_before == 8,
    "large-building coverage did not create four start and four loop anchors")
local wall_start_count = count_created(START)
local wall_loop_count = count_created(LOOP)
assert(wall_start_count == 6 and wall_loop_count == 5,
    "large-building construction used the wrong particle distribution")
visual.reset()
assert(visual._active_count_for_test() == 0,
    "reset left active construction visuals")
assert(#destroyed == 6,
    "reset did not immediately destroy every large-building loop particle")
assert(not wall.no_draw and wall.remove_no_draw_count == 1,
    "reset left a surviving construction model hidden")

local missing_draw_api = unit(705, 0)
missing_draw_api.AddNoDraw = nil
missing_draw_api.RemoveNoDraw = nil
missing_draw_api.SetRenderAlpha = nil
local missing_draw_state = assert(visual.start(missing_draw_api, {
    build_loop_particle = LOOP,
}))
assert(visual.complete(missing_draw_state),
    "missing NoDraw APIs prevented construction cleanup")

local precached = {}
PrecacheResource = function(resource_type, path, context)
    precached[#precached + 1] = {
        resource_type = resource_type,
        path = path,
        context = context,
    }
end
local context = {}
assert(visual.precache(context) == 3,
    "construction particle precache did not deduplicate enabled resources")
local seen = {}
for _, row in ipairs(precached) do
    assert(row.resource_type == "particle" and row.context == context,
        "construction precache used the wrong resource contract")
    assert(not seen[row.path], "construction precache emitted a duplicate path")
    seen[row.path] = true
end
assert(seen[START] and seen[LOOP] and seen[LEGACY],
    "construction precache omitted an active phase or legacy fallback")
assert(not seen["particles/test/disabled.vpcf"],
    "construction precache included a disabled row")

local invalid = unit(704, 0)
function invalid:IsNull() return true end
assert(visual.start(invalid, {}) == nil,
    "invalid building unexpectedly created a construction visual")

local building_source = assert(io.open(
    "scripts/vscripts/systems/building_system.lua",
    "rb"
)):read("*a")
assert(building_source:find(
    'require(\n    "systems/building_construction_visual_service"\n)',
    1,
    true
) and building_source:find("construction_visual.start(", 1, true)
    and building_source:find("construction_visual.complete(", 1, true)
    and building_source:find(
        "construction_visual.cancel(construction_visual_state)",
        1,
        true
    )
    and building_source:find("construction_visual.cancel(victim)", 1, true)
    and building_source:find("construction_visual.reset()", 1, true)
    and not building_source:find("construction_visual.set_progress", 1, true),
    "building lifecycle is not fully wired to construction visuals")

local game_mode_source = assert(io.open(
    "scripts/vscripts/addon_game_mode.lua",
    "rb"
)):read("*a")
assert(game_mode_source:find(
    "building_construction_visual.precache(context)",
    1,
    true
), "game-mode precache does not collect construction visual resources")

local generated = assert(loadfile(
    "scripts/vscripts/config/generated/building_construction_rules.lua"
))()
local wall_rule = assert(generated.by_id.wall)
assert(wall_rule.build_start_particle == START
        and wall_rule.build_loop_particle == LOOP,
    "generated construction config lost an active visual phase")
assert(wall_rule.build_complete_particle == nil,
    "generated construction config retained the full teleport-end burst")
assert(wall_rule.build_visual_scale == 2,
    "generated construction config lost large-building visual coverage")

print("BUILDING_CONSTRUCTION_VISUAL_SERVICE_PASS")