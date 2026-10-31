-- Fixed simulation time must not disable the incremental terrain work budget.
package.path = "scripts/vscripts/?.lua;" .. package.path
DOTA_TEAM_GOODGUYS=2
DOTA_UNIT_TARGET_TEAM_BOTH=3
DOTA_UNIT_TARGET_HERO=1
DOTA_UNIT_TARGET_BASIC=2
DOTA_UNIT_TARGET_BUILDING=4
DOTA_UNIT_TARGET_FLAG_INVULNERABLE=0
FIND_ANY_ORDER=0
local vector_meta={__add=function(a,b) return Vector(a.x+b.x,a.y+b.y,a.z+b.z) end}
Vector=function(x,y,z) return setmetatable({x=x,y=y,z=z or 0},vector_meta) end
local elapsed_ms,terrain_samples=0,0
local function native_cost() elapsed_ms=elapsed_ms+0.1 end
GetSystemTimeMS=function() return elapsed_ms end
Time=function() return 10 end
GameRules={GetGameTime=function() return 10 end}
GetGroundHeight=function() native_cost();return 384 end
GetGroundPosition=function(p) return Vector(p.x,p.y,GetGroundHeight(p)) end
FindUnitsInRadius=function() return {} end
GridNav={
    IsTraversable=function() native_cost();terrain_samples=terrain_samples+1;return true end,
    IsBlocked=function() native_cost();return false end,
    IsNearbyTree=function() native_cost();return false end,
}
package.loaded["systems/forbidden_region_service"]={validate_building_footprint=function() return true end}
local config=require("config/grid_placement_config")
config.build_bounds={min_x=-512,max_x=512,min_y=-512,max_y=512}
config.build_ground_height=384
config.preview_visual.radius=512

local function fresh()
    package.loaded["systems/grid_placement_system"]=nil
    return require("systems/grid_placement_system")
end

for _,method in ipairs({"preview_area","static_preview"}) do
    local grid=fresh()
    local full_payload={position=Vector(0,0,384),team=2}
    local expected=grid[method](full_payload)
    grid=fresh();elapsed_ms,terrain_samples=0,0
    local payload={position=Vector(0,0,384),team=2,yield_after=128,time_budget=.002}
    local job=coroutine.create(function() return grid[method](payload) end)
    local ok,partial=coroutine.resume(job)
    assert(ok,partial)
    assert(coroutine.status(job)=="suspended",method.." must yield before finishing")
    local first_samples=terrain_samples
    -- Each clear terrain cell samples five points. The minimum batch is eight.
    assert(first_samples>=8*5 and first_samples<128*5,method.." ignored elapsed-time budget")
    local batches,final=1,partial
    while coroutine.status(job)~="dead" do
        ok,final=coroutine.resume(job);assert(ok,final);batches=batches+1
        assert(batches<1000,"job must finish")
    end
    assert(final==expected,method.." batching changed placement output")
    assert(Time()==10,"simulation clock stays fixed for the entire test")
    print("GRID_ELAPSED_BUDGET_PASS method="..method.." first_cells="..(first_samples/5).." batches="..batches)
end

local clocks=require("core/performance_clock")
GetSystemTimeMS=nil
assert(clocks.new()==os.clock,"standalone fallback uses CPU elapsed time")
GetSystemTimeMS=function() return 0/0 end
assert(clocks.new()==os.clock,"invalid engine clock is rejected")
GetSystemTimeMS=function() error("missing native clock") end
assert(clocks.new()==os.clock,"unavailable engine clock is rejected")
elapsed_ms=1234
GetSystemTimeMS=function() return elapsed_ms end
assert(clocks.new()()==1.234,"native milliseconds are converted to seconds")
print("PERFORMANCE_CLOCK_PASS engine / fallback / invalid / missing; no simulation clock")
