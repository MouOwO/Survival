# 2026-10-31 商业、存档和英雄服务耦合审查

范围：Lua服务端/商业/账号投影及其事件边界。UI场景与头像由同轮另一份审查负责。本轮只读整理证据，没有把下述风险当成已证明的当前游廊掉帧原因，没有大规模重构业务。

## 结论与证据等级

现有工程已经有有效边界：权威支付和存档结算在后端、永久效果不重复写回存档、战斗读标量库存、事件回调快照缓存、英雄重算after_dispatch合并、部分事件changed_section过滤、换局generation与旧回包失效检查。继续保留这些边界。

剩余主要问题是**共享事件负载仍较宽、多个投影阶段靠调用顺序组合、同一费用/权益出现平行入口、运行服务与发布配置分属多个版本面**。已有四个商品边界直接展示了这种职责分散的功能后果；稳定调用计数另证明有重复提交和重复派生。实际耗时/FPS仍需原生采样。

静态盘点扫描当前开发Lua（排除tests/debug/fixtures）：810模块、12,608,654字节、2278条内部字面require边、332处显式字面subscribe；[完整盘点](architecture_coupling_review_20261031.public.json)。这是包含lazy require的潜在依赖图，动态构造/列表循环订阅不完整，注释示例也需人工甄别；不等于810个模块都在一帧执行。

## 可复现的运行调用计数

使用**冻结3102实际commerce_runtime和permanent_reward_effect_service函数**，仅替换引擎、玩家、scheduler和传输边界。不是自己重写一个等价算法。

[计数回执与原始合成轨迹](commerce_feature_audit_20261031.counters.json)绑定六份冻结模块SHA256和三个审计脚本SHA256，未包含真人数据。

| 场景 | 输入批次 | 直接owned查询 | worker容量查询 | 英雄bus请求 | 模拟NetTable桥提交 / 内容相同提交 |
| --- | --- | --- | --- | --- | --- |
| 开局无英雄/墙，1人，无商城权益 | 60个1秒tick | 660 | 60 | 60 | 60 / 59 |
| 同上，4人 | 60个1秒tick | 2640 | 240 | 240 | 240 / 236 |
| 英雄/墙就绪，1人，无商城权益 | 60个1秒tick | 780 | 60 | 60 | 60 / 59 |
| 同上，4人 | 60个1秒tick | 3120 | 240 | 240 | 240 / 236 |

worker helper内部的额外1~2次标量持有查询没有重复计入上表。这里实际native/network调用均为0；模拟的是Lua调用边界次数。真实引擎可能合并相同NetTable数据，不能把提交数当网络包数或帧率损失。

owned是本地标量权益读取，不是HTTP或数据库查询；生产已有窄库存读接口，不能把这些次数误写成同次数的整档复制。身份校验可能涉及的原生调用未由这个mock计数测量。

60次属性/库存完全相同的合成profile事件：`get_profile`60次、`commerce_effects.project`60次、库存标量查询6420次（每次扫98项抽奖定义及少量持有条件），最终只输出1次PERMANENT_REWARD_EFFECTS_CHANGED。说明已有same_values输出去重，但成本是在完整派生之后。真实在线checkpoint默认约60秒一次，也可能有登录/购买/领取等更新，**不能把本实验60次事件写成线上每秒60次**。

复现：

```powershell
& 'C:/Program Files/lua/bin/lua5.1.exe' tools/commerce_feature_audit_20261031/count_commerce_stable_calls.lua 'D:/Survival_发布候选/20261031_ws4_shop_recovery_v01_view'
& 'C:/Program Files/lua/bin/lua5.1.exe' tools/commerce_feature_audit_20261031/count_projection_refresh.lua 'D:/Survival_发布候选/20261031_ws4_shop_recovery_v01_view'
```

## 需要后续处理的职责与热路径

