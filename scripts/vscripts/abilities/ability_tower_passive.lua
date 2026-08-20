local skill_config = require("config/generated/tower_skill_definitions")
local fusion_runtime = require("config/generated/tower_fusion_runtime")
local tower_special_skill_system = require("systems/tower_special_skill_system")

local M = class({})

function M:GetBehavior()
    return DOTA_ABILITY_BEHAVIOR_PASSIVE
end

function M:GetManaCost()
    return 0
end

function M:OnProjectileHit_ExtraData(target, location, extra_data)
    return tower_special_skill_system.on_burning_wave_projectile_hit(
        self,
        target,
        location,
        extra_data
    )
end

-- 多个配置技能共用同一个实现。引擎按 Ability ID 查找 Lua 全局类，
-- 因此必须为 CSV 中每个真实 skill_id 注册同一个类。
_G.ability_tower_passive = M
for _, definition in ipairs(skill_config.rows or {}) do
    if definition.enabled ~= false and definition.skill_id then
        _G[definition.skill_id] = M
    end
end
for _, definition in ipairs(fusion_runtime.rows or {}) do
    if definition.enabled ~= false then
        for _, ability_id in ipairs(definition.passive_slot_ability_ids or {}) do
            _G[ability_id] = M
        end
    end
end

return M
