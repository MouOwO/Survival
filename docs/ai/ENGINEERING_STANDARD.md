# SurvivalContent Engineering Standard

Status: FACT
Last Reviewed: 2026-08-25

## Responsibility

本文件定义 AI 最终写出的代码、接口、数据库变更和文档应遵循的工程标准。它不描述项目当前事实；当前事实必须读取代码、CSV、migration、Registry 和 Integration 文档。

## Naming

优先遵循现有代码命名。新增对象默认使用：

- Service：`<domain>_service`
- Event：`<DOMAIN>_<ACTION>`
- API：`/v1/<domain>/<action>`
- Task：`TASK-XXX`
- Issue：`ISSUE-XXX`

现有实现若使用不同但一致的模式，保留现有模式，不强制改名。

## API

创建或修改 API 前必须读取 `registry/api_registry.md` 和当前实现。契约至少明确：

- Method、Endpoint、Request、Response
- Validation、Error
- Idempotency、Retry、Timeout

不得为了形式统一创建另一套 response envelope，除非项目已有统一 envelope。

## Database

数据库修改前必须读取当前 migration、RPC 和 schema。Python 是数据库入口，客户端不能直写数据库；不得在 Python 或 Lua 复制数据库默认值。业务配置权威源为 CSV 时，不创建第二套默认配置。

## Attributes

永久成长遵循现有 Attribute、Reward、Profile 体系。Attribute 来源可以是 Profile、Shop、Reward、BattlePass、Mail 或 Quest，但不得自行发明第二套永久属性系统。涉及属性时读取 `registry/attribute_registry.md`，完整字段直接以权威 CSV 为准。

## Logging

涉及 HTTP、Session、Reward 或 Purchase 时，先检查现有日志字段。适用时保持 `trace_id`、`request_id`、`session_id`、允许范围内的 `steam_id`/永久身份标识、`event`、`status`、`latency` 和 `retry_count`。禁止记录 token、Supabase service key 或其他敏感凭据。

## Errors

跨层错误必须区分 validation、authentication/authorization、business rejection、timeout、network failure、database failure、idempotency/duplicate 和 unknown exception，并说明：

- 是否 retry；
- 是否 rollback；
- 是否 safe to duplicate；
- 用户最终看到什么。

## Testing

报告必须准确区分：

- `STATIC`：静态文本、引用、编码、diff 或契约检查；
- `UNIT`：独立函数或服务测试；
- `CONTRACT`：API/Event/CSV/SQL 跨层契约；
- `SIMULATION`：Lua 5.1 Mock 或数学/行为模拟；
- `WORKSHOP`：Dota Workshop Tools 实机；
- `PRODUCTION`：真实账号、后端和目标环境。

不得把 Mock 或自动测试描述成 Workshop 或 Production 验证。

## Documentation

新文档只有在具有独立职责时才创建。优先更新现有权威文档，其次更新 Registry，再增加 ADR，最后才创建新文档，避免碎片化 Markdown。

## Change Discipline

不要为了符合本标准批量重构旧代码。只在当前任务直接涉及旧代码时做最小必要修正；修改前检查 Git 状态、Task 文件边界和其他进行中任务的文件冲突。