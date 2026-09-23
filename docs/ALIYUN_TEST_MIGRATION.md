# 阿里云测试后端迁移手册

**当前状态：ECS 测试后端 `20260920-test05` 已部署，新版存档、抽奖及重启持久化已验收，详见第 13 节。** 当前游戏和后端结算包哈希一致，但真实游戏客户端联调尚未完成。数据库为 23 项迁移/加固记录、12 个应用 RPC；支付仍为 `PAYMENT_MODE=test`，Supabase 原环境未修改。旧 test03 不能直接接入已升级数据库，回退边界见[新版兼容性检查](ALIYUN_UPSTREAM_COMPATIBILITY.md)。第 10～12 节为历史记录。

## 1. 固定边界与目录

| 项目 | 约定 |
|---|---|
| ECS | `47.110.238.248`；先经阿里云控制台核验机器与 SSH 指纹 |
| 现有数据库 | 保留 `goufayu-db`、`goufayu-db.service`、PostgreSQL 17.11、`127.0.0.1:5432` 和 `goufayu_test` |
| 数据目录 | 不执行任何 `/data/postgres17` 初始化、删除、迁移或重新挂载 |
| 应用 | 宿主机 Python 3.11、独立 `.venv`、非 root 用户 `goufayu`、`127.0.0.1:8765` |
| 发布目录 | `/opt/goufayu/releases/<release-id>`；`/opt/goufayu/releases/current` 是原子切换的符号链接 |
| 配置 | `/etc/goufayu`，服务使用 `api.env`；秘密不进入 Git、发布包、命令参数或日志 |
| 日志 | `/var/log/goufayu/api.log`，root:goufayu `0660`；目录 root:goufayu `0750`、服务用户不能替换文件。按天/20 MiB 轮转，保留 14 份；`copytruncate` 的瞬时少量丢日志窗口可接受于测试服 |
| 备份 | `/var/backups/goufayu` 私有目录；独立异地 restic 仓库另配，未配置时备份服务明确失败并保留本机导出 |
| 水平限制 | 不改原游戏 URL、CSV 默认、正式玩法与支付接入；Nginx HTTPS 模板不会自动启用 |

发布包至少包含：

```text
<release-id>/
  requirements.txt
  backend/run_fishing_api.py
  backend/fishing_api/       # PostgreSQL 适配后的服务，不是原 Supabase-only 版本
  backend/archive_backend/  # Python 扩展
  addon/data/csv/玩家档案系统/{star_blessing_reward_definitions,fishing_system_rules,player_gameplay_stats}.csv
  addon/server/bundles/current.json
  addon/server/bundles/<hash>/{bundle.json,worker.lua,core/*.lua,systems/*.lua}
  database/{dbtool.py,init_roles.sql,harden.sql,migration_manifest.json,migrations/...}
  deploy/                   # 本手册对应工具和 unit 模板
```

旧的历史 bundle 必须一起保存：数据库中未完成的操作按旧 `config_hash` 重放。只留当前 bundle 会令旧操作无法续办。客户端生成的 `archive_http_bundle.lua` 与当前服务包哈希也须一致。

## 2. 先建立专用 SSH 密钥，不上传私钥

### 本地电脑操作

以下 PowerShell 命令在自己的 Windows 电脑执行，首次应设置密钥口令。若这个专用文件名已存在，先核对用途，不覆盖旧密钥：

```powershell
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE/.ssh" | Out-Null
ssh-keygen -t ed25519 -a 100 -f "$env:USERPROFILE/.ssh/goufayu_ecs_ed25519" -C "goufayu-ecs-admin"
Get-Content -LiteralPath "$env:USERPROFILE/.ssh/goufayu_ecs_ed25519.pub" | Set-Clipboard
```

### 服务器操作（阿里云控制台终端）

在阿里云控制台的终端中，把上一步复制到剪贴板的 **`.pub` 公钥** 加入目标机器 `/root/.ssh/authorized_keys`，目录权限 `0700`、文件 `0600`。私钥只留在本机；不粘贴到对话、工单、ECS 或源码。不要在验证新密钥登录前关闭原有恢复入口。

```sh
install -d -m 0700 /root/.ssh
touch /root/.ssh/authorized_keys
chmod 0600 /root/.ssh/authorized_keys
cat >> /root/.ssh/authorized_keys
# 粘贴完整一行公钥，Enter 后 Ctrl+D 结束追加；保留文件中的已有公钥。
```

控制台终端读取服务器公钥指纹：

```sh
ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
```

### 回到本地电脑连接

本机扫描到临时文件，核对 SHA256 指纹确实与控制台一致，再追加到 `known_hosts`。`ssh-keyscan` 本身不验证身份，不允许直接跳过这一对比。

```powershell
ssh-keyscan -t ed25519 47.110.238.248 | Set-Content -Encoding ascii -LiteralPath "$env:TEMP/goufayu_hostkey.pub"
ssh-keygen -lf "$env:TEMP/goufayu_hostkey.pub"
# 仅在指纹一致后：
Get-Content -LiteralPath "$env:TEMP/goufayu_hostkey.pub" | Add-Content -Encoding ascii -LiteralPath "$env:USERPROFILE/.ssh/known_hosts"
ssh -o StrictHostKeyChecking=yes -i "$env:USERPROFILE/.ssh/goufayu_ecs_ed25519" root@47.110.238.248
```

不使用 `StrictHostKeyChecking=no`。管理员登录和应用账户分离；`goufayu` 是无登录 shell 的服务用户。

有口令的密钥可交给 Windows OpenSSH agent，便于后续非交互上传和部署。先在**本地管理员 PowerShell** 启动服务：

```powershell
Set-Service ssh-agent -StartupType Manual
Start-Service ssh-agent
```

再在**本地自己的普通 PowerShell** 添加密钥，口令只在本机输入：

```powershell
ssh-add "$env:USERPROFILE/.ssh/goufayu_ecs_ed25519"
ssh-add -l
```

安全组仅在连接超时且确认规则缺失时放行 TCP 22 到管理员当前公网 IP `/32`。不为部署开放 5432 或 8765。

## 3. 准备宿主机与不可变发布包

在项目工作目录本地构建（不改游戏默认 URL 或生成配置）：

```text
python tools/build_aliyun_release.py --backend-root D:/survival_database --release-id 20260920-test05
```

生成目录带 `release_manifest.json` 的逐文件 SHA256，`.tar.gz` 旁另有 `.sha256`。`game-config/archive_http_bundle.lua` 是随包待部署候选，须等联调/切换时与服务器包一起更新。

上传本地生成并校验过的发布包，先核对生成器的 SHA256/manifest，解包到一个**新的**发布目录。只使用自己生成的包，不覆盖 `current` 正在使用的目录。所有发布源文件由 root 持有且其他用户不可写，普通目录 `0755`、文件 `0644`；凭据不在包中。以下 `20260920-test05` 只是示例版本号。

服务器先准备接收目录：

```sh
install -d -m 0700 /root/goufayu_upload
```

本地电脑上传发布包和旁边的校验文件（版本号与实际产物一致）：

