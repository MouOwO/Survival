-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: hero_initial_skills.csv
local M = {}
M.rows = {
    { initial_entry_id = "initial_axe_01", hero_id = "hero_axe", slot_order = 1, skill_id = "skill_axe_exclusive", initial_level = 1, source_type = "exclusive", enabled = true, notes = "普通英雄1个初始专属技能。" },
    { initial_entry_id = "initial_slark_01", hero_id = "hero_slark", slot_order = 1, skill_id = "skill_slark_exclusive", initial_level = 1, source_type = "exclusive", enabled = true, notes = "普通英雄1个初始专属技能。" },
    { initial_entry_id = "initial_jugg_01", hero_id = "hero_juggernaut", slot_order = 1, skill_id = "skill_juggernaut_exclusive", initial_level = 1, source_type = "exclusive", enabled = true, notes = "普通英雄1个初始专属技能。" },
    { initial_entry_id = "initial_monkey_01", hero_id = "hero_monkey_king", slot_order = 1, skill_id = "skill_monkey_king_exclusive", initial_level = 1, source_type = "exclusive", enabled = true, notes = "VIP初始技能1。" },
    { initial_entry_id = "initial_monkey_02", hero_id = "hero_monkey_king", slot_order = 2, skill_id = "skill_power_training", initial_level = 1, source_type = "public_configured", enabled = true, notes = "VIP初始技能2。" },
    { initial_entry_id = "initial_monkey_03", hero_id = "hero_monkey_king", slot_order = 3, skill_id = "skill_attack_speed_training", initial_level = 1, source_type = "public_configured", enabled = true, notes = "VIP初始技能3。" },
    { initial_entry_id = "initial_monkey_04", hero_id = "hero_monkey_king", slot_order = 4, skill_id = "skill_attack_range_training", initial_level = 1, source_type = "public_configured", enabled = true, notes = "VIP初始技能4。" },
    { initial_entry_id = "initial_blademaster_01", hero_id = "hero_blademaster", slot_order = 1, skill_id = "skill_blademaster_exclusive", initial_level = 1, source_type = "exclusive", enabled = true, notes = "VIP初始技能1。" },
    { initial_entry_id = "initial_blademaster_02", hero_id = "hero_blademaster", slot_order = 2, skill_id = "skill_power_training", initial_level = 1, source_type = "public_configured", enabled = true, notes = "VIP初始技能2。" },
    { initial_entry_id = "initial_blademaster_03", hero_id = "hero_blademaster", slot_order = 3, skill_id = "skill_agility_training", initial_level = 1, source_type = "public_configured", enabled = true, notes = "VIP初始技能3。" },
    { initial_entry_id = "initial_blademaster_04", hero_id = "hero_blademaster", slot_order = 4, skill_id = "skill_attack_speed_training", initial_level = 1, source_type = "public_configured", enabled = true, notes = "VIP初始技能4。" },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["initial_entry_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
