# 当前 UI 接入与文档入口

伐木工 HUD 单选和多选统一为260逻辑像素高，属性图标下方仅留11像素，底边贴齐游戏窗口下沿。多选左侧使用与技能区一致的完整深色九宫背景，停用透明金色头像外框；头像区域为264×237，原生多选根节点改为透明，避免默认黑色梯度覆盖底板。共同父节点按实际行数与分页居中适配，不再为少量头像强留第二行；两、三、四列分别限制放大倍率，原生头像画布、格子、点击和分页处理保持原尺寸与行为。离开伐木工布局或切回单选时恢复原背景，英雄和其他单位继续使用原头像框与布局。2026-10-16在1600×900实机核验单选、2/4/9/12/13人多选、两页切换及头像点击；临时11个测试单位已清理，原选择与运行状态已恢复，截图与日志见 `output/worker_hud_compact_live_20261016/`。

## 伐木工训练面板（2026-10-15）

训练入口按“累计已完成 + 当前训练及等待预约”占用名额，负数上限才表示不限额。点击达到上限即隐藏对应等级，剩余等级顺序补齐四个入口；客户端预测本次尚未返回的点击，服务端回执携带认证主城的实际训练快照，失败后恢复空缺。快照的 `queue_revision` 拒绝旧响应，当前训练已包含在 `queued_count`，不能再加一次。服务端可选等级窗口与名额校验采用同一口径，未修改训练费用、人口、退款和总容量。

训练面板高度278，去掉标题、训练说明行、卡片LV文字、训练/锁定字样和底部帮助；头像、名额及木材图标费用保留，完整等级可悬停查看。队列最左侧为正在训练（或资源不足的待开始首项），后面六格才是等待；只有真实训练中项显示金边和进度，等待数量不包含首项。研究所继续使用原来的当前任务行与六个可取消等待格。验证及离线预览位于 `output/training_panel_20261015/`；离线截图不等同于Dota实机验收。

训练入口现以原生技能图标铺满按钮，名额与木材费用叠在下沿暗底上；LV1–8使用八种图标色调及对应细边，当前训练与等待格同步色调。2026-10-16将训练面板显示倍率由0.5调至0.75，入口图标、队列、文字与间距统一放大为调整前的1.5倍；逻辑高度仍为278，底部及侧边锚点按放大后的实际尺寸计算，小窗口仍保留原有上方布局与滚动适配。研究面板维持原尺寸。当前编译记录位于 `output/training_panel_scale_20261016/`，之前预览见 `output/training_icon_tiles_20261015/`。

存档现在采用独立的旧纸纹两栏界面：左侧青灰分类列表，右侧黑褐条目、橙金进度条，不再显示一级导航和公共资源行。依据是[用户确认效果图](../design_refs/archive_parchment_v1/approved.png)，材质与控件清单见 [asset_manifest.json](../tools/archive_parchment/asset_manifest.json)。每日登录也已独立，采用金色皇冠、月相和蓝黑笔刷底板，28 格免费奖励按 7 列 × 4 行排列，右侧为方形蓝框战令奖励。抽奖采用八方旅人参考布局和激战 2 材质的独立外壳，左侧选择现有四池，右侧展示原卡池场景并操作单抽／十连。宝物、商城、生存商店、VIP，以及兑换和支付确认仍采用 V10 紫色公共外壳；其几何与验证范围见 [V10 菜单交付](../design_refs/menus_v10/DELIVERY.md)。存档原业务说明仍见[存档数据与交互](../design_refs/archive_v10/Delivery/DATA_AND_INTERACTIONS.md)。历史外壳不能覆盖已经独立的界面。

## 实际入口

角色收藏抽取成功与每日奖励领取成功共用 `common/reward_feedback.css` 的玻璃扫光：一条带柔边的冷白斜光在0.58秒内横向掠过卡片，0.65秒后结束清理，不加整卡金色罩光、发光边框或浮字。角色卡仅对本次明确获得的卡片懒创建一个扫光节点；每日通过 `RewardFX.Create(..., {channel:"daily"})` 在已领取卡片的准确矩形上放置两个纯2D节点，避免继承已领取卡片的变暗透明度。保留权威成功确认、重复回包去重、关闭取消和原有领取/抽取请求，不添加粒子场景或逐帧轮询。商城奖池抽奖的原有反馈接口保留。编译与验证记录见 `output/reward_glass_sheen_20261016/`，实机视觉录制见 `output/glass_reward_live_20261016/`。

