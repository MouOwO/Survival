# 统一商店 / 物品栏图标

来自已确认的 `../../custom_game/shop_v2/` imagegen 图集。仅进行规则网格分图打包，未重新绘制或改色；完整生成提示词保留在原图集目录的 `PROMPTS.md`。

商店、tooltip 和原生物品栏都使用此目录的同一张单元图。原生物品 `AbilityTextureName` 为 `survival_shop_v2/<图集>_<序号>`。装备服务创建、接纳材料时也采用同一映射，避免写回旧官方图标。

生成流程：

1. `node tools/build_inventory_icon_manifest.cjs`（读取正式商店图标解析器，生成 KV / Lua / JSON 映射）。
2. `powershell -File tools/package_inventory_original_icons.ps1`（规则网格分图）。
3. `powershell -File tools/compile_inventory_original_icons.ps1`（同步 content 与编译）。
4. `node tools/test_inventory_original_icons.cjs`（核对各级装备、原生物品定义和编译贴图）。

成长之剑、霜之剑刃、极寒之刃各有五张进阶图；冰火裁决与深渊审判按现有等级映射到五个外观阶段。手套、灼热之刃、铁甲、熔火装备各等级复用对应装备图。切换贴图不会改变物品数值、合成规则和等级。
