if _G.WorldV2CommandVersion == 5 then return end
_G.WorldV2CommandVersion = 5
local shots={
 {name='overview',x=0,y=-1000,d=28000},
 {name='central_island',x=-1104,y=2720,d=7800},
 {name='shallow_lake',x=-1104,y=2720,d=2300},
 {name='volcanic_arena',x=7222,y=10280,d=2300},
 {name='upper_training',x=-6000,y=13760,d=4600},
 {name='lower_training',x=3500,y=-6800,d=5800},
 {name='snow_camps',x=11960,y=8600,d=5800},
 {name='boss_islands',x=6440,y=-700,d=4700},
 {name='tree_close',x=-1104,y=5920,d=2000}
}
local i,stage=1,0
local reviewCamera=CreateUnitByName('npc_dota_thinker',Vector(0,0,0),false,nil,nil,DOTA_TEAM_GOODGUYS)
GameRules:GetGameModeEntity():SetContextThink('world_v2_review_gallery',function()
 local s=shots[i]
 if not s then PlayerResource:SetCameraTarget(0,nil); UTIL_Remove(reviewCamera); return nil end
 if stage==0 then
   reviewCamera:SetAbsOrigin(GetGroundPosition(Vector(s.x,s.y,0),nil))
   PlayerResource:SetCameraTarget(0,reviewCamera)
   SendToServerConsole('r_drawpanorama 0')
   SendToServerConsole('r_farz 90000')
   SendToServerConsole('dota_camera_distance '..s.d)
   SendToServerConsole('dota_camera_set_lookatpos '..s.x..' '..s.y)
   stage=1
 else
   print('[WORLD_V2_GALLERY]',s.name)
   SendToServerConsole('screenshot world_v2_'..s.name)
   i=i+1;stage=0
 end
 return 4
end,8)
