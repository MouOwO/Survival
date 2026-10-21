-- Shared deterministic settlement: local game and authenticated HTTP backend use identical rules.
local stats_config = require("config/generated/player_gameplay_stats")
local achievements = require("config/generated/archive_achievements")
local challenge_rewards = require("systems/archive_challenge_rewards")
local daily_limits = require("systems/archive_daily_limits")
local clear_progress = require("systems/archive_clear_progress")
local M = {}
local clear_fields = { clear = "clear_counts", standard_clear = "clear_counts",
    rich_clear = "rich_clear_counts", cold_clear = "cold_clear_counts", scourge_clear = "scourge_clear_counts" }
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
        if field == "starjoy_points" then
            require("systems/archive_starjoy_rewards").change(stats, tonumber(stats[field]) or 0, value)
        else stats[field] = value end
    end
end

function M.settle(profile, command, pass, context)
    local archive, stats = copy(profile.save.archive or {}), copy(profile.save.gameplay_stats or {})
    local inventory, response
    archive.version = 1
    for _,key in ipairs({"clear_counts","completed","shadow_counts","processed"}) do archive[key]=archive[key] or {} end
    if archive.processed[command.id] then return {ok=true,duplicate=true,archive=archive,gameplay_stats=stats} end
    if (clear_fields[command.kind] or command.kind == "mode_clear")
        and archive.standard_clear_counts == nil then
        -- Preserve pre-mode historical clears once. Later pure/rich wins cannot
        -- keep extending this compatibility baseline.
        archive.standard_clear_counts = copy(archive.clear_counts)
    end
    -- Equipping cosmetics must not reconcile or award unrelated gameplay bonuses.
    if command.kind == "title_equip" then
        local ok, reason = require("systems/archive_titles").apply(command, archive)
        if not ok then return {ok=false,terminal=true,error=reason} end
        archive.processed[command.id] = true
        return {ok=true,archive=archive,gameplay_stats=stats}
    end
    require("systems/archive_starjoy_rewards").reconcile(stats)
    if command.kind == "online_checkpoint" or command.kind == "work_upgrade" then
        local ok, reason = require("systems/archive_online_rewards").apply(command, archive, stats, apply_effects, profile.save)
        if not ok then return { ok = false, terminal = true, error = reason } end
    elseif command.kind == "vip_claim" or command.kind == "vip_purchase" then
        local ok, reason = require("systems/archive_vip_rewards").apply(command, profile, archive, stats, apply_effects)
        if not ok then return {ok=false,terminal=true,error=reason} end
    elseif command.kind == "welfare_reconcile" then
        -- Reconcile trusted saved wins below; callers cannot supply progress or effects.
    elseif command.kind == "starjoy_reconcile" then
        -- Reconcile above uses saved account points only; no client amount.
    elseif command.kind == "boss_kill" then
        archive.boss_kills=(tonumber(archive.boss_kills) or 0)
            + daily_limits.grant(archive, "boss", 1, command.day_key, pass)
    elseif command.kind == "daily_init" or command.kind == "daily_claim" then
        local ok,reason=require("systems/archive_daily_rewards").apply(command,archive,stats,pass,apply_effects)
        if not ok then return {ok=false,terminal=true,error=reason} end
    elseif command.kind == "benefit_claim" then
        inventory=copy(profile.save.content_inventory or {})
        local ok, result=require("systems/archive_benefit_rewards").apply(command,archive,stats,inventory,pass,profile.save)
        if not ok then return {ok=false,terminal=true,error=result} end
        response=result
    elseif command.kind == "building_upgrade" or command.kind == "faith_cheat" then
        local ok, reason = require("systems/archive_building_rewards").apply(command, archive, stats, apply_effects)
        if not ok then return {ok=false,terminal=true,error=reason} end
    elseif clear_fields[command.kind] or command.kind == "mode_clear" then
        command=copy(command)
        local mode = command.mode_id or ({standard_clear="standard",rich_clear="rich",
            cold_clear="cold",scourge_clear="scourge"})[command.kind]
        if command.kind == "mode_clear" and not clear_progress.is_mode(mode) then
            return {ok=false,terminal=true,error="archive_mode_clear_invalid"}
        end
        if mode and clear_progress.max_available(mode) < (tonumber(command.difficulty_id:sub(2)) or math.huge) then
            return {ok=false,terminal=true,error="archive_mode_difficulty_unavailable"}
        end
        require("systems/archive_benefit_rewards").record_win(archive,command)
        if require('systems/commerce_effects').has(profile.save,'double_clear') then
            command.count=command.count*2
        end
        local accepted = math.min(command.count, daily_limits.remaining(archive,"clear",command.day_key,pass))
        local mode_key = mode and "mode_" .. mode
        if mode_key and (mode == "rich" or mode == "cold" or mode == "scourge") then
            accepted = math.min(accepted, daily_limits.remaining(archive,mode_key,command.day_key,pass))
        end
        command.count = daily_limits.grant(archive,"clear",accepted,command.day_key,pass)
        if mode_key and (mode == "rich" or mode == "cold" or mode == "scourge") then
            daily_limits.grant(archive,mode_key,accepted,command.day_key,pass)
        end
        if accepted > 0 then
            require("systems/archive_building_rewards").clear(archive, command, pass)
            if command.cooperative_win == 1 then
                -- One per successful match, regardless of teammate count; shares clear dedup.
                archive.cooperative_clear_count = require("systems/archive_welfare_rewards").cooperative_wins(archive) + 1
            end
            local difficulty = command.difficulty_id
            local key = mode and mode ~= "pure" and mode ~= "standard" and (mode .. "_clear_counts")
                or clear_fields[command.kind] or "clear_counts"
            -- Seed only proven compatibility maps. Pure wins never inherit old
            -- mixed history, and no history is copied to a different mode.
            if mode then
                archive.mode_clear_counts = archive.mode_clear_counts or {}
                if archive.mode_clear_counts[mode] == nil and mode ~= "pure" then
                    archive.mode_clear_counts[mode] = copy(archive[mode .. "_clear_counts"] or {})
                end
            end
            archive[key] = archive[key] or {}
            archive[key][difficulty] = (archive[key][difficulty] or 0) + command.count
            if mode == "standard" or command.kind == "standard_clear" then
                archive.standard_clear_counts = archive.standard_clear_counts or {}
                archive.standard_clear_counts[difficulty] = (archive.standard_clear_counts[difficulty] or 0) + command.count
            end
            if mode then
                command.mode_id = mode
                local ok,reason = clear_progress.record(archive,command,stats,apply_effects)
                if not ok then return {ok=false,terminal=true,error=reason} end
            else
                for _, item in ipairs(achievements.rows) do
                    if item.enabled and (not item.mode_id or item.mode_id == "standard") and item.difficulty_id == difficulty
                        and archive[key][difficulty] >= item.required_count
                        and not archive.completed[item.achievement_id] then
                        apply_effects(stats, item)
                        archive.completed[item.achievement_id] = true
                    end
                end
            end
        end
    elseif command.kind == "endless" then
        local config = require("systems/archive_endless_config")
        if not config.wave(command.difficulty, command.wave) then return { ok = false, terminal = true, error = "endless_wave_invalid" } end
        archive.endless_score = (tonumber(archive.endless_score) or 0)
            + daily_limits.grant(archive,"endless",config.score(command.wave),command.day_key,pass)
        archive.endless_best_wave = math.max(tonumber(archive.endless_best_wave) or 0, command.wave)
        require("systems/archive_endless_rewards").reconcile(archive, stats, apply_effects)
    elseif command.kind == "endless_reconcile" then
        -- Only persisted server progress is considered; this command has no progress input.
        require("systems/archive_endless_rewards").reconcile(archive, stats, apply_effects)
    elseif command.kind == "challenge" then
        local random_int
        if context and context.challenge_random_seed then
            random_int = require("systems/archive_cooperative_reward_policy").random_int(context.challenge_random_seed)
        end
        local ok, reason = challenge_rewards.apply(command, archive, stats, pass, apply_effects, random_int)
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
    require("systems/archive_titles").sync(archive)
    require("systems/archive_welfare_rewards").reconcile(archive, stats, apply_effects)
    -- Online checkpoints are deduplicated by their cumulative session cursor, without one saved ID per minute.
    if command.kind ~= "online_checkpoint" then archive.processed[command.id] = true end
    return {ok=true,archive=archive,gameplay_stats=stats,content_inventory=inventory,response=response}
end
M.apply_effects=apply_effects
return M
