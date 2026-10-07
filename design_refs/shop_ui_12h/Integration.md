# 商城最佳版：接入、资源与恢复

交付版本 **B17 + L21 + T23**。24 个候选完成后冻结材质；最新 T24 被淘汰。入口为 [离线图册](Delivery/index.html)，含真实游戏前后对比、默认/悬停、局部、四种分辨率、类别和候选证据。直接在本机浏览器打开 HTML 即可，不需服务器或外部依赖。

## 已验证范围

| 验证 | 结果及证据 |
|---|---|
| 实际 Dota 2 Tools，1280×800 | 同一活动测试局的原版、最终默认、最终悬停、道具分类、关闭商城后的 HUD；见 work/production/native_final_capture.json 和 native_baseline_capture.json。悬停由 Tools 强制状态重复显示，未点击兑换或购买。 |
| 生产资源编译 | 六个 JS/CSS/XML 源与运行文件 SHA256 一致，112 张新纹理依赖齐全；work/compile_report.json、Delivery/integration_audit.json。 |
| 浏览器生产组件和控制器 | 1280×720、1920×1080、2560×1440、2560×1080，窗口、网格和组件边界偏差不超过 2 设计像素；work/production/verification.json。 |
| 浏览器字段和复用 | 长名称、12 位价格、可滚动长描述、原弓/盾/杆/球/券图、皮肤图兼容样例、按钮三态、关闭叉号/外部遮罩；extended_qa.json。 |
| 原有业务回归 | tools/test_commerce_catalog_ui.cjs、tools/test_commerce_wallet.cjs 通过，覆盖券冷加载、取消、真实奖励和价格配置、货币、目录分片、重复点击、重试、热重载；仅测试桩，无真实订单。 |
| 源码保留审阅 | 现有 HUD 结构仅加入 3 个 CSS/JS 引用；原共享 UI 和 remaining 样式 SHA256 未变；购买、目录合并、券入口源码与任务开始时基线一致。 |

浏览器适配器将 Panorama 的 text-overflow:shrink 转成浏览器 ellipsis，两者并非同一字体排版引擎。四个规定分辨率、长字段、皮肤和未启用礼包尚未逐一在游戏内验证。真实截图是当前两类目录，不能代替尚未存在的商品数据。没有录屏或真实支付验收。

## 目录和数据约束

现有本地类别为武器装备、道具材料、科技服务、挑战、转职、礼包；启用 CSV 共 114 条，含 108 条商城兑换和 6 条付费配置，道具 84、科技 30，其余四类为空。当前已登录服务器返回 108 条兑换：科技 25、道具 83，导航仅显示其实际返回的两类。付费仍受原有测试账号限制。

商品图取原来的 icon 字段。本次没有为了截图改商品图映射、名称、价格、奖励、开放状态或目录过滤。科技首屏多张相同水晶源自原 CSV。53×48 的旧券图有自带深色底和低清限制，保留原图，在标准展示区内使用 96×96 inset。没有臆造去背景版本。皮肤兼容测试使用已有项目图，未新增皮肤商品；礼包使用已有未启用配置，只在浏览器样例中显示七项奖励。

## 源文件与加载顺序

| 文件（相对项目根） | 用途 |
|---|---|
| panorama/src/scripts/custom_game/common/commerce_components.js | Window、Nav、Product、Bundle、Price、Action、Box 的公共展示工厂，复用现有 SurvivalUI。 |
| panorama/src/scripts/custom_game/common/commerce_art_manifest.js | 75 张原商品图的尺寸、alpha 边界和独立投影映射；自动生成。 |
| panorama/src/styles/custom_game/common/commerce_jade.css | CommerceJade 作用域的材质、尺寸、层级、字体和交互状态。 |
| panorama/src/scripts/custom_game/commerce_remaining_5d5c1152eb.js | 现有商城控制器，仅重组展示、分页和 Tools 视觉入口；仍使用原目录与 Checkout。 |
| panorama/src/layout/custom_game/survival_hud.xml | 新样式 1 条引用，新 manifest / 工厂 2 条引用。原底部 HUD 元素保留。 |
| panorama/src/layout/custom_game/commerce_resources.xml | JS 动态图片的编译依赖清单，112 张图片；不作为游戏窗口加载。 |
| art/ui/sources/custom_game/commerce_jade_v1/ | 37 张独立 PNG 材质和 75 张商品投影。panorama/src/images 是原项目 junction，指向 art/ui/sources。 |
| art/ui/development/commerce_jade_v1/ | 27 个 SVG 源、6 个 CSS 导出配方、原山水图。其余 4 个导航图标保留原 PNG 源；没有虚构矢量源。 |
| panorama/scripts、styles、layout、images 中对应 commerce 文件 | 已编译的 vjs_c、vcss_c、vxml_c、vtex_c，当前可直接用于游戏。 |
| tools/test_commerce_catalog_ui.cjs、tools/test_commerce_wallet.cjs | 原有回归测试适配新增展示工厂，不增加真实订单调用。 |
| tools/shop_ui_12h/ | 候选、组装、截图、编译、审阅和恢复脚本。 |

