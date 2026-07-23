local return_home = require("systems/hero_return_home_service")

ability_survival_return_home = class({})

function ability_survival_return_home:OnSpellStart()
    local caster = self:GetCaster()
    if not caster or caster:IsNull() then return end
    return_home.return_unit(caster, caster:GetPlayerOwnerID())
end
