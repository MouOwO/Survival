# AI Session Recovery — Start Here

> **这是所有新会话的唯一恢复入口。** 不要仅凭聊天记忆继续工作，也不要先通读整个仓库。

## 当前状态

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

- 已完成实现、待实机验收：资源树`enemy_tree`只承受引擎基础普通攻击伤害；技能、脚本和攻击触发附伤全部无效。所有箭塔及转职塔不得自动或手动攻击树。生产实现与自动验证已完成；下一步是在Workshop Tools验证自动选敌、手动攻击命令、实际扣血分类和树耗尽升级。未经实机验证及用户确认，不得记录为制作完成。

- 四名免费英雄替换、固定Q槽专属技能、地狱火/小游侠活动锁及两种召唤物100%攻速继承已完成；用户于2026-08-02明确确认任务成功并验收通过。本任务不再作为活跃任务恢复，除非用户以后报告具体回归或提出新需求。

- 新公共技能 `proto_echo_slash` / “回音重斩·被动”已完成CSV、生成配置、五级运行配置、真实线性投射物、Ability KV和Tooltip。内部纯刀光方案经两次实机失败后已废弃；用户授权保留Kez模型，当前改用完整`kez_katana_echo_strike.vpcf`父粒子及其Kez/ground/movement/streaks/swoosh等子效果。每道用起点→中点、中点→终点两个0.5秒完整视觉实例覆盖1秒路径；完整父粒子的0.5秒移动载体曾因`DestroyParticle(..., false)`在收尾后继续外推，现所有视觉阶段边界统一立即销毁。碰撞投射物仍无视觉且唯一负责战斗，不调用原生能力、modifier、声音或额外结算。专项状态/契约、相邻视觉回归及Lua 5.4.5语法已通过，仍需Workshop Tools冷启动确认末端额外斩击消失且无明显断帧。
- 用户已于2026-08-03明确重新开启公共技能`proto_earth_line`五级“地裂冲击·被动”的移动视觉：Tiny岩石已替换为项目卡尔滚动父粒子`particles/survival_earth_line/survival_earth_line_chaos_meteor.vpcf`。该资源保留Valve陨石模型、火焰、拖尾、烟尘、贴地和滚动旋转，移除落地冲击/屏幕震动，并由CP2.x把原版0.2秒载体延长到权威飞行时长；碰撞仍由无视觉线性投射物唯一负责。Resource Compiler结果`1 compiled, 0 failed, 0 skipped`，专项状态/契约、Lua 5.4.5语法、严格UTF-8和限定检查通过；下一步完全重启Workshop Tools Run验收尺寸、贴地、方向、500速度同步、全路径连续和终点无残留。
- 五级“陨石坠落·被动”的CSV、运行逻辑、Buff、KV、Tooltip、定向生成和自动测试已完成；用户已确认不滚动、同点双陨石间隔0.5秒、第二颗全部伤害80%、每片熔岩独立结算3次及全程同技能活动锁。`addmonster`测试怪提高至600移速后，用户已实机确认LV3-LV5熔岩30%减速正常；其余陨石视觉、伤害、时序和活动锁仍按实际验收状态处理。
- 召唤英雄生命第一版直接Set方案实机仍为120，已废弃；第二版隐藏永久生命Modifier已由用户实机确认血量正常，作为可靠基线保留。
- 已确认普通英雄初始最大生命3000，齐天大圣/剑圣11000；`blood`百分比按当前最大生命，减血最低1点。
- `proto_holy_pulse` 已重做为五级“元气弹·被动”，毒云已改为活动期间禁止同一英雄再次触发。
- 元气弹飞行弹体已改为Sven Storm Hammer；LV5独立20%爆炸使用Storm Hammer原生爆炸，伤害范围仍由配置固定为250码。专项状态/视觉契约与Lua 5.4静态验证通过，等待Workshop Tools冷启动实机验收。
- 配置、运行逻辑、定向生成、专项测试、共享回归、Lua 5.1语法、严格UTF-8和限定diff检查均已完成；等待Workshop Tools实机验证和用户验收。
- 正在将公共技能 `proto_flame_burst` Lv5三颗随机溅射的龙破斩视觉替换为Snapfire Mortimer Kisses。
- 生产修改、定向Lua状态测试、视觉契约和相邻视觉回归已通过；仅待Workshop Tools实机验收。

