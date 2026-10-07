local definitions = require("config/challenge_guardians")
local M = {}
local active = {}
local TASK = "challenge_guardian_cleanup"
local function valid(e) return e and (not e.IsNull or not e:IsNull()) end
local function remove(e) if valid(e) then UTIL_Remove(e) end end
local function supported(unit)
    return valid(unit) and unit.GetUnitName and definitions[unit:GetUnitName()]
end
local function cleanup_state(state)
    for _, part in ipairs(state.parts or {}) do remove(part) end
    remove(state.body)
    if valid(state.owner) and state.owner.survival_guardian_visual == state then
        state.owner.survival_guardian_visual = nil
    end
    active[state] = nil
end
function M.clear(unit)
    local state = unit and unit.survival_guardian_visual
    if state and state.owner == unit then cleanup_state(state) end
end
local function freeze(body, definition)
    body:ResetSequence(definition.sequence)
    body:SetCycle(definition.cycle or 0)
    -- prop_dynamic exposes this as an entity input rather than an NPC method.
    DoEntFireByInstanceHandle(body, "SetPlaybackRate", "0", 0, nil, nil)
end
function M.apply(unit)
    local definition = supported(unit)
    if not definition then return false, "not_challenge_building" end
    if unit.IsAlive and not unit:IsAlive() then M.clear(unit); return false, "dead" end
    if unit.HasModifier and unit:HasModifier("modifier_building_under_construction") then
        M.clear(unit); return false, "constructing"
    end
    local current = unit.survival_guardian_visual
    if current and current.owner == unit and valid(current.body) then
        local complete = #current.parts == #definition.parts
        for _, part in ipairs(current.parts) do complete = complete and valid(part) end
        if complete then return true end
    end
    M.clear(unit)
    local state = { owner = unit, parts = {}, definition = definition }
    local ok, err = pcall(function()
        local body = assert(SpawnEntityFromTableSynchronous("prop_dynamic", {
            model = definition.body, DefaultAnim = definition.sequence,
            solid = "0", spawnflags = "256", origin = "0 0 -2048",
        }), "guardian body creation failed")
        state.body = body
        body:SetOwner(unit)
        body:SetParent(unit, "")
        body:SetLocalOrigin(Vector(unpack(definition.offset)))
        body:SetLocalAngles(0, definition.yaw, 0)
        body:SetModelScale(definition.scale)
        body.survival_challenge_guardian = true
        for _, model in ipairs(definition.parts) do
            local part = assert(SpawnEntityFromTableSynchronous("prop_dynamic", {
                model = model, solid = "0", spawnflags = "256", origin = "0 0 -2048",
            }), "guardian equipment creation failed")
            table.insert(state.parts, part)
            part:SetOwner(unit)
            part:SetParent(body, "")
            part:FollowEntity(body, true)
            if part.AddEffects and EF_BONEMERGE then part:AddEffects(EF_BONEMERGE) end
            part.survival_challenge_guardian = true
        end
        freeze(body, definition)
    end)
    if not ok then cleanup_state(state); print("[ChallengeGuardian] " .. tostring(err)); return false, err end
    unit.survival_guardian_visual = state
    active[state] = true
    return true
end
function M.precache(context)
    local seen = {}
    for _, definition in pairs(definitions) do
        for _, model in ipairs({definition.body, unpack(definition.parts)}) do
            if not seen[model] then PrecacheResource("model", model, context); seen[model] = true end
        end
    end
end
function M.init()
    -- Tools can retain Lua modules while replacing the game-mode scheduler.
    -- Always rebind the task; applying an intact ornament is idempotent.
    require("core/scheduler").cancel(TASK)
    for _, classname in ipairs({"npc_dota_creature", "npc_dota_building"}) do
        for _, unit in ipairs(Entities:FindAllByClassname(classname) or {}) do
            if supported(unit) then M.apply(unit) end
        end
    end
    require("core/scheduler").every(.5, function()
        local dead = {}
        for state in pairs(active) do
            if not valid(state.owner) or (state.owner.IsAlive and not state.owner:IsAlive()) then
                table.insert(dead, state)
            end
        end
        for _, state in ipairs(dead) do cleanup_state(state) end
        return true
    end, TASK)
end
function M.shutdown()
    local states = {}
    for state in pairs(active) do table.insert(states, state) end
    for _, state in ipairs(states) do cleanup_state(state) end
    require("core/scheduler").cancel(TASK)
end
M._definitions = definitions
M._active = active
M._freeze = freeze
return M
