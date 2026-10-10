# 商城与生存商店紫色 UI 迭代

本记录仅描述商店代理拥有的候选文件。共享顶部导航、货币栏和 XML includes 由主代理管理。预览加载实际生产组件、共享壳与真实 CSV，账号、库存、货币使用明确标注的本地示例；没有连接游戏、账号或支付。

## 保留的行为边界

- 生存商店保留服务器解锁、实际 `shop_id` 分类、库存与购买限制、科技前置、冷却、研究所来源、研究执行别名、自动书与自动研究请求。单击普通单元只选中 tooltip；明确点击 tooltip 的购买按钮或原有右键路径才请求购买。科技左键原行为保留。
- 商城保留目录、现有类别、礼包奖励与数量、服务器价格、货币账户、结算入口以及抽奖门票路由。hover 与选择不会下单，tooltip 的动作继续调用原控制器。
- 保留原 `ModalShell` 的 ESC、遮罩、关闭、层管理与 fit。共享壳仅装饰与导航，不移动跨 context 内容。

## 候选与差异复看

| 迭代 | 证据与发现 | 落地调整 |
| --- | --- | --- |
| A01 固定 1040×760 生存商店 | `work/checkpoints/shop_fixed_760/` 保留源码与 1920/1280 截图。实际装备只有 4 件，固定高度留白明显。 | 首先保留可回滚 checkpoint，再比较短窗。 |
| A02 四列原生图标与精简单元 | 按真实 CSV 装备 4、其他 6、挑战 21 件，未填充虚假商品。旧预览混入挑战的 fixture 已修正。 | 图标、可选右上数量、下方名称；价格、描述、购买移入紫色金边 tooltip。研究代码与锁定文案不再占卡片，右上等级仍保留。 |
| A03 原生资源校准 | 旧浏览器资源别名缺少 chainmail 等图；部分旧已解码预览图不是准确的原生图标。 | 从本机官方 `pak01_dir.vpk` 只读提取并解码 21 个真实图标，`work/native_preview/manifest.json` 记录 URI 映射与资源 sha256。生产仍使用 Dota 图片组件与原 URI，没有更换图标。 |
| A04 共享壳全链复看 | 真实共享导航曝光多 class 创建、旧 Label 颜色与本地分类条隐藏问题。 | 主代理修共享 class 创建与 Label inline 色；生存商店高优先级保留分类条；预览支持 Panorama flex / gradient / visibility，修适配问题后复拍。 |
| A05 浮动 tooltip 与层级 | 旧商城 tooltip 被后续卡片遮挡；生存商店滚动条出现时浏览器缩成三列；列表底部压到 footer。 | 所选商城卡 z-index 30，hide 恢复 0；四列间距 18→16；长列表最大 490 高，保留 footer 间隔。两个 tooltip 都可跨约 10–12px 间隙、进入后取消 0.18s 延迟 hide，并在屏幕边缘翻转/限位。进入 tooltip 取消 hide 不再取消 0.03s 测量定位；未测量尺寸有 fallback。商城 native 工具 Hover 指令改用真实 Show/Hide。 |
| A06 自适应高度 | `work/shop_preview/shop_same_equipment_height_456.png`、`662.png`、`760.png` 为同一真实装备状态对比。 | 选择 1040 固定宽、按实际行数 456 / 662 / 760 高。真实装备页 456，其他页 662，挑战与研究最多 760。导航上沿保持 1920 下 y160（1280 下约 y106.7），切换类别不移动顶部，无过渡动画。 |
| A07 原生热加载与旧 CSS 覆盖 | 主代理实机日志在旧商城 `Dispose → hideDetails → grid.Children` 报原生 panel 已删除；全链复看装备 / 挑战仍被旧双 ID 青色规则覆盖，footer 继承旧纵排导致 status 越界。 | 商城原生父 / 子 panel 均先验有效，旧版本升级仅恢复 deleted-panel 清理异常，其他异常继续抛出；释放共享壳注册和 ModalShell lifetime。Tooltip 延迟回调也验证有效。生存店具名 tab 规则提升优先级，footer 单行 28 高、资源 / status 各定宽。Checkpoint：`work/checkpoints/shops_compact_native_reload_a07`。 |
| A08 实机名称定位 | 本人实看主代理 `work/native/c06_shop.png`：真实 4 商品 / 库存可见，但全部底部名称缺失。新 caption 使用 y159，仍继承旧 `shop.css` 的 bottom anchor，Panorama 将位置加到卡片底部之外，浏览器适配未暴露。商城实机 compact 名称重复永久后缀。 | Shop 名称明确 left / top / margin0，创建 Label 同时清旧锚点，19px 和 y159 保留；增加原生锚点回归。商城 compact caption 仅删除末尾 ` · 永久`，详情完整标题 / SKU / 效果 / 购买保留，增加短名称与全详情回归。Checkpoint：`work/checkpoints/shops_native_name_a08`，保存修改前 C06 原生图；新原生截图由主代理验证。 |

