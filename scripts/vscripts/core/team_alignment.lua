local M = {}

function M.enforce(unit, team, label)
    if not unit or unit:IsNull() then return false end
    if unit.SetTeam then unit:SetTeam(team) end
    if unit.SetTeamNumber then unit:SetTeamNumber(team) end
    local ok = unit:GetTeamNumber() == team
    if not ok then
        print("[TeamAlignment] correction failed", label or "unit",
            unit:entindex(), unit:GetTeamNumber(), team)
    end
    return ok
end

function M.are_enemies(a, b)
    return a and b and not a:IsNull() and not b:IsNull()
        and a:GetTeamNumber() ~= b:GetTeamNumber()
end

return M
