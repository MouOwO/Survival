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
| Blocked Reason | Owner unassigned; TASK-001 dependency satisfied |

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

任务已登记，`TASK-001` 依赖已满足。城墙毁坏服务端 final 已验收；本任务其余范围需在分配 Owner 后重新界定。

## Next Action

分配唯一 Owner、登记 Affected Files，并核对正常终局、断线入口与剩余 callback 观测范围。

## Testing Matrix

| Test | Required | Status |
| --- | --- | --- |
| Disconnect/final state behavior | Yes | Not started for remaining scope |
| Multiple final entry idempotency | Yes | Existing evidence; recheck when scope starts |
| Lua 5.1 syntax and behavior | Yes | Existing evidence; recheck when scope starts |
| HTTP final callback integration | Yes | Wall-destroyed server persistence accepted |
| Workshop Tools normal end and wall-destroyed end | Yes | Wall-destroyed accepted; normal end not started |

## Handoff Notes

不得把静态契约或 Mock 描述为 Workshop Tools 实机 finalization 验证。