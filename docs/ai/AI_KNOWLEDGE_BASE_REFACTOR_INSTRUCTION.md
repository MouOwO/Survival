# SurvivalContent AI Knowledge Base Refactor Instruction

Version: 1.0
Purpose: 让 AI 在不改变项目认知、不大规模重写内容的前提下，对现有 `ai/` 目录进行一次低风险、低 Token 消耗的结构化重构。

---

# 0. 你的角色

你现在不是业务开发者。

你现在是：

**SurvivalContent AI Knowledge Base Architect**

你的任务不是新增架构、修改代码或重新设计项目。

你的任务只有一个：

> 把当前 `ai/` 目录整理成更容易被 AI 检索、更少重复读取、更不容易发生上下文污染的共享知识库。

---

# 1. 最高优先级原则

## 1.1 不改变项目事实

现有文档中的项目事实、已验证结果、当前代码状态、架构决策均视为已有知识。

不得因为整理格式而：

- 改变事实
- 推翻已有结论
- 自行补全未知信息
- 将“建议”写成“事实”
- 将“待验证”写成“已完成”
- 将“历史状态”写成“当前状态”

---

## 1.2 不进行架构重写

这次任务不是重新设计 SurvivalContent。

禁止：

- 发明新的后端架构
- 发明新的数据库模型
- 发明新的 API
- 发明新的 Session 规则
- 把项目改造成 MMO / ARPG / 大型 LiveOps 架构
- 因为你认为某种设计更优而替换现有设计

只允许对现有知识进行整理、压缩、归类和润色。

---

## 1.3 最小修改原则

目标不是“写得更多”。

目标是：

> **用更少的文字表达相同的项目知识。**

优先做：

- 删除重复描述
- 合并重复背景
- 把长段落改成表格
- 把状态改成短摘要
- 把历史内容移出当前上下文
- 把稳定事实和临时状态分离
- 用链接/引用代替重复复制

不要为了结构漂亮而大量扩写。

---

# 2. 当前项目知识库的核心问题

现有 `ai/` 内容已经包含大量有价值知识，但存在以下风险：

## 2.1 CURRENT_TASK 过重

它同时承担了：

- 当前任务
- 历史任务
- 修复记录
- 测试结果
- 技术背景
- 已完成事项
- 未完成事项
- 启动方式
- 联调状态

结果：

> AI 每次读取当前任务都会消耗大量 Token，同时容易把旧状态误认为当前状态。

---

## 2.2 START_HERE 过重

`START_HERE.md` 应该是“恢复入口”，而不是“项目完整历史”。

它必须短。

目标：

**让新 AI 在几十秒内知道：**

1. 项目是什么
2. 目前处于什么阶段
3. 当前最重要的问题
4. 下一步读哪个文件

---

## 2.3 AI_CTO 与 PROJECT_CONTEXT 存在职责重叠

应明确：

### AI_CTO
回答：

> AI 应该如何思考和工作。

### PROJECT_CONTEXT
回答：

> SurvivalContent 当前是什么。

不要互相重复。

---

## 2.4 SESSION_LOG / archive 内容价值很高，但不能进入常驻上下文

历史信息必须保留。

但是：

> 历史信息 ≠ 当前上下文。

因此历史内容应保留原文或轻量整理，但不要让 AI 每次任务默认读取。

---

# 3. 目标知识架构

请把 `ai/` 调整为以下逻辑结构。

```text
ai/
├── START_HERE.md
├── AI_CTO.md
├── PROJECT_CONTEXT.md
├── CURRENT_TASK.md
├── DECISIONS.md
├── KNOWN_ISSUES.md
│
├── active/
│   └── README.md
│
├── registry/
│   ├── README.md
│   ├── attribute_registry.md
│   ├── api_registry.md
│   ├── event_registry.md
│   └── database_registry.md
│
├── integration/
│   ├── README.md
│   ├── session.md
│   ├── player_profile.md
│   └── rewards.md
│
├── troubleshooting/
│   └── ...
│
├── archive/
│   └── ...
│
└── refactor/
    └── REFACTOR_REPORT.md
```

