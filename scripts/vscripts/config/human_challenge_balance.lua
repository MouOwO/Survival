-- Numeric authority from the complementary human-readable workbook and JSON.
-- This layer changes combat values only; existing encounter art and rewards stay
-- with their original definitions. Authored archive values are already final.
local rules = require("config/human_monster_rules")
local M = {}
function M.supports_mode(mode_id) return rules.data.modes[mode_id or "standard"] ~= nil end

local room_members = {
    practice_wood = 1, practice_gold = 2,
    practice_attribute = 3, practice_greater_attribute = 4,
}
local special_members = {
    challenge_08_boss = "火焰巨魔", challenge_09_boss = "冰烬挽歌",
    challenge_05_boss = "合成宝石", challenge_06_ice_wraith = "冰之幽魂",
    challenge_07_molten_minion = "概率掉落熔火核心",
    seven_sins_minion = "概率掉落精华",
    boss_ten_sin_01 = "真实", boss_ten_sin_02 = "信仰",
    boss_ten_sin_03 = "安息", boss_ten_sin_04 = "忍耐",
    boss_ten_sin_05 = "无欲", boss_ten_sin_06 = "戒杀",
    boss_ten_sin_07 = "沉默", boss_ten_sin_08 = "纯洁",
    boss_ten_sin_09 = "敬神", boss_ten_sin_10 = "慈爱",
}

local function named(rows, name)
    for _, row in ipairs(rows or {}) do if row.name == name then return row end end
end

local function source_for(member_id)
    local room_index = room_members[member_id]
    if room_index then return rules.data.rooms[room_index], "room" end
    local rebirth_index = tonumber(tostring(member_id):match("^encounter_rebirth_(%d+)$"))
    if rebirth_index then return rules.data.rebirth_bosses[rebirth_index], "rebirth", rebirth_index end
    local special_name = special_members[member_id]
    if special_name then return named(rules.data.special_bosses, special_name), "special" end
end

function M.resolve_member(member_id, difficulty_id, mode_id)
    if not M.supports_mode(mode_id) then return nil, nil end
    local source, category, index = source_for(member_id)
    if not source then return nil, nil end
    local mode, mode_error = rules.mode(mode_id or "standard", difficulty_id)
    if not mode then return nil, mode_error or "human_challenge_mode_missing" end
    local difficulty = rules.number(difficulty_id)
    if not difficulty then return nil, "human_challenge_difficulty_invalid" end
    local attack_multiplier = rules.challenge_attack_multiplier(mode_id or "standard", difficulty_id, category == "room")
    local first_rebirth_adjustment = category == "rebirth" and index == 1
        and (mode_id == "cold" or mode_id == "scourge") and 0.5 or 1
    local row = {
        profile_id = "human_" .. tostring(mode_id or "standard") .. "_" .. difficulty_id .. "_" .. member_id,
        member_id = member_id, difficulty_id = difficulty_id, mode_id = mode_id or "standard",
        health = source.health * mode.challenge_hp_multiplier * first_rebirth_adjustment,
        attack = source.attack * attack_multiplier,
        war3_armor = source.war3_armor * mode.challenge_armor_multiplier * first_rebirth_adjustment,
        count = source.count, enabled = true, human_spec = true,
    }
    if source.attack_interval then row.attack_speed = 1 / source.attack_interval end
    return row, nil
end

function M.member_count(member_id)
    local source = source_for(member_id)
    return source and tonumber(source.count) or nil
end

function M.has_member(member_id) return source_for(member_id) ~= nil end

function M.archive(challenge_id, difficulty_id)
    local name
    local shadow = tonumber(tostring(challenge_id):match("^shadow_(%d+)$"))
    if shadow then name = "虚空之影" .. shadow end
    local category, ordinal = tostring(challenge_id):match("^(hunt)_(%d+)$")
    if not category then category, ordinal = tostring(challenge_id):match("^(cage)_(%d+)$") end
    local source
    if name then source = named(rules.data.save_challenges, name)
    elseif category then
        local prefix = category == "hunt" and "神兽狩猎" or "秘法牢笼"
        local counter = 0
        for _, row in ipairs(rules.data.save_challenges or {}) do
            if row.name:sub(1, #prefix) == prefix then
                counter = counter + 1
                if counter == tonumber(ordinal) then source = row; break end
            end
        end
    end
    if not source then return nil end
    return {
        stats_id = challenge_id .. "_" .. tostring(difficulty_id),
        challenge_id = challenge_id, difficulty_id = difficulty_id,
        health = source.health, attack = source.attack, war3_armor = source.war3_armor,
        -- The workbook's 250 is the Warcraft attack-speed percentage. Runtime
        -- rows use attacks/second against the one-second archive base interval.
        attack_speed = source.attack_speed / 100, authored_attack_speed = source.attack_speed,
        count = source.count, enabled = true, human_spec = true,
        source_name = source.name, evidence = source.evidence,
    }
end

function M.building(challenge_id, current_wave, difficulty_id, mode_id)
    local index = tonumber(tostring(challenge_id):match("^challenge_monster_(%d+)$"))
    local source = index and rules.data.building_challenges[index]
    if not source then return nil, "challenge_definition_missing" end
    local mode, mode_error = rules.mode(mode_id or "standard", difficulty_id)
    if not mode then return nil, mode_error or "human_challenge_mode_missing" end
    current_wave = tonumber(current_wave) or 0
    if current_wave < 1 or current_wave >= mode.total_waves then
        return nil, "challenge_wave_limit_reached"
    end
    local next_base = rules.wave_base(current_wave + 1)
    local current_base = rules.wave_base(current_wave)
    if not next_base or not current_base then return nil, "challenge_wave_missing" end
    return {
        challenge_id = challenge_id, difficulty_id = difficulty_id,
        health = source.fixed_health + next_base.health * mode.hp_multiplier * source.health_coefficient,
        attack = source.fixed_attack + next_base.attack * mode.hp_multiplier * source.attack_coefficient,
        war3_armor = rules.wave_armor(mode_id or "standard", difficulty_id, current_wave),
        attack_speed = 1, enabled = true, human_spec = true,
        formula_wave_number = current_wave,
    }, nil
end

return M
