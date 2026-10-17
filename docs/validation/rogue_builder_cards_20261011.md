# 开局肉鸽卡牌效果核对（2026-10-11）

> **当前结果：** [48张启用卡的最新实际Dota自测](rogue_card_native_selftest_20261011.md)及[机器结果](../../validation/20261011/rogue_card_native_selftest.json)。本文件保留早期审计记录；其中“尚未游戏内验证”等历史状态以最新报告为准。

本记录核对启用的 `builder_start` 卡牌 20 张；`long_range_volley`（远距齐射）由本轮射程修复另行验证。权威配置为 `data/csv/肉鸽奖励系统/` 的 cards、effects、effect_params，运行时读取对应 generated Lua。已对照数值、目标归属、事件、实际属性/资源消费、已有与新单位、有效期；下面明确区分离线执行与代码链路审查，未做 Dota 引擎内完整逐卡实测。

20 张卡的数值参数与配置描述一致。确认并修复的差异是英雄攻速面板错误地把装备与科技攻速相乘、欢呼增减未刷新英雄快照，以及全能淬炼文案把实际全属性 +3 写成攻击属性 +3。壁垒续航、锐利速射和夯大力的文案也已明确现有回血、按命中成长、概率与收益叠加规则。锐利速射的攻速通过专用融合塔服务补接终极塔，卡面保持“你的防御塔”；命中成长保留原有触发规则。其他卡未发现确定的消费链中断。

## 逐卡结果

表中的 `builder` 指 `scripts/vscripts/systems/rogue_builder_start_effect_service.lua`。持久效果没有配置秒数到期；选择/重复领取控制仍由奖励服务与运行时的 `unique_card`/grant 幂等机制负责。资源卡以持卡玩家 ID 发起请求，实际资源服务写入该玩家账本，不向所有同队玩家各发一份。

