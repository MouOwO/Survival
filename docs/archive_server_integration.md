# 全存档 HTTP 联调方案

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
