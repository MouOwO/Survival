# V10 存档组件接入交付

已接入当前 `archive.xml` 和游戏运行资源。固定外壳复用一套 `ArchiveV10Canvas`，使用组件包原 PNG、原坐标和项目已注册的同源思源黑体；切换分类仅更新右侧内容、筛选文案和侧栏选中态。

2026-10-10 后续修缮：实机检查发现，Tooltip 的原生 `Image` 即使容器已经按九宫格切片放大，内部绘图仍保留比例，造成底图只显示在居中的小块区域。最终方案将同一批原PNG用于 `Panel` 背景，明确设置 `backgroundSize: 100% 100%`，再用裁剪容器完成九宫格；底图、边框和阴影分别固定8／10／32像素边角，未改素材像素。最终Panel方案已通过浏览器检查及原生编译；当前游戏窗口最小化／处于后台，**最终Tooltip原生显示效果尚未确认，不能称为最终实机验收通过**。浏览器前后对照和专项证据位于 `../work/nine_slice/`，其截图不是游戏内截图，需与最终源码哈希及验收状态对应阅读。

普通图标补上等比显示规则；无尽徽记和称号按完整组件适配，保留子环及多层称号的原始比例、位置和变换。另已实现35项正式装备的原生图标绑定：12件神兵碎片、9件存档神器、14件积分装备；保留已确认虚空之影原包及没有准确原生对应的项目图。修复战鬼双刃实际失效的旧资源路径，魔头之命按256×170显示区读取，不把256×256填充存储误作方形。正式ID与装备属性未变。逐项映射、原资源证据和验证说明见 [ICON_IMPLEMENTATION.md](ICON_IMPLEMENTATION.md)，其余分类来源及重复映射审计见 [ICON_AUDIT.md](ICON_AUDIT.md)。

## 完成内容

- 16 个参考分类全部接入同一外壳；保留原有星悦积分和称号入口。
- 虚空之影采用当前正式配置和原图标映射，首屏 8＋8＋7；新增条目没有 23 项容量限制。
- 各分类复用方形图标、右上角独立数字、下方名称、筛选和 Tooltip。数量固定右侧锚点；零值、未知、实际容量、成就目标、等级和波次按分类区分。
- 原福利／建筑升级、三种抽奖、神兵晋升、称号穿戴／卸下和原快照处理保留。未修改 CSV、服务端结算、玩家存档、主 HUD、生存商店或支付。
- 原 `shop` 存档目录未启用，保留固定入口并显示明确本地空态，点击、重开、刷新均不向服务端请求禁用分类。
- 打开时调用原钱包的只读目录刷新，余额未确认时显示「—」；类别切换和重复快照不重复刷新。
- 长 Tooltip 按正文自然高度展开，超长内容滚动；越界翻侧，阴影不截获图标点击。鼠标进入 Tooltip 可继续阅读，离开后延迟关闭，换分类立即关闭。
- 重新打开窗口及接管旧控制器保留的网格等公共面板时清理失效样式缓存，避免旧初始化把网格变回1000像素宽而第八列裁剪。回归覆盖同一原生网格被旧初始化实际改写后，V10恢复0坐标、1113×669和绝对排布。
- Tooltip三层切片使用原PNG的Panel背景和裁剪，解决原生Image内部等比绘图与切片尺寸不一致的问题；最终游戏显示仍待前台验收。
- 35项装备原生图源均已在本机VPK核实存在，34张不同原纹理逐张解码，并核对PNG实际尺寸与绑定显示区；只调整显示，不改正式配置。
- 旧紫色装饰不再覆盖 V10 单元；相同内容的 1,000 次快照修订不重建卡片、不重写样式、不重算适配。

## 修改清单

