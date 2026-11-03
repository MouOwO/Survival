# 2026-11-03｜已恢复排演与旧工坊输出清理

本轮仅本地清理，运行资源新增/修改/删除清单为空，后台与工坊零写入。用户明确追加要求清理 `D:\Survival_本地排演` 和 `D:\Survival_工坊输出`。此前压缩旧排演而未删除属于上一轮状态；本轮按新要求核对重复包后进一步清理，不追改历史回执。

## 实际移除

- 10轮已完整恢复到0104的旧排演，共301文件、76,834,231,816逻辑字节（约71.56GiB）。包含v05/run01，Boss v07/run01、02、04，lottery replay v11/run01，snapshot v10/run02—05，resolution v08/run01。三个无其他事务的旧family连同根锁文件整体移除，其余仅移除已恢复的叶目录。
- 32个10月旧工坊输出目录，共78份文件、57,674,009,992逻辑字节（约53.71GiB），含15个旧空目录及若干不完整旧包。仅固定 `D:\Survival_工坊输出` 的10月22—30日直接子目录，排除 `20261029_ws4_archive_all_v01`。不完整旧包不冒称通过原生验收，也不用于恢复。

每轮排演均须有真实 `ORIGINAL0104_FIVE_FILES_FULLY_RESTORED` 回执，其original文件表与transaction一致。100份VPK及一个遗留work恢复临时副本，共101份大文件逐SHA256确认与17份保留的canonical成包文件一致；所有canonical来源都在删除集合之外。缓存按底层file ID/长度/mtime建立，仅同一文件身份复用hash，没有因大小/预期hash相同跳过不同副本的校验。

## 保留与恢复依据

完整保留当前0301 family（run01、run02均已有恢复记录，但仍是当前候选资料）、`network50_probe_20261103`、缺少恢复收口记录的Boss v07/run03。保留正式0104、当前0301、全部11月工坊成包、3101/3102旧基线、interrupted_pack_01未收口证据与10/29 archive_all基线。此前迁移到 `D:\Survival_排演归档` 的恢复资料不在本轮删除范围。正式Workshop安装、ACF、玩家/后台、Git源码、密钥及当前验收文件未修改。

217份原始回执、过程记录和旧VPK小索引压缩保存到 `D:\Survival_清理记录\20261103_排演与工坊输出\closed_receipts_and_old_vpk_indexes.zip`，逐ZIP成员SHA256核对；完整清单另存inventory_before.zip。cleanup_plan.json含101份副本到保留源的对应关系、摘要、删除与保护范围，execution_receipt.json和verified_closeout.json记录实际执行及后验。本轮不往C盘搬大文件，不另复制整套大包。

旧已收口事务目录已退休，不能再对这些路径运行恢复命令。需要旧证据时读取外部ZIP；需要旧候选时使用保留canonical成包另建独立LAB。当前或未收口事务仍用原生命周期工具处理，不假造历史restore回执。

## 空间与验证

按底层file ID计数，仅目标包含全部硬链接名称才计入释放量，使用Win32压缩存储量求和：预计可回收69,114,129,386字节，约64.37GiB。执行前D盘可用161,275,813,888字节，执行后230,390,919,168字节；并发工作可能影响磁盘净变化，不作精确独占归因。先前压缩占用与本轮删除不能重复算两次释放量。

执行在同一canonical发行文件锁内；删除前再次核对固定绝对路径、无reparse、逐文件长度/mtime、恢复回执摘要和保护范围；仅解除精确文件名称，不修改共享文件内容/只读属性。42个目标实际不存在，保护路径及canonical来源存在，保护VPK的file ID/长度/mtime保持；journal原始摘要不变。清理后再次完整验证0104与0301签名、运行资源及五卷VPK通过。当前完整发行计划仍因另一任务修改 `tools/release_pipeline.py` 而被拒；此既有operator阻断没有通过改门禁、回滚其他工作或清理来消除。

正式远端仍按既有0104 / Steam manifest `7025356658517360342` 证据记录，本轮没有上传或官方完整下载，不能写已同步游廊。其他任务新运行修复与发行待办继续保留。

## 成本与本机证据

元数据单次索引548文件、约0.04秒；预检174次唯一文件hash、111,499,240,226字节读取，约138.56秒，属完整副本安全核对，不是游戏性能/FPS。一次性集合索引及删除O(N)，流式hash O(B)，索引空间O(N)，没有游戏循环或常驻任务。

忽略目录 `output/storage_alias_cleanup_20261103` 中的 rehearsal_output_inventory/plan/deleted/closeout_v01 及 rehearsal_output_dependencies_after 记录真实步骤；树外清理证据独立保留。见[脱敏结果与完整目标路径](storage_rehearsal_output_cleanup_20261103.public.json)。
