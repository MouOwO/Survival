# 当前进度

2026-10-13最新：用户追加的技能槽横向跳动已修复并接入当前game/content。geometry e733ef5b、production db912a4f、topnav最终29c3bbc1；三个锚点文件编译检查点 `ui_selection_build_20261013_090843_705`，仅topnav热载键恢复的最终编译 `ui_hotkey_build_20261013_100147_746`。630几何场景/10个完整IIFE视口回归、真实完整combat+topnav同实体热载旧源负对照、稳定布局零位置/宽度写入、稳定10秒额外hotkey writer调用0均通过。实际原生PNG `skill_switch_final_tower_hotkeys_resource45.png` / `skill_switch_final_worker_resource45.png` 首槽金边都x719，差0；主动标签可见、被动空。前期研究所图757→719，但快捷键热载缺失属于已定位并修复的中间状态，未用它宣称最终研究所keys通过。其他新截图因真前台检查拒绝未完成；没有捕获其他app图来替代。最后已请求返回原高级研究所，事件成功不冒充实际client选择截图。

正式单怪异步native control2/lane2均完成：18组实际record/launch/land和18个正式damage filter样本到同owner0墙720；30秒单原生hero攻击、32秒自然死亡/killed1、四波怪人口0/sessionreleased/owned NPC removed/基线计数恢复。独立89项审查在 `output/formal_lane_combat_probe_20261013/resource45_independent_review.json`，hero成长漂移与完整参数缺字段限制保留，不能称DPS等价。四消费者兼容层新增16场景347断言、真实旧消费者25负对照，root独立重跑PASS；生产class和factory字节未改，当前native未加载该新兼容层。实际原生尸体modifier/更大数量和FPS仍待。

真实模型几何已用两种现有原生资源读法交叉：LOD0完整Hoodwink套装22478面、裸主体12730面、Dire ranged5959面、Radiant ranged3742面；不推断实际游戏LOD或帧率。商城最后完整条目已按owner分四份UTF8安全原生只读导出；独立递归比较8个owner/phase各660叶值、initial/final与OFF/ON均零差异，并与原初始payload交叉一致，不重跑业务。默认console socket ENOBUFS已用单次显式loopback源端口私有helper恢复；没有关闭eCloud/VPN、重启系统服务或更改网络。对新采样仍要求焦点稳定和新swapchain身份证据，30FPS未达成。

resource45最新实机：已有原参数Tools可运行，原自动认证助手PID53912重新活动导致console竞争，官方Stop确认成功、隧道保留；后端/ready=200，inject成功/临时凭据已删除。正常UI选常规/N2，进入后才实际populate bots，初次arm缺fake owner已显式拒绝；精确停止部分builder observer后重试，四builder未败退确认才host8。正式A准备ready：104workers/52building/4VIP/waves0，host恢复1。新客户端PID62740/HWND3086882，旧ETWswapchain不再可用。

最新Q真实native观察：OFF64/21本体crit/85伤害事件、21本体实际施法；ON64/17crit/81伤害事件、17本体施法、clone6次实际施法、16次为caster重复施法，pool7created/17reuse/24queued/failed0。最后clone存在1 busy lease时own探针停止，明确不把23执行/24queued称为全clone逐次覆盖；本体逐次覆盖通过。停止6/6实际引用IsNull，target/observer/wrapper回收，最终pool0。正常AS和FPS未测，pool默认OFF。

研究缓存native修复复验通过：OFF/ON各10.133game秒，4owner各186–201真实资源事件；ON309reuse/40full（36有界年龄fallback），四份完整商品字段一致、业务/错误0、private仅owner。未减少payload频率：OFF344、ON349只是自然事件数不同，不能称减少消息收益；节省的是完整目录构建。全部4drawer精确关闭、cache恢复OFF，coverage/product_stability true。此前303溢出样本仍保留，未替代或删除。owner0完整首末payload已保存，其余分owner补档。

formal control单怪真实出生：NPC creature/owner0 population1/session1、原cap/range/AI目标wall720均存在；29组三事件record/launch/land约1秒间隔。root诊断订阅误用hero桥而非native damage事件，因此空damage数组不能当没有伤害。60s watchdog先于root迟到kill到达，精确kill拒绝，自动清理unit/session/population0/基线恢复；尚无自然死亡通过。更有界自动30s native单击/32s收尾的新inert probe正制作，不改生产wave。

用户追加技能槽横向跳动，完整实际topnav IIFE/真实枚举helper VM复现固定1672×941下hero4第一槽749.5、tower4 641、tower7 626.5、worker1 671、research10 802.93；高研先0列表733→10项802.93。旧/新枚举缓存源同坐标，主要是旧geometry每次居中政策，快捷键与科技清空无关。正在固定所有第一槽锚点，小视口队列上置自适应，保留旧业务/原生节点/英雄头像；修复前实际截图已保存，不声称已经验收。

新目标history窄修复28组/4212断言由root独立复跑通过，固定预算强handle键防index复用并回收失效目标，尸体/复活/跨world语义保留；真实HScript/collector成本仍待测。世界血条空态新JS定向编译成功，checkpoint ui_health_build_20261013_081149_490；完整IIFE空态600→10回调/几何600→0，活态无变化，尚未单独原生inspect确认，不推导高峰FPS。

resource42复验未执行：实际截图先显示N3已进入世界，旧准备UI坐标已失效；随后三次Lua请求无ACK、console设置仍有ACK。主代理恢复host1并实际截图查到主菜单“客户端版本过低”，只读GameRules=nil。该轮没有Q/商城/波次验证结果，不能沿用resource41当最新通过。已核实并关闭自己的survival PID63152，Steam更新及原参数Tools启动已请求；Steam反复App570 No connection/6 manifests下载失败，更新未完成。准备尝试现有二进制本地Tools，若仍拒绝则记录实机阻塞，继续独立代码验证，不改系统代理/Steam档案、不绕过版本检查。所有采样需要新的PID、窗口与swapchain身份。