```powershell
scp -i "$env:USERPROFILE/.ssh/goufayu_ecs_ed25519" ./output/aliyun_releases/20260920-test05.tar.gz ./output/aliyun_releases/20260920-test05.tar.gz.sha256 root@47.110.238.248:/root/goufayu_upload/
```

服务器验证并解压：

```sh
cd /root/goufayu_upload
sha256sum -c 20260920-test05.tar.gz.sha256
install -d -m 0755 /opt/goufayu/releases
tar --keep-old-files -xzf 20260920-test05.tar.gz -C /opt/goufayu/releases
```

```sh
cd /opt/goufayu/releases/20260920-test05
bash deploy/preflight_host.sh
# 先审查上一步的现状，再执行下列安装步骤。
bash deploy/provision_host.sh --install-os-packages
python3.11 deploy/manage.py prepare --release /opt/goufayu/releases/20260920-test05
```

`preflight_host.sh` 只读检查 OS、软件版本、服务状态、监听端口、目录权限、容器挂载、数据库角色和各表精确行数；不创建角色、不安装软件、不重启服务。复用 `/etc/goufayu/postgres-password`，以环境变量名称转交容器内客户端，不输出密码、连接密钥或玩家行内容。SQL 使用只读事务；若管理员不是 `postgres`，显式传 `--db-admin-user <role>`。登录后也可先通过 SSH stdin 执行本地这份脚本，完成检查后再上传发布包。

出现任何业务表/函数，即使行数为 0，也不能自动走空库 `db-init`。先按第 5 节做一致性备份、核对结构和迁移台账，再选择经过审核的升级路径。现有 `current`、服务配置或运行用户与约定不一致时，先记录并备份配置，不覆盖后再调查。

测试接口联调在本地另开一个终端建立隧道（避开现有本地后端的 8765）：

```powershell
ssh -N -o ExitOnForwardFailure=yes -o StrictHostKeyChecking=yes -i "$env:USERPROFILE/.ssh/goufayu_ecs_ed25519" -L 127.0.0.1:18765:127.0.0.1:8765 root@47.110.238.248
```

另一个本地终端访问 `http://127.0.0.1:18765/health`；带认证验收仍优先在 ECS 本机执行，避免把 Bearer 凭据放到命令行。不改游戏当前配置。结束隧道终端即关闭临时转发。

`provision_host.sh` 只使用服务器现有 Alibaba Linux 官方 dnf 源安装 `python3.11`、`python3.11-pip`、`lua`、`logrotate`、`iproute`；不替换系统 `/usr/bin/python`，不执行系统全量升级，也不安装/重建 PostgreSQL 容器。脚本要求已有数据库 unit 处于 active。若发行版仓库缺包，命令会失败，先核实官方仓库，不自动接入第三方源。

离线安装依赖可在 `prepare` 上增加 `--wheelhouse /path/to/reviewed-wheels`。运行时只用该版本 `.venv/bin/python`。`prepare` 自动以 umask 022 创建依赖，结束后恢复原 umask，并通过 `runuser` 以 `goufayu` 用户检查 psycopg 可用。Lua 必须先执行发布包提供的兼容性/结算测试；不能仅凭 `lua -v` 就认定所有结算兼容。

