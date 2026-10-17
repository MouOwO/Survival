-- Run with tools/map_c6/prepare-ai-check.cjs and the generated Tools-only script.
-- Each module is loaded in a separate sandbox; no live entities/globals change.
-- Direct Lua execution must also exercise the current contact allocator. The
-- historical Tools function below compares the retired FIFO implementation;
-- merely returning that function used to make a standalone run falsely green.
if type(IsInToolsMode) ~= 'function' then
    local clock,paths,nav_queries,body_queries=0,0,0,0
    local function vector(x,y,z) return {x=x,y=y,z=z or 384} end
    local function distance(a,b) return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2) end
    local actors={}
    local function entity(id,face,normal,lateral,radius)
        local p=face==1 and vector(-normal,lateral) or face==2 and vector(normal,lateral)
            or face==3 and vector(lateral,-normal) or vector(lateral,normal)
        local u={p=p,radius=radius or 32}
        function u:entindex() return id end
        function u:IsNull() return self.removed==true end
        function u:IsAlive() return not self.dead end
        function u:GetAbsOrigin() return self.p end
        function u:GetHullRadius() return self.radius end
        function u:GetPaddedCollisionRadius() return self.radius+10 end
        function u:GetTeamNumber() return 3 end
        function u:SetHullRadius() error('cache observation must never resize a body') end
        function u:SetAbsOrigin() error('cache observation must never move a body') end
        actors[#actors+1]=u
        return u
    end
    local env=setmetatable({Vector=vector,GameRules={GetGameTime=function() return clock end},
        GetGroundHeight=function() return 384 end,
        DOTA_UNIT_TARGET_TEAM_BOTH=3,DOTA_UNIT_TARGET_BASIC=1,DOTA_UNIT_TARGET_HERO=2,
        DOTA_UNIT_TARGET_FLAG_INVULNERABLE=1,DOTA_UNIT_TARGET_FLAG_MAGIC_IMMUNE_ENEMIES=2,FIND_ANY_ORDER=0,
        require=function(name)
            assert(name=='systems/wall_navigation_service','unexpected contact dependency')
            return {}
        end,
        GridNav={IsTraversable=function() nav_queries=nav_queries+1;return true end,
            IsBlocked=function() nav_queries=nav_queries+1;return false end,
            FindPathLength=function(_,a,b) paths=paths+1;return distance(a,b) end},
        FindUnitsInRadius=function(_,point,_,radius)
            assert(radius==512,'body cache must remain local to this wall')
            body_queries=body_queries+1
            local result={}
            for _,u in ipairs(actors) do
                if u:IsAlive() and distance(u.p,point)<=radius then result[#result+1]=u end
            end
            return result
        end},{__index=_G})
    local chunk=assert(loadfile('scripts/vscripts/systems/wall_melee_contact.lua'))
    setfenv(chunk,env)
    local contact=chunk()
    local wall=entity(1,1,0,0,128)
    local fronts,lanes={}, {-132,-44,44,132}
    for face=1,4 do for lane=1,4 do
        local u=entity(face*10+lane,face,400,lanes[lane])
        local plan=assert(contact.resolve(wall,u,face))
        assert(plan.claimed and u.radius==32)
        u.p=plan.point;assert(contact.settle(wall,u,plan.point))
        fronts[#fronts+1]=u
    end end
    local waiters,goals={},{}
    -- These actors are query clients for cache complexity, not a simulated
    -- birth/physics crowd. Full native movement is covered by four-face/live tests.
    for index=1,400 do
        local face=(index-1)%4+1
        local lane=math.floor((index-1)/4)%4+1
        local u=entity(1000+index,face,400,lanes[lane]);u.face=face
        local plan=assert(contact.resolve(wall,u,face))
        assert(not plan.claimed and u.radius==32)
        waiters[index],goals[index]=u,plan.point
    end
    local before_paths,before_nav,before_bodies=paths,nav_queries,body_queries
    for pass=1,30 do
        clock=pass*.05
        for index,u in ipairs(waiters) do
            local plan=assert(contact.resolve(wall,u,u.face))
            assert(not plan.claimed and plan.point==goals[index] and u.radius==32)
        end
    end
    assert(paths==before_paths and nav_queries==before_nav and body_queries==before_bodies,
        'unchanged full contacts must not run paths, terrain or body queries per waiter')
    for _,u in ipairs(fronts) do assert(contact.resolve(wall,u).claimed) end
    clock=2.1
    for _,u in ipairs(fronts) do assert(contact.resolve(wall,u).claimed) end
    before_paths,before_nav,before_bodies=paths,nav_queries,body_queries
    for _,u in ipairs(waiters) do assert(not contact.resolve(wall,u,u.face).claimed) end
    assert(paths==before_paths and body_queries==before_bodies,
        'expired wait geometry must refresh terrain only, without paths or body scans')
    assert(nav_queries>before_nav and nav_queries-before_nav<=16*5*2,
        'terrain expiry must refresh at most sixteen lane goals, not four hundred waiters')
    local dead=fronts[2];dead.dead=true
    clock=2.2
    local replacement=waiters[5] -- Nearest already-observed waiter on face1/lane2.
    local refill=assert(contact.resolve(wall,replacement,1))
    assert(refill.claimed and refill.point.y==-44 and replacement.radius==32,
        'death must invalidate a cached full face immediately and admit one replacement')
    contact.clear(wall:entindex())
    local new_owner=entity(2001,1,400,-44)
    assert(contact.resolve(wall,new_owner,1).claimed,'clear must discard all cached reservations')
    contact.reset()
    local new_wall=entity(1,1,0,0,128)
    assert(contact.resolve(new_wall,entity(2002,1,400,-44),1).claimed,
        'reset and wall-handle reuse must start a fresh cache lifecycle')
    print('WALL_ENGAGEMENT_CACHE_PASS current_allocator faces=4 contacts=16 waiters=400 updates=30'
        ..' stable_paths=0 stable_nav=0 stable_body_queries=0 bounded_ttl_refresh death_refill clear reset')
end
return function(sources)
    local function sandbox(source)
        local now, resolves, sorts = 0, 0, 0
        local entities = {}
        local tables = {}
        for k,v in pairs(table) do tables[k]=v end
        tables.sort = function(...) sorts=sorts+1 return table.sort(...) end
        local env=setmetatable({table=tables,GameRules={GetGameTime=function() return now end},
            EntIndexToHScript=function(i) resolves=resolves+1 return entities[i] end},{__index=_G})
        local module=assert(loadstring(source))
        setfenv(module,env)
        local M=module()
        local function entity(i,x,y)
            local u={index=i,live=true,p=Vector(x,y,0)}
            function u:entindex() return self.index end
            function u:IsNull() return false end
            function u:IsAlive() return self.live end
            function u:GetAbsOrigin() return self.p end
            function u:GetForwardVector() return Vector(0,1,0) end
            entities[i]=u
            return u
        end
        return M,entity,function(t) now=t end,function(reset)
            local r,s=resolves,sorts
            if reset then resolves,sorts=0,0 end
            return r,s
        end
    end
    local function scenario(source)
        local M,entity,clock=sandbox(source)
        local wall,wall2=entity(1,0,0),entity(2,3000,0)
        local units,trace={},{}
        local function record(p,slot,row)
            trace[#trace+1]=p and string.format('%.3f,%.3f,%.3f:%s:%s',p.x,p.y,p.z,tostring(slot),tostring(row)) or 'nil'
        end
        for i=1,16 do units[i]=entity(i+10,(i%4)*32,1200) end
        for i,u in ipairs(units) do trace[#trace+1]=tostring(M.claim(wall,u)) end
        for i=5,16 do record(M.queue_position(wall,units[i])) end
        -- Removal invalidates cached FIFO ranks in the same frame.
        M.release(1,units[6]:entindex())
        record(M.queue_position(wall,units[10]))
        units[1].live=false
        trace[#trace+1]=tostring(M.claim(wall,units[5]))
        record(M.queue_position(wall,units[10]))
        -- Unannounced deletions are discovered at the next server frame.
        units[8].live=false clock(1)
        record(M.queue_position(wall,units[10]))
        M.release(1,units[10]:entindex())
        trace[#trace+1]=tostring(M.claim(wall2,units[10]))
        record(M.queue_position(wall,units[16]))
        record(M.queue_position(wall,units[6])) -- rejoins at the tail
        wall.live=false
        trace[#trace+1]=tostring(M.claim(wall,units[7]))
        M.release(1,units[7]:entindex())
        wall.live=true
        trace[#trace+1]=tostring(M.claim(wall,units[7]))
        M.reset()
        trace[#trace+1]=tostring(M.claim(wall2,units[16]))
        record(M.position(wall2,2,3))
        return table.concat(trace,'|')
    end
    -- Compare caching with identical geometry; the wall radius intentionally shrank.
    local before_geometry = sources.before:gsub('local NORMAL_OFFSET = 288', 'local NORMAL_OFFSET = 176')
    assert(scenario(before_geometry)==scenario(sources.after),'slot/queue behavior changed')
    print('[C6_AI_CHECK] PASS FIFO, arrivals, release, death, promotion, retarget, reset')
    local function bench(source,count)
        local M,entity,clock,counters=sandbox(source)
        local wall,units=entity(1,0,0),{}
        for i=1,count do
            local u=entity(i+10,(i%4)*32,1200) units[i]=u
            if not M.claim(wall,u) then M.queue_position(wall,u) end
        end
        counters(true)
        local timer=os and os.clock
        local start=timer and timer() or 0
        for step=1,30 do
            clock(step*.5)
            for _,u in ipairs(units) do if not M.claim(wall,u) then M.queue_position(wall,u) end end
        end
        local elapsed=timer and (timer()-start)*1000 or -1
        local resolves,sorts=counters()
        return elapsed,resolves,sorts
    end
    for _,count in ipairs({100,200,400}) do
        local old_ms,old_resolves,old_sorts=bench(sources.before,count)
        local new_ms,new_resolves,new_sorts=bench(sources.after,count)
        assert(new_sorts==0,'unchanged queue must not be sorted repeatedly')
        assert(new_resolves<old_resolves/4,'waiter cleanup was not shared')
        print(string.format('[C6_AI_CHECK] count=%d updates=30 before_ms=%.3f after_ms=%.3f before_resolves=%d after_resolves=%d before_sorts=%d after_sorts=%d',count,old_ms,new_ms,old_resolves,new_resolves,old_sorts,new_sorts))
    end
end