注意：

**不要强制把所有现有文件搬进这些目录。**

只有在文件职责明显属于某一类别时才移动。

如果移动会造成大量修改，则宁可保留原位置。

---

# 4. 文件职责规则

## START_HERE.md

长度目标：

**50~120 行。**

只保留：

- 项目一句话定义
- 当前开发阶段
- 当前最高优先级
- 当前阻塞点
- AI 必读文件
- 当前任务入口

不要放：

- 长历史
- 详细代码说明
- 已经解决的问题
- 完整测试记录

---

## AI_CTO.md

这是 AI 的行为规范。

只回答：

- AI 是什么角色
- AI 如何分析需求
- 什么情况下不能直接写代码
- 如何检查现有架构
- 如何使用 Registry / ADR / Bible
- 如何做风险分析
- 如何设计测试
- 如何保持项目既有风格

不要复制：

- 当前数据库状态
- 当前 Bug
- 某个功能的完整实现
- 历史日志

---

## PROJECT_CONTEXT.md

只保留长期稳定事实。

建议包含：

### Project Identity

- Dota2 Arcade
- 小塔防 + 英雄成长
- Dota2 Lua + Panorama
- Python HTTP
- Supabase

### Current Architecture

- Dota server Lua
- loopback Python API
- Supabase RPC/PostgreSQL

### Important Boundaries

- client trust boundary
- data authority
- permanent progression
- CSV authority
- generated files

### Current Development Phase

一句话说明。

不要把每天变化的测试状态放进这里。

---

## CURRENT_TASK.md

必须改造成：

**“当前任务索引”，不是开发日志。**

目标长度：

**50~150 行。**

只记录：

- 当前 Sprint / Milestone
- P0 / P1 任务
- 当前进行中的任务
- 当前阻塞
- 每个任务对应的详细文件

推荐格式：

```text
# Current Task

## Current Milestone
Backend Integration

## P0
- TASK-001 Session Finalization
  Status: IN_PROGRESS
  Detail: integration/session.md

- TASK-002 Profile Persistence
  Status: READY
  Detail: PLAYER_PROFILE_INTEGRATION.md

## P1
...

## Current Blockers
- ...

## Next Recommended Action
...
```

不要把完成任务的完整历史继续堆在这里。

历史移动到 archive。

---

# 5. 不需要建立“人员 active 文件”

不要创建：

```text
active/alice.md
active/bob.md
active/yadong.md
```

除非以后项目真的出现这种管理需求。

原因：

- 三个人都可以处理多个领域
- 人员职责不是固定的
- 主要目标是统一 AI 输出，不是限制人员权限

本次只保留：

```text
active/README.md
```

用于说明：

> 当前知识库不按人员维护上下文。

---

# 6. Registry 的原则

Registry 是：

> “项目事实索引”。

不是解释文档。

例如：

## attribute_registry.md

只记录：

| Key | Type | Meaning | Source |
|---|---|---|---|

不要写长篇理论。

---

## api_registry.md

只记录：

| Method | Endpoint | Purpose | Owner | Idempotency |
|---|---|---|---|---|

---

## event_registry.md

只记录：

| Event | Producer | Consumer | Payload |
|---|---|---|---|

---

## database_registry.md

只记录：

| Table/RPC | Purpose | Writable By | Source |
|---|---|---|---|

如果当前无法从现有文档可靠确认，不要猜。

可以标记：

`UNKNOWN — verify in code`

---

# 7. Feature / Integration 文档原则

现有以下类型文件：

- PLAYER_PROFILE_INTEGRATION.md
- ROGUE_REWARD_INTEGRATION.md
- FISHING_REWARD_INTEGRATION.md
- WAVE_MODEL_RESOURCE_LIFECYCLE.md
- WAVE_MODEL_LOADING_TROUBLESHOOTING.md

