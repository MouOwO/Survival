# 2026-11-14｜容量自主优化：工具、原生微基准与下一轮门槛

本记录是正在进行的容量任务阶段交接，正式后台未部署、游廊未更新、未采购资源。继续使用既有上海4vCPU/8GiB独立测试机和Windows发生器，月预算上限3000元。本轮新增隔离源码候选、发生器与来源门禁；尚无100人、4000人或成熟账号4小时通过结论。

用户本轮明确授权的计划记录在树外`survival_capacity_autonomous_20261113_01/autonomous_plan_receipt.json`：开始于2026-11-13 15:09:36 UTC，目标10小时、最长15小时；时间预算不等于验收通过，也不生成采购、正式部署或工坊发布授权。

## 仍未通过的真实40人基线

继续沿用[G40完整记录](profile_pre_read_20261113.md)：10万合成薄档案、40活跃、PG2CPU/2GiB、HTTP32/PWA48/DB4/Q32/等待2秒。2249次HTTP零错、40完整清理，读档/周期/final分桶P95为630/940/11000ms，final原始最大10738ms。**事前10秒final目标仍失败，不能以零错误、原始Max或局部未收齐样本改写结论。**

本轮计划继续独立报告原严格门槛；预算优先目标为读档P95≤1000ms、周期≤1500ms、正常final完整workflow≤10000ms、HTTP/wire零错、所有账号清理完成，不降低旧门槛。新workflow含客户端后续读取和调度等待，不能与旧单条HTTP混称相同样本。房间结束与全员同时结束压力须分别报告。

## 已完成的工具及局部优化

### client-v2发生器

`--client-workload client-v2`按实际公开奖励CSV绑定ID、版本、enabled/permanent、数值范围及SQL返回的UUID。非空有效grants响应触发一条真实标记的profile HTTP，再结束checkpoint workflow；重复grant ID也保留实际客户端会再次读取的行为。读取失败不重发mutation，释放仍执行。

finalization从`test_stopping`意图时刻计时，包含等待on_stop调度、checkpoint、必要grant后续读取和release；HTTP、WORKFLOW、ASSERT分别计数，不能用混合事件总数冒充HTTP数。默认legacy路径保持。19项定向检查含本机随机端口真实HTTP/生产wire解码、Lua校验器公共向量、CSV绑定及Locust聚合；尚未代替上海同版真实业务或Dota验收。

定义索引初始化O(D≤256)，最多8个冻结配置；单回包校验O(K≤128)，固定指标和有界grant集合，没有逐用户/历史全量扫描。额外profile读取会增加真实负载，不能把旧发生器结果直接用于新协议容量认证。

### 同一checkpoint初始化证明

`checkpoint_initialization_scope_patch.py`只在原checkpoint HTTP分支建立新的私有词法ContextVar。证明绑定应用对象、线程对象/ID、active生命周期、数据库账号及类型敏感默认值快照，finally清空并reset。普通`_ensure_gameplay_stats`始终真实RPC并返回当前row；仅无row返回用途的`_initialize_profile`可跳过已成功且匹配的重复初始化。

不复用profile、奖励、角色/权限结果或跨请求账号缓存；账号/session/request/final仍按原顺序验证。非平面、非有限、超512字段、异常返回/失败RPC、默认值或出站快照变化均回到原RPC，不新增业务拒绝或自动重试。保留两轮各64项drain、pending恢复、最终fresh profile、VIP/排行榜与pure/standard投影。

18项真实冻结函数/线程/ContextVar及随机loopback HTTP处理器检查通过：常见正elapsed路径由G的10→9RPC，零待办8→7；generic ensure调用两次仍执行两次。覆盖cold/existing、跨请求/账号/应用/线程、过期复制context、类型与signed-zero、故障退出、128项两批及尾部、真实包装器和grants。RPC/DB状态及Lua settle结果为fake，不是原生PG或服务器容量测量。

103字段每HTTP固定3次快照/309字段访问，时间O(M log M)、空间O(M)，M≤512；无按注册账号规模增长的状态。局部Python1000次103字段快照wall均约24.36µs/次；仅说明本机局部成本，Windows CPU计数粗粒度的0不代表零成本。只允许已审SQL56467cf6…/600eb5d3…；不承诺活跃请求期间管理员删行、热DDL或未来函数增加副作用时仍等价。

### SQLite限流清理候选

`--frontend-rate hot-rate-v1`保留每次持久计数UPSERT/SELECT/commit、超限先提交再429和实时身份/过期/撤销查询，只增加`limits(bucket)`索引及每Service的成功清理分钟水位。原同分钟100请求的100次过期DELETE变为1次；原生SQLite8线程200请求仍50成功/150拒绝。4项原生SQLite检查及6项来源绑定检查通过，未改变WAL、连接拓扑、认证或PostgreSQL合同。

同分钟维持索引查询/更新，分钟变化仅一次处理过期E行；索引初始化O(L log L)，保留一个整数水位，无后台线程/定时器/账号缓存。倒拨时旧bucket可能延迟清理，失败不推进水位；不是磁盘保留、Linux fsync延迟或线上吞吐已改善的证明。

## PostgreSQL四臂：原始失败与追加审计均保留

独立DB-only库run `9d8e372f07c6ba3f0c38b489bdb325c9`，原G源码`33dc243e…`、SQL600eb5d3…、PG2CPU/2048MiB，只seed2合成账号并ANALYZE，不启动API/monitor。上传、plain-JSON容器身份/镜像/预算核验、前后marker及所属ID停止入口均独立绑定；停止状态以本轮真实stop回执为准，不能沿用旧G已停的历史记录。

四臂保持原SQL、每RPC角色和21函数检查、commit/未知结果/失败淘汰合同。baseline有5次显式cursor.execute；reset-v1首次物理连接验证5GUC的setting/reset_val/source/unit/身份后，保留全DISCARD而省重复恢复SELECT，暖连接4次；guard-v1合并两项现场guard为一条同快照查询；principal-v1同时采用两项，暖连接3次。commit另计，配置来源证明不是授权缓存。

v5真实执行35种权限/DDL场景×4臂，并完成会话污染、故障、deadline及微基准。8张业务表前后相同、剩余session0，但原安全元数据raw hash不同，原回执保持`NATIVE_NOT_CONFIRMED`/`restored=false`，没有改成通过。

随后两份离线语义审计定位到一个函数的ACL数组条目顺序：相同grantee、grantor与权限仅顺序不同，其余安全字段不变；重建得到原初精确摘要，追加审计`semantic_safety_equal=true`，审计SQL写入0。**语义审计与原字节门禁失败并列保留，不改数据库去迎合摘要、不覆盖v5原失败。**