收藏采用独立的背包网格界面：薄标题条、窄三图标栏、长搜索条、人物格子和底部平面抽取操作按原版背包的比例重组，素材清单见 [collection asset manifest](../tools/collection_gw2/asset_manifest.json)。背景从用户原始 GW2 Inventory 参考图清除物品、标注和残留结构后提取，格底直接取原图空格内部纹理，取消旧厚框与凸起按钮。标题、侧栏和底栏共用整齐边界；左侧不重复显示分类文字，完整名称保留在内容区与悬停提示。现有前女友与男性角色池已从存档导航移入收藏，老婆栏目展示视频核对的40个角色，其中38项可抽取、2项标注待适配。

入口由 [custom_ui_manifest.xml](../panorama/src/layout/custom_game/custom_ui_manifest.xml)及三个活动布局决定：`archive.xml`、`survival_hud.xml`、`payment_test.xml`，均位于 `panorama/src/layout/custom_game/`。公共 V10 实现在 `panorama/src/scripts/custom_game/common/menu_v10.js`、`panorama/src/styles/custom_game/common/menu_v10.css`；独立存档继续由 `archive_v10.js` 适配真实控制器，`archive_parchment_data.js` 提供新材质，`archive_v10_data.js` 保留原物品图标与必要契约。应沿 XML 的实际 include 顺序检查依赖，不能按历史文件名推断入口。

左上角“收藏”入口由 `collection_nav.js` 接在最右可见导航之后，采用其他普通入口的尺寸、文字、悬停和选中样式，以及同色金色线条 SVG。图标源位于 `art/ui/sources/custom_game/topnav_reference_v2/collection.svg`；特效入口隐藏或缺失不影响收藏显示。点击通过现有 `PurpleShell.Navigate` 打开收藏，仍尊重其他弹窗的导航守卫。

作者源码位于 `panorama/src/`；运行资源位于 `panorama/layout/`、`panorama/scripts/`、`panorama/styles/`。后缀分别为 `.vxml_c`、`.vjs_c`、`.vcss_c`。资源编译成功后仍需确认新 HUD 执行链已加载，避免把旧闭包和旧截图当成本版效果。

启动组队使用 Dota 原生选队与房主开始按钮；必须在 manifest 的 `GameSetup` 显式挂载 `native_team_setup.xml`，由其脚本 `BLoadLayout` 加载游戏 VPK 自带的 `team_select.xml`。单纯隐藏加载层不会自动创建官方选队控件，会永久停在组队阶段。运行时加载避免 Workshop 编译器尝试重编缺少完整 CSS 源文件的官方资源；挂载失败显示重试。`startup_loading` 在 `team_setup` 阶段隐藏，不能遮挡或改写官方控件。开始后显示顶部居中的“孤城逐晓”及底部魔兽争霸原版加载条，进度由资源、认证和客户端图片握手决定。四张切图保存在 `art/ui/sources/custom_game/loading/`，`tools/build_startup_loading.ps1` 编译七个 UI 文件和五个图片依赖。仅修复选队入口可执行 `tools/dawnward_loading_20261015/compile.ps1 -SetupManifestOnly`。加载预览记录在 `output/loading_refine_20261016/`，黑屏修复检查在 `output/native_setup_fix_20261016/`；尚需真实游戏验收。

菜单 Tooltip 共用 `common/menu_v10.css` 的透明外容器、独立底板和原生柔阴影规则，覆盖存档、每日奖励、收藏、抽奖及公共商店／商城／宝物。只对底板使用原生 `softedge_box` 遮罩，并以 `opacity-mask-threshold:0% 12%` 收紧过渡，避免长提示的标题区域透出底层条目；正文、数值、边框和滚动条不做整体透明或遮罩。装饰层不接收鼠标，动态高度同步底板与阴影。存档旧 `tooltip_shadow.png` 的透明度恒为95，已不再绘制该平黑矩形，资源保留供历史素材追溯。

