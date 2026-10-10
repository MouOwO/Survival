# 每日奖励紫色弹窗迭代

修改前真实活动 controller 已按字节保存在 `work/baseline/source/panorama/src/scripts/custom_game/daily_remaining_5d5c1152eb.js`，SHA256 `9EEDB0B1784A2800C53078FFE7D4A7AA14D3CAC20F50C1C1E89B420B0DA60FAF`。原始浏览器截图：`work/daily_baseline/1920x1080_daily_normal.png`、`1280x720_daily_normal.png`。

| 候选 | 对照发现 | 调整 |
| --- | --- | --- |
| A01 实数奖励紧凑布局 | 原页面 1344×752 使用 1672×941 fit 基准，旧蓝灰底与全局导航不统一，详情占单元空间。 | 1280×800、1920×1080 fit，共享紫色导航 / 货币栏，内容从 y145。7 个真实日组排成 4×2，最后一格为服务端独立通行证奖励。每件仅原项目图标、可选数量角标、下方名称；效果进入金字紫色 tooltip。真实 CSV 第 5 / 6 日各两件，合计 9 reward 槽，不填假奖励。 |
| A02 复看与边界 | 实看 A01 首次 hover 误选 day 组而非 reward，QA 修正操作后 tooltip 正常；通行证 3 项左偏、锁图放大模糊。 | 累计 7 / 14 / 21 次真实通行证奖励居中，返回与购买按钮对齐公共 footer；未配置奖励锁缩为 56×64。缺少数量不假定 1，显式 0 保留。Tooltip 0.18s 间隙延迟隐藏，进入可取消，窗口内翻转 / 限位，原生 panel 已删除时延迟定位安全返回。 |
| A03 奖励说明浮层 | 全链最终复看 `captures_final_style/1920x1080_daily_rules_crop.png` 显示规则仍继承 ReferenceWindows 的 inline 青色，文字宽度超出 popup 右界。 | controller 显式覆盖规则浮层紫色渐变 / 金边，912 外宽、28 padding、正文 840 宽并正常换行，留出滚动余量；19px 正文 / 28px 行高，z150。严格 native 失效方法 mock 回归涵盖每日旧 subtree 删除与新 controller 重建。 |
| A04 规则段落 | A03 浏览器规则四分辨率右界检查全部通过，实看正文 `white-space:normal` 将原换行合并，累计奖励各项挤在同段。 | 使用项目既有 HTML Label 方式，服务端纯文本先转义 `&<>`，原换行转换为 `<br>`，正常自动折行同时保留规则 / 补签 / 各累计奖励段落。增加精确分段和文本转义回归，业务数据不变。 |
| A05 原生规则与 tooltip 互斥 | 只读实看主代理真实鼠标 C12 hover / rules 图：打开规则后旧成长宝石 tooltip 仍挡正文，两个半透明表面透出背后图标 / 名称。 | 原规则 toggle 的 hide 保留；新增 tooltip 资格判断：controller / window 有效且窗口已打开，实际规则子 panel 处于 ArchiveHidden 才能显示；背后 reward hover 和旧 tooltip mouse-enter 都不能再开或保留 tooltip。规则 JS / CSS fallback 与 tooltip gradient 去除 alpha，金边 / 字号 / 原生 lifetime / 912×516 尺寸保留。关闭规则后新 hover 恢复。 |

当前源码 checkpoint：`work/checkpoints/daily_compact_real_a04/source_hashes.json`；前版 A02 / A03 仍保留。接入仅在活动 `panorama/src/layout/custom_game/archive.xml` 新增 `daily_purple.css` include，复用既有每日 controller；未新建 JS 控制器或修改 backend。

A05 最新源码 checkpoint 为 `work/checkpoints/daily_rules_tooltip_a05/source_hashes.json`，A04 及本轮修改前 `daily_rules_tooltip_before_a05` 均保留；后者含主代理原生 `c12_daily_native_mouse_hover.png`、`c12_daily_rules_native.png` 的具名副本。A05 daily_verify / test_daily_ui / JS syntax 已通过：严格 native panel 下执行 hover → toggle rules → 背后 card mouseover / tooltip mouseover / 旧 0.03s 回调 → tooltip 仍隐藏无请求 → toggle 关闭 → fresh hover 恢复；原领取 / 补签 / 通行证守卫及删除 subtree 重载回归继续通过。本轮先修互斥与 opaque 两项，未未经测量调整规则框高度；新的浏览器 / 原生视觉效果由预览代理与 root 的 C13 分别复核，不沿用 A04 图片冒充新证据。