原始四臂每臂仅160次、并发4，不能当小时级稳态、HTTP或容量验收。追加平衡阶段为3轮正反次序、每臂480次、合计1920次SELECT1 ready微基准；该阶段自身metadata/data前后相同、session0：

| 臂 | 显式execute/RPC | 合计RPS | 中位ms | P95ms |
| --- | --- | --- | --- | --- |
| baseline | 5 | 87.92 | 42.63 | 64.85 |
| reset-v1 | 4 | 89.62 | 40.65 | 66.81 |
| guard-v1 | 4 | 74.19 | 48.00 | 76.82 |
| principal-v1 | 3 | 87.62 | 39.43 | 68.87 |

合并guard没有确定总体收益，execute减少不等于性能通过。该阶段先选择较小的reset-v1＋ensure-scope＋frontend，再继续独立审阅下面的候选B。含原生故障验证的四臂也不能证明成熟账号、HTTP/SQLite/Lua、4000人或4小时。

## 后续候选B：完整过滤guard的原生边界通过，macro仍待

新`reset-filtered-v1`仍保留两条独立权限检查，只在角色SQL中将相同用户namespace条件及relation/function候选先MATERIALIZED，再求原owner、表/列、sequence、PUBLIC/继承及函数权限谓词。表类型r/p/v/m/f、序列S与所有用户函数保持，非白名单扫描不缩成21项；第二FUNCTION_CHECK、Python函数和中间deadline未变，没有跨RPC授权缓存。仍需扫描目录并物化候选，不能称O(用户对象)或O(玩家)查询，也不能保证未来固定提速。

新的真实两臂回执为`FILTERED_ROLE_NATIVE_TWO_ARM_PASSED`：35种权限场景×2臂、selected会话污染/GUC、真实写入及commit/reset/close故障和deadline均完成，raw元数据前后一致、8表数据一致、session0。这是独立新回执，不覆盖前述v5的raw hash失败或语义审计。

PG仍2CPU/2048MiB、4连接/Q32/2秒；平衡微基准每臂480次、合计960次SELECT1：

| 臂 | RPS | 中位ms | P95ms | Max ms |
| --- | --- | --- | --- | --- |
| 原baseline传输 | 81.99 | 43.24 | 79.40 | 254.72 |
| reset＋filtered候选B | 94.44 | 35.98 | 61.02 | 386.29 |

候选有一轮明显慢样本，386.29ms完整保留；该比较同时包含reset与SQL过滤，不能全归因过滤，更不是HTTP、成熟数据或容量通过。当前下一真实macro改选**reset-filtered-v1＋ensure-scope＋frontend**，先同版2账号烟测，再40人；尚未取得新40人结果，不升100。

源证明仍从原15efa…父源码，经原7d1518…operator生成reset fde92…，再以新a0308de0…operator只换角色SQL得到894df974…。三种transport互斥、principal行数仍最多2；filtered＋scope启动固定最多7读，无新module/driver绑定名。树外20项/12组合验证通过后，在原生边界通过的明确指令下仅把principal模块、CLI及filtered operator落main；正式后台未部署。

## 来源门禁、集成与下一步

`principal_experiments`最多2行：至多一种transport（principal/reset/reset-filtered互斥），再ensure-scope；共享operator/父源码按所选recipe绑定，不能把未选transport共享文件误认成孤立来源。默认不写新字段、零新增source读取；未知、丢失/伪造证明、混修订、回绑或源漂移拒绝。

启动先核实际完整sources，再principal replay返回原G父字节给旧business validator。metadata在副本中按frontend a62父视图→principal G父视图→business父视图→旧runtime最多3层恢复；旧observation层确实覆盖PWA service，不能跳过frontend父视图。client只验证metadata，不读服务源码。client-workload绑定仍保留。

初版13项/8组合来源与客户端检查通过；新增reset后的16项/10组合、再加filtered后的20项/12组合均通过，包括实际`guard.load`/client门禁、transport互斥/max2、shared operator缺失/孤立、实字节漂移和7读上界。Git传输为显式内存夹具；实际不可变Git导出、同版2账号及40人复测由后续真实回执证明，不以此代替。新文件仍需按双仓规则同步，提交编号由实际Git回执补记。

后续先完成新recipe烟测和40人workflow/清理/RPS验证，再按事前门槛决定100→200→500等阶段；成熟合成档案、正常房间结束/独立同步storm、4小时稳定窗口和公网7Mbps发生器链路均须真实观测。不得用长排队、错峰、延长timeout或遗漏grant读取掩盖失败。未达标就保留失败并定位，不凭SELECT1推断购买更强服务器即可解决。

## 可复核证据

### C40完整实测（2026-11-14补记）

新C40（`84918eae30a84868d60d80924a679a9b`，game `594df7c7`）已完成真实客户端式HTTP负载、正常停服与独立完整采集：100000个薄合成注册账号、40并发，PG实际2CPU/2048MiB、4连接/Q32/2秒，前端48/后台32。2459次HTTP、640次WORKFLOW均零失败；40次真实奖励及40次奖励后档案刷新成功，40个账号完成最终结算和释放，服务端HTTP/lease/pool均清零，容器正常退出。签名连续满员下界811.46秒。

档案HTTP P95为670ms，周期checkpoint为1200ms，最终checkpoint流程为8500ms，从共同退出意图到完整结束为8900ms。按事前预算取向1000/1500/10000ms标准完整通过；原500/1500ms严格标准仍有失败，不改写为严格通过。最大值、失败B40以及本轮压测器奖励字段错误的修复分别保留。此结果仅证明本次40人、薄合成数据与Windows经SSH公网转发拓扑；不是100/4000人、成熟档案、4小时、真实Steam或公开TLS容量结论。

权威证据：[完整分析](D:/Survival_本地工具/runs/survival_capacity_autonomous_20261113_01/C_full_analysis_01/analysis_receipt.json)，SHA256 `34d394ab683a203c8fb807a4f6c9f5e97d0e3f2e57ee9ffa8be07a31c1829f6d`；[原始采集](D:/Survival_本地工具/runs/survival_capacity_autonomous_20261113_01/C_results_01/collection_receipt.json)。`capacity_certified:false`仍保留，避免将诊断阶段通过当成整个项目上线认证。

SQLite 3.51.3已从固定官方C源码在上海独立目录构建，真实ABI、WAL/FULL及持久计数回读通过，实际库SHA256 `ddd51819f5bba0b54508c45f2bccd2bcdafabf3f3dd0d8667f96ab5a783fb090`，系统库和旧venv没有修改。它**未用于C40**；后续WAL候选须显式绑定此私有库并先做新的完整HTTP烟测。构建[真实回执](D:/Survival_本地工具/runs/survival_capacity_autonomous_20261113_01/sqlite_private_build_result_02_receipt.json)不能替代服务验证或更大容量结论。本轮没有正式后台部署、游廊发布或收费资源采购。