2026-10-14 本轮8个JS/CSS源文件已定向同步Content并原生编译、校验哈希；预览与验证位于 `output/tooltip_surface_20261014/`。显示修复不改奖励、解锁、字体层级或数量语义；新JS需要重新载入HUD，完整重启游戏可避免旧闭包继续显示旧阴影。

HUD 属性等原生文字提示通过 `SurvivalTooltipPosition.ShowText/HideText` 显示：悬停时临时提升原生提示容器及其祖先，覆盖技能框和血蓝条；离开后恢复原层级，保留引擎定位和正文。弹窗层级变化先释放提示租约，再基于新层级提升，避免关闭弹窗后残留高层级。只在显示及下一布局帧查找提示容器，不增加常驻轮询。回归入口为 `tools/test_native_tooltip_layer.cjs`，编译及验证记录位于 `output/tooltip_top_layer_20261015/`；实机显示仍需重新进图确认。

进攻怪物预警读取左下角计数器使用的同一份玩家私有 `wave.alive` 快照：超过85只（86起）显示屏幕四边红光和“即将超过怪物存在的上限”，回到85只及以下隐藏。`enemy_population_warning.js/css` 让四边和文字共用父容器的1.6秒呼吸动画，稳定数量更新不重启动画；不额外扫描怪物或新增JS动画计时器。摸鱼模式、玩家淘汰和终局结算清理预警；所有节点均不拦截鼠标。真正的数量上限、超限倒计时和失败判定继续由原服务端逻辑负责。回归入口为 `tools/tests/enemy_population_warning.test.cjs`。

存档挑战的27个技能（含无尽与结束入口）使用独立的 `ArchiveChallenge` 提示样式：隐藏顶部分类、等级、升级状态和“解锁条件”字段；只有未满足条件时显示服务端状态红字，条件满足后连同空状态行一起收起。主渲染与HUD接管渲染均按次切换该样式，复用提示框显示普通升级时恢复原呈现；资格判定、挑战次数及奖励仍以服务端为准。验证与定向编译记录位于 `output/archive_challenge_tooltip_20261015/`。

生存商店的提示框只保留图标、名称、费用及效果，类型文字与购买／自动购买按钮不再创建；热载遗留动作控件隐藏并禁用。商品格从136×132缩为90.6667×88，局部图片拉伸铺满并移除黑色内边框；窗口改为464×432，列表432×280，含原生滚动条仍保持每行四格、完整容纳三排。右键商品购买、研究前置和自动购买服务接口继续由原控制器处理。验证与编译记录位于 `output/survival_shop_tiles_20261015/`。

商城积分兑换行不常驻显示“商城积分不足”，与普通购买行同为64px高，36px按钮位于y14居中。积分不足点击兑换时只发送原生 `dota_hud_error_message`“您的积分不足”，保持商城打开，不创建确认框或兑换请求；确认打开后余额下降、服务器明确的终态不足也走该提示。未知余额不猜测为零，已有待确认订单继续使用原请求编号查单；VIP资格等其他说明和服务端结算保持原有规则。

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

侧栏现保留 16 个分类，支持搜索和滚动；前女友和男性角色收藏已移入独立“收藏”，瑞兽赐福继续留在存档。“商城道具”未启用时保留真实空态。横条进度来自 `ArchiveV10Semantics.Progress`：地图等级使用等级而非在线分钟，神兵碎片使用持有余额而非晋升级数；未知或无目标时不填造进度，超额只限制填充长度，文字仍显示真实值。升级、神兵晋升、称号穿戴继续走原控制器。

旧版存档原始包保留在 `design_refs/archive_v10/package/archive_ui_final_v1/`，包括仍在使用的物品图标、PNG、SVG 编辑稿、资源清单和字体许可。不能删除原包或拿示例数量替代正式配置。

其他 V10 菜单从项目根目录按需要执行：

```powershell
& tools/menus_v10/compile.ps1
node tools/menus_v10/preview.cjs
```

