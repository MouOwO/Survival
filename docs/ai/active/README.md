# Active Context

Status: FACT

当前知识库不按人员维护上下文。

- 任务归属、状态和依赖统一记录在 `../CURRENT_TASK.md`。
- 单项任务详情记录在 `../tasks/TASK-xxx.md`。
- 多人协作记录在 Task 文件的 Owner、Collaborators、Affected Files 和 Handoff Notes 中。
- 不创建 `active/alice.md`、`active/bob.md` 或其他人员专属文件，避免同一项目事实分叉。

## Collaboration Rules

- `Owner` 是当前主要推进责任，不是权限系统；其他成员可以 Review、Debug、修复、提出改动或接手。
- 修改 `IN_PROGRESS` Task 前检查 Affected Files、Git status、当前 diff、Task progress 和其他进行中任务的文件冲突。
- 可能产生冲突时输出 `TASK COLLISION WARNING`，说明冲突范围并交由人决定；不得自动覆盖或回滚他人修改。
- 依赖门禁仍以 `CURRENT_TASK.md` 和对应 Task 文件为准；Owner 软归属不等于可以跳过依赖或测试门禁。