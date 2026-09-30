-- SIMULATION: projection/event lifecycle, with real route data; no engine rendering.
package.path = "scripts/vscripts/?.lua;" .. package.path
local projection = require("systems/tower_rank_projection")
local routes = require("config/tower_route_config")
for route_number = 1, 7 do
    local route = routes.get_route("class_" .. route_number)
    assert(#route == 20, "review rank mapping when authoritative route length changes")
    for level = 1, 25 do
        local rank = projection.project({ building_id = "arrow_tower", level = level })
        local row = level <= 5 and routes.arrow(level) or route[level - 5]
        local old_rarity, old_level = row.rarity, row.level
        local name = routes.display_name(row)
        assert(name:find("【" .. rank.rarity .. "】", 1, true) == 1,
            "route/upgrade/overhead rarity mismatch at level " .. level)
        assert(row.rarity == old_rarity and row.level == old_level,
            "presentation must not mutate gameplay rows")
        if level >= 21 then
            assert(name:find("（进阶 " .. tostring(level - 20) .. "/5）", 1, true))
            assert(name:find(row.name, 1, true), "retain actual LV6–10 in selected text")
        end
        assert(rank.stars >= 1 and rank.stars <= 5)
        assert(rank.red_stars >= 0 and rank.red_stars <= rank.stars)
        if level <= 5 then assert(rank.rarity == "N" and rank.stars == level)
        elseif level <= 10 then assert(rank.rarity == "R" and rank.stars == level - 5)
        elseif level <= 15 then assert(rank.rarity == "SR" and rank.stars == level - 10)
        elseif level <= 20 then assert(rank.rarity == "SSR" and rank.stars == level - 15)
        else assert(rank.rarity == "SSR" and rank.stars == 5 and rank.red_stars == level - 20) end
    end
end
assert(projection.project({ building_id = "ultimate_tower", level = 1 }).rarity == "UR")
assert(not projection.project({ building_id = "wall", level = 5 }))
assert(not projection.project({ building_id = "arrow_tower", level = 26 }))
assert(routes.display_name_for_unit({ survival_building_id = "arrow_tower",
    survival_tower_class = "class_3", survival_level = 6,
    survival_display_name = "【N】旧缓存" }):find("【R】", 1, true) == 1)
assert(routes.display_name_for_unit({ survival_ultimate_tower = true,
    survival_display_name = "终极之塔" }) == "【UR】终极之塔")
assert(not routes.display_name_for_unit({ survival_building_id = "wall" }))
local bus, events = require("core/event_bus"), require("core/events")
local scheduler = require("core/scheduler")
GameRules = { GetGameTime = function() return 0 end, State_Get = function() return 0 end }
local values, writes = {}, 0
CustomNetTables = { SetTableValue = function(_, name, key, value)
    assert(name == "survival_tower_rank")
    values[key], writes = value, writes + 1
end }
local function unit(index, player)
    local u = { index = index, survival_player_id = player, alive = true }
    function u:entindex() return self.index end
    function u:IsNull() return self.null == true end
    function u:IsAlive() return self.alive end
    function u:GetUnitName() return "tower_" .. self.index end
    function u:GetTeamNumber() return 2 end
    return u
end
local first, second = unit(100, 0), unit(101, 1)
local a = { unit = first, entindex = 100, player_id = 0, building_id = "arrow_tower", level = 1 }
local b = { unit = second, entindex = 101, player_id = 1, building_id = "arrow_tower", level = 10 }
bus.handle_request(events.BUILDING_LIST_REQUEST, function() return { buildings = { a } } end)
local service = require("systems/tower_rank_presentation_service")
service.init()
assert(values.unit_100.rarity == "N" and values.unit_100.player_id == 0)
bus.emit(events.BUILDING_CREATED, b)
assert(values.unit_101.rarity == "R" and values.unit_101.stars == 5)
local before = writes
bus.emit(events.BUILDING_CHANGED, b)
assert(writes == before, "unchanged stats must not retransmit ranks")
a.level = 21
bus.emit(events.BUILDING_CHANGED, a)
assert(values.unit_100.stars == 5 and values.unit_100.red_stars == 1)
service.remove(100, unit(100, 0))
assert(values.unit_100.removed == 0, "late callback must not clear replacement entity")
first.alive = false
bus.emit(events.ENGINE_ENTITY_KILLED, { victim = first })
assert(values.unit_100.removed == 1 and values.unit_101.removed == 0)
second.null = true
service._sweep_for_test()
assert(values.unit_101.removed == 1)
local ultimate = unit(102, 0)
bus.emit(events.TOWER_FUSION_RUNTIME_CHANGED, {
    unit = ultimate, player_id = 0, building_id = "ultimate_tower", level = 1,
})
assert(values.unit_102.rarity == "UR" and values.unit_102.stars == 1)
bus.emit(events.TOWER_FUSION_RUNTIME_REMOVED, { entindex = 102 })
assert(values.unit_102.removed == 1)
local old_session = values._session.id
service.init()
assert(values._session.id ~= old_session, "new session invalidates old replicated ranks")
assert(scheduler.task_count() == 1, "hot init must replace lifecycle task")
first.alive = true
before = writes
bus.emit(events.BUILDING_CREATED, a)
assert(writes == before + 1, "inactive old subscriptions must not publish twice")
print("TOWER_RANK_PRESENTATION_SIMULATION_PASS: 7 routes, 25 levels, ownership, lifecycle, restart")
