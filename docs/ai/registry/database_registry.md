# Database Registry

Status: FACT
Last Reviewed: 2026-08-25

数据库实现位于独立 `D:\survival_database` 仓库。修改前必须读取当前 migration、RPC 和 schema；本表只做对象定位。

| Table / RPC | Purpose | Writable By | Source |
| --- | --- | --- | --- |
| `survival_players` | 永久玩家根记录 | Supabase RPC via Python | Current migrations |
| `player_gameplay_stats` | 玩家核心永久玩法属性与在线累计 | Supabase RPC via Python | `player_gameplay_stats.csv` + migrations |
| `online_time_sessions` | 当前在线 Session / 租约状态 | `checkpoint_online_time(...)` | Current checkpoint migrations |
| `online_time_idempotency` | Checkpoint 请求幂等响应 | `checkpoint_online_time(...)` | Current checkpoint migrations |
| `reward_grants` | 不可变奖励发放记录 | Reward/checkpoint RPC | Current reward migrations |
| `player_effect_totals` | 玩家永久效果当前投影 | Reward/checkpoint RPC | Current reward migrations |
| `ensure_player_gameplay_stats(...)` | 幂等创建 / 确保玩家属性行 | Python through Supabase RPC | Current profile migrations |
| `checkpoint_online_time(...)` | 原子累计在线时间、处理奖励和幂等 | Python through Supabase RPC | Current online-time migrations |
| `heartbeat_fishing_session(...)` | DEPRECATED：旧局内钓鱼心跳 | None | Removed by cleanup migration |

远端 migration 实际状态必须由目标 Supabase 核对，不能仅凭本地文件或本表宣称已部署。