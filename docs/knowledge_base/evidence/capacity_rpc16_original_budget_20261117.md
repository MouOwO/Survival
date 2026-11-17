# 原连接预算内的16进程候选与组件证据（2026-11-17）

仅隔离候选，生产后台、游廊和费用采购均未改变；4000账号共同持续一小时目标仍未实现，不能把下述组件或离线准备称为容量通过。

## 当前运行和失败对照

- F144：`c9i_tracebudget_linux4000_slowhour_20261117_01`，run `b97b0df6e5b70a4c71c0002a4ce5bbe1`，源码`a0113c2379613bfbae4823de80662fc279c14be7`。100000个合成注册、4000目标账号、1人/秒加入、要求全部4000共同3600秒、120秒渐退。当前仍爬升，尚无最终结果；不能当作集中登录验收。
- F146原直接池对照在约2600账号后发生失败，已校验唯一拥有的Locust PID/argv/启动时间后SIGINT，正常物理关闭，SQL `NOT_CONFIRMED`，并非通过。预停止混合事件失败294，停机后的取消事件不冒充自然HTTP错误。
- 原12进程每进程串行执行，用约12条真实连接；池的配置总上限虽为16，并不会让单进程同时执行两次SQL。高负载旧采样BE约0.63核、FE约0.39核，不能据此宣布单进程GIL持续满载或内存不足。

## 新候选c9ba04c

不可变源码`c9ba04c3c5e857db3e6e64e93268444ffc81ada0`，已推送`capacity/rpc-sixteen-20261117`；准备后该工作区保持冻结。

新增显式`driver-process16-v1`，旧默认和3/6/12档不变。16个串行进程，每个最大1条连接、2个池等待位；配置总连接16、等待位32、在途RPC24、队列开始等待2秒均保留。原驱动SHA256 `6de9219de5a011160d6a96b524f2f2fe45a775925d9a1510dd2646392c81ad9c`、SQL、提交/复位、每次完整权限核验、业务协议全部不变；未知提交仍不重放。纯工作进程生命周期显式增加16档，实际回包编码进程仍为3。

初始化O(W×S)，W最多16、S为固定源码/目录大小；每次RPC仍O(报文字节＋固定阶段)，无账号遍历或权限结果缓存；固定监控从16个身份增至20个（FE＋BE＋16RPC＋monitor＋PGinit），每次监控O(W)。角色/身份集合按固定索引校验，完整处理进程退出、父死亡和清理。资源开销需由真实压测判断，不能从12→16推算玩家数同比增长。

## 已验证与未验证

- 相关回归共148项，15项因当前环境跳过；22项直接相关配置、预算、进程身份测试通过。日志`rpc_sixteen_postpull_regression_01.log`保留。
- 47.116.11.179独立组件使用原已关闭合成库`4fb699774c5f5e76cf0a10086a0447e7`，原驱动字节校验一致；加载新候选的两个进程模块，不替换旧库运行源码。实际16条连接，120次并发ready成功；过期/非法请求不发送SQL；子进程故障关闭且重放0；正常关闭16个工作进程，父死亡后16工作进程及1资源跟踪进程均退出。唯一指定合成库已正常关闭，业务HTTP和业务写入0。这不是真实业务吞吐测试。
- F147两账号门禁：run`3b749a82707c643d704de8c27cc866f7`；F1484000人一小时：run`76530072bd02def23d758fb5b2a99261`。全部147来源绑定和离线准备通过，当前尚未启动，不冒充通过。
- 有条件衔接执行器只在F144完整停止且原4000人验收未通过时启动F147；F147全部原门禁、SQL及正常清理通过才启动F148。若F144已满足原目标，不再启动下一轮。观察超时不重启实例。
- `verify_goal_4000_slow_01.py`与`verify_goal_4000_rpc16_01.py`分别绑定完整来源；必须有4000共同≥3600秒、原始HTTP/工作流零失败、签名有效、50个SQL执行和24个聚合检查完整、待处理归零、原字节回执/HTML摘要一致及所有拥有进程正常关闭。缺失证据明确不通过。

## 另一个未采用的SQL候选

