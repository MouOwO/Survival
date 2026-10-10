# 紫色弹窗接入、编译与恢复说明

活动 UI 以 [custom_ui_manifest.xml](../../panorama/src/layout/custom_game/custom_ui_manifest.xml) 为入口。作者源位于 `panorama/src`；游戏加载的编译资源位于 `panorama/layout`、`panorama/scripts`、`panorama/styles`。本说明对应本次已接入的组件与实际工具，版本选择和原生复核进度以 [BEST_VERSION.json](BEST_VERSION.json)、[RootIterations.md](RootIterations.md) 为准；工作目录中的最新源不自动代表最终最佳版本。

最终恢复入口为 [best_final_compact_purple_c19/manifest.json](work/checkpoints/best_final_compact_purple_c19/manifest.json)。最终浏览器装配追踪143个活动XML/CSS/JS源，digest为 `5216ec0cffc8d3c5d663635855d894159a46590a5efbb8a602dd34734d8c2675`；[final_component_applicability.json](work/final_component_applicability.json) 按实际组件字节说明旧报告的适用范围与重新验证项。具名manifest保存的source/runtime、成功编译记录和实际截图共同确定恢复版本，单一全局digest不代替业务回归或原生验收。已保存的 [C18 manifest](work/checkpoints/best_final_compact_purple_c18/manifest.json) 是L07历史/更新说明修正前的已通过历史版，不能当作最终C19恢复入口。

各 XML 保持自己的 Panorama context，通过 `GameUI.CustomUIConfig()` 中的原业务 API 联通；没有把子面板搬到另一 XML context。

| 活动 XML | 本次页面与实际 API | 新增紫色层 / 业务源 |
| --- | --- | --- |
| [survival_hud.xml](../../panorama/src/layout/custom_game/survival_hud.xml) | 生存店：`SurvivalShop.ToggleShop/SelectShop`；商城：`SurvivalCommerceView.Open`；抽奖：`SurvivalLottery.Open/Feature` | `common/purple_shell.js/css`；`shop_purple.css` + `shop_remaining_5d5c1152eb.js` / `shop_tooltip_remaining_5d5c1152eb.js`；`common/commerce_purple.css` + `common/commerce_components.js` / `commerce_remaining_5d5c1152eb.js`；`menu_purple.js/css` + 原抽奖 controller / handoff / cinematic |
| [archive.xml](../../panorama/src/layout/custom_game/archive.xml) | 存档：`SurvivalArchive.Open/Toggle`；宝物：`SurvivalTreasure.Toggle`；每日：`SurvivalDaily.Open(false)`，通行证 `Open(true)`；VIP：`SurvivalVIP.Open/Toggle` | `common/purple_shell.js/css`；`archive_purple.js/css`；`treasure_purple.css` / `treasure_history.js`；`daily_purple.css` / `daily_remaining_5d5c1152eb.js`；`vip_purple.css` / `vip_window.js` / 原 `vip_catalog.js` |
| [payment_test.xml](../../panorama/src/layout/custom_game/payment_test.xml) | 商城 `purchase_method=wallet` → `SurvivalCommerceWallet.Checkout(sku)`；其它现金商品 → `SurvivalPayments.Checkout(sku)` | `common/checkout_purple.css` + 原 `commerce_wallet.js` / `payment_test.js`；钱包窗动态创建，现金窗为 XML 内 `PaymentDialog` |

`payment_test.xml` 在 manifest 中独立且先于主 HUD 加载。它保留原惰性 `prepareShell`：共享 U/R helper 尚未加载时不假设它们存在，真正打开/渲染时再接壳。订单与兑换确认窗口沿用原 ModalShell，只统一紫金外观，没有新增公共导航或改变订单规则。`checkout_purple.css` 同时进入主 HUD 和 payment XML 的 styles。

XML 中 CSS 紫色覆盖在旧样式之后。脚本顺序仍需保留：`common/ui_registry.js` / `common/ui_components.js`、`ui_layers.js` 与共享壳先于组件初始化；`reference_windows.js` 先于 `remaining_5d5c1152eb.js`，二者先于无条件调用它们的商店/商城 controller。存档的实际主 controller 是 `archive_180de7e38b_titles_compact_v6.js`，不按同目录历史文件名猜测入口。抽奖紫色 hook `menu_purple.js` 在原抽奖 controller 之后包装其 presenter。

