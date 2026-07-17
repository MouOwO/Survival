-- ============================================================================
-- ability_build: 建造技能 (Q)
-- ============================================================================
ability_build = class({})

function ability_build:GetCurrentBuildType()
    if BuildingSystem:GetBuildingCount("wall") < 1 then
        return "wall"
    end
    if not BuildingSystem.mainCity or BuildingSystem.mainCity:IsNull() then
        return "main_city"
    end
    if BuildingSystem:GetBuildingCount("arrow_tower") < 1 then
        return "arrow_tower"
    end
    if BuildingSystem:GetMainCityLevel() >= 3
       and BuildingSystem:GetBuildingCount("hero_altar") < 1 then
        return "hero_altar"
    end
    return "wall"
end

function ability_build:GetBehavior()
    return DOTA_ABILITY_BEHAVIOR_POINT
end

function ability_build:GetManaCost(level)
    return 0
end

function ability_build:GetCooldown(level)
    return 1.0
end

function ability_build:CastFilterResultLocation(location)
    local buildType = self:GetCurrentBuildType()
    local config = BUILDINGS_CONFIG[buildType]
    if not config then return UF_SUCCESS end

    -- 检查是否在建造范围内
    if not GridSystem:CanPlaceInBuildArea(location) then
        return UF_FAIL_CUSTOM
    end

    -- 检查网格
    local snapPos, gx, gy = GridSystem:SnapToGrid(location)
    if not GridSystem:CanPlace(gx, gy, config.size.x, config.size.y, config.terrain_allowed) then
        return UF_FAIL_CUSTOM
    end

    return UF_SUCCESS
end

function ability_build:GetCustomCastErrorLocation(location)
    local buildType = self:GetCurrentBuildType()
    local config = BUILDINGS_CONFIG[buildType]
    if not config then return "" end

    if not GridSystem:CanPlaceInBuildArea(location) then
        return "超出建造范围"
    end

    local snapPos, gx, gy = GridSystem:SnapToGrid(location)
    if not GridSystem:CanPlace(gx, gy, config.size.x, config.size.y, config.terrain_allowed) then
        return "无法在此处建造"
    end

    return ""
end

function ability_build:OnSpellStart()
    local caster = self:GetCaster()
    local location = self:GetCursorPosition()
    local playerID = caster:GetPlayerID()
    local team = caster:GetTeamNumber()

    local buildType = self:GetCurrentBuildType()
    local config = BUILDINGS_CONFIG[buildType]
    if not config then
        BuildingSystem:ShowMessage(playerID, "无法建造")
        return
    end

    -- 检查资源
    if not ResourceSystem:CanAfford(team, config.cost_wood, config.cost_gold, 0) then
        BuildingSystem:ShowMessage(playerID, "资源不足 (需要 " .. config.cost_wood .. "木材)")
        return
    end

    -- 检查数量限制
    if config.max_count > 0 and BuildingSystem:GetBuildingCount(buildType) >= config.max_count then
        BuildingSystem:ShowMessage(playerID, config.name .. " 数量已达上限")
        return
    end

    -- 检查主城等级解锁
    if config.requires_city_level then
        if BuildingSystem:GetMainCityLevel() < config.requires_city_level then
            BuildingSystem:ShowMessage(playerID, "需要主城LV" .. config.requires_city_level)
            return
        end
    end

    -- 扣资源
    ResourceSystem:Spend(team, config.cost_wood, config.cost_gold, 0)

    -- 放置建筑
    local snapPos, gx, gy = GridSystem:SnapToGrid(location)
    local building = BuildingSystem:CreateBuildingAtPosition(config, snapPos, team, buildType, gx, gy)

    if building then
        BuildingSystem:RegisterBuilding(building, buildType, config)
        print("[ability_build] Built " .. config.name)
    else
        -- 退还资源
        ResourceSystem:AddWood(team, config.cost_wood)
        ResourceSystem:AddGold(team, config.cost_gold)
        BuildingSystem:ShowMessage(playerID, "建造失败")
    end
end
