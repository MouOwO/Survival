local scale = require("visual/model_scale")
local M = {}
local initialized = false
local excluded = {
    npc_survival_grid_preview_proxy = true,
    npc_survival_upgrade_material = true,
}

function M.apply(unit)
    if not unit or unit.IsNull and unit:IsNull()
        or type(unit.IsBaseNPC) ~= "function" or not unit:IsBaseNPC()
        or unit.survival_is_grid_preview
        or unit.survival_wall_collision_barrier
        or unit.survival_is_native_wearable_visual then return false end
    if unit.GetClassname and unit:GetClassname() == "npc_dota_thinker" then return false end
    if unit.GetUnitName and excluded[unit:GetUnitName()] then return false end
    -- Native illusions may already inherit their source's reduced model size.
    if unit.IsIllusion and unit:IsIllusion() then
        for _, method in ipairs({"GetReplicatingOtherHero", "GetOwnerEntity"}) do
            if type(unit[method]) == "function" then
                local ok, source = pcall(unit[method], unit)
                if ok and source and source ~= unit
                    and (not source.IsNull or not source:IsNull())
                    and source.survival_visual_final_scale
                    and type(source.GetModelScale) == "function" then
                    return scale.copy_final(unit, source:GetModelScale())
                end
            end
        end
    end
    return scale.ensure(unit)
end

function M.init()
    if initialized then return end
    initialized = true
    ListenToGameEvent("npc_spawned", function(keys)
        local id = tonumber(keys and keys.entindex)
        local unit = id and EntIndexToHScript and EntIndexToHScript(id)
        M.apply(unit)
    end, nil)
    if not Entities or not Entities.FindAllByClassname then return end
    for _, classname in ipairs({"npc_dota_hero", "npc_dota_creature", "npc_dota_building"}) do
        for _, unit in ipairs(Entities:FindAllByClassname(classname) or {}) do M.apply(unit) end
    end
end

return M
