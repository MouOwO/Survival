# 全存档 HTTP 联调方案

## 2026-09-14：默认木材纠正

修复 `resource_system.lua` 将本地 10 与 HTTP 档案初始木材 10 重复相加的问题，档案字段现在作为完整开局数量。`player_gameplay_stats.csv` 的 `wood_per_second` 默认值从 1 改为 0；实际奖励仍可增加该字段。已执行 `202609140003_remove_default_wood_income.sql`，用一次性迁移记录扣除已有云档的旧基础 +1/s，并增加档案 revision，不反复扣减、不重置其他奖励。新配置 hash 为 `78b3d33d78e5bc4adc10dc15ae0bfe5f969f377a4ac0d6f0eadcacbbb98adb56`。

后端已同步重启，日志改为 `output/backend_integration/wood_fix_stdout.log`、`wood_fix_stderr.log`。通过真实 HTTP 复查当前账号：`initial_wood=10`、`wood_per_second=0`，游戏/后端 hash 一致。开局资源、30 次收入 tick、重复档案刷新、实际收益奖励及通关冻结测试通过，16 项后端回归通过。已通过控制台重新加载联调局。

## 2026-09-14：HTTP 权威联调已接通

- 当前存档、抽奖使用同一份 CSV 生成不可变后端包，当前 hash 为 `c9c0b2ba60ee0368f92f3c1d6b21038743edfd33cc6aa2eb2b5c356a55103ef5`。纯展示图标表由 UI 构建器处理，不进入结算包。`build_archive_configs.ps1`、`build_lottery_configs.ps1` 和 `build_archive_server_bundle.py` 同步游戏/后端配置；修改结算 CSV 后须构建、同步配置并重启 HTTP 和新游戏局，不能在旧局混用 hash。
- 主抽奖新增 `/v1/lottery/snapshot`；抽取、积分兑换、已读记录经 `/v1/archive/command` 的 `lottery_*` 命令，由 Python 调用共享 Lua 结算，HTTP 返回奖池内容及结果。游戏只缓存展示数据和转发操作，不再注册原本地抽奖实现，不自动赠送 1000 张测试券。价格、权重、保底、奖励属性来自后端加载的 CSV；客户端不得提交 results/roll/价格。
- 已停用 `commerce_remaining_5d5c1152eb.js` 的本地商品预览、假订单、模拟二维码/支付成功入口，并编译到游戏；抽奖券购买提示暂未开放。真实支付接口未实现，不能用演示订单代替入账。
- `player_profile_rules.csv` 默认 `http_fishing`，联调运行时拒绝本地 provider 和 isolated_test；本地单元测试仍可显式注入测试替身。游戏连接阶段预取档案，后续 UI 保持缓存与版本化增量；HTTP 故障不会回退假档案。HTTP 不再接受 faith_cheat。
- 用户授权后已通过已打开的 SQL Editor 执行 `202609140001_http_lottery.sql`（扣券、发奖、属性与回执在一个事务内）和 `202609140002_gameplay_stats_csv_bounds.sql`。后者根据 97 项当前 CSV 同步列默认值/约束，修复真实初始化暴露的旧 tower_attack_interval 约束；不重写玩家既有数值。用户先前执行的建筑字段迁移也已只读复查成功。
- 后端代码已部署到 `D:\survival_database\backend`，`.env` 持久设置 `SURVIVAL_ARCHIVE_HTTP=1`，8765 服务已由后台进程运行，日志为 `output/backend_integration/http_lottery_stdout.log` 和 `http_lottery_stderr.log`。原黑窗口进程已结束，无需同时再次启动占用端口。
- 实际 Steam 账户通过真实 HTTP/Supabase 验证了四个奖池读取、visit 入库、重复请求回执一致、独立 profile 请求读回；未赠送测试货币、未用真实货币抽奖。16 项后端测试覆盖模拟数据库事务与真实 Lua 的十连保底、余额不足、丢回包重试、兑换、已读；游戏传输缓存/异步结果/增量回归通过。
- 真实数据库补充通过零券抽奖失败路径：返回 `lottery_ticket_insufficient`，库存保持不变。再次开局后 HTTP online checkpoint 读回先前累计的 153 秒，确认不是新局内存重新从零初始化；未代替有余额抽奖成功发奖的验收。
- 已通过 VConsole 加载本机私有 `survival_archive_http_local.cfg` 并重开地图。新局后端记录 `/v1/profile`、`/v1/lottery/snapshot`、`/v1/online-time/checkpoint` 均 HTTP 200，控制台确认 provider=http_fishing。真实有余额的抽奖发奖、兑换和断网/重启恢复仍需后续游戏操作验收，不以只读/visit 测试替代。私有 cfg 含 API token，不得提交或分享。

