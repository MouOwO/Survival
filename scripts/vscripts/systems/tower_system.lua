-- ============================================================================
-- Tower System - 箭塔系统（升级+转职）
-- ============================================================================
if TowerSystem == nil then
    _G.TowerSystem = class({})
end

function TowerSystem:Init()
    self.towers = {}
    print("[TowerSystem] Initialized")
end

function TowerSystem:InitTower(building)
    building._towerLevel = 1
    building._towerClass = nil
    table.insert(self.towers, building)
    print("[TowerSystem] Tower initialized at level 1")
end

function TowerSystem:UpgradeTower(tower, hero)
    if not tower or tower:IsNull() then return false end

    local config = tower._buildingConfig
    if not config then return false end

    local level = tower._towerLevel or 1
    local maxLevel = config.max_level or 5

    if level >= maxLevel and not tower._towerClass then
        -- 可以转职
        BuildingSystem:ShowMessage(hero:GetPlayerID(), "箭塔已满级，请选择转职方向")
        return false
    end

    if level >= maxLevel and tower._towerClass then
        BuildingSystem:ShowMessage(hero:GetPlayerID(), "箭塔已达最高等级")
        return false
    end

    local team = hero:GetTeamNumber()
    local costWood = config.upgrade_wood or 30
    local costGold = config.upgrade_gold or 10

    if not ResourceSystem:CanAfford(team, costWood, costGold, 0) then
        BuildingSystem:ShowMessage(hero:GetPlayerID(), "资源不足")
        return false
    end

    ResourceSystem:Spend(team, costWood, costGold, 0)

    tower._towerLevel = level + 1

    local newHP = config.base_hp + config.hp_per_level * tower._towerLevel
    local newDmg = config.base_damage + config.damage_per_level * tower._towerLevel
    local newArmor = config.base_armor + config.armor_per_level * tower._towerLevel

    tower:SetBaseMaxHealth(newHP)
    tower:SetMaxHealth(newHP)
    tower:SetHealth(newHP)
    tower:SetBaseDamageMin(newDmg)
    tower:SetBaseDamageMax(newDmg)
    tower:SetPhysicalArmorBaseValue(newArmor)

    BuildingSystem:ShowMessage(hero:GetPlayerID(), "箭塔升到LV" .. tower._towerLevel)
    return true
end

function TowerSystem:ClassChangeTower(tower, classIndex, hero)
    if not tower or tower:IsNull() then return false end

    local classData = TOWERS_CONFIG.class_change[classIndex]
    if not classData then return false end

    tower._towerClass = classData.bonus
    tower._towerClassName = classData.name

    BuildingSystem:ShowMessage(hero:GetPlayerID(), "箭塔转职为: " .. classData.name)
    return true
end

function TowerSystem:GetTowerInfo(tower)
    if not tower or tower:IsNull() then return nil end
    return {
        level = tower._towerLevel or 1,
        class = tower._towerClass or "none",
        className = tower._towerClassName or "箭塔",
    }
end
