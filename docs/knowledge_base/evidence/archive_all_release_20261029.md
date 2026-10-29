# 存档四楼、全量修改与服务器配套发行证据（2026-10-29）

本轮用户明确授权提交、推送目前全部修改，更新相关服务器内容并发布原游廊。下列内容依据实际发行回执与对应工具源码独立复核；不保存认证信息、数据库连接串、玩家行或备份明文。开发交互与业务规则继续见[单行与独立召唤记录](archive_layout_independent_20261029.md)，视频来源与固定属性见[视频对照](archive_video_challenges_20261029.md)。这些旧证据中的“未部署／未上传”描述是当时状态，本次发行状态以本文为准。

截至本文件首次写入：服务器已完成 PG17 克隆验证、迁移、激活及健康验证；游廊 `2026102901 / WS4-ARCHIVE-ALL-01` 已成功上传原条目 `3824360109`，保持不公开列出。Steam上传成功，官方重新下载在内容分发阶段返回 No Download Source／No connection to content servers；当前未取得新版完整下载回执，不能把新远端manifest当安装成功。原生已完成签名候选启动测试，尚无本轮多人击杀与真实玩家云端到账验收。

## 发行身份

| 项目 | 本轮实际值 |
| --- | --- |
| 游廊条目／App | `3824360109`／`570`，原条目更新，visibility `3` |
| 发行序号／revision | `2026102901`／`WS4-ARCHIVE-ALL-01` |
| 客户端签名内容 SHA256 | `7eee7d5b975573da3e26b2f8fcf079cbc346e33e4a06dc7f7c1c7280691e46ba` |
| 服务端活动 release | `20261029-archive-d573588b64d2` |
| 服务端不可变 bundle | `d573588b64d2ea6d1431c856d52e0515b5ed471cfdf6af4456ff618d0f568488` |
| SQL 配置内容摘要 | `93e950784f60e92e718506eb6c8ef770c6f2a60771a3abdabc35a3f8b8366d81` |
| 构建源码快照 game HEAD | `936fe2fca9077b4a5e757526548ff75105a58e6d` |
| 随后服务器发行工具提交 | `8d6b8f8ffebca4a7350fe09b271b0bcb8adfd33a`，`dev` |

Git、服务端 bundle、签名内容摘要、VPK 索引和 Steam 安装 manifest 是不同身份。构建时另包含经逐字节清单审阅的d573游戏hash未提交修改，随后已纳入8d6b8f8ff；构建快照与随后发行工具提交并不要求相同。最终双仓推送提交由根代理交付报告与 Git 日志另行记录，不把提交成功代替上传或实机验收。

## 服务器基线、备份和首次克隆失败

只读审计时间为 `2026-10-29T03:39:57Z`（北京时间 11:39:57）。旧 API release 为 `20261025-onboarding-1f75fd5b5648`，旧活动 bundle 为 `47accd81d92265b93c243efc876cbd588e9f260ed8a8d7ff9e9afa1943ec9a9e`；数据库为 PostgreSQL `17.11`，ledger 34 项、应用 RPC 18 项，含既有排行榜 RPC。审计时 pending 为空，在线租约与近期心跳／会话聚合计数均为 0。聚合计数用于本次维护边界，不证明所有客户端进程都已退出。

维护流程先核对基线与 pending，再仅停止游戏 API，复核 pending 后备份游戏与支付数据库。支付服务和数据库进程不停止。私有 dump 的 SHA256 核对通过后，下载到本机内存并保存为 DPAPI 密文，实际解密回读与摘要复核成功，远端收到对应备份确认；明文未写入 Git 或知识库。

| 备份阶段 | dump 字节数 | dump SHA256 |
| --- | ---: | --- |
| 首次 v2，UTC `20261029T034813Z` | 5,147,229 | `fc21b16c363535984968b9888c0b6c20096e83ff5569ee21b15bcf9dc0d17c3b` |
| 最终 v3，UTC `20261029T035558Z` | 5,147,229 | `e7b7a0b882fc18293ce6e6ef8c83832d57fd97266ae84f424b9fbd1b3b3e83b7` |

首次 v2 在隔离数据库恢复阶段返回 `isolated_clone_restore_failed`，未迁移活动数据库。根代理随即执行 `resume`，实际回执为 `OLD_API_RESUMED`。之后只读诊断确认：同样的默认 Unix socket 连接返回 `peer_authentication`，显式 loopback TCP 连接成功；失败 clone 中业务关系数与 pgcrypto 均为 0。dump 另含 `CREATE SCHEMA public`，而新空库已有 public schema，下一次恢复还需处理该冲突。

