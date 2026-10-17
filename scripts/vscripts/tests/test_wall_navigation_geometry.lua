package.path = "scripts/vscripts/?.lua;" .. package.path
Vector = function(x,y,z) return {x=x,y=y,z=z or 0} end
local geometry = require("systems/wall_navigation_geometry")
local passed, failures = 0, {}
local function check(name, fn)
    local ok, message = pcall(fn)
    if ok then passed=passed+1
    else failures[#failures+1]=name..": "..tostring(message) end
end
local function equal(actual, expected, detail)
    assert(actual==expected, (detail or "value").." expected="..tostring(expected).." actual="..tostring(actual))
end
local function rotate(x,y,q)
    if q==0 then return x,y elseif q==1 then return y,-x
    elseif q==2 then return -x,-y else return -y,x end
end
local function unrotate(x,y,q) return rotate(x,y,(4-q)%4) end
local widths={256,384,512,640,768}
local hulls={0,10,12,32,40,64,128}
local origin=Vector(1280,4928,384)
local function corridor(width,q)
    return function(p)
        local _,y=unrotate(p.x-origin.x,p.y-origin.y,q)
        return math.abs(y)<width*.5
    end
end
local function expected_extent(width) return width>256 and width<=384 and 256 or 128 end
local function expected_count(width) return width>256 and width<=384 and 8 or 4 end

for _,width in ipairs(widths) do for q=0,3 do
    check("seams "..width.." rotation "..q,function()
        local offsets,bounds,gate=geometry.seams(origin,corridor(width,q))
        equal(gate,width<=384,"only body and two bounded64 seams may close an opening")
        equal(#offsets,expected_count(width)-4,"extra native obstacle count")
        local extent=expected_extent(width)
        equal(bounds.min_x,-(q%2==0 and 128 or extent),"min x")
        equal(bounds.max_x,(q%2==0 and 128 or extent),"max x")
        equal(bounds.min_y,-(q%2==0 and extent or 128),"min y")
        equal(bounds.max_y,(q%2==0 and extent or 128),"max y")
        for _,offset in ipairs(offsets) do
            local normal,lateral=unrotate(offset.x,offset.y,q)
            equal(math.abs(normal),64,"shoulders never protrude into approach")
            assert(math.abs(lateral)>=192 and math.abs(lateral)<=320)
        end
    end)
end end

check("open lawn unchanged",function()
    local offsets,bounds,gate=geometry.seams(origin,function() return true end)
    equal(gate,false,"open ground cannot infer movement chords through corners")
    equal(#offsets,0);equal(bounds.min_x,-128);equal(bounds.max_y,128)
end)
check("single terrain bank unchanged",function()
    local offsets=geometry.seams(origin,function(p) return p.y-origin.y>-192 end)
    equal(#offsets,0)
end)
check("T junction stays open",function()
    local offsets=geometry.seams(origin,function(p)
        local x,y=p.x-origin.x,p.y-origin.y
        return math.abs(y)<192 or (x>=32 and y>0)
    end)
    equal(#offsets,0,"a side branch must not become a closed bank")
end)
check("front and rear cross sections must close",function()
    for _,open_normal in ipairs({-96,-32,32,96}) do
        local offsets=geometry.seams(origin,function(p)
            local x,y=p.x-origin.x,p.y-origin.y
            return math.abs(y)<192 or (x==open_normal and y>0)
        end)
        equal(#offsets,0,"one open strip prevents corridor classification")
    end
end)
check("oversized opening unchanged",function()
    equal(#geometry.seams(origin,corridor(1024,0)),0)
end)
check("staggered banks cannot close a side branch",function()
    local offsets=geometry.seams(origin,function(p)
        local x,y=p.x-origin.x,p.y-origin.y
        local half=x<0 and 192 or 256
        return math.abs(y)<half
    end)
    equal(#offsets,0,"different front and rear boundaries are rejected")
end)
check("off-center 384 keeps its real side route",function()
    local offsets,bounds,gate,axis,layout=geometry.seams(origin,function(p)
        local y=p.y-origin.y;return y>-128 and y<256
    end)
    equal(#offsets,0);equal(bounds.min_y,-128);equal(bounds.max_y,128)
    assert(not gate and axis==1 and layout and not layout.gate)
end)
check("two narrow bank slits close within the64 limit",function()
    for _,width in ipairs({280,380}) do
        local offsets,bounds,gate=geometry.seams(origin,corridor(width,0))
        equal(#offsets,4);equal(bounds.min_y,-256);equal(bounds.max_y,256)
        equal(gate,true)
    end
end)

check("opening beyond 768 maximum width stays unmodified",function()
    for _,width in ipairs({770,784,800,832,896,1024}) do
        local offsets,bounds=geometry.seams(origin,corridor(width,0))
        equal(#offsets,0,"over-limit continuous bank width "..width)
        equal(bounds.min_y,-128);equal(bounds.max_y,128)
    end
end)

local square={min_x=-128,max_x=128,min_y=-128,max_y=128}
for _,radius in ipairs(hulls) do
    check("square corners and crossings hull "..radius,function()
        local safe_radius=math.max(1,radius)
        for q=0,3 do
            local a,b=rotate(-400,20,q)
            local c,d=rotate(400,20,q)
            local restored=assert(geometry.outside(square,Vector(c,d,384),Vector(a,b,384),radius),"full crossing must restore entry side")
            local n,l=unrotate(restored.x,restored.y,q)
            equal(n,-128-safe_radius-2,"entry side never ejects through rear")
            equal(l,20)
            local corner=assert(geometry.outside(square,Vector(120,120,384),Vector(220,220,384),radius))
            assert(corner.x>=128+safe_radius or corner.y>=128+safe_radius,"square corner must expel overlapping hull")
            -- This cuts across the square corner while both endpoints are exterior.
            assert(geometry.outside(square,Vector(160,80,384),Vector(80,160,384),radius),"corner chord cannot skip blocking")
        end
        equal(geometry.outside(square,Vector(400,128+safe_radius+8,384),Vector(-400,128+safe_radius+8,384),radius),nil,"legal route outside face")
        equal(geometry.outside(square,Vector(-200-safe_radius,200+safe_radius,384),Vector(-200-safe_radius,20,384),radius),nil,"legal move around exterior corner")
        assert(geometry.outside(square,Vector(-120,0,384),Vector(-400,0,384),radius),"overlap preserves approach face")
        equal(geometry.outside(square,Vector(-400,0,384),nil,radius),nil,"distant unit has no correction")
    end)
end
check("tangent center path not crossing body",function()
    equal(geometry.outside(square,Vector(300,129,384),Vector(-300,129,384),0),nil)
end)
check("swept hull cannot cut round-expanded corners",function()
    assert(geometry.outside(square,Vector(-140,200,384),Vector(-200,140,384),64),"endpoints outside but swept circle crosses corner")
    equal(geometry.outside(square,Vector(-180,240,384),Vector(-240,180,384),64),nil,"true exterior diagonal remains legal")
end)
check("swept hull cannot cross face strips with exterior endpoints",function()
    assert(geometry.outside(square,Vector(200,150,384),Vector(-200,150,384),32))
    equal(geometry.outside(square,Vector(200,160,384),Vector(-200,160,384),32),nil,"exact tangent is not penetration")
end)

-- Mock native navigation models the complete 128-square point obstruction,
-- terrain and height independently, rather than mirroring helper internals.
local nav,obstacles,created,removed,spawn_calls,fail_call,throw_call,nav_queries
local terrain,height
local function covered(o,p)
    return not o.deleted and p.x>=o.p.x-64 and p.x<o.p.x+64
        and p.y>=o.p.y-64 and p.y<o.p.y+64
end
local function reset(width,q,cliff)
    package.loaded["systems/wall_navigation_service"]=nil
    nav=nil;obstacles={};created=0;removed=0;spawn_calls=0;fail_call=nil;throw_call=nil;nav_queries=0
    local opening=width and corridor(width,q or 0) or function() return true end
    terrain=cliff and function() return true end or opening
    height=cliff and function(p) return opening(p) and 384 or 128 end or function() return 384 end
    GridNav={IsTraversable=function(_,p) nav_queries=nav_queries+1;return terrain(p) end,
        IsBlocked=function(_,p)
            nav_queries=nav_queries+1
            for _,o in ipairs(obstacles) do if covered(o,p) then return true end end
            return false
        end}
    GetGroundHeight=function(p) return height(p) end
    SpawnEntityFromTableSynchronous=function(name,kv)
        equal(name,"point_simple_obstruction");equal(kv.StartDisabled,0);equal(kv.block_fow,0)
        spawn_calls=spawn_calls+1
        if spawn_calls==throw_call then error("injected native spawn exception") end
        if spawn_calls==fail_call then return nil end
        local o={p=kv.origin,name=kv.targetname}
        function o:IsNull() return self.deleted or false end
        function o:GetName() return self.name end
        obstacles[#obstacles+1]=o;created=created+1;return o
    end
    DoEntFireByInstanceHandle=function(_,input) equal(input,"Disable") end
    UTIL_Remove=function(o) assert(not o.deleted);o.deleted=true;removed=removed+1 end
    Entities={FindAllByClassname=function() return obstacles end}
    nav=require("systems/wall_navigation_service")
    return nav
end
local function wall(id,p)
    local u={p=p or Vector(origin.x,origin.y,origin.z)}
    function u:IsNull() return self.deleted or false end
    function u:entindex() return id end
    function u:GetAbsOrigin() return self.p end
    function u:SetSize(a,b) equal(a.x,-128);equal(b.y,128) end
    function u:RemoveModifierByName(name) equal(name,"modifier_invulnerable") end
    return u
end
local function clear_point(x,y,radius)
    local margin=math.max(0,radius-.01)
    for _,offset in ipairs({{0,0},{margin,0},{-margin,0},{0,margin},{0,-margin}}) do
        local p=Vector(x+offset[1],y+offset[2],384)
        if not GridNav:IsTraversable(p) or GridNav:IsBlocked(p) or math.abs(height(p)-384)>128 then return false end
    end
    return true
end
local function path_around(width,q,radius)
    local sx,sy=rotate(-512,0,q)
    local ex,ey=rotate(512,0,q)
    sx,sy=origin.x+sx,origin.y+sy;ex,ey=origin.x+ex,origin.y+ey
    assert(clear_point(sx,sy,radius) and clear_point(ex,ey,radius),"flood-fill endpoints must be reachable")
    local queue,visited,head={{sx,sy}},{[sx..":"..sy]=true},1
    while head<=#queue do
        local p=queue[head];head=head+1
        if p[1]==ex and p[2]==ey then return true end
        for _,delta in ipairs({{-32,0},{32,0},{0,-32},{0,32}}) do
            local x,y=p[1]+delta[1],p[2]+delta[2]
            local n,l=unrotate(x-origin.x,y-origin.y,q)
            local k=x..":"..y
            if math.abs(n)<=512 and math.abs(l)<=width*.5+64 and not visited[k] and clear_point(x,y,radius) then
                visited[k]=true;queue[#queue+1]={x,y}
            end
        end
    end
    return false
end
for _,width in ipairs(widths) do for q=0,3 do
    check("native gate "..width.." rotation "..q,function()
        reset(width,q)
        local w=wall(10+q)
        equal(#nav.create(w),expected_count(width),"only the four physical body tiles")
        equal(#nav.create(w),expected_count(width),"creation is idempotent")
        local before=created
        nav.approach(w,{GetAbsOrigin=function() return Vector(origin.x+900,origin.y,384) end})
        nav.approach(w,{GetAbsOrigin=function() return Vector(origin.x-900,origin.y,384) end})
        equal(created,before,"first monster direction never changes geometry")
        for _,radius in ipairs(hulls) do
            equal(path_around(width,q,radius),width*.5-expected_extent(width)>=2*math.max(1,radius),"physical side route for hull "..radius)
        end
        local nx,ny=rotate(-192,0,q)
        assert(clear_point(origin.x+nx,origin.y+ny,32),"attack approach remains free")
        nav.clear(w)
        equal(removed,created,"all tiles are removed")
        assert(path_around(width,q,32),"path reopens after wall removal")
        equal(nav.original_nav(origin),nil,"terrain cache released")
    end)
end end
-- A tangent displacement leaves its physical gap. No unseen shoulder may
-- widen the 256-square footprint, regardless of the incoming monster side.
for _,width in ipairs({256,384,640}) do for q=0,3 do for _,offset in ipairs({0,-64,64,-128,128,-192,192}) do
    check("physical width "..width.." offset "..offset.." rotation "..q,function()
        reset(width,q)
        local x,y=rotate(0,offset,q)
        local w=wall(1000+q*10+offset/64,Vector(origin.x+x,origin.y+y,384))
        local closes=width*.5+math.abs(offset)<=192
        local left=math.max(0,width*.5+offset-128)
        local right=math.max(0,width*.5-offset-128)
        equal(#nav.create(w),closes and 4+(left>0 and 2 or 0)+(right>0 and 2 or 0) or 4)
        local layout=nav.contact_layout(w)
        if layout then
            equal(layout.gate,width*.5+math.abs(offset)<=192)
            equal(layout.axis,q%2==0 and 1 or 2)
            local before=nav_queries
            for _=1,100 do equal(nav.contact_layout(w),layout) end
            equal(nav_queries,before,"cached layout must not query terrain")
        end
        if width<=384 and offset==0 then equal(path_around(width,q,32),false) end
        if width>384 or (width>=384 and offset~=0) or math.abs(offset)>=128 then
            assert(path_around(width,q,32),"physical side passage must stay available")
        end
        nav.clear(w);equal(nav.contact_layout(w),nil);equal(removed,created)
    end)
end end end


-- Native maps have another floor beyond a finite bank. Its presence at the
-- scan endpoint is not a branch in the doorway touching the wall footprint.
for q=0,3 do for _,thickness in ipairs({128,256}) do
    for _,offset in ipairs({-128,128,-192,192}) do
        check("finite bank "..thickness.." offset "..offset.." rotation "..q,function()
            reset(256,q)
            terrain=function(p)
                local _,lateral=unrotate(p.x-origin.x,p.y-origin.y,q)
                return math.abs(lateral)<128 or math.abs(lateral)>128+thickness
            end
            local x,y=rotate(0,offset,q)
            local w=wall(2000+q*10,Vector(origin.x+x,origin.y+y,384))
            nav.create(w)
            local layout=nav.contact_layout(w)
            if math.abs(offset)==128 then
                assert(layout and not layout.gate,"offset wall must preserve its finite-bank side passage")
                equal(layout.center,layout.axis==1 and origin.y or origin.x)
                equal(layout.min,layout.center-128);equal(layout.max,layout.center+128)
                equal(path_around(256,q,32),true,"native blockers must preserve the actual side gap")
            else
                equal(layout,nil,"finite banks cannot authorize sealing a third-cell gap")
                equal(path_around(256,q,32),true,"third-cell real passage must remain available")
            end
            nav.clear(w);equal(created,removed)
        end)
    end
end end

-- A thin bank can close a terrain cross-section but cannot safely receive a
-- rounded 128 native tile if that tile would cover its far-side floor.
for q=0,3 do for _,width in ipairs({280,384,640}) do
    for _,thickness in ipairs({32,128}) do
        check("native tile thin-bank guard "..thickness.." width "..width.." rotation "..q,function()
            reset(width,q)
            terrain=function(p)
                local _,lateral=unrotate(p.x-origin.x,p.y-origin.y,q)
                return math.abs(lateral)<width*.5 or math.abs(lateral)>width*.5+thickness
            end
            local w=wall(3000+q)
            nav.create(w)
            if thickness==32 then
                equal(nav.contact_layout(w),nil,"native tile cannot bridge a thin bank onto another floor")
                equal(#obstacles,4,"thin-bank rejection must retain only the actual wall footprint")
            else
                assert(nav.contact_layout(w),"a full-thickness bank remains eligible for sealing")
                equal(path_around(width,q,32),width*.5-expected_extent(width)>=64)
            end
            nav.clear(w);equal(created,removed)
        end)
    end
end end

-- A real upper landing is open court behind the wall and a descending384
-- stair in front. The final native64 stair cell meets the wall's front edge.
-- Its raw bank midpoint may be32 below the canonical world64 grid center.
for q=0,3 do for _,native_bias in ipairs({0,-32}) do
    for _,offset in ipairs({0,-64,64,-128,128,-192,192}) do
        check("stair mouth offset "..offset.." native bank bias "..native_bias.." rotation "..q,function()
            reset()
            local bias=native_bias*((q==0 or q==1) and 1 or -1)
            terrain=function(p)
                local n,l=unrotate(p.x-origin.x,p.y-origin.y,q)
                return n>=0 or math.abs(l-bias)<192
            end
            height=function(p)
                local n,l=unrotate(p.x-origin.x,p.y-origin.y,q)
                if n>=0 then return 385.5 end
                return math.abs(l-bias)<192 and 385.5+n*.5 or 0
            end
            local x,y=rotate(128,offset,q)
            local w=wall(4000+q,Vector(origin.x+x,origin.y+y,385.5))
            nav.create(w)
            local layout=nav.contact_layout(w)
            if math.abs(offset)<=128 then
                assert(layout and layout.stair_mouth,"a real descending mouth must not be mistaken for a flat T")
                equal(layout.center,layout.axis==1 and origin.y or origin.x,
                    "stair midpoint must align to the real world64 entrance center")
                equal(layout.bounds[layout.axis==1 and "min_x" or "min_y"],-128)
                equal(layout.bounds[layout.axis==1 and "max_x" or "max_y"],128,
                    "a touching bank must not invent a forward navigation row")
                for _,o in ipairs(obstacles) do
                    local n=select(1,unrotate(o.p.x-w.p.x,o.p.y-w.p.y,q))
                    assert(math.abs(n)==64,"stair mouth may add only the original wall-depth shoulders")
                end
                for lane=1,4 do
                    local along=layout.center+(lane-2.5)*64
                    local px=layout.axis==1 and w.p.x-184 or along
                    local py=layout.axis==1 and along or w.p.y-184
                    -- Both normal signs are safe for navigation; inspect the
                    -- actual rotated stair approach below instead of guessing.
                    local nx,ny=rotate(-184,0,q)
                    if layout.axis==1 then px=w.p.x+nx else py=w.p.y+ny end
                    for _,h in ipairs({{0,0},{30,0},{-30,0},{0,30},{0,-30}}) do
                        local p=Vector(px+h[1],py+h[2],385.5)
                        assert(GridNav:IsTraversable(p) and not GridNav:IsBlocked(p),
                            "all four native-padded front bodies must fit the real stair")
                    end
                end
            else equal(layout,nil,"a third-cell stair offset must preserve its side passage") end
            nav.clear(w);equal(created,removed)
        end)
    end
end end
for q=0,3 do for _,normal_shift in ipairs({-64,0,64}) do
    check("stair normal shift "..normal_shift.." rotation "..q,function()
        reset()
        terrain=function(p)
            local n,l=unrotate(p.x-origin.x,p.y-origin.y,q)
            return n>=0 or math.abs(l)<192
        end
        height=function(p)
            local n,l=unrotate(p.x-origin.x,p.y-origin.y,q)
            if n>=0 then return 385.5 end
            return math.abs(l)<192 and 385.5+n*.5 or 0
        end
        local x,y=rotate(128+normal_shift,0,q)
        local w=wall(4500+q,Vector(origin.x+x,origin.y+y,385.5))
        equal(#nav.create(w),8,"both64 seams should close at one-cell normal displacement")
        local layout=assert(nav.contact_layout(w))
        assert(layout.gate and layout.stair_mouth,"normal displacement must keep the proven stair mouth")
        equal(layout.stair_lead,normal_shift==64 and 64 or 0)
        for _,o in ipairs(obstacles) do
            local n=select(1,unrotate(o.p.x-w.p.x,o.p.y-w.p.y,q))
            equal(math.abs(n),64,"seam blockers must stay within original wall depth")
        end
        nav.clear(w);equal(created,removed)
    end)
end end
for q=0,3 do for _,kind in ipairs({"flat_T","remote_wall","stair_side_branch"}) do
    check("stair fallback rejects "..kind.." rotation "..q,function()
        reset()
        terrain=function(p)
            local n,l=unrotate(p.x-origin.x,p.y-origin.y,q)
            return n>=0 or math.abs(l)<192 or (kind=="stair_side_branch" and n< -64 and l>0)
        end
        height=function(p)
            local n,l=unrotate(p.x-origin.x,p.y-origin.y,q)
            if n>=0 or kind=="flat_T" then return 385.5 end
            return (math.abs(l)<192 or (kind=="stair_side_branch" and l>0)) and 385.5+n*.5 or 0
        end
        local x,y=rotate(kind=="remote_wall" and 256 or 128,0,q)
        local w=wall(5000+q,Vector(origin.x+x,origin.y+y,385.5))
        nav.create(w);equal(nav.contact_layout(w),nil,"stair proof cannot close a flat T, remote mouth or true side branch")
        equal(#obstacles,4,"rejected mouth must retain only the original square")
        nav.clear(w);equal(created,removed)
    end)
end end

check("height cliffs enclose otherwise traversable terrain",function()
    reset(512,0,true)
    local w=wall(40);equal(#nav.create(w),expected_count(512))
    equal(path_around(512,0,32),true)
    local outside=Vector(origin.x+32,origin.y+224,384)
    equal(nav.original_nav(outside),nil,"terrain outside the physical wall is never masked")
    nav.clear(w);equal(removed,created)
end)
check("non-grid high-ground edges seal small hull navigation",function()
    for _,width in ipairs({280,380}) do
        reset(width,0,true)
        local w=wall(41);equal(#nav.create(w),expected_count(width))
        for _,radius in ipairs({0,10,12,32}) do equal(path_around(width,0,radius),width*.5-expected_extent(width)>=2*math.max(1,radius),"real height-bank slit hull "..radius) end
        nav.clear(w);equal(removed,created)
    end
end)
check("overlap preserves body and shoulder refs",function()
    reset(512,0)
    local first,second=wall(51),wall(52)
    equal(#nav.create(first),expected_count(512));equal(#nav.create(second),expected_count(512))
    local shoulder=Vector(origin.x+32,origin.y+32,384)
    assert(GridNav:IsBlocked(shoulder))
    equal(select(1,nav.original_nav(shoulder)),true)
    equal(select(2,nav.original_nav(shoulder)),false,"second owner does not cache first owner's obstacle")
    nav.clear(first);assert(GridNav:IsBlocked(shoulder));equal(select(2,nav.original_nav(shoulder)),false)
    nav.clear(second);equal(nav.original_nav(shoulder),nil);equal(removed,created)
end)
check("unrelated existing obstacle is retained",function()
    reset()
    local unrelated=SpawnEntityFromTableSynchronous("point_simple_obstruction",{origin=Vector(origin.x+512,origin.y,384),targetname="map_static_existing",StartDisabled=0,block_fow=0})
    local w=wall(60);equal(#nav.create(w),4)
    nav.clear_all();assert(not unrelated.deleted,"cleanup must leave map-owned obstruction")
    equal(nav.original_nav(unrelated.p),nil,"unrelated blocker is never masked")
    assert(GridNav:IsBlocked(unrelated.p))
end)
check("lost obstacle rebuild restores only the physical square",function()
    reset(512,0)
    local w=wall(61);local initial=nav.create(w)
    UTIL_Remove(initial[3].entity)
    local recovered=nav.create(w)
    equal(#recovered,expected_count(512));equal(path_around(512,0,0),true,"restored body must not fill real side passages")
    nav.clear(w);equal(removed,created,"stale cells released before rebuilding")
end)
check("VM reload cleanup retires owned orphan tiles",function()
    reset(512,0)
    local w=wall(62);nav.create(w)
    package.loaded["systems/wall_navigation_service"]=nil
    nav=require("systems/wall_navigation_service")
    nav.clear_all();equal(removed,created,"old native tiles remain identifiable after table loss")
    equal(nav.original_nav(origin),nil)
end)
check("late removal accepts wall with invalid native handle",function()
    reset(512,0)
    local w=wall(63);nav.create(w);w.deleted=true
    function w:entindex() error("native wall already removed") end
    nav.clear(w);equal(removed,created);equal(nav.original_nav(origin),nil)
end)
for _,failed in ipairs({1,2,3,4}) do
    check("nil spawn rollback at tile "..failed,function()
        reset(512,0);fail_call=failed
        local w=wall(70)
        equal(pcall(nav.create,w),false,"injected failed spawn must be reported")
        equal(removed,created,"previous tiles rolled back")
        equal(nav.original_nav(origin),nil)
        equal(nav.original_nav(Vector(origin.x+32,origin.y+160,384)),nil,"shoulder refs released")
        fail_call=nil;equal(#nav.create(w),expected_count(512),"retry creates full geometry")
        nav.clear(w);equal(removed,created)
    end)
end
check("native exception spawn rollback has no orphan refs",function()
    reset(512,0);throw_call=3
    local w=wall(80);equal(pcall(nav.create,w),false)
    equal(removed,created)
    for x=-352,352,64 do for y=-352,352,64 do
        equal(nav.original_nav(Vector(origin.x+x,origin.y+y,384)),nil,"exception cannot leak cached refs")
    end end
    throw_call=nil;equal(#nav.create(w),expected_count(512));nav.clear(w);equal(removed,created)
end)
check("body guard corrections preserve legal units",function()
    reset(256,0);local w=wall(90);nav.create(w)
    local u={p=Vector(origin.x+400,origin.y,384),moved=0}
    function u:IsNull() return false end
    function u:GetAbsOrigin() return self.p end
    function u:GetHullRadius() return 32 end
    function u:SetAbsOrigin(p) self.p=p;self.moved=self.moved+1 end
    assert(nav.enforce_boundary(w,u,Vector(origin.x-400,origin.y,384)))
    equal(u.p.x,origin.x-162);equal(u.moved,1)
    u.p=Vector(origin.x+400,origin.y+200,384)
    local queries_before=nav_queries
    equal(nav.enforce_boundary(w,u,Vector(origin.x-400,origin.y+200,384)),false)
    equal(u.moved,1,"legal corner route never teleports")
    equal(nav_queries,queries_before,"normal guard does no native navigation work")
    u.p=Vector(origin.x,origin.y,800)
    equal(nav.enforce_boundary(w,u,Vector(origin.x-400,origin.y,800)),false,"other height layer is unaffected")
    nav.clear(w)
end)
check("open floor observed chord around outer corner stays legal",function()
    reset();local w=wall(92);nav.create(w)
    local previous=Vector(origin.x-162,origin.y+80,384)
    local u={p=Vector(origin.x-80,origin.y+162,384),moved=0}
    function u:IsNull() return false end
    function u:GetAbsOrigin() return self.p end
    function u:GetHullRadius() return 32 end
    function u:SetAbsOrigin(p) self.p=p;self.moved=self.moved+1 end
    local queries_before=nav_queries
    equal(nav.enforce_boundary(w,u,previous),false,"0.5 second observation can hide a legal corner turn")
    equal(u.moved,0);equal(nav_queries,queries_before,"legal open-floor movement does no native work")
    equal(u.p.x,origin.x-80);equal(u.p.y,origin.y+162)
    nav.clear(w)
end)
check("open floor actual hull overlap still restores previous face",function()
    reset();local w=wall(93);nav.create(w)
    local previous=Vector(origin.x-162,origin.y+80,384)
    local u={p=Vector(origin.x-120,origin.y+20,384),moved=0}
    function u:IsNull() return false end
    function u:GetAbsOrigin() return self.p end
    function u:GetHullRadius() return 32 end
    function u:SetAbsOrigin(p) self.p=p;self.moved=self.moved+1 end
    assert(nav.enforce_boundary(w,u,previous),"all walls reject actual current square/hull penetration")
    equal(u.p.x,origin.x-162);equal(u.p.y,origin.y+20);equal(u.moved,1)
    nav.clear(w)
end)
check("blocked projected point restores legal previous position",function()
    reset();local w=wall(91);nav.create(w)
    local previous=Vector(origin.x-400,origin.y,384)
    local projected=Vector(origin.x-162,origin.y,384)
    terrain=function(p) return math.abs(p.x-projected.x)>8 or math.abs(p.y-projected.y)>8 end
    local u={p=Vector(origin.x,origin.y,384),moved=0}
    function u:IsNull() return false end
    function u:GetAbsOrigin() return self.p end
    function u:GetHullRadius() return 32 end
    function u:SetAbsOrigin(p) self.p=p;self.moved=self.moved+1 end
    assert(nav.enforce_boundary(w,u,previous));equal(u.p.x,previous.x);equal(u.p.y,previous.y)
    u.p=Vector(origin.x,origin.y,384);terrain=function() return false end
    equal(nav.enforce_boundary(w,u,previous),false,"no legal previous point cannot report correction")
    equal(u.moved,1,"no unsafe fallback movement")
    nav.clear(w)
end)

if #failures>0 then
    for _,message in ipairs(failures) do print("WALL_NAV_GEOMETRY_FAIL "..message) end
    error("wall navigation geometry failures="..#failures.." passed="..passed)
end
print("WALL_NAVIGATION_GEOMETRY_PASS cases="..passed.." 4 directions, physical256 body plus both seams<=64 only, tangent offsets keep real gaps, hull0-128, finite/thin banks, corner crossings, legal routes, height cliffs, refs and spawn rollback")
