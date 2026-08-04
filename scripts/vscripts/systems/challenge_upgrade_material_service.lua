local event_bus = require("core/event_bus")
local events = require("core/events")
local materials = require("config/challenge_upgrade_materials")
local weapons = require("config/generated/weapon_definitions")

local M = {}
local drops = {}
local next_drop_id = 0

local function valid(entity)
    return entity and not entity:IsNull()
end

local function notify(player_id, message, level)
    event_bus.emit(events.UI_NOTIFICATION, {
        player_id = player_id,
        message = message,
        level = level or "info",
    })
end

local function weapon_for(series_id, stage)
    for _, definition in ipairs(weapons.rows or {}) do
        if definition.enabled ~= false
            and definition.series_id == series_id
            and tonumber(definition.stage) == tonumber(stage) then
            return definition
        end
    end
    return nil
end

local function remove_drop(drop)
    if not drop then return end
    if valid(drop.unit) then
        drops[drop.unit:entindex()] = nil
        UTIL_Remove(drop.unit)
    end
end

local function synthesize(drop, player_id)
    if not drop or drop.consumed then
        return { ok = false, error = "upgrade_material_unavailable" }
    end
    if tonumber(player_id) ~= drop.player_id then
        return { ok = false, error = "upgrade_material_not_owned" }
    end

    local definition = drop.definition
    local current = weapon_for(definition.series_id, definition.required_stage)
    local next_id = current and tostring(current.next_content_id or "") or ""
    if not current or next_id == "" or not weapons.by_id[next_id] then
        return { ok = false, error = "upgrade_material_configuration_invalid" }
    end

    -- Do not invoke the idempotent transaction handler until the matching
    -- weapon exists. A stage mismatch is recoverable and must not permanently
    -- cache a failed transaction for this ground material.
    local inventory = event_bus.request(
        events.CONTENT_INVENTORY_GET_REQUEST,
        { player_id = player_id }
    )
    local counts = inventory and inventory.snapshot and inventory.snapshot.counts
    if not counts then
        return { ok = false, error = "challenge_inventory_unavailable" }
    end
    if (tonumber(counts[current.content_id]) or 0) < 1 then
        return {
            ok = false,
            error = "upgrade_material_stage_mismatch:" .. current.content_id,
        }
    end

    local result = event_bus.request(
        events.INVENTORY_TRANSACTION_EXECUTE_REQUEST,
        {
            player_id = player_id,
            request_id = "challenge_material:" .. drop.drop_id,
            consume = { [current.content_id] = 1 },
            grant = { [next_id] = 1 },
            reason = "challenge_material_synthesis:" .. definition.material_id,
        }
    ) or { ok = false, error = "inventory_transaction_unavailable" }

    if result.ok then
        drop.consumed = true
        remove_drop(drop)
        notify(
            player_id,
            definition.display_name .. "合成成功："
                .. tostring(weapons.by_id[next_id].display_name or next_id)
        )
        print(string.format(
            "[CHALLENGE_MATERIAL_SYNTHESIZED] player=%s material=%s from=%s to=%s",
            tostring(player_id), definition.material_id,
            current.content_id, next_id
        ))
    end
    return result
end

