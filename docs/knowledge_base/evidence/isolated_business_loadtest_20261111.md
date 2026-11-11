# 专用测试身份与真实业务压测工具（2026-11-11）

仅本地工具更新；代码已提交推送。生产后台未部署、未变更权限或限流、未重启，客户端及游廊无本轮运行改动。没有购买资源、消耗真实券、调用 Steam/支付或运行4000人压力。隔离功能验证使用原服务器上的全新独立数据库容器（256MiB、0.5核），完成后停止；这不构成容量评估。

用户要求实现“专用测试身份入口”和“真实业务压测脚本”，承接[4000同时在线／10万注册评估](capacity_4000_20261111.md)。入口及完整运行步骤见 [tools/loadtest_lab/README.md](../../../tools/loadtest_lab/README.md)。它们属于运维工具，不加入客户端发行包。

## 实现与边界

- `cli.py` snapshot/prepare/seed/serve/smoke/stop；snapshot通过既有固定指纹SSH只读导出后台Python/Lua、公开结算包与数据库结构，不复制生产表数据或环境凭据。prepare固定已提交操作者、PWA及CSV来源，生成独立空目录和随机密钥。
- `identity.py` 单独controller授权、`lt1_`令牌，复用真实PWA SQLite、principal账号/局绑定、代理与限流。生产PWA令牌解析和数据库均不接受该身份；不修改生产认证路由。100000身份为惰性区间，服务集中分配，worker不撞号。
- `runtime.py` 真实 fishing_api / archive_backend、真实PostgreSQL RPC与Lua reducer；启动与种数先核验回环25432、固定测试库名、随机数据库标记及清单SHA256。HTTP仅回环29565/29567。禁止Steam、支付、兑换路由。capacity模式发现现有生产端口即拒绝，功能验证最多10注册/5活跃/180秒/150请求。
- `workload.py` 认证→pure模式登录→配置/奖池→每60秒在线结算；每15–30秒读档、奖池快照或地图十连，首次领取合成月卡零分钟福利。写入不自动重试；显式复用相同请求探测幂等，检查回执和持久状态。月卡、券仅隔离数据库种入，不创建支付订单或伪造在线时长。
- `locustfile.py` 固定回环SSH目标、签名环境挑战、禁重定向、失败退出、错误率监控、退出最终统计。生产默认HTTP8/DB4/PWA24和2400次/分钟保留；显式改变参数另标实验，不改生产配置。

## 实际验证

全部测试/日志在树外 `D:/Survival_本地工具/runs/loadtest_implementation_20261111_160503`。独立测试虚拟环境实际安装 Locust 2.47.0、psycopg 3.3.8，版本表 `dependency_versions.txt`；未更改签包/支付虚拟环境。服务器Python使用既有依赖，冻结业务源码74个文件，SQL只含结构。

| 验证 | 真实结果 | 限制 |
| --- | --- | --- |
| `test_lab_boundaries.py` | 12项通过；含真实SQLite、HTTP入口、越权/过期/预算/标记/签名/源码篡改负例；十万身份lookup禁止迭代仍通过 | DB拒绝路径部分用mock；不冒充真实事务 |
| `smoke_lab_06` / `4871d433d702856ac9f509b6cc0b606f` | 真实PG＋HTTP＋Lua，33请求、十连10次、两种写入各重放一次、只扣10券、另一账号不变；cleanup_failures=0 | 2合成账号，不是压力或稳定性测试 |
| `locust_lab_07` / `cbe7ff54ccf706501eeb2a2032042e90` | 2用户20秒，退出0；最终控制台28请求0失败；服务含停止证明/停止命令合计30请求，峰值ready=2、ready目标时长17.550秒，退出active=0/inflight=0 | 周期CSV仅24请求，遗漏on_stop最后4请求，因此新增quitting最终回执 |
| `locust_lab_08` / `bbceaf048a9c317a4c164413497332c3` | 2用户20秒，退出0；最终quitting回执28请求0失败，包含最后4次收尾；服务含停止控制合计30请求，ready峰值2、目标时长17.604秒，退出active=0/inflight=0；容器已停止 | 不对4000人作结论 |

