# 已接入菜单覆盖审查

本记录按当前活动custom_ui_manifest与各XML实际include追踪，审查不操作游戏、不下单、不领奖、不改开局必选/战斗输入/底部HUD。紫色候选的组件浏览器截图与原生Dota验收分开记录。

| 页面/子弹窗 | 实际业务入口与数据 | 当前视觉 | 可独立实施范围 |
| --- | --- | --- | --- |
| 存档 | 顶栏SurvivalArchive.Toggle/Open；survival_archive_snapshot及现有升级/抽奖/称号事件；CSV18配置/17启用，旧shop分类禁用 | A14视觉＋A15生命周期/同步恢复；C12真实44通关记录与17分类基线；C13 clear44/fragment12/friend40，C15 titles9/work34/building9/pet真实空状态已实看 | 七类原生页面有证据，clear/titles/work/building真实hover可读；不声称17类全部实机或执行过升级/社交抽奖/兑换/穿戴。完整controller回归覆盖17缺baseline合并/重试/旧回调/预热与root及children重载 |
| 本局宝物 | 顶栏SurvivalTreasure.Toggle；survival_rogue_reward最近20记录 | T03紫色共享框、8列；C12实机真实2件、名称与离子护盾效果tooltip已实看 | 生命周期/四尺寸normal、hover、few、empty回归通过；20件上限与空记录为明确本地样例，不冒充真实账户库存 |
| VIP特权 | 顶栏vip→SurvivalVIP.Toggle；public profile vip_badge或指定Tools预览账户可打开；survival_vip_request/view/claim/purchase，survival_vip_snapshot权威状态 | V01紫色1280×800共享框；720/1080/1440已亲自复看；旧869×816青蓝装配保留 | 3分类33真实奖励、紧凑图标与完整tooltip；资格/余额/免费领取/购买/防重/三档UI scale/deleted subtree回归PASS；36组件场景PASS，具名vip_V01 checkpoint已保存，原生待复核 |
| 账户商城主页面 | 顶栏shop→SurvivalPayments.Open，经SurvivalCommerceView包装进入实际catalog；wallet目录与payment目录按原SKU合并，分类/分页/购买方法不变 | 五列紫金紧凑单元；C13真实25科技商品、不同Dota图标与居中名称；C15首件窗口浮层详情已绘制，C16不透明/按钮hover/ESC/重开已实机查看 | C16第五列tooltip被所属窗口裁切为FAIL；A17按window与viewport交集定位的候选与strict-native边界回归已完成，原生后版待验。余额/资格/成本保留真实值；未实际兑换或创建订单 |
| 商城余额兑换确认 | 商城item.purchase_method=wallet→SurvivalCommerceWallet.Checkout(sku)；commerce_wallet.js动态创建CommerceConfirm；同一pending兑换重试 | Checkout A01紫金760×700；common/checkout_purple.css，原copy/status与两按钮 | 商城代理实看正常/disabled/pending/receipt，四尺寸32场景wallet_checkout_p01_report PASS，0errors/missing；真实XML/controller回归覆盖金额/奖励/pending不可变/防重/ESC/deleted subtree；wallet receipt仅local fixture记1，其余0无外发，原生待复核 |
| 现金订单确认/支付结果 | 商城其它商品→SurvivalPayments.Checkout(sku)；PaymentDialog在payment_test.xml独立context；survival_payment_request/catalog/create/status/cancel | Checkout A01紫金960×740；共用checkout_purple.css，QR实用黑白块保留 | 商城代理保持确认、微信/支付宝、订单状态、receipt与外部付款入口；paid_checkout_p01_full_body_report四尺寸32场景PASS，描述/完整奖励/QR/footer/status均在窗内，cash create0，原生待复核；较佳checkpoint checkout_purple_a01保留 |
| 每日奖励/通行证 | SurvivalDaily.Open(false/true)，PassStatus/PassEntry打开权益；PassPurchase发survival_pass_purchase且受purchase_enabled约束 | daily_purple与共享框；C12原生实际第2日、7日9奖励与真实资格；补签/通行证是原页面内切换 | 原事件、价格、有效期与disabled/pending保持；浏览器四尺寸和真实controller回归，未实际领取、补签或购买通行证 |
| 每日奖励说明 | DailyRules按钮切换DailyRulesText；真实rule_text/makeup_days/specials | A06紫底金边规则popup、19字、按内容收紧/长文滚动；C14真实9行规则已实看 | 奖励tooltip与规则互斥；50行长规则与滚到底为组件预览验证，原生不声称运行50行样例 |
| 抽奖主页面/详情/记录/公告/单件效果 | SurvivalLottery.Open/Feature(details/history/announcement/update/reward)与原卡片/底部按钮；当前服务端奖池/最近本局30次记录/描述 | L03紧凑紫色主框与menu_purple的详情共享框；C12真实券0/单抽1/十连10/SSR保底，C13记录标题、C14真实元数据、C16的400积分同一行已实看 | 原draw/result/reveal/history路径及热重载/嵌套关闭用完整controller和本地recording mock验证；未真实抽取，不声称真实reveal动画或新增跨局记录 |
| 抽奖券购买/首充/礼包特权 | Feature(purchase)仅显式点击后进入SurvivalCommerceView.OpenTicketPurchase，按当前真实pool/ticket_content_id匹配；firstgift/privilege使用现有未开放提示 | 购买复用紫色账户商城/原checkout；未开放提示复用紫色详情框 | 普通券保留玩法获得提示、金色券保持实际商品路由；首充连领和免费单抽权益未接入，不新增扣券/发放逻辑或伪造可领取礼包 |
| 神兵晋升帮助与提交 | ArchivePromote真实按钮；ShowEffectOnly显示目标名、条件、等级与原兑换事件 | 已A11状态反馈、A10紫金说明；无额外确认弹窗 | 保留原提交与服务端权威，不新增确认步骤 |
| 生存店商品购买/提品 | SurvivalShop.ToggleShop与原ShopEntryTooltip购买按钮；本局金币/木材/条件由原快照驱动 | Shop A14紫色4列，C14装备/挑战/其他三分类、金字居中和旧青条清除已实看；C13不透明tooltip已复核 | 四/五/六列真实同状态比较保留4列，720p仍可辨关键等级；未真实购买。活动UI无独立提品/升品/升阶确认，原tooltip直接购买路由保留 |
| 排行榜 | 共享框只有disabled占位tab | 未接服务器数据 | 保持禁用，不创建榜单/名次 |

