-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: tower_lightning_effects.csv
local M = {}
M.rows = {
    { effect_key = "SR", particle_name = "particles/econ/items/zeus/zeus_ti8_immortal_arms/zeus_ti8_immortal_arc.vpcf", enabled = true, notes = "风暴之示ItemDef12323；完整Q；同品质五级共用；R沿用原资源。" },
    { effect_key = "SSR", particle_name = "particles/units/heroes/hero_zuus/zuus_arc_lightning.vpcf", enabled = true, notes = "第三阶段改回宙斯原生连锁闪电；取消金色连线与附加金色命中；含红星进阶。" },
    { effect_key = "strike", particle_name = "particles/econ/items/disruptor/disruptor_2022_immortal/disruptor_2022_immortal_static_storm.vpcf", enabled = true, notes = "风暴串联之震ItemDef23655原生R全套；CP1为技能半径；怒雷视觉1.2秒；塔雷暴沿用技能持续时间；不产生原生技能伤害或沉默。", visual_duration = 1.2 },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["effect_key"]
    if key ~= nil then M.by_id[key] = row end
end
return M
