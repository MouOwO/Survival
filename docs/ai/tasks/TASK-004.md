# TASK-004 - Attribute Sync

## Task Metadata

| Field | Value |
| --- | --- |
| Goal | 在玩家档案、数据库永久属性和 Dota 运行时之间建立受控的 Attribute 同步 |
| Priority | P1 |
| Status | BACKLOG |
| Owner | UNASSIGNED |
| Collaborators | None registered |
| Dependencies | TASK-001 must be DONE |
| Blocked Reason | 尚未完成需求分析；TASK-001 dependency satisfied |

## Architecture Impact

永久属性必须由服务端身份和数据库档案驱动；玩法默认值继续来自 `data/csv/玩家档案系统/`，不得在 Lua、Python 或 SQL 中维护第二套默认值。

## Affected Modules

- Player profile payload；
- Gameplay attribute projection；
- Python validation and RPC payload；
- Supabase player attribute storage；
- Player profile CSV and generated Lua。

## Affected Files

待需求分析和 Architecture Review 后登记。

## Current Progress

仅进入 Backlog，尚未开始设计或实现。

## Next Action

明确属性清单、同步时机、冲突策略与数据版本后再进入 `READY`。

## Testing Matrix

| Test | Required | Status |
| --- | --- | --- |
| CSV/schema/payload consistency | Yes | Not started |
| Profile API contract | Yes | Not started |
| Lua projection behavior | Yes | Not started |
| Cross-player isolation | Yes | Not started |
| Workshop Tools profile restore | Yes | Not started |

## Handoff Notes

进入 `READY` 前必须完成字段、数值单位、版本和错误恢复设计。