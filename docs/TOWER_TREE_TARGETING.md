# 防御塔排除资源树

## 问题与处理

资源树 `enemy_tree` 是敌方基础单位，会进入引擎的自动索敌和范围查询。
原来只有普通塔初始化时关闭原生索敌，升级与科技刷新又会开启；终极塔也没有安装自定义选敌 modifier。
激光等效果在最终伤害过滤之前创建，因此只拦伤害仍会看到塔向树木发射光束。

- 初建、升级、科技与永久属性刷新统一设置实际攻击距离，同时保持原生索敌距离为 0。
- 普通塔、路线塔和终极塔使用 `modifier_tower_auto_attack`，排除资源树，保留敌人优先、训练木桩兜底与防空规则。
- 旧塔恢复时补齐选敌 modifier；已存在的树木攻击会停止并重新选敌。
- 激光、连锁闪电、分裂箭、冰霜范围、穿透弹与延迟攻击在特效、伤害、事件、计数、奖励之前排除树木。
- 激光读取实际攻击距离并保留原有 96 单位的目标边缘容差，不使用已关闭的索敌距离。
- 伐木权限仍限真实英雄普通攻击与伐木工；塔、建筑和纯视觉载体不因使用英雄模型获得权限。

不调整怪物、训练木桩、树木血量、资源收益或后端存档格式。

## 回归测试

从 addon 根目录用 Lua 5.1+ 逐个执行：

```text
scripts/vscripts/tests/test_tower_idle_state.lua
scripts/vscripts/tests/test_tower_target_selection.lua
scripts/vscripts/tests/test_tree_attacker_whitelist.lua
scripts/vscripts/tests/test_ultimate_tower_tree_targeting.lua
scripts/vscripts/tests/test_tower_skill_tree_exclusion.lua
scripts/vscripts/tests/test_tower_upgrade_targeting.lua
```

邻接回归：`test_tree_health_projection.lua`、`test_wall_quick_upgrade.lua`、`test_startup_order_gate.lua`。

## 游戏内验收

Lua 业务模块会缓存，完整生效请重新开一局，无需重启 ECS 或迁移数据库。

1. 树旁建普通塔，并依次升级、转路线、刷新科技：只有树时保持待机。
2. 范围内加入普通敌人或训练木桩：正常开火；怪物优先于木桩。
3. 激光不连接树木；分裂箭、连锁闪电和范围技能不会选择树木或因树触发奖励。
4. 融合终极塔重复上述检查；手动点树也不能攻击。
5. 英雄与伐木工仍能正常砍树、取得木材。

本地回归使用实际业务模块和模拟的引擎接口，不能替代游戏内视觉验收。

## 2026-09-23：没有合法目标时禁止起手动画

用户实机反馈：树木已不受塔伤害，但塔仍出现攻击动作。仅将索敌半径设成 0、在 `OnAttackStart` 再 `Stop()` 属于起手后的拦截，不能作为待机保证。

- 普通塔和终极塔的 KV 初始 `AttackAcquisitionRange` 设为 0，避免 modifier 安装前沿用 1000 的原生索敌。
- 选敌 modifier 同时关闭 `SetIdleAcquire(false)` 与索敌半径。前者在本机 Valve `hero_demo/scripts/vscripts/events.lua` 中也与零半径配合使用。
- modifier 默认处于 idle：通过同步到客户端的 stack=0 返回 `DISARMED` 和 `GetDisableAutoAttack()=1`，在引擎起手前禁止攻击。
- 选到合法目标后，先设 stack=1 并刷新状态，再提交强制攻击；禁自动攻击属性返回 0。此时不返回 `DISARMED=false`，保留其他来源的缴械效果。
- 目标死亡时立即进入 idle，不等待 0.25 秒轮询；目标离开射程、失去防空资格或升级重置时也收回攻击权限。
- 进入 idle 时停止旧攻击并淡出攻击手势。稳定待机和持续攻击同一目标不会反复 Stop、重置姿态或重复下单。

树仍使用原有阵营。更换为中立不能代替显式排除规则，而且会改变英雄原生索敌的条件。英雄和伐木工的伐木流程、权限与收益均保留。

本轮通过六项回归：待机状态、目标选择、技能/原生模型手势排树、升级、终极塔、伐木权限。待机测试验证攻击命令下达前已经解锁、目标死亡立即禁攻，以及客户端读取相同待机状态。

实机控制台端口存在，但只读 Lua 探针未返回数据；**本轮尚未验证实际动画**。完整生效需重开测试局以加载 KV 和 Lua。重点验看树旁只有塔时无抬手、怪物死亡后回到 idle、普通怪到来仍正常连续攻击。

2026-09-22 验证：上述五项回归及三项邻接回归通过。
实机控制台能响应，但该时刻 `GameRules` 和开局加载模块均不存在，故没有创建测试实体，实战及视觉验收仍未验证。