### WAL、成熟数据及真实compact负载的边界

WAL两账号完整HTTP已通过：31 HTTP＋8 WORKFLOW零失败，2账号清理，真实加载私有3.51.3、同一Service连接wal/FULL=2、启动/停服依赖和独立终态库摘要均完成。[完整回执](D:/Survival_本地工具/runs/survival_capacity_autonomous_20261113_01/WAL_smoke_full_analysis_01/analysis_receipt.json)。此90秒烟测没有正checkpoint奖励，不以它代替奖励覆盖。

成熟2账号原生种数后，首次checkpoint elapsed=0且历史累计不变；普通与final同request_id重放的revision、stats、archive/content_inventory、effects/session明确投影与4表计数不变，另外账号投影不变、正常release。8笔真实star grant来自种数调用，区别于首次零elapsed checkpoint新奖励。该probe的保护表检查在HTTP之前，后置保护表由以下40人实际验证补充，不扩大旧回执。

成熟40（game `0609f2c4`、run `38c07e4ba829b89240fcc0af72d1c687`）已完整通过：2466 HTTP＋640 WORKFLOW零失败，600 checkpoint、41次真实checkpoint grant及后续profile读取成功，40个完整退出。档案P95 570ms、周期1500ms、完整退出9100ms；连续满员下界813.14秒。后置只读SQL确认4503条持久行、5种实际原型、会话/待处理项清理及保护表0；PG2CPU/2048MiB、WAL依赖、监控和正常停服均已核对。只有40个注册成熟账号；不是10万成熟账号验证。完整[分析回执](D:/Survival_本地工具/runs/survival_capacity_autonomous_20261113_01/Mature40_full_analysis_01/analysis_receipt.json) SHA256 `ac27f0d8f5586b72e62c7a61b7c4eec8dc7b8aa513dbbd475f9b1993b941f5dd`，及[后置SQL](D:/Survival_本地工具/runs/survival_capacity_autonomous_20261113_01/native_phase_operations/mature_stage40_01/small_post_http/execution_receipt.json)。

成熟原型artifact有16型；确定性100000/4000映射实际覆盖14型，不是早先审查转述的15型。缺active+dense的returning与collector两型。实际覆盖由种数和聚合回执报告，不把可用模板数当已执行覆盖数。

client-v2兼容压力保留。C的旧snapshot平均约36KB及每账号冷catalog约102KB不是新compact客户端的必然开销：真实Lua在compact_bound时停用旧snapshot，依靠profile与本地目录；已发布1303的双仓来源、关键11文件、本地种子及签名编译资源均独立核对，MD5 `4027c0e0b4d3218bd246a701478ce5c2`。新显式client-v3只按该路径建模：四人逻辑房间共享目录，启动/30秒poll明确真实HTTP，本地查看意图另计，不冒充请求；仍保留45%额外人工profile压力及原奖励、幂等和完整退出流程。13项定向检查及独立审阅通过；v3原生烟测/更大阶段尚待同提交实测，不能仅凭删除旧请求宣布容量提升。room初始化/空间O(N/4)，稳定tick/join/leave为O(1)，继任查找最多4成员，无逐tick全用户扫描。相关[来源与冻结回执](D:/Survival_本地工具/runs/survival_capacity_autonomous_20261113_01/client_v3_compact_candidate_02/candidate_generation_receipt.json)。

### 10万成熟数据通过，100启动失败与后续候选

client-v3两账号真实完整烟测通过：30 HTTP＋8流程零失败；1房间共享1次startup catalog、2次30秒poll均命中，2次本地查看无旧snapshot HTTP，2账号清理；WAL/签名/实际源/终态全门通过。见[完整回执](D:/Survival_本地工具/runs/survival_capacity_autonomous_20261113_01/Compact_smoke_full_analysis_01/analysis_receipt.json)。

100000注册/100 active成熟夹具真实种数493.47秒完成。独立只读聚合证明100000 HMAC映射、764058条持久行、409384627B数据库、87676条完成历史、400笔种数奖励、13种实际原型、保护表及pending/session/idle事务0。初版审计错误使用`prefix <= id < prefix+'~'`，实际排序下计到0；原FAIL保留，02仅去掉错误范围并用精确left前缀，原库没有修改，[新完整审计通过](D:/Survival_本地工具/runs/survival_capacity_autonomous_20261113_01/native_phase_operations_v2/compact_mature100_01/large_seed/execution_receipt.json)。

随后100人、spawn5/s、计划840秒阶段在31秒提前失败，未达满员。实际80 start/cleanup，431 HTTP含1个503、136 workflow含4失败、3 ASSERT失败，连续100-ready未成立；不能称80人容量通过。失败后SQL历史/奖励/保护表与待处理会话审计通过，API/lease/pool正常清理，保留[完整失败分析](D:/Survival_本地工具/runs/survival_capacity_autonomous_20261113_01/Compact100_failed_full_analysis_01/analysis_receipt.json)。

首个503的内容无关采样：benefit_claim总3226.395ms、lua_cache2009.359ms，且没有lua_exec；DB等待916.34ms、guard107.367ms。真实runner对同key冷cache follower等待固定2秒，证据支持在取得配置缓存前触顶，不把它解释为奖励数据丢失或已证明CHECK造成503。新可选`--settlement-cache warm-v1`在监听前以空`_cache`上下文真实编译静态配置，不运行交易；固定observed runner61c/bundle d388/current a958来源，默认零新增IO，2秒/4worker/20秒请求限制不变。19项绑定/生命周期检查通过，但其中cache生命周期使用fakeEntry；Windows编译失败保留，必须后续Linux真实编译、HTTP及宏观复验，不提前写“503已修”。

另一独立候选`--archive-validation indexed-v1`仅改原CHECK函数体，按实际键匹配固定规则，保留约束、函数属性及权限，完整源证明child1f30→600→564。6675原生bool用例、4组SQLSTATE、2张真实CHECK表与权限一致，12.43秒内完成；empty/sparse/rich/98合法/4096未知键小ABBA有改善，**98键全1非法输入回归0.474→0.642ms（约35.5%）**。这些是SQL规划执行和本机往返均摊，不是HTTP或CPU纯时，不宣称全输入提速。独立新数据库保留，100基线库未改，见[真实执行](D:/Survival_本地工具/runs/survival_capacity_autonomous_20261113_01/archive_unique_native_executor_02/execution_receipt.json)、[独立审计](D:/Survival_本地工具/runs/survival_capacity_autonomous_20261113_01/archive_unique_native_actual_audit_01/audit_receipt.json)。

