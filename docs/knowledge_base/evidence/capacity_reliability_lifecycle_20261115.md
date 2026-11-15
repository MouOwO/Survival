# 容量整改：结算生命周期候选（2026-11-15，进行中）

本轮仅本地源码和原上海隔离测试机诊断。没有部署正式后台、更新游廊、采购或回收新的旧数据。用户确认的顺序仍为：结算可靠性、后端调用和 CPU 成本、同源码独立硬件对照、人数阶梯及真实 2000 人两小时验证；当前不能称为全部完成或容量达标。

用户确认旧 2 核 4GB 机器 `47.110.238.248` 保留正式服务。只读盘点发现其仍运行 WS4、网页登录、支付和数据库，后续不施压、不停服；另准备短期独立试机方案，新增资源费用仍须具体确认。

## 已确认的问题和候选

游戏 `online_time_service.lua` 原错误回调调用成功收尾，将未知结果的最终请求标记为 CLOSED。候选仅在 `ok=true` 后收尾，保留同一请求 ID 和会话，最多三次发送；旧代、旧尝试、换账号和换局回调失效。周期请求失败耗尽时允许独立最终请求，须配套本轮数据库生命周期保护；本候选尚未向玩家交付。

压测 `Player._stop_session` 原先在 finally 中无条件释放身份并清除凭据。候选在最终结算确认前保留凭据和最终请求 ID，释放失败也保留重试能力；未登录的身份仍不虚构在线会话。该修正不会把失败统计改成成功。

原 SQL 的迟到旧会话 final 会先把当前行覆盖为旧会话，再删除它。独立新增的 `database/20_checkpoint_lifecycle.sql` 候选使用 `(account_id, session_id)` 主键记录关闭状态，在同一账号锁内阻止旧会话重新打开、迟到 final 覆盖新会话，并将新幂等回执绑定 session/final。不修改既有 10_schema.sql、不增加应用直读表权限、不更换 RPC 签名。新选项默认关闭，仅新建隔离压测目录可启用。

## 已执行验证

- 实际 Lua 5.1 模块：9 项故障场景通过；旧源码负对照可复现失败即 CLOSED。
- 实际 Python Player：5 项退出、凭据和请求 ID 场景通过；结算回包必须显式 `ok=true`。
- 原上海 ECS 新建独立 PostgreSQL：16 项检查通过，包括旧版负对照、乱序 final/periodic、关闭后重放、请求绑定冲突、真实计时和奖励、8 路已存在回执并发重放、无重复计时/奖励、RLS 和原应用 RPC 权限。首次写入并发另待补测，不能用缓存重放代替。
- 数据库容器网络 none，512MiB/0.75CPU，无公网监听；正常退出码 0、无 OOM，数据和证据保留。该功能诊断没有模拟数千在线，也不构成容量验收。

证据根：`D:/Survival_本地工具/runs/capacity_reliability_cpu_20261115_01`；原生结果：`native_lifecycle_probe_01/native_result_receipt.json`。SQL 父摘要 `1f30d656ffa7d70b31d3fca59d90b92326ee48c25502de825902c93856d5cca7`，候选摘要 `4e5fa9f37473c0b576df5d942239cd460a5ab1f182591cde12b3bbaef5c376c5`。没有原始认证或支付凭据。

## 成本和未完成项

游戏每会话 O(1) 状态，N≤4；健康请求无新增重试定时器，失败最多两个按会话索引的一次性任务。成功回包增加一次账号核对，换局清空旧代；不增加帧扫描。数据库初始化一次 O(当前在线行数) 回填，正常请求固定次数主键查找、每账号锁；生命周期空间 O(历史会话数)，保留期尚未设计，不自动删历史。

后续原生补测已完成：22 项（包含前述 16 项），新增首次 final 的 8 路并发、首次建号并发、旧版回执和实际直读拒绝，均通过。独立第二个数据库正常关闭，首次探针的数据没有改写。见 `native_lifecycle_probe_02/native_result_receipt.json`。

性能候选 `reset-filtered-combined-v1` 将原有两条完整权限检查合并为一条 SQL，保留每次 RPC 检查，不缓存授权结果。保留原过滤/重置候选与完整源码回放证明；新选项默认关闭。原上海新建无网络 PostgreSQL 小库、真实 guard 方法、私有 Unix socket、ABBA 交替各 20 个样本（包含事务成本）：原检查均值 4.352ms/中位数 3.969ms，新检查 3.061ms/2.723ms；本样本均值约降 30%。两者对新增表权限、数据库 CREATE、错误函数 search_path、额外函数 EXECUTE 全部拒绝。该结果不等于完整业务延迟降 30%，也不能外推 2000 人吞吐。见 `combined_guard_native_01/native_result_receipt.json`。

