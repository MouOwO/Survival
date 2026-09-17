if GetMapName()~='survival_basin_native' then return end
local gm=GameRules:GetGameModeEntity()
GameRules:SetCustomGameSetupAutoLaunchDelay(1)
gm:SetContextThink('native_preview_begin',function()
 if GameRules:State_Get()<DOTA_GAMERULES_STATE_PRE_GAME then return 1 end
 gm:SetFogOfWarDisabled(true);gm:SetDaynightCycleDisabled(true);GameRules:SetTimeOfDay(.3)
 for _,s in ipairs({'sv_cheats 1','r_drawpanorama 0','r_always_render_all_windows 1','r_farz 50000','r_nearz 32'}) do SendToServerConsole(s) end
 local hero=PlayerResource:GetSelectedHeroEntity(0)
 if hero then FindClearSpaceForUnit(hero,Vector(0,0,128),true) end
 for q=0,3 do
  local a=q*math.pi/2;local c=Vector(2816*math.cos(a),2816*math.sin(a),512)
  print('[NATIVE_PATH]',q,GridNav:CanFindPath(Vector(0,0,128),c),GridNav:CanFindPath(c,Vector(0,0,128)))
  for i=0,12 do local r=768+i*128;local p=Vector(r*math.cos(a),r*math.sin(a),0)
   print('[NATIVE_STAIR]',q,i,GetGroundHeight(p,nil),GridNav:IsTraversable(p),GridNav:IsBlocked(p))
  end
 end
 local shots={{'overview',0,-640,8700,200},{'basin',0,0,3300,128},{'snow',0,2816,3200,512},{'pine',-2816,0,3200,512},{'stair',1700,0,2300,300}}
 local i,stage=1,0
 local cam=CreateUnitByName('npc_dota_thinker',Vector(0,0,200),false,nil,nil,DOTA_TEAM_GOODGUYS)
 gm:SetContextThink('native_preview_camera',function()
  local s=shots[i];if not s then return nil end
  PlayerResource:SetCameraTarget(0,cam);SendToServerConsole('dota_camera_distance '..s[4]);SendToServerConsole('dota_camera_set_lookatpos '..s[2]..' '..s[3]);return .2
 end,1)
 gm:SetContextThink('native_preview_shots',function()
  local s=shots[i]
  if not s then PlayerResource:SetCameraTarget(0,nil);UTIL_Remove(cam);SendToServerConsole('dota_camera_distance 8700');SendToServerConsole('dota_camera_set_lookatpos 0 -640');print('[NATIVE_CAPTURE_COMPLETE]');return nil end
  if stage==0 then cam:SetAbsOrigin(Vector(s[2],s[3],s[5]));stage=1
  else SendToServerConsole('screenshot basin_native_'..s[1]);print('[NATIVE_CAPTURE]',s[1]);i=i+1;stage=0 end
  return 4
 end,5)
 return nil
end,2)
