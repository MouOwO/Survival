# 生存商店紧凑布局

正式窗口为 604×806（原宽 1208），商品图标 90×90，名称和效果进入原 tooltip。图标下仅显示非零金币/木材的资源图标与数值。右上角库存为黑色 13px 数字，无背景和“库存”前缀。真实补货库存优先；无补货库存、购买上限大于 1 的商品显示服务端 purchase_limit 减 owned_count，表示剩余可购买次数，不创建虚假的补货库存。

去掉悬停遮罩和购买按钮，保留 tooltip、右键购买、研究入口原有操作。页签只保留商店和挑战，选中显示地图抽奖同款 tab_glow；刷新按钮移除。

左上角导航增加与商城同款购物袋图标的“生存商店”。依据 SurvivalShopUnlocks.shop 显示灰态和禁用状态，原来的木材图标商店入口隐藏。

成长之剑统一使用实际物品的 item_broadsword 图标。装备使用各自配置的原生彩色图标；知识之书和超级知识之书使用 shop_compact_v1 下的红、蓝书籍图标，图片及完整生成提示词见该目录 README.md。

验证：node tools/test_shop_presentation.cjs；node tools/test_lottery_updates.cjs。
发布：pwsh -NoProfile -File tools/compile_shop_compact.ps1。
