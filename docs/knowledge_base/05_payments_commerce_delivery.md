# 05｜商城、扫码支付与权威交付

2026-10-31 根因：3101只读验收隔离商城/福利，默认已修false；兑换码还缺现役WS4的模块、3表2RPC及发布资源，历史另一后台部署不能代替本次授权。见[根因与上线边界](evidence/shop_readonly_root_cause_20261031.md)。

2026-10-31 后续：恢复运行仍空白，另有每日领取等待，尚未修复；已启用保留原认证规则的限量诊断，见[共同通路](evidence/shop_daily_transport_20261031.md)。

2026-10-31 游戏内商城：已按本次授权备份并将四人WS4同步到原游廊d573，原29张业务表与支付服务保持。重新登录后的真实获准身份经内部API能读126项钱包商品及48项现金商品，但用户确认恢复对局运行后仍显示目录未连接；真实游戏请求／回执仍待定位，不能称商城已修复。见[版本对齐及未完成验收](evidence/shop_catalog_sync_20261031.md)。

事实截点：2026-10-28。10/24知识包中“WS4现金一律关闭”的快照已过时：独立四账号 WS4 支付后端已接入，当前2802发行配置启用云档和现金能力；开发源码默认开关仍关闭。**真实支付证据是 helper2702 的微信0.50元伐木斧到账并生效，用户明确确认；原游廊2709加入方只完成手机识码和商品／金额核对，没有进行付款验收。** 不能把开关、账本、扫码与本局权益生效混成一个状态。

## 已完成什么、还缺什么

| 场景 | 已有证据 | 保留限制 |
| --- | --- | --- |
| 历史微信首单 | 2026-09-28，0.10元回调、永久库存和游戏刷新成功 | 属于历史服务，不替代WS4两账号验收 |
| WS4 helper2702 | 微信0.50元，`video_p033`伐木斧，delivered、单份库存、游戏刷新revision218；用户确认已生效 | 非原游廊客机交易；未测试真实充值数量到账 |
| helper2706 | 真实网页授权、云档revision223、积分失败结果与返回导航通过 | 因余额不足，真实积分兑换成功未测；未重付现金 |
| native2708 | 原游廊两人登录、逐人云档读回通过 | 当时加入方二维码错位；支付未验 |
| native2709 | 官方全量下载；原房间2人；加入方手机能识码，商品和金额正确 | 没有本轮真实付款、到账、权益刷新及重启读回验收；用户是否新建订单及总数未审计 |
| native2801／2802 | 保留2709的QR和认证／支付代码；作者官方完整下载通过 | 未重新进行客机支付；2802两人布局也待验 |

代理在2709及2801／2802修复轮次没有操作付款，不把“代理未创建订单”写成“用户没有订单”。总订单数未知时明确写未审计。

## 权威目录与币种契约

现金商品来自 `data/csv/商城支付系统/{payment_categories,payment_products,payment_rewards}.csv`；钱包商品来自 `商城兑换系统/{commerce_products,commerce_rewards,commerce_bundle_members}.csv`。`csv_catalog.py`、`commerce_bundles.py`、`ucoin_catalog.py` 联合核验引用、权益、效果、限购、套装和币种，再生成含hash的目录与Lua。生成JSON、Lua和UI均为派生物，不能只改线上一行金额或编译产物来更改报价。

已发布完整展示目录含173项启用报价：48项人民币、125项钱包报价；同SKU现金和钱包报价分别计数，不能称为173种不同商品。公开静态目录 `https://pay.xiaofengnet.com/ws4-shop/` 只是分类／搜索／详情，不创建订单、扣钱或发奖；快照不代表实时价格、余额与购买资格。

协议币种 `u_coin` 的展示名改为G币，字段名保持；`shop_points` 是积分，`shop_gold` 是商城金币，均不等于本局金币／木材。余额位于 `save.archive.commerce.balances`。商城金币交易当前拒绝 `shop_gold_not_open`，目录里有它不等于可购买。普通抽奖券是 `lottery_ticket`，特殊／金色券保持 `special_lottery_ticket` 身份；福利可以通过已实现专用能力发特殊券，不要将旧 external_purchase_only分类误读为禁止福利。

