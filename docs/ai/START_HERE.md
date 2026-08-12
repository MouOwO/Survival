# AI Session Recovery - Start Here

> 这是新会话的唯一恢复入口。当前只恢复多人联机工程；旧任务全部暂停并已归档。

## 当前任务

- 当前插入任务（2026-08-11，生产实现与自动验证完成）：基础箭塔/路线计数及并发预占已改为玩家作用域；七塔合一支持每玩家最多5座终极塔，材料不消耗且每座永久仅参与一次；齐天大圣R整组原子迁移全部终极塔并保留相对位置；任意已完工城墙死亡一次性触发全队失败，施工墙和主城不直接失败。专项Lua 5.1/契约、语法、生成一致、UTF-8/BOM和限定diff通过；下一步Workshop Tools完全冷启动实机验收，详见`CURRENT_TASK.md`顶部。
- 当前实施任务（2026-08-12）：外围玩家档案本地Fixture纵向切片已完成生产实现，包含CSV schema/公开白名单/开发账号映射、JSON Fixture生成、统一Provider、完整快照与增量revision/update_id、异步generation、VIP失败关闭、服务端私有档案和公开NetTable。专项Lua 5.1与契约已通过；真实HTTP、数据库、支付、Steam身份和写回尚未实现。下一步冷启动Workshop Tools验证玩家0 VIP、玩家1非VIP和公开表字段；详细协议见`PLAYER_PROFILE_INTEGRATION.md`。
- 逐波模型加载经验已沉淀到`WAVE_MODEL_LOADING_TROUBLESHOOTING.md`，包括W12 Visage告警的确定根因、CSV优先原则、正式/dev/出生统一解析、session租约、urgent并行、禁止误用`asset_preload.retire()`、复发排查顺序和未来逐波换模清单。用户2026-08-11后续观察中暂未再发现加载问题；只能记为阶段性有效，新增模型后仍需冷启动分别验证`monster<N>`与正式波次。
- 当前插入任务（2026-08-11）：闪电魔塔击杀风暴已改为死亡点500范围即时单次物理伤害，LV1至LV5使用触发时塔攻击快照110%/120%/130%/140%/150%；每目标只受伤和发布一次`TOWER_LIGHTNING_HIT`。随后一秒内5/6/7/8/9道雷柱仅作视觉，不查询敌人、不伤害、不触发扩散。原塔归因、风暴连锁击杀及独立雷电扩散30%/200%/非递归规则保留。CSV、生成Lua、Tooltip和六份本地化已同步；专项Lua 5.1行为/契约、相关回归、5个Lua语法、生成逐字节一致、配置CheckOnly、UTF-8/BOM和限定diff通过。下一步Workshop Tools冷启动实测即时伤害时点、物理护甲结果、纯视觉雷柱数量、扩散和连锁风暴，尚未实机验收。
- 当前插入任务（2026-08-11）：`ability_tooltip.js:997` 的几何诊断越作用域 `active.engineSlot` 已修正为函数参数 `binding.engineSlot`，并强制重编译 `ability_tooltip.vjs_c`。源码/产物作用域契约、输入生命周期契约、严格UTF-8和限定diff通过；完整内存生命周期契约仍被既有无关`SURVIVAL_UI_CONTEXT_GUARD_MISSING`阻断。下一步完全冷启动Workshop Tools确认不再出现`active is not defined`，尚未实机验收。
- 当前插入任务（2026-08-10）：本地化缺失/重复token已按最小范围修复。`npc_survival_builder_proxy`和`npc_survival_repairer`已从`unit_display_names.csv`补齐并生成；game六份本地化镜像和content两份Panorama源中的精确单位token、挑战奖励大小写别名、金矿/英雄祭坛显示值已同步。专项契约、冲突扫描、结构、生成一致性、Lua 5.1语法及UTF-8/BOM通过；仍需Workshop Tools完全冷启动确认`FindSafe`与重复token引擎告警消失，尚未实机验收。
- 当前插入任务（2026-08-10）：空区域配置兼容修复已实施。没有有效`hero_movable`时白名单不启用，英雄和建筑沿用旧导航/Grid规则；配置有效行后才启用严格白名单，`building_forbidden`始终独立生效。区域拒绝现在返回完整红色footprint cells，不再让Grid消失。CSV生成、专项契约/Lua 5.1行为和目标语法已通过，仍需Workshop Tools冷启动确认Grid显示、合法建造与拒绝红格；Hammer真实边界只阻断新白名单启用，不阻断当前地图可玩性。
- 已完成插入任务（2026-08-09）：怪物物理伤害按当前Dota护甲曲线补偿到War3目标曲线，且并发stash冲突已解决。117 War3护甲继续线性投影为39运行时护甲；现代非线性映射辅助API保留但不用于波次、挑战或调试怪。`monster_war3_armor_damage_enabled=1`只对明确项目怪物的正护甲物理伤害乘目标曲线/引擎曲线差值，随后仍由引擎结算。固定基准最终倍率约0.299401、理论23.79秒；专项Lua 5.1/契约/语法及科技减甲、毒云回归通过。用户明确确认固定样本测试验收通过，但未提供精确击杀秒数或日志；极高护甲怪仍需独立抽样。
- 当前插入任务（2026-08-09）：怪物尸体、运行时日志和Panorama本地化性能优化已完成生产实现及自动验证。明确标记的波次/挑战/调试怪死亡结算后按CSV保留0.6秒、共享任务下沉0.8秒/160码、隐藏并安全移除；强制清场仍立即删除。运行时成功路径详细日志默认关闭且惰性格式化，Tooltip详细日志默认关闭，四个动态本地化入口使用256项有界缓存。专项Lua 5.1行为/契约、全项目356个Lua语法、生成一致性、UTF-8、配置检查和两仓diff通过；4份Panorama产物均强制编译成功。下一步Workshop Tools冷启动批量击杀并对比实体/日志/帧时间，尚未实机验收。
- 当前插入任务（2026-08-09）：工人训练、建筑提交、普通升级、箭塔升级/转职已改为同步`event_bus.request/handle_request`结果。修理工按team独立消费CSV两级进度（LV1成功5次后进入LV2，LV2成功2次后保留最终完成态并拒绝继续训练），伐木工最终`max_count=-1`无限行为不变；只有单位创建成功才推进进度，创建失败继续退款。建造移动/施工异步失败保存`source_ability`并以独立幂等事务恰好回滚一次冷却，扣费后的创建/施工失败同时退木材、金币和人口。专项Lua 5.1行为、PowerShell契约、目标语法、CSV/生成字段、严格UTF-8、配置CheckOnly和限定diff通过；下一步Workshop Tools冷启动实测失败冷却、资源退款和两级修理工，尚未实机验收。
- 已完成当前任务（2026-08-09）：N1第11–25波以及N2–N5第11–30波普通怪均已调整为每波59只；多怪种按修改前数量比例使用最大余数法确定性放大，单怪种直接设为59。每波`wave_leader`精英和`assault_boss`数量均保持不变。权威`wave_definitions.csv`和生成`wave_definitions.lua`已同步；专项数量契约、Lua 5.1行为、语法、生成逐字节一致、严格UTF-8/BOM及限定diff检查通过。所有难度W1–W10保持原始普通怪数量，仍需Workshop Tools冷启动确认实际生成数量。
- 当前插入任务（2026-08-09）：正式后续波次资源已改为目标波首只敌人出现前4秒异步预载。首波、练功房、塔和城墙启动/后台边界按批准范围保留；敌方`zombie_stream`后台批量加载关闭。专项契约、Lua 5.1行为、语法、生成一致性、严格UTF-8和限定`diff --check`通过；尚未Workshop Tools实机确认4秒日志、模型视觉和首只敌人时刻。
- 当前插入任务（2026-08-08）：`monster19`实机已证明3秒门禁按预期输出`ready_after_buffer elapsed=3.00`，但仍显示红色`ERROR`。本机VPK索引确认最终根因是旧`models/heroes/tiny/tiny.vmdl`不存在；现已从权威CSV改为实际存在的`models/heroes/tiny/tiny_01/tiny_01.vmdl`，重建资产/怪物生成Lua并同步异步代理KV。3秒固定缓冲与连续命令generation门禁继续保留。下一步完全冷启动Workshop Tools复测W19模型和快速`monster19`/`monster20`；新路径尚未实机验收。
- 当前插入任务（2026-08-08）：N1 W13-W18客户端闪退的直接证据是`dota2_2026_0808_033038_0_V8_hiting_max_memory_limit__512_MB.mdmp`，Lua 16 MiB高水位不是同一内存池。用户新日志确认119次Tooltip几何诊断`active`越作用域异常和1次Combat不存在函数调用；两项已修复，`inventory_tooltip.js`也纳入generation/context门禁。Panorama现于启动1秒/5秒及之后60秒输出聚合，默认关闭高频Tooltip长诊断和200次游标探针。下一步必须完全冷启动，先验证出英雄5秒不再异常/退出，再跑N1到W20并核对`[SURVIVAL_MEMORY]`与新dump；尚未实机证明闪退解决。
- 当前插入任务（2026-08-08）：多选箭塔跨路线批量升级已按最新要求完成生产实现和自动验证。基础塔及不同转职塔以共同`arrow_tower`身份混选，各沿自身路线；Q按下一等级费用、W按直升当前阶段最高级累计费用报价，并按木材→金币→entindex升序尝试。客户端只提交最多64个去重候选，服务端逐塔重验owner/建筑/Ability并原子扣费；资源不足等失败跳过，成功受理后才启动冷却。专项Lua 5.1/契约、相关回归、语法、UTF-8和Panorama强制编译通过，下一步Workshop Tools冷启动实测，尚未用户验收。
- 当前插入任务（2026-08-08）：多选金矿批量协调已完成生产实现和自动验证。Q按各矿权威下一等级费用，以木材→金币→entindex排序逐矿原子升级；W/E每次批量请求只购买1级玩家共享科技，成功后同步有效候选冷却；自动按钮按明确目标状态批量开启/停止，混合状态幂等。同一玩家自动矿由最小entindex协调共享科技，其余矿只独立升级本体。沿用现有最多64个候选协议，无Panorama改动。专项批量/自动协调Lua 5.1、契约、箭塔及商店科技回归和目标语法通过；下一步Workshop Tools冷启动实测鼠标、Q/W/E快捷键、部分资源、混合自动状态及多人owner隔离，尚未用户验收。
- 当前插入任务（2026-08-08）：金矿升级后尺寸恢复原状的问题已完成生产修复和自动验证。`gold_mine_config`现把`building_visual_levels.csv`金矿LV1固定视觉投影到全部等级，手动/自动升级提交后均重新应用`radiant_ancient001.vmdl / 0.34`；专项Lua 5.1/契约、语法、生成一致性、UTF-8与限定diff通过。下一步Workshop Tools冷启动连续升级实测，尚未用户验收。
- 当前插入任务（2026-08-08）：金矿已从`tower_good4.vmdl / 1.0`替换为项目已确认可选中的`radiant_ancient001.vmdl / 0.34`，施工视觉、权威CSV、定向生成Lua和单位KV首帧回退已同步；金矿`selectable=true`及全部业务身份/数值保持不变。专项契约/Lua 5.1、生成一致性、语法、UTF-8与限定diff通过；下一步Workshop Tools冷启动验证鼠标命中和五个技能，尚未实机验收。
- 当前插入任务（2026-08-08）：城墙升级生命已由“保持百分比”改为“当前生命增加最大生命差值”；`100/200`升级到上限`400`后为`300/400`。提交瞬间读取即时生命，等级与科技后的最终实际上限共同参与差值；仅修改城墙，CSV生命数值和其他建筑升级行为保持不变。专项Lua 5.1行为/契约/语法、全项目Lua 5.1语法、邻近修理回归、UTF-8与限定diff已通过，仍需Workshop Tools实测。
- 已完成并经用户确认（2026-08-08）：人口训练权威CSV保持原始数据，阶段1至5各`max_count=5`，阶段6为`max_count=100`并启用。运行时按team共享、按`training_id`独立计数，当前CSV阶段达到自身上限后才顺序加载下一阶段；农场等级只校验前置条件。服务端和Tooltip共用CSV递增费用与阶段内进度。用户已明确反馈问题解决，该人口训练修复记为实机验收通过，不再恢复为活跃任务。组合任务中的城墙碰撞与迁移重锚仍保持独立待验收状态。
- - 当前插入任务（2026-08-07）：城墙基础Hull为256；用户实测并确认波次怪角色Hull为普通32、精英64、Boss无碰撞，`scalemonster <倍数>`按角色基准不累计作用于当前及之后波次怪且不改模型；研究所/农场施工、实际视觉及KV回退与英雄祭坛统一为`radiant_ancient001.vmdl`缩放0.34。该任务当时的“金矿保持原生缩放1”已被上方2026-08-08最新金矿可选模型要求替代。专项Lua 5.1/契约、目标Lua语法和diff检查通过；单位模型旧契约仍被无关伐木工CSV缺项阻断，下一步Workshop Tools实测真实碰撞与模型尺寸，尚未用户验收。
- 前序六项玩法修复（2026-08-07）：无声金矿飘字、农场/金矿1/5上限、CSV首发顺序和农场Tooltip实现保持完成；其中金矿旧`0.0875`和后续原生缩放1均已被上方2026-08-08最新`radiant_ancient001.vmdl / 0.34`替代，城墙Hull基准128已替换为256。其他专项验证结果保持有效，仍待Workshop Tools合并验收。
- 当前活跃任务（2026-08-06）：第1-5波数据驱动怪物视觉系统已完成生产实现和自动验证。新增独立视觉资产/组件/效果/波次CSV及生成Lua；按`wave_number + member_role + normal_index`解析，`normal`使用主/辅候选、`wave_leader`使用小Boss、`assault_boss`使用阶段Boss并回退小Boss。W4/W5辅助候选已录入，但未经批准的普通怪混编比例保持`support_every_nth=0`，当前不启用；没有运行时领头怪的波次不会新增Boss。11项模型与10个异步预载代理均通过本机VPK/KV检查，启动预载W1-5并在游戏中排队下一波。`wave_definitions.csv`和`monster_archetypes.csv`无改动。专项解析/服务/波次接入/清理/预载、Lua语法、生成一致性、UTF-8和限定diff通过；下一步Workshop Tools冷启动重点验收W5模型、缩放、动画与性能。
- 当前活跃任务（2026-08-05）：箭塔建造资源成本已完成生产修复和自动验证。工作簿7条路线共175个成本节点与塔CSV全部一致，只有建造适配层错误回退80木材+20金币；现改为从生成的`arrow_tower_base.lua`首级行读取0金币+50木材，服务端扣费与UI共享该值。专项契约/Lua 5.1、工作簿审计、生成一致性、相关回归、语法、UTF-8和限定diff通过；下一步Workshop Tools冷启动确认按钮与实际扣费。
- 当前活跃任务（2026-08-05）：所有防御塔基础攻击/索敌距离由权威`global_rules.csv`统一为1000，射程科技继续叠加。用户实测10000过快后，基础箭塔最终弹速改为5000；其他转职塔恢复修改前速度：神秘/机枪/多重/对空1250，死亡/冰霜/闪电100000，全局倍率恢复1；终极融合继承来源塔速度。专项契约、Lua 5.1、融合回归、语法、生成一致性和UTF-8通过；下一步Workshop Tools冷启动实测。
- 当前活跃任务（2026-08-05）：`N1按最新波次总表同步(1).xlsx`中的现有游戏内容已完成生产同步和自动验证。N1现有70条直接成员行，覆盖25波，普通202、首怪21、进攻Boss5、总228；Profile维持150条矩阵并更新N1四练功房、工作簿五类特殊目标、转生和十戒，工作簿未列的七宗罪材料怪保持既有批准值。存档挑战继续忽略。N1/N2-N5波次、Profile、转生行为、计时、Lua 5.1、生成一致性、UTF-8和限定diff通过；全量生成仍被既有物品CSV类型错位阻断。下一步Workshop Tools冷启动实机验收N1。
- 当前活跃任务（2026-08-05）：`N2按最新波次总表同步(1).xlsx`中的现有游戏内容已完成生产同步和自动验证。N2现有89条独立波次成员（普通1270、领头27、进攻Boss6、总1303），停止N1倍率派生；Profile扩展为150条并覆盖练功房、特殊目标、转生和十戒，N2使用工作簿值，其他难度保持同步前原型值。存档挑战按用户要求忽略；已有wave ID不迁移。下一步Workshop Tools冷启动实机核对N2波次与全部已接入目标。额外发现未修改的转生商店前台旧回归测试失败，未计入本任务通过。
- 当前最新任务（2026-08-05）：Undying外观的独立Builder建造技能从W修正到Q及工具技能尾部排序已完成生产修改和自动验证。阶段系统先按正确CSV添加建造技能，再创建Blink到D；Panorama现将普通技能与D/F/F2工具技能分离，普通技能独占Q/W/E/R/T/Y/U，工具技能稳定追加到尾部。Builder为建造技能后接最后一位Blink D；正式英雄为普通技能后接回城F2、最后拾取F。专项排序/输入/Builder契约与Lua 5.1、语法、CSV生成一致性、UTF-8和两份JS强制编译通过。下一步Workshop Tools冷启动确认视觉顺序、标签、鼠标和实际快捷键，尚未实机验收。
- 最新任务完成（2026-08-05）：开局资源与基础伐木效率修正已获用户明确验收通过。开局金币0、木材10及相关基础规则来自`global_rules.csv`；农民CSV基础效率`1/2/3/5/10/20/40/80`保持不变；资源树收益从LV2开始每级+1，LV1不再整体额外+1。生产修改、自动验证和Workshop Tools用户验收均已完成，不得恢复为活跃或待验收任务；等待用户指定下一项任务。
- 最新任务收束（2026-08-05）：用户反馈“范围拾取F + Builder建造槽位/CD”任务基本完成并要求记录经验。当前仓库已确认F归属、旧英雄圆心300拾取的所有权/排序/满栏停止，以及城墙→主城连续使用Q的CSV阶段槽位；但代码仍是无目标拾取且建造KV固定0.5秒CD，尚未体现鼠标点1000/300 AOE和施工期独立CD。经验已写入`PROJECT_CONTEXT.md`和`SESSION_LOG.md`；后续不得把“基本完成”误记为全部细项实机验收，继续前先核对实际运行分支/产物。
- 当前活跃任务（2026-08-05）：按用户提供的工作簿与截图重构N1–N5怪物难度数据。练功房与六类特殊目标已完成50条`challenge_combat_profiles.csv`录入、生成Lua和挑战运行时接入；遭遇创建时固定全局难度快照，刷新沿用快照，Profile缺行失败关闭，War3护甲只在生成边界换算一次。专项契约/Lua 5.1、挑战与N3-N5回归、Luac 5.1、定向生成一致性、严格UTF-8和限定diff均通过；下一步Workshop Tools冷启动逐难度核对四个练功房及六类特殊目标，尚未实机验收。
- 最新可靠检查点：用户补充的`N3按最新波次总表同步(1).xlsx`已作为N3数量与属性来源接入；N3模型映射、飞行回退和26–30波来源均由用户明确批准。权威CSV现包含N3普通小怪1270、领头怪27、进攻Boss6，总计划1303；N3独立30波难度已启用，飞行普通怪使用本波War3基准护甲3倍。Lua 5.1、契约、生成一致性、计时/减甲回归、UTF-8和限定diff均通过；下一步Workshop Tools冷启动验证每波实际数量、模型、领头怪首发、护甲UI及波次重叠。
- 最新可靠检查点：N4、N5已按本机`N4完全正确_倍率同步(1).xlsx`和`N5完全正确_倍率同步(1).xlsx`接入独立30波CSV。两者各包含普通怪1270、领头怪27、进攻Boss6，总计划1303；沿用已批准N3模型映射、确定性数量分配、飞行回退、普通飞行怪三倍War3护甲和角色顺序。开局难度选择现启用N1-N5，五格横向一排且不显示描述小字。专项Lua 5.1/契约、N3与计时回归、Lua 5.1语法、生成一致性、严格UTF-8、Panorama强制编译和限定diff均通过；下一步Workshop Tools冷启动验证N4/N5实际出怪与五格布局。
- 插入修复检查点：敌方单位和树木属性UI复用上一个单位的问题已完成生产修复和自动验证。根因是可控输入解析器拒绝不在`GetSelectedEntities()`中的敌方portrait；现新增HUD专用`ResolveDisplayUnit()`，属性/名称/生命/快照链使用display身份，技能与Builder输入继续使用可控`Resolve()`。专项/输入回归、Lua 5.1语法、严格UTF-8、限定diff和两个JS强制定向编译通过；下一步冷启动快速切换英雄、敌人和树木，并确认点击敌人后Q/W/E仍由可控单位处理。
- 插入修复检查点：转生挑战进行中重复购买、副本切换后旧回调拉回英雄及普通Boss刷新错误传送已完成生产修复和自动验证。商店快照与扣费前均拒绝活动中的转生挑战；每玩家唯一前台遭遇覆盖普通挑战与转生进入，延迟刷新校验session/generation/前台身份；普通挑战刷新保留位置，仅仍在前台的`challenge_11`重置到阶段入口。专项契约、Lua 5.1行为、相关回归、生成一致性、语法和UTF-8通过；下一步Workshop Tools冷启动实测重复点击转生购买、普通Boss刷新、十宗罪阶段刷新及十宗罪→转生切换，尚未用户验收。
- 本任务工作区保护基线：已有19个Panorama编译产物、4个粒子编译产物和一批未跟踪测试/日志文件，不属于本任务；用户停止Workshop Tools后连续两次`git status --short`一致。后续不得触碰、回滚或纳入本任务交付。
- 传说：深渊审判焰爆被动已由用户确认没有问题，不再作为活跃或待验收任务恢复。稳定实现只消费`HERO_MAIN_ATTACK_LANDED`并排除次级攻击，以`attack_id`有界去重；触发时读取`HERO_COMBAT_STATS_GET_REQUEST`逻辑三维，以佩戴英雄为500范围中心，逐目标提交全属性×50魔法伤害，并在英雄处播放一次焰爆粒子和声音。完整维护边界见`PROJECT_CONTEXT.md`和`DECISIONS.md`。
- 极寒之刃批量击杀进度修复已由用户在Workshop Tools确认成功，不再作为活跃或待验收任务恢复。稳定规则：成长只消费`ENGINE_ENTITY_KILLED`，不得按victim entindex跨实体生命周期永久去重；召唤/代理攻击沿有界owner链归属玩家；物品charges、Tooltip与成长HUD统一消费服务端投影的实际equipment progress、CSV target和现场remaining。完整根因、测试和验收记录见`PROJECT_CONTEXT.md`、`KNOWN_ISSUES.md`及`SESSION_LOG.md`顶部。
- 相机任务已由用户于2026-08-05在Workshop Tools明确确认解决，不再作为活跃任务恢复：空格定位使用`MoveCameraToEntity(target)`；挑战镜头已删除`SetCameraTarget(hero)`→`SetCameraTarget(-1)`锁定/释放链，改为一次性非锁定聚焦，镜头不再返回英雄传送前位置。稳定规则见`PROJECT_CONTEXT.md`，引擎陷阱见`KNOWN_ISSUES.md`；等待用户指定下一项任务。
- 已否定检查点：第一版曾使用`SetCameraLookAtPosition`并只有Panorama本地日志；虽然静态契约与编译通过，用户实机确认空格不定位、挑战仍回弹。该方案已被上方第二版替代，不得恢复。
- 关联前置修复：未召唤正式英雄时按空格选中隐藏 Undying 占位锚点的问题已完成生产修复和自动验证。Panorama 唯一输入所有者现在接管 `SPACE`：占位阶段选择 CSV Builder，正式英雄替换后选择正式英雄，并覆盖 fallback keybind；Builder身份NetTable声明已补齐。专项契约、Lua 5.1行为/语法和Resource Compiler强制编译通过。下一步完全停止后 Run，召唤前后各按空格并核对`[SURVIVAL_SELECTION] SPACE_SELECT`日志；尚未实机验收。
- 当前最新任务：黑暗游侠专属小游侠已同步新版多目标逻辑，在`MODIFIER_EVENT_ON_ATTACK`正式出手时固定向主目标和最近另外4个敌人并列发箭；落地阶段不再补射，小游侠也不发布英雄转生出手事件。专项嵌套行为、相关回归、契约、Lua 5.1语法、CSV/运行/生成一致性和UTF-8通过。下一步Workshop Tools冷启动确认5箭视觉同步、各目标独立结算和次级附带效果隔离。
- 当前最新任务：转生多目标普通攻击已从主箭命中后补射改为`MODIFIER_EVENT_ON_ATTACK`正式出手时并列发射，生产修改和专项/相关回归、Lua 5.1语法、CSV一致性及UTF-8验证通过；真实命中业务和次级attack record隔离保留。下一步Workshop Tools冷启动确认主/次级箭视觉同步、独立结算与技能隔离，并提供`[DROW_VISIBLE_MODIFIER]`日志归因黑暗游侠Buff图标；未归因前不删除Modifier。
- 待实机验收：祭坛召唤按钮修复已完成代码和自动验证，等待Workshop Tools冷启动实机确认。根因是creature祭坛动态Lua Ability经`CastAbilityNoTarget()`不可靠进入`OnSpellStart`，而服务端直接权威分发遗漏`ability_summon_*`；现复用既有Ability→hero_id映射直达`HERO_SUMMON_REQUEST`，客户端也显式托管召唤/旅行按钮。下一步选中祭坛点击免费英雄，确认`SEND_NO_TARGET`、`ALTAR_SUMMON_DISPATCHED ... ok=true`及正式英雄替换。此前缺失的`survival_builder_identity` NetTable声明已在空格选择修复中补齐，相关输入生命周期契约恢复通过。
- 科技研究进度与完成时序修复已完成代码、专项测试和资源编译，当前等待Workshop Tools冷启动实机验收：开始时服务端校验并立即扣费，但2秒研究期内保持旧等级/旧效果；同队同时只能研究一项；进度卡只显示径向遮罩、不显示`2 → 0`数字；结束后才提交等级、重算效果并提示“已完成研究”。提交异常会恢复旧等级并退款，迟到/重复回调不能二次升级。旧`technology_cooldown_*`协议字段暂时保留，但语义已改为研究进度。下一步完全停止并重新Run Workshop Tools，逐项确认扣费、团队互斥、无数字进度、延迟生效和完成提示；未经用户实机确认不得记录为验收完成。
- 用户已在 Workshop Tools 确认 Builder 当前可以正常建造，`builder_not_owned`、Grid 校验与建造提交主链视为实机通过；尚未据此推定城墙 Q 升级、完整 Q/W/E/R/T+D 或连续两次 Run 均已验收。6 个 Panorama 二进制生成物曾残留 Git `UU` stages，现已全部从当前 content JS 权威源强制重编译并精确暂存为 stage 0，未选择整仓 ours/theirs、未提交、未触碰其他既有修改。
- Builder ownership/槽位/建筑选择最新补丁已完成自动验证：普通 creature 的业务身份改由 `builder_service` 注册实体和 `survival_player_id` 权威解析，Grid/Building/建筑 Ability 路由不再假设 `GetPlayerOwnerID()` 有效；CSV `slot_order` 显式映射五个建造槽 index `0..4`，Blink 独立 index `5`。Grid、建筑移动与托管 Ability 输入统一当前选择解析并拒绝跨选择 runtime owner。专项 Lua 5.1/契约/语法/UTF-8/限定 diff 通过，四个 Panorama JS 均强制编译成功。下一步冷启动 Workshop Tools 验证 Q Grid、建造提交、城墙控制与 Q 升级、最终 Q/W/E/R/T + D。
- 最新可靠检查点：占位 Undying 物理/选择残留与 Grid 永久等待修复已完成自动验证。专用生命周期 Modifier 使占位锚点不可选择、无单位碰撞、命令受限且不可移动；Grid validate 的早期错误现在携带原 session/request/Ability/request anchor 返回，不再被客户端按默认 `(0,0)` 静默丢弃。客户端与服务端已有完整 `[GridPlacement]` 请求级日志。Builder专项契约/Lua 5.1行为与语法、输入/utility/Alt契约、严格UTF-8、两仓限定diff和 Grid Panorama 强制编译均通过。下一步完全停止 Workshop Tools 后 Run，验证移动无阻挡、W/图标网格和提交；若失败，提供同次操作的 `[SURVIVAL_INPUT]`、`[SURVIVAL_CAST]`、`[GridPlacement][CLIENT/SERVER]` 日志。
- 当前活跃任务为 Undying 建造者代理、祭坛英雄替换及其 Panorama 输入修复：生产代码与自动验证已完成。独立 `npc_survival_builder_proxy` 承接建造、D Blink、修理、选择和 UI；Ability runtime owner 现在是托管施法权威 caster，建造点击/快捷键强制进入冻结 Builder/Ability 身份的 Grid session。`ui_bootstrap.js` 每次 HUD generation 无条件重建唯一 dispatcher 与 generation keybind，消除第二次 Run stale callback。专项契约/Lua 5.1、相关回归、Lua语法、严格UTF-8和6个Panorama强制编译均通过。下一步完全停止并连续 Run Workshop Tools 两次，验证所有权、选择、全部快捷键、建筑点击、Grid、替换和死亡复活；首版不宣称代理为真实 courier class。
- 英雄最终伤害原生飘字分流已由用户确认完成，不再作为待验收任务恢复：普通攻击使用`OVERHEAD_ALERT_BONUS_SPELL_DAMAGE`白字，暴击使用`OVERHEAD_ALERT_CRITICAL`原生表现，带有效Ability的正式技能伤害使用`OVERHEAD_ALERT_DAMAGE`红字；三者均显示最终`OnTakeDamage.params.damage`，上一版Panorama暴击链已移除。稳定经验见`PROJECT_CONTEXT.md`。
- 齐天大圣E全属性×5暴击附伤修复已由用户实机确认数据正常，本任务完成且不得恢复为活跃任务。稳定方案是在最终`OnTakeDamage`阶段消费已确认的主攻击暴击身份并发布`HERO_FINAL_CRITICAL_ATTACK_DAMAGE`，不在较晚`OnAttackLanded`读取可能已销毁的record；次级攻击与W分身排除，伤害事务失败输出`MONKEY_KING_E_DAMAGE_FAILED`。长期规则见`PROJECT_CONTEXT.md`。
- 当前活跃任务为“超级防御塔暴击”四项效果修复。代码与自动验证已完成：每级同时增加防御塔暴击/攻击和召唤英雄暴击/攻击各 `0.5%`，CSV 的23级均有四行说明，生成科技 Lua 复合投影接入现有塔与英雄刷新/攻击链。下一步完全停止并重新 Run Workshop Tools，实机确认 Tooltip、已有单位即时刷新、实际攻击值和暴击率；未经用户确认不得记录为验收完成。
- 当前活跃任务为英雄实际射程与工具技能归属修正。用户最新批准齐天大圣由30000速度远程弹道改为近战式无飞行弹道结算，攻击/索敌仍为1000；CSV、生成Lua、运行时分流和自动验证已完成。Undying只保留D闪烁并修复D键；召唤英雄不拥有D，保留F范围拾取和F2回城。当前等待Workshop Tools实机验收，未经用户确认不得记录为制作完成。
- 三选一公共技能`proto_arcane_barrage`/“奥术弹幕·被动”已将每颗随机落击从基础爆炸替换为天怒法师秘奥耀光单次落击`skywrath_mage_mystic_flare.vpcf`；每颗CP0仍绑定Lua权威伤害落点，未接入会自行随机落点的持续ambient父粒子。5/7/21颗、调度、150伤害范围、全属性伤害和活动锁均未修改；专项契约、Lua 5.4.5语法、严格UTF-8和限定检查通过，下一步冷启动Workshop Tools实测连续落击外观、落点一致性和21颗性能。
- 齐天大圣W分身数据复刻实机反馈已完成代码修复和自动验证：攻击、最终攻速、生命、暴击及逻辑三维统一消费本体同一份`HERO_COMBAT_STATS_GET_REQUEST`快照；生命复用隐藏生命Modifier，分身选中面板也适配同一快照。下一步Workshop Tools确认本体/分身攻击、攻速、生命、暴击、三维面板一致且固定10护甲、仅Q隔离未回归。
- 齐天大圣Q/W/E/R专属技能、严格顺序`passN`与通用七塔合一已完成代码和自动验证；当前状态为等待Workshop Tools实机验收，不得描述为制作完成。Q/W/E/R分别1/3/6/10转解锁，四槽固定置灰；终极塔使用7个隔离代理执行真实路线攻击并由R继承英雄攻击/暴击。详细实现、测试与实机清单见`CURRENT_TASK.md`顶部。
- 资源树第二轮紧急修复待实机确认：第一轮移除Modifier重复分类后仍不掉血，现确认实机DamageFilter不保证`damage_category_const`，旧Mock错误掩盖缺字段拦截。已新增`ON_ATTACK_START`一次性真实攻击凭证，缺类别平A凭凭证放行，塔/技能/无凭证脚本伤害继续拒绝，并输出限次`TREE_DAMAGE_FILTER`诊断。
- 第一轮树Modifier重复分类修复已被实机证实不充分，勿再恢复“DamageFilter类别字段始终存在”的假设；下一步冷启动验证第二轮真实攻击凭证方案。
- 三选一公共技能`proto_void_pulse`/“虚空震爆·被动”的卡尔龙卷风视觉维护已完成：恢复content源`particles/survival_tornado/survival_tornado_follow.vpcf`，仅引用Valve `invoker_tornado_child.vpcf`且不含内部移动算子；生产主/小龙卷继续由Lua每0.05秒写CP0追踪。Resource Compiler强制编译为`1 compiled, 0 failed, 0 skipped`，新视觉契约、Lua 5.4.5语法、严格UTF-8和限定检查通过；下一步完全重启Workshop Tools Run确认视觉追踪、附着、死亡停留和LV5分裂。
- 紧急启动阻断已修复：提交`85ce4eb`引用但漏提交的`systems/building_upgrade_process.lua`已补齐；`building_upgrade_system.lua`与`addon_game_mode.lua` Lua 5.1语法、升级完成/重复拒绝/销毁取消/重置/失效建筑行为均通过。下一步必须完全停止并重新Run Workshop Tools确认不再出现`module not found`。
- 当前新增实现待实机验收：资源树初始位置改为`(448,64,128)`；伐木工LV1-LV8统一0.5次/秒、400射程、远程空弹道，LV3与LV6-LV8模型已替换；修理工保持纯修理但距离属性为400；其他五英雄保持远程，齐天大圣改为1000码近战式即时结算；一至四转普攻总目标数为3/4/5/6并按目标护甲独立结算。CSV、生成配置、运行时、KV、专项测试和相关回归已通过，下一步Workshop Tools冷启动验收。
- 紧急阻断已修复：`hero_passive_skill_service.lua`曾因顶层chunk拥有202个local而超过Lua 5.1的200-local上限，导致`addon_game_mode.lua`无法加载。末尾`trigger/roll/on_main_attack`现改为模块表方法，顶层声明降至199；Lua 5.1语法、8项公共技能状态和四英雄专属回归已通过。仍需完全停止并重新Run Workshop Tools确认地图实际进入。
- 当前活跃任务：资源树、召唤祭坛、主城、伐木工LV1至LV5及修理工LV1至LV2模型替换。CSV权威配置、定向生成、运行时应用、KV首帧回退与模型预缓存已完成；11个模型均在当前Dota VPK中确认存在，专项合同、Lua 5.1行为/语法、生成一致性、编码列数、限定diff及树伤害回归通过。下一步在Workshop Tools确认树尺寸、工人动画、主城五级缩放/切模及祭坛尺寸，未经实机验证和用户确认不得记录为制作完成。
- 活跃任务：把现有单人服务器权威玩法逐步改造成最多4人的个人防线联机玩法。
- 当前阶段：阶段1生产实现与自动验证完成，等待Workshop Tools单人冷启动验收。
- 玩法权威：每玩家独立经济、建筑、Builder、英雄和波次怪；空间共享；城墙可集中建造；怪物绑定所属玩家城墙；英雄可跨区支援；不能控制他人单位。
- 网络权威：客户端只发送操作意图，Lua服务端校验并执行，Dota 2引擎同步实体结果。

