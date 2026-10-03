-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: tower_lightning_effects.csv
local M = {}
M.rows = {
    { effect_key = "SR", particle_name = "particles/econ/items/zeus/zeus_ti8_immortal_arms/zeus_ti8_immortal_arc.vpcf", enabled = true, notes = "风暴之示ItemDef12323；完整Q；同品质五级共用；R沿用原资源。" },
    { effect_key = "SSR", particle_name = "particles/survival/towers/trial/lightning_ssr_arc.vpcf", enabled = true, notes = "SSR 原生白蓝连锁闪电加强版；主干宽度1.8倍，保留原生子层，取消金雷；本阶五级与红星共用。" },
    { effect_key = "strike", particle_name = "particles/econ/items/disruptor/disruptor_2022_immortal/disruptor_2022_immortal_static_storm.vpcf", enabled = true, notes = "塔雷暴使用风暴串联之震ItemDef23655原生R全套；CP1为技能半径；沿用技能持续时间；不产生原生技能伤害或沉默。", visual_duration = 1.2 },
    { effect_key = "hero_strike", particle_name = "particles/econ/items/zeus/lightning_weapon_fx/zuus_lightning_bolt_immortal_lightning.vpcf", cast_particle = "particles/econ/items/zeus/lightning_weapon_fx/zuus_lb_cfx_il.vpcf", enabled = true, notes = "英雄怒雷使用真霹实雳ItemDef5412原生W完整落雷与施法效果；主资源自带地面裂痕与火焰；自然消退保留秒杀残影。" },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["effect_key"]
    if key ~= nil then M.by_id[key] = row end
end
return M
