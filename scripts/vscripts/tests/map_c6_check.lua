-- Manual map-only verification: script_reload_code tests/map_c6_check
if not IsInToolsMode() or GetMapName() ~= "survival_c6" then
    print("[C6_CHECK] skipped: requires survival_c6 in Tools")
    return
end
local failed, checked = 0, 0
local function check(name)
    checked = checked + 1
    local entity = Entities:FindByName(nil, name)
    if not entity then failed = failed + 1; print("[C6_CHECK] MISSING " .. name); return end
    local p = entity:GetAbsOrigin()
    local ground = GetGroundHeight(p, nil)
    local ok = math.abs(p.z - ground) < 64 and GridNav:IsTraversable(p) and not GridNav:IsBlocked(p)
    if not ok then failed = failed + 1 end
    print(string.format("[C6_CHECK] %s %s x=%.0f y=%.0f z=%.0f ground=%.0f", ok and "PASS" or "FAIL", name, p.x, p.y, p.z, ground))
end
for i = 0, 3 do check("player_" .. i .. "_builder_spawn"); check("monsterborn_player" .. (i + 1)) end
local pool = Vector(-1024, 5376, 0)
pool.z = GetGroundHeight(pool, nil)
print(string.format("[C6_CHECK] pool ground=%.0f traversable=%s blocked=%s", pool.z, tostring(GridNav:IsTraversable(pool)), tostring(GridNav:IsBlocked(pool))))
for i = 0, 3 do
    local entrance = Entities:FindByName(nil, "c6_player_" .. i .. "_entrance")
    local ok = entrance and GridNav:CanFindPath(entrance:GetAbsOrigin(), pool)
    checked = checked + 1
    if not ok then failed = failed + 1 end
    print("[C6_CHECK] " .. (ok and "PASS" or "FAIL") .. " water_to_land_player_" .. i)
end
for _, group in ipairs({ {"west",10},{"west_inner",3},{"northwest",4},{"northeast",4},{"southwest",4},{"southeast",4},{"east",4},{"small",10} }) do
    for i = 1, group[2] do check("c6_" .. group[1] .. "_" .. i .. "_entry"); check("c6_" .. group[1] .. "_" .. i .. "_spawn") end
end
for _, name in ipairs({"star_west", "star_east", "far_east", "southern"}) do
    check("c6_" .. name .. "_entry"); check("c6_" .. name .. "_spawn")
end
local cfg = require("config/grid_placement_config")
local tree = require("config/tree_config")
print("[C6_CHECK] bounds=" .. tostring(cfg.build_bounds.min_x) .. "," .. tostring(cfg.build_bounds.max_x))
print("[C6_CHECK] resource_tree=" .. tostring(tree.spawn_point.x) .. "," .. tostring(tree.spawn_point.y))
print(string.format("[C6_CHECK] RESULT checked=%d failed=%d", checked, failed))