SQL与预热组合仍是隔离测试可选配方，尚未部署正式后台或游廊。所有后续阶段保留1000/1500/10000ms、连续满员600秒和零错误标准；短过载诊断另列实际issued/ready，不冒充通过。4小时验证必须记录真实连续满员下界。

树外根`D:/Survival_本地工具/runs/survival_capacity_autonomous_20261113_01`，以下链接均为现有真实文件；没有原始认证、密钥或账号完整数据。旧回执不生成新的部署/收费/清档授权。

- [事前计划](D:/Survival_本地工具/runs/survival_capacity_autonomous_20261113_01/autonomous_plan_receipt.json)、[client-v2来源与19项检查](D:/Survival_本地工具/runs/survival_capacity_autonomous_20261113_01/client_workload_01/implementation_freeze_receipt.json)。
- [scope候选/18项检查](D:/Survival_本地工具/runs/survival_capacity_autonomous_20261113_01/ensure_scope_candidate/candidate_generation_receipt.json)、[局部CPU与调用计数](D:/Survival_本地工具/runs/survival_capacity_autonomous_20261113_01/tests/ensure_scope_cpu_01/verification_receipt.json)。
- [SQLite原生4项候选](D:/Survival_本地工具/runs/survival_capacity_autonomous_20261113_01/sqlite_hot_rate_candidate_01/candidate_generation_receipt.json)、[frontend6项绑定](D:/Survival_本地工具/runs/survival_capacity_autonomous_20261113_01/frontend_binding_01/implementation_freeze_receipt.json)。
- [初版13项/8组合](D:/Survival_本地工具/runs/survival_capacity_autonomous_20261113_01/tests/principal_binding_02/verification_receipt.json)、[reset版16项/10组合](D:/Survival_本地工具/runs/survival_capacity_autonomous_20261113_01/tests/principal_binding_03/verification_receipt.json)、[当前六文件来源冻结](D:/Survival_本地工具/runs/survival_capacity_autonomous_20261113_01/integration_source_freeze_02/candidate_generation_receipt.json)。
- [DB-only生成与守卫](D:/Survival_本地工具/runs/survival_capacity_autonomous_20261113_01/principal_native_db_only_01/candidate_generation_receipt.json)、[原v5真实NOT_CONFIRMED](D:/Survival_本地工具/runs/survival_capacity_autonomous_20261113_01/principal_native_v5_verification_receipt.json)（SHA256 `9c66cb12d5480d0a8a26579c5fb102743536928026ee3e805d398213df1aeb70`）。
- [ACL顺序语义审计](D:/Survival_本地工具/runs/survival_capacity_autonomous_20261113_01/principal_native_semantic_audit_receipt_01.json)、[独立重算审计](D:/Survival_本地工具/runs/survival_capacity_autonomous_20261113_01/principal_native_semantic_restore_independent_audit_receipt.json)、[平衡1920次结果](D:/Survival_本地工具/runs/survival_capacity_autonomous_20261113_01/principal_balanced_phase_result_01_receipt.json)（原始外层文件SHA256 `b0ba1f827b7901820d0e66ba18427bb1f7087b9d22672eea95922087fa22552b`）。
- [候选B真实35×2与960次微基准](D:/Survival_本地工具/runs/survival_capacity_autonomous_20261113_01/filtered_role_native_result_01_receipt.json)（原始外层文件SHA256 `5e731488806a69f8d3fb41b55e6b54f256d12bb7c2d38a53163a428c9664c8a3`）、[B来源20项/12组合](D:/Survival_本地工具/runs/survival_capacity_autonomous_20261113_01/tests/principal_filtered_binding_01/verification_receipt.json)、[树外B集成冻结](D:/Survival_本地工具/runs/survival_capacity_autonomous_20261113_01/integration_source_filtered_candidate/candidate_generation_receipt.json)。


## 本轮补记：100人可靠性全过，五项延迟门槛失败

此处是当前阶段的补记。前文各时点“待烟测”“尚未进100”及旧失败证据原样保留。正式后台和游廊本轮均未部署，未购买或变配云资源，4000在线仍未认证。

C40为10万薄合成注册/40并发，2459 HTTP＋640 WORKFLOW零失败，档案/周期/完整退出P95为670/1200/8900ms；成熟40为40注册账号，2466 HTTP＋640流程零失败，档案/周期/退出P95为570/1500/9100ms。二者按事前预算取向门槛通过，原严格目标分开报告；40注册成熟账号不等于10万成熟注册验证，更不等于4小时通过。

### 新100的完整结果与清理

`warm_indexed100_01`，run `e8ff519634944f2558e505f5f193f386`，100000成熟合成注册/100 active；实际PG2CPU/2GiB、4连接/Q32、每次池等待2秒，后端HTTP32/前端128。prepared `9ee3dae2…`与实际operator `5f68f810…`的20个消费者LF字节绑定相同，130份prepared源、7份原始采集和派生摘要已独立核验。Windows经单条SSH公网转发，仍受上海7Mbps上限影响；不覆盖生产Nginx/TLS、真实Steam或支付。

最终HTML窗口为2026-11-14 01:34:56–01:47:19 UTC（743秒，含启动、爬坡及集中收尾）。6141个最终事件＝4807 HTTP＋1334 WORKFLOW，均零失败，无效wire0、ASSERT0。周期CSV停在6117个事件，不能当最终值。147份签名status形成100有效已确认身份的连续满员下界659.125506秒；这不是逐玩家心跳或每人持续业务进展证明。

| 指标 | 次数 | P95分桶 | 事前预算门槛 |
| --- | ---: | ---: | --- |
| profile HTTP | 1346 | 4800ms | 1000ms，失败 |
| periodic checkpoint HTTP | 1034 | 7400ms | 1500ms，失败 |
| periodic完整流程 | 1034 | 8600ms | 1500ms，失败 |
| final checkpoint HTTP | 100 | 23000ms | 单项HTTP另报 |
| final checkpoint完整流程 | 100 | 23000ms | 10000ms，失败 |
| 共同退出意图至完整结束 | 100 | 23000ms | 10000ms，失败 |

结论为`FAILED_FIXED_BUDGET`，恰有五项延迟门槛失败、pending为空；零错误与数据完整性不能覆盖延迟失败。P95是Locust分桶观测值，HTTP与WORKFLOW重叠，不相加、平均或用原始Max替换。checkpoint完整流程含奖励后真实profile读取；退出意图还含on_stop调度等待和release。