共享外观由 [common/purple_shell.js](../../panorama/src/scripts/custom_game/common/purple_shell.js) 和 [common/purple_shell.css](../../panorama/src/styles/custom_game/common/purple_shell.css) 提供。用法如下，原业务 ModalShell 的 Open/Close/Fit/ESC 继续保留：

```js
var purple = cfg.SurvivalPurpleShell.Adopt({
    id: "commerce",           // 层/业务标识
    navId: "commerce",        // 可省略；详情窗使用 lottery 高亮
    panel: existingWindow,
    width: 1280,
    height: 800,
    onClose: originalClose
});
// 返回 panel / chrome / corners / generation / Refresh / Dispose。
// Dispose 只清理该外观实例和 Entries，不替代原 ModalShell.Dispose。
```

公共导航/货币占顶部约 0–128，业务内容从 y=132 开始。`Adopt` 装饰现有 panel；同 generation 复用缓存，重载时重建 chrome 与四角，检查有效 panel 后更新余额。全局 API 还提供 `Navigate(id)`、`Refresh()`、`FormatNumber(value)`、`Entries`、`Resources`、`IsAlive()`、`ReleaseSubscriptions()`。

`Navigate` 调用原宝物/存档/抽奖/商城/每日/生存店 API，先通过原 `SurvivalUILayers.CloseTop()` 逐层关闭白名单内的普通菜单，最多 16 次。真实独立子层包括 `lottery_info`、`commerce_exchange`、`payment_shop`；到目标原主页已经在栈顶时直接返回，不重复打开/请求。每次关闭后栈顶仍不变就中止，保留原 pending/mandatory 保护；遇到 `hero_skill_choice`、`rogue_choice`、`survival_difficulty` 等非菜单层也中止，不触发它们的关闭回调。每日规则是实际 `DailyRulesText` 子 panel，由原每日 `Close` 一并隐藏，没有创建虚构的 `daily_rules` 栈层。排行榜 tab 保持未开放。VIP 沿原 HUD 入口与原资格判断打开，没有编造排行榜、装备或外观 API。

余额由真实快照/NetTable 和原 wallet catalog 提供：生存店为本局金币/木材，其余共享框为 U币/积分/商城金币，未知显示 `—`；抽奖券仍由抽奖自己的权威快照显示。共享壳订阅 `survival_ui_private_snapshot`、`ui_state_snapshot`、`ui_shop_snapshot`、`survival_commerce_result` 与 `survival_ui_state`；第二 context 继承活 Entries/Resources 并释放前一壳订阅，不新增轮询。

紧凑单元遵循图标、可选右上数量/进度、下方名称；条件、效果、价格、完整权益和持续时间进入 tooltip。组件保留各自的真实数据与业务边界：

| 组件 | 当前候选布局 | 保留的行为 |
| --- | --- | --- |
| 存档 | 1280×800，CSV 18 个配置分类、服务器当前 17 个启用（shop 禁用）、常规 7 列；称号独立宽度 | 筛选、真实进度/未知数量、社交总数与抽取栏、称号穿戴、建筑/积分道具升级、碎片晋升与完整效果说明 |
| 生存店 | 1040 宽、4 列；高度按实际内容 456/662/760，顶部锚点稳定；Dota 原图标 | 装备/挑战/其他分类、真实库存与可用条件；悬停/选中不购买，tooltip 明确购买、原右键、自动书及科技路由保留 |
| 账户商城 | 1280×800，5 列紧凑商品与分类/分页，名称文本盒自身居中；详情在所属窗口专用浮层，按window与screen交集定位 | 合并真实现金/余额目录，数量只在已知时显示；完整权益/价格在不透明 tooltip，长正文可接受真实滚轮；按 purchase_method 路由原两个 Checkout；25 个已知科技 SKU 的旧水晶占位通过公共 ProductIcon 展示现存 Dota 图，服务端专属图优先 |
| 每日/通行证 | 1280×800，7 天奖励组、真实累计 7/14/21 奖励，规则/tooltip 不透明 | 真实领取/补签顺序、period/day/count、防重、通行证资格和 `purchase_enabled`；未知价格不填假值；规则正文分段，框按内容收紧且最多516高并保留滚动，规则打开时隐藏 tooltip 并阻止背后卡片再触发，关闭后 fresh hover 恢复 |
| 本局宝物 | 1280×800，8 列、最多最近 20 条 | 真实本局历史与空提示，既有技能图标、原完整效果 tooltip；不补齐虚假空槽或数量 |
| 抽奖/详情/记录 | 1280×800；`menu_purple` 包装原 presenter，原电影在内容区域容纳 | 单抽/十连真实消耗与保底、pending/动画防重、独立详情快照、记录、跳过/关闭/ESC；compact tooltip保留真实品质/拥有/期限/重复转化，单件详情Note缺时长不猜永久；风格应用不抽取、不打开券购买 |
| VIP | 1280×800，原 3 分类/33 奖励 | 原账号可见资格、VIP等级/勋章/礼包、真实余额/免费领取/购买、防重、完整 tooltip；不编造专用物品图片 |
| 钱包/现金确认 | 原 760×700 / 960×740，紫金标题与按钮；二维码保留白底黑块 | 未确认兑换重试同 token；现金 pending 金额/奖励不随目录编辑改变，支付渠道、QR、可信备用地址、到账凭据与 before→after 保留 |

