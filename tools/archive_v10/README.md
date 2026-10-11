# V10 存档实际组件本地预览与验收

该预览直接读取当前生效的 `panorama/src/layout/custom_game/archive.xml`，按其 include 顺序加载项目真实 JavaScript 和 CSS，执行原存档控制器。页面不是效果图贴图；背景、横轨、按钮、图标框、图标与文本均为实际组装组件。

新 checkout 先执行 `node tools/archive_v10/import.cjs`，从已提交原包校验并重建 48 张本地源 PNG、布局数据及 `tools/archive_v10/compile_scope.json`。游戏使用仓库中的已编译资源；源 PNG 不重复提交。此步骤只写本地项目。

存档和共享菜单的编译范围分别维护在 `tools/archive_v10/compile_scope.json` 与 `tools/menus_v10/compile_scope.json`，验收截图和报告仍输出到忽略的 `work/`。

从项目根目录运行：

```powershell
node tools/archive_v10/native_icons.cjs
node tools/archive_v10/native_binding_previews.cjs
node tools/archive_v10/preview.cjs
```

然后使用浏览器打开 `design_refs/archive_v10/work/preview/index.html`。可以添加 `?category=work`、`?category=building`、`?category=ex` 查看分类，添加 `?state=edges`、`?state=extra`、`?category=shop&state=empty` 查看边界状态。

定义读取项目正式 CSV，包括真实名称、图标映射、描述、条件门槛、持有上限、等级上限及成本。进度、数量、余额是明确标注的本地验收样例；不读取或写入真实账户，不连接游戏服务器，不调用支付或奖励接口。预览包中的示例数字不作为 fixture 来源。

自动验收：

```powershell
node tools/archive_v10/capture.cjs
node tools/archive_v10/tooltip_nine.cjs after
node tools/archive_v10/icon_geometry.cjs
node tools/archive_v10/binding_acceptance.cjs
```

`native_icons.cjs` 从本机 Dota VPK 只读导出浏览器缺少的 5 个原生物品图标；导出仅用于本地预览，游戏仍直接调用原生 URI。需要项目原有本地 Source2Viewer CLI。运行一次后 PNG 缓存在 `work/native_icons/`。

`native_binding_previews.cjs` 复用 `build_icons.cjs` 已核验的 35 项正式 ID 与原生资源，将精确导出的原图提供给浏览器。`preview.cjs` 合并这些 URI 别名，不改游戏资源；`assembly.json` 记录各别名清单的哈希和来源。`binding_acceptance.cjs` 在四种分辨率逐项检查实际挂载的 ID、名称、原图、有效图像尺寸和 `contain` 比例，并检查 Tooltip 标题从背景的 22×19 内边距开始，天然正文与独立滚动视口一致。

`binding_acceptance.cjs` 还保存 `work/browser_bindings/pure_gold_tooltip.png`：正式 `fragment_09`「神兵-纯金之触」的全部 18 级说明，来自现有 CSV 与当前业务格式化器，数量与当前等级沿用明确的本地样例。验收检查最后一级文字仍在、自然正文完整、可见文字视口落在背景内；超过 730 逻辑像素时使用内部滚动并额外保存滚动截图。该图是浏览器实际组件组装，**不是游戏内截图**。

验收脚本使用已安装 Chrome 的隐藏无头实例。需要 Node 支持内置 `fetch` 和 `WebSocket`。截图和报告保存到 `design_refs/archive_v10/work/browser/`，涵盖 1280×720、1920×1080、2560×1440、2560×1080、16 个分类切换、共用外壳身份与几何稳定性、数量容器位置及文本右对齐、数量边界、长 Tooltip、阴影命中穿透、Tooltip 150ms 离开延迟与实际 Chrome 滚轮、容量超出 23、空态以及原升级/抽奖回调。回调仅记录到浏览器 stub，没有实际服务器副作用。

`tooltip_nine.cjs after` 额外校验 Tooltip 背景、边框、阴影三层的 9 裁片、原图哈希及四角尺寸，在最小 198、正常地图说明和长正文 730 三种逻辑高度下均保持不变。实际裁片使用原 PNG 的 Panel 背景，明确 `background-size:100% 100%` 双轴缩放；专项逐片检查 Panel 类型、无重复填充、原图解码宽高、裁剪比例与负坐标，防止仅改变面板尺寸而图片仍居中保留原高度。`preview.cjs` 从实际源图中的 XML、JS、CSS 统一解析本地原 PNG 路径，让运行时 Panel 背景与 Image 采用相同资源来源。专项截图与报告保存到 `work/nine_slice/`，已有修复前截图时自动生成 `comparison.html` 与 `comparison.png`。已有 `before` 是先前组件的浏览器基线，不能表现原生 Image 在实机中居中保留原高度的缺陷；该问题的直接证据是 `work/native/review_burst_27.png`。若开始下一次修改，可先对修改前的已生成预览运行 `tooltip_nine.cjs before` 保存新基线，再修改、重生成预览并运行 `after`。

浏览器 `actualuiscale` 模型已对照 1600×900 原生诊断：UI 基础缩放约 0.8333，Fit 的 CSS transform 约 1.1483；`actualuiscale` 不包含后者，而窗口坐标包含后者。浏览器文字排版仍是模拟，不能以浏览器通过代替原生 Tooltip 验收。

全量 capture 还验证无尽 ∞ 双环原几何与全部 9 个称号子层相对原业务构造器不变；`icon_geometry.cjs` 可另外导出这两类前四单元的实际组装局部图。百分比子层随整个称号舞台缩放，不要求将每层改为固定方图。

这是项目代码的可运行组件预览，**不是游戏内截图**。浏览器通过独立适配器模拟 Panorama 布局和 API；原生引擎的材质、字体栅格、滚动与鼠标交互仍需单独游戏验收。`assembly.json` 保存当前 XML/JS/CSS 源图与哈希，截图报告保存每个状态的实际几何和脚本错误信息。

原生窗口辅助工具 `window.ps1` 要求明确传入存活的 Dota 2 `ProcessId`，且只接受以 `-tools -addon survival` 启动的窗口。默认仅输出客户区的物理宽高、桌面起点和 DPI。可传 `ClickX/Y`、`PointerX/Y` 与 PNG 文件名 `Screenshot`，截图保存到 `work/native/`；坐标直接对应此截图的客户区物理像素。它先设置 Per-Monitor V2，核验前台与目标点命中；不会抢焦点、恢复/隐藏窗口，也不连接控制台。调用示例只读：`powershell -NoProfile -ExecutionPolicy Bypass -File tools/archive_v10/window.ps1 -ProcessId 50792`。该启动参数只作用于这个 PowerShell 进程，不修改系统执行策略；PID 需使用当前会话的实际进程号。受限环境可能限制只读 CIM 进程校验，应在允许读取此测试进程的环境调用，不跳过校验。

图标来源审计：`node tools/archive_v10/audit_icon_bindings.cjs`，只读本机 VPK，证据写入忽略的 `work/`。原生资源导出依赖本机 Source2Viewer CLI。
