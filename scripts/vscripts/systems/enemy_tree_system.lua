-- ============================================================================
-- Enemy Tree System - 敌方树木系统
-- ============================================================================
if EnemyTreeSystem == nil then
    _G.EnemyTreeSystem = class({})
end

ENEMY_TREE_BASE_HP = 500
ENEMY_TREE_HP_PER_LEVEL = 300
ENEMY_TREE_BASE_ARMOR = 2
ENEMY_TREE_ARMOR_PER_LEVEL = 1
ENEMY_TREE_RESPAWN_TIME = 10.0
ENEMY_TREE_SPAWN_OFFSET = 400

function EnemyTreeSystem:Init()
    self.tree = nil
    self.treeLevel = 1
    self.mainCityRef = nil
    print("[EnemyTreeSystem] Initialized")
end

function EnemyTreeSystem:SpawnTreeNearCity(mainCityBuilding)
    self.mainCityRef = mainCityBuilding
    self.treeLevel = 1
    self:SpawnTree()
end

function EnemyTreeSystem:SpawnTree()
    local spawnPos
    if self.mainCityRef and not self.mainCityRef:IsNull() then
        local cityPos = self.mainCityRef:GetAbsOrigin()
        spawnPos = cityPos + Vector(ENEMY_TREE_SPAWN_OFFSET, 0, 0)
    else
        spawnPos = Vector(500, 500, 128)
    end

    local groundZ = GetGroundHeight(Vector(spawnPos.x, spawnPos.y, 0), nil)
    spawnPos.z = groundZ + 32

    self.tree = CreateUnitByName("enemy_tree", spawnPos, true, nil, nil, DOTA_TEAM_BADGUYS)

    if self.tree then
        self.tree._isEnemyTree = true
        self.tree._treeLevel = self.treeLevel

        local hp = ENEMY_TREE_BASE_HP + (self.treeLevel - 1) * ENEMY_TREE_HP_PER_LEVEL
        local armor = ENEMY_TREE_BASE_ARMOR + (self.treeLevel - 1) * ENEMY_TREE_ARMOR_PER_LEVEL

        self.tree:SetBaseMaxHealth(hp)
        self.tree:SetMaxHealth(hp)
        self.tree:SetHealth(hp)
        self.tree:SetPhysicalArmorBaseValue(armor)
        self.tree:SetBaseDamageMin(10)
        self.tree:SetBaseDamageMax(10)
        self.tree:SetAttackCapability(DOTA_UNIT_CAP_NO_ATTACK)

        print("[EnemyTreeSystem] Tree spawned at level " .. self.treeLevel .. " HP=" .. hp)
    else
        print("[EnemyTreeSystem] ERROR: Failed to spawn tree!")
    end
end

function EnemyTreeSystem:OnTreeKilled(killer)
    self.treeLevel = self.treeLevel + 1

    if killer then
        local team = killer:GetTeamNumber()
        local woodBonus = 10 + self.treeLevel * 5
        ResourceSystem:AddWood(team, woodBonus)
    end

    Timers:CreateTimer(ENEMY_TREE_RESPAWN_TIME, function()
        self:RespawnTree()
    end)
end

function EnemyTreeSystem:RespawnTree()
    if not self.mainCityRef or self.mainCityRef:IsNull() then
        return
    end

    local cityPos = self.mainCityRef:GetAbsOrigin()
    local spawnPos = cityPos + Vector(ENEMY_TREE_SPAWN_OFFSET, 0, 0)
    local groundZ = GetGroundHeight(Vector(spawnPos.x, spawnPos.y, 0), nil)
    spawnPos.z = groundZ + 32

    self.tree = CreateUnitByName("enemy_tree", spawnPos, true, nil, nil, DOTA_TEAM_BADGUYS)

    if self.tree then
        self.tree._isEnemyTree = true
        self.tree._treeLevel = self.treeLevel

        local hp = ENEMY_TREE_BASE_HP + (self.treeLevel - 1) * ENEMY_TREE_HP_PER_LEVEL
        local armor = ENEMY_TREE_BASE_ARMOR + (self.treeLevel - 1) * ENEMY_TREE_ARMOR_PER_LEVEL

        self.tree:SetBaseMaxHealth(hp)
        self.tree:SetMaxHealth(hp)
        self.tree:SetHealth(hp)
        self.tree:SetPhysicalArmorBaseValue(armor)
        self.tree:SetBaseDamageMin(10)
        self.tree:SetBaseDamageMax(10)
        self.tree:SetAttackCapability(DOTA_UNIT_CAP_NO_ATTACK)

        print("[EnemyTreeSystem] Tree respawned at level " .. self.treeLevel .. " HP=" .. hp)
    end
end