编译范围清单分别位于 `tools/archive_v10/compile_scope.json` 和 `tools/menus_v10/compile_scope.json`，应先审阅再执行。`design_refs/*/work/` 仅保存可重建的预览、截图与报告。编译需要同步到引擎 Content 目录；仅拉取 Game 仓库不会自动更新 Content。保留每次具名备份、源文件与产物哈希，不用旧整套检查点覆盖当前 XML 和其他功能。图标配方的 LF 与编译依赖问题另见 [存档纹理重编译](ARCHIVE_TEXTURE_BUILD.md)。

浏览器预览运行实际 XML、JS、CSS，使用明确标记的隔离状态；其截图、缓存和报告可以重建。原生图标预览首次导出及自动检查命令见 [存档工具说明](../tools/archive_v10/README.md)。浏览器通过、Lua/Node 测试通过、资源编译通过分别记录，均不能替代游戏内鼠标、滚轮、字体、裁切和热重载验收。当前完整实机矩阵的边界以 V10 交付说明为准。

## 保留的业务边界

抽奖由 `survival_hud.xml` 加载 `lottery_gw2_data.js`、`lottery_gw2.js/css`，替代原抽奖专属 `menu_purple.js`／`menus_v10_lottery.css` 展示层。外壳为 1536 × 864，电影、翻牌结果及详情内容区保留 1113 × 669 契约；原控制器继续管理 `lottery`／`lottery_info` 层栈，外观不重复注册模态层。16 个无字材质由 `tools/lottery_gw2/split_assets.py` 包装，背景使用内置 imagegen，控件复用收藏的激战 2 材质；完整提示和来源位于 `design_refs/lottery_gw2_v1/generation_prompt.txt`，哈希清单见 [lottery asset manifest](../tools/lottery_gw2/asset_manifest.json)。

四池继续使用 `map`、`cultivation`、`dragon_knight`、`summer` 及现有 `lottery_cinematic_v1` 场景卡图、`reward_art_v5` 奖励图。抽奖展示层在原图标工厂生成 Image 后，仅对本窗口内、已有 `lottery_*` 专属图谱记录的奖励设置既有 `runtime_uri`，防止通用 Dota 道具图遮住现成卡图；未知记录沿原回退，退出展示层时还原工厂，其他菜单图标选择不变。真实奖励列表、名称、持有量、票券余额、费用、概率及保底均由服务端快照驱动，不以预览样例填造；修仙池保留地图累计 100 抽解锁，前两池普通券、后两池金券。原单抽／十连／再抽、影片及跳过、独立详情选池、当前局记录、公告和票券获取流程不变。普通开关窗口保留未完成请求；现有业务控制器的抽奖 pending 不跨脚本热重载保存，此次视觉改动不扩展该事务契约。

按顺序执行 `split_assets.py`、`node tools/lottery_gw2/build_scope.cjs`、`tools/lottery_gw2/compile.ps1 -CheckOnly`，再用 `preview.cjs`、`acceptance.cjs`／`capture.cjs` 检查实际源码组装，最后运行定向 `compile.ps1`。编译只更新新的抽奖 JS/CSS、HUD XML、资源预载布局及 16 个 PNG，保留现有卡图、影片和其他 HUD 源码／产物。`design_refs/lottery_gw2_v1/work/` 是可重建的隔离预览、组件图和验收报告；数值为明确标记的浏览器样例，不连接账号、服务器或支付，也不是游戏客户端截图。

收藏界面由 `collection_gw2.js/css` 和 `collection_gw2_data.js` 独立提供，当前画布为 900 × 478。窗口及提示框继续参考 1200 × 778 缩放，避免调整画布后再次撑满屏幕。格子从 104px 缩到 78px（75%），步长 84px，头像为 74px、内缩 2px；网格十列四行，前女友和男性角色各 40 项可一页全部显示。只为真实条目创建格子，不补齐末行；搜索无结果为零格；老婆池40项一页显示，待适配项可悬停查看。未来超过 40 项时保留滚动，另外给 8px 滚条预留空间，不截掉最右列。

