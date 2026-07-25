local config = require("config/research_technology_config")
local event_names = require("research/research_event_names")

local M = {}
M.__index = M

local function build_result(success, tech_id, old_level, new_level, cost,
        error_code)
    return {
        success = success,
        tech_id = tech_id,
        old_level = old_level or 0,
        new_level = new_level or old_level or 0,
        gold_cost = cost and cost.gold or 0,
        wood_cost = cost and cost.wood or 0,
        error_code = error_code,
    }
end

function M.new(deps)
    return setmetatable({
        repository = assert(deps.repository, "repository is required"),
        effects = assert(deps.effects, "effects is required"),
        event_bus = assert(deps.event_bus, "event_bus is required"),
        valid_player = assert(deps.valid_player, "valid_player is required"),
        get_resources = assert(deps.get_resources, "get_resources is required"),
        spend_resources = assert(
            deps.spend_resources,
            "spend_resources is required"
        ),
        refund_resources = assert(
            deps.refund_resources,
            "refund_resources is required"
        ),
        get_reincarnation_level = deps.get_reincarnation_level
            or function() return 0 end,
        get_access_state = deps.get_access_state or function()
            return { research_lab = true, advanced_research_lab = true }
        end,
        sync_client = deps.sync_client or function() end,
    }, M)
end

function M:_has_access(definition, access_state)
    return access_state and access_state[definition.building_id] == true
end

function M:_finish(response)
    local event_name = response.success and event_names.UPGRADE_SUCCEEDED
        or event_names.UPGRADE_FAILED
    self.event_bus.emit(event_name, response)
    return response
end

function M:RequestUpgrade(payload)
    payload = payload or {}
    local player_id = tonumber(payload.player_id)
    local tech_id = tostring(payload.tech_id or "")
    self.event_bus.emit(event_names.UPGRADE_REQUESTED, {
        player_id = player_id,
        tech_id = tech_id,
    })
    if not self.valid_player(player_id) then
        return self:_finish(build_result(
            false, tech_id, 0, 0, nil, "invalid_player"
        ))
    end

    local definition = config.by_id[tech_id]
    if not definition then
        return self:_finish(build_result(
            false, tech_id, 0, 0, nil, "unknown_technology"
        ))
    end

    local old_level = self.repository:GetLevel(player_id, tech_id)
    if not self:_has_access(definition, self.get_access_state(player_id)) then
        return self:_finish(build_result(
            false, tech_id, old_level, old_level, nil,
            "research_access_not_met"
        ))
    end

    local target_level = old_level + 1
    if target_level > definition.max_level then
        return self:_finish(build_result(
            false, tech_id, old_level, old_level, nil, "max_level_reached"
        ))
    end

    local cost = config.cost_for_level(definition, target_level)
    local required = definition.prerequisite or {}
    if required.tech_id and self.repository:GetLevel(
        player_id,
        required.tech_id
    ) < (required.required_level or 0) then
        return self:_finish(build_result(
            false, tech_id, old_level, old_level, cost,
            "prerequisite_not_met"
        ))
    end
    if self.get_reincarnation_level(player_id)
        < (required.reincarnation_level or 0) then
        return self:_finish(build_result(
            false, tech_id, old_level, old_level, cost,
            "reincarnation_not_met"
        ))
    end

    local resources = self.get_resources(player_id) or {}
    if (tonumber(resources.gold) or 0) < cost.gold then
        return self:_finish(build_result(
            false, tech_id, old_level, old_level, cost,
            "insufficient_gold"
        ))
    end
    if (tonumber(resources.wood) or 0) < cost.wood then
        return self:_finish(build_result(
            false, tech_id, old_level, old_level, cost,
            "insufficient_wood"
        ))
    end

    local spent = self.spend_resources(player_id, cost, tech_id)
    if not spent or spent.ok ~= true then
        local spend_error = spent and spent.error or ""
        local error_code = "resource_commit_failed"
        if spend_error == "gold_not_enough" then
            error_code = "insufficient_gold"
        elseif spend_error == "wood_not_enough" then
            error_code = "insufficient_wood"
        end
        return self:_finish(build_result(
            false, tech_id, old_level, old_level, cost, error_code
        ))
    end

    if not self.repository:SetLevel(player_id, tech_id, target_level) then
        self.refund_resources(player_id, cost, tech_id)
        return self:_finish(build_result(
            false, tech_id, old_level, old_level, cost,
            "resource_commit_failed"
        ))
    end

    local effect_snapshot = self.effects:Recalculate(player_id)
    local response = build_result(
        true, tech_id, old_level, target_level, cost, nil
    )
    response.player_id = player_id
    response.legacy_group = definition.legacy_group
    response.levels = self.repository:GetAllLevels(player_id)
    response.legacy_levels = self.repository:GetLegacyLevels(player_id)
    response.effects = effect_snapshot
    self.event_bus.emit(event_names.LEVEL_CHANGED, response)
    self.event_bus.emit(event_names.EFFECTS_CHANGED, {
        player_id = player_id,
        tech_id = tech_id,
        snapshot = effect_snapshot,
    })
    self.sync_client(player_id, self:BuildClientSnapshot(player_id))
    return self:_finish(response)
end

function M:BuildClientSnapshot(player_id)
    local resources = self.get_resources(player_id) or {}
    local reincarnation = self.get_reincarnation_level(player_id)
    local access_state = self.get_access_state(player_id)
    local entries = {}
    for _, definition in ipairs(config.technologies) do
        local level = self.repository:GetLevel(player_id, definition.tech_id)
        local target_level = level + 1
        local cost = config.cost_for_level(definition, target_level)
        local required = definition.prerequisite or {}
        local prerequisite_met = not required.tech_id
            or self.repository:GetLevel(player_id, required.tech_id)
                >= (required.required_level or 0)
        local reincarnation_met = reincarnation
            >= (required.reincarnation_level or 0)
        local locked_reason = nil
        if not self:_has_access(definition, access_state) then
            locked_reason = "research_access_not_met"
        elseif level >= definition.max_level then
            locked_reason = "max_level_reached"
        elseif not prerequisite_met then
            locked_reason = "prerequisite_not_met"
        elseif not reincarnation_met then
            locked_reason = "reincarnation_not_met"
        elseif (tonumber(resources.gold) or 0) < (cost and cost.gold or 0) then
            locked_reason = "insufficient_gold"
        elseif (tonumber(resources.wood) or 0) < (cost and cost.wood or 0) then
            locked_reason = "insufficient_wood"
        end
        entries[#entries + 1] = {
            tech_id = definition.tech_id,
            display_name = definition.display_name,
            current_level = level,
            max_level = definition.max_level,
            next_gold_cost = cost and cost.gold or 0,
            next_wood_cost = cost and cost.wood or 0,
            prerequisite_met = prerequisite_met and 1 or 0,
            can_upgrade = locked_reason == nil and 1 or 0,
            locked_reason = locked_reason or "",
            cumulative_effect_text = self:_effect_text(definition, level),
        }
    end
    return { player_id = player_id, technologies = entries }
end

function M:_effect_text(definition, level)
    local parts = {}
    for _, effect in ipairs(definition.effects) do
        local value = effect.mode == "constant"
            and (level > 0 and effect.value_per_level or 0)
            or effect.value_per_level * level
        parts[#parts + 1] = effect.key .. "=" .. tostring(value)
    end
    return table.concat(parts, "; ")
end

return M