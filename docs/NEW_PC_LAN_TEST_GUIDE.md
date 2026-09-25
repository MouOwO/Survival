# 新电脑复制与局域网联调

更新：2026-09-25。适用于 Windows 上的 `survival/template_map` Workshop Tools 测试，后端为现有阿里云测试环境。

## 先区分两种电脑

| 角色 | 需要安装/准备 | 从哪里进入游戏 |
| --- | --- | --- |
| 测试主机：运行本局服务端 Lua | 相同游戏资源、Workshop Tools、Python、Node.js、Git、OpenSSH、自己的登录密钥及测试 API 凭据 | 本文的主机启动入口 |
| 加入者：只加入这台主机的对局 | 相同游戏资源、Workshop Tools、自己的 Steam 账号 | 加入主机的同一对局 |

**加入者不需要 SSH 私钥、API token、数据库密码或 Python 后端。** 若某台电脑以后也要独立开局，才执行主机配置。两台电脑各自运行单人启动器，得到的是两个独立对局。

当前连接关系：

```text
加入者 B/C/D 的 Dota 客户端
             │ 游戏连接
             ▼
主机 A 的 Dota 服务端 Lua
             │ http://127.0.0.1:8765
             ▼
主机 A 的 SSH 隧道 ──► ECS 127.0.0.1:8765 Python API
                                      │
                                      ▼
                             goufayu_test PostgreSQL
```

局域网只承载游戏连接。主机仍需联网访问 Steam 和 ECS；这不是完全断网模式。不向局域网或公网开放 API `8765`、数据库 `5432`、开发控制台 `29000`。

## 一、同步项目：所有电脑都做

1. 安装 Steam、Dota 2 和 **Dota 2 Workshop Tools DLC**，每名参与者登录不同的 Steam 账号，保持 Dota 版本一致。
2. 将 `game` 仓库放到本机实际 Steam 库对应的目录：

   ```text
   <Steam 库>/steamapps/common/dota 2 beta/game/dota_addons/survival
   ```

3. 需要在 Hammer 中编辑的电脑，同时同步对应 `content/dota_addons/survival` 源资源；本局参与者必须使用相同的一组游戏代码、配置及编译资源。仅更新 `.vmap` 不会自动更新运行用的 `.vpk`。
4. 确认 `game` 目录中有本次验收版本的 `maps/template_map.vpk`，以及对应模型、材质和 Panorama 编译产物。开发源和游戏资源分别记录提交号；不要求两个不同仓库的提交号相同。
5. 更新本次连接工具。如果使用单独的工具更新压缩包，将包内内容解压到上述 **game 的 survival 根目录**，保留相对路径。该包不是完整游戏，不包含地图、模型、凭据或 Python 环境。

在各自仓库根目录记录版本：

```powershell
git rev-parse HEAD
git status --short
Get-FileHash -Algorithm SHA256 -LiteralPath .\maps\template_map.vpk
```

加入者至少比对 `game` 提交号和地图哈希；有未提交的游戏改动时，仅提交号相同不能证明内容一致。主机工具依赖 `git check-ignore` 验证临时凭据不会入库，因此主机应使用正常 Git 检出，不要仅复制没有 Git 元数据的散装文件。

**不要同步这些机器专属内容：** `.venv`、`output`、SSH 私钥、`.env`、临时凭据、计划任务、隧道进程状态。跨电脑复制 `.venv` 会保留旧 Python/Blender 的绝对路径，是本次已确认的失败原因之一。

以下命令均在新电脑的 `game/dota_addons/survival` 根目录执行。路径有空格时使用 PowerShell 的 `-LiteralPath` 和引号；每个代码块单独执行，不要把上一条路径后面直接接下一条命令。

## 二、主机建立本地环境

### 2.1 安装运行工具

主机需要 Python、Node.js、Git、Windows OpenSSH Client。当前推荐 Python 3.13；已在新电脑 Python 3.13.15 环境验证。无需在 Windows 安装 PostgreSQL，也不用启动另一份本地数据库。

检查工具：

```powershell
& { Get-Command py.exe,python.exe,node.exe,git.exe,ssh.exe,ssh-add.exe,ssh-keygen.exe -ErrorAction SilentlyContinue | Select-Object Name,Source; if (Get-Command py.exe -ErrorAction SilentlyContinue) { py -0p } }
```

只需要 OpenSSH **客户端**。连接 ECS 不要求新电脑安装 SSH Server。

### 2.2 重建本机环境和连接配置

双击根目录：

```text
setup_aliyun_test_host.cmd
```

