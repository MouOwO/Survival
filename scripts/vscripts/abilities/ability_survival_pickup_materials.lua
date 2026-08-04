local event_bus = require("core/event_bus")
local events = require("core/events")
local ground_item_pickup = require("systems/ground_item_pickup_service")
local upgrade_materials = require("systems/challenge_upgrade_material_service")

ability_survival_pickup_materials = class({})

function ability_survival_pickup_materials:OnSpellStart()
    if not IsServer() then return end
    local caster = self:GetCaster()
    if not caster or caster:IsNull() then return end
    local player_id = caster:GetPlayerOwnerID()
    local candidates = {}
    for _, candidate in ipairs(upgrade_materials.nearby(caster, player_id)) do
        candidate.kind = "upgrade_material"
        candidates[#candidates + 1] = candidate
    end
    for _, candidate in ipairs(ground_item_pickup.nearby(caster, player_id)) do
        candidate.kind = "ground_item"
        candidates[#candidates + 1] = candidate
    end
    table.sort(candidates, function(a, b)
        if a.distance == b.distance then return a.entindex < b.entindex end
        return a.distance < b.distance
    end)

    if #candidates == 0 then
        event_bus.emit(events.UI_NOTIFICATION, {
            player_id = player_id,
            message = "300范围内没有可拾取的物品",
        })
        return
    end

    for _, candidate in ipairs(candidates) do
        local result
        if candidate.kind == "upgrade_material" then
            result = upgrade_materials.pickup_candidate(candidate, player_id)
        else
            result = ground_item_pickup.pickup_candidate(caster, candidate)
        end
        if result and result.full then
            event_bus.emit(events.UI_NOTIFICATION, {
                player_id = player_id,
                message = "装备栏已满，已停止拾取剩余物品",
                level = "error",
            })
            break
        end
    end
end