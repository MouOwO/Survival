-- The two human-readable specification files own combat numbers. Existing
-- wave rows supply appearance/routing metadata only, never recorded final stats.
local rules = require("config/human_monster_rules")
local M = {}
local NO_LEADER = {[1]=true,[2]=true,[3]=true,[5]=true,[10]=true,
    [15]=true,[20]=true,[25]=true,[30]=true}
local ROTATION_MODES = {standard=true,cold=true,rich=true,pure=true}

local function clone(value)
    if type(value) ~= "table" then return value end
    local result = {}; for key, child in pairs(value) do result[key] = clone(child) end
    return result
end

local function templates(rows, difficulty_id, wave_number)
    local selected = {}
    for _, id in ipairs({difficulty_id, "N1", "N2"}) do
        for _, row in ipairs(rows or {}) do
            if row.enabled ~= false and row.difficulty_id == id and row.wave_number == wave_number then
                selected[#selected+1] = row
            end
        end
        if #selected > 0 then break end
    end
    table.sort(selected, function(a,b) return (a.spawn_order or 0) < (b.spawn_order or 0) end)
    local normal, leader, boss = {}, nil, nil
    for _, row in ipairs(selected) do
        if row.member_role == "assault_boss" or row.member_role == nil and row.is_boss then boss = row
        elseif row.member_role == "wave_leader" then leader = row
        else normal[#normal+1] = row end
    end
    return normal, leader, boss
end

local function combat(base, mode, hp, armor, attack)
    return {health=base.health*mode.hp_multiplier*hp,
        war3_armor=base.war3_armor*mode.armor_multiplier*armor,
        attack=base.attack*mode.hp_multiplier*attack,
        attack_speed=1/base.attack_interval}
end

local function member(template, stats, mode_id, difficulty_id, wave_number, index, role, interval)
    local row = clone(assert(template, "human_wave_appearance_missing:"..wave_number))
    -- The recordings' alternating final values must not overwrite the formulas
    -- later in rich_stat_variant_row.resolve at the spawn scheduling boundary.
    row.rich_stat_variants = nil
    row.health, row.war3_armor, row.attack, row.attack_speed =
        stats.health, stats.war3_armor, stats.attack, stats.attack_speed
    row.wave_id = string.format("human_%s_%s_%02d_%03d",mode_id,difficulty_id:lower(),wave_number,index)
    row.batch_id = string.format("%dS%d",wave_number,index)
    row.difficulty_id, row.mode_id, row.wave_number = difficulty_id, mode_id, wave_number
    row.monster_count, row.spawn_order, row.spawn_interval = 1, index, interval
    row.member_role, row.is_boss, row.boss_warning = role, role=="assault_boss", role=="assault_boss"
    row.enabled, row.human_spec_sequence, row.human_spec_stats, row.human_spec = true, true, true, true
    row.human_spec_position, row.stats_source = index, "human_monster_spec_v3"
    return row
end

function M.build(rows, definition, mode_id)
    mode_id = mode_id or "standard"
    local difficulty_id = definition.difficulty_id
    local mode, reason = rules.mode(mode_id,difficulty_id)
    if not mode then return nil, reason or "human_mode_difficulty_missing" end
    local built = {difficulty=definition,mode_id=mode_id,total_waves=mode.total_waves,rows={},waves={}}
    for number=1,mode.total_waves do
        local base = assert(rules.wave_base(number), "human_wave_base_missing:"..number)
        local normals, leader, boss = templates(rows,difficulty_id,number)
        local main = normals[1] or leader
        local population = assert(rules.count(mode_id,difficulty_id,number))
        local count, interval = population.count, population.spawn_interval
        local boss_base = rules.data.attack_bosses[number]
        -- Counts use the project's established per-player total: the assault
        -- boss occupies one slot rather than adding a sixty-first rich unit.
        local ordinary_count = count - (boss_base and 1 or 0)
        local wave, has_leader = {}, not NO_LEADER[number]
        local rotations = ROTATION_MODES[mode_id] and rules.data.special_rotation[number] or nil
        if boss_base then
            local extra = mode_id=="ruins" or mode_id=="celestial"
            local stats = combat(boss_base,mode,extra and 5 or 1,1,extra and 3 or 1)
            -- Preserve the existing boss arrival/warning at the start of each
            -- fifth wave; only its stats and total-count allocation change.
            wave[#wave+1] = member(boss or main,stats,mode_id,difficulty_id,number,1,"assault_boss",interval)
        end
        for index=1,ordinary_count do
            local role = has_leader and index==1 and "wave_leader" or "normal"
            local appearance = role=="wave_leader" and (leader or main) or main
            local stats, rotation = nil, nil
            if role=="wave_leader" then
                stats = mode_id=="scourge" and combat(base,mode,2,1,2) or combat(base,mode,10,2,4)
            else
                local position = ((index-(has_leader and 2 or 1))%3)+1
                for _, candidate in ipairs(rotations or {}) do
                    if candidate.position==position then rotation=candidate; break end
                end
                if rotation then
                    stats = combat(rotation,mode,1,1,1)
                    -- Confirmed final stats apply after mode scaling, scoped
                    -- to this mode/tier and rotation. Armor keeps its scale.
                    local confirmed = rules.special_rotation_stats(mode_id,difficulty_id,
                        number,rotation.position)
                    if confirmed then
                        stats.health = confirmed.health or stats.health
                        stats.attack = confirmed.attack or stats.attack
                    end
                    appearance = normals[rotation.position] or main
                else
                    stats = mode_id=="scourge" and combat(base,mode,3,2,1) or combat(base,mode,1,1,1)
                    -- Keep the existing ordinary model alternatives when there
                    -- is no authored special-monster cycle for this wave.
                    if not rotations then appearance=normals[(index-1)%math.max(1,#normals)+1] or main end
                end
            end
            local row = member(appearance,stats,mode_id,difficulty_id,number,
                index+(boss_base and 1 or 0),role,interval)
            row.movement_type_override = base.flying and "flying" or "ground"
            row.human_spec_rotation_position = rotation and rotation.position or nil
            if mode_id=="scourge" and role=="normal" then
                row.human_spec_scourge_roll = true
                row.human_spec_elite_stats = combat(base,mode,5,2,2)
            end
            wave[#wave+1] = row
        end
        built.waves[number] = wave
        for _, row in ipairs(wave) do built.rows[#built.rows+1] = row end
    end
    return built
end

-- Called separately for each player's physical spawn. Leaders and assault
-- bosses never consume a roll; all other scourge units independently roll 50%.
function M.resolve_spawn(row, random_int)
    if row.human_spec_scourge_roll ~= true then return row end
    local result = clone(row)
    result.human_spec_elite = (random_int or math.random)(1,100) <= 50
    if result.human_spec_elite then
        for key, value in pairs(assert(row.human_spec_elite_stats)) do result[key] = value end
    end
    result.human_spec_scourge_roll = nil
    return result
end

return M
