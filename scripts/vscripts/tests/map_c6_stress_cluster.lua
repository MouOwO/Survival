if not IsInToolsMode() or GetMapName()~='survival_c6' then return end
DoIncludeScript('tests/map_c6_stress',getfenv(0))
C6Stress.start({400},true,60)
