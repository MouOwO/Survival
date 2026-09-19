-- Read-only close-up geometry checks after pool/rim seam changes.
local map_name = GetMapName()
if not IsInToolsMode() or (map_name ~= 'survival_c6' and map_name ~= 'template_map') then return end
local cy = map_name == 'template_map' and 0 or 5376
local checked,failed=0,0
local function test(name,ok,detail)
 checked=checked+1 if not ok then failed=failed+1 end
 print('[C6_SEAM] '..(ok and 'PASS ' or 'FAIL ')..name..' '..(detail or ''))
end
local function point(x,y,r)
 for _=1,r or 0 do x,y=y,-x end
 local p=Vector(-1024+x,cy+y,0) p.z=GetGroundHeight(p,nil) return p
end
-- GetGroundHeight reads the navigation height field. Blocked steep banks are
-- absent from it, so use a real world collision trace for rock/root support.
local function surface(p,top)
 local t={startpos=Vector(p.x,p.y,top),endpos=Vector(p.x,p.y,-128)}
 TraceLine(t)
 return t.hit and t.pos and t.pos.z or -999
end
for r=0,3 do
 for _,x in ipairs({592,600,608,696,720}) do
  local p=point(x,0,r)
  local expected=4+20*math.max(0,math.min(1,(x-600)/96))
  test('water_join_'..r..'_'..x,math.abs(p.z-expected)<4 and GridNav:IsTraversable(p) and not GridNav:IsBlocked(p),string.format('ground=%.2f expected=%.2f',p.z,expected))
 end
 for _,y in ipairs({-480,480}) do
  local p=point(640,y,r)
  local z=surface(p,500)
  test('lower_bank_'..r..'_'..y,math.abs(z-194.37)<6,string.format('surface=%.2f nav=%.2f',z,p.z))
 end
end
local low,high=9999,-9999
for i=0,175 do
 local a=i*2*math.pi/176
 local p=point(3056*math.cos(a),3056*math.sin(a))
 local z=surface(p,300)
 low=math.min(low,z) high=math.max(high,z)
 -- The ring's trunk origins are 164; the shore must support all of them.
 test('rim_support_'..i,z>=164 and z<=224,string.format('surface=%.2f nav=%.2f',z,p.z))
end
print(string.format('[C6_SEAM] RIM ground_min=%.2f ground_max=%.2f trunk_origin=164',low,high))
print(string.format('[C6_SEAM] RESULT checked=%d failed=%d',checked,failed))
