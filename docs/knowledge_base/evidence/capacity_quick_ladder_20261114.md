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

## 尚未执行的100人和继续条件

新100人run `7a6d572003e557c78bd3b77524d71d8f`，manifest `edb6b86c1cecff6450dbfc7c057954b0d182967e2771cf17f8ae4d4ea84a81da` 已准备，131源与获准并通过的两账号版完全相同。V9/V12及收尾控件已独立复核、冻结登记；计划100/180秒/spawn5，保留原五项延迟、连续ready、完整WF/SQL/清理门。

上传原命令两次被自动审批拒绝，均在CreateProcess前，100档没有上传、启动、业务请求或远程新run。拒绝理由是需要用户明确授权这批内部131源向47.116.11.179上传；已向用户提出具体payload/独立目录确认，尚待答复。原拒绝证据 `striped100_upload_approval_block_01/refusal_receipt.json` SHA `72b215a04ec27a45e37b93eba34d1f8205b020825917f24e8893e590bfaf9e41`。没有改入口绕过，也没有重写成成功上传回执。

获明确授权后，继续原OpsV5 upload/bootstrap/warmup→正确Locust venv的V12真实100→API正常stop→PG仍运行时只读SQL03→PG/monitor正常stop→首次V9采集→SQLite终态→原分析器。命令清单 `striped100_post_controls_01/command_list.json`；SQL03仍原27needs、14受保护表及45秒只读限制，失败保持失败，不静默重试。按实际结果再决定200及更高档，未达满员时不跑空的4000四小时。

## 流量模型与采购边界

按当前client-v3，理想低延迟、4000人全部ready且4人满房的稳态约227.111HTTP/s；2人/1人房约260.444/327.111。均未计登录、发奖刷新和集中退出，不是实测容量或峰值。100人整个混合运行成功响应体均值约2.4KB，只能作包体算例，不能证明7Mbps足够或据此开月账单。见树外 `steady_request_model_01` 与 `steady_request_model_02`。

用户738/月与1012/月仍为参考报价，含盘/优惠/续费未独立核实。官方变配矩阵不保证现e能直接变c9i/u2a，Intel/AMD跨平台和回退有约束；先询价并在取得具体费用授权后新建一档按量临时机验证，不能承诺核数线性或当前方案可hold4000。旁证保存在 `survival_capacity_autonomous_20261113_01/budget_review_20261114/purchase_preflight_20261114_1935/purchase_preflight.md`。

旧源40人/10万成熟账号四小时通过仍限于[原证据](capacity_autonomous_20261114.md)，不自动变成新源100或4000通过。本轮不进行移交到其他对话的游戏卡顿修复。