修复使用新 v3 seal／stage，保留 v2 stage、失败 clone、原备份和恢复回执。恢复命令明确指定 `PGHOST=127.0.0.1`、`PGPORT=5432`；只对本次新建、名称匹配且经检查为空的 nonce clone，在 dump 确实创建 public 时执行 `DROP SCHEMA public`，无 CASCADE，不清理活动库或复用失败 clone。恢复保留单事务与遇错即停。修复经独立只读审查；本轮未执行数据库回灌式线上回滚。

## 最终 PG17 克隆验证与线上增量

v3 从最终私有备份创建独立 clone，真实 PostgreSQL 17 恢复、三项增量 SQL、精确配置同步和运行时探针均成功。`remote_validate-clone.json` 明确记录 `live_database_modified=false`、`actual_app_transport_ready=true`、`original_player_rows_unchanged=true`、`application_rpcs=19`、`synthetic_accounts_retained=0`。

新增 ledger 仅以下三项，旧 34 项和已发布配置分支保留：

| 增量 ledger ID | 目的 |
| --- | --- |
| `target/202610220001_human_spec_mode_admission.sql` | 配套真实模式准入合同，保留 release gate |
| `target/202610290001_archive_challenge_receipts.sql` | 新 challenge 原子奖励／response 持久回执 RPC |
| `security/harden_archive_challenge_receipts.sql` | 仅为新 RPC 配套最小权限 |

新增唯一应用 RPC 为 `archive_commit_challenge(text,text,bigint,jsonb,jsonb,text,jsonb)`。旧 RPC 签名与旧回执身份不改，已有 done 且 response 为 null 的历史不补写、不重抽。新 challenge 将真实 reducer response 与奖励同一事务提交；库存无需传入新 RPC，既有 `content_inventory` 不被覆盖。Python service、外置 PostgreSQL transport 的精确签名白名单、模式转换、完整不可变 bundle／CSV 和游戏端活动 hash 同批配套。103 个 gameplay stat 列均已存在，本次不新增列。

部署使用现役 18 RPC 审计结果做增量，未运行会覆盖现役排行榜授权的旧通用 hardening。上线前比较并确保应用 RPC 恰为原集合加新 RPC；原排行榜和 onboarding 权限保留。新配置仅增加 d573 分支，不替换旧 hash 分支、不增加兼容别名；被 release gate 禁用的模式仍不开放。

克隆运行时探针实际加载候选 Python 和 bundle Lua worker，走 command→prepare→worker→commit→resume，并覆盖：

- 可信 cold N30 会话，scourge 返回 `mode_not_released`；tower N30 波次 15 的真实 worker 进度保存。
- 绿茵奖励真实接受 10 积分，`response.rewards[]` 数量和为 10；首次持久提交后模拟丢 ACK，再次请求返回原明细，重复请求不再修改档案／属性／revision。
- 不相关库存哨兵保持 37；未满足社交领取资格时合法结算且奖励为 0，保留 skipped reason。
- 故意在 response 写入 trigger 中抛异常，嵌套 savepoint 验证整笔 archive／stats／revision／done 回滚。
- 专用 RPC 授权与拒绝直接 DML 的元数据检查；随后另用真实 `goufayu_app` 独立连接通过候选 transport 的完整 `ready()`，检查角色、白名单、RLS 和 DML 权限。

上述业务 RPC 探针使用 clone 的受控 owner 连接，并非冒充真实玩家或在活动库造奖励；独立 app 连接完成的是 transport readiness。探针账户、trigger 与函数在外层 savepoint 全部撤回。迁移前后比较所有原业务表行指纹，仅允许 ledger／配置表的既定变化，原玩家更新数为 0。此前 PGlite PG18.6 的角色实调与事务测试证据仍保留；本次追加的是生产快照隔离 PG17 验证，不宣称多连接竞争或真实玩家完整游戏验收。

实际激活再次校验最终备份及 DPAPI ACK、API 已停、pending 为空、候选 manifest 与原基线；同一事务迁移／同步／比较原业务行后提交，再以精确 CAS 切换 release 并启动 API。`remote_activate.json` 与 `remote_verify.json` 均为 ok：活动 release／d573 hash 正确，健康端口、数据库 ready 和 HTTP config hash 检查通过，ledger 37 项，应用 RPC 19 项，原玩家行未变，支付未动。

