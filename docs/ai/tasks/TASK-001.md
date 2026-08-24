# TASK-001 - Player Session

## Task Metadata

| Field | Value |
| --- | --- |
| Goal | 建立 Dota 2 游戏端、Python HTTP Server 与 Supabase 之间稳定且可恢复的玩家 Session |
| Priority | P0 |
| Status | IN_PROGRESS |
| Owner | @xxx |
| Collaborators | None registered |
| Dependencies | None |
| Blocked Reason | Owner 身份与本任务当前文件边界尚未完成交接确认 |

## Architecture Impact

涉及 `Dota server Lua -> loopback Python API -> Supabase RPC/PostgreSQL` 主链。Python 是唯一数据库入口，Panorama 不访问 HTTP，Lua 不访问 SQL。

## API And Database Impact

必须在实现前根据当前代码确认 Session API、请求幂等键、租约、重连和关闭语义。不得把历史归档 AI CTO 手册中的目标 FastAPI 目录误当成当前实现。

## Affected Modules

- Lua 玩家档案与在线 Session 服务；
- Python HTTP application 与 Supabase RPC client；
- Supabase Session/RPC/migration；
- 玩家档案系统 CSV 规则与生成配置（仅在数值规则确需修改时）。

## Affected Files

- 待 Primary Owner 或实际协作者在修改前依据当前调用链登记；未登记文件必须先补充并检查 Git collision，最终由人确认是否继续。

## Current Progress

任务注册为进行中。历史实现和验证证据保存在 `docs/ai/archive/2026-08-24-pre-task-registry-current-task.md`、`docs/ai/SESSION_LOG.md` 与相关集成文档中。

## Next Action

由 `@xxx` 完成交接：确认当前 Session 契约、实际关联文件、剩余验证和 Owner 身份。

## Testing Matrix

| Test | Required | Status |
| --- | --- | --- |
| API contract and idempotency tests | Yes | Pending handoff |
| Python unit tests | Yes | Pending handoff |
| Lua 5.1 behavior tests | Yes | Pending handoff |
| Lua 5.1 syntax | Yes | Pending handoff |
| CSV/generated consistency when applicable | Conditional | Pending handoff |
| Strict UTF-8 and `git diff --check` | Yes | Pending handoff |
| Workshop Tools session/reconnect integration | Yes | Pending handoff |

## Handoff Notes

不得依据旧 `CURRENT_TASK.md` 的历史段落直接宣称当前任务完成；交接时必须重新核对实际代码、远端 migration 和实机证据。