真实组件离线验收：`node tools/lottery_emerald_game_20261019/verify.cjs --run`。

脚本只写入 `output/lottery_emerald_game_20261019/qa`；Chrome profile、TEMP/TMP 均使用 D 盘项目目录。它装配实际 Panorama XML/JS/CSS，导出已安装的官方 VPK 纹理供浏览器显示，所有抽奖事件和回执仅在内存夹具中流转。不会操作游戏、账号、付款或存档，也不调用 Git 或编译器。

预览、电影传输、夹具、Chrome 控制和基线 SHA 均收录在本目录，不需要已有的旧任务 output 清单。依赖仓库通用 `tools/menus_v10/preview.cjs`、`tools/archive_v10/adapter.js`、`tools/vpk_inspect.cjs`，本机 Dota VPK 与 Chrome，以及纹理解码工具 Source2Viewer CLI。可通过 `SOURCE2VIEWER_CLI` 指向已安装的 CLI；默认使用此前下载的本机路径 `output/valley_decor_v2/source2viewer/Source2Viewer-CLI.exe`。Source2Viewer 是环境工具，不作为项目美术或提交二进制。

覆盖两种分辨率、四个原始奖池背景、移除 T10、原电影源码基线及原流程回归、冷打开/冷切池 revision、单抽和十连服务端格式结果、确认/再次、全屏结果、tooltip、未就绪/未知余额/免费单抽/失败回执，以及旧 XML 缺少 ZXDrawContent 的单独兼容样例。

`gameVerified:false` 表明全部截图属于离线组件预览，不能作为原生实机截图。旧 XML 样例移除两个 ZX 展示容器，并加入旧 footer 缩放祖先；它必须在补回容器后保持付费/免费居中、重复 Apply 不增节点，才算通过。

本轮正式接入要求：移除右侧 T10 装饰，各奖池保留原背景及原过场电影，结果页采用 R5 设计。备用背景只存入项目；`node tools/lottery_emerald_game_20261019/assets.cjs --check` 检查 JPEG 内容准确且没有运行引用。

部署由主线程按顺序执行：

1. `node tools/lottery_emerald_game_20261019/prepare_compile.cjs`
2. `./tools/lottery_emerald_game_20261019/compile.ps1 -CheckOnly`
3. `./tools/lottery_emerald_game_20261019/compile.ps1`

计划仅冻结本轮五份源码及电影基线。编译工具保留备份，失败还原，并检查 source/content/runtime hash 一致性。编译与真实游戏验收状态由主线程分别记录；本离线 QA 不预设实际游戏的可见窗口或部署结果。
