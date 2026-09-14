# 生存商店原创图集接入

本版已将确认的三张 imagegen 图集接入正式 Panorama 源码并编译到游戏资源。原始图集与提示词位于 `panorama/src/images/custom_game/shop_v2/`，原图集保留；后续统一图标更新通过规则分图生成原生物品栏贴图，没有重新生成或改色。

- 商店保持 604×806 设计尺寸，由左侧滑入；关闭后退出输入和窗口层栈，不使用全屏遮罩。
- 单元为 90×90，只显示自制图标，以及右下角白字黑色描边库存。限购可重复购买物品显示剩余购买次数；实际补货库存继续采用服务器 stock/stock_max。
- 单元不生成消耗行，tooltip 仅显示图标、名称、非零金币/木材消耗；右键购买及服务端校验沿用现有逻辑。
- 商店、挑战、自定义物品展示共用 SurvivalItemArt。成长之剑、霜之剑刃、极寒之刃、冰火裁决、深渊审判均映射到自制图集；后两组分别将 7/11 个正式等级映射到 5 个外观阶段。
- 后续统一图标更新已覆盖原生 Dota 物品栏 AbilityTextureName，商店与物品栏共同使用 images/items/survival_shop_v2 下的单元贴图；装备服务同时采用同一映射。

验证：`node tools/test_shop_presentation.cjs`、`node tools/test_shop_v2_tooltip.cjs`；编译：`powershell -NoProfile -ExecutionPolicy Bypass -File tools/compile_shop_v2.ps1`。编译脚本会将指定源码同步至引擎 content 目录并调用 resourcecompiler。

浏览器效果图位于 `art/ui/development/survival_shop_v2_preview/`，属于效果预览，不作为原生游戏实测证据。正式游戏内动画、字体和层级仍需进局目视确认。
