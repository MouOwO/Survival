# 商品功能、头像驻留及解耦审查｜2026-11-01

任务从UTC2026-10-31 14:31开始，用户限制12小时，截止UTC2026-11-01 02:31。优先级：实际游廊饰品头像与开局帧率，随后侏儒传送器门禁、全商品清单、解耦及新项目知识交接。用户确认3102商城已有商品信息，并自行完成兑换；这不等于每件商品及真人奖励到账都已逐项验收。

## 已完成与当前边界

上一轮源码交付为game `11571b4313401d3d15073a0d14234754fb851316 / dev`、content `fb775f5ae9a36d863f048928a8fa0230a5cbb548 / master`，已按stash→pull→pop→commit→push同步。它包含D权益统一与renderer缓存改动，不包含随后v04的combat_stats查询锚点修正。该次同步时game原HUD编译字节、Python缓存、bundle运行指针及两份头像实验脚本保留，content干净；新改属性文件的换行归一已逐字节对照确切stash规范内容，其余原始SHA一致、旧stash保持。这是历史同步状态，不能当作当前13文件v02已提交。

当前正式游廊仍为3102。2026110101曾准备12文件未签名审阅包，6918项资源、184保护模块，content `7ed3e94bb586cfb88802a97ef98dadce4743c98dfbb5bd6d1f2b42bf95611d69`；它只作保留的旧候选，不安装/运行unsigned，也不能作为最终头像修复。当前范围改为2026110102的13文件v02，追加已有combat_stats.vjs_c；新增运行模块仍仅hero_teleport_access，资源总数仍6918/184保护模块。第二次源码commit及13文件最终unsigned尚未产生，签名生产玩法、正式新游廊及新版FPS均未验。原四账号、正常联网配置及`all_difficulties_unlocked=false`、d573和地图保持原范围；后续签名/发布须按最终范围审阅，不能沿用旧12文件计划冒充新候选。

普通客户端8200已通过正常Steam授权，并在3102的template_map取得188场景READY；不再记录为“登录待用户”。普通局实证查询锚点缺失，离线v04的共享主头像/default-opacity修正及六场景视觉结果见下文。D原生fixture的run02现已完成15个串行阶段并finish，开发离线内存provider下的权益、真实施法/退款及共享CD有限通过；完整包等价、建造者实际施放和正式游廊仍未验，详见下方D验证补充。

## 商品审计结论

完整矩阵`docs/reviews/commerce_feature_audit_20261031.md`及其公开JSON覆盖134个在售SKU：126钱包和48现金报价、40项镜像去重；所有SKU均有接入证据，另有63种静态属性消费者证据，不是逐件真钱购买。现役d573与开发改名分开，不能把改名未发布当功能缺失。F02–F05为4条部分接入边界，涉及3个SKU；F03的全部来源成长口径仍需产品确认。

| 项目 | 结果/待安排 |
| --- | --- |
| F01 侏儒传送器／折跃信标 | 官方3102商城入口查权益，但原生英雄D无条件激活/0秒CD。开发版两入口共用按玩家索引的权益和10秒冷却，持有解锁、撤销禁用，源码回归通过；礼包video_bundle_b002继承该状态，正式3102尚未包含修复。run02离线原生有限验证通过，原库存恢复且临时英雄移除；建造者仅技能状态/过滤，D实际施放未测。原生800距离/20魔法与商城全图/0魔法为既有产品差异，列待确认 |
| F02 不灭涅槃 | 已到10转后才获得道具不会立即补5技能点，等其他成长请求才补；真实当前/冻结3102模块均复现，未修，等用户安排 |
| F03 无尽年轮属性成长 | +10%仅放大转生内置每击成长，未覆盖存档/商城每击成长；全部来源口径需确认，未修 |
| F04 无尽年轮训练室折扣 | 扣费确实75折，入场最低金币检查仍原价；折后7.5万足够却被原10万门槛拒绝，未修 |
| F05 朗基努斯枪 | 抽奖动态持有加成在5%增强之后派生，漏进增强基数；未修 |
| 其他口径/目录 | 焕天印“每次学习”是否包含旧技能升级待确认；开发3元普通券现金单品尚未进入现役目录；130行钱包配置中129行文案有差异（含停用条目），待另批同步 |

