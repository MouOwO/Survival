-- Opt-in art review only. Does not start or modify the actual challenge service.
local M={}
local scheduler=require('core/scheduler')
local anchor,viewer,builder,old_origin,old_speed
local function valid(e)return e and not e:IsNull()end
function M.finish()
    scheduler.cancel('molten_room_art_review');scheduler.cancel('molten_room_walk_probe')
    PlayerResource:SetCameraTarget(0,nil)
    GameRules:GetGameModeEntity():SetCameraDistanceOverride(1134)
    if valid(builder)then
        builder:Stop();builder:SetBaseMoveSpeed(old_speed)
        FindClearSpaceForUnit(builder,old_origin,false)
    end
    if valid(anchor)then UTIL_Remove(anchor)end
    if viewer and RemoveFOWViewer then RemoveFOWViewer(2,viewer)end
    anchor=nil;viewer=nil;builder=nil;old_origin=nil;old_speed=nil
    print('MOLTEN_ROOM_CLEAN')
end
function M.start()
    assert(IsInToolsMode() and GetMapName()=='molten_core_room_review','Independent Tools art map only')
    M.finish();GameRules:FinishCustomGameSetup()
    anchor=SpawnEntityFromTableSynchronous('info_target',{targetname='molten_room_review_camera'})
    anchor:SetAbsOrigin(Vector(0,-350,128));PlayerResource:SetCameraTarget(0,anchor)
    GameRules:GetGameModeEntity():SetCameraDistanceOverride(3600)
    viewer=AddFOWViewer(2,Vector(0,0,128),6000,600,false)
    scheduler.every(1,function()
        if GetMapName()~='molten_core_room_review'then return false end
        scheduler.cancel('player_unbuilt_wall_defeat');return true
    end,'molten_room_art_review')
    M.inspect()
end
function M.inspect()
    assert(GetMapName()=='molten_core_room_review')
    print('MOLTEN_ROOM_MAP',GetMapName(),GameRules:State_Get())
    for _,name in ipairs({'challenge_07_entry','challenge_07_home','challenge_07_boss_spawn','challenge_07_spawn_01','challenge_07_spawn_06'})do
        local e=Entities:FindByName(nil,name);local p=e and e:GetAbsOrigin()
        print('MOLTEN_ROOM_MARKER',name,p and p.x,p and p.y,p and p.z,p and GetGroundHeight(p,nil),p and GridNav:IsTraversable(p),p and GridNav:IsBlocked(p))
    end
    for _,xy in ipairs({{0,0},{800,0},{-800,0},{0,-960},{0,1280},{1024,0},{1104,0},{0,-1152},{0,1450}})do
        local p=Vector(xy[1],xy[2],128)
        print('MOLTEN_ROOM_NAV',p.x,p.y,GridNav:IsTraversable(p),GridNav:IsBlocked(p),GetGroundHeight(p,nil))
    end
end
function M.probe()
    assert(IsInToolsMode() and GetMapName()=='molten_core_room_review')
    assert(not valid(builder),'Finish previous probe first')
    for _,e in pairs(Entities:FindAllByClassname('npc_dota_creature'))do
        if e:GetUnitName()=='npc_survival_builder_proxy'then builder=e;break end
    end
    assert(valid(builder),'Wait for actual builder spawn')
    old_origin=builder:GetAbsOrigin();old_speed=builder:GetBaseMoveSpeed()
    builder:SetBaseMoveSpeed(420);FindClearSpaceForUnit(builder,Vector(0,1096,152),false)
    local route={Vector(0,-140,152),Vector(-800,-900,152),Vector(800,-900,152),Vector(800,900,152),Vector(-800,900,152),Vector(0,1096,152)}
    local index=1;local started=GameRules:GetGameTime();local legstart=started
    builder:MoveToPosition(route[1]);print('MOLTEN_ROOM_WALK_START')
    scheduler.every(.2,function()
        if not valid(builder)then return false end
        local p=builder:GetAbsOrigin();local d=(p-route[index]):Length2D()
        if d<50 then
            print('MOLTEN_ROOM_WALK_PASS',index,p.x,p.y,p.z)
            index=index+1;legstart=GameRules:GetGameTime()
            if index>#route then print('MOLTEN_ROOM_WALK_COMPLETE',GameRules:GetGameTime()-started);return false end
            builder:MoveToPosition(route[index])
        elseif GameRules:GetGameTime()-legstart>20 then
            print('MOLTEN_ROOM_WALK_FAIL',index,p.x,p.y,p.z,d);return false
        end
        return true
    end,'molten_room_walk_probe')
end
return M
