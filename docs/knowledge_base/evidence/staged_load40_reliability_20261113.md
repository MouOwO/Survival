# 40人集中结算修复与预算优先验收（2026-11-13）

本轮仅本地工具更新及上海专用测试机隔离实测。正式杭州后台未部署，客户端及游廊没有运行改动，未购买或升级云资源。上海仍为用户提供的4核8GB机器；PostgreSQL容器限额调整不等于ECS规格升级。10万账号均为合成薄档案，不复制生产行；不能外推成熟玩家档案、4000在线或每天4小时的容量。

用户选择预算和可靠性优先，集中退出允许等待数秒。后续候选预先采用读档P95≤1000ms、周期存档P95≤1500ms、最终集中存档P95≤10000ms，以及零HTTP/协议错误、40账号完整清理、零遗留租约和至少600秒连续签名就绪。原500/1500ms工程标准继续独立报告，既有失败回执不改写。

## 实际对照

每轮都是独立空目录和新合成库，同10万注册/40活跃、每4秒加1人、Locust840秒。下表P95来自包含入场、爬坡及收尾的完整HTTP报告；集中最终存档单列，不把普通请求和ASSERT事件混算，不平均不同路由的P95。

| 轮次 | HTTP/DB等待/PG核数 | HTTP请求/失败 | 读档P95 | 周期存档P95 | 40人最终存档P95 | 清理完成 |
| --- | --- | --- | --- | --- | --- | --- |
| 历史933957 | 24/20/1 | 2259/34 | 1500ms | 2300ms | 10000ms，18失败 | 22/40 |
| A 452520 | 32/28/1 | 2281/11 | 1300ms | 2200ms | 13000ms，11失败 | 29/40 |
| C 457043 | 32/32/1，队首通知 | 2288/4 | 1100ms | 2100ms | 16000ms，4失败 | 36/40 |
| D 21fc923 | 32/32/2，队首通知 | 2278/0 | 640ms | 1000ms | 12000ms，零失败 | 40/40 |
| E f5488f3 | 8/8/2，队首通知 | 2269/0 | 750ms | 1100ms | 13000ms，零失败 | 40/40 |
| F fe0b677 | 32/32/2，集合SQL校验 | 2305/0 | 730ms | 1000ms | 11000ms，零失败 | 40/40 |

D四舍五入P95桶为12秒，实际最长12.424秒；不是所有请求都在P95内。D169份签名状态全部有效，保守连续40就绪682.048秒。实际4条DB连接、等待峰30，池busy/timeout/reset/close失败均0；两层接入拒绝/派发/发送失败均0。停服后HTTP、池连接、合成租约均0，API/监控/容器正常停止且固定测试端口释放。D原严格标准未过，预算优先标准仍差最终存档时延。

A失败均为database_busy，C失败均为backend_busy。A有一笔失败发生在checkpoint提交之后，不能把全部503当作没有落库，不能自动重试结果不明的写入。旧失败数据、唯一恢复证据和测试库保留，不通过删除失败账号来制造清理成功。

## 修复及成本

原前端满槽会静默断开；新隔离接入实验返回固定503并限制backlog及等待。新HTTP源码有不可变父摘要和操作器绑定，旧候选不改。实际数据库连接仍4，原请求截止时间、交易、幂等键、权限检查和失败隔离保持。

FIFO等待者在notify后重新拿到互斥锁之前仍占等待名额。HTTP32配等待28在“连接已归还但旧等待者尚未取得锁”窗口仍会拒绝新的下一次RPC；受控原生线程复现确认，等待32覆盖该窗口。队首Condition通知替代正常归还时notify_all；不直接移交连接，关闭时仍唤醒全部等待者。正常通知由O(Q)变O(1)，关闭O(Q)，空间O(Q)，Q≤32。通知尝试次数不是原生唤醒耗时或FPS。

源码准备/启动按源码字节一次验证，最多三层精确绑定；请求热路径没有新增全玩家/全表扫描或源码读取。诊断只输出固定类别、次数、耗时和字节数，每进程最多60条/分钟、300条/24小时、4096字节/条；不记录账号、认证、SQL文本。采样P95不能替代完整HTTP P95。

