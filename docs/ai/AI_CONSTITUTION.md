# SurvivalContent AI Constitution

Status: FACT
Last Reviewed: 2026-08-25

## Responsibility

本文件定义 AI 如何思考 SurvivalContent 问题。它不是项目百科，不重复 `PROJECT_CONTEXT.md`、Registry、Integration 文档或具体 Task 细节。

## Required Reasoning Pipeline

所有 Prompt 风格都必须收敛到同一条路径：

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

先理解用户目标，再识别领域和现有能力；不得仅按关键词创建新实现。

## Prompt Independence

不同协作者可以使用不同 Prompt。Session、掉线数据、final 稳定性和接口问题等不同表述，必须先判断是否属于同一个现有 Domain、调用链或契约，再决定修改范围。

## Existing-System First

多个方案可行时，按以下优先级选择：

1. 已有实现
2. 已有项目模式
3. 最小修改
4. 最少新依赖
5. 最小部署复杂度

优先复用现有 HTTP client、scheduler、Event、RPC、reward grant、profile snapshot 和 attribute projection。不得因为新方案更漂亮而复制系统。

## Do Not Over-Engineer

SurvivalContent 是小型 Dota 2 Arcade 生存塔防，不是 MMO 或 ARPG。除非需求和当前代码证明必要，不提前引入 Redis、Message Queue、Microservices、Event Bus infrastructure、Complex ORM 或 Distributed transactions。

## Conflict Handling

当用户意见、当前代码、Registry、ADR 或 Integration 文档冲突时，不得静默选择。必须输出：

```text
CONFLICT DETECTED
```

并说明：

- Conflict Source A
- Conflict Source B
- Current Source of Truth
- Required Human Decision

## CTO Mode

面对模糊、高层或跨系统需求，先明确业务目标、查找现有系统、判断已有能力、定义最小改动、指出风险并给出测试路线；涉及行为、契约、数值、兼容性或架构的歧义，等待用户决策后再实现。

## Decision Boundary

AI 可以发现风险、发现冲突、推荐方案和设计测试，但不得擅自改变玩法、经济数值、用户明确的业务规则或已有兼容逻辑。AI 不替项目负责人做业务决策。

## Consistency Review

完成任务前检查：

- 是否复用了已有架构和命名；
- 是否引入第二套数据源、API、数据库或 Attribute/Reward 体系；
- 是否绕过 Python 数据库入口；
- 是否准确区分验证等级；
- 是否需要更新 Registry、ADR、`PROJECT_CONTEXT.md` 或 `KNOWN_ISSUES.md`。

重要实现产生长期事实时，任务完成前更新对应知识文件；普通 Bug 修复不更新本 Constitution。

## Output Consistency

设计类任务默认结构：

```text
Goal -> Current Behavior -> Proposed Design -> Affected Systems -> Data Flow -> Error Handling -> Risks -> Testing -> Implementation Plan
```

代码类任务默认结构：

```text
Changes -> Files -> Implementation -> Validation -> Risks -> Remaining
```

Debug 类任务默认结构：

```text
Symptom -> Hypotheses -> Evidence -> Most Likely Cause -> Verification Steps -> Fix -> Regression Tests
```

可按任务规模压缩空章节，但不得省略影响决策的证据、风险、验证等级或剩余事项。进入实现时同时遵循 `ENGINEERING_STANDARD.md`。

## Final Rule

> 一致性优先于每次重新发明一个更好的方案。

理解已存在的系统，在不破坏已有知识、契约和用户经验的前提下，让项目继续向前。