-- Strict Tools-only collision verification; never require from gameplay.
-- The native fixture explicitly samples every movement frame. Acceptance
-- forbids all phasing, hull changes, raw/swept penetration and position jumps.
-- A final non-overlapping frame cannot prove bodies did not cross between
-- frames. Compare simultaneous relative motion over each native think step.
local M = {}
local function closest(a0,a1,b0,b1)
    local x,y=a0.x-b0.x,a0.y-b0.y
    local dx,dy=(a1.x-a0.x)-(b1.x-b0.x),(a1.y-a0.y)-(b1.y-b0.y)
    local length=dx*dx+dy*dy
    local t=length>0 and math.max(0,math.min(1,-(x*dx+y*dy)/length)) or 0
    return (x+dx*t)^2+(y+dy*t)^2,t
end
M.closest=closest
function M.classify(previous,current,slack)
    slack=slack or 2
    local a,b=current.a,current.b
    local raw=math.max(0,a.hull)+math.max(0,b.hull)
    local distance=(a.x-b.x)^2+(a.y-b.y)^2
    local hard=distance<math.max(0,raw-slack)^2
    local result={hard_overlap=hard,phased=a.phased or b.phased,raw=raw,
        distance=math.sqrt(distance),swept_crossing=false}
    if previous and previous.a and previous.b then
        local minimum,t=closest(previous.a,a,previous.b,b)
        -- The endpoint test separately catches persistent penetration. This
        -- flag singles out paths that entered another live body in flight.
        result.minimum_distance=math.sqrt(minimum);result.closest_t=t
        result.swept_crossing=minimum<math.max(0,raw-slack)^2
    end
    return result
end
function M.new(options)
    options=options or {}
    return {previous={},initial_hulls={},frames=0,samples=0,pair_checks=0,
        hard_overlap_frames=0,swept_crossing_frames=0,phased_frames=0,
        hull_change_frames=0,jump_frames=0,maximum_jump=0,errors={},
        slack=options.slack or 2,max_speed=options.max_speed or 550,
        max_errors=options.max_errors or 30,seen_errors={},first_time=nil,last_time=nil}
end
local function record(s,kind,data)
    local key=kind..':'..tostring(data.id or data.a)..':'..tostring(data.b or '')
    if s.seen_errors[key] then return end
    s.seen_errors[key]=true
    if #s.errors<s.max_errors then data.kind=kind;s.errors[#s.errors+1]=data end
end
function M.sample(s,stamp,rows)
    assert(type(stamp)=='number' and (not s.last_time or stamp>s.last_time),'strictly increasing native time required')
    local next_rows,bins,pair_seen={},{},{}
    local dt=s.last_time and stamp-s.last_time
    local had_hard,had_swept,had_phase,had_hull,had_jump=false,false,false,false,false
    s.first_time=s.first_time or stamp;s.frames=s.frames+1;s.samples=s.samples+#rows
    local function key(x,y) return x..':'..y end
    for _,row in ipairs(rows) do
        assert(row.id and row.hull and row.hull>0,'live actor needs positive native hull')
        assert(not next_rows[row.id],'duplicate actor id')
        next_rows[row.id]=row
        local initial=s.initial_hulls[row.id]
        if initial and initial~=row.hull then
            had_hull=true;record(s,'hull_changed',{id=row.id,t=stamp,initial=initial,current=row.hull})
        end
        s.initial_hulls[row.id]=initial or row.hull
        if row.phased then had_phase=true;record(s,'phased',{id=row.id,t=stamp,state=row.state}) end
        local before=s.previous[row.id] or row
        local distance=math.sqrt((row.x-before.x)^2+(row.y-before.y)^2)
        s.maximum_jump=math.max(s.maximum_jump,distance)
        if dt and distance>s.max_speed*dt+2 then
            had_jump=true;record(s,'position_jump',{id=row.id,t=stamp,distance=distance,dt=dt,state=row.state})
        end
        -- The union of the moving hull's AABB covers every candidate pair.
        -- Hashing avoids an artificial O(N^2) diagnostic stall in 4-player
        -- same-portal cases while detecting movement between samples.
        local hull=row.hull
        for x=math.floor((math.min(before.x,row.x)-hull)/128),math.floor((math.max(before.x,row.x)+hull)/128) do
            for y=math.floor((math.min(before.y,row.y)-hull)/128),math.floor((math.max(before.y,row.y)+hull)/128) do
                local cell=key(x,y);bins[cell]=bins[cell] or {};bins[cell][#bins[cell]+1]=row
            end
        end
    end
    for _,bin in pairs(bins) do
        for i=1,#bin do for j=i+1,#bin do
            local a,b=bin[i],bin[j]
            local pair=a.id<b.id and a.id..':'..b.id or b.id..':'..a.id
            if not pair_seen[pair] then
                pair_seen[pair]=true;s.pair_checks=s.pair_checks+1
                local previous=s.previous[a.id] and s.previous[b.id] and {a=s.previous[a.id],b=s.previous[b.id]} or nil
                local result=M.classify(previous,{a=a,b=b},s.slack)
                if result.hard_overlap then had_hard=true end
                if result.swept_crossing then had_swept=true end
                if result.hard_overlap or result.swept_crossing then
                    record(s,'body_penetration',{a=a.id,b=b.id,t=stamp,
                        distance=result.distance,minimum_distance=result.minimum_distance,
                        closest_t=result.closest_t,raw=result.raw,phased=result.phased,
                        hard_overlap=result.hard_overlap,swept_crossing=result.swept_crossing,
                        state_a=a.state,state_b=b.state})
                end
            end
        end end
    end
    if had_hard then s.hard_overlap_frames=s.hard_overlap_frames+1 end
    if had_swept then s.swept_crossing_frames=s.swept_crossing_frames+1 end
    if had_phase then s.phased_frames=s.phased_frames+1 end
    if had_hull then s.hull_change_frames=s.hull_change_frames+1 end
    if had_jump then s.jump_frames=s.jump_frames+1 end
    s.previous=next_rows;s.last_time=stamp
    return not (had_hard or had_swept or had_phase or had_hull or had_jump)
end
function M.summary(s)
    return {frames=s.frames,samples=s.samples,pair_checks=s.pair_checks,
        hard_overlap_frames=s.hard_overlap_frames,swept_crossing_frames=s.swept_crossing_frames,
        phased_frames=s.phased_frames,hull_change_frames=s.hull_change_frames,
        jump_frames=s.jump_frames,maximum_jump=s.maximum_jump,errors=s.errors,
        duration=s.last_time and s.last_time-s.first_time or 0,
        passed=s.frames>1 and s.samples>0 and s.hard_overlap_frames==0
            and s.swept_crossing_frames==0 and s.phased_frames==0
            and s.hull_change_frames==0 and s.jump_frames==0}
end
return M