C与D的112个准备源文件逐项同字节，仅PG限额1→2CPU。D40个最终存档全部有后端采样：耗时中位7.994秒，累计池等待中位6.821秒，同记录等待占比中位83.71%。40个final共440RPC，guard/query/commit/reset累计43.564连接秒，除4连接为10.891秒；这是本次观测成本的下界，不是未来固定成本。C仅36个被接纳成功，不能把两组中位差称为逐请求配对因果结论。D未捕获final原生CPU窗口，不作峰值或无节流判断。

## 下一轮与明确待办

E `f5488f3a48df3c119e6a9ef6a6bce37c`已完成：HTTP8/等待8、PWA48、DB4、PG2CPU/2GiB，backlog64、accept等待2秒及原请求20秒截止不变。与D所有运行/配置表/SQL字节相同，仅三个操作器模块及配置绑定变化。2269HTTP零错、40完整清理、169/169有效签名、保守连续40就绪682.254秒，全部服务正常停止且HTTP/池/租约0。最终存档P95为13秒、最长13.019秒，两套标准仍分别未过；不采用HTTP8作为性能改善，也未进入100。

E后端handler final中位仅2.159秒、内部池等待0.998秒，显著低于D；但同服完整final批次12.008→12.794秒，连接占用43.564→47.350连接秒。等待移到了handler以外，完整吞吐没有改善。实际后台8槽全满、28次accept等待、最长1.892秒，无拒绝/超时；前端峰40、池等待峰7。E原生采样真实窗口13:29:16.044–35.106UTC，只覆盖final尾部并含空闲，不能当完整final峰值或与D缺失的原生窗口比较。

存档初始化SQL候选已在独立2账号PG17.11库完成30用例/60事务arm原生差分（10组成功、20组错误，每版各一次），结果一致，逐arm回滚及函数元数据/列约束/8表状态恢复全部通过。原生回执`c8e70da7…`、独立审计`ca546d44…`；SET LOCAL ROLE的session_user仍postgres，不替代真实app登录、权限重置或性能证明。2账号测试容器最后正常停止、端口释放、exit0、无OOM。

该烟测首次容器启动后，检查脚本用了不兼容的Podman模板字段`{{json .Id}}`，导致初始化前检查及同路径清理均未获确认。只读完整JSON在远端内存筛选，确认唯一ID/双标签/镜像及running、无OOM，实测`.Id`退出125而`.ID`成功。新恢复01绑定旧失败原始摘要，确认8表零/marker未seed后仅seed一次及ANALYZE，再做原生验证；未重跑启动、覆写旧回执或未知写重试。未执行的恢复02保留并标记未使用。

F40已完成同D的HTTP32/Q32/PG2CPU/2GiB、10万薄档案/40活跃/840秒，只把原SQL56467改为原生验证过的600eb5，其他运行Python/Lua/配置表保持。集合校验完整103字段的内部SQL边界107→5，非RPC数；空对象4→5，元数据仍O(M log A)、排序O(M log M)。新隔离开关只在prepare/启动核来源，热路径没有新增本地读取。

F2305次真实HTTP零失败，ASSERT/invalid0，40次final与release全成功、40完整清理；169/169签名有效，保守连续满员682.175秒。报告UTC13:49:41–14:03:52共851秒，真实约2.709HTTP/s；发生器CPU峰3.4%单核、RSS约137.5MB，不是发生器满载。读档P95730ms、周期1000ms、最终11000ms/最长11469ms；原严格及预算标准分别保留，预算仍仅final超10秒而未过。D→F最终P95约12→11秒，读档640→730ms，单次分桶差异不能证明整体容量改善。没有进入100或调整验收目标，API/监控/PG全部正常停止且端口释放、租约0，数据保留。

F完整证据pending为空。实际4连接/Q32/2秒、等待峰31、14395次归还，busy/timeout/reset/close失败均0；后台32槽、2149接纳且完成，前端48槽、2476完成，两层拒绝/派发/发送错误0。PG2CPU/2GiB实配一致、正常退出无OOM；170个窗口内系统样本覆盖完整，无观测错误，采样CPU均17.203%/峰57.702%，TX峰0.849Mbps包含SSH，不能当公网账单或连续峰值。

