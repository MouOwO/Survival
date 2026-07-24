local function setup_modifier(modifier_class, property, getter_name)
    function modifier_class:IsHidden()
        return true
    end

    function modifier_class:IsPurgable()
        return false
    end

    function modifier_class:RemoveOnDeath()
        return false
    end

    function modifier_class:OnCreated(params)
        self.bonus = tonumber(params and params.bonus) or 0
        if IsServer() and self.SetHasCustomTransmitterData then
            self:SetHasCustomTransmitterData(true)
        end
    end

    function modifier_class:DeclareFunctions()
        return { property }
    end

    function modifier_class:AddBonus(amount)
        if not IsServer() then return end
        self.bonus = (tonumber(self.bonus) or 0) + (tonumber(amount) or 0)
        if self.SendBuffRefreshToClients then
            self:SendBuffRefreshToClients()
        end
        self:ForceRefresh()
    end

    function modifier_class:GetBonus()
        return tonumber(self.bonus) or 0
    end

    function modifier_class:AddCustomTransmitterData()
        return { bonus = tonumber(self.bonus) or 0 }
    end

    function modifier_class:HandleCustomTransmitterData(data)
        self.bonus = tonumber(data and data.bonus) or 0
    end

    modifier_class[getter_name] = function(self)
        return tonumber(self.bonus) or 0
    end
end

modifier_debug_attack_bonus = class({})
_G.modifier_debug_attack_bonus = modifier_debug_attack_bonus
setup_modifier(
    modifier_debug_attack_bonus,
    MODIFIER_PROPERTY_PREATTACK_BONUS_DAMAGE,
    "GetModifierPreAttack_BonusDamage"
)

modifier_debug_armor_bonus = class({})
_G.modifier_debug_armor_bonus = modifier_debug_armor_bonus
setup_modifier(
    modifier_debug_armor_bonus,
    MODIFIER_PROPERTY_PHYSICAL_ARMOR_BONUS,
    "GetModifierPhysicalArmorBonus"
)

return modifier_debug_attack_bonus