-- Tools-only visual probe. Explicitly invoked; never loaded by the addon.
local M = {}
local visual = require("systems/building_construction_visual_service")
local shells = require("systems/building_white_shell")
local scheduler = require("core/scheduler")
local city, state

function M.prepare(freeze_for_capture)
    assert(IsInToolsMode(), "presentation probe is Tools-only")
    local bus = require("core/event_bus")
    local events = require("core/events")
    if freeze_for_capture then
        local subscription
        subscription=bus.subscribe(events.BUILDING_CREATED,function(data)
            if data.building_id~="main_city" then return end
            bus.unsubscribe(subscription)
            scheduler.after(1.2,function() M.start();PauseGame(true) end,"white_probe_freeze")
        end)
    end
    bus.request(events.WAVE_DIFFICULTY_SET_REQUEST,{player_id=0,difficulty_id="N1"})
    local owner = assert(bus.request(events.BUILDER_GET_REQUEST,{player_id=0}))
    local builder = assert(owner.builder)
    builder:SetAbsOrigin(Vector(0,-96,128))
    local result = bus.request(events.BUILD_REQUEST,{
        player_id=0,caster=builder,building_id="main_city",position=Vector(0,128,128),
    })
    print("WHITE_PREPARE",result and result.ok,result and result.error)
end

function M.start()
    assert(IsInToolsMode(), "presentation probe is Tools-only")
    city=nil
    for _,unit in ipairs(Entities:FindAllByClassname("npc_dota_creature")) do
        if unit:GetUnitName()=="building_main_city" and unit:IsAlive() then city=unit;break end
    end
    assert(city,"build a main city before running the probe")
    local def={}
    for key,value in pairs(require("config/buildings_config").main_city) do def[key]=value end
    def.build_time=60
    state=assert(visual.start(city,def),"construction visual did not start")
    PlayerResource:SetCameraTarget(0,city)
    local handle=assert(state.loop_particles[1])
    assert(shells.is_handle(handle),"construction did not select white shell")
    print("WHITE_HOLD",city:entindex(),city:GetAnglesAsVector(),handle.entity:GetAbsOrigin(),handle.entity:GetRenderAlpha())
end

function M.finish(freeze_for_capture)
    assert(state,"start probe first")
    if freeze_for_capture then PauseGame(false) end
    assert(visual.complete(state),"completion failed")
    state=nil
    for _,delay in ipairs({0.1,0.75,1.7}) do
        scheduler.after(delay,function()
            local props=Entities:FindAllByName("survival_build_white_*")
            print("WHITE_CURTAIN",delay,#props,props[1] and props[1]:GetMaterialGroupHash(),city:GetAnglesAsVector())
        end,"white_probe_sample_"..delay)
    end
    if freeze_for_capture then
        scheduler.after(1.9,function() PauseGame(true) end,"white_probe_freeze")
    end
end

function M.cleanup()
    if state then visual.cancel(state);state=nil end
    shells.reset()
    if city and not city:IsNull() then city:RemoveNoDraw() end
    PlayerResource:SetCameraTarget(0,nil)
    PauseGame(false)
end

function M.upgrade()
    if not city or city:IsNull() then
        for _,unit in ipairs(Entities:FindAllByClassname("npc_dota_creature")) do
            if unit:GetUnitName()=="building_main_city" and unit:IsAlive() then city=unit;break end
        end
    end
    assert(IsInToolsMode() and city and not city:IsNull(),"probe city is unavailable")
    local def=require("config/buildings_config").main_city
    local original_model,original_level=city:GetModelName(),city.survival_level
    local result=require("systems/building_upgrade_process").begin(city,{
        definition=def,duration=2,particle=def.build_loop_particle,target_level=2,
        on_complete=function()
            city.survival_level=2
            city:SetModel(def.levels[2].model_name)
            city:SetOriginalModel(def.levels[2].model_name)
        end,
    })
    assert(result.ok,"upgrade probe could not start")
    scheduler.after(2.15,function()
        local props=Entities:FindAllByName("survival_build_white_*")
        assert(#props==1 and props[1]:GetModelName():find("main_city_lv02_white_shell",1,true))
        print("WHITE_UPGRADE_FINAL_MODEL",props[1]:GetModelName(),city:GetAnglesAsVector())
    end,"white_probe_upgrade_model")
    scheduler.after(3.7,function()
        assert(shells._active_count_for_test()==0,"upgrade shell leaked")
        city.survival_level=original_level
        city:SetModel(original_model);city:SetOriginalModel(original_model)
        print("WHITE_UPGRADE_PASS")
    end,"white_probe_upgrade_restore")
end

local fixtures={}
function M.flow_fixture()
    assert(IsInToolsMode(),"Tools-only")
    M.clear_fixture()
    for i,step in ipairs({0,24,48}) do
        local p=GetGroundPosition(Vector((i-2)*300,-128,128),nil)
        for _,kind in ipairs({"base","flow"}) do
            local model="models/survival_buildings/main_city_lv01"..(kind=="flow" and "_white_shell" or "")..".vmdl"
            local ent=SpawnEntityFromTableSynchronous("prop_dynamic",{
                targetname="flow_fixture_"..i.."_"..kind,model=model,solid="0",
                disableshadows="1",rendermode="1",renderamt="255",rendercolor="255 255 255",
            })
            ent:SetAbsOrigin(p);ent:SetAngles(0,0,0);ent:SetModelScale(kind=="flow" and 1.006 or 1)
            if kind=="flow" and step>0 then ent:SetMaterialGroup(string.format("reveal_%02d",step)) end
            fixtures[#fixtures+1]=ent
            print("FLOW_FIXTURE",i,kind,ent:entindex(),ent:GetModelName(),ent:GetAbsOrigin())
            if i==2 and kind=="base" then PlayerResource:SetCameraTarget(0,ent) end
        end
        AddFOWViewer(2,p,600,600,false)
    end
end
function M.clear_fixture()
    for _,ent in ipairs(fixtures) do if not ent:IsNull() then UTIL_Remove(ent) end end
    fixtures={}
    PlayerResource:SetCameraTarget(0,nil)
end
return M