local function spawn_drop(payload)
    if payload.authoritative ~= true then
        return { ok = false, error = "upgrade_material_authority_required" }
    end
    local definition = materials.find(payload.challenge_id, payload.required_stage)
    local player_id = tonumber(payload.player_id)
    local position = payload.position
    if not definition or definition.enabled == false
        or player_id == nil or not position then
        return { ok = false, error = "upgrade_material_drop_invalid" }
    end

    local unit = CreateUnitByName(
        "npc_survival_upgrade_material",
        position,
        false,
        nil,
        nil,
        tonumber(payload.team) or DOTA_TEAM_GOODGUYS
    )
    if not valid(unit) then
        return { ok = false, error = "upgrade_material_entity_create_failed" }
    end
    unit:AddNewModifier(unit, nil, "modifier_invulnerable", {})
    unit:AddNewModifier(unit, nil, "modifier_phased", {})
    unit.survival_display_name = definition.display_name
    unit.survival_upgrade_material = true

    next_drop_id = next_drop_id + 1
    local drop = {
        drop_id = tostring(payload.completion_id or "drop")
            .. ":" .. tostring(next_drop_id),
        player_id = player_id,
        definition = definition,
        unit = unit,
        consumed = false,
    }
    drops[unit:entindex()] = drop

    if definition.auto_pickup then
        local result = synthesize(drop, player_id)
        if not result.ok then
            result.material_retained = true
            result.material_id = definition.material_id
            result.entindex = valid(unit) and unit:entindex() or -1
            notify(
                player_id,
                "自动合成失败，材料已保留在地面："
                    .. tostring(result.error or "unknown"),
                "error"
            )
        end
        return result
    end

    notify(player_id, "掉落：" .. definition.display_name .. "（按F拾取）")
    return {
        ok = true,
        material_id = definition.material_id,
        entindex = unit:entindex(),
        auto_pickup = false,
    }
end

local function pickup_nearby(payload)
    local caster = payload.caster
    local player_id = tonumber(payload.player_id)
    if not valid(caster) or player_id == nil or player_id < 0 then
        return { ok = false, error = "upgrade_material_picker_invalid" }
    end
    if not caster.GetPlayerOwnerID
        or caster:GetPlayerOwnerID() ~= player_id then
        return { ok = false, error = "upgrade_material_picker_not_owned" }
    end

    local nearby = {}
    local origin = caster:GetAbsOrigin()
    for _, drop in pairs(drops) do
        if not drop.consumed and drop.player_id == player_id and valid(drop.unit)
            and (drop.unit:GetAbsOrigin() - origin):Length2D()
                <= materials.pickup_radius then
            nearby[#nearby + 1] = drop
        end
    end
    table.sort(nearby, function(a, b)
        local a_distance = (a.unit:GetAbsOrigin() - origin):Length2D()
        local b_distance = (b.unit:GetAbsOrigin() - origin):Length2D()
        if a_distance == b_distance then return a.drop_id < b.drop_id end
        return a_distance < b_distance
    end)

    local synthesized = 0
    local last_error = nil
    for _, drop in ipairs(nearby) do
        local result = synthesize(drop, player_id)
        if result.ok then
            synthesized = synthesized + 1
        else
            last_error = result.error
        end
    end

    if #nearby == 0 then
        notify(player_id, "300范围内没有可拾取的升阶材料")
    elseif synthesized == 0 then
        notify(
            player_id,
            "没有符合当前武器阶段的材料，材料已保留在地面",
            "error"
        )
    end
    return {
        ok = true,
        found = #nearby,
        synthesized = synthesized,
        error = last_error,
    }
end

function M.nearby(caster, player_id)
    player_id = tonumber(player_id)
    if not valid(caster) or player_id == nil or player_id < 0 then return {} end
    local origin = caster:GetAbsOrigin()
    local result = {}
    for _, drop in pairs(drops) do
        if not drop.consumed and drop.player_id == player_id and valid(drop.unit) then
            local distance = (drop.unit:GetAbsOrigin() - origin):Length2D()
            if distance <= materials.pickup_radius then
                result[#result + 1] = {
                    drop = drop,
                    distance = distance,
                    entindex = drop.unit:entindex(),
                }
            end
        end
    end
    return result
end

function M.pickup_candidate(candidate, player_id)
    if not candidate or not candidate.drop then
        return { ok = false, error = "upgrade_material_unavailable" }
    end
    return synthesize(candidate.drop, tonumber(player_id))
end

function M.pickup(caster, player_id)
    return pickup_nearby({ caster = caster, player_id = player_id })
end

function M.init()
    drops = {}
    next_drop_id = 0
    event_bus.handle_request(events.CHALLENGE_MATERIAL_DROP_REQUEST, spawn_drop)
    event_bus.handle_request(events.CHALLENGE_MATERIAL_PICKUP_REQUEST, pickup_nearby)
    print("[CHALLENGE_MATERIAL_INIT] pickup_radius=300 virtual_ground_materials=true")
end

return M