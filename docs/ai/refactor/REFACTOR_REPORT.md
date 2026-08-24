# Refactor Report

Last Verified: 2026-08-25
Scope: `docs/ai/` knowledge base only

## Summary

完成一次低风险 AI 知识库重构，目标是把当前状态、稳定事实、任务索引、专题文档和历史证据分离，降低默认上下文 Token 消耗，避免把历史状态误读为当前状态。

本次没有修改业务代码、CSV、生成配置、SQL、Python、Lua 或 Panorama。

## Files Changed

核心常驻入口已重构：

- `docs/ai/START_HERE.md`：从 216 行压缩为 83 行，改为恢复入口和按需读取地图。
- `docs/ai/AI_CTO.md`：从 1089 行压缩为 98 行，保留 AI 工作规范、停止条件、来源优先级和验证等级。
- `docs/ai/PROJECT_CONTEXT.md`：从 653 行压缩为 89 行，只保留项目身份、稳定架构、边界和核心永久数据事实。
- `docs/ai/CURRENT_TASK.md`：从 268 行压缩为 86 行，只保留当前 Milestone、P0/P1 任务、阻塞和调度规则。
- `docs/ai/DECISIONS.md`：从 268 行压缩为 85 行，整理为 8 条架构决策摘要。
- `docs/ai/KNOWN_ISSUES.md`：从 257 行压缩为 101 行，只保留 6 个当前问题，并统一使用状态、优先级、症状、原因、临时方案、下一步和日期字段。

新增索引和协作辅助文件：

- `docs/ai/active/README.md`
- `docs/ai/registry/README.md`
- `docs/ai/registry/attribute_registry.md`
- `docs/ai/registry/api_registry.md`
- `docs/ai/registry/event_registry.md`
- `docs/ai/registry/database_registry.md`

## Files Moved

没有移动现有专题文件，避免产生大规模链接和内容变更。

原核心文件的完整副本已归档到：

- `docs/ai/archive/2026-08-25-pre-knowledge-refactor/START_HERE.md`
- `docs/ai/archive/2026-08-25-pre-knowledge-refactor/AI_CTO.md`
- `docs/ai/archive/2026-08-25-pre-knowledge-refactor/PROJECT_CONTEXT.md`
- `docs/ai/archive/2026-08-25-pre-knowledge-refactor/CURRENT_TASK.md`
- `docs/ai/archive/2026-08-25-pre-knowledge-refactor/DECISIONS.md`
- `docs/ai/archive/2026-08-25-pre-knowledge-refactor/KNOWN_ISSUES.md`

## Files Merged

没有合并 Feature 或 Troubleshooting 文档。现有专题文档内容相对独立，合并会增加事实丢失和引用回归风险。

## Files Archived

- 原 `CURRENT_TASK.md` 的完整任务和历史记录已经保留在既有 `docs/ai/archive/2026-08-24-pre-task-registry-current-task.md`。
- 本轮被压缩的 6 个核心文档完整保留在 `archive/2026-08-25-pre-knowledge-refactor/`。
- `SESSION_LOG.md`、既有 `archive/` 和专题文档保留原位置，继续作为按需历史/专题资料，不进入默认上下文。

## Duplicates Removed

- 从 `START_HERE.md` 移除长历史、详细测试清单和已解决事项，只保留当前阶段、阻塞点和读取路径。
- 从 `CURRENT_TASK.md` 移除历史实现、逐项测试日志和长背景，只保留任务索引。
- 从 `AI_CTO.md` 移除当前 Bug、当前数据库状态和具体功能实现，保留工作规则。
- 从 `PROJECT_CONTEXT.md` 移除每日变化的调试记录、旧任务和临时验证状态，保留稳定事实。
- 从 `DECISIONS.md` 移除重复实现细节，改为决策摘要并保留日期。
- 从 `KNOWN_ISSUES.md` 移除已解决/历史问题，旧内容通过归档可追溯。

没有删除历史知识，只将其从常驻入口移到归档或按需专题文件。

## Ambiguities Found

