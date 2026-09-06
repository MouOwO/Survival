# 波次怪物英雄外观调整（2026-09-06）

已按用户确认的 39 个原型配置独立外观。`orc_longnose_small` 使用死亡冲刺，`stitcher_small` 使用力士七兵，“干娇魔女”按官方名称千娇魔女处理。

## 配置入口

- `data/csv/怪物与波次系统/monster_archetypes.csv`：模型路径、普通飞行模型路径、`default_wearable_asset_id`。
- `data/csv/资源系统/asset_catalog.csv`：主体、材质皮肤、预载代理、基础英雄头像。
- `asset_components.csv`、`asset_effects.csv`、`asset_activity_modifiers.csv`：骨骼合并组件、常驻粒子、动作修饰。
- 三种古龙形态声明为完整 `model`，不挂人形部件；火龙使用 skin 1。其他套装声明为 `model_bundle`。
- 夜魇暗潮幽光主体和部件使用对应皮肤，并挂载官方幽光粒子。恐怖利刃使用 Arcana 主体、心渊魔角及其他槽位基础部件。
- 帕格纳冥灵之怒两种手臂互斥，采用列表中的刺臂；兽王召唤物、维萨吉佣兽、帕格纳守卫和载入画面不挂到怪物本体。普通龙骑士焦灼琥珀使用人形六部件。
- 外观服务通过既有逐原型资产 ID 预载链路接入，保留前 1–5 波的中立怪视觉覆盖。使用这些原型的练功房等既有非正式波次入口沿用原有模型规则。
- 数值、移动/攻击类型、模型缩放、怪物数量、波次与奖励未修改。

## 映射

| 怪物原型 | 英雄单位 | 官方套装/物品 | ItemDef |
| --- | --- | --- | --- |
| `humanoid_red_axe` | `axe` | 黑兽战魁 | 21022 |
| `skeleton_melee` | `clinkz` | 燃炙裁决游民 | 21005 |
| `orc_large_melee` | `beastmaster` | 混沌荒原劫掠酋长 | 21036 |
| `orc_small_axe` | `ogre_magi` | 双鱼双子 | 36001 |
| `demon_purple_melee` | `bloodseeker` | 血魔的夜魇暗潮幽光捆绑包 | 21789 |
| `boss_dreadlord` | `abyssal_underlord` | 贪婪深渊 | 21515 |
| `beast_green_large` | `tidehunter` | 深海巨兽 | 21503 |
| `skeleton_bone` | `pugna` | 冥灵之怒 | 22344 |
| `flying_red_gargoyle` | `dragon_knight` | 寒翼兽 | 9644 |
| `dragon_red_large` | `dragon_knight` | Monster Hunter火龙形态 | 31375 |
| `dragon_red_small` | `dragon_knight` | 烈焰之鳞龙影 | 8979 |
| `orc_brown_large` | `magnataur` | 猛犸霸王 | 36194 |
| `orc_brown_small` | `magnataur` | 马格纳斯的夜魇暗潮幽光捆绑包 | 21794 |
| `flying_green_head` | `visage` | 灵魂守卫铠甲 | 21010 |
| `dragon_purple_large` | `viper` | 冥虫先锋 | 21253 |
| `dragon_purple_small` | `viper` | 空袭之龙 | 21436 |
| `dwarf_white_rifle` | `hoodwink` | 托莫干步兵 | 29290 |
| `orc_longnose_large` | `spirit_breaker` | 苍晶巨人 | 30452 |
| `orc_longnose_small` | `spirit_breaker` | 死亡冲刺套装 | 20308 |
| `flying_carpet_mage` | `dark_willow` | 寒铁蒺藜 | 21604 |
| `carpet_red_large` | `dark_willow` | 千娇魔女 | 21428 |
| `carpet_red_small` | `dark_willow` | 盛冬玫瑰的诅咒 | 20623 |
| `undead_red_mage_large` | `troll_warlord` | 好乐劫徒 | 31091 |
| `undead_red_mage_small` | `troll_warlord` | 醒目罪魁 | 21815 |
| `golem_gray_small` | `dark_seer` | 维齐尔流犯著作 | 21053 |
| `golem_gray_large` | `dark_seer` | 宝蓝衣冠的洞察 | 21210 |
| `beast_striped_red` | `dragon_knight` | 焦灼琥珀 | 21387 |
| `boss_blade_demon` | `night_stalker` | 暗誓之源 | 21486 |
| `sea_beast_large` | `naga_siren` | 苍洋烈士 | 28273 |
| `sea_beast_small` | `naga_siren` | 娜迦海妖的夜魇暗潮幽光捆绑包 | 21795 |
| `armored_horned_large` | `axe` | 金辉暴君 | 31373 |
| `armored_horned_small` | `axe` | 斧王的夜魇暗潮幽光捆绑包 | 21694 |
| `dragon_black_red_large` | `winter_wyvern` | 极光之棘 | 21818 |
| `dragon_black_red_small` | `winter_wyvern` | 瑚海之秘 | 21112 |
| `stitcher_large` | `pudge` | 畸变观察者 | 28270 |
| `stitcher_small` | `pudge` | 力士七兵 | 20862 |
| `flying_black_bone` | `visage` | 灵空收割的制裁 | 21248 |
| `golem_green_fire` | `necrolyte` | 腐铁开膛手 | 25023 |
| `boss_twinblade_demon` | `terrorblade` | 心渊魔角 | 5957 |

## 构建和验证

`tools/build_wave_monster_cosmetics.py` 从本机 `pak01_dir.vpk` 读取官方经济定义，核对模型/粒子路径，再同步目标 CSV 和 39 个预载代理。`--check` 为只读比对。常规 CSV 修改使用已有 `build_configs.ps1` 生成 Lua；不要手改生成文件。

本次新增 39 个资产、174 个组件、47 个常驻粒子声明和 5 个动作修饰；241 个去重资源路径均存在于本机 VPK。五个受影响生成模块按 CSV 重建。

CSV 全局形状、声音引用、怪物视觉引用、完整模型/穿戴包引用、肉鸽配置验证通过。对比修改前怪物表，39 行仅三个视觉字段改变。

通过 Lua 测试：`test_monster_cosmetic_details`、`test_wave_monster_cosmetics`、`test_monster_hero_visual_service`、`test_monster_visual_config`、`test_monster_visual_service`、`test_monster_default_wearable_preload`、`test_wave_model_resource_lifecycle`。覆盖材质恢复、粒子挂点、重复应用、切换/清理、同主体多套装的独立预载及波次资源租约。

既有 `test_wave_monster_visual_integration.lua:224` 生命值/攻击/护甲断言仍失败，使用修改前生成怪物配置可复现；未更改战斗数值来迁就该断言。

`visual/monster_cosmetic_details.lua` 管理本批次 `wave_cosmetic_ambient` 粒子；`control_profile` 格式为 `CP=attachment|CP=attachment`，来自官方粒子控制点声明。死亡、换装和清理时释放粒子并恢复材质，挂件仍由现有 `model_appearance_service` 管理。

待 Workshop Tools 完全冷启动实机验证：39 套骨骼贴合、三种古龙的火龙材质、幽光效果、同波不同套装、尺寸/碰撞、死亡清理及基础头像。自动检查不代表完成实机视觉验收。