正式lane单出生接口已冻结（wave SHA0A3185D2...618A9D），149新集成项和原244出生/死亡/奖励回归通过；默认生产仍原class，只有显式Tools单budget ticket才能选择lane。要求freshmap、新世界N2/dev/4owner ready且wave0/session0，实际原生AI/DPS/死亡/清理待验证。Q最新59组/10负对照通过，legacy OFF/ON仍待实机。商城启动证据helper已改为只返回有界metadata，避免操作已执行后大JSON编码失败误导重复启动。

resource41新场景正常入局/四owner正式Builder通过，准备后104workers/52建筑/4正式VIP（全部public rank3奖励领取，四个真实英雄分别在四court）ready，host恢复1。Q真实128攻击分段第二轮更强native `ON_ABILITY_EXECUTED`：OFF主crit18/复制伤害82，但实际cast14（另3clone caster均0）；ON主crit22/复制86、实际主cast22，18次为重复nativecaster施放；pool6created/19reused/25queued、failed0，5存留caster停止后5/5真实native IsNull，target/观察器/wrapper清理。该证据证明池实际复用且本体覆盖正常；旧legacy自主命令/Playerowner竞争仍有丢视觉，已加legacy新Qcaster精确owner+idleAcquire/acquisition0+Stop，E不动；新场景须复验，不用旧14/18声称全通过。native执行截图resource41_q_active.png保留。

研究后台原生首次流程完成却**未通过**：resource41双10.13game秒、各4owner每段186–202真实资源变化、无业务变化/商品字段一致；ON 0reuse，coverage=false。实际303条shop_system.lua:434 stack overflow：source.unit是自环原生HScript表，旧v2错误深比，快回调被scheduler吞掉，因而ON42payload不是优化收益。私有抽屉和probe均自动精确关闭恢复。已窄修source native handle只用identity、其余已知标量和未知源fallback保留；通用深比不改。新真实scheduler自环回归0错误/16私有payload/13reuse，旧负对照16溢出/0payload。默认OFF，下一fresh场景重新实机。

native lane prototype：第一次严格KV准入因LoadKeyValues将数值字符串解析为number/float32舍入拒绝，未创建actor；专用KV比较只允许3已声明float半ULP、12整数exact、5字符串exact、完整键集合以及alias/control native字段同type/值，档案比较不放宽。resource41 control与lane各一个raw NPC原生创建readback通过：模型/数值/能力/一条healthbar/bountyXP/gold0全部相同，仅class/IsCreature/UnitName预期不同；各自owned stop removed=true。这还不是正式波次AI/死亡奖励或FPS通过，现正在做预算1的惰性正式单出生factory候选。正式生产class未替换。

resource40准备失败样本保留：初始本地console连接EADDRINUSE造成脚本先部分安装observer而未创建fixture，随后host8准备设置和延迟触发正常无墙败退，owner0 defeated/builder_unavailable；没有反败退造假修复，恢复host1并freshmap resource41。新的本地nonce证据helper将自己的脚本异常转成bounded result，不再弹Lua错误框；不重复已执行未知状态的mutation。资源隔离不写真实存档。

2026-10-13 resource39最新同场结果：`resource39_models_original_control` 158帧/5.371891FPS、CPU186.084111ms/GPU51.917470ms/P99231.353612ms；`resource39_models_bare_same_units` 202帧/6.881438FPS、CPU145.251456ms/GPU22.663662ms/P99183.444465ms。30/30焦点，game10/host1、相同455creature/244waves/4owners/镜头；非四网络客户端或持续操作验收。没有重建敌人：236普通怪清掉944props（1398→454）、8首领保留；32完整native数值/AI/目标样本一致，244个GetRangedProjectileName前后一致（空读回，不能当可视弹道图证）；三角形未测。实际截图`resource39_model_before.png`/`resource39_model_after.png`保留。又对换模原怪2751→原墙1393保持自然订单，三个精确record/launch/land于2803.5→2807.03game秒通过，projectile speed当前900（未测before），attachment1，callback已恢复。模型简化降低GPU负担，CPU仍145ms，30FPS未达到。

第三次清波244旧引用全部失效，creature210/props422、session1→0/有效租约2→0，四owner各13建筑/26workers和同帧经济保持；三个周期未见附件递增。Tools活动夹具rank-only导致专属锁定的问题已修正，普通游戏解锁不改。resource39通过public grant给rank3剑圣实际领取Q/W，critical30%，E/R保持锁定；旧128次攻击0crit/0caster不能当池有效证据。下一步真实Q原生施法/回收验证。

已保存源码检查点，四玩家活动夹具正在制作。当前观测的掉帧为活跃战斗相关，不证明具体根因。

首个诊断场景：N2第15波四通道，240远程枪兵+4近战Boss；优先查native处理/事件广播、伤害过滤、工人事件与UI，不先假设近战排队为主要瓶颈。

已有后台console轮询临时停止，采样由root单持久连接执行，结束后恢复。初次探测因历史日志未在15秒内回放完成超时，接收窗口加到60秒后探测成功。

实机已完成：

