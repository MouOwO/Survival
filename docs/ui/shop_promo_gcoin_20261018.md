# 商城促销原价与 G币显示

现有促销商品在现价右侧显示 `现价 × 1.5` 的灰色划线原价，字号为 18px，现价为 30px。例如 `3400 G币` 对应 `5100 G币`，奇数价格保留 `.5`。同一促销商品在首页和全部商品中也使用相同展示；非促销商品、充值及月卡不会因为这项展示逻辑新增折扣。

`ReferencePrice` 只计算展示值，复用已有促销分组资格，不更改商品原始 `original_*` 字段、实际售价、筛选规则或购买请求。价格组合扩大到 325px 并保持原列中心，给现价、原价和购买按钮留出间隔。

游戏玩家可见的货币名统一为 **G币**，覆盖商城余额、筛选、价格、购买确认、充值、奖励提示和回执。共享显示函数兼容旧目录和旧订单中的 U币文案。内部 `u_coin` 协议键、SKU、余额、1元兑换100代币的汇率及历史交易快照继续原样使用。原素材包的栅格文字记录和历史发布资料保留原始证据。

支付托管网页仅在浏览器局部转换显示标题；服务端订单及 API 返回值不受影响。独立支付候选只包含 `payment_backend/service.py` 的网页显示补丁，其余 75 个文件与当前线上基线一致，不执行 SQL 或重发目录。发布与验证结果见 `validation/20261018/shop_promo_gcoin.json`。

## 验证

- `node --test tools/tests/shop_promotion_reference_price.test.cjs`：促销资格、1.5倍原价、小字号划线、动态刷新、请求字段保持原样。
- `node --test --test-name-pattern="Legacy U-coin" tools/tests/ucoin_checkout.test.cjs`：旧名称在界面显示为 G币，原始对象和支付请求不变。
- `python -B -X utf8 tools/build_item_resources.py --check`：单一资源表与生成视图一致。
- `node tools/shop_promo_gcoin_20261018/preview.cjs --native-aliases "output/shop_icon_quality_20261017/native/manifest.json;output/daily_native_icons_20261017/manifest.json"`
- `node tools/shop_promo_gcoin_20261018/capture.cjs`：基于实际 XML、JS、CSS 和本机正式目录，检查 1920×1080、1280×720 的价格比例、字体、划线及按钮间隔，禁止发起交易。
- `tools/shop_promo_gcoin_20261018/compile.ps1`：只编译本次 11 个脚本和 1 个样式资源。

截图是隔离样例预览，保存在 `output/shop_promo_gcoin_20261018`。当前未取得有效前台游戏截图，实机显示仍需游戏内核对。

修改前的商城测试中存在关闭状态和旧布局断言失败，已在修改前快照复现；本次独立候选的 8 项促销、素材和旧名称兼容检查通过。提交仅包含本次修改，工作区其他功能修改和实际游戏用的完整编译结果继续保留。