1234个checkpoint全部完成；101次真实grant响应、101次grant校验和101次后续profile HTTP全部完成。100次final、release、cleanup均成功，不要求或宣称每个用户都取得了奖励。前端接收4956＝4807 Locust HTTP＋147独立status GET＋2停止控制，额外控制请求不计业务RPS。

后置只读SQL通过：100000 HMAC映射、13种实际原型（artifact提供16型）、87676条原完成历史、501笔持久奖励与幂等/定义关联保持。pending operation/outbox、online session、idle-in-transaction及支付/兑换保护表均0；当时仍有5个其他client backend，不能写成“SQL验收时全部会话为0”。最终API/monitor/PG正常停止、容器exit0无OOM、端口关闭、HTTP/lease/pool归零，原数据与失败证据保留。

[最终完整分析](D:/Survival_本地工具/runs/survival_capacity_autonomous_20261113_01/Warm_indexed100_full_analysis_01/analysis_receipt.json)、[完整采集](D:/Survival_本地工具/runs/survival_capacity_autonomous_20261113_01/warm_indexed100_01_results_01/collection_receipt.json)、[后置SQL](D:/Survival_本地工具/runs/survival_capacity_autonomous_20261113_01/native_phase_operations_v2/warm_indexed100_01/large_post_http/execution_receipt.json)、[独立最终审阅](D:/Survival_本地工具/runs/survival_capacity_autonomous_20261113_01/warm_indexed100_independent_final_audit_01/audit_receipt.json)（SHA256 `52292c0caa65b4d9f782413c73e52ce58f8df58a0fa5b01b396097cb33446a6f`）。

### 局部优化与下一代码方向的界限

两账号Linux监听前预热224.914ms（约225ms），56表/1621395字节，build1/hit0/retained1、业务命令0；该烟测31 HTTP＋8流程零失败。新100预热244.311ms，终态build1/hit1961/retained1、job failure0。私有SQLite 3.51.3、线程安全3、WAL/FULL=2及启动/停服同库摘要通过。SQL与预热组合验证，不能以小烟测或新100零错证明某一变化单独解决旧503。[预热及旧100独立审阅](D:/Survival_本地工具/runs/survival_capacity_autonomous_20261113_01/warm_smoke_and_failed100_independent_audit_01/audit_receipt.json)。

CHECK候选6675个原生bool、SQLSTATE、真实CHECK表及属性/权限通过；98键全1非法输入约0.474→0.642ms、回归约35.5%完整保留。ABBA含SQL规划执行与本机往返，不是HTTP提速、纯CPU时间或全输入改善。PG4CPU配置尝试被主机资源门禁拒绝，未启动，不能列为实测更大CPU结果。[CHECK独立原生审阅](D:/Survival_本地工具/runs/survival_capacity_autonomous_20261113_01/archive_unique_native_actual_audit_01/audit_receipt.json)。

live100受限样本中最慢regular为6832.464ms，poolwait5942.517ms、DB服务768.777ms（其中guard429.535ms）；42条同记录guard占DB服务成本中位52.4%，Lua cache/exec中位约1.7/85ms。它支持优先审查连接占用与重复RPC，但样本有时间和预算选择偏差、无请求关联ID，不能跨PWA/backend相减P95；单点PG cgroup含启动/种数累计，不能证明当前持续quota饱和。[只读数字分段审阅](D:/Survival_本地工具/runs/survival_capacity_autonomous_20261113_01/live_warm100_readonly_snapshot_analysis_01/analysis_receipt.json)。

下一方向仍针对5/7/9RPC与profile phase，但完全融合的profile5→3/checkpoint9→7/grant流程14→10只是调用数模型，**不能称语义等价**：把最终get_fishing_profile放入较早事务会改变transaction_timestamp()/now()起点，跨午夜的每日额度与权益starts_at边界可能返回不同视图；VOLATILE的新数据快照不能修复事务时钟变化，也不能临时把now改成clock_timestamp。最保守首候选仅合并两个pending检查，保留最终fresh profile原独立RPC/事务：空待办profile5→4、checkpoint9→8、grant流程14→12。非空online立即返回ID并提交，再沿原序Lua结算；64＋64两轮drain保留。**仅静态设计，尚未原生验证、实现或部署。**

保持旧21项函数及角色的实时权限检查；若新增phase函数，同步纳入严格白名单、权限与来源证明。事务/失败隔离、幂等、最终fresh profile及grants保留。没有grants仍可能更新福利日/周秒数、在线金币、地图经验、commerce/welfare/title等，不能当no-op跳过Lua；不以异步短ACK、自动mutation重试或延长期限绕过标准。先原生并发、时钟边界、故障/跨账号差分，再同源2账号与40/100复测。[事务时钟补充审查](D:/Survival_本地工具/runs/survival_capacity_autonomous_20261113_01/rpc_phase_clock_addendum_01/verification_receipt.json)。


### 新100流量的实际口径

发生器记录4807个HTTP响应body合计15598556B，除最终743秒窗口为20994.019B/s（约21KB/s；包含此发生器观察的控制响应，不等于TLS/SSH总线上字节）。NIC全内窗覆盖740.183秒、99.621%；最大完整约5.0018秒区间的TX均值为152918.064B/s＝1.2233445Mbps，这是全接口含SSH/status的采样区间均值峰，不是瞬时峰或精确业务出网账单。

本轮100人SLA失败，闭环发生器因响应慢而自限后续请求，故`normal4000_forecast_eligible:false`。不能把这组小流量或低平均RPS直接乘40来证明4000正常体验、更不能据此承诺20Mbps足够；当前7Mbps仍穿过SSH链路，也未实测生产TLS/Steam。报价可以比较20Mbps上限，最终带宽和按流量成本仍需合格SLA下的真实负载验证。[实际流量分析](D:/Survival_本地工具/runs/survival_capacity_autonomous_20261113_01/traffic_budget_analyzer_02/samples/New100_01/analysis_receipt.json)、[范围解释](D:/Survival_本地工具/runs/survival_capacity_autonomous_20261113_01/traffic_budget_analyzer_02/samples/New100_01/interpretation_receipt.json)。

### 40人／10万成熟注册长测最终结果

**最终状态：通过事前预算门槛。** run `e5a77eda68ae477a3be333c196bb0951`，manifest `959c19ee650ce24acf12182c733c88aeb812db655ef0bbd98d832dcf8923acb9`；实际HTML窗口2026-11-14T01:57:12Z–2026-11-14T06:01:20Z，14648.000秒，含启动/爬坡/集中收尾。计划14640秒，签名连续40有效已确认身份下界14615.920611秒；满员门槛14400秒，身份可用性不是逐玩家心跳。

