# 06｜冻结构建、工坊发布与回退

本模块记录可复用的发布办法，事实截点为 2026-10-24。当前发布是 `WS4-ENTRY-05`，不是开发目录全量打包。完整回执为 `publishing/workshop/workshop_entry_release_20261024.json`；独立云测试、真实登录与资源分发各有自己的验证范围。

## 1. 开发仓库、候选与平台版本分别管理

game 仓库为 `game/dota_addons/survival`，content 为 `content/dota_addons/Survival`，二者独立。content 保留可编辑地图、Panorama 和素材；game 提供 Lua、编译资源及对应源码镜像。修改 UI／地图时要配套核对源码与编译输出，遵守 `.gitattributes`，已有 LFS 资源继续通过 LFS 提交。

Git commit 说明代码历史；签名 candidate 内容 SHA 说明冻结运行集合；Steam manifest 说明平台上的下载快照；原生验收说明该启动方式实际可用。它们不能互相替代。Git push 不更新游廊，Steam 上传成功也不证明玩家入图、登录或多人联机。旧资料中的固定地图／单 VPK 限制已被当前入口和分卷实现扩展，执行时以当前工具、签名策略及最新回执为准。

不可变候选放在安装目录之外，新版本写新目录，不覆盖旧候选或正在运行的 addon。私钥仅在既有私有工具环境使用，不进入源码、trusted_source、VPK 或知识包。trusted_source 只包含批准的门禁源码、策略和公钥，不能把最新开发主入口整体替换进冻结版本。

## 2. 当前版本的精确范围

| 项目 | v04 基准 | v05 当前 |
| --- | --- | --- |
| 候选 | `20261024_ws4_web_auth_v04` | `20261024_ws4_workshop_entry_v05` |
| 发布序号 | `2026102404` | `2026102405` |
| 运行文件 | 6627 | 6630 |
| 内容 SHA-256 | `f5be8205cd107797f75c5b930224933de8c15f10e9a9e17932b3d6d747f91eb7` | `b4750e433bdd1b1ea2fab0de98d13b3660ed5d3ef80a10c63c46512eab10bc60` |

v05 只修改 `addoninfo.txt` 与主入口的固定前缀，新增 `maps/ws4_entry.vpk`、客户端入口脚本和 `systems/workshop_entry.lua`。180份受保护模块逐字节保留；冻结主脚本原正文、网页登录模块、production 配置和真实地图也不变。`tools/workshop_test/build_workshop_entry_candidate.py` 固定校验基准签名、序号与内容，约束五路径、文件数量与主正文后缀，构建前后检查输入和 HEAD 不漂移，生成新清单及签名。默认只读，显式 `--build` 才写新的外部目标；不自动安装、上传或启动游戏。

此前网页候选工具曾用 `git diff HEAD` 取补丁，提交后差异会变空；现已固定任务起始提交 `641e836c1a2b82f03f300e53dd567bd6a06ede81` 为补丁基线，并另记当前 HEAD。这是可复现构建的重要约束：比较基准和构建时工作区身份不能混用。受保护模块如必须修改，需走原保护与签名流程，不能把明文直接覆盖进已签名候选。

## 3. 自有轻量地图及发布门禁

`tools/build_workshop_entry_map.py` 从本项目 `maps/gold_training_room_review.vmap` 固定骨架生成自己的 `content/.../maps/ws4_entry.vmap`，保留标准根数据、最小实体和 floor_support 材质，移除装饰。Valve 编译器记录零失败；运行 `maps/ws4_entry.vpk` 为144203字节，SHA-256 为 `abce9c7f6a1159303c799ec9a8b40afa7f724e7bf4c52509038e490afa67fecb`。内部16项 CRC 通过，路径为 `maps/ws4_entry.*`，包含根 vmap_c、world 和 entities；所需材质／贴图已在冻结基准中，不新增第三方依赖。编译回执位于忽略的 `output/workshop_entry_map/20261024T121825_289020Z/`。

只改默认地图会产生一个隐蔽缺包风险：`tools/build_runtime_release.py:map_files` 必须同时保留未公开列为默认入口的 `maps/template_map.vpk`。发布器对入口布局要求 ws4_entry=1、template_map=4、两份地图和入口模块完整；新增 ENTRY_GATE_FILES 只在入口布局启用，旧候选仍可验证。上传器把 listing 地图和容量绑定候选 addoninfo，而不是沿用旧常量。对应回归覆盖缺真实地图、缺根 vmap_c、错误 CRC、改动保护模块与冻结正文等拒绝路径。

## 4. Failed to read 16 bytes 的实际修复

历史约3.77GB单 VPK 已与上传字节一致，CRC、SHA-256、MD5 和容器摘要全通过，Valve `resourceinfo.exe` 仍稳定报 `Unknown read error 87 / Failed to read 16 bytes`。只改 VPK v1 只能列目录，大偏移资源仍失败。证据支持本机原生大包读取兼容问题，未定位 Valve 源码具体缺陷，也不是“代码没提交”。

修复保留全部运行字节，改成小目录 VPK 加四个不超过1GiB的资源卷。当前 `tools/stream_workshop_vpk.py` 在容器超过 `0x7fffffff` 字节时自动分卷；逐项复制时核对大小、CRC 和双哈希，独立解析输出再验证。先发布数据卷，最后发布目录 VPK；已有目标拒绝覆盖，失败只清理本次产物。不能混放不同版本的目录和数据卷，也不能只发送目录 VPK。VPK 本身没有作者 RSA 签名，真实性来自打包前固定信任策略下的 Ed25519 清单。