也可在 PowerShell 中执行：

```powershell
& .\tools\setup_aliyun_test_host.ps1 -Action Setup
```

工具在当前仓库创建可用的 `.venv`，必要时先保留旧环境再重建，不沿用其他电脑的解释器路径。其本地配置位于：

```text
output/ecs_backend_work/local_config.json
```

首次执行时，SSH 和 API 凭据尚未准备，出现对应检查失败和 `SETUP_NEEDS_ATTENTION` 是预期的；
Python 环境和路径配置已经保留。继续完成下面第三、四节，再执行 `Check`。
重复执行 Setup 会复用可运行的环境，不重复创建或覆盖已有凭据。

该文件只存本机路径，不保存密钥或 token 内容。可显式指定路径，例如：

```powershell
& .\tools\setup_aliyun_test_host.ps1 -Action Setup -PythonExe "$env:LOCALAPPDATA\Programs\Python\Python313\python.exe" -KeyFile "$env:USERPROFILE\.ssh\goufayu_ecs_ed25519_v2" -EnvironmentFile "$env:USERPROFILE\.goufayu\game-test.env"
```

默认兼容已有 `D:/survival_database/.env`；没有该文件时使用本仓库忽略目录内的 `output/ecs_backend_work/game-test.env`。无需为了适配旧路径新建 D 盘，也不必复制整个后端仓库。

## 三、主机配置 SSH 登录

### 3.1 本地电脑：每台主机使用独立密钥

建议为每台受信任的开发主机生成自己的密钥，便于单独撤销权限。以下命令发现同名私钥或公钥时会停止，不覆盖现有文件：

```powershell
& { $keyPath = Join-Path $env:USERPROFILE '.ssh\goufayu_ecs_ed25519_v2'; if ((Test-Path -LiteralPath $keyPath) -or (Test-Path -LiteralPath ($keyPath + '.pub'))) { throw '同名密钥已存在，未覆盖；直接检查或使用现有密钥。' }; New-Item -ItemType Directory -Force -Path (Split-Path $keyPath) | Out-Null; ssh-keygen -t ed25519 -f $keyPath -C 'goufayu-test-host' }
```

按提示设置并保管好密钥口令。口令只在本机终端输入；它不是 ECS 密码，也不是 API token。忘记口令不能通过公钥找回，应另建密钥并安装新公钥。

### 3.2 阿里云控制台终端：只添加新公钥

本步骤由拥有 ECS 管理权限的人操作。服务器继续使用现有 `47.110.238.248`，不重建数据库、密码文件或容器。

在服务器终端先执行这一行，进入等待输入状态：

```sh
cat >> /root/.ssh/authorized_keys
```

再在**本地电脑**执行以下命令，将公钥复制到剪贴板：

```powershell
Get-Content -LiteralPath "$env:USERPROFILE\.ssh\goufayu_ecs_ed25519_v2.pub" | Set-Clipboard
```

切回服务器终端，先按一次 Enter，粘贴公钥这一整行，按 Enter，再按 Ctrl+D。先按 Enter 是为了避免原文件末尾没有换行时把两条公钥粘在一起。不要粘贴私钥、SHA256 指纹或 PowerShell 命令。

在服务器终端逐行执行：

```sh
chmod 700 /root/.ssh
chmod 600 /root/.ssh/authorized_keys
ssh-keygen -l -f /root/.ssh/authorized_keys
```

在本地核对自己这台电脑的公钥指纹：

```powershell
ssh-keygen -l -f "$env:USERPROFILE\.ssh\goufayu_ecs_ed25519_v2.pub"
```

服务器列表必须包含这个指纹。每台新主机独立生成的登录密钥指纹不同，这是正常情况。

### 3.3 本地电脑：载入 ssh-agent

先在普通 PowerShell 检查：

```powershell
& { Get-Service ssh-agent; ssh-add -l }
```

若服务被禁用或停止，才在**管理员 PowerShell**执行：

```powershell
& { Set-Service ssh-agent -StartupType Automatic; Start-Service ssh-agent }
```

然后回到平时运行 Steam/游戏的 Windows 用户的**普通 PowerShell**，执行：

```powershell
ssh-add "$env:USERPROFILE\.ssh\goufayu_ecs_ed25519_v2"
```

出现口令提示时输入本机密钥口令，输入过程不显示字符。成功应提示 `Identity added`，再执行 `ssh-add -l` 确认存在该指纹。**复制了私钥文件，不等于已在当前 Windows 用户的 agent 中载入它。**

工具包附带的是服务器**公开主机密钥**，不是登录私钥。已核验的服务器 ED25519 主机指纹为：