1. `@xxx` 是当前任务表中的原始 Owner 标识，不能安全推断为具体人员；保留原值并在任务规则中禁止 AI 自动接管。
2. `TASK-001` 的真实 Affected Files 尚未在 Task 文件中登记；当前标记为需要 Owner 交接。
3. `event_registry.md` 中部分事件的精确 payload 未从当前代码逐项确认，已标记 `UNKNOWN — verify in code`，没有自行补全。
4. 远端 Supabase migration 状态不能仅凭本地文档确认；`database_registry.md` 明确要求目标环境核对。

## Conflicts Found

1. 历史文档中存在不同日期、不同 checkpoint/lease 数值和不同 Workshop Tools 验证边界；本次未改写历史，只在当前核心文档采用最新恢复入口已确认的事实，并保留旧版本归档。
2. `AI_CTO.md` 原文包含 FastAPI 等目标目录描述，而当前实现是 `ThreadingHTTPServer + FishingApplication + SupabaseRpcClient`；当前核心文档已明确二者区别，原文保留在归档中。
3. `KNOWN_ISSUES.md` 历史文件包含已解决问题和当前问题混排；本次只将当前仍有证据的问题提取到新文件，其余保留原文归档。
4. 示例文本中的 `TASK-xxx`、`active/alice.md`、`active/bob.md` 不是实际路径，不作为失效链接处理。

未发现需要人工立即裁决、且会阻止本次知识库重构的冲突。上述动态事实在后续业务任务中仍须按 Source of Truth 顺序复核。

## Knowledge Not Modified

- 未修改 `PLAYER_PROFILE_INTEGRATION.md`、`FISHING_REWARD_INTEGRATION.md`、`ROGUE_REWARD_INTEGRATION.md`、`WAVE_MODEL_LOADING_TROUBLESHOOTING.md`、`WAVE_MODEL_RESOURCE_LIFECYCLE.md` 的正文。
- 未修改 `SESSION_LOG.md` 正文；其现有工作区差异来自本次重构之前。
- 未修改任何 `data/csv/` 权威数据或 `scripts/vscripts/config/generated/` 生成结果。
- 未修改 Lua、Python、SQL、Supabase migration、Panorama、Content 资源或测试业务实现。
- 未新增 API、数据库表、RPC、Session 规则、玩法数值或架构结论。

## Token Optimization

默认常驻读取由原来的多个超长文件收敛为：

1. `START_HERE.md`：83 行
2. `AI_CTO.md`：98 行
3. `PROJECT_CONTEXT.md`：89 行
4. `CURRENT_TASK.md`：86 行

合计约 356 行，且内容只覆盖恢复入口、工作规范、稳定项目事实和当前任务索引。原 216/1089/653/268 行内容均有完整归档。

专题内容改为按领域读取：

- Player Profile：Feature 文档 + API/Database Registry
- Session / Reward：`FISHING_REWARD_INTEGRATION.md` + Task + Registry
- Rogue：`ROGUE_REWARD_INTEGRATION.md`
- Wave Model：两个 Wave 文档
- 历史证据：仅按需读取 `SESSION_LOG.md` 或 `archive/`

## Validation

- `START_HERE.md`：83 行，符合 50~120 行目标。
- `CURRENT_TASK.md`：86 行，符合 50~150 行目标。
- 核心文档、Registry、active README 和归档文件已重新读取确认存在。
- 本次文档限定范围执行 `git diff --check`，未发现空白错误。
- 本机配置的 Python 3.14.3、PowerShell 7.6.5、Lua 5.1 和 `luac5.1` 路径均存在；本次没有业务 Lua 修改，因此不运行业务 Lua 测试。
- 未执行 Workshop Tools、Python 服务、Supabase 或生产联调；本任务不涉及业务运行验证。

## Recommended Next Step

知识库重构完成后停止本轮工作。下一次 AI 开始业务任务时：

1. 先读 `START_HERE.md`、`AI_CTO.md`、`PROJECT_CONTEXT.md`、`CURRENT_TASK.md`。
2. 识别 Domain，再只读对应 Task、Registry、Feature 或 Troubleshooting 文档。
3. 检查 Owner、Dependency、Affected Files 和 Git collision。
4. 以当前代码、migration/RPC、CSV 和最新验证记录为准，不从 Archive 恢复任务状态。
5. 按 Task Testing Matrix 工作，并准确区分 STATIC、UNIT、CONTRACT、SIMULATION、WORKSHOP 和 PRODUCTION。

本轮报告完成后不继续开发功能。