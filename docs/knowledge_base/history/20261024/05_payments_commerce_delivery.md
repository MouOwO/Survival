# 05 商城、支付、权益与奖励交付

核对日期：2026-10-24。项目已有通用商城与独立支付服务，也有历史真实微信验收；当前 WS4 是独立四账号测试，真实支付关闭。网页授权成功、库存测试通过、生成付款码和真实收款是四种不同证据，不能相互替代。本次未下单、未查单、未读取商户密钥或连接远端。

当前开发 `all_difficulties_unlocked=true` 还有整局只读验收隔离，不能把本地领取/兑换表现当作正式到账；它与 WS4 关闭真实支付是两道不同限制。以下说明正常契约与各自历史验证范围。

## 两条购买路径与唯一配置来源

钱包兑换走 `survival_commerce_request → commerce_service → /v1/archive/command → commerce_settlement`，不调用支付网关；真实付款走 `survival_payment_request → payment_service → /v1/payments/*`。两者共享商品能力、永久道具身份和限购语义，不能各发一份同名物品。前端只表达购买意图，账号来自游戏玩家身份；价格、余额、奖励、效果、是否持有均由服务端决定。

现金商品定义位于 `data/csv/商城支付系统/payment_categories.csv`、`payment_products.csv`、`payment_rewards.csv`；钱包商品位于 `商城兑换系统/commerce_products.csv`、`commerce_rewards.csv`、`commerce_bundle_members.csv`。编译器 `csv_catalog.py/commerce_bundles.py/ucoin_catalog.py` 联合权益、属性、抽奖道具和币种定义验证引用、限额、效果、套装组成，再生成有 hash 的目录；生成 Lua、目录 JSON、UI 展示均为派生物。修改生成文件或线上一行价格不能代替更新权威 CSV 和发布目录。

当前协议键 `u_coin` 的展示名曾从 U币变为 G币，字段不能随显示名称更改；`shop_points` 是积分，`shop_gold` 是商城金币，和单局木材/金币资源不是同一账户。余额位于 `save.archive.commerce.balances`。金币兑换当前明确返回 `shop_gold_not_open`，不能因为目录含该币种就开放购买。普通券 `lottery_ticket` 来自玩法；金色券沿用 `special_lottery_ticket` 身份，除经过验证的付费渠道外，当前福利也有专门发放能力，不能把“external_purchase_only”旧分类误解为禁止已实现福利。

当前新报价为 1元=100个 `u_coin`；充值 SKU `u_coin_recharge` 每份100分，到账100币。历史订单可保留1000比例，读取 `reward.grants.pricing` 和 `unit_pricing`，不能按新比例重算旧单。充值到账数独立验证，不从显示报价推导。普通数量上限100、总金额上限1000000分；充值数量上限999999，安全整数余额上限9007199254740991。月卡现价5800分，30天，明确固定价策略；历史20元基准仅作记录，不能再次五折。部分旧文档仍写50元、20元或1000比例，应以当前 CSV、代码和对应发布记录为准。

## 最小业务接口

所有游戏支付请求携带 `account_id,match_session_id`，只允许服务端 Bearer 凭据调用；支付服务还核对允许账号及数据库 session。不存在浏览器直接传 Steam ID 就获得发奖权限的接口。

| 路由/事件 | 额外字段或意义 |
| --- | --- |
| `POST /v1/payments/catalog` | 返回服务端 products、categories、catalog_hash、渠道能力 |
| `POST /v1/payments/create` | `sku`，可选 `provider=wechat/alipay`、整数 `quantity` |
| `POST /v1/payments/status`、`cancel` | `order_id`，必须属于当前账号 |
| `POST /v1/payments/reset` | 仅测试，`kind,request_id`，不是退款接口 |
| `POST /v1/payments/wechat/notify` | 原始带平台签名的 JSON 通知 |
| `POST /v1/payments/alipay/notify` | 平台签名的表单通知 |
| `survival_payment_result` | 单玩家结果，包括 action、state、报价、可选 qr_matrix |
| `survival_commerce_request/result` | catalog 或 purchase；购买只给 sku 与稳定 request_id |

钱包购买命令为 `kind=commerce_purchase,id=commerce:<request_id>,sku,request_id`，外层还带 config_hash。扣款、道具、效果与 receipt 一次提交；余额不足、限购、VIP 条件或属性溢出时整笔拒绝。旧确认价格与当前积分价格不同返回 `commerce_price_changed`，必须刷新后重新确认，不能直接以新价扣钱。

## 从下单到可信到账

1. 数据库 `payments.create_order_quantity()` 验证账号 session、商品启用、渠道、持有、限购、数量及金额，把标题、完整奖励、权限时长、单价、数量和目录 hash 冻结进 `orders.reward`。同账号同商品已有未完成订单时复用；切换数量或渠道返回冲突提示，先处理旧单，不能偷偷创建第二笔。
2. 微信创建 Native 订单并保存 `weixin://` 付款码。支付宝根据服务配置使用 `page_pay` 或 `precreate`；两者权限不同。游戏原生二维码展示使用后端生成的 `qr_matrix`，不是前端拼接商户支付地址。备用 checkout 链接带按订单签发的访问凭据，仅允许查看该单，不能调用内部发奖。
3. 微信先验平台序列、签名和五分钟时间窗，拒绝重复签名头，再 AES-GCM 解密；核对事件成功、NATIVE、订单号、商户/应用、CNY和精确整数分金额。支付宝严格解析不重复字段的 UTF-8 表单，验证 RSA2、商户/应用、订单号、金额，成功状态限定 `TRADE_SUCCESS/TRADE_FINISHED`。浏览器同步返回页不作为付款成功证据。
4. `Payments.success/alipay_success → payments.deliver` 再次检查冻结订单及交易号。账号行和订单行上锁；同渠道交易号唯一，同单重复通知返回原状态，奖励只交付一次。库存、权益、属性、审计 before/after、revision 和 delivered 在同一数据库事务提交后才算成功。
5. 游戏收到 delivered 后调用 `profiles.refresh_player`，等待权威新档案应用完成再通知玩家。刷新失败提示 `reward_refresh_pending`，不能再次发奖；重新查原订单即可。请求按账号、session 和 busy job 校验，旧回调不串号；刷新35秒兜底释放等待，避免已被新 generation 取代的回调永久卡住。