具体比较和检查点见 [ArchiveIterations.md](ArchiveIterations.md)、[ShopIterations.md](ShopIterations.md)、[DailyIterations.md](DailyIterations.md)、[TreasureIterations.md](TreasureIterations.md)、[VIPIterations.md](VIPIterations.md)、[CheckoutIterations.md](CheckoutIterations.md)，入口范围见 [MenuCoverage.md](MenuCoverage.md)。

业务事件名与服务器权威保持。例如存档仍发送 `survival_archive_request` / `survival_archive_social_draw` / `survival_archive_title_equip` / `survival_archive_building_upgrade` / `survival_archive_work_upgrade` / `survival_archive_promote`；生存店仍发送 `ui_shop_open_request` / `ui_shop_close_request` / `ui_shop_purchase_request` / `ui_shop_auto_purchase_toggle_request`；抽奖仍为 `ui_lottery_snapshot_request` / `ui_lottery_draw_request`；每日仍为 `survival_daily_request` / `survival_daily_claim` / `survival_pass_purchase`；VIP 为 `survival_vip_request`；钱包、现金分别为 `survival_commerce_request`、`survival_payment_request`。样式代码不填客户端价格、余额、权限或发放结果。

具名编译使用 [checkpoint.cjs](../../tools/purple_ui_10h/checkpoint.cjs) 和 [compile.ps1](../../tools/purple_ui_10h/compile.ps1)。以下命令从仓库根运行；检查点名必须唯一，示例名需按本轮改动命名，不能覆盖旧证据：

```powershell
node tools/purple_ui_10h/checkpoint.cjs C19_next_review
Get-Content design_refs/purple_ui_10h/work/compile_scope.json
& .\tools\purple_ui_10h\compile.ps1 -Scope 'design_refs/purple_ui_10h/work/compile_scope.json'
```

checkpoint 工具只列具名任务文件，写 `work/checkpoints/<name>/manifest.json` 和 `work/compile_scope.json`；它不复制整个 panorama 目录。编译前需审查 scope：新 CSS/JS/XML include 的依赖也必须进入 scope，不能只编调用它的 XML。新增资源不在当前 JS/CSS/XML 工具范围时应使用其已有资源流程，而不是假设此工具生成了图片/字体。

compile 工具按当前仓库位置解析以下三个树，并先备份所选文件：

| 树 | 当前项目绝对位置 / 映射 |
| --- | --- |
| 作者源 | `D:\SteamLibrary\steamapps\common\dota 2 beta\game\dota_addons\survival\panorama\src\<relative>` |
| Content 输入 | `D:\SteamLibrary\steamapps\common\dota 2 beta\content\dota_addons\Survival\panorama\<relative>` |
| 游戏运行产物 | `...\game\dota_addons\survival\panorama\<relative>`，`.js → .vjs_c`、`.css → .vcss_c`、`.xml → .vxml_c` |