```text
SHA256:3cUNJuxLSLLSw7CIDmtOis7yGlxaSt+D7DQJmc6Uno8
```

若服务器主机指纹变化，先通过阿里云控制台核实原因，不关闭严格主机密钥检查。安全组仅在 SSH 无法连通时检查 TCP 22 是否允许当前开发主机公网出口；不为此开放数据库端口。

## 四、主机配置测试 API 凭据并检查

SSH 登录凭据和游戏 API 凭据是两件事。测试 API token 必须与现有 ECS 测试服务匹配，由项目管理员通过安全渠道提供给受信任的开发主机，不能随意生成另一个值。

在主机普通 PowerShell 执行：

```powershell
& .\tools\setup_aliyun_test_host.ps1 -Action Credential
```

按本机隐藏输入提示录入测试 API token，不把它写进命令参数、聊天、截图或 Git。工具保存最小的本地凭据文件；不需要复制数据库管理员密码、Supabase 密钥或账号 pepper。

如果已经通过 `-EnvironmentFile` 指向可用凭据文件，跳过 `Credential`，直接检查。
`Credential` 只新建本工具的 `game-test.env`，已有该文件时会停止，不覆盖完整后端 `.env`。

依次检查：

```powershell
& .\tools\setup_aliyun_test_host.ps1 -Action Check
```

```powershell
& .\tools\setup_aliyun_test_host.ps1 -Action OnlineCheck
```

本地检查包含真实凭据目录的空文件 ACL 测试。在线检查验证 SSH/隧道及后端就绪状态。它们都不是多玩家实机验收。

## 五、先完成这台主机的单机验证

双击 `launch_aliyun_test_game.cmd`，保持游戏及命令窗口打开，等待：

```text
GAME_AUTH_READY: missing profiles requested; loaded profiles preserved.
```

该输出表示认证已传入，并已请求缺失档案，不代表所有业务验证自动完成。继续验收：

1. 进入模式和难度选择，完成后正常进入可操作状态。
2. 建造建筑，不再出现 `profile_not_loaded`。
3. 读取原存档并进行一笔可核对的测试变更。
4. 正常结束并重新进入，确认该账号数据保留。

相同 Steam 账号在不同主机上应读取同一账号的云端档案；不同 Steam 账号应分别创建/读取自己的数据。单机测试期间不要使用同一 Steam 账号同时进行多局存档写入。

### Hammer 自动认证：可选

主机单机测试通过后，双击 `setup_hammer_backend.cmd` 安装当前 Windows 用户的助手。以后 Hammer 运行正式 `template_map` 时自动接入认证；它不是加入者必需的软件。

```powershell
& .\tools\setup_hammer_backend.ps1 -Action Status
```

助手会主动注入认证，因此进行下一节“先等玩家、再认证”的 LAN 测试前，需要停止助手。结束 LAN 测试后可恢复：

```powershell
& .\tools\setup_hammer_backend.ps1 -Action Stop
```

```powershell
& .\tools\setup_hammer_backend.ps1 -Action Start
```

不要同时打开多个直连 `29000` 的开发控制台客户端。助手与启动器的状态日志不会输出凭据。

## 六、局域网同局测试

### 开始前

- 选定唯一主机 A，B/C/D 只加入 A。同一局最多四人；先用两人完成纵向验证。
- 所有电脑使用相同代码、配置和编译资源，处于同一受信任网络，每人登录不同 Steam 账号。
- Windows 防火墙仅为本次实际游戏端口放行 `dota2.exe`，限制为私有网络、本地子网。
  不关闭整个防火墙，也不创建对该程序所有端口的宽泛允许规则，避免连带暴露开发控制台。
  常见游戏端口为 UDP 27015，以本局 `status` 和实际监听结果为准。
- 历史项目曾用 `connect 192.168.1.134:27015` 加入并取得独立 PlayerID/操作同步；这个 IP 只是旧机器地址，不能复制到新网络。当前版本的完整两机流程仍需执行下方验收。

### 主机 A

1. 停止 Hammer 自动认证助手，并完全退出旧 Dota/Tools 游戏进程，使新会话不带旧 token。
2. 双击根目录 `launch_aliyun_lan_host.cmd`。它默认等待 **2 名玩家，包含主机自己**，最长等待 600 秒。
3. 保持地图和命令窗口开启；启动器先等待真实玩家加入，人数足够后才传入认证。当前代码由认证和资源加载屏障决定何时开始，**不能依赖旧 CSV 的 60 秒设置来保证固定加入窗口**。
4. 在主机游戏控制台查看 `status`，确认本次游戏服务端的 LAN 地址/端口。使用主机的局域网 IPv4，不使用 ECS 公网 IP，也不使用 `127.0.0.1`，把该地址交给 B。
5. B 加入后，启动器确认实际玩家人数达到要求，再自动执行现有认证流程。等待 `GAME_AUTH_READY`，由游戏内屏障确认参与者准备完成，再完成模式/难度选择。

