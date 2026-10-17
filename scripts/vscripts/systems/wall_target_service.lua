-- Completed wall registry and shared route cache. No entity discovery in AI
-- frames: building/player events own membership, one shared observation owns
-- movement/eligibility changes, and stable enemies retain their current goal.
local grid_config = require("config/grid_placement_config")
local player_context = require("systems/player_context_service")
local contact = require("systems/wall_melee_contact")
local M = {}
local registry, preferred, inactive, route_cache = {}, {}, {}, {}
local generation, next_order, checked_at, cache_count = 0, 0, -math.huge, 0
local metrics = {resolves=0, path_queries=0, route_cache_hits=0, observations=0}
local change_listener
local function valid(unit) return unit and (not unit.IsNull or not unit:IsNull()) end
local function position(unit)
    if not valid(unit) or not unit.GetAbsOrigin then return nil end
    local ok,p=pcall(unit.GetAbsOrigin,unit)
    if not ok or not p then return nil end
    for _,axis in ipairs({"x","y","z"}) do
        local v=tonumber(p[axis]);if not v or v~=v or math.abs(v)>32768 then return nil end
    end
    return p
end
local function now() return GameRules and GameRules:GetGameTime() or 0 end
local function changed()
    generation=generation+1;route_cache={};cache_count=0
    if change_listener then change_listener() end
end
local function in_build_bounds(unit,p)
    local area=grid_config.build_bounds
    if type(area)~="table" then return true end
    for _,name in ipairs({"min_x","max_x","min_y","max_y"}) do
        local v=tonumber(area[name]);if not v or v~=v or math.abs(v)==math.huge then return true end
    end
    local footprint=unit.survival_grid_footprint or {x=4,y=4}
    local size=tonumber(grid_config.cell_size) or 64
    local half_x=(tonumber(footprint.x) or 4)*size*.5
    local half_y=(tonumber(footprint.y) or 4)*size*.5
    return p.x-half_x>=area.min_x and p.x+half_x<=area.max_x
        and p.y-half_y>=area.min_y and p.y+half_y<=area.max_y
end
local function eligible(record,p)
    local unit=record.unit
    if not valid(unit) or not p or inactive[record.player_id] then return false end
    if type(player_context.is_defeated)=="function" and player_context.is_defeated(record.player_id) then return false end
    if unit.survival_building_id~=nil and unit.survival_building_id~="wall" then return false end
    if unit.IsAlive and not unit:IsAlive() then return false end
    if unit.survival_building_destroyed or unit.survival_wall_collision_barrier
        or unit.survival_is_hidden or unit.survival_building_hidden then return false end
    if unit.GetUnitName and unit:GetUnitName()=="npc_survival_wall_collision_barrier" then return false end
    if unit.HasModifier and unit:HasModifier("modifier_building_under_construction") then return false end
    if unit.IsInvulnerable and unit:IsInvulnerable() then return false end
    if unit.GetTeamNumber and DOTA_TEAM_GOODGUYS and unit:GetTeamNumber()~=DOTA_TEAM_GOODGUYS then return false end
    if not in_build_bounds(unit,p) then return false end
    return true
end
local function rebuild_preferred()
    preferred={}
    for index,r in pairs(registry) do if r.eligible then
        local old=preferred[r.player_id]
        if not old or registry[old].order<r.order then preferred[r.player_id]=index end
    end end
end
local function observe(force)
    local stamp=now()
    if not force and stamp>=checked_at and stamp-checked_at<.5 then return end
    checked_at=stamp;metrics.observations=metrics.observations+1
    local dirty=false
    for _,r in pairs(registry) do
        local p=position(r.unit);local allowed=eligible(r,p)
        if r.eligible~=allowed or (p and (not r.p or p.x~=r.p.x or p.y~=r.p.y or p.z~=r.p.z)) then dirty=true end
        r.eligible=allowed;r.p=p and {x=p.x,y=p.y,z=p.z} or nil
    end
    if dirty then rebuild_preferred();changed() end
end
function M.reset()
    registry,preferred,inactive,route_cache={},{},{},{}
    generation,next_order,checked_at,cache_count=0,0,-math.huge,0
    metrics={resolves=0,path_queries=0,route_cache_hits=0,observations=0}
    change_listener=nil
end
function M.set_change_listener(callback) change_listener=callback end
function M.register(payload)
    if not payload or payload.building_id~="wall" then return false end
    local index=tonumber(payload.entindex);if not index then return false end
    local unit=payload.unit
    if not unit and EntIndexToHScript then unit=EntIndexToHScript(index) end
    if not valid(unit) then return false end
    local player_id=tonumber(payload.player_id) or tonumber(unit.survival_player_id)
    if player_id==nil then return false end
    local before=generation;local record=registry[index]
    if not record or record.unit~=unit or record.player_id~=player_id then
        next_order=next_order+1;registry[index]={unit=unit,player_id=player_id,order=next_order}
    end
    observe(true);return generation~=before
