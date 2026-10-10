-- Viewer-local cosmetic filtering. Virtual handles never escape to native APIs.
-- Release transfers a finite effect to the engine; its Lua ownership ends then.
local model_visual_particles = require("config/model_visual_particles")
local scheduler = require("core/scheduler")
local M, proxy = {}, {}
local VIRTUAL_BASE = 1000000000
local reduced, records, serial = {}, {}, VIRTUAL_BASE
local last_toggle, viewers, next_viewer_refresh = {}, {}, 0
local filtered_viewers = false
local owned_count, created_count, failed_count, peak_owned = 0, 0, 0, 0
local world
local function now() return GameRules and GameRules.GetGameTime and GameRules:GetGameTime() or 0 end
local function native() return _G.ParticleManager end
local function valid_handle(entity)
    if not entity then return true end
    local ok, deleted = pcall(function() return entity.IsNull and entity:IsNull() or false end)
    return ok and not deleted
end
local function refresh_viewers(force)
    local time = now()
    if not force and time < next_viewer_refresh then return end
    next_viewer_refresh, viewers, filtered_viewers = time + 1, {}, false
    if not PlayerResource or not PlayerResource.GetPlayer or not PlayerResource.IsValidPlayerID then return end
    for id = 0, 23 do
        if PlayerResource:IsValidPlayerID(id) then
            local player = PlayerResource:GetPlayer(id)
            if player then
                viewers[id] = player
                if reduced[id] then filtered_viewers = true end
            end
        end
    end
end
local function dispose(children, destroy, immediate)
    local pm, first_error = native()
    for _, handle in ipairs(children) do
        if destroy then
            local ok, err = pcall(pm.DestroyParticle, pm, handle, immediate)
            if not ok then first_error = first_error or err end
        end
        local ok, err = pcall(pm.ReleaseParticleIndex, pm, handle)
        if not ok then first_error = first_error or err end
    end
    return first_error
