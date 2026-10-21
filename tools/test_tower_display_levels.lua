package.path = "scripts/vscripts/?.lua;" .. package.path
local builder = require("ui/ability_runtime_builder")
local routes = require("config/tower_route_config")
local resources = {gold=1e12,wood=1e12,population=0,max_population=100}
local checked = 0
for class_index=1,7 do
    local class_id="class_"..class_index
    local rows=routes.get_route(class_id)
    for index,row in ipairs(rows) do
        local state={level=index+5,tower_class=class_id,building_id="arrow_tower",player_id=0}
        for _,ability in ipairs({"ability_upgrade_tower_lv01","ability_upgrade_tower_max"}) do
            local result=builder.build(ability,state,resources)
            assert(result.current_level==state.level, "internal level must stay cumulative")
            assert(result.display_current_level==row.level, "current display must match named stage")
            if result.available==1 then
                local target=routes.row_at_level(state,result.target_level)
                assert(target and result.display_target_level==target.level)
                assert(result.tower_name==routes.display_name(target))
                local suffix=(ability=="ability_upgrade_tower_max" or target.level==target.max_level)
                    and "max" or tostring(target.level)
                assert(result.status_text=="升级至"..routes.display_name(target).." lv"..suffix,
                    "footer must identify target tower and its local stage level")
                for _,field in ipairs(result.fields or {}) do
                    assert(field.label=="自动升级","tower upgrade details must not be displayed")
                end
            end
            checked=checked+1
        end
    end
end
for level=1,5 do
    local result=builder.build("ability_upgrade_tower_lv01",{level=level,building_id="arrow_tower",player_id=0},resources)
    assert(result.display_current_level==level)
end
local base={level=1,building_id="arrow_tower",player_id=0}
assert(builder.build("ability_upgrade_tower_lv01",base,resources).status_text=="升级至【N】见习守望 lv2")
assert(builder.build("ability_upgrade_tower_max",base,resources).status_text=="升级至【N】见习守望 lvmax")
base.level=4
assert(builder.build("ability_upgrade_tower_lv01",base,resources).status_text=="升级至【N】见习守望 lvmax",
    "the last single-level upgrade also targets max")
base.level=5
local completed=builder.build("ability_upgrade_tower_lv01",base,resources)
assert(completed.available==0 and completed.status_text=="请先选择一个转职方向",
    "unavailable upgrade instructions retain their meaning")
print("PASS tower display levels: "..checked.." routed upgrade previews plus base towers")
