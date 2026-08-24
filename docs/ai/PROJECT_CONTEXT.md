# Project Context

Status: FACT
Last Verified: 2026-08-24

## Project Identity

- SurvivalContent 是 Dota 2 Arcade 生存塔防项目。
- 主要玩法包含英雄成长、防御塔、工人、资源、波次、挑战、奖励和永久玩家档案。
- 游戏运行层使用 Dota 2 Lua 与 Panorama；永久数据通过本机 Python HTTP API 接入 Supabase PostgreSQL。

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
- 推荐多人拓扑是主机运行 Dota 服务端、Python API 和 Supabase 访问；加入者只连接 Dota 对局。
- Python API 保持绑定 `127.0.0.1:8765`。改为 LAN 暴露必须另立安全设计任务。

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

详细契约见 `PLAYER_PROFILE_INTEGRATION.md` 与 `FISHING_REWARD_INTEGRATION.md`。

## Core Gameplay Engineering Rules

- Lua 生产代码兼容 Lua 5.1。
- 英雄逻辑三维通过项目战斗属性快照获取，不以原生 `GetStrength()` 等为权威。
- 技能伤害复用现有伤害服务、事件总线和事务。
- 真实逐单位碰撞的穿透直线技能使用 `ProjectileManager:CreateLinearProjectile()`。
- 攻击射程复用项目现有回退辅助函数。
- 定时逻辑优先使用项目 scheduler，并明确结束与清理路径。

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