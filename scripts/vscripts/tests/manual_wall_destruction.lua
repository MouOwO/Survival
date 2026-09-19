-- Explicit Tools-only probe. Uses disposable walls, no economy / live-wall edits.
local M={}
local fx=require('systems/wall_destruction_visual')
local scheduler=require('core/scheduler')
local unit,anchor,handle,started,viewer
local function valid(e)return e and not e:IsNull()end
function M.clear()
    assert(IsInToolsMode(),'Tools-only')
    scheduler.cancel('wall_death_probe_freeze')
    scheduler.cancel('wall_death_probe_cleanup_sample')
    for i=1,4 do scheduler.cancel('wall_death_probe_capture_'..i)end
    for i=1,2 do scheduler.cancel('wall_death_probe_defeat_'..i)end
    fx.reset()
    if valid(unit)then UTIL_Remove(unit)end
    if valid(anchor)then UTIL_Remove(anchor)end
    unit=nil;anchor=nil;handle=nil
    if viewer and RemoveFOWViewer then RemoveFOWViewer(2,viewer)end
    viewer=nil
    PlayerResource:SetCameraTarget(0,nil)
    PauseGame(false)
    print('WALL_DEATH_PROBE_CLEAN',fx.active_count(),#Entities:FindAllByName('survival_wall_death_*'))
end
function M.start(stage,freeze_at)
    assert(IsInToolsMode(),'Tools-only')
    M.clear()
    local origin=GetGroundPosition(Vector(0,-384,128),nil)
    unit=assert(CreateUnitByName('building_wall',origin,false,nil,nil,2))
    local model=string.format('models/survival_buildings/wall_lv%02d.vmdl',stage or 10)
    unit:SetModel(model);unit:SetOriginalModel(model);unit:SetModelScale(1);unit:SetAngles(0,180,0);unit:SetHullRadius(0)
    anchor=SpawnEntityFromTableSynchronous('prop_dynamic',{targetname='wall_death_probe_camera',model='models/development/invisiblebox.vmdl',solid='0',rendermode='1',renderamt='0'})
    -- Offset the sample away from the game's centered pause overlay.
    anchor:SetAbsOrigin(origin+Vector(-420,0,0));PlayerResource:SetCameraTarget(0,anchor)
    viewer=AddFOWViewer(2,origin,1000,90,false)
    unit:ForceKill(false) -- Service-only probe, deliberately bypass engine death events.
    started=GameRules:GetGameTime()
    handle=assert(fx.play({building_id='wall',unit=unit}))
    print('WALL_DEATH_PROBE_START',stage,started,origin,handle.height)
    if freeze_at then M.freeze_at(freeze_at)end
end
function M.freeze_at(offset)
    assert(handle,'start first')
    PauseGame(false)
    scheduler.after(math.max(.01,started+offset-GameRules:GetGameTime()),function()
        local p=handle.proxy
        print('WALL_DEATH_PROBE_FRAME',GameRules:GetGameTime()-started,handle.exploded==true,
            p and not p:IsNull() and p:GetAbsOrigin() or 'removed',#handle.particles)
        PauseGame(true)
    end,'wall_death_probe_freeze')
end
function M.finish()
    PauseGame(false)
    scheduler.after(2.8,function()
        print('WALL_DEATH_PROBE_FINISHED',fx.active_count(),#Entities:FindAllByName('survival_wall_death_*'))
    end,'wall_death_probe_cleanup_sample')
end
-- Unpaused timing samples. Screenshots must come from the console because
-- Source 2 intentionally rejects screenshot through SendToConsole.
function M.trace(stage)
    M.start(stage)
    for i,offset in ipairs({.72,1.12,1.42})do
        local frame=i
        scheduler.after(offset,function()
            print('WALL_DEATH_TRACE',frame,GameRules:GetGameTime()-started,handle.exploded==true)
        end,'wall_death_probe_capture_'..frame)
    end
    scheduler.after(2.8,function()
        print('WALL_DEATH_PROBE_FINISHED',fx.active_count(),#Entities:FindAllByName('survival_wall_death_*'))
        PauseGame(true)
    end,'wall_death_probe_capture_4')
end
-- Deliberately ends this disposable Tools round. Verifies the real engine death
-- event, building cleanup and delayed SetGameWinner (no manual fx.play call).
function M.defeat_test()
    M.clear()
    local bus=require('core/event_bus')
    local events=require('core/events')
    unit=assert(CreateUnitByName('building_wall',Vector(512,-384,128),false,nil,nil,2))
    unit:SetModel('models/survival_buildings/wall_lv01.vmdl')
    unit:SetOriginalModel('models/survival_buildings/wall_lv01.vmdl')
    unit:SetModelScale(1);unit:SetAngles(0,180,0)
    unit.survival_is_building=true;unit.survival_building_id='wall'
    unit.survival_player_id=0;unit.survival_level=1
    local id=unit:entindex()
    assert(bus.request(events.BUILDING_QUERY_REQUEST,{entindex=id}),'fixture registration failed')
    started=GameRules:GetGameTime()
    -- ForceKill bypasses entity_killed in this Workshop build. Kill follows the
    -- combat death path and supplies an attacker so the engine publishes it.
    unit:Kill(nil,unit)
    for i,delay in ipairs({.15,1.15})do
        local sample=i
        scheduler.after(delay,function()
            print('WALL_DEATH_REGISTERED',sample,GameRules:GetGameTime()-started,
                fx.active_count(),#Entities:FindAllByName('survival_wall_death_*'),
                bus.request(events.BUILDING_QUERY_REQUEST,{entindex=id})==nil,GameRules:State_Get())
        end,'wall_death_probe_defeat_'..sample)
    end
end
return M
