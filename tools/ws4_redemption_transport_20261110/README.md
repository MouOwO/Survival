# WS4 兑换码传输协议修复

现版游戏的所有 `/v1/archive/command` 请求都附带 `response_capabilities`。旧兑换入口严格拒绝这个顶层字段，返回 `redeem_request_invalid`，在调用数据库前中断，因此四档金色券虽然登记正确，仍没有领取记录。用户最终确认点击后无成功/失败提示；此前“显示成功”的回答已由用户更正，不作为真实发奖证据。

只修复 `server/archive_backend/redemption_codes.py`：允许三个既有布尔能力开关，不把能力开关传入 RPC，不接受客户端奖励、数量或内部账号字段。身份、真实码归一化、限领、冻结奖励和提交幂等不变。客户端没有改动，也不重新生成或登记四个码。

正式入口 `deploy.py` 默认只输出无网络计划。使用不可变源码/operator 提交按 `audit → prepare → probe → activate → verify` 执行；保留已验证 daily-refs 部署的连接排空、watchdog 和精确回退。独立复制现役完整版本，仅更新一个 Python 文件；不改 SQL、目录配置或支付、认证服务。API 启动仍执行原有同步策略，不宣称重启绝对零数据库写入。

准备版本的 `probe.py` 先复现父版本拒绝现版请求，再用真实 Linux Python/Lua 运行四档 × 四种能力组合共 16 个向量，检查精确券数、普通券保持、重试单次提交和 11 个非法输入。RPC 为隔离内存替身，不兑换真人码、不消耗券；这些结果不代表真人到账或原生提示观察通过。

成本：能力字段最多 3 项，校验时间/空间 O(1)，无初始化索引或稳定轮询；每次真实兑换沿用一次 prepare 与一次 commit RPC，冲突恢复仍最多 4 次。没有新增计时器、HTTP 或数据库查询。

本地诊断和测试位于树外 `D:/Survival_本地工具/runs/20261110_gold_ticket_delivery_diag01`。原登记的生产 apply 不重试、不覆盖旧回执；客户端沿用 2026110902 / Steam manifest `6445398778833066003`。

实际已完成：101 项隔离回归，服务器 16 个真实 Linux/Lua 向量与 11 个非法输入，独立激活/verify。现役后台为 `20261110-ws4-redemption-transport-ae3e77c24300`；只切换 WS4 API，支付/登录服务保持，136码及旧132项定义保持。真实玩家重试反馈待回报，详见[真实回执与边界](../../docs/knowledge_base/evidence/redemption_transport_20261110.md)。
