-- Explicit Tools-only render fixture; never loaded by the addon.
local M={}
local props={}
local viewer

function M.clear()
    assert(IsInToolsMode(),"Tools-only")
    PlayerResource:SetCameraTarget(0,nil)
    for _,prop in ipairs(props) do if not prop:IsNull() then UTIL_Remove(prop) end end
    props={}
    if viewer and RemoveFOWViewer then RemoveFOWViewer(2,viewer) end
    viewer=nil
    print("WALL_FIXTURE_CLEARED")
end

function M.show(first,count)
    assert(IsInToolsMode(),"Tools-only")
    M.clear()
    count=count or 5
    assert(first>=1 and count>=1 and first+count-1<=10,'wall fixture range')
    local origin=GetGroundPosition(Vector(0,-384,128),nil)
    for i=0,count-1 do
        local stage=first+i
        local model=string.format("models/survival_buildings/wall_lv%02d.vmdl",stage)
        local pos=origin+Vector((i-(count-1)/2)*310,0,0)
        pos=GetGroundPosition(pos,nil)
        local prop=assert(SpawnEntityFromTableSynchronous("prop_dynamic",{
            targetname="wall_review_"..stage,model=model,solid="0",renderamt="255",rendercolor="255 255 255",
        }))
        prop:SetAbsOrigin(pos);prop:SetAngles(0,180,0);prop:SetModelScale(1)
        props[#props+1]=prop
        for line=0,4 do
            local q=-128+line*64
            DebugDrawLine(pos+Vector(q,-128,2),pos+Vector(q,128,2),80,220,160,false,120)
            DebugDrawLine(pos+Vector(-128,q,2),pos+Vector(128,q,2),80,220,160,false,120)
        end
        print("WALL_FIXTURE",stage,prop:entindex(),prop:GetModelName(),prop:GetAbsOrigin(),prop:GetModelScale())
    end
    -- info_target is server-only; the camera needs a networked model entity.
    PlayerResource:SetCameraTarget(0,props[math.ceil(count/2)])
    viewer=AddFOWViewer(2,origin,1400,120,false)
end

return M
