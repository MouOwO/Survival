if not IsServer() or not IsInToolsMode() or GetMapName()~='template_map' then return end
local pass,fail=0,0
local function check(n,ok,detail) if ok then pass=pass+1 else fail=fail+1 end print('[CHALLENGE_NATIVE] '..(ok and 'PASS ' or 'FAIL ')..n..' '..tostring(detail or '')) end
local defs={{"05",-5248,10752},{"09",-5248,8704},{"08",-5248,6656},{"06",10624,2304},{"07",14336,2304}}
for _,r in ipairs({{"challenge_05_entry",-5248,10457,148},{"challenge_05_boss_spawn",-5248,10852,148},{"challenge_06_boss_spawn",10624,2404,148},{"challenge_06_entry",10624,2009,148},{"challenge_09_entry",-5248,8409,148},{"challenge_09_boss_spawn",-5248,8804,148},{"challenge_08_entry",-5248,6361,148},{"challenge_08_home",-5248,6696,148},{"challenge_08_boss_spawn",-5248,6756,148},{"challenge_08_spawn_01",-5093,6756,148},{"challenge_08_spawn_02",-5122.6025390625,6832.412109375,148},{"challenge_08_spawn_03",-5200.1025390625,6879.6372070312,148},{"challenge_08_spawn_04",-5295.8974609375,6879.6372070312,148},{"challenge_08_spawn_05",-5373.3974609375,6832.412109375,148},{"challenge_08_spawn_06",-5403,6756,148},{"challenge_08_spawn_07",-5373.3974609375,6679.587890625,148},{"challenge_08_spawn_08",-5295.8974609375,6632.3627929688,148},{"challenge_08_spawn_09",-5200.1025390625,6632.3627929688,148},{"challenge_08_spawn_10",-5122.6025390625,6679.587890625,148},{"challenge_07_entry",14336,2009,148},{"challenge_07_home",14336,2344,148},{"challenge_07_boss_spawn",14336,2404,148},{"challenge_07_spawn_01",14491,2404,148},{"challenge_07_spawn_02",14461.3974609375,2480.412109375,148},{"challenge_07_spawn_03",14383.8974609375,2527.6374511719,148},{"challenge_07_spawn_04",14288.1025390625,2527.6374511719,148},{"challenge_07_spawn_05",14210.6025390625,2480.412109375,148},{"challenge_07_spawn_06",14181,2404,148},{"challenge_07_spawn_07",14210.6025390625,2327.587890625,148},{"challenge_07_spawn_08",14288.1025390625,2280.3625488281,148},{"challenge_07_spawn_09",14383.8974609375,2280.3625488281,148},{"challenge_07_spawn_10",14461.3974609375,2327.587890625,148},{"challenge_06_home",10624,2344,148},{"challenge_05_home",-5248,10792,148},{"challenge_09_home",-5248,8744,148}}) do
 local e=Entities:FindByName(nil,r[1]);local p=e and e:GetAbsOrigin()
 check(r[1]..'.position',p and (p-Vector(r[2],r[3],r[4])):Length()<1)
 check(r[1]..'.nav',p and GridNav:IsTraversable(p) and not GridNav:IsBlocked(p))
 if p then check(r[1]..'.ground',math.abs(GetGroundHeight(p,nil)-128)<6,GetGroundHeight(p,nil)) end
end
for _,d in ipairs(defs) do
 local a=Entities:FindByName(nil,'challenge_'..d[1]..'_entry')
 local b=Entities:FindByName(nil,'challenge_'..d[1]..'_boss_spawn')
 local h=Entities:FindByName(nil,'challenge_'..d[1]..'_home')
 check(d[1]..'.entry_spawn_path',a and b and GridNav:CanFindPath(a:GetAbsOrigin(),b:GetAbsOrigin()))
 check(d[1]..'.home_path',a and h and GridNav:CanFindPath(a:GetAbsOrigin(),h:GetAbsOrigin()))
 for x=-480,480,96 do for y=-480,480,96 do local p=Vector(d[2]+x,d[3]+y,148);check(d[1]..'.core.'..x..'.'..y,GridNav:IsTraversable(p) and not GridNav:IsBlocked(p) and math.abs(GetGroundHeight(p,nil)-128)<6) end end
 for _,v in ipairs({{544,0},{-544,0},{0,544},{0,-544},{544,544},{-544,-544}}) do local p=Vector(d[2]+v[1],d[3]+v[2],128);check(d[1]..'.sea.'..v[1]..'.'..v[2],GridNav:IsBlocked(p) or not GridNav:IsTraversable(p)) end
 local unit=a and CreateUnitByName('npc_dota_creep_goodguys_melee',a:GetAbsOrigin(),false,nil,nil,DOTA_TEAM_GOODGUYS)
 if unit then unit.survival_hero_id='challenge_art_probe';local ok,err=require('systems/destination_validation_service').teleport(unit,b:GetAbsOrigin(),false);check(d[1]..'.teleport',ok and (unit:GetAbsOrigin()-b:GetAbsOrigin()):Length2D()<64,err);UTIL_Remove(unit) else check(d[1]..'.teleport',false) end
end
for _,d in ipairs(defs) do
 local a=Entities:FindByName(nil,'challenge_'..d[1]..'_playable_min')
 local b=Entities:FindByName(nil,'challenge_'..d[1]..'_playable_max')
 check(d[1]..'.design_1049',a and b and math.abs(b:GetAbsOrigin().x-a:GetAbsOrigin().x-1049)<0.01 and math.abs(b:GetAbsOrigin().y-a:GetAbsOrigin().y-1049)<0.01)
end
for i=1,#defs do for j=i+1,#defs do local a=Entities:FindByName(nil,'challenge_'..defs[i][1]..'_entry');local b=Entities:FindByName(nil,'challenge_'..defs[j][1]..'_entry');check(defs[i][1]..'.separate.'..defs[j][1],a and b and not GridNav:CanFindPath(a:GetAbsOrigin(),b:GetAbsOrigin())) end end
print(string.format('[CHALLENGE_NATIVE] SUMMARY passed=%d failed=%d',pass,fail))
