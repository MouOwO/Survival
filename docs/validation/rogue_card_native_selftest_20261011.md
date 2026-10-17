# 肉鸽卡牌全量实际自测结果（2026-10-11）

48张启用卡均完成离线生产模块自测与真实Dota核心消费者检查；21张开局卡、17张Boss战斗卡、10张Boss行动/资源卡全部通过。4张原本禁用的卡按配置跳过。当前没有尚未修复的核心卡牌效果失败。

实际检查包含资源到账、正式升级与训练、真实波次和挑战怪、原生攻击/伤害、吸血阶段及道具消费。领取成功、runtime登记和面板数字本身不替代消费者验证。

[机器结果与逐卡证据](../../validation/20261011/rogue_card_native_selftest.json)保留48张卡的正式ID、说明、离线测试入口及控制台映射。本页只记录当前通过状态和仍难测的边界，历史修复过程不重复列出。

## 实际游戏截图

截图来自实际Dota游戏窗口；数值结论仍以原生getter、正式事件和实际伤害/资源日志为证。

![普通防御塔实际测试场景](../../output/rogue_full_selftest_20261011/tower_cards_game_only.png)

![真正七材料终极融合塔实际测试场景](../../output/rogue_full_selftest_20261011/ultimate_cards_game_only.png)

## 终极融合验证

七条正式满阶路线通过正常建造/升级准备，再由生产融合消耗七个材料生成实际究极塔。最后23项原生断言全部通过：继承基线、科技/英雄平加、动态英雄更新、真实主攻击与伤害过滤一致。

首次领取远距齐射在实际究极塔上增加攻击800、射程500；锐利速射使原生频率3→3.6次/秒。预拥有斗志/串联的继承不会重复叠加，步调一致随英雄当前数据更新。

融合后首次领取防御工事，科技攻速贡献20%→26%，原生频率3.6→3.78次/秒；正式领取、主攻击过滤及实际扣血共5项断言全部通过。

[23项完整原生结果](../../output/rogue_full_selftest_20261011/ultimate_verified_console.txt)；[首次领取增量的实际记录](../../output/rogue_full_selftest_20261011/ultimate_retest_final_run_console.txt)。

## 逐卡映射

