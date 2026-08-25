# Architecture Decisions

Last Reviewed: 2026-08-25

本文件只保留当前仍适用的长期决策摘要。重构前完整决策记录见 `archive/2026-08-25-pre-knowledge-refactor/DECISIONS.md`。

## DECISION-001

**Decision:** 本地 Workshop/LAN 联调采用候选同机拓扑，Python API 保持绑定 `127.0.0.1:8765`；正常发布 Arcade 拓扑暂定 `MODEL-D`。

**Reason:** 当前代码与 Workshop 证据只证明 Lua 和 Python 同机时 loopback 可用；没有 Dota Arcade 专属证据证明 Lobby Owner 就是 Game Server 或 Lua 主机。loopback 仍用于缩小本地认证和网络暴露面。

**Impact:** 生产 Session Foundation 在最小拓扑实验完成前暂停；不得把 Lobby Owner、Game Server、Lua 主机和 Python 主机视为同一实体。LAN API 暴露仍必须另立安全任务。

**Date:** 2026-08-23; qualified 2026-08-25

## DECISION-002

**Decision:** 删除旧局内钓鱼持久化；在线奖励只使用独立 online checkpoint 链路。

**Reason:** 避免两套 session、幂等和计时状态并存。

**Impact:** 不得恢复 `fishing_states`、`fishing_sessions`、`fishing_idempotency`、`heartbeat_fishing_session(...)` 或 `/v1/fishing/heartbeat`。

**Date:** 2026-08-23

## DECISION-003

**Decision:** 永久玩家身份由服务端 Steam Account ID 经 Python 稳定 pepper HMAC-SHA256 后入库；玩法属性默认值来自 CSV。

**Reason:** 分离局内 PlayerID 与永久身份，并消除 Lua/Python/SQL 的重复默认值。

**Impact:** pepper 必须长期稳定且仅存在服务端；`player_gameplay_stats.csv` 是默认值权威源。

**Date:** 2026-08-20

## DECISION-004

**Decision:** 永久在线时长只累计同一 session、租约内相邻 checkpoint 的差值。

**Reason:** 墙钟时间和客户端上报不能可靠表示有效在线时间。

**Impact:** 首次、新 session、超租约、离线间隔与重复 request 均不得重复累计。

**Date:** 2026-08-20

## DECISION-005

**Decision:** CSV 是业务配置权威源，生成 Lua 禁止手改。

**Reason:** 防止配置在 CSV、Lua、Tooltip、Python 和数据库之间分叉。

**Impact:** 配置任务必须修改 CSV、运行生成器并检查跨层一致性。

**Date:** 2026-08-18 and earlier

## DECISION-006

**Decision:** 客户端只发送意图；抽卡、购买、奖励、档案和战斗结果由服务端校验和提交。

**Reason:** 保持 server authority、跨玩家隔离和幂等。

**Impact:** Panorama 不得直接授予权益、奖励、属性或数据库结果。

**Date:** 2026-08-17 and earlier

## DECISION-007

**Decision:** 多人最小闭环优先于正式商品和支付。

**Reason:** 身份、Session、归属和恢复是商品系统的前置边界。

**Impact:** 未确认订单、退款、撤销和商品类型前，不新增正式支付发货 schema。

**Date:** 2026-08-23

## DECISION-008

**Decision:** 终局在线结算使用幂等 `online_time_service.finish(source)`，失败局同时从已完工城墙毁坏业务入口触发。

**Reason:** Workshop Tools 中 `game_end` 不能作为唯一可靠入口。

**Impact:** `POST_GAME`、`game_end` 和 `wall_destroyed` 共享状态机，不得重复 final；城墙毁坏到服务端 final 持久化已完成 Workshop 验收。

**Date:** 2026-08-24; accepted 2026-08-25