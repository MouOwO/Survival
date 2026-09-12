# 商城显示组件的接入边界

当前没有注册支付适配器，也没有新增商城玩家入口。现有金币／木材局内商店保持原样。组件挂载于测试 HUD 的 `GameUI.CustomUIConfig().SurvivalCommerceView`。

## 等待现有业务提供的数据

- `SetCatalog({products, bundles, notice, balance_text})`：真实商品／礼包目录；名称 `name`、效果 `effect`、`image` 或公共资源 `artId`。
- `prices`：`[{amount: 数值, currencyName: 实际币种名称}]`。缺少可信价格时禁止购买。礼包 `items` 包含真实名称、图片、数量与效果。
- `purchasable`、`min_quantity`、`max_quantity`、`payment_methods: [{id,name,enabled}]` 由业务提供，不从确认图提取。
- `SetAdapter({createOrder(request, callback)})`：请求仅包含 `product_id`、`quantity`、`payment_method_id`，不提交客户端价格。
- 创建订单回调返回 `order_id`、`status`、`sequence`、`amount_text`、`payment_name`、`qr_image`、`expires_text`、`error`。`UpdateOrder` 接收同一订单的后续状态。

这只是显示适配契约，不是本轮新增的支付协议。需要实际后端确认字段后再映射；不得据此改动商品价格、支付方式或发奖条件。

## 已实现的 UI 防护

请求中禁止重复提交；关闭重开不会创建第二笔待处理订单；创建回调只消费一次。不同订单、过旧序号被忽略；过期和完成状态不会回退到等待支付。确认窗口不会发奖。

二维码只显示接口返回的 `qr_image`，没有使用交接包示例二维码。缺少二维码显示等待状态；失败、过期、完成时不再展示可扫码图片。实际支付金额以订单返回为准。

## 验证程度

商城四列两行、礼包两列两行、订单不可购买空状态已在 Dota 2 中截图。商品黑色悬停层、真实价格、支付方式和二维码状态只完成代码与组件模拟测试，缺少实际商品/支付接口，不能标记为实机业务验证。测试数据只存在 `test_commerce.cjs`，不会部署进游戏。