## 2026-09-23 补充：恢复合法目标攻击，失败转职只提示

### 箭塔已经选到怪物，却没有开始攻击

`SetForceAttackTarget` 留下的强制目标记录不代表引擎已经执行攻击。原生自动索敌关闭后，如果攻击命令被清除，脚本仍记着同一目标，就可能一直不再下单。

- 选敌 modifier 现在同时检查实际 `GetAttackTarget()`。同一合法目标连续 1 秒仍未开始攻击时，重新设置强制目标，并用 `MoveToTargetToAttack` 恢复攻击命令。
- 已正常攻击同一目标时不重复下单；恢复前继续检查目标存活、射程、防空规则与资源树排除。
- 脚本发出的攻击命令会再次经过订单过滤。新增发单保护，防止过滤器回调递归，或把自动目标错误登记成玩家手动锁定目标。
- 继续保持索敌半径为 0、`SetIdleAcquire(false)`；只有树或没有合法目标时仍以 stack=0 返回缴械状态，保留原有待机与伐木权限规则。

### 转职条件不满足时刷新模型和技能栏

原转职路径在完整校验费用之前预占路线名额，失败后再释放。预占和释放都会发布路线数量变化，进而触发技能同步与建筑快照；因此即使最终转职结果为失败，界面也已经收到中间状态更新。

- 新增只读 `TOWER_CLASS_CHECK_REQUEST`。转职报价先检查所有权、存活/施工状态、等级、现有路线、路线名额及费用；升级缓存缺失时使用只读状态恢复，不安装技能、修改模型或发布建筑变化。
- 资源系统新增只读 `RESOURCE_CAN_SPEND_REQUEST`，与实际扣费共用校验规则，保持木材、金币、人口、档案就绪、结算冻结和调试设置的语义一致。检查不扣费、不占人口、不发布资源变化。
- 前置校验通过后才预占名额并执行真实扣费；提交阶段仍重新校验，保留并发竞争、取消与退款处理。条件不足时只返回错误提示。
- UI 路由转职失败时不调用 `StartCooldown` 或 `EndCooldown`；仅成功且技能实体仍存在时启动冷却。原生技能也使用服务端 `CastFilterResult` 做相同只读校验，通过 `GetCustomCastError` 返回错误。玩家身份优先读取项目所有者 `survival_player_id`，再回退到 `GetPlayerOwnerID()`。
- 客户端现有 `ui_ability_cast_result` 已在失败时返回，不安排属性刷新；ScenePanel 也仅在模型标识改变时调用 `SetUnit`。因此本轮不修改客户端刷新链，修复服务端失败前产生的中间状态。

### 本轮验证与实机状态

在 addon 根目录运行以下 Lua 回归：

```sh
lua scripts/vscripts/tests/test_tower_idle_state.lua
lua scripts/vscripts/tests/test_tower_target_selection.lua
lua scripts/vscripts/tests/test_tree_attacker_whitelist.lua
lua scripts/vscripts/tests/test_ultimate_tower_tree_targeting.lua
lua scripts/vscripts/tests/test_tower_skill_tree_exclusion.lua
lua scripts/vscripts/tests/test_tower_upgrade_targeting.lua
lua scripts/vscripts/tests/test_tower_class_preflight.lua
```

上述本地回归已通过。新增覆盖攻击命令丢失/Stop 后恢复、真实订单过滤回流、转职热缓存/冷缓存失败零副作用、真实资源与路线限额、UI 冷却及原生施法过滤，以及合法提交、竞争、完成和取消。另以小型 mock 验证项目所有者有效而引擎 owner=-1 时仍能通过原生检查，项目字段缺失时正确回退。

2026-09-23 16:18 的 Workshop 隔离实测使用真实 `building_arrow_tower`、普通怪和 `enemy_tree`，没有直接施加伤害或由测试端发攻击命令：怪物两次观测到 40 点掉血，树木血量不变，攻击树木事件为 0；移除怪物后 stack=0、缴械、实际攻击目标为空。4.3 秒结束，临时实体剩余句柄为 0。该轮 Stop 后立即读取的目标仍非空，因此不能据此声称已在实机复现并恢复“引擎目标为空但脚本仍缓存目标”的情形；这一分支由真实 modifier + 订单过滤器回归覆盖。

进一步的 `manual_tower_attack_recovery.lua` 现在要求实际观测到目标清空及缓存保留，才继续验收恢复；该增强版后续控制台请求未收到响应，尚未取得实机结果。转职失败零事件、零技能/模型同步及零冷却已通过实际业务模块的回归，但 ScenePanel 与技能栏的游戏内目视验收尚未完成。重开测试局即可载入 Lua 修改，无需重启 ECS 或迁移数据库。
