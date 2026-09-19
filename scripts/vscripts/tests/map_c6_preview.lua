-- Optional local art review only: script_reload_code tests/map_c6_preview
if not IsInToolsMode() or (GetMapName() ~= "survival_c6" and GetMapName() ~= "template_map") then return end
GameRules:GetGameModeEntity():SetFogOfWarDisabled(true)
GameRules:SetTimeOfDay(0.3)
if GameRules:State_Get() == DOTA_GAMERULES_STATE_CUSTOM_GAME_SETUP then
    GameRules:FinishCustomGameSetup()
end
print("[C6_PREVIEW] Daylight and full map vision enabled for local review")
