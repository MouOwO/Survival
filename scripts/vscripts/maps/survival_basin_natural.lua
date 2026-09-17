if GetMapName()~='survival_basin_natural' then return end
local gm=GameRules:GetGameModeEntity()
GameRules:SetCustomGameSetupAutoLaunchDelay(1)
gm:SetContextThink('natural_preview_begin',function()
 if GameRules:State_Get()==DOTA_GAMERULES_STATE_CUSTOM_GAME_SETUP then GameRules:FinishCustomGameSetup();return 1 end
 if GameRules:State_Get()<DOTA_GAMERULES_STATE_PRE_GAME then return 1 end
 gm:SetFogOfWarDisabled(true);gm:SetDaynightCycleDisabled(true);GameRules:SetTimeOfDay(.3)
 for _,s in ipairs({'sv_cheats 1','r_drawpanorama 0','r_always_render_all_windows 1','r_farz 50000','r_nearz 32'}) do SendToServerConsole(s) end
 local hero=PlayerResource:GetSelectedHeroEntity(0)
 if hero then FindClearSpaceForUnit(hero,Vector(3300,-250,530),true) end
 for _,p in ipairs({Vector(1800,0,512),Vector(3000,0,512),Vector(4000,-400,512),Vector(4400,650,498)}) do
  print('[NATURAL_PATH]',p,GetGroundHeight(p,nil),GridNav:IsTraversable(p),GridNav:CanFindPath(Vector(3000,0,512),p))
 end
 local shots={{'overview',3100,-750,5700,440},{'ground',3328,-200,2400,512},{'shore',4110,1050,2300,498},{'entry',1350,0,2400,390}}
 local i,stage=1,0
 local cam=CreateUnitByName('npc_dota_thinker',Vector(3000,0,500),false,nil,nil,DOTA_TEAM_GOODGUYS)
 gm:SetContextThink('natural_preview_camera',function()
  local s=shots[i];if not s then return nil end
  PlayerResource:SetCameraTarget(0,cam);SendToServerConsole('dota_camera_distance '..s[4]);SendToServerConsole('dota_camera_set_lookatpos '..s[2]..' '..s[3]);return .2
 end,1)
 gm:SetContextThink('natural_preview_shots',function()
  local s=shots[i]
  if not s then PlayerResource:SetCameraTarget(0,nil);UTIL_Remove(cam);SendToServerConsole('dota_camera_distance 6400');SendToServerConsole('dota_camera_set_lookatpos 2900 -150');print('[NATURAL_CAPTURE_COMPLETE]');return nil end
  if stage==0 then cam:SetAbsOrigin(Vector(s[2],s[3],s[5]));stage=1
  else SendToServerConsole('screenshot basin_natural_'..s[1]);print('[NATURAL_CAPTURE]',s[1]);i=i+1;stage=0 end
  return 4
 end,8)
 return nil
end,2)