| 文件／目录 | 说明 |
| --- | --- |
| `panorama/src/layout/custom_game/archive.xml` | 接入 V10 数据、语义、渲染器和样式，继续加载原业务控制器。 |
| `panorama/src/scripts/custom_game/archive_v10.js` | 固定外壳、共享单元、分类映射、钱包、Tooltip、生命周期和样式缓存。 |
| `panorama/src/scripts/custom_game/archive_v10_semantics.js` | 只读快照归一化及各分类数量、状态、指标语义。 |
| `panorama/src/scripts/custom_game/archive_v10_icons.js` | 正式ID与分类隔离的35项原生装备图标解析；未命中保留原图，虚空之影始终不覆盖。 |
| `data/ui/archive_v10_icon_bindings.json` | 正式配置哈希、原资源路径与SHA256、存储及显示尺寸、匹配理由和保留条目。 |
| `panorama/src/scripts/custom_game/archive_v10_data.js` | 原组件坐标、哈希、字体与正式虚空之影 CSV 目录生成数据；不含预览数字。 |
| `panorama/src/styles/custom_game/archive_v10.css` | V10 隔离样式、原生字体、单元悬停、滚动及 Tooltip。 |
| `panorama/src/scripts/custom_game/archive_180de7e38b_titles_compact_v6.js` | 接入共享视图；保留旧动作；卡片组件复用；本地禁用目录和 Tooltip 离开处理。 |
| `panorama/src/scripts/custom_game/archive_purple.js` | 防止旧装饰覆盖 V10。 |
| `panorama/src/scripts/custom_game/archive_handoff_180de7e38b.js` | 导出原等级效果格式化函数供统一 Tooltip 复用。 |
| `panorama/src/images/custom_game/archive_v10/` | 48 张原版 PNG，字节及透明通道未修改。 |
| `panorama/src/layout/custom_game/archive_v10_assets.xml` | 原组件专属编译依赖清单。 |
| `panorama/{scripts,styles,layout,images}/custom_game/` 下的对应文件 | 本轮原生编译产物。 |
| `tools/archive_v10/` | 限定范围导入／编译、可运行本地预览和截图验收；新增图标生成、原纹理导出、35项组装截图及专项检查。 |
| `tools/tests/archive_v10_semantics.test.cjs`、`archive_v10_lifecycle.test.cjs` | 正式数据语义、共享外壳与生命周期回归。 |
| `tools/tests/archive_open_profile_refresh.test.cjs`、`archive_purple.test.cjs` | 当前真实脚本图、原业务／钱包／禁用目录及测试环境兼容。 |
| `tools/tests/archive_v10_icons.test.cjs` | 正式装备与原生饰品身份、缺失URI修正、显示区优先及安全回退、只读解析和虚空之影保留回归。 |
| `design_refs/archive_v10/` | 原包、读取记录、资产校验、截图、报告、接入及恢复说明。 |

Content 工程中仅同步了上述本轮存档文件，未执行全项目覆盖；Game 源、Content 源与原生编译输出均在 `work/compile.json` 逐项记录。

## 截图与验证范围

- 最终组件组装预览：`../work/browser/1920x1080_shadow.png`。
- 统一悬停：`../work/browser/shadow_tooltip.png`；长说明：`../work/browser/edges_long_tooltip.png`。
- 全部类别、四分辨率、空态及边界截图：`../work/browser/`。
- 35项原生图标本地组装：`../work/icon_map_v11/montage.png`；对应可运行HTML及PNG尺寸验证记录在同目录。该图是原图组件预览，不是游戏截图。
- 神兵、存档神器、积分装备四分辨率及Tooltip浏览器截图：`../work/browser_bindings/`。
- 用户本轮提出的「神兵-纯金之触」正式18级说明：`../work/browser_bindings/pure_gold_tooltip.png`，图中名称和效果来自正式配置，LV3及数量为本地验收样例；所有18条说明及底部数量均在伸展后的背景内。这是实际代码组装预览，不是实机截图。
- 原生游戏外壳验收：`../work/native/clear_before_alignment_fix.png`。它是在真实 Survival 地图、真实账户快照下截取的中间验收图，**不是最终数量对齐修复后的截图**。
- 后续原生装备及Tooltip中间检查：`../work/native/fragment_native_v11.png`、`../work/native/tooltip_before_panel_background.png`。后者记录修正前的原生Image问题，不能作为最终Panel方案验收截图。

浏览器图直接执行项目实际 XML／JS／CSS，但使用明确标注的本地数量／余额样例，不连接游戏或真实存档，不能称为游戏截图。正式名称、上限、条件和效果读取项目配置。

既有检查结果：61个组件校验、48张运行PNG原生编译、9组Node回归均通过。浏览器检查1280×720、1920×1080、2560×1440、2560×1080，逐图标坐标、16类切换、同一外壳对象及固定几何、未知／零／容量／超目标、73条列表、长名称、长Tooltip、连续重开及旧业务回调均通过。新增35项图标检查、本地原图组装检查已通过。最终Panel版通过浏览器检查和编译；这些结果不替代最终原生游戏截图验收。

