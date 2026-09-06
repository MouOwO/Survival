-- Shared deterministic settlement: local game and authenticated HTTP backend use identical rules.
local stats_config = require("config/generated/player_gameplay_stats")
local achievements = require("config/generated/archive_achievements")
local challenge_rewards = require("systems/archive_challenge_rewards")
local M = {}
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}; for k,v in pairs(value) do result[k]=copy(v) end; return result
end
local function apply_effects(stats, item)
    assert(#item.effect_ids == #item.effect_values, "archive_effect_array_mismatch")
    for i, field in ipairs(item.effect_ids) do
        local definition = assert(stats_config.by_id[field], "archive_unknown_stat:" .. field)
        local delta = assert(tonumber(item.effect_values[i]), "archive_invalid_effect")
        local value = (tonumber(stats[field]) or tonumber(definition.default_value) or 0) + delta
        -- Gameplay schema limits (e.g. 100% damage reduction) are hard caps.
        if definition.max_value then value = math.min(value, definition.max_value) end
        if definition.min_value then value = math.max(value, definition.min_value) end
        assert(value == value and value < math.huge, "archive_nonfinite_stat")
        stats[field] = value
    end
end

function M.settle(profile, command, pass)
    local archive, stats = copy(profile.save.archive or {}), copy(profile.save.gameplay_stats or {})
    archive.version = 1
    for _,key in ipairs({"clear_counts","completed","shadow_counts","processed"}) do archive[key]=archive[key] or {} end
    if archive.processed[command.id] then return {ok=true,duplicate=true,archive=archive,gameplay_stats=stats} end
    if command.kind == "online_checkpoint" or command.kind == "work_upgrade" then
        local ok, reason = require("systems/archive_online_rewards").apply(command, archive, stats, apply_effects)
        if not ok then return { ok = false, terminal = true, error = reason } end
    elseif command.kind == "boss_kill" then
        archive.boss_kills=(tonumber(archive.boss_kills) or 0)+1
    elseif command.kind == "daily_init" or command.kind == "daily_claim" then
        local ok,reason=require("systems/archive_daily_rewards").apply(command,archive,stats,pass,apply_effects)
        if not ok then return {ok=false,terminal=true,error=reason} end
    elseif command.kind == "building_upgrade" or command.kind == "faith_cheat" then
        local ok, reason = require("systems/archive_building_rewards").apply(command, archive, stats, apply_effects)
        if not ok then return {ok=false,terminal=true,error=reason} end
    elseif command.kind == "clear" then
        require("systems/archive_building_rewards").clear(archive, command)
        local difficulty = command.difficulty_id
        archive.clear_counts[difficulty] = (archive.clear_counts[difficulty] or 0) + command.count
        for _, item in ipairs(achievements.rows) do
            if item.enabled and item.difficulty_id == difficulty
                and archive.clear_counts[difficulty] >= item.required_count
                and not archive.completed[item.achievement_id] then
                apply_effects(stats, item)
                archive.completed[item.achievement_id] = true
            end
        end
    elseif command.kind == "endless" then
        local config = require("systems/archive_endless_config")
        if not config.wave(command.difficulty, command.wave) then return { ok = false, terminal = true, error = "endless_wave_invalid" } end
        archive.endless_score = (tonumber(archive.endless_score) or 0) + config.score(command.wave)
        archive.endless_best_wave = math.max(tonumber(archive.endless_best_wave) or 0, command.wave)
        for _, item in ipairs(require("config/generated/archive_endless_achievements").rows) do
            if item.enabled and archive.endless_score >= item.required_score and not archive.completed[item.achievement_id] then
                apply_effects(stats, item)
                archive.completed[item.achievement_id] = true
            end
        end
    elseif command.kind == "challenge" then
        local ok, reason = challenge_rewards.apply(command, archive, stats, pass, apply_effects)
        if not ok then return { ok = false, error = reason } end
    elseif command.kind == "social_draw" or command.kind == "social_ticket_cheat" then
        local ok, reason = require("systems/archive_social_rewards").apply(command, archive, stats, apply_effects)
        if not ok then return { ok=false, error=reason, terminal=true } end
    elseif command.kind == "promotion" then
        local ok, reason = challenge_rewards.promote(command, archive, stats, apply_effects)
        if not ok then return { ok = false, error = reason, terminal = true } end
    else
        return { ok = false, error = "archive_command_invalid" }
    end
    -- Online checkpoints are deduplicated by their cumulative session cursor, without one saved ID per minute.
    if command.kind ~= "online_checkpoint" then archive.processed[command.id] = true end
    return {ok=true,archive=archive,gameplay_stats=stats}
end
M.apply_effects=apply_effects
return M
