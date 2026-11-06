# 0604普通客户端视频与启动同步实证（2026-11-07）

仅本地更新；未上传游廊。正式版本仍为2026110104，Steam manifest `7025356658517360342`。0604是完整签名诊断候选，不是已通过全部准入的生产版本。后台保持已部署的每日上限HTTP去重v2，本轮没有后台变更。

## 不可变来源与候选

- game最终来源：`5b2b1bb14525f1cf40893e88c8ad095a6f136427`；content来源：`73a290a2ae57cac24e64a16657b3c1405f428f9b`；编译/保护/发行operator：`bda269713e612207e7737d49aa24ac4577bed2bd`。保留真实producer身份，不能将最终compiled提交反写为原编译来源。
- 报告：`output/complete_delivery_release_20261106_v04/package.json`，SHA-256 `e61fa08eefe25eaa2e15330ab3e9006a737738bfa2ed2d63ed50bd5fb14bd499`。
- 签名manifest：`d73ecc23f895f37d8b1a8a87e827cf2f8151a646782aee2918c01fef5e95bd41`；目录VPK SHA-256：`43e301a3298e799540401116a8b56202f36bb8528738105a692f0d89d4638415`。
- 154项官方编译、186保护模块及7项正式策略覆盖已核验；候选7038资源。完整源清单569项均已映射，unknown/deferred为0，但这些运行改动仍未完成SDK上传与官方下载验证，不能把“源映射无遗漏”写成“游廊待发为空”。

## 普通客户端视频结论

实测事务为 `complete0604_run01`，普通客户端PID20600。证据来自同一签包的真实GUI采集与引擎日志，所有A/B均为免费预览，不执行抽奖交易。

同一 `panorama/videos/custom_game/lottery_cinematic_v1/map.webm` 的三个路径表现不同：

1. `DOTAScenePanel/Movie wrapper`路径：原生报错，画面出现播放错误文字；日志probe1为`outcome=native_error`。
2. 普通direct MoviePanel路径：观察为黑屏；日志只标`visual_review_required`，不能解释为播放成功。
3. `buffered`（buffer-async MoviePanel）路径：实际连续三次启动成功，观察到不同时间帧推进并正常结束返回。真实成功采样编号为`world02_buffered01`、`world02_buffered04`、`world02_buffered05`，分别对应日志probe3/4/5。`buffered02`和`buffered03`因截图超过180秒的守卫拒绝，`command_attempted=false`，不能计为播放次数或媒体失败。

证据目录：

- `output/movie0601_diagnosis/ordinary0604_orchestrator/complete0604_run01/`：各轮命令、采集及失败保留回执。
- `output/movie0601_diagnosis/ordinary0604_captures/complete0604_run01/`：每轮`t8/t22/t62/t82`原生截图和身份元数据。
- `output/complete_delivery_rehearsal_20261103/complete0604_run01/engine.log`：wrapper/direct/buffered真实begin/complete日志。

这证明0604签包中的该原片可以在buffer-async原生路径播放，不能再笼统归因于视频未入包。但当前生产演出仍使用旧路径，尚须将可靠路径接入正式控制器、保留真实失败兜底，并验证四奖池、跳过、结束、切局、重复播放及结果展示。不能将单池免费A/B当作所有奖池或真实交易验收通过；本轮未重新测FPS。

## 四个旧快照大包与准备状态停滞

引擎日志world01记录271条`cw`；world02在相关区间没有`cw`。第二局2026-11-06 23:42:48暂停，同秒档案进入ready；23:42:49目录核对成功，后台请求耗时385ms、HTTP响应158B；23:42:52服务器却发送四个`ui_lottery_snapshot`：17121、16927、17908、16094B，共68050B。四包均为自动cache发布，无显式snapshot request id。这不是158B目录回包本身变成大包。

已定位两个相互叠加的问题：

- `startup_loading_service`的异步mode-profile完成回调仅修改entry状态，`profiles_ready`及gameplay gate仍等正间隔0.25秒Think推进。暂停时正间隔Think不执行，客户端按正确规则等待profiles_ready，因而没有开始Hello；不是已完成协商后单纯丢失能力标记。
- `lottery_http_service`将“尚未compact绑定”等同“旧客户端”，profile/catalog就绪即主动下载并发布四奖池完整快照。未知客户端应等待协商，旧协议须由明确请求启用。

已核对gen15生产source_export的transport/dispatch/startup/lottery/router与其不可变Git源逐字节一致；JS/Lua catalog schema均为`ea3c8c9bbe480abaaa9bfe7c87c287cdad4609e025913aeebcc44c3e2834669c`，保护后的生成表已有值及RNG一致证据。未发现策略覆盖关闭compact或旧包混入的证据。

