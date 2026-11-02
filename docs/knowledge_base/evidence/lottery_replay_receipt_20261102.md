# 连续抽奖与回执优化0204｜开发及暂装进行中，未发布

## 当前状态

用户要求修复连续十连只有首次演出、约3秒等待，并发布原游廊。用户另批准最多30张普通券用于三次十连。**本轮自动验收目前没有发起真实抽奖，预算已用0/30。** 不补券，不在结果不明时重复点击。无消耗预览和真实交易必须分开记录。

新0204已签且通过完整运行包验证、已暂装本机原条目；正式远端仍0104，尚无SDK Submit、官方下载或原生准入结果。本机测试包不可与正式0104混联。run01已owned direct启动PID9820，created_utc原串`2026-11-02T14:56:23.5508250Z`；keeper持续存活，工具会话49678必须保留，等待用户正常Steam网页登录并进入standard N1，禁止另开客户端或手动抽奖。初始共享只读日志114831字节已见addon初始化，演出命令stamp1793631406097，限定fatal计数0；不是完整结局日志验收。

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

## 后台已实际激活，支付不变

只读审计确认原发行`20261029-redemption-2f918e4c0edd`、d573588b…bundle，审计时无待处理/在线活动。线上service.py与本地HEAD有其他差异，所以部署器认证线上父SHA后，只替换结算后三行并新增helper；不整份覆盖本地service.py，不改bundle、SQL、配置、支付、凭据或玩家资料。

准备、激活和独立verify均已返回`RECEIPT_API_ACTIVE_VERIFIED`，新发行`20261102-lottery-receipt-d2c7c2e85920`，manifest SHA `04f03ebdc6681c00a76fdc0ed239e7f59066de39bb873bd1020908562e73051a`。服务文件SHA `56e32e2e30e2e46257ae002652b6800bc6b5b864fa6097a8fbd079b4af8df03f`，helper SHA `9192fc746010acd798a06fd551f65d5729e2727f5ed19667d8fbbff17a1c8e38`。原完整发行保留；API PID577091，支付PID5427和DB PID915未变。部署本身数据库写入0。

待激活目录真实Lua投影独立测试通过，4池、合成券数37、profile未改、DB mock调用0，单次约697.25ms；首次验证因隔离shell没有lua5.1失败，按线上公开ARCHIVE_LUA_PATH使用`/usr/bin/lua`后通过。该耗时只属合成投影，不是用户抽奖或网络总耗时。

## 本机暂装与下一步

首次stage因缺显式事务ID拒绝；第二次run01在检测到Dota客户端时拒绝，均未换包。用户随后确认退出；新的同run01事务已返回`LOCAL_SIGNED_CANDIDATE_STAGED_NOT_OFFICIAL_DOWNLOAD`，正式0104五包完整备份在`D:/Survival_本地排演/20261102_ws4_lottery_replay_v11/run01/backup`，候选五包及事务也在addon外。未改ACF，未上传。

当前唯一入口`rehearsal launch --transaction run01 --report-sha256 <上述signed SHA> --route direct`已返回`OWNED_REHEARSAL_V04_RUNNING_KEEP_THIS_TERMINAL_ALIVE`。继续时先核对现有owned keeper/实际process记录，不能重复启动、冒认其他Dota或强杀。已向用户请求正常Steam网页授权并进入N1，待回复“已进N1”。其后仍需四池预览及同池连续三轮实际像素、全日志零fatal、after/正常退出/完整restore，才可进行发布准入。真实交易另开独立记录，最多3次十连/30普通券，不污染禁止交易的原生预览证据。结束后必须恢复0104再交付，不把stage/Git/签名当作游廊发布。

本记录不包含原始认证日志、nonce、账号数据、凭据或兑换码。旧0202 fatal、0203多轮未准入及其他会话的中断仍完整保留，不据此归咎用户或认定崩溃。
