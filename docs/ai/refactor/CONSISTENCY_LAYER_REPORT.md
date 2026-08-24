# Consistency Layer Report

Last Verified: 2026-08-25
Scope: `docs/ai/` only

## Modified AI Documents

- 新增 `AI_CONSTITUTION.md`，集中定义 AI 的推理流程、Prompt 独立性、现有系统优先、冲突处理、CTO Mode 和决策边界。
- 新增 `ENGINEERING_STANDARD.md`，集中定义命名、API、数据库、属性、日志、错误、测试、文档和修改纪律。
- `AI_CTO.md` 改为极短兼容入口，不再维护第二套规则。
- `START_HERE.md` 的默认 Context 从 `AI_CTO.md` 切换为 `AI_CONSTITUTION.md`。
- `CURRENT_TASK.md` 的协作规则改为软 Owner，并统一使用 `TASK COLLISION WARNING`。
- `active/README.md` 补充多人协作、文件碰撞检查和人工裁决规则。
- `tasks/TASK-001.md` 将未登记文件规则改为“先登记、检查冲突、由人确认”，不再把 Owner 当作权限系统。

## Merged Responsibilities

原 `AI_CTO.md` 中的通用行为规范拆分合并到两个职责明确的新文件：

- “AI 如何思考”进入 `AI_CONSTITUTION.md`。
- “AI 应写出什么样的代码、接口、数据库和文档”进入 `ENGINEERING_STANDARD.md`。
- 项目事实没有复制到 Constitution 或 Standard，继续由 `PROJECT_CONTEXT.md`、Registry、Integration 文档和当前代码提供。

## Documents Not Modified

- 未修改 `PROJECT_CONTEXT.md` 的项目事实、架构边界或 CSV 权威源。
- 未修改 `DECISIONS.md` 的长期架构决策。
- 未修改 `KNOWN_ISSUES.md` 的问题状态和验证结论。
- 未修改 Feature / Integration / Troubleshooting 文档、Registry 内容、Session Log 或 Archive 内容。
- 未修改任何 Lua、Python、SQL、CSV、生成文件、Panorama、Content 资源或数据库。

## Rule Conflict Found

发现并处理一处规则冲突：旧 `CURRENT_TASK.md` 将“Owner 不同”和文件未登记解释为 AI 应直接拒绝或停止；安装指令要求 Owner 只是软归属，其他成员可以协作，发现潜在冲突时输出 `TASK COLLISION WARNING`，由人决定。当前入口已采用新规则。历史 Archive 保留原规则，不作为当前规范读取。

未发现 Constitution 与 Engineering Standard 之间的职责冲突。`AI_CTO.md` 现在只做兼容跳转，不再与新文件重复维护规则。

## Default Context

新任务默认读取：

1. `START_HERE.md`
2. `AI_CONSTITUTION.md`
3. `PROJECT_CONTEXT.md`
4. `CURRENT_TASK.md`

完成领域识别后，只读取最小相关的 Task、Registry、Integration、Troubleshooting 或 ADR。默认不读取 `SESSION_LOG.md`、`archive/`、所有 Integration 或所有 Registry。

## Validation

- 核心入口、新规范、兼容入口和报告已复读确认。
- `active/README.md` 的协作规则已复读确认，并与 `CURRENT_TASK.md` 一致。
- 相关引用路径检查通过；不存在的 `TASK-xxx` 和 `active/alice.md` 等仅为规则示例。
- 本次文档限定范围 `git diff --check` 通过。
- 本次新增/修改 AI 文档严格 UTF-8 检查通过。
- 未运行 Lua、Python、Workshop Tools、Supabase 或生产验证，因为本任务不修改业务实现。

## Business Code Boundary

本次没有修改业务代码、数据库、API、RPC、配置、生成结果或玩法规则。工作区中其他已有未提交修改未被覆盖、回滚或清理。

完成本报告后停止，不继续开发功能。