- `operation_diag_a`：独立instrumented60秒，ETW6.28FPS，VProf463帧/71.8秒。Native NextBot自身29.13ms/渲染帧、MoveTo自身14.94ms、DamageImpact自身19.52ms；server think inclusive68ms不能与其子项相加。Lua scheduler20秒合计752.8ms，当前不能把卡顿主因写成Lua扫描。
- `operation_a_baseline`：seed731、4英雄（猴王/剑圣/黑暗游侠/末日）、28塔、104初始工人，120秒无instrument真实ETW。7.6825FPS，P99338.681ms；各10秒FPS前半段约3.8–4.2、末段约17–18。before波次怪176、after0；活动新建4练功房带40dummy、工人涨至142，尾部不是空闲基线。
- 四人实际计划动作90/90/87/91、接受74/82/78/72，科技完成3/8/10/6次；钱包debug_mode=0且有正常扣费。采样外围活动elapsed131.922秒，原计划150秒尚未执行24/25/26/23步；慢帧延迟同计划前缀，不追赶洪泛。同seed不自动等于相同已完成工作量。
- 活动trace原512环被2078状态事件挤掉，仅保留49动作；原始证据保留，正在将操作trace与lifecycle计数拆开。新增原生英雄攻击/命中/技能观察只在可选独立审计启用，不冒称发命令等于执行完成。
- 第1候选：`systems/enemy_ranged_stationary.lua`，默认关闭、Tools当前world显式启用。只对已真实开火且保守射程内的ranged保持原生攻击并临时取消移动能力，不Stop/重发攻击/改BAT；等待真实覆盖/连贯性/帧率配对。不能把候选写成已完成正式优化。
- 第2候选正在制作Tools probe：仅新生成由城墙AI接管的正式wave单位禁用idle acquisition，另一个单独候选再设置acquisition0；不扩到heroes/clones/workers/challenges，必须核对攻击与死墙转攻。
后续证据：

- operation_a_baseline_v2：120秒有效前台ETW8.8996FPS、P99315.025ms；359条完整动作，四owner90/91/91/87步骤，正常扣费与固定seed前缀独立审计通过。异步建造支出不能等同同步请求窗口净支出。
- operation_a_ranged_v1：native start3190/landed3105但entered0，中途焦点丢失，排除帧率验收。实际没有GetMoveCapability/GetMovementCapability；native range128、wall hull128使center<=range-32几何门槛不适用。
- operation_a_acquire_idle：120秒有效前台7.8474FPS、P99182.271ms，244波次怪全部在场、240远程没有攻击活动；24同实体位置前后完全相同。候选存在行为回归，淘汰并reload恢复。
- 发现正式波次射程设置缺陷：枪兵配置600但native128，两种setter不可用；改用已注册BASE_OVERRIDE只对正式wave路径应用，额外buff/近战contact继续叠加。873真实batch等专项回归通过，等待fresh-map native600和性能验收；检查点output/four_operation_extreme_20261012/range_fix/。
- 血条visibility缓存及单文件编译入口已就绪，未同步content/编译，不能归因于上述样本。
- 非hero正式arrow_tower省吸血hurt事件声明候选默认off，两个属性及真实hero吸血保留；相关回归通过，native覆盖与收益待测。

- operation_a_range_fix：正式 native 射程600已验证，120秒前台ETW5.3501FPS/P99290.796ms；实际p0城墙镜头，357次四owner正常资源操作，244→0波次怪。此项是功能修复，不构成30FPS通过或与旧镜头的同条件性能增益。
- acquisition false候选已淘汰：它冻结了原生wave单位，恢复使用fresh-map。
- ranged ROOTED v2真实覆盖为0：Start/Landed原生record不对称及GetAttackTarget暂时nil，使安全证明没有成立。v3改用既有全局OnAttack的真实Fired(record)与Landed(record)精确配对；默认off，不增加native声明，待实机。
- 共享树事件路由v2实机覆盖4owner/4树；首次Declare均发生于OnCreated之前，4树创建前已正确选择shared；回调错误0，保持原同步事件与成长，FPS收益待匹配采样。
- 更正：40个十宗罪单位是可见的预备展示单位，不是40个正在运行practice AI的训练怪。AI在staged期间未启动；原生NextBot是否仍有成本需单独实验。两个默认off候选分别为staged OUT_OF_GAME及暂停0.1s自定义血条轮询，保留模型、饰品和checkout句柄。
- operation_tail_diag开启profiler/客户端探针，没有ETW CSV，不能作为渲染FPS验收。原生英雄攻击/命中已观察到四owner31/28/26/18次，技能nativeUsed5/9/9/6次；效果冷却观测未确认，不冒称技能效果成功。
- Tools渲染线程出现yield，r_always_render_all_windows=1恢复CSV。operation_tail_render_check 30秒ETW11.05FPS，但第4秒后焦点不合格，排除正式验收。
- 外部Lifecycle wrappers原生计数全部0表示hook未覆盖；不能据此声称事件或AI不存在。原始报告均保留。

- 原生OOG独立功能验收：40/40正式十宗罪展示单位native IsOutOfGame=true、stack1，4owner各10；模型与饰品状态40均known。正式挑战请求先因缺武器正常拒绝；随后仅用正式CONTENT_INVENTORY_GRANT_REQUEST写局内match_item（未写save）构造可进入测试数据，正常START_REQUEST成功。下一次snapshot同40句柄，1个checkout，39个仍staged；model/scale/wearables变化0，active单位原生OOG解除、practice AI恢复且生命真实减少。owner0正式defeat后仅清理自身10个，另外30个仍保留。截图stage_oog_display_models.png可见原生展示模型与饰品；该场景装备改变了战斗值，仅作功能验收，不算FPS配对。
- 血条visibility缓存单文件已编译：worldbar_visibility_cache_build_20261012_180708_583_776e9af4备份manifest保留原content源和compiled artifact。仅1 JS/1 vjs_c，回归通过，待真实客户端getter覆盖与性能归因。
- 原生伐木工AI源码发现GetAttackTarget!=tree即每0.25s下攻击令的路径，尚未证实native正常周期nil和重复下令次数；先制作不改变业务的20秒订单统计，不直接对玩家工人禁锢。
- 测试夹具塔攻污染回归：真人runtime 16/s、65次正式tick可复现static0/total1040；活动fixture将用已有deferred test reset+正式profile event清volatile counter，并阻止迟到profile入口覆盖。原真实profile完整保留、当前world/session绑定、loading必须先等完成。此项属测试隔离修复，不把模拟结果写真实存档。