下面保留此前阶段记录，当前状态以上述实连结果为准。

## 2026-09-14：页面预取与持久化联调进展

### 后续实连检查（用户启动 HTTP 后）

用户开启扩展并重启后，运行中的 `/v1/archive/config` 已返回 HTTP 200，摘要与游戏一致。本机私有 `survival_archive_http_local.cfg` 已准备（包含令牌，不纳入仓库、不分享），用于新局 HTTP 配置。进一步通过 Python 检查第三份迁移的四个字段时，数据库返回 HTTP 400 / PostgreSQL `42703`；至少一列尚不存在。因此先执行 `server/migrations/202609060003_archive_buildings.sql` 再开新局，目前尚未完成玩家存档保存/退出读回验收。`tools/probe_archive_database.py` 已包含这项字段检查。

本机 `/health` 已返回成功，四张存档表的空结果只读探测均为 HTTP 200，先前 TLS 阻塞已恢复。运行中的服务 `/v1/archive/config` 返回 HTTP 503 / `archive_disabled`。使用现有后端环境并设置 `SURVIVAL_ARCHIVE_HTTP=1` 执行真实 `build_application`，已成功完成扩展初始化及数据库配置同步；配置摘要 `52705dcb84a6c7cf141fbd69144931d4d2dd6fdd490ed1736706ae523d0dc7ca` 与游戏生成配置一致。未修改玩家档案，尚未验收三端保存读回。保留用户现有黑窗口进程；下一步在该窗口 Ctrl+C 后，设置 `$env:SURVIVAL_ARCHIVE_HTTP='1'` 并重新运行 `D:\survival_database\start_fishing_api.ps1`，再检查运行中存档路由。以下 TLS 失败描述为此前记录。

- 存档和地图抽奖 UI 初始化时主动预取全部分类/宝箱；游戏端收到玩家档案后也主动推送。切换已缓存的标签不再请求页面数据，存档原有 0.18 秒人工等待已移除。档案尚未到达时仍等待真实数据，不伪造就绪状态。
- 后续游戏端对每页快照做字段差异比较，仅推送变化；包含基础序号、更新序号和分片信息。客户端按分类独立组装、拒绝旧序号，基础版本不匹配时重新预取恢复。首次加载/重连恢复允许全量，正常切页不触发全量刷新。此处增量指游戏 Lua 到 Panorama；不代表现有 HTTP profile 响应也已改成增量协议。
- 存档复用没有变化的条目面板；两套界面在收取数据后分批预热图标。图片解码与实际首帧表现仍需 Dota 实机验收，不能保证所有机器零卡顿。宝箱访问/奖池详情已读操作仍会提交记录，抽奖和兑换仍需权威操作回执。
- 奖池来自本地 CSV 生成的 Lua 配置；目前没有在线热更新配置下载器。主抽奖仍由游戏 Lua 结算，尚未接入 HTTP 发货事务，不能将此次缓存修改视为抽奖持久化完成。
- 已通过 JS 缓存、存档分片交错、宝箱切换、增量应用及 Lua 存档/HTTP 适配器/在线进度回归；相关 Panorama 脚本和布局已编译。后端 13 项测试通过，使用真实本地 HTTP 和 Lua，但数据库仍是测试替身。
- 实际读取后端环境：`SURVIVAL_ARCHIVE_HTTP` 未启用；没有数据库直连/管理 SQL 凭据。原 API 尝试启动后报 `FISHING_API_STARTUP_ERROR supabase_unavailable` 并退出。对四张存档表进行 `limit=0` 只读探测时，Python 默认代理与直连均报 `SSL: UNEXPECTED_EOF_WHILE_READING`，PowerShell 也无法完成 TLS 连接。因此本次未确认远端迁移状态、未写玩家数据、未完成真实持久化验收。探测工具为 `tools/probe_archive_database.py`，凭据仅从后端环境读取。
- 下一步：先恢复后端到 Supabase 的 HTTPS 连接，然后核对并依次执行 `202609060001_archive_stat_columns.sql`、`202609060002_all_archive.sql`、`202609060003_archive_buildings.sql`；启用扩展，以 HTTP 模式开新局，验证操作前后 revision、重连读回与重复操作不重复发奖。远端 SQL 需通过项目 SQL 管理入口或数据库连接执行，Data API secret 不能代替 SQL 管理权限。

