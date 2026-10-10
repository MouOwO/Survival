# 商城兑换与现金订单紫色弹窗迭代

## A01：真实确认流程统一紫色与金边

修改前逐字节备份 `commerce_wallet.js`、`payment_test.js` 至 `work/baseline/source`。原件 SHA256：

- Wallet：`E2FA6CF2F4A7CAD5B8A1228892215CF8C77C2294DFE37622D65EED51ABB73AAC`。
- Payment：`505B83E175A4BA27059FD2964EDB01352EC01E79A8BF25FAF49E5F461D7627E4`。

`commerce_wallet.js` 保留真实目录分片、商城币种/售价/余额、持有上限、同一未确认兑换 token 与购买事件；仅将原 760×700 确认窗、标题、按钮和正文改为紫色金边，改用 1920×1080 缩放参考并保留 ModalShell 的关闭/ESC。服务端多行说明转为经过转义的 `<br>`，避免普通 white-space 合并段落。

`payment_test.js` 保留原 960×740 商品确认、支付渠道、pending 订单不可变金额/奖励、可信备用付款地址、到账结果和存档前后值。二维码容器与原二进制黑白模块继续保持白底；窗框、付款方式、状态和所有动作按钮改为紫色金边。付款渠道图仅隐藏旧蓝色装饰，未删除业务按钮。

生命周期新增 deleted owner 检查，超时/结果/tick/旧 API 在完整原生面板删除后不查询已删除子树；第一次热重载遇到旧版本 Dispose 的原生删除异常时只恢复这一种异常，其余异常继续抛出。未新增交易调用或修改事件 payload。

活动 HUD 仅新增 `common/checkout_purple.css` include；独立 `payment_test.xml` 由 root 同步新增同一 CSS include。A01 具名源快照位于 `work/checkpoints/checkout_purple_a01`。

本地验证：新增 `tools/purple_ui_10h/checkout_verify.cjs` 装配真实 HUD/payment XML，运行实际 U/R、层管理和两个 controller，全部网络与外部浏览器调用均为本地记录器。覆盖真实余额、6800 U币兑换、777分现金金额、完整奖励和权益、目录修改/下架仍保留既有 pending 金额/奖励、29×29 黑白二维码、到账 before→after、显式才创建/兑换/打开备用页、防重、未确认 token 热重载、disabled 及 ESC、整棵 root 原生删除后的旧事件/计时器与两遍重载无重复订阅。PASS。

现有 `test_commerce_wallet.cjs`、`test_payment_ui.cjs`、`test_payment_catalog_cache.cjs` PASS；两个生产 JS `node --check` PASS。无实际扣款、兑换、付款页访问或订单创建。

额外读取并运行 `test_payment_original_shell.cjs` 失败于旧 harness 未载入 `ReferenceWindows.Apply`。用逐字节备份的原 payment controller 在相同 harness 中复核，得到同一失败；该测试还固定断言已被公共组件替代的 `_rhFrame`，未改测试伪造通过。实际 XML/U/R 的新 strict-native 回归覆盖此处 late helper/窗框/关闭与交易安全行为。

只读实看 `work/captures_checkout_p01` 的 1080 现金 normal/pending/receipt、钱包 normal，以及 720 现金 pending/钱包 disabled：紫金一致，段落、商品金额/奖励、QR、三按钮、到账存档前后值与状态完整，没有残留青蓝或按钮越框。此预览为活动 141 依赖/真实 Checkout API 与服务器结果的本地 fixture；QR 明确为不可付款布局矩阵。全部 1080/720 截图 ready=true、0missing、0errors；现金四状态和钱包 normal/pending/disabled 都没有 create/purchase。钱包 receipt 为显式本地 mock 兑换结果展示，有一条被本地捕获的 purchase，没有实际交易。

最终四尺寸验收：`work/qa/paid_checkout_p01_full_body_report.json` 与 `wallet_checkout_p01_report.json`，1280×720、1920×1080、2560×1440、2560×1080 × normal/pending/receipt/disabled，共 32 cases 全 PASS。现金增强实际子组件断言包含 PaymentDescription、PaymentValues、PaymentRewardCopy、title/price/QR/footer/status/hint，均在窗内；0脚本错、0缺图。现金所有状态 create=0；钱包 receipt 每案例为显式本地 fixture 的 purchase=1，其他状态 purchase=0，无外发。截图按真实付款目录均为 single 商品，没有在浏览器预览虚构 bundle；777分组合只用于纯本地 controller 回归核对未来/既有组合处理能力。