三人或四人测试在 PowerShell 指定人数，例如：

```powershell
& .\tools\launch_aliyun_lan_host.ps1 -ExpectedPlayers 4 -JoinWaitSeconds 600
```

人数检查排除机器人、观战、断线、无 Steam 身份和重复身份，不把“打开了几个游戏窗口”当成人数。它不改玩家数据、创建角色或重新初始化游戏服务。

如果 Hammer 助手还在运行，LAN 启动器会要求先停用它；如果当前地图已经认证/放行，会要求冷启动新局。不要同时运行单机启动器绕过等待。等待人数超时后，先检查加入者连接结果，再重试 LAN 启动器，已有未放行的地图可继续接入。

如果主机在 B 加入前已经放行，或日志出现 `assignment_window_closed`，不要通过反复认证强行补造活动玩家槽位。退出后重新按顺序开局，先让所有玩家入局再放行。

LAN 测试结束、准备恢复 Hammer 单机开发时，在主机执行 `setup_hammer_backend.ps1 -Action Start`，重新启用自动认证助手；仅在已安装助手的电脑执行。

### 加入者 B/C/D

从 Steam 打开 Workshop Tools，选择同版本 `survival`。**不要运行** `launch_aliyun_test_game.cmd`，也不要自行 `dota_launch_custom_game` 新建地图。

在自己的游戏控制台输入主机实际提供的地址，例如：

```text
connect 192.168.1.134:27015
```

例子里的地址和端口必须替换成 A 本次的值。加载后确认进入 A 的同一名单/对局，等待主机放行。

如果当前 Dota 构建拒绝裸 IP 加入，保留主机和加入者的连接错误；可再核验本地托管开发大厅/好友加入入口，让玩家在启动前分配到活动槽位。普通游廊的远端专用服务器并不运行 A 的本地 Lua，不能假定它也能使用这套 loopback 隧道。不要以公开发布/远端大厅成功作为本工具已经保证的能力。

### 两人验收记录

| 检查项 | 通过条件 |
| --- | --- |
| 同一对局 | A/B 看到同一场战斗，分别获得不同 PlayerID 和可控制的建造者 |
| 开局屏障 | 两人完成认证与资源加载后才放行；没有重复闪回加载界面 |
| 控制隔离 | A 操作自己的建造者/建筑，不改变 B 的所有权和资源 |
| 波次/建造 | 各自能建造，正常出怪，目标与所属通道正确 |
| 档案隔离 | 不同 Steam 账号显示各自数据，重进后各自变更保留 |
| 重复操作 | 对同一可重试请求，不重复扣费或发奖 |
| 断线 | B 离开后 A 的运行、资源和数据不被重置；记录 B 重连实际结果 |
| 性能 | 记录单人/双人/四人、怪物高峰的 FPS、ping、单位数和测试时长 |

保存测试日期、两台机器代码提交号/地图哈希、错误代码和是否通过。不记录 token、密钥或玩家完整身份。双人通过后再扩展三至四人；单机 `GAME_AUTH_READY` 不能替代以上结果。

## 七、本次调试结论与故障定位

