# WS4 独立支付候选审阅

默认 `python -B tools/arcade_payment_link_20261027/run.py` 仅在内存生成计划，既不联网也不写文件。`plan --save-plan` 把完整公开计划写到忽略的 output，供根 agent 审阅。

`audit` 通过既有固定主机指纹 SSH 传输执行只读检查，完整脱敏结果落到 output。SQL 只连接固定 `goufayu-ws4-db/goufayu_ws4`，每次都是 READ ONLY + ROLLBACK；只返回数据库结构、支付表聚合数量、函数指纹及能力标记，不查询或导出玩家／订单行。

`prepare --review-hash <具体计划摘要>` 只把已冻结源码、现金目录、钱包目录及参考 CSV 写入全新的 `/root/goufayu_upload/ws4-payments-<摘要>` 私有目录。它不创建运行配置、凭据、用户、unit 或最终 release，不变更数据库、权限、现有文件或服务。

`run.py` 只负责只读审计和源码暂存。独立的 `activate.py` 生成包含审计记录的激活胶囊；只有提供精确 `--review-hash` 才能执行 `stage/activate/verify/enable/disable/rollback-no-orders`。默认无参数不联网、不写文件。激活必须由根 agent 审阅后执行，不能因为旧八个 RPC 存在就认定月卡、数量、VIP 充值、礼包和钱包充值语义已部署。`schema_contract.py` 将 35 个最终函数及其历史重命名版本、数量升级的 3 处精确替换与当前项目 SQL 逐一比较，包含函数体、参数、返回类型、语言、owner、SECURITY DEFINER 与 search_path。

计划固定新实例为 `/etc/goufayu-ws4-payment/config.json`、`127.0.0.1:18769`、`https://pay.xiaofengnet.com/ws4-payments`、`goufayu_ws4:15432/goufayu_payment`；原支付服务 :8766、旧回调、旧 API／数据库 PID 与 release 指针均需保留。专用角色只能连接隔离库、使用必要 payments RPC，无直接表或 owner 权限，reset 关闭。

正式目录为 48 条启用现金报价和 125 条启用钱包报价；源表另有停用条目，冻结时一并保留。`catalog_validation.py` 不导入固定旧库的 `deploy` 或 `sync_catalog`；它重新编译目录并逐份核对 WS4 实际 bundle。任何不一致先停止，不能将本机新目录直接发布到旧服务器定义上。

新 game_token、checkout_key 和数据库密码只可在后续经审阅的远端激活阶段生成并私有保存。档案 hash 必须复用 WS4 自身 pepper；商户参数从旧配置在服务端读取，5 份固定商户 key 可仅在远端私有复制至新实例目录、只读授予新服务用户；旧文件内容、owner、mode 与旧用户组均不改，密钥不下载、不提交、不进入候选包。

激活只 seed 已存在的 11 张空支付表中的配置：完整 50 条现金目录（启用 48）、属性规则、VIP 12 级、商户参数和禁用的 reset。四账号入口限制保存在新 config；不插入玩家、测试账号、订单或模拟交易，不重放任何 SQL 迁移，不修改 public 玩家数据。先以 `PAYMENTS_ENABLED=0` 切换新的 PWA release，复用原 SQLite、浏览器 secret 与同一组 Steam 账号。实际助手完成 Steam 授权和云档读回后，`enable` 另行要求真实读回记录摘要。

`disable` 只关闭新的 PWA 下单入口，保留 callback/worker 处理已经存在的支付，保留全部账本。`rollback-no-orders` 必须先证明新订单、VIP credit、reset 等账本全空及配置仍是本胶囊版本，才停止新服务并恢复旧 PWA/env/Nginx 和角色 state、移除本次配置 seed；不使用 pg_restore、不重放 schema、不删除玩家、收据或旧库数据。已有交易后保留账本并前向修复。

本地安全检查：`python -B tools/arcade_payment_link_20261027/test_review.py` 和 `test_activation.py`，不调用真实网络、网关或数据库。
The cloud-authority candidate uses `--cloud-snapshot output/arcade_payment_link_20261027/cloud_sources_<stamp>`.
`restore_cloud_sources.py` defaults to a local plan; `--fetch` reads only eleven named public configuration files from two pinned release directories and the fixed immutable WS4 bundle. No player rows or credentials are read or exported. Ten reference sources must match actual bundle CSV hashes. `entitlement_definitions.csv` is absent from that bundle and is separately pinned to the exact original bytes also verified in the legacy payment release; its missing bundle entry is never synthesized. Existing WS4 wallet prices and legacy exchange rules remain unchanged. Current cash CSVs are compiled against these original cloud capabilities without loosening reward type or amount validation.

2026-10-27 实机记录：原游廊仍返回 HTTP factory nil，验证使用用户同意的本机连接助手及独立 WS4 库。助手序号 2026102702 修复了生产包缺少可选 offline debug 模块时的启动异常；单文件补丁保留原冻结包及其余 6638 份运行资源。原 PWA systemd unit 带前导空白，首次部署在替换前停止；`repair_pwa.py` 仅接续切换已有 PWA release，保留原 SQLite、浏览器身份和新支付服务。随后真实授权、云档加载及单独 enable 均完成。

已核对一笔微信 0.50 元的 `video_p033`（伐木斧·永久）：订单已付款及发放，发奖账本记录 `commerce_p033 ×1`，同一局的真实游戏日志在 `payment_delivered` 后发布 revision 218。对照账号钱包及版本未变化。这证明助手的真实商品支付、发奖及档案刷新；没有将它表述为原生游廊 HTTP 已修复，也未声称完成真实 G币充值 +100、重新登录后的道具显示或重复回调实测。详细脱敏结果在忽略的 output，公开状态保存在 `publishing/workshop/payment_helper_20261027.json`。

使用现有 `联网登录测试.cmd` 进入助手；原游廊多人入口继续保留。此电脑仍承担临时 Steam TLS 出口，需要保持在线。仅四个获准账号可使用测试支付；授权四小时过期后需重开，支付宝现为外部 page_pay，微信采用 Native 二维码。关闭新订单请使用 `activate.py disable`，保留已付款的回调及账本。

`live_readback.py` 是独立只读验收工具，不改变冻结的部署操作器。默认 `plan` 不联网；`schema` 只读表／列名；`snapshot --account <获准SteamID或AccountID> --match <真实新对局ID> --control-account <另一获准账号> --save-record` 先核对 PWA SQLite 当前真实批准、未撤销且未过期的会话，再只读固定 WS4 容器中指定账号的云 login、钱包 U 币和 profile revision。缺少真实批准会话时不读取玩家钱包，也不生成通过结果。数据库映射只在远端使用 WS4 pepper，不导出 pepper、token、映射 hash 或完整档案；只读 SQL 不调用可能结算奖励的 profile RPC。

支付前后分别保存 snapshot，再用 `live_readback.py compare --before <前.json> --after <后.json> --expected-u-coin 100 --save-record` 比较实际 +100、版本增加及指定 control 账户完全未变。比较结果只声明服务端数据事实，不证明付款订单或回调幂等。现有 PWA 没有 auth/profile HTTP 成功收据表且关闭访问日志，不能用批准或 rate 计数替代客户端回读；root 可结合真实 UI 截图自行组成完整验收记录。可选 `--client-receipt` 仅接受确实从真实 helper 捕获的绑定 account/match/wallet/revision 标量，不要求为了验收而制造游戏内不可见字段。
