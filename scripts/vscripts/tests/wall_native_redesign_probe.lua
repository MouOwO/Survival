-- Explicit Tools-only native movement/attack/collision acceptance. Loaded in
-- a private scope by tools/build_wall_contact_native_probe.cjs, never by the
-- gameplay bootstrap. Real-map cases use the installed map's terrain; optional
-- artificial banks are fixture geometry, not a full-match economy/HTTP test.
local M = {}
local navigation = require('systems/wall_navigation_service')
local geometry = require('systems/wall_navigation_geometry')
local contact = require('systems/wall_melee_contact')
local implementation = require('modifiers/modifier_enemy_wall_ai')
local json = require('core/json_encoder')
local record_lifecycle = require('tests/wall_native_attack_record_lifecycle')
local state
local MODIFIER = 'modifier_wall_native_redesign_ai'
local TIMER = 'survival_native_wall_redesign_probe_'..tostring(__native_probe_namespace or 'single')
local function valid(unit) return unit and not unit:IsNull() end
local function alive(unit) return valid(unit) and unit:IsAlive() end
local function count(values) local n=0;for _ in pairs(values) do n=n+1 end;return n end
local function rotate(x,y,q) for _=1,q do x,y=-y,x end;return x,y end
local function local_point(s,p)
    local x,y=p.x-s.origin.x,p.y-s.origin.y
    return rotate(x,y,(4-s.q)%4)
end
local function world(s,x,y)
    x,y=rotate(x,y,s.q)
    local p=Vector(s.origin.x+x,s.origin.y+y,s.origin.z)
    p.z=GetGroundHeight(p,nil)
    return p
end
local function face(s,p)
    local wall=s.wall:GetAbsOrigin()
    local x,y=p.x-wall.x,p.y-wall.y
    local layout=navigation.contact_layout and navigation.contact_layout(s.wall)
    if layout and layout.gate then
        if layout.axis==1 then return x<0 and 1 or 2 end
        return y<0 and 3 or 4
    end
    if math.abs(x)>=math.abs(y) then return x<0 and 1 or 2 end
    return y<0 and 3 or 4
end
M._face_for_test=face
local function copy_metrics()
    local values={}
    for key,value in pairs(__native_probe_metrics.values or {}) do values[key]=value end
    return values
end
local function delta_metrics(before)
    local values={}
    for key,value in pairs(__native_probe_metrics.values or {}) do values[key]=value-(before[key] or 0) end
    return values
end
-- Padded collision radius is a native navigation/avoidance envelope, not a
-- second hard body. Real solid actors can compress that envelope while their
-- raw hulls remain separated. Keep both observations; only solid raw-hull
-- penetration is a hard-collision failure. Two units of numerical slack are
-- shared by both measurements, rather than hiding the extra native padding.
local function body_pair_overlap(a,b,separation_squared)
    local raw=math.max(0,a.hull)+math.max(0,b.hull)
    local padded=math.max(a.hull,a.padded or a.hull)+math.max(b.hull,b.padded or b.hull)
    local hard=separation_squared<math.max(0,raw-2)^2
    local avoidance=separation_squared<math.max(0,padded-2)^2
    local solid=not a.phased and not b.phased
    return {hard_overlap=hard,padded_overlap=avoidance,solid_overlap=hard and solid,
        phased_overlap=hard and not solid,raw=raw,padded=padded}
end
M._body_pair_overlap_for_test=body_pair_overlap
local function replacement_deadline_exceeded(s)
    if not s.max_replacement_seconds or not s.replace or not s.victim or s.replacement~=1 then return false end
    return not s.replacement_seconds or s.replacement_seconds>s.max_replacement_seconds
