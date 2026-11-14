# 2026-11-14 快速阶梯与身份绑定隔离实验

本轮仅本地工具和隔离测试更新；正式后台与游廊未部署。4000人尚未执行或认证。

## 范围和实际资源

用户要求快速完成100—2000筛查，中间长稳缩为2小时，最终4000人仍需4小时真实满员。当前上海专用测试ECS为4vCPU/8GiB、7Mbps按流量；本轮PG容器限制2CPU/2048MiB、HTTP32/FE128/FIFO32/等待2秒、Lua4workers、split-v1/client-v3。账号为10万合成薄档案；不复制生产玩家或使用真人兑换码。

DB4源为0908e0cf，DB8源为353ade7c；仅池预算接线4→8，其余126份业务导出相同。两组是顺序单轮测试，时段、随机操作和退出形态不同，不能宣布因果收益或多核线性容量。

## 已执行的快速结果

| 100人配置 | HTTP/失败 | 有效签名最高ready | 连续满员保守下界 | profile P95 | 周期P95 | 完整退出WF P95 | 退出SQL |
|---|---:|---:|---:|---:|---:|---:|---|
| DB4 | 1691/0 | 100 | 116.794秒 | 9600ms | 14000ms | 25000ms | PASS，online=0 |
| DB8 | 1708/1 | 100 | 116.728秒 | 6100ms | 8600ms | 27000ms | online=1，未收口 |

两组均未通过严格签名连续观测和原延迟门；不能将曾观察到100ready写成容量通过。DB8失败为最终checkpoint的backend_busy，另有派生WF/assert失败；短测无正在线grant覆盖。

| 池 | 名义目标 | 实际有效采样ready最高 | HTTP/失败 | SQL在线会话残留 |
|---|---:|---:|---:|---|
| DB4 | 200 | 19 | 882/25 | 旧SQL02失败，细项未知 |
| DB4 | 500 | 14 | 841/11 | 旧SQL02失败，细项未知 |
| DB4 | 1000 | 18 | 792/10 | 旧SQL02失败，细项未知 |
| DB4 | 2000 | 20 | 749/3 | 旧SQL02失败，细项未知 |
| DB8 | 200 | 14 | 815/12 | 4 |
| DB8 | 500 | 15 | 854/12 | 6 |
| DB8 | 1000 | 15 | 840/24 | 7 |
| DB8 | 2000 | 19 | 748/7 | 4 |

200—2000均在爬升中首先frontend_busy而早停，未达到各目标。DB8 SQL03实际pending/error/outbox均0，但online非0；11次execute后失败，后续受保护表检查未完成。原分析器必要路由缺失拒绝、未产生假的PASS。所有这些run的API/BE/PG/monitor和端口已物理正常停止，数据与残留证据保留；物理停止不代表业务退出成功。旧DB4第一次采集发生在PG停止前，保留原记录，以其后Ops正常stop作物理终态依据。

完整十档路径、SHA和限制见树外 `capacity_process_topology_20261114_01/db4_db8_quick_comparison_01/{summary.md,comparison.json,comparison.csv}`。

## 新的冷绑定候选和真实两账号验证

源码发现 `EndlessLeaderboard.bind` 在单个全局RLock内执行真实身份绑定RPC；不同账号冷读档会互相等待。候选采用固定128个RLock分片，全局锁仅保护既有4096项成功缓存；同账号二次检查、RPC失败不缓存、下一等待者重试和缓存清理保留。不同分片可并行，碰撞仍串行；没有按账号无限增大的锁表。

初始化O(128)，热命中O(1)且0RPC，冷绑定1个原RPC及O(1)索引，既有4096边界清理O(4096)；内存O(128+4096)。实际线程负对照13项、精确可逆补丁8项、工具接线45项通过。原14项合同测试父/子均13通过、1个共同历史夹具缺失错误，不能写成全套全绿。

仅提交了四份隔离工具，game `b354065e6158b18ea7e0ae4f892e92cd7dc12bec` / dev，content `1aaa557ab7cadc2ceb41f599809dce39a26dab36` / master，两仓均已按stash→pull→pop→commit→push核对。保留game106份其他改动、22个历史stash及content4个stash，未提交他人文件。

