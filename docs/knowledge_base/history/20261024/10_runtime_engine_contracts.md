# 10｜运行时与原生引擎契约

核对日期：2026-10-24。本模块只读审阅历史决策及当前开发源码，没有重跑测试、启动游戏或复验历史故障。以下“当前”指源码契约，不代表所有环境均已实机验收。路径相对 game 仓库；`core/`、`systems/` 均位于 `scripts/vscripts/`。

## 当前源码应保留的约束

1. **事件总线保留当前分发快照。** 回调中增删订阅只影响后续 emit；嵌套事件结束后，`after_dispatch(key, callback)` 合并同键投影，避免订阅顺序使界面读到半成品。reset 更换 generation，旧订阅不能误删新世界订阅，旧待办也不能继续运行。证据：`core/event_bus.lua`；测试：`tools/test_event_bus_after_dispatch.lua`、`test_event_bus_dispatch_cache.lua`。

2. **调度性能与重入语义一起维护。** 索引最小堆只取到期任务，取消／替换立即删除节点，不能采用积累残骸的延迟取消。同 ID 显式新任务优先于旧回调返回的重复间隔；clear 使正在执行的旧任务失效，init 每局重绑引擎 Think。证据：`core/scheduler.lua`、`deadline_queue.lua`；测试：`tools/test_deadline_scheduler.lua`、`test_scheduler_replacement.lua`。Tools 采样默认关闭，CPU统计不等于整帧耗时或实机帧率。

3. **modifier 绑定不能只依赖 require 成功。** Activate 获得 game-mode entity 后，先加载全部定义，验证最终 class，再统一 LinkLuaModifier；加载链可能替换 class table。ensure 复用已有实例，创建失败最多每5秒重试。证据：`core/modifier_registry.lua`、`addon_game_mode.lua`；测试：`scripts/vscripts/tests/test_modifier_registry.lua`。

4. **长期实体身份使用真实句柄与上下文。** 命中历史不能只按可复用的 entindex 保存；同时绑定 world、事件总线 generation 和任务 token。预算清扫不得误删同玩家的后继桶；reset 先撤销归属，再取消任务或调用原生清理，避免重入触碰新状态。证据：`core/target_history.lua`；测试：`tools/test_target_history.lua`。

5. **属性刷新与治疗分开处理。** 最大生命改变时，明确选择保持当前值或保持已损失血量；延迟保护只纠正异常补满，不应抵消正常恢复。主动治疗先调用 `allow_healing()`，使旧保护失效。证据：`core/hero_health_guard.lua` 的 `preserve_current/preserve_missing/allow_healing`。不要在新技能中再造一套延迟回写。

6. **肉鸽效果采用受限声明与分层身份。** CSV 只引用注册的 effect、event、predicate，不能执行自由 Lua。grant、effect instance、phase instance、target binding 分别处理幂等、阶段与目标；新机制先扩展 handler 和生成契约，再接配置，资源与属性效果仍走既有业务服务。证据：`systems/rogue_effect_runtime_service.lua`、`rogue_effect_registry.lua`、`rogue_event_registry.lua`、`rogue_predicate_registry.lua`。旧文档“仅3个 handler”不能作为当前数量。

7. **在线时长按会话检查点结算。** 历史事务契约规定首次、新会话及超租约间隔不累计。当前 Lua 分离 active/finalizing，断线只结算对应玩家；已有请求未完成则排队 final，回调校验代际，重连不能接收旧身份结果。证据：`systems/online_time_service.lua`、`tools/test_fishing_online_resume.lua`。历史 `game_end` 不可靠促成多终局入口，不等于所有退出路径已经验收。

8. **预载状态必须对应实际资源。** 正式出生、调试出生和预载共享模型解析；urgent 请求不能被后台批次阻塞，旧 session／回调必须可失效。`retire()` 是逻辑状态处理，不能冒充引擎卸载或解决资源从未加载。证据：`systems/asset_preload_service.lua`、`startup_asset_preload_service.lua`；测试：`scripts/vscripts/tests/test_startup_asset_preload_service.lua`。新增模型仍需冷启动检查。

维护这些模块时，保留三个容易遗漏的细节：事件订阅来自表遍历，不能依赖处理器的偶然先后次序完成业务事务；一个处理器异常被隔离，并不代表整条业务已经成功。调度器先收集本轮到期批次，回调中新加的零延迟任务不插入当前批次；固定0.05秒 Think 也不是逐帧承诺。目标历史的强引用必须随失效／到期清扫释放，不能为避免索引复用而无限留存实体。

生命保护的“保留已损失血量”表示最大生命增加多少，当前生命也增加相同量；不是保留旧血量百分比。旧延迟任务只在仍拥有该单位最新代际时生效，真实治疗必须主动撤销它。效果生命周期结束要同时处理到期任务、目标绑定与 handler 清理，不应只把界面卡牌隐藏。以上规则适合提取成新项目的基础设施契约，业务数值和模型资源则继续留在各自配置层。

## 历史经验与证据有效期

9. **原生故障保留首个失败层。** 历史粒子重复释放缺陷可模拟复现，但不能据此认定它是 particles.dll 崩溃的唯一原因。头像实验出现过“编译实体存在、运行时 ent_find 为0”，因此应停在实体加载层，不继续堆饰品。证据：`docs/ai/KNOWN_ISSUES.md` ISSUE-007/008、`docs/CRASH_20260926.md`。这些记录不证明今天仍复发，也不证明已修复。

10. **代码规则不等于配套云端已经生效。** 10月11日合作奖励决定共享成功事件的基础随机、逐真人独立命令，月卡与个人上限分别处理；终局先完成奖励交接再关闭入队。该记录仍明确代码完成、云端 bundle 发布待验收，本次未补做部署核对。证据：`docs/ai/DECISIONS.md`、`KNOWN_ISSUES.md` 的合作奖励条目，及 `systems/archive_cooperative_reward_service.lua`。

历史拓扑报告的 MODEL-D／本机8765、钓鱼文档的团队资源与全部奖励禁用、旧公共技能容量3及全局90怪，均不能当作当前状态。当前个人资源、个人怪物计数与技能容量见模块02；当前云服务与发布边界见04／06。恢复任务时先核源码、配置与新回执，再使用旧记录解释决策原因。
