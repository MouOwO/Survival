# Boss 行动、资源卡逐卡核对（2026-10-11）

> **当前结果：** [48张启用卡的最新实际Dota自测](rogue_card_native_selftest_20261011.md)及[机器结果](../../validation/20261011/rogue_card_native_selftest.json)。本文件保留早期审计记录；其中“尚未游戏内验证”等历史状态以最新报告为准。

按 `rogue_reward_cards.csv` 的启用状态逐一追踪卡牌 → effects → params → registry → 实际资源、升级、道具、训练和奖励消费者。此表覆盖 10 张 Boss 行动、资源卡；战斗和开局卡由同轮其他审计记录覆盖。

| 卡牌 | 描述对应的实际生效路径与参数 | 核对结果 |
| --- | --- | --- |
| 神许愿 `divine_wish` | `grant_random_cards` → `ROGUE_REWARD_GRANT_RANDOM_REQUEST`；数量 3，同 Boss 池按权重无放回抽取，排除自身、已领取和禁用卡；子卡使用稳定 `parent_grant_id:child:index:card_id`，成功子卡记录领取状态和历史。 | 修复部分子卡成功后能改选／刷新白拿效果：保留原页面和父领取 ID，部分成功后只允许重试同张神许愿。原已成功子卡不重复发放。正常候选不足 3 张时不提供神许愿；调试强制选卡仍安全报不足，不生成虚假历史。 |
| 命令更换 `command_change` | `next_hero_reroll_count` → 当前玩家 `next_rogue_reroll_count:boss += 1` → `create_offer` 首次创建下一个 Boss 选卡页面时 `take_numeric` 一次性消费。重新刷新页面沿用余次，不再次取额度。 | 行为符合当前描述“下一次肉鸽选择多 1 次刷新”；无英雄技能刷新消费路径。下一页已排队时，创建该页再消费。 |
| 基建狂魔 `infrastructure_maniac` | `random_building_upgrade_count`，次数 3；每次从本玩家存活、建造完成、不在升级中的建筑重新读取权威升级报价。免费请求免金币、木材，升级仍按正常建筑规则占用人口。基础 LV5 待转职塔、前置未满足／满级建筑报价失败不参与。 | 修复遗漏金矿本体：金矿分派至专用报价／升级请求，补 `gold_mine_upgraded` 完成原因。成功完成后才扣次数；取消／销毁不扣次数，重选其余候选；等本次事件所有消费者更新完后开始下一次。候选耗尽正常结束。 |
| 璀璨树苗 `radiant_sapling` | `grant_current_wood_pct` → `RESOURCE_GET_REQUEST` 读本玩家木材 → `floor(wood × 20 / 100)` → `RESOURCE_ADD_REQUEST` 加本玩家木材。 | 数量、向下取整、玩家钱包范围符合描述；CSV `team_resource` 标签不会令资源广播，实际账户按 `player_id` 查找。 |
| 财政补贴 `fiscal_subsidy` | `grant_gold_flat` → `RESOURCE_ADD_REQUEST`，`gold=10000, wood=0, player_id=持卡玩家`。 | 数量和钱包范围符合描述；成功领取 ID 幂等，不会给其他同队玩家。 |
| 核弹 `nuclear_bomb` | 发 `item_survival_rogue_nuclear_bomb` 给注册建造者；一次性使用锁，使用时快照当前存活敌方正式波次／挑战怪，按 4 个／0.05 秒分批 `ForceKill`，不包含以后新刷出的怪。 | 修复将非 Boss `wave_leader` 精英误判为 Boss 的保护条件；正式 `survival_is_boss`、Boss role／modifier 继续保护。同队／无怪物身份单位不误杀，最后一次性移除道具；背包满则领取失败，可空出背包重试。 |
| 赏金密令 `bounty_order` | `challenge_reward_multiplier` 登记本玩家 5 次；`building_challenge_service.on_entity_killed` 在建筑挑战成功、原奖励成功且非重复事务时，以相同 profile 和挑战波数再请求一份奖励；复制奖励成功后扣 1 次。 | 当前配置 multiplier=2，对应一份原奖励 + 一份副本。限定挑战建筑的 5 类挑战，超时／城墙失败、英雄挑战不消费；复制有独立事务 ID 去重；次数归挑战拥有者，其他玩家击杀不改变持卡者归属。 |
| 建造密令 `construction_order` | 给建造者 1 充能 `item_survival_rogue_building_upgrade`；使用前、请求时核对建造者身份、目标玩家归属、建筑存活和已建成；共用权威报价，金矿走专用升级服务。 | 任意实际可升级己方建筑免费升 1 级；请求失败保留道具并结束冷却；请求成功后消费一次，金币木材免费、正常人口规则仍适用。已开始升级后目标销毁不返还道具，符合配置“请求成功后消费”。 |
| 实习证明 `internship_certificate` | `training_capacity_flat` → 本玩家 `repairer_training_capacity_flat:train_repairer_01 += 2`；真实训练与技能面板消费者据此把初级上限 5 变为 7，高级仍为 2。 | 修复上限统计把同队其他玩家修理工混入：现在只计持卡玩家存活修理工，含无 training_id 的默认面板入口。领取不生成工人、不花资源；多出的 2 个名额训练仍正常消耗各 100 木材、1 人口；死亡后可补员。历史总训练计数不参与当前容量判定。 |
| 基建外包 `infrastructure_outsourcing` | `building_count_gold` → 本玩家 `BUILDING_LIST_REQUEST` 的存活已建成建筑数 × 波次状态 `difficulty_id` 中 N1–N5 的数值 × 100 → 本玩家钱包。 | 难度 1–5 的乘数符合描述；建造中的、已销毁的和其他玩家建筑不在权威列表内；领取时一次结算，不动态重算。 |

