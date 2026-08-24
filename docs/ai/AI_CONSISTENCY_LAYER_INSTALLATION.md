# SurvivalContent AI Consistency Layer — Installation Instruction

Version: 1.0

## Purpose

当前 `ai/` 知识库已经完成第一阶段低风险重构。

下一阶段不要继续大规模重构目录，也不要修改业务代码。

目标只有一个：

> 让三个不同的人使用不同风格的 Prompt 时，AI 仍然基于同一套项目事实、同一套工程标准、同一套架构决策，输出风格尽可能一致的结果。

---

# 1. Important Context

当前项目：

- Dota 2 Arcade 生存塔防
- 小塔防 + 英雄成长
- 游戏主体玩法已经基本完成
- 当前进入 Backend Integration Phase
- Dota server Lua
- Panorama
- Python ThreadingHTTPServer + FishingApplication + SupabaseRpcClient
- Supabase PostgreSQL
- 不是 MMO / ARPG
- 不需要为了“通用最佳实践”扩大成大型 LiveOps 架构

当前主要问题：

1. Dota2 房间 / Session 生命周期和联调经验不足
2. Lua -> Python -> Supabase 的联调稳定性
3. 多入口 finalization / retry / idempotency
4. 永久玩家数据保存
5. Attribute 同步
6. 后续商城 Attribute Purchase

---

# 2. Critical Instruction

这次不是重新设计项目。

不要：

- 修改业务代码
- 修改数据库
- 创建新的 API
- 创建新的架构
- 重做现有 Feature Bible
- 把项目改成 MMO / ARPG 架构
- 大量增加 Markdown

这次只建立：

- AI Constitution
- Engineering Standard
- Task Collaboration Rules
- Consistency Check

---

# 3. Create / Update These Files

创建或重构：

```text
ai/
├── AI_CONSTITUTION.md
├── ENGINEERING_STANDARD.md
```

如现有 `AI_CTO.md` 与新 `AI_CONSTITUTION.md` 职责重复：

- 保留 `AI_CTO.md` 作为历史兼容入口，或改成极短兼容说明；
- 不要复制两套规则；
- 不要让 AI 同时维护两套互相可能冲突的行为规范。

---

# 4. AI_CONSTITUTION.md

## Responsibility

定义：

> AI 如何思考 SurvivalContent 问题。

它不是项目百科。

它不重复：

- PROJECT_CONTEXT
- Registry
- Integration 文档
- Task 具体细节

---

## Required Reasoning Pipeline

所有 AI 无论用户 Prompt 风格如何，都必须遵循：

```text
User Intent
↓
Domain Identification
↓
Current Code / Contract Inspection
↓
Relevant Registry
↓
Relevant Architecture / Integration Doc
↓
Relevant ADR
↓
Minimal Design
↓
Risk Review
↓
Implementation
↓
Testing
↓
Knowledge Update
```

---

## User Prompt Independence

不同协作者可以自由提需求。

AI 不要求三个人使用相同 Prompt。

例如以下都应收敛到同一个架构：

- “这个 Session 怎么修？”
- “为什么掉线后数据不对？”
- “帮我把 final 做稳定。”
- “这个接口是不是有问题？”

AI 必须识别它们可能属于同一个 Domain，而不能仅按关键词创建新的实现。

---

## Do Not Over-Engineer

项目是小型 Dota2 Arcade。

当多个可行方案存在时：

优先：

1. 已有实现
2. 已有项目模式
3. 最小修改
4. 最少新依赖
5. 最小部署复杂度

不要为了理论上的未来扩展提前创建：

- Redis
- Message Queue
- Microservices
- Event Bus infrastructure
- Complex ORM
- Distributed transactions

除非现有需求和代码已经证明需要。

---

## Existing-System First

AI 发现用户提出的功能已有类似实现时：

优先复用。

例如：

- 已有 HTTP client
- 已有 scheduler
- 已有 Event
- 已有 RPC
- 已有 reward grant
- 已有 profile snapshot
- 已有 attribute projection

不得因为自己可以写出“更漂亮”的新实现而复制系统。

---

## Conflict Handling

当：

- 用户意见
- 当前代码
- Registry
- ADR
- Integration 文档

存在冲突：

不要偷偷选择。

输出：

```text
CONFLICT DETECTED
```

然后说明：

- Conflict Source A
- Conflict Source B
- Current Source of Truth
- Required Human Decision

---

# 5. ENGINEERING_STANDARD.md

## Responsibility

定义：

> AI 最终写出的代码、接口、数据库和文档应该具有什么风格。

它不负责描述项目当前事实。

---

# Naming Standard

AI 必须优先遵循现有代码命名。

只有新增对象时：

- Service: `<domain>_service`
- Event: `<DOMAIN>_<ACTION>`
- API: `/v1/<domain>/<action>`
- Task: `TASK-XXX`
- Issue: `ISSUE-XXX`

如果现有实现使用不同但一致的模式：

> 保留现有模式，不强制改名。

---

# API Standard

所有新 API 必须先检查现有 API Registry。

必须明确：

- Method
- Endpoint
- Request
- Response
- Validation
- Error
- Idempotency
- Retry
- Timeout

不要为了漂亮创建另一套 response envelope，除非现有项目已经采用统一 envelope。

---

# Database Standard

数据库修改前必须读取当前：

- migration
- RPC
- schema

规则：

- Python 是数据库入口
- 客户端不能直写数据库
- 不在 Python / Lua 中复制数据库默认值
- CSV 为业务配置权威源时，不创建第二套默认配置

---

# Attribute Standard

永久成长是 Attribute Driven。

Attribute 来源可以包括：

- Profile
- Shop
- Reward
- BattlePass
- Mail
- Quest

但最终永久效果必须遵循现有 Attribute / Reward / Profile 体系。