- operation_a_root_v3_health_ui：新严格实际HWND口径通过（唯一Dota2 HWND3675722/1600×900，120次焦点检查，maxgap1.001s，CSV753正间隔/119.576s）。平均6.2972FPS，P99269.357ms，前80秒10s分段4.5–4.9FPS，末尾清场抬高均值；未达到30。此为ranged v3+HB pause+UI visibility综合状态，无匹配新口径基线，不声称单项或百分比收益。
- 四owner完整动作349，连续action_sequence无dropped；step88/88/87/86，接受289拒绝60，正式科研27/升级47/训练35/新建筑9；150秒计划未完整执行，native订单提交不等同全部效果完成。before244→after0，28塔/4墙保留；射程600、4地图等级1/9/17/24。
- ranged v3：原生held Fired4882/Landed4839，精确record错配/重复0；死亡与不认识的外部modifier正常释放，candidate默认off不自动作为正式最优。
- 伐木工原生20秒独立诊断：104工人8320次Getter全tree，nil/foreign/内部重复订单0，真实harvest1511。重复下令假设未命中，不做worker缓存/root。
- 新profile wrapper原生确认四人static/total/runtime tower-flat均0；个人地图/百分比差异保留。
- 旧focus样本仅PID口径，不能排除同PID零尺寸工具窗口；原ETW数值保留但前台完整性需严格复测。新helper/observer以唯一真实Dota2标题、有效客户区及确切HWND验证。
- wave alive_limit90实际按每owner计算；四人244为每人61，属于当前源码允许范围。原CSV共享90注释与运行源码不一致，不能把244直接定为超额debug压力。

## 可见战场与真实回调复查

- 当前引擎原生 `DOTA_GAMERULES_STATE_GAME_IN_PROGRESS=10`、`POST_GAME=11`；旧资料中的 7 不适用。state10 的旧采样是进行中，不能误判为赛后。新采样在开始前、开始时、结束后都读取实际枚举及状态。
- 发现两个观测缺陷：同 PID 有零尺寸 Tools 窗口；鼠标边缘滚动会把镜头移到海面。真实 HWND/客户区验证已经加入，采样居中鼠标并临时关闭边缘移动、结束恢复，镜头前后读取实际 getter。旧样本数值保留，但不能作为最大可见战斗压力的证据。
- `operation_b_visible_v3`：120 秒，真实 1600×900 窗口、120 次确切 HWND 焦点检查通过，镜头前后均 (1580,4992,260.678711)，state 均为原生进行中10。786正间隔/119.552933秒，平均6.574494 FPS，P99 198.665945ms，最大218.3687ms，全部786间隔大于100ms；没有达到30 FPS。244→152波次单位，4墙和 owner0 的7塔保留，其他3人只有墙；数据/等级独立、常规资源扣费。
- B 操作 trace 339条连续无丢失，step89/75/88/87，接受243/拒绝96。发现 owner1 缓存 builder 已原生失效，35次移动失败，并阻塞了一次肉鸽选卡；因此不能把这轮写成4人操作全部正常。新 Tools 活动版本每次正式取当前 builder、验证原生对象与所有权，选卡独立验证完整profile/owner/session，修复 Lua `choice and nil or error` 的假错误日志。回归通过，等待 fresh-map 原生复测。
- 新 offer 通过正式肉鸽 SELECT 接口异步选择，处理期间该 owner 延后操作，其他 owner 独立继续；不再在弹窗背后继续发同玩家动作。正式 offer RNG 与原动作 plan/digest 分离。
- 真实 Lua debug hook 已覆盖原生 modifier 边界，计数上限100000后约0.33–0.55秒就结束，不能按5秒归一。墙反馈实际仅4个墙的全局 Landed/TakeDamage 声明；下一候选复用已有全局carrier并按目标路由，默认关闭。计数不证明它是主要耗时。
- 可选 debug hook timing 发生不可验证栈展开，已安全停止并恢复自己的 hook；不采用该时间作为收益证据。SetDamageFilter 的闭包和 engine-cached callback 仍需另行覆盖；VProf DamageImpact 的 native/self 时间可能包含未观测 Lua 工作，不能声称全部为引擎或粒子成本。

## 实际联机缺陷与待验收修复

- 自然攻击摧毁 owner0 城墙后旧逻辑直接全局结算，即使其余3墙仍活着。已修正正式参与者墙死亡仅调用个人 defeat，最终结算由全部参与者败退事件触发；保留单人、断线、未知 owner 兼容分支和原死亡表现。真实4人顺序败退/结算一次等6组源码回归通过，等待新地图加载后的自然死亡验收。
- shared wall-feedback Tools 候选已冻结，专项及5项相关回归通过；必须新世界启用并新建墙，旧 modifier 不迁移。下一步核对4墙声明/实际 route/声效与修理工唤醒，然后进行可见镜头的配对采样，不能直接当成正式最优。

