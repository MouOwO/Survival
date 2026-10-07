package.path = "scripts/vscripts/?.lua;" .. package.path
local builder = require("ui/ability_runtime_builder")
local bus, events = require("core/event_bus"), require("core/events")
local available = 1
bus.handle_request(events.LUMBERJACK_FUSION_STATUS_REQUEST,function()
 return {available=available,fusion_count=3,fusion_city_ready=available,fusion_city_level=5,fusion_required_city_level=5}
end)
local definitions = require("config/generated/lumberjack_fusion_definitions")
for _, row in ipairs(definitions.rows) do
    local runtime = builder.build(row.ability_id, nil, nil)
    assert(runtime.fusion_required_count == row.required_count)
    assert(runtime.fusion_level == row.level and runtime.available == 1)
end
assert(builder.build("ability_fuse_lumberjack_01",nil,nil).fusion_required_count == 5)
print("PASS fusion runtime: all eight authoritative recipe quantities and levels")

available=0
assert(builder.build("ability_fuse_lumberjack_03",{player_id=0},nil).available==0)
available=1
assert(builder.build("ability_fuse_lumberjack_03",{player_id=0},{gold=0,wood=0,max_population=10}).can_afford==0)
print("FUSION_RUNTIME_GATES_PASS: count/city authority and resource display")