已审阅修复及隔离证据（正式源码接入不代表新签包原生通过）：

- `output/startup_ready_edge_20261107_v01/`：完成边沿推进，epoch/entry/attempt/account与complete-once守卫，同步回调合并，异常后释放重入状态。候选SHA `23e0135c52978ec1cd78212279ae9da05bc72ca754dedede02fcc6be08536498`。真实Lua模块到现有JS runtime的无Think两局测试，旧代码Hello=0，候选Hello=2；重复状态100次额外消息0。
- `output/http_profile_refs_20261106/legacy_gate0604/`：明确私有legacy请求才启用旧缓存，compact打开或迟到读回调观察到绑定后退役旧读；交易提交和幂等规则保持。候选SHA `51c4c8e0ccfa7426b73cb06094d946e15db68cae781021563bc48248c92058fd`。24项Lua回归全部通过，其中11个新场景独立重跑通过；四个旧fixture只增加明确legacy请求，未删除原断言。

复杂度边界：startup每个真实异步完成做O(P)一次就绪检查，P≤4；四人分别完成的fixture累计16次loaded查询/4次发布，重复100次回调零查询零发布。同步同批完成合并一次后续扫描。legacy资格按玩家与owner索引O(1)查询，未知客户端没有额外旧HTTP/快照；没有新增轮询或自动交易重试。以上是隔离调用计数，不是原生耗时或FPS结果。

两个service都不在gen13实际226项生成readset内，修复本身不需重生成catalog；新runtime仍需新Git绑定、正确保护/编译闭包及签包，最终collector须继续验证原producer读集等价。

## 恢复后已接入的本地修复与正式回归

根代理确认恢复完成后，startup完成边沿修复已接入正式源码。正式回归入口为 `tools/test_startup_profile_ready_edge.lua`、`tools/test_startup_profile_ready_handshake.cjs` 和 `scripts/vscripts/tests/test_startup_loading_service.lua`，均通过。完整startup测试仅将预期roster丢失事件移动到最后一人的profile完成之前，保留全部原有准入断言；原版与候选均通过此事件顺序。

同时将两个不应默认运行的诊断路径改为按需启用：

- `workshop_network_probe.lua` 仅 `survival_workshop_network_probe=1` 时运行；默认值0。默认路径一次惰性注册后返回，不扫描许可名单、不创建Think、不发送健康HTTP。已有诊断显式开启时仍保留原边界、300秒上限、账户门禁、匿名固定URL与旧回调失效逻辑。`tools/test_workshop_network_probe.lua` 原4958项检查及新增默认关闭/换局测试通过。原300秒模拟存在14次HTTP、301ticks、357次访问检查；新默认路径这些计数均0。该比较为模拟计数，不能证明所有业务延迟来自此探针。
- `arcade_multiplayer_test.js` 无有效诊断NetTable事件时零定时器、零地图API调用；有效诊断会话保留原单个0.1秒恢复监视器，hide/dispose/reload使旧回调失效。`tools/tests/test_arcade_multiplayer_test.cjs` 198项检查通过。原10秒模拟空闲100次地图查询降为0；实际开启的诊断视图仍保留按需检查，不改变正式商店交易入口。

这两个诊断文件同样不在gen13的226项catalog读集中。它们仍需纳入本轮完整pending、JS官方编译和Lua保护/正式签包，不能只改源码或删发布清单。

## 后台、恢复与未完成边界

后台依据 `output/ws4_daily_refs_20261106_v02/verify.json` 保持`20261106-ws4-daily-refs-ed532ea60d2b`，manifest `839fa42cf775453bf90807b5b4eeb5d714a7a821f4cbfddd0046e015a927f106`，原部署verify状态为`ACTUAL_WS4_DAILY_REFS_V2_ACTIVE_VERIFIED`。本轮未再次改后台，不把目录385ms当作真实领取全链路低于1秒。

0604已正常关闭并完整恢复正式0104。真实恢复回执为`D:/Survival_本地排演/complete_delivery_20261103/complete0604_run01/restored.json`，状态`ORIGINAL0104_COMPLETE_SET_FULLY_RESTORED`，观测UTC为2026-11-06T23:13:23.445727Z。候选和备份保留；无ACF、正式journal或SDK写入。

本轮新增耗券0、SDK调用0。此前30张普通券授权已用完，不能自行再次抽奖。下一候选必须重新验证：暂停期间profile完成能主动打开ready并完成Hello、同客户端第二局不再主动发送旧四包；可靠视频路径接入生产后的四池/失败兜底/结果返回；真实领取端到端延迟及适用场景FPS；最后执行SDK上传、官方完整下载逐文件一致核对。0604本身不满足完整发布准入。