- map25 原生 shared-wall：4面墙首次选择 shared，原生声明为空，registered=4、registration_failed=0；大量真实 Landed/positive Damage 正常路由。owner0 自然败退后 active_shared=3、unregistered=1，无遗留该墙登记。
- `operation_b_shared_wall_v1` 无instrument120秒：770正间隔/119.721634秒，平均6.431586 FPS、P99 217.819341ms，真实窗口/镜头/state与清理检查通过。四owner step88/89/89/87，所有肉鸽offer合法选完，remaining0、无假错误；玩家1仍42次正式builder_unavailable，因此该问题升级为生产生命周期调查。其他正常资源/升级、满级/前置/阻挡拒绝保留。没有看到明确 shared-wall FPS 收益，也不能与旧B作百分比归因（英雄操作等工作量不同）。
- 显卡实际 GTX1050Ti 约4GiB，CPU i5-14600KF14核20线程，48GiB DDR5-5200。旧B完整GPUActive均值33.026ms，新B32.815ms，均已贴近30FPS的33.33ms GPU预算；帧间隔约152–155ms说明还有明显GPU以外成本，不能仅看叠加GPU占用率，也不能完全排除图形侧预算。
- 独立真实private damage filter 8秒336次，合计6.1781ms、最大0.0346ms，errors0、restored=true。此为余波而非最大244同条件时间；证明实际入口被覆盖，不足支持它解释全部DamageImpact热点。
- 新debug call-only传入当前仓库明确绝对vscripts根后覆盖绝对modifier与匿名闭包。尾波3只样本100000calls/0.6875秒，6143工作区C/无Lua祖先边界，其中1362旧modifier分类可重叠；`modifier_survival_hero_skill.modifier_value` 1204调用。尾调用/pcall导致helper也可能出现在边界，计数不等于真实引擎绑定数量或self时间。发现generic hero intrinsic目前25正式技能全部非stat effect，却各声明11个永远返回0的属性；正在进行保留getter动态值与未知兼容的按实例精简声明。
- 个人墙自然败退已原生验收：只解除owner0精确Tools保护，由新波真实敌军杀死；墙destroy1、player_defeated1、disconnected/cleanup各1，owner0建筑/英雄/工人及本通道活怪清为0。native仍GAME_IN_PROGRESS10，active=[1,2,3]，其余3墙完整继续受击，通道61/61/64仍活着，全部个人profile/map/revision正确。修复成功，不使用直接Kill/SetHealth/伪造Death。尚未原生验收最后一个玩家死亡时最终结算只一次。
- 玩家1 builder从activity第一步已经不可用，新正式getter确认无对象；城市清理未发现删除路径。proxy仅1000HP且目前phase不带无敌，是正常战斗死亡的待证假设。新默认关闭的lifecycle probe将在下一图prep前记录真实death/最后HP/位置/攻击者，正式FPS前停止，不能用测试重建掩盖。

## 后续功能修复与测试恢复

- 工人败退人口竞态已在真实 worker/resource/training/multiplayer/event_bus 模块中复现：ForceKill 的异步死亡被随后 UTIL_Remove 吞掉，正式列表0而人口仍占用。正式清理改为先逐人调用既有 remove_worker 同步退登记/占用，再执行原生 ForceKill；不清零账户，保留其他资产占用、余额和上限。新专项与6项相关回归通过，尚待新图自然个人败退原生复验。
- hero_skill 声明优化正式代码已冻结：25条现有非stat技能首次Declare为空，11种未来stat effect仅声明对应属性，未知/失效/disabled/nil/native异常保留原11项；按实例首次决定固定。原有getter/激活/等级逻辑未改，2008专项检查与升级/移除回归通过，尚待新实例原生覆盖与FPS测量。
- 新独立 `run_native_cpu_gpu_diagnostic.cjs` 使用signed PresentMon2.6 v2，30秒+8延迟，独立随机ETW会话、焦点/镜头/枚举/人口快照；永远 diagnostic-only，不冒称正式30FPS通过。66纯解析/ownership/cleanup检查通过，尚未在稳定新场景运行。
- 第一个新进程46248在地图重载期间挂起，Responding=false持续、CPU仅背景微增，console handshake无法完成；窗口正焦点不能证明实时画面，截到其他应用/幽灵窗口的图片全部排除。已存仅本地私密的线程小转储（不上传）；98线程RIP为97ntdll/1win32u，不读栈或内存，尚不能识别具体主线程等待或认定死锁。核验PID/Tools/addon路径后重启为58004，实际party截图响应正常。
- 进程变化期间后台Hammer助手确曾恢复为connected，已再次优雅stop；仅证明它运行和认证行为，尚无证据把模式选择/进程重启归因于它。用户再次确认没有其他游戏操作者，继续自动测试。
- 更正冷启动登录假设：`manual_real_game_stress.isolate_writes()`已有 authenticate/login/profile/lottery snapshot 的读白名单，不能把20%加载失败归因于它拦截所有HTTP。新地图仍先完成正常账号准入，再绑定写隔离与4份内存profile；不在原生INIT/VM替换期间提前修改测试状态。58004实际完成模式/N2准入后再次退出；本机console记录 DISCONNECT_BY_USER 后 Quitting，尚不能识别发起者，也没有崩溃证据。没有遗留本任务活动脚本，Hammer bridge仍stopped。已启动61220，显式关闭赛后退出，继续恢复实机。

## 新增资源与绘制成本排查

- 用户补充授权：检查资源回收/对象池、普通怪物低面或无饰品候选、UI高频刷新。保留英雄/召唤外观、死亡表现及正常玩法；候选以同场景证据决定，不直接删全体饰品或池化死亡怪物。
- 原有三域压力控制器独立output复跑 A/B各5seed，共52,681 checks、0 failures；正式源码SHA和奖励生产指针均未改变。报告 `output/four_player_offline_recheck_20261012_v1/report.md`。这是本地生产模块/内存数据库验证，不是四网络客户端、原生碰撞或FPS验收。
- 波次预缓存有resource READY/LOADING去重；新怪fresh_unit路径跳过全世界饰品查找，稳定appearance匹配复用实体。不能声称每次普攻重新加载模型。低面/少组件方案仍需读取当前每类怪的body/组件清单并截图，避免删除必要头部/武器。
- 新 `manual_resource_churn_probe.lua` 默认惰性、显式Tools/write-isolation限定、1–30秒有界；计数Particle创建/释放/控制、Lua可见NPC/饰品创建与移除。保留原生返回值个数/异常、仅恢复自己的wrapper，跨世界不计数。专项通过；缓存的API及引擎内部调用不覆盖，released有限粒子仍自然存续，计数不能等同原生池、模型卸载或内存泄漏。