预备 safe release 为 `20261029-archive-d573588b64d2-safe`，保留旧 archive 公开源码和旧 47acc 活动指针，同时保留与新数据库权限匹配的 transport。该回退仅切代码，不恢复数据库或库存。本次未触发 safe 回退。新客户端须更新并重开旧局；不通过伪造旧 hash 别名延续旧客户端合同。

## 商城与支付同步范围

父 bundle 与 d573 的比较确认积分兑换目录有实际改动，完整新 bundle 和配套 CSV 已同步；现金商品金额、币种、物品数量、效果和权益合同未变。现金金色抽奖券的现役支付商品标题已经是“金色抽奖券”，金额 600 分；hosted checkout／订单标题按该独立支付商品快照生成。因此本轮保持支付 release `20261018-checkout-gcoin-v1` 与原进程不变，没有造订单、付款或支付部署。本轮证明的是支付进程与资料未被修改，不增加新的支付到账验收。

## 全量候选、门禁、保护与上传

本次从当前完整 runtime 输入生成生产源，不只是把少数存档文件覆盖旧包。保留动态依赖所需的 Lua、地图、模型、材质、粒子、UI 与声音；开发目录、测试 fixtures、工具、服务器、知识库和凭据不进入客户端候选。生产差异只定向移除开发 lobby 前缀，并保留正式入口、四账号测试门禁、联网禁作弊与当前 release policy。客户端签名候选原生启动时 `cheats=false`，debug probe 被拒绝。

184 个指定模块全部从本轮源重新保护，复用旧保护模块数为 0；825 份 Lua 语法检查及完整 runtime validator 通过，生成配置逐值语义比对通过。保护加载检查没有新增 io／os／debug 依赖，加载不改变玩法随机状态；耗时只是本地 Lua 解析加载测量，不作为 Dota 帧率证明。签名与逐文件 SHA256／MD5、VPK CRC／section MD5／whole VPK MD5 检查通过，私钥未复制到候选。Lua 保护与签名不等同于对全部运行资源进行密码学加密。

实际包包含 6,695 项签名资源，payload 3,777,720,828 字节，索引加四个外置分卷总计 **3,777,996,435 字节（约 3.52 GiB）**，满足低于 10 GB 的包体目标。生产源 manifest 的摘要与保护后的最终签名内容摘要不同，不能互换。

| VPK 文件 | 字节数 | SHA256 |
| --- | ---: | --- |
| `3824360109.vpk` | 275,607 | `ccfcc45828f8ce758f43cb4749dd90edf33ed8659a1cdc259bfdc9f762786109` |
| `3824360109_000.vpk` | 1,071,697,318 | `87b335f40a4fe133b7901a70e5b49a6d634a08b078259ba28ddb792208fcb4f2` |
| `3824360109_001.vpk` | 1,071,529,200 | `3046a3ae720dd0e80950e14562bf8c8c556f095a4ab068773d7f34dd78ca2b49` |
| `3824360109_002.vpk` | 1,072,379,215 | `e03f21542c7c283460e21c60c6350587a8b100b9ab5789d7cfa2ebe41fd1206a` |
| `3824360109_003.vpk` | 562,115,095 | `a951c2374339e7007d350fe22ae5600f1d27169d03ee41f6b6ae0e2bedfc7f6d` |

`upload_preflight_exit.json` 为 exit 0／`VERIFIED_NO_PUBLICATION`；随后 `upload_apply_01_exit.json` 为 exit 0、uploaded true。实际 apply 最终记录时间 `2026-10-29T04:09:18.045839+00:00`（北京时间约 12:09:18），序号 2026102901、条目和内容摘要均匹配，状态为 `SUBMITTED_UNLISTED_PENDING_DOWNLOAD_AND_NATIVE_TEST`。上传日志 SHA256 为 `edd1fb3643da42d5dcc19be3762f86c2ed1226636300859767671ced57585ff6`。构建／assembly 早期记录的 NOT_RUN／尚未上传状态保留原样，后续上传状态以 apply 回执为准。

## 官方重新下载结果

Steam上传成功，官方重新下载在内容分发阶段返回 No Download Source／No connection to content servers；当前未取得新版完整下载回执，不能把新远端manifest当安装成功。

远端已发布manifest字符串 `1297565240173722470`（Steam上传日志及下载manifest HTTP200），它不是新版完整安装成功证明。单次SDK下载返回Failure，未修改canonical journal／ACF，不重传、不伪造成功。脱敏诊断：`output/release_archive_20261029/download_failure_diagnosis.json`。旧2805安装与本轮未完成staging保留，后续仍需同一冻结验证器的真实3406／全包验签回执。

