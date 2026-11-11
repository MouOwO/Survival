# 2026-11-11 账号清档入口审计与独立维护工具

用户要求检查游廊清档指令、移除入口，并提供包含兑换码领取情况的远程 CMD 清理工具。没有指定真实目标账号，本轮未清理真实账号、未停止线上服务、未兑换或创建订单。

## 审计与变更

旧 `debug/payment_test_commands.lua` 注册 `refreshdata`、`refreshmoney`，要求 development + server + Tools + 网页认证关闭。实际1009签名候选的 release_profile 是 production，所以普通游廊不会注册这两个命令；不能据此声称线上玩家原本能随意清档。

现在模块保留无操作 init 以兼容旧离线调用，删除所有注册；payment_service 删除 reset_player、reset 请求和缓存分支，仅保留 catalog/create/status/cancel。后台源码一并删除旧 HTTP reset 路由及 begin_reset/finish_reset 调用映射。WS4 隔离路由原本已不提供 reset，网页登录代理也不接受该路径。历史 SQL 函数保留，不执行数据库迁移。后台源码尚未部署。

根目录 `远程清理账号.cmd` 进入 `tools/account_cleanup/cli.py`。固定 SSH 主机密钥、已有私钥、仅管理员维护电脑使用；无游戏或网页管理入口。预览显示规范化 AccountID/SteamID64 与各表行数，实际执行要求完整目标确认语及维护停服确认。源码必须与 Git blob 一致，目标结构合同、服务版本/进程和账号摘要再次核对。

清理23张身份相关表，含档案/属性/库存/权益/限额/排行/会话、支付充值、兑换领取与尝试、奖励幂等；删除对应领取时减 reserved_count，码定义保留。保留身份行、提高版本和重建初始 onboarding；管理员准入 enabled 不变。认证 SQLite 清理目标旧会话/授权/流程/账号限流，其他账号及共享 IP 限流保留。

实际执行才短暂停止 WS4 web/payment/archive，先备份完整 PostgreSQL 和 SQLite，私有原始数据只存 root 目录；锁表内单事务删除并恢复唯一奖励触发器。未结订单、旧预览或结构变化阻断。COMMIT 回执丢失仅只读核对前后指纹，不重放；真正未知时不启动写服务，失败恢复逐一尝试。详细使用、恢复路径和限制见工具 README（项目源码路径 `tools/account_cleanup/README.md`）。

## 验证与保留

树外证据根：`D:/Survival_本地工具/runs/20261111_account_cleanup01`。源码备份8项及 SHA 已登记。旧聊天模块和旧 payment_service 均触发新断言失败；当前聊天组合8项无注册，四组 Lua 支付/认证/发布门禁通过，发布门禁178项。发布测试夹具补齐现有 compact transport 所需 GetGameModeEntity 空接口，没有改动运行时退路。

维护本地5项测试含真实认证 SQLite 结构的双合成账号；9项编排故障测试覆盖仅预览、错误账号、未结单、备份失败、SQL回滚、COMMIT已成功/已失败/未知及服务启动失败仍继续恢复。后台远端现有 Python 环境34项隔离测试，32通过、2跳过（含旧开关开启时 HTTP reset 在读认证/请求体前404）；连接限于模拟DB及本机loopback，无真实交易。

实际 PostgreSQL 克隆：`/root/goufayu_upload/account_cleanup_checks/4ce8cdd97cb810d0512cc085`，仅从生产导出结构，真实玩家复制0。合成双账号验证完整备份恢复、清理范围、另一账号不变、奖励触发器/兑换计数回滚、结构变化/旧计划/未结单拒绝、同码重新占用名额。克隆库 `goufayu_ws4_account_test_c6158b53ae3d` 和 `goufayu_ws4_account_restore_c6158b53ae3d` 及失败尝试证据均保留，没有按日期清理。真实维护停服和真实账号清理未执行，不以克隆通过冒充线上实测。

成本：无新增游戏定时器/原生桥/网络调用。单次 snapshot 23目标表各2条读取，加3条结构、时区及3条核对共53条SQL；全预览PG55条，认证 SQLite16条（服务探测另外3次 systemctl）。账号排序约 O(K log K)、可保留行 O(K)，总预算10万行/100MiB；兑换全局定义/计数及明确确认后的全库备份随全表/全库规模增长。SQL30秒、锁5秒、备份180秒、维护300秒有界。均为手工操作，不是 FPS 或线上耗时结论。

## 交付边界

**已同步游廊1102**：原条目3824360109，Steam manifest `7805846272729005356`。7056运行资源、186保护模块、5个VPK包文件官方完整下载一致；完整来源检查点清零，待发0、阻断0、脏运行文件0。源码绑定 game `e5d552d91107d504e3eecc377463c18cb1b9cc2a` / content `dc667dca77c285cfe3c91946ac58e69ef1047f1f`，功能提交 `deaa62ac5623169f2147f59143c40830ba22c2c5`，严格CSV与登记修复 `d01c5574999b74fd09bbd947a097f0f85557b837`。后台源码未部署；本轮线上停服0、真实账号删除0。普通客户端功能与真实清理维护未实测，仍待用户按需测试。

首次完整任务 `pack_2026111101_c7b1ea02` 在严格来源审查阻断：4份新抽奖CSV没有精确映射，另外2份目录JSON已有严格合同。未签包/未上传；生成/编译回执与三个自动提交保留，未改写旧任务。固定工具的模板渲染器新增4条明确 CSV→Lua 映射，仍使用既有固定SHA生成器逐字节复现，不扩大未知文件豁免；5项回归含实际4输入、8项篡改负对照、生成器摘要变化和未知路径拒绝，以及22工具渲染编译。维护CMD对实际执行/未知结果用已提交固定字节的登记工具记录原始回执；合成回执真实登记通过。下一轮用新任务保留不可变来源。


最终固定任务 `pack_2026111102_3ae9c5c2` 已返回 WORKSHOP_SYNCED。首次发布因 Steam SDK BLoggedOn=false 在 sdk.Steam 初始化处失败，账号/AppID均正确，无UGC写调用；用户恢复在线并明确要求继续后，独立无缓存查询与1009官方下载回执的条目时间/大小/可见性完全一致。全局发行锁内保存原始lineage/journal、登记备份、校验审查和协调工具SHA，仅显式恢复已知上传前失败的pending，保留原意图、代际、父head和正式journal；随后固定入口完成一次成功提交及官方下载、完整待发收口。协调审查和应用回执在树外同一证据根，未以删除未知pending绕过门禁。

交付回执：`D:/Survival_本地工具/runs/packaging_jobs/pack_2026111102_3ae9c5c2/delivery_receipt.json`；官方证明：`output/packager/pack_2026111102_3ae9c5c2/download_evidence/20261111T061331Z_c81571431dd44ebab3d80c5ddd0fcb8b/verification.json`，SHA256 `eccd9e0e74d3449bc90fed0f9d04cea81a697d3ae360176a180e651384e7ce9d`。协调备份已登记，旧1101/失败意图/合成库均保留。

其他窗口5项未提交内容原样保留：`server/archive_backend/__pycache__/match_modes.cpython-314.pyc`、`server/bundles/current.json`、`tools/monster_portrait_release_20261030/finalize_package.py`、同目录 `verify_download.py`、`tools/prepare_delivery_operator_20261103.py`。content工作区干净。两仓均按各自分支同步推送；本轮文档提交不改变已发布运行绑定。
