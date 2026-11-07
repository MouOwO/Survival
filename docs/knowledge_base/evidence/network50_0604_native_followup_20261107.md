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

1. `Movie wrapper`路径：原生报错，画面出现播放错误文字；日志probe1为`outcome=native_error`。
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

上述启动同步、legacy资格与默认诊断停用修复已提交并推送：game `dev` 为 `967da6e99266d3775bec804e03d93d96d2c998ee`，content `master` 为 `9fbc596e43dba03bc72a9358fa52f47894dba004`；该次提交核对两仓本地HEAD与各自上游一致。这些新源码尚未执行新一轮官方编译、签包或游廊发布，不改变上文0604的原始producer身份与实测范围。0701发行operator的版本元数据初稿通过83项测试；后续影片v3及验收规则已在本地接入，实际当前检查及待冻结事项见下文，不能把早先83项结果当成后续全部修改的验证。

## 领奖链路复核：实际记录与合成计量

再次只读核对0602、0603、0604完整日志，成功`benefit_claim`计时仍只有0602的一次：HTTP 944.497ms、总计947.941ms、请求452B、Lua收到的响应正文19445B；解析1.215ms、同步回调2.104ms。0603和0604没有新的领取计时，不能据目录请求较快或v2已部署宣称真实领奖耗时已经验证。旧API记录的345.310ms仅为时间、类型、状态、正文长度相符的唯一候选；约599ms差额包括网关、传输及原生回调调度，不能全部称为网络耗时。

当前正常链路是立即入队并提交HTTP，回包先应用权威档案，再发布领取结果，JS收到结果即刷新；未发现固定等待1秒的代码。远程模式跳过1秒在线计时器；35秒是失败超时，10秒是慢请求的一次状态恢复查询，都不是成功显示的最短等待。已有交易占用、失败重试或发送队列仍可能产生等待，不能由静态检查排除。

使用实际Lua奖励结算器、已审计的standard投影及当前v2打包函数，对合成新账号进行离线计量：完整回包41290B，v1为15579B，v2为9757B，v2再减少5822B。其中每日上限行5310B、档案save值3290B、纯领奖receipt值164B；这些字段值尺寸不含键名和分隔符，不能直接相加。测试使用内存receipt和合成身份，没有HTTP、SQL或真实奖励操作，不能将该尺寸当成玩家实际回包。

实际UI投影与codec的合成计量中，普通revision=2的领取成功变化为3帧、按现有标定估算142B，pending为3帧145B，每帧最大49B；uint53极值回归才需要5帧235B。空队列的8帧/16ms共享预算可以在一轮容纳普通结果，没有新增1秒显示等待。这是编码调用计数与既有标定估算，不是新普通客户端抓包或FPS实测。

证据在`output/http_profile_refs_20261106/claim_path_review_20261107/`：`review.json` SHA-256为`24ed733d427d058ce25d98c30b2cdd98f342d73474d0b82c025570e853363f63`，另保留`measurements.json`、`normal_revision_wire.json`及仅含白名单计时字段的`safe_log_timings.json`。本次没有新增生产补丁或后台部署；进一步省略每日静态项或档案字段需要明确的配置/基线校验协议，不能只下发物品ID就跳过到账确认。下一候选为0701，仍需在该候选实测当前v2领取回包及端到端耗时。

## probe06隔离原生A/B：真实事件和透明坏媒体

2026-11-07的probe06为`-tools`隔离松散资源实验，不是普通签包或游廊验收。PID23308、原生创建时间`2026-11-07T03:01:35.2913410Z`，窗口1600×900。独立复核仅纳入根代理操作的A/attempt1（`caseA02`，11:14:45开始）和B/attempt2（`caseB01`，11:15:33开始），逐一核对8张截图及进程/准备回执摘要。11:15:44起D3、D4、C5、C6、B7、A8至A11属于后续非本轮操作，全部排除；更早的`caseA01`因焦点变化被拒，输入事件0、截图0，也不算播放。

A使用原始map影片和`buffer-async`子MoviePanel，实际截图从金色龙门推进至打开后的光球场景；B使用固定59B坏媒体，仅透出移动的洋红/青色测试底色，没有视频画面。两轮均在8秒清理回Idle。B结束截图另有“技能尚未学习”游戏提示，不能把该图称为完全无文字；测试底色也不能计作解码成功或生产兜底动画。

有效A的子面板实际收到`VideoPlayerInitalized`（原生拼写如此）一次和约7秒后的`VideoPlayerEnded`一次；坏媒体B在开始的同一日志秒收到Ended一次，没有Initalized。A/B的PlaybackStateChange分别4/2次，四类`MoviePlayerPlayback*`/FrameUpdate均未触发。该结果支持为当前子面板绑定初始化和结束事件，但结束事件本身不能证明播放成功；仍须核对实际画面和面板/代际身份。

