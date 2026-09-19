-- Local art preview: nearly freeze simulation without the pause grayscale filter.
if not IsInToolsMode() or (GetMapName() ~= "survival_c6" and GetMapName() ~= "template_map") then return end
PauseGame(false)
Convars:SetFloat("host_timescale",0.001)
print("[C6_PREVIEW] Terrain inspection speed enabled (host_timescale 0.001)")