| 项目 | 真实源码证据 | 当前成本/影响 | 适合的边界 |
| --- | --- | --- | --- |
| R01 商业稳定tick重复提交 | commerce_runtime.tick / publish每秒遍历活跃玩家，无条件SetTableValue；同轮计数见上 | 时间O(P)，P上限4；稳定状态仍每秒P次桥提交和11~13P个直接权益读 | 持有变化、次数消耗、英雄/墙重建、冷却完成时标脏；每玩家小动作快照有版本/值比较；冷却用一次完成任务；保留世界/主体销毁失效 |
| R02 profile事件驱动整档复制和全投影 | player_profile_service.get_profile:987递归copy；permanent_reward_effect_service.refresh先重建所有来源，same_values:182后才早退；commerce_effects.project每次扫全部抽奖定义 | profile大小S、道具L下每次O(S+L+来源条目)，相同属性也重做；登录/领取/在线时长共用profile事件 | 在账号边界发布不可变的小型游戏投影和真实变化域；库存/永久属性/在线时间等分别有版本。战斗继续用标量API，UI账户完整档单独读；按当前账号/会话/generation失效，不能按player_id永久缓存 |
| R03 每秒成长仍遍历全局建筑集合 | permanent_reward_effect_service.apply_tower_tick:270、apply_wall_tick:428；building_upgrade_system.on_technology_stats_changed:716，塔攻击分支:723、通用墙分支:755均pairs(buildings)再筛主人/类型 | 若P名玩家都有每秒塔/墙成长，约O(P×B)检查，更新仅K座本方塔/墙；当前已排除英雄和工人不相关事件，但相关1Hz路径仍扫全局 | 建owner→type→entindex索引，创建/销毁/换局维护；增长只更新K项。原生写仍是必要O(K)，稳定无成长为O(1)，别只减少SetBaseDamage却保留每次全局过滤 |
| R04 商业服务同时编排多个玩法域 | commerce_runtime包含传送、清怪、科技、工人、粒子、轨道炮和终极塔；当前字面依赖14项 | 每增商品容易跨hero/worker/building/research/native入口改多处；D闪旁路是已经发生的平行入口差异 | 商业只判定/发布只读权益；英雄移动、建造、工人等各自执行，所有入口调用同一领域命令和同一权益读；不是让商业模块取得所有实体控制权 |
| R05 永久效果组合靠手工顺序 | permanent_reward_effect_service.refresh中commerce来源→commerce_effects→lottery_dynamic→monthly→Boss；longinus在commerce_effects内部提前结算 | 抽奖财宝/村正的动态持有来源落在5%增强之后，F05已用真实模块复现 | 统一分层：静态持久来源→全部持有条件来源→明确的持久乘区→局内成长；来源有标识和分类，乘区明确定义范围，重复刷新幂等；不要把月卡/Boss/装备全部粗暴放入同一乘区 |
| R06 同一概念拆成多个状态和报价 | 每击属性分在hero_progression与permanent_reward两个池（F03）；训练室入场检查/真实spend各算费用（F04）；10转发点只在progression请求里检查（F02） | 功能在正常顺序可用，但晚购买、来源叠加或折后边界遗漏 | 统一成长口径/只读费用quote；权益变化单独触发领域reconcile并有同局已授予回执。命令和UI共用quote，展示不代替服务端复核 |
| R07 共享事件同步传播 | event_bus.emit:92按该事件快照同步pcall每个handler；显式profile订阅15处、permanent订阅9处、hero progression订阅8处（不含循环注册） | 调用栈累计处理各消费者；有些同逻辑分别收到profile/permanent/equipment事件；顺序来自订阅容器，不能把先后当合同 | payload给变化域/实体集合/版本；投影提交后发一次事实事件；必要同栈一致性由after_dispatch按owner合并，异步UI可预算化，但不得延后权威扣费/伤害校验 |
| R08 code、目录与运行渠道多版本 | 本次线上Workshop3102、archive d573、现金目录644782…、开发新CSV各独立；普通券SKU已写但现役现金无项，129钱包行改名/文案未发布 | “源码有”不能证明在售包/库已接入；商城恢复与头像历史也说明冻结包需要实际下载校验 | 发布清单同时固定runtime签名、archive合同、现金目录、数据库迁移和功能开关；每层独立验收并写真实版本。商品级能力矩阵可阻止半套宣称上线 |
| R09 测试配置与商业隔离耦合 | mode_unlock_test.reset把all_difficulties_unlocked锁到本局；HTTP/archive/cash均参照该隔离，3101商城/福利事故已真实复现 | 一个看似难度配置的值可使整个商业写路径不发生；热切不能恢复旧测试收益 | 新项目用明确运行渠道/持久化模式合同和签名前断言；保持测试收益隔离与同局锁定，避免用普通玩法开关暗含线上写权限 |

