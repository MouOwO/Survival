-- Isolated layout review only; no changes to the main map's spawn rules.
if GetMapName()~='survival_basin_review' and GetMapName()~='survival_basin_edit' then return end
local gm=GameRules:GetGameModeEntity()
GameRules:SetCustomGameSetupAutoLaunchDelay(1)
gm:SetContextThink('basin_review_begin',function()
 if GameRules:State_Get()<DOTA_GAMERULES_STATE_PRE_GAME then return 1 end
 gm:SetFogOfWarDisabled(true);gm:SetDaynightCycleDisabled(true);GameRules:SetTimeOfDay(.3)
 SendToServerConsole('sv_cheats 1');SendToServerConsole('r_drawpanorama 0')
 SendToServerConsole('r_always_render_all_windows 1');SendToServerConsole('r_farz 50000');SendToServerConsole('r_nearz 32')
 local hero=PlayerResource:GetSelectedHeroEntity(0)
 if hero then FindClearSpaceForUnit(hero,Vector(96,0,80),true) end
 if GetMapName()=='survival_basin_edit' then
  SendToServerConsole('r_drawpanorama 1');SendToServerConsole('dota_camera_distance 1650')
  SendToServerConsole('dota_camera_set_lookatpos 0 0')
  return nil
 end
 local total,failed=0,0
 local function sample(name,x,y,expected,z)
  local p=Vector(x,y,0);local walk=GridNav:IsTraversable(p) and not GridNav:IsBlocked(p)
  local h=GetGroundHeight(p,nil);local ok=walk==expected and (not z or math.abs(h-z)<36)
  total=total+1;if not ok then failed=failed+1 end
  print('[BASIN_NAV]',name,ok and 'PASS' or 'FAIL','walk='..tostring(walk),'height='..tostring(h))
 end
 sample('puddle',0,0,true,64)
 for q=0,3 do
  local a=q*math.pi/2
  for i=0,32 do
   local r=1024+i*32+8;sample('stair_'..q..'_'..i,r*math.cos(a),r*math.sin(a),true,i==32 and 640 or 128+(i+1)*16)
  end
  local c=Vector(2880*math.cos(a),2880*math.sin(a),640)
  sample('court_'..q,c.x,c.y,true,640)
  sample('wall_gap_'..q,2112*math.cos(a),2112*math.sin(a),true,640)
  for _,side in ipairs({-1,1}) do sample('blocked_stair_side_'..q..'_'..side,1500*math.cos(a)-side*448*math.sin(a),1500*math.sin(a)+side*448*math.cos(a),false) end
  print('[BASIN_PATH]',q,GridNav:CanFindPath(Vector(0,0,64),c),GridNav:CanFindPath(c,Vector(0,0,64)))
 end
 sample('void_diagonal',1800,1800,false)
 print('[BASIN_NAV_SUMMARY]','samples='..total,'failed='..failed)
 local shots={{'overview',0,0,8400,256},{'basin',0,0,3600,100},{'peach',2880,0,4000,640},{'snow',0,2880,3400,640},{'snow_material_close',0,2880,1500,640},{'pine',-2880,0,4000,640},{'sand',0,-2880,4000,640},{'stair_gate',0,-1800,2800,400}}
 local i,stage=1,0
 local cam=CreateUnitByName('npc_dota_thinker',Vector(0,0,256),false,nil,nil,DOTA_TEAM_GOODGUYS)
 gm:SetContextThink('basin_camera_lock',function()
  local s=shots[i];if not s then return nil end
  if stage==1 then PlayerResource:SetCameraTarget(0,cam);SendToServerConsole('dota_camera_distance '..s[4]);SendToServerConsole('dota_camera_set_lookatpos '..s[2]..' '..s[3]) end
  return .1
 end,1)
 gm:SetContextThink('basin_review_shots',function()
  local s=shots[i]
  if not s then
   PlayerResource:SetCameraTarget(0,nil);UTIL_Remove(cam)
   SendToServerConsole('dota_camera_distance 4200');SendToServerConsole('dota_camera_set_lookatpos 0 0')
   print('[BASIN_CAPTURE_COMPLETE]');return nil
  end
  if stage==0 then cam:SetAbsOrigin(Vector(s[2],s[3],s[5]));PlayerResource:SetCameraTarget(0,cam);SendToServerConsole('dota_camera_distance '..s[4]);stage=1
  else SendToServerConsole('screenshot basin_review_'..s[1]);print('[BASIN_CAPTURE]',s[1]);i=i+1;stage=0 end
  return 4
 end,5)
 return nil
end,2)