end
M._replacement_deadline_exceeded_for_test=replacement_deadline_exceeded
local function pick_vacancy_victim(s,current)
    if not s.allow_partial_vacancy then
        -- Preserve the historical full-face selection for existing cases.
        for _,unit in ipairs(s.monsters) do
            local side=s.hit_face[unit:entindex()]
            if alive(unit) and s.hits[unit:entindex()] and current.locked[side]==4
                and (not s.vacancy_face or side==s.vacancy_face) then return unit end
        end
        return nil
    end
    local front={}
    local side=s.vacancy_face
    if not side or (current.locked[side] or 0)<2 then return nil end
    for _,unit in ipairs(s.monsters) do if alive(unit) and s.hits[unit:entindex()] then
        local ai=unit:FindModifierByName(MODIFIER)
        local goal=ai and ai.contact_move
        if ai and ai.contact_locked and goal and face(s,goal)==side
            and contact.arrived(s.wall,unit,goal,true) then
            local p=unit:GetAbsOrigin()
            front[#front+1]={unit=unit,goal=goal,tangent=side<=2 and p.y or p.x}
        end
    end end
    if #front<2 then return nil end
    table.sort(front,function(a,b)
        if a.tangent==b.tangent then return a.unit:entindex()<b.unit:entindex() end
        return a.tangent<b.tangent
    end)
    -- Kill an interior occupant when three real bodies are present; no test
    -- movement, hull shrink, phase or forced positioning creates the gap.
    return front[math.ceil(#front/2)].unit,front
end
M._pick_vacancy_victim_for_test=pick_vacancy_victim
local function record_partial_vacancy_hit(s,ai,unit,target)
    if not s.allow_partial_vacancy or not s.victim or not ai.contact_locked or not target
        or face(s,target)~=s.victim_face or not contact.arrived(s.wall,unit,target,true) then return false end
    local id=unit:entindex()
    if id==s.victim or s.vacancy_front_ids[id] or s.vacancy_fill_ids[id] then return false end
    local goal=s.vacancy_goal
    if not goal or (target.x-goal.x)^2+(target.y-goal.y)^2>4^2 then return false end
    for _,blocker in ipairs(s.vacancy_blockers) do
        if not alive(blocker) then
            if not s.vacancy_blocker_lost then
                s.vacancy_blocker_lost=true;s.errors[#s.errors+1]='vacancy_live_blocker_lost'
            end
            return false
        end
    end
    s.vacancy_fill_ids[id]=true;s.replacement=(s.replacement or 0)+1
    s.replacement_seconds=GameRules:GetGameTime()-s.killed_at
    s.vacancy_fills[#s.vacancy_fills+1]={id=id,face=s.victim_face,elapsed=s.replacement_seconds,
        global_hits=s.hits[id] or 0,claimed=true,goal={x=target.x,y=target.y,z=target.z},
        hull=unit:GetHullRadius(),phased=unit:IsPhased()}
    return true
end
M._record_partial_vacancy_hit_for_test=record_partial_vacancy_hit
local function stable_phase_failures(s)
    return (s.maximum_stable_phased_overlaps or 0)>0,
        (s.maximum_stable_phased_count or 0)>0
end
M._stable_phase_failures_for_test=stable_phase_failures
local function four_source_min_x(population,clear_margin)
    local depth=352+math.floor((population-1)/16)*80
    assert(clear_margin>=depth+32,'four-source clear_margin must cover the farthest spawn and raw hull')
    return -math.ceil((depth+64)/64)*64
end
M._four_source_min_x_for_test=four_source_min_x
local function front_row_overflow(positions,locked)
    local overflow,details,rows=0,{},{}
    local function along(p,side) return side<=2 and p.y or p.x end
    local function normal(p,side)
        local value=side<=2 and p.x or p.y
        return (side==1 or side==3) and -value or value
    end
    local function id(actor) return actor.id or (actor.unit and actor.unit:entindex()) end
    for side=1,4 do
        if (locked[side] or 0)>=4 then
            local anchors={}
            for _,b in ipairs(positions) do
                if b.ai and b.ai.contact_locked and b.side==side then
                    anchors[#anchors+1]={along=along(b.p,side),normal=normal(b.p,side),hull=b.hull,id=id(b)}
                end
            end
            table.sort(anchors,function(a,b) return a.along<b.along end)
            if #anchors>=4 then rows[#rows+1]={face=side,anchors=anchors} end
        end
    end
    for _,a in ipairs(positions) do
        if not (a.ai and a.ai.contact_locked) then
            for _,row in ipairs(rows) do
                local side,anchors=row.face,row.anchors
                local tangent=along(a.p,side)
                local first,last=anchors[1],anchors[#anchors]
                -- A legal route around the row's outer end is not insertion
                -- among its four bodies. Use actual centers, not each end's
                -- old96-unit diagnostic rectangle extended beyond the row.
                if tangent>=first.along and tangent<=last.along then
                    local left,right=first,last
                    for index=2,#anchors do
                        if tangent<=anchors[index].along then left,right=anchors[index-1],anchors[index];break end
                    end
                    local span=right.along-left.along
                    local t=span>0 and (tangent-left.along)/span or 0
                    local plane=left.normal+(right.normal-left.normal)*t
                    local actual=normal(a.p,side)
                    local delta=actual-plane
                    -- Ordinary native bodies may form a curved line or a
                    -- rear wedge. A center still behind the actual line is
                    -- being blocked, not passing through it. The raw/swept
                    -- body oracle and square-wall checks remain independent.
                    local forward=math.min(a.hull+math.max(left.hull,right.hull)-4,48)
                    if delta<=2 and delta>-forward then
                        overflow=overflow+1
                        details[#details+1]={id=id(a),face=side,target_face=a.side,along=tangent,
                            row_min=first.along,row_max=last.along,normal=actual,plane=plane,
                            delta=delta,left_id=left.id,right_id=right.id}
                        break
                    end
                end
            end
        end
    end
    return overflow,details
end
M._front_row_overflow_for_test=front_row_overflow
local function report(s,include_units)
    local rows,locked,hit_faces={}, {0,0,0,0}, {0,0,0,0}
    local crossings,living,overlaps,front_overflow=0,0,0,0
    local positions,overlap_pairs,padded_overlap_pairs={},{},{}
    local solid_overlaps,phased_overlaps,padded_overlaps,phased_count=0,0,0,0
    for _,unit in ipairs(s.monsters) do
        if alive(unit) then
            living=living+1
            local p=unit:GetAbsOrigin()
            local x,y=local_point(s,p)
            local ai=unit:FindModifierByName(MODIFIER)
            local side=face(s,ai and ai.contact_move or p)
            local phased=unit:IsPhased()
            if phased then phased_count=phased_count+1 end
            if x>160 then crossings=crossings+1 end
            if ai and ai.contact_locked then locked[side]=locked[side]+1 end
            positions[#positions+1]={unit=unit,p=p,hull=unit:GetHullRadius(),
                padded=unit:GetPaddedCollisionRadius(),phased=phased,ai=ai,side=side}
            if include_units then rows[#rows+1]={id=unit:entindex(),x=math.floor(x*10)/10,
                y=math.floor(y*10)/10,state=ai and ai.ai_state,face=side,stack=ai and ai:GetStackCount(),
                hits=s.hits[unit:entindex()] or 0,hull=unit:GetHullRadius(),
                padded=unit:GetPaddedCollisionRadius(),
                phased=phased,rooted=unit:IsRooted(),idle=unit:IsIdle()} end
        end
    end
    for i,a in ipairs(positions) do for j=i+1,#positions do
        local b=positions[j]
        local separation=(a.p.x-b.p.x)^2+(a.p.y-b.p.y)^2
        local classified=body_pair_overlap(a,b,separation)
        if classified.hard_overlap then overlaps=overlaps+1 end
        if classified.solid_overlap then solid_overlaps=solid_overlaps+1 end
        if classified.phased_overlap then phased_overlaps=phased_overlaps+1 end
        if classified.padded_overlap then padded_overlaps=padded_overlaps+1 end
        if classified.hard_overlap or classified.padded_overlap then
            local pair={a=a.unit:entindex(),b=b.unit:entindex(),
                distance=math.sqrt(separation),raw=classified.raw,padded=classified.padded,
                hard_overlap=classified.hard_overlap,solid_overlap=classified.solid_overlap,
                padded_overlap=classified.padded_overlap,
                state_a=a.ai and a.ai.ai_state,state_b=b.ai and b.ai.ai_state,
                phased_a=a.phased,phased_b=b.phased,
                goal_a=a.ai and a.ai.contact_move and {x=a.ai.contact_move.x,y=a.ai.contact_move.y},
                goal_b=b.ai and b.ai.contact_move and {x=b.ai.contact_move.x,y=b.ai.contact_move.y},
                idle_a=a.unit:IsIdle(),idle_b=b.unit:IsIdle()}
            if classified.hard_overlap then overlap_pairs[#overlap_pairs+1]=pair end
            if classified.padded_overlap then padded_overlap_pairs[#padded_overlap_pairs+1]=pair end
        end
    end end
    -- Count a non-owner physically interleaved with a settled contact row.
    -- This diagnoses the visible fifth body independently of damage licences.
    local front_overflow_details
    front_overflow,front_overflow_details=front_row_overflow(positions,locked)
    for _,side in pairs(s.hit_face) do hit_faces[side]=hit_faces[side]+1 end
    local vacancy_blockers={};local vacancy_blockers_alive=true
    for _,unit in ipairs(s.vacancy_blockers or {}) do
        local phased;if valid(unit) then phased=unit:IsPhased() end
        local living_blocker=alive(unit)
        vacancy_blockers_alive=vacancy_blockers_alive and living_blocker
        vacancy_blockers[#vacancy_blockers+1]={id=s.vacancy_blocker_ids[unit],alive=living_blocker,
            hull=valid(unit) and unit:GetHullRadius() or nil,phased=phased}
    end
    local result={label=s.label,elapsed=GameRules:GetGameTime()-s.started,
        bank_width=s.bank_width,offset=s.offset,q=s.q,phase=s.phase,living=living,
        locked=locked,hit_faces=hit_faces,unique_hits=count(s.hits),invalid_hits=s.invalid_hits,
        crossings=crossings,overlaps=overlaps,overlap_pairs=overlap_pairs,front_overflow=front_overflow,
        front_overflow_details=front_overflow_details,
        solid_overlaps=solid_overlaps,phased_overlaps=phased_overlaps,phased_count=phased_count,
        padded_overlaps=padded_overlaps,padded_overlap_pairs=padded_overlap_pairs,
        maximum_stable_front_overflow=s.maximum_stable_front_overflow or 0,
        maximum_stable_solid_overlaps=s.maximum_stable_solid_overlaps or 0,
        maximum_stable_phased_overlaps=s.maximum_stable_phased_overlaps or 0,
        maximum_stable_phased_count=s.maximum_stable_phased_count or 0,
        maximum_stable_padded_overlaps=s.maximum_stable_padded_overlaps or 0,
        maximum_locked=s.maximum_locked,maximum_path_bucket=__native_probe_metrics.max_path_bucket or 0,
        metrics=copy_metrics(),stable_metrics=s.stable_metrics or (s.stable_before and delta_metrics(s.stable_before)),
        replacement=s.replacement,max_replacement_seconds=s.max_replacement_seconds,
        victim=s.victim,victim_face=s.victim_face,vacancy_face=s.vacancy_face,
        allow_partial_vacancy=s.allow_partial_vacancy,vacancy_front_count=s.vacancy_front_count,
        vacancy_goal=s.vacancy_goal,vacancy_front_ids=s.vacancy_front_id_list,
        vacancy_fills=s.vacancy_fills,vacancy_blockers=vacancy_blockers,
        vacancy_blockers_alive=vacancy_blockers_alive,
        vacancy_blocker_lost=s.vacancy_blocker_lost==true,
        first_four=s.first_four,first_sixteen=s.first_sixteen,
        replacement_seconds=s.replacement_seconds,
        errors=s.errors,assertions=s.assertions,units=include_units and rows or nil,
        layout=navigation.contact_layout and navigation.contact_layout(s.wall),
        source_hashes=M.source_hashes}
    return result
end
function M.is_active() return state~=nil end
function M.focus()
    assert(IsInToolsMode() and state and valid(state.wall),'an isolated test wall is required')
    PlayerResource:SetCameraTarget(0,state.wall)
    state.camera=true
end
function M.inspect_layout(origin)
    assert(IsInToolsMode() and not state,'inspect only between isolated tests')
    local p=Vector(origin.x,origin.y,GetGroundHeight(origin,nil))
    local seams,bounds,gate,axis,layout=geometry.seams(p,function(point)
        return GridNav:IsTraversable(point) and not GridNav:IsBlocked(point)
            and math.abs(GetGroundHeight(point,nil)-p.z)<=128
    end)
    return {x=p.x,y=p.y,z=p.z,gate=gate,axis=axis,layout=layout,seams=#seams}
end
function M.snapshot(include_units)
    if state and state.draining then
        state.stop_report.attack_records=state.attack_records:summary()
        return state.stop_report
    end
    return state and report(state,include_units~=false) or M.last_result
end
function M.diagnose_pending()
    assert(state and IsInToolsMode(),'active isolated test required')
    local result={}
    local function xyz(p) return p and {x=p.x,y=p.y,z=p.z} end
    for _,unit in ipairs(state.monsters) do if alive(unit) then
        local ai=unit:FindModifierByName(MODIFIER)
        if ai and (ai.ai_state=='approach' or ai.ai_state=='route') and ai.contact_move then
            local p,goal=unit:GetAbsOrigin(),ai.contact_move
            local radius=unit:GetHullRadius()-1
            local r={id=unit:entindex(),state=ai.ai_state,p=xyz(p),goal=xyz(goal),
                arrived=contact.arrived(state.wall,unit,goal,false),idle=unit:IsIdle(),
                rooted=unit:IsRooted(),stunned=unit:IsStunned(),phased=unit:IsPhased(),
                blocked_samples={},bodies={}}
            local steps=math.max(1,math.ceil(math.sqrt((p.x-goal.x)^2+(p.y-goal.y)^2)/16))
            for i,o in ipairs({{0,0},{radius,0},{-radius,0},{0,radius},{0,-radius}}) do
                for step=0,steps do
                    local t=step/steps
                    local q=Vector(p.x+(goal.x-p.x)*t+o[1],p.y+(goal.y-p.y)*t+o[2],goal.z)
                    if not GridNav:IsTraversable(q) or GridNav:IsBlocked(q)
                        or (i==1 and math.abs(GetGroundHeight(q,nil)-goal.z)>32) then
                        r.blocked_samples[#r.blocked_samples+1]={sample=i,step=step,p=xyz(q),
                            ground=GetGroundHeight(q,nil)}
                    end
                end
            end
            local nearby=FindUnitsInRadius(unit:GetTeamNumber(),goal,nil,512,DOTA_UNIT_TARGET_TEAM_BOTH,
                DOTA_UNIT_TARGET_BASIC+DOTA_UNIT_TARGET_HERO,0,FIND_ANY_ORDER,false)
            for _,other in ipairs(nearby) do if other~=unit and alive(other) then
                local q=other:GetAbsOrigin()
                local gap=math.sqrt((goal.x-q.x)^2+(goal.y-q.y)^2)
                if gap<unit:GetPaddedCollisionRadius()+other:GetPaddedCollisionRadius()+1 then
                    local oa=other.survival_wall_contact_owner
                    r.bodies[#r.bodies+1]={id=other:entindex(),p=xyz(q),gap=gap,
                        padded=other:GetPaddedCollisionRadius(),mode=oa and oa.contact_mode,
                        phased=other:IsPhased(),name=other:GetUnitName()}
                end
            end end
            result[#result+1]=r
        end
    end end
    return result
end
local function finish_stop(s,final)
    final.attack_records=s.attack_records:summary()
    assert(final.attack_records.pending==0,'never delete an attacker/target with pending native records')
    state=nil
    if s.camera then pcall(function() PlayerResource:SetCameraTarget(0,nil) end) end
    __native_probe_metrics.active=false
    GameRules:GetGameModeEntity():SetContextThink(TIMER,nil,0)
    GameRules:GetGameModeEntity():SetContextThink(TIMER..'_spawn',nil,0)
    GameRules:GetGameModeEntity():SetContextThink(TIMER..'_drain',nil,0)
    for _,unit in ipairs(s.monsters) do
        if valid(unit) then
            pcall(function() unit:RemoveModifierByName(MODIFIER) end)
            assert(s.attack_records:detach(unit),'native record observer must drain before actor deletion')
            unit.survival_native_probe=nil;unit.survival_native_ai_impl=nil
            pcall(UTIL_Remove,unit)
        end
    end
    if valid(s.wall) then pcall(navigation.clear,s.wall);pcall(UTIL_Remove,s.wall) end
    if contact.reset then pcall(contact.reset) end
    for _,entity in ipairs(s.obstacles) do
        if valid(entity) then
            pcall(DoEntFireByInstanceHandle,entity,'Disable','',0,nil,nil)
            pcall(UTIL_Remove,entity)
        end
    end
    if s.viewer and RemoveFOWViewer then pcall(RemoveFOWViewer,DOTA_TEAM_BADGUYS,s.viewer) end
    final.reason=s.stop_reason or 'stopped'
    final.ok=#s.errors==0 and s.stop_reason=='complete' and final.attack_records.passed
    final.cleaned=true
    M.last_result=final
    print('[WALL_NATIVE_RESULT] '..json.encode(final))
    return final
end
function M.stop(reason)
    local s=state
    if not s then return M.last_result end
    if s.draining then return M.last_result end
    -- Preserve the actual combat evidence before removing the AI. The target
    -- and every attacker stay alive/valid while native records drain.
    local final=report(s,true)
    final.pending_trace=s.pending_trace
    if s.pre_vacancy then
        local before=s.pre_vacancy
        final.pre_vacancy={locked=before.locked,hit_faces=before.hit_faces,
            unique_hits=before.unique_hits,crossings=before.crossings,
            overlaps=before.overlaps,overlap_pairs=before.overlap_pairs,front_overflow=before.front_overflow,
            solid_overlaps=before.solid_overlaps,phased_overlaps=before.phased_overlaps,
            phased_count=before.phased_count,
            padded_overlaps=before.padded_overlaps,padded_overlap_pairs=before.padded_overlap_pairs}
    end
    s.stop_report=final;s.stop_reason=reason;s.draining=true;s.phase='draining'
    __native_probe_metrics.active=false
    local mode=GameRules:GetGameModeEntity()
    mode:SetContextThink(TIMER,nil,0);mode:SetContextThink(TIMER..'_spawn',nil,0)
    -- Destroy the AI first so no observer can issue another attack order.
    for _,unit in ipairs(s.monsters) do if valid(unit) then
        local modifier=unit:FindModifierByName(MODIFIER)
        if modifier then modifier:Destroy() end
    end end
    s.attack_records:begin_drain()
    local function drain()
        if state~=s then return nil end
        local status=s.attack_records:poll()
        local audit=s.attack_records:summary()
        if status=='pending' or (status=='failed' and audit.pending>0 and not audit.timed_out) then return .03 end
        if status=='ready' or audit.pending==0 then
            if not audit.passed then s.errors[#s.errors+1]='native_attack_record_audit_failed' end
            finish_stop(s,final);return nil
        end
        -- An expired/missing native record is evidence of unsafe cleanup.
        -- Keep the target and disarmed actors, stop the matrix, and refuse a
        -- new probe/scene restore instead of silently deleting pending records.
        s.errors[#s.errors+1]='native_attack_record_cleanup_blocked'
        final.attack_records=audit;final.reason='attack_record_cleanup_blocked'
        final.ok=false;final.cleaned=false;final.cleanup_blocked=true
        M.last_result=final
        print('[WALL_NATIVE_CLEANUP_BLOCKED] '..json.encode({label=s.label,attack_records=audit}))
        if PauseGame then PauseGame(true) end
        return nil
    end
    s.retry_cleanup=drain
    mode:SetContextThink(TIMER..'_drain',drain,.03)
    return nil
end
function M.retry_cleanup()
    assert(state and state.draining and state.retry_cleanup,'no retained cleanup to retry')
    GameRules:GetGameModeEntity():SetContextThink(TIMER..'_drain',state.retry_cleanup,.03)
end
local function fail(s,message)
    s.errors[#s.errors+1]=message
    print('[WALL_NATIVE_FAIL] '..message)
end
local function record_hit(ai,event)
    local s=state
    if not s or event.target~=s.wall then return end
    local unit=event.attacker
    local id=unit:entindex()
    local p=unit:GetAbsOrigin()
    local target=ai.contact_move
    if not ai.contact_locked or not target or not contact.arrived(s.wall,unit,target,true) then
        s.invalid_hits=s.invalid_hits+1
    end
    s.hits[id]=(s.hits[id] or 0)+1
    if s.hits[id]==1 then
        s.hit_face[id]=face(s,target or p)
        if count(s.hits)==4 then s.first_four=GameRules:GetGameTime()-s.started end
        if count(s.hits)==16 then s.first_sixteen=GameRules:GetGameTime()-s.started end
        if not s.allow_partial_vacancy and s.victim and s.hit_face[id]==s.victim_face then
            s.replacement=(s.replacement or 0)+1
            s.replacement_seconds=GameRules:GetGameTime()-s.killed_at
        end
        print('[WALL_NATIVE_FIRST_HIT] '..json.encode({label=s.label,id=id,
            elapsed=GameRules:GetGameTime()-s.started,face=s.hit_face[id]}))
    end
    record_partial_vacancy_hit(s,ai,unit,target)
end
local function tick()
    local s=state
    if not s then return end
    local t=GameRules:GetGameTime()-s.started
    if not s.refreshed then navigation.create(s.wall);s.refreshed=true end
    local current=report(s,false)
    local total_locked=0
    for side=1,4 do
        total_locked=total_locked+current.locked[side]
        s.maximum_locked[side]=math.max(s.maximum_locked[side],current.locked[side])
        if current.locked[side]>4 then fail(s,'face_'..side..'_over_capacity') end
    end
    if t>=s.stable_start and not s.stable_before then s.stable_before=copy_metrics() end
    if t>=s.stable_start and t<s.kill_at then
        s.maximum_stable_front_overflow=math.max(s.maximum_stable_front_overflow or 0,current.front_overflow)
        s.maximum_stable_solid_overlaps=math.max(s.maximum_stable_solid_overlaps or 0,current.solid_overlaps)
        s.maximum_stable_phased_overlaps=math.max(s.maximum_stable_phased_overlaps or 0,current.phased_overlaps)
        s.maximum_stable_phased_count=math.max(s.maximum_stable_phased_count or 0,current.phased_count)
        s.maximum_stable_padded_overlaps=math.max(s.maximum_stable_padded_overlaps or 0,current.padded_overlaps)
    end
    if t>=s.kill_at and not s.victim and s.replace then
        local victim,front=pick_vacancy_victim(s,current)
        if victim then
            if s.stable_before then s.stable_metrics=delta_metrics(s.stable_before) end
            s.pre_vacancy=report(s,true)
            s.unique_before_kill=count(s.hits);s.victim=victim:entindex();s.phase='replacement'
            s.victim_face=s.hit_face[s.victim];s.replacement=0
            if s.allow_partial_vacancy then
                s.victim_face=s.vacancy_face;s.vacancy_front_count=#front
                s.vacancy_front_ids={};s.vacancy_front_id_list={};s.vacancy_blockers={};s.vacancy_blocker_ids={}
                s.vacancy_fill_ids={};s.vacancy_fills={}
                for _,row in ipairs(front) do
                    local id=row.unit:entindex();s.vacancy_front_ids[id]=true
                    s.vacancy_front_id_list[#s.vacancy_front_id_list+1]=id
                    if row.unit~=victim then
                        s.vacancy_blockers[#s.vacancy_blockers+1]=row.unit;s.vacancy_blocker_ids[row.unit]=id
                    else s.vacancy_goal={x=row.goal.x,y=row.goal.y,z=row.goal.z} end
                end
            end
            s.killed_at=GameRules:GetGameTime()
            victim:ForceKill(false)
            print('[WALL_NATIVE_VACANCY] '..s.victim)
        end
    end
    if s.victim and s.replacement~=1 and s.trace_pending and #s.pending_trace<20 then
        s.pending_trace[#s.pending_trace+1]={elapsed=t,units=M.diagnose_pending()}
    end
    if t>=(s.next_report or 0) then
        s.next_report=t+2
        print('[WALL_NATIVE_SAMPLE] '..json.encode(current))
    end
    if t>=s.seconds then
        if s.assertions then
            if current.invalid_hits>0 then fail(s,'attack_without_arrived_contact') end
            local before=s.pre_vacancy or current
            if before.solid_overlaps>0 then fail(s,'settled_body_overlap') end
            if (s.maximum_stable_solid_overlaps or 0)>0 then fail(s,'stable_solid_body_overlap') end
            local phased_overlap,phased_actor=stable_phase_failures(s)
            if phased_overlap then fail(s,'stable_phased_body_overlap') end
            if phased_actor then fail(s,'stable_phased_actor') end
            if (s.maximum_stable_front_overflow or 0)>0 then fail(s,'fifth_body_in_full_contact_row') end
            local stable=s.stable_metrics
            if stable and ((stable.orders or 0)>0 or (stable.position_writes or 0)>0
                or (stable.stops or 0)>0 or (stable.nav_FindPathLength or 0)>0) then
                fail(s,'stable_combat_repeated_work')
            end
            if before.unique_hits<s.min_hits then fail(s,'too_few_native_attackers') end
            if s.replace and not s.victim then fail(s,s.allow_partial_vacancy
                and 'no_partial_face_for_replacement_test' or 'no_full_face_for_replacement_test') end
            if s.replace and s.victim and s.replacement~=1 then fail(s,'vacancy_did_not_replace_exactly_one') end
            if s.allow_partial_vacancy and s.victim and not current.vacancy_blockers_alive then
                fail(s,'vacancy_live_blocker_lost')
            end
            if replacement_deadline_exceeded(s) then fail(s,'replacement_hit_deadline_exceeded') end
            if s.open_floor then
                for side=1,4 do if before.hit_faces[side]~=4 then fail(s,'open_face_'..side..'_not_four') end end
            elseif s.expected_closed or (math.abs(s.offset)<=128 and s.bank_width==256) then
                if before.unique_hits~=4 then fail(s,'sealed_gate_attackers_not_four') end
                if before.crossings>0 then fail(s,'sealed_gate_was_crossed') end
            elseif math.abs(s.offset)>=192 then
                local faces=0;for side=1,4 do if before.hit_faces[side]>0 then faces=faces+1 end end
                if faces<2 then fail(s,'open_side_did_not_reach_other_face') end
                if before.crossings==0 then fail(s,'open_side_not_crossed') end
            end
        end
        return M.stop('complete') and nil
    end
    return .5
end
function M.start(origin,bank_width,offset,q,population,options)
    assert(IsServer() and IsInToolsMode(),'Tools server only')
    assert(not state,'stop the previous isolated test first')
    assert(origin and origin.x%64==0 and origin.y%64==0,'explicit 64-aligned empty origin required')
    local loading=require('systems/startup_loading_service')
    assert(loading.is_ready(),'the real game must already be ready')
    assert(not GameRules:IsGamePaused(),'test requires real unpaused engine frames')
    options=options or {}
    local vacancy_face=tonumber(options.vacancy_face)
    assert(options.vacancy_face==nil or (vacancy_face and vacancy_face%1==0
        and vacancy_face>=1 and vacancy_face<=4),'vacancy_face must be a physical face 1..4')
    assert(options.allow_partial_vacancy~=true or vacancy_face,
        'partial vacancy requires an explicit physical vacancy_face')
    population=tonumber(population) or 28
    assert(population>=5 and population<=96 and population%1==0,'population 5..96')
    q=(tonumber(q) or 0)%4
    assert(q%1==0,'q must be an integer quarter turn')
    bank_width=tonumber(bank_width) or 0;offset=tonumber(offset) or 0
    assert((bank_width==0 or (bank_width>=192 and bank_width<=512 and bank_width%64==0))
        and math.abs(offset)<=256 and offset%64==0,'bounded grid geometry required')
    local bank_length=tonumber(options.bank_length) or 1280
    local clear_margin=tonumber(options.clear_margin) or 512
    assert(bank_length==768 or bank_length==896 or bank_length==1024 or bank_length==1280,
        'bank_length must be 768, 896, 1024 or 1280')
    assert(clear_margin==320 or clear_margin==384 or clear_margin==512,
        'clear_margin must be 320, 384 or 512')
    local max_replacement_seconds=tonumber(options.max_replacement_seconds)
    assert(not options.max_replacement_seconds or (max_replacement_seconds
        and max_replacement_seconds>0 and max_replacement_seconds<math.huge),
        'max_replacement_seconds must be a positive finite duration')
    local s={origin=Vector(origin.x,origin.y,GetGroundHeight(origin,nil)),q=q,bank_width=bank_width,
        offset=offset,open_floor=bank_width==0,units={},monsters={},obstacles={},hits={},hit_face={},
        errors={},maximum_locked={0,0,0,0},invalid_hits=0,started=GameRules:GetGameTime(),phase='front',
        label=tostring(options.label or ('width'..bank_width..'_offset'..offset..'_q'..q)),
        real_terrain=options.real_terrain==true,
        expected_closed=options.expected_closed==true,
        trace_pending=options.trace_pending==true,pending_trace={},
        seconds=tonumber(options.seconds) or 14,kill_at=tonumber(options.kill_at) or 9,
        stable_start=tonumber(options.stable_start) or 5,replace=options.replace~=false,
        max_replacement_seconds=max_replacement_seconds,
        vacancy_face=vacancy_face,allow_partial_vacancy=options.allow_partial_vacancy==true,
        assertions=options.assertions==true,min_hits=tonumber(options.min_hits) or (bank_width==0 and 16 or 4)}
    s.attack_records=record_lifecycle.new({timeout=options.attack_record_timeout})
    s.min_x=math.min(-bank_length,-math.ceil((480+math.floor((population-1)/3)*84)/128)*128)
    if bank_width==0 and options.four_sources then
        -- Four source rings have no linear tail or synthetic banks. Validate
        -- their actual bounded footprint instead of unrelated distant cliffs.
        s.min_x=four_source_min_x(population,clear_margin)
    end
    -- Refuse occupied/blocked terrain before adding any temporary obstruction.
    for _,class_name in ipairs({'npc_dota_creature','npc_dota_building','npc_dota_hero'}) do
        for _,unit in ipairs(Entities:FindAllByClassname(class_name) or {}) do
            if valid(unit) then
                local x,y=local_point(s,unit:GetAbsOrigin())
                assert(x < s.min_x-128 or x > 768 or math.abs(y)>768,'test area contains an existing gameplay entity')
            end
        end
    end
    if not s.real_terrain then
    for x=s.min_x,640,64 do for y=-clear_margin,clear_margin,64 do
        local p=world(s,x,y)
        assert(GridNav:IsTraversable(p) and not GridNav:IsBlocked(p)
            and math.abs(p.z-s.origin.z)<16,'test area is not empty flat traversable terrain')
    end end
    end
    state=s;M.last_result=nil
    __native_probe_metrics.values={};__native_probe_metrics.max_path_bucket=0
    __native_probe_metrics.path_buckets={};__native_probe_metrics.active=true
    s.record_hit=record_hit
    local ok,message=pcall(function()
        if bank_width>0 and not s.real_terrain then
            -- Stair banks stop at +128; the courtyard behind them is open.
            -- An oversized wall offset therefore leaves a real route around
            -- the exposed edge into the courtyard, not an infinite corridor.
            for x=s.min_x+64,64,128 do for _,sign in ipairs({-1,1}) do for depth=0,1 do
                local entity=SpawnEntityFromTableSynchronous('point_simple_obstruction',{
                    origin=world(s,x,sign*(bank_width/2+64+depth*128)),StartDisabled=0,block_fow=0,
                    targetname='survival_native_redesign_bank'})
                assert(valid(entity),'temporary native bank creation failed')
                s.obstacles[#s.obstacles+1]=entity
            end end end
            for y=-bank_width/2+64,bank_width/2-64,128 do
                local entity=SpawnEntityFromTableSynchronous('point_simple_obstruction',{
                    origin=world(s,s.min_x-64,y),StartDisabled=0,block_fow=0,
                    targetname='survival_native_redesign_bank_back'})
                assert(valid(entity),'temporary native back bank creation failed')
                s.obstacles[#s.obstacles+1]=entity
            end
        end
        -- Give Source 2 one real navigation update after adding the banks;
        -- gate detection must observe actual obstructions, never stale GridNav.
        local function prepare()
        local p=world(s,0,offset)
        local wall=CreateUnitByName('building_wall',p,false,nil,nil,DOTA_TEAM_GOODGUYS)
        assert(valid(wall),'temporary wall creation failed')
        s.wall=wall;wall:SetAbsOrigin(p);wall:SetHullRadius(128)
        wall:SetMaxHealth(1000000);wall:SetHealth(1000000);wall:SetBaseHealthRegen(0)
        wall.survival_fixed_position=p
        wall:AddNewModifier(wall,nil,'modifier_building_stationary',{})
        navigation.create(wall)
        s.viewer=AddFOWViewer(DOTA_TEAM_BADGUYS,s.origin,2400,s.seconds+3,false)
        local function spawn_one(index)
            -- Stagger actual spawns in free rows behind the front. Reusing an
            -- occupied portal lets FindClearSpace relocate late actors over
            -- the test banks, which would invalidate the blocking evidence.
            local columns=(s.real_terrain and bank_width>=384) and 4 or 3
            local row,lane=math.floor((index-1)/columns),(index-1)%columns
            local x,y=-352-row*96,(lane-(columns-1)*.5)*84
            if bank_width==0 and options.four_sources then
                local side=(index-1)%4
                local depth=352+math.floor((index-1)/16)*80
                local along=(math.floor((index-1)/4)%4-1.5)*64
                x,y=rotate(-depth,along,side)
            end
            local spawn=world(s,x,y)
            local unit=CreateUnitByName('npc_survival_wave_monster',spawn,false,nil,nil,DOTA_TEAM_BADGUYS)
            assert(valid(unit),'temporary monster creation failed')
            s.monsters[#s.monsters+1]=unit
            assert(s.attack_records:attach(unit),'temporary native attack-record observer failed')
            unit:SetMoveCapability(DOTA_UNIT_CAP_MOVE_GROUND)
            unit:SetAttackCapability(DOTA_UNIT_CAP_MELEE_ATTACK)
            unit:SetHullRadius(32);unit:SetMaxHealth(10000);unit:SetHealth(10000)
            unit:SetBaseDamageMin(1);unit:SetBaseDamageMax(1);unit:SetBaseAttackTime(1)
            unit:SetBaseMoveSpeed(300);unit:SetAcquisitionRange(0)
            unit:SetMinimumGoldBounty(0);unit:SetMaximumGoldBounty(0);unit:SetDeathXP(0)
            -- Native spawn clearance is allowed once, before any AI admission.
            -- No test code writes the unit's coordinates during movement.
            FindClearSpaceForUnit(unit,spawn,true)
            if s.real_terrain then
                local actual_x,actual_y=local_point(s,unit:GetAbsOrigin())
                assert(actual_x<-128-16 and math.abs(actual_y-y)<=128,
                    'native spawn clearance crossed the test wall or left its source lane')
            end
            if bank_width>0 and not s.real_terrain then
                local _,actual_y=local_point(s,unit:GetAbsOrigin())
                assert(math.abs(actual_y)+unit:GetPaddedCollisionRadius()<=bank_width/2+1,
                    'native spawn clearance left the doorway; invalid test arrangement')
            end
            unit.survival_native_ai_impl=implementation;unit.survival_native_probe=s
            unit:AddNewModifier(unit,nil,MODIFIER,{wall_entindex=wall:entindex()})
        end
        s.phase='front';s.started=GameRules:GetGameTime()
        local spawned=0
        GameRules:GetGameModeEntity():SetContextThink(TIMER..'_spawn',function()
            if state~=s then return nil end
            spawned=spawned+1
            local success,message=pcall(spawn_one,spawned)
            if not success then fail(s,tostring(message));M.stop('spawn_error');return nil end
            if spawned>=population then return nil end
            return .2
        end,.1)
        end
        s.phase='prepare'
        GameRules:GetGameModeEntity():SetContextThink(TIMER,function()
            if s.phase=='prepare' then
                local success,message=pcall(prepare)
                if not success then fail(s,tostring(message));M.stop('setup_error');return nil end
                return .5
            end
            local success,result=pcall(tick)
            if not success then
                fail(s,tostring(result));M.stop('runtime_error');return nil
            end
            return result
        end,.25)
        print('[WALL_NATIVE_STARTED] '..json.encode({label=s.label,population=population,
            origin={x=s.origin.x,y=s.origin.y,z=s.origin.z},offset=offset,q=q,bank_width=bank_width,
            seconds=s.seconds,assertions=s.assertions}))
    end)
    if not ok then fail(s,tostring(message));M.stop('setup_error');error(message) end
    return {ok=true,label=s.label,seconds=s.seconds}
end
return M