这些文件的价值很高。

不要大规模重写。

只需要统一头部。

推荐固定结构：

```text
# Title

## Status

## Purpose

## Current Architecture

## Rules / Contracts

## Current Known State

## Validation

## Next Action

## Related Files
```

---

# 8. Status 必须严格区分

全库统一使用以下状态词：

- FACT
- IMPLEMENTED
- VERIFIED
- TESTING
- BLOCKED
- TODO
- DEPRECATED
- HISTORICAL
- UNKNOWN

不要使用模糊表达：

- “应该已经好了”
- “基本完成”
- “感觉没问题”
- “大概”
- “可能”

如果事实不确定：

`UNKNOWN`

如果只通过自动测试：

`TESTING`

如果真实 Workshop Tools 已验证：

`VERIFIED`

---

# 9. 时间信息原则

所有动态事实必须有日期。

例如：

```text
Last Verified: 2026-08-24
```

而不是：

```text
目前已经完成
```

---

# 10. 自动验证与实机验证必须区分

统一：

### STATIC

代码/文本静态检查。

### UNIT

单元测试。

### CONTRACT

契约测试。

### SIMULATION

模拟运行。

### WORKSHOP

Dota Workshop Tools 实机。

### PRODUCTION

真实环境。

任何文档不得把：

`STATIC / UNIT / CONTRACT`

描述成：

`WORKSHOP / PRODUCTION VERIFIED`

---

# 11. 历史信息处理

对于现有 CURRENT_TASK 中已经完成的大量历史内容：

不要删除。

按照以下规则处理：

```text
Current
↓
保留 1~3 行摘要
↓
详细记录
↓
archive/
```

例如：

```text
Current Task:
Online Finalization is waiting for Workshop verification.

Historical Detail:
See archive/2026-08-24-online-finalization.md
```

---

# 12. SESSION_LOG 重构原则

SESSION_LOG 是历史恢复材料。

保留。

但把每条记录压缩成：

```text
## 2026-08-24

### Goal
...

### Result
...

### Important Discovery
...

### Decision
...

### Remaining
...
```

不要重复整个 Feature 文档。

---

# 13. DECISIONS.md

只记录架构决策摘要。

每条使用：

```text
## DECISION-XXX

Decision:
...

Reason:
...

Impact:
...

Date:
...
```

如果详细决策存在于其它文件：

只保留摘要 + 链接。

---

# 14. KNOWN_ISSUES.md

只记录：

**现在仍然存在的问题。**

任何：

- 已解决
- 已验证
- 已弃用

都移动到 archive 或历史记录。

每个 Issue 使用：

```text
## ISSUE-XXX

Status:
Priority:
Symptom:
Known Cause:
Current Workaround:
Next Action:
Last Verified:
```

---

# 15. Token Optimization Rules

这是本次重构非常重要的目标。

AI 不应默认读取所有 `ai/` 文件。

默认常驻上下文只建议：

```text
START_HERE.md
AI_CTO.md
PROJECT_CONTEXT.md
CURRENT_TASK.md
```

处理具体任务时才读取：

```text
相关 Registry
相关 Integration/Bible
相关 ADR
相关 Troubleshooting
```

绝对不要默认加载：

```text
archive/*
SESSION_LOG.md 全文
其他无关系统文档
```

---

# 16. AI Context Selection Rule

以后 AI 面对任务必须先做：

```text
1. Identify Domain
2. Identify Relevant Files
3. Read Minimum Required Context
4. Implement
```

例如：

### 玩家档案问题

读取：

- PROJECT_CONTEXT
- CURRENT_TASK
- PLAYER_PROFILE_INTEGRATION
- API Registry
- Database Registry

不要读取：

- Rogue Reward
- Wave Model
- Historical archive

---

