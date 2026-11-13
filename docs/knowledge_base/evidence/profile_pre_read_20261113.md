# 省去被丢弃的档案预读：隔离候选与同负载验证（2026-11-13）

本轮仅更新隔离压测工具，并在用户指定的上海4核8GB测试机运行合成账号。正式后台未部署，本轮未操作游廊、购买或升级云资源。对照为上一轮F40（10万合成薄档案、40活跃、2305HTTP零错，最终结算P95约11秒，仍超预定10秒），见[上一轮完整记录](staged_load40_reliability_20261113.md)。

## 本轮最小变化

冻结`ArchiveService.profile`原先先调用`application.profile`，其ensure后读取完整档案并公开转换；这份value随后被结算后的fresh get覆盖。候选将原账号字符串校验、HMAC与ensure抽为`_initialize_profile`，独立`application.profile`继续ensure+get，存档加载只初始化，再沿原路径结算并读最终档案。

第二次ensure、外层和存档内部两轮online drain、archive_pending、最终get/public response、VIP及排行榜包装器都保留。两轮drain各最多64项，不能当作普遍重复删除。没有授权缓存、全账号扫描、异步ACK、未知写重试、SQL/事务/幂等或权限/连接重置变更。

静态常见正elapsed checkpoint从11→10RPC，零待办9→8；带match context的普通profile6→5，冷身份bind/VIP奖励另计。每次archive profile省1RPC及一次被丢弃档案的O(P)构造/转换（P为档案大小），新增请求状态O(1)。准备/启动为O(源码字节数+最多300个来源项)，固定读取operator与两个目标，业务热路径无新增本地读取或集合遍历。这些是源码成本和调用计数，不是延迟或容量证明。

## 来源及明确边界

操作器`server/fishing_api_overrides/profile_initialization_patch.py`精确SHA256为`a478be66d1ca9bb6ac7291676e37fee158e98572a0f58da572a5ab575107761a`。

| 目标 | 父来源 | 候选输出 |
| --- | --- | --- |
| fishing_api/application.py | 5bcc930a… | 9c4ca317… |
| archive_backend/service.py | c0591659… | 672a1e84… |

只支持已审完整SQL56467cf6…/600eb5d3…；本轮同F保持600eb5d3…不变。该SQL的get_fishing_profile唯一写入是ensure已保证的玩家INSERT ON CONFLICT，其profile_json及每日额度链为SELECT/JSON聚合，未发现发奖/领取副作用。等价范围限冻结有效schema与合法业务数据；原先初次get触发的数据库/损坏数据异常可能延后到drain之后，故障注入明确展示这一差异，不能宣称所有故障点顺序相同。已提交写入仍依原request/operation ID恢复，不换新ID自动重试。

新`--profile-load init-only-v1`仅用于全新bounded-v2隔离候选，默认保持旧路径。独立`business_experiment`绑定Git、operator及两份父/子摘要。application与观测层重叠，因此仅对副本恢复固定父摘要校验原三层链；真实manifest/source map不改。server启动先逐源path/hash，再restore/replay/compile，client只做零I/O metadata核验。已知输出丢证明、改来源或SQL版本均拒绝。V7补齐第10个来源消费者，生命周期代码与V6逐字相同。

## 已完成验证

- 12组真实冻结Python函数流程检查通过，RPC/数据库状态与Lua settle结果为fake；实际finish_prepared、match context/project、VIP/排行榜包装器参与。覆盖periodic/final、pure/standard、cold/existing、第二ensure失败、128项两批及剩余tail、revision冲突与pending、RPC失败不重试、初次bind/VIP claim及最终profile/grants；额外保留预读故障发生顺序变化的反例。
- 65项准备/来源/兼容检查通过：旧baseline/v1/v2及新SQL600/profile init实际prepare流程（Git传输为mock），双SQL来源、metadata零I/O/完整固定3读、虚拟父视图不改真实manifest、源/证明/修订/重绑/冻结目录拒错。
- 同版真实两账号烟测：39次业务HTTP、3次显式幂等重放，另一账号数据不变，wire invalid与HTTP错误0；另2次签名status和2次stop共43接纳且完成。API/监控/PG正常停止，端口释放、租约0、连接池closed。
- 两份真实backend final各10RPC，get_fishing_profile各1次、ensure各2次；两份零待办regular各8RPC。final后端耗时142.822/154.993ms，n=2，不作为P95或容量证明。

烟测独立audit仅读取去身份回执/计数，不含raw body。实际烟测按既有协议验证profile when present、幂等状态及另一账号快照；完整profile/grants与wrapper字段保留还依赖精确两文件差异及上述真实函数检查，不宣称跨版本随机新发奖励的body逐字相等。

## G40实际结果

G40已在独立新库完成：10万合成薄档案、40活跃、每4秒加1人、Locust840秒，数据库仍2CPU/2GiB，HTTP32/PWA48/DB4/Q32、排队2秒、两层backlog64及原超时不变。验收分别报告原500/1500ms工程目标和预算优先1000/1500/10000ms目标，不改变门槛。

