# AI Session Recovery — Start Here

> **这是所有新会话的唯一恢复入口。** 不要仅凭聊天记忆继续工作，也不要先通读整个仓库。

## 当前活跃任务

- 任务：为固定 52×52 技能行增加运行时锚点校准器，让用户在 Workshop Tools 中直接比较九宫格锚点并微调 X/Y。
- 当前阶段：事件驱动选中切换、无闪过渡和带版本迁移的正式布局预设均已完成自动验证；等待 Workshop Tools 实机验收。
- 最新实机证据：单技能与多技能图标大小相同、地面 Tooltip 成功；但以官方 `abilities` 容器左上角定位后，技能整体超出原范围，因此左上角方案已被实机否定。
- 本轮边界：只修复重新 Run 后回退到 `top_left / 0 / 0` 的状态问题；不改变 52×52 cell、4px 间距、九宫格公式、视觉顺序、原子接管、v5 选择事件、技能输入或 Tooltip。

## 最后可靠检查点

- 日期：2026-07-29
- 已确认：最终技能行位置集中由 `measureFixedRowGeometry()` 和 `row.style.position` 应用，现有 0.5 秒刷新可直接消费运行时校准状态，无需改服务端或技能输入链。
- 已完成：正式 `middle_left / X=5 / Y=35` 预设、旧状态版本迁移，以及选中/查询单位事件即时刷新、0.10 秒轻量实体哨兵和 `0/0.016/0.05/0.10/0.20s` 有界无闪重试；版本为 `grid52_preset_v6`。
- 已排除：当前异常不是动态几何公式随机失效，而是完全重新 Run 后运行时校准状态丢失并回到源码默认 `top_left / 0 / 0`；暂不需要 Panorama Debugger。
- 自动验证：`ARROW_TOWER_COMPLETION_PASS`；`.cline_tmp/preset_v6_all_tests.txt` 末尾为 `ALL_LUA_TESTS total=32 failed=0`；`hud_takeover.js` 强制编译为 `1 compiled, 0 failed, 0 skipped`。
- 用户正式批准参数：`middle_left / X=5 / Y=35`；启动默认值和重置必须共用该基线，并通过预设版本迁移旧 HUD 状态。
- 尚未确认：正确预设下 1、3、5、7 技能的实机位置，以及切换响应速度与 Valve 原技能图标是否完全不再闪现。
- 下一步唯一动作：完全停止 Workshop Tools 后重新 Run，确认首条校准日志为 `build=grid52_preset_v6 preset_version=1 source=preset_default ... alignment=middle_left offset_x=5 offset_y=35`，再验收 1、3、5、7 技能。

## 新会话恢复顺序

必须按以下顺序读取：

1. `docs/ai/START_HERE.md` — 判断当前阶段和唯一下一步。
2. `docs/ai/CURRENT_TASK.md` — 恢复用户要求、验收标准、证据和待确认事项。
3. `docs/ai/SESSION_LOG.md` — 从末尾向前读取最近检查点；需要研究脉络时再继续向前。
4. `docs/ai/DECISIONS.md` — 恢复不可随意推翻的架构与行为决策。
5. `docs/ai/KNOWN_ISSUES.md` — 恢复环境陷阱、风险和禁止操作。
6. `docs/ai/PROJECT_CONTEXT.md` — 需要项目全局背景时读取。
7. 仅当当前任务引用历史工作时，再读取 `docs/ai/archive/` 中对应归档。

读取后必须先向用户复述以下四项，再执行任何修改：

- 我恢复出的当前任务。
- 最后一个可靠检查点。
- 尚未确认的内容。
- 下一步准备做什么。

若文件之间冲突，以 `START_HERE.md` 的当前阶段和 `CURRENT_TASK.md` 的用户原始需求为恢复依据，同时把冲突写入 `SESSION_LOG.md`，不得静默猜测。

## 强制检查点协议

在以下任一时刻，必须先更新文档再继续：

1. 用户新增或改变需求后。
2. 完成一轮关键代码/配置调查后。
3. 排除一个重要方案后。
4. 做出架构、数据语义或兼容性决定后。
5. 准备进行大范围编辑、生成、编译或测试前。
6. 工具异常、终端超时、需要用户实机验证或准备结束会话时。

每次检查点至少记录：

- 用户最新原话或准确摘要。
- 新确认事实及证据文件。
- 推断与事实的明确区分。
- 已排除方案及原因。
- 尚未验证的事项。
- 下一步唯一或最小动作。

## 文件职责

- `START_HERE.md`：只保存当前状态、恢复顺序和唯一下一步；保持简短。
- `CURRENT_TASK.md`：只保存一个活跃任务；任务结束后整体归档并新建。
- `SESSION_LOG.md`：追加式研究日志；旧检查点不覆盖、不改写结论历史。
- `DECISIONS.md`：已确认且后续必须遵守的长期决策。
- `KNOWN_ISSUES.md`：仍存在的风险与已解决但需防回归的问题。
- `PROJECT_CONTEXT.md`：稳定项目背景、目录和工具链。
- `archive/`：完成或被替换任务的历史全文，不作为默认当前上下文。

## 用户可使用的恢复提示词

新会话中只需发送：

> 读取 `docs/ai/START_HERE.md`，严格按其中顺序恢复。先复述当前任务、最后检查点、未知项和下一步；不要凭记忆或猜测继续。