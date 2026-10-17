-- Tools diagnostic self-test: a physical full row owns its overflow test.
-- A routing actor's desired face must neither invent nor hide a fifth body.
package.path='scripts/vscripts/?.lua;'..package.path
for _,name in ipairs({'systems/wall_navigation_service','systems/wall_navigation_geometry',
    'systems/wall_melee_contact','modifiers/modifier_enemy_wall_ai','core/json_encoder'}) do
    package.loaded[name]={}
end
local probe=assert(loadfile('scripts/vscripts/tests/wall_native_redesign_probe.lua'))()
local classify=assert(probe._front_row_overflow_for_test)
local probe_face=assert(probe._face_for_test)
local current_layout
package.loaded['systems/wall_navigation_service'].contact_layout=function() return current_layout end
local scene={wall={GetAbsOrigin=function() return {x=0,y=0} end}}
for _,layout in ipairs({{gate=false,axis=1},{gate=false,axis=2}}) do
    current_layout=layout
    for side,p in ipairs({{x=-184,y=44},{x=184,y=44},{x=44,y=-184},{x=44,y=184}}) do
        assert(probe_face(scene,p)==side,'open wall with stair-axis metadata must retain all four physical faces')
    end
end
current_layout={gate=true,axis=1}
assert(probe_face(scene,{x=-8,y=184})==1 and probe_face(scene,{x=8,y=-184})==2,
    'a genuinely sealed X-axis gate must retain its two physical approach ends')
current_layout={gate=true,axis=2}
assert(probe_face(scene,{x=184,y=-8})==3 and probe_face(scene,{x=-184,y=8})==4,
    'a genuinely sealed Y-axis gate must retain its two physical approach ends')
current_layout=nil
local function actor(id,x,y,side,locked)
    return {id=id,p={x=x,y=y},hull=32,side=side,ai={contact_locked=locked}}
end
local function fixture()
    return {actor(741,-3500.4089355469,5098.642578125,2,true),actor(1004,-3528,5204,2,true),
        actor(805,-3528,5292,2,true),actor(829,-3497.1572265625,5373.953125,2,true),
        actor(964,-3580,5064,3,true)}, {0,4,1,0}
end
-- Exact native west_tangent_plus128 frame, t9.966796875: the full east
-- destination face had4 owners; the nearby north row had only1. The old
-- diagnostic borrowed the former count while measuring against the latter.
local rows,locked=fixture()
rows[#rows+1]=actor(692,-3664.3356933594,5073.8911132813,2,false)
assert(classify(rows,locked)==0,'the real west corner route must not invent a fifth body on a different, unfilled row')
local distance=math.sqrt((rows[6].p.x-rows[5].p.x)^2+(rows[6].p.y-rows[5].p.y)^2)
assert(distance>64,'the reproduced native pair must remain physically separate')

-- A physically interleaved fifth body may target a different face. Requiring
-- a.side==b.side would hide this case. The retained48-unit forward range
-- complements the unchanged strict physical and swept-body acceptance.
rows,locked=fixture()
rows[#rows+1]=actor(200,-3575,5248,3,false)
assert(classify(rows,locked)==1,'a different target face must not hide a real fifth body in the full east row')
rows[6].side=2
assert(classify(rows,locked)==1,'same-target-face interleaving must also fail')
rows[6].p.x=-3436
assert(classify(rows,locked)==0,'a legal rear body92 behind the row must remain accepted')
rows[6].p.x=-3575;locked[2]=3
table.remove(rows,4)
assert(classify(rows,locked)==0,'an unfilled physical row must not use a neighbouring full-face count')

-- A real same-plane/forward fifth body is invalid regardless of its target.
for _,x in ipairs({-3528,-3536}) do
    rows,locked=fixture();rows[#rows+1]=actor(200,x,5248,3,false)
    local count,details=classify(rows,locked)
    assert(count==1 and details[1].face==2 and details[1].plane==-3528,
        'a same-plane or forward insertion must identify its actual full row')
end
-- The normal gap of a native blocked wedge can be47 while both physical
-- distances exceed64. A symmetric48 band must not call that forward passage.
rows,locked=fixture();rows[#rows+1]=actor(200,-3481,5248,3,false)
assert(math.sqrt(47^2+44^2)>64)
assert(classify(rows,locked)==0,'a physically blocked rear wedge is not through the front plane')
rows[6].p.x=-3525
assert(classify(rows,locked)==0,'a center more than2 behind the plane is still rear')
rows[6].p.x=-3526
assert(classify(rows,locked)==1,'retain the explicit2-unit plane tolerance')

-- Reproduce every outer-route record missed by the old target-face guard.
for _,p in ipairs({{-3512.3364257813,5012.1826171875},
    {-3504.5148925781,5005.0927734375},{-3467.8747558594,5021.1147460938},
    {-3457.2136230469,5014.7338867188},{-3480.7749023438,5013.8930664063},
    {-3452.8728027344,5029.1118164063}}) do
    rows,locked=fixture();rows[#rows+1]=actor(200,p[1],p[2],4,false)
    assert(classify(rows,locked)==0,'route outside actual row ends must stay accepted')
end

-- The actual native line curves because MOVE can stop early. Interpolation
-- must follow that line instead of borrowing one endpoint's normal plane.
rows,locked=fixture()
local tangent=5150
local curve=-3500.4089355469+(-3528+3500.4089355469)
    *(tangent-5098.642578125)/(5204-5098.642578125)
rows[#rows+1]=actor(200,curve,tangent,3,false)
local curved_count,curved_details=classify(rows,locked)
assert(curved_count==1 and math.abs(curved_details[1].plane-curve)<.0001,
    'actual front interpolation must identify the physical row at this tangent')

local rotate_face={[1]=3,[2]=4,[3]=2,[4]=1}
for turn=1,4 do
    rows,locked=fixture()
    rows[#rows+1]=actor(200,-3575,5248,3,false)
    for _=1,turn do
        local counts={0,0,0,0}
        for side=1,4 do counts[rotate_face[side]]=locked[side] end
        locked=counts
        for _,row in ipairs(rows) do
            row.p={x=-row.p.y,y=row.p.x};row.side=rotate_face[row.side]
        end
    end
    assert(classify(rows,locked)==1,'true physical-row overflow must survive every map orientation')
end
print('WALL_FRONT_ROW_ORACLE_PASS exact west corner and row-end routes accepted; same/forward/cross-target insertion detected; native rear wedge accepted; four orientations; interpolated actual row; strict raw/swept checks unchanged')
