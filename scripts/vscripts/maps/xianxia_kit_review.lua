-- Isolated local asset-review scene. Never runs on gameplay maps.
if GetMapName() ~= 'xianxia_kit_review' then return end
local gm=GameRules:GetGameModeEntity()
gm:SetContextThink('xianxia_kit_review_start',function()
 if GameRules:State_Get()<DOTA_GAMERULES_STATE_PRE_GAME then return 1 end
 gm:SetFogOfWarDisabled(true);gm:SetDaynightCycleDisabled(true);GameRules:SetTimeOfDay(.3)
 SendToServerConsole('sv_cheats 1');SendToServerConsole('r_drawpanorama 0');SendToServerConsole('r_farz 25000')
 local shots={{'assembly',0,0,2800},{'components',0,3300,6600}}
 local i,stage=1,0
 local cam=CreateUnitByName('npc_dota_thinker',Vector(0,0,256),false,nil,nil,DOTA_TEAM_GOODGUYS)
 gm:SetContextThink('xianxia_kit_camera_lock',function()
  local s=shots[i];if not s then return nil end
  if stage==1 then
   PlayerResource:SetCameraTarget(0,cam)
   SendToServerConsole('dota_camera_distance '..s[4])
   SendToServerConsole('dota_camera_set_lookatpos '..s[2]..' '..s[3])
  end
  return .1
 end,3)
 gm:SetContextThink('xianxia_kit_review_shots',function()
  local s=shots[i]
  if not s then PlayerResource:SetCameraTarget(0,nil);UTIL_Remove(cam);return nil end
  if stage==0 then
   cam:SetAbsOrigin(Vector(s[2],s[3],256));PlayerResource:SetCameraTarget(0,cam)
   SendToServerConsole('dota_camera_distance '..s[4]);SendToServerConsole('dota_camera_set_lookatpos '..s[2]..' '..s[3]);stage=1
  else
   SendToServerConsole('screenshot xianxia_kit_'..s[1]);print('[XIANXIA_KIT_CAPTURE]',s[1]);i=i+1;stage=0
  end
  return 3
 end,3)
 return nil
end,2)
