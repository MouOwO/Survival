-- Workshop console: script_reload_code tests/manual_monster_navigation_check
-- Read-only: no entities, orders, timers, service resets or navigation mutations.
-- Run on a fresh template_map for unobstructed terrain checks; run again during
-- a wave to inspect actual move capabilities. Existing buildings can block paths.
if not IsServer() or not IsInToolsMode() or GetMapName() ~= "template_map"
    or not GridNav or not Entities or not GetGroundHeight then
    print("[MONSTER_NAV] UNVERIFIED requires Workshop template_map server")
    return
end

local layout = require("config/map_layouts/template_map")
local center = layout.center
local report = { checked = 0, failed = 0, unverified = 0, monsters = 0, logical_flying = 0 }
local function check(name, ok, detail)
    report.checked = report.checked + 1
    if not ok then report.failed = report.failed + 1 end
    print("[MONSTER_NAV] " .. (ok and "PASS " or "FAIL ") .. name .. " " .. (detail or ""))
end
local function unverified(name, detail)
    report.unverified = report.unverified + 1
    print("[MONSTER_NAV] UNVERIFIED " .. name .. " " .. (detail or ""))
end
local function rotate(x, y, side)
    for _ = 1, side do x, y = y, -x end
    return x, y
end
local function point(x, y, side)
    x, y = rotate(x, y, side)
    local position = Vector(center.x + x, center.y + y, 0)
    position.z = GetGroundHeight(position, nil)
    return position
end
local function clear(position)
    return GridNav:IsTraversable(position) and not GridNav:IsBlocked(position)
end
local function marker(name, expected)
    local entity = Entities:FindByName(nil, name)
    if not entity then check(name, false, "missing"); return nil end
    local position = entity:GetAbsOrigin()
    local dx, dy = position.x - expected.x, position.y - expected.y
    check(name, dx * dx + dy * dy <= 4 and clear(position),
        string.format("world=(%.0f,%.0f,%.0f)", position.x, position.y, position.z))
    return position
end
local function segment(name, a, b, side)
    local dx, dy = b[1] - a[1], b[2] - a[2]
    local steps = math.max(1, math.ceil(math.sqrt(dx * dx + dy * dy) / 64))
    local failed_at
    for index = 0, steps do
        local position = point(a[1] + dx * index / steps, a[2] + dy * index / steps, side)
        if not clear(position) and not failed_at then
            failed_at = string.format("blocked world=(%.0f,%.0f)", position.x, position.y)
        end
    end
    check(name, failed_at == nil, failed_at or ("samples=" .. (steps + 1)))
end

print(string.format("[MONSTER_NAV] center=(%.0f,%.0f) live GridNav; no units moved", center.x, center.y))
for side = 0, 3 do
    local label = "side_" .. side
    local spawn = marker("monsterborn_player" .. (side + 1), point(600, 0, side))
    local entrance = marker("c6_player_" .. side .. "_entrance", point(2100, 0, side))
    segment(label .. ".low_road", {600, 0}, {2100, 0}, side)
    local route = {{2100, 0}, {2432, 0}, {2432, 800}, {2000, 1000}, {1420, 1116}}
    for index = 1, #route - 1 do
        segment(label .. ".outside_stair_route_" .. index, route[index], route[index + 1], side)
    end
    check(label .. ".spawn_to_court_path", spawn ~= nil
        and GridNav:CanFindPath(spawn, point(1420, 1116, side)))
    check(label .. ".entrance_to_stair_path", entrance ~= nil
        and GridNav:CanFindPath(entrance, point(2432, 384, side)))

    -- Test every cell of the two-cell retaining strip. CanFindPath(low, high)
    -- must NOT be used as a shortcut test: the intended stair detour is valid.
    local blocked, first_open = 0, nil
    for x = 736, 2080, 64 do
        for _, y in ipairs({288, 352}) do
            local position = point(x, y, side)
            if not clear(position) then
                blocked = blocked + 1
            elseif not first_open then
                first_open = string.format("open world=(%.0f,%.0f)", position.x, position.y)
            end
        end
    end
    check(label .. ".no_cliff_shortcut", blocked == 44,
        string.format("blocked=%d/44 %s", blocked, first_open or ""))
end

local seen = {}
for _, class_name in ipairs({"npc_dota_creature", "npc_dota_creep", "npc_dota_hero"}) do
    for _, unit in ipairs(Entities:FindAllByClassname(class_name) or {}) do
        if not seen[unit] then
            seen[unit] = true
            if not unit:IsNull() and unit.survival_is_wave_monster == true and unit:IsAlive() then
                report.monsters = report.monsters + 1
                local logical_type = unit.survival_wave_movement_type
                    or unit.survival_movement_type_override or unit.survival_movement_type or "ground"
                if logical_type == "flying" then report.logical_flying = report.logical_flying + 1 end
                local name = "monster_" .. unit:entindex()
                if type(unit.GetMoveCapability) ~= "function" or DOTA_UNIT_CAP_MOVE_GROUND == nil then
                    unverified(name, "engine capability API unavailable")
                else
                    local capability = unit:GetMoveCapability()
                    check(name, capability == DOTA_UNIT_CAP_MOVE_GROUND,
                        "logical=" .. tostring(logical_type) .. " engine=" .. tostring(capability))
                end
            end
        end
    end
end
if report.monsters == 0 then unverified("monster_capabilities", "no living wave monsters") end
if report.logical_flying == 0 then unverified("flying_type_capabilities", "no living flying-type wave monsters") end
unverified("observed_movement", "read-only checks do not replace watching monsters traverse the stairs")
print(string.format("[MONSTER_NAV] RESULT checked=%d failed=%d unverified=%d monsters=%d logical_flying=%d",
    report.checked, report.failed, report.unverified, report.monsters, report.logical_flying))
return report
