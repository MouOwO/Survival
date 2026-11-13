# 隔离测试身份与真实业务压测

这是独立工具，不接入游戏、生产 systemd 或生产认证服务。默认准备 **10万合成注册账号、最多4000个并发身份**；准备成功不代表容量通过。没有真实 Steam 登录、支付、兑换码或真实玩家数据，也不开放新的公网端口。

## 两个入口

- `python -B -m tools.loadtest_lab.cli`：只读源码快照、准备隔离环境、合成数据、启动身份入口及真实 API、两账号事务验证、停止。
- `locust -f tools/loadtest_lab/locustfile.py`：真实 HTTP 流程。依次认证、选择 pure 模式、读取配置/奖池、在线结算；稳定阶段每人约60秒结算一次，每15–30秒执行读档/奖池快照/十连，首次领取测试月卡的零分钟福利。显式重放抽奖及福利请求，校验持久状态与原回执，禁止自动重试结果不明的写请求。

2026-11-13更新：默认精确协商当前`X-Survival-Wire`，使用生产有界数字回包解码，并还原同回包的profile refs v1/v2；控制路由不加协商头。保留`--wire-mode legacy-json`作无数字编码对照，抽奖的已提交profile能力保持相同。报告分别记录压缩/原文回退、正文实收字节和客户端解码时间。Locust的HTTP耗时不含本地解码；小规模smoke的整次调用耗时包含解码，二者不可直接混为同一计时。

稳定操作加入奖池MD5命中和单波无尽结算，抽样权重依次为读档45%、奖池快照20%、目录10%、无尽15%、十连10%；首次福利另计，1%显式重放；抽奖5%重放。smoke另做32波批次、显式幂等重放以及冷/热目录验证。无尽是实际SQL/Lua结算意图，不模拟战斗或伪造波次耗时；单局最多1000波，不循环复用命令ID，未知或部分回执拒绝继续提交。

身份入口是仅监听 `127.0.0.1:29567` 的 `POST /_loadtest/identity`，使用本轮独立 controller 密钥。返回 `lt1_` 测试令牌，实际业务仍通过生产 PWA 的 SQLite、会话绑定、代理校验及限流代码；默认 `--backend-db-pool baseline` 保留后端和 PostgreSQL/Lua 结算源码原字节。`lt1_` 无法用于正常生产认证库。身份还绑定账号、局、期限及本轮数据库证明。

## 运行前提

使用独立 Linux 测试机，有 Docker Compose、PostgreSQL 17 镜像、Python 3.11+、与待测后台一致的 Lua。不要求购买 PTS，可用自己的电脑运行 Locust。压测发生器尽量与业务测试机分开。Windows 只负责准备文件和运行发生器，数据库使用 Linux 主机网络，不能直接把该 compose 当作 Docker Desktop 配置使用。

独立虚拟环境安装 `requirements.txt`，不要复用签包/支付虚拟环境。固定并保存实际依赖版本与镜像 digest；镜像获取、机器租用和实际负载启动是独立操作。真实4000容量测试使用 `purpose=capacity`，发现常用生产端口即拒绝启动；`functional-smoke` 只允许最多10注册/5活跃、最长180秒及150个前端请求，用于小规模事务验证。

默认同机PG预算改为2GiB/1CPU，functional-smoke保持256MiB/0.5CPU，避免旧8GiB/4CPU配方占满上海4核8GiB机器。可显式设置`--database-memory-mib`和`--database-cpu-limit`；capacity启动检查PG声明不超过主机60%内存/50%逻辑CPU。实际容器Memory/CPU、镜像digest须另行inspect核对，回执中的requested不是已生效证明。该拓扑明确为`same_host_database_diagnostic`，不能外推独立RDS性能；现有固定回环DB门禁仍不支持RDS，不能改地址常量绕过。

40人集中退出修复实验增加两个显式开关，均只允许新建的`bounded-v2`隔离候选：`--checkpoint-observation`增加结算/代理分段观测；`--http-admission bounded-v1`使用已审阅的HTTP32、web48、DB4、等待28、排队2秒组合（其余参数必须显式匹配），两层backlog64、后台accept等待最多2秒。准备顺序固定为pool-v2→观测→接入；各层分别绑定已提交operator、所有父/子摘要，启动逆向核对重叠文件，拒绝错序、漏文件或混合来源。旧候选及默认baseline/v1/v2配置保持原有来源。

观测记录只含固定类别、次数、状态、字节数和分段耗时，不含账号、会话、SQL及凭据；同进程backend与代理合计最多60条/分钟、300条/24小时、每条4096字节，为最终结算预留份额。采样分布不能代替Locust全量时延。准备和启动是一次O(源码字节数)验证；稳定请求只做固定map/计数/时钟操作，接入存储为O(并发槽+固定backlog)，无玩家集合扫描、无限队列或未知写重试。启动/停服回执分别记录实际接入参数、计数与诊断预算；更高阶梯须重新审查接入预算和完整清理，不能凭新增开关宣称容量通过。

