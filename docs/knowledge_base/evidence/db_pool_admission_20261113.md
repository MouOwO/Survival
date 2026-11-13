# 2026-11-13｜数据库连接复用隔离候选

本轮按用户“开始下一步任务”实施后台连接复用、有界等待及安全错误分类。正式杭州后台和游廊未切换，无云资源购买。测试继续使用上海4核8GiB经济型机器。

## 源码与行为

初版实现提交 c4cddadfbc7e2a8f5647d9c90490ea0f062b3836，v2联动与收尾修复提交 edf1827d51a8423dae76febeae7a34abb63c301f（均game/dev）；content/master 6dbd93580c5a178412546a6535d59cbac88387c1无本轮变更。实际生产传输源码位于外部部署，故用v1三份持久reviewed overlay/helper及v2新增一份精确overlay导出各阶段候选，不修改旧快照。父postgres.py/server.py/timing源码与Git operator均按摘要绑定；默认baseline保持后台源码原字节。

- 每进程最多4条连接、最多4个FIFO等待者，排队最多2秒并受HTTP绝对期限约束（新建连接仍使用原3秒connect_timeout）；保持HTTP8、PWA24和2400次/分钟的原限制。
- 每个RPC仍在本事务内执行角色/函数权限检查、业务SQL及commit；任何事务异常回滚并丢弃连接，不自动重放。未知commit结果不解释成未写入。
- 成功commit后DISCARD ALL，再用一条参数化SQL恢复5项会话设置；禁用psycopg自动prepare，避免本地prepared cache与DISCARD失配。reset失败只淘汰连接，保留原成功结果；commit后期限已过则直接淘汰。
- 固定503错误只透传database_busy/database_timeout/database_unavailable，其他驱动细节脱敏，无retryable字段。HTTP socket计时器不等于取消在途SQL；当前仅在SQL边界检查剩余期限，原statement/lock timeout仍有效。
- 先停前端新请求、有限排空前后端，再关闭池；排空或关闭未完成不写成功。新增db_pool_wait/db_reset两个固定脱敏计时项，不记录账号或SQL。

复杂度：初始化O(1)且不预连、不添后台维护线程；借还索引O(1)，唤醒O(W<=4)，空间O(C+W)。只关服时一次O(C+HTTP并发)处理。原每RPC3条SQL（两权限+业务）变为成功事务5条（额外两条session reset）；物理连接由每RPC新建改为复用，不能声称SQL条数减少。每次请求仍验证权限，不扫描玩家集合。数据导入O(N)按1000行分批，ANALYZE只初始化一次，监控每5秒两条只读聚合SQL。

## 验证

27项池定向测试、24项实际回环HTTP/helper联合测试、220项lab绑定/关闭/统计检查和62项collector检查通过。27项使用模拟连接，不冒充真实数据库；220项包含合成SQL记录器，不冒充线上压测。

独立上海功能库 f6deea72d374a89c3690e8eb829cad7f，实际PostgreSQL17.11、512MiB/1CPU：真实PG28条检查记录（含10次重复ready、17种标签）通过。10次ready只新建1连接；测试会话GUC清理、回滚、权限撤销/恢复、后端断线、未知commit不重放。commit确认丢失为实际commit成功后注入OSError，该次RPC仅调用commit一次、合成session行数1；显式同ID再调仍1，不等同真实网络故障覆盖。reset失败实验为ready探针，不夸称业务奖励写入实验。

两账号真实HTTP39次（31业务/8控制），HTTP/解码错误0，十连只扣10券，福利/32波重放不重复变更，另一账号状态保持。API进程整个生命周期391次连接租用，仅1次新建、390次复用；含启动/SELECT1，不称391业务RPC。故障回归独立client的计数不并入API统计。正常排空、租约0、池closed且total0、容器exit0且无OOM，端口释放；未全量审计业务pending/outbox。

## 相同资源的20人对照

两组均实际种入100000合成注册、20个活跃夹具，PG2GiB/1CPU、HTTP8/DB4/PWA24/2400次每分钟。同一父版业务/静态配置、数字回包协议、公开目录MD5及Lua，operator按各阶段冻结（原版/v1为c4cddadf，最终v2为edf1827d），各自新空数据库；均种后显式ANALYZE、4次受保护ready预热，每4秒启动1人、原定240秒。随机加权业务路径相同但未固定同一随机序列；单组实验不等于统计显著重复实验。