真正跑通前，隔离验证暴露并修正：SQL结构授权依赖的NOLOGIN角色缺失；镜像postgres用户读取初始化SQL的权限；`inet_server_addr()::text`返回`127.0.0.1/32`导致地址误拒绝（改`host()`）；新库默认PUBLIC TEMP权限不符合真实运行角色检查；Lua入口文件遗漏，以及服务器实际可执行文件为`/usr/bin/lua`（Lua 5.3），不是`lua5.1`。现在启动先做真实公开目录投影，并记录二进制摘要 `99d86376effb9163db8f37f75f79e65aaa23a5a954547867176d5b701ce774d3`。保留失败回执，不把失败改写为通过。

冻结后台来源为 `/opt/goufayu-ws4/releases/20261111-ws4-lottery-rates-e487206a31dc/backend`，公开配置摘要 `98761e2a9386174e696fada8efdc2fc6891365dc661215b576b5f90f02fc8fac`，数据库结构SHA256 `acb0d31f1e13eafabb014c18e8e0cb1229cbabeb7a602507bd8d23b8e90a2cbf`。这是取样当时的独立冻结基线；其他窗口后续发布配置，不自动改变本轮取样。新一轮容量测试应重新snapshot，核验拟上线配置。

## 成本、证据与待办

新增身份区间初始化/查询O(1)，分配/重试/释放均摊O(1)，内存O(已发身份)、上限10万；无刷新扫描。种数O(N)、1000行COPY批次、内存O(1000)，每批3次INSERT；已有SQL触发器的内部成本仍真实执行。每个玩家O(1)状态；入局8个HTTP、一般操作1个、有幂等校验的写操作4个、收尾2个；状态ready时长只在变化时累计。5秒监控只读总计数O(1)，最终汇总仅退出时O(固定路由数)。真实PWA已有SQLite锁/清理成本保持，未声称将生产成本降为O(1)。没有原生调用/FPS测试。

源码/prepare回执已即时登记；远程回执原字节及SHA256通过本地collection回执登记，Linux原路径保留、不伪造生成日期。原服务器 `/root/survival_loadtest_lab/<run_id>` 的新测试数据、停止容器和失败证据保留，无自动删除。不会停止或删除生产容器。测试令牌、client/private.json、数据库密码和原始认证数据不入Git/知识库。

最终工具来源 game `946f646d84b685448237f5b41b98b316596ce0d1`（dev）；完整功能回归运行核心与该版一致，后一次Locust验证了新增quitting统计。8份远程采集回执均已登记；总采集回执 `implementation_collection_receipt.json` 的存储登记ID `96e35d420ac766895eecc0c9fe62813742437fc826121ba526dc1f9f389b9718`，摘要 `1906698bb7305cbaa340608d592a95184a2c21f130ccd5e94c503628f07a80c6`。content同步基线 `35b12be1f6174c27b700dd5297025228f96fbc3a/master`，本轮无内容源码改动，音乐改动留原窗口。

待真正容量测试：独立机器准备10万合成注册记录（本轮实际只种2账号），确认典型存档体积及用户行为；先20/100/500/1000再4000并监控CPU、内存、磁盘/锁等待和发生器；当前40RPS全局限流连4000人每分钟结算所需66.7RPS都不够，必须将参数实验与生产改造分别验收。真实Steam登录、公网nginx/单IP限制、支付、游戏帧率和其他玩法尚未覆盖。所有回执`capacity_certified=false`，不据两账号或短测承诺4000在线。

其他窗口的UI/背景音乐、Steam登录修复、发行工具、current.json及缓存改动均保留；本轮仅提交loadtest工具和本证据。content侧没有本轮工具改动，不造空提交，仍执行同步核对。