正式比较应填写`--postgres-image docker.io/library/postgres@sha256:<真实摘要>`或`public.ecr.aws/docker/library/postgres@sha256:<真实摘要>`，匹配拟上线PG版本及镜像。显式参数仅允许这两个官方仓库的固定摘要；省略时保留`postgres:17`兼容，运行前仍须记录实际镜像。不要为下载方便改用无法核验来源的镜像。

## 准备（项目 Windows 工作目录）

运行工具必须先提交，`prepare` 只导出不可变 Git HEAD 的操作者及 PWA/CSV，与工作区工具不一致会拒绝。源码快照只导出当前后端代码、公开配置及数据库结构，不复制表数据或生产环境变量。

```powershell
python -X utf8 -B -m tools.loadtest_lab.cli snapshot --directory D:/Survival_本地工具/runs/loadtest_source_NEW
python -X utf8 -B -m tools.loadtest_lab.cli prepare --source-receipt D:/Survival_本地工具/runs/loadtest_source_NEW/source_snapshot_receipt.json --directory D:/Survival_本地工具/runs/loadtest_NEW
```

小规模验证在 prepare 后添加 `--purpose functional-smoke`，默认2注册/2活跃、120秒。每次使用独立空目录，失败文件和旧回执保留，不覆盖重用。`private.json`、`compose.yaml`、初始化SQL含测试密钥；整个目录按私密资料传输、只授予操作者权限，不进 Git。发生器只需要 `client.json` 与提交的工具包，**不需要数据库密码或 private.json**。

`--lottery-catalog-md5 <32位MD5>`仅填写由相同公开配置实际验证的客户端本地目录摘要。未提供时首次启动明确为冷加载；客户端只保留摘要，后续传MD5命中，不保存每用户整份目录。冷启动、带本地种子的命中及强制错版本分别测试，禁止把全员下载目录当作已验证本地命中。

连接池对照可显式添加 `--backend-db-pool bounded-v1 --db-concurrency 4`。这只给新隔离目录应用经过精确父源码摘要和 AST 检查的连接复用/限时排队/错误分类候选；Git 中的两个 overlay 和 helper 必须与同一个 HEAD 一致。回执绑定原始快照、操作器提交、变更前后 transport 摘要及 helper，不改旧快照或正式后台。当前候选固定每进程4连接、最多4个等待者、排队最多2秒且受整个HTTP请求剩余期限约束；不自动重放结果不明的写入。baseline 不应用 overlay。其他HTTP/PG CPU/内存/前端限流参数应保持相同，先比较软件变化，再另做参数实验。

联动参数实验使用 `--backend-db-pool bounded-v2`，省略并发选项时采用 DB=4、HTTP=24、PWA=24、等待队列20、等待上限2秒。新增独立v2来源补丁，保留v1补丁及helper原字节；通过构造参数传入队列与等待预算。可显式设置 `--db-pool-max-waiters`（0–32）及 `--db-pool-wait-seconds`（大于0且不超过5）；HTTP必须不超过DB连接数加等待队列，DB连接数保持4。requested/effective参数、实际池预算及运行计数写入清单和started/stopped回执，实际构造预算不符即拒绝就绪。baseline/v1省略HTTP选项仍为8，其历史清单继续可验证。v2改变了HTTP/排队准入，应与v1分组报告，不能将差异全部归因于连接复用，也不能据此宣布4000人容量通过。

v2普通后台入口的默认值仍为4个等待者，当前仅隔离lab显式传入20；正式服务的配置接线和部署尚未完成。隔离lab也没有生产systemd的TasksMax限制，当前正式单位的64任务上限须连同HTTP线程、每连接deadline Timer和Lua子进程另行核算；两层服务在lab与正式环境的进程布局不同，不能直接照搬HTTP=24认定正式资源预算已通过。

## 测试机（将完整目录安全复制到独立 Linux 目录）

```bash
cd /srv/survival-loadtest/NEW
chmod 700 .
chmod 600 private.json client.json compose.yaml
chmod 755 database
chmod 644 database/*.sql
docker compose up -d database
# 等数据库初始化完成；只初始化新 cluster，不复用现有数据目录
/path/to/test-venv/bin/python -B run_lab.py seed --directory "$PWD" --analyze-after-seed
/path/to/test-venv/bin/python -B run_lab.py serve --directory "$PWD"
```

serve 在前台运行，到期自动关闭 API。数据库监听回环25432，业务后端29565、认证代理29567；启动/种数前先验证真实数据库地址、库名、随机标记及清单摘要。服务账号由独立 cluster 创建，生产密码不参与。种数1000行一批，只有前 active 个合成账号有测试抽奖券/月卡；不生成订单。

