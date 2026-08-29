# Project Context

Status: FACT
Last Verified: 2026-08-25

## Project Identity

- SurvivalContent 是 Dota 2 Arcade 生存塔防项目。
- 主要玩法包含英雄成长、防御塔、工人、资源、波次、挑战、奖励和永久玩家档案。
- 游戏运行层使用 Dota 2 Lua 与 Panorama；当前已验证的本地 Workshop 路径通过同机 Python HTTP API 接入 Supabase PostgreSQL。

## Current Architecture

```text
Dota client / Panorama
        |
        | Custom Game Event / NetTable
        v
Dota server Lua
        |
        | loopback HTTP
        v
Python: ThreadingHTTPServer + FishingApplication + SupabaseRpcClient
        |
        | HTTPS REST/RPC
        v
Supabase PostgreSQL
```

- Python API 位于独立 `D:\survival_database` 仓库，当前不是 FastAPI。
- 本地 Workshop/LAN 候选拓扑是同一主机运行 Dota 服务端 Lua、Python API 和 Supabase 访问；该结论不得外推为正常发布 Arcade 的事实。
- 正常发布 Arcade 中 Lobby Owner、Game Server、Lua 运行主机和 Python 主机的关系尚未证实，当前归类为 `MODEL-D`。见 `architecture/MULTIPLAYER_TOPOLOGY_REPORT.md`。
- Python API 保持绑定 `127.0.0.1:8765`；它只适用于 Lua 与 Python 同机的拓扑。不得为探测拓扑直接改绑 LAN 地址。

## Authority And Trust Boundaries

| Concern | Authority |
| --- | --- |
| 业务配置 | `data/csv/` |
| 生成 Lua | `scripts/vscripts/config/generated/`，禁止手改 |
| Gameplay 状态 | Dota server Lua |
| UI 表现 | Panorama，只消费服务端投影 |
| HTTP 与数据库凭据 | Python server environment |
| 永久数据 | Supabase RPC/PostgreSQL |
| 永久玩家身份 | 服务端 Steam Account ID，经 Python HMAC-SHA256 后入库 |

客户端不能决定身份、奖励、支付成功、价格、永久属性或数据库写入结果。

## Permanent Progression

- `/v1/profile` 负责首次幂等建档和已有档案读取。
- `/v1/online-time/checkpoint` 负责在线 checkpoint、累计和 final 请求。
- `player_gameplay_stats.csv` 是核心玩法属性默认值权威源；档案私有 `save.gameplay_stats` 不发布到公开 NetTable。
- 在线时长只累计同一 session、租约内相邻 checkpoint 的有效差值；首次、新 session、超租约和离线间隔累计 0。
- Session ID 必须包含每次运行唯一 nonce，避免跨 Workshop Run 重放历史幂等响应。
- `reward_grants` 是不可变发放记录，`player_effect_totals` 是永久效果当前投影。
- 已完工城墙毁坏通过 `finish("wall_destroyed")` 进入共享 final 状态机；验收服务端持久化以 Lua `final=true`、Python API HTTP 200 和 Supabase 返回最终在线累计为证据。终局后的本地 `session_closed` callback 可独立观测，不否定已成功提交的服务端 final。

详细契约见 `PLAYER_PROFILE_INTEGRATION.md` 与 `FISHING_REWARD_INTEGRATION.md`。

## Core Gameplay Engineering Rules

- Lua 生产代码兼容 Lua 5.1。
- 英雄逻辑三维通过项目战斗属性快照获取，不以原生 `GetStrength()` 等为权威。
- 技能伤害复用现有伤害服务、事件总线和事务。
- 真实逐单位碰撞的穿透直线技能使用 `ProjectileManager:CreateLinearProjectile()`。
- 攻击射程复用项目现有回退辅助函数。
- 定时逻辑优先使用项目 scheduler，并明确结束与清理路径。
- 多人 Builder progression、建筑数量、普通波次 Marker、怪物城墙目标和断线生命周期均以数字 `player_id` 隔离；同属 `DOTA_TEAM_GOODGUYS` 不能作为共享或所有权依据。
- 玩家命令统一经过唯一 ExecuteOrderFilter；真实玩家命令的全部单位必须解析为该玩家 owner，系统/AI issuer `-1` 保持放行。服务端注册身份和 `survival_player_id` 优先于普通 creature 不可靠的引擎 owner getter。
- 普通波次出生点由 `player_slots.csv::wave_spawn_marker` 权威映射。玩家断线后该槽位本局不再生成波次怪，其他玩家通道继续运行。

## Current Development Phase

Backend Integration Phase：当前 P0 是 Player Session、在线 checkpoint、终局 finalization 和生产双玩家联调。

动态状态只记录在 `CURRENT_TASK.md`、对应 Task 文件和 `KNOWN_ISSUES.md`。

## Context Map

| Topic | Source |
| --- | --- |
| 当前调度 | `CURRENT_TASK.md`, `CURRENT_SPRINT.md`, `tasks/` |
| API / DB / Event / Attribute 索引 | `registry/` |
| 玩家档案 | `PLAYER_PROFILE_INTEGRATION.md` |
| 在线奖励 | `FISHING_REWARD_INTEGRATION.md` |
| 肉鸽奖励 | `ROGUE_REWARD_INTEGRATION.md` |
| 波次模型 | `WAVE_MODEL_RESOURCE_LIFECYCLE.md` |
| 故障排查 | `WAVE_MODEL_LOADING_TROUBLESHOOTING.md`, `KNOWN_ISSUES.md` |
| 历史证据 | `SESSION_LOG.md`, `archive/`，仅按需读取 |

## History

重构前的完整稳定知识与历史混合文档保存在 `archive/2026-08-25-pre-knowledge-refactor/PROJECT_CONTEXT.md`。