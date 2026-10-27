# SHOP02 有界增量打包

`incremental_vpk.py` 只准备本地候选与 VPK，不上传、不切换助手、不启动或停止游戏。默认只读；只有 `--build` 创建新目录和文件。

固定基线是签名 SHOP02（2026102604、6637 份资源、5 个 VPK），基线目录、manifest 内容标识、序号、VPK 大小和 SHA256 均固定在工具中。当前原生包序号为 2026102705，助手包为 2026102706。本工具不选择商业规则；原生多人保留本局数据，云档及支付使用连接助手，由发布候选的代码、配置及审核记录约束。前一版2703提交失败及2704安装／回滚的候选、目录与回执保留，不能当成本版验收。

## 输入和输出

- `--overlay`：全新外部小目录，恰好包含相对基线修改／新增的 runtime 文件，以及完整 `_release_manifest.json`、`_release_signature.json`。不放私钥、构建报告、源码、旧资源副本或其他 provenance 文件。删除资源只反映在完整 manifest 中。
- `--candidate-view`：尚不存在的外部目录，与基线同盘。未变资源建立硬链接，修改／新增资源独立复制；两份 release 元数据独立写入。完整候选可直接交给现有发布器。
- `--output-dir`：全新或空的外部目录。最终只包含完整目录 VPK 和所有数据卷。
- `--review-source`：包含最终 admission gate、公开签名信任配置的审阅源码树；默认当前 game 仓库。构建前应冻结这些源码，不在构建期间修改。
- `--reuse hardlink`：默认，相同盘上未变 VPK 卷复用硬链接；工具全程只读打开它们。`--reuse copy` 可以把 VPK 放另一盘，但未变卷会实际占用空间，且需要通过空间预检。

影子候选和复用卷是冻结的发布输入。不要在影子候选上重新编译、保护 Lua、写配置、设置文件只读属性或修改 ACL；对硬链接的原地写入或属性修改会影响同一文件的其他名称。需要新修改时，在独立 overlay 中完成，再创建新的 view 和输出目录。清理只应删除新链接名称，不能就地改写这些文件。

## 校验和空间

工具对旧 loose runtime、旧 VPK、完整新 manifest、Ed25519 签名及全部合并输入执行校验。构建时仍调用原有 `pack.authenticate`，包括完整 runtime allowlist、production、四账号、admission gate；最终仍调用原有 VPK 校验器，逐文件检查 CRC32、MD5、SHA256，以及目录／全文件 MD5、连续偏移、无多余数据、分卷容量。基线在结束时再次完整核验。

已有路径保留原 archive 分组；新增路径放最后一卷，现阶段不自动重分组。任一卷超过 1GiB 或删除后形成空卷时停止，需要单独审阅。第000卷原来只剩147917字节余量；XML在第003卷，Lua、JS、CSS主要在第000卷。只重写受影响卷，未变卷不分配新 payload 空间。空间预检按磁盘分开计算，并保留256MiB；仍需另行保证 Steam 上传暂存和官方重新下载空间。

## 命令

在 game 仓库内使用带 cryptography 的现有安全解释器。下面的三个外部目录由本轮候选构建流程确定；先只读核对，确认后才添加 `--build`。

```powershell
& 'D:/Survival_安全工具/venv/Scripts/python.exe' -B -X utf8 tools/arcade_cleanup_20261027/incremental_vpk.py --overlay 'D:/Survival_发布候选/20261027_ws4_refresh_native_v02_overlay' --candidate-view 'D:/Survival_发布候选/20261027_ws4_refresh_native_v02_view' --output-dir 'D:/Survival_工坊输出/20261027_ws4_refresh_native_v02' --review-source 'D:/Survival_发布候选/20261027_ws4_refresh_native_v02_overlay_trusted_source' --sequence 2026102705
```

真实构建的 stdout 是兼容现有 uploader 的 JSON build report，须以 UTF-8 保存到 VPK 目录以外。例如添加 `--build` 后通过 `Set-Content -Encoding utf8` 保存到本轮 ignored output 路径。工具本身不读取签名私钥；完整清单由候选构建者先通过既有 `tools/release_security/protect_data.py sign` 签名，私钥留在外部安全目录。