`seed --analyze-after-seed` 在本轮合成数据库批量导入后显式执行一次 `ANALYZE`，成功与真实耗时写入 seed 回执。两个对照组均须开启，再执行相同预热；省略开关保留原种数行为，不补改旧实验。统计更新是一轮初始化工作，不在请求或定时刷新中扫描。started/stopped 回执分别保留候选池的固定数字统计；停服先停止前端接入、有限等待两层已接受的HTTP请求全部退出，确认后才关闭连接池。45秒内未排空会保留未完成状态并返回非零，不能将“已停止监听”解释成所有写入完成。

启动前检测 `lua5.1` 或 `lua` 的实际版本，并用真实不可变配置执行奖池目录预检；started 回执登记版本和可执行文件摘要。若不在 PATH，可在 serve 添加 `--lua-executable /absolute/path/to/lua`。默认只接受 Lua 5.1–5.4；正式容量比较应使用与待测后台相同的版本及构建，不用本地可执行文件替代服务器版本作结论。

新终端可运行两账号验证（会修改合成账号并占用两个一次性身份，因此正式容量测试应另建新环境）：

```bash
/path/to/test-venv/bin/python -B run_lab.py smoke --directory "$PWD" --stop-lab
```

容量实验在测试机另开一个终端采集只读聚合监控：

```bash
/path/to/test-venv/bin/python -B run_lab.py monitor --directory "$PWD" --duration 600 --interval 5
```

每5秒读取固定系统计数及两条PG聚合查询，不读取账号行、SQL文本、认证或进程参数。连接限定本轮随机标记的回环测试库，并强制只读；停止回执出现后退出。JSONL记录实际采样耗时、CPU/iowait/steal、内存、所在磁盘计数和默认网卡字节、PG连接/等待/事务/临时文件等。网卡包含私网流量，不是云账单公网计量；PG时间指标依赖原有track_io_timing，本工具不改数据库参数。有缺口的监控返回非零退出并保留回执，不能把缺失当零。

## 电脑启动 Locust

先用可信 SSH 主机指纹建立回环转发，不关闭指纹检查：`ssh -N -L 127.0.0.1:29567:127.0.0.1:29567 测试机`。只允许固定目标 `http://127.0.0.1:29567`，拒绝重定向；每个虚拟用户先校验带本轮随机挑战签名的环境证明，再申请独立身份。

```powershell
$env:LOADTEST_CLIENT='D:/Survival_本地工具/runs/loadtest_NEW/client.json'
$env:LOADTEST_REPORT_DIRECTORY='D:/Survival_本地工具/runs/loadtest_NEW'
locust -f tools/loadtest_lab/locustfile.py --headless --host http://127.0.0.1:29567 --users 20 --spawn-rate 2 --run-time 5m --stop-timeout 45 --csv D:/Survival_本地工具/runs/loadtest_NEW/load20 --html D:/Survival_本地工具/runs/loadtest_NEW/load20.html
```

先20、40，再100、200、500、1000、2000、4000；每轮新建环境和输出目录。40人诊断先保持每4秒增加1人、满员至少10分钟，并把集中退出单列；当前40人的退出结算与延迟尚未通过，不自动进入100。4000建议每秒增加10–20人，ready稳态至少60分钟，通过后另建一轮4小时长稳，并同时采集测试机CPU、内存、磁盘延迟、PostgreSQL连接/锁等待、业务错误及发生器CPU/网络。先确认发生器没有成为瓶颈，再决定多进程/多机 Locust；服务统一分配账号，worker不会撞号。Windows不支持Locust的`--processes`自动fork，应使用显式master/worker；主从final未收齐会非零退出。关闭只停止本轮监听服务；数据库用 `docker compose stop database`，保留数据及证据，不自动删除。

认证、登录、活动或不变量出现非预期失败时，立即停止整轮并阻止申请替换身份；分布式由master通知所有worker停止，避免失败后自动补人形成启动风暴。未确认登录的身份清理只释放；已登录会话仍尝试最终结算并释放。另保留两次5秒窗口的错误率守护。HTTP失败标签只保留状态及经过严格筛选的业务代码，不记录响应正文、令牌或账号。中止或网络断开可能留下未完成请求，检查 stopped 回执中的 remaining_http_requests 和业务状态后再判断，不能自动重放写操作。

Locust 的周期 CSV 可能停在用户退出前；`locust_final_*_receipt.json` 在正常 quitting 时保存包含用户收尾的最终统计，分布式只由 master 写一份。请将它与 stopped 回执一起核对，不凭周期 CSV 的最后一行判断收尾成功。报告目录必须是已存在的树外目录；不设置时使用 client.json 所在目录。