详细逐图尺寸、源文件、运行资源和 SHA256：**Delivery/resources.json**。布局以 layout.json 和 nav_component_layout.json 为合同，不从参考图重算位置。

本轮修改文件与资源族清单：**Delivery/changes.json**。最佳快照包括 6 个运行源编译文件及 112 张纹理，共 118 个运行文件；未把其他已有工作区改动纳入本轮交付清单。

加载顺序：原 SurvivalUI → commerce_art_manifest.js → commerce_components.js → 原 commerce 控制器。commerce_jade.css 放在原 remaining 样式后，所有主要选择器限定 CommerceJade；未重写原公共组件或其他窗口。

## 尺寸、锚点与层级

所有数值为设计像素；窗口内坐标从左上角起算。原 ModalShell 负责根据 1920×1080 参考画布居中、整体等比例适配，物品图 preserve-aspect，不独立拉伸。

| 元素 | x,y | 宽×高 | 层级 / 说明 |
|---|---:|---:|---|
| 窗口 | 画布 160,80 | 1600×920 | 居中整体缩放，象牙实底防 HUD 透入。 |
| 顶部底图 | 0,0 | 1600×112 | header 3，图片 0，标题 2；独立文字。 |
| 顶部过渡 | 320,88 | 1280×96 | 4，压在 header 下沿上方使雾化有效。 |
| 侧栏底图 | 0,112 | 320×808 | 1；侧栏接缝 312,112 / 24×808 / 2。 |
| 导航容器 | 0,128 | 320×768 | 3，单行 320×96，overflow:noclip。 |
| 导航光晕 / 底线 | -10,-10 / 0,94 | 340×116 / 320×2 | 独立图层 0 / 1，行底端一致。 |
| 商品网格 | 344,174 | 1232×714 | 5，4 列 2 行，步长 312×366；分页八件。 |
| 商品卡 | 网格内按步长排列 | 296×348 | hover 上移 2，物品 / 投影上移 3，等比 1.035。 |
| 卡片投影 / halo | -12,-8 | 320×376 | -3 / -2，独立 PNG，透明边缘不截断。 |
| 展示区 | 16,12 | 264×224 | 2；原图在 4,4 / 256×192 区域 preserve-aspect。 |
| 物品投影 | 展示区 -12,-12 | 288×224 | 1，按原图 alpha 生成，最终 opacity .55。 |
| 悬停内容 | 展示区 0,0 | 264×224 | 3，软边 PNG，无浏览器 backdrop-filter。 |
| 短描述 / 长描述 | 12,123 / 12,16 | 240×40 / 240×148 | 动态 Label；长说明软边全区遮罩 .84、可滚动。 |
| 悬停购买按钮 | 展示区 38,170 | 188×46 | 独立 Button，原 ActionButton 回调。 |
| 名称区域 | 卡内 12,244 | 272×34 | 3；内部 fit-children Label + horizontal-align:center，实际字串居中。 |
| 价格区 | 卡内 16,286 | 264×42 | 3；非按钮，不拦截输入；独立 26px 货币图标与 21px 数值。 |
| 关闭叉号 | 1528,28 | 点击 48×48 / 图 40×40 | header 内 4，独立叉号，没有方框底。 |
| 窗口框 | 0,0 | 1600×920 | 20，装饰 Image 禁止 hittest。 |
| 礼包卡 | 网格步长 624×366 | 608×348 | 2 列 2 行；内容 568×202，奖励单元 262×94。 |

礼包单元比初版缩小到 262px，给原生滚动条留宽度，仍为 2×2 四单元首屏。超过四项在内容区滚动，价格和购买区不移动。这一适配和名称父容器层级修复是接入合同的实现修正，未当作新的材质候选计数。

## 复用 API

```js
var J = GameUI.CustomUIConfig().SurvivalCommerceComponents;
var card = J.Product(parent, authoritativeItem, {
    effect: dynamicRewardText,
    purchaseLabel: existingPurchaseLabel,
    action: existingCheckoutHandler
});
J.Box(card, column * 312, row * 366, 296, 348);
```

Product 的 item 使用原目录字段 title、icon、enabled、owned、purchase_method、price/currency/currency_name、amount_fen。Bundle 另传原 reward_lines，经原控制器转成 rewards。工厂只展示和绑定既有回调；不计算定价、继承商品或生成订单。新增图应追加原图 alpha 投影清单和编译依赖，而不是给页面写新的图片壳。

