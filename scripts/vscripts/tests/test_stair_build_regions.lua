package.path = "scripts/vscripts/?.lua;scripts/vscripts/?/init.lua;" .. package.path

local current_map = "template_map"
GetMapName = function() return current_map end

local regions = require("systems/forbidden_region_service")
regions.init()

local movable, forbidden = regions.counts()
assert(movable == 0 and forbidden == 4)

for _, stair in ipairs({
    { "east", 1280, 4544 },
    { "south", -576, 1792 },
    { "west", -3328, 3648 },
    { "north", -1472, 6400 },
}) do
    local x, y = stair[2], stair[3]
    local ok, reason = regions.validate_building_footprint(
        x - 128, y - 128, x + 128, y + 128
    )
    assert(not ok and reason == "building_forbidden_region:main_stair_" .. stair[1])
end

local lawn_ok = regions.validate_building_footprint(268, 5084, 524, 5340)
assert(lawn_ok)

-- This is the south stair's upper landing, where the wall preview was legal.
local landing_ok = regions.validate_building_footprint(-198, 1564, 58, 1820)
assert(not landing_ok)

current_map = "survival_dev"
regions.init()
local _, dev_forbidden = regions.counts()
assert(dev_forbidden == 0)
assert(regions.validate_building_footprint(1152, 4416, 1408, 4672))

print("stair build regions: PASS")