用户已授权精确旧合成库 `d5fafef2c424d463406cc091e661e5e8/pgdata` 及本轮后续新建、已正常关闭、无引用且完整备份恢复验证通过的合成库展开副本回收。指定旧副本已核验并回收；约 257MB 压缩备份、源码、日志和回执保留。其他历史数据库没有新增删除授权。见 `storage_archive_01`，后续仍逐次记录实际路径和结果。

尚需：完整 HTTP/Lua 业务与 SQL 后验、配套客户端有界恢复、实际分段成本对照、独立硬件试机以及人数阶梯长测。生命周期表能阻止已记录或已关闭的旧会话；从未到达数据库的旧会话首次请求与一个真正新会话，单凭现有八参 RPC 的无序 session_id 无法完全区分，跨新局绑定还需补齐。游戏结束后进程被终止时，本地内存重试不能保证继续执行，三次重试不能写成进程外持久结算保证。

## 09:20 UTC 之前的完整业务事实

同源码 `c04cecd0d7ee26607956dae81c7edbb0111d0cf3`、10 万成熟合成存档、100 人、240 秒阶段、2 人/秒入局：

| 指标 | 生命周期修复基线 | 加合并完整权限检查 |
| --- | ---: | ---: |
| HTTP 请求/原始失败 | 2058 / 0 | 2096 / 1 |
| 业务流程失败 | 0 | 0 |
| 实际持续业务共同区间 | 159.0 秒 | 163.8 秒 |
| 正常资料 HTTP P95 | 5600ms | 4800ms |
| 周期结算 HTTP P95 | 8800ms | 6100ms |
| 集中退出流程 P95 | 24000ms | 25000ms |
| 最终退出完成 | 100/100 | 100/100 |

两轮 SQL V5 均完整执行 50 次、24 个聚合，在线会话/待操作/异常/待出站队列和四项生命周期异常均为零，奖励关联和 14 张受保护交易表检查通过。正常停服、数据库停机、完整采集和 SQLite 退出核对完成。两轮均 `FAILED_FIXED_BUDGET`，延迟不达标；第二轮原始 HTTP 失败保留，业务流程最终成功，不据此宣布容量通过。随机行为不同，一组对照不足以宣称确定吞吐倍率。原始统计含 WORKFLOW，不能把 2629/2672 总事件数误作 HTTP 请求数。

基线分析器最初漏把新增 SQL 文件计入精确消费者集合；原失败工具与日志保留。独立修正版将其来源和目标明确加入 BINDINGS，重新验证全部来源、HMAC 活跃、延迟和 SQL；没有移除 SLA 或数据门禁。基线最终报告在树外 `capacity_process_topology_20261114_01/reliability_controls_v14_20261115_02/baseline100_readonly_reanalysis/analysis`；对照报告在同工具根的 `reliability_lifecycle_combined100_20261115_01/analysis`。

真实 HTTP 回包丢失验证也已通过：独立两账号库使用明确的合成历史进度 590 秒和 65 秒心跳夹具跨过真实 600 秒奖励阈值，服务器实际执行 SQL、Lua 存档和一份奖励后，客户端故意丢弃第一次 HTTP200，再用完全相同 final 请求恢复。7 项检查通过，响应档案和 grant ID 一致、没有重复奖励、另一账号不变、所有会话和出站队列最终完成。正常关闭，非容量测试。首个未设置历史进度的探针未跨过奖励阈值，失败结果原样保留。见 `ackloss_native_02/execution_receipt.json`。

执行计划假设的独立原生小库检查：保留内部计划的资料读取均值 9.71ms，原 DISCARD ALL 为 9.32ms，未见稳定收益；103 字段默认初始化样本有差异但不足以归因整个业务。会话隔离、临时对象、锁、序列及当前权限验证通过。本轮没有合入修改连接重置语义。见 `reset_plans_native_03/native_result_receipt.json`；计时在 reset 之后开始，不包含 reset 自身成本，不能写成完整 RPC 成本比较。

后续新增 `--checkpoint-drain single-profile-v1` 为默认关闭的独立候选：精确绑定服务器及未改动的实际 `ArchiveService.profile`，只删其前面重复的一次 `drain_online`。3 项可逆来源/篡改检查和 5 项实际方法编排（模拟 RPC）通过；真实 HTTP 新候选验收与人数阶梯仍待。初始化范围证明和完整授权每次保留；没有减少实际待处理项的 resume/commit。

