# 支付数量契约

`POST /v1/payments/create` 允许可选 `quantity`，缺省为 1。必须是 JSON 整数 1–100；字符串、小数、布尔、null 均拒绝。不接受客户端单价、总价、汇率或奖励。

- `catalog.products[].amount_fen` / `u_coin_price` 仍是单价，另有 `unit_amount_fen`、`unit_u_coin_price`、`max_quantity`。
- 订单 `amount_fen` / `u_coin_price` 是实际总价，另有 `quantity`、`unit_amount_fen`、`unit_u_coin_price`；有折前价时另有 `unit_original_u_coin_price` 和总额 `original_u_coin_price`。
- 订单 `reward_lines` 和 `effects` 已按数量展开，客户端不得再乘一次。
- 实际数量受剩余限购、道具/属性容量及总价最多 1,000,000 分约束。VIP、限购 1、永久权益最多 1。30 天月卡每单最多 12 份（360 天），沿用现有续费规则。

同 SKU 旧订单数量或渠道不同时，返回 `ok:true` 的原订单及 `warning:"order_quantity_conflict"` 或 `"order_provider_conflict"`。恢复返回的真实数量、渠道、总价及二维码，不能改写旧单。冲突恢复不创建网关付款：created 原单可按恢复后的数量再次确认；pending 原单继续付款或取消后再选新数量。status/cancel 仍按所属账号鉴权。

新订单保存 reward.version=5、quantity、unit_amount_fen、unit_pricing；effects/items/components/有限权益天数为总奖励。旧 v1–v4 单据不改写，按一份兼容。旧四参/五参 RPC 仍可调用。回调必须匹配总金额、渠道和商户；发奖按快照一次提交。

迁移为 `server/payment_backend/upgrade_order_quantity.sql`，调用者持有事务，不含 COMMIT。先验证并回滚，再由既有发布流程备份后安装 SQL 能力并切换匹配 HTTP 源码。目前没有外网部署。

本地验证：

```
python tools/compact_checkout_20261015/test_quantity_http.py
python tools/compact_checkout_20261015/test_quantity_database.py
```

依赖沿用 `output/video_shop_20261015/deps`；数据库仅限隔离 `127.0.0.1:54627/survival_bundle_test`，不得用于生产。

发布工具：`server/payment_backend/upgrade_order_quantity.py`，只支持 `validate EXPECTED_CURRENT` / `activate EXPECTED_CURRENT`。基线必须是已审阅 payment01，候选必须为 payment02；同时核对两个 manifest、线上当前指针、b56e 商品目录和 dee53 存档包。validate 的迁移和真实 nonce 测试全部回滚，并比较 16 张业务表哈希；activate 备份后只安装新数量 SQL，使用有界锁，重启支付服务，保持游戏服务 PID。

发布包生成器只从 `output/payment_release/20261015-payment01/manifest.json` 复制 59 个原文件，替换 service 并新增 6 个文件。不运行通用全量 catalog 生成器，也不重放 bundle/monthly SQL。恢复失败不会覆盖第三方 current 版本，不会降级 v5 reader。离线安全回归：`python tools/compact_checkout_20261015/test_quantity_operator.py`。