- PID61220新原生实例确认10个hero_skill modifier首次声明全部为空（已决定=true），功能优化确实覆盖；没有单项匹配FPS归因。
- native完整Entities枚举：出怪前231 BaseNPC/422 props；满批后475 BaseNPC/1398 props，wave244、工人104、展示40、建筑52、战斗hero4，差值恰是244 NPC＋976 props。固定镜头1580/4992、边缘滚动关闭，实际截图可见密集怪群。
- 稳态10.033秒资源API-slot诊断：339次 rattletrap_cog_attack_impact Create/Control/Release，outstanding0、peak1、errors0，自己hook全部恢复；未观测CreateUnit/SpawnProp/UTIL_Remove。此Lua覆盖范围没有每刀重建NPC的证据，不等同完整引擎寿命或泄漏判定。当前没有完整怪物原生对象池；预缓存、stable组件复用、staged checkout复用已存在，释放后的native particle ID不能池化再次调用。剑圣Q临时视觉施法者仍是已知特定创建热点，需单独高攻速场景量化；不盲池化正式死亡NPC与奖励状态。
- 原生PM2.6 v2成功样本 `churn29_pre_wave`：879帧29.867s，CPU FrameTime约33.978ms（约29.43 cadence FPS）、CPUBusy32.793ms、GPUBusy12.447ms，0怪/四人资产。`churn29_peak_original`：141正样本，平均4.814 FPS，244→244；CPUBusy207.650ms、GPUBusy53.782ms，P99 FrameTime约247.963ms。两者都是diagnostic-only，CPU/GPU可重叠不能相加，不能作为同时操作的30FPS通过。
- ambient-only显式同实体处理通过范围核对：236普通波怪、472 owned饰品ambient handles退登记为0，leaders/boss/其他218实体跳过；同244 wave NPC/攻击玩法保留，没有假spawn。候选default OFF，新spawn/existing共用严格world/guard/context政策，seen弱keys。原helper保护native销毁异常，不能把空列表单独当GPU销毁成功。
- `churn29_peak_ambient_off`中途原生QUIT，19秒正间隔仅94帧，后快照/镜头缺失，capture_valid=false。约4.90的部分数值不能算30秒通过或正式收益。native日志00:24:20 QueueNewRequest Quitting，非SetGameWinner/赛后流；窗口先消失，工具finally随后发生，PM/focus正常自有退出，cleanup没杀子进程，不能归因于误杀Dota。退出发起者未查明。
- UI两组生产修复：topnav/production相同URI/abilityname/style赋值缓存，保留进度/cd及时路径；fusion/inventory按实际所选owner/slot/key过滤无关nettable广播，一次burst合并1任务，保留selection/迟到native槽恢复。2000无关fusion广播0任务、1000相关1；inventory1000无关0/相关1及最终tooltip/slot/reload回归通过。四源已定向同步content与编译（checkpoint `ui_presentation_build_20261013_003031_218`），尚待新场景游戏内覆盖与FPS，不能从VM计数推出时间收益。

- 新PID63152正式准入/N2后准备A，仅准备期host8，采样前host1实读。标准Ogre演示完整身体/行走/攻击gesture截图已查看；新`lowmodel30_original`有效30秒baseline244→244，4.963FPS/CPU201.412ms/GPU51.585ms，仍diagnostic-only无持续玩家活动。模型转换初被BAT getter严读拒绝，0视觉写；原生实际API证明4getter均要求extra bool，false/true成功，不传均arity throw。未放宽验证，修正契约后才重试。
- 修正候选读取后同236普通怪原生模型转换，全部HP/BAT/AS/SPA/APS/前摇/acquisition/hull/移速/目标/AI字段比较一致，新失败0，历史前读失败1保留。944旧props退登记，native props1398→454、wave244仍保留；console大报告超过处理窗口首次ACK未收到，随后短摘要/census/实际截图确认已完成，不重复执行转换。
- **Ogre候选淘汰**：真实远程发射大量 missing attach_attack1 warnings。gesture能播放与数据不变不足保证原生远程挂点/投射物效果，未采该状态FPS作优化结论。新spawn hook已stop，自己的Ogre demo2021回收，正式CFG不变但既有236源单位暂保留Ogre，需新图恢复或仅继续下一受控视觉候选。标准官方 `npc_dota_creep_badguys_ranged` 已异步预缓存，root own demo3373的模型实读为 lane_dire_ranged.vmdl，ScriptLookupAttachment('attach_attack1')=1；新模板必须短时真实发射/落地验收再启用，不继承旧认可。
- 正式生产getter修复冻结：hero_combat_stat_service增加varargs，BAT/AS及选中单位router四getter漏false补齐，v3的非高频BAT也修正。严格bool native fixture实际hero初始化/重算/缺配置BAT兜底/选中UI/两人归属/固定率/真实异常fallback PASS，负对照旧checkpoint按预期FAIL；10/11既有相关回归PASS，旧summon UI失败在变更前同样存在（fixture cached10与actual native mock1.4语义冲突），未改算法掩盖。仍待freshmap原生覆盖，不宣称攻速单位改变或FPS收益。
- 正式个人伤害producer窄过滤冻结：已知canonical attacker owner不同于当前hero玩家时提前退出；unknown/异常/冲突保留旧同队分发。真实四producer→permanent/growth/execution/UI A/B有效payload/奖励/成长/浮字一致，80→51事件，7项旧回归通过。只减少Lua事件/下游工作，4个native OnTakeDamage声明仍在，不将纯事件数当FPS收益；当前63152仍旧实例需freshmap。

## 无饰品兼容远程模型原生验证（2026-10-13）

