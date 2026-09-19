-- Explicit local visual-review map only. No effect on other maps.
if GetMapName() ~= 'survival_world_v2' then return end
local gm = GameRules:GetGameModeEntity()
gm:SetContextThink('world_v2_visual_review', function()
    if GameRules:State_Get() < DOTA_GAMERULES_STATE_PRE_GAME then return 1 end
    gm:SetFogOfWarDisabled(true)
    gm:SetDaynightCycleDisabled(true)
    GameRules:SetTimeOfDay(0.3)
    print('[WORLD_V2_TIME]',GameRules:GetTimeOfDay())
    SendToServerConsole('sv_cheats 1')
    SendToServerConsole('r_always_render_all_windows 1')
    SendToServerConsole('r_farz 100000')
    -- Preserve depth precision in the unusually distant whole-map preview.
    SendToServerConsole('r_nearz 64')
    SendToServerConsole('r_drawpanorama 0')
    SendToServerConsole('dota_camera_distance 5200')
    SendToServerConsole('dota_camera_set_lookatpos -1104 7200')
    print('[WORLD_V2] loaded cultivation cloud-sea preview', GetMapName())
    -- Colored map trees are baked by the tile compiler; their native material
    -- groups are authored in the VMAP and visually reviewed in the screenshots.
    DoIncludeScript('maps/survival_world_v2_verify', getfenv())
    DoIncludeScript('maps/survival_world_v2_commands', getfenv())
    gm:SetContextThink('world_v2_capture', function()
        SendToServerConsole('screenshot')
        return nil
    end, 4)
    return nil
end, 2)