HTTP 34396次/0失败；WORKFLOW 9781次/0失败；ASSERT 0/0。真实grant响应961次、validated grant 961、奖励后profile 961/961完成；final/release/cleanup各40完成。

| 指标 | 最终P95分桶ms |
| --- | ---: |
| profile HTTP | 400 |
| periodic HTTP | 760 |
| periodic完整流程 | 860 |
| final HTTP | 8700 |
| final完整流程 | 8700 |
| 共同退出意图完整流程 | 8800 |

原分析失败门槛：无；pending为空。HTTP/流程百分位重叠不相加或平均；退出流程保留排队、奖励后读取和release，原严格目标仍由完整报告单独列出。

PG实际2CPU/2GiB、DB4/Q32/2秒及原HTTP有界参数保持；prepared/operator实际为`5f68f8102151fa1b23d202fa81f9644ebdda5355`。与先前prepared `9ee3dae2…`的130份源映射相同、20消费者导出逐项绑定；testbundle仍d388…和原runner61c，不把未部署候选说成生产。

后置只读SQL通过：持久行801476、数据库445208243B、实际原型13/16、奖励1121及幂等/定义关联完整，原历史每表87676保留；pending/outbox/online session/idle-in-transaction及保护表0。SQL审计时其他client backend=5，不等于所有会话0。API/monitor/PG已正常停止、容器exit0无OOM、端口/HTTP/lease/pool归零；私有SQLite库启动/停服/终态摘要一致，数据与旧证据保留。

数据库大小是post时点总量，不能把相对更早seed标记的增长当成HTTP阶段增长；关系物理分配、完整回执JSON逻辑字节、临时文件累计和WAL/备份分别报告，不相加重复计费。长期预测与按表增长若另有完整回执，由root附录，不能只凭初始0.4GB或短测机械外推。

本结果仅覆盖40人、10万成熟合成注册、该时长及Windows经SSH公网转发拓扑。即使此档通过，也不覆盖100人五项延迟失败、4000未认证、真实Steam/支付或生产TLS。预算≤3000仅取报价，本轮无采购、正式后台部署或游廊更新。

长测HTTP响应body实际182364676B，整个HTML窗均值12449.800B/s（含启动/控制/收尾，不含请求、头、SSH/TLS开销）。NIC全内窗覆盖14641.232秒，≥5秒采样区间TX均值峰0.887301Mbps；这是全接口含SSH/status的区间均值，非瞬时或body峰。仍非生产4000容量或账单证明。[长测流量回执](D:/Survival_本地工具/runs/survival_capacity_autonomous_20261113_01/traffic_budget_analyzer_02/samples/Soak40_01/analysis_receipt.json)，SHA256 `1fe609041f41a3b66e924f702ad05a8f7fd6633f7c4f091b99a80474f6203b82`。

长测前后实际数据库407230131→445208243B，差分37978112B、新增38018行。五类历史/幂等/奖励关系物理分配差分32997376B；完整奖励response::text逻辑差分6583008B，不能重复加入物理增长。页复用、TOAST/index、WAL/备份另按实际指标解释，初始与短期增长不承诺长期容量。[按表存储回执](D:/Survival_本地工具/runs/survival_capacity_autonomous_20261113_01/storage_growth_model_01/samples/Soak40_01/analysis_receipt.json)，SHA256 `d4a931829e0e6650f81566fdb34252085f0d412d102fdece271d85380b9388df`。

长测独立审阅回执若晚于本候选生成，由root另附；不把尚未取得的审阅写成通过。

最终来源与证据：
- [完整分析](D:/Survival_本地工具/runs/survival_capacity_autonomous_20261113_01/Soak40_full_analysis_01/analysis_receipt.json)，SHA256 `989b34fac6fd7921d06abba016c0fc4fd405d8b2e65bb9a499fdae48d56bcdae`。
- [完整采集](D:/Survival_本地工具/runs/survival_capacity_autonomous_20261113_01/warm_indexed_soak40_01_results_01/collection_receipt.json)，SHA256 `5a85b4bcfe7f37159c51945be67a80431a5745af595a455bc963271076373a41`。
- [最终driver](D:/Survival_本地工具/runs/shanghai_test_20261113/stage_20261114T015701Z_629e9cb72c/stage_receipt.json)，SHA256 `da1e7c76817582a5c9460d639398872c78a395051ac84abed85c2a0914504262`。
- [后置SQL](D:/Survival_本地工具/runs/survival_capacity_autonomous_20261113_01/native_phase_operations_v2/warm_indexed_soak40_01/large_post_http/execution_receipt.json)，SHA256 `a9ae0fe43a72f6b389673b9557dc6fd629dd3876e9829f7e881968953b21a5d8`。
- [正常停止](D:/Survival_本地工具/runs/survival_capacity_autonomous_20261113_01/capacity_operations_v4/operations_warm_indexed_soak40_01/stop_result_receipt.json)，SHA256 `44cfa3cdd59e5967224368fbe7722d3120f5c54646639c99dca900fdc5d7dd58`。
- [SQLite终态](D:/Survival_本地工具/runs/survival_capacity_autonomous_20261113_01/stage_toolsets_v5/warm_indexed_soak40_01/sqlite_terminal_observation.json)，SHA256 `1ea7d6ff64977bdd326c31038a5dc05123ce3b7e083280515cf0d6e8c723231d`。

当前仓库最终commit/push状态只由root最后真实Sync回执另附；本生成器未执行Git，不能把测试source revision填作最终交付提交。


### 隔离研究与成本补记

仅本地更新。以下内容为隔离压测研究及证据补记，不构成游廊发布、生产 gzip 启用或已支持 4,000 人的结论。

Windows 本机固定 Steam SDK DLL 的原生 ISteamHTTPv003 探针完成三案：identity 返回原始 3,873 B；显式 Accept-Encoding:gzip 和脚本不主动设置该头但服务强制 gzip 的两案，服务均发送 1,642 B，SteamHTTP 返回相同 SHA 的 3,873 B JSON，说明该本机路径自动解压。第三案底层 Steam 仍附加了未记录原文的 Accept-Encoding，不能写成实际请求头缺失。三请求句柄均释放、SDK正常关闭，wall 0.283 秒、子进程 CPU 0.046875 秒；未触远端压测、未启动 Dota/Tools，原始 SDK 日志及旁置文件未收集。这只证明当前本机 Flat ABI，不能替代普通 Dota 的 CreateHTTPRequestScriptVM 实机、TLS/代理路径或当前真实业务节流收益验证；生产 gzip 仍未因本探针而开启。证据：steam_http_gzip_probe_01/native_audit_01/verification_receipt.json（SHA64012dd3…），完整三案表在同目录 OBSERVATION.md。