本轮目标是扩展现有 `Dota server Lua → loopback Python → Supabase` 链路，让存档读取及操作统一走权威后端。保持原有账户HMAC、钓鱼奖励和在线checkpoint；不把Panorama或房主电脑等同可信专用服务器，不开放公网监听。

## 先处理的风险

| 风险 | 本轮处理 |
|---|---|
| 双击、超时后实际已提交、进程重启导致重发 | 数据库按账户+操作ID保存命令指纹和回执；相同ID不同内容拒绝，重复操作返回最新档案 |
| 钓鱼、抽奖、签到同时覆盖属性 | 所有永久写入按统一锁顺序锁玩家、属性行；预期revision校验，冲突重新读取并重算，不整档盲覆盖 |
| 随机结果随重试改变 | 后端HMAC种子+命令ID固定随机序列，提交失败重试复用；客户端不传roll/drops |
| CSV分叉 | 生成统一配置包和SHA256；HTTP提交携带摘要，后端只加载启动时固定包；不接收客户端上传CSV覆盖 |
| 本地作弊污染正式档案 | HTTP拒绝测试命令；本地zaixian/yitie/tongguan测试仍可用，远端不得自动降级为本地写档 |
| 多人/多窗口刷在线、掉线补算 | 沿用数据库online checkpoint租约的实际elapsed；新增存档消费持久化checkpoint记录，禁止相信客户端分钟数 |
| 通行证过期、跨日重试 | 时间取数据库，UTC+8；持久化事件时间，按事件时间结算；购买仍只能由可信支付回调授予 |
| 配置/数据版本不兼容 | 显式schema与配置摘要；启动校验，失配停止结算；已提交回执可查询，不重新抽奖 |
| 接口故障/错误被吞 | 结构化错误、有限重试，终止性业务错误出队；连接错误保留待办；失败不扣币 |
| 关闭游戏时内存队列丢失 | 后端收到的命令先持久化；尚未送达的Lua内存事件无法保证跨VM恢复，明确列为实机验收项目 |
| 密钥泄漏 | Supabase secret及pepper只保留Python服务端，日志不输出token/完整档案；保持loopback |

