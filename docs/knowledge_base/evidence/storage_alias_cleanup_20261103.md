# 2026-11-03｜旧测试 addon 与排演存储清理

本轮仅本地磁盘清理，无运行资源改动，无工坊、后台、支付或玩家数据写入。用户授权清理旧 `svt_*`、C 盘归档并检查 D 盘本地排演；不得据此把尚待验收/发布的客户端标为已同步。当前其他任务的发行状态仍以各自最新真实回执为准。

## 已完成

- 删除 game addon 下 `svt_f1104`、`svt_m2902`、`svt_m3001`、`svt_m3002`、`svt_m3003`、`svt_m3004`、`svt_m3101`、`svt_s3102` 八个旧原生测试副本，以及对应八个空 content 目录。它们是历史 `INSTALLED_FOR_NATIVE_TEST_ONLY` 副本，非主 `survival`。删除前逐资源核对副本与树外签名来源 SHA256，共 54,992 份资源、两侧 109,984 次资源哈希；额外文件仅 Tools 可再生缓存。已移除逻辑文件 30,304,751,974 字节（28.22 GiB），外部来源和回执全部保留。第一次目录删除未完成后按剩余清单复核并完成第二轮，失败回执不覆盖。
- `C:\Survival_排演归档` 是此前转移到 C 盘的真实历史排演恢复资料，不是游戏安装需求。全部 129 份文件、30,304,999,690 字节迁至 `D:\Survival_排演归档`，逐文件 SHA256 和有效 Owner/Group/DACL 核对后才删除 C 原目录；原 SDDL 留存，SACL 未独立验证。新根 `_C_migration_20261103.json` 保留迁移对应关系，SHA256 为 `f6e50e726bc9ac2f8a73b97b6c6d6497877bf8241d05a96d9c95d12eaeddb15d`。四处旧 D 路径新增 `ARCHIVE_RELOCATED_20261103.json`，原 `ARCHIVED_TO_C_20261102.json` 不改写。
- D 盘七个已确认恢复完成的旧排演目录启用 NTFS 无损压缩，文件数、长度、最后写入时间前后核对一致，未删除恢复文件。独立复测共 213 文件、54,105,510,358 逻辑字节，存储量 31,919,158,283 字节；压缩并非逐内容重哈希验收。不触碰当前 `20261103_ws4_lottery_redemption_v12`，也不触碰未收口 `20261101_ws4_shared_boss_portrait_v07/run03_shared_boss_portrait`。整个 `D:\Survival_本地排演` 不能直接删除。

七个压缩叶目录：five_account_portrait_v05/run01；shared_boss_portrait_v07/run01、run02、run04；lottery_replay_v11/run01；lottery_snapshot_v10/run05；shared_boss_portrait_v08/run01。完整路径在机器摘要。

## 复核、指标边界与权限报错

独立检查八个 game 和 content 目标均不存在、树外来源仍存在、C 归档已不存在、D 归档 130 文件（含迁移元数据）和迁移摘要一致，主工程及受保护目录存在。D 归档含元数据共 30,305,114,165 逻辑字节、17,850,113,120 存储字节。检查时 C 可用 34,611,118,080 字节、D 可用 33,673,404,416 字节；并发测试可能继续改变余量，不能把磁盘净变化全部归因本轮。

原压缩 v01 回执对 OrderedDictionary 使用属性求和，导致 before/logical 错为 0、saved 为负；这些统计作废，原记录保留。v02 使用独立文件长度和 Win32 GetCompressedFileSizeW 重新测量当前值；压缩前物理总量未知，不声称精确释放量。实际压缩、文件保留核对和退出码成功与错误统计分别记录。

`failed to load workspace requirements: permission denied` 在本机 Codex `responses_retry` 和 turn 日志中出现，属于工作区要求加载被拒绝；日志未给出具体被拒路径。当前 AGENTS.md 及工程可读，检查和清理工具可执行，不能据此断言项目文件损坏、清理失败或本地 ACL 一定异常。本轮没有扩大访问权限、修改 Codex 配置或重启正在工作的客户端。官方排查参考：Windows sandbox 文档建议分别检查权限配置、managed requirements 与 Windows 文件权限；本轮未确定具体拒绝来源。

## 证据与成本

原始脚本/清单在忽略目录 `output/storage_alias_cleanup_20261103`，`closeout_v02.safe.json` 是最终独立检查，`c_archive_migration_v01.safe.json` 与 `deleted_aliases_v02.safe.json` 为成功执行回执；原失败/错误统计仍保留。脱敏摘要见 [机器结果](storage_alias_cleanup_20261103.public.json)。无凭据进入知识库。

本轮均为一次性维护：资源核对哈希 O(B) 字节读取、迁移 O(B) 读取/写入与复核，集合存储 O(N)。独立收口 O(N) 文件元数据/API 调用，仅扫描明确目标；旧预检在单目录元数据判断曾使用列表查找，最坏 O(N²)，执行后已改为分别遍历文件和目录，不能把历史执行冒称全部线性。没有新增游戏计时器、帧循环或刷新查询，没有 FPS 验收结论。