主 `server/archive_backend/endless_leaderboard.py` 仍为父9de91c7；使用旧冻结BASE源码，只有显式 `--leaderboard-binding striped-v1` 才在新隔离目录得到child af4e0245。新baseline130源，striped131源，22个实际消费者、6个完整restore/replay helper；旧SQL、权限、源证明、SLA、failfast和清理门都保留。真实已提交Git导出及三个独立portable fullguard验证通过，非仅mock。

新两账号run `cf5b45b470b9c9a14d22fe5c609524a4`，manifest `3f8ac2508614e9a75a7b8cb1c5729a2e22628d64cbed3038d3747c5aadb480f6`：37HTTP零错、3幂等重放、十连10次结果、32无尽波、另一账号原指纹不变、cleanup失败0；服务内调用7.393秒。API/BE正常exit0非forced、池关闭、PG/monitor与三个端口全停，SQLite WAL/FULL及终态库摘要一致。独立审计 `striped_db8_smoke_independent_audit_01/audit_receipt.json` SHA `2280be085533b2b3437e325301d6428a61084a29c4e4c1b9694eb69b56a8803b`。

这只是功能烟测；实际池峰值1，不能认证8连接同时工作、100或4000容量；accounts2不适用thin100k SQL03及14表完整检查。

## CPU采样缺口

另一次CPU40的596HTTP和160WF零失败、40清理及SQL零残留完成，全部物理正常停止。但执行时选错Python环境，采样窗口11:08:30—11:09:30UTC与实际HTTP11:10:20启动错开；FE/BE各316个候选请求全部在窗口外，captured=0、hot=0。因此CPU_NOT_CONFIRMED，没有函数热点结论。保留失败，不重开旧窗口或冒充CPU证据；原始审计 `CPU40_native_diagnostic_audit_01/audit_receipt.json` SHA `458c85fe9d6e941380d8f9126e173ac460b8cea1626ce41858f106ce825304f5`。

原5秒资源样本未显示持续网卡/磁盘占满或发生器CPU满核，但不排除短峰、单核、锁等待或宿主限制，不能据此排除CPU问题。

## 用户授权后已实际完成的新100人

新100人run `7a6d572003e557c78bd3b77524d71d8f`，manifest `edb6b86c1cecff6450dbfc7c057954b0d182967e2771cf17f8ae4d4ea84a81da`，131源与获准并通过的两账号版完全相同。用户已明确授权向47.116.11.179的该独立目录上传并继续阶梯；随后实际完成上传、bootstrap、warmup、100/180秒/spawn5、收尾和离线分析。

此前两次自动审批拒绝均在CreateProcess前；保留原拒绝证据 `striped100_upload_approval_block_01/refusal_receipt.json` SHA `72b215a04ec27a45e37b93eba34d1f8205b020825917f24e8893e590bfaf9e41`，不改写为成功。这次成功以用户后续具体授权和新执行回执为依据。

实际HTTP窗口12:50:40—12:54:03UTC，1691HTTP/3失败、460WF/6失败、3ASSERT/3失败；后两者是相同失败的派生事件，不能算成12次HTTP错误。3次均为最终checkpoint的503/backend_busy，普通1491HTTP零失败。退出100尝试、97完成、3失败；签名最高ready100，连续满员保守下界118.075秒，但42探针中有1次失败，严格连续证据未过。profile/周期HTTP/最终checkpoint WF/完整finalization WF的P95分别7600/10000/23000/23000ms。短测没有正grant覆盖，不能解释为奖励丢失或通过正发奖验收。

API先正常停，PG仍运行时原SQL03读到pending/error/outbox均0、online_sessions=3，第11次execute／第5个aggregate即拒绝；后续14受保护表及奖励关联检查未执行，不能写成其均通过。随后BE、PG、monitor正常停、池关闭、三个端口均不监听，首次采集和SQLite终态已完成；物理停服不代表三次业务退出成功。原生SQL回执SHA `5585b96d1dcdfc32cabb1d1374ac93330c61e7670981a1ca1175923a71c8ff36`。