在同一空闲隔离机、同一个已关闭合成库做原驱动完整RPC对照，候选只复用查询执行计划，每次仍读取全量权限与函数元数据，没有授权结果缓存。八轮AB/BA、每轮5预热＋50计时，ready中位4.368→3.765 ms（约1.160倍），`get_fishing_profile`7.666→7.046 ms（约1.088倍）。结果一致、原驱动未改、目录摘要前后相同、账号数不变，缺helper执行权限时拒绝；临时函数已删除、库已正常关闭。该收益只适用于组件，不作为4000人改善证明，当前未采用。

证据根`D:/Survival_本地工具/runs/capacity4000_linux_20261117_01`：
`sql_guard_cached_old179_01/{preparation,execution}_receipt.json`、`rpc_sixteen_component_old179_01/{preparation,upload,execution}_receipt.json`、`rpc_sixteen_preparation_01_receipt.json`、`rpc_sixteen_git_sync_01_receipt.json`、`rpc_sixteen_case_preparation_01_receipt.json`；全部历史失败及原始回执保留。

二进制小测试另在`capacity/binary-frame-20261117`候选，默认关闭；当前及新16进程容量候选均使用旧BW1协议，不把包体变化混入进程对照。


## LuaJIT实验拒绝采用（同日后续）

2000账号的只读采样中，FE约0.293核、BE约0.474核；另一个监控窗口BE每5秒回收的结算子进程累计CPU约5.06秒，约一个核。该成本不应遗漏为“后端自身CPU很低”。

为核对结算开销，在47.116.11.179树外独立目录从官方LuaJIT提交`63c8f1a9b479ba5518cf6a170ff7729178bc3cfd`构建CLI，未make install、未替换系统Lua。二进制SHA256 `8c1dbc040cf102757a77f08860c749384e20a8eccc957f47bb43c18891391812`。构建警告无法从归档git log确定rolling版本号，因此依赖身份以官方提交、原始归档摘要和真实二进制摘要绑定，不伪造版本日期。

首次组件01使用旧实验源码摘要，在任何结算执行前失败。已核对当前与旧隔离库三个实际运行文件均一致：结算器`61c51346fc526a76816810469b6a8f82e1fe9b0a548628e0d18d9ac897421234`、worker `4a85d79d97599f44bc5026bad154f0f2ffbe35b024151ca327a30625716d20b4`、Bundle `b2753aaba9b6138a1708a77dca3ef09e130f10e9920c5010245b8903453b4caa`。

组件02四项真实动作/种子回归及102个比较通过，六轮AB/BA的子进程CPU约1.848倍、墙钟约1.825倍；但其中额外online输入缺真实字段，两端都拒绝；只读snapshot的大数检查也不能证明可变状态保持。这些初步PASS不足以采用。

补强组件03强制有效在线结算成功并返回gameplay_stats；19次有效在线状态比较通过，随后第98个比较在大整数边界的在线结算返回值不同，整体`REJECTED_PARITY`。两个真实CLI对字面整数9007199254740991的输出分别为Lua5.3 `9007199254740991`、LuaJIT `9.007199254741e+15`。因此当前实现不能无损替换，**拒绝LuaJIT候选，不以更快为由放宽数据一致性**。当前F144和后续F147/F148均继续`/usr/bin/lua5.3`。

可选CLI曾复制到C9I独立目录，但上传器保留了禁止执行权限，版本探针返回PermissionError而未通过。旧`installation_receipt.json`的kind含verified字样，实际verification失败结果才是权威；`luajit_rejection_and_dependency_status_01_receipt.json`已明确更正，未修权限、未激活、未装系统组件。保留全部源包、失败及回执。

证据：`slow_case_profiles/near2000_receipt.json`、`luajit_native_tool_01/*receipt.json`、`luajit_settlement_component_01/02/03`、`luajit_numeric_boundary_diagnosis_01_receipt.json`。另一个`slow_trace_stage_diagnostics/near2500_receipt.json`为空诊断尾样本，其active_annotation误继承旧局，已用`slow_trace_annotation_correction_01_receipt.json`作废该显示字段；不据此推算当前人数或零耗时，原始绑定未改。
