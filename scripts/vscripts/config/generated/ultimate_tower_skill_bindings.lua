-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: ultimate_tower_skill_bindings.csv
local M = {}
M.rows = {
    { binding_id = "ultimate_direct_piercing", slot_category = "直接作用于普通攻击", display_slot = 1, skill_id = "piercing_ballista_lv05", source_tower = "anti_air_tower", trigger_phase = "on_attack_landed", enabled = true, notes = "命中后施加穿甲减益" },
    { binding_id = "ultimate_direct_critical", slot_category = "直接作用于普通攻击", display_slot = 1, skill_id = "critical_strike_lv05", source_tower = "death_tower", trigger_phase = "on_attack_start", enabled = true, notes = "普通攻击暴击判定" },
    { binding_id = "ultimate_direct_multi", slot_category = "直接作用于普通攻击", display_slot = 1, skill_id = "multi_attack_lv05", source_tower = "multi_tower", trigger_phase = "on_attack_landed", enabled = true, notes = "额外目标分裂箭不生成普通攻击递归" },
    { binding_id = "ultimate_attack_bounty", slot_category = "由普通攻击引出", display_slot = 2, skill_id = "bounty_machine_gun_lv05", source_tower = "machine_gun_tower", trigger_phase = "on_attack_landed", enabled = true, notes = "命中后奖励金币" },
    { binding_id = "ultimate_attack_ice", slot_category = "由普通攻击引出", display_slot = 2, skill_id = "ice_blizzard_lv05", source_tower = "frost_tower", trigger_phase = "on_attack_landed", enabled = true, notes = "命中后概率触发暴风雪" },
    { binding_id = "ultimate_attack_explosive", slot_category = "由普通攻击引出", display_slot = 2, skill_id = "explosive_gatling_lv01", source_tower = "machine_gun_tower", trigger_phase = "on_attack_landed", enabled = true, notes = "只计数不改为机枪多跳" },
    { binding_id = "ultimate_attack_arcane", slot_category = "由普通攻击引出", display_slot = 2, skill_id = "arcane_cannon_lv05", source_tower = "mystery_tower", trigger_phase = "on_kill", enabled = true, notes = "击杀后叠加面板伤害Buff" },
    { binding_id = "ultimate_panel_frost", slot_category = "面板被动", display_slot = 3, skill_id = "frost_attack_lv05", source_tower = "frost_tower", trigger_phase = "on_attack_landed", enabled = true, notes = "命中附加范围减速伤害" },
    { binding_id = "ultimate_panel_death", slot_category = "面板被动", display_slot = 3, skill_id = "death_grenade_lv01", source_tower = "death_tower", trigger_phase = "on_attack_landed", enabled = true, notes = "仅对原目标追加技能伤害" },
    { binding_id = "ultimate_aura_polar", slot_category = "光环", display_slot = 4, skill_id = "polar_obelisk_lv01", source_tower = "frost_tower", trigger_phase = "aura_interval", enabled = true, notes = "范围内敌人攻击速度降低" },
    { binding_id = "ultimate_secondary_lightning", slot_category = "次生技能", display_slot = 5, skill_id = "lightning_strike_lv05", source_tower = "lightning_tower", trigger_phase = "secondary_chain", enabled = true, notes = "链条以去重集合终止" },
    { binding_id = "ultimate_secondary_storm", slot_category = "次生技能", display_slot = 5, skill_id = "lightning_storm_lv05", source_tower = "lightning_tower", trigger_phase = "secondary_storm", enabled = true, notes = "风暴伤害不重新触发普通攻击技能" },
    { binding_id = "ultimate_secondary_diffusion", slot_category = "次生技能", display_slot = 5, skill_id = "lightning_diffusion_lv01", source_tower = "lightning_tower", trigger_phase = "secondary_diffusion", enabled = true, notes = "扩散链禁止递归扩散" },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["binding_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