| 卡牌 | 描述与参数 | 实际消费、范围与时间 | 结论与证据 |
| --- | --- | --- | --- |
| 壁垒续航 `wall_recovery` | 每秒恢复 20 生命；每 60 秒 1 护甲 | builder:118 的每秒任务寻找本人的存活城墙，`Heal` 当前生命且不超过最大生命；城墙存在时累计 60 个 tick 后向科技增加 1 点 War3 护甲。科技 `1/3` 内部换算由 building_upgrade_system 转回 War3；后续重建墙仍读取持久科技护甲。没有最大生命成长。 | **离线执行通过；文案已明确回血。** 实测 980/1000 到 1000/1000，60 tick 后护甲增加 1。effects 的备注原本即为“恢复生命”；CSV 和 generated cards 同步为“每秒恢复20生命”。 |
| 富甲天下 `wealthy_start` | 每波 `30 × 波数` 金币 | builder:69、154 订阅正式/dev/提前最终波开始事件；本人的 `last_paid_wave` 防止同一波重复支付，领取后的下一次波开始才支付。 | **离线执行通过。** 第 3 波支付 90，重复开始事件不重发。没有领取瞬间追补过去波次的实现。 |
| 锐利速射 `sharp_volley` | 你的防御塔攻速 +20%；每次攻击命中攻击力 +1，连续射击/穿透分别计数 | builder:160 将攻速写入科技，building_upgrade_system 的建造及科技事件重算本人普通/转职箭塔的真实 BAT；`rogue_ultimate_tower_effect_service` 补接终极塔，使用融合固定基础攻速与最新科技重算真实 BAT。builder:99 响应 `TOWER_ATTACK_LANDED`，对命中塔自己的 `modifier_rogue_sharp_volley_growth` 增加 +1 原生 PREATTACK_BONUS_DAMAGE；此成长也覆盖终极融合塔。机枪的真实结算命中和燃烧巨箭命中也发出该事件。 | **已补终极塔攻速消费者；文案已明确按命中成长。** 机枪子命中、穿透箭的多个受害者分别成长。领取前/后创建的普通、转职与终极塔均读取科技攻速；个人成长不被科技重算覆盖。保留原有触发规则，未改为可取消的攻击前摇事件。 |
| 伐木狂袭 `lumberjack_assault` | 伐木工攻速 +25% | builder:169 → technology_stat_manager rogue lumberjack → worker_system:483 的真实 `SetBaseAttackTime`，同类攻速百分点相加。科技变更刷新已有普通/合体工人，新训练/合成也执行刷新。 | **消费链审查通过。** 无时长到期；不依赖描述/UI 数值。 |
| 坚甲固守 `fortified_defense` | 城墙生命 +5000、护甲 +5、减伤 10% | builder:176 存储持久城墙生命 flat 与减伤；随后科技护甲事件使 building_upgrade_system 重算实际最大生命与 War3 护甲。damage_filter_service 对本人城墙的实际伤害应用 10% 减免。已有墙保留生命比例；新/重建墙读取同一持久 flat 与科技值。 | **消费链审查通过。** 最大生命实际增加 5000；残血墙的当前生命按原比例重算，文案没有承诺瞬间恢复 5000 当前生命。 |
| 基建狂魔 `infrastructure_maniac_start` | 基地升级木材消耗返还 | builder:185 设置标志；building_upgrade_system:812 的主城升级完成回调返还最终实际 `cost.wood`。开始失败/中途取消由已有退款路径处理，成功退款才走卡牌分支。 | **消费链审查通过。** 作用于主城，不作用于墙、塔、农场；先支付、成功后返还，不免除升级前的资源门槛。 |
| 精研伐木 `precision_lumber` | 伐木效率 +1 | builder:189 → 科技 wood_per_hit_bonus → worker_system:483 将真实伐木 AI 效率改值；modifier_lumberjack_ai:295 的 TREE_HIT 携带它，tree_system 最终结算木材。已有/新工人都读取科技。 | **消费链审查通过。** 普通工人每击 +1；合体工人依项目已有科技继承规则乘 fusion_count。未发现仅改面板不入账的问题。 |
| 安居乐业 `peaceful_labor` | 城墙未被攻击时伐木效率 +2 | builder:195 → tree_system:239；每次 TREE_HIT 查询本人的墙以及当前活着的波次/挑战怪攻击目标，未有怪以墙为攻击目标时加 2；检查按帧缓存，下一帧重新取目标。 | **离线执行通过。** 基础 10 实际支付 12；怪当前目标切为墙后支付 10。条件是当前攻击目标，不是“最近几秒没有受伤”的冷却窗口；没有配置等待时间。 |
| 伐骨积薪 `woodcutting_bounty` | 击杀怪物 `5 × 当前波数` 木材 | builder:85、201 订阅真实 ENGINE_ENTITY_KILLED；仅波次怪/挑战怪，按击杀者所有者玩家 ID 读取数值，当前波从 WAVE_STATE 取出，再请求真实资源增加。 | **离线执行通过。** 第 3 波每杀支付 15；另一玩家的击杀不享有此人的卡。召唤物/塔能通过 ownership 归属于持卡玩家。 |
| 瞬采木料 `instant_wood` | 立即 `100 × 难度` 木材 | builder:207 解析 difficulty_id 尾部整数后调用 RESOURCE_ADD_REQUEST；instant_transaction 执行后完成，后续难度改变不重算。 | **离线执行通过。** n3 实际请求 +300。 |
| 淘金秘法 `gold_mining_secret` | 采矿效率 +10% | builder:213 → 科技 gold_mine.income_bonus_pct；gold_mine_system:55、483 在每次真实产出时读取最新科技，最终金额累积小数、向下取整支付。已有和后建金矿都读取持久值。 | **消费链审查通过。** 与其他采矿百分比相加；分数结转避免低产出时 +10% 长期丢失。 |
| 英雄降临 `hero_descent` | 开局免费建造英雄祭坛 | builder:219 登记一次额度；building_cost_quote:5 报价金币/木材归零；builder progression、building_system 的主城门槛分支同步放行。建造成功才消费额度；召唤 eligibility 认可已完成的早期祭坛。 | **已有离线回归通过。** 无主城/无资金也能建造，玩家隔离、唯一数量限制和消费后的正常门槛/价格均被验证。 |
| 聚拢扩容 `population_expansion` | 立即人口上限 +5 | builder:223 → RESOURCE_ADD_REQUEST.max_population；resource_system.handle_add 加到玩家的真实上限。instant_transaction，不是普通人口占用增加。 | **离线执行通过。** 请求入账 +5 最大人口。 |
| 自然馈赠 `natures_gift` | 每秒木材 +3 | builder:229 使用每秒任务；scheduler.every 首次安排在一秒后，每 tick 请求 +3；active instance 归属检查避免替换后旧任务继续；remove 取消该任务。 | **离线执行通过。** interval=1、每 tick +3、取消后任务移除。没有短期到期参数。 |
| 紧急加固 `emergency_reinforcement` | 生命 ≤30% 时减伤 20% | builder:234 存储 threshold=30/reduction=20；damage_filter_service 按本人的墙，在本次伤害前读取 `GetHealth()/GetMaxHealth() <= 0.30`，实际伤害乘剩余减伤比例。 | **消费链审查通过。** 边界含等号；与坚甲及永久减伤按项目减伤百分点规则相加。穿过 30% 的那一击若击前高于门槛，不提前获得减伤。 |
| 疾风战法 `wind_strategy` | 英雄攻速 +400%；间隔减少 0.03 秒 | builder:242 → 科技 hero；hero_combat_stat_service 从配置 BAT 减 0.03，modifier_weapon_stat_projection 提供原生 +400 IAS。已拥有英雄接收科技事件，尚未召唤/重召英雄在生成时读取科技。 | **修复后真实配置/原生 getter 回归通过。** 空装备频率为 `5/(基础BAT-0.03)`；装备/科技 IAS 相加，欢呼百分比再乘。面板 cadence 与 getter 组合后的真实频率一致。 |
| 全能淬炼 `allround_tempering` | 英雄攻速 +100%；全属性 +3 | builder:249 → 科技 hero attack_speed_bonus_pct / all_attributes_flat → 英雄战斗属性计算；真实原生 +100 IAS，逻辑力量/敏捷/智力各 +3，并进入项目的属性生命/攻击映射。 | **修正文案且回归通过。** 旧“攻击属性提高3”与 all_attributes_flat、effect 备注和既有测试不符；CSV 与唯一对应 generated cards 已定向同步为“全属性提高3”，行为保持。 |
| 夯大力 `heavy_hand` | 合体伐木工采木暴击率 +5 个百分点，暴击基础收益为双倍木材 | builder:256 → tree_system:244 检查 survival_super_lumberjack 标志；给本次已有暴击率增加 5 个百分点；RandomFloat < 概率时最终采木收益乘 `2 + 已有暴击收益加成`。普通工人不会得到该卡概率。 | **离线执行通过；文案已明确概率/收益叠加。** 4.99 触发、5 不触发；普通工人排除；已有科技 20% 时合为 25%。基础暴击收益 2 倍，叠加其他暴击收益后可高于 2 倍。 |
| 身先士卒 `first_to_strike` | 英雄攻击大树木材 +100% | builder:262 → tree_system:235，英雄 TREE_HIT 对完整基础采木效率（含树等级）乘 2 后结算；不是所有伤害事件发木材。每次读取持久状态，覆盖前/后召唤英雄。 | **离线执行通过。** 相同树与英雄条件实际入账为未领卡时的 2 倍；伐木工分支不读取该 bonus。 |
| 无限轮回 `endless_rebirth` | 英雄对转生 Boss 伤害 +50% | builder:268 → damage_filter_service 的最终伤害阶段；要求 attacker:IsRealHero() 且受害者 encounter_id 以 encounter_rebirth_ 开头，实际 multiplier ×1.5。持久玩家状态动态读取。 | **消费链审查通过。** 普通怪/Boss、塔和非英雄召唤物不匹配；英雄直接造成的技能与普通攻击均匹配，不只展示面板。 |