除F01外按用户要求只列清单，没有顺便修改其他商品、价格/奖励或玩家数据。全模块复现、覆盖证据和成本在审查矩阵/JSON及tools/commerce_feature_audit_20261031中。

## D原生验证补充（开发离线范围）

Root用真实Tools开发局、template_map、offline内存provider与临时免费Axe完成run02的15个串行阶段，最终phase12：未持有隐藏/拒绝、持有成功、撤销恢复拒绝、零距离失败退魔法且不新增CD、原生与商城入口双向共享10秒CD均通过。三个原生订单以ExecuteOrderFromTable下达，在游戏时间实际推进后分别观察；没有直接调用OnSpellStart。cleanup和finish确认原P026库存槽恢复、绑定临时英雄移除。独立复核同一夹具SHA、发送顺序、15份response和源码判据，见[逐阶段原件SHA与脱敏指标](hero_teleport_native_20261101.public.json)；具体实现报告为`docs/reviews/hero_teleport_entitlement_20261031.md`。

首次run01保留为拒绝：现场HTTP标记1，prepare guard107在状态建立和库存写入前停止。Root确认严格offline内存provider后显式设HTTP0，再开新run02，未改夹具检查。离线启动器补显式HTTP0的两份Python入口与9项隔离回归由root验证。最终fixture_cloud_calls=0仅是此内存夹具路径，不是进程全部网络追踪。

建造者对象、技能等级/显隐/激活及CastFilterResultLocation保持，但没有实际建造者施法订单（builder_native_order_tested=false）；gameplay_package_equivalence=false，签名生产、正式3102/新游廊及多人仍各自待验。Root另观察免费Axe选中截图外观完整，不能推广到全部免费英雄或所有饰品。原生800距离/20魔法与商城全图/0魔法的既有产品差异保留待确认。

## 头像与真实性能

截图挑战5转对应Bane及目录预期4件组件。实际Steam3102包的关键资源、五份JS DATA及HUD布局语义与源码一致，未证实漏打包/为性能删饰品。旧签名启动仅到GameSetup，不是正式选怪验收，这是此前发布证明的缺口。资源READY中的组件数量是目录预期值，不是原生逐网格可见计数。

`docs/reviews/portrait_runtime_review_20261031.md`记录旧renderer的两个设计风险：全目录预建后保留188个DOTAScenePanel；超10秒永久failed回退裸模。开发renderer保留197身份/188地图目录，改为4项逻辑驻留LRU、当前/加载保护、仅响应明确请求，取消全目录后台预建；失败按真实选择epoch和2/10/30秒退避重试，不再永久黑名单，保留100ms防闪遮罩。失败超过10秒的原生退路仍存在，DeleteAsync也不证明GPU瞬时驻留绝不超过4。随后还必须修正combat_stats挂接，不能把renderer改动单独当完整修复。

renderer的game/content源码同SHA `2bff46da002ffdef17b69eef6fa3dc28df374deee8ce4a878f3568634bd701c7`，官方编译物SHA `d83c2d9165a1efc048bfe8a8426ac0e8ce747e12432d071a8aec86545062bade`。combat_stats的v04源码/官方编译双摘要与实机证据记录在`docs/reviews/query_portrait_anchor_20261101.md`；它们尚待第二次源码提交纳入13文件v02，不能覆盖旧v01计划或将开发视觉记作已上线。

有效原游廊3102基线见`docs/reviews/arcade_opening_baseline_20261031.md`：本机一个普通Steam客户端1600×900、N1首波前、同视角建造者，2889完整帧间隔、约30秒，平均96.5384FPS，P95/P99为23.39448/28.196832ms，真正最慢29帧的1%low为32.6845FPS。>16.7/25/33.3/50ms为309/113/4/0帧。前后倒计时01:38→01:04；30个1Hz前台样本均通过，不冒称逐时刻无暂停/无切换。长帧更伴随CPU Busy时长，不能由此确定188世界为因果。

