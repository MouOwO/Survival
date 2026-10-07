-- Worker presentation only: gameplay stats and abilities remain owned by worker_system.
local M = {}
local function valid(unit)
    return unit and (not unit.IsNull or not unit:IsNull())
end
function M.cleanup(unit)
    if not unit then return end
    for _, part in ipairs(unit.survival_worker_model_parts or {}) do
        if valid(part) then
            if UTIL_Remove then UTIL_Remove(part) elseif part.RemoveSelf then part:RemoveSelf() end
        end
    end
    unit.survival_worker_model_parts = nil
end
function M.apply(unit, training, fused)
    if not valid(unit) or not training then return end
    M.cleanup(unit)
    if training.model_name and training.model_name ~= "" then
        unit:SetModel(training.model_name)
        unit:SetOriginalModel(training.model_name)
    end
    local scale = (tonumber(training.model_scale) or 1) * (fused and 1.5 or 1)
    if unit.SetModelScale then unit:SetModelScale(scale) end
    unit.survival_worker_model_parts = {}
    if not SpawnEntityFromTableSynchronous then return end
    for _, model in ipairs(training.model_components or {}) do
        local part = SpawnEntityFromTableSynchronous("prop_dynamic", {
            model = model, DefaultAnim = "idle", solid = "0", spawnflags = "256",
        })
        if valid(part) then
            part:SetOwner(unit)
            part:SetParent(unit, "")
            part:FollowEntity(unit, true)
            if part.AddEffects and EF_BONEMERGE then part:AddEffects(EF_BONEMERGE) end
            table.insert(unit.survival_worker_model_parts, part)
        end
    end
end
return M