## 最后可靠检查点

- 2026-08-12玩家档案Fixture纵向切片代码与自动测试完成；已增加公开投影成功日志，可直接核对玩家0/1的Fixture账号、revision及公开白名单字段。VIP权威CSV默认关闭，Mock账号验证后再投影。尚未Workshop Tools实机验证，也未接HTTP/数据库。
- 2026-08-10空区域配置兼容策略已落地：CSV无启用`hero_movable`业务行时保持旧地图导航与Grid建造，区域拒绝仍返回可渲染红格；等待Workshop Tools实机验证。
- 2026-08-06已完成代码库只读审计并建立完整任务清单。
- `addon_game_mode.lua`和`addoninfo.txt`已开放4名好人方玩家。
- Builder已经按player注册并保存`survival_player_id`，是多人身份改造的可复用基础。
- 资源、Builder阶段、建筑上限和波次仍存在team或全局单例状态，尚未迁移。
- 地图源存在`template_map.vmap`和`survival_dev.vmap`，当前只确认历史波次marker `monsterborn`，尚未建立4套玩家marker。
- 旧`CURRENT_TASK.md`与旧`START_HERE.md`已归档为`docs/ai/archive/2026-08-06-pre-multiplayer-*.md`，不得作为活跃任务恢复。

## 尚未确认