## 最后可靠检查点

- 日期：2026-08-04
- 奥术弹幕每颗权威随机落点现创建并释放天怒秘奥耀光单次落击粒子，启动预缓存已同步；旧基础爆炸预缓存继续保留给毒云死亡爆炸。新增专项视觉契约锁定CP0、预缓存、排除ambient随机父粒子和既有5/7/21颗、150范围、顺序调度配置。
- `ARCANE_BARRAGE_VISUAL_CONTRACT_PASS`、生产Lua 5.4.5语法、严格UTF-8和限定`git diff --check`通过；本轮没有可用Lua 5.1可执行文件，未宣称Lua 5.1验证。毒云旧视觉契约仍失败于本任务前已有的创建模式断言，本轮未修改毒云运行区段。
- 下一步唯一动作：完全停止并重新Run Workshop Tools，逐级触发奥术弹幕，确认秘奥耀光逐颗落在伤害中心、连续21颗显示完整且无明显性能问题。
- 日期：2026-08-03
- 地裂冲击卡尔滚动视觉的生产Lua、content粒子源、game编译产物、预缓存和专项测试已落盘；主服务顶层local仍为199。当前环境只有Lua/Luac 5.4.5，没有可用Lua 5.1命令，因此本轮不宣称Lua 5.1验证。
- 相邻回音重斩、陨石坠落、元气弹状态测试及回音重斩、脉冲激射、魔法弹弓、陨石坠落、元气弹视觉契约通过；移动冰球契约因本轮前已有的旧基础弹体常量失败，地裂差异未触碰该区域。
- 下一步唯一动作：完全停止并重新Run Workshop Tools，实机触发地裂冲击，检查卡尔陨石尺寸/高度、地面贴合、固定方向、500速度与碰撞同步、并行实例、终点无残留及既有无伤害爆炸。
- 日期：2026-08-03
- 回音重斩末端额外斩击已定位为完整Kez父粒子内部0.5秒移动载体在非立即销毁后继续存活；不是CP1终点错误，也没有第二个延迟父载体。阶段切换、正常终点、异常及重置现统一立即销毁视觉父粒子并释放索引，权威碰撞和伤害代码未变。
- 下一步冷启动Workshop Tools，分别观察0.5秒换段和1秒终点，确认额外前冲消失并检查换段是否有明显断帧。
- 日期：2026-08-03
- 树位置、工人远程属性、四个伐木工模型、六英雄远程和转生多目标普攻已完成权威CSV、生成Lua、运行时和KV实现；专项合同、Lua 5.1行为/语法、VPK模型、生成编码、树/免费英雄/射程/减甲回归及限定diff检查通过。
- 下一步：完全停止并重新Run Workshop Tools，确认树位于`(448,64,128)`、伐木工无可见弹道且400射程、修理工不攻击、六英雄均可按CSV射程远程攻击，以及一至四转实际攻击3/4/5/6个目标并按不同护甲独立扣血。
- 当前任务最新数值与结算：齐天大圣攻击/索敌距离为1000，攻击能力为`melee`，不配置飞行弹道；攻击前摇结束时应像近战英雄一样直接命中。所有召唤英雄通过隐藏永久Modifier落实CSV射程。Undying只保留D闪烁、NO_ATTACK和原生主体/饰品，召唤英雄保留F拾取与F2回城且不拥有D。
- 下一步：完全停止并重新Run Workshop Tools，重新召唤齐天大圣验证1000码近战式即时结算和攻击事件回归；同时验证Undying仅D且可正常选点、召唤英雄F/F2、真实物品所有权/满包、防复制以及Undying主体显示/重生/不可攻击树。
- 日期：2026-08-03
- 回音重斩内部纯刀光方案实机先后出现残缺、大圆环和端点白爆，现按用户授权改为完整Kez Echo Slash父粒子，允许显示Kez模型。完整资源作为独立视觉层按起点→中点和中点→终点两段驱动；权威碰撞、五级波数/概率/伤害和1秒路径不变。
- `ECHO_SLASH_VISUAL_STATE_PASS`、完整父粒子视觉契约、剑刃震荡隔离、Lua 5.4.5语法、严格UTF-8、顶层local 199和限定diff均已通过。下一步完全停止并重新Run Workshop Tools，确认Kez、swoosh、地面痕迹、方向、两段衔接和完整射程。Lua 5.1工具仍不可用。
- 日期：2026-08-03
- 回音重斩已从马格纳斯震荡波替换为Kez Echo Slash纯刀光子粒子；完整Echo Strike父粒子、Kez英雄残影、原生技能、modifier、声音和额外结算均未接入。剑刃震荡仍保留马格纳斯震荡波。
- `ECHO_SLASH_VISUAL_CONTRACT_PASS`、`BLADE_PULSE_VISUAL_CONTRACT_PASS`、Lua 5.4.5语法、严格UTF-8和限定diff通过；本轮环境没有历史记录的Lua 5.1可执行文件。下一步在Workshop Tools确认刀光实际朝向、尺寸和移动观感。
- 日期：2026-08-03
- 用户批准当前任务：齐天大圣攻击/索敌距离以CSV 500为准；Undying建造者D闪烁、F范围300拾取、T回城；删除F2；修复实际射程和头冠/可攻击异常。调查已确认旧`Script_SetAttackRange`不能保证原生近战英雄实际攻击距离，头冠`prop_dynamic`不是攻击者，真正攻击者是Undying主体。
- 下一步：实施CSV与运行时投影、D/F/T能力、NO_ATTACK和Panorama输入，并执行Lua 5.1、契约、生成、编译、UTF-8及限定diff验证。
- 日期：2026-08-03
- 树位置、工人远程属性、四个伐木工模型、五英雄远程/齐天大圣近战式即时结算和转生多目标普攻已完成权威CSV、生成Lua、运行时和KV实现；专项合同、Lua 5.1行为/语法、VPK模型、生成编码、树/免费英雄/射程/减甲回归及限定diff检查通过。
- 下一步：完全停止并重新Run Workshop Tools，确认树位于`(448,64,128)`、伐木工无可见弹道且400射程、修理工不攻击、其他五英雄保持CSV远程攻击、齐天大圣1000码攻击无飞行弹道，以及一至四转实际攻击3/4/5/6个目标并按不同护甲独立扣血。
- 日期：2026-08-03
- 已消除阻断地图加载的Lua 5.1顶层local上限错误：`hero_passive_skill_service.lua`由202个顶层声明降至199，`luac5.1 -p`确认主服务、专属服务和`addon_game_mode.lua`通过。
- 下一步：完全停止并重新Run Workshop Tools；先确认不再出现`main function has more than 200 local variables`，再继续模型实机验收。
- 日期：2026-08-03
- 模型替换已完成：资源树使用Mango Tree；伐木工LV1至LV5和修理工LV1至LV2使用用户指定模型；祭坛使用tower_good4；主城LV1至LV3使用tower_good逐级放大，LV4至LV5使用tower_good3逐级放大。
- 权威源为`training_definitions.csv`、`building_visual_levels.csv`和`world_visual_definitions.csv`；生成配置逐字节一致，11个模型通过VPK索引验证。
- 下一步：完全停止并重新Run Workshop Tools，逐项确认实际模型、尺寸、动画、朝向、主城升级切模及无粉色/无模型残留。
- 日期：2026-08-02
- 四英雄替换任务已获用户明确成功确认；稳定实现与维护经验已写入`PROJECT_CONTEXT.md`，验收结论已追加到`SESSION_LOG.md`。
- 地狱火和小游侠的攻速继承使用触发瞬间权威战斗快照：`attack_speed`表示每秒攻击次数，召唤物按100%继承并使用`SetBaseAttackTime(1 / attack_speed)`应用。
- 下一步：等待用户指定新任务；不得根据旧的“待实机验证”记录自动重启四英雄替换任务。
- 日期：2026-08-02
- 回音重斩使用`public_13`、`ability_survival_echo_slash`和五级配置；LV1至LV5为1/2/3/3/4波，触发率12%/15%/15%/15%/15%，每波全属性×1，LV5每波独立随机提高5%～20%。
- 每次触发固定英雄起点、目标当时方向、攻击射程和逻辑全属性快照；每波间隔0.1秒、1秒走完全程、总宽200，使用真实穿透线性投射物和逐波命中去重。
- `ECHO_SLASH_STATE_LUA51_PASS`、`ECHO_SLASH_CONTRACT_PASS`、`ECHO_SLASH_LUAC51_PASS`、生成比较、严格UTF-8、限定diff及共享投射物回归通过。
- 下一步：Workshop Tools冷启动后使用`addskill`取得并升级回音重斩，确认图标/Tooltip、1/2/3/3/4波、弧形斩视觉、方向、宽度、伤害和LV5随机增伤。
- 日期：2026-08-02
- 地裂冲击使用Tiny岩石线性投射物；起点和目标位置均在攻击触发时固定，`bDeleteOnHit=false`并逐单位去重，到终点只播放基础无伤害爆炸。
- `EARTH_LINE_STATE_LUA51_PASS`、`EARTH_LINE_CONTRACT_PASS`、`EARTH_LINE_LUAC51_PASS`、`EARTH_LINE_GENERATED_COMPARE_PASS`、相关公共技能回归、严格UTF-8和限定`git diff --check`均通过。
- 用户确认口径为“技能暂时完成”：保留当前实现作为稳定基线，不主动继续视觉、数值或碰撞调整。若未来重新开启，先读`PROJECT_CONTEXT.md`中的地裂冲击维护经验，再从权威CSV和现有专项测试开始。
- 日期：2026-08-02
- 龙卷风规则已确认：攻击命中15%概率从攻击者向目标方向生成主龙卷，速度500、持续3秒；t=0/1/2每次实时读取逻辑全属性并对中心300范围造成×2纯粹伤害，影响范围600。
- LV3起范围内持续减速20%，主龙卷命中目标额外减速15%，离开600范围立即移除；LV4无新增效果。
- LV5主龙卷结束时按仍存活的已命中不同目标数量，在结束位置生成无上限小龙卷；每个持续2秒、随机目标方向、其他参数相同、伤害为60%，仅施加20%范围减速。
- 验证结果：`TORNADO_CONTRACT_PASS`、`TORNADO_STATE_LUA51_PASS`、相关公共技能回归、Lua 5.1语法、严格UTF-8和限定`git diff --check`均通过。
- 实机修正规则：主龙卷每帧以500速度追踪原攻击目标当前位置，第一次到达后附着并直接跟随目标；目标死亡后停在最后存活位置，若尚未到达则先前往该位置，生命周期仍固定3秒。
- 追踪修正后的`TORNADO_STATE_LUA51_PASS`、`TORNADO_CONTRACT_PASS`、相关公共技能回归、Lua 5.1语法、严格UTF-8和限定`git diff --check`均通过。
- 附着修正后的`TORNADO_STATE_LUA51_PASS`、`TORNADO_CONTRACT_PASS`、相关公共技能回归和Lua 5.1语法均通过。
- 新粒子已由Resource Compiler强制编译，结果为`1 compiled, 0 failed, 0 skipped`；专项、共享回归及Lua 5.1语法均通过。
- 用户确认口径：阶段性完成不等于最终优化或全部实机验收完成；不得擅自继续调整数值、视觉或行为。
- 下一步：生命Modifier方案已获用户实机确认；仅在用户需要时继续逐项验收`blood`命令、VIP具体数值、装备叠加和重生保持，不主动改变当前生命基线。
- 爆炎弹现有五级概率、伤害、点燃、随机落点、同步落地和逐颗重叠结算逻辑保持不变。
- 飞行视觉改为`hero_snapfire_ultimate.vpcf`，落地冲击改为`hero_snapfire_ultimate_impact.vpcf`；Dragon Slave生产依赖和预缓存已移除。
- `FLAME_BURST_VISUAL_STATE_PASS`、`FLAME_BURST_VISUAL_CONTRACT_PASS`、五项相邻视觉契约、Lua 5.4语法、严格UTF-8和限定差异检查均通过；历史Lua 5.1工具当前不存在。
- 下一步：Workshop Tools冷启动确认三颗弹体的实际飞行、同步落地、冲击位置和无残留。
- 陨石减速专项已由用户实机确认，不得因旧描述再次调整减速数值或重复实现；如继续验收，仅检查尚未明确确认的坠落/爆炸/熔岩视觉、双陨石间隔、伤害和不重触发。