A06 规则高度：root C13 实机 `work/native/c13_daily_rules_no_stale_tooltip.png` 已确认规则底材不透明、无旧 tooltip；9 行真实规则仍使用固定516高度，底部留白过多。本轮仅高度策略一变量：JS inline 与 CSS fallback 同为 height:fit-children / max-height:516px，位置184,164、外宽912、正文840、padding28、19px字体/28px行高、金边与 squish scroll 均保持。现有 body 已 fit-children，短文本随内容收紧，长文本保留上限及完整可滚动正文。daily_verify 新增真实controller配置/长50行规则全部保留与转义/无额外请求断言，原 hover→rules→背后hover/旧延时→reclose→freshhover互斥、领取/补签/通行证防重、deleted native subtree 重载仍 PASS；test_daily_ui与语法也 PASS。修改前 `daily_rules_autofit_before_a06` 保留C13具名截图，当前 `daily_rules_autofit_a06` 保存源/test/SHA。Mock验证配置和完整业务文本，实际短框高度、长规则触底滚动由新浏览器及 root 新实机分别复核，不以 mock 模拟结果替代引擎证据。

A06 后版验证完成：预览代理四尺寸20项常规/长规则与4项真实 pointer 互斥通过，报告 `work/qa/final_daily_a06_report.json` / `final_daily_a06_pointer_report.json`。真实短规则未缩放高282（小于516），50行压力样例保持最大516、scrollHeight1652，滚到底第50行与真实累计14/21段完整可见，正文/页底不越界，未领取或交易。本人实看 `captures_final_components/1920x1080_daily_rules_crop.png` 与 `qa/1920x1080_daily_rules_long.png` 确认短内容留白收紧、长内容可读；另只读实看 root 的真实 `work/native/c14_daily_rules_compact.png`，九行服务端规则在收紧后的不透明框内完整显示，无旧 tooltip，7天/14天/21天奖励段保留。原生证据是当次1600×900截图，浏览器四尺寸结果不推为四个引擎尺寸均通过。

服务端累计签到 / 7 日循环、独立 premium 领取、最早漏签日补签、30 天通行证、7 / 14 / 21 次奖励、序号 / 日期防旧响应、busy 防重复请求保留。现有配置 `purchase_enabled=0`、价格待配置、周末装备池未配置，界面明确不可购买 / 暂未开放；没有补造金额或装备。

第一轮候选截图：`work/captures_tertiary_a01/1920x1080_daily_normal_crop.png`（真实不同奖励，0 errors / 0 missing）、`work/captures_t02/1280x720_daily_hover_crop.png`（成长宝石真实效果与数量 3）、`work/captures_tertiary_a01/1920x1080_daily_pass_crop.png`（真实 3 累计奖励与禁用购买）。

最终 A04 全链 139 依赖快照，4 分辨率 × normal / hover / pass / rules = 16 cases 全通过，报告 `work/qa/final_daily_report.json`。最新 1080 / 720 四状态图片与报告已一并保存在 A04 checkpoint。本人实看最终 1080 规则截图：紫色背景、金边、7 / 14 / 21 各自分段。1080 rules panel x505 / right1417 / width912，body x534 / right1374 / width840，右留43；正文 scrollWidth = clientWidth = 840，其他三分辨率按比例均无右溢出。

验证通过：

```text
node tools/purple_ui_10h/daily_verify.cjs
node tools/test_daily_ui.js
```

新回归实际执行活动 `daily_remaining_5d5c1152eb.js`、真实公共 ModalShell / PurpleShell、项目原图组件与每日 CSV。本地 mock 捕获请求，涵盖 7 组 / 9 单元、真实累计通行证奖励、可选服务端数量、hover 无领取、间隙、加载超时与重试、busy / failed / confirmed 领取、旧序号与日期、独立 premium、最早漏签、配置禁用购买不发请求、显式开放按钮仅发一次原请求、关闭 / unsubscribe 和原生已删除 subtree 后重载无交易。没有向游戏或支付端发出交易。

浏览器与 mock 能验证资源 / UI / 请求路由；最终 Panorama 编译与实机截图由主代理负责。
