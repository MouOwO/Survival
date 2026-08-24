# TASK-003 - Offline Finalization

## Task Metadata

| Field | Value |
| --- | --- |
| Goal | 在断线、终局和失败入口可靠完成玩家 Session 最终结算，并保持多入口幂等 |
| Priority | P0 |
| Status | READY |
| Owner | UNASSIGNED |
| Collaborators | None registered |
| Dependencies | TASK-001 must be DONE |
| Blocked Reason | TASK-001 尚未 DONE，当前不可进入实现 |

## Architecture Impact

覆盖 Dota 生命周期事件、Lua Session 状态机、Python final checkpoint 和 Supabase 事务关闭语义。

## Affected Modules

- Dota game end、player disconnect 与业务失败入口；
- Online time finalization state machine；
- Python checkpoint/final endpoint；
- Supabase Session finalization RPC。

## Affected Files

依赖解除且 Owner 明确后，在 Architecture Review 中登记。

## Current Progress

任务已登记。相关历史实现和 Workshop Tools 未决证据位于归档、`PROJECT_CONTEXT.md` 与 `KNOWN_ISSUES.md`。

## Next Action

等待 `TASK-001` 完成，然后分配唯一 Owner 并核对当前终局入口与实机日志。

## Testing Matrix

| Test | Required | Status |
| --- | --- | --- |
| Disconnect/final state behavior | Yes | Blocked |
| Multiple final entry idempotency | Yes | Blocked |
| Lua 5.1 syntax and behavior | Yes | Blocked |
| HTTP final callback integration | Yes | Blocked |
| Workshop Tools normal end and wall-destroyed end | Yes | Blocked |

## Handoff Notes

不得把静态契约或 Mock 描述为 Workshop Tools 实机 finalization 验证。