## 新会话恢复顺序

必须按以下顺序读取：

1. `docs/ai/START_HERE.md` — 判断当前阶段和唯一下一步。
2. `docs/ai/CURRENT_TASK.md` — 恢复用户要求、验收标准、证据和待确认事项。
3. `docs/ai/SESSION_LOG.md` — 从末尾向前读取最近检查点；需要研究脉络时再继续向前。
4. `docs/ai/DECISIONS.md` — 恢复不可随意推翻的架构与行为决策。
5. `docs/ai/KNOWN_ISSUES.md` — 恢复环境陷阱、风险和禁止操作。
6. `docs/ai/PROJECT_CONTEXT.md` — 需要项目全局背景时读取。
7. 仅当当前任务引用历史工作时，再读取 `docs/ai/archive/` 中对应归档。

读取后必须先向用户复述以下四项，再执行任何修改：

- 我恢复出的当前任务。
- 最后一个可靠检查点。
- 尚未确认的内容。
- 下一步准备做什么。

若文件之间冲突，以 `START_HERE.md` 的当前阶段和 `CURRENT_TASK.md` 的用户原始需求为恢复依据，同时把冲突写入 `SESSION_LOG.md`，不得静默猜测。

## 强制检查点协议

在以下任一时刻，必须先更新文档再继续：

