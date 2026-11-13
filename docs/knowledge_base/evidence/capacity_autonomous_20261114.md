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

合并guard没有确定总体收益，execute减少不等于性能通过。当前选择较小的**reset-v1＋ensure-scope＋frontend**进入下一轮真实2账号烟测和40人macro；这是待测recipe，不是已经上线或证明更快。含原生故障验证的四臂也不能证明成熟账号、HTTP/SQLite/Lua、4000人或4小时。

## 来源门禁、集成与下一步

`principal_experiments`最多2行：至多一种transport（principal/reset互斥），再ensure-scope；共享operator/父源码按所选recipe绑定，不能把未选transport共享文件误认成孤立来源。默认不写新字段、零新增source读取；未知、丢失/伪造证明、混修订、回绑或源漂移拒绝。

启动先核实际完整sources，再principal replay返回原G父字节给旧business validator。metadata在副本中按frontend a62父视图→principal G父视图→business父视图→旧runtime最多3层恢复；旧observation层确实覆盖PWA service，不能跳过frontend父视图。client只验证metadata，不读服务源码。client-workload绑定仍保留。

初版13项/8组合来源与客户端检查通过；新增reset独立recipe后的16项/10组合检查也通过，包括reset-only、reset＋scope＋frontend实际`guard.load`/client门禁、transport互斥与max2。Git传输为显式内存夹具；实际不可变Git导出、同版2账号及40人复测由后续真实回执证明，不以此代替。新文件仍需按双仓规则同步，提交编号由实际Git回执补记。

后续先完成新recipe烟测和40人workflow/清理/RPS验证，再按事前门槛决定100→200→500等阶段；成熟合成档案、正常房间结束/独立同步storm、4小时稳定窗口和公网7Mbps发生器链路均须真实观测。不得用长排队、错峰、延长timeout或遗漏grant读取掩盖失败。未达标就保留失败并定位，不凭SELECT1推断购买更强服务器即可解决。

## 可复核证据

树外根`D:/Survival_本地工具/runs/survival_capacity_autonomous_20261113_01`，以下链接均为现有真实文件；没有原始认证、密钥或账号完整数据。旧回执不生成新的部署/收费/清档授权。

- [事前计划](D:/Survival_本地工具/runs/survival_capacity_autonomous_20261113_01/autonomous_plan_receipt.json)、[client-v2来源与19项检查](D:/Survival_本地工具/runs/survival_capacity_autonomous_20261113_01/client_workload_01/implementation_freeze_receipt.json)。
- [scope候选/18项检查](D:/Survival_本地工具/runs/survival_capacity_autonomous_20261113_01/ensure_scope_candidate/candidate_generation_receipt.json)、[局部CPU与调用计数](D:/Survival_本地工具/runs/survival_capacity_autonomous_20261113_01/tests/ensure_scope_cpu_01/verification_receipt.json)。
- [SQLite原生4项候选](D:/Survival_本地工具/runs/survival_capacity_autonomous_20261113_01/sqlite_hot_rate_candidate_01/candidate_generation_receipt.json)、[frontend6项绑定](D:/Survival_本地工具/runs/survival_capacity_autonomous_20261113_01/frontend_binding_01/implementation_freeze_receipt.json)。
- [初版13项/8组合](D:/Survival_本地工具/runs/survival_capacity_autonomous_20261113_01/tests/principal_binding_02/verification_receipt.json)、[reset版16项/10组合](D:/Survival_本地工具/runs/survival_capacity_autonomous_20261113_01/tests/principal_binding_03/verification_receipt.json)、[当前六文件来源冻结](D:/Survival_本地工具/runs/survival_capacity_autonomous_20261113_01/integration_source_freeze_02/candidate_generation_receipt.json)。
- [DB-only生成与守卫](D:/Survival_本地工具/runs/survival_capacity_autonomous_20261113_01/principal_native_db_only_01/candidate_generation_receipt.json)、[原v5真实NOT_CONFIRMED](D:/Survival_本地工具/runs/survival_capacity_autonomous_20261113_01/principal_native_v5_verification_receipt.json)（SHA256 `9c66cb12d5480d0a8a26579c5fb102743536928026ee3e805d398213df1aeb70`）。
- [ACL顺序语义审计](D:/Survival_本地工具/runs/survival_capacity_autonomous_20261113_01/principal_native_semantic_audit_receipt_01.json)、[独立重算审计](D:/Survival_本地工具/runs/survival_capacity_autonomous_20261113_01/principal_native_semantic_restore_independent_audit_receipt.json)、[平衡1920次结果](D:/Survival_本地工具/runs/survival_capacity_autonomous_20261113_01/principal_balanced_phase_result_01_receipt.json)（原始外层文件SHA256 `b0ba1f827b7901820d0e66ba18427bb1f7087b9d22672eea95922087fa22552b`）。
