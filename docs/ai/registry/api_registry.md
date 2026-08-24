# API Registry

Status: FACT
Last Reviewed: 2026-08-25

| Method | Endpoint | Purpose | Owner | Idempotency |
| --- | --- | --- | --- | --- |
| GET | `/health` | 仅检查 Python API 进程可达 | Python API | Not required |
| POST | `/v1/profile` | 幂等确保玩家档案存在并返回档案快照 | Python `FishingApplication` / Supabase RPC | Account identity / RPC semantics |
| POST | `/v1/online-time/checkpoint` | 在线时间 checkpoint、奖励里程碑和 `final=true` 结算 | Python `FishingApplication` / Supabase `checkpoint_online_time` | `request_id` within session |
| POST | `/v1/fishing/heartbeat` | DEPRECATED：旧局内钓鱼持久化入口 | None | Removed |

## Trust Boundary

- 调用方是 Dota server Lua，不是 Panorama。
- Python API 绑定 loopback，并持有 Supabase 凭据。
- 请求 / 响应完整字段：按任务读取当前 Python 代码与相关 Integration 文档。