| 输出/现象 | 已确认原因或定位方向 | 最少操作 |
| --- | --- | --- |
| `did not find executable` 指向旧 Blender/Python | 从另一台电脑复制了 `.venv` | 执行本机 `Setup`，重建环境 |
| `The agent has no identities` | 当前 Windows 用户 agent 未加载密钥 | 同一用户下执行 `ssh-add` |
| `Server accepts key` 后仍拒绝 | 公钥已匹配，但客户端签名/解锁可能失败 | 检查 agent 与本机口令，不重复改服务器公钥 |
| `Host key verification failed` | 主机密钥文件/路径/算法不匹配或主机发生变化 | 使用工具附带的核验主机密钥；不关闭严格检查 |
| `temporary_auth_acl_failed` | 旧实现重设文件所有者，部分复制目录拒绝此操作 | 更新本次工具，执行 `Check`；不授予 Everyone 权限 |
| 空文件子目录测试成功，直接目录失败 | 两个测试位置的继承权限不相同 | 使用工具真实凭据目录的 `check-acl` 结果 |
| `tools_console_unavailable` | 游戏关闭、Tools 控制台未就绪 | 保持正常 Tools 游戏开启，再运行启动器 |
| `tools_server_confirmation_missing` | 未取得指定地图的服务端回显，或中途关闭了游戏 | 保持 `survival/template_map` 开启，检查控制台占用 |
| `authenticated_backend_not_ready` | 本机 API token、隧道或远端服务/数据库就绪检查未通过 | 先执行 `OnlineCheck`，不用空档案替代云端档案 |
| `assignment_window_closed` | 新玩家在本局活动槽位分配结束后才加入 | 所有人在放行前加入，重新开局验证 |
| `GAME_AUTH_READY` | 本机认证传入与缺失档案请求通过 | 继续验收游戏读写与多人同步 |
| `api_environment_missing` | 本机还未配置 API 凭据 | 执行 `Credential` 或通过 Setup 指定现有 `-EnvironmentFile` |
| `ssh_key_not_loaded_in_current_user_agent` | agent 中没有当前配置对应的密钥 | 在运行游戏的同一 Windows 用户下加载该密钥 |
| `compiled_template_map_missing` | 游戏目录没有编译后的主地图 | 同步正确的 `.vpk`，不能只复制 `.vmap` |
| `lan_session_already_authenticated_restart_without_bridge` | 这局已认证或已放行，无法再充当人数等待阶段 | 停助手、退出旧游戏，再用 LAN 主机入口冷启动 |

已经实测：新电脑重建 Python 环境、修复 ACL 后，用户确认出现 `GAME_AUTH_READY`。ACL 修复保留可信所有者，只收紧访问规则；token 在空文件权限校验通过后才写入，使用后删除。没有修改 ECS 数据库、管理员密码或 Supabase 原数据。

尚未验证：本次工具整合后的新一轮两机/四机完整联调、断线重连、长期战斗及公开游廊服务器的托管拓扑。

本次整合的 **85 项自动化测试通过**，包括真实 Windows ACL、复制失效虚拟环境后的
保留/重建/复用、路径配置、隧道/认证/助手回归，以及真实 Lua 解释器中的 LAN 人数与
开局屏障模拟。模拟与本机工具测试不替代两台电脑的实际游戏连接。
当前开发电脑还以正常桌面用户运行了完整离线 `Check`：12 个检查项全部通过，
包括真实 agent 身份、凭据格式和凭据目录权限；未因此连接或修改 ECS。

可分发工具包：`output/test_host_bundle/goufayu_test_host_tools.zip`。包内
`TEST_HOST_TOOLS_MANIFEST.json` 列出文件及 SHA256；它只装入固定清单中的公共工具、
测试、已核验的服务器公开主机密钥和文档，不包括任何登录私钥、token、`.env`、虚拟环境、
隧道状态或完整游戏资源。更新包包含当前工作区内容，不能假定其改动已经提交到远端。

## 八、停用和回退

- 停用 Hammer 助手用 `setup_hammer_backend.ps1 -Action Stop`；卸载用 `-Action Uninstall`。不删除已有云端存档。
- 工具更新压缩包只覆盖其列出的连接脚本/文档；回退时恢复对应版本这些文件，不恢复其他机器的 `.venv`。
- 独立新密钥需要撤销时，由服务器管理员只删除其对应公钥行，并保留当前可用的管理连接；不要覆盖整个 `authorized_keys`。
- 不删除 `/data/postgres17`，不重建 `goufayu-db`，不修改当前游戏正式后端地址，不启用真实支付。

## 参考与证据范围

- 项目当前代码：`tools/launch_aliyun_test_game.ps1`、`tools/aliyun_game_test_auth.py`、`scripts/vscripts/systems/startup_loading_service.lua`、`scripts/vscripts/systems/multiplayer_player_service.lua`。
- 项目历史双机记录：`docs/ai/START_HERE.md`、`docs/ai/SESSION_LOG.md` 的 2026-08-26 至 2026-08-29 记录。旧 `MULTIPLAYER_TOPOLOGY_REPORT.md` 中“LAN 未跑”早于这些记录；生产托管拓扑仍未证明。
- Dota 2 官方中文站的[运行自定义地图说明](https://www.dota2.com.cn/wiki/Dota_2_Workshop_Tools/Addon_Overview/Playing_Addons.htm)记录了本地 `dota_launch_custom_game` 测试入口以及大厅中先入队再启动的流程；它不保证当前构建中未发布地图的裸 IP 加入方式。