顶部“收藏”、窄图标选单和底部抽取按钮保留平面风格；窗口和背景采用不透明 `#171e24` 衬底，背景节点透明度为 1，原 PNG 的透明通道不透出游戏。格底为 0.45，人物与文字不整体降透明。`tools/collection_gw2/split_reference_assets.py` 的画布元数据、`collection_gw2_data.js` 和素材 manifest 同为 900 × 478；22 张材质的原采样尺寸和哈希不变。底图连续无分栏；全宽标题栏压薄到 34px，42px 侧栏位于 y34–430，底栏为 48px。标题左边距 12px、字号从 24px 降到 18px（75%）；关闭继续使用统一的 20px X 图片，点击区为 28px。左侧按钮 34px，图标从 36px 降到 27px。格底继续只截取原图空格内侧；当前角色外框与右上角品质标识使用下述五档颜色。

角色头像仍由 `ArchiveHandoff.Icon` 解析正式 `head_v3` 资源，随后把它创建的同一个 Image 直接放进收藏头像容器，去掉旧存档装饰层和图标样式的继承。两个池共 80 张原图均为 1254 × 1254，现有 GPU 贴图均为 313 × 313、BGRA8888、单 mip，足够本次 74px 显示；不重新画角色或编译头像图片。

存档和收藏的提示框共用 `common/archive_tooltip.js/css`，各创建一个独立实例，使用同一九宫格底板、边框、分隔线、文字颜色及数量排版。素材优先采用 `ArchiveParchmentData`，效果文本继续由 `ArchiveHandoff.FormatEffects` 格式化，状态和数量沿用存档语义；未知数量显示“—”。收藏只提供自己的分类名、缩放、位置和高度限制：外框含阴影最大 406px，长说明保留受限滚动视口。短提示框仍在鼠标移入时隐藏；实际正文超出视口的长提示框允许移入并滚动查看，跨过头像与提示框之间的间隙有短暂宽限，只有离开两者后才隐藏。滚动或缩放移动头像时隐藏旧提示，关闭和重载取消提示框自身的计时器，不干扰抽取恢复流程。

`build_scope.cjs`、`compile.ps1 -CheckOnly`、`preview.cjs`、`acceptance.cjs`、`capture.cjs` 和实际 `compile.ps1` 负责限定编译、隔离预览与最终截图。本版只编译收藏 JS、data、CSS、资源预载 XML 和 22 个 v2 PNG；原 HUD、导航、存档控制器及抽取业务不在重编范围。`collection_nav.js` 继续扩展原 HUD 入口。旧 `split_assets.py`、v1 参考和材质保留供历史交付及抽奖皮肤使用，不要执行旧拆分脚本覆盖当前 v2 数据。六种预览尺寸含原图 815 × 528；底栏边界、装饰透明度、细框和 Tooltip 前景遮挡均单独核对，输出位于 `design_refs/collection_gw2_v2/work/`。

收藏编译的 `-SourceRoot` 默认是 `panorama/src`，也可指定工作区内经过审阅的完整源码快照，资源范围和 PNG 哈希检查不变。有其他工作修改同一文件时，以本次提交的源码快照编译，保留工作区原改动；编译报告记录实际来源及产物哈希。

“我的前女友”沿用 `ex`，“我的前男友”沿用原男性角色 `friend` 池、持有数量及票券；头像使用现有 `archive_portraits_v3`，不重新生成角色。“我的老婆”使用 `wife` 独立池，40项角色名字和效果来自本地视频逐格核对，原始记录位于 `data/reference/wife_tooltips_20261016.json`，头像使用 `wife_portraits_v1` 专属角色图（39张新制，祈采用已有同角色原画并绑定独立ID），身份、完整提示词和生成记录见 `data/ui/wife_portraits_v1.json`。使用独立玫瑰，每次抽取消耗1朵；第3座存档建筑提供老婆挑战，每局一次，每日最多10朵，联机基础奖励每人独立一份。持有上限沿用前女友对应序号档位。凯尔希“初始魔法卡+1”、夜刀神十香“墙皮肤-夜刀神十香”保留原文并标注待适配，展示但不参与抽取，不计入剩余权重，其余38项真实结算。旧存档 `SelectCategory('ex'/'friend'/'wife'/'beast')` 转到收藏。抽取使用原 `survival_archive_social_draw`，回执 `survival_archive_social_result` 关联 pool/request_id 及档案版本；未确认意图跨选单、闭窗和重载保留，同一意图不生成第二个交易编号。其他确认弹窗继续拦截跨菜单导航。

