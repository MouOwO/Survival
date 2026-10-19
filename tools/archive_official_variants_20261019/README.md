# 存档界面 · 五套官方 UI 方案

打开 `design_refs/archive_official_variants_20261019/index.html`。五个主题可直接切换；支持积分道具、通关存档、搜索、解锁筛选、选择详情及仅图标悬停提示。其他分类保留真实目录，用空状态展示布局。本轮是设计预览，没有写入玩家数据，也没有替换游戏中的存档界面。

| 编号 | 主题 | 官方材质 |
| --- | --- | --- |
| 01 | 经典灰蓝 | Dota Dashboard 拉丝顶栏、灰色石板、Reborn 提示框 |
| 02 | 倾天史册 | Crownfall 棕色画板、金色标签与几何横饰 |
| 03 | 黑金珍藏 | Dota Plus 黑石纹、暖金横幅、九宫格金色选中框 |
| 04 | 冰蓝银辉 | Crownfall 雪山横幅、Frostivus 冰霜九宫格边框 |
| 05 | 暮紫典藏 | Dark Carnival 紫色木纹、铜饰九宫格窗口边框 |

布局参考 [GW2 英雄面板](https://wiki.guildwars2.com/wiki/Hero_panel)、[成就面板](https://wiki.guildwars2.com/wiki/Achievement) 和 [装备面板](https://wiki.guildwars2.com/wiki/Equipment)：窄图标栏、分组目录、主内容区，并将装备页右侧属性栏适配为道具详情。没有使用 GW2 图片制作成品。

道具名称、效果、重复转换积分来自项目静态配置，来源记录在 `fixture.json`。解锁状态是明确的展示样例，不代表任何玩家账号。积分道具以解锁呈现，没有拥有数量。图标、底图、装饰与边框均读取已安装 Dota 的官方图册原始导出图；构建时验证 SHA-256，输出 `assets.json` 记录官方 URI 和哈希。

```powershell
node tools/archive_official_variants_20261019/build.cjs
node tools/archive_official_variants_20261019/preview.cjs
```

先前导出的官方图册需要位于 `design_refs/official_ui_catalog_20261019/`。如果缺失，先运行 `node tools/official_ui_catalog_20261019/build.cjs all`。

生成页面和官方图片在 `design_refs/archive_official_variants_20261019/`，浏览器截图与检查报告在 `output/archive_official_variants_20261019/preview/`。这些生成文件不加入 Git；本目录保存可复现的方案源码。预览使用隔离的本地 Chrome，无外部资源请求。截图检查覆盖 1600×900 和 1280×720；浏览器预览不等同于 Panorama 实机渲染。
