# Project Registries

Status: FACT
Last Reviewed: 2026-08-25

Registry 是项目事实索引，不是解释文档，也不替代代码、CSV、migration 或 Integration 文档。

| Registry | Purpose |
| --- | --- |
| `attribute_registry.md` | 永久玩法属性与权威源索引 |
| `api_registry.md` | 当前已确认 HTTP API 索引 |
| `event_registry.md` | 当前已确认关键事件索引 |
| `database_registry.md` | 当前已确认数据库表 / RPC 索引 |

使用规则：

1. 只在任务涉及对应领域时读取。
2. `UNKNOWN — verify in code` 不是事实，实施前必须核对。
3. Registry 与代码冲突时，以当前代码、migration/RPC 和权威 CSV 为准，并更新 Registry。
4. 不在 Registry 记录历史过程、测试日志或设计理论。