在线结算分别使用 `[checkpoint:setup]`、`[checkpoint:periodic]`、`[checkpoint:final]` 统计名，区分入局、正常在线和退出时延。这只影响本地统计，不改变请求路径、正文、幂等请求ID或服务端处理；不得将集中退出的结果冒称常规稳态表现。

合成 `lt1_` 身份统一到“本轮启动时间＋已校验的运行预算＋120秒收尾余量”过期；配置足够运行预算（上限18000秒）后可覆盖入场后四小时长稳，新业务仍在原单调时钟期限停止。没有续签、换号或未知写重试，生产四小时授权规则与生产对 `lt1_` 的拒绝保持。4小时边界由模拟时钟回归覆盖，不等同已经实际执行4小时压测，也不覆盖真实Steam授权续期。时钟偏差超过60秒（仅容许1微秒表示精度）或单调时钟回退会使本轮持续失效，计时保守截到最后验证时刻。

控制器可读取 `GET /_loadtest/status?nonce=<32位小写hex>`，必须单个控制器Authorization。响应使用独立kind、run、manifest、nonce及HMAC固定签名；调用方缓存清单摘要一次，用 `loadtest_lab.status.decode_status()` 验证16KiB上限、重复键、字段和签名。状态读取为固定字段O(1)，不扫描身份集合或查询DB；新增请求计入API总请求和 `status_requests`，外部观察不能混入Locust业务统计。状态保留原始未释放数，并分别提供有效已确认ready、当前/最长连续满员及起止时间。关服开始时冻结测量，已受理请求仍可在原业务期限内完成；排空时间不增加有效ready时长。

ready表示已确认且仍有效的合成租约能力，不是客户端心跳。容量判断必须结合停止前的签名状态、发生器实际运行窗口、到达率及完成率；不能单靠stopped累计/最长秒数认定稳定负载。当前仍需人工逐级设置和审查，没有自动放行到4000的一键控制器。 Locust的run-time包含入场，满员4小时需另加200–400秒入场和准备/收尾余量；只填写4h不能证明满员4小时。服务实际剩余预算也必须覆盖整段负载与收尾。

## 容量判断与限制

默认保留现有 HTTP=8、DB=4、PWA=24、全局2400次/分钟（40 RPS）限制。4000人每分钟结算已经需要约66.7 RPS，**现有限流本身就无法达到目标**。这套工具用于测出问题，不能把拒绝请求当作服务达标。调整 prepare 的 `--http-concurrency / --db-concurrency / --web-concurrency / --global-http-per-minute` 会明确标记为参数实验，不修改生产配置。

当前路径覆盖存档/抽奖/福利/在线结算，未覆盖真实 Steam 往返、支付网关、公网 nginx 单IP限流、游戏帧率及其他玩法写入。回环转发会绕过公网代理；4000人容量结论必须结合拟上线配置、真实用户操作分布和完整链路再验收。SQLite 仍保留生产全局锁与清理工作，结果会暴露这部分成本。库中10万注册记录也不等同于10万个长期重度存档，应另行准备合成存档体积实验。

这些仍是分步CLI，不是已完成的一键阶梯/完整公网链路容量验收。隔离环境的连接池候选不代表正式后台已部署；SQLite串行热点和正式准入也仍须独立处理。上海当前7Mbps上限下只能得到受该出口约束的结果；调高峰值、数据库分离与软件参数变化必须分别记录，不能把不同环境的数字混作同一组对照。

## 成本与证据

账号区间初始化O(1)，查询/分配/重试/释放O(1)，已发身份内存O(数量)，最多10万；无按人数扫描的刷新。种数O(N)，每批1000行、内存O(1000)，每批约3次SQL写入加1次COPY；初始化种数单独计时，不算稳定业务吞吐。每个虚拟用户O(1)状态；首次8个HTTP（环境证明、身份、认证、登录、配置、奖池、结算、ready），稳定通常一次操作1个HTTP；有重放校验的写操作额外3个HTTP；收尾结算/释放2个HTTP。统计监控每5秒读累计计数O(1)，就绪时长按状态变更累计，无全账号轮询。

保留 source_snapshot、prepare、seed、started、smoke、stopped 回执、Locust CSV/HTML及系统监控；回执明确 `capacity_certified=false`，程序不自动宣布通过。Windows prepare/snapshot/smoke 自动调用存储登记；Linux回执显示待导入。远程产物收回树外目录后，建立注明远程原路径、原回执SHA256及本地artifact_root的真实采集回执，再执行：

```powershell
python -X utf8 -B tools/release_storage_ledger.py record --receipt D:/Survival_本地工具/runs/NEW/collection_receipt.json
```

登记失败须保留回执并处理；不触发全盘扫描或自动清理。任何私密令牌、账号原始会话和数据库密码均不写进知识库、Git或公开报告。