| 卡牌 | 离线 | 核心实机 | 主要实际证据 |
| --- | --- | --- | --- |
| 冰封城墙 `frozen_wall` | PASS | PASS | [native_verified_console.txt:20](../../output/rogue_full_selftest_20261011/native_verified_console.txt) |
| 新兵作训 `recruit_training` | PASS | PASS | [builder_consumers1_console.txt:14](../../output/rogue_full_selftest_20261011/builder_consumers1_console.txt) |
| 离子护盾 `ion_shield` | PASS | PASS | [wall_fusion_result_console.txt:8](../../output/rogue_full_selftest_20261011/wall_fusion_result_console.txt) |
| 虚弱宝珠 `weakening_orb` | PASS | PASS | [native_verified_console.txt:20](../../output/rogue_full_selftest_20261011/native_verified_console.txt) |
| 神许愿 `divine_wish` | PASS | PASS | [fresh_wish_console.txt](../../output/rogue_full_selftest_20261011/fresh_wish_console.txt) |
| 炮塔成长 `tower_growth` | PASS | PASS | [combat_final2_console.txt:25](../../output/rogue_full_selftest_20261011/combat_final2_console.txt) |
| 防御工事 `fortifications` | PASS | PASS | [builder_consumers1_console.txt:12](../../output/rogue_full_selftest_20261011/builder_consumers1_console.txt) |
| 盛宴 `feast` | PASS | PASS | [combat_formal_console.txt:26](../../output/rogue_full_selftest_20261011/combat_formal_console.txt) |
| 老板的大饼 `boss_promise` | PASS | PASS | [builder_consumers1_console.txt:10](../../output/rogue_full_selftest_20261011/builder_consumers1_console.txt) |
| 命令更换 `command_change` | PASS | PASS | [actions_trials_console.txt](../../output/rogue_full_selftest_20261011/actions_trials_console.txt) |
| 基建狂魔 `infrastructure_maniac` | PASS | PASS | [endless_class_console.txt](../../output/rogue_full_selftest_20261011/endless_class_console.txt) |
| 火药溅射 `gunpowder_splash` | PASS | PASS | [gunpowder_confirmed_console.txt:6](../../output/rogue_full_selftest_20261011/gunpowder_confirmed_console.txt) |
| 璀璨树苗 `radiant_sapling` | PASS | PASS | [endless_class_console.txt](../../output/rogue_full_selftest_20261011/endless_class_console.txt) |
| 落井下石 `kick_when_down` | PASS | PASS | [combat_formal_console.txt:10](../../output/rogue_full_selftest_20261011/combat_formal_console.txt) |
| 炮塔串联 `tower_network` | PASS | PASS | [fresh_network_console.txt:4](../../output/rogue_full_selftest_20261011/fresh_network_console.txt) |
| 财政补贴 `fiscal_subsidy` | PASS | PASS | [endless_class_console.txt](../../output/rogue_full_selftest_20261011/endless_class_console.txt) |
| 腐蚀护盾 `corrosive_shield` | PASS | PASS | [fusion_corrosive_console.txt:8](../../output/rogue_full_selftest_20261011/fusion_corrosive_console.txt) |
| 核弹 `nuclear_bomb` | PASS | PASS | [verify_wave6_console.txt](../../output/rogue_full_selftest_20261011/verify_wave6_console.txt) |
| 赏金密令 `bounty_order` | PASS | PASS | [wish_bounty_result_console.txt](../../output/rogue_full_selftest_20261011/wish_bounty_result_console.txt) |
| 斗志昂扬 `high_morale` | PASS | PASS | [final_combat_valid_console.txt:4](../../output/rogue_full_selftest_20261011/final_combat_valid_console.txt) |
| 步调一致 `in_step` | PASS | PASS | [combat_formal_console.txt:19](../../output/rogue_full_selftest_20261011/combat_formal_console.txt) |
| 建造密令 `construction_order` | PASS | PASS | [fresh_wish_console.txt](../../output/rogue_full_selftest_20261011/fresh_wish_console.txt) |
| 实习证明 `internship_certificate` | PASS | PASS | [gunpowder_confirmed_console.txt](../../output/rogue_full_selftest_20261011/gunpowder_confirmed_console.txt) |
| 渴血药剂 `bloodthirst_potion` | PASS | PASS | [combat_final2_console.txt:8](../../output/rogue_full_selftest_20261011/combat_final2_console.txt) |
| 基建外包 `infrastructure_outsourcing` | PASS | PASS | [endless_class_console.txt](../../output/rogue_full_selftest_20261011/endless_class_console.txt) |
| 铁腕政策 `iron_fist_policy` | PASS | PASS | [wish_bounty_result_console.txt:6](../../output/rogue_full_selftest_20261011/wish_bounty_result_console.txt) |
| 训练靶子 `training_dummy` | PASS | PASS | [combat_final2_console.txt:13](../../output/rogue_full_selftest_20261011/combat_final2_console.txt) |
| 壁垒续航 `wall_recovery` | PASS | PASS | [wall_fusion_result_console.txt:3](../../output/rogue_full_selftest_20261011/wall_fusion_result_console.txt) |
| 富甲天下 `wealthy_start` | PASS | PASS | [resources_upper_console.txt:1](../../output/rogue_full_selftest_20261011/resources_upper_console.txt) |
| 锐利速射 `sharp_volley` | PASS | PASS | [builder_consumers1_console.txt:3](../../output/rogue_full_selftest_20261011/builder_consumers1_console.txt) |
| 伐木狂袭 `lumberjack_assault` | PASS | PASS | [builder_consumers1_console.txt:4](../../output/rogue_full_selftest_20261011/builder_consumers1_console.txt) |
| 坚甲固守 `fortified_defense` | PASS | PASS | [remaining_console.txt:3](../../output/rogue_full_selftest_20261011/remaining_console.txt) |
| 基建狂魔 `infrastructure_maniac_start` | PASS | PASS | [actions_wave_console.txt:5](../../output/rogue_full_selftest_20261011/actions_wave_console.txt) |
| 精研伐木 `precision_lumber` | PASS | PASS | [builder_consumers1_console.txt:5](../../output/rogue_full_selftest_20261011/builder_consumers1_console.txt) |
| 安居乐业 `peaceful_labor` | PASS | PASS | [builder_consumers1_console.txt:6](../../output/rogue_full_selftest_20261011/builder_consumers1_console.txt) |
| 伐骨积薪 `woodcutting_bounty` | PASS | PASS | [endstage_verify_console.txt:1](../../output/rogue_full_selftest_20261011/endstage_verify_console.txt) |
| 瞬采木料 `instant_wood` | PASS | PASS | [builder_initial2_console.txt:1](../../output/rogue_full_selftest_20261011/builder_initial2_console.txt) |
| 淘金秘法 `gold_mining_secret` | PASS | PASS | [ownership_actions_console.txt:7](../../output/rogue_full_selftest_20261011/ownership_actions_console.txt) |
| 英雄降临 `hero_descent` | PASS | PASS | [final_scene_console.txt:49](../../output/rogue_full_selftest_20261011/final_scene_console.txt) |
| 聚拢扩容 `population_expansion` | PASS | PASS | [builder_initial2_console.txt:2](../../output/rogue_full_selftest_20261011/builder_initial2_console.txt) |
| 自然馈赠 `natures_gift` | PASS | PASS | [actions_wave_console.txt:4](../../output/rogue_full_selftest_20261011/actions_wave_console.txt) |
| 紧急加固 `emergency_reinforcement` | PASS | PASS | [remaining_console.txt:4](../../output/rogue_full_selftest_20261011/remaining_console.txt) |
| 疾风战法 `wind_strategy` | PASS | PASS | [builder_initial2_console.txt:6](../../output/rogue_full_selftest_20261011/builder_initial2_console.txt) |
| 全能淬炼 `allround_tempering` | PASS | PASS | [builder_initial2_console.txt:8](../../output/rogue_full_selftest_20261011/builder_initial2_console.txt) |
| 夯大力 `heavy_hand` | PASS | PASS | [fused_rebirth_console.txt:1](../../output/rogue_full_selftest_20261011/fused_rebirth_console.txt) |
| 身先士卒 `first_to_strike` | PASS | PASS | [ownership_actions_console.txt:11](../../output/rogue_full_selftest_20261011/ownership_actions_console.txt) |
| 无限轮回 `endless_rebirth` | PASS | PASS | [remaining_console.txt:2](../../output/rogue_full_selftest_20261011/remaining_console.txt) |
| 远距齐射 `long_range_volley` | PASS | PASS | [builder_consumers1_console.txt:2](../../output/rogue_full_selftest_20261011/builder_consumers1_console.txt) |