1. 用户新增或改变需求后。
2. 完成一轮关键代码/配置调查后。
3. 排除一个重要方案后。
4. 做出架构、数据语义或兼容性决定后。
5. 准备进行大范围编辑、生成、编译或测试前。
6. 工具异常、终端超时、需要用户实机验证或准备结束会话时。

每次检查点至少记录：

- 用户最新原话或准确摘要。
- 新确认事实及证据文件。
- 推断与事实的明确区分。
- 已排除方案及原因。
- 尚未验证的事项。
- 下一步唯一或最小动作。

## 文件职责

- `START_HERE.md`：只保存当前状态、恢复顺序和唯一下一步；保持简短。
- `CURRENT_TASK.md`：只保存一个活跃任务；任务结束后整体归档并新建。
- `SESSION_LOG.md`：追加式研究日志；旧检查点不覆盖、不改写结论历史。
- `DECISIONS.md`：已确认且后续必须遵守的长期决策。
- `KNOWN_ISSUES.md`：仍存在的风险与已解决但需防回归的问题。
- `PROJECT_CONTEXT.md`：稳定项目背景、目录和工具链。
- `archive/`：完成或被替换任务的历史全文，不作为默认当前上下文。

## 用户可使用的恢复提示词

新会话中只需发送：

> 读取 `docs/ai/START_HERE.md`，严格按其中顺序恢复。先复述当前任务、最后检查点、未知项和下一步；不要凭记忆或猜测继续。
