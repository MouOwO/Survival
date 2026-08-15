local M = class({})

_G.ability_open_research = M

function M:OnSpellStart()
    -- Panorama-routed building actions are authoritative in ui_request_router.
end

return M