当前五文件为 `3824360109.vpk` 与 `_000`～`_003.vpk`。Steam manifest `2955439000185399689` 的正式下载逐字节匹配，6630运行项与签名通过；四卷及包尾资源均由 Valve 原生工具读取成功。完整起因与历史范围见 `publishing/workshop/startup_read16_repair_20261023.md`、`docs/stream_workshop_vpk.md`。验证一个包的数学摘要和验证引擎能读取它，应分别保留证据。

## 5. Windows 分发与长路径经验

历史加入客户端需要约3.77GB完整资源。缺目录、解压过深、0字节资源、清单版本不符和安装阶段路径过长会产生不同故障，不能统一归因 VPN。应先校验完整文件集、每项大小与 SHA，再安装，最后测试 UDP 连通。一次性生成 `client_resource_audit.json` 比逐个补一张纹理更有效；移动到短路径不能恢复已经丢失的文件，必须从完整包重新解压。

最终安装器采用长路径感知的文件操作，同时处理源和目标目录，不只给输入目录加前缀；固定诊断区分 check_layout、check_resources 与 install_runtime。历史脚本为 `tools/workshop_test/join_client.ps1`，派发器已移入 legacy，当前玩家无需该连接助手。引擎会扫描 addon 下的诊断 VPK，`.gitignore` 不阻止扫描；虚拟包、故障夹具和大包输出必须放在安装／content 搜索范围之外，不能留一个占位坏包污染 Tools 启动。

## 6. 发布、部署、回退的最小操作顺序

先读帮助、审阅默认计划，再执行已获授权的写步骤；下列命令只用于维护参考，此知识整理未运行部署或发布。

```powershell
# 本地两入口只读核对，不启动游戏或中转
./tools/workshop_test/launch_test.ps1 -Mode Offline -CheckOnly
./tools/workshop_test/launch_test.ps1 -Mode Online -CheckOnly
# 使用项目配置的解释器；不输出其私有环境
. ./tools/backend_python.ps1
$knowledgePython = Resolve-SurvivalBackendPython -RepoRoot (Get-Location).Path
& $knowledgePython -B -X utf8 tools/workshop_test/build_workshop_entry_candidate.py --help
& $knowledgePython -B -X utf8 tools/stream_workshop_vpk.py --help
& $knowledgePython -B -X utf8 tools/steam_workshop_upload.py --help
& $knowledgePython -B -X utf8 tools/workshop_test/deploy_web_auth.py audit
& $knowledgePython -B -X utf8 tools/workshop_test/deploy_web_auth.py verify
```

候选流程为：验基准→定向叠加→保护和差异审计→全清单双哈希→签名→分卷→上传前只读验证→明确更新原条目→Steam 正式下载→全量校验→原生读取→玩家启动验收。工坊更新需显式 `--apply --update-existing`，保留原 journal ID，不能删恢复记录后盲目重建条目。当前只允许原不公开列出条目与四测试账号，支付关闭。

网页服务首次安装执行 `audit → prepare → activate → verify`；更新已有 sidecar 源码前必须先成功 rollback，顺序为 `audit → rollback → prepare → activate → verify`，不能原位覆盖运行服务。失败保留私有回滚记录并恢复原服务／Nginx 状态，不能顺手重启原库或支付服务。临时传输切换严格为 `rollback → prepare → configure-transport --steam-tls-relay 0|1 → activate → verify`。回退要区分代码、服务、资源包和数据库：恢复已审核旧候选与同版全部卷，重新校验摘要；保留新测试档，不把部署回退误作数据库回滚。签名有最低序号策略，不能为降级关闭验签；旧序号不被策略接受时，从批准的旧内容生成新的合规候选。

## 7. 测试 scope 与双仓交付

自动测试证明协议、输入校验、权限和打包规则；编译成功证明资源可编译；原生资源读取证明引擎能读指定资源；Tools 入图、非 Tools 独立 addon、直接启动原 ID、原游廊按钮是不同 scope，必须分别记录。v05最终由 owner 正常 Steam 启动并确认原条目，进入 N5，云端只读汇总观察到 revision43 与在线检查点；没有打断现有对局。该局未查询引擎 sv_cheats 值，不能把启动器参数冒写为现场测量；项目禁作弊策略已确认，先前原生联网也确有引擎拒绝作弊命令记录。

离线入口显式 Tools＋development＋离线标记，使用本局内存档，不触云和支付，允许 cheats；联网入口使用签名冻结副本、真实 Steam 授权和 WS4测试库，启动参数设置 `sv_cheats=0`，中央策略拒绝调试修改并重核已注册回调。launcher 校验内容、保护策略和 production 配置三个摘要，防止用旧副本。此规则仍不能使本地主机战果成为可信排行依据。

每次代码交付均检查 game/content 两仓：记录分支、上游、未提交和未推送状态、已有 stash；`stash --include-untracked` 保存并记录本次对象→按既有策略 pull→只 pop 本次 stash→核对原改动恢复→只暂存任务文件→相关验证→commit→push→核对远端 HEAD。无改动不造空提交，不强推、不清历史 stash。本会话原102份开发改动应继续保留，不能被冻结发布误收。最终报告分别列两仓提交、推送分支和保留改动；知识包和运行缓存不替代这些交付记录。

本模块的可迁移部分是边界、审计和验证流程；新项目需替换条目、域名、信任策略、账号配置及数据库隔离，不能沿用本项目私钥、Bearer、测试身份或第三方保护核心。[Steam UGC 文档](https://partner.steamgames.com/doc/api/ISteamUGC#SetItemContent)只说明内容目录接口，不能替代 Dota 自身发布和原生验证。