## 当前截图

- `work/shop_preview/shop_1920.png`：4 个真实装备，1040×456。
- `work/shop_preview/shop_1920_other.png`：6 个其他商品，1040×662。
- `work/shop_preview/shop_1920_more.png`：21 个挑战 / 转职条目，1040×760，四列滚动。
- `work/shop_preview/shop_1920_tooltip.png`：浮动效果、真实价格与购买按钮。
- `work/shop_preview/shop_1280.png`：1280×720 缩放。
- `work/shop_preview/commerce_1920.png` 与 `commerce_1920_tooltip.png`：1280×800 商城、15 个紧凑单元、独立 hover 详情。
- `work/shop_preview/commerce_1920_more.png`：真实礼包奖励进入 tooltip，分类 / 分页保留。
- `work/shop_preview/inspection.json`：示例请求数、缺图统计、window bounds、实际商店高度。

## 验证

以下检查通过，所有购买和结算测试均为本地 mock 捕获，不是实际交易：

```text
node tools/purple_ui_10h/shop_verify.cjs
node tools/purple_ui_10h/commerce_verify.cjs
node tools/test_shop_prerequisites.cjs
node tools/test_shop_v2_tooltip.cjs
node tools/test_commerce_catalog_ui.cjs
node tools/test_lottery_updates.cjs
```

自有回归涵盖真实类别、单元结构、三种自适应高度、稳定顶部锚点、屏幕边缘 tooltip、hover 间隙、选中不购买、实时可用状态、购买守卫、自动书 / 科技执行别名、所选商城 tooltip 层级、目录刷新和关闭清理。原 `test_book_shop_ui.cjs` / `test_shop_presentation.cjs` 的老 harness 未加载当前 `ReferenceWindows`，且固定 604 左抽屉断言已不适用于此次设计；未修改这些旧测试以伪造通过。

商城回归额外严格模拟 Panorama 原生删除：所有 native panel 方法在无效时抛错，递归删除旧窗口后执行旧 Close / Open / Update / Inspect、旧 tooltip 定时器与真实新 controller 初始化均通过。旧版本 `Dispose` 精确抛 `Underlying panel is deleted` 时可升级恢复；无关清理异常仍上抛；多次 Dispose 不重复释放，重载不增加购买请求。主代理后续实机编译 / 热加载负责确认原生错误消失。

浏览器预览可验证组件、资源与交互适配，不能替代 Panorama 编译和游戏内最终渲染验收。该代理没有操作游戏、编译 Content 或执行 Git；这些由主代理统一处理。

A08 原生复核：只读实看主代理 `work/native/c08_shop.png`，四个真实商品的下方名称均已恢复（成长之剑、加速手套LV1、灼热之刃LV1、铁甲LV1），图标、右上库存、单行 footer 与公共顶部导航正常。该截图由主代理在游戏内采集，本代理没有操作游戏。

A09 原生名称对齐：主代理进一步实看 A08 发现短名称实际从 cell 左侧起点显示。只在名称创建处补 `width=220px`、`height=30px`、`position=0px 159px 0px`、`textAlign=center`，保留原 top/left 锚点；数据/名称/字号未变，回归加入实际 native caption 这四个字段断言，PASS。具名前版 c08 截图与新源保存于 `work/checkpoints/shops_native_center_a09`，原生对齐复核由主代理继续采集。

A10 原生文本盒自身居中：主代理 C10 诊断确认名称 inline width=220px（原生实际183px）、textAlign=center 都生效，但仍从 cell 左侧画文本，因此推断 nowrap 对齐行为未按固定 Label 宽度工作。只替换名称文本盒策略：width=fit-children、maxWidth=220px、horizontalAlign=center，保留 y159/top、height30、textAlign=center、字号19及 long name shrink。JS 与同名 CSS 保持一致；回归断言自身宽度/居中锚点及最大宽度，shop_verify 与 node --check PASS。具名源快照为 `work/checkpoints/shops_native_textbox_a10`；原 A09/C09/C10 证据保留，待 root 原生复验，不提前记为实机成功。