系统适配依据：[Alibaba Cloud Linux 3 官方 Python 安装说明](https://www.alibabacloud.com/help/en/alinux/support/install-a-newer-python-3-on-alibaba-cloud-linux-3)支持并行安装 Python 3.11，保留系统 Python；[systemd v240 更新说明](https://raw.githubusercontent.com/systemd/systemd/v240/NEWS)列出该版本新增的 `append:` 输出模式，因此发布 unit 使用兼容旧版本的日志追加方式。服务器实际软件版本和 unit 支持情况仍以登录后的预检为准。

`prepare`、`db-init`、unit 安装、激活和恢复入口都校验发布 manifest：拒绝越界/符号链接路径、缺失文件、额外未列出的源文件和哈希变化；`.venv` 是本机生成依赖目录，单独不计入源码 manifest。文件 chmod 不改变内容哈希。

### PostgreSQL 17 客户端

本机备份默认用 `deploy/pg-bin`：这是现有容器内 PG17 客户端的有限桥接器，只执行 `podman exec`，不新建/停止容器。导出文件通过 stdin/stdout 保留在宿主机；密码读宿主机受限 pgpass，以环境变量**名称**转发，不写命令参数和容器数据目录。

桥接器仅支持当前工具的导出/恢复参数、`goufayu_test` 和 `goufayu_restore_*`、loopback；它不提供任意 SQL。`psql` 桥接只支持版本查询，角色初始化由 `manage.py` 的 psycopg 连接完成。

**源 Supabase 导出需要真实 PostgreSQL 17 客户端**，可在 Windows 装官方 PG17 客户端，并给 `dbtool.py --pg-bin <PG17/bin>`。宿主机已安装同版本官方客户端也可替换桥接器路径。不要使用旧版 `pg_dump`，也不要为了装客户端重建现有数据库。

## 4. 配置秘密与角色（先于启动应用）

必须保留现有 `FISHING_ACCOUNT_ID_PEPPER`，它参与玩家账号的 HMAC；改变后老账号会像新账号。迁移中保留现有 API token，使服务器与客户端一致。新应用数据库角色密码由工具生成并持久保存，与数据库管理员密码分开。

阿里云终端中交互录入，不回显、不把值写入命令行：

```sh
python3.11 deploy/manage.py capture-secrets
python3.11 deploy/manage.py configure \
  --api-token-file /etc/goufayu/api-token \
  --pepper-file /etc/goufayu/account-pepper \
  --lua /usr/bin/lua
```

`capture-secrets` 只补缺失文件，已存在的文件会校验权限，不覆盖。数据库管理员密码写入 `/etc/goufayu/postgres-password`，仅 root、`0600`。该密码必须是**现有容器的管理员密码**，不是另随机生成一个值。非默认管理员角色通过 `configure --admin-user <role>` 指定。

若集群已经有 `goufayu_app` 或 `goufayu_migrator`，必须先准备与既有角色相符的 `app-password`、`migrator-password` 文件。`db-init` 和 `trial-restore` 在初始化或创建演练库之前，先用这些凭据对现有 `goufayu_test` 做只读连接及身份校验；失败立即拒绝。已有角色不会重设密码，只有本次缺失后新建的角色才设置专用密码。不要并行运行多份角色初始化，也不要把生成的新密码误当作既有角色的密码。

`configure` 会重写部署管理的 `api.env` 和 `pg_service.conf`；若已有自定义调优或额外 service 别名，先记录并备份再执行。它保留现有 token、pepper 和专用密码文件，不用作密码轮换入口。

输出文件权限：

| 文件 | 权限/用途 |
|---|---|
| `api.env`、`postgres-password`、`api-token`、`account-pepper`、`app-password`、`migrator-password` | root `0600`；systemd 管理器读取环境再以非 root 启动 |
| `pg_service.conf` | root:goufayu `0640`，只有地址、数据库名和角色名，没有密码 |
| `admin.pgpass`、`migrator.pgpass` | root `0600`；只用于管理员或备份/迁移 |
| `app.pgpass` | goufayu:goufayu `0600`；应用只持有受限账号密码 |

环境包含 `FISHING_DATABASE_BACKEND=postgres`、`POSTGRES_DSN="service=goufayu_app"`、`PGSERVICEFILE`、`PGPASSFILE`、`SURVIVAL_ARCHIVE_HTTP=1`、`PAYMENT_MODE=test`、`ARCHIVE_LUA_PATH`。DSN 中不含密码。应用不可读管理员文件，不加入 Podman 管理权限。`pg_service.conf` 写为 libpq 要求的 `key=value`，等号两边不加空格。

### 空库安装与数据迁移是两个不同分支

**分支 A：只建立空测试库结构。** 管理员先确认现有 `goufayu_test` 没有业务对象；工具会再次检查。若已有业务数据，立即停止这个分支，不能清库重试。

```sh
.venv/bin/python deploy/manage.py db-init \
  --release /opt/goufayu/releases/20260920-test05 --confirm-empty
export PGSERVICEFILE=/etc/goufayu/pg_service.conf
export PGPASSFILE=/etc/goufayu/migrator.pgpass
.venv/bin/python database/dbtool.py migrate --bundle database --target-service goufayu_migrator
```

`db-init` 只对空目标初始化安全角色；新建登录角色才设置 `configure` 保存的密码，既有角色只验证、不轮换。当前发布迁移按 manifest 重放 **16 份历史 SQL**（12 份后端、3 份扩展、1 份已并入逻辑的手工补丁），再加 1 份原目标兼容调整、4 份本次业务升级和 2 份权限收紧，共 **23 项账本**，逐条校验哈希。应用账号只得到 **12 个 RPC** 执行权，没有表写入、CREATE、BYPASSRLS 或 owner 成员资格。已存在旧账本的库保留历史记录，仅追加审核后的新迁移；不能对现有 `goufayu_test` 重做空库初始化。

**分支 B：迁移源 Supabase 的现有玩家数据。** 先做第 5 节的只读导出、独立恢复演练和 reconcile 验证。**不要先执行分支 A 的 `migrate` 建表。** 演练通过后，最终复用已有 `goufayu_test`：它仍为空才允许 `db-init` 仅配角色，然后 `trial-restore` 导入该空库，最后 `reconcile`。若 `goufayu_test` 已有业务对象，必须拒绝覆盖并保留，另做明确的数据合并/切换计划；不 `--clean`、不清库重试，也不默认把应用改指演练库。

## 5. Supabase 只读备份与独立恢复演练

源数据库连接信息写入受限 `PGSERVICEFILE` 和 `PGPASSFILE`；来源是数据库直连或适合完整导出的 session 连接，不是 Supabase REST URL，不是 transaction pooler。密码不得放 DSN/命令参数。TLS 使用 `verify-full` 并配置受信 CA；确有平台连接约束时先单独核实，不静默降级 TLS。

源服务示意仅包含非秘密字段：

```ini
[legacy_read]
host=SOURCE_DB_HOST
port=5432
dbname=postgres
user=SOURCE_READ_BACKUP_ROLE
sslmode=verify-full
sslrootcert=PATH_TO_TRUSTED_CA
connect_timeout=15
```

`PGPASSFILE` 单独保存实际密码。Linux `0600`；Windows 用 ACL 限当前管理员账户。使用能够读取所有业务表、定义并执行 pg_dump 的受信账号，工具会设置只读事务，不修改源数据库。

```text
python database/dbtool.py audit --source-service legacy_read --output <new-audit-directory>
python database/dbtool.py --pg-bin <PG17-bin> export --source-service legacy_read --output <new-export-directory>
```

产物：`database.dump`、`schema.sql`、`inventory.json`、`backup_manifest.json`。同一个 repeatable-read 只读快照用于 pg_dump 与表行数/内容指纹，期间快照连接保持存活；不是分别在两个时刻取数。未知业务对象、跨库依赖、未覆盖策略/扩展/sequence 会拒绝自动导出，先审查差异，不删源对象来绕过校验。

把整个导出目录加密传输到 ECS 私有目录，核对 manifest 哈希。ECS 上使用独立目标演练：

```sh
.venv/bin/python deploy/manage.py trial-restore \
  --release /opt/goufayu/releases/20260920-test05 \
  --backup /var/backups/goufayu/source_export_20260919 \
  --name goufayu_restore_trial_20260919 \
  --pg-bin /opt/goufayu/releases/20260920-test05/deploy/pg-bin
```

入口只新建指定 `goufayu_restore_*`，目标已存在即拒绝；不复用、不 drop、不清空原 `goufayu_test`。创建前先验证已存在的专用登录角色及密码；首次部署尚无 `goufayu_owner` 时，由管理员创建新库，再初始化安全角色和 schema，并仅为本次新建角色设置 `configure` 保存的密码，不要求先跑分支 A。恢复比较表指纹、字段、索引/约束、函数和触发器。报告保留在导出目录 `<db>_restore_verification.json`，部署入口另写 `/var/lib/goufayu/restore/<db>/result.json`。失败时保留现场，不自动删除数据库。

**恢复 PASS 不等于适合立刻运行应用。** 源快照保留原业务 SQL，恢复阶段暂不开放应用的 schema/RPC 访问。使用数据库工具的显式 `reconcile`，它要求对应 target 的恢复报告 PASS、再次核验数据，然后在事务内补扩展、目标兼容和最小权限，并核对原有列的内容指纹未变：

```sh
export PGSERVICEFILE=/var/lib/goufayu/restore/goufayu_restore_trial_20260919/pg_service.conf
export PGPASSFILE=/etc/goufayu/migrator.pgpass
.venv/bin/python database/dbtool.py reconcile \
  --target-service goufayu_trial \
  --backup /var/backups/goufayu/source_export_20260919 \
  --bundle /opt/goufayu/releases/20260920-test05/database
```

审阅 `database/README.md` 和实际 reconcile 报告。不能在无账本的既有对象上直接运行 `migrate` 强行认领，也不能把恢复 PASS 当作 reconcile 已通过。

### 演练通过后最终复用空的 `goufayu_test`

停止目标 API 写入后使用最终导出快照。先恢复 `PGSERVICEFILE` 到常规配置；`goufayu_migrator` 指向既有 `goufayu_test`。下面 `db-init` 和恢复均会拒绝非空业务库，不会创建/替换原数据库：

```sh
systemctl stop goufayu-api.service  # 若尚未安装该 unit，略过此行；确保没有目标写入方
export PGSERVICEFILE=/etc/goufayu/pg_service.conf
export PGPASSFILE=/etc/goufayu/migrator.pgpass
.venv/bin/python deploy/manage.py db-init \
  --release /opt/goufayu/releases/20260920-test05 --confirm-empty
.venv/bin/python database/dbtool.py --pg-bin deploy/pg-bin trial-restore \
  --target-service goufayu_migrator --backup /var/backups/goufayu/final_source_export
.venv/bin/python database/dbtool.py reconcile \
  --target-service goufayu_migrator --backup /var/backups/goufayu/final_source_export \
  --bundle /opt/goufayu/releases/20260920-test05/database
```

确认真实目标名、报告、原玩家数据指纹、12 RPC 权限后再启应用。`goufayu_app` 保持 `dbname=goufayu_test`。独立 `goufayu_restore_*` 只用于演练，不是默认上线目标。

## 6. 本机启动与验收

完成 schema/权限验收后，安装 unit 模板，再显式激活：

```sh
.venv/bin/python deploy/manage.py install-units --release /opt/goufayu/releases/20260920-test05
.venv/bin/python deploy/manage.py activate --release /opt/goufayu/releases/20260920-test05
.venv/bin/python deploy/manage.py health
systemctl status goufayu-api.service --no-pager
ss -lntp
```

使用专门随机合成账号的 HTTP 验收脚本（显式允许测试写入）：

```sh
.venv/bin/python tests/http_acceptance.py \
  --base-url http://127.0.0.1:8765 \
  --token-file /etc/goufayu/api-token \
  --confirm-test-writes \
  --report /var/lib/goufayu/http-acceptance.json
```

它默认不写库，只有显式确认后才用两个随机 `900` 开头合成账号执行。PASS 只覆盖该报告中的 HTTP 测试，不代表真实游戏、进程重启持久化或异地恢复已验收；本次 ECS 实际执行与独立重启证据见第 13 节。新版抽奖另使用 [lottery_upgrade_acceptance.py 操作说明](../server/aliyun/tests/LOTTERY_ACCEPTANCE.md)。

首次验收生成格式 2 的受限权限报告，保存合成账号、操作编号、计数和存档摘要，不保存 token 或完整档案。随后记录进程身份并实际重启，再复验**同一批**账号：

```sh
systemctl show goufayu-api.service --property=MainPID,InvocationID
systemctl restart goufayu-api.service
systemctl show goufayu-api.service --property=MainPID,InvocationID
.venv/bin/python -B deploy/manage.py health
# health 已成功后执行；启动尚未就绪时先重新检查 health。
.venv/bin/python -B tests/http_acceptance.py \
  --base-url http://127.0.0.1:8765 \
  --token-file /etc/goufayu/api-token \
  --verify-report /var/lib/goufayu/http-acceptance.json \
  --report /var/lib/goufayu/http-after-restart.json
```

只有前后进程/InvocationID 已改变、服务重新就绪、原存档摘要及计数一致，才能记录为本机进程重启持久化通过。`--verify-report` 与 `--confirm-test-writes` 互斥，不提交新领奖或计时指令；现有 profile 接口仍可能初始化记录或完成待结算操作，因此不是数据库严格只读模式。报告拒绝非合成账号、旧格式、非 PASS 源报告、不受限权限及摘要不匹配；不覆盖旧报告。该复验命令自身不会重启服务，不能仅凭复验 PASS 宣称重启发生。

`install-units` 先在隔离临时目录做 `systemd-analyze verify`、`logrotate --debug`，通过后才写入系统配置；已有内容若不同，会先逐字节备份到 `/var/lib/goufayu/config-backups/install-units-*/`，连同原路径、权限和 SHA256 保存。相同内容重复运行不覆盖，也不重复 daemon-reload。命令不启用 API、备份 timer 或 Nginx。

首次安装不需要提前创建或切换 `current`：API 与备份 unit 的固定启动程序是 `/bin/sh`，在真正启动时才 `exec` 当前发布的 Python。API 日志用静态命令 `>>` 安全追加，不依赖上游 systemd 240 才新增的 `StandardOutput=append:`；启动脚本打开日志前的错误写入 journal，兼容 Alibaba Cloud Linux 3 的 systemd 239。`ProtectSystem=strict` 仅为该日志文件打开写权限，日志目录仍不可由服务用户写入。

`activate` 切换 `current`，记录旧链接，启动服务并限时检测；未就绪会停服务，不自动降级数据库或切回旧版本继续写。

主服务依赖现有 `goufayu-db.service`；失败自动重启带退避和启动频率限制。非 root、只读系统、私有临时目录、512 MiB 内存及 64 任务上限。API 和数据库仅绑定 localhost；当前宿主机不支持 unit 的 BPF/cgroup 网络限制，因此不能声称已经限制进程所有出站连接。unit 支持情况以服务器 `verify` 和运行日志为准。

验收分开记录：

1. 5432 与 8765 只监听 loopback；外部不能直连。安全组和防火墙不开放这两个端口。
2. 正确身份/权限、schema 与 RPC 校验通过；应用不是管理员/migrator。
3. `/health` 需 HTTP 200 且 JSON `ok=true`，表示进程存活；`manage health` 另外使用 Bearer 认证访问 `/ready`，要求 HTTP 200、`ok=true` 及实际数据库探测 `database=ready`，再校验 archive 配置哈希。该 API 不返回用于验收的 `status="ok"` 字段。数据库可连仍不等于可恢复。
4. 使用专门测试账号做 profile、在线检查点、存档指令、重试幂等性与断线恢复；测试数据记录清楚，不拿真实玩家随意发奖励。
5. Lua 结算兼容、CSV version 对齐、包哈希与游戏 Lua 一致。
6. 本机备份、异地副本、独立恢复三个状态分别记录。

HTTP 是 stdlib `ThreadingHTTPServer`，请求体最多 16 KiB、仅 JSON 对象，POST 必须 Bearer 认证；不是公网 HTTP/TLS 入口。Lua 子进程每次结算最多 10 秒、最多 4 个并行槽位；游戏端 HTTP 绝对超时 30 秒。不要仅用“进程启动了”代替联调与并发验证。

## 7. 每日备份与异地加密副本

复制后默认 `/etc/goufayu/backup.env` 权限 root `0600`。默认管理员专用 migrator service 明确 `SET ROLE goufayu_owner` 导出；应用没有备份表的权限。手动执行一次验证本机导出：

```sh
systemctl start goufayu-backup.service
systemctl status goufayu-backup.service --no-pager
```

未配 restic 时预期显示 `LOCAL_BACKUP_OK; OFFSITE_NOT_CONFIGURED`，**unit 返回失败**。本机备份仍保留，不能把它描述为异地备份成功。状态 JSON：`/var/lib/goufayu/backup-status.json`；`local_export_ok`、`offsite_ok` 分开。

选择与这台 ECS 独立的 SFTP 主机，或独立 S3/OSS 兼容存储账户。脚本拒绝本机目录、非 HTTPS 的 S3、URL 内嵌密码、localhost、已知 ECS 公网地址和解析到本机网卡的目标；`OFFSITE_REQUIRED` 只接受 `1`，不能用 `0` 或拼写错误让缺失异地备份变成成功。使用官方 restic 程序，独立备份凭据、最小 bucket/path 权限；不是把私钥/密码写入 repository URL。SFTP 使用独立备份 SSH 密钥并提前核验 host key，管理员登录密钥不拿来复用。restic 仓库密码保存 root `0600` 文件，并另存于离线密钥保管处；密码丢失将无法恢复加密备份。

在受限 `backup.env` 中配置：

```ini
RESTIC_REPOSITORY=sftp:backup@INDEPENDENT_HOST:/srv/backups/goufayu
RESTIC_PASSWORD_FILE=/etc/goufayu/restic-password
OFFSITE_REQUIRED=1
```

S3/OSS 使用 `backup.env.example` 的独立凭据文件和已验证 endpoint；区域、兼容 API、限权策略尚未配置，不能宣称 OSS 已可用。首次 `restic init` 由管理员确认目标后执行，脚本不会自动初始化不明仓库。

```sh
# root shell: 仅 source 自己审核过的受限配置文件，不 source 外来文件。
set -a
. /etc/goufayu/backup.env
set +a
restic init
restic snapshots
systemctl start goufayu-backup.service
systemctl enable --now goufayu-backup.timer
systemctl list-timers goufayu-backup.timer --all
```

定时器每日 03:15 加最多 15 分钟随机延迟，补跑错过的任务。先完成一致性导出，再 `restic backup` 和 `restic check`；任何阶段失败都保留本机产物。此工具不自动 prune/delete 备份。定期检查磁盘容量并制定经过确认的保留策略，不能长期忽略容量。

至少一次从异地独立恢复，而不是只读取本机文件：

```sh
restic snapshots --tag goufayu-postgresql17
restic restore <EXACT_SNAPSHOT_ID> --target /var/backups/goufayu/offsite_drill_20260919
# 在恢复出来的完整 export 目录上，调用第 5 节 trial-restore，使用新的 DB 名。
```

最终记录异地 snapshot ID、文件 hash、恢复目标、指纹比较报告和实际耗时。`restic check` 不等于数据库恢复演练。

## 8. HTTPS 和游戏地址最后处理

域名和证书当前未配，不影响前面的 localhost 验收。`deploy/nginx-https.conf.example` 只是未启用模板：填写真实域名/证书、用已安装可信 Nginx 做 `nginx -t`，再显式启用。公网只开放确认后的 443；需要 ACME 时单独配置验证方式。不开 HTTP 明文传 Bearer token。

模板保留 profile、rewards/grant、在线检查点和 archive config/command 的原接口格式，统一需要明确的可信游戏服务器出口 IP/CIDR；默认只有 `deny all`，必须填写并启用 `allow` 后才放行。health/ready 保持本地，`rewards/grant` 也不是公众支付回调。限流阈值是测试初值，需按实际同服人数与请求峰值调整。请求体/超时要与游戏 30 秒超时匹配；代理日志不记录 Authorization 或请求体。

现有游戏入口：

| 配置 | 当前来源/切换方式 |
|---|---|
| URL | `data/csv/玩家档案系统/fishing_system_rules.csv` 的 `api_base_url`，生成 `scripts/vscripts/config/generated/fishing_system_rules.lua`；当前 `http://127.0.0.1:8765` |
| token | 仅 Dota 服务器 ConVar `survival_fishing_api_token`，不能写进 Panorama 客户端 |
| provider | `player_profile_rules.csv` 当前默认 `http_fishing`，禁止自动回退本地模拟档案；服务器 ConVar 为 `survival_player_profile_provider` |
| 存档 HTTP | 服务器 `survival_archive_http_enabled=1`，后台 `SURVIVAL_ARCHIVE_HTTP=1` |
| 测试 fixture | `survival_fishing_reward_fixture` 在正常测试迁移中留空；`automation_9001`/`production_60s` 是工具测试配置 |

异机游戏服务器的 `127.0.0.1` 不会指向 ECS；等 TLS 和认证验收后，再一次性更新受控 CSV、重生成游戏配置并部署，不能只改生成 Lua。全过程保留现有默认直到明确切换。

支付审计：月卡购买有 `set_purchase_provider/create_order` 接口占位，当前没有真实 payment provider，`archive_daily_rules.csv` 的 `purchase_enabled=0`，特殊抽奖券标注需后端验签。不存在已接通的支付宝/微信订单与验签回调。`PAYMENT_MODE=test` 不会自动补齐这些能力。

现有测试命令包括 `faith_cheat` 等。游戏入口有 Tools/Cheats 限制，但旧后端接收 Bearer 后未单独区分这个命令；迁移测试不对公网开放，也不把它视作生产权限策略已完备。发布应用增加的明确生产禁用策略与对应测试，应独立验收。

## 9. 切换与回退：不能丢新写入

1. 先在隔离库完整演练，并确认目标角色权限、备份、玩家身份一致。记录源 schema/version、所有包 hash、部署版本和检查报告。
2. 切换窗口暂停写入口、排空游戏在线检查点与未完成存档操作，再做**最终**一致性源备份。第一次演练时的旧快照不能充当最终数据。
3. 若既有 `goufayu_test` 仍空，按第 5 节最终恢复步骤复用该库，再 reconcile、核对指纹和权限；若非空，停止并保留，不擅自覆盖。备份原 service/env/版本链接，目标仍是 `goufayu_test`，保持 pepper 和 token。
4. 先限制到测试服务器/测试玩家进行读取与幂等写验收，再开放预定测试范围；同一玩家不得同时向两套数据库写入。
5. 记录第一笔目标新写入时间。若发现问题，先停写并备份新目标，不立刻把 URL 切回旧库。
6. **尚无新写入且旧代码与当前数据库权限、结构已验证兼容**时，才可按记录恢复旧 URL/env/current 并启动原服务；**已有新写入**时，必须先对差异做受审的迁回/对账与重放，确认目标新增记录、幂等回执和在线 outbox 都保留后才能切回。直接回旧快照会丢数据。当前 test03 严格要求旧 11-RPC 权限，与升级后的 12-RPC 数据库不兼容，不能直接激活回退。
7. 代码版本回退与数据库回退分开。`previous-release` 只记录旧代码位置，不保证旧代码兼容新 schema；部署工具不会自动清库、执行 down migration 或删除新发布。

## 10. 第一阶段本地检查（历史记录）

本地可运行、不连接外部服务：

```text
python -B -m unittest discover -s server/aliyun/deploy -p test_deploy.py -v
bash -n server/aliyun/deploy/provision_host.sh
```

第一阶段的封存本地结果见 [验证记录](../server/aliyun/validation/local_20260919.json)：

- 87 项测试通过：后端 49、真实 Lua 存档结算 14、部署工具 16、数据库工具 8。
- 独立 PostgreSQL **17.11** 的 8 项集成测试通过，包括永久奖励、旧存档冲突、玩家隔离、断库返回 503、正数在线时间 outbox 恢复与权限拒绝。
- 真 HTTP 进程的 9 项检查通过；随后启动另一后端进程，重新读取两个合成账号，确认存档保留。
- 带数据完整库恢复、仅旧 9 表的源库恢复后升级、已升级库再次灾备恢复均通过。比较内容指纹、结构、函数、触发器，旧列数据未改变；拒绝覆盖非空库。
- Python 3.11 语法及 shell 语法通过。本地运行实际使用 Python 3.13.13、Lua 5.4.5、psycopg 3.3.6。

本节记录连接 ECS 前的本地验证，不能用于判断当前部署状态。最新状态见第 13 节。

待完成：专用 SSH 公钥安装和指纹核验、目标机 Python/Lua 和 PG 客户端检查、源 Supabase 连接/只读导出、隔离恢复与权限验收、实际本机联调、域名/HTTPS、独立异地仓库和从异地恢复。当前没有进行云端切换。

## 11. 首次连接受阻时的准备记录（历史，2026-09-19）

**以下是公钥修复前的历史记录，当前部署状态见第 13 节。** 当时 Windows OpenSSH 可用，已到达 `47.110.238.248:22` 的 SSH 握手阶段；实际检查 `C:/Users/li/.ssh` 不存在。严格主机验证返回 `No ED25519 host key is known` / `Host key verification failed`，当时没有成功认证或执行远端命令。

候选公开主机指纹为 `SHA256:3cUNJuxLSLLSw7CIDmtOis7yGlxaSt+D7DQJmc6Uno8`，**尚未经阿里云控制台确认，不作为可信主机记录**。先完成第 2 节的本地密钥生成、服务器追加公钥及控制台指纹核对。当前无需为了此次连接另开安全组端口。工具进程的默认 SSH home 与 Windows 用户 home 可能不同，实际部署命令应显式指定 `C:/Users/li/.ssh` 下的 IdentityFile、UserKnownHostsFile，避免读错配置。

本轮已修正并测试：

- `deploy/manage.py`、unit、`provision_host.sh`：首次安装校验、日志追加、原配置备份、受限运行用户、venv 可读性；已有数据库角色先验证凭据，禁止自动重设密码。
- `database/dbtool.py`、`init_roles.sql`：实际数据库名白名单、未知 schema/扩展拒绝、空账本和缺号账本拒绝、账本与实际对象核对、首次迁移原子提交；历史业务 SQL 未修改。
- `deploy/preflight_host.sh`：服务器只读预检，管理员密码仅本机读取；SQL 只读，遇到 RLS 导致无法完整计数时拒绝继续。
- `tests/http_acceptance.py`：格式 2 报告及 `--verify-report`，实际重启后读取原测试账号，不另发新业务指令。

验证证据：

- 离线测试 **49 项**通过：部署 26、数据库工具 13、验收报告 10。Python 3.11 语法和 Shell 语法检查通过。
- 本地 PostgreSQL 17.11 的 **13 项**迁移保护检查通过，包括 17 项迁移、重复执行 0 项、真实中间版本续跑和备份恢复核对：[数据库检查记录](../server/aliyun/validation/database_guards_20260919.json)。
- 本地实际 HTTP 进程完成 **9 项**写入/幂等/隔离检查；退出后启动新 PID，再完成 **6 项**原账号重读检查：[重启验证记录](../server/aliyun/validation/http_restart_20260919.json)。这不是 ECS 验收。
- SSH 探测及所有远端未验项：[连接记录](../server/aliyun/validation/ecs_connection_20260919.json)。

新候选包使用 `20260919-test02`；`test01` 保留作历史产物，不用于本次部署。发布包不包含秘密文件、数据库备份或私钥。

| 部署项目 | 计划值 | 当前证据 |
|---|---|---|
| 发布目录 | `/opt/goufayu/releases/20260919-test02` | 本次未创建，服务器现有内容未核验 |
| 后端服务 | `goufayu-api.service`，用户 `goufayu` | 未安装/启动，既有状态未核验 |
| 后端监听 | `127.0.0.1:8765` | 未验证 |
| 数据库 | 复用 `goufayu_test`、`goufayu-db`、`127.0.0.1:5432` | 用户提供，尚未登录复核 |
| 游戏地址 / Supabase / 支付 | 保持原环境与测试模式 | 本轮未修改 |

当前没有远端变更，无需服务器回退。后续若测试部署验收失败，先停止 `goufayu-api.service`；保留数据库、测试数据、原密码和发布目录。只有确认旧代码兼容当前数据库后才切回记录的旧发布，涉及新写入时按第 9 节处理，不恢复旧快照覆盖新数据。

## 12. ECS 首次部署（历史记录，2026-09-19）

**本节记录当时 test03 的部署和旧数据库状态；当前版本及回退约束见第 13 节。不要把下文的旧迁移/RPC 数量当成当前值。**

公钥修复后已通过严格主机验证连接 ECS，用户在控制台核对过服务器主机指纹。实际登录使用本机 `goufayu_ecs_ed25519_v2`，私钥保留在本机 SSH agent 中。

- 系统实测 Alibaba Cloud Linux 3.2104 U13.4、systemd 239；Python 3.11.13、Lua 5.3.4、psycopg 3.3.6。
- 原 `goufayu-db` 容器、`goufayu-db.service`、PostgreSQL 17.11、`/data/postgres17` 和管理员密码均复用。预检确认 `goufayu_test` 没有业务表；操作前已导出空库备份。
- 已创建 `goufayu_owner`（NOLOGIN）、`goufayu_migrator`、`goufayu_app`；已执行 17 项审核迁移及权限加固，运行账号只有 11 个业务 RPC，无直接表权限和建表权限。
- `goufayu-api.service` 已启用开机启动，以 `goufayu` 用户运行，`Restart=on-failure`。实际监听 `127.0.0.1:8765`，数据库仍为 `127.0.0.1:5432`。
- 当前发布目录 `/opt/goufayu/releases/20260919-test03`；`current` 指向此版本，`test02` 保留。已修复 PG17 容器桥接遗漏的离线 SQL 输出参数和数据库恢复参数；test03 未重跑建库或迁移。
- 实际 HTTP 9 项验收通过，重启后端后 PID 从 9626 变为 9848，原账号重读 6 项验收通过。证据在 `/var/lib/goufayu/acceptance_20260919T134554Z`。
- 当前游戏地址及 Supabase 数据未修改，支付保持测试模式。源 Supabase 业务数据尚未导入，此实例目前用于合成测试账号验证。

systemd 明确提示此宿主机不支持 BPF/cgroup IP 防火墙，unit 中的 `IPAddressDeny/Allow` 不生效。实际安全边界是 API 和数据库仅绑定回环地址；不能宣称已限制进程全部出站网络。

补充服务器实测：

- test03 升级后，原测试账号 6 项重读通过；实际 SIGKILL 终止 API 主进程后，systemd 自动拉起，PID 从 10499 变为 10974，`NRestarts` 从 0 变为 1，存档重读再次通过。数据库服务 PID 始终为 6590。
- 使用非 root 应用账号验证旧 revision 不能覆盖永久奖励；模拟数据库连接失败，真实 ArchiveService HTTP 路径返回 503，无空存档返回，原数据不变。该测试未中断实际数据库。
- 日志在 `/var/log/goufayu/api.log`；强制轮转已验证，crond 已启用。每日检查、超过 20MB 时可提前轮转、保留 14 份并压缩。`maxsize` 仅在 logrotate 执行时检查，并非持续硬性大小限制。
- 每日 `03:15`（服务器 Asia/Shanghai）加最多 15 分钟随机延迟运行 `goufayu-backup.timer`，已启用。备份 `/var/backups/goufayu/backup_20260919T141151Z` 本机导出成功；因尚无异地仓库，service **退出 1 / failed**，状态文件明确记录 `local_export_ok=true`、`offsite_ok=false`、`offsite_not_configured`。这不表示 API 或本地导出失败；也不能当作完整异地备份成功。
- 已通过 SSH 下载该备份到本机电脑，4 个文件哈希与云端一致。在本机独立 PostgreSQL 17.11 新建恢复测试库完成恢复：15 张表内容、结构、函数、触发器、约束和索引核对通过；权限加固后 14 张业务表原数据保持，应用就绪和 5 项越权拒绝通过。未在 ECS 建立额外数据库。本机副本不提交仓库。
- 已实测 SSH 隧道 `127.0.0.1:18765 -> ECS 127.0.0.1:8765` 的 `/health`，测试后关闭临时隧道。

完整记录：[服务器部署验收](../server/aliyun/validation/ecs_deployment_20260919.json)、[云端备份在本机恢复](../server/aliyun/validation/ecs_backup_restore_20260919.json)。更早的 connection/authentication 文件仅记录公钥修复前状态。

### 本地电脑操作：重新打开联调隧道

在本项目根目录 PowerShell 执行，保持窗口打开；该主机文件已与阿里云控制台指纹核对。私钥由本机 ssh-agent 解锁。

```powershell
ssh -F none -N -o BatchMode=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=output/ecs_backend_work/ecs_hostkey_candidate.pub -o IdentitiesOnly=yes -o ExitOnForwardFailure=yes -i "$env:USERPROFILE/.ssh/goufayu_ecs_ed25519_v2" -L 127.0.0.1:18765:127.0.0.1:8765 root@47.110.238.248
```

另开窗口访问 `http://127.0.0.1:18765/health`。业务接口需要原 API token；不要将 token 放入聊天、URL 或提交到仓库。关闭隧道窗口或按 Ctrl+C 即可停止转发。不要为此开放 5432 或 8765 公网端口。

### 服务器操作：检查与回退

```sh
systemctl status goufayu-api.service --no-pager
/opt/goufayu/releases/current/.venv/bin/python -B /opt/goufayu/releases/current/deploy/manage.py health
cat /var/lib/goufayu/backup-status.json
```

当前游戏没有切换到 ECS。若要撤下本次测试后端，执行以下命令即可，保留数据库和备份：

```sh
systemctl disable --now goufayu-api.service
```

恢复测试后端运行：`systemctl enable --now goufayu-api.service`，再执行上述 health 检查。

当时 `/var/lib/goufayu/previous-release` 记录 test02，test03 与 test02 的数据库结构一致；但 test02 的备份桥接有已知缺陷。该记录不适用于本次升级后的数据库，**现在不得直接激活 test02/test03 回退**。版本路径记录不保证旧后端与当前权限兼容，按第 13 节隔离恢复及保留新增数据的步骤处理。

不执行 down migration，不还原旧快照覆盖新写入，不删除 `/data/postgres17`。以后若切换真实游戏或迁入 Supabase 数据，仍必须执行第 9 节的停写、最终一致性备份、对账和防丢数据回退流程。

**仍缺配置 / 未验收：** 测试域名、Nginx/HTTPS、自动异地备份仓库（OSS/S3 兼容或独立 SFTP 主机）及从该仓库恢复；Supabase 源业务数据迁移、真实游戏客户端联调、整台 ECS 重启和真实数据库停机演练。当前没有向公网开放 API，没有开启真实支付。

## 13. 新版存档与抽奖实际升级（2026-09-20）

### 当前部署

| 项目 | 已验证结果 |
|---|---|
| 发布目录 | `/opt/goufayu/releases/20260920-test05` |
| 当前链接 | `/opt/goufayu/releases/current` → `20260920-test05` |
| 后端服务 | `goufayu-api.service`，`active/running`，开机自启 `enabled`，用户 `goufayu`，`Restart=on-failure` |
| 后端监听 | `127.0.0.1:8765` |
| 数据库 | 复用 `goufayu_test`、`goufayu-db`、PG 17.11、`127.0.0.1:5432`、`/data/postgres17` |
| 迁移和权限 | 23 项迁移/加固账本记录，应用仅有 12 个 RPC；无表访问、DDL 或 owner 角色成员资格 |
| 服务器报告 | `/var/lib/goufayu/upgrade-20260920` |
| 支付 / Supabase | `PAYMENT_MODE=test`，未接真实收款；Supabase 原数据未修改、未导入 |

发布包 SHA256：`bd497cf2114d2c81f7d96eb61b03165d13d270660b999243b9022b13ad0a21d3`。
游戏 `scripts/vscripts/config/generated/archive_http_bundle.lua` 与 test05 的结算包一致：
`4b28247fa0bbabf0d220b4f178a9d8379fc54d362792b031fbfcd5a71c8bf20d`。
历史结算包仍保留，以支持旧未完成回执恢复。

### 备份、试迁移和目标升级

1. API 停止期间对现有测试库做一致性备份，目录
   `/var/backups/goufayu/preupgrade_20260920_005800Z`；15 张表来自同一导出快照。
   `database.dump` SHA256 为 `65f4b1670cb063ae1ef76db26105bf9711d846cb86ea77ebcc9daa7cddf97f32`。
2. 恢复到新的独立库 `goufayu_restore_upgrade_20260920`，表内容指纹、函数、触发器、
   约束和索引比对通过。保留原 `goufayu_test`，未重新初始化集群、数据目录或管理员密码。
3. 在恢复库先执行 4 项审核业务升级及独立抽奖权限加固；验收通过后对 `goufayu_test`
   执行相同升级。保留旧 SQL 与迁移账本校验值，新增账本到 23 项。两个库重复执行
   均新增 0 项迁移，所有业务行保持不变。
4. 原有 4 个合成账号的木材默认秒产各减少一次，最低为 0，对应 revision 增加；
   重复执行不会继续扣减。攻击/属性成长仅调整默认值，已有玩家值、奖励历史、
   内容库存及在线 outbox 保留。
5. 恢复库和目标库各通过真实 PG 回滚事务验收：97 项 CSV 默认值、6 项越权拒绝、
   领奖/存档/在线检查点幂等、抽奖回执和库存原子提交、旧 revision 拒绝及 outbox
   只结算一次。该 SQL 检查提交测试行数为 0。

### 实际 API、抽奖与重启验收

- `manage.py health` 通过：`/health` HTTP 200 且 `ok=true`；认证 `/ready`
  HTTP 200 且 `ok=true, database=ready`；归档配置哈希与当前发布相同。
- HTTP 存档 **9 项**通过：鉴权、建档、读写、相同指令重试一次结算、玩家隔离、
  重新连接存档保留、拒绝原始存档上传及正数在线时长检查点幂等。
- 真实 HTTP + Lua 抽奖 **7 项**通过：两个新合成账号各取得普通地图券后十连；
  真实扣券、结果和回执持久化、相同完整 command ID 重放不重复扣发、玩家隔离、
  永久内容保留以及旧存档上传拒绝。没有充值特殊券或启用支付。
- 非 root 运行账号完成 **2 项**保护检查：旧 revision 不能覆盖新永久奖励；独立
  测试 HTTP 实例连接失败数据库时返回 503，不返回空 profile/save，原健康库数据不变。
  该测试未停止数据库，也不代表真实数据库服务停机已演练。
- 手动重启 API：PID `15435 → 15885`。之后模拟 API 进程异常，systemd 自动拉起：
  PID `15885 → 15959`，`NRestarts: 0 → 1`。两次恢复均验证原 4 个合成账号完整
  存档摘要、revision 和抽奖快照保持一致；数据库服务 PID 始终为 `6590`。

这些结果使用合成账号，**不等同于真实游戏客户端已连接成功**。验收报告只保存
合成 ID、摘要和结果，不保存密码、token、完整玩家存档或密钥。

本地脱敏过程日志在 `output/ecs_upgrade_20260920/`：`backup_before_upgrade.log`、
`restore_before_upgrade.log`、`upgrade_clone.log`、`upgrade_test_database.log`、
`activate_test05.log`、`http_acceptance_test05.log`、`restart_test05.log`。
该目录和私有数据库备份均不提交仓库。

### 升级后的异地副本与恢复验收

新备份为 `/var/backups/goufayu/postupgrade_20260920_014155Z`，16 张表使用同一
一致性快照，dump SHA256 为
`e1f87fd3ae7e1132c284155a70fb9ac94e6b30543720921dac93675e04b81eab`。

4 个备份文件已下载到本地电脑
`D:/survival_database/local_test_exports/20260920-upgrade/postupgrade_20260920_014155Z`，
逐一校验 SHA256；目录访问权限受限且被 Git 忽略。随后从**该本地副本**重新上传到
`/var/lib/goufayu/restore-input-20260920/postupgrade_20260920_014155Z`，恢复到新的
独立库 `goufayu_restore_postupgrade_20260920`。16 张表数据指纹、表结构、函数、
触发器、约束和索引全部相同；再施加权限加固，新增迁移为 0、账本 23 项、
12 个应用 RPC，应用无直接表访问、DDL 或角色成员权限。原 `goufayu_test` 未被覆盖。

`goufayu-backup.timer` 保持 enabled/active；日志轮转配置解析通过。
**自动异地同步尚未配置**，手动副本及其恢复验证不等于定时异地备份完成。
详情见 [脱敏验收记录](../server/aliyun/validation/ecs_upgrade_20260920.json)。

### 本地电脑操作：游戏测试隧道

游戏默认 provider 为 `http_fishing`，CSV URL 保持 `http://127.0.0.1:8765`；
该 localhost 是运行游戏服务器的电脑。本次已建立匹配端口的 SSH 隧道，
通过它验证了健康检查、认证 `/ready`、未认证请求拒绝和游戏配置哈希。
Python 和数据库端口在 ECS 上仍只绑定 loopback。

在项目根目录 PowerShell 中执行以下命令可检查隧道：

```powershell
& output/ecs_backend_work/.venv/Scripts/python.exe -B tools/aliyun_test_connection.py check
```

如电脑重启或隧道退出，将 `check` 改成 `connect`；结束联调时改成 `stop`。
该工具仅管理自己创建且身份校验匹配的 SSH 进程，不会终止占用同端口的其他程序。
需要本机 ssh-agent 已解锁专用密钥，以及已经核对过服务器指纹的
`output/ecs_backend_work/ecs_hostkey_candidate.pub`。这些本机文件不提交仓库。

下一步在 Dota 2 Workshop Tools 正常启动 `survival` 游戏并进入测试地图。
`launch_template_map.cmd` 是美术预览入口，会改变时速和 UI，不能作为正常存档验收入口。
认证口令仅在本机 Tools 服务器内传入；不粘贴到控制台或聊天、不提交仓库。
真实游戏内存档写入、退出重进、抽奖与界面反馈**尚未验证**。

进入可操作英雄的正常游戏后，可在项目根目录 PowerShell 执行：

```powershell
& output/ecs_backend_work/.venv/Scripts/python.exe -B tools/aliyun_game_test_auth.py probe
& output/ecs_backend_work/.venv/Scripts/python.exe -B tools/aliyun_game_test_auth.py inject
```

`probe` 只检查本工具管理的隧道和正常 `template_map` Tools 服务器。
`inject` 从本机现有 `.env` 选择 API token，先验认证 `/ready`，再通过访问权限
受限、Git 忽略的临时 KV 文件传给服务器 ConVar，并在成功或失败后删除临时文件。
命令行、请求 JSON、生成 Lua 和工具输出均不包含口令，不传入账户 pepper。
ConVar 仍可被本机开发者查询，此工具仅用于本机联调，不是正式游戏的凭据分发方式。
本工具尚待实际游戏运行验证；能力探测失败时不会读取或写入认证口令。

首次空 token 导致的档案加载失败会在正常游戏时间推进后重试（间隔约 5 个游戏秒）。
不要重复调用档案服务 `init`；暂停状态或美术预览极慢时速会延迟重试。

域名、Nginx/HTTPS、自动异地备份仓库及该仓库恢复、Supabase 源玩家迁移仍未完成；
整台 ECS 重启和真实数据库停机也未演练，真实支付保持关闭。

### 当前安全回退方式

出现问题先停 API 写入，保留数据库和全部备份：

```sh
systemctl stop goufayu-api.service
```

需一并关闭开机自启时使用 `systemctl disable --now goufayu-api.service`。
只恢复当前 test05 运行，可使用 `systemctl enable --now goufayu-api.service`，随后执行：

```sh
/opt/goufayu/releases/current/.venv/bin/python -B /opt/goufayu/releases/current/deploy/manage.py health
```

**不要直接 `activate` test03/test02。** 旧后端严格校验 11 个 RPC，当前数据库
已授予 12 个 RPC，因此旧代码不能直接连接当前已升级库。`previous-release` 只记录
代码路径，不能证明数据库可回退。需要旧版行为时先备份当前新写入，另建独立库恢复
上述升级前备份，验证旧后端和权限后再制定测试连接切换、新增数据保留和对账方案。
不得将旧快照覆盖 `goufayu_test`，不得删除数据目录或自动执行 down migration。

## 14. 游戏建造提示 profile_not_loaded（2026-09-22）

实际定位：ECS 和 SSH 隧道正常，但当前游戏进程未设置认证 token，因此档案和资源
账户均未初始化。游戏还处于暂停，按游戏时间调度的加载重试没有推进。
安全注入认证后，只为尚未加载档案的玩家触发正常读取，当前玩家档案和资源账户
已恢复；未使用本地空存档替代远端存档，未重置当前对局或已加载的档案。

以后测试请双击项目根目录 `launch_aliyun_test_game.cmd`。它依次连接 ECS 隧道、
打开正常 `survival/template_map` Tools 游戏、等待游戏就绪、配置认证，并请求缺失档案。
如果 Dota 已打开，只尝试接入现有游戏，不重开地图。工具只回显状态，认证临时文件
用后删除；本机密钥仍由 ssh-agent 管理，不在仓库保存密钥或 token。

附加修复：档案预加载、英雄就绪和显式重试统一记录正在进行的请求，避免新请求替代
旧请求后，旧回包被丢弃却永久阻塞后续重试。错账号响应继续拒绝，同时正确结束本次
尝试。回归测试覆盖认证恢复、失败间隔、过时响应、账户隔离和已有永久物品保留。
该 Lua 修复在下次正常加载地图时生效；本次未热重载或重新初始化正在玩的档案服务。

当前确认的是档案与建造资源恢复，最终建筑落地结果仍需实际游戏操作确认。
