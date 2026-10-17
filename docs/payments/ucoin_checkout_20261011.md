# U 币商品人民币直购 · 2026-10-11

2026-10-17 起，当前实际商品售价统一减半，兑换比例为 **1 元人民币 = 100 U 币**，金额以人民币整数分存储，`amount_fen = u_coin_price`。例如红色抽奖券 1200→600 U 币，对应 ¥6.00。充值不打折，每份1元到账100 U 币。新目录只接受100的比例；历史订单仍采用创建时冻结的1000或100比例，原金额和奖励不变。商品列表只显示代币价格，结算确认继续显示实际人民币金额。

下文为2026-10-11的接入记录；当时的报价比例和部署编号仅用于历史追溯。现行发布及验证记录见 [商城半价同步](shop_half_price_20261017.md)。

商城将同 SKU 的余额商品和支付商品合并展示。U 币商品使用服务端支付目录的报价和可购买状态，余额不足不会阻止人民币直购；积分、商城金币商品继续使用原余额兑换。确认页同时显示 U 币售价、人民币实付及汇率；购买按钮只显示支付方式和 U 币，避免长文字溢出。

订单请求只提交 SKU 和支付渠道，游戏服务补充可信账号及对局身份。客户端不能指定金额或汇率。订单保存当时的人民币金额、U 币价格、限购标记和完整奖励快照，后续改价或下架不改变已有订单。沿用原发货、永久物品限购、抽奖券重复购买和到账刷新流程。异常报价禁止下单；已有订单仍可查询或取消。

正式配置继续维护在 `data/csv/商城兑换系统/commerce_products.csv`、`commerce_rewards.csv`，通过 `ucoin_catalog.py` 合入支付目录。没有把预览价格或数量写入存档。原人民币商品仍保留，其服务器报价也按同一汇率提供 U 币展示。

## 发布结果

- 支付服务器：`47.110.238.248`；当前版本：`/opt/goufayu/payments/20261011-payment02`。
- 用户明确授权上传发布包、商品目录并备份更新支付服务后完成发布。
- 发布包：`output/payment_release/20261011-payment02.tar.gz`，SHA256 `4465b2f451cf2efd2fa68d5847fbbd849bd53d67be382b04e49cd9bd862b9f34`。
- 商品目录哈希：`6a9bb5d72b9ce943dbb503553e8eda1ac7d246487b4d50619d88d974a99cac1d`。
- 本地数据库备份：`/var/backups/goufayu-payment/game-and-payments-20261011T013750Z.dump`。没有异地复制。
- 只重启支付服务；游戏 API 进程未变且健康。
- 现有权限维持 1 个支付测试账号。没有扩展为全部玩家。
- 发布前后历史订单均为已关闭 9 笔、已发货 3 笔；本轮没有创建真实支付网关订单。
- 发布脚本先验证完整性和正式基础配置，再运行全部回滚的数据库测试；失败时按目录哈希恢复旧目录及代码。新增 SKU 回退时只禁用，保留可能关联的订单。后续他人发布不会被覆盖。

## 验证范围

- 60 项 Python 单元与回滚流程测试通过。
- 10 项 U 币购买与 V10 商城交互测试，以及 5 个既有支付/商城 Node 回归脚本通过。
- Lua 支付接口测试通过：可信身份、过滤客户端价格、服务器报价透传、缓存、到账刷新。
- 3 个 UI JS 已同步 Content 工程并编译为游戏 `.vjs_c`；最终按钮调整再次编译 `payment_test.js`。
- 服务端真实 PostgreSQL 回滚测试验证全部 24 件 U 币商品的金额/奖励/限购、未付款无发货、待付款订单复用、不可变快照、错误金额拒绝、重复发货安全及旧余额持有标记兼容。随机测试账号及订单全部回滚。
- 内网 HTTP 和正式 HTTPS 的真实商品目录均核对通过：全部 U 币金额、汇率、奖励及目录哈希一致，微信和支付宝渠道可用。
- 本地生产组件组装截图：`output/ucoin_checkout/wechat_confirmation.png`、`alipay_confirmation.png`。使用正式商品配置和显式样例持有数量，未连接账号或支付网关。
- 尚未执行本轮真实付款、退款或游戏内扫码验收。截图是浏览器对现有 Panorama 组件的组装预览，不是新一轮游戏截图。

## 修改入口与恢复

核心服务端文件：`server/payment_backend/ucoin_catalog.py`、`csv_catalog.py`、`sync_catalog.py`、`service.py`、`upgrade_ucoin_shop.py`。测试为 `test_ucoin_catalog.py`、`test_ucoin_service.py`、`test_ucoin_database.py`、`test_upgrade_ucoin_shop.py`。

前端：`panorama/src/scripts/custom_game/commerce_remaining_5d5c1152eb.js`、`common/commerce_components.js`、`payment_test.js`，以及对应游戏编译资源。Lua 生产接口未改，扩展了 `scripts/vscripts/tests/test_payment_service.lua` 验证新的报价字段。

构建工具：`tools/build_payment_release.py`、`build_payment_ui.ps1`、`sync_payment_shop.ps1`；回归测试新增 `tools/tests/ucoin_checkout.test.cjs`，既有商城/支付夹具适配现有 V10 外壳。`tools/menus_v10/compile.ps1` 增加可选报告路径，避免覆盖其他 UI 交付记录。

详细记录在 `validation/20261011/ucoin_checkout.json`，编译备份见其 `compile_backup`。构建和预览过程文件保存在 `output/ucoin_checkout/`。本轮没有进行 Git 提交或推送，保留用户原有工作区修改。后续如要求提交，按项目规定执行 stash → pull → pop → commit → push。
