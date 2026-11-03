# 2026-11-03｜旧发布候选展开副本清理

仅本地磁盘清理，运行文件变更清单为空，后台及工坊均零写入。用户明确要求检查 `D:\Survival_发布候选` 并删除过时内容；此次为本轮授权的人工清理，不是声称新版本已通过自动发行保留门禁或已同步游廊。

## 清理范围和保留范围

单次枚举152目录、369,558文件，用时18.14秒；逻辑总量204,606,368,599字节（190.55GiB），文件ID合并后的逻辑字节78,512,007,699。硬链接占比高，不能把目录逻辑量全部称作可释放空间。

已删除40个10月21—30日旧的完整展开视图，共266,842文件、150,853,447,153逻辑字节（140.49GiB）。每个目标须为 `_release_manifest.json` 声明的 `runtime_release_allowlist`；逐目标核对完整文件集、大小、mtime、file ID和无reparse，额外项仅签名、manifest和历史provenance/检查记录。删除使用精确绝对路径白名单、逐文件解除名称，不改写共享硬链接文件的内容或只读属性。

保留112个原目录，包括所有11月候选、0104正式基线、0301当前候选、3101/3102旧正式基线、`20261029_ws4_archive_all_v01_source/view`、全部overlay、trusted_source和源码增量。没有删除任何 `D:\Survival_工坊输出` 成包、正式Workshop安装、真实排演/恢复备份、工作区地图、Git源码、后台、密钥或玩家资料。未收口Boss事务和当前候选原生事务保持。以后复用已退休旧展开路径的历史测试，须先从Git或保留成包重新建立独立LAB，不能把旧脚本路径存在当作永久保证。

## 树外证据和释放量

删除前，112份原始manifest/签名/历史构建记录已压入 `D:\Survival_清理记录\20261103_旧发布候选\historical_manifests_signatures_provenance.zip`，ZIP成员逐SHA256复核通过；原369,558文件完整元数据清单另存 `inventory_before.zip`。计划、实际执行回执、独立收口均在同目录，未在C盘新建大归档。所有旧trusted_source/overlay仍在原位，不是只留下文档而删掉源码。

按目标内file ID索引计数，仅当目标包含该底层文件的全部硬链接名称才计入回收，再以GetCompressedFileSizeW测量压缩存储量：70,114,505,258字节，约65.30GiB。执行前D可用90,774,769,664字节，执行后161,346,494,464字节；净变化含文件系统元数据及并发任务影响，不作为精确独占释放量。其余候选逻辑量按原清单约50.06GiB，不能等同实际磁盘独占量。

## 清理后验证与发行边界

执行期间持有与正式发行相同的canonical文件锁，只用于防止同时发布；不写journal、不使用UGC接口。当前journal原始SHA保持不变。40个目标确实不存在，112个保留目录确实存在；归档摘要、ZIP完整性独立核对。清理前后均完整验证0104基线与0301候选的签名、运行资源和VPK五文件，内容摘要保持一致：0104为 `6ffc0816d040ffe4a4d7a3db472c74dc18b96fad36f5f204cba5b0879ab5489f`，0301为 `6de5f3d485bb619c99a3ecaf887f6803dd5ba04c21a88718317ca191491f4338`。实际读取仅涉及这两版view/trusted_source，与删除集合无交集。

发行全计划在清理前已有 `DIRTY_OR_UNCOMMITTED_AUXILIARY_INPUT: tools/release_pipeline.py`，因为另一任务正在修改发行工具；该阻断保留，不通过改门禁或回滚其他改动伪装发布通过。上面的独立字节保留检查不替代新operator绑定、原生验收、SDK上传或官方完整下载。正式0104 / Steam manifest `7025356658517360342` 的历史状态未由本轮修改。

维护成本：单次O(N)元数据索引、O(N)文件集核对及删除、O(U)底层file ID计数，空间O(N)；当前基线/候选完整复核为O(B)字节读取，前后各一次，无游戏循环或常驻扫描。预检14837次文件系统audit事件只代表该次独立验证计数，不是原生帧耗时/FPS或网络请求数。代码/游戏性能未在此任务验收。

工具和详细本机回执：`output/storage_alias_cleanup_20261103/`，尤其 `candidate_cleanup_plan_v01.private.json`、`candidate_deleted_v01.safe.json`、`candidate_dependencies_before/after.safe.json`、`candidate_closeout_v01.safe.json`。脱敏摘要见[机器结果](storage_candidates_cleanup_20261103.public.json)。
