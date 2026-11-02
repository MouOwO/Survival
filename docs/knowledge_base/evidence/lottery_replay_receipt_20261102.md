# 连续抽奖与兑换刷新｜源码修复已推送，0204已恢复0104，未发布

## 当前状态

用户要求修复连续十连只有首次演出、约3秒等待，并发布原游廊。用户另批准最多30张普通券用于三次十连。**本轮自动验收目前没有发起真实抽奖，预算已用0/30。** 不补券，不在结果不明时重复点击。无消耗预览和真实交易必须分开记录。

0204已签且通过完整运行包验证，曾暂装本机原条目。run01由owned direct启动PID9820（created_utc `2026-11-02T14:56:23.5508250Z`），在OAuth/N1等待阶段用户新增兑换刷新问题，未完成准入。随后canonical WM_CLOSE、keeper会话49678正常exit0，restore实际exit0并返回`ORIGINAL0104_FIVE_FILES_FULLY_RESTORED`。本机和正式远端仍0104，尚无SDK Submit、官方下载或原生准入结果。初始日志的有限fatal=0不能替代完整日志验收。

新增兑换缓存修复game `14812ec239d3dd24634b9b860b81e35a9a9fd721` / dev、content `a9590039044285dd96ca056a720747973f16cf2c` / master已推送，未进入冻结0204。必须另建候选，不改写旧包。23缓存、25Lua并发、3兑换UI合同全通过；官方编译1/0。成功兑换后只发一次全池权威重同步，退休兑换前在途读，不猜测奖励数或乐观加券。空闲新增0工作，每成功回执固定4池/O(1)去重，最多32键；见独立开发审阅。

## 不可变身份

- game运行源码：`13941240a848013d63b89cf8e8c6251cc0dfc0b3`，已推送dev。
- content作者源：`4a5a79c0c8cc290459f110e6a7ba867bf859674a`，已推送master。
- operator：`838fee9f2cbf3cccfb9c68555ad2186d099cdd27`，已推送dev。
- 统一入口仍为`tools/release_pipeline.py`，新注册目录`tools/lottery_replay_release_20261102`及独立授权JSON。旧0202/0203源码、签包和失败证据保持不动。
- sequence `2026110204`，内容SHA `db82e149482cd868121aec5566cbe74eae719afb4efe81013017ac2892bbda98`。
- 计划`output/lottery_replay_release_20261102/plan_v01.json`，SHA `5bbb8fa781eee966cec520aca3c275d274531c400529174795bf3fc12e892875`。
- unsigned报告SHA `87ddc2eaa0816fc67d14f0e82dbf022a2fb9e3e6bcc50b721924edc8f3b3a7e4`；七项实际载荷独立逐SHA核对通过，没有签名。
- signed报告`output/lottery_replay_release_20261102/package.json`，SHA `4b6455f9fc90ee4a25b1c4c4c789419069bd12d5a8c5f3fc7057465ab6caa4fc`。
- 6917资源、184保护模块、22源码审阅、2编译绑定；七项替换，新增资源0，未知源码差异0。原220历史延期和22个未发布0201域仍明确延期，不宣称完整HEAD已发布。

七项是演出JS/CSS、archive_http_adapter、lottery_http_service以及旧0203已经审阅但未发布的archive UI-wire和两处中文训练提示。后者是保留原0203范围，不夹带其余0201玩法/头像/D技能等延期项。

## 修复与验证

移除同池首错后整局禁播标记；每次新建Movie，每次备用演出退休旧层并重建固定5节点，保证不复用结束的CSS时间线。保持原视频/声音/实际结果，关闭、跳过、换模块代际失效及单次回调。

游戏只接受当前会话已认证且确实成功应用profile的结算回执投影，配置hash必须匹配，最多4池、所选池必须存在；HTTP不能伪造本地“已应用”标记。旧并发查询失去所有权，其晚回包不能覆盖新余额。缺失、过期或不兼容回退原权威快照端点。

已执行：JS10组含三次连续十连结果、consumer反馈回归、Lua缓存并发24组、adapter4身份场景、Python后台44项、helper3项；官方1 compiled/0 failed；统一入口16项、lease9项、旧冻结工具36项、新重复演出准入2项合成合同通过。合同测试不是原生画面或FPS，真实30券及请求毫秒尚待。