收藏导航入口单独使用 `tools/collection_gw2/entry_compile.ps1 -CheckOnly` 和实际 `entry_compile.ps1`，只编译 `collection_nav.js`、`collection.svg` 两项；保存备份并核对原顶部导航源码、产物及 HUD XML 的哈希。`entry_preview.cjs` 加载活动顶部导航与收藏源码，`entry_capture.cjs` 验证六种尺寸的真实鼠标命中、开关、分类和重载。截图与报告位于 `design_refs/collection_gw2_v2/work/entry_final/`，编译报告为 `work/entry_compile.json`。浏览器原生 HUD 占位和数据样例有明确标记，不连接游戏服务器，也不等同于客户端实机截图。

原六列紧凑版的基准及截图保留在 `compact_baseline.json`、`work/compact_final/`；其约三分之一面积和第 40 项滚动断言不适用于当前十列一页布局。当前一页版本只使用 `onepage_compile.ps1` 编译收藏 JS 与 data 两项，不重编 CSS、图片、布局或导航。定向预览检查两个池的 40 格全部落在网格视口内、首尾及行边界真实鼠标命中、统一 tooltip 隐藏、搜索、老婆40项及两项待适配状态和更大列表的滚动兜底；先运行 `entry_preview.cjs`，再运行 `onepage_capture.cjs`，截图及头像局部图位于 `work/onepage_final/`，编译报告为 `work/onepage_compile.json`。

提示框共享改动单独用 `tools/collection_gw2/tooltip_compile.ps1 -CheckOnly` 和实际编译，限定六项源码：共享 JS/CSS、存档 JS、收藏 JS/CSS、`archive.xml`。已存在的提示框图片和其他菜单资源只读核对，不重编。先运行 `entry_preview.cjs`，再运行 `tooltip_capture.cjs` 检查两页面外观一致、九宫格、长内容滚动及悬停生命周期；截图与报告位于 `work/tooltip_final/`，编译报告为 `work/tooltip_compile.json`。

所有项目自定义 tooltip 的鼠标交互统一由 `common/tooltip_dismiss.js` 管理，三个活动菜单布局先加载该公共模块。各 renderer 注册真实提示面板、锚点及自身隐藏回调：短提示框在鼠标进入正文范围时清理提示状态；商城、存档、收藏、每日奖励和抽奖的长提示框按实际正文与滚动视口高度决定是否允许进入查看。长提示框沿用短延迟离开判定，进入源卡片或提示框会取消过期隐藏，关闭或换页仍立即清理。被主动关闭的短提示框区域和原锚点在鼠标真实离开前阻止重显，避免遮挡下的另一卡片触发闪烁；普通移出时若鼠标已离开两处则同步解锁，快速返回不必等待 30ms 几何检查。技能、背包等关闭命中检测的面板采用仅显示期间的光标几何检查；共享技能面板按当前 renderer owner 隐藏，避免错清另一控制器。关闭和重载退出计时，普通按钮点击及购买卡片入口沿用原逻辑。引擎文字提示继续在离开源按钮时发送原生隐藏事件，隔离浏览器不宣称验证原生提示框渲染。

提示框复用已有面板；悬停仅显示、隐藏和定位，鼠标移动或位置测量不每帧重建文字、图标与边框。切换条目及真实数据更新仍可更新内容。商城把标题、品级、效果和礼包成员说明放入同一个滚动视口，内部内容保留完整自然高度，避免把已裁切高度再次用于测量；外框受窗口和屏幕边界限制，只有实际溢出时启用滚动。显示后的有限布局测量回调以及迟到的隐藏回调均校验当前 owner／代次，不访问删除后的旧面板。

商城整行离开时释放该短提示框的 owner，避免旧框的覆盖区域阻止相邻商品显示；下次悬停复用原面板。提示框按进入该商品时的鼠标位置做一次左右避让，后续布局校正继续沿用这个进入点，不追着鼠标移动；真正进入短提示框仍隐藏，长提示框继续允许滚动查看。回归同时覆盖“相邻行落在旧框范围内”和“新框出生在鼠标下方”的情形，不能只用远离整个窗口后再返回的路径验收。

