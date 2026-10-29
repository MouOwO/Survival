-- Project-authored equipment for the video's 20/15-floor reward cadence.
-- This pure reducer only sees verified, actually completed wave commands.
local items = require("config/generated/archive_challenge_gear_items")
local probabilities = require("config/generated/archive_challenge_gear_quality_rules")
local M = {}
local qualities = {"N", "R", "SR", "SSR", "UR"}
local appearance = {N="gray", R="green", SR="blue", SSR="purple", UR="gold"}
local function integer(value)
    return type(value) == "number" and value >= 0 and value < math.huge and value == math.floor(value)
end
local function rule_for(wave)
    for _, row in ipairs(probabilities.rows) do
        if row.enabled and wave >= row.min_wave and wave <= row.max_wave then return row end
    end
end
local function roll(save, wave, random_int)
    local rule = rule_for(wave)
    if not rule then return nil, "archive_gear_quality_rule_missing" end
    local groups, total = {}, 0
    for _, quality in ipairs(qualities) do
        local pool = {}
        for _, item in ipairs(items.rows) do
            if item.enabled and item.quality == quality
                and (save.challenge_gear_counts[item.item_id] or 0) < item.max_owned then
                pool[#pool + 1] = item
            end
        end
        local weight = tonumber(rule["weight_" .. quality:lower()]) or 0
        if #pool > 0 and weight > 0 then
            total = total + weight
            groups[#groups + 1] = {edge = total, pool = pool}
        end
    end
    if total == 0 then return nil, "collection_full" end
    local choose = random_int or RandomInt or math.random
    local ticket = choose(1, total)
    assert(integer(ticket) and ticket >= 1 and ticket <= total, "archive_gear_roll_invalid")
    for _, group in ipairs(groups) do
        if ticket <= group.edge then
            local index = choose(1, #group.pool)
            assert(integer(index) and index >= 1 and index <= #group.pool, "archive_gear_roll_invalid")
            return group.pool[index]
        end
    end
end
function M.grant_endless(command, save, stats, apply_effects, random_int)
    local variant = command.variant or "endless"
    if variant ~= "endless" and variant ~= "tower" then return false, "endless_variant_invalid" end
    if not integer(command.wave) or command.wave < 1 or type(command.id) ~= "string" or command.id == "" then
        return false, "endless_wave_invalid"
    end
    local interval = variant == "tower" and 15 or 20
    local bucket = math.floor(command.wave / interval)
    if bucket == 0 then return true, {awarded = 0} end
    -- Separate each durable match and variant. Keeping old cursors makes a late
    -- old-match retry safe even after a newer match has started saving rewards.
    local scope = command.id:match("^(.-):endless:%d+$") or command.id:match("^(.-):tower:%d+$")
        or command.id:match("^([^:]+)")
    save.challenge_gear_progress = save.challenge_gear_progress or {}
    local progress = save.challenge_gear_progress[scope] or {}
    local previous = tonumber(progress[variant]) or 0
    if bucket <= previous then return true, {awarded = 0, duplicate_milestone = true} end
    save.challenge_gear_counts = save.challenge_gear_counts or {}
    local item, reason = roll(save, command.wave, random_int)
    if not item and reason ~= "collection_full" then return false, reason end
    -- One real clear crossing one or many milestones awards at most one item.
    -- Increasing the skip interval cannot mint all the skipped floors' loot.
    progress[variant] = bucket
    save.challenge_gear_progress[scope] = progress
    if not item then return true, {awarded = 0, collection_full = true} end
    save.challenge_gear_counts[item.item_id] = (save.challenge_gear_counts[item.item_id] or 0) + 1
    apply_effects(stats, item)
    local result = {awarded = 1, item_id = item.item_id, name = item.display_name,
        quality = item.quality, variant = variant, wave = command.wave}
    save.last_challenge_gear = result
    return true, result
end
function M.rows(save)
    save = save or {}
    local result = {}
    for _, item in ipairs(items.rows) do
        if item.enabled then
            result[#result + 1] = {id = item.item_id, name = item.display_name, quality = appearance[item.quality],
                description = item.quality .. " · " .. item.description .. "\n无尽每20层／通天塔每15层掉落；层数越高，高品质概率越高。",
                count = (save.challenge_gear_counts or {})[item.item_id] or 0, target = item.max_owned,
                icon_style = "seal", rune = "装"}
        end
    end
    return result
end
return M
