# 首次存档UI报文预算修复与验收边界（2026-11-01）

新冷Tools/offline日志已独立共享读取：20个完整页面摘要合计945行、108个分包，最大JSON估算5928字节；后续40个增量页面摘要正常，已读214709字节/1999行中无CustomEvent序列化失败、reliable-too-big、SnapshotError、UI拒绝或脚本运行错误。用户确认查看结果正常并要求继续；这是用户验收和一局开发日志范围，不是root全玩法、普通生产或长局通过。详情及安全原件SHA见[脱敏指标](../knowledge_base/evidence/archive_ui_wire_budget_20261101.public.json)。root先前.NET共享读取失败产生的0计数没有作为证据。

## 实际修改

只改`archive_service.lua`。保留M.snapshot完整daily_limits、服务器额度和全部道具/库存；UI wire投影去掉没有显示/校验消费者的daily_limits，连增量baseline也使用相同投影。每页只创建一次metadata视图，分包时只复制header与本包rows，不再copy整页rows后立即丢弃。

发送前用core/json_encoder计算header及逐row成本，6KiB预算预留固定256字节，且每包最多12行。全部row先通过可分性检查；单个header/row不可分且超预算会明确REJECT，不丢字段、造数据或建立baseline。每个实际packet再核JSON上界。仅所有同步Send调用返回后才提交sent_pages；中途异常保留旧baseline，重试不会把未完整发出的页当成delta基础。没有新增调度器/定时器；Tools且严格offline provider下只记录每页计数，不输出payload/账号。

source raw SHA `51b554d203485c1ccad6fa9d91cd197cf91ff6400e572e3cdf8c7455f617cd4b`；GitLF SHA `6a50c80d15ba98374d8a7df31aa664112070a8ffb4e8b71867a0fd1ae2cddec4`。运行源码在原生冷复验前已冻结，之后只补测试/文档。

## 成本与可复现检查

令R为全部页面行数945，H为不含rows/daily_limits的metadata，C为分包数。原发送循环每包深拷贝整页再丢弃那份rows，transport部分为O(ΣCᵢ(Rᵢ+Hᵢ))；现在逐页metadata投影、逐row一次估长、每包只复制其行，为O(R+ΣCᵢHᵢ+编码字节量)，另完整baseline缓存一次O(R+H)。范围规划只存每包边界O(Cᵢ)，没有后台全表扫描或新timer。按实际目录推导的transport行记录深拷贝数9346→1890；这是代码/目录推导，不是原生GPU或耗时计数。

| 阶段 | 可复现结果 |
| --- | --- |
| 初始化，真实projectors/合成空档案 | 20类945行；88→108包；总JSON1503242→552791，最大23490→5928；1093次JSON encode |
| 同状态事件 | 0次JSON encode、0次新增Send；原有全分类投影/diff仍存在，不声称整体O(1) |
| 合成P026库存/版本变化 | 84次encode、20个delta包，全部在预算内 |
| 原生冷日志首轮 | 20页/945行/108chunks，最大5928；随后40页delta，已读范围0对应错误 |

```powershell
& 'C:/Program Files/lua/bin/lua5.1.exe' scripts/vscripts/tests/test_archive_ui_wire_budget.lua
node tools/test_archive_ui_wire_budget.cjs
```

专项Lua通过实际目录全量预算、M.snapshot/真实quota上限、超大header/row整页拒绝、自定义projector私有参数、发送到chunk2异常后的完整baseline重试及稳定0编码/0发送。Node直接使用实际compact onArchiveSnapshot与实际ui_snapshot_cache.Apply，验证20分类945行完整页和增量在正/逆序下与服务器快照逐值一致，缺baseline必须重同步。两项均为隔离合成测试，0真实HTTP/持久化/native/UI调用。

旧大测试test_archive_service.lua:155及test_archive_retry_snapshot.lua:111分别仍受旧积分目录数量/空points假设影响；以未修改HEAD模块在独立Lua进程对照，原位置同样失败。保留原断言，未修旧fixture或宣称原样全套通过。

## 发行与剩余风险

6KiB只是JSON保守预算，不是原生protobuf字节或引擎上限；目前108包仍同步发送，未做聚合帧预算。旧9条native失败与7628未精确归属到某包/单位，不因本次成功而抹去；旧ETW后hang仍未定因。

已签13文件v02包2026110102保持原样、尚未发布（content `9535cee3defd7e2a9a4cb1ed5861e229481a4465ea44afdab958c04b33cf08aa`，source048a2d6）。它不含此archive修复；后续必须把该路径纳入14文件v03，完成新源码提交、计划/unsigned审阅、重新签名与生产/普通游廊实机，再按授权更新原条目。新14包、普通生产、多人与长局/FPS均未在本报告中记为通过。