实际编译器为 `...\game\bin\win64\resourcecompiler.exe`，逐个调用 `-i <Content-file> -game <engine-root>\game\dota -fshallow -nop4`，先 scripts/styles 再 layout。编译日志必须含 `0 failed`、退出码 0，并核对产物非空/时间和源 SHA 未在编译期间变化。成功写 [work/compile.json](work/compile.json)，记录具名 source/content/artifact、SHA 与备份路径；日志和原字节位于 `output/purple_ui_10h/compile_<timestamp>`。该步骤写 Content 和运行产物，应由负责原生验证的执行者在相应授权环境完成。

失败时 `compile.ps1` 自动按已记录的 `contentExisted` / `runtimeExisted` 恢复原 Content 和运行产物；此次新增且原先不存在的所选文件被移除。作者源保留候选，不由 catch 回退。不要把仍存在的上次成功 `compile.json` 当成本次失败成功的证明。本轮 C07 因漏列 checkout CSS 依赖失败，恢复后补齐具名范围再编；细节见 RootIterations。重新编译前先处理失败日志和依赖，不做整 Content 同步。

检查点恢复按最终 [C19 manifest](work/checkpoints/best_final_compact_purple_c19/manifest.json) 的明确目标执行。先核对 [BEST_VERSION.json](BEST_VERSION.json) 的组件选择、checkpoint 时间、`kind/source/saved/sha256`，保存当前目标字节到新的具名备份，然后只恢复所需记录。不要把早期组件 checkpoint 内的整份 `archive.xml`、`survival_hud.xml` 覆盖到当前项目；后续 daily/VIP/checkout include 或其它用户改动可能不在那份 XML 中。若本次只回退公共外框，则只选其 CSS/JS；XML 引用行按当前依赖逐行审阅、必要时合并。

checkpoint 工具的 `runtime` 记录中，`saved` 可能以 `.js/.css/.xml` 命名保存编译字节，真正目的路径是 record.source 中的 `.vjs_c/.vcss_c/.vxml_c`，不能按 saved 扩展名猜目标。编译前创建的 checkpoint 也可能是新作者源加前一版运行产物，并非已验证的同版配对。恢复某候选组件时优先恢复选中的 source 并重新具名编译；要原样恢复运行字节时需核对成功编译记录中的 SHA 与对应源码。

下例按最终C19 manifest只恢复公共外框两个作者文件；执行前仍须保存当前目标并核对BEST选择。[C09_native_state_recovery](work/checkpoints/C09_native_state_recovery/manifest.json) 仅保留为历史恢复证据，不能整份覆盖最终XML或把旧运行字节作为C19。下例不会枚举或递归删除目录：

```powershell
$recoveryRepo = (Resolve-Path '.').Path
$recoveryCheckpoint = (Resolve-Path 'design_refs/purple_ui_10h/work/checkpoints/best_final_compact_purple_c19').Path
$recoveryManifest = Get-Content -LiteralPath (Join-Path $recoveryCheckpoint 'manifest.json') -Raw | ConvertFrom-Json
$recoveryTargets = @('panorama/src/scripts/custom_game/common/purple_shell.js', 'panorama/src/styles/custom_game/common/purple_shell.css')
$recoveryRows = @($recoveryManifest.records | Where-Object { $_.kind -eq 'source' -and $_.source -in $recoveryTargets })
if ($recoveryRows.Count -ne $recoveryTargets.Count) { throw 'Selected manifest targets missing' }
$recoveryBackup = Join-Path $recoveryRepo ('output/purple_ui_10h/restore_' + (Get-Date -Format yyyyMMdd_HHmmss))
foreach ($row in $recoveryRows) {
    $saved = [IO.Path]::GetFullPath((Join-Path $recoveryRepo $row.saved))
    $target = [IO.Path]::GetFullPath((Join-Path $recoveryRepo $row.source))
    if (-not $saved.StartsWith($recoveryCheckpoint + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Backup outside checkpoint' }
    if (-not $target.StartsWith($recoveryRepo + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Target outside repository' }
    if ((Get-FileHash -LiteralPath $saved).Hash -ne $row.sha256) { throw 'Checkpoint bytes changed' }
}
foreach ($row in $recoveryRows) {
    $target = Join-Path $recoveryRepo $row.source
    $before = Join-Path $recoveryBackup $row.source
    New-Item -ItemType Directory -Path (Split-Path -Parent $before) -Force | Out-Null
    if (Test-Path -LiteralPath $target) { Copy-Item -LiteralPath $target -Destination $before }
    Copy-Item -LiteralPath (Join-Path $recoveryRepo $row.saved) -Destination $target -Force
}
```

