-- Viewer-local cosmetic filtering. Projectiles, damage, targeting and timing
-- remain native. Only selected hero/tower particle creation sites use this proxy.
local model_visual_particles = require("config/model_visual_particles")
local M = {}
local reduced, records, serial = {}, {}, 1000000000
local last_toggle = {}
local viewers, next_viewer_refresh = {}, 0
local scheduler = require("core/scheduler")
local function now() return GameRules and GameRules.GetGameTime and GameRules:GetGameTime() or 0 end
local function refresh_viewers(force)
    if not force and now() < next_viewer_refresh then return end
    next_viewer_refresh = now() + 1
    viewers = {}
    if not PlayerResource or not PlayerResource.GetPlayer or not PlayerResource.IsValidPlayerID then return end
    for id=0,23 do
        if PlayerResource:IsValidPlayerID(id) then
            local player=PlayerResource:GetPlayer(id)
            if player then viewers[id]=player end
        end
    end
end
local function filtered()
    for id in pairs(viewers) do if reduced[id] then return true end end
    return false
end
local function native() return _G.ParticleManager end
local function valid_handle(entity)
    if not entity then return true end
    local ok,deleted=pcall(function() return entity.IsNull and entity:IsNull() or false end)
    return ok and not deleted
end
local function create_children(record)
    local pm=native()
    record.children={}
    if not valid_handle(record.owner) then return end
    if not model_visual_particles.contains(record.path)
        and filtered() and pm.CreateParticleForPlayer then
        for id,player in pairs(viewers) do
            if not reduced[id] then
                local handle=pm:CreateParticleForPlayer(record.path,record.attach,record.owner,player)
                record.children[#record.children+1]=handle
            end
        end
    else
        record.children[1]=pm:CreateParticle(record.path,record.attach,record.owner)
    end
end
local proxy={}
function proxy:CreateParticle(path,attach,owner)
    refresh_viewers()
    local record={path=path,attach=attach,owner=owner,controls={}}
    create_children(record)
    serial=serial+1;records[serial]=record
    return serial
end
function proxy:DestroyParticle(id,immediate)
    local record=records[id]
    if record then
        if record.destroyed then return end
        record.destroyed=true
        for _,handle in ipairs(record.children) do native():DestroyParticle(handle,immediate) end
        if record.released then records[id]=nil end
    elseif id < 1000000000 then native():DestroyParticle(id,immediate) end
end
function proxy:ReleaseParticleIndex(id)
    local record=records[id]
    if record then
        if record.released then return end
        record.released=true;record.expires=now()+30;record.controls={}
        record.owner,record.path=nil,nil
        for _,handle in ipairs(record.children) do native():ReleaseParticleIndex(handle) end
        if record.destroyed or #record.children==0 then records[id]=nil end
    elseif id < 1000000000 then native():ReleaseParticleIndex(id) end
end
setmetatable(proxy,{__index=function(self,key)
    local pm=native()
    if not pm or type(pm[key])~="function" then return nil end
    local method=function(_,id,...)
        local pm=native()
        local record=records[id]
        if record then
            if record.destroyed then return end
            local args={...}
            if key=="SetParticleControlEnt" and not valid_handle(args[2]) then return end
            if not record.released then record.controls[key..":"..tostring(args[1])]={method=key,args=args} end
            for _,handle in ipairs(record.children) do pm[key](pm,handle,unpack(args)) end
        elseif type(id)~="number" or id < 1000000000 then return pm[key](pm,id,...) end
    end
    rawset(self,key,method);return method
end})
function M.manager() return proxy end
function M.set_reduced(id,value)
    value = value == true
    if (reduced[id] == true) == value then return end
    reduced[id]=value;refresh_viewers(true)
    -- Model appearance particles are always visible and keep their handles.
    -- Persistent combat areas switch immediately. One-shot effects already released
    -- finish naturally; never touch a released native particle twice.
    for _,record in pairs(records) do
        if not record.released and not record.destroyed
            and not model_visual_particles.contains(record.path) then
            for _,handle in ipairs(record.children) do
                native():DestroyParticle(handle,true);native():ReleaseParticleIndex(handle)
            end
            create_children(record)
            for _,control in pairs(record.controls) do
                if control.method~="SetParticleControlEnt" or valid_handle(control.args[2]) then
                    for _,handle in ipairs(record.children) do
                        native()[control.method](native(),handle,unpack(control.args))
                    end
                end
            end
        end
    end
end
function M.init()
    reduced={};last_toggle={};next_viewer_refresh=0
    scheduler.every(2,function()
        local time=now()
        for id,record in pairs(records) do
            if record.released and time >= record.expires then records[id]=nil end
        end
    end,"combat_effect_records_gc")
    CustomGameEventManager:RegisterListener("ui_combat_effects_setting",function(_,payload)
        local id=tonumber(payload and payload.PlayerID)
        if not id or not PlayerResource:IsValidPlayerID(id) then return end
        local player=PlayerResource:GetPlayer(id)
        if not player then return end
        local time=now()
        if not last_toggle[id] or time-last_toggle[id]>=0.25 then
            last_toggle[id]=time
            M.set_reduced(id,tonumber(payload.reduced)==1)
        end
        CustomGameEventManager:Send_ServerToPlayer(player,"ui_combat_effects_state",{reduced=reduced[id] and 1 or 0})
    end)
end
return M