此前统一隐藏版本使用 `tools/tooltip_hover/compile.ps1`，只编译公共模块、十一项 tooltip owner 脚本和三个布局，不重编 CSS 或图片；其证据位于 `output/tooltip_hover_unification/` 和 `design_refs/collection_gw2_v2/work/tooltip_hover_unification/`，其中“长内容也进入即隐藏”的旧验收不再适用于当前可滚动长提示框。2026-10-17 的生命周期修正由 `tools/tests/tooltip_dismiss.test.cjs`、`archive_shared_tooltip.test.cjs`、`daily_tooltip_dismiss.test.cjs` 和 `lottery_gw2.test.cjs` 覆盖快速返回、跨窗口遮挡、长内容滚动、过期回调、短提示关闭及计时释放，并有只在内存恢复旧行为的负对照；审计范围、源码小差异和离线结果记录在 `output/tooltip_native_20261017/lifecycle_audit.json`。游戏内鼠标、滚轮、字体与全部商品的实机验收另行记录，离线通过不等同于实机通过。

每日登录当前执行 `daily_remaining_5d5c1152eb.js`，由 `daily_gw2_data.js` 和 `daily_gw2.css` 提供独立外壳。`tools/daily_gw2/split_assets.py` 从 imagegen 生成的无字底板及控件图集中拆出 19 个组件，正式 PNG、源图与提示分别保存在 `art/ui/sources/custom_game/daily_gw2_v1/`、`design_refs/daily_gw2_v1/`。先运行拆分、`build_scope.cjs` 和 `compile.ps1 -CheckOnly`，再执行 `preview.cjs`、`acceptance.cjs` 与实际 `compile.ps1`；最终视觉刷新用 `capture.cjs`，输出位于该参考目录的 `work/`。

28 格由服务器 `calendar28` 快照展开正式七次循环四轮，保留原 `cycle`、`period_id` 和发奖逻辑；第 5、6 次的两项奖励都要展示。右栏三项真实战令奖励为累计 7、14、21 次的一次性里程碑，第四位置是购买和有效期信息。购买价格及 provider 当前未配置，界面按服务器状态显示暂未开放；购买不能在客户端解锁资格，已达标奖励仍在下一次有效签到时结算。补签请求使用服务器日历日期，不能发送 1–28 展示格号。宝物背包参考的去菜单、空网格美术稿保存在 `design_refs/treasure_gw2_v1/empty_inventory.png`，该图尚未作为游戏背景接入。

- 存档的分类、数量、进度、升级、神兵晋升、社交抽取与称号操作继续使用原服务端接口。未知数量、期限和资格不填造默认值；同局共享奖励按[联机奖励规则](COOPERATIVE_REWARD_RULES_20261011.md)结算。
- 生存商店保留真实目录、金币/木材、前置条件、库存、冷却、自动购买和科技队列；商城保留账户币种、原 SKU、价格和权益。悬停与选中不创建交易，只有原明确购买动作提交请求。
- 钱包兑换重试使用原未确认 token；现金订单的 pending 金额与奖励不随目录变化而重算。二维码、可信付款入口和到账凭据沿原支付流程处理。
- 每日奖励、补签、通行证、VIP 的资格、防重和领取状态保持个人隔离。队友权益不用于本人发奖；没有配置的价格和奖励不冒充已经开放。
- 普通菜单关闭与切换尊重现有层栈、pending 和 mandatory 守卫。难度选择、英雄/肉鸽必选、瞄准输入、建筑销毁确认与 TAB 战斗属性层保持各自输入流程；官方返回、设置等入口继续使用原生界面。排行榜没有权威数据时保持未开放。
- 生命周期检查使用所属有效上下文；关闭、删除和重载后取消旧定时器与订阅，迟到响应不得访问已删除面板。底部战斗 HUD、头像与生产队列仍有独立接入规则。

需要修改规则时优先阅读[存档业务契约](archive_data_contract.md)、[抽奖数据契约](lottery_data_contract.md)、[奖池更新](lottery_pool_updates.md)、[存档服务器接入](archive_server_integration.md)、[商城 CSV 说明](payment_shop_csv_guide.md)、[U 币兑换](payments/ucoin_checkout_20261011.md)和[建筑生产队列](BUILDING_PRODUCTION.md)。菜单外观文档不取代支付、奖励或战斗配置。

