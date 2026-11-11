# 隔离测试身份与真实业务压测

这是独立工具，不接入游戏、生产 systemd 或生产认证服务。默认准备 **10万合成注册账号、最多4000个并发身份**；准备成功不代表容量通过。没有真实 Steam 登录、支付、兑换码或真实玩家数据，也不开放新的公网端口。

## 两个入口

- `python -B -m tools.loadtest_lab.cli`：只读源码快照、准备隔离环境、合成数据、启动身份入口及真实 API、两账号事务验证、停止。
- `locust -f tools/loadtest_lab/locustfile.py`：真实 HTTP 流程。依次认证、选择 pure 模式、读取配置/奖池、在线结算；稳定阶段每人约60秒结算一次，每15–30秒执行读档/奖池快照/十连，首次领取测试月卡的零分钟福利。显式重放抽奖及福利请求，校验持久状态与原回执，禁止自动重试结果不明的写请求。

身份入口是仅监听 `127.0.0.1:29567` 的 `POST /_loadtest/identity`，使用本轮独立 controller 密钥。返回 `lt1_` 测试令牌，实际业务仍通过生产 PWA 的 SQLite、会话绑定、代理校验及限流代码；真实后端和 PostgreSQL/Lua 结算源码保持原字节。`lt1_` 无法用于正常生产认证库。身份还绑定账号、局、期限及本轮数据库证明。

## 运行前提

使用独立 Linux 测试机，有 Docker Compose、PostgreSQL 17 镜像、Python 3.11+、Lua 5.1。不要求购买 PTS，可用自己的电脑运行 Locust。压测发生器尽量与业务测试机分开。Windows 只负责准备文件和运行发生器，数据库使用 Linux 主机网络，不能直接把该 compose 当作 Docker Desktop 配置使用。

独立虚拟环境安装 `requirements.txt`，不要复用签包/支付虚拟环境。固定并保存实际依赖版本与镜像 digest；镜像获取、机器租用和实际负载启动是独立操作。真实4000容量测试使用 `purpose=capacity`，发现常用生产端口即拒绝启动；`functional-smoke` 只允许最多10注册/5活跃、最长180秒及150个前端请求，用于小规模事务验证。

## 准备（项目 Windows 工作目录）

运行工具必须先提交，`prepare` 只导出不可变 Git HEAD 的操作者及 PWA/CSV，与工作区工具不一致会拒绝。源码快照只导出当前后端代码、公开配置及数据库结构，不复制表数据或生产环境变量。

```powershell
python -X utf8 -B -m tools.loadtest_lab.cli snapshot --directory D:/Survival_本地工具/runs/loadtest_source_NEW
python -X utf8 -B -m tools.loadtest_lab.cli prepare --source-receipt D:/Survival_本地工具/runs/loadtest_source_NEW/source_snapshot_receipt.json --directory D:/Survival_本地工具/runs/loadtest_NEW
```

小规模验证在 prepare 后添加 `--purpose functional-smoke`，默认2注册/2活跃、120秒。每次使用独立空目录，失败文件和旧回执保留，不覆盖重用。`private.json`、`compose.yaml`、初始化SQL含测试密钥；整个目录按私密资料传输、只授予操作者权限，不进 Git。发生器只需要 `client.json` 与提交的工具包，**不需要数据库密码或 private.json**。

## 测试机（将完整目录安全复制到独立 Linux 目录）

```bash
cd /srv/survival-loadtest/NEW
chmod 700 .
chmod 600 private.json client.json compose.yaml
chmod 755 database
chmod 644 database/*.sql
docker compose up -d database
# 等数据库初始化完成；只初始化新 cluster，不复用现有数据目录
/path/to/test-venv/bin/python -B run_lab.py seed --directory "$PWD"
/path/to/test-venv/bin/python -B run_lab.py serve --directory "$PWD"
```

serve 在前台运行，到期自动关闭 API。数据库监听回环25432，业务后端29565、认证代理29567；启动/种数前先验证真实数据库地址、库名、随机标记及清单摘要。服务账号由独立 cluster 创建，生产密码不参与。种数1000行一批，只有前 active 个合成账号有测试抽奖券/月卡；不生成订单。