全部11个已查询的直接节点播放方法均为`undefined`，包括IsPlaying、Play、Stop、SetMovie、GetDuration等，不能凭其他控件API猜测可用。`RegisterEventHandler`返回undefined但确实送达子面板事件；`$.UnregisterEventHandler`在该原生环境不存在，A/B清理共出现28条TypeError，不能称日志无错误。生产代码应使用自有面板销毁和代际/身份失效守卫，不依赖这个缺失的注销函数；B期间另有两次busy拒绝，未启动新演出。

重新只读检测四个正式原片：map、cultivation、dragon_knight、summer容器显示均7.00秒，音视频流时长均7.003秒，VP9 1280×720/30fps。截图文件`t22/t62`是2.2/6.2秒采样标签，不是22/62秒；不能据此写影片长于8秒。这里只实际观察map播放，其他三池仅核实文件摘要和时长。

独立事实回执为`output/movie0601_diagnosis/probe06_firsttwo_independent_review/review.json`，SHA-256 `78bffed3fcc5fd9468e026df72930ab1789ed83d9a1205057025d50d2e7cbaf4`；目录保留前两轮日志摘录及四片只读媒体元数据。原截图、日志和helper均未改写。外部LAB的`mounts_retired.json`确认仅退役自有挂载，原文件保留。无新耗券、业务请求、SDK操作；没有FPS、音频或0701生产路径验收结论。

## 0701本地候选优先与协作验收安排

用户现在要求先提供可用的本地0701候选，双方共同验证主要业务，确认后再调整、发布。五个优先项为：服务端响应、抽奖速度、获得权益/属性立即生效、画面流畅度、联机客机购买同步。“客机”指同局第二台电脑或非房主玩家，不能误写成未登录游客。客机正常授权后使用自己的已有游戏资源购买/领取，核对其余额和权益及时变化、主机与他人账户不串号、双方属性按规则同步；不自动充值付款。断线重连等未覆盖边界如实留待后续，不扩展无关功能。

短清单在`output/complete_delivery_release_20261107_v01/manual_acceptance_draft.md`，仅用正常界面点击，不要求用户控制台操作。下一交付是本地候选，不是已经上传；实际业务由用户选择何时点击，我方配合记录。三次真实十连共需30张普通券，历史30券授权已用完；清单和测试通过均不产生新的自动花券/付款授权，当前不为此反复询问用户。

影片生产v3已由根代理实际接入正式运行源码：两个JS、四奖池buffer-async布局、一个固定坏媒体布局及59B坏媒体，共8项运行文件；两项正式测试为`tools/test_lottery_buffered_events.cjs`和`tools/tests/lottery_buffered_controller.test.cjs`。影片JS SHA-256 `71db1169f30fdb927ac5842555a026d8b07bdfdc744b86dafa6a3f330cbe65bd`，控制器SHA-256 `e28da994b4f9668a1ad9cb3fe22dddef2911a2014ecdfa9e6541c8a7f384c3ea`。15项生命周期与10项实际compact/controller联合测试通过，尚未完成gen16官方编译、保护、签包和新普通客户端验收。

本轮采用用户选择的低成本失败处理：生产播放失败后立即调用控制器显示已经收到的真实结果，清除卡片覆盖并启用确认；不播放第二段备用动画、不重新抽奖、不再次请求奖励。免费预览失败只返回原界面，不虚构结果。健康影片仍使用原片和正常结果展示。每轮创建自有host/child，绑定真实`VideoPlayerInitalized`/`VideoPlayerEnded`，以代际、对象身份及terminal标志拒绝旧回调；只有5秒启动和12秒完成两个有限保护期限，无播放状态轮询或全场景扫描。开始与结束的正常路径为固定面板/事件/计时器成本，稳定空闲新增调用0；这些是代码与模拟计数，不是实测FPS。

验收工具也已正式适配新行为：`native_admission.py`对`release_sequence >= 2026110701`使用`BUFFERED_VIDEO_OR_DIRECT_RESULTS_V1`，0604等旧版仍按原规则重验。健康视频要求真实帧推进；实际失败允许真实结果/预览返回截图，无需伪填备用动画。生产失败覆盖必须使用当前签包坏媒体和真实child Ended事件；旧wrapper CSS探针、setup异常、静默超时不能冒充这一覆盖。原source/operator/签名/进程/恢复、券数连续与唯一结果、高频50B、SDK及官方下载门禁保留。日志一次建索引O(日志字节)，资源一次建索引O(资源数)，不为每个case重复扫描完整集合。