当前兑换比例为1元=100个 `u_coin`，充值SKU `u_coin_recharge` 每份100分、到账100币。历史订单可冻结1000或100比例，必须读订单pricing／unit_pricing，不按新价重算旧单。普通购买数量上限100、金额上限1000000分，充值数量上限999999；余额遵守安全整数上限。月卡 `archive_pass_monthly` 固定58元／5800币、30天，采用 `monthly_fixed_58_20261017`；旧20元基准只作历史，不再二次五折。价格与奖励以当前权威CSV和实际发布目录核对。

2026-10-28 用户确认的新开发配置：普通抽奖券 `lottery_ticket_single` 3元／张；`special_lottery_ticket_single` 调整为6元／张，与既有 `video_p001` 的6元／600币一致。特殊券全游戏统一显示为“金色抽奖券”，协议ID仍为 `special_lottery_ticket`。普通券改为玩法与购买共同产出，原福利渠道保留；抽奖界面的购买入口按实际券ID选择单券商品，不能误选含券礼包。两种现金单券使用 `fixed_ticket_price_20261028`，旧订单仍按冻结快照交付，不能追改金额。

本轮商城积分单品标准价：N=100、R=500、SR=1000、SSR=2500、UR=5000。用户明确指定两个例外：`video_p103` 薪火余烬1个、`points_welfare_zongzi` 粽子1个均为60积分；余烬不限次数，粽子沿用150个库存上限。库存派生基础攻击成长与阶段效果，不把每次购买的成长重复写成永久属性。旧余烬百个装 `video_p089` 继续下架。历史参考价保留作证据，不参与再次打折。

商城所有分类（包括首页与只读预览）按显示售价数值从低到高排序；人民币分先转元，G币和积分分别按显示数值排序，没有引入跨货币兑换率。新开发公开目录为175项启用报价：49项人民币、126项钱包；先前已发布的173项快照保留为历史状态。本轮完成本地编译与回归、双仓Git交付，不代表云端商品同步、结算服务激活或游廊发布。详细证据见 [本轮记录](evidence/commerce_prices_20261028.md)。

## 两条交易链路

钱包兑换：`survival_commerce_request → commerce_service → /v1/archive/command → commerce_settlement`。命令为 `kind=commerce_purchase,id=commerce:<request_id>,sku,request_id`，还绑定config_hash。前端只发送购买意图与稳定request_id，不能传权威价格、余额、奖励或收款对象。扣款、道具、属性效果和receipt在一个事务提交，余额不足、限购、VIP条件或溢出时整笔拒绝。旧确认价改变返回 `commerce_price_changed`，刷新后重新确认，不能悄悄以新价扣钱。

现金：`survival_payment_request → payment_service → /v1/payments/{catalog,create,status,cancel}`。游戏服务端的玩家令牌先经网页sidecar核验，账号与match从已持久化授权取值，再由服务端独立支付凭据转发到loopback18769。客户端不能用手填SteamID、支付Bearer或“已支付”消息获得发奖能力。

sidecar严格限定路由、字段、数量、渠道和SKU格式。订单status／cancel必须属于同账号、同局的持久绑定；大厅 `lobby_` 会话不得访问支付或云档。目录返回失败不应该误撤销合法玩家身份。支付上游响应只放行白名单字段，拒绝任一内部秘密泄漏；转发后再次检查授权仍有效，避免旧授权撤销期间返回的订单能力落入旧会话。checkout仅接受独立WS4收银台的单订单能力，不能据此调用内部发奖接口。

开发 `config/commerce_payment_access.lua` 默认 `enabled=false`。冻结候选通过审核后单独启用；`commerce_release_policy`还检查production、正确地图、网页认证、四账号门禁和相应helper许可。离线内存档、模式全解锁验收隔离、本局多人内存provider都拒绝现金，不能靠残留token或前端开关放行。当前listing现金true是发行配置，不是任意开发局都能付费。

