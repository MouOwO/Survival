local M = {}

-- Flying is a combat/visual classification, not permission to cross cliffs.
-- Apply before FindClearSpaceForUnit; spawn callers must disable the implicit
-- CreateUnitByName placement so even a flying base unit uses ground navigation.
function M.apply(unit)
    unit:SetMoveCapability(DOTA_UNIT_CAP_MOVE_GROUND)
    unit.survival_navigation_type = "ground"
end

return M