用户随后提出请求处理期间加锁的建议。源码核对：checkpoint、奖励和 archive 提交均已有按账号的 stats→player 锁序；奖励还有 grant advisory transaction lock。事务提交成功后才从 RPC 返回，异常回滚；跨 Lua 计算不长持数据库行锁，而由 `archive_commit` 校验 profile_revision、`finish_prepared` 最多四次重读重算。现有机制能防止重复奖励和旧数据覆盖；同账号不同操作并发的实际 HTTP 补测另列待办，不把已有同 ID 重放测试当成不同操作竞争测试。两轮 100 人 DB 锁等待采样峰值均为零，当前不能把尾延迟归因于锁竞争。

## 同账号并发与回包防护补测

`a4463c111781040cd943df394f91beab647dbb9c` 的单次 profile drain 候选在独立两账号真实 HTTP 环境通过 11 项检查、41 次实际 HTTP（12 次来自独立并发 transport），原始 HTTP 错误、无效响应、未完成交换均为零。同一账号 2 笔及 4 笔不同单抽并发时精确扣券 2/4 张，再并发重放相同 ID 不再扣券，另一账号不变；丢 ACK 后同 ID final 恢复并取得同一份真实奖励的检查也全部通过。正常停止，证据 `same_account_native_03/execution_receipt.json`。前一轮探针因报告聚合遗漏 mode 参数而失败，原结果保留，不计作通过。

已有保护分别解决不同问题：数据库按账号行锁跨进程串行关键写入，请求 ID 与持久回执防重复执行，profile revision 冲突校验防旧计算覆盖，客户端 `player_profile_service.apply_snapshot` 的账号/当前局/代际与账号版本高水位防旧回包覆盖新视图。事务在提交/回滚后释放锁；不把锁一直占到网络 ACK 返回，不新增全局互斥锁。上述功能样本没有证明任意规模容量或所有故障模式。

## CPU 与实际数据库往返成本补测

原机独立纯计算进程依次为 1/2/4/1 路，各自 4 秒，分别固定到不同 guest 逻辑 CPU，总吞吐约为 721.1/661.8/652.0/650.6 万操作每秒；4 路总吞吐没有明显增加。guest 显示 2 个 core/每 core 2 个 SMT sibling，纯计算探针所在的 Linux 可见祖先 cgroup 未发现 CPU quota 限制（实验数据库仍有显式 2CPU 配额）。不能由此断言具体宿主调度原因或只有一个物理核，也不是 SQL/HTTP 容量；仍待独立实例对照。见 `cpu_process_scaling_01/verification_receipt.json`。

从两份已关闭 100 人日志只提取数字白名单：基线/合并检查的周期 checkpoint 样本均值分别约 2218/1037ms，其中全部 RPC wall 为 2096/974ms、连接池等待 1174/431ms、projection+serialize 15/9ms；集中退出样本 RPC wall 为 5331/5987ms、连接池等待 3720/4406ms。采样不是随机样本或路由 P95，嵌套阶段不能相加推导收益。普通无奖励 checkpoint 原有 7 RPC、含奖励的样本均值约 8.3，单次 drain 候选减少其中重复的一次 archive_online_pending。见 `paired100_safe_timings_01/RPC_cost_receipt.json`。

独立两账号、固定 20 次实际 profile 直接调用的 cProfile 线程 CPU 诊断已通过：总 wall 945.590ms、带 profiler 的 Python 线程 CPU 369.542ms、所属 PostgreSQL cgroup CPU 564.168ms；每次实际为 ensure/defaults、online pending、archive pending、profile 四个 RPC，存档指纹不变、会话关闭、服务正常停机。它排除了 HTTP 授权/上下文/投影和传输，profiler 有自身开销，数据库 CPU 含后台工作；不能当作未采样完整 HTTP 的 CPU 占比或容量。见 `components_native_02/execution_receipt.json`。第一轮诊断写死了未安装的 Lua5.1 路径，无耗时样本，证据保留；修正版用实际 resolver 和已核对的 Lua5.3 二进制摘要。

## 额外回收授权和阶梯当前状态

本轮 5 个已正常关闭的合成库已逐库压缩、实际恢复核对全部字节/UID/GID/权限/mtime 后回收展开副本；源、日志、回执和压缩备份保留。用户又明确授权精确历史库 `b4c226b345af210661835a197e8c1a52/pgdata`，约 0.94GB 展开副本已在约 191MB 备份实际恢复核对后回收，原失败 2000 人测试证据未删除。最终可用约 13.37GB。仅这一个历史库获得新增授权，不扩展到其他历史数据库。见 `storage_current_round_batch_01` 和 `storage_historical_b4_01`。

