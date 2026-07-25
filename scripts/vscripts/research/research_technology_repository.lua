local config = require("config/research_technology_config")

local M = {}
M.__index = M

local function copy(source)
    local result = {}
    for key, value in pairs(source or {}) do result[key] = value end
    return result
end

function M.new(deps)
    return setmetatable({
        levels_by_team = {},
        resolve_team = assert(deps.resolve_team, "resolve_team is required"),
    }, M)
end

function M:Reset()
    self.levels_by_team = {}
end

function M:GetTeam(player_id)
    return self.resolve_team(player_id)
end

function M:GetLevel(player_id, tech_id)
    local team = self:GetTeam(player_id)
    if team == nil then return 0 end
    return tonumber((self.levels_by_team[team] or {})[tech_id]) or 0
end

function M:SetLevel(player_id, tech_id, level)
    local team = self:GetTeam(player_id)
    local definition = config.by_id[tech_id]
    level = tonumber(level)
    if team == nil or not definition or level == nil
        or level < 0 or level > definition.max_level then
        return false
    end
    self.levels_by_team[team] = self.levels_by_team[team] or {}
    self.levels_by_team[team][tech_id] = math.floor(level)
    return true
end

function M:GetAllLevels(player_id)
    local team = self:GetTeam(player_id)
    return copy(team ~= nil and self.levels_by_team[team] or {})
end

function M:GetLegacyLevels(player_id)
    local result = {}
    for tech_id, level in pairs(self:GetAllLevels(player_id)) do
        local definition = config.by_id[tech_id]
        if definition then result[definition.legacy_group] = level end
    end
    return result
end

function M:BuildClientSnapshot(player_id)
    local result = {}
    for _, definition in ipairs(config.technologies) do
        result[#result + 1] = {
            tech_id = definition.tech_id,
            current_level = self:GetLevel(player_id, definition.tech_id),
            max_level = definition.max_level,
        }
    end
    return result
end

return M