end
function M.remove(index)
    index=tonumber(index)
    if not registry[index] then return false end
    registry[index]=nil;rebuild_preferred();changed();return true
end
function M.deactivate_player(player_id)
    player_id=tonumber(player_id);if player_id==nil or inactive[player_id] then return false end
    inactive[player_id]=true;observe(true);return true
end
function M.navigation_changed() changed() end
function M.revision() observe(false);return generation end
function M.preferred_wall(player_id) observe(false);return preferred[tonumber(player_id)] end
function M.wall_indices()
    observe(false);local result={};for player_id,index in pairs(preferred) do result[player_id]=index end;return result
end
local function route(unit,r)
    local p=position(unit);if not p then return false end
    local radius=tonumber(unit.survival_monster_hull_radius) or (unit.GetHullRadius and unit:GetHullRadius()) or 32
    radius=math.max(1,radius)
    -- Neighboring native navigation cells can have different connectivity.
    -- Share only an identical origin/radius, preserving the full Lua double;
    -- stable AI goals already avoid subsequent route calls while moving.
    local key=string.format("%d:%.17g:%.17g:%.17g:%.17g",r.unit:entindex(),p.x,p.y,p.z,radius)
    local cached=route_cache[key]
    if cached and now()-cached.time<4 then metrics.route_cache_hits=metrics.route_cache_hits+1;return cached.reachable,cached.point end
    -- A sealed wall's centre is intentionally unreachable. Its four face
    -- centres can also be blocked while an outer contact remains legal.
    -- Check the same terrain-filtered slots used by the real attack allocator.
    -- Copy the list before sorting; the allocator owns its shared cache.
    local points={}
    for _,candidate in ipairs(contact.approach_points(r.unit,unit)) do
        points[#points+1]=candidate.point
    end
    table.sort(points,function(a,b) return (a.x-p.x)^2+(a.y-p.y)^2<(b.x-p.x)^2+(b.y-p.y)^2 end)
    local reachable,selected_point=false,nil
    for _,point in ipairs(points) do
        local open=not GridNav or ((not GridNav.IsTraversable or GridNav:IsTraversable(point))
            and (not GridNav.IsBlocked or not GridNav:IsBlocked(point)))
        if open and (not GetGroundHeight or math.abs(GetGroundHeight(point,unit)-r.p.z)<=128) then
            if GridNav and GridNav.CanFindPath then
                metrics.path_queries=metrics.path_queries+1
                local ok,result=pcall(GridNav.CanFindPath,GridNav,p,point);reachable=ok and result==true
            elseif GridNav and GridNav.FindPathLength then
                metrics.path_queries=metrics.path_queries+1
                local ok,length=pcall(GridNav.FindPathLength,GridNav,p,point);reachable=ok and type(length)=="number" and length>=0
            else reachable=true end
            if reachable then selected_point=point;break end
        end
    end
    if cache_count>=512 then route_cache={};cache_count=0 end
    route_cache[key]={reachable=reachable,point=selected_point,time=now()};cache_count=cache_count+1
    return reachable,selected_point
end
function M.resolve(unit,player_id,current,cache,retry)
    observe(retry==true);cache=cache or {};metrics.resolves=metrics.resolves+1
    local active=registry[tonumber(current)]
    if not retry and cache.generation==generation and active and active.eligible then return current,cache end
    -- A missing target does no repeated scans until registry changes or a
    -- bounded no-route retry is explicitly requested by the AI.
    if not retry and cache.generation==generation and current==-1 then return -1,cache end
    local own=registry[preferred[tonumber(player_id)]]
    local selected,waypoint,selected_wall
    local function choose(record)
        if not record or not record.eligible then return false end
        local reachable,point=route(unit,record)
        if not reachable then return false end
        selected,waypoint,selected_wall=record.unit:entindex(),point,record.unit
        return true
    end
    if not choose(own) and not choose(active) then
        local p=position(unit);local candidates={}
        for _,r in pairs(registry) do if r.eligible then candidates[#candidates+1]=r end end
        table.sort(candidates,function(a,b)
            local da=p and (a.p.x-p.x)^2+(a.p.y-p.y)^2 or 0
            local db=p and (b.p.x-p.x)^2+(b.p.y-p.y)^2 or 0
            return da==db and a.unit:entindex()<b.unit:entindex() or da<db
        end)
        for _,r in ipairs(candidates) do if choose(r) then break end end
    end
    unit.survival_wall_route=selected_wall and {wall=selected_wall,
        revision=tonumber(selected_wall.survival_wall_relocation_revision) or 0,
        point=Vector(waypoint.x,waypoint.y,waypoint.z)} or nil
    cache.generation=generation;return selected or -1,cache
end
function M._snapshot_for_test()
    local result={generation=generation,registered=0}
    for _ in pairs(registry) do result.registered=result.registered+1 end
    for name,value in pairs(metrics) do result[name]=value end;return result
end
return M