重要表为 `payments.orders/products/providers/catalog_state/test_accounts`；订单包括金额、货币、provider、reward、transaction_id、expires_at、paid_at、granted_at、generation 及 applied_* 审计字段。应用角色 `goufayu_payment` 没有表写权限，仅调用白名单函数；普通游戏角色不能执行 deliver。不要把 `schema.sql` 当成当前完整结构重新安装，它只是早期首单版本，现有数量、双渠道、月卡、礼包、充值能力由后续迁移叠加。

## 超时、重试、退款与风控边界

订单一般30分钟有效。后台每10秒查待处理订单；网络故障保留原单，网关已收单但本地未保存二维码时仍用同一商户单号恢复。关闭前先查最终状态，已付款转交付；只有经验签的状态才能确认关闭。支付宝网页单在绝对到期前仍可能被用户提交，查无订单不立即放行另一笔，必要时返回 `payment_close_pending`。延迟成功通知仍须核对并处理，不能仅因本地显示过期丢弃资金事实。

付款后奖励已被其他途径获得、超过上限或测试重置 generation 改变，订单进入 `paid_review` 留待人工处理；不重复发、不擅自换奖励、不再次扣款。当前没有自动退款接口，也没有经过验证的全自动退款后撤销权益/成长链。`refreshmoney/refreshdata` 是受开发构建、HTTP 开关和数据库测试名单限制的测试回退，不是正式退款工具。真实退款需人工核对网关交易、退款流水与已消费奖励，保留原订单及处置审计。

服务已有请求体上限、字段白名单、支付签名、账号隔离、进程锁及数据库行锁；不等于具备完整商业反作弊。玩家自托管进程仍能伪造战斗结果，不能把本机局生成的财富和成绩接入正式收费经济、交易市场或可信排行榜。上线前还需独立确认支付产品权限、退款与客服流程、异常订单告警、备份异地保存及法律合规，不应通过关闭验签或扩大数据库权限解决接入失败。

## 月卡、VIP、礼包和日常发放

月卡权益 ID 为 `archive_pass`，按订单冻结的 duration_days 发放；有效月卡续费从原到期时间增加30个24小时，已到期从当前交付时间算；旧永久权益保留，永久月卡禁止再买。权益到期不删除永久道具，也不能修改已经完成的历史订单。VIP 充值进度由 delivered 状态触发器写 `vip_recharge_credits`，按订单及渠道交易号去重，累计到 `vip_recharge_total_fen`，按档位计算等级；测试重置账号和历史订单不自动回填。

`VipProgression.reconcile()` 只按已存充值进度补领免费 privileges，使用固定 receipt ID 和持有标记；它不代表重新收款或购买VIP礼包。礼包、组件限购、VIP已领取标记和效果去重共同校验。抽奖券在 `content_inventory`，抽奖通过 archive receipt 消耗与发放，不能使用前端显示数量当余额。每日赠礼、在线、胜场和周常依赖统一05:00周期与 claimed 记录；具体“可领”“已领”由服务端状态决定。

## 已验证范围与复用步骤

历史证据确认：2026-09-28 微信0.10元首单真实回调、一次永久库存和游戏刷新成功；本文不携带任何订单号或玩家信息。支付宝网页接入及签名查单有历史记录，但2026-09-30原生扫码 precreate 权限被拒，不能据此宣称扫码已开放或已有真实支付宝付款。10月17日100比例/半价和随后58元月卡已部署验证，使用合成事务回滚测试，没有新增真实付款。10月21日福利基础版本已部署；后续零分钟手动月卡赠券在本地通过，普通服务发布记录仍待完成。

当前 `server/workshop_test/run_api.py` 强制独立 `goufayu_ws4`、四账号与 `payment_mode=test`；`commerce_release_policy.real_money_allowed()` 在公开/测试构建直接关闭现金路径，离线逻辑入口即使残留旧 token 也不得发起支付 HTTP。钱包兑换和隔离测试存档可继续验证，不意味着正式商城、真实付款或可信排行开放。

迁移新项目时先固定币种、SKU、权益与不可变 receipt 契约，再重建测试库、目录编译、RPC权限和支付沙箱/合成验收。维护入口包括 `tools/build_payment_catalog.py`、`tools/sync_payment_shop.ps1`、`payment_backend/sync_catalog.py` 及各 `upgrade_*` 的 validate/activate；按当前远端基线 hash 准备、同事务试运行后回滚、完整备份、切换命名版本并验证。恢复要包括 public/extensions/payments 的同一快照，不能只还原游戏而保留另一时刻订单。

关键回归入口：`payment_backend/test_payments.py/test_alipay.py`、数量/充值/月卡/礼包数据库专项、`tools/test_payment_reward_refresh_chain.lua`、`test_payment_profile_refresh.lua`、`tools/tests/test_offline_payment_isolation.lua`。部署证据见 `validation/20261017/{shop_half_price,monthly_pass_58}.json`、`validation/20261021/{benefits,benefit_login_manual}.json`、`docs/payments/payment_acceptance_20260928.json`、`publishing/workshop/test_listing.json`。本次整理未重跑支付测试或刷新这些线上证据。
