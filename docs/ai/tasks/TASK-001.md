# TASK-001 - Player Session

## Task Metadata

| Field | Value |
| --- | --- |
| Goal | 建立 Dota 2 游戏端、Python HTTP Server 与 Supabase 之间稳定且可恢复的玩家 Session |
| Priority | P0 |
| Status | DONE |
| Owner | @xxx |
| Collaborators | None registered |
| Dependencies | None |
| Blocked Reason | None |

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

用户已确认城墙毁坏最终结算验收通过。已完工城墙死亡能够触发
`finish("wall_destroyed")`，Lua 发出 `final=true`，Python API 返回 HTTP 200，Supabase
成功执行最终 checkpoint 并记录在线时间。`session_closed` 属于游戏失败后的本地
Lua 收尾回执，不作为本次服务端持久化验收的阻断条件。

## Next Action

本任务已完成。双玩家生产联调、重连和 API 重启属于独立后续验证，不重新打开本任务。

## Testing Matrix

| Test | Required | Status |
| --- | --- | --- |
| API contract and idempotency tests | Yes | Passed in existing test evidence |
| Python unit tests | Yes | Passed in existing test evidence |
| Lua 5.1 behavior tests | Yes | Passed in existing test evidence |
| Lua 5.1 syntax | Yes | Passed in existing test evidence |
| CSV/generated consistency when applicable | Conditional | Passed; no CSV change in finalization scope |
| Strict UTF-8 and `git diff --check` | Yes | Passed |
| Workshop Tools wall-destruction finalization | Yes | User accepted; API final HTTP 200 and online time persisted |

## Handoff Notes

任务于 2026-08-25 按用户确认关闭。验收范围是“已完工城墙毁坏 -> `wall_destroyed` ->
`final=true` -> Python API -> Supabase 在线时间最终记录”。Dota 终局后未观察到
`session_closed` 仅保留为非阻断的本地 callback 观测项；不得将其扩大解释为服务端
持久化失败。后续双玩家生产联调另行记录。