- 原始首次预览目标同帧创建并下令时尚未可见，真实零发射超时被保留。deferred .1s复核current/tokens/CanEntityBeSeenByMyTeam后，exact preview3378/target3381完成3个实际record→launch→land，unknown records0、target HP不变、observer已销毁；没有用gesture或假回调批准。native ranged visibility checkpoint保存原失误。
- 只转换236个普通RANGED波怪；完整455个creature扫描，236次视觉apply全成功、失败0；逐体HP/cap/BAT/AS/SPA/APS/attackpoint/射程/acquisition/hull/移速/target/AI句柄与字段不变，最多保存32条详细样本。8个leader/boss及其他单位跳过。停止hook并回收自己的preview/target后测量，实际战场图ranged31_before_cpu_gpu.png。
- ranged31_no_accessories：signed PM v2有效30秒，182正样本/29.535s，mean cadence FPS6.162267、FrameTime P99204.994ms、CPUBusy162.211ms、GPUBusy24.707ms；before/start/after均244波怪，真实1600×900窗口及相同镜头。相比lowmodel30_original同批244的4.963296/201.412ms/51.585ms，绘制和CPU都有下降，但整体仍远未30FPS。body、props和ambient作为一组候选，不能归因于三角面数；native BaseNPC476（比早基线多1个原生猴哥单位）/props454，额外单位尚待只读归属核对。
- 对同一可见稳定战场另做12秒VProf，仅诊断：75 MainLoop平均160.522ms；INextBot inclusive81.217ms/self50.652ms，DamageImpact inclusive34.257ms/self34.083ms，MoveTo self13.017ms。native self可能包含未观测Lua边界，不视作全C++或粒子时间；该profiler不计正式FPS收益。重心转向实际全局伤害fanout/AI与静止UI多余刷新，保留核心攻击与频率。
- 新UI审查证实survival_ui私有服务不发送idle heartbeat，2秒无新sequence不能判断断线；现有.25s轮询会静止时发full rebuild。正在做启动/恢复的有界单pending、session epoch和退避，以及无active倒计时的护盾轮询清理；事件资源/科技/CD路径保留。

## UI 原生验收与稳定射击候选（2026-10-13）

- survival_ui/commerce_actions定向编译2源，最新检查点ui_idle_build_20261013_025833_596；Tools自动资源重载后从最新唯一只读广告实际读取前/后计数。IDLE33 30秒requests1→1、legacyReads2→2、5秒poll14→20、private received/applied137→203、builder finished无pending；未拥有护盾refreshes1→1，无countdown/refresh timer和重复visible写。回退/倒计时/新会话的全面验证仍仅VM。
- idle33_plain_ranged signed PM v2有效30秒182样本，6.173658FPS/CPU161.909ms/GPU24.772ms/P99207.513ms；与此前6.162无可测FPS改善，不从减少请求次数声称时间收益。
- 新stable acquire仅Tools显式独立flag，在v3已有真实F→Land hold、严格nativeTarget==wall、原ShouldIdleAcquire bool已知时才单次关闭。当前桥接只换public functions到旧module表（现存AI保存表指针），单无yield调用先核对244 AI旧hold/evidence/pending/fired_seen/mode6/idle tokens全空；不迁移旧token/records，原导出只作被动checkpoint。
- 原生覆盖94，94原true→false；真实post-set record pairs累计19544、stalls/mismatch/missing/恢复错误0、没有Stop/攻击令或BAT改动。该数字是整个探针寿命累计，不是每30秒DPS。stop94次成功恢复原true，owned/recovery/errors0、244全true。v3-only对照后也关闭并精确释放94 own root；mode6=0、所有自有标记0。
- idle34_v3_and_stable_acquire有效30秒6.112008FPS/CPU163.544ms/GPU21.393ms/P99212.021ms；idle34_v3_only_restored有效30秒6.127806/163.121/28.083/P99220.204。同PID/唯一链/窗口/镜头/单位与四人资产统计相同，但顺序动态粒子/攻速与时间未逐帧匹配。无提升证据，两候选保持OFF；不因能运行或最新而选择它们。
- 新20wall秒battle32独立短诊断完整前后实体遍历3138；433 healthbar、244 enemy AI(shared attack/death真)、104worker(shared attack真)、4wall反馈legacy、4tree legacy、4equipment、4projection，无corrosive实例。实际global callbacks53072；equipment Damage10616中related8/unrelated10608，projection Record10608与Damage10616，wall每事件10616中1535相关。cached callbacks可能绕包装，0不能当0原生广播；已保存计数/分类/恢复，非FPS仪器。
- 新default-OFF装备吸血共享候选已冻结：复用原carrier、精确attacker路由、首次声明原子登记才省独立事件；未知/旧carrier/失败全部legacy；原4属性和HandleTakeDamage函数体保持原字节。关闭仅停新注册，已省声明的实例在同world guard变化/死亡后在途hit继续原吸血，Destroy exact cleanup。专项与6相关回归PASS，原生firstDeclare/lifesteal尚待新世界。


### equip35 freshmap：共享装备首次原生声明已验证

主动重载同 PID63152，实际截图确认队伍就绪→常规→N2，正式 admission ready/state10。卸图前旧v3/idle-acquire均已精确恢复关闭。新4-owner A夹具正式ready，104工人/28塔/4墙，map_level=1/9/17/24。默认关闭的装备共享probe在创建英雄前开启，carrier_ready=true。原生4个equipment实例均`shared_registered_at_first_declare`、owns=true；registered=4、active=4、registration_failed/route_rejected=0。四英雄BAT/AS/SPA/APS按false布尔ABI读取成功，未手调Declare/OnCreated。装备值均lifesteal=0，因此routed=250仅证明真实路由，不证明吸血；正在做独立正式match装备增减/实际Heal验收。

证据：`output/four_operation_extreme_20261012/equip35_admission.log`、`equip35_ready.json/.log`与`design_refs/menus_v10/work/native/equip35_{admission,after_party,difficulty,ready}.png`。此处非FPS采样，host8仅准备，随后已恢复1。当前正式第15波四通道正常出怪，塔hold仅用于积压对照，不是玩家实战帧率通过。


### equip35 正式吸血、个人败退人口和同轮HUD原生检查

