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
| Blocked Reason | None; TASK-001 dependency satisfied |

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

需求已登记，`TASK-001` 依赖已满足；尚未登记本任务 Affected Files 或进入实现。

## Next Action

由 Owner 登记 Affected Files，并核对 API Contract、CSV 规则、RPC 签名和现有测试。

## Testing Matrix

| Test | Required | Status |
| --- | --- | --- |
| Checkpoint API/RPC contract | Yes | Not started |
| Duplicate request and retry idempotency | Yes | Not started |
| Lua 5.1 scheduling behavior | Yes | Not started |
| CSV/generated consistency | Yes | Not started |
| Python and SQL tests | Yes | Not started |
| Workshop Tools checkpoint integration | Yes | Not started |

## Handoff Notes

`TASK-001` 依赖已于 2026-08-25 解除。`READY` 仍要求实现前完成文件边界和测试矩阵复核。