VIP真实奖励来自vip_catalog.js（12等级特权、10勋章、11礼包共33），其来源archive_vip_rewards.csv/levels.csv。当前卡片均使用既有vip.svg；新呈现不编造独立物品图片、收藏数量或领取资格。VIP是否可见由原public profile规则决定，不为了截图改变真实入口权限。

活动源证据：archive.xml加载vip_catalog/vip_window；payment_test.xml由manifest单独Hud加载，脚本prepareShell可能晚于主HUD helper，因此新的checkout外壳接入须沿原惰性prepareShell调用。commerce_remaining的checkout明确按purchase_method分支，两个确认窗口均为生产业务路径。

commerce_actions.js是商城能力的右侧战斗操作与瞄准输入，ArrowTowerDestroyConfirm是销毁战斗建筑，DifficultySelection/Rogue选择/技能选择为开局或战斗必选；本轮不归入普通菜单迁移。

返回按钮沿原生DOTAHUDShowDashboard打开官方首页，设置沿DOTAShowSettingsPopup打开官方设置；社交按钮切换原生SharedUnits/SharedContent/CombatLog。完整/简化特效按钮沿原ui_combat_effects_setting，只改变战斗效果设置，不是遗漏的业务弹窗。以上官方界面与战斗输入不改造。

GameInfoPanel实际由SurvivalInputDispatcher的TAB战斗快捷键进入，survival_game_info提供建筑/英雄属性并每0.25秒刷新原生英雄血量。当前是透明战斗属性覆盖层，属于保留的战斗输入范围；不因存在Open/Toggle API就把它迁进购买/存档菜单，也不改TAB绑定。

SurvivalEquipment/SurvivalAppearance在旧HUD导航action map里有名字，但当前未发现实现API，当前活动顶导航也未展示装备/外观业务入口；不根据名称新增无数据的菜单。

实际分工：存档代理完成VIP（源码与新CSS、现有VIP行为回归）；商城代理完成wallet/payment两套checkout；Root保持共享框/抽奖/每日与原生操作所有权。组件预览仅调用本地fixture与recording mock；原生截图沿真实已同步状态，未进行真实购买/支付/领取。

有意义的行为证据分开记录：存档的[archive_lifecycle.test.cjs](../../tools/tests/archive_lifecycle.test.cjs)、[archive_fragment_tooltip.test.cjs](../../tools/tests/archive_fragment_tooltip.test.cjs)、[test_archive_work_click.cjs](../../tools/test_archive_work_click.cjs)和[test_archive_artifacts_navigation.cjs](../../tools/test_archive_artifacts_navigation.cjs)覆盖真实controller与原动作；[treasure_purple.test.cjs](../../tools/tests/treasure_purple.test.cjs)与[vip_window.test.cjs](../../tools/tests/vip_window.test.cjs)验证所属生命周期、权威状态与防重。商城/支付用[commerce_verify.cjs](../../tools/purple_ui_10h/commerce_verify.cjs)、[checkout_verify.cjs](../../tools/purple_ui_10h/checkout_verify.cjs)、[test_commerce_wallet.cjs](../../tools/test_commerce_wallet.cjs)和[test_payment_ui.cjs](../../tools/test_payment_ui.cjs)，抽奖/奖励用[lottery_verify.cjs](../../tools/purple_ui_10h/lottery_verify.cjs)和[daily_verify.cjs](../../tools/purple_ui_10h/daily_verify.cjs)。这些网络与交易均由本地记录器代替；浏览器ESC是调用原API，只有Root具名原生ESC截图能证明当次引擎键盘路径。

当前审查未发现已实现普通菜单入口被移除；未开放/原生官方/战斗必选入口均按上表保留边界。原生目前为1600×900当次会话；720/1080/1440/超宽的浏览器截图不等于四种引擎分辨率已验。C16账户商城最右详情失败与VIP/checkout原生待验仍明确保留；待Root接受A17后再更新最终覆盖与BEST。
