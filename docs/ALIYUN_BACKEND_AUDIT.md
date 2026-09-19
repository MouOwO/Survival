# 苟发育后端迁移代码审计

审计日期：2026-09-19。范围为本地两个仓库；未读取后端 `.env`，未连接 ECS 或 Supabase。云端实际对象清单必须通过只读导出核实。

## 实际运行链路

- 后端仓库：`D:/survival_database`，入口 `backend/run_fishing_api.py` → `fishing_api/server.py`。
- 原服务：Python 标准库 HTTP + `urllib` 调用 Supabase `/rest/v1/rpc/...`，没有 Supabase Python SDK、ORM、FastAPI 或直接 PostgreSQL 连接。
- 核心业务在 PostgreSQL 函数中：档案、永久奖励、幂等回执、在线结算、存档版本冲突。换地址不能替代 PostgREST 协议。
- 存档服务另位于游戏仓库 `server/archive_backend`，用固定 Lua 结算模块和版本化 CSV bundle。原独立后端没有合入存档 HTTP 路由；此次作为可配置扩展接入。
- 玩家标识为账号加 `FISHING_ACCOUNT_ID_PEPPER` 的 HMAC。必须保留 pepper；原数据库管理员密码不得作为应用密码。

## Supabase 依赖

| 能力 | 本地代码结果 | 迁移处理 |
|---|---|---|
| PostgreSQL RPC | 主要业务依赖；11 个公开业务 RPC | 固定签名、参数绑定、JSONB、每次单独事务的 psycopg 适配 |
| RLS | 业务表开启 RLS；函数 SECURITY DEFINER | 保留 RLS；对象归 NOLOGIN owner；运行角色只授精确 RPC |
| 角色 | 迁移引用 anon/authenticated/service_role | 目标创建无登录兼容角色；运行账号不继承它们 |
| 扩展 | pgcrypto，用于摘要等 | PG17 目标显式安装；导出审计实际扩展依赖 |
| Auth | 未发现游戏业务调用 Supabase Auth | 仍使用受信游戏服务器 Bearer；不是玩家身份 JWT 接入 |
| Storage / Realtime / Edge Functions | 未发现当前后端运行链使用 | 不迁移这些托管服务；实际源出现依赖则工具拒绝继续 |
| 触发器 | 不可变奖励配置、在线结算 outbox | 完整 schema+data 恢复；避免先建触发器再导入导致重发 |
| 支付 | 本地只有预留接口；purchase_enabled=0 | 强制 PAYMENT_MODE=test；未接真实收款/支付回调 |

源码审计不能证明云端不存在人工添加的对象。导出工具检查函数、触发器、角色、表、约束、索引、扩展、RLS policy、跨 schema 依赖及 sequence；遇到未覆盖内容停止，不自行删除或绕过。

## 本次适配

1. 默认仍为 Supabase。通过 `FISHING_DATABASE_BACKEND=postgres` 和 libpq service/独立密码文件选择 ECS 测试数据库；不做隐式双写、故障回退或写操作自动重试。
2. 运行账号 `goufayu_app` 无超级权限、owner 成员资格、直接表读写、建库/建表/TEMP 权限；每条 RPC 同事务验证权限，提交成功后才返回业务结果。DDL 使用 `goufayu_migrator` 显式切换 `goufayu_owner`。
3. HTTP 保留档案/奖励/检查点格式，补入存档路由，限制请求体、线程和请求时限。`/ready` 必须认证并探测真实数据库。数据库失败返回 503，不构造空档案。
4. 属性 CSV 原固定 38 字段限制改为按已启用字段校验，目前 97 字段。新增目标迁移把旧 `tower_attack_interval > 0` 约束改为 `>= 0`，匹配当前“减少量”配置；不重写既有数值。
5. 历史 16 个迁移原文及哈希保留；额外兼容迁移与权限收紧单独记录。源恢复后使用独立 reconcile 流程，不重新执行会删旧表的完整历史链。
6. 存档 pending 未完成时拒绝返回成功旧档；服务恢复按数据库回执和版本重新结算。UI 图标 CSV 不参与结算 bundle，保持类型检查；发布生成不修改正在使用的游戏配置。

## 验收范围与限制

本地真实 PG17.11 的合成账号测试覆盖读写、重新创建应用后读取、玩家隔离、并发重复奖励、提交后响应丢失重试、旧存档与新永久物品、在线 outbox 恢复和独立永久库存、运行账号权限拒绝、HTTP 断库 503。独立恢复对比表行数/内容指纹、结构、函数和触发器。

另运行真实 HTTP 进程的 9 项验收，并重新启动独立后端进程读取原合成账号，确认存档保留。汇总见 `server/aliyun/validation/local_20260919.json`；记录不含真实账号或秘密。

本地 Python 为 3.13，Lua 为 5.4；部署目标选择 Alibaba Linux 官方 Python 3.11 独立 venv。云端 Python/Lua、systemd、Podman 客户端桥接、Nginx/HTTPS、真实玩家游戏联调和异地备份恢复仍需在服务器验证。它们不能由本地通过推断已完成。

全局 Bearer 仅供受信游戏服务器；RPC 可以代玩家结算，不能把 token 放到 Panorama/玩家客户端。现有 `faith_cheat` 等测试命令保持原业务，本轮不是生产支付/多租户安全上线。

原发奖与在线结算存在不同锁顺序；极端交错可能触发 PostgreSQL 死锁检测。适配不自动重复写，返回可重试错误，调用方必须用原幂等 ID 重试。此次不改奖励计算和既有经济逻辑。

实际部署、SSH 密钥、备份与切换/回退命令见 [测试迁移手册](ALIYUN_TEST_MIGRATION.md)。
