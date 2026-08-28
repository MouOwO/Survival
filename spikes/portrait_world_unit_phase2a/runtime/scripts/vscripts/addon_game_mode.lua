if PortraitWorldUnitPhase2A == nil then
    PortraitWorldUnitPhase2A = class({})
end

function Precache(_context)
end

function Activate()
    GameRules.PortraitWorldUnitPhase2A = PortraitWorldUnitPhase2A()
    GameRules.PortraitWorldUnitPhase2A:InitGameMode()
end

function PortraitWorldUnitPhase2A:InitGameMode()
    print("[PHASE2A] isolated portrait_world_unit spike loaded")
end