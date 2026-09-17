-- A dead wall becomes a non-solid visual prop. Gameplay cleanup stays immediate.
local scheduler = require("core/scheduler")
local profiles = require("config/generated/wall_destruction_models")
local M = { shake_seconds=1.0, defeat_delay=1.45, lifetime=2.6 }
local active, next_id = {}, 0
local prefix = "particles/survival_buildings/wall_death_"
local particle_names = { "charge", "sparks", "flash", "ring", "shards", "dust" }
local shard_model = "models/survival_buildings/wall_death_shard.vmdl"
local sound_file = "soundevents/game_sounds_heroes/game_sounds_crystalmaiden.vsndevts"

local function valid(entity)
    return entity and (not entity.IsNull or not entity:IsNull())
end
local function copy(v) return Vector(v.x,v.y,v.z) end
local function remove(entity)
    if valid(entity) and UTIL_Remove then UTIL_Remove(entity) end
end
local function clear_particles(handle,graceful)
    for _,index in ipairs(handle.particles) do
        pcall(function() ParticleManager:DestroyParticle(index,not graceful) end)
        pcall(function() ParticleManager:ReleaseParticleIndex(index) end)
    end
    handle.particles={}
end
local function particle(handle,name,position)
    if not ParticleManager then return end
    local index
    local ok,err=pcall(function()
        index=ParticleManager:CreateParticle(prefix..name..".vpcf",PATTACH_WORLDORIGIN,nil)
        assert(index and index>=0,"particle allocation failed")
        -- Independent world positions survive removal of the real wall/proxy.
        ParticleManager:SetParticleControl(index,0,position)
        ParticleManager:SetParticleControl(index,1,Vector(128*handle.scale,handle.height,1))
    end)
    if ok then handle.particles[#handle.particles+1]=index
    else
        if index and index>=0 then
            pcall(function() ParticleManager:DestroyParticle(index,true) end)
            pcall(function() ParticleManager:ReleaseParticleIndex(index) end)
        end
        print("[WallDestruction] particle failed: "..name.." "..tostring(err))
    end
end
local destroy
local function deliver_callback(handle)
    local callback=handle.after_burst
    handle.after_burst=nil
    if callback then
        -- SetGameWinner can freeze GameTime. Release server handles before the
        -- callback; finite particles finish naturally instead of being cut off.
        destroy(handle,true)
        local ok,err=pcall(callback)
        if not ok then print("[WallDestruction] completion failed: "..tostring(err)) end
    end
end
destroy=function(handle,graceful)
    if handle.finished then return end
    handle.finished=true
    if handle.task then scheduler.cancel(handle.task) end
    clear_particles(handle,graceful)
    remove(handle.proxy);handle.proxy=nil
    active[handle.id]=nil
end
local function explode(handle)
    if handle.exploded then return end
    handle.exploded=true
    clear_particles(handle)
    particle(handle,"flash",handle.center)
    particle(handle,"ring",handle.origin+Vector(0,0,12))
    particle(handle,"shards",handle.center)
    particle(handle,"dust",handle.center)
    if EmitSoundOnLocationWithCaster and valid(handle.proxy) then
        pcall(EmitSoundOnLocationWithCaster,handle.center,"Hero_Crystal.CrystalNova",handle.proxy)
    end
    remove(handle.proxy);handle.proxy=nil
end
local function tick(handle)
    local elapsed=GameRules:GetGameTime()-handle.started
    if elapsed<M.shake_seconds then
        if valid(handle.proxy) then
            local t=math.max(0,elapsed/M.shake_seconds)
            local amplitude=(1.5+6*t*t)*handle.scale
            handle.proxy:SetAbsOrigin(handle.origin+Vector(
                math.sin(elapsed*89)*amplitude,
                math.sin(elapsed*113+.7)*amplitude*.7,
                math.abs(math.sin(elapsed*93))*t*1.4))
            handle.proxy:SetAngles(math.sin(elapsed*73)*t*1.15,handle.yaw,
                math.sin(elapsed*97)*t*1.45)
        end
    else explode(handle) end
    if elapsed>=M.defeat_delay then deliver_callback(handle) end
    if handle.finished then return false end
    if elapsed>=M.lifetime then destroy(handle);return false end
    return true
end

function M.play(state)
    local unit=state and state.unit
    if not state or state.building_id~="wall" or state.constructing
        or not valid(unit) or unit.survival_disconnect_cleanup
        or unit.survival_wall_destruction_started then return nil end
    local model=unit.GetModelName and unit:GetModelName()
    if not profiles[model] or not SpawnEntityFromTableSynchronous then return nil end
    next_id=next_id+1
    local handle={id=next_id,particles={},started=GameRules:GetGameTime()}
    local ok,err=pcall(function()
        handle.origin=copy(unit:GetAbsOrigin())
        handle.scale=unit:GetModelScale()
        handle.yaw=unit:GetAnglesAsVector().y
        handle.height=profiles[model]*handle.scale
        handle.center=handle.origin+Vector(0,0,handle.height*.55)
        handle.proxy=SpawnEntityFromTableSynchronous("prop_dynamic",{
            targetname="survival_wall_death_"..handle.id,model=model,solid="0",
            origin=string.format("%f %f %f",handle.origin.x,handle.origin.y,handle.origin.z),
            angles=string.format("0 %f 0",handle.yaw),renderamt="255",rendercolor="255 255 255",
        })
        assert(valid(handle.proxy),"wall visual prop creation failed")
        handle.proxy:SetAbsOrigin(handle.origin)
        handle.proxy:SetAngles(0,handle.yaw,0)
        handle.proxy:SetModelScale(handle.scale)
        unit:AddNoDraw()
        handle.hid_unit=true
        -- Keep the charging core above the opaque deck / crenellations.
        particle(handle,"charge",handle.origin+Vector(0,0,handle.height*.98))
        particle(handle,"sparks",handle.origin+Vector(0,0,handle.height*.98))
        active[handle.id]=handle
        handle.task=scheduler.every(.03,function()
            if handle.finished then return false end
            local success,keep=pcall(tick,handle)
            if not success then
                print("[WallDestruction] update failed: "..tostring(keep))
                deliver_callback(handle);destroy(handle);return false
            end
            return keep
        end,"wall_destruction_"..handle.id)
        unit.survival_wall_destruction_started=true
    end)
    if not ok then
        destroy(handle)
        if handle.hid_unit and valid(unit) and unit.RemoveNoDraw then unit:RemoveNoDraw() end
        print("[WallDestruction] start failed: "..tostring(err))
        return nil
    end
    return handle
end

-- Reserve defeat immediately in building_system, but let the burst be visible
-- before SetGameWinner stops the gameplay clock / covers the scene with UI.
function M.after_burst(handle,callback)
    if not handle or handle.finished then
        callback()
    else
        handle.after_burst=callback
        if GameRules:GetGameTime()-handle.started>=M.defeat_delay then deliver_callback(handle) end
    end
end

function M.precache(context)
    for _,name in ipairs(particle_names) do PrecacheResource("particle",prefix..name..".vpcf",context) end
    PrecacheResource("model",shard_model,context)
    PrecacheResource("soundfile",sound_file,context)
end

function M.reset()
    local pending={}
    for _,handle in pairs(active) do pending[#pending+1]=handle end
    for _,handle in ipairs(pending) do handle.after_burst=nil;destroy(handle) end
end
function M.active_count()
    local count=0;for _ in pairs(active) do count=count+1 end;return count
end
return M