正常3102客户端8200已授权，188场景均READY、Bane5专属地图105ms就绪且静态含完整4组件；没有LOAD_FAILED。实机选中Bane5后仅记录`HIDE reason=selection_transition`和`anchor_state=missing_anchor`，没有对应SCENE_SET/SHOW，原生残缺头像仍可见。这将本次可证故障定位到查询头像挂接，不能再将“地图没打包/整体加载失败/永久超时”写成本局根因。官方二进制虽含dota_dump_scene_panel_state字符串，普通客户端实际返回Unknown command，也不能把字符串当可用API证明。

实际该HUD没有独立QueryUnitHeroPortrait，显示复用主树的portraitHUD/DOTAPortrait。v04独立查询叶优先；共享主头像须可见、挂接有效且原生当前展示单位等于目标，单位不符/API异常/显式0透明度仍拒绝。默认null/undefined/空白opacity按未设置处理，修复Number(null)=0的兼容缺陷；不能由早期JSON的null独断原始值类型。该变化不改相机、场景组件、背景或既有几何算法。11项领域回归及官方编译通过；一次显式暂停DOM诊断的33249节点/43ms不进入稳定热路径或FPS证据。

离线v04在同一开发世界已真实选中Bane5、转生1/2/3/4/6，再冷回Bane；六个不同场景均关联shared_main、实际SCENE_SET/SHOW和匹配头部/饰品/背景画面。Bane经过五个不同资产后再次READY并恢复像素，证明应用LRU淘汰后的场景重建/回切，不证明原生GPU已即时释放。具体画面和时间记录见`docs/reviews/query_portrait_anchor_20261101.md`。

两段屏幕采样各约8秒、239张PNG：Bane→转生1实际是Undying/phalanx（旧路径含tide不代表Tidehunter）；独立检查13张关键样本，先遮罩/背景再完整模型，未见原生裸模。五场景后回Bane独立检查24张关键样本，也未见裸模，标题出现至完整模型的采样差约333.7ms。它们是受CopyFromScreen/编码扰动的约30Hz屏幕采样，未逐帧检查全部478张，也不能证明每个游戏渲染帧零闪帧、动画、全部饰品网格或FPS。反复热切、正式签名生产及新游廊行为仍待验。

旧局及该普通局在无主基地、首波开始后自然结算。第二段Bane视角ETW跨入POST_GAME（本地02:31:14，约采样19秒），因此整段排除于优化比较；98.09FPS只是混合场景原始统计，不是有效开局或Bane验收。后续需在稳定场景采样。截图/CSV/日志和账号资料只留ignored output，不入Git。

冷开发局另保留一次稳定性失败：本地03:23:31首次模式档案加载（reason=match_mode_selected、revision=1）后连续9条CUserMsg_CustomGameEvent序列化失败，随后ParticleManager序列化失败、reliable data too big(7621)和SnapshotError。日志没有具体CustomEvent名/调用栈，也没有同期前台采样，不能精确归属档案某页、后台失焦或新锚点。热缓存重载后视觉可用不能消除该冷启动失败。诊断证据为ignored `output/net_snapshot_diagnostic_20261101_goods/cold_disconnect_review.json`；未修改运行代码或放宽护栏。

## 开发局Bane5原生ETW补充

本次v04 Tools/offline开发局在D夹具finish完成恢复/清理后，Bane5视角取得30秒原生ETW：1796原行舍首后1795帧，平均60.0002677FPS，P95/P99 16.816110/16.930878ms，真正最慢18整帧1%low 58.9428405FPS，最大17.0589ms；>16.7/25/33.3/50ms为503/0/0/0。30个1Hz前台样本均同1600×900窗口（不是32个），13项/778335字节采样前后及独立磁盘复核一致。独立查看前后图倒计时01:56→01:21、均0/90、完整Bane5头像及背景；日志先有unpaused，采样包络未见POST_GAME/胜利结束标记，没有旧98.09样本的跨结算证据，但仍仅是端点/离散观测。采样内另完成4项后台AssetPreload。详见[脱敏指标与原件SHA](dev_bane5_etw_20261101.public.json)，短审查为`docs/reviews/dev_bane5_etw_20261101.md`。