A10 原生复核完成：主代理 C11 在真实战场采集 `work/native/c11_shop_textbox_battlefield.png`，四个真实名称的文本盒宽度分别约 62 / 87 / 87 / 57 实际像素，所在 cell 约 183 实际像素，各自文本盒均居中。本人只读实看该截图确认名称、Dota 图标与库存正常；这份证据对应该次原生 viewport，不推及未实测的引擎分辨率。

A11 原生旧 header 细线：C11 分类栏底部仍留青绿线，读取实际 `reference_windows.js:26` 找到首轮 PurpleShell 创建前遗留的 `ShopHeader.style.borderBottom="1px solid #afbb9977"`，优先于新 stylesheet 的 `border:0px`。只在商店布局应用时显式设置该字段为 `0px`，未改名称 A10、tabs、窗口尺寸、背景或加载业务；测试加入原旧 inline 值再验证清除，shop_verify / JS syntax PASS。具名源码与 C11 前版证据保存在 `work/checkpoints/shops_native_header_a11`，新原生效果由 root 的 C12 验证。图标后淡字暂未明确归因，等待实际 Label / visibility / position 证据，未隐藏真实加载提示。

A11 原生复核限制：只读实看主代理 `work/native/c12_shop_native_mouse_hover.png`，header 底部细线仍在，因此不能把 JS 字段断言通过等同于视觉问题已解决。`U.TabBar.Adopt` 的实际实现仅加 UITab / 选择状态，不创建 underline 子 panel。旧 CSS `nav_windows_modern_20260929.css` 的 ShopHeader `border-bottom:#35525f`、公共 UIModalHeader 的底边与旧 Selected rule 仍是需要原生样式诊断区分的候选；此次没有继续改细线。

A12 原生淡字/透字：C12 真实鼠标 hover 的 tooltip 下仍能透出底层 5/5、商品名称；主代理原生诊断已确认 ShopTitleBlock.visible=false、ShopLoading.visible=false / Hidden=true，可见 Label 中无额外文本，支持半透明底色为来源。本轮只改两个表面变量：商店窗体 JS / 同名 CSS #100b21fa→#100b21；tooltip gradient 两个端点 #211630fc / #0d091bfc→#211630 / #0d091b。背景色相、金边、阴影、字号、尺寸、名称 A10、点击与服务端购买守卫均保留。shop_verify 的真实场景回归、窗体 opaque / tooltip gradient opaque 检查及 JS syntax PASS；具名 `work/checkpoints/shops_native_opaque_a12` 保留 C12 hover 前版证据，原生修复效果待 root 的 C13 确认。

QA 使用实际 CDP mouse pointer 验证完成 16 项：1280×720、1920×1080、2560×1440、2560×1080 × 生存商店 / 商城 × enabled / locked。路径为商品 source → gap 停 40ms → tooltip 停 230ms，tooltip 唯一且保持可见，`elementFromPoint` 命中购买按钮；enabled 仅记录本地 mock 请求，locked 不产生交易请求。完整记录 `work/qa/pointer_report.json`。为存档 / 宝物预览追加只读官方资源解码后，manifest 合并共 49 个 unique 图标，missing 0；fragment_10 的实际错误路径由存档代理按官方定义 5810 修正，未创建伪造 alias。

A13 商城原生图标与名称：本人只读实看主代理 `work/native/c12_commerce_true_state.png`，真实后端科技页25件（原15/10分页）统一显示青水晶、compact名称左起。根因是实际 commerce_products.csv 的25个technology SKU原icon均为lottery_attribute_crystal.png，controller未丢字段；native_ui_icon_mapping.csv没有video_p现成映射。本轮两个视觉变量：common/commerce_components.ProductIcon(item)集中按canonical SKU替换已知占位/空icon，用已存在官方Dota图表达商品主题，compact/detail/bundle缺省图同用；未来服务端非占位专属icon优先，未知SKU保留原icon，hasOwnProperty拒绝继承键。权益名/价格/数量/描述/奖励/购买守卫与catalog对象均未改。RCProductName采用ShopA10已实证的自身文本盒居中：fit-children、max188、hcenter/vtop/y140，18px/shrink保留。commerce_verify执行实际CSV25 SKU、原生产catalog合并/15与10页/hover一致图/caption字段/原目录对象不变/专属图优先/未知SKU，全部通过；原checkout/lifecycle回归仍通过。25个URI全部在官方pak01 VPK找到，独有预览export按公共ProductIcon读取CSV，没有重复第二份映射；native_preview共76unique/missing0。两源+test/SHA与C12前版保存在work/checkpoints/commerce_native_icons_caption_a13；目前源码候选，C13引擎视觉待root验证。以下图标是权益的界面展示选择，不宣称其为权益原始作者插画或额外奖励。

