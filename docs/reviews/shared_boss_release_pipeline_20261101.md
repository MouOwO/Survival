# 共享Boss与头像发行链审阅（2026-11-01）

根集成复核：122项Python隔离检查通过（含两项纯包/发布后生命周期检查），三份Lua解析、共享Boss真实服务夹具、既有重生节奏及房间位置检查通过。这些不是实机FPS。另三项旧回归已与20420完整旧Lua根做真实双跑：失败行及失败前加载源码摘要完全一致，未加载本轮三个Boss模块；基线收据位于忽略目录 `output/shared_boss_baseline_regression_20261101/run01/comparison.json`，SHA `37c9c8dd4bf58423937d230980394ea9d5a6bb0fbac55bb9602dfd710499a759`。未顺带改动这些旧夹具。

2026-11-02更新：1107已按本次用户授权完成plan/unsigned及签名，原正式游廊仍0104，未上传。
report SHA`86c10bed12d60403d31b1951cbd608a86523835bca39ef563b1f36b3fd3878e3`，
content`7a4c5af2bb1f25cc4adacb46228cf9f129d58571afc30367f649250b165221ce`。
game/operator为`eaef4398383be211880423eb142eb0a1d723c69f`，content仓库为
`eb281a1398466876575a5885e60a8dd207e5f556`。下面代码/隔离结论与后续实际证据分开。

run03普通PID30424取得QOP09三张正确近景（137ms/5组件），Bane98ms初载及1/2/3/4/6后96ms冷回
（4组件/六张settled画面完整）；不宣称197全量或完整转场逐帧通过。
30秒ETW独立复算3389间隔mean113.2008925FPS/P9511.16886ms/P9914.25142ms，
真1%low60.982FPS（最慢34帧），max23.7336ms、0>25ms、30焦点样本全部有效。
前后N4计时01:03→00:29且未暂停/结算，完整Bane与15只Meepo可见，本样本90/16.7阈值通过；
不等于旧新同负载因果对比或全模式长局通过。

before inspection四data均Dota+keeper、indexfalse/all5false原样保留，status仍INCOMPLETE；after缺失。
用户只明确确认run01/02退出为手动操作。run03原进程已结束、随后检测到新进程，退出原因本轮未另确认；
Root未发送WM_CLOSE/kill，不据此判crash或已确认manual。UTC15:59:21.987019获同retained
handle退出及keeper exit0，但无WM_CLOSE intent/close_requested链，尚未完整restore0104。
随后检测到新PID33900，不属于原keeper；本机候选五卷仍未恢复，新进程占用不能继承旧验收。
正式0104/20条history不变，没有SDK上传；远端0104和本机1107版本不同阻止同局，手动同签客机包
仍在准备。peer installer v01真实小文件失败已阻止；v02 SHA`fdd669c0…16398dd`的实际同helper
小文件10项通过，receipt`bc396cba…87833f`确认0真实VPK字节、完整Install/Restore未执行，不能写客机分发通过。
剩余门槛为免费英雄/建造者、实际带饰品wave7 Axe、双PC共享Boss、after inspection、完整正常
退出/恢复及发布/下载。实际已签VIEW确认最早N4 costumed wave为7(Axe/6组件)，正常英雄入口
是Lv4后建祭坛第三原生Axe按钮；这两项还只是定位，不是操作通过。


## 本次范围与来源

新候选把14项待发布的头像、HUD缓存、英雄D权益/共享CD、archive wire修复，
与共享Boss的3个Lua合并为17项；计划资源数6919，184保护模块原字节保留，
22份源码审阅。仅新增英雄传送权限边界和共享Boss registry两个运行模块。
0104五账号/四人准入、支付及后台不在本次改动范围。

`source_baseline_0104.json` SHA256为
`3a60ddab9a93b58fa936e789f1a9d2008d39ed7eca9545487e1f40bf32219ee3`。
它逐项保留6917份已签父资源的SHA/字节来源；game锚点20420efc、content锚点f8640121
是源码游标，**不是整棵树已发布的声明**。220项历史差异明确标记
`DEFERRED_UNRELEASED_OUTSIDE_THIS_TASK`，不宣称安全或生产等价。
17项与延期清单零重叠；锚点后延期项改字节/身份、删除或新增未审运行路径均拒绝。
工具代码的`operator_revision`与运行源码game/content提交独立，全部AUX实际字节必须
匹配其不可变工具提交；只允许显式Git LF→CRLF变换并记录双摘要，脏工具不准入。
本次不可变源码与工具提交见开头，后续文档提交不改变此签名包来源。

## 共享实体与个人结果

`shared_challenge_boss_registry`只负责世界槽位、实体身份、参与session索引、目标和重生；
`challenge_session_service`保留个人入场、阶段、资格和奖励；AI仅消费当前槽位目标。
仅05/08/09三个单Boss和11的十戒十个槽位共享，最多13个已配置单体槽位。
四玩家旧规则理论上限52与新13的对比是配置边界，**不是实机实体计数或FPS收益**。
十转/转生模块未改；maintain_count练功房仍按原数量，四玩家全房间fixture创建296只。