全部帧SyncInterval=1/Composed Copy GPU GDI；CPU Busy/Wait均值1.5491/15.1175ms，GPU Busy/Wait 6.4245/9.6309ms，与60Hz呈现节奏一致，具体限帧/垂直同步配置未查询，不能判定未限帧上限或单一CPU/GPU瓶颈。此为Tools开发离线Bane视角，与旧普通游廊建造者96.54FPS负载不等，不能称提速/退化对照；正式签名生产包、新普通游廊及多人长局性能仍待验。原始CSV、safe_summary和runner字节均保留未改。

采样后另发生稳定性失败，不能被上述30秒指标覆盖：两次C6 pause均Console history replay did not complete；正常CloseMainWindow请求返回true但进程持续，严格截图拒绝window invalid or hung且前台已到非Dota。Root用OS确认Responding=false并核对精确CIM/argv/exe/hwnd，在合成库存/临时英雄已恢复的前提下结束该自有hung离线进程，无dump/凭据读取。诊断原件SHA `4c0b34c7b4d98064343822ab42730ad7bddb7c722be77cf7ac485bd69d43b8fa` 已纳入公共回执。30秒样本及正常前后图仍保留，但候选稳定性未通过；原因未定，不能归因VConsole、Tools、退出、原生缓存、ETW或本轮头像变更。

## 解耦评价及复用

`docs/reviews/architecture_coupling_review_20261031.md`和头像领域审查分别记录职责边界。已有事件代际、账号/局内投影、窄库存读、after_dispatch合并等有效设计；“解耦不够”不自动等于FPS原因。已修D的平行入口和同值商业快照重复提交；未大范围重构其他商品。

仍需安排：1Hz塔/墙成长按玩家重复筛全局buildings（O(P×B)）、相同profile事件仍在去重前复制全档并重算所有来源、永久来源乘区手工顺序、combat_stats同栈拥有战斗数值/技能/原生头像几何。对应建议是owner/type索引、按变化域发布带版本的小投影、统一来源层、独立头像挂载适配器；都需以实际热点和兼容回归决定范围。

新增可复现的首次快照风险：当前与实际冻结3102的snapshot_profile/send_page/send区域LF字节相同；相同合成空档案、真实投影函数和mock传输下，均同步发送20分类/88包，JSON合计约1.503MB，最大约23KB，第二次同状态0包。空shadow页也重复daily_limits约11,160字节和categories约1,474字节；分包仅按12行，没有单包字节或每批发送预算。43个相关generated表已对冻结保护模块返回值比较并核manifest字节，26完全相同、17存在差异（主要名称/描述，另benefit追加1条、endless起始延迟）；分类及各主要目录行数保持。此路径在3102已存在、且不在13文件替换范围，不能当作新候选回归证明。JSON体积和模拟88次调用不等于原生报文大小、7621的单位/上限或本次断线唯一原因；后续应按事件时序定位，并拆共享元数据/页面数据、建立真实字节和发送预算。

本轮启动目录索引O(N)，取消全目录3D预建，按需创建、逻辑缓存最多4项；原生实际释放峰值未测。稳定准备/显隐O(1)。197与1970目录的300次调用均0枚举/0样式写、相同1800模拟GetParent。D权限O(1)标量读，1000次检查在1和10001库存下各1000标量读/0完整档；同状态事件0原生setter，10个稳定tick0NetTable提交。这些是模拟调用数，实际FPS仅上述有效原游廊ETW。

新项目应复用数据目录/原生重资源生命周期分离、权益与动作单一权威边界、事件变化域/账号代际、不可变源码与官方编译输入双摘要、真实游廊像素/功能/性能分层验收，见[08复用入口](../08_new_project_reuse.md)。

扩大英雄生命周期回归时，summon_flow/player_isolation/runtime_availability三项在当前与父提交2f6b818预加载822运行模块的独立进程中同位置失败，前置均为test_access_denied。仅注入显式合成准入fixture后父/当前均通过，未改原断言或生产门禁；不把旧fixture失败当新回归，也不因此冒称原样全套通过。完整8模式离线开局集成通过（0次真实HTTP、0次持久化写入），不替代上述真实冷开发局稳定性验证。私有对照`output/hero_lifecycle_baseline_20261101_goods/3feeca302842/report.json`。
