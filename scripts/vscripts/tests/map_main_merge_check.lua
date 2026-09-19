if not IsInToolsMode() or GetMapName()~='template_map' then return end
local checked,failed=0,0
local function test(name,ok,detail) checked=checked+1 if not ok then failed=failed+1 end print('[MAIN_MERGE] '..(ok and 'PASS ' or 'FAIL ')..name..' '..(detail or '')) end
local markers={
{'challenge_01_entry',-6784,6336,128},
{'challenge_01_spawn_01',-6720,7296,128},
{'challenge_02_spawn_01',-4416,7360,128},
{'challenge_02_entry',-4480,6336,128},
{'challenge_03_spawn_01',-4352,4928,128},
{'challenge_03_entry',-4416,4032,128},
{'challenge_04_spawn_01',-6784,4864,128},
{'challenge_04_entry',-6784,4032,128},
{'challenge_05_entry',-4096,-4800,128},
{'challenge_05_boss_spawn',-4160,-3968,128},
{'challenge_06_boss_spawn',-6720,2560,128},
{'challenge_06_entry',-6720,1728,128},
{'challenge_07_boss_spawn',-6656,-4160,128},
{'challenge_07_entry',-6656,-4864,128},
{'challenge_08_boss_spawn',-6720,-6464,128},
{'challenge_08_entry',-6720,-7232,128},
{'challenge_09_entry',-6720,-2432,128},
{'challenge_09_boss_spawn',-6656,-1728,128},
{'rebirth_01_boss_spawn',7552,-3136,128},
{'rebirth_01_entry',6720,-3136,128},
{'rebirth_02_entry',7488,-5120,128},
{'rebirth_02_boss_spawn',6882.2802734375,-5190.91015625,128},
{'rebirth_03_entry',6848,-7168,128},
{'rebirth_03_boss_spawn',7430.4599609375,-7189.8901367188,128},
{'rebirth_04_entry',4992,-2752,128},
{'rebirth_04_boss_spawn',5177.7797851562,-3335.9699707031,128},
{'rebirth_05_entry',4928,-4736,128},
{'rebirth_05_boss_spawn',5124.3100585938,-5260.330078125,128},
{'rebirth_06_entry',4928,-6848,128},
{'rebirth_06_boss_spawn',5095.1499023438,-7459.9697265625,128},
{'rebirth_07_entry',2944,-3328,128},
{'rebirth_07_boss_spawn',3072,-2688,128},
{'rebirth_08_entry',3008,-5504,128},
{'rebirth_08_boss_spawn',3200,-4864,128},
{'rebirth_09_entry',3008,-7488,128},
{'rebirth_09_boss_spawn',3008,-6912,128},
{'rebirth_10_entry',768,-5504,128},
{'rebirth_010_boss_spawn',1024,-4992,128},
{'challenge_11_stage_02_entry',6912,5120,128},
{'challenge_11_stage_02_spawn',7488,4928,256},
{'challenge_11_stage_03_spawn',7424,3136,128},
{'challenge_11_stage_03_entry',6848,3136,-26.08203125},
{'challenge_11_stage_04_spawn',5440,7296,128},
{'challenge_11_stage_04_entry',4672,7296,256},
{'challenge_11_stage_05_entry',5184,5568,128},
{'challenge_11_stage_05_spawn',5056,4736,256},
{'challenge_11_stage_06_entry',5056,3328,128},
{'challenge_11_stage_06_spawn',5056,2624,256},
{'challenge_11_stage_07_entry',3136,7680,128},
{'challenge_11_stage_07_spawn',2880,6912,0},
{'challenge_11_stage_08_entry',3072,5568,128},
{'challenge_11_stage_08_spawn',3008,4800,256},
{'challenge_11_stage_09_entry',3008,3392,128},
{'challenge_11_stage_09_spawn',2944,2624,256},
{'challenge_11_stage_10_entry',1408,5184,128},
{'challenge_11_stage_10_spawn',640,5120,256},
{'challenge_10_stage_01_entry',-6912,64,128},
{'challenge_10_stage_01_spawn',-6208,0,256},
{'challenge_11_stage_01_entry',6912,7296,128},
{'challenge_11_stage_01_spawn',7488,7360,128},
}
for _,m in ipairs(markers) do
 local e=Entities:FindByName(nil,m[1])
 local p=e and e:GetAbsOrigin()
 test(m[1],p and (p-Vector(m[2],m[3],m[4])):Length()<1)
end
local c=require('config/grid_placement_config').build_bounds
 test('new_build_bounds',c.min_x==-4096 and c.max_x==2048 and c.min_y==-3072 and c.max_y==3072)
local c=require('config/tree_config').spawn_point
 local p=Vector(c.x,c.y,c.z)
 test('resource_tree_position',c.x==646 and c.y==1366 and math.abs(GetGroundHeight(p,nil)-384)<4 and GridNav:IsTraversable(p) and not GridNav:IsBlocked(p))
 local preview=Entities:FindAllByClassname('prop_dynamic') or {}
 test('no_animated_editor_models',#preview==0,'count='..#preview)
 local hero=PlayerResource:GetSelectedHeroEntity(0)
 test('player_0_builder_spawn',hero and (hero:GetAbsOrigin()-Vector(396,1116,400)):Length2D()<128)
 print(string.format('[MAIN_MERGE] RESULT checked=%d failed=%d',checked,failed))
