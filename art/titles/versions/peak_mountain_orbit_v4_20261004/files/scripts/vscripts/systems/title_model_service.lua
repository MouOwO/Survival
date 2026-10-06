-- Actual Source 2 mesh attached to the combat hero; never grants stats or collision.
local M = {}
local MODEL = "models/survival_titles/peak_perfection.vmdl"
local active = {}
local function valid(e) return e and (not e.IsNull or not e:IsNull()) end
local function alive(e) return valid(e) and (not e.IsAlive or e:IsAlive()) end
function M.clear(id)
    local state = active[id]
    if state and valid(state.body) then UTIL_Remove(state.body) end
    active[id] = nil
end
local function update(state, now)
    local unit, body = state.unit, state.body
    if not alive(unit) or not valid(body) then return false end
    -- Parent handles translation at engine frame rate. Keep readable world-facing
    -- orientation independent of the hero's attack/turn animation.
    body:SetLocalOrigin(Vector(0, 0, 285))
    body:SetAngles(0, math.sin(now * 0.8) * 6, 35)
    local cycle = now % 3
    local band = cycle < 0.9 and math.min(12, math.floor(cycle / 0.075) + 1) or 0
    if state.band ~= band then
        body:SetMaterialGroup(band == 0 and "default" or string.format("sweep_%02d", band))
        state.band = band
    end
    return true
end
function M.sync(id, unit, title_id)
    if title_id ~= "peak_perfection" or not alive(unit)
        or unit.survival_hide_custom_health_bar
        or (unit.IsIllusion and unit:IsIllusion()) then
        M.clear(id); return nil
    end
    -- Test harness / non-engine settlement never instantiates scene objects.
    if type(SpawnEntityFromTableSynchronous) ~= "function" then return nil end
    local state = active[id]
    if state and (state.unit ~= unit or not valid(state.body)) then M.clear(id); state = nil end
    if not state then
        local ok, body = pcall(SpawnEntityFromTableSynchronous, "prop_dynamic", {
            model = MODEL, solid = "0", spawnflags = "256", origin = "0 0 -2048",
            disableshadows = "1", disablereceiveshadows = "1",
        })
        if not ok or not valid(body) then return nil end
        state = {unit = unit, body = body}
        active[id] = state
        local configured, err = pcall(function()
            body:SetOwner(unit)
            body:SetParent(unit, "")
            body:SetModelScale(0.48)
            body.survival_title_prop = true
            update(state, GameRules:GetGameTime())
        end)
        if not configured then
            M.clear(id); print("[TitleModel] setup failed: " .. tostring(err)); return nil
        end
    end
    return {entindex=state.body:entindex(), height=285, width=178.4}
end
function M.init()
    require("core/scheduler").every(0.05, function()
        local now = GameRules:GetGameTime()
        for id, state in pairs(active) do
            local ok, keep = pcall(update, state, now)
            if not ok or not keep then M.clear(id) end
        end
    end, "title_mesh_update")
end
function M.precache(context) PrecacheResource("model", MODEL, context) end
return M
