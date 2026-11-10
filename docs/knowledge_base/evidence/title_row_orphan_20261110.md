# 称号卸下后左上角残留整行UI（2026-11-10）

用户截图为“登峰造极／已穿戴／已穿戴·点击卸下”的整行存档卡片出现在HUD左上角，不是tooltip。本轮前的已发布1004不包含该修复；用户已正常退出Dota/Tools、Steam保持登录。

## 根因与修复

称号点击会将旧控制器行fingerprint置空，等待回包重绑操作。卸下的既有语义是恢复最高档自动选择，因此最高称号可能仍是同一个：新旧权威显示数据完全相同。旧render临时将保留的V10 host移到HUD根节点，再删除旧版装饰子节点；而V10的displayKey命中相同数据缓存，提前返回，没有把host挂回card。这个完整行在根节点的0,0位置显示，关闭存档窗口也不会跟着隐藏，正好对应截图。

已用真实旧控制器和V10渲染器复现到“same-result unequip must keep title visual under its owner”断言失败；这是合成生命周期复现，没有宣称原生截图取证。修复不把host移出card：只有sourceArtKey一致才保留已有host，只删除该card的旧版装饰子节点；重绑后把新建旧版标签隐藏，避免displayKey命中时重复显示两套文字。美术身份变化时仍按既有路径销毁和重建视觉。没有改变称号解锁、穿戴/卸下协议、存档或自动选择规则。

game panorama/src/scripts 与 content panorama/scripts 的 archive_180de7e38b_titles_compact_v6.js 配套修改。

## 成本与验证

新增逻辑只进入真正fingerprint变化的已有行。每个变化行直接子节点C约3至8个，删除/隐藏共两次O(C)访问，不查HUD或场景集合；美术键比较O(L)，L为固定几个字段长度，额外空间O(C)由原生Children返回数组产生。初始化无新面板或索引；稳定快照继续命中旧fingerprint，无新增子节点枚举、创建或reparent。K个变化行总O(K*C)，原全快照外层N行行为未扩展，没有新增计时器、轮询或网络请求。没有为防泄漏强制全页重绘。

树外 D:/Survival_本地工具/runs/20261110_title_row_orphan01 保存原始字节备份、双仓stash/pull/精确pop记录、候选回执、旧源码负对照和相关回归。20轮卸下同结果/关闭重开、拒绝回包、真实状态切换、图标身份更换、HUD销毁检查通过；1000稳定快照新增面板0、reparent0、称号card子节点枚举0，HUD根临时挂行0。原V10生命周期、图标、语义、共享tooltip、打开后profile刷新套件全部通过。离线调用计数不是实机FPS或新版本视觉验收。

## 1005 已完整交付

固定任务 pack_2026111005_7453969b 已完成 build/publish-test。当前游廊2026111005，原封闭条目3824360109，Steam manifest 8113612381032502226；7056资源、5包文件官方完整下载逐文件一致，186保护模块通过。工具最终 WORKSHOP_SYNCED，完整待发资源/源码/历史来源/阻断/dirty runtime均0。普通新客户端视觉与实机FPS仍待用户测试，不能以离线检查冒充实机验收。后台未改，无玩家交易或自动启动游戏。

官方隔离编译2项（称号控制器与本轮静态目录）；称号控制器实际DATA与不可变作者的编译输入摘要一致，262项回归全部通过，1000稳定快照新增面板、称号card子节点枚举和reparent均0，临时HUD根挂行0。备份、候选、实际编译及最终交付回执均按真实证据登记，旧产物未清理。

- 原始作者提交：game e0631f72cbfdb0483d1432152746bfbe9f7978d8，content 93ff7e3bf6741e78ca81c8324394ca148d827ce1。
- 最终运行来源：game 2f7ece1eb850b0f758e9818c36d00a3e4b2dabba，content 46380333f91d451d057f059c2b685a3c1c7b676c；实际发布operator f42f98fcf7d3cde6c768efd05055b960cdad7e64。双仓定向提交/push且执行约定stash/pull/精确pop，历史stash与原有5项无关改动保留。
- 包回执 output/packager/pack_2026111005_7453969b/package.json，SHA256 a896a52a34996daac04fb1660768d054eb9527eae9eb4cdf39e2712d6716aa47。
- 签名manifest SHA256 f2bd56b71dc9f28244e5ee9f0d831a89003550f3b17eb92c2e83a94bd2caea27；完整内容 SHA256 804404d9e288d528cc1319260e66f26526e42d7aeae8686ee1320787825a7b12。
- 官方下载回执 output/packager/pack_2026111005_7453969b/download_evidence/20261110T083400Z_6fa62452332d4c12b116927dac769714/verification.json，SHA256 31d928e3de07f292f6aaf061da0e8f55a9f00ae948c0e65b997a799947d7c757。
- 树外 official_data_verification.json、candidate_verification.json、source_verification.json、related_verification.json、final_delivery_receipt.json 与固定工具完整阶段回执保留。
