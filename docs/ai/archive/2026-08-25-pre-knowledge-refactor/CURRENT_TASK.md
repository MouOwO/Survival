# SurvivalContent 当前任务调度中心

> 本文件只描述当前项目有哪些任务、任务状态、负责人、依赖关系、协作边界和下一步行动。
>
> 本文件不是个人工作日志，也不是代码实现说明。实际开发内容必须读取 `docs/ai/tasks/TASK-xxx.md`。

---

## 1. 协作模型

```text
PROJECT
   |
   v
CURRENT_SPRINT
   |
   v
CURRENT_TASK
   |
   +----------------+----------------+
   v                v                v
TASK-001         TASK-002         TASK-003 ...
   |                |                |
   v                v                v
 Files            Files            Files
   |                |                |
   v                v                v
 Tests            Tests            Tests
```

### 层级职责

| Layer | Authority | Location |
| --- | --- | --- |
| PROJECT | 项目稳定架构、业务边界和长期约定 | `docs/ai/PROJECT_CONTEXT.md` |
| CURRENT_SPRINT | 当前迭代目标、范围、门禁和任务集合 | `docs/ai/CURRENT_SPRINT.md` |
| CURRENT_TASK | 任务注册、状态、Owner、依赖和调度规则 | `docs/ai/CURRENT_TASK.md` |
| TASK | 单项任务的目标、进度、文件、测试和交接信息 | `docs/ai/tasks/TASK-xxx.md` |
| Files | 该任务允许修改和禁止修改的文件边界 | 对应 Task 文件的 `Affected Files` |
| Tests | 该任务必须通过的验证矩阵 | 对应 Task 文件的 `Testing Matrix` |

### 单向追踪规则

1. Project 决定 Sprint 的架构边界，Sprint 决定可调度的 Task 集合。
2. `CURRENT_TASK.md` 只注册任务，不复制 Task 文件中的实现说明。
3. 每个 Task 必须先声明 Files，再进入实现；未声明的文件默认不在修改范围内。
4. 每个 Task 必须声明 Tests；代码完成但测试矩阵未通过时不得标记 `DONE`。
5. 文件修改和测试结果必须能够反向追踪到唯一 Task ID。
6. 跨 Task 修改共享文件时必须先执行碰撞检查，并在两个 Task 文件中记录协作决定。

---

## 2. Current Project Phase

**Phase:** Backend Integration Phase

**Current Goal:** 完成 Dota 2 游戏端与 Python HTTP Server / Supabase 的稳定联调。

### Current Priority

| Priority | Area |
| --- | --- |
| P0 | 基础通信与 Session |
| P1 | 玩家永久数据 |
| P2 | 商城 / Attribute |
| P3 | BattlePass / Reward |
| P4 | 其他运营系统 |

---

## 3. Task Status Definition

| Status | Meaning |
| --- | --- |
| BACKLOG | 已记录但尚未开始 |
| READY | 已完成需求分析，可以开始；仍需满足 Dependency |
| IN_PROGRESS | 已有唯一 Primary Owner 正在开发 |
| BLOCKED | 被依赖、环境或外部条件阻塞 |
| REVIEW | 已完成实现，等待代码或架构 Review |
| TESTING | 已完成 Review，等待 Testing Matrix 或联调 |
| DONE | Testing Matrix 与用户要求的验收均已完成 |
| CANCELLED | 已取消，不再进入调度 |

```text
BACKLOG -> READY -> IN_PROGRESS -> REVIEW -> TESTING -> DONE
                         |
                         v
                      BLOCKED
```

`CANCELLED` 可从非 `DONE` 状态进入，但必须在 Task 文件中记录原因。

---

## 4. Priority Definition

| Priority | Meaning |
| --- | --- |
| P0 | 阻塞整个后端联调 |
| P1 | 当前阶段核心功能 |
| P2 | 正常功能 |
| P3 | 优化 |
| P4 | 非必要 |

---

## 5. Current Tasks

| ID | Task | Priority | Status | Owner | Dependency | Task File |
| --- | --- | --- | --- | --- | --- | --- |
| TASK-001 | Player Session | P0 | IN_PROGRESS | @xxx | None | `docs/ai/tasks/TASK-001.md` |
| TASK-002 | Online Checkpoint | P0 | READY | @xxx | TASK-001 | `docs/ai/tasks/TASK-002.md` |
| TASK-003 | Offline Finalization | P0 | READY | UNASSIGNED | TASK-001 | `docs/ai/tasks/TASK-003.md` |
| TASK-004 | Attribute Sync | P1 | BACKLOG | UNASSIGNED | TASK-001 | `docs/ai/tasks/TASK-004.md` |
| TASK-005 | Attribute Purchase | P1 | BACKLOG | UNASSIGNED | TASK-004 | `docs/ai/tasks/TASK-005.md` |

> `@xxx` 沿用当前项目输入，代表已登记但尚未映射到明确协作者身份的 Owner。Owner 明确前不得由 AI 自动接管。