## 锐利速射事件与终极融合塔范围

当前 `core/events.lua` 只定义 TOWER_ATTACK_START 与 TOWER_ATTACK_LANDED，没有表示“实际发射一次”的总线事件。`modifier_tower_attack_effects:OnAttackStart` 在攻击前摇开始时发 START；前摇仍可能取消。`OnAttack` 才代表原生攻击发射，还存在防空 secondary attack 和技能替代攻击；燃烧巨箭当前由 START 的技能服务发射。因而不能把成长订阅简单换为 START 就宣称每次实际发射只增加一次。

锐利速射的配置参数本来就是 `attack_per_hit=1`。保持已有规则、只将按命中与多次命中边界显性写入卡牌，避免未经确认改变机枪和穿透路线的成长速度。如果未来决定改为每次主攻击发射一次成长，应增加独立提交攻击事件，区分主攻击与副攻击、处理取消前摇/技能替代攻击，并回归一次机枪攻击、多目标穿透、防空副攻击、未命中以及取消攻击。

命中成长保存的是逻辑攻击点数。本轮同时修正 `modifier_rogue_sharp_volley_growth` 的原生 getter，按塔当前 `survival_endless_attack_scale` 换算；scale10 时一击 +1 返回 0.1，连续两击返回 0.2，scale20 时同一已存成长返回 0.1。普通塔与终极融合塔的真实领取/命中事件链均通过回归，其他玩家命中不获得该成长。

20 张卡中，锐利速射直接投影塔属性；伐骨积薪通过任意归属于持卡玩家的击杀者（含终极融合塔）支付资源。其余卡目标为城墙、资源、伐木工、主城/祭坛/金矿或英雄，不给终极塔直接的攻速/射程/攻击加成。

