-- Isolated UI inspection only. Does not change combat values or reward rules.
return function()
if not IsInToolsMode() then error("tools_mode_required") end
require("systems/wave_system").set_dev_mode(true)
-- This scene inspects UI without playing the construction tutorial. Suspend
-- only its deadline in this tools session; the production defeat rule remains.
require("core/scheduler").cancel("player_unbuilt_wall_defeat")
print("[UI_STAGE3_SETUP] automatic wave timer paused for UI inspection")
end
