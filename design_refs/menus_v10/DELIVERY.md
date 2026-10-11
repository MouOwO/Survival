# V10 菜单接入交付说明

存档、宝物、抽奖、商城、生存商店、每日奖励、VIP，以及商城兑换和支付确认，现在共用 V10 紫色星云外壳。顶部导航、左侧分类、资源栏、关闭按钮和上下暗金线沿用已确认组件。切换分类只更新右侧内容和选中态；正式数据、升级、抽奖、购买及退款等行为继续使用原接口。

## 查看可运行预览

新 checkout 先运行 `node tools/archive_v10/import.cjs`，从已提交原包重建本地源 PNG 与存档编译范围。

在项目根目录运行：

```powershell
node tools/menus_v10/preview.cjs
```

随后用 Chrome 打开 `design_refs/menus_v10/work/preview/index.html`。可以在地址末尾添加：

| 页面 | 参数 |
| --- | --- |
| 存档 / 虚空之影 | `?page=archive&category=shadow` |
| 生存商店及购买 Tooltip | `?page=shop&state=hover` |
| 商城及商品详情 | `?page=commerce&state=hover` |
| 宝物 | `?page=treasure` |
| 抽奖详情、记录 | `?page=lottery&state=details`、`?page=lottery&state=history` |
| 每日奖励 / 通行证 | `?page=daily`、`?page=daily&state=pass` |
| VIP 礼包 | `?page=vip&state=packages` |
| 商城兑换确认 | `?page=wallet_checkout` |
| 原有支付确认 | `?page=paid_checkout` |

这个预览实际加载当前工程的 XML、JS、CSS 和原组件；名称、商品及效果定义来自项目 CSV。持有量、余额、冷却和解锁状态使用明确标注的预览快照，不写入正式存档，也不连接游戏、账户、支付、抽奖或领奖接口。浏览器对 Panorama 布局、原生图标和场景组件的模拟不能代替游戏内验收。

自动生成多分辨率截图及导航检查：

```powershell
node tools/menus_v10/acceptance.cjs
```

需要本机 Node.js 和 Chrome。截图保存到 [work/final](work/final/)，验证记录见 [report.json](work/final/report.json)；组装来源及预览限制见 [assembly.json](work/preview/assembly.json)。截图左下角有“生产 XML / JS / CSS · 显式浏览器样例 · 未连接游戏、账号或支付”标记。

## 主要修改

| 文件范围 | 内容 |
| --- | --- |
| `panorama/src/scripts/custom_game/common/menu_v10.js`、`styles/custom_game/common/menu_v10.css` | 共享外壳、统一等比缩放、导航、分类、资源栏、图标单元及 Tooltip 九宫格；生命周期和业务面板移动保持原上下文。 |
| `common/purple_shell.js`、三个页面 XML | 菜单路由及公共模块接入；关闭上一页后打开目标页，避免多个窗口叠加。 |
| `archive_v10.js`、`archive_*titles_compact_v6.js`、`archive_handoff_180de7e38b.js` | 存档沿用固定外壳和动态单元；虚空之影保留正式配置、数量语义和 Tooltip。 |
| `shop_remaining_5d5c1152eb.js`、`shop_tooltip_remaining_5d5c1152eb.js` | 生存商店、挑战和研究入口进入统一外壳；保留商品筛选、资源、库存、前置条件、队列、购买及自动购买。 |
| `common/commerce_components.js`、`commerce_remaining_5d5c1152eb.js`、`commerce_wallet.js`、`payment_test.js` | 商城每页 24 项，图标、数量和名称统一；商品详情、兑换及原有支付确认进入同一外壳，原 SKU 和请求流程保持不变。 |
| `lottery_*`、`menu_purple.js` | 抽奖主页、详情、历史和结果适配；保留奖池切换、演出和开奖行为。 |
| `treasure_history.js`、`daily_remaining_5d5c1152eb.js`、`vip_window.js` | 宝物历史、每日奖励、通行证及 VIP 复用外壳、单元和 Tooltip。 |
| `menus_v10_commerce.css`、`menus_v10_lottery.css`、`menus_v10_archive_pages.css` | 各页内容的局部样式，公共材质和九宫格不在各页重复实现。 |
| `tools/menus_v10/`、`tools/tests/menus_v10_*` 及相关业务回归测试 | 生产组件预览、截图比较、指定文件编译和业务验证。 |