源导出固定b354，而实际operator为仅多3份文档的e93febf8。原分析器错误地要求两种提交号相同而拒绝；新独立分析控件分别精确绑定两者，验证22个实际Git消费者字节及全部131导出，29个其他函数／类不变，6项负对照通过；全部SLA、错误、SQL、清理门保留。最终 `Striped100_full_analysis_03/analysis_receipt.json` 为FAILED_FIXED_BUDGET、pending空，不是通过。原分析器拒绝与后续纠正均保留。

## 新40人诊断及真实函数采样

另外运行 `bd6d336498c743a7f975e1975821a583`，manifest `b0fa226babb2b8e3e6bdf1af82cc8173831ad846c6a79b49d919672fe58ce50d`，b354相同131源、40/150秒/spawn5、10万薄档案及相同资源。682HTTP与200WF均零失败，40次完整退出，签名连续满员下界125.689秒。SQL03完整46次execute／22个aggregate通过，pending/error/outbox/online、奖励关联及14受保护表均0；所有进程、池、端口正常停止，SQLite终态确认。

诊断profile/周期HTTP/完整退出WF P95为1900/5000/10000ms，仍超读档和周期门，且短测无正grant覆盖；`Profile40_full_analysis_01/analysis_receipt.json` 为FAILED_FIXED_BUDGET、pending空。不能把这轮零失败写成性能通过或套用旧源40人四小时结论。

通过官方py-spy0.4.3、固定wheel和二进制摘要，在实际40-ready业务窗口对已核验身份的FE/BE分别采样45秒、10Hz、GIL-only/nonblocking；获得FE50、BE45个有效栈。无locals/真实回包/原生SQL栈采集或目标信号。FE pack_bytes包含35/50、encode23/50、canonical15/50；BE rpc包含28/45、权限检查13/45。这是少量GIL栈频率，不是精确CPU占比、调用计数或PG/Lua耗时。原先错过窗口的CPU40失败仍独立保留。证据 `pyspy_profile40_01/{execution_receipt,profiles_collection_receipt,hotspot_summary_receipt}.json`。

原100的5秒样本约200秒：FE均值0.475核、BE0.538核、PG1.156核／最高1.678核；PG上限2核，累计节流计数增加9.824秒，不能直接当墙钟百分比。磁盘平均忙6.95%、5秒峰18.8%，发生器单核CPU峰5.9%；没有持续磁盘饱和证据，仍不排除短峰、单核、锁或共享宿主限制。见 `metrics_summary_01/samples/striped_db8_quick100_01/summary_receipt.json`。

对已有157+111条限额、指定命令脱敏耗时记录做一次离线聚合：100档74个最终checkpoint记录平均6776.8ms，其中DB池等待累计平均4814.0ms、role/function guard累计562.0/280.8ms、实际query累计433.3ms。通常周期路径7次RPC，带结算时更多，最终路径9次。此为有选择的墙钟样本，包含排队和调度；嵌套阶段不可相加，也不是CPU归因。见 `http_stage_timing_summary_01/summary_receipt.json`。

## 编码CPU候选与当前继续条件

通用标量缓存只作上海独立合成微测，5种输入中2种CPU反而慢约5.6%和11.4%，没有合入。另准备更局部的候选：一次构建编码键JSON长度索引、每字段只编码一次，并复用单次pack自身写出的不超过64KiB字节；保留严格解析、权限、边界、完整解码逐字节核验及原回退。

局部候选父／键长度／组合版本各1462项旧回归、1028项定向、8770键长度差分和800项附加encode行为检查通过；主业务文件未修改。初始化O(固定协议别名)，稳定已知键O(1)查询、未知键O(键字节)，每回包复杂度仍O(B+sum K log K)，无按账号的全局缓存、额外网络或DB调用。示例实际JSON序列化调用从869→334、656→198；这是函数调用计数，不是CPU/FPS结果。

本机Windows/Python3.14合成微测仅显示优化方向，CPU时钟粒度有限，不能代替上海Python3.12或HTTP容量。8文件/约74KB的新派生候选尚未上传：自动审批认为先前b354的131冻结源授权未覆盖新派生源码，在CreateProcess前拒绝；已再次列明文件、47.116.11.179及全新 `/srv/survival-loadtest/codec_key_size_probe_20261114_01` 向用户申请授权。保留 `wire_key_size_native_benchmark_01/approval_refusal_observation_receipt.json`，没有绕过拒绝。获得授权后先做独立CPU对照，再决定接入下一轮业务压测。