| Canonical SKU | 原商品名 | 现有原生展示图 |
| --- | --- | --- |
| video_p004 | 清暑符·永久 | items/null_talisman.png |
| video_p005 | 双倍通关卡·永久 | items/tpscroll.png |
| video_p011 | 炫彩足球·永久 | items/orb_of_venom.png |
| video_p012 | 剑圣·永久 | spellicons/juggernaut_blade_fury.png |
| video_p013 | 精良工匠·永久 | items/meteor_hammer.png |
| video_p014 | 硬质涂层·永久 | items/platemail.png |
| video_p015 | 金斧头·永久 | items/bfury.png |
| video_p017 | 铜斧头·永久 | items/ogre_axe.png |
| video_p018 | 时间科技·永久 | spellicons/faceless_void_time_lock.png |
| video_p019 | 淬火剂·永久 | items/bloodthorn.png |
| video_p020 | 地精油锯·永久 | spellicons/shredder_whirling_death.png |
| video_p021 | 优质装备·永久 | items/armlet.png |
| video_p022 | 高级伐木场·永久 | spellicons/shredder_timber_chain.png |
| video_p023 | 古董收藏家·永久 | items/relic.png |
| video_p024 | 建筑手册·永久 | items/recipe.png |
| video_p025 | 文玩收藏家·永久 | items/philosophers_stone.png |
| video_p026 | 侏儒传送器·永久 | items/blink.png |
| video_p027 | 精英装备·永久 | items/assault.png |
| video_p029 | 工作效率·永久 | spellicons/alchemist_goblins_greed.png |
| video_p030 | 银斧头·永久 | items/iron_talon.png |
| video_p031 | 强化箭塔·永久 | spellicons/windrunner_powershot.png |
| video_p032 | 快速建造·永久 | items/repair_kit.png |
| video_p033 | 伐木斧·永久 | items/quelling_blade.png |
| video_p037 | 新手木材·永久 | items/branches.png |
| video_p038 | 新手金币·永久 | items/hand_of_midas.png |

A14 标题栏青色残条根因：只读分析 C13 `work/native/c13_shop_opaque_hover.png`，y289–291 的连续残条 RGB(24,56,68)，窗底 #100b21 同图呈 RGB(17,12,34)，统一渲染偏移后残条对应旧 #173743。`common/ui_components.js:52` 的真实 ModalShell.Adopt 给 header 写入 inline surface_teal，压过 shop_purple.css 的 transparent；header 48px、分类按钮 44px，露出的 4px 在 1600×900 原生图中约 3px，与实色残条位置一致。U.TabBar.Adopt 没有 underline 子 panel，旧 borderBottom 字段断言不能证明此背景已清除。本轮经 root 授权仅一视觉变量：applyShopLayout 显式把 header inline backgroundColor 设为窗底 #100b21，保持尺寸、分类按钮边框与既有业务。shop_verify 运行真实公共 ModalShell 后增加背景字段断言，原购买/库存/自动书/研究路由回归和语法 PASS。修改前 checkpoint `shops_native_header_surface_before_a14` 保留 C13 实机图，源码候选 checkpoint `shops_native_header_surface_a14`；最终青条消失需 root 新一轮原生复核。C13 已由 root 确认 A12 不透明生存商店与 A13 商城 Dota 图标/名称居中成功。

A15 商城详情原生绘制边界：主代理 C14 真实鼠标选中首商品后，原生诊断记录 selected=true、shown=true、visible=true、详情 260×376，屏幕位置 (629,263)，商品 (460,263)，wellHit=true，但 `work/native/c14_commerce_tooltip_diagnostic.png` 没有详情可见。源码没有额外隐藏详情的规则或业务分支；事件、权限和屏内定位已排除。卡片内部 paint/clip 边界是剩余的结构性候选，不能把浏览器通过写成原生绘制成功。本轮经 root 授权把详情独立放在所属 CommercePurple 窗口的 CommercePurpleDetailLayer，保留祖先紫色 CSS 和原详情背景 fc、边框、字号、效果、真实价格与购买按钮；卡片/图标/名称/目录/分页/权限/结算逻辑均保持。定位按原生 source card 与 layer 的实际屏幕 origin 和 UI scale 换算，保留屏幕边缘翻转、上下限位、hover 间隙和 pin。详情带明确 __purpleSource；render、close、Dispose 清理所属浮层，失效 source 的迟到定位/购买回调安全返回。关闭再打开只重建详情并重新绑定同一活卡片，保留原卡片身份与目录页定位。

