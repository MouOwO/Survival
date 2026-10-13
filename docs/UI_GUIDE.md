# 当前 UI 接入与文档入口

存档现在采用独立的旧纸纹两栏界面：左侧青灰分类列表，右侧黑褐条目、橙金进度条，不再显示一级导航和公共资源行。依据是[用户确认效果图](../design_refs/archive_parchment_v1/approved.png)，材质与控件清单见 [asset_manifest.json](../tools/archive_parchment/asset_manifest.json)。每日登录也已独立，采用金色皇冠、月相和蓝黑笔刷底板，28 格免费奖励按 7 列 × 4 行排列，右侧为方形蓝框战令奖励。宝物、抽奖、商城、生存商店、VIP，以及兑换和支付确认仍采用 V10 紫色公共外壳；其几何与验证范围见 [V10 菜单交付](../design_refs/menus_v10/DELIVERY.md)。存档原业务说明仍见[存档数据与交互](../design_refs/archive_v10/Delivery/DATA_AND_INTERACTIONS.md)。历史外壳不能覆盖独立存档和每日登录布局。

## 实际入口

入口由 [custom_ui_manifest.xml](../panorama/src/layout/custom_game/custom_ui_manifest.xml)及三个活动布局决定：`archive.xml`、`survival_hud.xml`、`payment_test.xml`，均位于 `panorama/src/layout/custom_game/`。公共 V10 实现在 `panorama/src/scripts/custom_game/common/menu_v10.js`、`panorama/src/styles/custom_game/common/menu_v10.css`；独立存档继续由 `archive_v10.js` 适配真实控制器，`archive_parchment_data.js` 提供新材质，`archive_v10_data.js` 保留原物品图标与必要契约。应沿 XML 的实际 include 顺序检查依赖，不能按历史文件名推断入口。

作者源码位于 `panorama/src/`；运行资源位于 `panorama/layout/`、`panorama/scripts/`、`panorama/styles/`。后缀分别为 `.vxml_c`、`.vjs_c`、`.vcss_c`。资源编译成功后仍需确认新 HUD 执行链已加载，避免把旧闭包和旧截图当成本版效果。

## 素材、编译与验证

独立存档的无字材质由 imagegen 从确认图提取，源图保存在 `design_refs/archive_parchment_v1/`；`tools/archive_parchment/split_assets.py` 按固定坐标拆出 37 个 PNG，生成哈希清单、材质数据和编译用资源布局。标题、搜索文字、分类名称、数量及进度均由独立控件绘制。正式源 PNG 位于 `art/ui/sources/custom_game/archive_parchment_v1/`，脚本同步一份至被忽略的 `panorama/src/images/custom_game/archive_parchment_v1/` 供编译。默认字体沿用已安装的思源黑体，标题与分类使用宋体。

存档验证与编译使用独立范围，避免重写其他菜单：

```powershell
& 'C:/Users/Administrator/AppData/Local/Programs/Python/Python314/python.exe' tools/archive_parchment/split_assets.py
node tools/archive_parchment/build_scope.cjs
& tools/archive_parchment/compile.ps1 -CheckOnly
node tools/archive_parchment/preview.cjs
node tools/archive_parchment/acceptance.cjs
& tools/archive_parchment/compile.ps1
```

`-CheckOnly` 只核对来源、哈希和依赖；实际编译会先保存 Content 与 Game 产物的具名备份，再更新限定范围，失败恢复。本次预览、组件总览与检查报告位于 `design_refs/archive_parchment_v1/work/`，属于可重建输出。浏览器使用隔离样例，不连接账户或发出升级、抽取请求；真实游戏渲染仍需单独核验。不要再运行旧 `tools/archive_v10/import.cjs` 覆盖当前存档材质接入。

2026-10-13 已通过 43 个原生资源的编译及产物核验、5 种尺寸和 18 分类的浏览器检查，以及进度语义、图标、Tooltip、生命周期和业务点击回归。最终组装截图由 `node tools/archive_parchment/capture.cjs` 保存至 `work/final/`；状态文字按可见纸面下缘验证，不能只检查透明画布边界。本次未执行游戏客户端内的视觉验收。

侧栏保留 18 个真实分类，支持搜索和滚动；“商城道具”未启用时保留真实空态。横条进度来自 `ArchiveV10Semantics.Progress`：地图等级使用等级而非在线分钟，神兵碎片使用持有余额而非晋升级数；未知或无目标时不填造进度，超额只限制填充长度，文字仍显示真实值。升级、神兵晋升、称号穿戴和社交抽取继续走原控制器。