数据库行锁用于阻止并发事务同时覆盖同一行，冲突需重读并重试，参考 [PostgreSQL显式锁文档](https://www.postgresql.org/docs/current/explicit-locking.html)。Supabase secret/service-role会绕过RLS，必须仅用于后端，参考 [Supabase API密钥说明](https://supabase.com/docs/guides/getting-started/api-keys)。

## 实现边界

复用同一份纯Lua存档结算器供游戏本地测试和Python后端调用，避免Python再抄一遍奖励逻辑。Python负责认证、请求字段校验、配置版本、数据库事务及固定随机种子；Lua只接收后端整理的数据，不能读取网络或客户端脚本。服务端运行需要Lua5.1可执行文件。

页面覆盖通关、BOSS、虚空之影、神兵碎片、秘法牢笼、无尽、三类收集抽奖、地图等级、上班福利、签到及每日积分物品。积分道具读取既有content_inventory；钓鱼数量读取成功reward_grants。普通抽奖/真实购买的发货不通过存档UI伪造，支付仍未开放。

正式公网验收仍需确认专用服务器可信身份、HTTPS部署、密钥轮换、进程监督、监控报警、备份恢复、跨机并发及终局断网重试。本轮代码与测试不能替代这些实机验收。

## 文件与部署顺序

1. 先运行 `tools/build_archive_configs.ps1`，然后用Python运行 `tools/build_archive_server_bundle.py`。后者生成 `server/bundles/<sha256>` 不可变结算包和游戏端 `config/generated/archive_http_bundle.lua`。相同摘要包含同一组CSV数据及结算Lua源码；Python启动时核对源码和包摘要，客户端只发送摘要，不上传可执行配置。保留旧摘要目录用于恢复旧版本待办。异机部署须复制完整bundle及current.json，并更新服务端SURVIVAL_ADDON_ROOT指向部署根。
2. `tools/stage_archive_http_server.py` 准备HTTP路由、CSV解析器及原测试修复；`tools/deploy_archive_http_server.ps1` 已将扩展部署到 `D:\survival_database\backend`，原文件备份为 `.before_archive`。扩展默认关闭。
3. 在**原Supabase项目**依次执行 `server/migrations/202609060001_archive_stat_columns.sql` 和 `202609060002_all_archive.sql`。第一份只增加缺失属性列；第二份增加存档状态、权益读取、配置版本、命令回执和在线待办，并扩展原profile。SQL保留已有玩家数值，不把本地测试档案上传覆盖云档。本次远端只读探测返回PGRST202，迁移尚未执行；没有数据库直连或管理SQL凭据，只有Data API secret。
4. 在启动Python的同一终端设置 `$env:SURVIVAL_ARCHIVE_HTTP='1'`，然后运行原 `D:\survival_database\start_fishing_api.ps1`。Lua路径默认 `C:\Program Files\lua\bin\lua5.1.exe`，可用 `ARCHIVE_LUA_PATH` 覆盖。服务启动会同步配置集合，缺表或配置异常会报错退出；配置集合不可同摘要覆盖。
5. 游戏服务器启动新局前设置 `survival_player_profile_provider http_fishing` 与 `survival_archive_http_enabled 1`，沿用原API token。不要在一局内切换本地/HTTP模式。新增档案操作走 `/v1/archive/command`，版本检查走 `/v1/archive/config`。真实在线进度只消费原 `/v1/online-time/checkpoint` 的数据库elapsed，停用本地存档计时提交，钓鱼计时/发奖链路继续使用原逻辑。

新玩家初始化已移除Python“必须38字段”的旧限制，改为CSV字段类型/边界校验；当前93项。数据库初始化函数也改为按CSV字段动态插入，新账号采用当前默认值，旧账号不会重置。新增字段仍需先运行列迁移。

## 事务和故障恢复细节

后端先记录操作ID、命令指纹、当时日期、通行证状态和配置hash；再用共享Lua结算。数据库以当前revision进行CAS提交，按原在线链路的**玩法属性行→玩家行**顺序加锁；只提交属性增量，保留其他写入者的字段变化。发生冲突重新读取，最多重试4次。回包丢失后重复请求只读取既有回执及最新档案，不能重新扣币。相同会话的通关、无尽波次、同一挑战奖励会规范化幂等ID，不能通过更换请求尾部再发一份。

在线checkpoint事务内触发器将已核准elapsed写入待办；服务端重启后profile请求继续消费，所以不会因Python恰好在钓鱼记账后崩溃而丢掉已入库的地图/软妹币时间。通行证加权按该时间段与权益有效期交集计算，软妹币只使用实际elapsed。仅迁移之后的新checkpoint进入存档待办，不回溯不明历史。

尚未完成的普通存档命令在profile请求时重试，按其初始配置版本恢复；需要保留旧bundle文件。每次恢复最多64项，避免单请求无限占用。失败日志与数据库待办应由部署环境监控；尚未送达HTTP的Lua事件仍只在游戏进程内，必须通过实际断网/结束游戏验收决定是否增加独立可靠投递代理。

HTTP测试模式不接受zaixian、yitie、批量tongguan、客户端roll/drops、客户端权益和价格。真实月卡购买仍待支付渠道；存档已有权益表仅供可信后台发货使用，不提供客户端授予接口。主抽奖系统的本地存量content_inventory不会自动迁移到云；积分页能读取云库存和每日签到物品，主抽奖发货事务需单独接入后端，避免把客户端整包库存当权威数据。

## 本轮验证与尚未通过的验收

- 新后端10项测试：真实本地HTTP鉴权/路由、真实Lua结算、模拟数据库并发/回执丢失/重启恢复、玩家隔离、版本不符及伪造参数拒绝。数据库在这些测试中使用内存事务替身。
- 原钓鱼HTTP服务29项回归通过；修复了旧38字段假设和局内钓鱼CSV迁移后的测试路径。
- 游戏Lua存档、在线/作弊、HTTP适配器、属性投影回归与相关Lua语法检查通过。
- 未执行远端迁移，未完成真实Supabase事务与Dota实机三端验收，不标记为生产可用。

迁移后重点验收：两名玩家同时通关/抽奖；断网后重发同一操作；保存成功后主动丢回包；跨零点签到；通行证到期；在线final重复到达；Python重启恢复待办；配置hash故意不一致；大型存档响应体与延迟。正式公开服务前还须补可信专用服务器身份与部署验证。