## 全表接入完整性

- 当前 48 张启用卡均有启用 effect 和真实 registry handler，无重复启用 effect_id／同 effect 下重复 param_name；启用 effect 的生命周期 predicate 均已注册。
- `hero_descent` 和开局版 `infrastructure_maniac_start` 没有独立 params，分别使用一次祭坛建造额度和真实主城升级消费后的返木，不构成漏接。
- `far_sighted`、`goblin_duplicator`、`lucky_watch`、`burst_potion` 的卡牌和 effect 都为禁用，普通抽取不可能提供；遗留参数／规则不等于已启用功能。
- 通用 runtime 的 `activate` 在领取时调用 handler；持续功能也可由真实领域服务直接订阅事件。不能仅凭某卡只有 `grant_applied` 规则认定没生效。本轮已由战斗审计补齐火药溅射／炮塔串联的建筑投影事件。
- 核弹的道具状态、赏金密令的领域次数由实际消费者管理；runtime 中残留 active／counter 外观不等于道具或奖励会再发。本轮未为纯诊断外观重构计数。
- 个别 effects `notes` 保留乱码或过期描述（例如训练靶子的旧“建造者位置”），不参与玩家展示和执行；玩家展示取 cards.description，本表以实际运行路径核对。

## 回归验证

使用 `C:/Program Files/lua/bin/lua5.1.exe` 执行真实生产 Lua 模块；Dota 原生对象由测试 fixture 提供。

- `scripts/vscripts/tests/test_infrastructure_maniac.lua`：真实 registry + runtime + lifecycle，金矿专用路径、串行成功 3 次、其他玩家完成不消费、候选耗尽、建造中排除、取消／销毁后继续。
- `tools/test_divine_wish_history.lua`：真实卡表、registry、runtime、选卡／历史服务；3 张效果、图标／描述、玩家隔离、幂等重试、部分成功后禁止改选与刷新、正常候选不足过滤；全部通过。
- `scripts/vscripts/tests/test_rogue_item_rewards.lua`：道具实际使用代码，建造者、背包、归属、升级失败保留、金矿、非 Boss 精英杀死、正式 Boss 保留、分批／单次消费；通过。
- `scripts/vscripts/tests/test_gold_mine_reward_upgrade.lua`：真实金矿消费者，免费升级、所有权／忙碌／死亡拒绝、正常升级费用、完成事件原因；通过。
- `scripts/vscripts/tests/test_lumberjack_training_queue_integration.lua`：真实工人系统和训练流程，额外验证同队两玩家分别可训练 5 个修理工、持卡玩家单独变 7、正常资源／人口消费、初级与高级隔离、死亡补员；通过。
- 原 `test_rogue_offer_effect_flag.lua`、`test_rogue_reward_history.lua` 保持通过；新增流程没有改变页面刷新是否需要重算已生效效果的语义。
- `node tools/test_rogue_reward_ui.js` 和 `node tools/tests/escape_choice_windows.test.cjs`：两份真实肉鸽 UI 的部分神许愿状态下，只开放同卡重试、禁止其他卡／重抽，关闭再打开仍可继续；通过。
- 修改的生产 Lua 经 `luac5.1.exe -p` 解析通过；`git diff --check` 无空白错误。