R03实际集合规模/耗时尚未原生测得。复杂度是直接由循环和事件频率确定的上界，不能把它转换成“减少多少毫秒/FPS增加多少”。R01/R02模拟调用数是确定实验结果，原生影响需要对应采样。

## 已有措施与需要保留的约束

- [event_bus](../../scripts/vscripts/core/event_bus.lua) 已按事件缓存handler快照；稳定emit不重建整个订阅集合，实际执行H个消费者为O(H)。generation和after_dispatch在重入/换局时保护旧回调。不要用延时定时器随意替换同栈一致性。
- [hero_combat_stat_service](../../scripts/vscripts/systems/hero_combat_stat_service.lua) 的queue_recalculation/flush_recalculation按玩家、实体及generation合并成长重算，读取战斗快照时按需flush；COMBAT_DAMAGE_RESOLVED只保留最后一次伤害，已经避免每击全量统计发布。
- [player_profile_service](../../scripts/vscripts/systems/player_profile_service.lua) 有库存标量、每日额度小投影、账号/会话绑定、异步generation和高水位检查；完整copy是保护不可变边界，改进方向是增加窄接口/版本域，不是把可变存档引用暴露给战斗。
- resource、worker、gold_mine、building等已有changed_section早退；production_ui也避免普通每击/收入更新重画研究项。保留这些收益，进一步收窄事件而不是恢复无条件全刷新。
- commerce_runtime与titan_aura已有持有/主人/世界归属、粒子销毁、旧监听撤销/委托处理。任何缓存或按域拆分仍须覆盖死亡、销毁、重建、重连和换局。

静态图只找到一组3节点lazy潜在环：multiplayer_player_service、online_time_service、startup_loading_service；它不是已证明的启动循环错误。新项目迁移启动/在线时长时应把会话状态读与加载通知抽成明确接口，避免只搬其中一个文件却隐式依赖整个原启动系统。

## 后续新项目复用边界

| 可复用单元 | 迁移时必须替换/注入 |
| --- | --- |
| 纯结算/投影：库存去重、叠加门槛、余额安全整数、月卡续期、声明式效果 | 新SKU/永久身份、货币、价格/效果CSV、模式投影、日切/额度合同；不要沿用旧账号或历史玩家数据 |
| 命令协议：稳定request_id、原子扣款授予、丢失回包恢复、重复提交去重 | 新后端应用/数据库/域名/签名和权限配置，实际迁移/回退验收；支付网关和回调是外部独立适配器 |
| event_bus、deadline_queue、scheduler及generation模式 | 新世界生命周期、单调耗时预算/引擎think、模块init所有权；不要复制旧诊断任务或假定每个M.init可任意重复 |
| 商业权益只读接口、领域quote/reconcile的设计 | 新英雄/建造者/地图区域/技能入口/资源池。侏儒D案例说明搬商城按钮不会自动覆盖原生技能 |
| 发布完整性/双仓源编译资源对应、签名/官方回调验证原则 | 新项目目录、Workshop条目、允许账号、密钥、签名序号、资源策略及后端合同；历史授权和旧测试证据不迁移 |

建议实施顺序：先按实机采样命中的服务定向维护owner/type索引与提交去重；再处理已复现的F02~F05功能边界；后续在明确数据/版本合同下拆分投影和命令职责。大规模模块数量减少本身不是性能验收指标。

## 审计工具自身成本

scan_coupling单次按源码字节扫描、构建O(V+E)图，再做一次Tarjan O(V+E)；引用行号通过预构建换行索引二分，O((E+S)log L)。空间O(V+E+S)，V=810、E=2278、S=332。只在显式审查运行，正常游戏稳定/变化时新增成本均为0。

调用计数脚本是60次有界合成批处理，P为1或4，不读取场景、玩家档案或云端；没有游戏运行时timer，没有新增原生桥或网络调用。它们用于区分复杂度和重复提交，不能代替实机帧率记录。