## 下单、扫码、通知与到账

1. `create_order_quantity()` 核对session、账号范围、商品、渠道、持有、限购、数量和金额，把单价、数量、奖励、权益时长、目录hash冻结到订单。已有同账号同商品未完成单优先复用，换渠道或数量须显式处理冲突，不能隐建第二笔。
2. 微信Native下单得到订单专属码；支付宝按商户权限走page_pay或precreate，二者能力不同。游戏展示后端 `qr_matrix`，不加载外部付款图片、不在前端拼商户地址。只给该订单玩家发送二维码和状态，不广播订单能力。
3. 微信通知校验平台序列、签名、五分钟时间窗、重复签名头，再AES-GCM解密，核对成功事件、NATIVE、订单、商户／应用、CNY和精确整数分。支付宝严格解析无重复字段表单，校验RSA2、商户／应用、订单、金额和允许成功状态。浏览器返回页不能作为到账证据。
4. `Payments.success/alipay_success → payments.deliver` 再核对冻结快照和交易号。账号／订单行锁、渠道交易号唯一、receipt幂等，确保重复通知仅返回原状态。库存、权益、属性、before/after审计、revision和delivered在同一数据库事务提交。
5. 游戏收到delivered后调用 `profiles.refresh_player`，待权威新档案应用成功才告诉玩家生效；失败显示 `reward_refresh_pending`，查原订单恢复，不能重发奖励。按账号、session和job generation核对回包，35秒兜底释放等待，防止旧回包串号或永久卡住。

重要表包括 payments.orders/products/providers/catalog_state/test_accounts；角色仅调用白名单函数，不给通用写表或deliver权限。`schema.sql`只是早期首单结构，不可覆盖当前数据库；数量、双渠道、月卡、礼包、充值、VIP来自后续迁移。部署必须对现有真实基线做精确升级。

## 自有商城、兑换面板与二维码几何

玩家使用自有商城美术和组件，保留首页／礼包／促销／VIP／全部商品及增量列表。未知余额、持有、限购显示“—”，不能伪装成已同步零。原生只读目录不覆盖认证目录，认证可在关闭只读窗口后恢复。

积分／G币兑换已改为直接权威请求和紧凑成功／失败面板，旧紫色兑换窗口入口已退休。点击pending防重复，未知结果重试保留原request_id；迟到回包不得重开已关闭面板；真实价格变更要求新确认。世界称号等覆盖跟随模态层隐藏，窗口关闭／重载要释放所有权。像素调整历史不作为长期知识保存。

2026-10-29新增商城标题旁“兑换码”，复用购买按钮，弹窗使用原生输入框与按钮，错误采用官方HUD提示。127项非VIP商品各有独立码，另有1个全部非VIP奖品码；每账号每码一次，礼包/单品永久权益去重，错误、过期、停用与总次数限制由数据库判断。码表只在服务器登记哈希，真实码Excel在用户桌面，不进入客户端或Git。服务器已启用独立兑换码版本，支付进程和原d573存档配置保持；真实数据库克隆验收通过，尚无真人兑换或新版游廊包验收。见[兑换码功能与部署记录](evidence/redemption_codes_20261029.md)。

2709二维码修复将行流布局改为固定白底画布和黑色区段绝对定位，防止缩放时不同QR行被舍入／挤压成不同宽度。后端保持4模块静区、严格矩阵校验、订单过期与归属检查；清理失败不能保留已完成缓存。源码与game/content镜像对应，Valve真实编译1成功0失败，46项本地检查含8项几何检查通过，之后加入方手机实测通过。数学模型不等于Panorama像素测量，扫码成功也不等于付款。不要解析、归档或复用用户二维码载荷。

## 超时、异常订单与退款