最终HTML（UTC14:44:09–14:58:19，850秒）为2249次真实HTTP，HTTP/ASSERT/wire invalid均0；40次final和release全部成功，40完整清理。169/169签名有效，保守连续满员682.452秒；实际约2.646HTTP/s，发生器CPU峰2.8%单核、RSS约137.6MB，不是发生器满载。API/监控/PG正常停止，端口释放、池关闭、租约0，保留原数据。

| 指标 | F对照 | G本轮 |
| --- | --- | --- |
| 读档P95 | 730ms | 630ms |
| 周期存档P95 | 1000ms | 940ms |
| 集中final P95（Locust分桶） | 11000ms | 11000ms |
| 集中final最长原始耗时 | 11469ms | 10738ms |
| 集中final平均耗时 | 9178.490ms | 8496.983ms |

原严格标准仍因读档及final时延未过；预算优先标准仍仅因final P95>10秒未过。P95分桶可以高于原始Max，不能把Max10.738秒或尚未收全的周期CSV（32次final/P959700ms）写成最终P9510秒。组间小幅变化不是稳健容量或因果提速证明；尚未开展100人，更不能认证4000人或4小时高峰。

完整证据pending为空。实配PG2CPU/2GiB、正常退出无OOM；池4/Q32/2秒、等待峰31、归还12499次，busy/timeout/reset/close失败0且closed/total0。后台32槽、2093接纳且完成；前端48槽、2420完成，两层拒绝/派发/发送错误及active/admitting均0。170个窗内系统样本无错、覆盖完整，CPU采样均16.520%/峰77.090%，TX采样峰1.510Mbps含SSH，不当作连续峰值、公网账单或吞吐认证。

40个实际backend final各10RPC（F各11）；每条get_profile1次、ensure2次。后端中位F7728.004→G7253.244ms，累计池等待6539.333→6133.691ms，同记录等待占比83.934%→83.374%；guard515.200→477.957ms、query277.736→263.238ms、reset145.844→123.975ms。互斥连接占用合计42.115758→38.983145连接秒，除4连接为10.528940→9.745786秒；这些是实际观察和源码计数，不是任意未来输入的固定成本或单因素因果证明。

G原生40点窗口14:57:52.020513–14:58:31.184082UTC完全覆盖同服final14:58:12.248038–22.710000（10.461962秒），同时包含前20.227525秒/后8.474082秒空闲。完全位于final内的9个约1秒区间共9.089825秒，PG加权平均使用1.541579核，观测单区间最高1.946146核；节流累计0.880984秒/31周期不是wall百分比。全39秒均值0.506核不能代表final，F有10个内部区间而G有9个，不能作CPU因果提速结论。观察到API最多107线程、RSS84924KiB，PG cgroup内存最高558485504B，无OOM，均限本窗口采样。

本轮只完成移除一份丢弃预读。剩余往返仍需在保留初始化、待办、profile/grants、幂等、权限和重置合同下另做审阅及同负载验证；不直接删第二次ensure、任一drain或放宽超时。10万薄档案不等于成熟账号历史深度；当前Locust也不包含真实Lua收到非空grants后额外load_player这一读取，不能当完整游戏在线流量模型。

## 真实证据与保留

树外根：`D:/Survival_本地工具/runs/shanghai_profile_read_20261113_01`；候选根仍`D:/Survival_本地工具/runs/shanghai_test_20261113`。新候选/源码归档/采集回执按实际来源登记，不扫描、删除或改写旧证据。

- 操作器及12组验证：`profile_init_candidate/candidate_generation_receipt.json`、`tests/profile_init_01/verification_receipt.json`。
- 65项来源验证：`tests/business_binding_01/verification_receipt.json`。
- 事前目标：`profile_init_plan_receipt.json`；F→G逐源证明：`F_to_G_source_verification_receipt.json`。
- 真实烟测：`profile_init_smoke_01_actual_verification_receipt.json`、`profile_init_smoke_01_results_01/collection_receipt.json`、`profile_init_smoke_01_stop_receipt.json`。
- 烟测独立审计：`profile_init_smoke_actual_independent_audit_receipt.json`；G完整结果：`analysis_stage40_profile_init_full_01/analysis_receipt.json`（SHA256 `ae95e2c18e33aabefc18acdca0869518354fd5daf44fca2f74a2b370d13de5f4`）；实际采集：`stage40_profile_init_cpu2_02_results_01/collection_receipt.json`；实际停服：`stage40_profile_init_cpu2_02_stop_receipt.json`。
- G分段及完整原生窗口独立审计：`stage40_profile_init_cpu2_checkpoint_timing_analysis_receipt.json`（SHA256 `9df29aabba36ee5ae8f5032dc8adaa377b17b9c8dbc68a24dab0c26c1def467e`）。
- G候选`stage40_profile_init_cpu2_02`，run `5ef9ea11c4e74e30fef9612ab2bbe012`，源码/operator提交`33dc243e95c56a1b81e164be14c2e643a8fde735`。
- 双仓同步：`profile_init_tools_git_sync_receipt.json`。game/dev本轮工具提交33dc243e；content/master核对/拉取/推送后仍6dbd9358，无空提交；原14项并行改动及所有历史stash保留。