A15 验证：`commerce_verify.cjs` 的严格 deleted-native-panel harness 通过独立 layer 归属、真实 body/价格、0.6667/0.8333/1/1.25 scale 与非零 origin、屏幕边缘、hover→gap→tip、pin、实际购买路由、source 删除、category/page 刷新、close/reopen、两次 Dispose 与完整 root 删除/reload，无 orphan 或额外订单。原 `test_commerce_catalog_ui.cjs` 曾准确抓住首版 close/reopen 重建整张卡片的回归，修复生产重建策略后原测试通过，未放宽该断言。`checkout_verify.cjs` 与两源 `node --check` 通过。修改前候选与 C14 图保存在 `work/checkpoints/commerce_native_layer_before_a15`，冻结候选为 `work/checkpoints/commerce_native_layer_a15`；测试购买只进入本地 mock，未操作游戏、编译 Content 或真实支付。新结构最终绘制仍需 root 原生复验，浏览器补充物理 pointer/四尺寸截图由预览代理负责。

A14 后版原生复核：本人只读实看主代理 `work/native/c14_shop_header_purple.png`，分类栏底部青色残条已消失，四个商品名称、库存、完整 tooltip / 真实成本 / 购买按钮仍可见；公共紫色导航与金币/木材行正常。此证据仅对应该次 1600×900 游戏截图，不宣称四个浏览器分辨率均作过引擎验证。A14 四尺寸 normal/hover 浏览器补充共8项通过，见 `work/qa/final_shop_a14_report.json`。

A15 原生后版通过：本人只读实看主代理 `work/native/c15_commerce_loaded_layer_hover.png`，真正加载新专用 layer 后首件清暑符 tooltip 已绘制，完整标题、权益正文滚动区、真实6800 U币、暂不可购提示、查看/兑换按钮均可读，原生25商品/15与10分页与居中名称保留。C15 首次 `c15_root_layer_hover` 仍使用旧 Window、没有 DetailLayer；root 通过 linkedSource/factory 与 XML 刷新确认加载新代码后再截图，因此首图不作为 A15 结构失败证据。此图仅验证该次1600×900原生状态；原生屏幕边缘、hover间隙、关闭重开还由root后续实测，不从本地mock或browser报告推定。

A16 商城 tooltip 不透明：上述 C15 已正常绘制的 tooltip 仍淡透背后商品名称。经 root 授权只改自有 `commerce_purple.css` 的 tooltip gradient 两个端点 #211630fc/#0d091bfc→#211630/#0d091b，与 Shop A12/Daily A05 一致；金边/阴影/字号/所有几何/浮层层级/事件/业务/两JS保持。字节级差异断言确认 CSS 只有这两个 alpha 删除、两JS与前版逐字节相同，commerce_verify 的原真实目录/价格/checkout/层生命周期回归仍PASS。前版 `commerce_native_opaque_before_a16` 保留 C15 新 layer 原生截图及源；候选 `commerce_native_opaque_a16` 保存新CSS与SHA。去透字最终效果等待root最终具名编译与原生复验；未操作游戏、调用nativeconsole或真实交易。

A17 商城原生窗口裁切：本人只读实看主代理 `work/native/c16_commerce_edge_tooltip.png`，第五列真鼠标hover虽已触发，tooltip从约x1300起却被window右边约1333裁掉大半；在1600屏幕内仍有空间。根因是详情已归属窗口专用layer，原生仍对所属window执行clip，CSS overflow:noclip不取消这个边界；A16首件opaque/按钮hover已由root通过，因此不回滚layer或重改opacity。本轮仅原组件place()的定位边界：取所属window实际屏幕位置/尺寸与viewport安全边界交集，保留12px逻辑间隙，右边不足向左翻转，底部按已测详情高度向上限位；没有改卡片、浮层结构、尺寸、CSS、controller、事件、价格权限或购买。代价是右/底列详情可能盖住窗内相邻商品，换取完整正文、价格、按钮始终在实际可绘制范围；同一时间只显示一个详情与选中机制仍保留。

