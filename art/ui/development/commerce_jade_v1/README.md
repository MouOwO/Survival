# 商城材质源 · B17 + L21 + T23

运行 PNG 在 ../../sources/custom_game/commerce_jade_v1/；详细映射、尺寸和 SHA256 在项目根 design_refs/shop_ui_12h/Delivery/resources.json。

source/ 保存 27 个可编辑 SVG，已选用最佳候选版本，不指向最后一次实验。component_recipes.json 保存 6 个未改动的 CSS 导出配方，山水底图为 scenery.png。配方中的原 ../assets/scenery.png 对应此山水源。sword_light/hover 和 gift_light/hover 是原参考包 PNG 图标，源就是运行 PNG，未虚构 SVG。

文字、价格、描述、货币数值没有进入材质图片。75 个 shadows/ PNG 来自原商品透明度投影，生成程序为 tools/shop_ui_12h/assets.cjs；原商品图未修改。新图片需要追加编译依赖，不能只写入 JS 路径。

编辑 SVG 后先在候选中导出和组装比较，保留改善的版本再替换主 PNG。脚本 experiment.cjs / real-experiments.cjs 是本轮生成方式；最终 assets.cjs 只采用明确选择的 B17、L21，而不是最新目录。

完整游戏接入、尺寸/层级、检查与恢复步骤见 design_refs/shop_ui_12h/Integration.md。生产可恢复快照为 work/checkpoints/production_best；本目录是编辑源，不是另一套自动生效的皮肤。
