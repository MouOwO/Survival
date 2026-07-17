-- ============================================================================
-- Building UI - 服务端UI推送（资源+建造信息）
-- ============================================================================
if BuildingUI == nil then
    _G.BuildingUI = class({})
end

function BuildingUI:Init()
    self.heroRef = nil
    self.lastChatUpdate = 0
    print("[BuildingUI] Initialized")
end

function BuildingUI:AttachToHero(hero)
    self.heroRef = hero
    print("[BuildingUI] Attached to hero")
end

function BuildingUI:StartUIUpdates()
    -- 每2秒推送一次资源数据到聊天框（Panorama备用方案）
    Timers:CreateTimer("ui_resource_update", 2.0, function()
        return self:UpdateResourceDisplay()
    end)
end

function BuildingUI:UpdateResourceDisplay()
    if not self.heroRef or self.heroRef:IsNull() then
        return 2.0
    end

    local playerID = self.heroRef:GetPlayerID()
    local player = PlayerResource:GetPlayer(playerID)
    if not player then return 2.0 end

    local team = self.heroRef:GetTeamNumber()
    local res = ResourceSystem:GetAllResources(team)
    local wave = WaveSystem:GetCurrentWave()
    local waveTimer = WaveSystem:GetTimeUntilNextWave()
    local waveActive = WaveSystem:IsWaveActive()
    local cityLevel = BuildingSystem:GetMainCityLevel()

    -- 通过 CustomGameEvent 推送到客户端
    CustomGameEventManager:Send_ServerToPlayer(player, "ui_update_resources", {
        wood = res.wood,
        gold = res.gold,
        pop = res.pop,
        max_pop = res.max_pop,
        wave = wave,
        wave_timer = waveTimer,
        wave_active = waveActive and 1 or 0,
        city_level = cityLevel,
    })

    -- 同时更新 NetTable
    ResourceSystem:UpdateNetTable()

    return 2.0
end
