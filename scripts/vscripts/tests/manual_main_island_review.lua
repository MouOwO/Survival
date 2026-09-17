-- Opt-in Workshop art review, isolated to main_island_review.
local M={}
local scheduler=require('core/scheduler')
local anchor,unit,viewer,probe_started,original_origin,original_speed
local function valid(e)return e and not e:IsNull()end
local function point(q,r)
    local a=q*math.pi/2
    return Vector(-r*math.sin(a),r*math.cos(a),664)
end
function M.finish()
    scheduler.cancel('main_island_art_review');scheduler.cancel('main_island_walk_probe')
    PlayerResource:SetCameraTarget(0,nil)
    GameRules:GetGameModeEntity():SetCameraDistanceOverride(1134)
    if valid(unit)then
        unit:Stop();unit:SetBaseMoveSpeed(original_speed)
        if original_origin then FindClearSpaceForUnit(unit,original_origin,false)end
    end
    if valid(anchor)then UTIL_Remove(anchor)end
    if viewer and RemoveFOWViewer then RemoveFOWViewer(2,viewer)end
    anchor=nil;unit=nil;viewer=nil;original_origin=nil;original_speed=nil
    print('MAIN_ISLAND_REVIEW_CLEAN')
end
function M.start()
    assert(IsInToolsMode() and GetMapName()=='main_island_review','Independent review map only')
    M.finish();GameRules:FinishCustomGameSetup()
    GameRules:GetGameModeEntity():SetCameraDistanceOverride(10000)
    anchor=SpawnEntityFromTableSynchronous('info_target',{targetname='main_island_review_camera'})
    anchor:SetAbsOrigin(Vector(0,-1500,640));PlayerResource:SetCameraTarget(0,anchor)
    viewer=AddFOWViewer(2,Vector(0,0,640),15000,600,false)
    scheduler.every(1,function()
        if GetMapName()~='main_island_review'then return false end
        scheduler.cancel('player_unbuilt_wall_defeat');return true
    end,'main_island_art_review')
    M.inspect()
end
function M.inspect()
    assert(GetMapName()=='main_island_review')
    print('MAIN_ISLAND_MAP',GetMapName(),GameRules:State_Get())
    for q=0,3 do
        for _,r in ipairs({3456,2816,2700,2480,2320,2200,640})do
            local p=point(q,r)
            print('MAIN_ISLAND_NAV',q,r,GridNav:IsTraversable(p),GridNav:IsBlocked(p),GetGroundHeight(p,nil))
        end
    end
    for _,p in ipairs({Vector(0,0,400),Vector(6000,0,400),Vector(1536,3456,640)})do
        print('MAIN_ISLAND_EDGE',p.x,p.y,GridNav:IsTraversable(p),GetGroundHeight(p,nil))
    end
end
function M.probe()
    assert(IsInToolsMode() and GetMapName()=='main_island_review')
    assert(not valid(unit),'Finish the previous probe before starting another')
    -- Use the actual controllable builder; autonomous lane/neutral creeps can
    -- overwrite scripted movement and are not reliable geometry probes here.
    for _,e in pairs(Entities:FindAllByClassname('npc_dota_creature'))do
        if e:GetUnitName()=='npc_survival_builder_proxy' then unit=e;break end
    end
    assert(valid(unit),'Wait for the builder to spawn first')
    original_origin=unit:GetAbsOrigin();original_speed=unit:GetBaseMoveSpeed()
    unit:SetBaseMoveSpeed(550);FindClearSpaceForUnit(unit,Vector(0,3456,664),false)
    local route={Vector(0,0,400),point(1,3456),Vector(0,0,400),point(2,3456),Vector(0,0,400),point(3,3456),Vector(0,0,400),point(0,3456)}
    local index=1;local start=GameRules:GetGameTime();probe_started=start
    unit:MoveToPosition(route[index]);print('MAIN_ISLAND_WALK_START')
    scheduler.every(.2,function()
        if not valid(unit)then return false end
        local p=unit:GetAbsOrigin();local distance=(p-route[index]):Length2D()
        if distance<55 then
            print('MAIN_ISLAND_WALK_PASS',index,p.x,p.y,p.z)
            index=index+1;start=GameRules:GetGameTime()
            if index>#route then print('MAIN_ISLAND_WALK_COMPLETE',GameRules:GetGameTime()-probe_started);return false end
            unit:MoveToPosition(route[index])
        elseif GameRules:GetGameTime()-start>25 then
            print('MAIN_ISLAND_WALK_FAIL',index,p.x,p.y,p.z,distance);return false
        end
        return true
    end,'main_island_walk_probe')
end
function M.camera(distance,x,y)
    assert(GetMapName()=='main_island_review')
    GameRules:GetGameModeEntity():SetCameraDistanceOverride(distance)
    if valid(anchor)then anchor:SetAbsOrigin(Vector(x,y,640))end
end
function M.probe_status()
    if not valid(unit)then print('MAIN_ISLAND_NO_UNIT');return end
    print('MAIN_ISLAND_UNIT',unit:GetAbsOrigin(),unit:GetIdealSpeed(),unit:IsRooted(),unit:IsStunned(),unit:GetPlayerOwnerID())
end
return M