原版run 2bc8150a3e126deb729bb8970706e1da，seed71.868秒，ANALYZE616.946ms。stage stage_20261113T081358Z_6846566ff0，HTML实际16:14:08–16:15:32（秒级84秒，duration文字1分23秒）。256统计事件=240真实HTTP+16ASSERT，33失败=17HTTP503+16ASSERT。峰值ready18/20，目标0秒；20次清理4成功、16失败。17HTTP失败均checkpoint，首错503 database_unavailable；统一label不能区分入局/周期。20条安全command时序均200且4RPC/4connect，没有503时序，不能把上一轮4RPC/3connect直接证据移用到此轮。

本轮原版P95分桶1700ms、均值482.60ms包含爬坡、失败、ASSERT及清理，不当作20人稳态成功延迟。实际阶段完整5秒区间主机CPU均18.62%、峰32.92%，iowait峰0.602%、steal0；默认网卡TX峰0.923Mbps含私网SSH。PG采样活跃峰2/连接3/锁等待0/idle-in-tx1；采样不证明短时从未4槽满。cgroup前后累计窗口另存，不冒充84秒专属计数。正常停止API/容器不表示16个失败结算已补成功，测试数据保留。

v1候选run d037935ffb91240f6a8c3b8c403d8b1e，原同资源/HTTP8/DB4/queue4，种数74.057秒，完成4分钟常规负载并达到20ready，累计目标162.669秒。收尾出现server_busy；API独立统计池opened4/reused2195/returned2199、等待61次、busy3、maxwaiting4、timeout0，说明连接复用实际生效，但接入/等待预算仍不足。

本轮同时暴露压测工具过早final：HTML/最终回执404事件/1失败，而同份wire424请求/404回包；cleanup_attempt20但完成/失败/中断全0。之后安全失败CSV继续变化，不能把404冒充完整实际HTTP总量或把部分P95当最终统计。停服回执仍有15合成租约未释放；HTTP前后端已排空，池已关闭total0、容器exit0无OOM。未知结算未自动补发，原数据保留。16:20:10–16:24:11窗口的监控可作为该时间窗资源观察，但不补齐丢失的业务最终回执。

因此增加新v2候选，保留v1/helper原语义；DB仍4，HTTP24/PWA24、FIFO等待20、2秒，显式build_application kwargs传参并核验实际pool_stats。范围约束queue0..32、wait>0且<=5秒、HTTP<=DB+queue。只lab设置20，普通后台main默认仍4等待者；正式systemd TasksMax64、HTTP线程+socket Timer+Lua子进程预算和部署接线尚未验收。唤醒成本随W为O(W<=20)，不声称扩队列提升SQL吞吐。

Locust修复正常停止时重入quit导致过早quitting的问题，单机/分布式均采用有限收尾协调；每用户清理也有绝对预算。所有HTTP发出/回包、统计路由和cleanup分区对齐才标完整。新增独立v3阶段驱动，以原版有效回执与已知过早候选作真实负对照，旧驱动保留。最终186项检查与10次真实Locust进程运行通过：76项/8组正常收尾成功、尾错、超时和旧版负对照，加既有110项首错回归。修后尾错16实际HTTP=wire16/16，4清理=3完成+1失败；超时明确1中断、wire14/13不完整并exit2，未释放fixture如实保留。未把本机模拟上游的进程回归当作上海真实业务压测。

v2最终run `991992127934a0c3cae55440f4c861a7`，operator `edf1827d51a8423dae76febeae7a34abb63c301f`，种数71.865秒；ANALYZE实际完成，用时 622.607ms，4次受保护ready全部200。实际PG仍2GiB/1CPU，真实池参数、requested/effective均为HTTP24/DB4/PWA24/W20/2秒。

stage `stage_20261113T084656Z_6c63035636`，HTML实际上海16:47:07–16:51:15，共248秒（240秒运行另含收尾）：

