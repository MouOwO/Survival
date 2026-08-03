-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: hero_exclusive_skills.csv
local M = {}
M.rows = {
    { exclusive_entry_id = "exclusive_doom_01", exclusive_group_id = "exclusive_doom", hero_id = "hero_doom", skill_id = "skill_doom_infernal", initial_level = 1, guaranteed = true, enabled = true, notes = "免费英雄一转激活固定Q槽专属技能。" },
    { exclusive_entry_id = "exclusive_shadow_fiend_01", exclusive_group_id = "exclusive_shadow_fiend", hero_id = "hero_shadow_fiend", skill_id = "skill_shadow_fiend_raze", initial_level = 1, guaranteed = true, enabled = true, notes = "免费英雄一转激活固定Q槽专属技能。" },
    { exclusive_entry_id = "exclusive_axe_01", exclusive_group_id = "exclusive_axe", hero_id = "hero_axe", skill_id = "skill_axe_counter_helix", initial_level = 1, guaranteed = true, enabled = true, notes = "免费英雄一转激活固定Q槽专属技能。" },
    { exclusive_entry_id = "exclusive_drow_01", exclusive_group_id = "exclusive_drow_ranger", hero_id = "hero_drow_ranger", skill_id = "skill_drow_companion", initial_level = 1, guaranteed = true, enabled = true, notes = "免费英雄一转激活固定Q槽专属技能。" },
    { exclusive_entry_id = "exclusive_monkey_01", exclusive_group_id = "exclusive_monkey_king", hero_id = "hero_monkey_king", skill_id = "skill_monkey_king_exclusive", initial_level = 1, guaranteed = true, enabled = true },
    { exclusive_entry_id = "exclusive_monkey_02", exclusive_group_id = "exclusive_monkey_king", hero_id = "hero_monkey_king", skill_id = "skill_monkey_king_fury", initial_level = 1, guaranteed = true, enabled = true, notes = "VIP一转解锁专属技能。" },
    { exclusive_entry_id = "exclusive_monkey_03", exclusive_group_id = "exclusive_monkey_king", hero_id = "hero_monkey_king", skill_id = "skill_monkey_king_swiftness", initial_level = 1, guaranteed = true, enabled = true, notes = "VIP一转解锁专属技能。" },
    { exclusive_entry_id = "exclusive_monkey_04", exclusive_group_id = "exclusive_monkey_king", hero_id = "hero_monkey_king", skill_id = "skill_monkey_king_agility", initial_level = 1, guaranteed = true, enabled = true, notes = "VIP一转解锁专属技能。" },
    { exclusive_entry_id = "exclusive_blademaster_01", exclusive_group_id = "exclusive_blademaster", hero_id = "hero_blademaster", skill_id = "skill_blademaster_exclusive", initial_level = 1, guaranteed = true, enabled = true },
    { exclusive_entry_id = "exclusive_blademaster_02", exclusive_group_id = "exclusive_blademaster", hero_id = "hero_blademaster", skill_id = "skill_blademaster_agility", initial_level = 1, guaranteed = true, enabled = true, notes = "VIP一转解锁专属技能。" },
    { exclusive_entry_id = "exclusive_blademaster_03", exclusive_group_id = "exclusive_blademaster", hero_id = "hero_blademaster", skill_id = "skill_blademaster_swiftness", initial_level = 1, guaranteed = true, enabled = true, notes = "VIP一转解锁专属技能。" },
    { exclusive_entry_id = "exclusive_blademaster_04", exclusive_group_id = "exclusive_blademaster", hero_id = "hero_blademaster", skill_id = "skill_blademaster_mobility", initial_level = 1, guaranteed = true, enabled = true, notes = "VIP一转解锁专属技能。" },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["exclusive_entry_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