| 条件 | 终极融合塔当前实际行为 | 证据与处理建议 |
| --- | --- | --- |
| 锐利速射 +20% 攻速 | 已补接终极融合塔。新融合塔读取已有科技，领取卡牌导致的科技变化刷新已有融合塔，按固定基础攻速重算 BAT。 | `rogue_ultimate_tower_effect_service.initialize/refresh/init` 独立订阅科技与融合事件；不修改终极塔业务身份，不继承材料塔的攻速从而重复叠加。描述明确“你的防御塔”。 |
| 锐利速射逐命中 +1 | 作用于终极融合塔自身。融合塔挂同一 tower attack modifier、发 TOWER_ATTACK_LANDED；builder 回调按所有者读取状态，没有过滤掉 ultimate。 | builder:99-115；tower_fusion_service:255 挂 modifier_tower_attack_effects。描述中的成长对象明确为“你的防御塔”。 |
| 融合前材料塔的既有攻击加成 | 融合时读取每座材料塔的真实 GetAverageTrueAttackDamage，将 actual-base 的非负差值一次性加入 fused_base_attack；包括已经累积的命中成长。 | tower_fusion_service:213-219、543-544。融合继承的是攻击快照，不能随后盲目再加一次全局 flat，否则可能重复计算材料塔已带入的加成。 |
| 融合后的科技/卡牌攻速、攻击与射程变化 | 通用 arrow_tower 分支保留，终极塔通过专用服务接入攻速/射程；攻击类肉鸽卡以融合已烘焙快照为基线接入增量，个人成长仍走融合原路径。远距齐射由本轮主修另行核对。 | `rogue_ultimate_tower_effect_service` 与独立 Modifier，`tower_fusion_service` 的初始化和个人成长/英雄路径；保持 `survival_ultimate_tower` 身份，避免把已带入的材料收益再次整体加一遍。 |

## 修复与验证

`hero_combat_stat_service.lua` 的攻速频率、cadence 百分比与真实间隔统一为原生 modifier 属性组合：

```text
IAS = 100 + 装备攻速百分点 + 科技/肉鸽/存档攻速百分点
最终频率 = IAS / 100 × (1 + 欢呼百分比 / 100) / 减少后的基础间隔
```

原来的英雄面板把装备与科技相乘。例如疾风战法、全能淬炼与 +100% 攻速装备并存时，原生为 700% 基础攻速，旧面板显示为 1200%。修复前 `tools/test_hero_rogue_projection.lua` 在装备叠加场景实测失败：面板 `8.5801838610827` 次/秒，预期/原生 `5.0051072522983` 次/秒。

欢呼来自 `modifier_lumberjack_cheer` 的 ATTACKSPEED_PERCENTAGE；不是 IAS 常量。已有 worker 事件 `UNIT_COMBAT_STATS_CHANGED(reason=lumberjack_cheer_changed)` 现在触发对应当前英雄的快照重算。只接收该 reason 和相同 unit，避免通用战斗刷新事件递归重算。固定攻击频率调试 modifier 继续拥有最终间隔，cadence 同样读取其真实间隔。

使用 `C:/Program Files/lua/bin/lua5.1.exe` 实际执行均通过：

- `tools/test_hero_rogue_projection.lua`：真实 grant/config、早/晚召唤、6 英雄、两卡叠加、装备/永久奖励 IAS 加法、真实欢呼 getter 乘法及增减事件、native cadence、客户端 callback、重召、幂等与稳定刷新。
- `tools/test_rogue_builder_resource_harvest.lua`：真实配置、builder handler、事件总线、科技聚合与树资源结算；验证表中 9 张资源/采木卡，含付款/概率边界、归属和取消任务。资源入账边界使用引擎替身，此测试不声明引擎帧时序完全等同实机。
- `tools/test_addspeed_snapshot.lua`：固定攻击频率更新/移除、callback 顺序、重召和稳定读取。
- `tools/test_hero_display_bonus.lua`：英雄固定属性、科技与永久奖励的展示投影。
- `tools/test_free_altar_runtime.lua`：免费祭坛的实际可用性、零报价与消费后的门槛。
- `tools/test_rogue_boss_combat.lua`：锐利速射真实配置领取、普通/终极塔逐命中逻辑成长、攻击缩放变更与玩家隔离。

生成仅使用既有配置构建器的 `rogue_reward_cards.csv` 单文件入口，并执行 `tools/build_rogue_reward_configs.ps1 -CheckOnly` 确认权威 CSV 与生成 Lua 一致，没有运行全仓生成器。其余资源/战斗卡的代码链路核对不等于实机测量；如继续在 Dota 内验证，优先检查墙 30% 边界、残血领取坚甲、合体继承、带装备与欢呼的英雄实际攻击间隔，以及金矿多次小数结转。
