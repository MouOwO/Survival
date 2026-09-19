-- Explicit art-review helper. Only runs in Tools on the independent review map.
local M={}
local anchor,viewer
local scheduler=require('core/scheduler')
local function valid(e)return e and not e:IsNull()end
function M.finish()
    scheduler.cancel('gold_room_art_review')
    PlayerResource:SetCameraTarget(0,nil)
    GameRules:GetGameModeEntity():SetCameraDistanceOverride(1134)
    if valid(anchor)then UTIL_Remove(anchor)end
    anchor=nil
    if viewer and RemoveFOWViewer then RemoveFOWViewer(2,viewer)end
    viewer=nil
    print('GOLD_ROOM_REVIEW_CLEAN')
end
function M.start()
    assert(IsInToolsMode() and GetMapName()=='gold_training_room_review','Independent Tools art map only')
    M.finish()
    GameRules:FinishCustomGameSetup()
    GameRules:GetGameModeEntity():SetCameraDistanceOverride(3400)
    anchor=SpawnEntityFromTableSynchronous('info_target',{targetname='gold_room_review_camera'})
    anchor:SetAbsOrigin(Vector(0,140,128));PlayerResource:SetCameraTarget(0,anchor)
    viewer=AddFOWViewer(2,Vector(0,0,128),5000,600,false)
    -- This art sample has no player base; prevent the normal build-a-wall
    -- deadline from covering the review with a defeat screen. No CSV changes.
    scheduler.cancel('player_unbuilt_wall_defeat')
    scheduler.every(1,function()
        if GetMapName()~='gold_training_room_review' then return false end
        scheduler.cancel('player_unbuilt_wall_defeat')
        return true
    end,'gold_room_art_review')
    M.inspect()
end
function M.inspect()
    assert(GetMapName()=='gold_training_room_review')
    print('GOLD_ROOM_MAP',GetMapName(),GameRules:State_Get())
    for _,name in ipairs({'challenge_02_entry','challenge_02_home','challenge_02_spawn_01','challenge_02_spawn_05'})do
        local e=Entities:FindByName(nil,name);local p=e and e:GetAbsOrigin()
        print('GOLD_ROOM_MARKER',name,p and p.x,p and p.y,p and p.z,p and GetGroundHeight(p,nil),p and GridNav:IsTraversable(p),p and GridNav:IsBlocked(p))
    end
    for _,x in ipairs({0,900,1024,1200})do
        local p=Vector(x,0,128)
        print('GOLD_ROOM_NAV',x,GridNav:IsTraversable(p),GridNav:IsBlocked(p))
    end
end
return M