本轮考虑用直接 aclexplode 目录 ACL 查询替换 has_*，经双人静态审阅后否决，严格原检查保持。尽管完整旧 MEMBER/owner/超权门槛可把普通准入域收窄到当前 role 与 PUBLIC，替换会删除旧 helper 的函数 EXECUTE 检查、增加新 helper 的 EXECUTE 检查，并新增 relacl/attacl/proacl 等目录列 SELECT 依赖。合法权限 DDL 即可让原查询与改写查询接受结果不同，不能默认为 stock 目录权限恒定。没有生成改写 operator、没有新原生实验或修改环境合同，也未将该研究称为生产性能修复。历史隔离库实际计划只有4个用户namespace、36条guard relation、107条guard function及21条独立允许函数检查；复杂度由对象、列和ACL规模决定，不是注册玩家数，展开也可能增加 tuple/内存成本。证据：acl_guard_source_review_01/verification_receipt.json（SHAb3b1476b…），独立 peer 在 acl_expanded_independent_static_peer_01/review.md（SHA5a1ab216…）。

已完成百人短测的实际数据库大小从 407,008,947 B 变为 413,054,643 B，差分为 6,045,696 B、新增4,727行；不能直接把 post 相对更早seed标记的6,206,628 B当本阶段增长，因为seed自身已增加160,932 B。五类历史/回执关系物理分配增加3,915,776 B；101笔新增奖励的完整 response::text 合计增加584,805 B，是逻辑文本量，不能重复加进物理增长。已审冻结 schema/runtime 未发现普通历史TTL；final checkpoint 只删除当前在线游标，而幂等回执、outbox/operation、奖励与会话基线保留。未审计远端外部cron，因此不宣称绝无另配任务。删除这些记录可能破坏防重、日限额、兑换码使用状态或支付对账，未自动删除任何数据。把743秒的全物理增长机械延伸到4,000人×每天4小时×30天约140.6 GB，只是高延迟闭环短测的风险情景，非长期预测或采购保证，也不是与另一时间分母构成上下界。初始10万账号约0.4GB不能代表长期需求；须用完整4小时40人快响应阶段的前后聚合，再考虑页复用、实际增长、备份/WAL/日志与保留协议。证据：storage_growth_model_01/samples/New100_01/analysis_receipt.json（SHAd2aff977…）、STORAGE_REVIEW.md及retention_review_receipt.json（SHA9f8f30e0…）。


Windows Lua5.3独立功能预演仅证明同host的9组fixture/27 fresh VM父重复与子完整typed JSON一致；原Linux POSIX验证器保持，不能把Windows结果、RNG/时区或预算耗时当Linux原生性能，更不能称备份恢复演练已完成。相关后续原生证据如有由root独立附录。 [Windows同host功能范围回执](D:/Survival_本地工具/runs/survival_capacity_autonomous_20261113_01/windows_lua53_preflight_01/actual_scope_audit_receipt.json)，SHA256 `7e4e6387bf28b4fc2157ec72b78e177a1fea41833e74538d5e4b1d0a27ab0828`。

补记原始来源摘要：
- [verification_receipt.json](D:/Survival_本地工具/runs/survival_capacity_autonomous_20261113_01/steam_http_gzip_probe_01/native_audit_01/verification_receipt.json)，SHA256 `64012dd3c782cbc2d73d139b728671f8a43d1c75ae046f3d3d77418d864020d7`。
- [native_child_receipt.json](D:/Survival_本地工具/runs/survival_capacity_autonomous_20261113_01/steam_http_gzip_probe_01/executions/native_01/native_child_receipt.json)，SHA256 `8d8b15ea9eb98a3ee66593ee4cc366fb9aa7a12c126be9bb5835cff81150fb25`。
- [verification_receipt.json](D:/Survival_本地工具/runs/survival_capacity_autonomous_20261113_01/acl_guard_source_review_01/verification_receipt.json)，SHA256 `b3b1476bbb07aa0bdb0b4a03c764c2b936ef5f0399ee89bcfd2765f946777518`。
- [review.md](D:/Survival_本地工具/runs/survival_capacity_autonomous_20261113_01/acl_expanded_independent_static_peer_01/review.md)，SHA256 `5a1ab2162c3857c139030226d475d268f26bf07ac6cb54e8676028427642b0df`。
- [analysis_receipt.json](D:/Survival_本地工具/runs/survival_capacity_autonomous_20261113_01/storage_growth_model_01/samples/New100_01/analysis_receipt.json)，SHA256 `d2aff97728edf23e234ad27cb750ac25a530f7b14274cbc38bdd9dee52fcbd07`。
- [retention_review_receipt.json](D:/Survival_本地工具/runs/survival_capacity_autonomous_20261113_01/storage_growth_model_01/retention_review_receipt.json)，SHA256 `9f8f30e044440700111083b663b070fb8b68330b202713bec189c0a02825dd0c`。

用户现在可与Codex并行：向阿里云只取企业8核16GB、16核32GB＋同地域SSD/独立数据盘、公网20Mbps按流量的相同周期首期和续费报价；另取8核16GB＋同区托管PG作比较，不购买或改现有7Mbps。总账含租金、实际流量、备份、监控和旧机重叠，每月≤3000；不能承诺8核hold住4000。Steam登录出口、备份实际恢复演练、普通Dota客户端HTTP gzip自动解压仍需分别验收，gzip研究不等于启用。具体采购、生产迁移/部署及游廊发布另行确认。
### SQLite认证清理五索引：Windows原生局部结果

新的树外候选仅新增五个非唯一索引，保持原清理SQL、TTL/时钟、限流提交顺序和外键行为。实际验证使用Windows标准库SQLite **3.50.4／DELETE journal／单线程合成库**：四个主要认证历史表各100000行、合计400000行；这不是PostgreSQL的10万注册账号，也不是正在运行的Linux私有SQLite3.51.3/WAL服务。

原Service.start与logout实际调用的VM指令计数如下。计数开启逐指令Python callback，wall受该instrumentation开销影响，不能把表中比值解释成HTTP延迟或P95。

| 实际操作 | 父版VM步数 | 五索引候选VM步数 |
| --- | ---: | ---: |
| start | 1200204 | 230 |
| logout | 300348 | 385 |

父/子功能投影及重启投影相同，覆盖NULL/0/live token/严格过期边界、FK级联、退出、失败回滚与已提交rate保留、时钟回拨和持久429。四种源码父绑定含hot/WAL字节恢复证明；实际原生Service功能仅base与tracked/latest父子四臂，不能扩大为hot/WAL或Linux均已实测。400k初建索引单次约0.165秒、文件增加12644352B；索引维护、历史库初建、写放大和更多过期行成本仍需计入。

