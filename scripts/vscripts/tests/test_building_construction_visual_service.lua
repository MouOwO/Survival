package.path = "scripts/vscripts/?.lua;scripts/vscripts/?/init.lua;" .. package.path

local START = "particles/survival_buildings/warp_start.vpcf"
local LOOP = "particles/survival_buildings/white_build_channel.vpcf"
local COMPLETE = "particles/survival_buildings/white_build_reveal.vpcf"
local LEGACY = "particles/test/legacy_build.vpcf"

package.loaded["config/generated/building_construction_rules"] = {
    rows = {
        {
            enabled = true,
            build_start_particle = START,
            build_loop_particle = LOOP,
            build_complete_particle = COMPLETE,
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
PATTACH_ABSORIGIN_FOLLOW = 1
Vector = function(x, y, z) return { x = x, y = y, z = z } end

local created = {}
local controls = {}
local destroyed = {}
local released = {}
local lifecycle = {}
local model_bindings = {}
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
    SetParticleControlEnt = function(_, particle, cp, owner, attach, _, origin)
        assert(cp==3 and attach==PATTACH_ABSORIGIN_FOLLOW and origin==owner.origin)
        model_bindings[particle]=owner
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
    function result:GetModelScale() return 2.5 end
    function result:GetAnglesAsVector() return Vector(0,-90,0) end
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

local definition = { build_start_particle=START, build_loop_particle=LOOP,
    build_complete_particle=COMPLETE, build_time=3, footprint={x=2,y=2},
    levels={[1]={model_scale=1,model_yaw=0}} }
local first = unit(701,10)
local first_state = assert(visual.start(first,definition))
assert(#created==2 and #controls==6, "expected one centered start and one channel")
assert(controls[1].cp==0 and controls[1].value==first.origin)
assert(controls[2].cp==1 and controls[2].value.x==64 and controls[2].value.z==3,
    "warp radius/duration did not match the real footprint")
assert(controls[4].value==first.origin, "channel is offset from building center")
assert(controls[3].cp==2 and controls[3].value.x==1
    and controls[3].value.y==0,
    "projection must use configured south-facing degrees before entity visual apply")
assert(model_bindings[created[2].id]==first,"projection did not bind the actual building")
assert(lifecycle[1]=="hide:701" and first.no_draw)
local second=unit(702,200)
local second_state=assert(visual.start(second,{build_start_particle=START,build_particle=LEGACY}))
assert(count_created(LEGACY)==1 and visual._active_count_for_test()==2)
assert(visual.complete(first_state))
assert(#destroyed==2 and destroyed[1].immediate and destroyed[2].immediate,
    "start/channel handles were not safely retired")
assert(count_created(COMPLETE)==1 and created[#created].owner==first)
assert(not first.no_draw and first.render_alpha==255 and first.remove_no_draw_count==1)
assert(not visual.complete(first_state) and count_created(COMPLETE)==1,
    "duplicate completion replayed the finish burst")
assert(visual.cancel(second) and second.no_draw)
assert(#destroyed==4 and count_created(COMPLETE)==1, "cancellation played a completion burst")
assert(not visual.cancel(second_state) and visual._active_count_for_test()==0)

local wall=unit(703,500)
local before=#created
local wall_definition={build_start_particle=START,build_loop_particle=LOOP,footprint={x=4,y=4}}
assert(visual.start(wall,wall_definition))
assert(#created-before==2 and controls[#controls-1].value.x==128,
    "large buildings must use a single scaled center")
visual.reset()
assert(#destroyed==6 and visual._active_count_for_test()==0 and not wall.no_draw)

local missing=unit(705,0)
missing.AddNoDraw=nil; missing.RemoveNoDraw=nil; missing.SetRenderAlpha=nil
assert(visual.complete(assert(visual.start(missing,{build_loop_particle=LOOP}))))
-- Every created handle must be released once, including the finite finish burst.
local releases={}
for _,id in ipairs(released) do releases[id]=(releases[id] or 0)+1 end
for _,row in ipairs(created) do assert(releases[row.id]==1,"particle leaked or released twice") end
-- CP initialization failures must retire handles and must not prevent reveal.
local original_control=ParticleManager.SetParticleControl
ParticleManager.SetParticleControl=function() error("simulated CP failure") end
local failed=unit(706,0)
local failed_state=assert(visual.start(failed,definition))
ParticleManager.SetParticleControl=original_control
assert(#failed_state.loop_particles==0 and failed_state.start_particle==nil)
assert(visual.complete(failed_state) and not failed.no_draw)

-- A late model-binding failure must clean up both handles after CP0/1/2.
local original_binding=ParticleManager.SetParticleControlEnt
ParticleManager.SetParticleControlEnt=function() error("simulated model binding failure") end
local binding_failed=unit(707,0)
local created_before,destroyed_before,released_before=#created,#destroyed,#released
local binding_state=assert(visual.start(binding_failed,definition))
ParticleManager.SetParticleControlEnt=original_binding
assert(#created-created_before==2 and #destroyed-destroyed_before==2
    and #released-released_before==2 and #binding_state.loop_particles==0
    and binding_state.start_particle==nil,"failed projection leaked a particle")
assert(visual.complete(binding_state) and not binding_failed.no_draw)
releases={}
for _,id in ipairs(released) do releases[id]=(releases[id] or 0)+1 end
for _,row in ipairs(created) do assert(releases[row.id]==1,"failed projection released twice") end

local precached = {}
PrecacheResource = function(resource_type, path, context)
    precached[#precached + 1] = {
        resource_type = resource_type,
        path = path,
        context = context,
    }
end
local context = {}
assert(visual.precache(context) == 38,
    "construction particle precache did not deduplicate enabled resources")
local seen = {}
for _, row in ipairs(precached) do
    assert((row.resource_type == "particle" or row.resource_type == "model") and row.context == context,
        "construction precache used the wrong resource contract")
    assert(not seen[row.path], "construction precache emitted a duplicate path")
    seen[row.path] = true
end
assert(seen[START] and seen[LOOP] and seen[LEGACY] and seen[COMPLETE],
    "construction precache omitted an active phase or legacy fallback")
assert(not seen["particles/test/disabled.vpcf"],
    "construction precache included a disabled row")
for stage=1,10 do
    assert(seen[string.format("models/survival_buildings/wall_lv%02d_white_shell.vmdl",stage)],
        "construction precache omitted a reference wall shell")
end

local invalid = unit(704, 0)
function invalid:IsNull() return true end
assert(visual.start(invalid, {}) == nil,
    "invalid building unexpectedly created a construction visual")

local building_source = assert(io.open(
    "scripts/vscripts/systems/building_system.lua",
    "rb"
)):read("*a"):gsub("\r\n", "\n")
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
)):read("*a"):gsub("\r\n", "\n")
assert(game_mode_source:find(
    "building_construction_visual.precache(context)",
    1,
    true
), "game-mode precache does not collect construction visual resources")

local generated = assert(loadfile(
    "scripts/vscripts/config/generated/building_construction_rules.lua"
))()
local wall_rule = assert(generated.by_id.wall)
assert((wall_rule.build_start_particle or "") == ""
        and wall_rule.build_loop_particle == LOOP,
    "generated construction config lost an active visual phase")
assert(wall_rule.build_complete_particle == COMPLETE,
    "generated construction config lost its completion burst")
assert(wall_rule.build_visual_scale == 1,
    "reference wall geometry already fits 4x4 cells; do not scale it a second time")

-- The production white effect holds one model, with no separate flash phase.
local white_unit=unit(708,0)
before=#created
local white_state=assert(visual.start(white_unit,wall_rule))
assert(#created-before==1 and created[#created].path==LOOP,
    "white construction spawned a second overlapping effect")
assert(white_unit.no_draw)
assert(visual.complete(white_state) and not white_unit.no_draw)
assert(#created-before==2 and created[#created].path==COMPLETE,
    "white construction did not transition into its finite fade")
assert(not visual.complete(white_state) and #created-before==2)
local apply_position=assert(building_source:find("building_visual.apply(unit, completed_level)",1,true))
local reveal_position=assert(building_source:find("construction_visual.complete(",1,true))
assert(apply_position<reveal_position,"white reveal started before the final model was applied")

print("BUILDING_CONSTRUCTION_VISUAL_SERVICE_PASS")