恢复后运行相关原 controller 回归，重新建立唯一检查点/审阅 scope、具名编译并作同状态截图比较。组件私有 `source_hashes.json` 检查点（如 `checkout_purple_a01`、`shops_native_center_a09`）和统一 `manifest.json` 检查点格式不同，应先读取实际记录，不能套同一恢复路径。

本地验证工具为 [shop_verify.cjs](../../tools/purple_ui_10h/shop_verify.cjs)、[commerce_verify.cjs](../../tools/purple_ui_10h/commerce_verify.cjs)、[daily_verify.cjs](../../tools/purple_ui_10h/daily_verify.cjs)、[lottery_verify.cjs](../../tools/purple_ui_10h/lottery_verify.cjs)、[checkout_verify.cjs](../../tools/purple_ui_10h/checkout_verify.cjs)，以及现有 `tools/tests/archive_purple.test.cjs`、`treasure_purple.test.cjs`、`vip_window.test.cjs` 等组件回归。例：

```powershell
node tools/purple_ui_10h/shop_verify.cjs
node tools/purple_ui_10h/commerce_verify.cjs
node tools/purple_ui_10h/daily_verify.cjs
node tools/purple_ui_10h/lottery_verify.cjs
node tools/purple_ui_10h/checkout_verify.cjs
node tools/test_commerce_wallet.cjs
node tools/test_payment_ui.cjs
node tools/test_payment_catalog_cache.cjs
```

这些回归运行真实 controller/组件；网络、购买、支付、抽取和领取被本地记录器捕获。strict-native mock 在完整子树删除后拒绝访问旧面板，验证旧 API、事件/计时器、重新初始化和订阅/包装释放。旧 `test_payment_original_shell.cjs` 未加载当前 ReferenceWindows 且断言旧 frame；基线源同样失败，未修改旧测试伪造通过，详情见 CheckoutIterations。

浏览器组装工具 [preview.cjs](../../tools/purple_ui_10h/preview.cjs) 从活动 manifest 追踪实际 XML/CSS/JS 顺序，生成 `work/preview/assembly.json`、fixture 和静态预览；[qa.cjs](../../tools/purple_ui_10h/qa.cjs) 使用本机 Chrome CDP。示例仅在本地 fixture 中运行：

```powershell
node tools/purple_ui_10h/preview.cjs
node tools/purple_ui_10h/qa.cjs --page paid_checkout --states normal,pending,receipt,disabled --no-pointer --report paid_checkout_review
```

已记录浏览器分辨率为 1280×720、1920×1080、2560×1440、2560×1080。对应 [final_primary_report.json](work/qa/final_primary_report.json)、[pointer_report.json](work/qa/pointer_report.json)、[final_daily_report.json](work/qa/final_daily_report.json)、[final_treasure_report.json](work/qa/final_treasure_report.json)、[lottery_l03_report.json](work/qa/lottery_l03_report.json)、[vip_v01_report.json](work/qa/vip_v01_report.json)、[paid_checkout_p01_full_body_report.json](work/qa/paid_checkout_p01_full_body_report.json)、[wallet_checkout_p01_report.json](work/qa/wallet_checkout_p01_report.json)。同一案例在多个报告出现不重复累加覆盖。

商店/商城还用实际鼠标走 source → gap 停 40ms → tooltip 停 230ms，确认悬停延迟、唯一 tooltip 和可命中的购买按钮；enabled 仅产生本地 mock，locked 不产生交易。Checkout 四尺寸共 32 状态案例含正文/奖励、QR、按钮和状态子边界；cash 全状态 create=0，wallet receipt 是显式本地 fixture 的 purchase=1，其余状态 0。预览原生图通过 [shop_native_assets.cjs](../../tools/purple_ui_10h/shop_native_assets.cjs) 从官方 VPK 解码，aliases 仅用于浏览器；不替换运行时 Dota 图标。浏览器 shrink/native DOTA widgets 仍是适配模拟。

