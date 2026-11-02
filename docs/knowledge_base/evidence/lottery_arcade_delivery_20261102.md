# 2026-11-02 抽卡交付移交：本机恢复0104，客机报告恢复0104成功，0203未发布

**并发编辑已实证。** 同一工作区另有抽奖JS／编译资源、Lua适配与后台修改，以及未跟踪的`tools/lottery_replay_release_20261102/`；当前编译JS已从签候选11246字节变为10835字节。Root保留全部外部改动，等待用户协调其他任务与客户端；不能把当前工作区当成旧0203已审源，也不能让旧候选覆盖另一任务的新修复。本轮没有运行SDK Submit。

**后续发布尝试仍未完成。** run04安装末尾检测全局ACF变动，目标条目清单及候选索引只读复核未变，保留失败事件后由canonical launch完整重验启动；该局随后出现两条非Root发送的实际抽奖结果链，不能作无消耗验收，已正常退出并完整恢复。run05已stage／owned15432启动／before01，但没有取得可用预览画面，原进程21:21正常退出，原因待确认；完整关闭日志Snapshot／CustomGameEvent序列化／脚本runtime诊断均0，不是画面通过。之后Steam启动32920占用恢复，Root观察其停在游廊菜单，正常WM_CLOSE后经canonical restore完整恢复run05，当前0个Dota进程、正式0104。未Submit，不宣称11月2日更新已发布。

下一步等待用户确认连续客户端验证窗口；run06的v09 collector生成器与专用dota_pause辅助脚本已准备，尚未stage／启动。不要使用已退出run04／05补作通过，也不要在用户实际抽奖或客户端被重开的情况下继续标记无消耗准入。

为保留空间，对addon树外147个旧LAB及已完成恢复的run02／03／04副本仅执行可逆NTFS存储压缩，文件全部保留；核对路径／长度／last-write未变，不声称全量内容重哈希，也没有新增帧循环或原生FPS结论。

**当前不是最终完成状态。** 0203 run03原owned进程27636已同handle结束；Root实际恢复官方0104五文件，restore exit0，状态`ORIGINAL0104_FIVE_FILES_FULLY_RESTORED`。fresh-only官方SDK查询result1、cachefalse、maxcache0，time_updated1793536475及3788093063字节与0104一致，ACF manifest `7025356658517360342`未改。用户确认双端退出且客机0201路径未变，Root已给专用Restore命令，用户现已报告客机显示`ORIGINAL0104_RESTORED`；尚未实际联机验收。0203没有准入、没有SDK Submit；不能写“游廊已修好”。

## 实际原因与修复范围

实际0104四段WebM均在包内，与开发文件相同；安装旧JS/CSS没有新fallback，d71开发演出修复此前没有发布。原生MovieError是事实，底层读包／解码原因未证；官方intro松散文件、合法VP9/Vorbis头或Tools播放，都不能替代普通压包实测。

0203 `WS4-LOTTERY-SNAPSHOT-03`以认证0104为父，精确五项：`lottery_cinematic_v1.vjs_c/.vcss_c`、`ui/production_ui_service.lua`、`ui/ui_request_router.lua`及`systems/archive_service.lua`。保留6917资源、184保护模块、五账号／四人容量及后台／支付配置；JS/CSS两组作者源、CRLF输入、官方产物及content镜像分别绑定。archive Git-LF为已审 `6a50c80d15ba98374d8a7df31aa664112070a8ffb4e8b71867a0fd1ae2cddec4`，只晋升UI-wire修复，不改奖励／RPC。

原18可信审查先完整认证，原17保持、router替换、production及archive新增，最终20；Training2与UIWire1分列。实际父Lua归一CRLF比较，仅中文训练映射／常量表提升，没有夹带认证、交易或发奖变更。0201其余16运行资源＋3game作者源＋3content镜像共22域延期，旧220延期不动；所有旧0201／0202产物保留，不宣称完整HEAD已发布。

## 0202失败与0203逐轮边界

| 轮次 | 已观察事实 | 结论与恢复 |
| --- | --- | --- |
| 0202 owned19776 | 四池16张真实图、39券不变，各池native_error→fallback→return | 全日志冷启动12:14:35／12:15:05累计10次`Failed to serialize CUserMsg_CustomGameEvent [148]`，明确拒发；正常退出、keeper exit0及恢复0104实际exit0。旧证据全部保留。 |
| 0203 run01 owned30076 | 普通standard N1和已填充通关存档两图的有限视觉 | 空场结束后未完成四池采集；不能验收。06:41:51同handle正常结束、06:49:26实际恢复0104，事务已完整归档C盘并留D指针。 |
| 0203 run02 owned2172 | 四池日志链完成，计数39券保持 | Root实际看图发现结算遮罩覆盖，视觉明确拒绝；07:32:58同handle正常结束、07:41:32实际恢复0104。不能把日志完成当可见动画通过。 |
| 0203 run03 owned27636 | 已stage、owned direct启动、before01真实执行；原进程同handle已结束 | 10:28:50结束记录、11:33:35实际完整恢复0104、exit0。本轮没有有效N1／四池／after准入证据；不能当验收通过。 |