end
local function create_children(record)
    local pm = native()
    record.children = {}
    if record.released or record.destroyed or not valid_handle(record.owner) then return end
    local function create(player)
        local ok, handle
        if player then
            ok, handle = pcall(pm.CreateParticleForPlayer, pm, record.path, record.attach, record.owner, player)
        else
            ok, handle = pcall(pm.CreateParticle, pm, record.path, record.attach, record.owner)
        end
        if not ok or type(handle) ~= "number" or handle < 0 then
            local children = record.children
            record.children = {}
            dispose(children, true, true)
            failed_count = failed_count + 1
            error(ok and "Particle creation returned no valid native handle" or handle, 0)
        end
        if record.released or record.destroyed then
            dispose({handle}, true, true)
        else record.children[#record.children + 1] = handle end
    end
    if not record.protected and filtered_viewers and pm.CreateParticleForPlayer then
        for id, player in pairs(viewers) do if not reduced[id] then create(player) end end
    else create() end
end
function proxy:CreateParticle(path, attach, owner)
    refresh_viewers()
    local record = {path=path, attach=attach, owner=owner,
        protected=model_visual_particles.contains(path)}
    create_children(record)
    serial = serial + 1
    records[serial], record.id = record, serial
    owned_count, created_count = owned_count + 1, created_count + 1
    peak_owned = math.max(peak_owned, owned_count)
    return serial
end
function proxy:DestroyParticle(id, immediate)
    local record = records[id]
    if record then
        if record.destroyed then return end
        record.destroyed = true
        -- Consume destruction ownership before native calls, including reentry.
        local children = record.children
        record.children, record.release_children = {}, children
        local pm, first_error = native()
        for _, handle in ipairs(children) do
            local ok, err = pcall(pm.DestroyParticle, pm, handle, immediate)
            if not ok then first_error = first_error or err end
        end
        if first_error then error(first_error, 0) end
    elseif type(id) == "number" and id < VIRTUAL_BASE then native():DestroyParticle(id, immediate) end
end
function proxy:ReleaseParticleIndex(id)
    local record = records[id]
    if record then
        -- No 30-second history, GC scan, or forwarding to a recycled native ID.
        records[id], owned_count, record.released = nil, owned_count - 1, true
        local children = record.release_children or record.children
        record.children, record.release_children, record.controls = {}, nil, nil
        local err = dispose(children, false)
        if err then error(err, 0) end
    elseif type(id) == "number" and id < VIRTUAL_BASE then native():ReleaseParticleIndex(id) end
end
local function remember(record, method, point, ...)
    if record.protected then return end
    point = point == nil and "__particle__" or point
    -- Moving beams update stable argument slots, not new tables/string keys.
    local methods = record.controls
    if not methods then methods = {}; record.controls = methods end
    local points = methods[method]
    if not points then points = {}; methods[method] = points end
    local args = points[point]
    if not args then args = {}; points[point] = args end
    local count, previous = select("#", ...), args.n or 0
    args.n = count
    for i = 1, count do args[i] = select(i, ...) end
    for i = count + 1, previous do args[i] = nil end
end
function proxy:SetParticleControl(id, point, value)
    local record, pm = records[id], native()
    if record then
        if record.destroyed then return end
        remember(record, "SetParticleControl", point, point, value)
        for _, handle in ipairs(record.children) do pm:SetParticleControl(handle, point, value) end
    elseif type(id) == "number" and id < VIRTUAL_BASE then pm:SetParticleControl(id, point, value) end
end
setmetatable(proxy, {__index=function(self, key)
    local pm = native()
    if not pm or type(pm[key]) ~= "function" then return nil end
    local method = function(_, id, ...)
        local record, pm = records[id], native()
        if record then
            if record.destroyed then return end
            if key == "SetParticleControlEnt" and not valid_handle(select(2, ...)) then return end
            remember(record, key, select(1, ...), ...)
            for _, handle in ipairs(record.children) do pm[key](pm, handle, ...) end
        elseif type(id) ~= "number" or id < VIRTUAL_BASE then return pm[key](pm, id, ...) end
    end
    rawset(self, key, method)
    return method
end})
function M.manager() return proxy end
function M.set_reduced(id, value)
    value = value == true
    if (reduced[id] == true) == value then return end
    reduced[id] = value
    refresh_viewers(true)
    for _, record in pairs(records) do
        if not record.destroyed and not record.protected and not record.rebuilding then
            record.rebuilding = true
            local children = record.children
            record.children = {}
            dispose(children, true, true)
            local ok = pcall(create_children, record)
            if ok and records[record.id] == record and not record.destroyed then
                for method, points in pairs(record.controls or {}) do
                    for _, args in pairs(points) do
                        if method ~= "SetParticleControlEnt" or valid_handle(args[2]) then
                            for _, handle in ipairs(record.children) do
                                pcall(native()[method], native(), handle, unpack(args, 1, args.n))
                            end
                        end
                    end
                end
            end
            record.rebuilding = nil
        end
    end
end
function M.debug_snapshot()
    local handles = 0
    for _, record in pairs(records) do
        handles = handles + #(record.release_children or record.children)
    end
    return {owned_records=owned_count, owned_native_handles=handles,
        created=created_count, failed=failed_count, peak_owned_records=peak_owned}
end
function M.init()
    local current_world = GameRules and GameRules.GetGameModeEntity and GameRules:GetGameModeEntity() or GameRules
    -- Another map's IDs must never be destroyed after the engine recycled them.
    if world == current_world then
        local previous = records
        records = {}
        for _, record in pairs(previous) do
            dispose(record.release_children or record.children, not record.destroyed, true)
        end
    end
    world = current_world
    records, reduced, last_toggle, viewers = {}, {}, {}, {}
    owned_count, created_count, failed_count, peak_owned = 0, 0, 0, 0
    next_viewer_refresh, filtered_viewers = 0, false
    scheduler.cancel("combat_effect_records_gc")
    CustomGameEventManager:RegisterListener("ui_combat_effects_setting", function(_, payload)
        local id = tonumber(payload and payload.PlayerID)
        if not id or not PlayerResource:IsValidPlayerID(id) then return end
        local player = PlayerResource:GetPlayer(id)
        if not player then return end
        local time = now()
        if not last_toggle[id] or time - last_toggle[id] >= 0.25 then
            last_toggle[id] = time
            M.set_reduced(id, tonumber(payload.reduced) == 1)
        end
        CustomGameEventManager:Send_ServerToPlayer(player, "ui_combat_effects_state", {reduced=reduced[id] and 1 or 0})
    end)
end
return M