## 仍需保留的验证边界

- 实机为单人Dota Tools；多人归属与隔离已有离线生产消费者覆盖，未在四人房逐项复测。
- 夯大力触发、神许愿真实无放回三子均已实际生效；短样本及受控随机数不能证明长期概率分布。
- 已有工人真实攻速翻倍及原截止时间退场已验证；120秒窗口内后新增工人的剩余时间与同步退场未实机量化。
- 实机非零快照5%及真实伤害已验证；领取后满阶塔死亡不改变快照未另行实机采样。50%保护上限仅离线覆盖，正式7塔规则下最大35%。
- 真正七材料融合已验证预拥有30%斗志不会重复添加；融合后首次新领取斗志的增量未独立实机采样。
- 英雄原生物理攻击护甲忽略已量化；终极融合、激光和机枪脚本交付的穿透仍主要由离线生产消费者覆盖。
- 部分卡仅量化原生IAS/BAT/getter及消费者，未逐项采集连续普攻时间戳；训练靶子精确30秒逐帧退场、射程边缘摆位、全部Tooltip同状态截图未逐项采样。
- 取消/失败退款、后合体工人独立收益、金矿高等级暴击并发、安居切换目标与不同击杀单位组合等次要条件，已离线覆盖但未全部重复实机量化。
- 临时原生挑战建筑注册使用明确事件注入；后续正式召唤、原生死亡、五类各双奖及第六次正常奖励实际执行，配额5→0。

真正融合塔后领取防御工事也已通过：[实际结果](../../output/rogue_full_selftest_20261011/final_native_full_map_console.txt)。

## 禁用跳过

| 卡ID | 当前正式停用原因 |
| --- | --- |
| `far_sighted` | 需要定义与已领取排除及效果失败的原子事务 |
| `goblin_duplicator` | 项目没有地精复制器道具与目标选择流程 |
| `lucky_watch` | 原文未明确哪些技能属于相关技能 |
| `burst_potion` | 兴奋剂效果未在来源中定义 |

实机为单人Tools隔离测试，测试辅助不接正常init；探针不主动写线上存档或调用支付。已保留正常业务逻辑和历史审计。

验收后已退出测试对局并重新加载普通地图：测试卡牌为空，测试场景未加载，波次冻结关闭。原有 Hammer 助手已恢复运行，目前正常等待开始加载；检查证据保存在 `output/rogue_full_selftest_20261011/final_clean_map_check_console.txt`。