本轮20份显式回执登记18份成功或已登记；原生SQL原始回执无已知storage绑定、SQLite observation不在白名单，两份被登记器拒绝，原证据和上层执行／采集回执保留，不修改日期或伪造绑定。见 `post_profile_evidence_registration_01/registration_observation.json`。不清理任何旧数据。新200以上、2小时及4000四小时不据失败的100自动宣称完成；需要先改善实际瓶颈并通过相应门。未购买、升级或改变生产后台／游廊。

另尝试仅把本机PG容器CPU上限2→4准备一个100人对照，既有冻结工具在本地返回 `reviewed_db8_postgres_resources_required`：当前8连接实验合同严格绑定2核／2GiB。此新档未准备完成、未上传或启动，不能拿更改JSON绕过来源与预算校验。若继续资源对照，应先扩展并验证资源合同及对应采集／分析绑定，再运行；不能报告为已完成4核对照。

## 恢复压测主线后的同源200／400快速筛查

用户最新明确要求本对话只推进压测，临时闪退任务暂停。自建Tools已正常退出，端口与两个精确LAB联接已退役，现场树外保留；没有游戏运行源码修复、正式部署或游廊操作。此后只执行容量任务。

继续使用已经获准的b354冻结131份源码，逐SHA与获准100档完全一致；每档10万合成薄档案、180秒计划、spawn5、min-ready60，PG2核／2GiB、DB8及其余预算不变。实际均在爬升中触发失败停压：

| 目标 | 实际启动尝试 | 有效签名采样最高ready | HTTP／失败 | WF／失败 | ASSERT／失败 | 完整清理 | SQL online |
|---:|---:|---:|---:|---:|---:|---:|---:|
| 200 | 150 | 16 | 825／12 | 265／24 | 11／11 | 144／150 | 2 |
| 400 | 140 | 11 | 739／9 | 247／17 | 15／15 | 135／140 | 2 |

200的run为 `1cd72a651357a49ea8182618bd3edd68`，manifest `1038d39f25dd8981908291d0f8eab3f9205c138ad10e5f229973db29ae6b3362`，窗口14:41:44—14:42:38UTC；400的run为 `aaa6ab401ea954aca1b96e7ce392c652`，manifest `511b0c8b72ba10bd655701cdac0ecccd64512f3e7887b3caf803204ee68f1119`，窗口14:55:53—14:56:41UTC。HTTP失败均为frontend_busy，分布于接入证明、login／ready、最终checkpoint及release。没有达到名义人数，目标连续ready下界均0，不能将启动尝试数当作有效同时在线。

两档pending/error/outbox均0、online均2；SQL03在第11次execute／第5个aggregate拒绝，后续14受保护表与奖励关联检查未到。API／BE、PG及monitor正常退出、PG exit0／无OOM、三个端口全不监听，数据保留；首次采集与SQLite终态确认完成。这些物理终态不能替代业务退出或落库验收。

HTML／final／路由／HTTP／wire计数相互一致。driver通用错误为 `final_statistics_mismatch`，实际未过的是compact目录对账、房间及业务完整性门，并非总数与HTML不一致。两份独立原分析控件仍因必要路由缺失返回 `ANALYSIS_NOT_CONFIRMED / analysis_required_route_missing`，未放宽门生成PASS。首次分析候选的Windows CRLF原始摘要预检拒绝也保留；02候选固定真实LF字节、29个其他函数／类与12个helper不变，22个Git／工作区消费者及6个负对照已核对，实际operator均d1b4ce2f、准备源仍b354。

200窗口有10个有效5秒区间、约50秒：FE平均0.639核、BE0.705核、PG1.493核／区间峰1.715核，PG节流计数增加3.282秒，磁盘平均忙8.96%。400有8个区间、约40秒：FE0.630核、BE0.735核、PG1.577核／峰1.649核，节流计数2.342秒、磁盘12.47%。这是短窗口聚合，不能当瞬时峰值、精确CPU归因、节流墙钟百分比或单独的服务器选型结论。

