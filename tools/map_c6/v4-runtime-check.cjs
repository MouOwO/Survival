// Build an explicit tools-only probe from the actual map placement manifest.
const fs=require('fs'),path=require('path');
const root=path.resolve(__dirname,'../..'),m=require('../../output/map_layout_v4/manifest.json');
const q=v=>JSON.stringify(v);
const markers=m.markers.map(r=>`{${q(r.name)},${r.origin.join(',')}}`).join(',\n');
const routes=m.fields.filter(f=>f.spawn).map(f=>`{${q(f.id)},${f.spawn.join(',')},${f.center.join(',')}}`).join(',\n');
fs.writeFileSync(path.join(root,'scripts/vscripts/tests/map_c6_layout_v4_check.lua'),`-- Generated from the actual V4 manifest; run explicitly in a local tools game.
if not IsServer() or not IsInToolsMode() or GetMapName() ~= 'template_map' then return end
local pass,fail=0,0
local function check(name,ok,detail)
 if ok then pass=pass+1 else fail=fail+1 end
 print('[LAYOUT_V4] '..(ok and 'PASS ' or 'FAIL ')..name..' '..tostring(detail or ''))
end
local list={${markers}}
for _,r in ipairs(list) do
 local e=Entities:FindByName(nil,r[1]);local p=e and e:GetAbsOrigin()
 check(r[1]..'.location',p and (p-Vector(r[2],r[3],r[4])):Length()<1)
 check(r[1]..'.nav',p and GridNav:IsTraversable(p) and not GridNav:IsBlocked(p))
 if p then check(r[1]..'.floor',GetGroundHeight(p,nil)>-1,GetGroundHeight(p,nil)) end
end
for _,r in ipairs({${routes}}) do
 local a=Vector(r[2],r[3],128);local b=Vector(r[4],r[5],128)
 check(r[1]..'.route',GridNav:CanFindPath(a,b))
 check(r[1]..'.level',math.abs(GetGroundHeight(a,nil)-GetGroundHeight(b,nil))<2)
 for step=0,12 do local p=a+(b-a)*(step/12);check(r[1]..'.lane_'..step,GridNav:IsTraversable(p) and not GridNav:IsBlocked(p)) end
end
local resolver=require('systems/player_room_locations')
for p=0,3 do
 local e=Entities:FindByName(nil,'player_'..p..'_hero_spawn')
 local unit=e and CreateUnitByName('npc_dota_creep_goodguys_melee',e:GetAbsOrigin(),false,nil,nil,DOTA_TEAM_GOODGUYS)
 if unit then
  unit.survival_hero_id='layout_v4_probe'
  for _,id in ipairs({'challenge_01_room','challenge_02_room','challenge_03_room','challenge_04_room','endless_cycle_sanctum'}) do
   local row=resolver.resolve(id,p);local point=Entities:FindByName(nil,row.entry_target_name)
   local ok,err=require('systems/destination_validation_service').teleport(unit,point:GetAbsOrigin(),false)
   check('player_'..p..'.teleport.'..id,ok and (unit:GetAbsOrigin()-point:GetAbsOrigin()):Length2D()<64,err)
   for _,n in ipairs(row.spawn_target_names) do local spawn=Entities:FindByName(nil,n);check('player_'..p..'.spawn_path.'..n,spawn and GridNav:CanFindPath(point:GetAbsOrigin(),spawn:GetAbsOrigin())) end
  end
  UTIL_Remove(unit)
 else check('player_'..p..'.probe',false) end
 local b=Entities:FindByName(nil,'player_'..p..'_builder_spawn')
 check('central.builder_'..p,b and math.abs(GetGroundHeight(b:GetAbsOrigin(),nil)-384)<2)
 local gate=Entities:FindByName(nil,'c6_player_'..p..'_entrance')
 check('central.route_'..p,gate and GridNav:CanFindPath(Vector(-1024,4096,16),gate:GetAbsOrigin()))
end
for _,pair in ipairs({{'player_0_challenge_01_entry','player_0_challenge_02_entry'},{'player_0_challenge_01_entry','player_1_challenge_01_entry'},{'player_2_challenge_01_entry','player_3_challenge_01_entry'},{'v4_volcanic_1_entry','v4_volcanic_2_entry'},{'v4_southwest_a_field_1_center','v4_southwest_b_field_1_center'}}) do
 local a=Entities:FindByName(nil,pair[1]);local b=Entities:FindByName(nil,pair[2]);check('isolation.'..pair[1],a and b and not GridNav:CanFindPath(a:GetAbsOrigin(),b:GetAbsOrigin()))
end
for _,id in ipairs({'06','07'}) do
 local a=Entities:FindByName(nil,'challenge_'..id..'_entry')
 local b=Entities:FindByName(nil,'challenge_'..id..'_boss_spawn')
 local h=Entities:FindByName(nil,'challenge_'..id..'_home')
 check('east_challenge_'..id..'.route',a and b and GridNav:CanFindPath(a:GetAbsOrigin(),b:GetAbsOrigin()))
 check('east_challenge_'..id..'.home',a and h and GridNav:CanFindPath(a:GetAbsOrigin(),h:GetAbsOrigin()))
 for _,name in ipairs({'v4_northeast_field_4_center','v4_east_mode_field_1_center','v4_volcanic_1_entry'}) do
  local other=Entities:FindByName(nil,name)
  check('east_challenge_'..id..'.sea_gap.'..name,a and other and not GridNav:CanFindPath(a:GetAbsOrigin(),other:GetAbsOrigin()))
 end
 local unit=a and CreateUnitByName('npc_dota_creep_goodguys_melee',a:GetAbsOrigin(),false,nil,nil,DOTA_TEAM_GOODGUYS)
 if unit then
  unit.survival_hero_id='layout_v4_probe'
  local ok,err=require('systems/destination_validation_service').teleport(unit,b:GetAbsOrigin(),false)
  check('east_challenge_'..id..'.teleport',ok and (unit:GetAbsOrigin()-b:GetAbsOrigin()):Length2D()<64,err)
  UTIL_Remove(unit)
 else check('east_challenge_'..id..'.teleport',false) end
end
local ice=Entities:FindByName(nil,'challenge_06_entry')
local molten=Entities:FindByName(nil,'challenge_07_entry')
check('east_challenges.separate',ice and molten and not GridNav:CanFindPath(ice:GetAbsOrigin(),molten:GetAbsOrigin()))
print(string.format('[LAYOUT_V4] SUMMARY passed=%d failed=%d',pass,fail))
`);
console.log('Generated V4 runtime marker, path, teleport and isolation checks.');