新终端可运行两账号验证（会修改合成账号并占用两个一次性身份，因此正式容量测试应另建新环境）：

```bash
/path/to/test-venv/bin/python -B run_lab.py smoke --directory "$PWD" --stop-lab
```

## 电脑启动 Locust

先用可信 SSH 主机指纹建立回环转发，不关闭指纹检查：`ssh -N -L 127.0.0.1:29567:127.0.0.1:29567 测试机`。只允许固定目标 `http://127.0.0.1:29567`，拒绝重定向；每个虚拟用户先校验带本轮随机挑战签名的环境证明，再申请独立身份。

```powershell
$env:LOADTEST_CLIENT='D:/Survival_本地工具/runs/loadtest_NEW/client.json'
locust -f tools/loadtest_lab/locustfile.py --headless --host http://127.0.0.1:29567 --users 20 --spawn-rate 2 --run-time 5m --stop-timeout 45 --csv D:/Survival_本地工具/runs/loadtest_NEW/load20 --html D:/Survival_本地工具/runs/loadtest_NEW/load20.html
```

先20，再100、500、1000、4000；每轮新建环境和输出目录。4000建议每秒增加10–20人，稳态至少30分钟，并同时采集测试机CPU、内存、磁盘延迟、PostgreSQL连接/锁等待、业务错误及发生器CPU/网络。先确认发生器没有成为瓶颈，再决定多进程/多机 Locust；服务统一分配账号，worker不会撞号。关闭只停止本轮监听服务；数据库用 `docker compose stop database`，保留数据及证据，不自动删除。

脚本连续两个5秒窗口、每窗至少100请求且错误率超过5%会停止；任何业务/不变量错误导致非零退出。中止或网络断开可能留下未完成请求，检查 stopped 回执中的 remaining_http_requests 和业务状态后再判断，不能自动重放写操作。

## 容量判断与限制

默认保留现有 HTTP=8、DB=4、PWA=24、全局2400次/分钟（40 RPS）限制。4000人每分钟结算已经需要约66.7 RPS，**现有限流本身就无法达到目标**。这套工具用于测出问题，不能把拒绝请求当作服务达标。调整 prepare 的 `--http-concurrency / --db-concurrency / --web-concurrency / --global-http-per-minute` 会明确标记为参数实验，不修改生产配置。

当前路径覆盖存档/抽奖/福利/在线结算，未覆盖真实 Steam 往返、支付网关、公网 nginx 单IP限流、游戏帧率及其他玩法写入。回环转发会绕过公网代理；4000人容量结论必须结合拟上线配置、真实用户操作分布和完整链路再验收。SQLite 仍保留生产全局锁与清理工作，结果会暴露这部分成本。库中10万注册记录也不等同于10万个长期重度存档，应另行准备合成存档体积实验。

## 成本与证据

账号区间初始化O(1)，查询/分配/重试/释放O(1)，已发身份内存O(数量)，最多10万；无按人数扫描的刷新。种数O(N)，每批1000行、内存O(1000)，每批约3次SQL写入加1次COPY；初始化种数单独计时，不算稳定业务吞吐。每个虚拟用户O(1)状态；首次8个HTTP（环境证明、身份、认证、登录、配置、奖池、结算、ready），稳定通常一次操作1个HTTP；有重放校验的写操作额外3个HTTP；收尾结算/释放2个HTTP。统计监控每5秒读累计计数O(1)，就绪时长按状态变更累计，无全账号轮询。

保留 source_snapshot、prepare、seed、started、smoke、stopped 回执、Locust CSV/HTML及系统监控；回执明确 `capacity_certified=false`，程序不自动宣布通过。Windows prepare/snapshot/smoke 自动调用存储登记；Linux回执显示待导入。远程产物收回树外目录后，建立注明远程原路径、原回执SHA256及本地artifact_root的真实采集回执，再执行：

```powershell
python -X utf8 -B tools/release_storage_ledger.py record --receipt D:/Survival_本地工具/runs/NEW/collection_receipt.json
```

登记失败须保留回执并处理；不触发全盘扫描或自动清理。任何私密令牌、账号原始会话和数据库密码均不写进知识库、Git或公开报告。