A17 验证：先将实际window clip加入strict-native mock，新测试在A16准确失败于“native window right clip applies even when viewport has unused space”，再修改生产place后通过。报告 `work/qa/commerce_a17_clip_report.json` 为明确strict_native_mock，覆盖1280×720、1600×900、1920×1080、2560×1440、2560×1080模拟的第五列首行/底行×300/540逻辑高共20项，加window部分出屏时交集限位1项；并经真实controller注入完整50行effect，保留原inner180/outer540上限和滚动CSS，目录对象不变、不下单。既有gap/pin/购买/源card删除/分类分页/close-reopen相同卡片/reload释放回归PASS；原catalog-ui、checkout和JS语法PASS。差异断言确认只改place()、controller/CSS逐字节与A16相同。前版检查点 `commerce_window_clip_before_a17` 含C16原生失败图，候选 `commerce_window_clip_a17` 含源码/test/report/SHA；新原生翻转/底部/长滚动与物理pointer由root/预览代理后续确认，不把模拟尺寸称为引擎实测。

A17 原生范围补正：root C17 已实际鼠标复看第五列上方左翻转、右下上限位、close/reopen与ESC通过，具名图为 `c17_commerce_top_right_flip.png`、`c17_commerce_bottom_right_clamped.png`、`c17_commerce_reopen_edge_hover.png`、`c17_commerce_esc_closed.png`。长effect原生物理wheel仍未通过：root在首tip正文区连续三次滚轮后的 `work/native/c17_commerce_effect_scrolled_end.png` 仍是头部，本人只读实看确认未显示末尾。早先browser对 inner effect直接调用Panel.ScrollToBottom证明的是程序化滚动/内容保留，不能当作物理wheel可达；strict mock此前也仅检查正文与滚动CSS，未验证input命中，这个验证限制明确保留。

A18 正文滚轮命中：真实label()公共助手默认hittest=false，RCProductEffect未覆盖；本轮仅给effect.hittest=true，使已显示tip的hittestchildren=true时正文可成为wheel目标。未改Label结构/正文/价格/按钮/opacity/clip定位/CSS/controller/事件与购买。新增strict-native input-routing mock按目标hittest和祖先hittestchildren/有效性选目标，不调用ScrollToBottom、也不伪造Label scroll offset；新断言先在A17失败，A18可命中正文、阻止祖先禁子命中和已删除正文的迟到wheel，50行真实props/目录对象/价与按钮保持。原clip/gap/pin/买/删除/reload/reopen card identity与原catalog-ui/checkout/语法继续PASS，报告 `work/qa/commerce_a18_wheel_report.json` 明确只证明input路由。前版 `commerce_effect_wheel_before_a18` 保留C17未滚动真图，候选 `commerce_effect_wheel_a18`；实际Panorama Label是否接收到wheel并滚到末尾仍由root新编译实测，若Label不能滚再决定结构升级，未预先重写为Panel。

A18 最终原生通过：root C18 实际滚轮已通过，本人只读实看 `work/native/c18_commerce_long_before_wheel.png` → `c18_commerce_long_after_wheel.png`，真实清暑符8行效果末行“星悦积分×68”完整显示，6800 U币、暂不可购提示与原查看/兑换按钮保留，底材不透字。没有点击兑换。本轮Label仅hittest一行已解决，不再升级Panel结构。最终browser真实CDP wheel四尺寸×8行/50行共8项通过，报告 `final_commerce_a18_physical_wheel_report.json`；没有使用ScrollToBottom，物理pointer8、lifecycle4重新通过。抽奖L07说明修正后的最终143活动源digest为5216ec0cffc8d3c5d663635855d894159a46590a5efbb8a602dd34734d8c2675，`work/final_component_applicability.json` 明确A17几何到A18仅hittest的适用证明，以及抽奖Note改变后商城组件字节不变。最终恢复是 `work/checkpoints/best_final_compact_purple_c19/manifest.json`，其35source/35runtime与当前源、Content输入、compile哈希已独立核对差异0。原生尺寸只称当次1600×900，不扩大为四个引擎尺寸均通过。


<!-- standalone-shop-c25 -->
## 独立生存商店C25

最新用户要求生存商店不在存档弹窗内，旧A14生存店选择已淘汰。C20–C25改动/改善/代价/淘汰理由及原生图在[StandaloneShop.md](StandaloneShop.md)；最终C25三分类与入口实机通过，四尺寸12组48图比对通过，源/运行/Content配对完成。普通商城A18保持原选择。
