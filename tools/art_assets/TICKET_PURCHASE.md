# 购买抽奖券 UI 与模拟流程完成

2026-09-13：复用商城的订单确认、付款码、状态预览和计时器生命周期；不创建新的一套支付组件。

## 行为
- 抽奖右上角加号 → 当前奖池抽奖券订单确认 → 数量与模拟金额 → 模拟付款方式 → 本地二维码 → 返回原抽奖页面。
- 关闭、取消保留原奖池，不打开额外商城页；同一确认窗不重复创建订单。
- 数据来自当前奖池名称和券名；模拟单价 1 U币、上限 99 放在 shop_preview_v1/data.js 的 ticketPreview 中，只用于演示，未写入真实配置。
- 模拟成功不增加抽奖券，不调用 HTTP 或游戏服务端，不扣款。

## 修改位置
- art/ui/development/shop_preview_v1/data.js：集中 ticketProduct、ticketPreview。
- art/ui/development/shop_preview_v1/view.js：OpenTicketPurchase、按来源返回、共享确认页与二维码页、复用券图轮廓遮罩。
- tools/patch_lottery_ticket_purchase.cjs：抽奖入口接入；prepare.cjs 自动应用。
- panorama/src/scripts/custom_game/commerce_remaining_5d5c1152eb.js、lottery_ui_remaining_5d5c1152eb.js 及 candidate 同步并编译。
- shop_preview_v1/test.cjs：增加券商品切换、数量、重复打开、订单取消、过期重试验证。

## 验证
自动测试通过：商城原流程及抽奖券订单、六种模拟状态、重复提交保护、关闭清理，无网络/服务端调用。
实机：1768×992 游戏客户端（1920×1080 桌面截图），从入口进入确认页，数量 1→2、金额同步 1→2，付款码、模拟成功、返回原地图奖池、重新打开归零订单状态已验证。券数前后 1000→1000。
截图：ticket_order_final.png、ticket_quantity_two.png、ticket_qr_waiting.png、ticket_simulated_success.png、ticket_returned.png。未录制视频。其他奖池切换已自动测试，未逐池进行游戏内截图。

后续真实数据接入位置：data.js 的商品构造与订单来源；本轮未确定支付协议或真实售价。
