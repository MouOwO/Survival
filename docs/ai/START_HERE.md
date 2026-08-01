# AI Session Recovery — Start Here

> **这是所有新会话的唯一恢复入口。** 不要仅凭聊天记忆继续工作，也不要先通读整个仓库。

## 当前活跃任务

- 公共技能 `proto_magic_slingshot` 五级“魔法弹弓”已完成配置、运行时、Tooltip、碎石区和目标选择修复，当前等待投射物命中回调与后续等级效果实机验收。
- 实机已确认主攻击命中后的10%判定正常，单目标可成功得到 `range=3000 selected=1 launched=1`；5是最多目标数，不是触发所需人数。

## 最后可靠检查点

- 日期：2026-08-01
- 魔法弹弓曾因召唤英雄 `GetAttackRange()` 返回0而在概率成功后得到 `reason=no_targets`；现已使用运行时缓存、`Script_GetAttackRange`、`GetAttackRange`和英雄CSV配置多级回退，并始终保留本次合法命中的敌方主目标。
- 实机证据：`[MAGIC_SLINGSHOT_ROLL] ... success=true` 后已出现 `[MAGIC_SLINGSHOT_LAUNCHED] ... range=3000 selected=1 launched=1`，证明概率、射程回退、单目标选择及投射物创建成功。
- 尚未在最新日志中看到 `[MAGIC_SLINGSHOT_HIT]`，因此不得声称投射物命中回调、伤害和眩晕已经实机验证。
- `MAGIC_SLINGSHOT_TARGETS_LUA51_PASS`、魔法弹弓/奥术弹幕/寒冰锥/addskill契约、相关Lua 5.1语法、严格UTF-8和`git diff --check`均通过。
- 下一步唯一动作：继续实机观察同一发射后的 `[MAGIC_SLINGSHOT_HIT]`；确认后再逐级验收LV2优先级、LV3旧眩晕增伤及LV5碎石区。

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