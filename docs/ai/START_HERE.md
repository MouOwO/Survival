# AI Session Recovery - Start Here

Last Verified: 2026-08-26

## Project

SurvivalContent 是 Dota 2 Arcade 生存塔防项目，包含英雄成长、防御塔、工人、波次、挑战和永久玩家数据。

## Current Phase

**Backend Integration Phase**

当前已验证的本地 Workshop 主链：

```text
Dota server Lua -> 127.0.0.1 Python API -> HTTPS Supabase RPC/PostgreSQL
```

- Python 当前实现是 `ThreadingHTTPServer + FishingApplication + SupabaseRpcClient`，不是 FastAPI。
- Panorama 不直接访问 HTTP；Lua 不直接访问 SQL；Python 是唯一数据库入口。
- `data/csv/` 是业务配置权威源，`scripts/vscripts/config/generated/` 是生成结果。
- 正常发布 Arcade 的 Game Server/Lua 主机与 loopback 归属尚未证实，当前是 `MODEL-D`；详见 `architecture/MULTIPLAYER_TOPOLOGY_REPORT.md`。

## Current Priority

P0 是 Player Session、在线 checkpoint 和终局 finalization 的稳定联调。

当前任务注册表见 `CURRENT_TASK.md`，Sprint 门禁见 `CURRENT_SPRINT.md`。

## Current Blockers

- `TASK-001` 已于 2026-08-25 按用户确认完成：已完工城墙毁坏能够产生单次 `final=true`，并由 Python API/Supabase 成功记录最终在线时间。
- `TASK-002` 与 `TASK-003` 不再因 `TASK-001` 的城墙 final 验收而阻塞。
- Dota 终局后的 `session_closed` 本地 callback 未作为本次服务端持久化验收阻断项，保留为非阻断观测事项。
- 生产双玩家端到端验收仍是独立后续工作，不等同于 `TASK-001` 本次城墙毁坏范围。
- 生产 Session Foundation 在发布 Lobby 拓扑实验完成前暂停；不得假定 Lobby Owner 就是 Game Server 或 Python 主机。
- LAN 直连已出现“地图可加载但无英雄/Builder且快速断联”；生产入口已补充 setup 前全连接玩家分队、连接字段兼容和结构化诊断，但尚未完成 Workshop 双机验收。下一可靠检查点是 Hidden/Friends Only 大厅中两名玩家启动前进入好人方，并确认 `status`、PlayerID、`hero_ready` 和 `BUILDER_READY`。

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