完整原始来源／摘要／分项在树外 `striped200_400_quick_comparison_01/{comparison_receipt.json,summary.md}`，资源分项在 `metrics_summary_01/samples/striped_db8_quick{200,400}_01/summary_receipt.json`。当前需要改进接入／排队并对照验证；4000及新长稳未执行，不对未满员阶段凑2小时或4小时。

原131冻结源的阶梯授权已用于上述真实执行。8文件、约74KB新派生编码候选仍未上传；自动审批明确认为原授权不涵盖新派生源码，已在恢复主线后再次列明原ECS、独立目录、CPU及业务压测用途向用户确认。收到明确答复前保留此上传阻断，不改入口或用间接执行绕过。

## 流量模型与采购边界

按当前client-v3，理想低延迟、4000人全部ready且4人满房的稳态约227.111HTTP/s；2人/1人房约260.444/327.111。均未计登录、发奖刷新和集中退出，不是实测容量或峰值。100人整个混合运行成功响应体均值约2.4KB，只能作包体算例，不能证明7Mbps足够或据此开月账单。见树外 `steady_request_model_01` 与 `steady_request_model_02`。

用户738/月与1012/月仍为参考报价，含盘/优惠/续费未独立核实。官方变配矩阵不保证现e能直接变c9i/u2a，Intel/AMD跨平台和回退有约束；先询价并在取得具体费用授权后新建一档按量临时机验证，不能承诺核数线性或当前方案可hold4000。旁证保存在 `survival_capacity_autonomous_20261113_01/budget_review_20261114/purchase_preflight_20261114_1935/purchase_preflight.md`。

旧源40人/10万成熟账号四小时通过仍限于[原证据](capacity_autonomous_20261114.md)，不自动变成新源100或4000通过。本轮不进行移交到其他对话的游戏卡顿修复。


## 2026-11-15 新候选授权、上海CPU对照及业务准备

用户已明确授权8文件新派生候选上传原上海ECS的独立压测目录并继续CPU与业务对照；原自动拒绝保留，后续成功有独立授权／上传／执行回执，不改写旧失败。新目录codec_key_size_probe_20261114_01，归档SHA256 c683b8044ecee26fa8b4562defd7328a3f8d6532778b81db5f863c622a92c5d0，73733字节。五种输入各72次pack，旧／键优化／组合三臂全部输出字节一致。组合候选045afbbe03cd4e5cc91f879f6db2cd6881b7362c80cc1c248152a94619387ff5，原生Python3.12 process CPU均值相对旧版约下降12.31%、25.51%、3.18%、16.75%、24.52%，配对中位数下降约16.94%、15.88%、11.74%、4.92%、20.98%；单轮存在反向噪声，不能承诺固定增益或据此认证在线人数。

调用计数869→334、656→198，初始化仅O(固定schema别名)，稳定已知编码键尺寸O(1)、未知键保留精确JSON转义；整次pack仍O(B+sum K log K)，额外空间仅固定表和本次pack至多64KiB。没有按账号或授权的全局缓存。状态变化不跨请求保留，新回包重新处理；公共decode和全部解析/预算/重复字段/类型检查及完整重建比对保留。每请求HTTP、RPC、DB调用增量均0。实际Handler.do_POST对照每臂720合成请求、4321项检查通过：9业务和3非业务路由、200/400/503、协议头重复或未知、fallback均与父版一致。它是本地分派一致性证据，不是真实认证或容量证据。

独立旧版100控制run ad9a7c4c7d2e27a95abc75199b082240，manifest 90f44a110788247459867c48fd1211a5305cbce62ee3f9e6dcd432f0e2980a39，仍b354的131源、同PG2核/2GiB/DB8及100/180秒/spawn5。实际16:26:21—16:26:53UTC仅476HTTP、1次login backend_busy；最高签名采样ready8，未达到100。90次退出全部完成，SQL03完整46execute/22aggregate通过，pending/error/outbox/online及受保护表均0。API/BE/PG/monitor正常退出、首次采集与SQLite终态确认。原分析器因必要路由未覆盖返回analysis_required_route_missing，保留失败、不放宽门。不能把短测或零残留视为100通过。