## 本机重建与检查

从项目根运行，依赖现有 Node、Chrome、Dota 2 resourcecompiler；不下载 Playwright、sharp 或新 npm 包。

```powershell
# 生产组件预览，使用本地只读 CSV 和 Checkout 测试桩
node tools/shop_ui_12h/preview.cjs
node tools/shop_ui_12h/verify.cjs
node tools/shop_ui_12h/extended-qa.cjs

# 现有业务回归
node tools/test_commerce_catalog_ui.cjs
node tools/test_commerce_wallet.cjs

# 更新真实运行资源：仅六个源和新素材族；保留外部 content 旧文件备份
powershell -NoProfile -ExecutionPolicy Bypass -File tools/shop_ui_12h/compile.ps1

# 交付审阅与图册（先保留截图，不将当前实验自动设为最佳）
node tools/shop_ui_12h/deliver.cjs
node tools/shop_ui_12h/delivery-images.cjs
node tools/shop_ui_12h/audit-delivery.cjs
```

Chrome CDP / 外部 content 编译需要本机对应权限；自动化运行时可能需要 sandbox escalation。浏览器专用适配仅在 preview.cjs，不会进入 Panorama 源。

重建当前材质可运行 assets.cjs：从明确选中的 B17 和 L21 PNG 导入，不自动选择最新候选，同时从原商品图生成投影和 commerce_resources.xml。改 SVG 时先导出到新候选、用真实组件组装、截图比较，再决定是否更新 PNG；PNG 修改后运行 compile.ps1。assets.cjs 不把 Delivery 中的参考整页截图作为任何运行素材。

原生验收通过“商城”原入口打开。Tools 热重载后日志 `[COMMERCE_JADE_COMMANDS]` 给出本次唯一命令名，用 open、technology、item、hover、normal、close、inspect 检查。命令以时间戳后缀避免旧 JS 上下文被复用，不会执行 Checkout。日志输出不要整段公开，以免夹带项目其他账号信息。

## 检查点与明确恢复步骤

任务开始前的实际未提交文件在 work/checkpoints/baseline，不是 Git HEAD。九组材质检查点在 work/checkpoints/01_junction 至 09_navigation；每组含 config、独立材质、组装 HTML、默认/悬停、局部及 decision.json。assembly 是参考组件的浏览器组装，不冒充游戏截图；移动仓库后可按 config.parent/changes 用 experiment.cjs 在副本中重建。

**生产最佳检查点** work/checkpoints/production_best：六个最终源、112 张 PNG、六个编译文件、112 张编译纹理、真实游戏证据、四个生产候选及 manifest / compiled_manifest。实际生产版本以该检查点为准。L21–T24 的 assembly.html 还需对应 config 覆盖；真实比较截图和配置一并保留。

```powershell
# 只检查是否可恢复；不写文件
powershell -NoProfile -ExecutionPolicy Bypass -File tools/shop_ui_12h/restore.ps1 -Mode Best -WhatIf
powershell -NoProfile -ExecutionPolicy Bypass -File tools/shop_ui_12h/restore.ps1 -Mode Baseline -WhatIf

# 恢复本次最终最佳源 / 缺失素材，然后重编译
powershell -NoProfile -ExecutionPolicy Bypass -File tools/shop_ui_12h/restore.ps1 -Mode Best
powershell -NoProfile -ExecutionPolicy Bypass -File tools/shop_ui_12h/compile.ps1

# 若要回到本次任务开始前，只恢复当时的商城控制器和 HUD 引用
powershell -NoProfile -ExecutionPolicy Bypass -File tools/shop_ui_12h/restore.ps1 -Mode Baseline
powershell -NoProfile -ExecutionPolicy Bypass -File tools/shop_ui_12h/compile.ps1
```

恢复脚本发现文件在检查点之后被改过会停止，要求人工合并；不会用 git reset、清空目录或删除用户素材。回到 Baseline 后新增的作用域文件可以保留为未加载资源。两种恢复均已用 -WhatIf 检查。

临时 startup/mode/旧商城验收探针已还原外部 content 源和运行文件，校验见 work/probes_restored.json；临时背景别名纹理已移除。它们用于解决 Tools 热重载中的实际 ImageLoaded 和原界面选择入口，不作为生产启动逻辑交付。原账号准入与模式/难度检查始终保留。

工作区已有大量本轮之前的改动，未做 Git 提交、推送或重置。后续若要求提交，遵循项目规定 stash → pull → pop → commit → push，并仅暂存本轮必要内容；output/ 下本机日志、编译备份和运行输出不得提交。