正式门禁SHA-256为`ac8b8b4147f08e3a55e6ba691bad5f09c27be857e803a1cdb3b5c1554de915c8`，authority为`9cb101fcbc5d1daba21aabe6481d60638a610470d50048f4effb508fdfe48bb0`，hook已同步其摘要。20项新增门禁测试（含0604旧/0701新/0702新分派）、30项旧native、6项decoder、11项post-download、9项SDK hook，共76项通过；这仍不是原生验收。根代理另记录producer 5项及pipeline 21项通过；完整recipe 25项尚有提交前Git身份检查未通过，因build_release尚未冻结提交，必须在实际提交后重跑，不能删掉该守卫或称全套已通过。

## 即时权益校准已落源

经根代理批准和独立审查，`scripts/vscripts/systems/commerce_runtime.lua`已接入本玩家档案完成边沿的即时校准，SHA-256 `1e6b22eb848214c56ea91a891998fff874154f49e3a8a9457c5ab3c3c32d7747`。训练容量、既有两项研究各+5、仙人召唤、光环/称号及轨道炮显示不再只依赖1秒游戏时间定时器；仅权威权益变化触发相应所有者更新。伤害等原有周期战斗逻辑保持周期执行，未改奖励数额、抽奖规则、付款或账户授权。

新正式入口`tools/test_commerce_immediate_entitlements.lua`的19项检查通过，覆盖冻结游戏时间时即时生效、重复事件不重复发放、两个所有者隔离及旧世界失效。对应测试SHA-256 `e05ac25782869d1f35cdd5326412ed1ebe6740d880b795f50e061e961d82d940`。`output/commerce_immediate_0701/production_tests.json`（SHA-256 `c58a8cfe0f2aeb6d062865fcbb167e3c6d0343e11f7e2438b027d76099f9940f`）记录9个命令退出0；其中8项无handler错误，覆盖旧完整资源生命周期、账户重绑定、抽奖刷新25项、transport35项、英雄权益、支付属性及commerce batch2。pure permanent测试虽然退出0并打印PASS，stdout仍有100条事件处理器捕获的`test_pure_permanent_rewards.lua:53`断言失败，不能将其计作完整断言通过；此测试边界须单列核对，不能被退出码掩盖。四个旧fixture仅在隔离进程显式设定合成准入条件，未移除原断言或改生产准入配置。

复杂度：真实权益变化按player ID校准，固定字段查询O(1)；首次需要城市时最多一次该玩家建筑列表O(B)，之后按创建/销毁事件维护。100次未变化profile事件计量为1400次标量权益读、0次hero/building重复查询、0次原生资源重建；状态O(P)，P≤4，初始化、战败和世界变化时失效。保留原周期战斗成本，这些不是原生FPS、真实HTTP或双客户端联机实测。

gen13实际226项`source_hashes`不包含`commerce_runtime.lua`，实际catalog manifest SHA-256为`8ea218bab4c34df14cfef78739103410a4d0a3b812b38807efac4421dd28f5e8`；该修改可复用原catalog producer读集，仍须纳入完整pending及Lua保护，并由最终collector核读集等价，不可省略运行文件。

## 后台、恢复与未完成边界

后台依据 `output/ws4_daily_refs_20261106_v02/verify.json` 保持`20261106-ws4-daily-refs-ed532ea60d2b`，manifest `839fa42cf775453bf90807b5b4eeb5d714a7a821f4cbfddd0046e015a927f106`，原部署verify状态为`ACTUAL_WS4_DAILY_REFS_V2_ACTIVE_VERIFIED`。本轮未再次改后台，不把目录385ms当作真实领取全链路低于1秒。

0604已正常关闭并完整恢复正式0104。真实恢复回执为`D:/Survival_本地排演/complete_delivery_20261103/complete0604_run01/restored.json`，状态`ORIGINAL0104_COMPLETE_SET_FULLY_RESTORED`，观测UTC为2026-11-06T23:13:23.445727Z。候选和备份保留；无ACF、正式journal或SDK写入。

本轮新增耗券0、SDK调用0。此前30张普通券授权已用完，不能自行再次抽奖。下一候选必须重新验证：暂停期间profile完成能主动打开ready并完成Hello、同客户端第二局不再主动发送旧四包；生产视频四池、失败直接返回真实结果/原界面；真实领取端到端延迟、权益立即生效、适用场景FPS与联机客机账户隔离。先交付本地候选配合用户验收，接受后再执行SDK上传和官方完整下载逐文件一致核对。0604本身不满足完整发布准入。