# 17. 不要过度拆文件

本次重构不是为了产生几十个 Markdown。

如果两个文件：

- 内容很短
- 目的高度相似
- 经常一起读取

可以合并。

原则：

> 少文件 + 清晰职责 > 大量碎片文件

---

# 18. 重构时的内容润色规则

允许：

- 修复重复
- 修复明显歧义
- 统一术语
- 统一标题
- 统一日期格式
- 改成长表格
- 将长段落拆成短条目
- 删除已经在其他权威文档中重复出现的内容
- 添加 Related Files / Source

不允许：

- 改变业务含义
- 新增未经验证的事实
- 修改 API 名称
- 修改数据库名称
- 修改配置值
- 修改代码
- “顺便”优化架构

---

# 19. Source of Truth 规则

对于冲突内容，按照以下优先级核对：

1. 当前代码
2. 当前数据库 migration / RPC / schema
3. 权威 CSV / 配置
4. 最新验证记录
5. DECISIONS / ADR
6. Feature 文档
7. Archive

如果仍冲突：

不要自行选择。

标记：

`CONFLICT — requires human decision`

---

# 20. 重构操作顺序

严格按以下顺序执行：

### Phase 1 — Inventory

列出：

- 所有文件
- 每个文件用途
- 是否当前需要
- 是否历史
- 是否重复

不要修改。

### Phase 2 — Classification

给每个文件分类：

- CORE
- CURRENT
- FEATURE
- REFERENCE
- TROUBLESHOOTING
- HISTORY

### Phase 3 — Minimal Refactor

只进行：

- 重命名
- 移动
- 去重
- 摘要
- 标题统一
- Status 统一

### Phase 4 — Build Index

更新：

`START_HERE.md`

`CURRENT_TASK.md`

必要时创建：

`registry/README.md`

### Phase 5 — Consistency Check

检查：

- 是否有事实丢失
- 是否有状态错误
- 是否有链接失效
- 是否出现重复
- 是否出现冲突

### Phase 6 — Report

最终创建：

`ai/refactor/REFACTOR_REPORT.md`

---

# 21. REFACTOR_REPORT.md 必须包含

```text
# Refactor Report

## Summary

## Files Changed

## Files Moved

## Files Merged

## Files Archived

## Duplicates Removed

## Ambiguities Found

## Conflicts Found

## Knowledge Not Modified

## Token Optimization

## Recommended Next Step
```

---

# 22. 最终验收标准

重构完成后必须满足：

- AI 可以在不读取 archive 的情况下理解项目当前阶段。
- AI 可以在少量文件下理解核心架构。
- CURRENT_TASK 不再承载历史日志。
- START_HERE 足够短。
- AI_CTO 不包含大量业务细节。
- PROJECT_CONTEXT 不包含大量临时状态。
- Feature 文档互不重复。
- 历史记录仍然可追溯。
- 未改变已知项目事实。
- 没有新增未经验证的架构结论。
- 没有修改业务代码。

---

# 23. 最终交付格式

完成后不要直接开始写业务代码。

先向用户输出：

## A. Refactor Summary

本次整理了什么。

## B. Current Knowledge Structure

AI 现在应该如何读取。

## C. Important Conflicts

发现哪些需要人工判断的问题。

## D. Token Optimization

哪些内容从常驻上下文移到了按需读取。

## E. Recommended Workflow

以后 AI 应该怎样开始一个新任务。

然后等待用户新的开发任务。

---

# 24. 最重要的一句话

这次任务的目标不是：

“把 ai/ 写得更漂亮。”

而是：

> **让三个不同的人使用不同 Prompt 时，三个 AI 仍然基于同一套项目事实、同一套工程规范、同一套架构决策，输出尽可能一致的结果。**

因此：

**统一知识 ≠ 统一 Prompt**

**统一事实 + 统一规范 + 统一决策 + 最小上下文 = 一致的 AI 输出。**
