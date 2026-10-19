# 官方 UI 离线图册

入口为 `design_refs/official_ui_catalog_20261019/官方UI图册.html`。HTML 内嵌所有缩略图和索引，可单独打开；保留相邻 `assets/` 才能查看原始导出图。图库只读取安装包，不修改游戏 UI，不执行官方或自定义游戏脚本。

包含按用途筛选的官方原图、常用原生控件的浏览器交互示例、官方 CSS 原文、Panorama 复用代码和整个 `panorama/images/` 目录的路径索引。未预览资源明确显示为路径索引。缩略图是浏览用途的缩放；原图保留原始解码像素，SVG 保留原始解码文本。

在项目根目录运行：

```powershell
node tools/official_ui_catalog_20261019/build.cjs all
node tools/official_ui_catalog_20261019/verify.cjs
```

依赖 Node、已安装 Dota 2、Source2Viewer CLI，以及带 Pillow 的 Python。默认解码器为项目现有的 `output/valley_decor_v2/source2viewer/Source2Viewer-CLI.exe`；可用 `DOTA_UI_VIEWER` 指定其他安装。可用 `DOTA_UI_PYTHON` 指定 Python。原包位置由当前项目的游戏目录推导。

分步处理可用 `build.cjs extract`、`build.cjs decode`、`thumbnails.py`、`build.cjs build`。解码按不超过 64 MiB 的输入批次复制到独立临时目录，完成后校验并删除本工具创建的临时目录。中间文件和检查报告在 `output/official_ui_catalog_20261019/`；导出图册在 `design_refs/official_ui_catalog_20261019/`，均不提交到 Git。

浏览器示例与真实 Panorama 的排版、字体和状态渲染会有差别；复用时参考详情里的官方源码。图册选择只写浏览器本地存储，导出的 JSON 清单没有游戏副作用。