首次仅因空间不足在SDK初始化前拒绝；清理本轮自有临时smoke副本后通过预检，实际下载才遭遇上述内容链路错误。第二次显式尝试返回 `shop02_subscription_not_stable_for_refresh`，在订阅／下载前停止，未发出第二次DownloadItem。Steam随后自动排队全workshop更新，未由本任务修改队列、ACF或网络设置；日志不能区分远端源故障与本机DNS／代理链路问题。保留签名候选、原失败日志和历史包，不删除Steam下载状态来强行制造新回执。

为保留同一冻结验证器的空间守卫，本轮仅对自己新建生产源副本内纹理做普通NTFS压缩（不使用WOF、链接或删除），释放635,259,316字节；所有触及文件前后SHA和逻辑长度一致，完整签名候选未改。记录位于 `output/release_archive_20261029/source_ntfs_compaction.json`。

下载预置 pins 已记录在 `output/release_archive_20261029/download_pins.json`，含构建报告、完整输入、保护报告、签名 metadata 和关键门禁源码摘要。该文件是验证预期，不是下载成功回执。

## 原生验收范围与后续实机项

`native_smoke.json` 为 `PASS_NATIVE_SIGNED_PRODUCTION_STARTUP_ONLY`：独立临时 addon 选中本轮签名候选，服务端激活、addon／modifier registry 初始化、Panorama 布局加载成功，无 script runtime／VScript 错误；6,695 项签名资源与 184 个保护模块匹配。该测试在身份认证前完成，保持禁作弊；之后只关闭本轮自建进程并清理自有临时 smoke 副本，外部签名候选保留。

该回执明确 `real_account_grants_verified=false`、`multiplayer_verified=false`、`challenge_ui_visual_acceptance=false`。因此仍需本轮新安装包的新局实测四楼落点、单行技能／hover、多人同时召唤时拥挤寻位、完整击杀、逐人资格／每日上限与真实云端奖励提示；不能将隔离数据库探针、旧版本真人记录或本轮启动成功写成这些项目已通过。

## 可复核证据路径

下列路径均相对 game 仓库；运行输出不加入 Git，本文保存脱敏摘要，凭据与备份密文另行保管。

- 基线与差异：`output/release_archive_20261029/server_plan/live_audit.json`、`commerce_diff.json`。
- 首次失败与恢复：同目录 `candidate_v2/remote_backup.json`、`candidate_v2/remote_resume.json`、`clone_restore_connection_diagnostic.json`、`clone_restore_diagnostic.json`。
- 最终服务器：同目录 `candidate_v3/plan.json`、`seal.json`、`remote_prepare.json`、`remote_backup.json`、`remote_validate-clone.json`、`remote_activate.json`、`remote_verify.json`；`protected_backup.json` 证明最终 DPAPI 密文回读成功。
- 服务器工具：`tools/archive_release_20261029/server_prepare.py`、`server_deploy.py`、`server_remote_operator.py`、`server_runtime_probe.py`、`test_server_release.py`。v3 修复后 8 项离线工具回归通过；实际 PG17 结论来自上述 clone 回执。
- 候选与上传：`output/release_archive_20261029/workshop_build/{reviewed_plan,production_manifest,assembly,package}.json`、`upload_preflight_exit.json`、`upload_apply_01_exit.json`、`upload_apply_01.jsonl`、`download_pins.json`。
- 原生启动：`output/release_archive_20261029/native_smoke.json`、`native_smoke_engine_frozen.log`、`native_smoke_cleanup.json`。冻结 engine log SHA256：`a4e2e706db6c3c06134d5f94f085d1e5c3ce1766dcf579a154b113011bb84136`。

| 最终服务器回执 | 文件 SHA256 |
| --- | --- |
| `candidate_v3/remote_backup.json` | `943f0cd8570a581839b03e50815f8e75f86f2b72838b5e8db12b12ce221038e7` |
| `candidate_v3/remote_validate-clone.json` | `3d206faf172e6c884ab5e3b977d732c473b03bf4d526aacfe65422b23e851ef0` |
| `candidate_v3/remote_activate.json` | `92443d3432cef07647f71dab91cc3e262c192f3fcca863f8a723a29454287a58` |
| `candidate_v3/remote_verify.json` | `1dbe9d5b18e066031af9b320f012935ce059f0706de1c3f187762c2e1dbb1024` |