一次物理死亡只退役一个body，只有成功进入该槽位当前阶段、仍有效的个人session走
原个人MONSTER_KILLED/完成/材料链；未进入、迟到、阶段不符、已败退者不广播奖励。
奖励消费者按player/session/completion隔离，没有新增全服钱包或数据库合并。
旧session清理必须同时匹配实体句柄，不能只按可复用entindex删新body元数据；
world epoch、slot life与timer身份共同使旧回调失效。测试验证这些机制，尚未证明真实DB到账。

## 成本与解耦边界

| 场景 | 成本/调用 | 已有证据边界 |
| --- | --- | --- |
| 初始化或真空槽创建 | 按key/entindex/session/player建索引，O(S+P)，S≤13、P≤4；十戒初次10个预览，其他3个按实际入场创建 | 源码和模拟引擎，不是新普通局计数 |
| 稳定共享AI | 每0.5秒保留目标O(1)，无世界枚举、无FindUnitsInRadius/EntIndexToHScript；目标不变不重复SetForceAttackTarget | 真生产modifier fixture连续20次：查询增量0、首次目标写1，随后19次无重复写 |
| 目标变化/死亡/撤回 | 目标失效仅查该槽参与者O(P)；死亡O(P)，玩家离开仅自身session索引；每空槽一条1秒补位任务 | 混合阶段/迟到/重入/败退/同idx新life/旧timer/reset专项通过 |
| 难度/模式变化 | 同状态直接返回；实际变化仅刷新十戒10成员，O(10)，不按tick遍历全场 | 模拟计数，原生耗时待验 |
| HUD缓存 | 稳定100ms对已知路径/库存骨架增量校验，0根递归；真实容器重建才重索引 | 既有生产callback fixture：31→0根查询；不是已测FPS提升 |
| 头像 | 197身份/188场景目录与renderer逻辑LRU4解耦；只选中/有限近期请求，组件不删 | 原生DeleteAsync释放时刻与完整197像素未证明 |
| 排演keeper | 稳定期每2秒一次只读kernel wait，0CIM/哈希/VConsole；控制点才查身份/完整性 | 新1107 run03同handle退出已有，完整close/restore链未闭合 |

本轮解决了特定所有权和热点边界，不是整个工程已完成解耦。模块数量本身不等于FPS因果；
1105旧样本mean100.3055FPS/P95=19.9931ms，P95门槛失败，不能借新单测覆盖。

## 唯一发行入口与硬门禁

稳定入口为`tools/release_pipeline.py`，默认status零SDK/写入。
固定authority pin为`06df3c0d9154b2866463a5e525c85997590a0b8d6f71013b98279c36405eaacb`；
其validator为`e710ef28dcb914f4237f0c78433953b5fc05d9aae8a281faa8a24b3014fa2121`，
recipe为`3019bff7b53f22f4301a399b4a78a3ab24fb18da3fe739d779016298215a7dfa`，
rehearsal为`72c6a012ddf54766ac33bc17ac4d45b898f6bbd5a3a684f0ad75e1d8b8d2a7ac`。

流程是：双仓同步→不可变源码/工具提交→真实plan→unsigned审阅→申请本次17项签名范围→
签名候选→获准普通客户端排演→真实证据preflight→另经明确发布授权更新原条目→官方下载核验。
这次Git源投影是增量准入，Steam仍发完整校验VPK；不是运行热补丁。
bootstrap/preflight不提供Steam发布能力，publish必须持同一live lease，沿既有canonical锁和
journal更新，不能嵌套第二把SDK锁、清pending或失败后盲重试。请求固定在当前REPORT目录并
带SHA；listing仅从固定模板派生content/sequence，名单/封面/可见性不靠CLI任改。

普通验收绑定同signed report、两仓源码游标和原生PID/CIM/100ns创建代际，发布generation整数
与native_process_generation分开。四data卷必须观察到owned Dota+keeper使用；index以签名、
FileID及持有证明，原始indexfalse/all5false/INCOMPLETE不得改成true。
须实看Bane5、敬神QOP09五组件、真实带饰品波次、免费英雄/建造者切换和≥5其他场景后Bane冷回；
正常加载遮罩/原背景/饰品/无QWER与镜头都按实际画面审，不以READY替代像素。
共享Boss须同commit真实领域测试，加同普通局before/death/respawn及第二PC用户确认；
领域假引擎结果不能代替跨PC、DB奖励或FPS。

还须≥30秒实际Intel ETW/CSV与前台证据、前后正常速度计时截图，mean≥90FPS且P95≤16.7ms；
无snapshot/CustomGameEvent/reliable超限等fatal，正常WM_CLOSE与同一retained handle确证退出，
再完整恢复0104五卷。未到这些门槛不发布，不因时间或平均FPS够高降低P95门槛。

## 已做与待做

共享Boss真实service/registry/AI+假引擎专项已通过。发行目录独立复跑24构建+12排演+7组完整
证据测试，共43项（其中拒绝变体另有多例）；根集成新增生命周期检查另记，不把不同suite简单
相加为实机结果。根任务已报告SDK hook9、legacy SDK21+18、guard18、CLI11项隔离结果。
这些隔离计数不冒充实机。后续实际签名/有限像素/一次FPS结果见开头，整体原生/多人/恢复未通过。
下一步补齐剩余真实门槛并安全恢复；门槛未齐不得发布，当前正式0104保持。