run02关闭后的完整engine.log已独立只读筛查：295954字节／2886行，SHA `26f3f58d851fb01e159772b3b2443c68f4049d3efef88f6b038f27c82e8cd7db`，读取前后size／mtime稳定；CustomGameEvent序列化、SnapshotError、reliable-data-too-big及脚本runtime-error均0。只支持该有限关闭日志没有这些诊断，不消除视觉拒绝，不证明run03或长局稳定；没有复制原始日志或认证内容。

run03 before01原始状态为`INCOMPLETE_NATIVE_FILE_USE_EVIDENCE`：四data卷真实Dota使用为true，index使用／all_five_open为false，6917／184外部签包绑定保持。原始false与INCOMPLETE不改写为完整PASS；原进程现已结束，不能事后补填该进程缺失的画面或after证据。

本地辅助脚本PS7自动日期反序列化丢失原ISO文本，以及F9暂停／镜头操作路径不符合预期，污染了采集时机；它们不是运行源码回归或游戏崩溃证明。采集应保留ISO原串（`ConvertFrom-Json -DateKind String`）；旧无效截图和被遮挡画面不能反复算通过。

## 不可变源码和真实签包

运行game `d611d7c7e27d2d0f0722bad9cce04fb8c3d862eb`、content `ef3f6ad1343ceb327a9932cd8317eafd7dd54874`，operator `11f25d8456356032ac01f80f6ef2b84fb6708f7b`均已推送；用户原5个dirty文件保留。后续知识提交不改变这三份冻结身份。

| 0203产物 | SHA256 |
| --- | --- |
| plan_v01 | `16da85205b4b01e1814853e766c06fc0023efcd8f8c6afd4bc5d4b374bc08009` |
| unsigned_v01 | `8796413039b4cf744677a820e38d2adcdb399e1a2694a36ac1918e8744413cd1` |
| signed package | `8ae7d8a921eff12beac1376671a4f5b9713b37a8c2dfa1f75e33a87f7496ec10` |
| content身份 | `9cfd6a09a1bda6b35f649cb2240b6de757f1d53aa91037416bd8657f55a21d54` |

独立unsigned审阅核五payload匹配plan，archive等已审6a50，其余四项逐字等0202；6912未变父行、184保护行、20审查和2compiled均符合，无签名。随后Root实际签名并分轮排演。新family26＋common28共54项隔离回归、9个生产演出模块模拟场景及两条consumer回归通过；这些不等于原生、FPS、真人花券或发奖通过。0202签包SHA `3a59fd1528b99554d989685293ae29a2116b401db94ae7c3c354ad32cdc111a4`继续保留为失败候选，不覆盖其记录。

## 接手与安全保留

另一台电脑已按用户反馈用原0201专用恢复器及`D:/steam/SurvivalPeerBackup_0201_run01`恢复0104；旧`SurvivalPeerBackup_1107_run02`和当前备份都保留，不重跑安装wrapper、不删订阅目录、不手改ACF。路径已由用户确认未改，且用户已报告`ORIGINAL0104_RESTORED`；Root没有独立访问客机或代替用户验证入房；恢复结果与实际联机验收分开记录。若后续继续0203，须另有有效普通N1／冷开档、四池无消耗预览、全日志零fatal、after与退出恢复证据，不能补作已结束run03的通过。本轮不要求消费或发奖；后台／支付未因此部署或重启，没有新FPS结论。

lineage bootstrap已完成但仍head0104／generation0／pendingNone，没有Submit或canonical journal写入；CAS用于防过期包覆盖，不是发布完成。四pool失败索引固定4键，稳定演出外0新计时器／状态查询，同池首错后0新Movie／错误轮询；最多5复用节点、1当前主题图、2活动计时器，没有反复全场扫描。

空间归档只动completed＋restored事务：旧v03 33文件／7576239101字节、v04 31文件／7576239932字节，均在`C:/Survival_排演归档/20261102/completed_candidate14_v03`／`completed_candidate14_v04`；0202 run01为30文件／7576230438字节，位于`completed_lottery_hotfix0202_run01`；0203 run01为29文件／7576242209字节，位于`completed_lottery_snapshot0203_run01`。D原叶均留`ARCHIVED_TO_C_20261102.json`指针，未删除证据或触碰当前run03／正式包。后两份全SHA及有效Owner／Group／DACL核验，C目标保护继承，原SDDL／继承标志另存可恢复；不声称live继承位相同或独立验证SACL。旧恢复入口须先找回完整归档，不可直接对指针目录运行。

新隔离规则要求裸VPK／LAB位于addon树外。Root本轮没有新造裸VPK；只读发现的205项历史非maps裸VPK（含output／tmp及stash字节备份）归属仍待审阅，不能自动移动或删除用户备份，也没有充分证据把它们定为本次版本失配根因。

安全回执与逐轮SHA见[配套机器摘要](lottery_arcade_delivery_20261102.public.json)。不保存授权截图、nonce、原始认证日志、账号身份或兑换码；当前记录不是READY开关，后续结果由Root按真实证据更新。
