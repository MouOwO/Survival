# TASK-002 - Online Checkpoint

## Task Metadata

| Field | Value |
| --- | --- |
| Goal | 实现在线 Session 的周期 checkpoint、累计时间、奖励里程碑与幂等重试 |
| Priority | P0 |
| Status | READY |
| Owner | @xxx |
| Collaborators | None registered |
| Dependencies | TASK-001 must be DONE |
| Blocked Reason | TASK-001 尚未 DONE，当前不可进入实现 |

## Architecture Impact

沿用 Lua 调度、Python 参数验证、Supabase RPC 事务的单向数据流；奖励与 checkpoint 规则必须以对应 CSV 为权威源。

## Affected Modules

- Online time scheduler/service；
- HTTP checkpoint endpoint；
- Supabase online time RPC、幂等与 reward grant；
- 玩家档案规则和奖励定义 CSV。

## Affected Files

依赖解除后，由 Owner 在 Architecture Review 中登记。

## Current Progress

需求已登记，尚未因依赖门禁进入实现。

## Next Action

等待 `TASK-001` 完成；随后核对 API Contract、CSV 规则、RPC 签名和现有测试。

## Testing Matrix

| Test | Required | Status |
| --- | --- | --- |
| Checkpoint API/RPC contract | Yes | Blocked |
| Duplicate request and retry idempotency | Yes | Blocked |
| Lua 5.1 scheduling behavior | Yes | Blocked |
| CSV/generated consistency | Yes | Blocked |
| Python and SQL tests | Yes | Blocked |
| Workshop Tools checkpoint integration | Yes | Blocked |

## Handoff Notes

`READY` 不表示可立即实现；Dependency 未完成时保持门禁。