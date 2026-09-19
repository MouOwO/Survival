if GetMapName()~='survival_world_v2' then return end
local tests={
{name='n01_10_player_0',x=2560.000000000001,y=2687.9999999999995,walk=true,shallow=false},
{name='n01_10_player_1',x=-1152,y=6400,walk=true,shallow=false},
{name='n01_10_player_2',x=-4864.000000000001,y=2687.9999999999995,walk=true,shallow=false},
{name='n01_10_player_3',x=-1152,y=-1024.000000000001,walk=true,shallow=false},
{name='n01_10_monster_spawn',x=-1152,y=2687.9999999999995,walk=true,shallow=false},
{name='n11_20_player_0',x=-5750,y=-10240,walk=true,shallow=false},
{name='n11_20_player_1',x=-3450,y=-12280,walk=true,shallow=false},
{name='n11_20_player_2',x=-5727,y=-14240,walk=true,shallow=false},
{name='n11_20_player_3',x=-8050,y=-12280,walk=true,shallow=false},
{name='n11_20_monster_spawn',x=-5750,y=-12240,walk=true,shallow=false},
{name='n21_30_player_0',x=-14214,y=9360,walk=true,shallow=false},
{name='n21_30_player_1',x=-14214,y=6160,walk=true,shallow=false},
{name='n21_30_player_2',x=-11454,y=6160,walk=true,shallow=false},
{name='n21_30_player_3',x=-11454,y=9360,walk=true,shallow=false},
{name='n21_30_monster_spawn',x=-12834,y=7600,walk=true,shallow=false},
{name='n31_40_player_0',x=-11776,y=-5120,walk=true,shallow=false},
{name='n31_40_monster_0',x=-14444,y=-5120,walk=true,shallow=false},
{name='n31_40_player_1',x=-14076,y=-7680,walk=true,shallow=false},
{name='n31_40_monster_1',x=-11316,y=-7680,walk=true,shallow=false},
{name='n31_40_player_2',x=-11776,y=-10240,walk=true,shallow=false},
{name='n31_40_monster_2',x=-14444,y=-10240,walk=true,shallow=false},
{name='n31_40_player_3',x=-14076,y=-12800,walk=true,shallow=false},
{name='n31_40_monster_3',x=-11316,y=-12800,walk=true,shallow=false},
{name='n41_50_player_0',x=10028,y=13120,walk=true,shallow=false},
{name='n41_50_monster_0',x=12696,y=13120,walk=true,shallow=false},
{name='n41_50_player_1',x=10028,y=10400,walk=true,shallow=false},
{name='n41_50_monster_1',x=12696,y=10400,walk=true,shallow=false},
{name='n41_50_player_2',x=10028,y=7680,walk=true,shallow=false},
{name='n41_50_monster_2',x=12696,y=7680,walk=true,shallow=false},
{name='n41_50_player_3',x=10028,y=4960,walk=true,shallow=false},
{name='n41_50_monster_3',x=12696,y=4960,walk=true,shallow=false},
{name='n51_60_player_shared',x=13984,y=-4160,walk=true,shallow=false},
{name='n51_60_monster_spawn',x=10028,y=-4320,walk=true,shallow=false},
{name='rebirth_01_boss_spawn',x=-8970,y=10929.6,walk=true,shallow=false},
{name='rebirth_02_boss_spawn',x=-8970,y=9345.6,walk=true,shallow=false},
{name='rebirth_03_boss_spawn',x=-8970,y=7761.6,walk=true,shallow=false},
{name='rebirth_04_boss_spawn',x=-8970,y=6177.6,walk=true,shallow=false},
{name='rebirth_05_boss_spawn',x=-8970,y=4593.5999999999985,walk=true,shallow=false},
{name='rebirth_06_boss_spawn',x=-8970,y=3009.6000000000004,walk=true,shallow=false},
{name='rebirth_07_boss_spawn',x=-8970,y=1425.5999999999995,walk=true,shallow=false},
{name='rebirth_08_boss_spawn',x=-8970,y=-158.39999999999918,walk=true,shallow=false},
{name='rebirth_09_boss_spawn',x=-8970,y=-1742.4,walk=true,shallow=false},
{name='rebirth_10_boss_spawn',x=-8970,y=-3326.400000000001,walk=true,shallow=false},
{name='flame_troll_boss_spawn',x=-7406,y=10640,walk=true,shallow=false},
{name='ice_elegy_boss_spawn',x=-7406,y=8560,walk=true,shallow=false},
{name='synthesis_gem_boss_spawn',x=-7406,y=6480,walk=true,shallow=false},
{name='commandment_01_boss_spawn',x=5336,y=1592.0000000000005,walk=true,shallow=false},
{name='commandment_02_boss_spawn',x=6394,y=1592.0000000000005,walk=true,shallow=false},
{name='commandment_03_boss_spawn',x=7452,y=1592.0000000000005,walk=true,shallow=false},
{name='commandment_04_boss_spawn',x=5336,y=-103.99999999999864,walk=true,shallow=false},
{name='commandment_05_boss_spawn',x=6394,y=-103.99999999999864,walk=true,shallow=false},
{name='commandment_06_boss_spawn',x=7452,y=-103.99999999999864,walk=true,shallow=false},
{name='commandment_07_boss_spawn',x=5336,y=-1800,walk=true,shallow=false},
{name='commandment_08_boss_spawn',x=6394,y=-1800,walk=true,shallow=false},
{name='commandment_09_boss_spawn',x=7452,y=-1800,walk=true,shallow=false},
{name='commandment_10_boss_spawn',x=5336,y=-3495.999999999999,walk=true,shallow=false},
{name='polar_crystal_mobs_boss_spawn',x=5520,y=3847.9999999999995,walk=true,shallow=false},
{name='molten_core_mobs_boss_spawn',x=7268,y=3847.9999999999995,walk=true,shallow=false},
{name='seven_sins_boss_spawn',x=7222,y=10280,walk=true,shallow=false},
{name='training_p0_wood_center',x=-8602,y=13760,walk=true,shallow=false},
{name='training_p0_gold_center',x=-7130,y=13760,walk=true,shallow=false},
{name='training_p0_attributes_center',x=-5658,y=13760,walk=true,shallow=false},
{name='training_p0_greater_attributes_center',x=-4186,y=13760,walk=true,shallow=false},
{name='training_p1_wood_center',x=1150,y=13760,walk=true,shallow=false},
{name='training_p1_gold_center',x=2622,y=13760,walk=true,shallow=false},
{name='training_p1_attributes_center',x=4094,y=13760,walk=true,shallow=false},
{name='training_p1_greater_attributes_center',x=5566,y=13760,walk=true,shallow=false},
{name='training_p2_wood_center',x=-8602,y=-6560,walk=true,shallow=false},
{name='training_p2_gold_center',x=-7130,y=-6560,walk=true,shallow=false},
{name='training_p2_attributes_center',x=-5658,y=-6560,walk=true,shallow=false},
{name='training_p2_greater_attributes_center',x=-4186,y=-6560,walk=true,shallow=false},
{name='training_p3_wood_center',x=1150,y=-6560,walk=true,shallow=false},
{name='training_p3_gold_center',x=2622,y=-6560,walk=true,shallow=false},
{name='training_p3_attributes_center',x=4094,y=-6560,walk=true,shallow=false},
{name='training_p3_greater_attributes_center',x=5566,y=-6560,walk=true,shallow=false},
{name='endless_p0_center',x=46,y=-10320,walk=true,shallow=false},
{name='endless_p1_center',x=3358,y=-10320,walk=true,shallow=false},
{name='endless_p2_center',x=6670,y=-10320,walk=true,shallow=false},
{name='endless_p3_center',x=9982,y=-10320,walk=true,shallow=false},
{name='original_challenge_center',x=-12972,y=320,walk=true,shallow=false},
{name='mountain_northwest',x=-15500,y=15100,walk=false,shallow=false},
{name='mountain_south',x=0,y=-15100,walk=false,shallow=false},
{name='shallow_x_-2048',x=-3200,y=2688,walk=true,shallow=true},
{name='shallow_x_-1920',x=-3072,y=2688,walk=true,shallow=true},
{name='shallow_x_-1792',x=-2944,y=2688,walk=true,shallow=true},
{name='shallow_x_-1664',x=-2816,y=2688,walk=true,shallow=true},
{name='shallow_x_-1536',x=-2688,y=2688,walk=true,shallow=true},
{name='shallow_x_-1408',x=-2560,y=2688,walk=true,shallow=true},
{name='shallow_x_-1280',x=-2432,y=2688,walk=true,shallow=true},
{name='shallow_x_-1152',x=-2304,y=2688,walk=true,shallow=true},
{name='shallow_x_-1024',x=-2176,y=2688,walk=true,shallow=true},
{name='shallow_x_-896',x=-2048,y=2688,walk=true,shallow=true},
{name='shallow_x_-768',x=-1920,y=2688,walk=true,shallow=true},
{name='shallow_x_-640',x=-1792,y=2688,walk=true,shallow=true},
{name='shallow_x_-512',x=-1664,y=2688,walk=true,shallow=true},
{name='shallow_x_-384',x=-1536,y=2688,walk=true,shallow=true},
{name='shallow_x_-256',x=-1408,y=2688,walk=true,shallow=true},
{name='shallow_x_-128',x=-1280,y=2688,walk=true,shallow=true},
{name='shallow_x_0',x=-1152,y=2688,walk=true,shallow=true},
{name='shallow_x_128',x=-1024,y=2688,walk=true,shallow=true},
{name='shallow_x_256',x=-896,y=2688,walk=true,shallow=true},
{name='shallow_x_384',x=-768,y=2688,walk=true,shallow=true},
{name='shallow_x_512',x=-640,y=2688,walk=true,shallow=true},
{name='shallow_x_640',x=-512,y=2688,walk=true,shallow=true},
{name='shallow_x_768',x=-384,y=2688,walk=true,shallow=true},
{name='shallow_x_896',x=-256,y=2688,walk=true,shallow=true},
{name='shallow_x_1024',x=-128,y=2688,walk=true,shallow=true},
{name='shallow_x_1152',x=0,y=2688,walk=true,shallow=true},
{name='shallow_x_1280',x=128,y=2688,walk=true,shallow=true},
{name='shallow_x_1408',x=256,y=2688,walk=true,shallow=true},
{name='shallow_x_1536',x=384,y=2688,walk=true,shallow=true},
{name='shallow_x_1664',x=512,y=2688,walk=true,shallow=true},
{name='shallow_x_1792',x=640,y=2688,walk=true,shallow=true},
{name='shallow_x_1920',x=768,y=2688,walk=true,shallow=true},
{name='shallow_x_2048',x=896,y=2688,walk=true,shallow=true},
{name='shallow_y_-2048',x=-1152,y=640,walk=true,shallow=true},
{name='shallow_y_-1920',x=-1152,y=768,walk=true,shallow=true},
{name='shallow_y_-1792',x=-1152,y=896,walk=true,shallow=true},
{name='shallow_y_-1664',x=-1152,y=1024,walk=true,shallow=true},
{name='shallow_y_-1536',x=-1152,y=1152,walk=true,shallow=true},
{name='shallow_y_-1408',x=-1152,y=1280,walk=true,shallow=true},
{name='shallow_y_-1280',x=-1152,y=1408,walk=true,shallow=true},
{name='shallow_y_-1152',x=-1152,y=1536,walk=true,shallow=true},
{name='shallow_y_-1024',x=-1152,y=1664,walk=true,shallow=true},
{name='shallow_y_-896',x=-1152,y=1792,walk=true,shallow=true},
{name='shallow_y_-768',x=-1152,y=1920,walk=true,shallow=true},
{name='shallow_y_-640',x=-1152,y=2048,walk=true,shallow=true},
{name='shallow_y_-512',x=-1152,y=2176,walk=true,shallow=true},
{name='shallow_y_-384',x=-1152,y=2304,walk=true,shallow=true},
{name='shallow_y_-256',x=-1152,y=2432,walk=true,shallow=true},
{name='shallow_y_-128',x=-1152,y=2560,walk=true,shallow=true},
{name='shallow_y_0',x=-1152,y=2688,walk=true,shallow=true},
{name='shallow_y_128',x=-1152,y=2816,walk=true,shallow=true},
{name='shallow_y_256',x=-1152,y=2944,walk=true,shallow=true},
{name='shallow_y_384',x=-1152,y=3072,walk=true,shallow=true},
{name='shallow_y_512',x=-1152,y=3200,walk=true,shallow=true},
{name='shallow_y_640',x=-1152,y=3328,walk=true,shallow=true},
{name='shallow_y_768',x=-1152,y=3456,walk=true,shallow=true},
{name='shallow_y_896',x=-1152,y=3584,walk=true,shallow=true},
{name='shallow_y_1024',x=-1152,y=3712,walk=true,shallow=true},
{name='shallow_y_1152',x=-1152,y=3840,walk=true,shallow=true},
{name='shallow_y_1280',x=-1152,y=3968,walk=true,shallow=true},
{name='shallow_y_1408',x=-1152,y=4096,walk=true,shallow=true},
{name='shallow_y_1536',x=-1152,y=4224,walk=true,shallow=true},
{name='shallow_y_1664',x=-1152,y=4352,walk=true,shallow=true},
{name='shallow_y_1792',x=-1152,y=4480,walk=true,shallow=true},
{name='shallow_y_1920',x=-1152,y=4608,walk=true,shallow=true},
{name='shallow_y_2048',x=-1152,y=4736,walk=true,shallow=true},
{name='round_lake_0',x=-294.63979382952596,y=3043.130225234803,walk=true,shallow=true},
{name='round_lake_1',x=-796.8697747651966,y=3545.360206170474,walk=true,shallow=true},
{name='round_lake_2',x=-1507.1302252348032,y=3545.360206170474,walk=true,shallow=true},
{name='round_lake_3',x=-2009.3602061704742,y=3043.130225234803,walk=true,shallow=true},
{name='round_lake_4',x=-2009.3602061704742,y=2332.869774765197,walk=true,shallow=true},
{name='round_lake_5',x=-1507.130225234804,y=1830.639793829526,walk=true,shallow=true},
{name='round_lake_6',x=-796.8697747651966,y=1830.6397938295258,walk=true,shallow=true},
{name='round_lake_7',x=-294.63979382952607,y=2332.869774765196,walk=true,shallow=true}
}
local failures=0;local low=99999;local high=-99999
for _,t in ipairs(tests) do local p=Vector(t.x,t.y,500);local walk=GridNav:IsTraversable(p) and not GridNav:IsBlocked(p);local h=GetGroundHeight(p,nil);local ok=walk==t.walk;if not ok then failures=failures+1 end;if t.shallow then low=math.min(low,h);high=math.max(high,h) end;print('[WORLD_V2_CHECK]',t.name,ok and 'PASS' or 'FAIL',walk,h) end
print('[WORLD_V2_CHECK_TOTAL]',#tests,failures)
print('[WORLD_V2_SHALLOW_HEIGHT]',low,high,high-low<=4 and 'PASS' or 'FAIL')
local horizontal=GridNav:CanFindPath(Vector(-3328,2688,384),Vector(1024,2688,384));local vertical=GridNav:CanFindPath(Vector(-1152,512,384),Vector(-1152,4864,384));print('[WORLD_V2_SHALLOW_PATH]',horizontal,vertical,horizontal and vertical and 'PASS' or 'FAIL')
local upper=GetGroundHeight(Vector(-8602,13760,256),nil);local lower=GetGroundHeight(Vector(-8602,-6560,640),nil);print('[WORLD_V2_ELEVATION]',upper,lower,lower>upper and 'PASS' or 'FAIL')
print('[WORLD_V2_CAMP_PATH]', 'n01_10_player_0', GridNav:CanFindPath(Vector(2560.000000000001,2687.9999999999995,384),Vector(-1152,2688,384)) and 'PASS' or 'FAIL')
print('[WORLD_V2_CAMP_PATH]', 'n01_10_player_1', GridNav:CanFindPath(Vector(-1152,6400,384),Vector(-1152,2688,384)) and 'PASS' or 'FAIL')
print('[WORLD_V2_CAMP_PATH]', 'n01_10_player_2', GridNav:CanFindPath(Vector(-4864.000000000001,2687.9999999999995,384),Vector(-1152,2688,384)) and 'PASS' or 'FAIL')
print('[WORLD_V2_CAMP_PATH]', 'n01_10_player_3', GridNav:CanFindPath(Vector(-1152,-1024.000000000001,384),Vector(-1152,2688,384)) and 'PASS' or 'FAIL')
do local lo=99999;local hi=-99999;for dx=-128,128,64 do local h=GetGroundHeight(Vector(-12880+dx,-7680,700),nil);lo=math.min(lo,h);hi=math.max(hi,h) end; print('[WORLD_V2_TERRAIN_SEAM]','dirt_paving',lo,hi,(hi-lo<=4 and math.abs(lo-396)<=4) and 'PASS' or 'FAIL') end
do local lo=99999;local hi=-99999;for dx=-128,128,64 do local h=GetGroundHeight(Vector(-13156+dx,9360,700),nil);lo=math.min(lo,h);hi=math.max(hi,h) end; print('[WORLD_V2_TERRAIN_SEAM]','grass_paving',lo,hi,(hi-lo<=4 and math.abs(lo-396)<=4) and 'PASS' or 'FAIL') end
do local lo=99999;local hi=-99999;for dx=-128,128,64 do local h=GetGroundHeight(Vector(11316+dx,13120,700),nil);lo=math.min(lo,h);hi=math.max(hi,h) end; print('[WORLD_V2_TERRAIN_SEAM]','grass_snow',lo,hi,(hi-lo<=4 and math.abs(lo-524)<=4) and 'PASS' or 'FAIL') end
do local h=GetGroundHeight(Vector(0,9000,700),nil);print('[WORLD_V2_SEA_BED]',h,(h>=254 and h<=256) and 'PASS' or 'FAIL') end
do local p=Vector(0,-14000,800);local blocked=not GridNav:IsTraversable(p) or GridNav:IsBlocked(p);local h=GetGroundHeight(p,nil);print('[WORLD_V2_SPA]',h,blocked,(blocked and math.abs(h-640)<4) and 'PASS' or 'FAIL') end
do local a=GetGroundHeight(Vector(2560,2688,1000),nil);local l=GetGroundHeight(Vector(2048,3788,1000),nil);local r=GetGroundHeight(Vector(2048,1588,1000),nil);print('[WORLD_V2_ISLAND_LEVELS]',0,a,l,r,(math.abs(a-640)<4 and math.abs(l-768)<4 and math.abs(r-768)<4) and 'PASS' or 'FAIL') end
do local a=Vector(1110,2688,1000);local b=Vector(1920,2688,1000);local ok=GridNav:CanFindPath(a,b);local prev=0;local heights={};for i=0,24 do local p=a+(b-a)*(i/24);for _,offset in ipairs({-192,192}) do local side=p+Vector(-(b.y-a.y),b.x-a.x,0):Normalized()*offset;if not GridNav:IsTraversable(side) or GridNav:IsBlocked(side) then ok=false;print('[WORLD_V2_STAIR_EDGE]',0,i,offset) end end;local h=GetGroundHeight(p,nil);table.insert(heights,math.floor(h));if not GridNav:IsTraversable(p) or GridNav:IsBlocked(p) or (i>0 and (h<prev-4 or h-prev>64)) then ok=false;print('[WORLD_V2_STAIR_DETAIL]',0,i,p.x,p.y,h,prev,GridNav:IsTraversable(p),GridNav:IsBlocked(p)) end;prev=h end;print('[WORLD_V2_ISLAND_STAIRS]',0,table.concat(heights,','),ok and 'PASS' or 'FAIL') end
do local a=GetGroundHeight(Vector(-1152,6400,1000),nil);local l=GetGroundHeight(Vector(-2252,5888,1000),nil);local r=GetGroundHeight(Vector(-52,5888,1000),nil);print('[WORLD_V2_ISLAND_LEVELS]',1,a,l,r,(math.abs(a-640)<4 and math.abs(l-768)<4 and math.abs(r-768)<4) and 'PASS' or 'FAIL') end
do local a=Vector(-1152,4950,1000);local b=Vector(-1152,5760,1000);local ok=GridNav:CanFindPath(a,b);local prev=0;local heights={};for i=0,24 do local p=a+(b-a)*(i/24);for _,offset in ipairs({-192,192}) do local side=p+Vector(-(b.y-a.y),b.x-a.x,0):Normalized()*offset;if not GridNav:IsTraversable(side) or GridNav:IsBlocked(side) then ok=false;print('[WORLD_V2_STAIR_EDGE]',1,i,offset) end end;local h=GetGroundHeight(p,nil);table.insert(heights,math.floor(h));if not GridNav:IsTraversable(p) or GridNav:IsBlocked(p) or (i>0 and (h<prev-4 or h-prev>64)) then ok=false;print('[WORLD_V2_STAIR_DETAIL]',1,i,p.x,p.y,h,prev,GridNav:IsTraversable(p),GridNav:IsBlocked(p)) end;prev=h end;print('[WORLD_V2_ISLAND_STAIRS]',1,table.concat(heights,','),ok and 'PASS' or 'FAIL') end
do local a=GetGroundHeight(Vector(-4864,2688,1000),nil);local l=GetGroundHeight(Vector(-4352,1588,1000),nil);local r=GetGroundHeight(Vector(-4352,3788,1000),nil);print('[WORLD_V2_ISLAND_LEVELS]',2,a,l,r,(math.abs(a-640)<4 and math.abs(l-768)<4 and math.abs(r-768)<4) and 'PASS' or 'FAIL') end
do local a=Vector(-3414,2688,1000);local b=Vector(-4224,2688,1000);local ok=GridNav:CanFindPath(a,b);local prev=0;local heights={};for i=0,24 do local p=a+(b-a)*(i/24);for _,offset in ipairs({-192,192}) do local side=p+Vector(-(b.y-a.y),b.x-a.x,0):Normalized()*offset;if not GridNav:IsTraversable(side) or GridNav:IsBlocked(side) then ok=false;print('[WORLD_V2_STAIR_EDGE]',2,i,offset) end end;local h=GetGroundHeight(p,nil);table.insert(heights,math.floor(h));if not GridNav:IsTraversable(p) or GridNav:IsBlocked(p) or (i>0 and (h<prev-4 or h-prev>64)) then ok=false;print('[WORLD_V2_STAIR_DETAIL]',2,i,p.x,p.y,h,prev,GridNav:IsTraversable(p),GridNav:IsBlocked(p)) end;prev=h end;print('[WORLD_V2_ISLAND_STAIRS]',2,table.concat(heights,','),ok and 'PASS' or 'FAIL') end
do local a=GetGroundHeight(Vector(-1152,-1024,1000),nil);local l=GetGroundHeight(Vector(-52,-512,1000),nil);local r=GetGroundHeight(Vector(-2252,-512,1000),nil);print('[WORLD_V2_ISLAND_LEVELS]',3,a,l,r,(math.abs(a-640)<4 and math.abs(l-768)<4 and math.abs(r-768)<4) and 'PASS' or 'FAIL') end
do local a=Vector(-1152,426,1000);local b=Vector(-1152,-384,1000);local ok=GridNav:CanFindPath(a,b);local prev=0;local heights={};for i=0,24 do local p=a+(b-a)*(i/24);for _,offset in ipairs({-192,192}) do local side=p+Vector(-(b.y-a.y),b.x-a.x,0):Normalized()*offset;if not GridNav:IsTraversable(side) or GridNav:IsBlocked(side) then ok=false;print('[WORLD_V2_STAIR_EDGE]',3,i,offset) end end;local h=GetGroundHeight(p,nil);table.insert(heights,math.floor(h));if not GridNav:IsTraversable(p) or GridNav:IsBlocked(p) or (i>0 and (h<prev-4 or h-prev>64)) then ok=false;print('[WORLD_V2_STAIR_DETAIL]',3,i,p.x,p.y,h,prev,GridNav:IsTraversable(p),GridNav:IsBlocked(p)) end;prev=h end;print('[WORLD_V2_ISLAND_STAIRS]',3,table.concat(heights,','),ok and 'PASS' or 'FAIL') end
do local ok=true;local count=0;for r=128,2176,128 do local margin=384-256*math.max(0,math.min(1,(r-1152)/896));for _,v in ipairs({-margin,0,margin}) do local p=Vector(-1152+r*1-v*0,2688+r*0+v*1,500);local h=GetGroundHeight(p,nil);count=count+1;if not GridNav:IsTraversable(p) or GridNav:IsBlocked(p) or math.abs(h-396)>4 then ok=false;print('[WORLD_V2_CHANNEL_DETAIL]',0,r,v,h,GridNav:IsTraversable(p),GridNav:IsBlocked(p)) end end end;print('[WORLD_V2_CHANNEL_WIDTH]',0,count,ok and 'PASS' or 'FAIL') end
do local ok=true;local count=0;for r=128,2176,128 do local margin=384-256*math.max(0,math.min(1,(r-1152)/896));for _,v in ipairs({-margin,0,margin}) do local p=Vector(-1152+r*0-v*1,2688+r*1+v*0,500);local h=GetGroundHeight(p,nil);count=count+1;if not GridNav:IsTraversable(p) or GridNav:IsBlocked(p) or math.abs(h-396)>4 then ok=false;print('[WORLD_V2_CHANNEL_DETAIL]',1,r,v,h,GridNav:IsTraversable(p),GridNav:IsBlocked(p)) end end end;print('[WORLD_V2_CHANNEL_WIDTH]',1,count,ok and 'PASS' or 'FAIL') end
do local ok=true;local count=0;for r=128,2176,128 do local margin=384-256*math.max(0,math.min(1,(r-1152)/896));for _,v in ipairs({-margin,0,margin}) do local p=Vector(-1152+r*-1-v*0,2688+r*0+v*-1,500);local h=GetGroundHeight(p,nil);count=count+1;if not GridNav:IsTraversable(p) or GridNav:IsBlocked(p) or math.abs(h-396)>4 then ok=false;print('[WORLD_V2_CHANNEL_DETAIL]',2,r,v,h,GridNav:IsTraversable(p),GridNav:IsBlocked(p)) end end end;print('[WORLD_V2_CHANNEL_WIDTH]',2,count,ok and 'PASS' or 'FAIL') end
do local ok=true;local count=0;for r=128,2176,128 do local margin=384-256*math.max(0,math.min(1,(r-1152)/896));for _,v in ipairs({-margin,0,margin}) do local p=Vector(-1152+r*0-v*-1,2688+r*-1+v*0,500);local h=GetGroundHeight(p,nil);count=count+1;if not GridNav:IsTraversable(p) or GridNav:IsBlocked(p) or math.abs(h-396)>4 then ok=false;print('[WORLD_V2_CHANNEL_DETAIL]',3,r,v,h,GridNav:IsTraversable(p),GridNav:IsBlocked(p)) end end end;print('[WORLD_V2_CHANNEL_WIDTH]',3,count,ok and 'PASS' or 'FAIL') end
do local left=GetGroundHeight(Vector(1408,2304,1000),nil);local middle=GetGroundHeight(Vector(1408,2688,1000),nil);local right=GetGroundHeight(Vector(1408,3072,1000),nil);print('[WORLD_V2_GATE_CHOKE]',0,left,middle,right,(left>=764 and right>=764 and middle>396 and middle<640) and 'PASS' or 'FAIL') end
do local left=GetGroundHeight(Vector(-768,5248,1000),nil);local middle=GetGroundHeight(Vector(-1152,5248,1000),nil);local right=GetGroundHeight(Vector(-1536,5248,1000),nil);print('[WORLD_V2_GATE_CHOKE]',1,left,middle,right,(left>=764 and right>=764 and middle>396 and middle<640) and 'PASS' or 'FAIL') end
do local left=GetGroundHeight(Vector(-3712,3072,1000),nil);local middle=GetGroundHeight(Vector(-3712,2688,1000),nil);local right=GetGroundHeight(Vector(-3712,2304,1000),nil);print('[WORLD_V2_GATE_CHOKE]',2,left,middle,right,(left>=764 and right>=764 and middle>396 and middle<640) and 'PASS' or 'FAIL') end
do local left=GetGroundHeight(Vector(-1536,128,1000),nil);local middle=GetGroundHeight(Vector(-1152,128,1000),nil);local right=GetGroundHeight(Vector(-768,128,1000),nil);print('[WORLD_V2_GATE_CHOKE]',3,left,middle,right,(left>=764 and right>=764 and middle>396 and middle<640) and 'PASS' or 'FAIL') end
do local a=Vector(1216,1952,1000);local b=Vector(1856,1952,1000);local hi=GetGroundHeight(a,nil);local lo=GetGroundHeight(b,nil);local ok=math.abs(hi-768)<4 and math.abs(lo-640)<4 and GridNav:CanFindPath(b,a);local prev=hi;local heights={};for i=0,20 do local p=a+(b-a)*(i/20);local h=GetGroundHeight(p,nil);table.insert(heights,math.floor(h));if h>prev+4 or prev-h>48 then ok=false end;prev=h;for _,offset in ipairs({-1,0,1}) do local v=p+Vector(0,96,0)*offset;if not GridNav:IsTraversable(v) or GridNav:IsBlocked(v) then ok=false;print('[WORLD_V2_TOWER_STAIR_DETAIL]',0,-1,i,offset,GetGroundHeight(v,nil)) end end end;print('[WORLD_V2_TOWER_STAIRS]',0,-1,table.concat(heights,','),ok and 'PASS' or 'FAIL') end
do local a=Vector(1216,3424,1000);local b=Vector(1856,3424,1000);local hi=GetGroundHeight(a,nil);local lo=GetGroundHeight(b,nil);local ok=math.abs(hi-768)<4 and math.abs(lo-640)<4 and GridNav:CanFindPath(b,a);local prev=hi;local heights={};for i=0,20 do local p=a+(b-a)*(i/20);local h=GetGroundHeight(p,nil);table.insert(heights,math.floor(h));if h>prev+4 or prev-h>48 then ok=false end;prev=h;for _,offset in ipairs({-1,0,1}) do local v=p+Vector(0,96,0)*offset;if not GridNav:IsTraversable(v) or GridNav:IsBlocked(v) then ok=false;print('[WORLD_V2_TOWER_STAIR_DETAIL]',0,1,i,offset,GetGroundHeight(v,nil)) end end end;print('[WORLD_V2_TOWER_STAIRS]',0,1,table.concat(heights,','),ok and 'PASS' or 'FAIL') end
do local a=Vector(-416,5056,1000);local b=Vector(-416,5696,1000);local hi=GetGroundHeight(a,nil);local lo=GetGroundHeight(b,nil);local ok=math.abs(hi-768)<4 and math.abs(lo-640)<4 and GridNav:CanFindPath(b,a);local prev=hi;local heights={};for i=0,20 do local p=a+(b-a)*(i/20);local h=GetGroundHeight(p,nil);table.insert(heights,math.floor(h));if h>prev+4 or prev-h>48 then ok=false end;prev=h;for _,offset in ipairs({-1,0,1}) do local v=p+Vector(-96,0,0)*offset;if not GridNav:IsTraversable(v) or GridNav:IsBlocked(v) then ok=false;print('[WORLD_V2_TOWER_STAIR_DETAIL]',1,-1,i,offset,GetGroundHeight(v,nil)) end end end;print('[WORLD_V2_TOWER_STAIRS]',1,-1,table.concat(heights,','),ok and 'PASS' or 'FAIL') end
do local a=Vector(-1888,5056,1000);local b=Vector(-1888,5696,1000);local hi=GetGroundHeight(a,nil);local lo=GetGroundHeight(b,nil);local ok=math.abs(hi-768)<4 and math.abs(lo-640)<4 and GridNav:CanFindPath(b,a);local prev=hi;local heights={};for i=0,20 do local p=a+(b-a)*(i/20);local h=GetGroundHeight(p,nil);table.insert(heights,math.floor(h));if h>prev+4 or prev-h>48 then ok=false end;prev=h;for _,offset in ipairs({-1,0,1}) do local v=p+Vector(-96,0,0)*offset;if not GridNav:IsTraversable(v) or GridNav:IsBlocked(v) then ok=false;print('[WORLD_V2_TOWER_STAIR_DETAIL]',1,1,i,offset,GetGroundHeight(v,nil)) end end end;print('[WORLD_V2_TOWER_STAIRS]',1,1,table.concat(heights,','),ok and 'PASS' or 'FAIL') end
do local a=Vector(-3520,3424,1000);local b=Vector(-4160,3424,1000);local hi=GetGroundHeight(a,nil);local lo=GetGroundHeight(b,nil);local ok=math.abs(hi-768)<4 and math.abs(lo-640)<4 and GridNav:CanFindPath(b,a);local prev=hi;local heights={};for i=0,20 do local p=a+(b-a)*(i/20);local h=GetGroundHeight(p,nil);table.insert(heights,math.floor(h));if h>prev+4 or prev-h>48 then ok=false end;prev=h;for _,offset in ipairs({-1,0,1}) do local v=p+Vector(0,-96,0)*offset;if not GridNav:IsTraversable(v) or GridNav:IsBlocked(v) then ok=false;print('[WORLD_V2_TOWER_STAIR_DETAIL]',2,-1,i,offset,GetGroundHeight(v,nil)) end end end;print('[WORLD_V2_TOWER_STAIRS]',2,-1,table.concat(heights,','),ok and 'PASS' or 'FAIL') end
do local a=Vector(-3520,1952,1000);local b=Vector(-4160,1952,1000);local hi=GetGroundHeight(a,nil);local lo=GetGroundHeight(b,nil);local ok=math.abs(hi-768)<4 and math.abs(lo-640)<4 and GridNav:CanFindPath(b,a);local prev=hi;local heights={};for i=0,20 do local p=a+(b-a)*(i/20);local h=GetGroundHeight(p,nil);table.insert(heights,math.floor(h));if h>prev+4 or prev-h>48 then ok=false end;prev=h;for _,offset in ipairs({-1,0,1}) do local v=p+Vector(0,-96,0)*offset;if not GridNav:IsTraversable(v) or GridNav:IsBlocked(v) then ok=false;print('[WORLD_V2_TOWER_STAIR_DETAIL]',2,1,i,offset,GetGroundHeight(v,nil)) end end end;print('[WORLD_V2_TOWER_STAIRS]',2,1,table.concat(heights,','),ok and 'PASS' or 'FAIL') end
do local a=Vector(-1888,320,1000);local b=Vector(-1888,-320,1000);local hi=GetGroundHeight(a,nil);local lo=GetGroundHeight(b,nil);local ok=math.abs(hi-768)<4 and math.abs(lo-640)<4 and GridNav:CanFindPath(b,a);local prev=hi;local heights={};for i=0,20 do local p=a+(b-a)*(i/20);local h=GetGroundHeight(p,nil);table.insert(heights,math.floor(h));if h>prev+4 or prev-h>48 then ok=false end;prev=h;for _,offset in ipairs({-1,0,1}) do local v=p+Vector(96,0,0)*offset;if not GridNav:IsTraversable(v) or GridNav:IsBlocked(v) then ok=false;print('[WORLD_V2_TOWER_STAIR_DETAIL]',3,-1,i,offset,GetGroundHeight(v,nil)) end end end;print('[WORLD_V2_TOWER_STAIRS]',3,-1,table.concat(heights,','),ok and 'PASS' or 'FAIL') end
do local a=Vector(-416,320,1000);local b=Vector(-416,-320,1000);local hi=GetGroundHeight(a,nil);local lo=GetGroundHeight(b,nil);local ok=math.abs(hi-768)<4 and math.abs(lo-640)<4 and GridNav:CanFindPath(b,a);local prev=hi;local heights={};for i=0,20 do local p=a+(b-a)*(i/20);local h=GetGroundHeight(p,nil);table.insert(heights,math.floor(h));if h>prev+4 or prev-h>48 then ok=false end;prev=h;for _,offset in ipairs({-1,0,1}) do local v=p+Vector(96,0,0)*offset;if not GridNav:IsTraversable(v) or GridNav:IsBlocked(v) then ok=false;print('[WORLD_V2_TOWER_STAIR_DETAIL]',3,1,i,offset,GetGroundHeight(v,nil)) end end end;print('[WORLD_V2_TOWER_STAIRS]',3,1,table.concat(heights,','),ok and 'PASS' or 'FAIL') end