200 人首个新候选因导入过程磁盘安全检查停止，未发压；第二个新候选启动时 SSH 连接失败，只读核对确认无数据库/容器/端口/进程启动。两次失败保留，不能算作 200 人业务压测结果。第三个新候选 `91d9634b69e6e761b14b8350de240058`（manifest `e8df0dcaa0e1ed35a598eaf66bfaaca1cc02521365f6d83ed75fbb4c6e5c9df5`）已完成发压、正常关闭、完整采集和 SQLite 终态核对。最终 HTML/native final 口径 HTTP 3671 次、611 次失败（16.64%），其中 476 次明确 frontend_busy、135 次未取得有效 HTTP 回复。周期 CSV 末次刷新并非最终窗口，不能用其 3633 次代替最终计数。收尾函数完成 110/200、失败 90；SQL V5 实际执行 13 次、6 个聚合后因在线会话 4 而拒绝，pending/outbox/errored 为 0，但后续奖励关联与受保护交易审计未完整执行。

500/1000 短阶段及 2000 的 8000 秒请求阶段已离线准备，2000 仍要求真实共同业务活跃至少 7200 秒；不能以启动虚拟用户数代替在线人数。四套源绑定离线校验全过，200 阶段已关闭，后续三档实际执行仍待空间恢复后启动；新实例实际按量报价及独立硬件试机授权仍待。当前后台与游廊均未部署，无采购。


200 的严格 stage 因 final_statistics_mismatch 未确认，随后分析因 progress_server_ready_not_confirmed 停止；原失败不改为通过。最终 HTTP/Wire 数和普通 WORKFLOW 计数可对齐，但 compact/catalog/room/recovery 部分门禁未对齐；签名 status 71 次中 46 次验证成功、25 次失败，采样 server-marked ready 峰值 184，没有证明 200 人共同持续业务活跃。167 个 actor 被隔离后不能继续当作活跃玩家。

复用冻结分析器独立核对来源与物理关闭后，一次离线 69 个完整进程区间汇总：前端/后端自身 CPU 均值约 0.664/0.680 guest core，PG cgroup 均值 1.506、峰值 1.709 core，PG 内存峰 1.384GB、OOM 0。PG 在 3440 个配额周期中 585 个发生限流，累计 throttled 19.851 秒；这不是墙钟节流百分比。全主机采样 CPU 均值 87.46%、峰 95.14%，DB 锁等待采样峰 0，idle-in-transaction 采样峰 7，5秒 TX 峰 1.164Mbps（含 SSH，非计费或连续瞬时峰）。尚不能据此断言具体共享宿主原因、所有 HTTP0 均为丢包，或外推4000人的流量。见 `single200_factual_01/{factual_receipt,CPU_by_role_receipt}.json`。

本轮200及两个新小诊断库均已完整备份并实际恢复核验，后续按既有授权回收展开副本，保留失败数据的全量压缩副本。另精确历史合成库 `e8ff519634944f2558e505f5f193f386/pgdata` 约1.09GB也已只备份（约246.5MB）、实际恢复核对，不含删除授权，原库保留；更高阶段需按当前实际空余量安排，不降低12GB导入余量门禁。见 `storage_for_higher_stages_01`。


## 故障恢复与导入空间补充验证

独立两账号真实补测：writer 在实际 SQL 提交后、Lua/archive结算前以预定77码退出，另一实际HTTP后台进程成功从持久outbox恢复。8项检查、26次HTTP通过且原始错误0；同finalID重放不重复奖励、不再次改变存档，另一账号不变，最终会话/待操作/出站队列均完成。只结束本测试新建的writer子进程，API/PG均正常关闭。不是PostgreSQL断电/整机灾难恢复或容量证明。见 `process_crash_native_01/execution_receipt.json`。

备份文件元数据盘点：约1.09GB展开库中，业务数据目录约435MB、WAL654MB。独立新两账号库以39次有界WAL切换复现后，仅临时调整检查点参数，由PG自身将WAL654MB→134MB，随后原GUC、postgresql.auto.conf字节摘要和新连接设置全部恢复；8项检查、12次真实HTTP通过。fsync、同步提交、full_page_writes及wal_level均未关闭/改变，没有手动删WAL或更改任何历史库。见 `seed_storage_breakdown_01`、`seed_wal_native_01`。