稳定范围查找可减少无关历史扫描；challenge索引先按expires范围定位，COALESCE(token_expires,0)仍有残余过滤，成本依候选范围R而非仅删除K。全体过期K接近N的情况未测，不能写成任意历史规模恒定耗时。同名错误定义仅由外部metadata验证发现，constructor不自动修复，也未证明所有初始化失败都自动完整回滚。

该结果为局部功能/执行量证据，未做Linux3.51.3/WAL多连接或HTTP宏观/P95验收，未改main、正式后台或当前长测来源，不能用它覆盖100人SLA失败。实际[Windows原生回执](D:/Survival_本地工具/runs/survival_capacity_autonomous_20261113_01/sqlite_auth_expiry_indexes_candidate_03/runs/native_01/native_receipt.json)，SHA256 `d43cc04d4c977b5e084053dbd4dadc914c1a40c4fb52fcb4d3872ab3bcfbb232`；[四父源码冻结](D:/Survival_本地工具/runs/survival_capacity_autonomous_20261113_01/sqlite_auth_expiry_indexes_candidate_03/candidate_generation_receipt.json)，SHA256 `f77764c0c51d9525ecf8ab7cafe3b321c4ffd911aedc79f70c334ba7804c1ad3`。

### 最新报价记录：用户已说明参考月价，续费仍待订单核验

用户已将16核规格更正为`ecs.u2a-c1m2.4xlarge`，并最新说明“参考价格人民币每月，再计算了满1000减80，应该续费也是同价位”。本轮预算按下表用户提供的参考月价记录；是否已包含满1000减80尚不确定，因此不再次减80。续费同价只是用户预计，未经实际续费页面或账单核验，不能写成续费保证。此前型号/账期未明确的旧候选和回执均保留。

| 用户最新规格 | 官方规格对照 | 用户提供的参考月价 | 用户口述磁盘 |
| --- | --- | ---: | --- |
| `ecs.u2a-c1m2.4xlarge`，用户描述AMD | 16 vCPU／32 GiB | 1012元/月；不再扣80 | 40GB；“扩4倍、加20–30元”待订单核实 |
| `ecs.c9i.2xlarge`，用户描述Intel | 8 vCPU／16 GiB | 738元/月；不再扣80 | 40GB；“扩4倍、加20–30元”待订单核实 |

官方[实例规格总览](https://help.aliyun.com/en/ecs/user-guide/overview-of-instance-families)列出上述两档vCPU与内存；[c9i CPU选项表](https://help.aliyun.com/zh/ecs/user-guide/cpu-options-of-compute-optimized-instance-families)也说明c9i.2xlarge默认8vCPU。u2a官方说明兼容多代AMD EPYC并提供企业级算力，不能据型号或“最高”频率推定报价实例的具体CPU代次、实际分配频率或单核性能。[u2a官方说明](https://help.aliyun.com/en/ecs/user-guide/general-work-force)。

用户下一步只需核对同地域/可用区、完整规格ID、实际CPU与资源分配、首期和续费页面总额、优惠是否已含、磁盘类型/扩容后确切容量及加价周期、备份、20Mbps按流量的实际GB单价和旧机重叠费用。40GB扩容“4倍”及20–30元只保留为口述，不预设扩后容量或每月加价。Codex据完整总账比较每月≤3000元方案；当前没有购买、变配、生产部署或游廊发布授权。较多vCPU、参考月价及Windows局部优化均不证明4000人已可用，仍需同源目标硬件原生及分级SLA验收。

### JIT假设的既有证据边界

只读核对两份已有实际EXPLAIN回执：8个查询标签各3次TIMING FALSE，共24条记录的`jit`均为null；源探针直接取真实JSON计划的JIT字段。没有记录JIT编译耗时，安全摘要也未保留Total Cost或实际JIT设置，不能证明成本越过阈值，不能将每RPC编译当作已定位原因。另8条TIMING TRUE摘要未保留JIT字段，不扩大为这些计划也已证明无JIT。本次没有新增SQL、SSH或native请求，已停止此方向排查。[filtered计划回执](D:/Survival_本地工具/runs/survival_capacity_autonomous_20261113_01/filtered_role_plan_result_01_receipt.json)，SHA256 `4d8b2454731e674238e566a4800176ab02c92cc07655c554bfbb108dec52bf1e`；[principal计划回执](D:/Survival_本地工具/runs/survival_capacity_autonomous_20261113_01/principal_plan_probe_result_01_receipt.json)，SHA256 `f2fa5d1304683d4b58d2febe54d3700ab4c11993f42aa2bbbce79a486b27c03d`。

### 选型限制：本轮lab的后台与PWA为同进程HTTP线程

已只读核对当前长测实际导出的`operator/loadtest_lab/runtime.py`，原始SHA256 `c6aa4233bd6747bbdd85495d156f2d288f4511eabb2c945517f26cb822b6f700`，与该lab清单及已完成100人测试的实际导出相同。第284行创建后台HTTPServer，第294行创建PWA HTTPServer，第326–328行对两个server分别启动`threading.Thread(...serve_forever...)`：它们由同一个Python进程构造并以不同线程服务。内部后台/代理接口绑定loopback；Windows发生器经SSH公网进入服务器，未绕过7Mbps公网传输限制。PostgreSQL则是同机独立容器，限定2CPU/2GiB，不能把整机4核8GB都当成数据库可用资源。[本次启动源码只读核验](D:/Survival_本地工具/runs/survival_capacity_autonomous_20261113_01/final_doc_supplement_04/topology_readonly_receipt.json)。

因此，本轮100人延迟失败是这一软件拓扑、配额、请求节奏和测量路径下的结果，不能当作整台4核8GB硬件的容量上限。已有whole-host CPU及池排队数据不足以证明PG配额耗尽，也未证明GIL或其他串行等待已是根因。较多vCPU不保证同进程路径或等待按比例改善；不能从核数线性预判16核可以承载4000人。所有100人失败门槛和4000未认证结论继续保留。

下一步先补各进程CPU、IO与分层排队观测，再确认并匹配正式部署拓扑做同源对照，随后才决定RPC合并候选和采购。本地已知systemd模板分别为`player_web_auth.run`和`workshop_test.run_api`独立入口，源码仅证明部署意图；本次未查询生产，不能据模板声称现网实际分进程。16核u2a的1012元/月及8核c9i的738元/月仍只是参考采购候选，优惠不二扣、续费待核；用户暂不需要立即购买或变配。[模板来源与准确行号](D:/Survival_本地工具/runs/survival_capacity_autonomous_20261113_01/final_doc_supplement_04/topology_readonly_receipt.json)。
