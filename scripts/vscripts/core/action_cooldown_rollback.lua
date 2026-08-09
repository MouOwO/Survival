local M = {}

function M.once(action)
    if not action or action.cooldown_rolled_back then return false end
    action.cooldown_rolled_back = true
    local ability = action.source_ability
    if ability and not ability:IsNull() then ability:EndCooldown() end
    return true
end

return M