停API后的只读目录检查EXPLAIN显示role查询原生执行约1.45～3.35ms、function约0.46～0.96ms；与负载下数百毫秒墙钟样本存在明显排队/调度区别，单凭栈频率不能断言SQL计划就是全部瓶颈。首次使用系统解释器缺依赖的失败保留，后续专用venv只读对照有独立记录。

树外证据位于capacity_process_topology_20261114_01的wire_key_size_native_benchmark_01、wire_cpu_result_review_20261115_01、wire_http_dispatch_integration_20261115_01及codec_business_pair_20261115_01。仅将精确组合候选合入后台源码以供下一轮固定源压测；未部署正式后台、未改客户端协议或schema、未操作游廊、未购买。下一轮须断言131源仅business_wire.py一份变化，再执行相同100对照与收尾。4000四小时及新2小时长稳仍未执行。

## 2026-11-15 本轮全部业务对照与正常收尾

运行源码提交928da435dfa51bf73e519f276aa0428e863e9923已推送game/dev，content/master为1aaa557ab7cadc2ceb41f599809dce39a26dab36；仅后台编码文件及知识记录变化，不等于后台部署或游廊发布。新131源与获准b354的131源只有runtime/player_web_auth/business_wire.py一项不同，组合045候选与此前8文件授权内容逐SHA一致，schema与协议hash不变。其余业务规则、PG2核/2GiB、DB8/HTTP32/FE128/队列32/等待2秒、10万合成薄档案及client-v3保持不变。

| 阶段 | 目标 | 入场/秒 | HTTP/失败 | 有效签名采样最高ready | 完整退出/尝试 | SQL online |
|---|---:|---:|---:|---:|---:|---:|
| 旧版控制 | 100 | 5.0 | 476/1 | 8 | 90/90 | 0 |
| 新版快速 | 100 | 5.0 | 1724/0 | 100 | 100/100 | 0 |
| 新版快速 | 200 | 5.0 | 887/18 | 16 | 136/150 | 10 |
| 新版快速 | 400 | 5.0 | 865/12 | 17 | 141/150 | 3 |
| 新版快速 | 500 | 5.0 | 804/9 | 20 | 134/140 | 4 |
| 新版快速 | 1000 | 5.0 | 850/14 | 17 | 134/145 | 4 |
| 新版快速 | 2000 | 5.0 | 865/12 | 16 | 142/150 | 7 |
| 新版慢入场 | 200 | 1.0 | 1841/43 | 114 | 129/156 | 26 |

新版100真实窗口16:44:34—16:47:57UTC，100-ready连续下界114.404秒，42签名探针全部有效；1724个已完成HTTP零错误，463个WF零错误，100次退出全完成。SQL03完整46execute/22aggregate、14受保护表与奖励关联及pending/error/outbox/online均0。然而wire记账1725 requests/1724 responses，原driver及分析器保留analysis_wire_http_counts_unsettled；未伪造少的响应、调整统计或改成PASS。profile/周期WF/最终checkpoint WF/完整finalization WF P95为6800/7800/22000/22000ms，均仍慢；短测无正grant覆盖。单轮随机工作选择、早停窗口不同，不能把旧控制早停与新版完整运行直接解释为固定容量提升。

五档快速实验分别计划200/180秒、400/180、500/280、1000/380、2000/580，均spawn5/min-ready60；实际均在约50～60秒爬升窗口发生frontend_busy并停止，所有目标连续ready下界0。表中的目标或启动尝试不能冒充有效在线，不能以空转凑2小时。SQL均只完成11execute/5aggregate后因online残留拒绝；pending/error/outbox均0，后续14受保护表和奖励关联未到，不能声称全部通过。原分析器保留必要路由缺失拒绝。

