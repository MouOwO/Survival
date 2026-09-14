# 官方技能与物品图标替换（2026-09-13）

已实现：22 个技能定义、17 个物品定义修正；同步配置 CSV、生成 Lua、Tooltip 和物品目录图标。未改商城与存档已经确认的独立美术素材。

已验证：直接读取本机 dota/pak01_dir.vpk 索引，243 个技能定义及 56 个物品定义中所有可显示图标均能找到官方资源；6 个隐藏占位槽无图标按原用途保留。KV 对比仅 AbilityTextureName 变化；CSV 对比仅 icon 相关字段变化，无玩法值变化。

尚未验证：重新载入地图后的游戏内显示。当前对局未重启；KV 和服务配置不能仅靠 Panorama 热更新确认。

复查命令：`python tools/art_assets/audit_official_icons.py`。它读取当前安装版本 VPK，不依赖旧资源名缓存。

| 定义 | 旧图标 | 新官方图标 |
|---|---|---|
| ability_challenge_monster_03 | skeleton_king_vampiric_aura | lycan_feral_impulse |
| ability_lumberjack_personality_workaholic | juggernaut_omnislash | juggernaut_omni_slash |
| ability_survival_power_training | item_blades_of_attack | sven_gods_strength |
| ability_survival_vitality_training | item_vitality_booster | centaur_great_fortitude |
| ability_survival_agility_training | item_eagle | morphling_morph_agi |
| ability_survival_intellect_training | item_mystic_staff | silencer_glaives_of_wisdom |
| ability_survival_armor_training | item_chainmail | dragon_knight_dragon_blood |
| ability_survival_attack_speed_training | item_gloves | invoker_alacrity |
| ability_survival_move_speed_training | item_boots | windrunner_windrun |
| ability_survival_health_regen_training | item_ring_of_regen | huskar_inner_vitality |
| ability_survival_mana_regen_training | item_void_stone | crystal_maiden_brilliance_aura |
| ability_survival_return_home | item_tpscroll | furion_teleportation |
| ability_survival_rogue_reward | item_tome_of_knowledge | invoker_invoke |
| ability_survival_pickup_materials | item_recipe | alchemist_goblins_greed |
| ability_research_lumberjack_speed | ability_train_lumberjack | alchemist_goblins_greed |
| ability_research_advanced_lumberjack_speed | ability_train_lumberjack | alchemist_goblins_greed |
| ability_research_tower_attack | ability_upgrade_attack | sven_great_cleave |
| ability_research_advanced_tower_attack | ability_upgrade_attack | sven_great_cleave |
| ability_research_wall_health | ability_upgrade_wall | treant_living_armor |
| ability_research_advanced_wall_health | ability_upgrade_wall | treant_living_armor |
| ability_research_ars_03 | ability_upgrade_wall | treant_living_armor |
| ability_research_ars_05 | ability_upgrade_attack | sven_great_cleave |
| item_survival_challenge_reward | item_recipe | item_ultimate_orb |
| item_survival_synthesis_gem_shell | item_recipe | item_gem |
| item_survival_molten_core_01_shell | item_recipe | item_soul_booster |
| item_survival_molten_core_02_shell | item_recipe | item_soul_booster |
| item_survival_molten_core_03_shell | item_recipe | item_soul_booster |
| item_survival_molten_core_04_shell | item_recipe | item_soul_booster |
| item_survival_ice_soul_ember_shell | item_recipe | item_shivas_guard |
| item_survival_frost_blade_01 | item_crystalys | item_lesser_crit |
| item_survival_frost_blade_02 | item_crystalys | item_lesser_crit |
| item_survival_frost_blade_03 | item_crystalys | item_lesser_crit |
| item_survival_frost_blade_04 | item_crystalys | item_lesser_crit |
| item_survival_frost_blade_max | item_crystalys | item_lesser_crit |
| item_survival_ice_blade_01 | item_daedalus | item_greater_crit |
| item_survival_ice_blade_02 | item_daedalus | item_greater_crit |
| item_survival_ice_blade_03 | item_daedalus | item_greater_crit |
| item_survival_ice_blade_04 | item_daedalus | item_greater_crit |
| item_survival_ice_blade_max | item_daedalus | item_greater_crit |
