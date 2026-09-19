-- Run with tools/map_c6/prepare-ai-check.cjs and the generated Tools-only script.
-- Each module is loaded in a separate sandbox; no live entities/globals change.
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
    assert(scenario(sources.before)==scenario(sources.after),'slot/queue behavior changed')
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
