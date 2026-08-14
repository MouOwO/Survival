ability_destroy_arrow_tower = class({})

function ability_destroy_arrow_tower:OnSpellStart()
    if IsServer() then self:EndCooldown() end
end

return ability_destroy_arrow_tower