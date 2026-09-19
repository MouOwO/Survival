if not IsInToolsMode() or GetMapName()~='survival_c6' then return end
print('[C6_STRESS] STATE current='..GameRules:State_Get()..' playing='..DOTA_GAMERULES_STATE_GAME_IN_PROGRESS..' post='..DOTA_GAMERULES_STATE_POST_GAME..' setup='..DOTA_GAMERULES_STATE_CUSTOM_GAME_SETUP)
DoIncludeScript('tests/map_c6_stress',getfenv(0))
C6Stress.start({100,200,400})