新增默认关闭的正式工具选项 `--seed-storage wal-checkpoint-v1`：只允许新的mature-v1合成库，独立核对固定PG容器/镜像/挂载与未seeded标记、started导入记录、原始默认配置；在导入期间每批做O(1)LSN元数据查询，累计32MiB WAL或10秒单调时间时做检查点。初始化一次独立admin连接和两次容器检查，保留状态O(1)+9个GUC，批量导入额外成本O(批数+检查点数)，稳定业务/监控阶段新增SQL与定时器0。保留12GB空余量、行数/3GB数据量/900秒导入门禁和全部实际数据检查，ready前精确恢复设置与配置文件，并以新连接验证。失败恢复另有5秒预算，和原5秒advisory解锁合计在所选模式中明确报告10秒，baseline仍5秒。

候选实际类故障回归通过：35种篡改/孤立元数据拒绝、错误数据库/已seeded标记在ALTER前拒绝、非事务配置写入后失败恢复、查询前后截止、独立恢复查询预留、计数一致与baseline零额外SQL/原12GB门禁。真实10万存档接入仍待；这些结果不代表更高人数容量通过。为后续同源对照将重新绑定候选，不启动已过期的operator来源。`e8ff…/pgdata`回收仍未授权且原库保留，只有新导入模式实际满足余量后才能不依赖该授权继续测试。

配置回收与恢复语义参照[PostgreSQL17 WAL配置](https://www.postgresql.org/docs/17/runtime-config-wal.html)、[ALTER SYSTEM](https://www.postgresql.org/docs/17/sql-altersystem.html)与[CHECKPOINT](https://www.postgresql.org/docs/17/sql-checkpoint.html)；此选项仅用于离线合成数据导入，压测阶段恢复原配置。


## 16:45 UTC 前的后续实测与集中退出修正

单次profile drain的旧500/1000短测及2000目标长测已完成并失败；2000阶段73445个完成HTTP中5582失败，另3个取消/未闭合交换单列，最大实际有效业务人数148、2000共同活跃0秒。CPU采样均86.35%，可用内存最低约6.23GiB、未见增量OOM；不能按启动用户数宣称容量，也不能把入口拒绝当作偶发网络丢包。所有隔离进程已正常关闭，失败数据经实际恢复核验后只回收已授权展开副本，备份与证据保留。见single2000_factual_01及closed_memory_CPU_evidence_03。

默认关闭的idle-v1资料上下文候选保留完整每次权限检查、先online再normal待处理和实际profile流程，将健康资料4次RPC减为2次。独立真实PostgreSQL/HTTP/Lua两账号43HTTP/12项、ABBA160次直接profile对照通过；薄/密存档直接调用wall样本均值约降35%/33%，不是全HTTP或人数倍率。SQL计划实测按账号索引访问；密存档仍过滤该账号512条历史，不能把LIMIT64写成仅访问64行。运行来源3fcb0a2c。

新100人/10万成熟存档短测2162HTTP零错、100完整退出、SQL50执行/24聚合全过；签名共同活跃185.865秒，profile/周期/final P95约220/370/7000ms，预算优先门通过、旧1.5秒final严格门仍失败。只是短测，不是长期2000容量。新200人5369完成HTTP/66个frontend_busy原始错误；196/200完成退出，残留4在线会话，SQL后验未完整通过；profile/周期HTTP P95约280/400ms，final工作流P95约12秒。37笔最终结算遇忙，33笔恢复，4笔在三次上限耗尽。失败原样保留，尚未启动500及更高人数的新上下文候选。

新增可选admission-busy-v4只扩展final、确切frontend_busy/backend_busy的有界恢复，Locust最终请求最多6次，其他路由仍3次，共享30秒单调期限且保留所有原始失败、SQL和SLA。游戏调用方只对同类明确busy final扩为6次，同一payload/请求/账号/会话/代际保持；其他错误仍最多3次，忙碌退避每次1秒。健康路径新增HTTP/调度0，每会话O(1)，N≤4，每失败会话最多一个索引一次性任务，不扫描玩家或场景。游戏调度基于game time，不宣称进程外持久保证或整流程30秒墙钟截止。实际Lua13种场景、Locust实际方法12组和107项断言及5项路由账目上限/篡改检查通过，旧版第四次busy前耗尽的负对照复现；两次测试脚手架依赖错误保留。新候选真实200复验、后续阶梯及独立硬件对照仍待，未部署正式后台/游戏/游廊、未采购。

用户所见“内存使用率”下安装插件按官方文档为云监控采集Agent；它采集内存/磁盘和告警，不增加算力。官方说明安装及基础监控免费、通常无需重启；本轮对照期间未安装。见https://help.aliyun.com/zh/cms/cloudmonitor-1-0/user-guide/install-and-uninstall-the-cloudmonitor-agent-for-cpp。