旧版存档原始包保留在 `design_refs/archive_v10/package/archive_ui_final_v1/`，包括仍在使用的物品图标、PNG、SVG 编辑稿、资源清单和字体许可。不能删除原包或拿示例数量替代正式配置。

其他 V10 菜单从项目根目录按需要执行：

```powershell
& tools/menus_v10/compile.ps1
node tools/menus_v10/preview.cjs
```

编译范围清单分别位于 `tools/archive_v10/compile_scope.json` 和 `tools/menus_v10/compile_scope.json`，应先审阅再执行。`design_refs/*/work/` 仅保存可重建的预览、截图与报告。编译需要同步到引擎 Content 目录；仅拉取 Game 仓库不会自动更新 Content。保留每次具名备份、源文件与产物哈希，不用旧整套检查点覆盖当前 XML 和其他功能。图标配方的 LF 与编译依赖问题另见 [存档纹理重编译](ARCHIVE_TEXTURE_BUILD.md)。

浏览器预览运行实际 XML、JS、CSS，使用明确标记的隔离状态；其截图、缓存和报告可以重建。原生图标预览首次导出及自动检查命令见 [存档工具说明](../tools/archive_v10/README.md)。浏览器通过、Lua/Node 测试通过、资源编译通过分别记录，均不能替代游戏内鼠标、滚轮、字体、裁切和热重载验收。当前完整实机矩阵的边界以 V10 交付说明为准。

## 保留的业务边界

每日登录当前执行 `daily_remaining_5d5c1152eb.js`，由 `daily_gw2_data.js` 和 `daily_gw2.css` 提供独立外壳。`tools/daily_gw2/split_assets.py` 从 imagegen 生成的无字底板及控件图集中拆出 19 个组件，正式 PNG、源图与提示分别保存在 `art/ui/sources/custom_game/daily_gw2_v1/`、`design_refs/daily_gw2_v1/`。先运行拆分、`build_scope.cjs` 和 `compile.ps1 -CheckOnly`，再执行 `preview.cjs`、`acceptance.cjs` 与实际 `compile.ps1`；最终视觉刷新用 `capture.cjs`，输出位于该参考目录的 `work/`。

28 格由服务器 `calendar28` 快照展开正式七次循环四轮，保留原 `cycle`、`period_id` 和发奖逻辑；第 5、6 次的两项奖励都要展示。右栏三项真实战令奖励为累计 7、14、21 次的一次性里程碑，第四位置是购买和有效期信息。购买价格及 provider 当前未配置，界面按服务器状态显示暂未开放；购买不能在客户端解锁资格，已达标奖励仍在下一次有效签到时结算。补签请求使用服务器日历日期，不能发送 1–28 展示格号。宝物背包参考的去菜单、空网格美术稿保存在 `design_refs/treasure_gw2_v1/empty_inventory.png`，该图尚未作为游戏背景接入。

- 存档的分类、数量、进度、升级、神兵晋升、社交抽取与称号操作继续使用原服务端接口。未知数量、期限和资格不填造默认值；同局共享奖励按[联机奖励规则](COOPERATIVE_REWARD_RULES_20261011.md)结算。
- 生存商店保留真实目录、金币/木材、前置条件、库存、冷却、自动购买和科技队列；商城保留账户币种、原 SKU、价格和权益。悬停与选中不创建交易，只有原明确购买动作提交请求。
- 钱包兑换重试使用原未确认 token；现金订单的 pending 金额与奖励不随目录变化而重算。二维码、可信付款入口和到账凭据沿原支付流程处理。
- 每日奖励、补签、通行证、VIP 的资格、防重和领取状态保持个人隔离。队友权益不用于本人发奖；没有配置的价格和奖励不冒充已经开放。
- 普通菜单关闭与切换尊重现有层栈、pending 和 mandatory 守卫。难度选择、英雄/肉鸽必选、瞄准输入、建筑销毁确认与 TAB 战斗属性层保持各自输入流程；官方返回、设置等入口继续使用原生界面。排行榜没有权威数据时保持未开放。
- 生命周期检查使用所属有效上下文；关闭、删除和重载后取消旧定时器与订阅，迟到响应不得访问已删除面板。底部战斗 HUD、头像与生产队列仍有独立接入规则。

需要修改规则时优先阅读[存档业务契约](archive_data_contract.md)、[抽奖数据契约](lottery_data_contract.md)、[奖池更新](lottery_pool_updates.md)、[存档服务器接入](archive_server_integration.md)、[商城 CSV 说明](payment_shop_csv_guide.md)、[U 币兑换](payments/ucoin_checkout_20261011.md)和[建筑生产队列](BUILDING_PRODUCTION.md)。菜单外观文档不取代支付、奖励或战斗配置。