正式页面直接使用 `panorama/images/custom_game/archive_v10/` 已有组件与思源黑体，没有重新生成相似外壳。旧独立紫色外壳、重复窗口装饰及相关 `*_purple.css` 接入已移除；旧独立 `lottery_window.xml` 已删除。对应 Content 的 10 个废弃源文件也已备份后移除，见 [retired_content.json](work/retired_content.json)。为了兼容现有控制器，部分旧业务 ID 作为隐藏锚点保留，不再绘制旧布局，也没有可切回旧格局的显示分支。底部 HUD 保持独立。

## 验证结果

- 浏览器生产组件验收覆盖 9 个页面 × 4 种分辨率，共 **36 个页面状态**：1280×720、1600×900、1920×1080、2560×1080。
- **5 次顶栏切换**验证每次只显示一个菜单；另检查 **9 个详情状态**，涵盖长存档说明、商城与商店 Tooltip、抽奖详情及记录、每日奖励、通行证和 VIP 礼包。
- 最终报告中的脚本异常为空；外壳位于视口内，旧紫色装饰没有继续显示，虚空之影可见单元为 23 项。
- 商城与生存商店相关生产源码回归 **17/17 通过**，覆盖真实目录合并、24 项分页、兑换与支付路由、重复快照不重建 DOM、资源增量、库存、研究队列、前置条件、冷却、自动购买和过期响应。
- 其他页面的业务回归覆盖分类、奖励与数量语义、关闭后刷新、热重载、已移动节点查找、抽奖流程及 Tooltip。游戏内数据和请求仍由原服务端校验。
- 指定 **25 个 JS / CSS / XML 源文件**已通过 Dota 2 原生资源编译；编译范围、源文件到 Content 的一致性及产物记录见 [compile_scope.json](../../tools/menus_v10/compile_scope.json) 和 [compile.json](work/compile.json)。编译工具为 `tools/menus_v10/compile.ps1`，仅同步列出的源文件，并为原文件与产物保存备份。

游戏内已取得 1600×900 存档截图：[通关存档](work/native/archive_clear.png)、[虚空之影](work/native/archive_shadow.png)。旧青色外框已清理，分类可切换。其他菜单的完整游戏内验收尚未完成：更新后新控制器初始化日志已确认无 JS 异常，但新的工具对局在确认 N1 后直接进入失败结算，原生 F9 无法在结算状态暂停。重复尝试仍被结算遮罩阻挡，记录放在 work/native_attempts/。这是当前测试会话的阻塞，未据此修改游戏逻辑。

此前旧 HUD 脚本没有随资源编译重载，造成商城和抽奖仍呈现旧运行实例；这些截图已淘汰，不能作为本版验收图。survival_hud.xml 现声明 MenuV10Context，完整新执行链可通过 [COMMERCE_JADE_COMMANDS] 和 [LOTTERY_V10_READY] 的初始化时间核对。实际组装总览见 [gallery.html](gallery.html)，它明确区分生产组件浏览器预览和游戏截图。

恢复实机验收：启动 survival 的 template_map 工具测试；等待测试后端准备；先保证测试对局可保持运行，再打开各 HUD 菜单入口及统一顶栏切换。勿用旧实例的截图替代新执行链。工具 tools/menus_v10/window.ps1 只在核实 survival tools 进程、前台窗口和物理坐标后发送菜单点击/指针/F9，并保存截图。当前新 V10 产物已在 Game 路径，正式定义仍来自项目 CSV/服务端快照。
## 尚存差异

- VIP 沿用项目现有图标，没有制作新的成套 VIP 美术。
- 部分商城商品在正式 CSV 中共用属性水晶图；本轮保留原数据和图标配置，未把预览数字或示例图写入正式配置。
- Dota 2 长方形物品图标在方形单元内保持比例，可能留下上下留白；没有拉伸或重画原图。
- 排行榜沿用尚未接业务的禁用状态。
- 原有支付流程只迁移界面，没有新增支付通道；本地预览中的支付按钮不会连接真实支付。