原生证据是 `work/native/*.png` 与同名 `kind=actual_game_capture` 元数据。本说明确认已有的 [c06_archive.png](work/native/c06_archive.png)（真实44条通关记录/筛选）、[c06_commerce.png](work/native/c06_commerce.png)（真实25种商品）、[c08_shop.png](work/native/c08_shop.png)（四件商品名称/库存/footer）独立截图；其余最新原生状态由 root 继续复核并更新 BEST_VERSION。浏览器四尺寸通过不代表这四个引擎分辨率均已测试，也不代表其它类别、原生 tooltip 或所有菜单已完成实机验收。

后续本人只读实看 [c11_shop_textbox_battlefield.png](work/native/c11_shop_textbox_battlefield.png)，确认四商品名称文本盒自身居中；[c12_shop_native_mouse_hover.png](work/native/c12_shop_native_mouse_hover.png)、[c12_commerce_true_state.png](work/native/c12_commerce_true_state.png)、[c12_daily_rules_native.png](work/native/c12_daily_rules_native.png) 则记录半透明透字、科技统一占位、名称左起及规则 tooltip 重叠等具体偏差，不能把这些前版图片算作问题已修复。新 C13 原生 [c13_shop_opaque_hover.png](work/native/c13_shop_opaque_hover.png) 确认 Shop A12 底材/tooltip 不再透字，[c13_commerce_distinct_icons.png](work/native/c13_commerce_distinct_icons.png) 确认 A13 真实25科技使用不同现存Dota图且名称居中，[c13_daily_rules_no_stale_tooltip.png](work/native/c13_daily_rules_no_stale_tooltip.png) 确认 A05 不透明且无旧 tooltip。A13 浏览器四尺寸显式真实wallet25目录/15与10分页图标与名称报告 [final_commerce_a13_report.json](work/qa/final_commerce_a13_report.json)，Daily A05 真实鼠标规则互斥报告 [final_daily_a05_pointer_report.json](work/qa/final_daily_a05_pointer_report.json)。商品图主题选择与 canonical SKU 对照见 [ShopIterations.md](ShopIterations.md)，未改 CSV / backend / payment 数据。

C13仍有两个具体验收差异：生存店分类按钮下露旧青底，是公共 ModalShell 写入 header inline surface_teal、48高header与44高tab空隙共同造成；9行每日真实规则框固定516高留白过多。Shop A14 只将 header inline 背景改成窗底 #100b21；Daily A06 只改变规则框 height:fit-children/max-height:516px。两组真实controller回归/语法通过，具名源检查点分别 [shops_native_header_surface_a14](work/checkpoints/shops_native_header_surface_a14/source_hashes.json)、[daily_rules_autofit_a06](work/checkpoints/daily_rules_autofit_a06/source_hashes.json)，前版与 C13 截图均保存。本人后续只读实看 [c14_shop_header_purple.png](work/native/c14_shop_header_purple.png) 确认青条消失、原tooltip与四商品完整，[c14_daily_rules_compact.png](work/native/c14_daily_rules_compact.png) 确认真实九行规则收紧且没有旧tooltip。浏览器补充四尺寸报告 [final_shop_a14_report.json](work/qa/final_shop_a14_report.json)、[final_daily_a06_report.json](work/qa/final_daily_a06_report.json)、[final_daily_a06_pointer_report.json](work/qa/final_daily_a06_pointer_report.json) 还验证50行长规则滚到底与奖励说明互斥；原生仅确认当次1600×900状态。

C14 原生商城详情是单独的前版未通过项：[c14_commerce_tooltip_diagnostic.png](work/native/c14_commerce_tooltip_diagnostic.png) 中商品已选中、tip shown/visible=true且260×376在屏内，仍未绘制。Commerce A15 把原完整详情放到该 CommercePurple 窗口的专用浮层，保留祖先紫色CSS、原body/价格/购买路由/卡片布局，按 source card 与 layer 屏幕 origin、实际UI scale定位；render/close/Dispose删除所属tip，close/reopen保留相同卡片并只重建详情。严格原生删除与scale/edge/orphan回归、原catalog-ui与checkout回归均通过，具名候选 [commerce_native_layer_a15](work/checkpoints/commerce_native_layer_a15/source_hashes.json)。真正刷新新XML/factory后的 [c15_commerce_loaded_layer_hover.png](work/native/c15_commerce_loaded_layer_hover.png) 已由本人只读实看：首件 tooltip 绘制、真实6800 U币/暂不可购/查看兑换与权益正文区均完整；首次C15截图仍使用无DetailLayer的旧Window，不计为新结构失败。

