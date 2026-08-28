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
- LAN 双机已由用户确认联机、独立 PlayerID 和操作同步成功。Player 1 Builder 缺失已定位为 `template_map` 缺少四个 Builder Marker：Player 0 依赖旧坐标回退，Player 1 按 CSV 失败关闭并暴露地下 Undying 占位锚点。地图现已新增 `player_0_builder_spawn..player_3_builder_spawn`、完成 DMX 往返并以 `191 compiled, 0 failed` 重建 VPK；setup 权威 CSV 已由用户调为 60 秒，血条 Modifier 也补齐无效 parent 方法保护。下一可靠检查点是双机冷启动确认双方真实 `BUILDER_READY`、仅控制各自 `npc_survival_builder_proxy`，且不再出现 `modifier_single_health_bar IsAlive` 错误。

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