现有发布器的精确命令结构如下；它通过本机已经登录的 Steam 客户端工作，不读取网页 cookie、Steam 密码、网关凭据或 API token：

```powershell
& 'D:/Survival_安全工具/venv/Scripts/python.exe' -B -X utf8 tools/steam_workshop_upload.py --candidate 'D:/本轮全新candidate_view' --vpk 'D:/本轮全新VPK目录/3824360109.vpk' --listing publishing/workshop/test_listing.json --build-report '本轮UTF8构建报告.json' --state-file output/four_accounts_20261022/steam_upload_state.json
```

无 `--apply` 时仍只验证与查询。审核完成后由发布负责人添加 `--apply --update-existing` 更新原条目。固定使用原条目ID，不创建新条目、不改变已批准的可见性／封面／账号名单；listing 的清单 SHA 和序号须匹配新包。`Steam.__enter__()` 固定校验已安装 DLL 的 SHA、app570、登录状态和作者 SteamID；`publish()` 经 `StartItemUpdate/SetItemContent/SubmitItemUpdate` 提交，日志会先落盘，再执行不可逆的提交。超时保留日志，使用 `tools/workshop_test/reconcile_workshop_pending.py` 查询现状，不能直接重复提交。

若候选使用单独的 frozen reviewed-source，发布器也应沿已有 `web.trusted_root(...)` 包装在同一信任根中调用；不能删除 gate 校验来迁就源码差异。发布后还需重新生成当前版本的官方下载 pins 并实测，旧 `verify_native_shop_download.py` 固定 SHOP02，不能把旧结果当成本轮下载证明。

```powershell
& 'D:/Survival_安全工具/venv/Scripts/python.exe' -B -X utf8 -m unittest discover -s tools/arcade_cleanup_20261027 -p test_incremental_vpk.py -v
```

Fixtures 使用临时随机 Ed25519 密钥、小型多分卷资源和独立 Node VPK reader。涵盖重复构建一致性、跨卷修改、新资源、硬链接／copy复用、原基线不变、签名／内容／名单／gate／超容量拒绝、默认只读和失败清理；不访问真实 Steam、后端或生产候选。

## 本轮官方重新下载核验

`verify_download.py` 固定本轮原生包 content `8a01a5b66603804c683b879043c220e4f9496d7cca75f304ac5d9da210794cf6`、序号2026102705、6655份资源，使用 `20261027_ws4_refresh_native_v02_view`、对应v02 VPK及 `native_package_build_v02.json`。默认只读计划，不初始化 Steam；实际下载需添加 `--download`，要求 Dota 已正常退出、Steam 在线、canonical journal 已记录同版本上传成功，并有全包加1GiB的可用空间。工具不退出游戏、不上传、不编辑 canonical journal、不自动重试。

```powershell
& 'D:/Survival_安全工具/venv/Scripts/python.exe' -B -X utf8 tools/arcade_cleanup_20261027/verify_download.py
```

实际执行时，工具在 publication lock 内再次校验完整候选及本地 VPK，发出一次订阅刷新（1313回调）及一次下载（3406回调），用前后未缓存官方查询绑定安装目录、大小、更新时间。随后验证完整5个VPK、4个数据卷、全部6655份签名资源，并核对180份保护模块相对签名SHOP02保持不变。

Steam UGC details 本身不返回 depot manifest ID。若本次 journal 顶层已有 `steam_manifest`／`download_manifest`，必须为一致的 uint64 十进制字符串；没有时，工具从3406后实际安装的官方 ACF 读取 manifest，再用前后查询和完整新包实字节核验绑定。不会从 `previous_release`、历史记录或旧工具常量借用 manifest。证据仅写入 `output/arcade_cleanup_20261027/download_evidence_v02`，成功下载不代表实机或多人验收完成。

安全测试：`python -B -X utf8 -m unittest discover -s tools/arcade_cleanup_20261027 -p test_verify_download.py -v`。

## 2026-10-27 10:19 上传失败的单次恢复