复杂度：演出外0新计时器/查询；活跃Movie最多70次单节点状态读取，峰值2计时器；失败备用每次5节点+1主题图，0JS帧循环。回执入口只校验固定<=4池，仍沿用原publish/delta及后台投影成本，不把后者宣称O(1)。成功快速路径追加snapshot HTTP从1降0；不兼容仍1。原后台快照含O(C×I)库存汇总与排序，本轮未改其CPU复杂度。GetSystemTimeMS仅在真实抽奖记录ACK/快照ready；不输出身份或凭据。

## 后台目标纠正：旧测试API已恢复，WS4未部署

此前只读审计和窄补丁误针对旧测试API `/opt/goufayu/releases/current` / `goufayu-api.service`，不是当前游廊WS4。该服务父版为`20261029-redemption-2f918e4c0edd`；补丁只改3行及helper，没有SQL/玩家数据写入，但不能据此认定WS4已修复。本轮已撤回自己的指针变更并仅重启旧测试API，WS4/两个支付/旧DB进程保持；只读独立核对`legacy_restored=true`及`legacy_prepared_preserved=true`。首次回滚远端已成功、仅本地写回执因dict/str类型错误失败；没有重复回滚，改为独立只读确认。

旧测试API准备/激活/verify历史回执仍保留；其新目录`20261102-lottery-receipt-d2c7c2e85920`及manifest `04f03ebdc6681c00a76fdc0ed239e7f59066de39bb873bd1020908562e73051a`也保留。该目录现在不是运行指针。不可将历史`RECEIPT_API_ACTIVE_VERIFIED`解读为WS4已上线。

实际WS4只读核查：`goufayu-ws4.service` PID489555，发行`20261101-admission-five-ffd96ff80622`，manifest `970792238ee146c7dbb247e5fe1e7b320899c4f8273859223d591069a1a3d38e`，bundle d573588b…，DB `goufayu_ws4` / port15432，service.py SHA `b75684f5052930b579d5dc3e0df6004e83328ff171c75c650f5564b813998165`，helper不存在。兑换定义132项，原RPC/定义未改。只输出聚合结果、不输出账号/码的24小时查询找到成功普通券兑换，之后存在已完成map抽奖扣券；不能把该聚合账号冒认为用户。`redemption_commit`已在库存更新后返回fresh archive_resume，本轮不改历史SQL、不重放兑换。完整脱敏机器回执在output/lottery_replay_release_20261102/backend/ws4_redemption_audit.json。

旧测试API准备目录真实Lua投影独立测试通过，4池、合成券数37、profile未改、DB mock调用0，单次约697.25ms。该耗时只属旧测试API合成投影，不是WS4、用户抽奖或网络总耗时。后续加速若继续部署，必须重新审阅实际WS4父版并保留其完整发行，不可上传本地整份service.py夹带其他差异。

## 本机暂装与下一步

首次stage因缺显式事务ID拒绝；第二次run01在检测到Dota客户端时拒绝，均未换包。用户随后确认退出；新的同run01事务已返回`LOCAL_SIGNED_CANDIDATE_STAGED_NOT_OFFICIAL_DOWNLOAD`，正式0104五包完整备份在`D:/Survival_本地排演/20261102_ws4_lottery_replay_v11/run01/backup`，候选五包及事务也在addon外。未改ACF，未上传。

上述run01已正常退出并完整恢复0104，不再等待旧keeper或复用旧进程。新兑换修复需要新候选；D盘约4.4GB、C盘约3.5GB，canonical新验收约需10GB可用空间，已向用户请求清出至少6GB或提供其他磁盘。不得删除备份、把VPK放回addon树或绕过容量检查。其后仍需四池预览、同池连续三轮实际像素、全日志/after/正常退出/完整restore；真实交易另开独立记录、最多3次十连/30普通券。最后才可lease准入/上传/官方下载，不把Git或签名当作发布。

本记录不包含原始认证日志、nonce、账号数据、凭据或兑换码。旧0202 fatal、0203多轮未准入及其他会话的中断仍完整保留，不据此归咎用户或认定崩溃。