## 究极融合塔与“所有防御塔”接入

真实融合入口保留 `survival_ultimate_tower=true`、`survival_building_id=nil`，继续使用独立数量、销毁、占地和攻击继承规则；没有把究极塔改成普通箭塔或套用普通升级初始化。新增 `rogue_ultimate_tower_effect_service` 在创建时初始化，在真正的 `TOWER_FUSION_RUNTIME_CHANGED/REMOVED` 中登记／移除，并按本玩家 `TECHNOLOGY_STATS_CHANGED` 刷新。

| 效果 | 究极塔实际行为 |
| --- | --- |
| 防御工事、锐利速射攻速 | 从配置固定 3 次／秒按 `final.tower.attack_speed_bonus_pct` 重算；两卡同时持有为 `3 × 1.26 = 3.78` 次／秒。素材攻速没有进入融合攻击快照，创建和后领都只应用一次；移动、重复事件、研究刷新不重新叠加。 |
| 攻击范围科技 | 从创建时原生攻击距离加当前 final 科技范围，调用统一 `tower_combat_rules.set_attack_range`，同步原生范围覆盖和 Lua 取值；仍关闭原生自动索敌。 |
| 斗志昂扬、炮塔串联 | 融合公式是 `CSV 基础攻击 × 3 + max(0, 素材当前攻击 − CSV 基础攻击)`，旧素材的加成已进入究极塔基础攻击。创建时记录已持有的百分比，新 modifier 只给当前百分比与创建百分比之差，避免旧加成再乘一次。新领取的卡对这座究极塔的继承攻击应用新增百分点；炮塔串联仍保留领取时快照。 |
| 步调一致 | 共享 `combat/rogue_hero_attack_projection.lua` 读取英雄当前原生真实攻击并恢复逻辑缩放，再转换为接收塔原生值；无原生 getter 时读逻辑攻击区间中点。融合时记录当时的一份投影，究极塔只应用当前投影减该基线；后领、英雄增长／消失都动态读取。素材当时的七份攻击贡献按原融合设计冻结继承，不追溯拆解，后续变化按新增的一座究极塔计算。 |
| 铁拳 | 战斗过滤器以究极塔标记判断防御塔攻击资格，不依赖普通建筑 ID；原生攻击与替代攻击分别遵守已有伤害来源规则。 |
| 塔成长、锐利速射命中成长、英雄 R 继承 | 已烘焙的素材攻击继续保留；究极塔个人成长和英雄 R 的原有 base damage 更新路径继续工作，科技刷新只处理攻速／范围，不写回基础攻击。 |
| 新兵塔、火药溅射 | LV1–4 基础塔／穿透弩车阶段资格继续按具体塔判断；素材曾获得的攻击贡献由融合快照继承，不把限定阶段卡再次全量套到究极塔。 |

直接购买究极塔的 commerce 路径使用合成资料，没有真实素材攻击快照，因此基线为 0，已有斗志／串联／步调一致直接应用一次。真实路径测试同时暴露并修复其读取不存在的 `arrow_tower.levels[1]`：现在兼容真实配置的 `pre_class_levels`，不改变费用和建造数量规则。

新增 `scripts/vscripts/tests/test_ultimate_tower_rogue_effects.lua` 使用真实融合服务、卡牌 registry/runtime、科技管理器及 modifier getter，验证融合前后领取、混合先后顺序、7 素材攻击不重复、英雄逻辑／原生缩放、英雄消失、最终科技攻速／原生范围、同队玩家隔离、runtime 重复事件、移除后停止刷新、客户端 modifier 传输、个人攻击成长、英雄 R 继承与 commerce 初始化；全部通过。原 `test_ultimate_tower_tree_targeting.lua`、`test_tower_destruction_rebuild.lua`、`tools/test_hero_rogue_projection.lua` 和 `tools/test_rogue_boss_combat.lua` 保持通过，后者当前 100 项检查。新增生产 Lua 均通过 `luac5.1 -p`。

该记录为离线行为核对，未声称完成本次游戏客户端实机验收。