具体证据：`../work/import.json`、`../work/compile.json`、`../work/final_test_results.json`、`../work/browser/report.json`、`../work/preview/assembly.json`；新增图标证据为 `../work/icon_binding_verification/manifest.json`、`../work/icon_map_v11/montage_validation.json`、`../work/browser_bindings/report.json`。记录包含生成时间和对应源版本，旧中间报告不能代替最终版本。数据规则见 [DATA_AND_INTERACTIONS.md](DATA_AND_INTERACTIONS.md)，浏览器边界见 [BROWSER_ACCEPTANCE.md](BROWSER_ACCEPTANCE.md)。

最后源码版本为 `5b3642530869399f40b5f743b15b06e6aa5a272da3afee8acc13d4f3d0a16225`。本轮最终全量浏览器、35项绑定／纯金之触18级、三层九宫格、真实模块双重重载四份报告均通过，并核对它们的源码图哈希与当前运行源码相同。`../work/browser/module_reload_grid.json` 记录旧初始化写入24,60坐标／1000宽后，实际重新打开恢复0,0／1113×669及第八列坐标。`../work/final_runtime_verification.json` 逐项核对Game、Content及编译产物与最后编译记录一致。原生最终视觉仍维持待验收状态。

## 差异与待补实机检查

- 实际名称、真实上限和真实进度与包内样例不同，未为视觉复现改业务配置。
- 项目多出的星悦积分、称号通过侧栏滚动保留，参考图仅展示 16 项。
- `shop` 原服务端尚无启用目录；本轮只呈现真实未启用状态。
- 原生截图发现数量的 `text-align:right` 在引擎里未产生预期结果，已改为固定宿主加自然宽度 Label 右侧锚定。最终原生逐分类截图、右侧锚定、Tooltip 鼠标滚轮和多分辨率复测尚待补齐。
- 最终Tooltip的Panel背景方案已经编译，浏览器检查通过，但当前游戏窗口最小化／处于后台，无法确认已加载最终版本及其原生绘图结果。现有真实游戏截图均标记为中间验收或问题证据；最终背景覆盖、边框／阴影衔接及交互尚需前台游戏截图确认。
- 原测试游戏退出后曾重新启动并取得外壳及装备中间截图；随后窗口失去前台可操作状态。没有新增直接控制台连接、改写真实存档或执行升级／抽奖来制造截图数据。

## 本地预览与恢复

从项目根目录运行 `node tools/archive_v10/preview.cjs`，浏览器打开 `design_refs/archive_v10/work/preview/index.html`。原有原生图标缓存首次需要 `node tools/archive_v10/native_icons.cjs`；新增装备图标需先运行 `node tools/archive_v10/build_icons.cjs` 和 `node tools/archive_v10/native_binding_previews.cjs`，生成真实PNG及预览别名。单独查看35项原图可打开 `work/icon_map_v11/montage.html`。具体说明见 `tools/archive_v10/README.md` 和 [ICON_IMPLEMENTATION.md](ICON_IMPLEMENTATION.md)。

源文件及当前编译产物已保存。继续验收时使用已有 Survival Tools 对局，打开顶部「存档」，逐项切换侧栏；无需覆盖配置或再次生成素材。确认测试窗口可操作后，用 `tools/archive_v10/window.ps1` 按正常界面截图，不直接连接控制台。待补截图应存入 `work/native/` 并更新本文验证范围。用于诊断的自动打开存档、F7绑定与详细逐切片日志均已从运行源码删除。

重新导入用 `node tools/archive_v10/import.cjs`，重新编译用 `powershell -NoProfile -ExecutionPolicy Bypass -File tools/archive_v10/compile.ps1`。编译限定白名单，执行前备份目标，失败时只恢复本次文件。最后的 Content／运行时恢复检查点路径在 `work/compile.json.backup`。

本轮没有执行 Git 提交或推送；用户原有未提交改动保持在工作区。未来提交按项目 AGENTS.md 的 stash → pull → pop → commit → push 顺序执行。原资源包随 `design_refs/archive_v10/package/` 保留；项目现有规则忽略 `panorama/src/images/`，提交原 PNG 时应明确暂存本轮目录，不修改整个资源忽略策略。
