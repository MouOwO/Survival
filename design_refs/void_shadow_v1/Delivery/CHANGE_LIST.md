# 虚空之影 V1 修改文件

只列本轮接入范围；项目中其他既有修改不属于此清单。完整路径、原图 SHA 和编译 SHA 见 [CHANGE_LIST.json](CHANGE_LIST.json)。

| 生产源码 | 用途 |
| --- | --- |
| `panorama/src/layout/custom_game/archive.xml` | 接入本页样式、配置和渲染器，沿用现有存档布局与控制器。 |
| `panorama/src/scripts/custom_game/archive_180de7e38b_titles_compact_v6.js` | 在现有完整快照组装、分类切换、打开关闭和销毁处增加局部视图钩子。 |
| `panorama/src/scripts/custom_game/archive_void_v1_data.js` | 从真实 CSV 导出的只读名称、上限和分类，关联包内坐标及正式资产。 |
| `panorama/src/scripts/custom_game/archive_void_v1.js` | 虚空之影的动态组件、计数语义、筛选、原 Tooltip、统一缩放及生命周期。 |
| `panorama/src/styles/custom_game/archive_void_v1.css` | 本页局部材质和文本样式，离开本页恢复原存档窗口。 |
| `panorama/src/layout/custom_game/archive_void_v1_assets.xml` | 38 张正式 PNG 的独立资源依赖，用于精确编译。 |

新增 PNG 位于 `panorama/src/images/custom_game/void_shadow_v1/`，共 38 张：`backgrounds/` 4 张、`common/` 11 张、`items/virtual_01.png` 至 `virtual_23.png` 23 张。全部直接复制附件 `assets`，未重绘。编译输出共 44 个：38 个 `.vtex_c`、3 个 `.vjs_c`、1 个 `.vcss_c` 和 2 个 `.vxml_c`，位于对应的 `panorama/images`、`scripts`、`styles`、`layout` 运行目录；相同源文件同步到 Content authoring 目录。

辅助工具归于 `tools/void_shadow_v1/`：素材导入、首次接线、精确编译、游戏窗口与截图、本地组件预览及截图检查。组件包、参考图、数据审查、SHA 记录、前后截图、浏览器报告与接入前检查点归于 `design_refs/void_shadow_v1/`，验收入口为本目录 README。

没有修改服务器保存服务、研究或战斗逻辑、真实 CSV 业务值、系统字体配置和其他页面样式。