老婆视频导入的当前定向编译使用 `tools/wife_video_20261016/compile_ui.ps1`，只编译本次实际修改的 JS；原头像贴图、CSS、布局和其他菜单不重编。配置/生成Lua、原始tooltip核对表以及受限服务器发布包共同校验，服务端发布保留现有收藏数据与旧版本结算器。

老婆头像更新使用 `tools/wife_portraits_20261016/import_assets.py`（默认只读，`--apply`导入）和 `compile_assets.ps1`。40个wife ID各自绑定原始1254px透明PNG和独立512px BGRA8888、单mip、NO_LOD纹理；定向编译40个VTEX及头像目录JS。身份总览见 `output/wife_portraits_20261016/identity_preview/all_40.png`；既有导入器在后续重导收藏数据时会保留这些同ID专属头像。

四个收藏池（前女友、前男友、老婆、瑞兽）统一采用 N 绿 `#8fc47b`、R 蓝 `#74c8f2`、SR 紫 `#b680ee`、SSR 金 `#f5c65e`、UR 红 `#ef5350`，常态为2px品质框，右上角显示品质，提示框中的角色名字使用对应品质色。悬停与选中沿用品质色；未拥有、未知数量和待适配只降低头像饱和度，彩框和名字品质色保留。未知品质的名字恢复默认标题色，普通存档提示框的标题颜色保持原样。获奖扫光内缩2px，数量、待适配与品质标识分别放置，避免遮挡。

服务端先按品质总权重 N6000/R2500/SR1000/SSR450/UR50 选档（五档均可抽时为60%/25%/10%/4.5%/0.5%），再按该档每个角色剩余可持有数量选角色。集满角色及待适配项不参与；某档全部集满后移除该档，其余档重新归一。配置源是 `archive_social_items.csv` 的quality和 `archive_social_rules.csv` 的五个quality_weight字段；重导入规则在 `tools/collection_rarity_config.py`。既有收藏数量、上限、效果和券不迁移或重置。Tooltip只读取权威快照的 `draw_probability` 显示当前单角色概率，不以品质总概率冒充角色概率；缺失概率不猜测，待适配显示“暂不参与抽取”。

本次品质界面使用 `tools/collection_rarity_20261016/compile_ui.ps1`，限定收藏JS/CSS和共享Tooltip JS共三项，不重编图片或布局。脚本首次升级品质缓存schema时只清除旧页面和版本号，保留待结算意图、原请求编号与流水，避免旧N级缓存遮住新快照或重新消费券；正常热重载继续复用缓存和拒绝过期快照。浏览器预览使用明确标注的虚拟库存，验证四池、五档、两个尺寸及真实鼠标悬停；预览不会发起交易，也不作为真实客户端截图。规则、定向编译及服务器发布证据位于 `output/collection_rarity_20261016/`，截图位于 `design_refs/collection_gw2_v2/work/onepage_final/`。

建造者艾欧至宝头像使用独立 `portraits/builder_io_companion_v2` 场景与 `SurvivalBuilderIoPortraitSceneV2Alpha` 节点。地图的 StartingAnim/IdleAnim 必须是模型实际存在的 `ti7_io_idle`，不能用不存在的 `idle`；前者是约15.3秒的原生轻微悬浮循环。背景复用官方 `portraitbackground_coolinterior` 的128px原图，建造者专用，普通英雄及塔保持原配色。ScenePanel 按官方 Io 至宝弹窗开启 renderdeferred/deferredalpha，避免不透明清屏底色盖住后方背景；模型和粒子不整体染色或变暗。旧节点在热更新时释放，新节点持续复用。`tools/build_builder_portrait_map.ps1` 只编译新v2地图，`tools/builder_scene_20261016/compile_ui.ps1` 定向编译两份头像JS和背景依赖；实机截图、128帧完整待机记录及资源审计见 `output/builder_scene_20261016/`、`output/builder_scene_audit_20261016/`，验证摘要见 `docs/ai/validation/20261016/builder_scene.json`。