---

## 6. Assignment Rules

1. 一个任务只能有一个 Primary Owner。
2. 多人可以协作，但协作者必须记录在对应 Task 文件中。
3. AI 不得自动接管其他人的 `IN_PROGRESS` 任务。
4. Owner 不明确时必须标记为 `UNASSIGNED`；已有但身份待映射的 Owner 使用原登记值并视为不可自动接管。
5. `Dependency != DONE` 时，任务不得进入 `IN_PROGRESS`。
6. 接手任务时必须同步更新本表和对应 Task 文件中的 Owner、Status、Current Progress 与 Next Action。

---

## 7. AI Task Selection

用户未明确指定 Task 时，按以下顺序选择：

1. 当前用户自己的 active task。
2. 当前 Sprint 中属于该用户的 `READY` Task。
3. 没有 Owner 的 `READY` Task。
4. Priority 最高的 `READY` Task。
5. Dependency 已全部为 `DONE` 的 Task。

AI 不得选择：

- `IN_PROGRESS` 且 Owner 不是当前用户的任务；
- `BLOCKED`、`DONE` 或 `CANCELLED` 任务；
- `REVIEW` 中且 Owner 不是当前用户的任务；
- 依赖尚未完成的任务。

---

## 8. Task Collision Prevention

修改任何文件前必须检查当前 Task Owner、`Affected Files`、Dependency、Git 工作区，以及其他 `IN_PROGRESS` Task 是否声明相同文件或共享模块。

发现文件冲突时必须停止实现并输出：

```text
TASK COLLISION DETECTED
Conflict Task ID:
Conflict Owner:
Conflict Files:
Recommended Resolution:
```

推荐由现有 Owner 合并工作、拆分文件所有权、显式建立协作关系，或等待冲突 Task 离开 `IN_PROGRESS`。不得擅自覆盖其他人的修改。

---

## 9. Task File Contract

每个 `docs/ai/tasks/TASK-xxx.md` 至少包含：

- Task ID、Goal、Priority、Status、Owner、Collaborators；
- Dependencies、Blocked Reason；
- Architecture / API / Database Impact；
- Affected Modules、Affected Files；
- Current Progress、Next Action；
- Testing Matrix、Handoff Notes。

任务文件负责“这个任务具体怎么做”，但不得复制长期项目知识；稳定结论应回写 `PROJECT_CONTEXT.md`。

---

## 10. Task Handoff

任务转交必须同时更新任务注册表和对应 Task 文件：

```text
Owner:
Status:
Current Progress:
Next Action:
Blocked Reason:
Affected Files:
Testing Results:
```

缺少上述任一关键信息时，不得视为完成交接。

---

## 11. Task Completion

任务不能因为“代码写完”直接标记 `DONE`，必须依次通过：

```text
IN_PROGRESS -> REVIEW -> TESTING -> DONE
```

进入 `DONE` 前必须满足：

1. `Affected Files` 与实际 diff 一致；
2. Testing Matrix 已记录每项结果；
3. 静态检查、模拟测试、构建和实机验证被准确区分；
4. Dependency 和下游任务状态已重新评估；
5. 用户要求的验收已明确完成。

---

## 12. AI Output Requirement

AI 接手任务后必须先报告：

```text
Task ID:
Task Goal:
Current Status:
Owner:
Dependencies:
Affected Modules:
Affected Files:
Required Tests:
Next Action:
Blocked Conditions:
Collision Check:
```

完成报告并读取对应 Task 文件后，才能开始实现。

---

## 13. Unknown Situation

无法确定当前任务、Owner、依赖、代码状态或文件归属时，不得猜测，必须进入 `ARCHITECTURE REVIEW`，按顺序检查：

1. `docs/ai/CURRENT_SPRINT.md`；
2. `docs/ai/CURRENT_TASK.md`；
3. 对应 `docs/ai/tasks/TASK-xxx.md`；
4. `docs/ai/PROJECT_CONTEXT.md`；
5. 相关 Registry、CSV 权威源、调用链和测试。

---

## 14. Important Principle

- `CURRENT_SPRINT.md` 回答“本次迭代要完成什么”。
- `CURRENT_TASK.md` 回答“当前有哪些任务，由谁负责，如何调度”。
- `tasks/TASK-xxx.md` 回答“单个任务具体如何实施和验证”。
- `PROJECT_CONTEXT.md` 回答“项目稳定事实和长期边界是什么”。
- `SESSION_LOG.md` 与 `archive/` 回答“过去发生过什么”。

这些职责不得混用。

---

## 15. Current Next Action

`TASK-001` 已处于 `IN_PROGRESS` 且 Owner 为 `@xxx`。在 Owner 身份和任务文件中的文件边界被确认前，AI 不自动接管；`TASK-002` 与 `TASK-003` 因依赖 `TASK-001` 尚未 `DONE`，不得进入实现。