F仍每个final11RPC；后端中位7.728秒，其中累计池等待6.539秒，同记录等待占比中位约83.93%。业务SQL query累计中位278ms（D308ms）、guard515ms（D524ms），不把小幅组间差异单独归因于ensure。下一步需减少同一结算路径可证明重复的数据库往返，保留drain/客户端profile及grants、交易、幂等、权限和重置合同，然后重新40人完整验收；不直接放宽deadline或跳到100。

这里的元数据复杂度是索引查找下的理论成本，实际执行计划也可能采用O(M+A)的hash连接；本轮没有用EXPLAIN证明具体计划，不能将文档复杂度当作实测耗时。F相对D共有7项来源差异：除SQL和新增证明模块/补丁外，还继承了E已审阅的可选配置验证工具变化，HTTP仍选择D的32/Q32。操作器并非逐字节相同；业务运行Python/Lua/配置表均逐项同字节，新证明只在准备/启动执行。详见`D_to_F_source_cleanup_verification_receipt.json`。

重复权限查询、数字编码及异步ACK路径仅为只读审查，未改正式后台。final还用于断线、淘汰、重连，游戏仍消费profile/grants，不能简单省略或立即ACK。真正异步方案还需持久worker、版本绑定、账号顺序及读取水位，不纳入这次SQL实验。

100/200/500/1000/2000/4000阶梯仍以完整门禁、接入预算及清理审查为前提；PWA48尚不适用于100同时请求。没有通过低阶梯前不盲目加并发，也未进行4000容量认证。

## 真实证据位置

树外根目录：`D:/Survival_本地工具/runs/shanghai_stage40_fix_20261113_01`；独立候选根：`D:/Survival_本地工具/runs/shanghai_test_20261113`。所有新候选/验证/采集回执按真实来源登记到`D:/Survival_清理记录/records`，未自动扫描或删除旧产物。

- A完整：`analysis_stage40_full_01/analysis_receipt.json`。
- C完整：`analysis_stage40_notify_full_01/analysis_receipt.json`。
- D完整：`analysis_stage40_notify_cpu2_full_01/analysis_receipt.json`；分段：`stage40_notify_cpu2_checkpoint_timing_analysis_receipt.json`。
- E完整：`analysis_stage40_admission8_full_01/analysis_receipt.json`，SHA256 `856b1623fc1225200d32670a256cf5c740b9d721941668767efd05ddf2e80ef7`；原生尾段：`native_admission8_final_window_observation_receipt.json`。
- F完整：`analysis_stage40_setdefaults_full_01/analysis_receipt.json`，SHA256 `fbc23d85befa633a3e785abd6c1e23b1339c535a4f1a71e1beb92f35c19c88b1`；原生40样本：`native_setdefaults_final_window_observation_receipt.json`。F源/operator绑定`0a1befe74bb74ba21582ffc6b401f2deabdc2d95`；V6验证9个发生器消费者，旧V5及其回执保持。
- C→D：`C_to_D_source_cleanup_verification_receipt.json`；D→E：`D_to_E_source_cleanup_verification_receipt.json`。
- E预定标准：`admission8_cpu2_plan_receipt.json`；8源实际发生器绑定：`driver_notify_candidate/run_locust_stage_v5.py`。
- 原生SQL审计：`native_gameplay_defaults_actual_semantic_audit_receipt.json`；实际60事务：`native_gameplay_defaults_06_bridge_operations_01/native_execute_01/verification_receipt.json`；实际停服：`native06_final_stop_receipt.json`。F40预定标准：`setdefaults_cpu2_plan_receipt.json`。
- 工具提交及双仓固定流程：`experiment_tools_git_sync_receipt.json`、`notify_tools_git_sync_receipt.json`、`admission8_tools_git_sync_receipt.json`。

本轮保留另一窗口14项未提交改动及全部原有stash；不把它们混入工具提交。game `dev`工具提交依次`e5ffd1d7`、`40bc3d32`、`e09a9f98`、`0a1befe7`；content `master`无本轮源码变更，核对/拉取/推送后仍`6dbd9358`。

E上传原回执因缺少登记器识别的存储字段被拒绝（`receipt_has_no_known_storage_bindings`），原回执保留；另建真实归档观察补登记，明确本次观察不是原生成时间，归档SHA核验一致，登记`c014fd90…`成功。没有为登记改写原上传回执或旧日期。
