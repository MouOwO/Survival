-- ============================================================================
-- Modifier: worker_builder
-- 应用到 undying 英雄上：移除原有技能，添加Q建造技能，设置高血量+移速
-- ============================================================================
modifier_worker_builder = class({})

function modifier_worker_builder:IsHidden()
    return false
end

function modifier_worker_builder:IsPurgable()
    return false
end

function modifier_worker_builder:GetAttributes()
    return MODIFIER_ATTRIBUTE_PERMANENT
end

function modifier_worker_builder:OnCreated()
    if not IsServer() then return end

    local parent = self:GetParent()
    if not parent then return end

    -- 1. 移除 undying 原有的所有技能
    for i = parent:GetAbilityCount() - 1, 0, -1 do
        local ab = parent:GetAbilityByIndex(i)
        if ab then
            local abName = ab:GetAbilityName()
            if abName then
                parent:RemoveAbility(abName)
            end
        end
    end

    -- 2. 添加 Q 技能：建造
    local ab = parent:AddAbility("ability_build")
    if ab then
        ab:SetLevel(1)
        print("[modifier_worker_builder] Added ability_build at slot 0")
    end

    -- 3. 设置血量 10,000,000
    parent:SetBaseMaxHealth(10000000)
    parent:SetMaxHealth(10000000)
    parent:SetHealth(10000000)

    -- 4. 禁用技能点
    parent:SetAbilityPoints(0)

    -- 5. 延迟初始化UI状态
    Timers:CreateTimer(0.5, function()
        if parent and not parent:IsNull() then
            self:SendBuildStateToClient(parent)
        end
    end)

    print("[modifier_worker_builder] Undying configured: Q=build, HP=10M, Speed=fast")
end

function modifier_worker_builder:SendBuildStateToClient(hero)
    if not hero or hero:IsNull() then return end
    local playerID = hero:GetPlayerID()
    local player = PlayerResource:GetPlayer(playerID)
    if not player then return end

    local buildType = "wall"
    local buildName = "城墙"
    local costWood = 30
    local costGold = 0

    if BUILDINGS_CONFIG then
        if BuildingSystem:GetBuildingCount("wall") < 1 then
            buildType = "wall"
        elseif not BuildingSystem.mainCity or BuildingSystem.mainCity:IsNull() then
            buildType = "main_city"
        elseif BuildingSystem:GetBuildingCount("arrow_tower") < 1 then
            buildType = "arrow_tower"
        elseif BuildingSystem:GetMainCityLevel() >= 3
               and BuildingSystem:GetBuildingCount("hero_altar") < 1 then
            buildType = "hero_altar"
        else
            buildType = "wall"
        end

        local config = BUILDINGS_CONFIG[buildType]
        if config then
            buildName = config.name
            costWood = config.cost_wood or 0
            costGold = config.cost_gold or 0
        end
    end

    CustomGameEventManager:Send_ServerToPlayer(player, "ui_build_state_changed", {
        build_type = buildType,
        build_name = buildName,
        cost_wood = costWood,
        cost_gold = costGold,
    })
end

function modifier_worker_builder:DeclareFunctions()
    return {
        MODIFIER_PROPERTY_MOVESPEED_BONUS_UNIQUE,
    }
end

function modifier_worker_builder:GetModifierMoveSpeedBonusUnique()
    return 150
end
