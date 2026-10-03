-- Optional art inspection; never loaded by normal gameplay.
if not IsInToolsMode() or GetMapName() ~= "valley_decor_review" then return end
GameRules:GetGameModeEntity():SetFogOfWarDisabled(true)
GameRules:GetGameModeEntity():SetDaynightCycleDisabled(true)
GameRules:SetTimeOfDay(0.3)
if GameRules:State_Get() == DOTA_GAMERULES_STATE_CUSTOM_GAME_SETUP then
    GameRules:FinishCustomGameSetup()
end
local checked, failed = 0, 0
for i = 1, 4 do
    local marker = Entities:FindByName(nil, "monsterborn_player" .. i)
    local fx = Entities:FindByName(nil, "valley_decor_v1_fx_monsterborn_player" .. i)
    checked = checked + 1
    if not marker or not fx then
        failed = failed + 1
    else
        local p = marker:GetAbsOrigin()
        local valid = GridNav:IsTraversable(p) and not GridNav:IsBlocked(p)
        print("VALLEY_REVIEW_SPAWN", i, valid, GetGroundHeight(p, nil), fx:GetAbsOrigin().z)
        if not valid then failed = failed + 1 end
        local direction = (p - Vector(-1024, 4096, p.z)):Normalized()
        local side = Vector(-direction.y, direction.x, 0)
        for step = 0, 8 do
            for offset = -1, 1 do
                local sample = p + direction * (step * 90) + side * (offset * 80)
                checked = checked + 1
                if not GridNav:IsTraversable(sample) or GridNav:IsBlocked(sample) then
                    failed = failed + 1
                    print("VALLEY_REVIEW_BLOCKED", i, step, offset)
                end
            end
        end
        checked = checked + 1
        if not GridNav:CanFindPath(p, p + direction * 720) then failed = failed + 1 end
    end
end
print("VALLEY_REVIEW_CHECK", checked, failed)
require("tools/valley_reference_portals").Apply()
print("VALLEY_REVIEW_READY")
