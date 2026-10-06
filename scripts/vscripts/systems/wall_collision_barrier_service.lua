-- Compatibility cleanup for retired wall collision units. Small navigation obstacles block the gate independently of melee distance.
local M = {}
local function valid(unit)
    return unit and (not unit.IsNull or not unit:IsNull())
end
local function remove_matching(wall_index)
    if not Entities or not Entities.FindAllByClassname then return end
    for _, class_name in ipairs({"npc_dota_creature", "npc_dota_building"}) do
        for _, unit in ipairs(Entities:FindAllByClassname(class_name) or {}) do
            if valid(unit) and (unit.survival_wall_collision_barrier == true
                or (unit.GetUnitName and unit:GetUnitName() == "npc_survival_wall_collision_barrier"))
                and (not wall_index or unit.survival_wall_entindex == wall_index) then
                UTIL_Remove(unit)
            end
        end
    end
end
function M.clear(wall)
    local index = type(wall) == "number" and wall
        or (wall and wall.survival_wall_navigation_index)
        or (valid(wall) and wall:entindex())
    if index then
        require("systems/wall_navigation_service").clear(wall)
        remove_matching(index)
    end
end
function M.clear_all()
    require("systems/wall_navigation_service").clear_all()
    remove_matching(nil)
end
function M.create(wall)
    if not valid(wall) then return {}, "wall_invalid" end
    -- Retained for recovery/upgrade callers; no new invisible units.
    return require("systems/wall_navigation_service").create(wall)
end
function M.count() return 0 end
return M
