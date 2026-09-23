if not IsServer() or not IsInToolsMode() or GetMapName()~='template_map' then return end
local pass,fail=0,0
local function check(n,ok,detail) if ok then pass=pass+1 else fail=fail+1 end print('[CHALLENGE_ART] '..(ok and 'PASS ' or 'FAIL ')..n..' '..tostring(detail or '')) end
local defs={{"05",-5248,10752},{"09",-5248,8704},{"08",-5120,6656},{"06",10624,2304},{"07",14336,2304}}
for _,r in ipairs({{"challenge_05_entry",-5248,10457,148},{"challenge_05_boss_spawn",-5248,10852,148},{"challenge_06_boss_spawn",10624,2404,148},{"challenge_06_entry",10624,2009,148},{"challenge_09_entry",-5248,8409,148},{"challenge_09_boss_spawn",-5248,8804,148},{"challenge_08_entry",-5120,6361,148},{"challenge_08_home",-5120,6696,148},{"challenge_08_boss_spawn",-5120,6756,148},{"challenge_08_spawn_01",-4965,6756,148},{"challenge_08_spawn_02",-4994.602365871883,6832.412082798021,148},{"challenge_08_spawn_03",-5072.102365871883,6879.63734711837,148},{"challenge_08_spawn_04",-5167.897634128117,6879.63734711837,148},{"challenge_08_spawn_05",-5245.397634128117,6832.412082798021,148},{"challenge_08_spawn_06",-5275,6756,148},{"challenge_08_spawn_07",-5245.397634128117,6679.587917201979,148},{"challenge_08_spawn_08",-5167.897634128117,6632.36265288163,148},{"challenge_08_spawn_09",-5072.102365871883,6632.36265288163,148},{"challenge_08_spawn_10",-4994.602365871883,6679.587917201979,148},{"challenge_07_entry",14336,2009,148},{"challenge_07_home",14336,2344,148},{"challenge_07_boss_spawn",14336,2404,148},{"challenge_07_spawn_01",14491,2404,148},{"challenge_07_spawn_02",14461.397634128118,2480.4120827980214,148},{"challenge_07_spawn_03",14383.897634128118,2527.63734711837,148},{"challenge_07_spawn_04",14288.102365871882,2527.63734711837,148},{"challenge_07_spawn_05",14210.602365871882,2480.4120827980214,148},{"challenge_07_spawn_06",14181,2404,148},{"challenge_07_spawn_07",14210.602365871882,2327.5879172019786,148},{"challenge_07_spawn_08",14288.102365871882,2280.36265288163,148},{"challenge_07_spawn_09",14383.897634128118,2280.36265288163,148},{"challenge_07_spawn_10",14461.397634128118,2327.5879172019786,148},{"challenge_06_home",10624,2344,148},{"challenge_05_home",-5248,10792,148},{"challenge_09_home",-5248,8744,148}}) do
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
 for x=-192,192,96 do for y=-192,192,96 do local p=Vector(d[2]+x,d[3]+y,148);check(d[1]..'.core.'..x..'.'..y,GridNav:IsTraversable(p) and not GridNav:IsBlocked(p) and math.abs(GetGroundHeight(p,nil)-128)<6) end end
 for _,v in ipairs({{700,0},{-700,0},{0,700},{0,-700}}) do local p=Vector(d[2]+v[1],d[3]+v[2],128);check(d[1]..'.sea.'..v[1]..'.'..v[2],GridNav:IsBlocked(p) or not GridNav:IsTraversable(p)) end
 local unit=a and CreateUnitByName('npc_dota_creep_goodguys_melee',a:GetAbsOrigin(),false,nil,nil,DOTA_TEAM_GOODGUYS)
 if unit then unit.survival_hero_id='challenge_art_probe';local ok,err=require('systems/destination_validation_service').teleport(unit,b:GetAbsOrigin(),false);check(d[1]..'.teleport',ok and (unit:GetAbsOrigin()-b:GetAbsOrigin()):Length2D()<64,err);UTIL_Remove(unit) else check(d[1]..'.teleport',false) end
end
for i=1,#defs do for j=i+1,#defs do local a=Entities:FindByName(nil,'challenge_'..defs[i][1]..'_entry');local b=Entities:FindByName(nil,'challenge_'..defs[j][1]..'_entry');check(defs[i][1]..'.separate.'..defs[j][1],a and b and not GridNav:CanFindPath(a:GetAbsOrigin(),b:GetAbsOrigin())) end end
print(string.format('[CHALLENGE_ART] SUMMARY passed=%d failed=%d',pass,fail))
