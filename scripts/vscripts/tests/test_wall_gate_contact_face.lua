-- Exercise cached contact faces only for a real 192-wide opening fully
-- closed by the physical 256-square. Wider/offset passages are covered by
-- test_wall_gate_contact_layout.lua. No Dota session is used.
package.path='scripts/vscripts/?.lua;'..package.path
Vector=function(x,y,z) return {x=x,y=y,z=z or 384} end
GetGroundHeight=function() return 384 end
local geometry=require('systems/wall_navigation_geometry')
local navigation=require('systems/wall_navigation_service')
local terrain=function() return true end
local obstacles,created,removed,nav_queries={},0,0,0
local function covered(o,p)
    return not o.deleted and p.x>=o.p.x-64 and p.x<o.p.x+64
        and p.y>=o.p.y-64 and p.y<o.p.y+64
end
GridNav={
    IsTraversable=function(_,p) nav_queries=nav_queries+1;return terrain(p) end,
    IsBlocked=function(_,p)
        nav_queries=nav_queries+1
        for _,o in ipairs(obstacles) do if covered(o,p) then return true end end
        return false
    end,
}
SpawnEntityFromTableSynchronous=function(name,kv)
    assert(name=='point_simple_obstruction' and kv.StartDisabled==0)
    local o={p=kv.origin,IsNull=function(self) return self.deleted==true end}
    created=created+1;obstacles[#obstacles+1]=o;return o
end
DoEntFireByInstanceHandle=function(_,input) assert(input=='Disable') end
UTIL_Remove=function(o) assert(not o.deleted);o.deleted=true;removed=removed+1 end
local function entity(id,p)
    return {p=p,entindex=function() return id end,
        IsNull=function(self) return self.deleted==true end,
        GetAbsOrigin=function(self) return self.p end}
end
local function rotate(x,y,q)
    if q==0 then return x,y elseif q==1 then return y,-x
    elseif q==2 then return -x,-y else return -y,x end
end
local base=Vector(1280,4928,384)
local function point(x,y,q)
    x,y=rotate(x,y,q)
    return Vector(base.x+x,base.y+y,384)
end
local function corridor(q)
    return function(p)
        local _,y=rotate(p.x-base.x,p.y-base.y,(4-q)%4)
        return math.abs(y)<96
    end
end
local function expected(q,sign)
    local x,y=rotate(sign*184,0,q)
    if x~=0 then return x<0 and 1 or 2 end
    return y<0 and 3 or 4
end
local checks=0
for q=0,3 do
    terrain=corridor(q)
    local wall=entity(10+q,point(0,0,q))
    local _,_,gate,axis=geometry.seams(wall.p,terrain)
    assert(gate and axis==(q%2==0 and 1 or 2),'closed corridor lost its proven axis')
    local registered=navigation.create(wall)
    assert(#registered==4,'offset gate must retain the actual square body')
    local layout=navigation.contact_layout(wall)
    local center=layout.axis==1 and base.y or base.x
    assert(layout.gate and layout.center==center and layout.min==center-96 and layout.max==center+96,
        'registration must preserve actual world-space banks instead of snapping to the wall')
    for _,sign in ipairs({-1,1}) do
        for _,lateral in ipairs({-121,-8,40,88,136}) do
            local u=entity(100+checks,point(sign*184,lateral,q))
            assert(navigation.contact_face(wall,u)==expected(q,sign),
                'offset edge body was assigned to a sealed shoulder')
            checks=checks+1
        end
    end
    local u=entity(200+q,point(-184,-121,q))
    local before=nav_queries
    for _=1,100 do
        assert(navigation.contact_face(wall,u)==expected(q,-1))
        assert(navigation.contact_layout(wall)==layout)
    end
    assert(nav_queries==before,'cached gate face performed per-monster terrain queries')
    local center=entity(300+q,wall.p)
    assert(navigation.contact_face(wall,center)==nil,'gate center has no known approach end')
    local high=entity(400+q,Vector(u.p.x,u.p.y,577))
    assert(navigation.contact_face(wall,high)==nil,'unrelated elevation reused the gate face')
    navigation.clear(wall)
    assert(navigation.contact_face(wall,u)==nil,'cleared gate retained its corridor axis')
    assert(navigation.contact_layout(wall)==nil,'cleared gate retained its contact layout')
end

-- Open-floor registrations and unknown entities must preserve four-face AI.
terrain=function() return true end
local lawn=entity(500,Vector(0,0,384))
local outsider=entity(501,Vector(-184,-185,384))
local _,_,gate,axis=geometry.seams(lawn.p,terrain)
assert(not gate and axis==nil,'open floor invented a corridor direction')
assert(navigation.contact_face(lawn,outsider)==nil,'unregistered wall returned a contact face')
navigation.create(lawn)
assert(navigation.contact_face(lawn,outsider)==nil,'open floor constrained contact ownership')
assert(navigation.contact_layout(lawn)==nil,'open floor invented a gate contact layout')
assert(navigation.contact_face(nil,outsider)==nil and navigation.contact_face(lawn,nil)==nil)
assert(navigation.contact_face(lawn,{IsNull=function() return false end})==nil)
navigation.clear(lawn)

-- Entity indices are reusable; a new handle must never inherit old gate data.
terrain=corridor(0)
local first=entity(600,point(0,0,0))
local fifth=entity(601,point(-184,-121,0))
navigation.create(first)
assert(navigation.contact_face(first,fifth)==1)
local replacement=entity(600,point(0,0,0))
assert(navigation.contact_face(replacement,fifth)==nil,'reused index inherited an unregistered gate')
assert(navigation.contact_layout(replacement)==nil,'reused index inherited another native handle layout')
terrain=corridor(1)
replacement.p=point(0,0,1)
navigation.create(replacement)
assert(navigation.contact_face(first,fifth)==nil,'old handle read a replacement gate')
assert(navigation.contact_layout(first)==nil,'old handle read a replacement layout')
local rotated=entity(602,point(-184,-121,1))
assert(navigation.contact_face(replacement,rotated)==4,'replacement did not register its own axis')
navigation.clear(first)
assert(navigation.contact_face(replacement,rotated)==4,'stale handle cleared a replacement gate')
navigation.clear(replacement)
assert(navigation.contact_face(replacement,rotated)==nil)

-- A legacy/unknown gate snapshot cannot guess a direction; rebuild supplies it.
local original_seams=geometry.seams
geometry.seams=function(...)
    local offsets,bounds,known=original_seams(...)
    return offsets,bounds,known
end
terrain=corridor(0)
local legacy=entity(700,point(0,0,0))
navigation.create(legacy)
assert(navigation.contact_face(legacy,fifth)==nil,'unknown gate axis was guessed')
navigation.clear(legacy)
geometry.seams=original_seams

-- Native wall destruction can precede cleanup; invalid handles remain safe.
local dead=entity(800,point(0,0,0))
navigation.create(dead);dead.deleted=true
dead.entindex=function() error('deleted native handle must not be queried') end
assert(navigation.contact_face(dead,fifth)==nil)
assert(navigation.contact_layout(dead)==nil)
navigation.clear(dead)
navigation.clear_all()
assert(created==removed,'gate face registration leaked native obstruction entities')
print('WALL_GATE_CONTACT_FACE_PASS closed192_four_rotations both_ends bodies='..checks
    ..' stable_nav_queries=0 open_floor unknown_axis index_reuse clear dead_handle')
