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
for _, row in ipairs(require("config/generated/archive_challenge_actions").rows) do
    if row.enabled then _G[row.ability_name] = create(row.action_id) end
end
ability_archive_finish = create("finish")
ability_archive_endless = create("endless")
