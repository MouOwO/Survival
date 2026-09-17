if _G.WorldV2CommandVersion == 18 then return end
_G.WorldV2CommandVersion = 18
local shots={
 {name='central_island',x=-1152,y=2688,d=9000},
 {name='island_levels',x=-1152,y=5900,d=5200},
 {name='tower_stairs',x=-1152,y=-128,d=2700},
 {name='overview',x=0,y=-1000,d=32000},
 {name='mountain_detail',x=2800,y=-14300,d=2700},
 {name='cloud_edge',x=-17400,y=13500,d=6200},
 {name='cloud_band',x=2500,y=-9000,d=4000},
 {name='training_close',x=-8602,y=13760,d=2100},
 {name='boss_close',x=-8970,y=10864,d=2000},
 {name='original_challenge',x=-12972,y=320,d=4100},
 {name='island_stairs',x=-1152,y=4900,d=3400},
 {name='hot_spring',x=0,y=-14000,d=3400},
 {name='camp_boundary',x=12200,y=-4200,d=3300},
 {name='grass_detail',x=13800,y=-4600,d=1900},
 {name='shallow_lake',x=-1152,y=2688,d=2300},
 {name='volcanic_arena',x=7222,y=10280,d=2300},
 {name='upper_training',x=-6000,y=13760,d=4600},
 {name='lower_training',x=3500,y=-6800,d=5800},
 {name='snow_camps',x=11960,y=8600,d=5800},
 {name='boss_islands',x=6440,y=-700,d=4700},
 {name='tree_close',x=-1152,y=5888,d=2800},
 {name='camp_transition',x=-13900,y=-7700,d=3600},
 {name='mountain_canopy',x=0,y=-14500,d=4300},
 {name='grass_paving',x=-13000,y=9400,d=3000},
 {name='prison_floor',x=10300,y=-4200,d=3200},
 {name='ocean_motion_a',x=1248,y=5088,d=1800},
 {name='ocean_motion_b',x=1248,y=5088,d=1800}
}
local i,stage=1,0
local reviewCamera=CreateUnitByName('npc_dota_thinker',Vector(0,0,0),false,nil,nil,DOTA_TEAM_GOODGUYS)
-- Reassert the review target while the screenshot is settling; edge scrolling must
-- not move an automatically labelled screenshot into the neighbouring region.
GameRules:GetGameModeEntity():SetContextThink('world_v2_review_camera_lock',function()
 local s=shots[i];if not s or not IsValidEntity(reviewCamera) then return nil end
 if stage==1 then PlayerResource:SetCameraTarget(0,reviewCamera);SendToServerConsole('dota_camera_set_lookatpos '..s.x..' '..s.y) end
 return .1
end,8)
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
 -- Finish all 21 views before the visual test match automatically ends.
 return 2.5
end,8)
