local M = {}
function M.Apply()
    if not IsInToolsMode() or GetMapName() ~= "valley_decor_review" then return end
    return require("systems/valley_environment_service").apply()
end
return M