订单一般30分钟有效，后台周期查询待处理单。网关已收单但本地未保存二维码时使用同一商户单号恢复，不能重复建单。关单前先查最终状态，已付款转交付。支付宝网页单在绝对到期前仍可能提交；查无订单不立即放行第二笔，必要时返回 `payment_close_pending`。延迟成功通知仍核对处理，不因本地曾显示过期丢失资金事实。

付款后奖励已被其他途径获得、达到上限或测试generation改变，进入 `paid_review`，保留资金和奖励处置审计；不能重复发、不擅换奖励、不再次扣款。没有已验证的全自动退款＋权益撤销链。`refreshmoney/refreshdata` 是构建、HTTP与数据库名单约束的测试回退，不是退款工具。真实退款需要人工核对网关交易／退款流水及已消费权益。

## 月卡、VIP、礼包与日常权益

月卡权益ID `archive_pass`，按冻结duration_days交付；有效续费在原到期时间加30个24小时，已过期从本次交付时间起算；历史永久权益保留且不再允许重复买永久月卡。到期不删除永久道具、不改已完成旧订单。月卡每日加成规则按用户本轮决策保留当前配置，具体上限见[03](03_progression_save_contract.md)，不再以旧“VIP／月卡不提高最终上限”的历史句覆盖。

VIP充值进度由delivered触发器写入去重充值credit及累计分，再计算档位；测试重置和历史订单不会自动回填。`VipProgression.reconcile()` 只按已存进度补免费privileges，用固定receipt与持有标记，不代表重新收款。礼包组件限购、已领取与效果去重共同校验；抽奖券在content_inventory，消耗与发放使用archive receipt。每日／在线／胜场／周常采用统一05:00周期和claimed状态，前端按钮不能决定可领取。

## 运维、验证与复用

独立WS4支付服务、DSN、最小权限角色、四账号、正式目录及回调已配置，旧服务／旧账本不迁移。10/26曾只读发现WS4支付表空、角色无CONNECT，该结果是接入前历史，不应再当当前状态。最新接入依据为 `publishing/workshop/payment_helper_20261027.json` 及其激活review摘要；本次知识整理没有重新连接云端或重新下单。

维护入口：`tools/build_payment_catalog.py`、`tools/sync_payment_shop.ps1`、`server/payment_backend/sync_catalog.py`及各upgrade工具的validate/activate。按当前远端hash准备、备份、事务试跑后回滚、切换命名版本再验证；备份恢复必须包含同一时点public/extensions/payments，不能只回游戏而保留另一时点订单。

回归入口：`server/payment_backend/test_payments.py`、`test_alipay.py`、数量／充值／月卡／礼包数据库专项、`tools/test_payment_reward_refresh_chain.lua`、`test_payment_profile_refresh.lua`、离线支付隔离、钱包结果与QR几何测试。历史通过不是本次重跑；已知旧高度／tooltip断言与冻结基线同样失败，不能把它们悄悄改成PASS。

下一轮先让第二台获得正确2802，再验证双方独立账号交易隔离、实际积分成功、扫码小额付款、权威到账、限购与余额刷新、退出重开读回。支付验收需避免重复建单／重复收费；先核对现有待处理单。支付宝precreate历史被拒，当前以page_pay为已配置路线，尚无WS4真实支付宝付款证据。正式开放还需要稳定Steam出站、可信奖励来源、异常单／退款处理、告警、备份恢复和四人长局测试；本地主机禁作弊不构成商业反作弊证明。

依据：商城接入历史（项目来源：`docs/payment_shop_20261026.md`）、自有UI历史（项目来源：`docs/native_shop_qr_20261026.md`）、加入方QR修复（项目来源：`docs/guest_payment_qr_20261027.md`）、payment helper记录（项目来源：`publishing/workshop/payment_helper_20261027.json`）、native2709记录（项目来源：`publishing/workshop/native_arcade_cloud_20261027.json`）。迁移新项目可复用订单状态机、签名验收、幂等与刷新屏障；不能沿用本项目域名、商户凭据、真实账本、测试身份或付款码。