本次SDK3404明确返回EResult2，Steam记录向 `depot-ingest.discovery.steamserver.net` 上传104792字节manifest时超时；约11.05MiB资源差分尚未得到成功发布证明。真实未缓存查询确认远端仍是SHOP02，更新时间1792994420、完整大小3767101843。失败原日志、pending逐字节备份、脱敏网络诊断和该查询保存在 ignored `output/arcade_cleanup_20261027/upload_recovery_attempt_20261027_101903`，evidence SHA256为 `6479ce916c8af73d3d0198ca1022418ba047364e21630e9f4e730f1e9fd0de4b`。

`capture_upload_failure.py` 已完成本次证据捕获，固定目录不覆盖；其默认模式只读。网络诊断不导出代理用户名、密码、URL路径／查询、响应正文或头部。程序的`direct`探测表示未显式使用HTTP CONNECT代理，不保证绕开系统TUN或透明路由；HEAD能连接不等于带认证manifest上传能成功，不能据此写入上传成功。

`recover_failed_upload.py` 默认只读计划。以下命令的 `--verify` 会真实下载旧SHOP02并完整验证，只写新证据、不改canonical。发布负责人审阅后可用 `--apply`：它必须在同进程、publisher lock内重新执行未缓存前后查询、真实3406下载回调、6637份签名资源／全部5VPK／4分卷及ACF验证，再以固定pending SHA执行CAS原子替换。没有导入旧验收文件、force、直接清pending或自动重传入口；执行前正常退出Dota并保留Steam。

```powershell
& 'D:/Survival_安全工具/venv/Scripts/python.exe' -B -X utf8 tools/arcade_cleanup_20261027/recover_failed_upload.py --verify
```

需恢复时把 `--verify` 替换为 `--apply`，不能把之前的verify JSON当作apply授权。工具保留本次失败attempt及完整原pending，恢复的成功状态只属于经过真实重新下载的旧SHOP02；旧native验收标记保留为历史，未晋升为本轮成功。恢复后才可由正常发布器对相同的新签名候选进行一次受控重试；任何再次超时仍应保留新的pending和真实回调证据。此工具不配置网络、不重启Steam、不重编候选、不上传。

安全测试：`python -B -X utf8 -m unittest discover -s tools/arcade_cleanup_20261027 -p test_upload_recovery.py -v`。

## 连接助手的薄包安装

`install_refresh_helper.py` 固定把已签名的 helper v04 refresh overlay（序号2026102706）安装到 `svt_w24`，旧状态必须完整匹配 helper02（2026102702）。它通过旧 helper01 与签名 policy patch 认证旧清单，通过 SHOP02 与新的 thin overlay 验证新清单的每个文件，不创建完整3.77GB影子副本。新内容标识未固定时拒绝操作。

默认只读核验；只有 `--apply` 在 Dota 已关闭时备份差异、逐文件 CAS 替换／新增／删除、完整核验新 runtime 后更新 marker。唯一删除为旧 `commerce_wallet.vcss_c`。新事务及备份位于 `output/arcade_cleanup_20261027/helper04_alias_transactions`，与原安装器共用互斥锁。`--rollback` 只接受与 active 事务一致且完整核验通过的新状态，恢复旧字节并保留引擎缓存；外来修改不会被覆盖。两份 release 元数据不安装到游戏目录。

```powershell
& 'D:/Survival_安全工具/venv/Scripts/python.exe' -B -X utf8 tools/arcade_cleanup_20261027/install_refresh_helper.py
& 'D:/Survival_安全工具/venv/Scripts/python.exe' -B -X utf8 -m unittest discover -s tools/arcade_cleanup_20261027 -p test_install_refresh_helper.py -v
```

本次只重新编译钱包JS。`build_refresh.py` 读取全新的 `compile_v02.json`：沿用原11条精确编译记录，替换钱包1条；旧 `compile.json` 与旧日志保留。新回执SHA和钱包日志的精确路径需审核后固定到 `COMPILE_REPORT_SHA`／`COMPILE_LOG_OVERRIDES`，未固定时拒绝投影和签名。其余11项仍绑定原日志目录，不能任意改变日志来源。旧2703/2704工具原字节及SHA清单位于 `output/arcade_cleanup_20261027/source_history_2703_2704`，该目录供历史审阅，不作为当前工具入口。