C15 新详情仍淡透背后名称。Commerce A16 只把自有CSS tooltip gradient 两端 #211630fc/#0d091bfc 改为不透明六位色，几何/业务/JS逐字节保持；最小diff断言与commerce回归通过，候选 [commerce_native_opaque_a16](work/checkpoints/commerce_native_opaque_a16/source_hashes.json)，前版 [commerce_native_opaque_before_a16](work/checkpoints/commerce_native_opaque_before_a16/source_hashes.json) 保留 C15 源和原生图。root C16已确认首卡不透字及按钮hover，C17/C18后版也保留完全不透明底材。

C16 [c16_commerce_edge_tooltip.png](work/native/c16_commerce_edge_tooltip.png) 第五列仍被所属商城window右界裁掉。Commerce A17只调整原place()：按所属window实际bounds与viewport安全bounds交集定位，保留间隙/左翻转/按已测高度向上限位及原inner/outer滚动。strict-native模型先在A16失败、修复后21边界项通过，完整50行effect/目录不变和原购买/close-reopen卡片身份/销毁回归保持，报告 [commerce_a17_clip_report.json](work/qa/commerce_a17_clip_report.json)。root C17真实鼠标第五列 [右上左翻](work/native/c17_commerce_top_right_flip.png)、[右下向上限位](work/native/c17_commerce_bottom_right_clamped.png)、[关闭重开后hover](work/native/c17_commerce_reopen_edge_hover.png) 与 [ESC关闭](work/native/c17_commerce_esc_closed.png) 通过；本人已实看前两图确认整个详情/真实价格/按钮在窗内。四尺寸browser明确模拟window clip，16项first/rightmost/bottomright/50行定位通过，见 [final_commerce_a17_report.json](work/qa/final_commerce_a17_report.json)。窗内相邻商品可能被详情覆盖，这是保住原生可绘制范围的定位代价；旧A15/A16 viewport-only边缘报告不证明window clip通过。

A17长effect的真实wheel仍曾失败：[c17_commerce_effect_scrolled_end.png](work/native/c17_commerce_effect_scrolled_end.png) 连续滚轮后还是头部。旧browser直接调用Panel.ScrollToBottom只证明程序化滚动和内容存在，不能称为物理滚轮验收。Commerce A18仅增加RCProductEffect Label的hittest=true，使已显示tooltip的hittestchildren=true时正文可命中；CSS、价/资格、按钮、目录、所有定位和释放策略保留。strict命中模拟 [commerce_a18_wheel_report.json](work/qa/commerce_a18_wheel_report.json) 尊重目标/祖先有效性与hittestchildren，不伪造Label offset。后版browser用实际CDP mouseWheel、没有ScrollToBottom API，四尺寸×真实8行/50行压力样例共8流程末行可读，价和购买目标完整，见 [final_commerce_a18_physical_wheel_report.json](work/qa/final_commerce_a18_physical_wheel_report.json)；8项物理source→gap→detail→action和4项close/reopen/category/page生命周期也重新通过，见 [pointer](work/qa/final_commerce_a18_pointer_report.json) / [lifecycle](work/qa/final_commerce_a18_lifecycle_report.json)。root C18真实游戏 [wheel前](work/native/c18_commerce_long_before_wheel.png) → [wheel后](work/native/c18_commerce_long_after_wheel.png) 已由本人只读实看：实际末行“星悦积分×68”露出、6800 U币与原查看/兑换按钮保留；后续 [按钮hover](work/native/c18_commerce_wheel_to_button_hover.png)、[ESC](work/native/c18_commerce_final_esc.png)、[重开右下详情](work/native/c18_commerce_final_reopen_bottom_right.png) 也实测通过，本人复看按钮和重开图确认整窗内可读。没有点击兑换。原生只实测当次1600×900，不能称四个引擎尺寸均验收。

