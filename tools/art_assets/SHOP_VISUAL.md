# 商店样式对接

生存商店复用 RemainingHandoff 的窗口九宫格、页签端头、关闭叉号、按钮和商品卡九宫格，商品卡增加名称、实际金币/木材价格、悬停效果说明和购买入口，沿用 SurvivalShop 的 purchase、库存、科技条件及右键自动研究流程。

新增作者文件：art/ui/development/remaining_ui_handoff_v1/shop_visual.js、shop_visual.css，prepare.cjs 已接入。tools/patch_shop_visual.cjs 将视觉调用插入现有控制器，不修改支付、解锁或奖励规则。当前正式版本 remaining_5d5c1152eb.js/css、shop_remaining_5d5c1152eb.js 已同步。

公共组件 common/ui_components.js 的 PriceLabel：U币显示数值与已有 currency_icon_64 图标，裁去图标透明留边；积分保持文本。版本号升为 1.0.2，避免初始化保护跳过新实现。普通商品与礼包价格均上移 8 个设计像素，分别保留原布局宽度。奖品预览页签禁用缩放和按压变暗。

验证：tools/test_shop_presentation.cjs 加载实际版本化控制器和公共样式辅助脚本，验证原有解锁、模式、交易路由、余额不足、过期数据、关闭清理及币种显示区别；商城模拟测试与抽奖测试通过。正式根布局及最终公共组件/样式编译通过。

当前游戏截图仍显示热更新前的价格标签，未作为新样式验收通过。需重新载入地图加载新公共组件后，检查生存商店、商城价格及奖品预览的实际画面。没有执行真实购买或扣款。