owner1剑圣、owner2黑暗游侠、owner3末日逐一使用正式match库存增/减item_death_mask与真实PerformAttack/ApplyDamage：各正普攻实际Heal一次，法术category0、真实友军category1、移除后0%均无equipment Heal；全部4阶段通过。owner1实际damage640→Heal320/HP2750→3070，.25秒后仍3072，未被health rollback吞回。临时targets各2只、库存、HP、位置和class/Heal wrapper全部恢复。owner0当时原生已有AttackTarget，工具preflight严格拒绝，不停止其战斗来伪造通过；失败调用没有安装新的observer，读回最后状态仍owner1 completed。

原饰品/shared gear新世界244波怪有效30秒ETW：149 frames，5.10929FPS、CPU195.654ms、GPU53.018ms、P99246.933ms；454creatures/244waves/各owner建筑人口前后稳定，焦点30/30，camdelta0。不同世界/卡牌/皮肤，不能与旧5→6裸模实验归因为共享gear收益。

HUD同轮技能列表复用已定向编译（presentation组4源，只有topnav是新增变化），检查点ui_presentation_build_20261013_040511_363。真实12.245秒probe，generation2/captureSerial2，topnav.refresh/layout/fit各61；全局nativeAbilityEntries104=topnav61+其它visibleEntries43，仍保留全局调用与runtime刷新。观察到native style写7604，主要horizontalAlign/verticalAlign/transitionDuration各1926，native getter为null，作为下一只读定位证据。Stop后所有hooked=false，未把instrument调用当FPS。首次工具误检查started元数据中不存在enabled字段，短样本作废并明确Stop；单独ui2有效样本保留。实机HUD截图equip35_topnav_refresh_context.png无布局改动。

释放owner0 exact Tools墙protections后由原生攻击自然打死墙：game仍state10，active[1,2,3]，own26workers→0、人口60→0（以前残59的问题native修复已证实），own13建筑/hero/builder/waves全部退出formal列表；其它三owner各26工人/人口60/原建筑和61波怪保留，profilematches全true。wallDestroyed/playerDefeated/defeatCleanup各1。equipment active_registrations仍4：真实英雄作为已禁respawn/NoDraw/ForceKill的引擎绑定保留且equipment RemoveOnDeath=false，不可据此称4live玩家或确证泄漏；继续核对最终生命周期。证据equip35wall_*及equip35_equipment_after_defeat.log。

本轮builder_lifecycle.start漏传显式enabled=true，因工具默认关闭而未启动，不能声称抓到了准备期builder事件；下一freshmap必须正确传参。当前所有4owner正式builder在败退前均存在有效，不能用此反证旧B owner1丢失原因。


### equip35 四墙自然败退收尾

四墙按owner0→1→2→3顺次只释放exact test protections，native攻击致死。前三个owner败退后分别active[1,2,3]、[2,3]、[3]，state10维持；已读出的前三者工人/人口归零，其他owner原资产保留。最后owner3于04:15:22自然wallDestroyed，日志playerDefeated/disconnectCleanup各1、survivors0，原生S与C各一次进入POST_GAME；真实截图显示夜魇胜利。并非两次比赛结算：两行分别S:Gamerules/C:Gamerules。native SetGameWinner方法调用次数未旁路计数，不用转状态日志冒充该计数。

POST_GAME之后三个只读script_reload_code请求均未ACK；普通console echo与host_timescale/dota_quit_after_game读取仍成功，native窗口实际响应，并非Dota已退出或崩溃。最后owner完整人口/资源census未读取，预装own game-state listener的stop未确认，依靠下一freshmap销毁旧VM/world，不伪造final snapshot。第一份census名equip35_after_owner0_world实际采样已在owner1也败退之后，内容准确是两个owner；后续以two_owners snapshot为准。范围说明与源文件保留equip35_final_native_transition.json/public.log。


2026-10-13 range37：244只正式波怪（每owner61），native范围别名244、失败/回退0，英雄射程modifier只余28塔；原饰品仍保留。30秒ETW 153帧/5.221 FPS，CPU191.476ms/GPU51.480ms/P99233.918ms，非验收采样且无持续玩家操作。短战斗共享装备HandleTakeDamage3次均exact parent；完整原生攻击/DPS还需对照。已新增并纯Lua测试debug_clear_wave_for_comparison，仅Tools隔离4owner世界可调用、完整预检、沿用原清理路径，不结算死亡奖励。当前旧世界未加载此导出，正freshmap resource38加载。

2026-10-13 resource39：上一resource38曾lobby消失退主菜单，不采纳。正常host1重建resource39（准备期单独8倍，性能前恢复1倍），A ready四份不同档案、104工人/52建筑含28塔/4墙/4祭坛/4英雄。projection共享default-OFF候选实际4首次注册，无错误；record与props不变。topnav1保留；worldtitle空idle与loading退场优化分别VM通过后定向编译，两项不宣称FPS收益。30s有效ETW resource39原饰品组合5.533 FPS、CPU180.675ms/GPU39.230ms/P99224.112ms；样本内GPU51→35→30ms在漂移，不跨world归因。新正式清理导出原生验证：244旧wave引用全部失效、454→210 creature、1398→422 prop，resource session1→0、有效租约2→0，4owner每人13建筑/26workers及同帧资源值保留，未结算奖励；2个预热驻留租约保留，不当泄漏。当前在0wave世界以真实native PerformAttack/procs进行Q池OFF→ON短诊断，不是正常AS/FPS验收。

resource39第二组原名同world ETW因第26–29秒第三方进程PID60396抢占焦点而无效（非Dota错误窗口），原始证据保留，不做FPS对比。第二次完整清理仍244旧引用无效、creature210/prop422基线、session0、有效lease0，四owner资产/经济保留；两次复刷未显示模型实体递增。首次Q真实攻击64+64都实际伤害记录，但crit0/临时caster0，发现四专属正式快照全locked1/level0，因此本轮不能给池收益或原生施法验证；现修正Tools活动夹具的正式专属奖励领取。正式游戏解锁规则不改。裸远程原型在resource39实际3个record→launch→land，attachment1，目标HP保持（探针零攻击、不算DPS）。