慢入场200是额外诊断，明确与快速档分开：spawn1、计划420秒、同源同配额，run f8e030f838c7dbd543c0e57ec4641868，manifest c7b05c05da0cd4e575b4de5435ca4681ac4d23bb36e1f6df50508b1631592d45。实际17:29:02—17:32:18UTC，启动156、最高采样ready114、目标ready下界0；1841HTTP/43错、517WF/57错、33ASSERT/33错，后两者不重复算成HTTP。129/156完整退出，SQL online26、pending/error/outbox0，后续保护检查未到。原完整分析为FAILED_FIXED_BUDGET、pending空；读档/周期WF/最终WF/完整退出WF P95为18000/21000/24000/41000ms。较慢入场能提高就绪数，但尚未到200，既不能承诺稳定114，也不能替代快速档标准或4000验收。

八轮API/BE、monitor、PG均正常关闭，容器exit0/无OOM，三个测试端口均不监听，全部数据保留；首次采集和SQLite终态确认齐全。物理关闭不等于表中失败的业务退出已修复。独立闭环审核在codec_full_closure_audit_20261115_01/audit_receipt.json。

资源证据：新版100的39个完整区间约195秒，FE自身平均0.444核、BE0.584核、PG1.208核；不把PG父进程waited-child重复相加。五档爬升短窗口FE约0.592～0.600核、BE0.754～0.780核、PG1.570～1.610核，磁盘平均忙9.06%～10.31%。整机100窗口busy约66.94%、iowait0.77%、暴露steal0；短5秒采样不排除瞬时饱和，steal0不证明独占宿主。PG节流累计计数不能当墙钟百分比。

已测完整区间的整机网卡出站5秒峰约0.907～1.469Mbps，包含SSH/control和其他系统流量，不是游戏裸包或瞬时峰；未接近用户7Mbps上限，不能据失败爬升外推4000的带宽/月账单。见host_cpu_observation_20261115_01与host_network_observation_20261115_01。

已有5秒PG会话采样进一步显示：新版100的40样本均有8连接，active均值1.2、idle_in_transaction均值2.4，waiting_for_lock全0；慢入场39样本分别active均值1.846、idle_in_transaction均值2.077、锁等待采样0，最大9连接含额外诊断连接。它们是离散样本均值，不是精确时间平均，也不能证明没有短锁。需要继续拆分应用持有租约/事务期间的处理与调度，不能凭本轮数据断言直接加CPU、内存、磁盘就能hold4000。观测覆盖层为固定map/有界日志，无逐阶段同步落盘或无界遍历；尚无关闭观测的原生A/B，不能归罪或排除其全部开销。

额外表扫描统计诊断未取得结果：绑定当前合成库的只读尝试返回非零，仅保留错误摘要；未读取账号行或改结构。原始失败保留在readonly_table_statistics_20261115_01/first，第二快照明确未执行，不自动重试、不重启已关闭数据库，也不写成“无全表扫描”。下一轮须先准备正确的只读统计角色和安全错误阶段信息，并在开始压测前采基线。

本地汇总首版误把quick1000包含quick100的子串当成100路径，已保留原工具及其失败；02版只将路径选择换为两个精确100标签，原始统计、门槛、SLA无变化，八轮真实来源与逐文件摘要已复核。它是汇总工具修正，不是业务性能修复。

完整机器证据：树外codec_full_comparison_20261115_01/comparison_receipt.json，SHA256 a10ae9e045324c6a688e3cb537eaf9786b151ad36a78f010b00e733396c7665a；包括每轮run/manifest/source、各路由分项、签名ready、SQL、清理、CPU和原分析拒绝。五档资源汇总位于metrics_summary_01/samples/codec_candidate_quick*_20261115_01。新生成、备份和控制回执均按明确列表登记；不删除旧候选/PGdata/原失败。

本轮结论：编码CPU优化有效方向已验证、代码可复核，但业务容量仍不达200，更不能按4000上线。4000四小时、新2小时稳态和10万成熟/满背包账号均未由这些薄档案短测认证。下一阶段优先修复请求完整计数、拆清事务租用段与接入/最终退出排队，再同资源复测；放宽资源配额必须先扩展并验证当前固定工具合同，不手改JSON绕过2核/2GiB/DB8绑定。更大云机和收费操作仍需具体报价及授权；本轮没有采购、扩容、正式后台或游廊操作。临时游戏闪退任务保持暂停。
