# AI Session Recovery - Start Here

Last Verified: 2026-08-25

## Project

SurvivalContent 是 Dota 2 Arcade 生存塔防项目，包含英雄成长、防御塔、工人、波次、挑战和永久玩家数据。

## Current Phase

**Backend Integration Phase**

当前主链：

```text
Dota server Lua -> 127.0.0.1 Python API -> HTTPS Supabase RPC/PostgreSQL
```

- Python 当前实现是 `ThreadingHTTPServer + FishingApplication + SupabaseRpcClient`，不是 FastAPI。
- Panorama 不直接访问 HTTP；Lua 不直接访问 SQL；Python 是唯一数据库入口。
- `data/csv/` 是业务配置权威源，`scripts/vscripts/config/generated/` 是生成结果。

## Current Priority

P0 是 Player Session、在线 checkpoint 和终局 finalization 的稳定联调。

当前任务注册表见 `CURRENT_TASK.md`，Sprint 门禁见 `CURRENT_SPRINT.md`。

## Current Blockers

- `TASK-001` 已登记为 `IN_PROGRESS`，Owner 为 `@xxx`，但 Owner 身份和 Affected Files 尚未完成交接确认。
- `TASK-002` 与 `TASK-003` 依赖 `TASK-001`，依赖完成前不得进入实现。
- 2026-08-24 的自动测试覆盖了终局多入口幂等；Workshop Tools 仍需确认 `wall_destroyed` / `POST_GAME` 能产生单次 `final=true` HTTP 200 和 `session_closed`。
- 生产双玩家端到端验收尚未完成。

## Minimum Required Context

新任务默认只读：

1. `START_HERE.md`
2. `AI_CONSTITUTION.md`
3. `PROJECT_CONTEXT.md`
4. `CURRENT_TASK.md`

然后识别领域，按需读取：

| Domain | Read |
| --- | --- |
| 当前 Sprint / Task | `CURRENT_SPRINT.md`、对应 `tasks/TASK-xxx.md` |
| 玩家档案 | `PLAYER_PROFILE_INTEGRATION.md`、`registry/api_registry.md`、`registry/database_registry.md` |
| Session / 在线奖励 | `FISHING_REWARD_INTEGRATION.md`、相关 Task、API/DB Registry |
| 肉鸽奖励 | `ROGUE_REWARD_INTEGRATION.md` |
| 波次模型 | `WAVE_MODEL_RESOURCE_LIFECYCLE.md`、`WAVE_MODEL_LOADING_TROUBLESHOOTING.md` |
| 未解决问题 | `KNOWN_ISSUES.md` |
| 长期决策 | `DECISIONS.md` |
| 历史证据 | 仅按需读取 `SESSION_LOG.md` 或 `archive/` |

## Context Selection Rule

```text
1. Identify Domain
2. Identify Relevant Files
3. Read Minimum Required Context
4. Check Task Owner / Dependency / File Collision
5. Implement and run the task Testing Matrix
```

不要默认读取 `SESSION_LOG.md` 全文或整个 `archive/`。

## Validation Language

- `STATIC`: 静态代码或文本检查
- `UNIT`: 单元测试
- `CONTRACT`: 跨层契约检查
- `SIMULATION`: Lua/Mock 模拟
- `WORKSHOP`: Dota Workshop Tools 实机
- `PRODUCTION`: 真实生产环境

自动测试通过不能写成 `WORKSHOP VERIFIED` 或 `PRODUCTION VERIFIED`。

## History

本次重构前的完整恢复入口保存在 `archive/2026-08-25-pre-knowledge-refactor/START_HERE.md`。