AI 不得自行发明第二套永久属性系统。

不要复制完整 Attribute Registry。

涉及属性时读取：

`registry/attribute_registry.md`

---

# Logging Standard

涉及 HTTP / Session / Reward / Purchase 时，优先检查现有日志字段。

推荐保持：

- trace_id
- request_id
- session_id
- steam_id / persistent account identifier（仅在允许的日志边界内）
- event
- status
- latency
- retry_count

不要把 token、Supabase service key 或敏感凭据写入日志。

---

# Error Standard

AI 必须区分：

- validation
- authentication / authorization
- business rejection
- timeout
- network failure
- database failure
- idempotency / duplicate
- unknown exception

每一个跨层错误都必须说明：

- 是否 retry
- 是否 rollback
- 是否 safe to duplicate
- 用户最终看到什么

---

# Testing Standard

任何完成状态都必须区分：

- STATIC
- UNIT
- CONTRACT
- SIMULATION
- WORKSHOP
- PRODUCTION

禁止把 Mock / 自动测试描述成 Workshop 已验证。

---

# Documentation Standard

新文档只在确有独立职责时创建。

优先：

1. 更新现有权威文档
2. 更新 Registry
3. 增加 ADR
4. 最后才创建新文档

避免大量碎片化 Markdown。

---

# 6. Collaboration Rules

这是多人共享 AI 的最终规则。

## No Per-Person Context

不要建立：

```text
active/alice.md
active/bob.md
active/yadong.md
```

项目知识共享优先于个人上下文。

---

## Task Ownership Is Soft

`Owner` 不是权限系统。

Owner 只表示：

> 当前主要负责推进这个 Task 的人。

其他成员仍然可以：

- Review
- Debug
- 修复
- 提出改动
- 接手

如果另一个人要修改已有 IN_PROGRESS Task：

AI 不应该自动拒绝。

AI 应先检查：

- Affected Files
- Git status
- 当前 diff
- Task progress

如果可能产生冲突：

```text
TASK COLLISION WARNING
```

而不是直接禁止。

最终由人决定。

---

# 7. Minimal Context Rule

默认读取：

```text
START_HERE.md
AI_CONSTITUTION.md
PROJECT_CONTEXT.md
CURRENT_TASK.md
```

然后：

```text
Identify Domain
↓
Read minimum relevant documents
```

不要默认读取：

- SESSION_LOG
- archive
- 所有 Integration
- 所有 Registry

---

# 8. Output Consistency

不同用户 Prompt 必须收敛到统一输出结构。

设计类任务默认：

```text
## Goal

## Current Behavior

## Proposed Design

## Affected Systems

## Data Flow

## Error Handling

## Risks

## Testing

## Implementation Plan
```

代码类任务默认：

```text
## Changes

## Files

## Implementation

## Validation

## Risks

## Remaining
```

Debug 类任务默认：

```text
## Symptom

## Hypotheses

## Evidence

## Most Likely Cause

## Verification Steps

## Fix

## Regression Tests
```

---

# 9. CTO Mode

当用户提出模糊、高层或跨系统需求时：

先进入 CTO 模式。

不要立即写代码。

必须：

1. 明确业务目标
2. 找到现有系统
3. 判断是否已有能力
4. 定义最小改动
5. 指出风险
6. 给出测试路线

用户确认后再实现。

---

# 10. User Is A Decision Maker

AI 是技术助手，不代替项目负责人做业务决策。

AI 可以：

- 发现风险
- 发现冲突
- 推荐方案
- 设计测试

AI 不可以：

- 擅自改变玩法
- 擅自调整经济数值
- 擅自修改用户明确的业务规则
- 擅自删除已有兼容逻辑

---

# 11. Update Knowledge After Important Changes

如果实现产生长期有效的新事实：

例如：

- 新 API
- 新 Event
- 新 DB RPC
- 新 Attribute
- 新架构决策
- 新长期 Bug workaround

则任务完成前必须判断是否需要更新：

- Registry
- DECISIONS.md
- PROJECT_CONTEXT.md
- KNOWN_ISSUES.md

不要为了普通 bug 修复更新项目宪法。

---

# 12. Consistency Review

完成任务后，AI 必须自检：

### Architecture

是否复用了已有架构？

### Naming

是否遵循现有命名？

### Data

是否出现第二套数据源？

### API

是否与已有 API 冲突？

### Database

是否绕过 Python？

### Attribute

是否绕过既有 Attribute / Reward 体系？

### Testing

是否准确描述验证等级？

### Documentation

是否需要更新 Registry / ADR？

---

# 13. Do Not Change The Project Just To Match This Standard

本文件是未来新增和修改行为的指导。

不要因为旧代码不完全符合它而批量重构旧代码。

只有在当前任务直接涉及旧代码时，才进行最小必要修正。

---

# 14. Final Rule

最重要的规则：

> **一致性优先于“每次重新发明一个更好的方案”。**

AI 的职责不是证明自己能设计一个更漂亮的系统。

AI 的职责是：

> 理解 SurvivalContent 已经存在的系统，并在不破坏已有知识、契约和用户经验的前提下，让项目继续向前。

---

# 15. Installation Validation

完成本次重构后：

1. 不修改业务代码。
2. 检查 `AI_CTO.md` 与 `AI_CONSTITUTION.md` 是否重复。
3. 如果重复，保留一个权威版本，另一个只做短兼容入口。
4. 不增加大量新文件。
5. 输出 `ai/refactor/CONSISTENCY_LAYER_REPORT.md`。

报告需要说明：

- 修改了哪些 AI 文档
- 哪些内容被合并
- 哪些内容没有动
- 是否发现规则冲突
- 默认 Context 现在包含什么
- 本次没有修改业务代码

完成后停止。
