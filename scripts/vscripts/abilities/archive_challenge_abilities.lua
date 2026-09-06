local definitions = require("config/generated/archive_challenge_definitions")
local function create(id)
    local Ability = class({})
    function Ability:OnSpellStart()
        if IsServer() then require("systems/archive_challenge_service").cast(self, id) end
    end
    return Ability
end
for _, row in ipairs(definitions.rows) do
    _G["ability_archive_" .. row.challenge_id] = create(row.challenge_id)
end
ability_archive_finish = create("finish")
ability_archive_endless = create("endless")
