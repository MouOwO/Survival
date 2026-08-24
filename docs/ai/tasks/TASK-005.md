# TASK-005 - Attribute Purchase

## Task Metadata

| Field | Value |
| --- | --- |
| Goal | 实现服务器权威、事务化且幂等的永久 Attribute Purchase |
| Priority | P1 |
| Status | BACKLOG |
| Owner | UNASSIGNED |
| Collaborators | None registered |
| Dependencies | TASK-004 must be DONE |
| Blocked Reason | 尚未完成需求分析，且依赖 TASK-004 |

## Architecture Impact

购买必须通过 Python 数据库入口执行校验、扣费、属性发放和日志事务；客户端只能发送购买意图，不得提交权威价格或属性增量。

## Affected Modules

- Purchase request/event；
- Python purchase transaction；
- Supabase balance, attribute and order/reward log；
- Attribute product/config CSV；
- Panorama purchase presentation when scoped。

## Affected Files

待需求分析、商品模型确认和 Architecture Review 后登记。

## Current Progress

仅进入 Backlog，尚未开始设计或实现。

## Next Action

等待 `TASK-004` 完成，再明确商品、货币、价格、退款、重复请求和失败恢复语义。

## Testing Matrix

| Test | Required | Status |
| --- | --- | --- |
| Purchase API contract | Yes | Not started |
| Transaction rollback | Yes | Not started |
| Idempotency and duplicate request | Yes | Not started |
| Insufficient balance and invalid product | Yes | Not started |
| Attribute refresh and cross-player isolation | Yes | Not started |
| Workshop Tools purchase integration | Yes | Not started |

## Handoff Notes

商品和支付语义未确认前，不新增正式发货 schema 或硬编码价格。