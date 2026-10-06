-- Block the registered square and terrain-bounded gate seams. Combat lanes
-- are movement destinations, never additional invisible collision units.
local M = {}
local geometry = require("systems/wall_navigation_geometry")
local walls, cells = {}, {}
local SIZE = 64
local function valid(u) return u and not u:IsNull() end
local function key(x,y) return x .. ":" .. y end
local function cell_at(p) return math.floor(p.x/SIZE), math.floor(p.y/SIZE) end

-- Building validation must still see the underlying terrain in a navigation
-- shoulder. Registered building footprints separately enforce occupied cells.
function M.original_nav(p)
    local x,y=cell_at(p)
    local cell=cells[key(x,y)]
    if cell then return cell.traversable, cell.blocked end
end

local function terrain_open(p)
    local traversable, blocked = M.original_nav(p)
    if traversable == nil then
        traversable, blocked = GridNav:IsTraversable(p), GridNav:IsBlocked(p)
    end
    return traversable and not blocked
        and (not GetGroundHeight or math.abs(GetGroundHeight(p,nil)-p.z)<=128)
end

local function add(state,x,y,z)
    local covered={}
    -- Official simple_obstruction covers a 128x128 square at these aligned origins.
    for gx=x/SIZE-1,x/SIZE do for gy=y/SIZE-1,y/SIZE do
        local k=key(gx,gy)
        if not cells[k] then
            local p=Vector((gx+.5)*SIZE,(gy+.5)*SIZE,z)
            cells[k]={traversable=GridNav:IsTraversable(p),blocked=GridNav:IsBlocked(p),refs=0}
        end
        cells[k].refs=cells[k].refs+1
        covered[#covered+1]=k
    end end
    local ok,entity=pcall(SpawnEntityFromTableSynchronous,"point_simple_obstruction",{
        origin=Vector(x,y,z),StartDisabled=0,block_fow=0,
        targetname="survival_wall_navigation_"..state.index,
    })
    if not ok or not valid(entity) then
        for _,k in ipairs(covered) do
            cells[k].refs=cells[k].refs-1
            if cells[k].refs==0 then cells[k]=nil end
        end
        error("wall navigation obstruction could not be created: "..tostring(entity))
    end
    state.obstacles[#state.obstacles+1]={entity=entity,cells=covered}
end

function M.create(wall)
    if not valid(wall) or not SpawnEntityFromTableSynchronous then return {} end
    local index=wall:entindex()
    wall.survival_wall_navigation_index=index
    local p=wall:GetAbsOrigin()
    -- npc_dota_building starts with the native invulnerability modifier.
    -- Construction protection is owned separately by our construction modifier.
    if wall.RemoveModifierByName then wall:RemoveModifierByName("modifier_invulnerable") end
    -- SetHullRadius does NOT update the entity bounds (verified in Workshop:
    -- hull 128 still had bounds +/-8). Keep native target bounds on the square.
    if wall.SetSize then
        wall:SetSize(Vector(-128,-128,0),Vector(128,128,192))
    end
    if walls[index] and walls[index].wall==wall then
        local intact=true
        for _,obstacle in ipairs(walls[index].obstacles) do
            if not valid(obstacle.entity) then intact=false;break end
        end
        if intact then return walls[index].obstacles end
    end
    if walls[index] then M.clear(index) end
    local state={index=index,wall=wall,obstacles={},x=math.floor(p.x/SIZE+.5)*SIZE,
        y=math.floor(p.y/SIZE+.5)*SIZE,z=p.z}
    local seams, bounds, gate = geometry.seams(Vector(state.x,state.y,state.z),terrain_open)
    state.bounds=bounds
    state.gate=gate
    walls[index]=state
    local ok, message = pcall(function()
        for _,dx in ipairs({-64,64}) do for _,dy in ipairs({-64,64}) do
            add(state,state.x+dx,state.y+dy,state.z)
        end end
        for _,offset in ipairs(seams) do
            add(state,state.x+offset.x,state.y+offset.y,state.z)
        end
    end)
    if not ok then M.clear(index); error(message) end
    return state.obstacles
end

-- Piggyback the existing enemy AI observation; normal frames do no nav query,
-- placement or order work. Restore only a real square overlap/crossing.
function M.enforce_boundary(wall,unit,previous)
    local state=valid(wall) and walls[wall:entindex()]
    if not state or state.wall~=wall or not valid(unit) or not unit.SetAbsOrigin then return false end
    local p=unit:GetAbsOrigin()
    if math.abs(p.z-state.z)>192 then return false end
    local relative={x=p.x-state.x,y=p.y-state.y,z=p.z}
    local before=previous and {x=previous.x-state.x,y=previous.y-state.y,z=previous.z}
    local radius=unit.GetHullRadius and unit:GetHullRadius() or 1
    -- An open-floor unit may legally walk around a corner between observations.
    -- Only sealed terrain gates may interpret the observed chord as a crossing;
    -- every wall still rejects a real current hull/rectangle overlap.
    local safe=geometry.outside(state.bounds,relative,before,radius,state.gate)
    if not safe then return false end
    local destination=Vector(state.x+safe.x,state.y+safe.y,p.z)
    if not GridNav:IsTraversable(destination) or GridNav:IsBlocked(destination) then
        if not before or geometry.outside(state.bounds,before,nil,radius)
            or not GridNav:IsTraversable(previous) or GridNav:IsBlocked(previous) then return false end
        destination=Vector(previous.x,previous.y,previous.z)
    end
    if GetGroundHeight then destination.z=GetGroundHeight(destination,unit) end
    unit:SetAbsOrigin(destination)
    return true
end

function M.approach(wall,unit)
    if valid(wall) then M.create(wall) end
end

function M.clear(wall)
    local index=type(wall)=="number" and wall
        or (wall and wall.survival_wall_navigation_index)
        or (valid(wall) and wall:entindex())
    local state=index and walls[index]
    if not state then return end
    if type(wall)~="number" and state.wall~=wall then return end
    walls[index]=nil
    local contact=package.loaded["systems/wall_melee_contact"]
    if contact then contact.clear(index) end
    for _,obstacle in ipairs(state.obstacles) do
        if valid(obstacle.entity) then
            DoEntFireByInstanceHandle(obstacle.entity,"Disable","",0,nil,nil)
            UTIL_Remove(obstacle.entity)
        end
        for _,k in ipairs(obstacle.cells) do
            cells[k].refs=cells[k].refs-1
            if cells[k].refs==0 then cells[k]=nil end
        end
    end
end

function M.clear_all()
    for index in pairs(walls) do M.clear(index) end
    -- A script VM reload can lose the table while map entities still exist.
    if Entities and Entities.FindAllByClassname then
        for _,entity in ipairs(Entities:FindAllByClassname("point_simple_obstruction") or {}) do
            if valid(entity) and entity.GetName
                and entity:GetName():find("^survival_wall_navigation_") then
                DoEntFireByInstanceHandle(entity,"Disable","",0,nil,nil)
                UTIL_Remove(entity)
            end
        end
    end
end

return M
