# 肉鸽奖励系统接入经验

> 本文记录 2026-08-17 已落地的肉鸽奖励数据、服务端运行时、Panorama UI 和调试入口。它是后续新增卡牌与效果时的恢复入口；当前状态仍是自动验证通过、Workshop Tools 实机验收未完成。

## 权威数据与生成链

- 卡牌、效果、参数和生命周期分别维护在 `data/csv` 下的 `rogue_reward_cards.csv`、`rogue_reward_effects.csv`、`rogue_reward_effect_params.csv` 和 `rogue_reward_effect_lifecycle.csv`。卡牌名称、说明、图标、启用状态、抽取规则和业务数值不得在 Lua 或 Panorama 中维护第二份。
- `tools/build_configs.py`负责四表唯一键、外键、枚举、强类型参数、必需参数、启用状态和生命周期完整性校验，并生成 `scripts/vscripts/config/generated` 下的运行配置。生成文件禁止手改。
- CSV 只能声明注册表允许的 effect、event 和 predicate 身份，不接受自由 Lua 表达式。新增机制时先扩展明确的 Lua handler/注册表和生成器契约，再通过 CSV 引用。
- 当前数据规模为 31 张卡、31 个效果、38 个强类型参数和 21 条生命周期规则。只有 `fiscal_subsidy`、`radiant_sapling`、`fortifications` 已启用并具有业务 handler；其余卡可展示但不可宣称效果已完成。

## 服务端会话与效果边界

- 正式 offer 按玩家隔离，包含递增 token、当前三卡、一次免费重抽、已领取集合和待处理奖励队列。只有成功领取才永久排除卡牌；仅展示或被重抽替换的卡未来仍可出现。
- 每次重抽或替换当前 offer 都必须产生新 token。选择与重抽请求必须同时校验玩家、当前会话、token 和 card ID；旧 token、重复请求和跨玩家请求不得产生效果。
- 效果运行时使用稳定的 `grant_id`，并以 `effect_instance_id`、`phase_instance_id`、`target_binding_id`管理幂等、阶段和目标绑定。玩家归属、限时到期、事件计数、下一匹配事件、动态 binding 和多阶段转换都由服务端维护。
- 资源效果复用既有资源事务；塔属性效果进入 `technology_stat_manager` 的独立 rogue 永久层，并沿 `TECHNOLOGY_STATS_CHANGED` 刷新现有塔。新效果应复用对应业务服务，不能直接从奖励服务旁路修改实体或客户端状态。
- 正式 Boss 奖励由权威 `meta.is_boss` 死亡事件触发，并遍历 `player_context_service.active_player_ids()`为所有有效 Radiant 在局玩家分别创建或排队。奖励归属不依赖最后一击者。
- Builder 开局奖励是一次性业务入口：成功创建或排队后才消费，并立即同步权威 Builder 布局。调试 offer 不得消费该入口，也不得清空正式 Boss/Builder 队列。

## Panorama UI 接入

- Content 权威源位于 `content/dota_addons/survival/panorama/{layout,scripts,styles}/custom_game/rogue_reward_ui.*`，由 `custom_ui_manifest.xml`作为独立 Hud 元素加载。不要手改 Game 目录中的 `.vxml_c/.vjs_c/.vcss_c` 编译产物。
- UI 按本地 `PlayerID` 订阅 Custom Net Table `survival_rogue_reward`，只渲染服务端发布的卡牌顺序、名称、说明、图标、token 和剩余重抽次数。Lua table 到 Panorama 后可能是数字键对象，渲染前必须按数字键排序，不能依赖 JavaScript 对象枚举顺序。
- 卡牌选择发送 `ui_rogue_reward_select { token, card_id }`，重抽发送 `ui_rogue_reward_reroll { token }`。Panorama 只发送意图和表现动画，不决定抽卡、领取、幂等或效果成功。
- 当前界面是独立 overlay：整卡点击领取、Dota Ability 图标、窄高牌面、悬停反馈、翻牌和错峰入场；视觉只借鉴交互节奏，不包含第三方代码或素材。
- 服务端运行时失败时保持界面并返回失败提示，不能由客户端假定领取成功后自行关闭。未启用卡被调试展示后点击失败关闭属于当前预期。

## 指定三卡调试入口

- 聊天命令：`rogue <card_id1> <card_id2> <card_id3>`；推荐基线为 `rogue fiscal_subsidy radiant_sapling fortifications`。
- 三个 ID 必须存在且互不重复。输入顺序就是 UI 顺序；调试 offer 禁用重抽，并允许已领取卡重复测试。
- 参数不足、重复 ID 或未知 ID 必须失败且保留当前 offer。合法调试请求只替换屏幕上的当前会话并使旧 token 失效，不清空正式奖励队列，不消费 Builder 一次性奖励。
- 调试选择仍走正式选择校验、稳定 `grant_id` 和通用效果运行时。不得为作弊命令增加直接发资源、直接写属性或跳过生命周期的旁路。

## 新卡接入顺序

1. 在四张权威 CSV 中补齐卡牌、效果、参数和生命周期；引用已有 enum/handler，无法准确映射的卡保持 `enabled=0`。
2. 运行生成器契约和 `--check-only`，确认唯一键、外键、参数类型、必需参数及生命周期闭合。
3. 需要新机制时，在运行时注册表实现最小 handler，并为 grant 幂等、玩家隔离、目标绑定、事件推进和清理增加 Lua 5.1 行为测试。
4. 用 `rogue` 命令按固定顺序反复验证卡牌。先测失败输入和旧 token，再测实际业务效果；不能把“卡牌能显示”当作“效果已接入”。
5. 强制编译变更的 Panorama 资源，并执行 Workshop Tools 冷启动。自动测试、Lua 语法和 Resource Compiler 成功都不等于引擎实机验收。

## 当前验证边界

- 已通过：四表契约、100 个生成配置模块加载、Lua 5.1 奖励服务与通用运行时回归、聊天作弊测试、目标 Lua 语法、Python 静态编译、严格 UTF-8、Panorama 资源编译和限定 `git diff --check`。
- 未执行：Workshop Tools 冷启动下的 UI 实际布局与动画、开局技能消费、Boss 触发、连续队列、资源到账、塔攻速刷新，以及双客户端分别获得同次 Boss 奖励。
- 后续报告必须明确区分静态契约、模拟/单元测试、语法检查、资源编译和引擎实机结果。