- 445统计事件全部真实HTTP，没有ASSERT；365业务、80控制，HTTP/数字解码错误0。请求/回包445/445，HTML/最终回执/路由计数/v3门禁全部对齐；Locust退出0，run_state stopped/complete且failed=false。
- 20/20达到客户端确认ready；整轮目标ready累计169.505秒，包含正常工作与首个退出前时间，不冒称独立60分钟稳定阶段。
- 20次最终清理全部完成，失败0、中断0；95次checkpoint均成功。API总447次=阶段445+额外停服控制2，最终HTTP在途0、合成租约0。
- 整阶段P50分桶230ms、P95分桶860ms、均值581.981ms，最长8271ms。**单独95次checkpoint均值1871.729ms、中位280ms、P95分桶8100ms，最长8271ms**，不能用总体860ms掩盖结算慢尾；本轮尚未定位慢尾属于哪一段，不据此断言CPU、锁、SQLite或带宽为唯一根因。
- API生命周期2377次借还=新开4+复用2373；最大物理连接4、等待212次、队列峰18/20，busy/timeout/connect/reset/close错误均0。含启动/ready探针，不称2377业务RPC。独立真实PG故障注入client的预期失败不并入API零错误统计。
- 正常排空前后端并关闭池total0，容器退出0无OOM；不因此宣称全库pending/outbox已审计或过去失败结算已补成功。
- 实际阶段49监控样本/48完整差分区间覆盖240.017秒，无采样错误；主机CPU均6.967%/峰16.759%，iowait峰0.856%、steal0；PG瞬时活跃峰3、连接4、锁等待0、idle-in-transaction1。五秒采样不代表连续极值，也不证明毫秒级从无锁等待。
- 默认网卡TX五秒平均峰1.082Mbps，包含SSH/私网；回包正文总1810017字节不含HTTP/SSH/TLS头，不能直接当公网账单或线性外推4000峰值。
- cgroup前后08:46:19.493544–08:52:17.073892 UTC，357.580348秒中CPU增35.753426秒、节流增5.497169秒/103周期，OOM增0；此窗口包括预热后及收尾后的空闲，不冒充248秒专属计数。

两账号v2功能库 `e62fce50bafcd72fdc5d954dca1fe4fb`再次通过真实PG28条检查与39HTTP、十连/福利/32波幂等和另一账号隔离；实际池W20核验，API391次借还只建1连接，正常排空、租约0。两个功能库的28条检查均含重复ready，不求和成56种独立故障。

这组实验仅证明当前配置在该合成负载下20人零错误并完整收尾；原版20人未就绪、旧候选收尾失败与过早统计均保留。两组随机加权命令序列、持续时长、v2接入参数不同，因此不计算“吞吐翻倍/延迟下降百分比”等单因果收益，也不将零错误等同4000容量或响应时延SLA全部通过。

最终只读核验本轮5个容器均停止/exit0/无OOM，10个已知API/监控PID均已退出，25432/29565/29567无监听；原sshd/nginx/DNS/HBR监听仍在，原服务未改。本轮未删任何数据。预热初稿漏测试Authorization得到401后已按真实合同纠正；最终监听检查初稿正则转义失败后改为简单拆分，两个失败回执均保留，没有改写成通过。

证据登记：v1功能5644994c…、原版628fd45d…、v1不完整b0f042c3…；v2功能ea9d4c2f…、v2完整阶段 `6a73ca25f589e564854e08cb36f725619d8083fcc32b890cdb9c1cc48f4c3b42`。原始及派生回执保存在同名results_01树外目录，源字节SHA/mtime和collector摘要可复核。最终服务器证据为 `final_server_state_v2_receipt.json`，首次失败另存原路径。


## 交付边界

当前是隔离候选，不是正式服务部署或4000容量认证。原40RPS门槛低于4000人每分钟结算66.7RPS；SQLite认证串行热点、其他业务预算、正式公开准入、RDS拓扑、公网Nginx/Steam/支付及7Mbps带宽仍需各自验证。未自动开放真人账户、消耗真人券、代兑兑换码或购买资源。下一步先对95次checkpoint的8.1秒P95慢尾做安全分段定位，再做100→500等阶梯；4000ready至少60分钟另做4小时长稳。10万数据为薄初始档案，长期重度档案、幂等表/备份增长尚未覆盖，不能凭本轮断言机器可承载4000或作最终采购承诺。

树外证据根 D:/Survival_本地工具/runs/shanghai_db_pool_20261113_01；全部旧快照、失败、容器数据、回执及其他窗口14份改动保留。

永久工具与复现实验步骤见 [loadtest_lab说明](../../../tools/loadtest_lab/README.md)。本轮仍是分步运维，不是一键全流程/RDS适配或正式上线交付。
