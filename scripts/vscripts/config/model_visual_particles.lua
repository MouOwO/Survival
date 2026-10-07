-- Persistent catalog particles form part of model appearances (Io's entire
-- visible body is one). They must remain visible in reduced-combat-effects mode.
local catalog = require("config/asset_catalog")
local protected = {}
for _, asset in ipairs(catalog.rows or {}) do
    if asset.enabled ~= false then
        for _, effect in ipairs(asset.environment_particles or {}) do
            local path = type(effect) == "table" and effect.path or effect
            if type(path) == "string" and path ~= "" then protected[path] = true end
        end
    end
end
local M = {}
function M.contains(path) return protected[path] == true end
return M