- Hammer中东南西北4个玩家槽位的最终位置和marker名称。
- 当前Dota版本下未发布addon的最佳两客户端加入入口，需要在阶段2用两台机器实测。
- 支援击杀的成长和额外奖励归属，阶段6前必须由用户确认或写入CSV规则。
- 同一挑战是否允许多名玩家并发进入同一个挑战实例，阶段7前确认。
- 正式档案键直接使用Steam Account ID，还是由后端映射为自有账号ID。

## 下一步唯一动作

完全停止并冷启动Workshop Tools，确认玩家0加载`mock_account_10001`后VIP链可用、玩家1加载`mock_account_10002`后VIP链锁定、`survival_player_public_profiles`只含CSV白名单字段且无Lua异常；随后恢复多人阶段1单人/双客户端验收。Hammer区域边界与玩家1出生Marker仍是后续地图数据阻断。

## 恢复顺序

1. `docs/ai/START_HERE.md`

2. `docs/ai/CURRENT_TASK.md`
3. `docs/ai/PROJECT_CONTEXT.md`
4. `docs/ai/DECISIONS.md`
5. `docs/ai/KNOWN_ISSUES.md`
6. 涉及波次模型加载、预载或换模时读取`docs/ai/WAVE_MODEL_LOADING_TROUBLESHOOTING.md`和`docs/ai/WAVE_MODEL_RESOURCE_LIFECYCLE.md`
7. 仅需历史证据时读取`docs/ai/SESSION_LOG.md`和`docs/ai/archive/`

恢复后先向用户复述当前阶段、最后检查点、未知项和下一步，再修改代码。
