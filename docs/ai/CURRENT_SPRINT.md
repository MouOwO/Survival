# Current Sprint

## Sprint Goal

完成 Dota 2 游戏端与 Python HTTP Server / Supabase 的基础通信、Player Session、在线 checkpoint 和离线最终结算闭环。

## Phase

Backend Integration Phase

## Scope

| Task | Priority | Sprint Role |
| --- | --- | --- |
| TASK-001 Player Session | P0 | 已完成基础任务 |
| TASK-002 Online Checkpoint | P0 | 依赖已满足的在线累计任务 |
| TASK-003 Offline Finalization | P0 | 依赖已满足的终局结算任务 |
| TASK-004 Attribute Sync | P1 | 后续永久数据任务 |
| TASK-005 Attribute Purchase | P1 | 后续属性购买任务 |

## Sprint Gate

1. `TASK-001` 已于 2026-08-25 完成 Review、Testing 和城墙毁坏验收，`TASK-002`、`TASK-003`、`TASK-004` 的依赖门禁已解除。
2. 每个任务必须在对应 `docs/ai/tasks/TASK-xxx.md` 中声明 Files 和 Tests。
3. Supabase、Python 和 Lua 的联调结果必须区分自动测试、HTTP 联调与 Workshop Tools 实机验证。
4. CSV 继续作为业务配置权威源；涉及配置的任务必须从 CSV 修改并生成，禁止直接修改生成 Lua。

## Registry

任务状态、Owner 和依赖以 `docs/ai/CURRENT_TASK.md` 为准。