抽奖L05仅修 [lottery_ui_remaining_5d5c1152eb.js](../../panorama/src/scripts/custom_game/lottery_ui_remaining_5d5c1152eb.js) 的rewardDetails Note：品质后只在服务端提供duration_text时追加时长，缺字段不加分隔或“永久”。L05原mock的Panel.visible不等于CSS实际可见，旧样式仍collapse，因此那版只称语义通过。L06由 [menu_purple.js](../../panorama/src/scripts/custom_game/menu_purple.js) 给真实reward视图Note内联visibility=visible、margin=0/background透明；L06曾把history一并collapse，会丢掉原“本局最近30次/跨局未接入”，因此这个历史隐藏策略已经淘汰。L07按 [原remaining.css](../../panorama/src/styles/custom_game/remaining_5d5c1152eb.css) 的history/update既有visible语义修正为reward/history/update visible、其它collapse；update只在没有活Purple hook时沿旧坐标，紫色窗保持773脚注，不碰共享chrome。最新 [lottery_l07_note_contract_report.json](work/qa/lottery_l07_note_contract_report.json) 经真实result card onactivate验证7天/缺时长和Note.style.visibility，另验证history原30次/跨局限制文本、update本地服务端快照样例的日期/完整摘要/脚注坐标、details collapse、奖励行不变和操作计数不变，L04原套件仍通过。最终L07生产XML/CSS/controller浏览器四尺寸×known/unknown/history/update共16项通过，见 [final_lottery_l07_popup_report.json](work/qa/final_lottery_l07_popup_report.json)；真实CSV的map公告没有effective_date，界面按原规则显示“奖池配置已更新”，保留原title/summary，没有填造日期。root C19原生 [历史范围说明](work/native/c19_lottery_history_scope_preserved.png) 已由本人实看，实际0条记录空状态仍显示本局30次/跨局未接入脚注；这条history呈现已实机通过。游戏未触发真实抽奖，没有result流程的真实结果，L05/L06/L07没有原生结果卡验收；主页面/实际奖池详情/记录标题/tooltip的其它原生证据不能代替此项。

最终C19编译与恢复配对已独立只读核对：[final_integration_peer_report.json](work/qa/final_integration_peer_report.json) 验证manifest的35 source/35 runtime共70条保存字节与当前目标一致，并与35条成功compile记录的sourceHash/compiledHash及实际Content输入逐项匹配，差异0。这项检查没有再次编译、恢复文件或操作游戏。

原生工具 [native.cjs](../../tools/purple_ui_10h/native.cjs) 的实际具名截图用法是 `node tools/purple_ui_10h/native.cjs --menu shop --capture <unique_name>`：它找当前 Tools review command、调用现有菜单并保存引擎截图/TGA转换记录，不创建交易。该命令会操作正在运行的游戏，由原生验证执行者使用；本说明没有执行它。

本轮未真实支付、扣款、兑换、抽奖或领取发放。现金 QR 是明确不可付款的布局矩阵；账号余额、库存、资格和 pending/receipt 样例不等于实际账号结果。开局/战斗必选、瞄准输入、销毁战斗建筑、TAB 属性覆盖层等范围没有因为普通菜单迁移而新增交易或改键；实际范围见 MenuCoverage。


<!-- standalone-shop-c25 -->
## 当前C25独立商店接入

最新交付见[StandaloneShop.md](StandaloneShop.md)。生存店沿原SurvivalShop API与ModalShell输入层，使用PurpleShell.Detach移出共享外框；两个旧布局助手对ShopStandalone返回，避免覆盖左侧位置。共享顶部导航不包含shop，原HUD入口仍打开该店。Tooltip XML新增ShopTooltipFrame并使用正坐标尖角空间，样式为shop_purple.css；没有改服务端、目录CSV或底部战斗HUD。

**恢复更新：上文C19模板仅为历史示例，当前检查点应使用work/checkpoints/best_standalone_shop_c25。** 三十五份源码与三十五份运行产物已跟三十五个Content输入及编译记录独立SHA核对差异0。先备份当前目标、校验manifest、只恢复所需目标，再做相关验证和具名编译；不得整仓覆盖其它人的改动。最终生产完整143源digest为6fb899933e2bcd6e9a3a6fee14ca50fcaa5ba8f4ee97823a2b7fd14b0536bba3。

实机范围见work/native_shop_standalone_acceptance.json；浏览器四尺寸不等于四个引擎尺寸。临时启用的展示入口已恢复，真实英雄前置和购买资格保持，未触发交易。
