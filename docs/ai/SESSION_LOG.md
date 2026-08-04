# 2026-08-04 — 英雄最终攻击飘字第二轮实机根因与修复

- 用户提供完整`[HERO_ATTACK_DAMAGE_NUMBER]`日志：首次0至64512的record持续`show/clear`，`addspeed`后record从0循环并连续`dedup/clear`；全程没有`roll`且所有`show`均为`critical=false multiplier=nil`。据此确认停止飘字是裸record循环复用后旧去重状态误杀，不是客户端overhead队列；暴击不出现是outgoing getter实机无record导致掷骰入口未执行。
- 科技配置链确认有效：权威CSV的超级塔暴击Lv.1/19/23为0.5%/9.5%/11.5%，technology manager同步投影到英雄暴击率，英雄战斗快照消费该字段。`addtechnology`按传入的具体科技ID设置等级；Lv.1下30次不暴击概率约86%，高概率实机测试应使用`researcher_super_tower_crit_23`。
- 用户批准后完成第二轮修复：本体和齐天大圣W分身使用`ON_ATTACK_RECORD`掷骰并准备本次outgoing倍率；每次新record先清除同攻击者同编号上一代显示状态；共享身份键由裸record改为`attacker entindex + record`，多目标继续按victim去重；销毁事件清理长期身份和未消费的临时倍率。
- 自动验证通过：专项Lua 5.1行为/契约、超级塔暴击Lua/契约、科技CSV定向生成逐字节比较、英雄多重攻击、猴王QWE/近战/塔、研究减甲回归、目标生产与测试Lua 5.1语法、严格UTF-8。全量生成器因项目既有装备CSV类型错误`invalid number: equipment_iron_armor_01`中止，未出现新的工作区路径；本任务改用临时文件定向生成科技Lua并比较通过。
- 尚未完成Workshop Tools实机验证。下一步冷启动并使用Lv.23，确认日志出现`roll chance=11.5 → show → clear`，暴击伤害倍率实际生效、橙字使用最终扣血、record循环后仍持续显示。

# 2026-08-04 — 最终伤害飘字首轮实机失败反馈

- 用户反馈：疑似首次暴击时没有显示暴击数字，并且从该次攻击后所有攻击伤害数字均停止显示。提供的日志没有Script Runtime Error或堆栈，只显示齐天大圣真实攻击DamageFilter的category=nil及其他常规日志。
- 本机Dota目录未发现近期可读取的console日志，现阶段不能静默断言根因。优先取得暴击时刻前后完整红色Lua错误；若确认完全无错误，则为最终显示函数增加调用前后诊断，区分回调停止、record提前清理和Valve overhead队列/样式互斥。
- 用户确认控制台完全无红色错误。已在modifier_weapon_stat_projection.lua增加最多80条[HERO_ATTACK_DAMAGE_NUMBER]诊断，覆盖record暴击roll、最终show、重复dedup和销毁clear；不改变伤害或显示调用。诊断版通过DAMAGE_NUMBER_DIAGNOSTIC_LUAC51_PASS、HERO_ATTACK_DAMAGE_NUMBERS_LUA51_PASS、两项契约、严格UTF-8和限定git diff --check。

# 2026-08-04 — 英雄普通攻击最终伤害飘字实机问题与批准方案

- 用户实机确认：英雄攻击约1115；目标项目UI护甲约3333、Dota内置面板约1000；普通平A最终扣血约17但没有白字，暴击原生橙字2564而最终扣血及`OnTakeDamage`测试面板均为38。
- 调查确认权威训练目标配置仍来自`data/csv/商店系统/altar_actions.csv`，本轮不改变其护甲，也不改变其他单位各自独立护甲。高护甲下17/38最终伤害符合现有物理减伤数量级，代码问题限定为飘字语义与缺失。
- 生产英雄暴击当前使用`MODIFIER_PROPERTY_PREATTACK_CRITICALSTRIKE`，该引擎属性产生减甲前Valve橙字；项目普通攻击没有发送`OVERHEAD_ALERT_DAMAGE`，因此小额最终伤害没有稳定白字。
- 用户批准方案：同一attack record继续唯一掷骰，改用普通攻击伤害倍率保留原生护甲/攻击事件结算；最终`OnTakeDamage`按record暴击身份发送实际扣血，普通白字、暴击橙字。技能和脚本伤害隔离，本体、W分身和多目标按真实命中分别显示。
- 当前仅完成调查和方案批准，尚未完成代码与自动验证，更未进行Workshop Tools实机验收。
- 后续实施完成：`modifier_weapon_stat_projection.lua`用record级`MODIFIER_PROPERTY_DAMAGEOUTGOING_PERCENTAGE`替代英雄原生暴击属性；attack tracker改为只读取暴击身份并等待record销毁统一清理；齐天大圣W分身接入同一倍率、最终飘字和清理路径。
- 最终飘字严格读取`OnTakeDamage.params.damage`，要求攻击category、无inflictor且存在record；普通使用`OVERHEAD_ALERT_DAMAGE`，暴击使用`OVERHEAD_ALERT_CRITICAL`。显示按`record + victim entindex`去重，同一多目标record可对不同受击单位分别显示。
- `altar_actions.csv`训练目标护甲100000未修改；专项契约锁定源CSV、生成Lua和训练服务消费者一致。项目UI继续显示引擎实际运行时护甲投影，实机约3333 War3 UI/约1111 Dota运行时与CSV请求100000不是同一层概念。
- 新增专项Lua与PowerShell契约，覆盖230% record倍率、最终38橙字、最终16.6四舍五入17白字、同目标去重、多目标分别显示、技能排除、W分身契约和训练CSV链。
- 自动结果：专项Lua/契约、英雄多重攻击、猴王QWE/近战/塔、超级塔暴击、研究减甲和多重攻击回归均通过；目标Lua 5.1语法、严格UTF-8和限定`git diff --check`通过。尚未进行Workshop Tools实机验证，不能称为制作完成或用户验收。

## 2026-08-03 - 检查点：齐天大圣改为近战式无弹道结算

- 用户批准将齐天大圣从30000速度的远程攻击改为近战英雄式无飞行弹道即时结算，同时保留攻击前摇、1000攻击距离和1000索敌距离。
- 调查确认`hero_stat_adapter.lua`当前无论有无正弹道速度都强制`DOTA_UNIT_CAP_RANGED_ATTACK`，不存在可直接复用的近战回退；因此决定在权威`hero_attack_projectiles.csv`增加显式`attack_capability`字段，而不使用0速度或空值作为隐式开关。
- 齐天大圣将配置为`melee`，其他五英雄保持`ranged`；1000射程继续由现有隐藏永久射程Modifier落实，不另写伤害，保留原生普通攻击事件链。自动验证完成前不记录为已实施，Workshop Tools验证前不称为实机通过。

## 2026-08-03 - 齐天大圣无弹道即时结算实施与自动验证完成

- 权威`hero_attack_projectiles.csv`新增`attack_capability`列并定向生成对应Lua：齐天大圣为`melee`且无弹速/弹道模型，其他五英雄为`ranged`并保留原配置。
- `hero_stat_adapter.lua`对`melee`清空远程弹道名并设置`DOTA_UNIT_CAP_MELEE_ATTACK`；1000攻击距离仍由现有射程Modifier覆盖，1000索敌范围保持不变。未新增伤害逻辑，普通攻击、暴击、多目标与技能触发仍使用原生攻击链。
- 自动验证通过：`BUILDER_UTILITY_CONTRACT_PASS`、`WORKER_RANGED_MULTISHOT_CONTRACT_PASS`、`MONKEY_MELEE_ATTACK_LUA51_PASS`、`MONKEY_MELEE_TEST_LUAC51_PASS`、`MONKEY_MELEE_LUAC51_PASS`、`HERO_ATTACK_PROJECTILES_GENERATED_COMPARE_PASS`、`HERO_MULTISHOT_LUA51_PASS`、`HERO_CONFIGURED_HEALTH_LUA51_PASS`、`MONKEY_MELEE_STRICT_UTF8_PASS`及限定`MONKEY_MELEE_DIFF_CHECK_PASS`。
- 尚未完成引擎验证：必须完全停止并重新Run Workshop Tools、重新召唤齐天大圣，确认1000码攻击命令、攻击动画、无飞行弹道的命中时点及普通攻击事件链实际表现。未经用户确认不得记录为验收完成。

## 2026-08-03 - 齐天大圣弹道速度提高到30000

- 用户确认目标是视觉上基本瞬间命中；由于当前3000改为1000会更慢，最终明确选择30000。权威`hero_attack_projectiles.csv`及生成Lua同步改为30000，攻击/索敌距离继续保持1000。

## 2026-08-03 - 齐天大圣攻击范围调整为1000

- 用户要求将猴哥攻击范围改为1000后立即实机测试。权威`hero_definitions.csv`中的`attack_range`和`acquisition_range`同步改为1000，独立投射物CSV中的弹道速度3000保持不变。

## 2026-08-03 - 实机反馈：修正Undying与召唤英雄工具技能归属

- 用户实机确认旧方案不符合最终需求：Undying不应拥有回城和拾取，只保留D键1000码闪烁；当前D键实际不可用，需要修复。
- 召唤战斗英雄不拥有D闪烁，默认工具输入恢复为F2回城和F范围拾取。F2必须继续通过服务端当前玩家召唤英雄查询，不能作用于Undying或客户端指定的任意单位。
- 调查确认当前代码分别在`hero_ability_policy`给Undying授予D/F/T、在`hero_skill_system`给召唤英雄授予回城/拾取；D输入还依赖实机日志已证实不可用的`SetKeyPressedCallback`兜底。批准方案为Undying闪烁固定引擎D槽，召唤英雄按Ability名称保留F拾取，并恢复既有F2服务端旁路。
- 实施完成：`hero_ability_policy`只给Undying保留闪烁，清除旧实体残留的拾取/回城并固定到四建造技能后的槽位；召唤英雄原有回城/拾取授予链保持不变且无闪烁。
- D/F专用输入补齐裸命令及`+/-`命令，D按名称找到闪烁后使用`Abilities.ExecuteAbility`进入引擎点目标模式；F2恢复`ui_return_home_request`，服务端只通过`HERO_SUMMON_GET_REQUEST`定位当前玩家召唤英雄。技能栏显示分别固定为D、F、F2。
- 验证通过：`BUILDER_UTILITY_CONTRACT_PASS`、`GROUND_ITEM_PICKUP_LUA51_PASS`、`BUILDER_UTILITY_LUAC51_PASS`、`ALT_HERO_ABILITY_ORIGIN_DEV_CONTRACT_OK`、`FREE_HERO_REPLACEMENT_CONTRACT_PASS`；两个Panorama JS均强制编译为`1 compiled, 0 failed, 0 skipped`，限定`git diff --check`通过。
- `.cline/local-toolchain.json`的Lua路径仍失效，本轮实际使用MSYS2 Lua/Luac 5.1.5。`SESSION_LOG.md`当前3个历史`U+FFFD`与已知问题记录一致，本轮新增段为0；未改写历史乱码。

## 2026-08-03 - 英雄实际射程与Undying建造者D/F/T实现完成

- 用户批准齐天大圣攻击/索敌距离500、弹道3000，以及仅开局Undying建造者拥有D闪烁、F范围拾取、T回城；同时删除F2旁路并修复漂浮头冠与可攻击树。
- 权威数据：`hero_definitions.csv`和生成Lua把齐天大圣攻击/索敌改为500；弹道3000已由`hero_attack_projectiles.csv`及生成Lua提供，保持不变。
- 射程实现：新增隐藏永久`modifier_survival_hero_attack_range`，通过基础射程覆盖属性落实引擎实际射程；`hero_stat_adapter`仍同步远程能力、弹道、`survival_attack_range`和索敌范围。
- 建造者实现：`hero_ability_policy`按Undying身份授予D/F/T；初始化和重生均设`DOTA_UNIT_CAP_NO_ATTACK`。D校验1000距离、GridNav可通行/阻挡，使用`FindClearSpaceForUnit`、起终点Blink粒子和`ProjectileDodge`。
- F实现：虚拟升阶材料与真实`dota_item_drop`进入统一二维距离、entindex平局排序；普通物品保留自定义owner、Purchaser、OwnerEntity和PlayerOwner校验；挑战奖励继续由官方背包拾取事件进入既有Claim/逻辑库存/防复制链；满包停止且不处理后续实体。
- 输入实现：`combat_stats.js`和`hud_takeover.js`按Ability名称标记并绑定D/F/T；删除F2命令、图标和`ui_return_home_request`客户端旁路。两个JS强制编译均为`1 compiled, 0 failed, 0 skipped`。
- 外观实现：删除Undying Hallows头冠prop及粒子配置，保留原生主体/饰品；`hero_cosmetic_service`在非隐藏配置时明确移除旧`EF_NODRAW`，支持热重载和重生幂等恢复。
- 自动验证：`BUILDER_UTILITY_CONTRACT_PASS`、`GROUND_ITEM_PICKUP_LUA51_PASS`、`BUILDER_UTILITY_LUAC51_PASS`、`HERO_DEFINITIONS_GENERATED_COMPARE_PASS`、`BUILDER_UTILITY_STRICT_UTF8_PASS files=25`、`PANORAMA_DFT_IDENTITY_STATIC_PASS`及免费英雄、建造者Ability、英雄生命回归通过；限定`git diff --check`通过。
- 环境记录：配置中的`C:\Program Files\lua\bin`失效，本次实际使用MSYS2的Lua/Luac 5.1.5。全量生成被既有无关`item_definitions.csv`数字列错误阻断，目标英雄配置改用同一生成器函数定向生成并逐字节比较通过。
- 尚未实机验证：实际攻击距离、D/F/T最终按键、闪烁边界/视觉、真实物品拾取、满包、防复制、Undying外观和重生后NO_ATTACK。执行前已有未跟踪测试文件及`卡的文本.txt`均未修改。

## 2026-08-03 — 地裂冲击卡尔陨石滚动视觉获批实施

- 用户明确重新开启三选一公共技能`proto_earth_line`，要求增加卡尔混沌陨石落地后向前滚动的视觉；批准用该视觉替换当前Tiny岩石移动外观，不叠加双模型。
- 本机Valve content源码确认`invoker_chaos_meteor.vpcf`通过CP1初始化速度、`C_OP_BasicMovement`移动、CP3跟随主体并贴地；`invoker_chaos_meteor_fly.vpcf`是坠落段，不用于本任务。
- 实施边界：独立卡尔父粒子只负责表现，无视觉线性投射物继续唯一负责碰撞和伤害；CP0为触发起点，CP1为固定方向×500；终点和兜底立即销毁父粒子并保留既有无伤害爆炸。全部数值、穿透、去重、眩晕和LV5范围伤害不变。
- 当前生产服务顶层local为199，新增实现只能挂到既有`earth_rock`表。文档所列旧地裂专项测试文件当前不存在，本轮需补建真实可运行的视觉状态与契约测试。
- 实施中进一步核对Valve源发现完整`invoker_chaos_meteor.vpcf`主载体寿命固定为0.2秒，速度500时只覆盖约100码，单次直接创建无法覆盖地裂路径。方案调整为项目滚动父粒子：保留Valve模型、CP1速度、贴地、旋转及滚动火焰/拖尾/烟尘，CP2.x提供整段真实飞行时长，并排除land ring/soil/debris/fireball等落地瞬时冲击，避免每100码重播落地爆炸。
- 最终生产实现使用`particles/survival_earth_line/survival_earth_line_chaos_meteor.vpcf`；content源由当前Valve父资源最小化派生，移除屏幕震动、crumble、全部land冲击和坠落辉光，只保留陨石模型、fire/glow/ray/fire trail/smoke/burnt/light。Resource Compiler强制定向编译结果为`OK: 1 compiled, 0 failed, 0 skipped`，game产物存在。
- 线性投射物移除`EffectName`后继续唯一负责碰撞、穿透、去重和伤害；独立视觉状态保存CP0起点、CP1固定方向×500、CP2.x=`distance/speed`。正常终点、1.25秒兜底、服务重置和局部创建失败均幂等销毁释放；正常/兜底保留既有终点无伤害爆炸，重置不播放爆炸。
- 新建`scripts/vscripts/tests/test_earth_line_visual.lua`和`tools/test_earth_line_visual_contract.ps1`。结果：`EARTH_LINE_VISUAL_STATE_PASS`、`EARTH_LINE_VISUAL_CONTRACT_PASS`、当前Lua/Luac 5.4.5语法、严格UTF-8、主服务199个顶层local和限定`git diff --check`通过。状态测试包含两个并行实例及视觉API异常隔离。
- 相邻回音重斩、陨石坠落、元气弹状态测试及回音重斩、脉冲激射、魔法弹弓、陨石坠落、元气弹视觉契约通过。移动冰球契约因本轮前已有的旧基础弹体常量报`MOVING_ICE_BALL_OLD_PROJECTILE_REMAINS`；地裂差异没有触碰该区域，未为迁就无关旧断言修改生产代码。
- 当前环境只有Lua/Luac 5.4.5，文档中的历史Lua 5.1路径不存在，因此不宣称本轮Lua 5.1已执行。尚待完全重启Workshop Tools Run验收实际尺寸、贴地高度、方向、500速度同步、完整路径连续、终点残留和并行观感。

## 2026-08-03 — 资源树第二轮实机修复：DamageFilter缺少类别字段

- 用户确认第一轮移除树Modifier类别二次过滤后，伐木工仍只加木材、不扣树生命。
- 复查发现专项Mock一直主动传入`damage_category_const`，但实机DamageFilter不保证该字段存在；旧全局规则对`nil/0`失败关闭，导致测试与实机不一致。已撤销“DamageFilter始终提供类别字段”的错误经验。
- 新实现由树Modifier在`ON_ATTACK_START`登记“攻击者+树+record”短生命周期凭证；DamageFilter类别缺失/0且无inflictor时，只有一次性消费凭证才能放行。明确基础攻击仍放行并消费凭证，箭塔不能登记且始终拒绝，后续无凭证脚本伤害无法复用。
- 增加失败/record销毁清理及限20次`TREE_DAMAGE_FILTER`日志，输出allow、category、inflictor、evidence、damage和实体阻断状态。未添加`ApplyDamage`，未修改伐木工CSV/远程属性。
- Lua 5.1行为测试已覆盖实机等价的“无category+无inflictor+真实攻击凭证”正向路径、凭证一次性、无凭证脚本伤害拒绝、塔不能登记、明确类别消费和攻击失败清理。

## 2026-08-03 — 修复伐木工平A树只加木材但不扣生命

- 用户明确规则：所有非塔单位的真实平A都应扣树生命，只有箭塔及转职塔不能攻击树；技能、脚本和攻击附伤仍不得伤树。
- 用户实机确认伐木工攻击会出现木材绿字并增加木材，因此空远程弹道、攻击命令和`OnAttackLanded`均正常，问题发生在生命承伤过滤之后。
- 根因：`modifier_tree_progression`曾使用非权威的`params.damage_category`重复分类伤害。真实远程平A在该入口可能报告`0`/其他值，旧逻辑返回`-100%`，覆盖了全局DamageFilter已放行的基础攻击。
- 修复：树Modifier只保留稳定箭塔身份的`-100%`兜底，所有非塔伤害返回`0`并由拥有`damage_category_const`的全局DamageFilter权威分类。未修改CSV、伐木工远程/射程/攻速/弹道，也未新增`ApplyDamage`。
- 自动验证通过：`TREE_DAMAGE_RULES_LUA51_PASS`、`TREE_DAMAGE_RULES_CONTRACT_PASS`、`TREE_LUMBERJACK_ALL_LUAC51_PASS`和限定`git diff --check`。行为测试新增显式伐木工攻击者、Modifier类别`0`放行和DamageFilter基础平A正向断言；仍需Workshop Tools实机确认树实际扣血。

## 2026-08-03 — 固化Lua模块加载故障排查经验

- 用户要求把本次`building_upgrade_process.lua`漏提交导致的启动阻断写入当前项目经验。
- `PROJECT_CONTEXT.md`新增长期规则：将`module not found`分为真实文件缺失和目标模块Lua 5.1编译失败两类，并固定文件/Git历史/完整错误/Lua 5.1/静态require/行为测试/Workshop Tools冷启动的排查顺序。
- `KNOWN_ISSUES.md`补充防复发检查：新增静态`require`必须同时确认目标文件被Git纳入，并检查目标模块、直接调用方和`addon_game_mode.lua`；动态require需单独核对配置，不能依赖简单正则。
- 本次仅更新文档，不修改生产代码。

## 2026-08-03 — 紧急修复建筑升级流程模块缺失

- 用户实机报告`building_upgrade_system.lua:12`无法require `systems/building_upgrade_process`，阻断`addon_game_mode.lua`。
- Git取证确认提交`85ce4eb`新增升级流程依赖与`begin/is_active/cancel_by_entindex/reset`调用，但该文件从未被提交，无法从历史恢复。
- 新建完整流程模块，复用`core/scheduler`与`asset_preload_service`，提供单建筑去重、1秒完成、目标状态投影、可选粒子、异步视觉状态、销毁取消、reset清理和失效实体保护；既有`building_upgrade_system`无需改动。
- 验证通过：`BUILDING_UPGRADE_LOAD_CHAIN_LUAC51_PASS`、`BUILDING_UPGRADE_PROCESS_LUA51_PASS`、`SYSTEM_REQUIRE_RESOLUTION_PASS`、严格UTF-8与限定`git diff --check`。全systems扫描仅在仓库已有BOM文件`building_relocation.lua`上被本地luac5.1拒绝；Dota此前已加载同样带BOM的`building_system.lua`并进入后续模块，因此未扩大范围改写既有编码。
- 尚需用户完全停止并重新Run Workshop Tools，确认引擎实际进入地图和建筑升级/销毁时的1秒流程。


## 2026-08-03 — 修理工修理有效间距统一为200

- 用户确认修理工继续保持400的无攻击距离属性，并继续强制`NO_ATTACK`；LV1/LV2实际修理最大有效间距统一为200。
- 权威`training_definitions.csv`中LV2 `repair_range`由240改为200并定向生成。运行时已有模型边缘间距判定：边缘间距大于200时靠近，小于等于200时持续修理，因此无需新增另一套距离逻辑。
- 专项合同补充两级修理工400/200配置、`NO_ATTACK`和边缘距离判定断言。
## 2026-08-03 — 树位置、工人/英雄远程与转生多目标普攻实施前检查点

- 用户最终确认：`attack_rate=0.5`表示每秒0.5次；所有英雄含齐天大圣和剑圣统一远程；一至四转总目标数含主目标为3/4/5/6；各目标使用相同普通攻击基础过程并由引擎按各自护甲独立结算；次级攻击不应重复触发项目技能。
- 工人边界：伐木工400射程、远程能力、无可见弹道；修理工保持纯修理和`NO_ATTACK`，只统一400距离属性。伐木工LV3模型无动作，替换为`creep_bad_flagbearer.vmdl`；LV6-LV8使用用户指定模型。
- 已确认现有基础：`modifier_weapon_attack_tracker`已有次级record集合和项目事件隔离；`hero_progression_system`已有`split_multishot_unlocked/multishot_count`但未消费；奖励CSV当前一转解锁值1且二至十转持续+1，必须调整为一转总数3并在运行时封顶6。
- 工作区保护：实施前只有用户已有未跟踪`tools/test_unit_model_config.lua`、`tools/test_unit_model_config_contract.ps1`和`卡的文本.txt`，不得覆盖或删除。
- 下一步：修改权威CSV、最小运行时与KV回退，定向生成后补专项测试并执行Lua 5.1、编码、模型VPK、生成一致性和限定diff验证。

## 2026-08-03 — 树位置、工人/英雄远程与转生多目标普攻实现完成

- 权威CSV完成：树位置`448/64/128`；八级伐木工0.5次/秒与400射程；修理工400距离但不攻击；LV3、LV6-LV8模型；六英雄远程弹道配置；转生总目标3/4/5/6并从五转起不再增加。四份生成Lua均由生成器定向重建并逐字节比较通过。
- 运行时完成：树坐标读取世界视觉生成表；伐木工远程、空弹道名和高速瞬发；修理工继续`NO_ATTACK`；所有英雄统一远程；`hero_progression_system`消费已有转生状态执行次级`PerformAttack`，现有tracker按record隔离项目事件链，并覆盖主目标被击杀后继续发射。
- 最终复读发现科技刷新原本仍从旧`workers_config.attack_rate=1.0`重算伐木工攻速；已改为在工人状态保存训练行基础0.5并从该值叠加科技，缺失配置回退同步为0.5，专项合同新增对应防回归断言。
- VPK v2正确按扩展名/目录/文件名三层解析，确认LV3、LV6、LV7、LV8四个新增模型存在，输出`WORKER_MODEL_VPK_PASS 4 INDEXED 383571`。首次把目录树误当连续完整路径字符串导致假缺失，已排除检查器错误，未据此修改模型。
- 验证通过：专项PowerShell合同、Lua 5.1多目标行为、目标生产/生成Lua及`addon_game_mode.lua`语法、生成一致性、严格UTF-8/历史GB18030解码、树伤害、免费英雄次级攻击、魔法弹弓目标选择、研究减甲以及限定`git diff --check`。
- 用户已有未跟踪`test_unit_model_config_contract.ps1`仍断言LV3旧坏模型，按预期失败；未修改。实施期间误删的三个已跟踪Python缓存已立即从HEAD逐字节恢复，最终状态无缓存差异。
- 尚未实机验证：树实际位置与占地、四个新模型动画、伐木工400射程与无可见弹道、六英雄远程攻击表现、一至四转目标数量及不同护甲独立扣血。自动测试不得描述为Workshop Tools实机通过。

# 2026-08-02 — 检查点：四名免费英雄方案批准并开始实施

- 用户要求用末日使者、影魔、斧王、黑暗游侠替换原有全部非VIP英雄，并要求所有基础配置从CSV获取；齐天大圣、剑圣VIP英雄不变。
- 用户批准普通模板数值、四技能1级、Q槽开局置灰一转原位激活、末日10%召唤、影压先加层再伤害且每层独立3秒、斧王目标中心范围伤害、小游侠主目标加最近4目标。
- 用户修正召唤策略：不得新召替换旧召唤；召唤物存续期间后续攻击直接跳过概率判定，直到召唤物死亡、持续时间结束或实体失效才解除活动锁。
- 调查证据：`hero_definitions.csv`当前普通英雄为斧王/斯拉克/主宰；`hero_initial_skills.csv`为空；现有`hero_skill_system`开局不创建专属技能，一转后才AddAbility，因此必须新增正式locked状态而不能只改UI颜色。
- 工作区保护：实施前仅`data/csv/英雄系统/hero_skill_definitions.csv`为已跟踪修改，内容是用户已有公共技能完整等级描述；另有大量未跟踪测试文件。本任务必须保留这些内容且不清理无关文件。
- 下一步：修改权威CSV和祭坛召唤入口，定向生成配置，再实现锁定状态与四个运行技能。

## 2026-08-02 — 四名免费英雄实现完成，等待实机验证

- 权威数据：`hero_definitions.csv`改为末日/影魔/斧王/黑暗游侠免费，齐天大圣/剑圣VIP；普通模板、500/1200射程、专属关系、技能说明、弹道和Tooltip均从CSV生成或读取。
- 技能栏：四免费专属开局项目等级0并置灰，占固定Q槽；一转授予将原条目升级为等级1并激活。修正`owned_passives()`，确保locked等级0不会被旧`math.max(1, level)`逻辑误判为已拥有。VIP不预创建。
- 运行逻辑：独立`hero_exclusive_passive_service.lua`避免主被动服务超过Lua 5.1每函数200个局部变量限制；通过注入原`deal_group`继续使用既有纯粹伤害事务。影压先入层再按27.5/30/32.5/35/37.5结算，每层独立3秒；斧王目标中心400范围×30。
- 召唤：地狱火继承项目战斗快照平均攻击、最大生命与运行时护甲；小游侠继承150%平均攻击并挂项目无敌Modifier。两者在概率前检查活动锁，死亡/到期/失效解除。小游侠攻击record标记次级攻击，次级`PerformAttack`关闭Proc并不发英雄攻击事件。
- 资源：替换祭坛实际`buildings_config.lua`按钮列表和所有召唤脚本注册；加入两个专用单位KV、四个1级Ability壳、模型/粒子预缓存与六份中英文本地化镜像；删除旧斯拉克/主宰召唤脚本和三个旧普通专属KV壳。
- 自动验证：新PowerShell合同、Lua 5.1层数/倍率行为、所有变更Lua语法、CSV生成一致性、KV名称唯一性、任务业务文件严格UTF-8、本地化结构、限定diff检查均通过。英雄生命、英雄原生Ability保留、addskill、Ice Cone、Meteor、Magic Slingshot、Poison Cloud、Tornado合同/行为通过；Flame Burst、Moving Ice Ball等行为测试也通过。
- 未通过但非本轮生产回归：用户已有未跟踪Blade Pulse合同仍要求已批准删除的旧斧王专属壳；用户已有未跟踪Flame Burst合同要求HEAD原本未包含的Dragon Slave预缓存。保留失败事实，未修改无关生产文件。
- 尚未完成：Workshop Tools实机验证与用户验收。

## 2026-08-02 - 完成检查点：陨石落地改为术士地狱火纯爆炸

- 用户实机发现卡尔`invoker_chaos_meteor.vpcf`落地主粒子爆炸后持续残留，并批准新边界：卡尔陨石只播放0.8秒坠落；权威落地时卡尔粒子消失，同点衔接术士地狱火爆炸；不召唤地狱火。用户明确选择保留全部现有Lua落地伤害、熔岩伤害和减速。
- 本机Dota Content确认`warlock_rain_of_chaos.vpcf`完整父粒子包含最长11秒烧焦地面，不适合与现有熔岩叠加；最终使用`particles/units/heroes/hero_warlock/warlock_rain_of_chaos_explosion.vpcf`纯爆炸，只含碎石、火焰、烟、闪光与扩张效果，不包含单位模型或召唤逻辑。卡尔`invoker_chaos_meteor.vpcf`生产依赖和预缓存已移除。
- 术士爆炸不绑定施法锁：每次爆炸分配独立ID并注册3.1秒Scheduler任务，正常到期后EndCap销毁并释放索引；LV1落地解锁不会提前清除。LV5两颗独立注册；`clear_meteors()`取消任务并立即销毁全部爆炸；注册项先移除，保证自然到期、清局和迟到回调共用幂等入口。
- 战斗边界未改：12%触发、0.8秒落地、500范围、全属性×3纯粹伤害、LV2三次熔岩伤害、LV3 30%减速、LV5第二颗晚0.5秒且爆炸/熔岩80%、Viper熔岩及触发锁均保持。粒子失败仍不阻断权威伤害与状态机，生产代码没有任何术士单位创建。
- 定向结果：`METEOR_VISUAL_STATE_PASS`、`METEOR_VISUAL_CONTRACT_PASS`、目标Lua 5.4语法通过；爆炎弹、怒雷、元气弹视觉状态/契约及剑刃震荡视觉契约通过。移动冰球视觉状态仍因本任务前已有的重复粒子常量覆盖Puck Orb而失败，本轮未修改该无关区域。
- 尚未验证：Workshop Tools冷启动中的卡尔坠落到术士爆炸实际衔接、爆炸颜色/尺寸、约3.1秒后完全无残留、无地狱火单位、Viper熔岩继续存在及LV5两颗独立表现。

## 2026-08-02 - 完成检查点：元气弹 Sven Storm Hammer 视觉

- 用户批准为三选一公共技能`proto_holy_pulse`/“元气弹·被动”使用Sven Storm Hammer视觉：飞行弹体保留其原生普通命中EndCap爆裂，LV5每颗命中独立20%成功时再播放一次额外Storm Hammer爆炸。
- 本机Dota Content资源确认：完整追踪弹体为`particles/units/heroes/hero_sven/sven_spell_storm_bolt.vpcf`；独立爆炸为`particles/units/heroes/hero_sven/sven_storm_bolt_projectile_explosion.vpcf`。后者及其子粒子使用CP3作为冲击中心，生产逻辑同步设置CP0与CP3。
- `hero_passive_skill_service.lua`只替换元气弹两个视觉常量；`CreateTrackingProjectile`的目标、速度1000、不可躲避、无视野和独立ExtraData状态保持不变。`addon_game_mode.lua`显式预缓存完整弹体与独立爆炸。
- LV5战斗规则未改：`explosion_chance={0,0,0,0,0.20}`、`explosion_radius={0,0,0,0,250}`、`explosion_damage_pct={0,0,0,0,60}`；伤害继续通过`enemies_touching_radius`按250码及敌人Hull边缘判定，包含原命中目标。
- 新增`test_spirit_bomb_visual.lua`和`test_spirit_bomb_visual_contract.ps1`，覆盖多目标Storm Hammer追踪弹体、CP0/CP3、250码内外边界、原目标重复伤害、60%倍率及粒子API失败不阻断伤害/不跳过索引释放。结果：`SPIRIT_BOMB_VISUAL_STATE_PASS`、`SPIRIT_BOMB_VISUAL_CONTRACT_PASS`。
- 相邻回归通过：爆炎弹、怒雷、移动冰球视觉状态，以及爆炎弹、魔法弹弓、怒雷、剑刃震荡视觉契约。当前Lua/Luac 5.4.5语法、四个任务文件严格UTF-8/无BOM/无尾随空白及限定`git diff --check`通过。
- 两个未跟踪旧契约未计为本任务失败：移动冰球契约全文件禁止共享服务其他路径仍使用的CP0字符串；毒云视觉契约仍要求已废弃的“新云释放旧云”，与当前“活动期间拒绝重触发”规则冲突。本轮未为迁就旧断言修改无关生产逻辑。
- 尚未验证：Workshop Tools冷启动中的多目标弹体尺寸/朝向/轨迹、普通EndCap爆裂、LV5额外爆炸位置与连续触发无残留。

## 2026-08-02 — 回音重斩自动实现完成检查点

- 用户新增五级公共技能“回音重斩”并批准最终口径：LV1攻击命中12%概率发射1道总宽200的弧形斩，路径所有单位受到触发时全属性×1伤害；LV2概率15%、2波、间隔0.1秒；LV3为3波；LV4继承LV3；LV5为4波，每波独立随机提高5%～20%伤害。
- 身份与配置：新增`proto_echo_slash`、`ability_survival_echo_slash`和公共池成员`public_13`；英雄技能、公共池、Tooltip三份权威CSV已更新，并通过标准生成器定向生成三份Lua。生成英雄技能和公共池Lua与CSV临时重建结果逐字节一致，Tooltip生成仅新增目标行。
- 方向与快照：每次触发固定英雄位置、被攻击目标当时位置方向、项目攻击射程回退结果和逻辑全属性快照；目标或英雄后续移动不改变已确认路径。每道波按射程动态计算速度，固定1秒走完全程。
- 真实碰撞：复用马格纳斯震荡波视觉与`CreateLinearProjectile`；200为总宽、碰撞半径100，`bDeleteOnHit=false`，每波唯一ID、独立命中去重、单位回调返回false。同一敌人可被不同波各命中一次。
- 时序与随机：首波立即发射，后续波由单条绝对时间校正任务在t=0.1/0.2/0.3发射；不设置技能活动锁，允许不同攻击触发并行。LV5每道波创建时独立抽取5%～20%，倍率快照后供该波全部命中使用。
- Lua 5.1约束：初版新增多个模块级local导致大型服务超过Lua 5.1主函数200局部变量限制；已将状态、常量和函数收拢为单一`echo_slash`表，恢复Lua 5.1编译且不改变行为。
- 自动验证：`ECHO_SLASH_STATE_LUA51_PASS`、`ECHO_SLASH_CONTRACT_PASS`、`ECHO_SLASH_LUAC51_PASS`、配置validate、生成比较、12个目标文件严格UTF-8、限定`git diff --check`通过；`BLADE_PULSE_STATE_LUA51_PASS`、`EARTH_LINE_STATE_LUA51_PASS`及魔法弹弓完整契约通过。
- 已知测试差异：`test_blade_pulse_contract.ps1`仍断言历史Vengeful预缓存，但生产与项目稳定文档早已使用Magnataur粒子，因此PowerShell旧契约失败；其生产Lua和状态测试通过，本任务未顺带修改该既有未跟踪测试。
- 工作区保护：实施前已有大量未跟踪测试文件，均未删除、覆盖或整理；只删除本轮Python导入产生的`tools/__pycache__/build_configs.cpython-314.pyc`。
- 尚未验证：Workshop Tools中的图标与五级Tooltip、马格纳斯震荡波是否呈现理想弧形斩、200总宽实际碰撞、1/2/3/3/4波观感、真实扣血和LV5随机增伤。自动测试不等于引擎验证或用户验收。

## 2026-08-02 - 检查点：召唤英雄CSV生命与blood作弊码实施前确认

- 用户要求修复召唤战斗英雄的实际生命没有采用`hero_definitions`配置的问题，并新增聊天作弊码`blood`。
- 权威数据确认：`data/csv/英雄系统/hero_definitions.csv`与生成Lua一致；普通英雄`base_health=3000`，齐天大圣/剑圣`base_health=10000`且`max_health_multiplier=1.1`，全局CSV倍率当前为1。用户批准最终初始最大生命分别为3000和11000。
- 根因链确认：`hero_stat_adapter`写入生命后调用`CalculateStatBonus(true)`；随后`HERO_SUMMONED`订阅者`hero_combat_stat_service.apply_base_projection()`还会调用两次`CalculateStatBonus(true)`。原生英雄模板可能在这些阶段覆盖先前写入，因此最终必须在所有召唤期属性计算后重写同一个CSV权威生命值。
- `blood`规则确认：`+/-数值`按固定生命变化，`+/-百分比%`按执行时当前最大生命计算；加血不超过最大生命，减血最低保留1点，不允许命令直接杀死英雄；只作用于当前玩家召唤的战斗英雄。
- 实施边界：不改CSV数值，不改生成Lua，不定时覆盖生命，不破坏装备`MODIFIER_PROPERTY_HEALTH_BONUS`；合法加血调用`hero_health_guard.allow_healing()`。
- 下一步：修改生命适配器、召唤期战斗投影和作弊命令，新增Lua 5.1行为/PowerShell契约测试并执行限定验证。

## 2026-08-02 - 召唤英雄CSV生命与blood作弊码自动实现完成

- `hero_stat_adapter`新增权威生命计算与应用API，不再从原生`GetMaxHealth()`临时值乘算；最终生命为`floor(base_health × max_health_multiplier × hero_meta_max_health_multiplier)`，并保存`survival_base_max_health`诊断值。
- 生命写入移动到适配器内部`CalculateStatBonus`和等级应用之后；`hero_combat_stat_service`在召唤期两次基础投影计算后再次应用同一权威生命，输出`[HERO_CONFIGURED_HEALTH]`诊断。
- 首次创建装备生命Modifier使用`hero_health_guard.preserve_missing()`并重算属性，使召唤时已损失生命为0的英雄在装备生命加成后仍保持满血；后续装备刷新继续沿用既有相同语义。
- 新增`debug/health_cheat.lua`并接入聊天命令`blood`：只查找当前玩家召唤英雄；固定值和按当前最大生命百分比增减均支持；加血封顶、减血最低1点；合法加血先调用`allow_healing()`。
- 新增`tools/test_hero_configured_health.lua`、`tools/test_health_cheat.lua`和`tools/test_hero_health_contract.ps1`。验证通过：`HERO_CONFIGURED_HEALTH_LUA51_PASS`、`HEALTH_CHEAT_LUA51_PASS`、`HERO_HEALTH_CONTRACT_PASS`。
- 6个本任务生产/测试Lua通过`luac5.1 -p`；12个相关文件通过严格UTF-8；CSV/生成Lua生命字段契约和限定`git diff --check`通过。`ADDSKILL_CONTRACT_PASS`、元气弹及毒云专项契约/Lua 5.1回归通过。
- 未修改`hero_definitions.csv`或生成配置，因为权威源与生成Lua原本已经一致；未触碰用户既有技能配置、Ability KV和大量生成文件修改。
- 尚未验证：Workshop Tools中的普通英雄3000、VIP英雄11000、带初始装备生命时总生命/满血状态，以及`blood +100/-100/+10%/-10%`实际聊天输入。

## 2026-08-02 - 元气弹与毒云触发锁实施检查点

- 用户批准将已完整接入的 `proto_holy_pulse`/“圣光震荡·被动”原身份重做为“元气弹·被动”，保留 `ability_survival_holy_pulse` 和公共池成员 `public_10`。
- 最终规则：LV1攻击命中12%概率向普攻范围内最近最多5个目标发射追踪投射物，每颗真实命中造成触发时逻辑全属性×4纯粹伤害；LV2每颗命中恢复英雄5%最大生命；LV3基础7目标且每次触发10%概率提高到9；LV4继承LV3；LV5每颗命中独立20%概率对目标250范围追加基础伤害60%，原目标重复承受爆炸伤害。
- 用户新增毒云规则：同一英雄活动毒云未结束时禁止再次触发，结束后才恢复判定；不得继续使用新触发替换旧毒云。
- 工作区最新提交为 `08317a6 技能提交`，本轮相关已跟踪文件在修改前干净；未跟踪的本地规则和既有测试文件不清理、不覆盖。
- 实施方案：复用魔法弹弓的攻击射程回退、最近目标查询和共享 Ability 追踪投射物回调，但为元气弹建立独立状态、ID、命中清理与测试；伤害继续进入既有纯粹伤害事务，合法治疗调用 `hero_health_guard.allow_healing` 后使用 `Heal`。
- 尚未验证：配置生成、专项Lua 5.1行为测试、PowerShell契约、公共技能回归、Lua语法、严格UTF-8、限定diff检查及Workshop Tools实机表现。

## 2026-08-02 - 元气弹与毒云活动锁自动实现完成

- 完成权威CSV、生成技能配置、生成Tooltip、五级运行定义、Ability KV和动态Tooltip白名单；保留`proto_holy_pulse`、`ability_survival_holy_pulse`与`public_10`身份。
- 元气弹复用现有射程回退与最近目标排序，使用独立投射物ID和状态；真实命中后依次结算全属性×4纯粹伤害、5%最大生命治疗和LV5独立爆炸判定，状态在命中或10秒兜底时清理。
- 合法治疗先调用`hero_health_guard.allow_healing`再使用Ability句柄执行`Heal`；LV5爆炸使用Hull边缘精确范围查询并包含原目标。
- 毒云在通用概率判定前检查同英雄活动状态，创建函数同时提供第二层拒绝保护；原“新云替换旧云”行为测试已改为“活动拒绝、到期后允许”。
- 验证：`SPIRIT_BOMB_STATE_LUA51_PASS`、`SPIRIT_BOMB_CONTRACT_PASS`、`POISON_CLOUD_STATE_LUA51_PASS`、`POISON_CLOUD_CONTRACT_PASS`，以及奥术弹幕、魔法弹弓、爆炎弹、移动冰球、寒冰锥、脉冲激射、龙卷风回归全部通过；8文件Lua 5.1语法、12文件严格UTF-8、CSV/生成字段一致性和限定diff检查通过。
- 奥术弹幕旧契约曾因扫描整个共享服务而把已提交龙卷追踪的必要平方根误报为奥术AOE回归，已将断言收窄到禁止“平方根距离+hit_radius”的旧奥术模式，未修改生产逻辑。
- 完整配置生成在无关`item_definitions.csv`历史列错位（数字列读到`equipment_iron_armor_01`）处失败；使用相同`tools.build_configs.build()`定向重建英雄技能，并用Tooltip专用生成器重建Tooltip。实际生成内容差异只有两份目标文件。
- 尚未完成：Workshop Tools实机验证与用户验收。

## 2026-08-02 - 完成检查点：爆炎弹Lv5 Mortimer Kisses视觉

- 最终生产状态：`FLAME_SMALL_FIREBALL_PARTICLE`使用`hero_snapfire_ultimate.vpcf`，`FLAME_SMALL_FIREBALL_IMPACT_PARTICLE`使用`hero_snapfire_ultimate_impact.vpcf`；服务和预缓存资源计数均为弹体1、冲击1、Dragon Slave 0。
- 控制点与时序：三颗弹体分别以CP0主爆炸中心和CP1=`(随机落点-中心)/0.5`初始化；原有单个0.5秒Scheduler回调同步清理三颗弹体，以CP3生成三次落地冲击，再沿原路径逐颗执行250范围×3伤害和点燃。
- 表现故障隔离：弹体创建、控制点、销毁、索引释放和落地冲击均不会把粒子API异常传播到战斗结算；销毁失败仍独立尝试释放索引。Lua状态测试覆盖弹体、冲击和清理三类模拟失败。
- 定向结果：`FLAME_BURST_VISUAL_STATE_PASS`、`FLAME_BURST_VISUAL_CONTRACT_PASS`、`MOVING_ICE_BALL_VISUAL_STATE_PASS`、`MOVING_ICE_BALL_VISUAL_CONTRACT_PASS`、`MAGIC_SLINGSHOT_VISUAL_CONTRACT_PASS`、`FURY_THUNDER_VISUAL_CONTRACT_PASS`、`BLADE_PULSE_VISUAL_CONTRACT_PASS`及`POISON_CLOUD_VISUAL_CONTRACT_PASS`。
- 静态结果：目标生产Lua与新测试通过当前Lua/Luac 5.4.5语法；8个目标文件严格UTF-8通过；限定`git diff --check`通过，仅有Git的LF/CRLF工作区提示。
- 全量Lua结果：当前63项中54项通过、9项失败。失败位于未修改区域：`test_addhero_cheat`缺Vector Mock、旧原生智力快照预期、旧三级Tooltip预期、英雄召唤Mock、攻速Buff调度、Modifier注册数量、饰品肖像环境、树调度和血条Mock；其中智力快照失败已有多轮历史日志证据。本任务未修改这些模块，不顺带修复。
- 尚未验证：Workshop Tools实机中的Mortimer Kisses弹体实际弧线/朝向/速度、三颗同步落地、CP3冲击与随机点一致、重叠视觉及连续触发无残留。
- 下一步唯一动作：完全停止并重新Run Workshop Tools，使用爆炎弹Lv5进行冷启动实机视觉验收。

## 2026-08-02 - 实施检查点：爆炎弹Lv5 Mortimer Kisses视觉

- 用户新任务并批准实施：将`proto_flame_burst` Lv5三颗随机溅射的视觉从莉娜龙破斩替换为Snapfire Mortimer Kisses；现有概率、伤害、点燃、随机落点和同步落地规则不得改变。
- 本机Dota Content资源确认：完整飞行弹体为`particles/units/heroes/hero_snapfire/hero_snapfire_ultimate.vpcf`，瞬时落地冲击为`hero_snapfire_ultimate_impact.vpcf`；前者使用CP0起点与CP1初速度，后者使用CP3落点。
- 已排除`hero_snapfire_ultimate_linger.vpcf`，因其固定持续约3.1秒会暗示持续伤害；已排除`hero_snapfire_ultimate_calldown.vpcf`，因其预警半径约428与小球250伤害范围不符。
- 生产实现：弹体CP0写入主爆炸中心，CP1按`(landing_position-center)/flight_time`计算；0.5秒原有单Scheduler回调继续同步销毁三颗弹体、创建三次CP3冲击并执行权威伤害/点燃。主爆炸光击阵未改。
- 预缓存已由Dragon Slave替换为Mortimer Kisses完整弹体与落地冲击；移动冰球契约已移除对爆炎弹旧Dragon Slave资源的跨技能耦合。
- 新增`test_flame_burst_visual.lua`和`test_flame_burst_visual_contract.ps1`。当前结果：`FLAME_BURST_VISUAL_STATE_PASS`、`FLAME_BURST_VISUAL_CONTRACT_PASS`、`MOVING_ICE_BALL_VISUAL_STATE_PASS`、`MOVING_ICE_BALL_VISUAL_CONTRACT_PASS`，目标Lua 5.4.5语法通过。
- 会话中出现`Upstream HTTP/2 stream failed`，这是工具上游传输中断；已先检查磁盘和Git状态，确认上一补丁成功后继续，没有重复写入。
- 尚未验证：其余相邻视觉回归、严格UTF-8、最终限定差异以及Workshop Tools中的弹体实际弧线、朝向、速度、同步落地和残留情况。
- 下一步：执行相邻契约与更广Lua回归，完成静态验证后交付实机验收。

## 2026-08-02 — 完成检查点：剑刃震荡马格纳斯震荡波视觉

- 生产实现：`hero_passive_skill_service.lua`的`BLADE_PULSE_PARTICLE`已从复仇之魂恐怖波浪替换为`particles/units/heroes/hero_magnataur/magnataur_shockwave.vpcf`；`addon_game_mode.lua`同步替换显式预缓存。
- 战斗边界保持：`CreateLinearProjectile`、动态攻击射程、1秒全程、宽度200、`bDeleteOnHit=false`、逐投射物命中去重、回调`return false`和LV5三道独立状态均未修改；未添加cast/hit粒子。
- 新增`tools/test_blade_pulse_visual_contract.ps1`，锁定目标资源、旧资源移除、预缓存、线性投射物字段和穿透回调。结果`BLADE_PULSE_VISUAL_CONTRACT_PASS`。
- 相邻视觉回归通过：`MOVING_ICE_BALL_VISUAL_CONTRACT_PASS`、`MAGIC_SLINGSHOT_VISUAL_CONTRACT_PASS`、`FURY_THUNDER_VISUAL_CONTRACT_PASS`。
- 静态验证：目标生产Lua通过当前可用Luac 5.4.5语法检查；六个任务文件严格UTF-8、目标tracked diff check和新增测试尾随空白检查通过；目标粒子在服务/预缓存各出现一次，旧粒子均为零。
- 环境限制：历史记录的`C:\msys64\mingw64\bin\luac5.1.exe`及MSYS2候选目录当前不存在，因此未宣称Lua 5.1语法通过；已修正`KNOWN_ISSUES.md`与`PROJECT_CONTEXT.md`的当前工具说明。
- 已知无关失败：`test_hero_passive_attribute_snapshot.lua`仍要求旧原生`GetIntellect(true)`契约，与项目逻辑三维决策冲突；该失败已在历史全量测试中记录，本次仅替换粒子字符串，未修改其生产链或测试。
- 尚未验证：Workshop Tools冷启动中的震荡波实际朝向、视觉速度/宽度、穿透多目标后是否持续及LV5三道重合效果。

## 2026-08-02 — 检查点：剑刃震荡马格纳斯震荡波视觉实施

- 用户新任务：为三选一公共技能`proto_blade_nova`/“剑刃震荡·被动”增加马格纳斯震荡波特效，并已明确批准实施。
- 已确认现状：技能使用`CreateLinearProjectile`沿英雄面向移动，现有`EffectName`为复仇之魂恐怖波浪；伤害、碰撞、射程和LV5三脉冲逻辑已完成，本任务不得改变。
- 资源证据：目标主体粒子为`particles/units/heroes/hero_magnataur/magnataur_shockwave.vpcf`；另有cast/hit配套粒子，但用户未要求额外前摇或逐目标命中视觉，本次不叠加。
- 实施边界：仅替换`BLADE_PULSE_PARTICLE`、同步`M.precache`并新增定向视觉契约；继续由原生线性投射物承担权威碰撞，保留`bDeleteOnHit=false`和回调`return false`。
- 工作区保护：`hero_passive_skill_service.lua`和`addon_game_mode.lua`在本任务前已有用户未提交修改，只做最小增量，不回滚其他被动与游戏模式变更。
- 尚未验证：契约测试、Lua 5.1语法、严格UTF-8、限定差异及Workshop Tools实机视觉。
- 下一步：完成最小代码修改并执行全部限定自动验证。

## 2026-08-02 - 检查点：虚空震爆重做龙卷风需求确认与实现调查

- 用户要求将现有 `proto_void_pulse` / “虚空震爆·被动”重做为龙卷风，并已明确批准编码。
- 身份边界：保留 `ability_survival_void_pulse`、公共池成员 `public_12` 和原显示名；当前CSV、运行配置与Ability KV仍为旧三级虚空震爆，需要统一升至五级。
- 最终规则：15%触发；主龙卷从攻击者位置朝目标触发位置固定方向移动，速度500、持续3秒；t=0/1/2实时读取逻辑全属性，对中心300范围造成×2纯粹伤害，同一目标每个周期最多一次。
- 控制规则：影响范围600；LV3起范围内持续减速20%，主龙卷曾命中目标在仍处于范围时额外减速15%，总计35%，离开立即移除；LV2无新增效果，LV4继承LV3。
- LV5规则：主龙卷结束时，仅统计仍存活的已命中不同目标；每个目标在结束位置产生一个无上限小龙卷，随机选择上述目标方向，持续2秒、速度500、t=0/1实时属性×1.2伤害，只保留20%范围减速，不施加额外15%且不继续分裂。
- 调查证据：配置权威源为 `data/csv/英雄系统/hero_skill_definitions.csv`；运行定义为 `config/hero_passive_skill_definitions.lua`；执行服务为 `systems/hero_passive_skill_service.lua`；Tooltip动态等级字段由 `ui/ability_runtime_service.lua` 白名单发布；减速复用 `buff_manager` 的显式apply/remove受管Buff模式。
- 工作区存在大量既有未提交修改，本任务相关文件也已修改；实现必须基于当前内容追加，不覆盖或回滚。
- 尚未验证：生产实现、生成配置、Lua测试、契约测试、语法、UTF-8、限定diff检查以及Workshop Tools实机表现。
- 下一步：实现CSV、运行配置、双减速Buff、共享龙卷状态机、Ability KV、Tooltip发布和测试。

## 2026-08-02 - 检查点：龙卷风实现与自动验证完成

- 完成 `proto_void_pulse` 的CSV重做、生成配置、五级运行定义、Ability KV最高等级、Tooltip能力白名单和 Invoker Tornado 预缓存。
- `hero_passive_skill_service.lua` 新增独立主/小龙卷状态：主龙卷从攻击者向目标方向以500速度移动3秒，t=0/1/2伤害；小龙卷从结束位置按仍存活命中目标数量生成，持续2秒，伤害倍率为60%，不继续分裂。
- 命中使用单位中心二维距离300；影响范围600；主/小龙卷各自独立命中集合；主龙卷结束只统计仍存活的不同目标。
- 每个伤害周期通过 `HERO_COMBAT_STATS_GET_REQUEST` 刷新逻辑属性快照，伤害仍进入既有纯粹伤害事务；范围减速按所有活动龙卷聚合，离开全部覆盖范围立即移除。
- 新增 `tools/test_tornado_contract.ps1` 与 `tools/test_tornado_state.lua`。
- 自动验证通过：`TORNADO_STATE_LUA51_PASS`、`TORNADO_CONTRACT_PASS`；火焰、毒云、移动冰球、魔法弹弓、寒冰锥、脉冲激射相关回归全部通过；相关Lua 5.1语法、严格UTF-8、CSV/生成Lua一致性和限定`git diff --check`通过。
- 已修正一次减速清理元字段过滤问题，并重新执行最终测试；未触碰用户其他既有修改。
- 尚未验证：Workshop Tools中的实际视觉、真实移动与粒子、范围减速即时移除、动态属性变化和LV5随机分裂方向。
- 下一步唯一动作：用户进行Workshop Tools实机验证并反馈结果。

## 2026-08-02 - 检查点：龙卷风实机移动与追踪修正

- 用户实机反馈：龙卷风没有移动；预期是不论等级都移动到被攻击单位位置，并具有追踪功能。
- 根因1：生产状态按触发瞬间固定方向和绝对时间计算位置，没有保存并逐帧追踪原攻击目标。
- 根因2：Invoker Tornado粒子CP1写入单位方向向量而非`方向×500`速度向量，视觉移动速度接近零；追踪转向也没有更新CP1。
- 用户确认目标死亡边界：继续移动到目标最后存活位置，到达后停住直到3秒结束。
- 小龙卷边界不变：仍按LV5随机目标方向直线移动，不改成追踪。
- 下一步：主龙卷保存目标与最后位置，逐帧重新计算方向并限制步长不越过目标；同步粒子CP0中心和CP1速度；更新Tooltip和专项测试。

## 2026-08-02 - 检查点：龙卷风追踪移动修正完成

- 主龙卷状态现在保存原攻击目标与最后目标位置；每个共享调度帧读取存活目标当前位置，以`min(目标距离, 500×dt)`推进，不越过目标。
- 到达目标当前位置后权威中心停止，粒子CP1速度归零；若存活目标随后移动，下一帧重新计算方向并恢复追踪。
- 目标死亡后不再刷新最后位置，龙卷继续前往已保存的最后存活位置，到达后停住；总生命周期仍固定3秒，伤害仍严格为t=0/1/2。
- Invoker Tornado粒子CP1由单位方向向量修正为真实速度向量`direction×move_speed`，并在追踪转向、停止时逐帧同步；CP0继续同步权威中心。
- 小龙卷保持既有随机方向直线移动，不改成追踪；其生命周期与t=0/1伤害规则不变。
- Tooltip等级1和权威技能CSV描述已更新为追踪目标，相关生成Lua和Tooltip已重建。
- 自动验证：追踪步进覆盖500速度、到达不越界、停止及目标再次移动后恢复追踪；`TORNADO_STATE_LUA51_PASS`、`TORNADO_CONTRACT_PASS`、六项共享公共技能回归、相关Lua 5.1语法均通过。
- 下一步唯一动作：Workshop Tools重新验证实际粒子追踪、到达停止与目标死亡后的最后位置。

## 2026-08-02 - 检查点：龙卷到达后附着跟随规则补充

- 用户补充：主龙卷到达敌方单位后应停止自身追赶并跟随该单位，相当于附着在单位上；不是目标移动后再次以500速度追赶。
- 死亡边界保持：目标死亡后龙卷停留在死亡位置，静止等待生命周期结束；若尚未到达，则先移动到最后位置再等待。
- 当前实现差异：到达后只在当帧速度归零，目标下一帧移动时会恢复500速度追赶，尚无持久`attached_to_target`身份。
- 下一步：增加附着状态；附着且目标存活时直接同步目标位置，死亡时保留最后位置并停止；补充行为与契约测试。

## 2026-08-02 - 检查点：龙卷附着跟随实现完成

- 新增持久`attached_to_target`状态：到达前以500速度追踪；第一次到达存活目标时进入附着状态。
- 附着且目标存活时，每个共享调度帧将龙卷权威中心直接同步为目标当前位置，返回零粒子速度，不再产生追赶距离。
- 附着后目标死亡时不再刷新位置，龙卷固定在最后存活位置；到达前死亡则继续以500速度前往最后位置，到达后静止。
- 粒子CP0继续同步权威中心，附着阶段CP1为零；伤害、减速、主龙卷3秒生命周期和LV5分裂规则均未改变。
- 权威技能CSV、Tooltip CSV、运行配置等级描述和生成Lua已同步更新。
- Lua 5.1行为测试新增完整状态流：到达前追踪、第一次到达进入附着、目标移动时直接同步、目标死亡后位置固定。
- 验证结果：`TORNADO_STATE_LUA51_PASS`、`TORNADO_CONTRACT_PASS`、`TORNADO_ATTACHMENT_LUAC_PASS`及六项共享公共技能回归全部通过。
- 下一步唯一动作：Workshop Tools实机验证视觉追踪、附着跟随和死亡后静止。

## 2026-08-02 - 检查点：实机确认完整Invoker粒子不接受跟随重定位

- 用户实机反馈：龙卷视觉仍按直线继续前进，没有跟随；提供的`[CombatDamage]`日志显示`proto_void_pulse`仍持续产生3060纯粹伤害事务，无Lua报错。
- 日志能证明伤害状态机运行，但没有龙卷ID、位置和附着状态，不能证明视觉或服务端中心是否附着。
- 根因证据：生产仍使用完整`particles/units/heroes/hero_invoker/invoker_tornado.vpcf`；该技能粒子按创建时CP1自行直线推进，后续更新CP0/CP1不能保证重定位已发射的内部粒子。这解释了Lua模拟通过而画面直线飞走。
- 本机`pak01_dir.vpk`索引确认存在`invoker_tornado_child`及其dust/leaves/twigs等子资源；项目content已有可编译KV3粒子链模式。
- 已排除继续依赖完整Invoker粒子动态转向：实机已经证明该方案不可靠。
- 修复决策：新增项目父粒子，仅引用`particles/units/heroes/hero_invoker/invoker_tornado_child.vpcf`，不包含直线推进算子；所有视觉位置只由Lua每帧更新CP0。加入spawn/attached/target_dead/finish低频状态日志。
- 下一步：创建并编译粒子、替换Lua常量和预缓存、补充契约测试并重跑回归。

## 2026-08-02 - 检查点：Lua定位龙卷视觉完成

- 新增content源粒子`particles/survival_tornado/survival_tornado_follow.vpcf`：父粒子只引用Valve的`invoker_tornado_child.vpcf`，没有`C_OP_BasicMovement`或速度控制点。
- 生产Lua与预缓存均切换到项目粒子；删除主/小龙卷创建时和共享同步中的CP1速度写入，视觉位置仅由每帧CP0同步权威中心。
- 新增低频`[HeroTornado]`日志：spawn、attached、target_dead、finish，包含龙卷ID、主/小身份、目标entindex、附着状态和位置；不在每帧输出。
- Resource Compiler强制编译结果：`OK: 1 compiled, 0 failed, 0 skipped`；game产物`particles/survival_tornado/survival_tornado_follow.vpcf_c`存在。
- `TORNADO_STATE_LUA51_PASS`、`TORNADO_CONTRACT_PASS`、生产/测试Lua 5.1语法和六项共享公共技能回归全部通过。
- 用户提供的`[CombatDamage]`日志无明确错误，只能证明`proto_void_pulse`伤害事务持续发生；同一attack标识下多个事务可能来自重叠活动龙卷，不能替代龙卷ID状态日志。
- 下一步唯一动作：完全重启Workshop Tools Run后实机复验；需要观察同一ID是否依次出现spawn和attached，以及视觉是否随CP0中心移动。

## 2026-08-02 - 检查点：龙卷风任务阶段性完成

- 用户原话：`这个任务暂时完成，还需要一些优化，但是可以先记录到我们的docs文件夹下的相关文件当中`。
- 状态结论：用户确认当前阶段暂时完成，本轮停止继续编码；当前实现作为可靠基线保留。
- 确认范围：五级配置、伤害/减速/分裂状态机、主龙卷追踪与附着规则、目标死亡位置规则、Lua控制CP0的项目龙卷粒子、预缓存、诊断日志和自动测试均已落盘。
- 不扩大结论：用户明确说明仍需要一些优化，因此不得记录为“最终优化完成”“全部实机验收通过”或“制作永久封版”。
- 稳定架构已写入`PROJECT_CONTEXT.md`：追踪视觉必须使用`particles/survival_tornado/survival_tornado_follow.vpcf`及Lua CP0定位，不得恢复完整Invoker Tornado粒子的CP1直线推进方案。
- 当前没有代码阻塞，也没有活跃编码动作；后续优化内容、数值和验收优先级尚未由用户指定。
- 下一步唯一动作：等待用户指定具体优化项或新的开发任务；不得自动恢复龙卷风修改。
# Session Checkpoint Log

> 仅追加关键检查点。记录研究过程，而不只是任务完成后的总结。

## 2026-08-02 — 公共技能“脉冲激射”完成确认

- 用户明确确认“技能已经制作完成”，本技能从“等待冷启动实机验收”转为已完成状态；当前没有脉冲激射待办，不再把它作为活跃开发任务恢复。
- 最终基线保持不变：保留`proto_blade_nova`/`ability_survival_blade_nova`、显示名“剑刃震荡·被动”和`public_05`公共池身份；LV1至LV5规则、200总宽度、英雄面向、1秒全程、LV2逐道首目标、LV3距离倍率、LV4继承及LV5同路径三道完整独立伤害均按上一实现检查点固化。
- `START_HERE.md`、`CURRENT_TASK.md`和`PROJECT_CONTEXT.md`已同步完成状态与稳定规则。后续只有用户提出明确调整或实机问题时才重新打开该技能。

## 2026-08-02 — 公共技能“脉冲激射”五级实现

- 用户确认保留`proto_blade_nova`/`ability_survival_blade_nova`和显示名“剑刃震荡·被动”，最高5级；LV4完整继承LV3，LV5才获得射程+50%和30%三道脉冲。三道完全重合，30%成功时本次总数为3道而非额外增加3道，每道完整独立伤害。
- 运行实现改为原生穿透线性投射物：触发时快照英雄面向、逻辑全属性与多级回退攻击射程；总宽度200对应起止半径100，`bDeleteOnHit=false`，每道保存独立首目标状态和命中去重。复用已验证的Wave of Terror粒子，速度按射程动态计算，使所有射程均在1秒走完全段。
- LV1为15%触发、全属性×4纯粹伤害；LV2每道首个目标翻倍；LV3按目标沿脉冲方向投影距离从×4线性增长到末端×8并钳制；LV4不变；LV5射程×1.5，30%概率发射同路径3道，同一敌人可分别承受3次且无衰减。
- 源CSV、引擎Ability五级KV、运行配置、自定义Tooltip发布、生成技能/Tooltip配置和粒子预缓存已同步。当前环境无可用Python 3，使用仓库既有PowerShell CSV生成回退重建目标技能配置；生成结果与源CSV由契约测试核对。
- `BLADE_PULSE_STATE_LUA51_PASS`、`BLADE_PULSE_CONTRACT_PASS`、addskill及爆炎弹/移动冰球/毒云/魔法弹弓/寒冰锥/奥术弹幕回归通过；相关Lua 5.1语法、严格UTF-8和限定`git diff --check`通过。仍需Workshop Tools冷启动验收粒子、引擎碰撞回调顺序和三道重合效果。

## 2026-08-01 — 英雄科技攻击减甲实机诊断

- 用户回传前5次权威命中均进入服务，但全部以 `reduction_not_positive` 拒绝，且科技/final/hero结构完整、减甲值为0；这排除了事件、攻击者、目标与Modifier应用链，根因收窄到科技运行值同步。
- 根因确认：`addtechnology researcher_hero_armor_reduction_19` 走生成科技分支并在 `TECHNOLOGY_CHANGED` 中携带 `researcher_hero_armor_reduction=19`，但 `technology_stat_manager.on_technology_changed` 丢弃 `payload.levels`，转而查询独立旧研究仓库；旧仓库未写入 `ARS-09`，其0值遂覆盖生成科技。现生成科技事件优先按自身完整levels调用`rebuild`，仅无levels的旧调用方保留旧仓库兼容回退，并新增旧仓库返回0时仍必须得到`9.5/3`的Lua回归测试。
- 用户冷启动实测同一怪物攻击500次后实际伤害仍不变，证明此前仅模拟`AddNewModifier`调用次数的测试不足以确认引擎创建、刷新和物理护甲属性结算。
- 权威命中服务现对目标分别计数，在1至5及10/25/50/100/250/500次命中记录玩家、攻击者/目标、实时科技值、调用前护甲、Modifier返回值栈数和同调用栈有效护甲；`AddNewModifier`抛错或返回nil时输出`RESEARCH_ARMOR_APPLY_FAILED`，不再由EventBus静默吞掉关键信息。
- 目标Modifier在相同里程碑记录`OnCreated`或`OnRefresh`、增量、计划/延迟帧栈数、延迟帧前后有效护甲、护甲差和显式下限。该诊断可直接区分服务未调用、Modifier未创建/未刷新、栈累计但引擎护甲不变三类故障。
- 用户反馈`RESEARCH_ARMOR_APPLY/APPLY_FAILED/EFFECT`均完全未出现，因此故障已收窄到应用前：运行时可能仍加载旧Lua、服务未初始化、权威事件未到达、事件载荷被拒绝或科技管理器运行值为0。新增模块加载、服务订阅、回调入口和明确拒绝原因日志；回调入口/拒绝日志仅输出前5次，内存高水位警告本身不作为根因证据。

## 2026-08-01 — 英雄科技19级攻击减甲结算与UI修复

- 用户反馈`researcher_hero_armor_reduction_19`已完成但敌方实际护甲和自定义UI均未降低。完整链路确认配置无误：CSV/生成配置19级累计9.5 War3显示护甲，旧科技`ARS-09`通过`war3_hero_armor_shred_flat`累计，并由`armor_balance.from_war3`换算为每击约3.1667 Dota底层护甲后写入英雄`modifier_research_technology`；普攻命中及目标减甲Modifier注册也正常。
- 实际结算根因：波次、遭遇和挑战生成入口在怪物未配置`minimum_armor`时默认写入`survival_minimum_armor=1`，等价于3点自定义显示护甲。减甲Modifier严格执行该下限，导致显示2/3护甲的前期怪完全不能降低，显示4护甲也最多降到3；`addmonster`同样硬编码该下限。现改为缺省`nil`，仅显式配置下限的特殊单位继续受限，树木规则未改。
- UI根因：科技事件在`SetStackCount`同一调用栈同步派发，可能让`GetPhysicalArmorValue(false)`读取引擎旧值；同时项目英雄权威快照只对毒云覆盖实时护甲，`research_armor_reduction`会被稳定装备护甲隐藏。现将科技刷新延迟到下一Scheduler帧，并将该原因纳入实时有效护甲字段覆盖，其他英雄权威属性保持不变。
- 验证：新增Lua状态测试覆盖19级换算后的累计减甲、无隐式下限、负护甲、显式下限与事件去重；契约测试锁定配置、换算、三个怪物入口、调试怪、Modifier注册和UI分流。`RESEARCH_ARMOR_REDUCTION_STATE_LUA51_PASS`、`RESEARCH_ARMOR_REDUCTION_CONTRACT_PASS`及毒云状态/契约回归通过；修改Lua 5.1语法、严格UTF-8和全局`git diff --check`通过。仍需Workshop Tools冷启动确认每击UI减少9.5且物理伤害同步提高。

## 2026-08-01 — 毒云LV2减甲选中单位UI刷新修复

- 后续冷启动实机反馈确认补发事件后护甲仍未等比例降低。重新追踪真正的自定义UI：`CombatArmorValue`直接消费`ui_selected_unit_stats_snapshot.armor`，事件名、服务端订阅、Panorama接收及普通敌人的版本规则均正确；根因不再是事件路由，而是`MODIFIER_PROPERTY_PHYSICAL_ARMOR_TOTAL_PERCENTAGE`未可靠反映到自定义UI权威读取的`GetPhysicalArmorValue(false)`。
- 最终修复：毒云Modifier改用项目科技与装备链已验证的`MODIFIER_PROPERTY_PHYSICAL_ARMOR_BONUS`。每次0.05秒同步读取包含毒云旧修正的当前护甲，加回毒云自身旧减甲得到实时外部护甲，再按层数重算20%/40%/60%的平坦负护甲；其他装备、科技、平A减甲和Buff变化会动态参与，不保存进入时快照。负护甲按绝对值继续向更低方向减少，例如-10的一层结果为-12。
- 自定义UI边界：普通敌人继续由运行时快照读取有效护甲；若毒云事件目标命中项目英雄权威快照路径，仅覆盖该次快照的`runtime_armor/armor`为当前有效护甲，攻击、攻速和逻辑三维仍保持原子权威值。事件只在层数、比例或实际平坦减甲变化时派发，移除时派发恢复事件。
- 用户实机反馈：毒云等级2未看到敌方单位护甲减少；用户同时指出若引擎减甲已经生效，则缺口可能是没有派发敌方单位护甲UI刷新事件。
- 根因确认：敌方普通单位选中面板会在`UNIT_COMBAT_STATS_CHANGED`后通过`GetPhysicalArmorValue(false)`重新读取包含Modifier的实时护甲；科技平A减甲每次变化都会派发该事件，而`modifier_hero_poison_cloud_armor`此前只更新层数与总护甲百分比，创建、叠层和移除均未派发事件，因此面板会停留在旧护甲值。
- 修复：毒云减甲Modifier在1/2/3层或每层百分比实际变化时延迟到下一Scheduler帧派发`UNIT_COMBAT_STATS_CHANGED`，原因标记为`poison_cloud_armor_changed`；移除时派发`poison_cloud_armor_removed`，使面板读取Modifier已完成变化或销毁后的护甲。0.05秒区域同步重复写入相同层数时不重复派发，避免UI事件洪泛。
- 验证：Lua状态测试真实执行延迟回调，覆盖三次层数刷新、相同层数去重和移除恢复事件；毒云契约同时锁定UI路由订阅及`GetPhysicalArmorValue(false)`实时读取。`POISON_CLOUD_STATE_LUA51_PASS`、`POISON_CLOUD_CONTRACT_PASS`及爆炎弹、移动冰球、魔法弹弓、寒冰锥、奥术弹幕、addskill回归通过；Lua 5.1语法、严格UTF-8和全局`git diff --check`通过。仍需冷启动实机确认引擎实际护甲与面板同步下降。

## 2026-08-01 — 公共技能“毒云”五级重做实现检查点

- 身份与配置：保留`proto_poison_cloud`/`ability_survival_poison_cloud`及原公共池身份，最高等级由3改为5。LV1/2为12%触发、400固定范围、5秒内第1至第5秒各造成触发时全属性×1纯粹伤害；LV3起20%触发、持续7秒共7次；LV4完整继承。
- 单云与状态：同一英雄同时只有一个毒云，再次触发立即销毁旧粒子、清理旧区域减甲并在新位置重置完整时序。所有毒云共用一个0.05秒Scheduler任务，整秒伤害按绝对开始时间校正；AOE与死亡判定均使用敌人Hull边缘二维范围。
- 动态减甲：LV2起每次Tick命中增加1层，最多3层，分别通过专用`modifier_hero_poison_cloud_armor`返回实时总护甲-20%/-40%/-60%。不保存初始护甲快照，因此科技、平A减甲、装备和其他Buff变化会实时参与；离开、毒云替换或到期立即移除Modifier。不同英雄毒云重叠时取最高有效减甲而不相加超过60%。
- LV5：订阅`ENGINE_ENTITY_KILLED`，死亡瞬间按实际位置重新检查有效毒云，以死亡位置为中心造成300范围、触发时全属性×3纯粹伤害；每个死亡单位去重一次，但爆炸击杀仍在毒云内的敌人可继续连锁。
- 表现与验证：地面使用毒龙幽冥剧毒`viper_nethertoxin.vpcf`并显式预缓存；死亡反馈使用项目已验证的`basic_explosion.vpcf`。`POISON_CLOUD_STATE_LUA51_PASS`、`POISON_CLOUD_CONTRACT_PASS`及爆炎弹、移动冰球、魔法弹弓、寒冰锥、奥术弹幕、addskill回归通过；相关Lua 5.1语法、严格UTF-8和全局`git diff --check`通过。仍需Workshop Tools冷启动确认粒子控制点、动态总护甲属性、负护甲边界和连锁实机表现。

## 2026-08-01 — 公共技能“爆炎弹”用户实机验收记录

- 用户在实机体验后明确反馈“这个做的也很好”，并要求直接记录。该反馈作为爆炎弹整体效果的正向验收证据；不虚构用户未逐项报告的具体伤害数字或粒子测量结果。
- 当前`proto_flame_burst`/`ability_survival_flame_burst`五级实现正式固化：15%触发、500范围×4主爆炸、3秒总计×2.2点燃、LV3五层独立生命周期、LV4继承、LV5三颗小火球在200落点范围内同步落地并各自造成250范围×3及点燃。
- 后续默认不再主动调整爆炎弹数值、点燃替换规则、同步落地逻辑或粒子；只有用户提供新的明确需求或实机问题时才重新打开该技能任务。

## 2026-08-01 — 公共技能“爆炎弹”五级重做实现检查点

- 身份与配置：保留`proto_flame_burst`/`ability_survival_flame_burst`及原公共池身份，显示名改为“爆炎弹·被动”，最高5级。主攻击命中15%触发，主爆炸固定触发时目标位置，对500范围造成触发时全属性×4纯粹伤害。
- 点燃：LV2起主爆炸命中施加点燃；每层在第1/2/3秒结算，三次总倍率通过末次余数校正确保精确为全属性×2.2。LV2重复点燃替换旧层并重置完整3秒；LV3起最多5层，每层独立保存属性快照、Tick进度和到期时间，第6层替换最早到期层；LV4完整继承。
- LV5：主爆炸后一次性生成3个中心200半径内的均匀圆形随机落点，同时创建飞行粒子，仅用一个0.5秒Scheduler任务同步落地。每颗小火球分别对250范围造成全属性×3纯粹伤害并增加1层点燃；重叠敌人逐颗承受直接伤害并逐颗增加点燃。
- 工程与表现：主爆炸和小火球AOE复用实际Hull边缘二维命中；点燃由单个0.05秒共享任务管理，敌人只创建一个持续燃烧视觉。暂用Lina光击阵/龙破斩及Huskar燃烧之矛粒子并显式预缓存，视觉仍需实机调整。
- 自动验证：`FLAME_BURST_STATE_LUA51_PASS`与`FLAME_BURST_CONTRACT_PASS`通过，覆盖×2.2精确总倍率、LV2替换、五层上限、第6层替换最早层和200随机边界；移动冰球、魔法弹弓、寒冰锥、奥术弹幕、addskill、英雄Ability与原生血条契约全部回归通过，相关Lua 5.1语法、严格UTF-8和`git diff --check`通过。仍需Workshop Tools冷启动实机验收。

## 2026-08-01 — 公共技能“移动冰球”五级重做实现检查点

- 身份与配置：保留公共池`public_02`的`proto_frost_nova`/`ability_survival_frost_nova`，显示名改为“移动冰球·被动”，最高5级；没有覆盖独立的`proto_ice_cone`寒冰锥。源CSV、运行参数、Ability KV、生成技能与Tooltip配置已同步。
- 运行规则：主攻击命中12%触发；LV1速度360、300范围、每0.5秒触发时全属性×2纯粹伤害；LV2速度540，每颗冰球按不同沿途敌人去重增长5%，最多10层；LV3起范围350并在所有飞行结束情形固定爆炸全属性×3；LV4继承LV3。
- LV5：最大移动距离为触发时英雄至原攻击目标二维距离的150%，在该范围内随机选择敌人追踪，每实际移动100码使周期基础伤害+10%。目标死亡后锁定其死亡位置且不重新索敌，随后直线飞向该位置；到达死亡位置或耗尽最大距离时爆炸。碰撞和距离成长只影响周期×2，不影响固定×3爆炸。
- 工程实现：每颗冰球保存触发时逻辑三维快照、当前位置、累计距离、碰撞去重集和追踪状态；所有活动冰球由单个0.05秒共享Scheduler任务更新。范围伤害复用实际Hull边缘二维命中，路径碰撞使用线段至单位原点距离再叠加单位Hull。
- 表现与验证：移动/爆炸暂用项目内`basic_projectile`粒子并显式预缓存；Tooltip发布LV1至LV5完整说明。`MOVING_ICE_BALL_MATH_LUA51_PASS`、`MOVING_ICE_BALL_CONTRACT_PASS`及魔法弹弓、寒冰锥、奥术弹幕、addskill回归通过；相关Lua 5.1语法、严格UTF-8和`git diff --check`通过。仍需Workshop Tools冷启动验收粒子、Dota API、实际移动与伤害。

## 2026-08-01 — 魔法弹弓10%触发与召唤英雄射程兼容实机修复

- 用户实机连续攻击未见石弹。加入限量诊断后确认10%算法本身正常：日志多次出现`random < 0.1 success=true`，但随后为`MAGIC_SLINGSHOT_FAILED reason=no_targets range=0 primary=828`。因此根因不在随机数、攻击事件、技能拥有状态或“必须5人”，而在成功掷骰后的射程目标查询。
- 规则澄清并固化：任意敌方主攻击命中都进行10%判定；`target_count=5`表示最多5名，绝不是至少5名。只有1名敌人时只发射1颗，少于5名时对所有有效目标各发1颗，超过5名时按LV2未眩晕优先及距离顺序截取5名。
- 根因：项目通过`hero_stat_adapter::Script_SetAttackRange()`为`CreateUnitByName`召唤英雄应用CSV射程，但Dota实机中同一英雄`GetAttackRange()`返回0。旧魔法弹弓在`radius <= 0`时提前返回，甚至没有执行本次命中主目标的保底插入。
- 修复：`hero_stat_adapter`同步保存`unit.survival_attack_range`；`current_attack_range()`受保护读取运行时缓存、`Script_GetAttackRange`、`GetAttackRange`和`hero_definitions[survival_hero_id].attack_range`并取最大有效值。宽查询使用`射程+256`，最终按`射程+敌人实际HullRadius`的XY平方距离过滤；本次合法命中的敌方主目标始终保底，即使所有射程来源仍为0也不会空触发。
- 诊断：前30次打印`MAGIC_SLINGSHOT_ROLL`，之后仅成功掷骰继续打印；失败输出`MAGIC_SLINGSHOT_FAILED`及原因，创建投射物输出`MAGIC_SLINGSHOT_LAUNCHED`，命中回调输出`MAGIC_SLINGSHOT_HIT`。`HERO_PASSIVE_SKILL_TRIGGERED`已移动到runner成功之后，失败启动不再伪报触发。
- 自动测试：新增`tools/test_magic_slingshot_targets.lua`并由`C:\msys64\mingw64\bin\lua5.1.exe`真实执行，覆盖单目标只发1颗、少于5名全部选择、6名截断最近5名、LV2未眩晕优先、Hull边界、引擎射程0时CSV回退及全部射程为0时主目标保底。`MAGIC_SLINGSHOT_TARGETS_LUA51_PASS`、魔法弹弓/奥术弹幕/寒冰锥/addskill契约、相关`luac5.1 -p`、严格UTF-8和`git diff --check`通过。
- 最新实机证据：`[MAGIC_SLINGSHOT_ROLL] ... random=0.016141 chance=0.100000 success=true`后出现`[MAGIC_SLINGSHOT_LAUNCHED] ... range=3000 selected=1 launched=1`，证明概率、配置射程回退、单目标选择和投射物创建成功。该段日志尚无`MAGIC_SLINGSHOT_HIT`，所以命中回调、伤害、眩晕以及LV2/LV3/LV5效果仍必须继续实机验收，禁止提前标记完成。

## 2026-08-01 — Lua 5.1工具路径纠正与寒冰锥语法补验

- 用户纠正此前环境判断：可用编译器为 `C:\msys64\mingw64\bin\luac5.1.exe`。已实际探测文件存在并执行 `-v`，结果为Lua 5.1.5。
- 根因：该可执行文件不在当前PATH，先前只探测`lua`/`luac`命令和Dota目录，因此错误地记录为没有Lua/Luac。后续会话不得仅依赖PATH探测，必须优先检查上述绝对路径。
- 已将稳定路径和标准`-p`命令写入`PROJECT_CONTEXT.md`，并在`KNOWN_ISSUES.md`中把“没有解释器”修正为“存在但不一定在PATH”。旧检查点中的错误判断保留为历史，不静默改写。
- 已使用该编译器补跑本次寒冰锥相关Lua文件语法检查；语法验证结果见本检查点后的当前任务状态。Luac通过不替代Workshop Tools中的Dota API与视觉行为验证。

## 2026-08-01 — 公共技能“寒冰锥”五级重做完成检查点

- 配置完成：保留 `proto_ice_cone` / `ability_survival_ice_cone` 身份；权威英雄技能 CSV、五级运行配置、Ability KV、生成技能配置和Tooltip配置已同步。技能最高5级，图标改为 `crystal_maiden_freezing_field`，等级4明确完整继承等级3。
- 运行完成：旧前方扇形 `cone_targets()` 已删除；触发时固定目标地面位置并复用同一份逻辑三维快照，每次通过既有 Ability 伤害链造成全属性×1纯粹伤害。500范围使用 `enemies_touching_radius()` 的宽查询与实际Hull二维精确过滤。
- 时序与锁：等级1至4同步执行t=0首击、单个绝对时间校正顺序任务执行t=1/2，共锁3秒；等级5执行t=0/1/2/3/4，共锁5秒。活动期在概率事件和随机数之前跳过；正常结束任务释放锁与雪场，理论过期检查可在回调异常时清理残留雪场并恢复资格。
- 控制完成：新增 `debuff_hero_ice_cone_attack_slow`，`negative + none + refresh`；等级2至4每次命中刷新20%攻速降低3秒，等级5刷新40%。等级3起每次落冰循环内对每个存活命中敌人独立掷20%，成功添加1秒 `modifier_stunned`。
- 表现完成：每场创建一次极寒领域雪场，每次落冰创建一次至宝爆发粒子，两项均在 `addon_game_mode.lua` 显式预缓存。每场只有一个落冰顺序任务与一个结束释放任务，没有恢复逐落冰独立调度。
- Tooltip复核发现已有 `hero_skill_tooltip_view_model.lua` 未接入底栏技能Tooltip；现仅为 `proto_ice_cone` 在 `ability_runtime_service.lua` 发布当前等级与LV1至LV5完整效果字段，复用现有 `runtime.fields` 渲染，不修改Panorama源码也不影响其他11个公共技能。
- 定向生成：当前WindowsApps `python.exe` 是不可用别名，使用PowerShell 7按正式生成器类型规则定向重建 `hero_skill_definitions.lua`、`buff_definitions.lua`，并同步寒冰锥Tooltip CSV/Lua行；差异审计确认未重建或污染其他生成模块。
- 自动验证：`ICE_CONE_CONTRACT_PASS`、`ARCANE_BARRAGE_CONTRACT_PASS`、`ADDSKILL_CONTRACT_PASS`；三份目标CSV及六份相关Lua严格UTF-8解码成功、替换字符为0；旧 `cone_targets` 残留0、寒冰锥顺序调度入口1、释放调度入口1、Tooltip等级发布入口1；全局 `git diff --check` 通过。
- 限制与下一步：当前环境没有Lua/Luac且仓库当前无Lua测试目录，不能声称Lua VM或Dota引擎加载已通过。必须完全停止并重新Run Workshop Tools，逐级验收Tooltip，确认1至4级3次、5级5次落冰，减速刷新不叠加，冻结按敌人分别发生，连续触发锁可恢复，雪场和爆发粒子无残留。

## 2026-08-01 — 公共技能“寒冰锥”五级重做实施前检查点

- 用户要求开始第三个五级公共技能“寒冰锥”，并批准推荐口径：攻击命中15%概率触发；立即落第1次、之后每秒1次；等级1至4共3次且整场锁3秒，等级5共5次且整场锁5秒；等级3起每次落冰对每个命中敌人独立判定20%冻结1秒。
- 权威身份确认：`hero_definitions.csv` 只声明英雄使用 `public_pool`；实际技能池成员为 `hero_skill_pool_members.csv` 中的 `proto_ice_cone`，引擎壳为 `ability_survival_ice_cone`。必须保留二者以兼容已有技能状态；独立的 `proto_frost_nova` 不得覆盖。
- 旧实现差异：当前寒冰锥最高3级，运行时是英雄前方扇形伤害、移动减速和中心冻结；本次整体替换为固定在攻击目标触发位置的500范围暴风雪。
- 实施决定：整场使用触发时逻辑三维快照并结算纯粹伤害；等级2至4使用20%、等级5使用40%的3秒攻速降低，`none + refresh` 且不可叠加；等级4完整继承等级3；单个绝对时间校正顺序任务驱动3/5次落冰，活动锁同时提供理论过期和令牌化调度兜底。
- 表现决定：使用项目已知可用的水晶室女至宝极寒领域持续雪场与爆发粒子；持续场每次触发只创建一次，每次落冰播放一次爆发。
- 环境限制：当前PATH仅有`pwsh`，没有`py`、`lua`或`luac`，且当前工作树没有`scripts/vscripts/tests`目录；将使用PowerShell契约、定向配置生成、编码/结构检查和`git diff --check`，Lua VM与引擎表现需Workshop Tools冷启动验证。
- 旧机枪塔视觉任务已归档；其未完成的Workshop Tools视觉验收不属于本次业务修改，不得回退相关文件。

## 2026-08-01 — 奥术弹幕性能自查与最小化优化

- 用户反馈：完成奥术弹幕改写后，整体运行明显变慢并出现卡顿，要求确认此前是否属于最小范围修改并进行自查。审计结论是配置/KV/Tooltip修改较小，但 `scripts/vscripts/systems/hero_passive_skill_service.lua` 的运行时改写并非严格最小：等级5原实现会创建21个独立飞弹任务及1个锁兜底任务，每次爆炸还会执行排序后的宽范围单位查询、逐候选 `pcall` 和平方根距离计算，密集怪群中可能形成周期性尖峰。锁表检查是常数开销；每次攻击读取技能状态和属性快照是旧服务已有行为；工作区既有 Buff/UI 修改没有新增永久轮询，因此都不是本次卡顿的第一嫌疑。
- 用户提出并批准的优化口径：以XY差值平方和判断命中。候选宽查询仍使用 `explosion_radius + ARCANE_MAX_HULL_RADIUS`，用于避免引擎按单位原点预查询时漏掉Hull边缘；最终精确过滤必须使用每只怪物实际Hull：`dx²+dy² <= (explosion_radius+enemy:GetHullRadius())²`。不采用纯 `150²`，因为会漏掉碰撞体边缘；不采用统一 `(150+最大Hull)²` 作为最终命中，因为会错误扩大对小怪的AOE。
- 已实现：仅奥术弹幕候选查询改用 `FIND_ANY_ORDER`，不改变其他技能共用的 `FIND_CLOSEST`；精确过滤不再计算 `math.sqrt`、不计算Z轴，也不再为每个候选包装 `GetHullRadius()` 的 `pcall`。运行代码位置为 `hero_passive_skill_service.lua` 的 `enemies_touching_radius()`。
- 已实现：21个独立飞弹任务合并为一个按理论落点时间排序、通过回调返回下一次间隔的顺序任务，另保留1个令牌化锁兜底任务；等级5一次施法的活动调度任务由最多22个降至2个。下一颗延迟按 `cast_start_time + following.delay - current_game_time` 计算，避免Scheduler 0.05秒粒度逐颗累积漂移。运行代码位置为 `run_arcane()` 的 `impacts` 队列与 `run_next_impact()`。
- 行为保持：随机落点仍使用均匀圆分布，等级5仍为21个落点、21次粒子和最多21次伤害查询；飞弹理论时序、全属性×2纯粹伤害、150爆炸半径、实际Hull边缘命中、最后一颗正常解锁、按时过期和令牌化兜底均未改变。此次没有修改既有 Buff/UI 工作区内容。
- 自动验证：`ARCANE_BARRAGE_CONTRACT_PASS`、`ADDSKILL_CONTRACT_PASS`、`ALT_HERO_ABILITY_ORIGIN_DEV_CONTRACT_OK`、`UI_RESTORE_NATIVE_HEALTH_BAR_CONTRACT_OK`；严格UTF-8、原始定界符504/504、限定及全局 `git diff --check` 通过；运行源码中逐飞弹 `scheduler.after(impact_delay...)` 残留0、旧平方根距离残留0、单队列入口1、绝对时间校正1。
- 工具注意：当前 `pwsh` 可正常执行 `tools/test_arcane_barrage_contract.ps1`；旧 Windows PowerShell 5 独立进程会把无BOM脚本中的中文CSV路径错误解码并报路径不存在，这不是业务断言失败。当前环境仍无独立Lua/Luac，无法完成真实Lua VM和引擎性能测试。
- 后续实机唯一验收清单：完全关闭并重启Workshop Tools；在密集怪群中触发等级5弹幕，确认3秒内21次爆炸完整且帧时间改善；确认怪物Hull边缘接触150范围时受伤、爆炸视觉与伤害中心一致；连续触发至少5次并确认每次结束后重新具备触发资格。若仍卡顿，下一优先嫌疑是21次粒子及21次 `FindUnitsInRadius` 的引擎成本，而不是平方距离或锁检查。

## 2026-08-01 — 公共技能“奥术弹幕”五级区域炮击实现

- 最终规则：攻击命中10%概率触发，记录目标位置及逻辑三维快照；等级1在500落点半径内于1秒落5颗飞弹，等级2落点半径缩至200，等级3与等级4每轮7颗，等级5在0/1/2秒开始三轮并于第3秒完成，共21颗。每颗独立对150范围造成全属性总和×2纯粹伤害，同一单位可被多颗分别命中。
- 不叠加契约：按英雄 entindex 保存活动施法令牌与剩余飞弹数；活动期间在掷概率和发布概率事件之前直接跳过奥术弹幕，最后一颗完成伤害回调后才解除。针对实机出现两次后疑似残留锁，增加理论结束时间主动过期与结束后0.5秒令牌化调度兜底；即使最后回调丢失也不会永久锁定。
- 表现：用户实机认为追踪导弹效果不理想，已完全移除矮人直升机飞行/爆炸粒子及预加载，改为项目内 `basic_explosion.vpcf` 在随机落点地面播放简单爆炸。`opvar_get_float ... dota_battleend` 在项目源码无引用，判断来自原粒子内部操作器，移除该粒子后不再属于奥术弹幕运行链。
- AOE口径：实机反馈怪物视觉上接近爆炸却不受伤；原实现虽确实将 `explosion_radius=150` 传给 `FindUnitsInRadius` 并遍历全部返回敌人，但引擎预查询按单位原点，模型/Hull边缘进入范围仍可能漏判。现先用 `150+256` 宽查询候选，再按XY距离 `<=150+enemy:GetHullRadius()` 精确过滤；不计算Z高度，所有碰撞体边缘进入爆炸范围的敌人分别结算，同一颗对同一单位仍只伤害一次。
- 配置与验证：源CSV、运行配置、引擎Ability五级KV、生成技能/Tooltip配置已同步；`ARCANE_BARRAGE_CONTRACT_PASS`、`ADDSKILL_CONTRACT_PASS`、CSV解析、严格UTF-8解码及限定 `git diff --check` 通过。当前环境无独立Python/Lua，需Workshop Tools完全冷启动实机验收简单地面爆炸、随机落点与连续触发时的锁释放。

## 2026-07-31 — 英雄技能伤害测试、addskill 与公共技能上限

- 伤害测试：沿用现有英雄伤害面板和最终 `OnTakeDamage` 事件，新增累计技能伤害、最近技能伤害和技能命中次数；普通攻击仍只进入总伤害。公共被动技能伤害请求补充真实 Ability handle，确保包括怒雷在内的技能伤害被归类为 `ability`。
- 作弊码：新增聊天命令 `addskill`，通过独立 `HERO_SKILL_POINT_SET_REQUEST` 将当前英雄技能点直接设置为10，重复输入不累加；无英雄时返回 `combat_hero_not_ready`。
- 技能池审计：原实现只有英雄总技能容量10，没有公共池独立上限；现增加公共技能上限3，并在候选生成、选择创建和最终授予三层检查。达到3个后转生随机技能奖励正常跳过，不影响同次技能点奖励或专属技能。
- 验证：`REBIRTH_SKILL_CONTRACT_PASS`、`COMBAT_STAT_REFRESH_CONTRACT_PASS`、`SKILL_DAMAGE_AND_CHEAT_CONTRACT_PASS`、`git diff --check`；Panorama JS/CSS 分别 `1 compiled`，HUD XML加载链 `7 compiled`，均为0失败0跳过。当前环境无独立Lua解释器，仍需Workshop Tools完全冷启动实机确认。

## 2026-07-31 — 公共技能“怒雷”五级实现与 Office CSV 编码兼容

- 用户批准将现有 `proto_chain_lightning`/“雷霆连锁”原 ID 重做为“怒雷”，避免公共池数量与存档身份变化；等级4明确完整继承等级3，无任何数值或效果变化。
- 最终规则：等级1触发率20%，主目标全属性×3纯粹伤害，400范围其他敌人承受50%；等级2命中施加/刷新3秒标记，旧标记目标额外全属性×1.5；等级3触发率45%，标记降低15%基础攻击力；等级5一次触发依次落3道，优先不同目标，不足时重复主目标且从第二次主雷起减半。每一道及其扩散均参与标记检查与刷新。
- 实现：被动配置改为逐技能 `max_level`；怒雷引擎 Ability `MaxLevel=5`；运行服务取消三级硬截断，继续读取 `HERO_COMBAT_STATS_GET_REQUEST` 逻辑三维并通过既有纯粹伤害事务结算；复用宙斯 `zuus_lightning_bolt.vpcf`。
- Buff：新增 `debuff_hero_fury_thunder_mark`，`none + refresh`，等级2数值0只作标记，等级3以上通过 `MODIFIER_PROPERTY_BASEDAMAGEOUTGOING_PERCENTAGE` 施加-15%；每次怒雷命中先检查旧标记和额外伤害，再刷新完整3秒。
- 编码：`data/csv/英雄系统/hero_skill_pool_members.csv` 从 UTF-8无BOM转换为UTF-8 BOM（`EF BB BF`），WPS与现有生成器继续兼容，Office/Excel双击可识别UTF-8中文。
- 生成与验证：PowerShell定向生成 `hero_skill_definitions`、`buff_definitions`、`hero_skill_pool_members` 等配置；`REBIRTH_SKILL_CONTRACT_PASS` 与 `COMBAT_STAT_REFRESH_CONTRACT_PASS`。当前环境仍无独立 Python/Lua，Lua运行效果需 Workshop Tools 冷启动实机验收。

## 2026-07-30 — 英雄护甲 0/850 跳变与攻速刷新审计

- 用户实机截图确认：英雄护甲显示在 0 与 850 间反复跳变，要求先阅读刷新规则并同步审计攻速。
- 既有规则：英雄面板护甲必须来自 `hero_combat_stat_service` 经 `combat_stat_projection` 生成的 War3 显示值；攻速必须来自配置 BAT、固定间隔变化和装备攻速百分比，禁止依赖引擎当前帧攻击间隔。完整属性为事件驱动，0.25 秒循环只刷新生命/魔法。
- 根因：`ui_request_router.hero_ui_snapshot()` 取得英雄权威快照后，又用当前帧 `GetPhysicalArmorValue()` 覆盖其中 `runtime_armor`；这违反函数自身注释。英雄 NetTable 与即时响应又共用无版本 `update()`，后到的临时 0 与稳定 850 可互相覆盖。
- 攻速审计：英雄即时响应没有单独改写权威攻速，但与护甲共用无版本 `update()`，因此旧的整份快照迟到时同样可能让攻速倒退。
- 修复：英雄即时响应不再覆盖任何权威护甲字段；英雄战斗快照新增单调 `refresh_version`；Panorama 对同一选中单位拒绝旧版本，以及已有版本后到达的无版本快照。攻击、护甲、攻速与三维继续作为一份原子快照更新。
- 验证：`COMBAT_STAT_REFRESH_CONTRACT_PASS`；`combat_stats.js` 强制编译为 `OK: 1 compiled, 0 failed, 0 skipped`；game 目录 `combat_stats.vjs_c` 已刷新；game/content 限定 `git diff --check` 均通过。当前环境仍无独立 `lua/luajit`，未虚报 Lua 运行测试。
- 冷启动复测后护甲稳定为 0 的后续根因：5001 的生成武器字段 `base_war3_armor` 当前为 0，850 来自 `equipment_level_definitions.lua` 的完整阶段快照；英雄权威快照却仍从同帧 `GetPhysicalArmorValue()` 反推 HUD 值，Modifier 尚未完成刷新时会把 0 固化。现改为直接发布装备聚合的 War3 护甲（5001=850），装备护甲为 0 时回退英雄配置基础护甲；引擎 `runtime_armor` 只保留作结算诊断。刷新契约测试与两侧限定 `git diff --check` 再次通过。

## 2026-07-30 — 二转技能授予失败与启动时序修复

- 实机日志确认：`hero.skill.grant.request` 在 `hero_skill_system.lua:144` 执行 `index - 1` 时崩溃；循环使用 `for _, skill_id` 丢弃了索引，客户端因此只收到通用 `skill_grant_failed`。
- 状态污染风险：旧实现先修改 `levels/order/version` 再同步 ability；异常后提示失败但服务端可能已拥有技能。技能点升级同样先扣点再同步，存在吞点风险。
- 修复：技能同步改为受保护调用并返回 `skill_sync_failed`；授予失败回滚等级、顺序和版本，技能点升级失败恢复点数、等级和版本，并尝试重建旧 ability 集合。
- 启动日志确认：模块顶层调用 `GetGameModeEntity()` 可能得到 nil。顶层现在只记录 `game_mode_entity_unavailable` deferred；`Activate()` 阶段必须成功应用启动规则，否则明确中止初始化。
- Modifier 注册：统一注册表新增完整 class 验证并向启动日志输出验证数量；旧局出现 unknown modifier 且同时执行已删除代码，判定必须通过全新冷启动复验，不能用热加载混合局作为结论。

## 2026-07-30 — 智慧之书逻辑三维与原生三维隔离

- 用户实机发现：购买智慧之书后三维和攻击力数值正确，但攻速随敏捷增长，说明逻辑三维被写入了 Dota 原生属性。
- 根因：`hero_progression_system.lua` 在累计 `all_attributes` 后又调用 `ModifyStrength/ModifyAgility/ModifyIntellect`；`modifier_weapon_stat_projection.lua` 也把七宗罪逻辑三维作为原生属性 bonus 投影。
- 技能风险：`hero_passive_skill_service.lua` 原先优先读取 `GetStrength/GetAgility/GetIntellect`，会把引擎副作用当成技能权威数据；原生三维归零后还会导致技能按零三维结算。
- 修复边界：逻辑三维只保存在 progression、装备聚合和 `hero_combat_stat_service` 快照中；被动技能与装备三维伤害统一通过 `HERO_COMBAT_STATS_GET_REQUEST` 读取；不增加抵消攻速的 modifier。
- 预期结果：购书和其他全属性成长只改变三维 UI 及明确使用三维公式的技能/装备伤害，不再改变 Dota 原生攻速、护甲、生命、魔法或主属性攻击。

## 2026-07-28 — 检查点 001：确认上下文丢失风险

- 用户最新要求：多次断开和界面关闭导致深度计划讨论丢失；希望解决即使重读四份上下文文档仍无法恢复断点的问题。
- 已读取：`PROJECT_CONTEXT.md`、原 `CURRENT_TASK.md`、`DECISIONS.md`、`KNOWN_ISSUES.md`。
- 新确认事实：四份文档保存了此前已完成的工程结论，但没有“最后一条用户要求、断开前正在研究什么、尚未定案证据、下一步唯一动作”。
- 已确认历史工程状态：Tooltip 事件驱动重构已完成；29 个 Lua 测试通过；相关 Panorama 资源已强制编译；仍有 Workshop Tools 实机确认项。
- 已排除：不能恢复已关闭界面的聊天原文；不能声称记得未落盘内容；不能从历史 Tooltip 总结推断断开前的新任务。
- 用户决策：批准先建立抗断连文档系统，再重建丢失任务。
- 下一步：迁移旧任务历史，创建唯一恢复入口和追加式检查点日志。

## 2026-07-28 — 检查点 002：开始实施恢复系统

- 工作区事实：`docs/ai` 当前整体为 Git 未跟踪目录；没有可依赖的上下文文档版本历史。
- 修改边界：只修改 `docs/ai`，不修改游戏代码、配置或 Panorama 源码。
- 迁移策略：原 `CURRENT_TASK.md` 移至 `docs/ai/archive/2026-07-28-tooltip-and-prior-tasks.md`，仅改归档标题并添加说明，保留其余历史内容。
- 新结构：`START_HERE.md` 为唯一入口；`CURRENT_TASK.md` 只包含当前恢复任务；`SESSION_LOG.md` 追加研究检查点。
- 尚未确认：断开前具体任务内容。
- 下一步：更新长期协议文档，复读文件并执行限定路径验证。

## 2026-07-28 — 检查点 003：恢复系统验证完成

- 已建立：`START_HERE.md` 唯一恢复入口、单一活跃任务格式的 `CURRENT_TASK.md`、追加式 `SESSION_LOG.md` 和 `archive/` 历史归档。
- 长期协议：`PROJECT_CONTEXT.md`、`DECISIONS.md` 和 `KNOWN_ISSUES.md` 已登记恢复顺序、强制检查点和禁止猜测原则。
- 归档验证：原任务记录的开头与末尾均已复读，历史 Tooltip、属性、建筑和输入链内容仍保留。
- 格式验证：7 个 Markdown 文件存在；限定路径 `git diff --check` 无报错；独立尾随空白检查无结果。
- 代码影响：没有修改游戏代码、配置、CSV 或 Panorama 源码，因此无需运行游戏代码测试或资源编译。
- 剩余风险：`docs/ai` 整体仍未被 Git 跟踪；界面关闭不会删除文件，但清理未跟踪文件仍可能删除这些文档。
- 尚未确认：断开前具体任务内容。
- 下一步唯一动作：请用户提供最小线索；收到后先追加检查点，再开始代码调查。
## 2026-07-28 — 检查点 004：恢复 Tooltip 完全自主控制需求

- 用户要求：Tooltip 完全由项目自主控制；方向是替换原生底部角色 UI，因为原生技能悬停会自动显示 Valve Tooltip。
- 上一轮用户约提供 10 张 Panorama 节点截图后会话断开。原图当前不可见，项目目录也未找到图片文件。
- 已发现替代证据：.cline_tmp 节点 ID、Tooltip 备份与 diff，以及历史自定义底栏。
- 本轮只分析与更新 docs/ai，不修改游戏 UI。

## 2026-07-28 — 检查点 005：Tooltip 全接管分析完成

- 当前根因：自定义 SurvivalHeroBottomHUD 被折叠；官方 abilities 可见且可命中；物品栏完全由官方 HUD 拥有。
- 当前普通技能调用 Valve Ability Tooltip；托管建筑技能用 0.08 秒循环压制原生 Tooltip；人物属性使用 Valve TitleText Tooltip。
- 可复用基础：历史技能槽采用 Button 加 DOTAAbilityImage 且图像 hittest=false；现有服务端输入链支持无目标与点目标。
- 结构风险：折叠 AbilitiesAndStatBranch 会破坏 flow 布局并导致物品栏滑位。
- 技能风险：单位目标、toggle、autocast 等行为未在自定义链中实现，必须先枚举验证。
- 物品风险：没有自定义主动使用、拖放、丢弃、出售或拆分链，不可直接隐藏官方物品栏。
- 推荐：先接管技能区与人物属性，再单独完成物品全交互接管，最后清理官方节点扫描与 Tooltip 压制。
- 下一步：等待用户确认首轮范围；推荐阶段 A 到 C。

## 2026-07-28 — 检查点 006：明确四类 Tooltip 接管目标与最小运行时证据

- 人物属性：保留官方攻击力等图标与当前权威数字显示，关闭官方悬停气泡，改由项目悬停代理显示自定义 Tooltip。
- 技能：关闭 Valve 技能 Tooltip 触发源，项目悬停显示自定义 Tooltip，同时保留点击、快捷键、冷却与等级等功能。
- 物品栏：使用项目 Tooltip，但必须保留物品主动使用、拖放、换位与其他原生交互。
- 地面掉落物：先调查世界物品官方 Tooltip 能否被替换；若不能，研究光标下世界实体检测与自定义屏幕 Tooltip 等替代方案。
- 当前源码候选：Damage；AbilityN 下的 AbilityButton、ButtonWell、AbilityImage；inventory_slot_N 及其 DOTAItemImage 后代。
- 地面物品事实：挑战奖励通过 CreateItemOnPositionSync 创建，并以物品实体 entindex 发布 survival_inventory_item_identity。
- 工具限制：助手不能直接连接用户当前运行中的 Panorama Debugger；需要最小定向截图与一次地面物品控制台诊断。
- 下一步：用户提供 Damage、Ability0、inventory_slot_0 三组展开树截图，以及地面掉落物悬停诊断。

## 2026-07-28 — 检查点 007：用户批准人物属性与技能接管试点

- 用户已把 `图片1.png` 至 `图片7.png` 放在桌面并按顺序提供；当前节点证据足够启动人物属性与技能试点，不再把额外 Debugger 截图作为开工前置条件。
- 用户批准推荐范围：阶段 0～3，即建立可回滚接管基线、人物属性 Tooltip 完全自定义、技能显示/悬停/鼠标输入完全接管，并在验证后清理对应旧兼容路径。
- 本轮明确不做：隐藏官方背包、重写物品主动使用/拖放/换位/丢弃，以及地面掉落物悬停；这些保留为后续独立阶段。
- `DOTAAbilityTooltip` 展开截图可在自定义骨架完成后用于视觉校准（标题、描述、费用、冷却、属性区及尺寸），但不能恢复 Valve 内部代码或替代项目 ViewModel。
- 安全边界：保留官方底栏几何与背包交互；技能项目代理必须位于原生 `AbilityN` 祖先树之外；未知 AbilityBehavior 不得误按无目标技能发送。
- 下一步：核对加载顺序与现有定位工具，实施 Panorama 试点，强制定向编译并输出实机验收矩阵。

## 2026-07-28 — 检查点 008：接口中断后的精确恢复状态

- 用户报告接口请求错误并要求继续执行；该错误发生在编辑工具请求期间，不是 Dota、资源编译器或项目代码的运行错误。
- 中断前已成功修改：`ui_bootstrap.js` 增加阶段开关（abilities/stats=true、inventory=false）；`ability_tooltip.js` 在技能接管模式下停止绑定 Valve AbilityN；`survival_hud.xml` 增加独立技能/属性代理层并加载 `hud_takeover.js`；`ability_tooltip.css` 增加接管层样式。
- 中断前未成功修改：`hero_stat_tooltip.js`。原因是补丁工具拒绝同一补丁中对同一路径先 Delete 再 Add；原文件应仍保持 Valve TitleText Tooltip 实现。
- 尚未创建/修改：`hud_takeover.js`、`combat_stats.js` 的普通技能订单分流；尚未执行任何 Panorama 编译。
- 恢复动作：先复读实际文件确认磁盘状态，再用普通 Update 修改属性 Tooltip，随后完成技能接管控制器、施法安全分流和强制编译。

## 2026-07-28 — 检查点 009：人物属性 Tooltip 源码接管已写入

- `hero_stat_tooltip.js` 已从 Valve `DOTAShowTitleTextTooltip` 事件改为项目 `CustomHeroStatTooltip` 面板。
- 属性输入代理位于独立 `SurvivalStatTakeoverLayer`，以官方 Damage/Armor/AttackSpeed 和项目三围覆盖行为几何锚点；锚点本身关闭命中，避免进入 Valve Tooltip 触发树。
- 属性内容仍只消费 `SurvivalCombatStatsStore` 的服务端投影；未新增客户端护甲单位换算。
- 已保留 `SetTakeoverEnabled()` 回滚入口；关闭后隐藏代理并恢复官方目标命中。
- 尚未编译或实机验证；下一步唯一动作是创建独立技能接管控制器。

## 2026-07-28 — 检查点 010：独立技能接管控制器已创建

- 新增 `hud_takeover.js`：自定义技能按钮位于 `SurvivalAbilityTakeoverLayer`，官方 AbilityN 仅作为几何锚点并保持 flow 占位；官方槽位使用 opacity=0 且关闭命中，不执行 collapse。
- 首版已实现可见能力枚举、图标、Q/W/E/R/T/Y/U 或 F2、等级、魔法费用、冷却数字/遮罩、被动/不可用/资源不足状态，以及 `SetEnabled(false)` 回滚入口。
- 控制器只调用统一 `SurvivalAbilityInput.ExecuteAbility`，本步骤未擅自改变服务端施法路由。
- 复核发现：旧 `ability_tooltip.js` 在接管模式下提前退出，其私有 render 不可复用；新控制器当前必须补上独立 Tooltip 渲染函数后才能认为悬停闭环完成。
- 尚未编译；下一步唯一动作：迁移必要的 Tooltip ViewModel 渲染到 `hud_takeover.js`，然后处理普通/托管技能安全施法分流。

## 2026-07-28 — 检查点 011：技能 Tooltip 渲染与安全施法分流已写入

- `hud_takeover.js` 已独立渲染 `CustomAbilityTooltip`，消费 `survival_ability_data`、`survival_tooltips` 和 `survival_ability_runtime`，显示名称、等级、描述、金币/木材费用、施法类型、魔法、冷却、运行时字段和状态。
- `combat_stats.js` 已增加托管身份/建筑白名单判定：托管无目标和建造点目标继续走服务端权威事件；普通无目标/点目标技能改走 Panorama 原生单位订单。
- 被动技能和未支持的单位目标/切换等 behavior 会安全拒绝并记录诊断，不再误按无目标技能发送。
- 点目标状态已增加 `managed` 标记；`ability_survival_return_home` 点击转到现有回城请求，并向新控制器公开 `SurvivalReturnHomeInput.Request`。
- 尚未编译；下一步唯一动作：完整复核职责链，修复任何物品 Tooltip 回归或 XML/API 对应问题后强制编译。

## 2026-07-28 — 检查点 012：编译前职责链复核完成

- 直接读取正式 `ability_tooltip.js` 后确认：正式文件当前只有技能绑定，没有背包物品绑定；物品代码只存在于 `.cline_tmp` 候选残留。因而接管模式下提前退出不会关闭正式物品绑定，官方背包仍完整由 Valve 负责。
- XML 中技能/属性代理层与两个项目 Tooltip 均位于项目 HUD 根层，且 `hud_takeover.js` 在 `combat_stats.js` 后加载，统一输入 API 在控制器启动前已建立。
- 修正被动/不可用技能悬停：自定义 Button 始终保持 enabled，点击回调内部拒绝施法，避免禁用 Button 导致 Tooltip 悬停丢失。
- 回滚边界仍为 `SurvivalHudTakeover.abilities/stats`；inventory 保持 false。
- 下一步唯一动作：强制编译所有改动 Panorama 资源并进行限定静态验证；失败时按单文件错误修复，不重跑未知状态写命令。

## 2026-07-28 — 检查点 013：终端类型差异导致编译命令未可靠执行

- 编译请求使用了 PowerShell `$rc = ...; & $rc` 语法，但终端桥接实际显示为 Git Bash；已捕获的明确结果是 `bash: syntax error near unexpected token '&'`，不能认定任何资源已重新编译。
- 同批后续命令出现输出捕获超时；按环境规则，必须先检查产物时间戳和残留 `resourcecompiler` 进程，禁止直接重复写命令。
- 静态复核进一步确认：正式 `ability_tooltip.js` 当前只有技能绑定，物品绑定只在 `.cline_tmp` 候选文件中；本轮官方背包职责没有被正式脚本接管或移除。
- 施法分流将收紧：普通非托管技能交还 `Abilities.ExecuteAbility`，由引擎继续处理普通点目标/单位目标/切换行为；只有托管建造和建筑操作使用项目自定义服务端事件。
- 下一步唯一动作：检查编译产物/进程状态，修正普通技能执行路径，再以 Git Bash 兼容命令逐个强制编译。

## 2026-07-28 — 检查点 014：技能与人物属性接管试点完成静态验收

- `ui_bootstrap.js` 的阶段开关最终为 abilities=true、stats=true、inventory=false；背包与地面物品不在本轮接管范围。
- 新增 `hud_takeover.js`，独立技能层覆盖官方 AbilityN 的实际几何；官方槽位保留 flow 占位但 opacity=0 且关闭命中。自定义槽负责图标、快捷键、等级、魔法、冷却、被动/不可用/资源不足状态、项目 Tooltip 和点击。
- `hero_stat_tooltip.js` 使用独立属性代理和 `CustomHeroStatTooltip`，消费服务端 `stat_tooltips` 投影，不触发 Valve TitleText Tooltip，也不改变结算单位边界。
- 最终施法分流：普通非托管技能使用 `Abilities.ExecuteAbility`；托管建筑无目标技能走 `ui_ability_cast_request`；托管建造点目标走 `ui_ability_cast_position_request`；回城走既有 `ui_return_home_request`。
- 强制编译结果：`ui_bootstrap.js`、`ability_tooltip.js`、`hero_stat_tooltip.js`、`combat_stats.js`、`hud_takeover.js`、`ability_tooltip.css` 均为 `OK: 1 compiled, 0 failed, 0 skipped`；`survival_hud.xml` 为 `OK: 7 compiled, 0 failed, 0 skipped`。
- 完整 7 个目标资源于 2026-07-28 16:02:47 编译；随后修复 Valve 重建 AbilityN 时的回滚状态缓存，并再次编译 `hud_takeover.vjs_c` 与 XML，最终时间戳为 16:06:08。XML 中 `CustomAbilityTooltip`、`SurvivalAbilityTakeoverLayer`、`SurvivalStatTakeoverLayer`、`CustomHeroStatTooltip` 均且仅出现一次；源码中无 `PrepareUnitOrders`/`dotaunitorder_t` 残留。
- 限制：当前 PATH 没有 node，未执行 `node --check`；Dota `resourcecompiler.exe` 已实际编译全部 Panorama JS。尚未进行游戏内视觉与输入验收。
- 下一步唯一动作：重新 Run 地图，依次验证英雄/建筑/农民、普通与托管技能、人物属性、官方背包、选择切换、分辨率/HUD 比例和第二次 Run；若失败，提供代理层/官方锚点 Debugger 截图与相关控制台日志。

## 2026-07-28 — 检查点 015：再次断开后的恢复确认

- 用户最新要求：界面再次断开，要求继续尝试恢复，不希望重新复述此前的深度讨论。
- 恢复依据：重新读取 `START_HERE.md`、`CURRENT_TASK.md`、`SESSION_LOG.md` 最近检查点和相关 `KNOWN_ISSUES.md`；没有使用跨会话记忆填补缺口。
- 新确认事实：上一轮聊天曾表示准备新增检查点并继续自动复核，但磁盘日志仍停在检查点 014，因此这些后续动作不能视为已经执行。
- 产物证据：`content/.../hud_takeover.js` 时间为 16:05:32；游戏目录 `hud_takeover.vjs_c` 与 `survival_hud.vxml_c` 时间均为 16:06:08，与检查点 014 一致。没有发现断开后新增的本轮源码或编译结果。
- 当前可靠状态：阶段 0～3 的源码实施与强制编译已经完成；技能和人物属性由项目代理层接管，官方背包仍由 Valve 负责。
- 尚未验证：Workshop Tools 中的视觉对齐、项目 Tooltip、鼠标与快捷键施法、英雄/建筑/农民选择切换、HUD 比例/分辨率变化、官方背包交互和第二次 Run。
- 已排除：不把编译成功冒充实机通过；不在没有实机异常证据时继续猜测性修改布局；不接管本轮范围外的物品栏与地面物品。
- 下一步唯一动作：在 Workshop Tools 重新 Run 地图，按 `CURRENT_TASK.md` 验收标准 1～8 实机验证；若失败，记录对应代理层/官方锚点截图与 `[SURVIVAL_TAKEOVER]`、`[SURVIVAL_CAST]` 日志后再进行定向修复。

## 2026-07-28 — 检查点 016：用户批准按恢复计划执行

- 用户最新要求：在重新读取持久化上下文并复述恢复计划后，明确选择“按上述恢复计划开始执行”。
- 当前可靠起点：阶段 0～3 源码实施与强制编译已完成；技能和人物属性由项目代理层接管，官方背包仍由 Valve 负责。
- 本轮执行边界：先做非破坏性静态复核和 Workshop Tools 实机验收；只有获得明确的游戏内异常、节点坐标或 `[SURVIVAL_TAKEOVER]`/`[SURVIVAL_CAST]` 日志证据后才定向修改。
- 禁止事项：不执行全局 reset/checkout/clean；不覆盖工作区其他任务修改；不把物品栏或地面物品接管混入本轮。
- 尚未验证：英雄、建筑、农民的代理层几何和 Tooltip，全部技能输入类型，人物属性 Tooltip，官方背包交互，选择切换、HUD 比例/分辨率变化及第二次 Run。
- 下一步唯一动作：复核 7 个接管相关 Panorama 源资源、加载顺序和编译产物，然后进入 Workshop Tools 验收矩阵。

## 2026-07-28 — 检查点 017：接管静态复核完成，进入实机验收

- 已复核接管开关：`SurvivalHudTakeover` 为 `abilities=true`、`stats=true`、`inventory=false`。
- 已复核加载顺序：`ui_bootstrap.js` 先建立开关，旧 `ability_tooltip.js` 在技能接管模式下停止绑定 Valve `AbilityN`，随后加载属性代理、统一输入控制器和 `hud_takeover.js`。
- 已复核职责边界：技能和人物属性由独立代理层负责；官方背包没有启用项目接管，仍保留 Valve 输入与物品 Tooltip。
- 编译产物证据：7 个目标产物均存在且大小非零；时间戳统一为 `2026-07-28 16:06:08`，与检查点 014/015 一致。
- XML 唯一性证据：`CustomAbilityTooltip`、`SurvivalAbilityTakeoverLayer`、`SurvivalStatTakeoverLayer`、`CustomHeroStatTooltip` 均且仅出现一次。
- 本轮没有修改 Panorama 源码、CSS 或 XML，只追加恢复日志，因此无需因本轮记录变更重新编译资源。
- 工具限制：终端桥接再次对部分只读命令出现 30 秒无输出超时，无法据此判断 Dota 进程状态；助手也无法直接观察 Workshop Tools 可视界面。不能把静态复核冒充实机通过。
- 下一步唯一动作：用户在 Workshop Tools 重新 Run 地图并执行 `CURRENT_TASK.md` 验收标准 1～8；按首个失败类别返回画面/日志后再定向修复，若全部通过则记录最终验收并归档任务。

## 2026-07-28 — 检查点 018：实机发现技能槽几何与箭塔转职失败

- 用户实机结果：英雄、建筑、农民的全部技能槽位置异常；箭塔 5 级无法完成转职升级。
- 事实与推断边界：全单位共同偏移表明共享坐标系、UI scale 或接管层根节点几何是首要调查方向，但尚未获得节点坐标截图，不能直接断言具体偏移量。箭塔转职失败可能发生在客户端能力映射、托管请求、服务端路由、资源扣费或升级任务中的任一环节，尚未定位。
- 本轮调查边界：分别追踪 Panorama 技能代理定位链和箭塔 5 级转职完整调用链；不修改官方背包或地面物品。
- 下一步唯一动作：读取技能代理坐标实现、XML/CSS 根层结构、箭塔转职技能配置与服务端路由，结合相关 diff 找到可验证的根因；若代码不足以确定几何根因，再索取最小 Panorama Debugger 坐标证据。

## 2026-07-28 — 检查点 019：确认技能锚点查找回归，准备定向修复

- 已确认技能几何共同根因候选：正式 `hud_takeover.js` 使用 HUD 根节点直接 `FindChildTraverse("AbilityN")`；旧节点调查实现则先限定到官方 `abilities` / `AbilitiesAndStatBranch` 容器。HUD 中同名节点可能来自隐藏模板或其他分支，全树首个匹配不能作为可见技能槽锚点。
- 修复策略：新增官方技能容器解析函数，只在该容器内查找 `AbilityN`；每次刷新重新解析以兼容 Valve HUD 重建，不缓存跨 Run 节点。
- 箭塔链已确认：5 级会添加并激活 `ability_tower_class_1..7`；客户端将其识别为托管无目标技能；服务端校验后发送 `TOWER_CLASS_REQUEST`；`building_upgrade_system` 消费事件并执行权威扣费与路线切换。
- 当前未确认：箭塔失败是否只是错误代理位置导致点击错位，或服务端仍有独立失败。没有 `[SURVIVAL_CAST]` 日志前不改权威转职逻辑。
- 下一步唯一动作：确认 5 级箭塔可见技能数量后修改技能锚点解析，强制编译 `hud_takeover.js` 与 HUD XML，并复测全单位位置和箭塔转职。

## 2026-07-28 — 检查点 020：官方技能容器锚点修复已编译

- 已修改 `content/.../hud_takeover.js`：新增 `officialAbilitiesContainer()`，优先从 `AbilitiesAndStatBranch` 内解析官方 `abilities` 容器；`AbilityN` 只在该容器内查找，不再使用整个 HUD 树的首个同名节点。
- HUD 重建兼容：容器与槽位每次刷新重新解析，不缓存跨 Run 的 Valve 节点；新增 `[SURVIVAL_TAKEOVER] anchor_state=` 状态变化诊断，可区分容器缺失、特定槽缺失和可用槽数量。
- 已确认 5 级基础箭塔会移除两个普通升级能力并显示 7 个转职能力，正好对应 Q/W/E/R/T/Y/U；配置没有第 8 个无锚点能力。
- 编译证据：定向 `hud_takeover.js` 为 `OK: 1 compiled, 0 failed, 0 skipped`；HUD XML 加载链为 `OK: 7 compiled, 0 failed, 0 skipped`。
- 最终产物：`hud_takeover.vjs_c` 与 `survival_hud.vxml_c` 时间戳均更新为 2026-07-28 17:52:14，大小分别为 20357 和 8028 字节。
- 尚未修改箭塔权威转职逻辑：现有代码已具备 5 级按钮添加、客户端托管分流、服务端 `TOWER_CLASS_REQUEST` 路由与消费者；需先排除技能代理错位导致的点击错误。
- 下一步唯一动作：停止当前 Run 后重新 Run，复测英雄/建筑/农民技能槽位置和 5 级箭塔转职；若位置恢复但转职仍失败，收集 `[SURVIVAL_CAST]` 与 UI 通知后定向修复服务端链。

## 2026-07-28 — 检查点 021：箭塔转职恢复，技能几何仍异常

- 用户复测结果：技能槽位置仍异常，但箭塔 5 级转职已经恢复。
- 已确认：箭塔服务端权威转职链无需修改；先前失败由错误锚点/点击代理错位引起，官方技能容器限定修复已恢复实际点击目标。
- 剩余唯一故障：英雄、建筑、农民共用的技能代理几何仍不正确。
- 根因范围：`placeOverOfficial()` 的窗口坐标与 UI scale 换算、代理层局部坐标空间，或官方容器内最终锚点层级；没有偏移方向、尺寸和节点坐标证据前不能安全写固定补偿。
- 下一步唯一动作：复核完整几何算法并恢复桌面节点截图；若旧材料不足，采集一张当前 `SurvivalAbilityTakeoverLayer` 与对应 `AbilityN` 的 Panorama Debugger 几何截图或等价坐标日志。

## 2026-07-28 — 检查点 022：一次性技能几何诊断已编译

- 已核对用户提供的 7 张旧 Panorama Debugger 截图：确认官方 `Ability0`、`Damage`、`inventory_slot_0` 节点树，但截图没有运行时几何属性，无法计算当前偏移。
- 已确认 XML/CSS：`SurvivalAbilityTakeoverLayer` 是 `SurvivalHUDRoot` 的直接子节点，声明为全屏 `100% x 100%`、`position: 0 0`。
- 已在 `hud_takeover.js` 增加状态去重的 `[SURVIVAL_GEOMETRY]` 诊断，仅记录 `Ability0`：官方槽与父节点、窗口坐标、布局尺寸、UI scale；接管层与父节点；计算局部矩形；自定义槽应用后的实际窗口坐标与尺寸。
- 诊断不会改变现有几何公式，不会修改技能输入或箭塔逻辑；仅在几何签名变化时输出，避免 0.5 秒刷新刷屏。
- 写入期间终端曾返回瞬时 2635 字节状态；随后已确认源文件完整闭合，共 528 行 / 22635 字节，不存在截断。
- 编译证据：诊断版 `hud_takeover.js` 为 `OK: 1 compiled, 0 failed, 0 skipped`；HUD XML 加载链为 `OK: 7 compiled, 0 failed, 0 skipped`。
- 下一步唯一动作：停止当前 Run 后重新 Run，复制首条完整 `[SURVIVAL_GEOMETRY]` 日志；据此修正窗口坐标到代理层局部坐标的公式。

## 2026-07-28 — 检查点 023：确认锚点层级错误，用户批准原版 UI 调查模式

- 用户提供完整日志：官方 `Ability0` 与自定义槽窗口左上角均为 `723,1200`，证明 `GetPositionWithinWindow()`、代理层原点及当前位置换算能够对齐左上角；此前优先怀疑全屏坐标系的方向已被证据排除。
- 日志同时显示官方 `Ability0` 为 `72x200`、自定义实际为 `80x222`、双方 UI scale 为 `1.111111...`。事实：`Ability0` 是远高于技能图标的复合外壳；推断：其内包含图标、按钮、升级等多个组件，不能作为最终按钮矩形。另有重复尺寸缩放风险，需要子节点数据继续确认。
- 旧调查代码保留候选顺序 `AbilityButton -> ButtonWell -> AbilityImage -> AbilityN`，进一步支持应调查内部可见/可点击子节点，而非继续为 `AbilityN` 写固定补偿。
- 用户明确批准：先只实施“恢复原版技能 UI + 自动日志”的调查模式；在数据出来前不修改正式接管几何公式，不提前决定升级按钮的最终接管方式。
- 已开始实施临时 `abilitySurvey` 开关：调查模式恢复官方技能槽、隐藏自定义代理，并准备自动输出 `Ability0` 完整子树与所有槽位的 `AbilityButton`/`ButtonWell`/`AbilityImage` 候选摘要。
- 下一步唯一动作：完成源码复核与强制编译；用户重新 Run 后采集英雄有技能点、农民/普通建筑、5 级七技能箭塔三种原版 UI 状态的调查日志与截图。

## 2026-07-28 — 检查点 024：原版技能 UI 调查模式已完成并强制编译

- `ui_bootstrap.js` 的 `SurvivalHudTakeover` 新增临时 `abilitySurvey: true`。调查模式不进入正式 `ensureSlot/placeOverOfficial/suppressOfficial` 路径，恢复 Valve `AbilityN` 显示与命中并折叠现有自定义技能代理。
- `hud_takeover.js` 新增自动调查日志：`[SURVIVAL_ABILITY_SURVEY_BEGIN]`、`[SURVIVAL_ABILITY_SLOT]`、`[SURVIVAL_ABILITY_CANDIDATE]`、`[SURVIVAL_ABILITY_TREE]`、`[SURVIVAL_ABILITY_SURVEY_END]`。
- `Ability0` 递归子树逐节点输出路径、类型、classes、窗口坐标、布局尺寸、UI scale、offset、可见性、CSS opacity/visibility、命中状态、CSS position/size 和子节点数量；所有可见槽额外输出 `AbilityButton`、`ButtonWell`、`AbilityImage` 候选摘要。
- 日志按选中单位、技能列表、树结构和候选几何签名去重；缺失 `Ability0` 状态也去重。可调用 `GameUI.CustomUIConfig().SurvivalAbilityTakeover.DumpSurvey()` 强制重新导出。
- 可靠性处理：`GetClasses()` 同时兼容数组与字符串；调查模式不永久改写自定义槽命中属性；NetTable 监听在调查模式下不再更新旧代理槽。
- 编译证据：`ui_bootstrap.js` 为 `OK: 1 compiled, 0 failed, 0 skipped`；`hud_takeover.js` 为同样结果；HUD XML 加载链为 `OK: 7 compiled, 0 failed, 0 skipped`。
- 调查边界：没有修改正式技能定位公式、技能输入路由、人物属性接管、箭塔权威逻辑或 Valve 原生物品栏。
- 下一步唯一动作：用户停止并重新 Run，依次采集有未分配技能点的英雄、农民/普通建筑、5 级七技能箭塔的原版底栏截图及对应完整同编号调查日志。

## 2026-07-28 — 检查点 025：首份原版 Ability0 子树样本已取得

- 用户提供了单位 `489`、唯一可见技能 `ability_build_wall` 的完整调查日志，包含 `dump=1` 与 `dump=2`，每份均有 87 个 `Ability0` 子树节点和完整 BEGIN/END。
- `dump=1` 发生于 `initial_0.35`，`Ability0` 窗口 Y 为 `1200`；随后 `dump=2` 在 `geometry_tick` 稳定为 Y=`944`，其所有内部节点同步上移 256。结论：首个 dump 是 HUD 布局中的瞬时状态，后续应以稳定后的 `dump=2` 为几何依据。
- 稳定样本确认：`Ability0` 是 `72x200` 的复合容器，窗口位置 `723,944`；真正按钮热区 `AbilityButton` 为 `70x71`，窗口位置 `725,1045`，`hittest=true`；`ButtonWell` 与它矩形完全相同但 `hittest=false`；`AbilityImage` 是内部留边后的 `54x55`，窗口位置 `733,1053`。
- 节点职责已确认：`LevelUpTab` 是按钮区域上方的独立兄弟组件，稳定矩形 `70x40 @ 725,1000`；`AbilityLevelContainer` 是独立等级点区域 `13x10 @ 753,1116`；`HotkeyContainer`、`AbilityCharges` 与 `ButtonWell` 同属 `ButtonWithLevelUpTab` 下的兄弟节点。
- 因此正式代理的首选几何锚点应为 `AbilityButton`（回退 `ButtonWell`），不是 `AbilityImage`，更不是 `Ability0`。`AbilityImage` 仅代表图像内芯，若以它为按钮会丢失边框与完整点击热区。
- 尺寸证据继续支持重复缩放判断：锚点的 `actuallayoutwidth/height=70x71` 是窗口实际矩形；代理层本地 CSS 尺寸应除以代理层累计 UI scale，而不应再次乘源节点 scale。
- 正式隐藏边界不能继续把整个 `Ability0` 设为 opacity 0，否则会一并隐藏 `LevelUpTab` 和等级点。后续需按组件隐藏 `ButtonWell`/按钮视觉，并单独决定 Hotkey、Charges、LevelUpLight 等兄弟组件的保留或替换。
- 尚未验证：该样本对应用户所述三类状态中的哪一类；英雄多技能/未分配技能点、普通建筑和 5 级七技能箭塔是否维持相同 `AbilityButton` 结构与尺寸。
- 下一步唯一动作：确认本样本的单位类别并继续采集剩余两类状态；在至少取得七技能箭塔的所有候选槽摘要前，不提交正式锚点修复。

## 2026-07-28 — 检查点 026：首份样本确认为农民/建造单位

- 用户确认检查点 025 的 `ability_build_wall` 样本来自农民/建造单位。
- 农民单槽结构已验证：`AbilityButton` 是完整 `70x71` 按钮热区，`ButtonWell` 同矩形，`AbilityImage` 是内部 `54x55` 图像；`LevelUpTab` 与等级点属于 `Ability0` 内独立组件。
- 当前不需要再次采集农民完整 87 节点子树。后续状态若候选路径和尺寸相同，只需 BEGIN、SLOT、CANDIDATE、END 与底栏截图；仅在树结构或候选节点缺失时再导出完整 TREE。
- 下一优先样本为 5 级七技能箭塔，用于验证 `Ability0..Ability6` 的横向位置、尺寸、间距、候选节点存在性，以及七槽布局是否缩放或压缩。
- 在七技能箭塔样本取得前不修改正式接管；普通英雄样本用于随后确认原生升级组件和英雄多技能布局。
- 下一步唯一动作：选中 5 级七技能箭塔，强制或自动导出一次稳定调查日志，并提供 BEGIN、7 条 SLOT、21 条 CANDIDATE、END 和一张底栏截图。

## 2026-07-28 — 检查点 027：5 级七技能箭塔布局已确认

- 用户提供稳定 `dump=16`：单位 `226`，7 个可见转职技能，BEGIN/END 完整，包含 7 条 SLOT、21 条候选节点和 `Ability0` 完整 87 节点树。
- 七个外层槽 `Ability0..Ability6` 的窗口 X 依次为 `680,744,808,872,936,1000,1064`，固定步长 `64`；每个外层槽均为 `64x200`。这证明 Valve 在七技能布局中按技能数量压缩槽宽。
- 七个 `AbilityButton` 的窗口 X 依次为 `683,747,811,875,939,1003,1067`，固定步长 `64`；全部为 `60x60`、Y=`1048`、`hittest=true`。按钮之间实际窗口间隙为 `4`。
- 七个 `ButtonWell` 与对应 `AbilityButton` 矩形完全相同，均为 `60x60`，但 `hittest=false`；七个 `AbilityImage` 均为 `54x54`，相对按钮内缩 `3px`。
- 与农民单槽样本对比：农民 `AbilityButton=70x71`、外层槽 `72x200`；七技能箭塔 `AbilityButton=60x60`、外层槽 `64x200`。结论：按钮大小、外层槽宽、图像留边会随可见技能数量动态变化，正式实现不得写死固定像素尺寸。
- 节点路径在农民与七技能箭塔中保持一致：`AbilityN/ButtonAndLevel/ButtonWithLevelUpTab/ButtonWell/ButtonSize/AbilityButton`。因此首选锚点规则稳定为 `AbilityButton`，回退 `ButtonWell`；布局位置和尺寸必须每槽实时读取。
- 七技能 `Ability0` 中 `LevelUpTab=60x40 @ 683,1001`，`ButtonWell=60x60 @ 683,1048`；它们仍是兄弟组件。继续确认不能把整个 `AbilityN` 隐藏，否则会同时破坏升级区域及其他官方组件。
- 尺寸换算应直接从锚点窗口实际尺寸进入代理层局部单位：`localWidth = anchor.actuallayoutwidth / layer.actualuiscale_x`、`localHeight = anchor.actuallayoutheight / layer.actualuiscale_y`。位置仍使用 `(anchorWindow - layerWindow) / layerScale`。
- 正式修复方案已具备两项核心证据：动态选择内部 `AbilityButton` 锚点；移除源 scale 的重复尺寸乘法。尚需普通英雄样本确认英雄多技能布局、升级按钮可见状态及是否维持同一路径。
- 下一步唯一动作：采集一个有多个技能、最好有未分配技能点的普通英雄稳定 dump；只需 BEGIN、SLOT、CANDIDATE、END，并说明升级加号是否可见。之后即可实施正式自适应接管修复。

## 2026-07-28 — 检查点 028：普通英雄样本不要求激活升级加号

- 用户说明：项目当前尚未实现用于增加英雄经验值的调试命令，因此现阶段只能采集“没有未分配技能点”的多技能英雄；无法方便地让原版升级加号进入可点击状态。
- 决定：不为本轮几何调查临时增加经验值/升级调试命令，避免把服务端调试功能混入技能代理锚点修复。
- 没有未分配技能点的多技能英雄仍足以验证：英雄 `AbilityN` 与 `AbilityButton` 路径、可见槽数量、动态按钮尺寸、横向步长、每槽候选节点存在性，以及与农民/七技能箭塔的结构一致性。
- 升级按钮激活态不再作为正式几何修复的前置条件。现有证据已确认 `LevelUpTab` 是 `AbilityButton` 上方的独立兄弟组件；正式修复不得覆盖或整体隐藏该区域。
- 未验证项单独保留：英雄获得未分配技能点后，原版 `LevelUpTab` 的显示、命中和升级操作是否正常。该项应在经验/升级链可测试后纳入功能验收，而不是阻塞当前锚点修复。
- 下一步唯一动作：采集一个没有未分配技能点的多技能普通英雄稳定 dump，只需 BEGIN、所有 SLOT、所有 CANDIDATE、END，并提供一张底栏截图或说明可见技能数量。

## 2026-07-28 — 检查点 029：普通英雄样本完成，批准的几何调查具备实施条件

- 用户提供全能骑士单位 `323` 的完整 `dump=1/2`。稳定样本为 `dump=2`：4 个官方技能槽 `Ability0..Ability3`，外层均为 `72x200`，窗口 X=`771,843,915,987`、步长 `72`。
- 当前 `visibleAbilities()` 错误枚举出 12 个条目：4 个真实技能加 8 个 `special_bonus_*` 天赋；官方 HUD 只创建 4 个 `AbilityN`。正式修复必须过滤天赋，否则代理列表、快捷键和缺失锚点诊断都会错误。
- 英雄槽 0、1、3 的 `AbilityButton=70x71`；槽 2 的被动技能 `omniknight_hammer_of_purity` 为 `AbilityButton=64x64 @ 919,1048`，而同槽 `ButtonWell` 仍为 `70x71 @ 917,1045`。结论：即使同一英雄同一排，真实按钮矩形也可因技能表现类型不同；必须逐槽读取 `AbilityButton`，不能以 `ButtonWell` 或槽数量统一推算。
- 英雄 `Ability0` 路径与农民/箭塔一致；`LevelUpTab=70x40 @ 773,1000`，是按钮上方独立兄弟组件。日志中的 `LevelUpBurstFXContainer`、`LevelUpTab` 和 `LevelUpButton` 均为 visible，说明升级相关区域确实独立存在，正式接管不得整体隐藏 `AbilityN`。
- 三类样本现已齐全：农民单槽、七技能箭塔、四技能英雄（含不同尺寸被动槽）。调查结果足以实施正式自适应修复；无需继续收集布局数据。
- 实施方案：关闭 `abilitySurvey`；过滤 `special_bonus_*`；每槽选择 `AbilityButton || ButtonWell`；位置使用窗口差除代理层 scale；尺寸使用锚点 `actuallayoutwidth/height` 除代理层 scale；仅抑制 `ButtonWell`/按钮区域与项目已替代的官方热键/等级视觉，保留 `LevelUpTab`。
- 下一步唯一动作：修改 `ui_bootstrap.js` 与 `hud_takeover.js`，强制编译 JS/XML，重新 Run 验证英雄、农民和七技能箭塔的对齐、Tooltip、点击与升级区域保留情况。

## 2026-07-28 — 检查点 030：自适应技能按钮锚点修复已实施并编译

- 用户澄清全能骑士样本是存在未分配技能点的状态。日志也提供直接证据：英雄 `LevelUpBurstFXContainer=visible true, 72x89` 并生成 `LevelUpBurstFX` 场景节点；此前农民样本该容器为 `visible=false, 0x0`。因此升级提示激活态已经采集，无需再为本轮调查增加经验命令。
- `ui_bootstrap.js` 已将临时 `abilitySurvey` 默认值切回 `false`，恢复正式技能代理；调查代码和 `SetSurveyEnabled`/`DumpSurvey` 接口保留为可回滚诊断入口。
- `visibleAbilities()` 已过滤名称以 `special_bonus_` 开头的天赋。全能骑士正式代理将只映射 4 个真实官方槽，不再错误创建/诊断 8 个天赋槽。
- 新增 `officialAbilityAnchor(panel)`：逐槽优先选择内部 `AbilityButton`，缺失时回退 `ButtonWell`，最终才回退外层面板。英雄被动槽的 `64x64`、普通技能的 `70x71`、七技能箭塔的 `60x60` 都会分别按实测矩形处理。
- `placeOverOfficial()` 已移除源节点 scale 的重复乘法。位置公式为 `(anchorWindow-layerWindow)/layerScale`；CSS 本地尺寸为 `anchor.actuallayoutwidth/height / layerScale`，保留三位小数以减少 UI scale 取整误差。
- 官方压制从“整个 `AbilityN` opacity=0 且关闭全部命中”改为仅压制项目已经替代的 `ButtonWell`、`HotkeyContainer`、`AbilityCharges`、`AbilityLevelContainer`。`LevelUpTab`、`LevelUpButton`、`LevelUpBurstFXContainer` 未被压制，升级加号和提示区域得以保留。
- 官方状态存储改为每槽多节点数组，切回调查模式或关闭接管时可逐节点恢复 opacity/hittest/hittestchildren。
- 编译证据：`ui_bootstrap.js` 为 `OK: 1 compiled, 0 failed, 0 skipped`；`hud_takeover.js` 同样通过；HUD XML 加载链为 `OK: 7 compiled, 0 failed, 0 skipped`。
- 静态边界：未修改人物属性接管、技能输入路由、箭塔权威逻辑、物品栏或服务端经验功能。实机视觉、Tooltip、点击和升级按钮命中仍需重新 Run 验收。
- 下一步唯一动作：停止并重新 Run，依次选择有未分配技能点的英雄、农民和 5 级七技能箭塔；检查自定义按钮是否逐槽精确覆盖、无放大偏移、Tooltip/点击正常且英雄升级加号仍显示可点击。

## 2026-07-28 — 检查点 031：实机仍加载修复前技能几何代码

- 用户重新实机测试后提供截图与完整日志：`official=Ability0 source=723,1200 source_size=72x200 source_scale=1.111111... calculated=651,1080 72x200 custom_actual=723,1200 custom_size=80x222`。截图中单个技能代理仍纵向覆盖整个复合槽，图标下方存在大块黑色区域。
- 事实：日志中官方与自定义左上角同为 `723,1200`，再次证明窗口位置到代理层局部位置的换算正确；当前错误仍是外层 `Ability0` 锚点与重复尺寸缩放。
- 事实：磁盘上的正式 `content/.../hud_takeover.js` 已优先选择 `AbilityButton`，尺寸使用 `anchor.actuallayoutwidth/height / layerScale`，且诊断函数接收该内部锚点。若运行的是当前源码，日志不应再出现 `official=Ability0 source_size=72x200 custom_size=80x222`。
- 结论：本次日志来自修复前的运行时代码；不是新自适应公式产生的新几何错误。当前 Run/HUD 上下文没有加载最新 `hud_takeover.vjs_c`，或加载到旧缓存/旧产物。
- 下一步唯一动作：重新强制编译 `ui_bootstrap.js`、`hud_takeover.js` 与 `survival_hud.xml` 加载链，确认零失败后完全停止当前 Run 再启动；新日志必须先确认 `official=AbilityButton`，然后才继续判断视觉几何。

## 2026-07-28 — 检查点 032：用户批准底栏 UI 收尾新范围

- 用户最新实机基线：当前截图中的技能代理已显示，但技能槽缺少清晰边框；由于未重新启动 Workshop Tools，截图保持当前运行时原样，用户明确要求按此继续。
- 新 Bug：第一座箭塔升到 5 级后，转职技能开始是亮的，稍后置灰；第二座箭塔升到 5 级再转职正常。
- 新范围：继续物品栏项目气泡 UI；角色栏攻击、护甲、攻速、力量、敏捷、智力的悬停详细 Tooltip 整体删除，以减少工作量。
- 保留边界：角色栏图标与权威数值继续保留；官方背包的使用、拖放、换位、丢弃和出售继续由 Valve 负责；地面掉落物 Tooltip 不进入本轮。
- 已确认事实：客户端技能代理只在 Runtime `removed=1` 或 `available=0` 时置灰；项目已有 `survival_inventory_item_identity`、`survival_item_tooltips` 和 `tooltip_view_model` 数据基础。
- 当前推断：箭塔“稍后置灰”很可能来自延迟 Runtime 快照或错误/过期的单位状态；具体根因尚未通过测试确认。
- 已排除：不通过 CSS 强制保持转职技能点亮；不为了物品气泡重写官方背包输入；不删除 `combat_stats.js` 的权威数值显示链。
- 工作区风险：存在大量本任务之外的修改和未跟踪文件；后续只编辑明确相关文件，不执行全局 reset/checkout。
- 用户决策：已批准按“检查点 → 箭塔测试/根因 → 技能边框 → 删除属性 Tooltip → 独立物品气泡 → 编译测试”的计划执行。
- 下一步唯一动作：读取实际 Panorama、Runtime、建筑升级与测试文件，先建立首座/第二座箭塔延迟刷新回归测试。

## 2026-07-28 — 检查点 033：首座箭塔延迟置灰根因已测试并修复

- 新测试序列：同队两座箭塔；第一座 Runtime 缓存仍为 1 级，但单位实体已达到 5 级；第二座正常为 5 级；随后触发延迟 `RESOURCE_CHANGED` 全队刷新。
- 修复前证据：`test_tower_upgrade_runtime_refresh.lua` 明确失败于“first tower class ability regressed to unavailable after delayed refresh”。
- 根因：`ability_runtime_service.lua` 在资源事件中直接重发 `state_by_unit` 缓存；箭塔升级系统虽已先写 `unit.survival_level` / `unit.survival_tower_class`，Runtime 发布前没有与实体权威字段对账。
- 修复：仅对箭塔在每次 Runtime 发布前读取自身实体的权威等级、路线与显示名；不改变 `tower_class()` 可用规则，不用客户端 CSS 强制点亮，也不共享两座塔的状态。
- 修复后证据：扩展后的 `TOWER_UPGRADE_RUNTIME_REFRESH_PASS` 通过；首塔和第二塔的 `owner_entindex`、`current_level=5`、`available=1` 均分别断言。
- 尚未完成：技能边框、属性 Tooltip 删除、独立物品 Tooltip Panorama 实施与编译。
- 下一步唯一动作：按已确认职责边界完成限定 Panorama 编辑，然后强制定向编译和回归测试。

## 2026-07-28 — 检查点 034：底栏 UI 收尾实施与自动验证完成

- 技能边框：`ability_tooltip.css` 的代理槽改为 2px 浅色边框与暗色阴影；hover 使用金色边框和光晕；被动、资源不足继续有独立边框状态。
- 属性 Tooltip：删除 `hero_stat_tooltip.js`，从 HUD XML 移除脚本、`SurvivalStatTakeoverLayer` 和 `CustomHeroStatTooltip`，删除对应 CSS 和旧 `hero_stat_tooltip.vjs_c`；`combat_stats.js` 仍写入攻击、护甲、攻速与三围权威数字。
- 物品气泡：新增 `inventory_tooltip.js`、`inventory_tooltip.css` 和 `CustomInventoryItemTooltip` XML；静态字段读取 `survival_item_tooltips`，身份读取 `survival_inventory_item_identity`，动态成长读取 `survival_weapon_snapshot.tooltip_view_model.items[content_id]`。
- 交互边界：控制器只设置 `onmouseover/onmouseout`，不设置 `onactivate`，不关闭槽或 ItemImage 命中，不创建覆盖背包的代理层；绑定恢复只扫描 6 个槽并由初始有限重试、选择变化、身份/快照变化和鼠标移出触发。
- 原生物品 Tooltip 压制：悬停当帧与 50ms 后有限隐藏一次，不使用 0.03/0.35 秒永久循环。
- Panorama 编译：`ui_bootstrap.js`、`combat_stats.js`、`inventory_tooltip.js`、`ability_tooltip.css`、`inventory_tooltip.css` 均获得 `1 compiled, 0 failed, 0 skipped`；最终 HUD XML 加载链获得 `7 compiled, 0 failed, 0 skipped`。
- Lua 验证：`ALL_LUA_TESTS total=30 failed=0`；箭塔定向测试通过；相关 Lua 文件 `luac -p` 通过。
- 静态验证：game/content 两侧限定 `git diff --check` 均无空白错误，仅有既有 LF/CRLF 提示；新编译产物均存在且非空，旧属性 Tooltip 产物不存在。
- 尚未验证：助手无法直接观察 Workshop Tools；技能边框视觉、Valve 物品 Tooltip 是否在当前 HUD 版本完全消失、物品使用/拖放/换位/丢弃/出售，以及两座真实箭塔延迟状态仍需重新 Run 实机确认。
- 下一步唯一动作：完全停止并重新 Run，按 `CURRENT_TASK.md` 的四组实机项目验收；若物品仍出现双 Tooltip，提供官方槽展开树与截图，不要用关闭 ItemImage 命中作为修复。

## 2026-07-28 — 检查点 035：属性 Tooltip 删除边界补齐

- 最终复核发现：只删除自定义属性代理仍可能让 Valve 的 `Damage`、`AttackSpeed`、`Armor` 节点恢复原生悬停 Tooltip。
- 补丁：`combat_stats.js` 在保留三个节点可见、图标和权威数字覆盖的同时，将它们设为 `hittest=false`、`hittestchildren=false`；三围项目行原本就是非命中。
- 该补丁不创建属性代理、不显示 Tooltip、不改变服务端快照或任何结算值。
- 编译证据：最终 `combat_stats.js` 为 `1 compiled, 0 failed, 0 skipped`；HUD XML 加载链为 `7 compiled, 0 failed, 0 skipped`。
- 恢复文档已同步清理旧冲突：不再把 `hero_stat_tooltip.js`、`SurvivalStatTakeoverLayer` 或属性 Tooltip 作为当前实现/待验收项。
- 下一步唯一动作不变：完全停止并重新 Run，执行底栏视觉、双塔 Runtime、背包气泡/操作和无属性 Tooltip 实机验收。

## 2026-07-28 — 检查点 036：批准专属真实地面物品方案

- 用户最终问题：地面物品 Tooltip 若只能由官方 UI 可靠显示，是否可直接创建一个能被官方 Tooltip 识别的真实物品；并询问 `ItemLaunch` 是否可用于此目的。
- 已确认：`CreateItem` 创建已注册的真实 Dota item ability，`CreateItemOnPositionSync` 创建承载它的地面物理容器；官方世界 Tooltip 根据引擎物品名读取 KV 和本地化。`ItemLaunch` 类接口只负责掉落运动/动画，不负责运行时定义新物品。
- 当前根因：`challenge_equipment_reward_service.lua` 对所有挑战材料统一创建 `item_survival_challenge_reward`，所以官方 Tooltip 只能显示笼统的“挑战奖励”。
- 已确认基础：项目已有合成宝石、熔火核心 Lv1～Lv4、冰魂焰魄六个专属壳 KV 与本地化；但这些壳当前只是视觉类，真正的采用、库存登记、合并和自动合成逻辑只在通用奖励的 `Claim()` 中。
- 配置决策：在 `data/csv/物品系统/item_definitions.csv` 增加 `engine_item_name`，复用武器表已有模式；通用 CSV 生成器会自动透传新增列，不创建第二份手写映射。
- 安全决策：新地面奖励带 `survival_ground_reward=true`，成功登记后清除；拾取入口不能只按专属物品名判断，否则玩家把已有材料丢下再捡会复制逻辑库存。
- 用户批准：按完整方案实施“专属真实地面物品 + 官方地面 Tooltip + 项目背包 Tooltip”；不实施世界鼠标实体轮询。
- 下一步唯一动作：实施 CSV 映射、共享 Claim、专属掉落和拾取回归测试，并完成全量自动验证。

## 2026-07-28 — 检查点 037：专属真实地面物品实施完成

- 配置：`data/csv/物品系统/item_definitions.csv` 新增末尾列 `engine_item_name`；六种材料映射到 `item_survival_synthesis_gem_shell`、熔火核心 01～04 壳和 `item_survival_ice_soul_ember_shell`。使用 `py -3` 定向生成 `config/generated/item_definitions.lua`，临时重建文件与正式产物逐字节一致。
- 掉落：`challenge_equipment_reward_service.lua` 不再创建通用 `item_survival_challenge_reward`，而是按 CSV 创建专属物品；映射缺失失败关闭并返回 `challenge_ground_reward_item_mapping_missing`。
- Claim：新增 `items/challenge_ground_reward_claim.lua`，通用兼容物品和六个专属壳共享所有者校验、ID 规范化、可见壳采用、逻辑库存登记、重复合并、失败释放、合成事件和通知。
- 防复制：新掉落实体设置 `survival_ground_reward=true`；成功登记后设置为 `false`。拾取入口只处理该标记或未登记的通用兼容物品，因此已有背包材料丢下再捡不会重复发放逻辑库存。
- 失败回退：`addon_game_mode.lua` 现在检查 `Claim()` 返回值；登记失败且实体仍有效时，把同一实体放回英雄脚下，不创建副本。
- 单一来源：`weapon_equipment_service.lua` 删除手写材料壳表，补建、采用和同步判断统一读取 `item_definitions` 生成配置。最终源码复核曾发现采用入口残留旧变量引用，已修正并新增服务级回归测试。
- Tooltip：中英文补齐熔火核心 Lv1～Lv4 与冰魂焰魄的 `item_...`、`DOTA_Tooltip_ability_...`、`DOTA_Tooltip_Ability_...` 名称和说明；合成宝石沿用并保留既有完整键。
- 测试：新增 `test_challenge_ground_reward_claim.lua`、`test_material_shell_adoption.lua`；扩展 `test_molten_core_ground_drop.lua` 覆盖挑战 05/07/08/09、幂等和映射缺失失败关闭。
- 验证：`ALL_LUA_TESTS total=32 failed=0`；相关 Lua `luac -p` 成功；CSV 可重现生成成功；限定 `git diff --check` 通过，仅有 LF/CRLF 提示；限定源码搜索无 `material_shells` 或 `CreateItem("item_survival_challenge_reward")` 残留。
- 尚未验证：Valve 世界物品 Tooltip 的最终视觉与鼠标命中只能在 Workshop Tools 中观察；还需实机确认装备栏满回落、重复材料数量显示、已有材料丢弃再拾取不复制和自动合成后的实体清理。
- 下一步唯一动作：完全停止并重新 Run，先验收挑战 05/07/08/09 的专属地面 Tooltip 与拾取全链，再执行既有底栏 UI、双塔 Runtime、背包操作和无属性 Tooltip 验收。

## 2026-07-28 — 检查点 038：箭塔技能代理与官方 UI 同时出现，用户批准完整修复

- 用户最新反馈：箭塔底栏同时出现项目大按钮和 Valve 官方小按钮，并询问是否为此前 `[SURVIVAL_GEOMETRY]` 调查取错图片尺寸或布局。
- 截图直接证据：项目按钮的连续视觉位置显示 `Q/W/T`；右侧官方小图标分别吻合 `ability_tower_class_4` 的 `sniper_take_aim` 和 `ability_tower_class_6` 的 `lich_frost_nova`，因此不是物品栏或无关 HUD。
- 已确认事实：当前 `hud_takeover.js` 已以内部 `AbilityButton` 为几何锚点并移除重复 scale，旧 `72x200 Ability0` 外壳问题不是本次唯一或主要根因。
- 已确认根因：实体技能数组被稠密化后，刷新仍以 `displayIndex` 直接查 `AbilityN`；箭塔 5 级删除原升级技能并动态追加七个转职技能时，Valve 节点可出现 ID 空洞/复用/重排。当前逐槽立即提交会让成功槽保持项目 UI、失败槽折叠代理、未压制槽继续显示官方 UI。
- 已确认附加风险：官方压制缺少 `ButtonWell` 时不会可靠隐藏实际 `AbilityButton`；服务端两处对数组 `class_options` 使用 `pairs()`。
- 已排除：不再针对特定 `Ability2/Ability3` 写硬编码补丁；不通过固定像素缩小项目按钮；不隐藏整个官方技能容器；不改变技能施法与费用权威语义。
- 用户决策：明确“确认”视觉顺序映射、原子接管/整批回退、确定性服务端顺序、状态变化映射日志和完整编译测试计划。
- 编辑边界：只修改 `hud_takeover.js`、`building_upgrade_system.lua`、`tower_ability_sync.lua` 和恢复文档；工作区大量其他修改不得 reset/checkout。
- 下一步唯一动作：实施限定编辑，强制编译 Panorama，运行 Lua 语法、全量测试和限定静态检查。

## 2026-07-28 — 检查点 039：原子技能接管已实施，终端验证通道异常

- 已实施 `hud_takeover.js`：枚举 `Ability0..Ability23` 中具有有效内部视觉/几何的节点，按窗口 X/Y 排序，预先校验数量、代理槽和全部几何后才整批提交。
- 原子行为：每轮先恢复上一代官方节点；映射失败时折叠全部项目代理并保留完整官方 UI；映射成功时按视觉顺序生成 `Q/W/E/R/T/Y/U`、覆盖全部按钮并统一压制官方视觉。
- 官方压制：优先压制 `ButtonWell`，不存在时压制实际 `AbilityButton`；继续独立压制官方热键、充能和等级容器，保留 `LevelUpTab`。
- 诊断：新增状态去重的 `[SURVIVAL_TAKEOVER_MAP]`，记录单位、模式、官方节点 ID、锚点尺寸/坐标和视觉映射；旧 `anchor_state` 失败信息改为真实预检原因。
- 服务端：`building_upgrade_system.lua` 添加转职能力和 `tower_ability_sync.lua` 清理转职能力均由 `pairs()` 改为数组确定顺序 `ipairs()`；`test_arrow_tower_completion.lua` 增加源码级防回归断言。
- 当前有效验证：限定 Lua/docs `git diff --check` 已通过，仅有既有 LF/CRLF 提示；源码回读确认文件完整闭合。
- 工具异常：资源编译、Lua 语法、定向测试和全量测试四个独立命令均在 30 秒被终端桥接统一超时；后续连 `py -3` 文件元数据和进程查询也超时。全量新日志没有创建，因此不能把此次超时视为 PASS 或代码 FAIL，也不能直接重复写入/编译命令。
- 尚未验证：本轮 `hud_takeover.vjs_c` 是否已实际更新、Lua 语法、两个定向测试、32 个全量测试和最终限定差异。
- 下一步唯一动作：先用最小只读命令确认终端恢复；再只补跑缺失证据，不重复已有明确成功项。

## 2026-07-28 — 检查点 040：固定技能网格与地面物品 Tooltip 失败实证

- 用户最新实机反馈：1～2 个技能时项目图标较大、7 个技能时较小；用户要求采用 Unity `GridLayout + ContentSizeFitter` 等价结构，固定每个 cell 大小。
- 截图直接证据：地面物品的 Valve Tooltip 只显示物品图标和“技能：被动”，标题与说明为空；此前“专属真实物品已修复世界 Tooltip”的视觉结论被推翻。
- 代码证据：`hud_takeover.js` 的 `applyOfficialGeometry()` 仍执行 `customPanel.style.width/height = geometry.width/height`，所以项目 cell 必然继承 Valve 动态尺寸。
- 代码证据：`challenge_equipment_reward_service.lua` 已调用 `CreateItem(engine_item_name)`，CSV、KV 和中英文本地化也已有六种材料静态定义；问题不是尚未使用 `CreateItem`。
- 架构结论：Lua 实例上的 `survival_content_id` 等字段不会成为 Valve Tooltip 元数据；没有采用虚构的运行时名称/说明/图标 setter。继续走静态注册 item ability，并诊断 requested/actual item name 与客户端本地化加载。
- 用户批准：固定 65×65 技能行、保留视觉顺序和原子接管、增加服务端物品身份日志与客户端一次性本地化诊断、补测试、强制编译和全量验证。
- 修改边界：不重写世界鼠标命中、拾取、背包操作、技能施法或费用语义；不 reset/checkout 工作区其他改动。
- 下一步唯一动作：实施固定技能行和诊断，完成定向/全量测试与资源编译，再完全停止 Workshop Tools 重启实机验收。

## 2026-07-28 — 检查点 041：固定技能行与物品诊断实施、自动验证完成

- HUD 实施：`survival_hud.xml` 新增 `SurvivalAbilityTakeoverRow`；`ability_tooltip.css` 固定 cell 为 65×65、间距 4px；`hud_takeover.js` 使用整组官方锚点的包围宽度中心和底部定位固定行，不再复制单个 Valve 锚点宽高。
- 原子行为保留：每次刷新先恢复上一代官方状态；映射失败时折叠整行并保留完整 Valve UI；成功后整批显示固定行并压制所有对应官方按钮。
- 物品诊断：服务端 `[CHALLENGE_REWARD_DROP]` 增加 `requested_item` 与 `actual_item`；客户端 HUD 初始化增加一次性 `[SURVIVAL_GROUND_ITEM_LOCALIZATION]`，覆盖六种材料名称与说明 token。
- 静态契约：`test_molten_core_ground_drop.lua` 现在校验六个 CSV 映射、KV 注册和中英文本地化；`test_arrow_tower_completion.lua` 校验固定 65×65、行容器存在且源码不再复制 Valve 动态宽度。
- 定向验证：`ARROW_TOWER_COMPLETION_PASS`、`MOLTEN_CORE_GROUND_DROP_PASS`；掉落测试中挑战 05/07/08/09 的 requested/actual item 全部一致。
- 全量验证：`ALL_LUA_TESTS total=32 failed=0`；相关 `luac -p` 成功；game/content 限定 `DIFF_CHECK_PASS`，仅有 LF/CRLF 提示。
- Panorama 强制编译：`hud_takeover.js` 与 `ability_tooltip.css` 各 `1 compiled, 0 failed, 0 skipped`；`survival_hud.xml` 加载链 `7 compiled, 0 failed, 0 skipped`。目标产物时间为 22:10:32～22:10:33。
- 事实边界：自动证据证明静态定义完整、实际创建名正确，但不能证明 Valve 世界 Tooltip 已显示名称与说明；该视觉问题仍未解决，必须完全重启后依据客户端本地化日志继续判断。
- 下一步唯一动作：完全停止 Workshop Tools 并重新 Run；验收 1/2/7 技能固定尺寸，触发挑战 05/07/08/09，保存两类新诊断日志与 Tooltip 截图。

## 2026-07-28 — 检查点 042：实机反馈推翻 65px 基线并定位本地化加载路径

- 用户最新反馈：完全重启后的技能图标仍明显偏大，要求按此前“小图标”尺寸修正；挑战 05 地面掉落仍显示官方空 Tooltip，并提供两类诊断日志。
- 掉落实体事实：`[CHALLENGE_REWARD_DROP]` 中 `requested_item=item_survival_synthesis_gem_shell` 与 `actual_item=item_survival_synthesis_gem_shell` 一致，因此掉落服务、CSV 映射和 `CreateItem` 实际身份不是本次 Tooltip 空白根因。
- 客户端事实：`[SURVIVAL_GROUND_ITEM_LOCALIZATION]` 中六种材料的名称与说明全部原样返回 `#token`，证明客户端没有加载这些本地化 token；该日志只输出一次符合预期，不是诊断循环问题。
- 加载路径根因：完整中英文文件位于非标准的 `resource/localization/addon_*.txt`；引擎实际读取的根目录 `resource/addon_english.txt` 仍是 `YOUR ADDON NAME` 模板，且根目录没有 `addon_schinese.txt`。同机 Valve 示例均把游戏本地化放在 `resource/addon_<language>.txt`。
- Panorama 边界：一次性 `$.Localize()` 诊断同时需要标准 `panorama/localization/addon_<language>.txt` 词典；本项目此前没有该标准目录文件。
- 尺寸结论：65 Panorama px 在当前 `1.111...` UI scale 下约为 72 屏幕 px，与截图中的偏大尺寸一致。按用户指出的“小图标”视觉基线，本轮改为固定 52×52，间距继续为 4px；仍禁止继承 Valve 动态宽高。
- 已排除：没有把长行读取工具的截断显示误判为英文引号缺失；逐行扫描确认中英文源文件均无奇数引号行。
- 下一步唯一动作：同步标准游戏/Panorama 本地化入口，修改 52×52 源码与测试，强制编译 Panorama，并执行定向/全量回归。

## 2026-07-28 — 检查点 043：52px 与标准本地化入口修复验证完成

- 技能源码：`hud_takeover.js` 的 `fixedCellSize` 与 `ability_tooltip.css` 的 row/slot 宽高均为 52；4px 间距、固定行居中、视觉顺序映射、原子接管/整批回退均保留。
- 本地化源码：完整 `lang/Tokens` 中英文已进入 `game/.../resource/addon_english.txt` 与 `addon_schinese.txt`；完整平铺 `dota` 中英文已进入 content 和 game 两侧 `panorama/localization/addon_*.txt`。
- 诊断增强：一次性 `[SURVIVAL_GROUND_ITEM_LOCALIZATION]` 现在先输出 `addon_game_name` 与通用挑战奖励 token 两个 control，再输出六种材料，便于区分整份词典和单个材料 token 的加载状态。
- 静态验证：六个标准词典文件均为 UTF-8 BOM；游戏文件括号为 2/2，Panorama 文件为 1/1；奇数引号行均为 0；关键合成宝石中英文存在；游戏文件与原 `resource/localization/` 文本逐字节一致。
- 定向验证：`ARROW_TOWER_COMPLETION_PASS`、`MOLTEN_CORE_GROUND_DROP_PASS`；挑战 05/07/08/09 requested/actual engine item 全部一致；相关 `luac -p` 成功。
- 全量验证：新日志 `.cline_tmp/ground_item_localization_fix_all_tests.txt` 末尾为 `ALL_LUA_TESTS total=32 failed=0`。
- Panorama 强制编译：`hud_takeover.js` 与 `ability_tooltip.css` 各为 `OK: 1 compiled, 0 failed, 0 skipped`；产物时间 `22:30:57～22:30:58`。game/content 限定 `diff --check` 通过，仅有既有 LF/CRLF 提示。
- 尚未验证：自动验证不能证明 52px 最终视觉或 Valve 世界 Tooltip 已显示；必须完全停止 Workshop Tools 后重新 Run。
- 下一步唯一动作：实机选择 1/2/7 技能单位并触发挑战 05；确认小尺寸固定、control/材料 token 均解析为真实文本、世界 Tooltip 显示标题与说明。

## 2026-07-28 — 检查点 044：服务中断后恢复与用户日志版本判定

- 用户要求确认任务是否完成，并再次提供一条只包含六种材料的 `[SURVIVAL_GROUND_ITEM_LOCALIZATION]` 日志，以及挑战 05 的 `[CHALLENGE_REWARD_DROP]` 日志；随后上游服务暂时不可用，用户要求继续之前任务。
- 任务状态：未完成。用户实机仍报告技能尺寸明显偏大、官方地面物品 Tooltip 为空。
- 掉落实体事实：`requested_item=item_survival_synthesis_gem_shell` 与 `actual_item=item_survival_synthesis_gem_shell` 一致，掉落实体身份链正常。
- 版本判定：用户日志没有检查点 043 最新源码新增的 `addon_game_name` 与通用挑战奖励两个 control，因此该日志不是最新诊断格式，极可能来自旧 `hud_takeover.vjs_c`；对应画面也不能证明当前 52px 产物实际已加载。
- 尚未确认：Workshop Tools 当前 Run 究竟加载了哪个时间戳的 VJS/VCSS；最新版标准本地化文件是否被当前进程读取；52px 若确实加载后是否仍偏大。
- 下一步唯一动作：核对源码、编译产物和 HUD 加载链，重新强制编译相关 Panorama 资源，再以包含 control 的新日志进行实机版本确认。

## 2026-07-28 — 检查点 045：版本化诊断与最终自动验证完成

- 用户在服务恢复后再次询问任务是否完成，并要求未完成则继续。当前任务整体仍需实机验收，但所有可由助手执行的代码、编译与自动测试工作已完成。
- 版本防混淆：`hud_takeover.js` 新增 `takeoverBuild="grid52_loc_v2"`；一次性日志现在以 `build=grid52_loc_v2|cell=52|gap=4` 开头，随后输出 `addon_game_name`、通用挑战奖励 control 和六种材料 token。
- 尺寸证据：历史 `OfficialOverlayOnly_20260722_0004` 的旧自定义技能槽明确为 65×65；用户报告的偏大画面与无 control 的旧日志相匹配。当前源码和 CSS 均为固定 52×52，未找到可证明应采用其他像素值的可靠历史证据，因此不凭猜测继续缩放。
- 防回归测试：`test_arrow_tower_completion.lua` 新增 build 标识和运行时 cell 尺寸日志断言，原有固定 52px、固定行和禁止继承 Valve 动态宽度断言保留。
- 定向测试：`ARROW_TOWER_COMPLETION_PASS`、`MOLTEN_CORE_GROUND_DROP_PASS`；后者继续确认挑战 05/07/08/09 requested/actual engine item 一致。
- 全量测试：`ALL_LUA_TESTS total=32 failed=0`。
- Panorama：更新后的 `hud_takeover.js` 为 `OK: 1 compiled, 0 failed, 0 skipped`；HUD XML 加载链为 `OK: 7 compiled, 0 failed, 0 skipped`。最终 `hud_takeover.vjs_c`、`ability_tooltip.vcss_c`、`survival_hud.vxml_c` 时间均为 2026-07-28 23:05:38 +0800。
- 差异检查：限定 game/content `diff --check` 成功，仅有既有 LF/CRLF 提示。
- 尚未确认：助手无法直接观察 Workshop Tools。必须完全停止后重新 Run；若首条本地化日志没有 `build=grid52_loc_v2|cell=52|gap=4`，说明仍未加载最终产物。只有版本标识正确后，技能视觉与世界 Tooltip 结果才是有效验收样本。
- 下一步唯一动作：用户完全停止并重新 Run，返回首条带 build 标识的本地化日志，并确认 1/2/7 技能尺寸与挑战 05 地面 Tooltip。

## 2026-07-28 — 检查点 046：最终实机确认尺寸与地面 Tooltip，剩余技能行垂直基准问题

- 用户最新实机反馈：单技能与多技能的图标大小已经相同，地面 Tooltip 已成功；仅剩多技能状态的技能行明显更高，用户要求按左上角对齐修复最后这个小问题。
- 源码事实：`ability_tooltip.css` 中行高和 cell 均固定为 52px；高度差不是内容撑开或尺寸回归。
- 根因证据：`hud_takeover.js` 的 `measureFixedRowGeometry()` 仍按内部 Valve 按钮包围盒执行水平居中和底边对齐：`x = left + ((right - left) - width) / 2`、`y = bottom - fixedCellSize`。Valve 单技能与多技能布局会改变内部按钮的垂直位置，因此项目固定行仍随数量上下移动。
- 修复决定：整行改用稳定的官方 `abilities` 容器左上角作为原点，技能数量只向右扩展固定行宽；内部 `AbilityButton` 继续只负责视觉顺序映射、完整性校验和官方视觉压制。
- 修改边界：不改 52×52、4px 间距、技能输入/Tooltip、地面物品 Tooltip、本地化或服务端逻辑。
- 尚未验证：新的左上角基准在 Workshop Tools 中的最终视觉位置。
- 下一步唯一动作：修改 JS/CSS 与源码防回归断言，强制编译相关 Panorama 资源并运行定向/全量验证。

## 2026-07-28 — 检查点 047：技能行左上角对齐实施与自动验证完成

- Panorama 实施：`hud_takeover.js` 新增 `officialAbilitiesRowAnchor()`，固定行 `x/y` 直接采用官方 `abilities` 容器几何；删除内部按钮包围盒的水平居中和底边定位。行宽仍为 `数量×52 + 间距×4`，仅向右延伸。
- 兼容边界：逐槽 `AbilityButton` 几何校验、视觉顺序映射、原子接管/整批回退、官方压制、`Q/W/E/R/T/Y/U`、Tooltip 与施法输入均未改变。
- 版本防混淆：`takeoverBuild` 更新为 `grid52_topleft_v3`；最新一次性日志应以 `build=grid52_topleft_v3|cell=52|gap=4` 开头。
- 防回归测试：`test_arrow_tower_completion.lua` 断言必须使用 `officialAbilitiesRowAnchor` 的 `x/y`，且 JS 源码不得再含 `bottom - fixedCellSize`。
- 定向验证：`ARROW_TOWER_COMPLETION_PASS`。
- 全量验证：`.cline_tmp/ability_topleft_v3_all_tests.txt` 末尾为 `ALL_LUA_TESTS total=32 failed=0`。
- Panorama 强制编译：`hud_takeover.js` 为 `OK: 1 compiled, 0 failed, 0 skipped`；游戏产物 `panorama/scripts/custom_game/hud_takeover.vjs_c` 时间为 `2026-07-28 23:19:30 +0800`，大小 44883 字节。
- 差异与源码复核：game/content 限定 `diff --check` 成功；源码回读确认固定 52×52、4px 间距和左上角公式完整。
- 尚未确认：助手无法直接观察 Workshop Tools；1、2、7 个技能的最终左边/顶边一致性仍需重新 Run 实机确认。
- 下一步唯一动作：完全停止 Workshop Tools 并重新 Run；确认 `grid52_topleft_v3` 版本标识后，对比 1 个与 7 个技能的左边和顶边。

## 2026-07-29 — 检查点 048：左上角方案被实机否定，批准运行时锚点校准器

- 用户补充断线前的最新实机结论：此前已经提供截图；采用官方 `abilities` 容器左上角后，所有项目技能超出原来的技能范围。因此检查点 047 的代码/编译事实仍有效，但“左上角只差最终验收”的结论已被实机证据推翻。
- 用户候选想法：以中下位置作为锚点可能更合理，但用户不希望继续猜测，希望能在游戏中自己调整锚点并直接看 1、2、7 技能的实际分布。
- 源码调查：最终位置只由 `measureFixedRowGeometry()` 生成并由 `row.style.position` 应用；现有 `geometryTick()` 每 0.5 秒刷新，适合接入统一运行时校准状态。`SurvivalAbilityTakeover` 也已有 `Refresh`、`DumpSurvey` 和 `SetSurveyEnabled` API 模式可复用。
- 已排除：仅在 Panorama Debugger 修改 `style.position`，因为 0.5 秒几何刷新会覆盖临时值，且无法可靠输出可固化参数；也不直接把中下候选写死为最终决策。
- 用户批准完整方案：九宫格锚点、X/Y ±1/±5 微调、Valve `abilities` 容器/可见技能包围范围/项目行边界框、锚点十字、实时数据、重置/关闭和参数日志输出。
- 修改边界：只改 Panorama JS/CSS/XML 和源码契约测试；保持 52×52、4px、视觉顺序、原子接管/整批回退、官方压制、快捷键、技能输入、Tooltip、背包和地面物品逻辑不变。
- 下一步唯一动作：实施校准器并完成强制编译、定向/全量测试和限定差异检查，再交由用户实机输出最终参数。

## 2026-07-29 — 检查点 049：运行时锚点校准器实施完成，准备资源编译

- `hud_takeover.js`：版本更新为 `grid52_calibrator_v4`；增加九宫格归一化锚点模型，同一锚点同时作用于 Valve `abilities` 容器与固定技能行，再叠加运行时 X/Y 偏移。默认仍为旧左上角/0,0，避免未开启调试时出现未经实机选择的新布局。
- 运行时 API：增加 `SetCalibrationAlignment`、`NudgeCalibration`、`ResetCalibration`、`SetCalibrationVisible`、`ToggleCalibration`、`DumpCalibration` 和 `GetCalibration`；控制台命令 `survival_ability_calibration` 切换面板，`survival_ability_calibration_dump` 输出参数。
- 游戏内面板：增加九宫格按钮、X/Y ±1/±5、实时容器/原生技能/项目行矩形、重置、关闭和输出参数按钮。
- 可视边界：蓝框为 Valve `abilities` 容器、黄框为当前有效 Valve 技能包围范围、绿框为项目固定技能行、红十字为容器选定锚点；所有边界节点关闭命中，不阻断技能点击。
- 保留边界：cell 仍为 52×52、间距 4px；视觉顺序映射、完整映射校验、原子接管/整批回退、官方压制、快捷键、技能点击与 Tooltip 路径未修改。
- 自动验证现状：限定 game/content `diff --check` 通过（仅既有 LF/CRLF 提示）；`test_arrow_tower_completion.lua` 已返回 `ARROW_TOWER_COMPLETION_PASS`。
- 下一步唯一动作：强制编译 `hud_takeover.js`、`ability_tooltip.css` 和 `survival_hud.xml`，检查每项 `compiled > 0`、`failed=0`，再运行全量回归。

## 2026-07-29 — 检查点 050：校准器 Panorama 资源强制编译成功

- `hud_takeover.js` 强制编译：`OK: 1 compiled, 0 failed, 0 skipped`。
- `ability_tooltip.css` 强制编译：`OK: 1 compiled, 0 failed, 0 skipped`。
- `survival_hud.xml` 加载链强制编译：`OK: 7 compiled, 0 failed, 0 skipped`；JS/CSS/XML 均通过资源编译器实际解析。
- 定向源码契约仍为 `ARROW_TOWER_COMPLETION_PASS`。
- 下一步唯一动作：运行 32 项全量 Lua 回归、核对新编译产物元数据并完成最终限定 `diff --check` 和源码回读。

## 2026-07-29 — 检查点 051：运行时锚点校准器自动验证全部完成

- 全量回归：新日志 `.cline_tmp/ability_calibrator_v4_all_tests.txt` 末尾为 `ALL_LUA_TESTS total=32 failed=0`；32 个测试逐项均为 PASS。
- 编译产物：`hud_takeover.vjs_c` 55243 字节、`ability_tooltip.vcss_c` 16064 字节、`survival_hud.vxml_c` 9725 字节，三者时间均为 `2026-07-29 08:54:12 +0800`。
- 最终源码回读：九宫格公式按容器/项目行同一归一化点对齐；X/Y 偏移实时进入最终 `row.style.position`；面板 XML API 名称与 JS 导出一致；边界节点均关闭命中。
- 保留契约：52×52、4px、完整映射、原子接管/回退、官方压制、输入与 Tooltip 路径保持不变；默认面板隐藏且保持 `top_left/0,0`，未擅自固化中下候选。
- 最终限定 `diff --check` 通过，仅有既有 LF/CRLF 提示。
- 实机入口：完全停止并重新 Run 后，在控制台执行 `survival_ability_calibration`；满意后点击“输出当前参数”或执行 `survival_ability_calibration_dump`。
- 尚未验证：助手无法直接观察 Workshop Tools；最终锚点和偏移必须由用户比较 1、2、7 技能状态后确认。

## 2026-07-30 — 检查点 052：商店 UI 布局重构调查完成

- 用户最新要求：商店物品单元只显示图片，不在单元中显示金币和木材；悬停仍显示 Tooltip；Tooltip 与物品单元垂直中心对齐，左边缘距单元右边缘 10px；商品区域宽度缩为原来的约三分之一。
- 源码证据：`shop_ui.js` 当前为每个 `168×205px` 单元创建图片、名称、科技等级、金币、木材和购买状态；卡片 `onmouseover` 显示、`onmouseout` 隐藏 Tooltip。
- 闪烁根因：`tooltip_position.js::PlaceRight()` 带有历史 `-78px/-88px` 偏移，可能把 Tooltip 放回卡片命中区域；`ShopEntryTooltip` 未显式关闭子节点命中。
- 尺寸决定：当前 `980px` 窗口扣除内边距、`180px` 分类栏和 `12px` 间距后，商品区约 `760px`；商品区改为 `254px`（约三分之一），窗口配套改为 `474px`，保留分类栏可用性。
- 实施边界：只改 content Panorama 的商店 JS/CSS/XML；保留右键购买、服务器快照、分类、Tooltip 中的价格/名称/条件/状态和不可购买视觉。
- 尚未验证：截图未作为可访问文件提供；最终视觉、不同 UI scale 下的精确 10px 间距及鼠标悬停稳定性需要完全重启 Workshop Tools 后实机确认。
- 下一步唯一动作：实施图片单元、独立右侧定位和商品区缩宽，强制编译相关 JS/CSS/XML，并执行源码契约与限定差异检查。

## 2026-07-30 — 检查点 053：商店 UI 布局重构实施与自动验证完成

- `shop_ui.js`：商品单元只创建 `ShopItemFrame + ShopItemIcon`；删除卡内名称、科技等级、金币、木材和购买状态节点及无用 `createCost()`。右键购买、悬停 Tooltip 和不可购买样式保留。
- `shop.css`：窗口宽度 `980px → 474px`，商品区固定为 `254px`（原约 `760px` 的三分之一）；商品单元改为纯图片 `80×64px`，移除废弃文本/成本样式。
- `shop_tooltip.js`：改用商店专用右侧定位，`x=物品右端+10px`，`y=物品中心-Tooltip半高`；显示后在当前帧、下一帧和 0.03 秒复测动态高度，并保留上下 12px 屏幕边界。
- `survival_hud.xml`：`ShopEntryTooltip` 同时设置 `hittest=false` 与 `hittestchildren=false`，避免 Tooltip 覆盖卡片后触发 hover 抖动。
- Tooltip 内容边界：名称、说明、金币、木材、购买条件、拥有数量、动态字段和购买状态全部保留，不改变服务端商店数据或购买逻辑。
- 编译结果：`shop_ui.js`、`shop_tooltip.js`、`shop.css` 各 `1 compiled, 0 failed, 0 skipped`；`survival_hud.xml` 加载链 `7 compiled, 0 failed, 0 skipped`。
- 编译产物时间均为 `2026-07-30 17:20:36`；源码契约 `SHOP_LAYOUT_CONTRACT_PASS`；content 限定 `git diff --check` 通过，仅有 LF/CRLF 提示。
- 尚未验证：助手无法直接观察 Workshop Tools；需要完全停止并重新 Run，实机确认 Tooltip 不闪烁、垂直中心对齐、右侧 10px 间距及 `254px` 商品区宽度是否符合截图预期。
- 下一步唯一动作：完全停止并重新 Run 地图，依次悬停商品区顶部/中部/底部物品，确认 Tooltip 稳定和边界位置；如视觉宽度仍需微调，返回新截图与目标宽度即可定向调整。
- 下一步唯一动作：用户返回完整 `[SURVIVAL_ABILITY_CALIBRATION] build=grid52_calibrator_v4 ...` 日志；根据实机结果固化最终布局，并决定移除还是默认关闭校准 UI。

## 2026-07-29 — 检查点 052：收到三技能校准参数并定位切换延迟/原生图标闪现

- 用户实机输出：`build=grid52_calibrator_v4 alignment=middle_left offset_x=5 offset_y=35 ability_count=3 anchor=652.5,939.6 container_rect=652.5,849.6,190.8x180 visual_rect=652.5,940.5,192.6x63.9 row_rect=657.5,948.6,164x52`；用户认为该版本较好看。当前证据明确覆盖 3 个技能。
- 用户新增问题：切换选中目标时项目 UI 更新明显慢于原版，且有时 Valve 原技能图标先出现，随后才替换为项目图标。
- 源码根因：`runtimeTick()` 每 0.10 秒只更新已接管槽内容；完整技能发现、映射和官方视觉压制仅由 `geometryTick()` 每 0.50 秒调用 `refresh()`。`hud_takeover.js` 当前没有选中单位变化事件订阅，因此切换最差延迟接近 0.5 秒。
- 闪现机制：Valve 先重建/复用新单位的 `AbilityN`，项目层在下一次 0.5 秒刷新前尚未压制这些新视觉节点；映射尚不完整时现有安全回退还会恢复官方视觉，因此原版图标可短暂出现。
- 已排除：把完整 24 槽 HUD 扫描永久提高到 0.03 秒。该方案持续增加扫描与样式写入，仍无法消除 Valve 重建与扫描之间的闪现窗口，并违背事件驱动边界。

## 2026-07-29 — 检查点 053：批准事件驱动无闪切换，准备实施

- 用户明确批准：事件监听触发是正确思路，立即按该方案修复选中目标响应慢和原版技能图标闪现。
- 额外源码确认：`prepareTakeover()` 当前校验技能数量、代理槽和 Valve 几何，但不校验 Valve 节点已经完成新单位内容重建；因此选择事件同一帧不能把新技能数据直接提交到可能仍属于旧单位的视觉节点。
- 实施决定：选中/查询单位事件与 0.10 秒轻量实体哨兵共同触发有界过渡；先隐藏旧项目行、关闭 Tooltip，并临时隐藏官方 `abilities` 容器。随后按 `0/0.016/0.05/0.10/0.20s` 有限刷新，只有完整映射稳定后才原子显示新项目行。
- 安全边界：官方容器过渡状态必须完整保存并恢复；超过短暂宽限仍映射失败则恢复 Valve UI，避免永久无技能按钮。0.5 秒低频几何恢复保留，不增加永久高频 24 槽扫描。
- 校准边界：本次只修响应生命周期；`middle_left/+5/+35` 保留为用户已确认的三技能候选，不擅自改变其他技能数量参数。
- 下一步唯一动作：修改 `hud_takeover.js` 与定向源码契约，强制编译并执行定向/全量回归。

## 2026-07-29 — 检查点 054：事件驱动无闪切换代码完成，准备强制编译

- `hud_takeover.js` 版本更新为 `grid52_selection_events_v5`。
- 即时触发：订阅 `dota_player_update_selected_unit` 与 `dota_player_update_query_unit`；额外 0.10 秒 `selectedUnitSentinel()` 只比较 portrait unit entindex，不执行完整 HUD 扫描。
- 过渡行为：单位变化立即关闭旧 Tooltip、折叠旧项目行并把当前 Valve `abilities` 容器设为透明且关闭命中；容器仍参与布局，因此可继续读取新节点几何。
- 有界重试：严格使用 `0/0.016/0.05/0.10/0.20s`；serial 取消旧单位回调，同单位事件/哨兵在活动窗口内去重。完整映射后原子显示项目行；最终失败恢复 Valve 容器。
- 保留边界：现有逐节点 `rememberOfficial/restoreOfficial` 仍负责正式压制状态；0.5 秒 `geometryTick` 保留为低频恢复，没有引入永久 0.03 秒扫描；校准公式和用户三技能候选参数语义未修改。
- 自动验证现状：更新后的 `test_arrow_tower_completion.lua` 已返回 `ARROW_TOWER_COMPLETION_PASS`；限定源码 `diff --check` 未报告空白错误。
- 下一步唯一动作：强制编译 `hud_takeover.js`，再运行 32 项全量回归、产物检查和最终源码复核。

## 2026-07-29 — 检查点 055：事件驱动无闪切换自动验证完成

- 最终版本：`grid52_selection_events_v5`。
- 实施结果：`dota_player_update_selected_unit` 与 `dota_player_update_query_unit` 立即触发选中切换；0.10 秒哨兵只比较 portrait unit entindex。切换时立即关闭 Tooltip、隐藏旧项目行并透明化 Valve `abilities` 容器。
- 有界过渡：`0/0.016/0.05/0.10/0.20s` 有限重试；同单位重复事件去重，serial 取消旧切换回调。过渡中的暂时 0 技能或数量不匹配继续保持透明，最终成功原子显示项目行，最终失败恢复 Valve UI。
- 性能边界：0.5 秒低频 `geometryTick` 保留为容错；没有永久 0.03 秒完整技能扫描。0.10 秒哨兵不遍历 HUD 或技能槽。
- 定向测试：最终 `ARROW_TOWER_COMPLETION_PASS`，并覆盖事件名、有界延迟、过渡压制恢复、临时空帧和禁止高频扫描。
- Panorama 强制编译：最终 `hud_takeover.js` 为 `OK: 1 compiled, 0 failed, 0 skipped`。
- 全量回归：`.cline_tmp/selection_events_v5_final_all_tests.txt` 末尾为 `ALL_LUA_TESTS total=32 failed=0`。
- 最终产物：`panorama/scripts/custom_game/hud_takeover.vjs_c` 时间 `2026-07-29 09:25:23 +0800`，大小 60732 字节。
- 最终限定 `diff --check` 通过，无空白错误。
- 尚未验证：助手无法直接观察 Workshop Tools；切换响应速度和 Valve 原图标是否完全不再闪现需要实机确认。
- 下一步唯一动作：完全停止并重新 Run，确认 `grid52_selection_events_v5`，快速切换英雄/农民/建筑/七技能箭塔；若仍闪现，返回 `[SURVIVAL_TAKEOVER_SELECTION]` begin/end 日志与单位组合。

## 2026-07-29 — 检查点 056：确认重新 Run 丢失校准状态并批准固化正式预设

- 用户最新反馈：重新 Run 后截图中的技能行仍明显偏离，询问动态调整为什么不理想、是否需要 Panorama Debugger；随后明确批准按恢复出的最小方案执行。
- 新实机证据：当前运行参数回到了 `top_left / X=0 / Y=0`，而用户此前认为较好看的参数为 `middle_left / X=5 / Y=35`。因此当前截图不能用于评价正确参数下的五技能布局。
- 已确认根因：`hud_takeover.js` 启动默认值和 `resetCalibration()` 均硬编码 `top_left / 0 / 0`；用户调出的参数只存在于当次 `CustomUIConfig` 状态，完全重启 Workshop Tools 后会丢失。
- 实施决定：建立唯一正式预设 `middle_left / 5 / 35`；启动默认和重置共用它；增加预设版本，旧状态首次加载新版时迁移，同一 Run 内后续微调保留；日志增加预设版本和参数来源。
- 保留边界：不改现有九宫格公式和 `visualBounds`，不改 v5 事件监听、0.10 秒哨兵、有限重试、无闪压制、52×52、4px、输入与 Tooltip。
- 已排除：现在使用 Panorama Debugger 继续调查。当前已有直接源码证据证明是状态回退；只有正确预设下多技能仍异常时才评估几何模型。
- 下一步唯一动作：修改 `hud_takeover.js` 和 `test_arrow_tower_completion.lua`，随后强制编译并执行定向/全量验证。

## 2026-07-29 — 检查点 057：正式预设与版本迁移代码完成，准备强制编译

- `hud_takeover.js` 版本更新为 `grid52_preset_v6`，新增唯一 `calibrationPreset`：`version=1 / middle_left / X=5 / Y=35`。
- 初始化行为：没有旧状态时来源为 `preset_default`；旧状态没有当前版本时来源为 `preset_migration` 并迁移一次；版本一致时保留当前 Run 内状态，不重复覆盖用户微调；非法值回退来源为 `preset_recovery`。
- 交互行为：九宫格和 X/Y 微调把来源标记为 `runtime_adjustment`；“重置”调用同一 `applyCalibrationPreset()` 并标记 `preset_reset`，不再包含独立的 `top_left / 0 / 0` 硬编码。
- 诊断行为：`[SURVIVAL_ABILITY_CALIBRATION]` 新增 `preset_version` 与 `source`；`GetCalibration()` 同步返回这两个字段。
- 防回归契约：`test_arrow_tower_completion.lua` 新增 v6 build、正式值、统一重置、版本迁移和诊断来源断言；原 v5 选择事件、有界重试、0.5 秒容错、禁止 0.03 秒扫描、九宫格公式、52×52 断言全部保留。
- 快速验证：更新后的定向测试返回 `ARROW_TOWER_COMPLETION_PASS`；game/content 限定 `diff --check` 未报告空白错误。一次只读编译器路径探测因终端兼容超时，没有写入文件，将直接使用项目已知绝对路径强制编译。
- 下一步唯一动作：强制编译 `hud_takeover.js` 并核对 `1 compiled, 0 failed, 0 skipped`，再运行 32 项全量回归与最终复核。

## 2026-07-29 — 检查点 058：v6 Panorama 强制编译成功

- 使用绝对路径执行 `resourcecompiler.exe -f`，输入为 content 侧 `panorama/scripts/custom_game/hud_takeover.js`，输出为 game 侧 `panorama/scripts/custom_game/hud_takeover.vjs_c`。
- 编译结果：`OK: 1 compiled, 0 failed, 0 skipped`；更新后的版本迁移、正式预设与事件驱动代码均通过 Dota Panorama 资源编译器解析。
- 下一步唯一动作：运行 32 项全量 Lua 回归，随后核对产物元数据、最终源码和限定差异。

## 2026-07-29 — 检查点 059：正式预设修复验证完成

- 定向契约：`lua scripts/vscripts/tests/test_arrow_tower_completion.lua` 返回 `ARROW_TOWER_COMPLETION_PASS`。
- 全量回归：目录当前包含 32 个 `scripts/vscripts/tests/test_*.lua`；先完成的 31 项与补跑的 `test_addhero_cheat.lua` 均通过，`.cline_tmp/preset_v6_all_tests.txt` 末尾为 `ALL_LUA_TESTS total=32 failed=0`。
- Panorama 强制编译：`hud_takeover.js` 返回 `OK: 1 compiled, 0 failed, 0 skipped`；game 产物 `panorama/scripts/custom_game/hud_takeover.vjs_c` 已刷新，大小 61756 字节。
- 源码复核：正式预设唯一值为 `middle_left / 5 / 35`；启动迁移、运行时微调、重置和诊断来源均存在；源码中不再存在旧的 `calibration.alignment = top_left`、`offsetX = 0`、`offsetY = 0` 默认赋值。
- 差异复核：目标 game 文档/测试和 content HUD 源码的限定 `diff --check` 已通过；工作区其他既有修改未清理、未回退。
- 实机边界：助手无法直接观察 Workshop Tools；下一步只需完全停止并重新 Run，确认首条 `[SURVIVAL_ABILITY_CALIBRATION]` 为 `grid52_preset_v6`、`preset_version=1`、`source=preset_default`、`middle_left`、`5`、`35`，再比较不同技能数量。

## 2026-07-29 — 检查点 060：恢复执行模式并复核实施边界

- 用户最新要求：思考完成后转入执行模式开始编码，并已批准按恢复出的计划继续。
- 源码复核：`hud_takeover.js` 已包含 `grid52_preset_v6`、唯一正式预设 `middle_left / X=5 / Y=35`、版本迁移、统一重置、参数来源诊断和 `survival_ability_calibration_dump`；对应测试契约也已存在。
- 事实与边界：批准的编码工作在检查点 057～059 已经落地，本轮没有发现仍需补写的代码；重复修改会无意义地扩大风险，因此只追加恢复检查点并重新执行测试、强制编译和产物复核。
- 工作区状态：`docs/ai`、定向测试和 `hud_takeover.js` 存在既有未跟踪状态，相关 XML/CSS 存在既有修改；本轮不暂存、不提交、不清理、不回退。
- 尚未验证：Workshop Tools 中正确预设下 1、3、5、7 技能位置、快速切换响应和 Valve 图标闪现情况。
- 下一步唯一动作：重新运行定向与 32 项全量测试，强制编译 `hud_takeover.js`，核对产物与限定差异后等待实机验收。

## 2026-07-29 — 检查点 061：终端桥接 Shell 不一致

- 新工具事实：定向 Lua 测试已明确返回 `ARROW_TOWER_COMPLETION_PASS`；随后使用 PowerShell 语法的全量测试和资源编译请求在 30 秒处超时，预期新日志未创建，不能视为已执行或代码失败。
- 根因证据：后续命令回显为 Git Bash `MINGW64` 提示符；PowerShell 变量在嵌套调用前被错误展开，说明当前桥接会话与声明的 PowerShell 环境不一致。
- 禁止误判：不使用超时输出证明 PASS/FAIL，不原样重复写入型命令，不把旧检查点的 PASS 当成本轮新证据。
- 调整方案：改用明确的 Git Bash 可执行文件调用和 POSIX 路径；全量测试拆分为短批次，资源编译后单独核对产物。
- 下一步唯一动作：先用只读 Bash 命令确认测试清单、Lua/编译器进程和产物元数据，再执行缺失验证。

## 2026-07-29 — 检查点 062：执行模式验证完成，等待实机验收

- 定向验证：`lua scripts/vscripts/tests/test_arrow_tower_completion.lua` 返回 `ARROW_TOWER_COMPLETION_PASS`。
- 全量验证：32 个 Lua 测试拆为 4 个 8 项批次执行，`.cline_tmp/preset_v6_exec_batch1.txt` 至 `batch4.txt` 均返回 `total=8 failed=0`；合计 `32/32` 通过。
- Panorama 编译：通过独立 `powershell.exe -NoProfile` 调用资源编译器强制编译 `hud_takeover.js`，结果为 `OK: 1 compiled, 0 failed, 0 skipped`；game 产物大小 `61756` 字节，时间 `2026-07-29 11:28:24 +08:00`。
- 源码契约：v6 正式预设、版本迁移、统一重置、诊断输出、事件驱动选择切换、有界无闪重试和固定 52×52 cell 均已由源码/定向测试确认存在。
- 差异/格式：game 侧 `diff --check` 返回 0；game 定向文件和 content 三个目标文件逐文件尾随空白检查均为 0。content 仓库的 `git diff --check` 因终端桥接在 30 秒处超时，未将其误记为通过或失败。
- 工作区边界：未暂存、未提交、未清理、未回退任何既有修改；本轮只新增本检查点和测试日志，并刷新编译产物。
- 尚未验证：Workshop Tools 完全重启后的首条校准日志，以及 1、3、5、7 技能位置、不同单位切换响应和 Valve 图标闪现情况。
- 下一步唯一动作：用户完全停止 Workshop Tools 后重新 Run，执行 `survival_ability_calibration_dump`，确认 `grid52_preset_v6 / preset_version=1 / source=preset_default / middle_left / 5 / 35`，再进行实机验收。

## 2026-07-29 — 检查点 063：新任务覆盖为 Undying 建造者 Immortal 外观

- 用户最新要求：只给玩家开局的 Undying 建造者使用 `The Hallows Within Bundle`；本轮实现角色模型、环境特效和可安全恢复的姿势动画，墓碑/僵尸只记录资源。
- 已确认物品定义：Bundle `21800`；`The Hallows Within` `14963`（Head）；`The Hallows Within Tombstone` `14994`（Tombstone）。
- 关键语义：该 Bundle 不是多个身体槽组件；角色外观主要是单个大型 Head wearable。墓碑、墓碑环境特效和专属僵尸属于独立技能资产。
- 代码证据：`addon_game_mode.lua` 强制 `npc_dota_hero_undying` 并在 `initialize_survival_hero()` 发布 `HERO_READY`；现有 `hero_cosmetic_service.lua` 已支持模型 wearable，但没有开局建造者接入、粒子生命周期和重复应用清理。
- 用户批准：进入执行模式，按角色本体优先范围实施。
- 安全边界：不影响修理工、波次怪、普通僵尸、Boss 或祭坛英雄；不强行替换主体骨骼模型；不修改建造者玩法属性。
- 文档迁移：旧技能行任务已复制到 `docs/ai/archive/2026-07-29-ability-row-calibration.md`。
- 尚未确认：本机 VPK 中 defindex `14963` 的模型、粒子、attachment 和动画 modifier 精确路径。
- 下一步唯一动作：只读解析 VPK 中的 Undying 模型/粒子和物品 schema 候选，验证资源后再修改游戏运行逻辑。

## 2026-07-29 — 检查点 064：The Hallows Within 代码与资源契约完成

- 本机 VPK 取证：角色模型为 `models/items/undying/undying_fall20_immortal_head/undying_fall20_immortal_head.vmdl`；主环境粒子为 `particles/econ/items/undying/fall20_undying_head/fall20_undying_head_ambient.vpcf`。两者对应的编译资源均存在于当前 `pak01_dir.vpk`。
- 已记录但未运行：`undying_fall20_immortal_tombstone.vmdl`、`undying_fall20_immortal_minion.vmdl`、`fall20_undying_tombstone_ambient.vpcf`。
- 配置实施：`hero_cosmetics_config.lua` 增加独立 `builder_undying`，使用命名组件 `hallows_head`，主环境粒子绑定该 wearable。
- 服务实施：`hero_cosmetic_service.lua` 保持旧字符串 wearable 配置兼容；新增命名组件、项目自有 wearable/粒子状态、重复应用清理、`DestroyParticle`、`ReleaseParticleIndex`、`UTIL_Remove` 回退和 `clear()`。
- 开局接入：`addon_game_mode.lua::initialize_survival_hero()` 只在 `unit_name == SURVIVAL_FORCE_HERO` 时应用 `builder_undying`，且发生在 `HERO_READY` 前。普通 Undying 怪物不会进入该路径。
- 重生恢复：新增 `npc_spawned` 监听；只有单位名是强制 Undying 且 `ready_hero_entindex_by_player[player_id]` 等于当前 entindex 时才幂等重建，初次未初始化英雄和普通 Undying 怪物均被排除。
- 动画决策：官方页面确认 Head 饰品绑定轻微姿势调整，但没有找到可安全调用的独立 Lua 动画 modifier；不替换主体骨骼模型，不调用猜测接口，保留原版动画和 wearable 骨骼跟随。
- 新增测试：`scripts/vscripts/tests/test_hero_cosmetic_service.lua` 覆盖模型/粒子预缓存、默认 wearable 隐藏、Owner/FollowEntity、命名粒子 owner、重复应用与显式清理。
- 可执行验证：`.cline_tmp/test_hallows_within_contract.ps1` 返回 `HALLOWS_WITHIN_CONTRACT_PASS`；目标 `git diff --check` 返回 `TARGET_DIFF_CHECK_PASS`。
- 环境限制：当前 PowerShell PATH 和常见安装路径均无 `lua`、`luac`、`luajit`；WSL 探测超时。未把无法执行的 Lua 测试和语法检查伪记为通过。当前磁盘中的测试目录只有原 `test_hero_health_guard.lua` 和本轮新增测试，与历史 32 项文档环境不同。
- 尚未验证：Workshop Tools 中大型 wearable 的实际覆盖、环境粒子 attachment、移动/建造/死亡/重生动画，以及第二次 Run 是否无重复。
- 下一步唯一动作：完全停止 Workshop Tools 后重新 Run，实机验收开局建造者；如异常，返回 `[Survival][INFO][HeroCosmetic] builder_undying applied wearables=... particles=...` 日志和截图。

## 2026-07-29 — 检查点 065：用户实机确认部件饰品上线成功

- 用户原话：`部件饰品上线成功，记录成功的经验`。
- 实机确认范围：开局 Undying 建造者成功显示 `The Hallows Within` 部件饰品。
- 由实机结果直接证明：`undying_fall20_immortal_head.vmdl` 路径正确；`SpawnEntityFromTableSynchronous("prop_dynamic")` 可创建该大型 Head wearable；`SetOwner` 与 `FollowEntity(hero, true)` 能让其跟随建造者骨骼；在 `HERO_READY` 前应用的时机有效。
- 不扩大结论：用户没有在本次反馈中分别确认环境粒子、死亡/重生或第二次 Run，三项继续作为防回归检查，不写成已实机通过。
- 可复用资源定位经验：先用公开 defindex 确认 Bundle/子物品和槽位，再从本机 `pak01_dir.vpk` 按英雄目录、发布时间开发代号和模型/材质/图标/粒子交叉验证；展示名与内部目录名不同是常态。
- 可复用模型经验：商城视觉上像“全身套装”不代表存在多个身体组件。本套英雄外观实际是 Head 槽 defindex `14963` 的单个大型 wearable；墓碑 defindex `14994` 是独立技能槽资产。
- 可复用运行时经验：保留原英雄主体骨骼与动画，以项目创建的 `prop_dynamic` 做 bone merge；不要用 `SetModel` 把英雄主体直接换成 wearable，也不要猜测官方 econ 动画 modifier。
- 可复用生命周期经验：项目创建的 wearable/粒子必须按 hero entindex 保存；重复应用先清理项目自有实体和粒子；重生恢复必须同时校验强制英雄单位名、玩家 ID 和已初始化 entindex，避免影响外形相同的怪物。
- 可复用粒子经验：粒子配置应通过命名 `owner` 绑定到对应 wearable，而不是一律绑定英雄原点；主粒子负责引用子粒子，运行时只需预缓存和创建已确认的入口 `.vpcf`。
- 任务状态：角色部件饰品主目标完成并实机验收成功；任务归档到 `docs/ai/archive/2026-07-29-undying-hallows-within.md`。
- 下一步唯一动作：等待用户新任务。

## 2026-07-29 — 检查点 066：血条与 Tooltip 最小修改方案获批

- 用户最新要求：头顶血条长度改为原来的二分之一并整体上移约 20px；隐藏第一张图中的 Valve 官方“攻击 / 防御”属性汇总面板；技能与背包项目 Tooltip 统一为中心横坐标对齐，Tooltip 下锚点距图标上锚点 10px；多人协作中必须保持最小修改量。
- 用户已确认官方 Tooltip 范围只指“攻击 / 防御”属性汇总面板，并明确批准开始修改。
- 源码事实：`hero_world_health_bar.css` 当前宽 124px；`hero_world_health_bar.js` 以 `screenX - 62` 居中并使用 `screenY - 6`。最小修改为 62px、`screenX - 31` 和 `screenY - 26`。
- 源码事实：技能 `hud_takeover.js` 和背包 `inventory_tooltip.js` 已共同调用 `tooltip_position.js::PlaceAbove()`；该函数仍含 `-78/-88` 历史位移和 14px 间距，可只改共享函数实现统一规则。
- 源码事实：`combat_stats.js::updateOfficialStatsVisibility()` 已对 `Damage/AttackSpeed/Armor` 关闭命中，但共同 `stats_container` 仍可命中；最小修复是在同一路径关闭该只读父节点及子树命中，不增加遮罩或高频 Hide 事件。
- 安全边界：不修改血条高度/颜色/逐帧更新，不改变 Tooltip 内容，不隐藏官方底栏，不修改技能输入，不触碰背包原生操作，不清理或回退工作区其他修改。
- 尚未验证：资源编译器解析、编译产物、限定差异与 Workshop Tools 实机效果。
- 下一步唯一动作：实施四个 Panorama 源文件的局部修改，随后强制定向编译和限定验证。

## 2026-07-29 — 检查点 067：血条与 Tooltip 最小修改完成

- 实施结果：头顶血条宽度由 124px 改为 62px；JS 半宽偏移由 62 改为 31，保持单位中心对齐；垂直偏移由 -6 改为 -26，整体上移 20px。
- 实施结果：共享 `tooltip_position.js::PlaceAbove()` 删除历史 `-78/-88/14px` 定位，改为 Tooltip 与悬停图标中心 X 对齐，Tooltip 下边缘距图标上边缘 10px；仍在当前帧、下一布局帧和 0.03 秒后复测真实尺寸，并保留 12px 屏幕边界。
- 实施结果：`combat_stats.js::updateOfficialStatsVisibility()` 在原有三个属性子节点关闭命中的基础上，补充关闭 `stats_container.hittest/hittestchildren`；不隐藏属性视觉，不修改技能或背包输入。
- 编辑纠正：首次上下文补丁误命中同名 `statsContainer` 的权威数字写入函数；在编译前已发现、移除并移动到目标可见性函数。最终源码中该父节点命中关闭仅出现一次，位于正确函数。
- 编译证据：`hero_world_health_bar.js`、`hero_world_health_bar.css`、`tooltip_position.js`、`combat_stats.js` 分别强制编译，四项均返回 `OK: 1 compiled, 0 failed, 0 skipped`。
- 产物证据：`hero_world_health_bar.vjs_c` 6052 字节、`hero_world_health_bar.vcss_c` 2701 字节、`tooltip_position.vjs_c` 4635 字节、`combat_stats.vjs_c` 71739 字节，时间戳均在本轮刷新。
- 自动验证：`UI_MINIMAL_CHANGE_CONTRACT_PASS`、`CONTENT_DIFF_CHECK_PASS`、`DOCS_DIFF_CHECK_PASS`。
- 环境说明：并行启动资源编译器曾导致终端捕获超时，未把未捕获项记为成功；其后四项全部串行重跑并取得独立成功汇总。
- 尚未验证：助手无法直接观察 Workshop Tools；需要完全停止当前 Run 并重新启动后实机确认视觉位置、边缘约束以及官方“攻击 / 防御”面板是否彻底消失。
- 下一步唯一动作：用户实机验收血条、技能 Tooltip、背包 Tooltip、属性区域悬停和背包原生操作。

## 2026-07-29 — 检查点 068：选择事件与属性文字定位修复获批

- 用户实机反馈：频繁点击同一单位时名称会先空再恢复；切换多个角色后攻速图标对应的权威文字会越来越向上偏移；选择刷新不够即时，应由 UI 选择事件推动。
- 用户批准最小方案，并确认攻速/护甲文字右端与对应图标左端间距先采用 4px。
- 已确认名称根因：两个 Valve 选择事件无条件调用 `beginUnitNameTransition()`；该函数在判断 entindex 是否变化前先隐藏名称、写空名称并清空快照，因此同单位重复事件也制造空帧。
- 已确认刷新事实：`refreshHeroPanel()` 末尾仍永久 `$.Schedule(0.25, refreshHeroPanel)`；已有 `ui_selected_unit_stats_request/snapshot` 即时链和 NetTable 更新链，可以让名称、头像和战斗属性改为事件驱动。
- 已确认持续数据边界：生命/魔法没有等价的现成 Panorama 属性变化事件，保留仅更新生命/魔法的轻量循环；不得继续让该循环重做名称、头像、Tooltip 绑定和服务端属性请求。
- 已确认定位事实：`positionRelativeToOfficialPanel()` 当前只锚定 `AttackSpeed/Armor` 外层面板，并使用固定右对齐、22px margin 和 180px 宽度，没有读取真实图标几何。切换时 Valve 复用/重建属性行会使该关系不稳定。
- 实施决定：保留 `0/0.016/0.05/0.10/0.20s` 有限选择重试以等待 portrait unit 更新，但重试期间不清空 UI；只有 entindex 真正变化时刷新一次。攻速/护甲改为 `findIcon(statPanel)` 的窗口坐标转 `stats_container` 局部坐标，文字右端固定在图标左侧 4px并垂直居中。
- 修改边界：只改 `content/.../combat_stats.js` 和对应 game 编译产物；不改 XML、CSS、Lua、服务端请求语义或其他 UI。
- 尚未验证：JS 编译、源码契约、限定差异和 Workshop Tools 实机结果。
- 下一步唯一动作：实施单文件局部修复并强制定向编译。

## 2026-07-29 — 检查点 069：选择事件与属性文字定位修复完成

- 名称闪空修复：新增 `observedSelectedUnit`；Valve `selected_unit/query_unit` 事件仍使用 `0/0.016/0.05/0.10/0.20s` 有限重试等待 portrait unit 更新，但只有当前 entindex 与已观察 entindex 不同时才执行一次完整刷新。同单位重复事件不再隐藏名称、不写空名称、不清空快照、不重绑 Tooltip，也不重新请求权威属性。
- 事件驱动修复：`refreshHeroPanel()` 移除永久 `0.25s` 自调度，选择变化时立即同步解析名称/头像/等级/生命魔法，并发送 `ui_selected_unit_stats_request`；`ui_selected_unit_stats_snapshot` 和 NetTable 到达后继续即时覆盖权威属性。
- 持续数据边界：新增 `refreshHeroVitalsTick()`，仅每 0.25 秒读取当前单位生命/魔法并更新文本和填充宽度；不执行名称、头像、Tooltip 绑定、属性定位或服务端请求。
- 属性定位修复：`positionRelativeToOfficialPanel()` 改为通过现有 `damageIconAnchor(statPanel)` 找到攻速/护甲真实图标；图标窗口坐标和高度按 `stats_container` UI scale 转换为局部单位，文字右端固定在图标左侧 4px，并按图标垂直居中。移除固定 `horizontalAlign=right + marginRight=22px` 的不稳定布局。
- Valve 布局兼容：同一选择事件的后续有限回调只调用 `writeOfficialAttackText()` 和 `writeOfficialSecondaryStats()` 重新定位，等待 Valve 属性行稳定；不会清空 UI、请求快照或形成永久扫描。
- 编译验证：`combat_stats.js` 强制定向编译返回 `OK: 1 compiled, 0 failed, 0 skipped`；game 产物 `combat_stats.vjs_c` 为 72018 字节，时间 `2026-07-29 21:46:15`。
- 源码验证：`FINAL_SELECTION_EVENT_ICON_ANCHOR_PASS`，逐项确认同单位守卫、旧名称清空路径删除、完整 0.25 秒轮询删除、生命/魔法轻量循环保留、真实图标锚定和 4px 间距。
- 限定检查：`COMBAT_STATS_DIFF_CHECK_PASS`；未修改 XML、CSS、Lua 或服务端请求语义。
- 尚未验证：助手无法直接观察 Workshop Tools；需要用户完全停止当前 Run 并重新启动后连续点击同一单位、快速往返切换英雄/建筑/农民，确认名称无空帧、属性即时切换且攻速/护甲文字不漂移。
- 下一步唯一动作：用户实机验收上述三项行为。

## 2026-07-29 — 检查点 070：属性原文闪烁、装备刷新与拾取归属修复获批

- 用户实机反馈：当前名称刷新及时；攻速/护甲权威文字与可见图标视觉间距约 20px；切换单位时 Valve 原始攻速/护甲 Text 会短暂闪现；购买装备后选中英雄防御等属性不实时刷新；召唤英雄拾取物品时原生特效错误出现在建造者头顶。
- 用户批准按调查方案开始修复，并要求继续保持最小修改量。
- 间距调查结论：项目 Label 已内联 `textAlign=right`，不是未右对齐；当前 `damageIconAnchor()` 返回递归遇到的第一个 Image，可能命中大背景、外框或带透明留白的容器，导致数学 4px、视觉约 20px。修复为候选筛选，优先合理小尺寸且最靠右的真实图标，保留 4px 公式。
- 原文闪烁根因：`writeOfficialSecondaryStats()` 在项目快照未匹配时显式恢复 Valve Label 为 visible。修复为官方攻速/护甲 Label 始终 collapse，项目值未准备好时只隐藏项目 Label。
- 装备刷新结论：服务端装备聚合、`EQUIPMENT_STATS_CHANGED`、英雄战斗快照推送链存在；客户端 `combat_stats.js` 未监听最终 `ui_weapon_synthesis_snapshot`。修复为该事件到达后强制请求当前选中单位权威属性一次。
- 拾取归属结论：`resolve_item_pickup_hero()` 当前无条件信任事件 `HeroEntityIndex`，召唤英雄场景可能返回玩家原生建造者，从而永远不进入 summon 回退。修复为枚举事件英雄、权威召唤英雄和原生英雄候选，优先返回实际持有 item 的 0～8 槽单位，并在 Claim/七宗罪返回前将 purchaser 绑定实际拾取者。
- 修改边界：`content/.../combat_stats.js`、`scripts/vscripts/addon_game_mode.lua`、对应编译产物和定向契约；不改装备数值语义、库存事务、合成逻辑或显式创建新拾取粒子。
- 下一步唯一动作：实施两个目标文件的局部修改，强制编译 JS 并执行源码/Lua 契约与限定差异检查。

## 2026-07-29 — 检查点 071：属性原文、装备刷新与拾取归属修复完成

- UI 图标锚点：`damageIconAnchor()` 不再返回递归遇到的第一个 Image；现在收集子树候选，限定可见且布局尺寸 6～40px，按窗口 X 从右到左、同 X 时面积从小到大选择。项目 Label 仍为右对齐，继续使用文字右端距真实图标左端 4px 的公式。
- Valve 原文压制：`writeOfficialSecondaryStats()` 在项目快照未匹配时也调用 `setNativeStatLabelsVisible(..., false)`；攻速和护甲原始 Label 不再临时恢复，因此切换单位时不应闪现旧值。
- 装备 UI 刷新：客户端新增 `ui_weapon_synthesis_snapshot` 监听；最终装备快照到达且属于本地玩家时，对当前选中单位调用 `requestSelectedUnitStats(unit, true)`，在装备聚合完成后重新拉取权威攻击/攻速/护甲。
- 拾取实际持有者：`addon_game_mode.lua` 新增 `item_slot_for()`；`resolve_item_pickup_hero()` 枚举事件英雄、权威召唤英雄和玩家原生英雄并去重，优先返回 0～8 槽实际持有 item 的候选，日志 source 增加 `_holder`。
- 拾取身份：槽位验证成功后、七宗罪直接返回或 Claim 前调用 `item:SetPurchaser(hero)`，把物品 purchaser 绑定到实际拾取者；未新增自定义拾取粒子，也未改变库存登记/Claim/合成语义。
- 编译：`combat_stats.js` 最终强制定向编译返回 `OK: 1 compiled, 0 failed, 0 skipped`；产物已刷新。
- 自动验证：`HUD_EQUIPMENT_PICKUP_CONTRACT_PASS`、`PICKUP_ACTUAL_HOLDER_CONTRACT_PASS`、`COMBAT_STATS_DIFF_CHECK_PASS`、`PICKUP_DOCS_DIFF_CHECK_PASS`。
- 环境限制：当前 Shell 没有独立 Lua/LuaJIT 解释器，未虚报 Lua 运行测试；Lua 修复通过源码顺序契约和限定差异检查。
- 尚未验证：Valve 原生拾取特效由引擎播放，代码只能修正实际拾取者解析和 purchaser；是否完全改变特效 attachment 必须由 Workshop Tools 实机确认。
- 下一步唯一动作：完全停止当前 Run 并重新启动，验收四项实机行为。

## 2026-07-29 — 检查点 072：combat_stats.js 编码事故恢复完成

- 用户运行时报错：`combat_stats.js line 29` 的 `enemy_tree` 中文字符串变为 `鏍?` 且引号损坏，Panorama 报 `Invalid or unexpected token` 并跳过脚本剩余内容；后续 HUD/网格初始化同时缺失。
- 根因确认：上一轮 PowerShell 整文件读写把 UTF-8 中文错误按 CP936/GBK 解码后重新写成 UTF-8，造成整文件乱码和 18 处不可逆替换字符；不是单独一行逻辑 Bug。损坏差异曾达到 `262 additions / 119 deletions`。
- 安全措施：未执行整文件 Git checkout/reset，避免丢失多轮未提交协作修改；损坏文件备份为 `.cline_tmp/combat_stats_corrupt_20260729_2253.js`。
- 恢复方法：对乱码执行 CP936 字节到 UTF-8 的逆向恢复，生成 `.cline_tmp/combat_stats_recovered_preview.js`；逐行修复 18 处不可逆字符和被注释吞并的语句，并整体重建 `bindHotkeys()`、`bindHeroPortrait()` 两个受损函数。
- 保留内容：名称事件去重、生命/魔法轻量刷新、真实图标候选筛选、Valve 原始 Text 永久压制、`ui_weapon_synthesis_snapshot` 装备刷新监听等已确认逻辑全部保留。
- 正式恢复：恢复预览以 UTF-8 无 BOM 覆盖 content 源文件；第29行现为合法的 `"enemy_tree": "树",`，第30行为 `"npc_dota_hero_undying": "建造者"`。
- 编译证据：正式 `combat_stats.js` 强制定向编译返回 `OK: 1 compiled, 0 failed, 0 skipped`；game 产物 `combat_stats.vjs_c` 为 74645 字节，时间 `2026-07-29 23:10:13`。
- 验证证据：`COMBAT_STATS_ENCODING_RECOVERY_PASS`、`COMBAT_STATS_RECOVERY_DIFF_CHECK_PASS`；全文件残留乱码/替换字符为 0，`bindHotkeys()` 与 `bindHeroPortrait()` 各仅一份。
- 长期禁止：对含中文的 Panorama/Lua 源码禁止再使用会隐式解码再整文件写回的 `Get-Content/Set-Content` 或默认编码路径；应使用字节级复制、明确 UTF-8 严格读取，或局部补丁工具。
- 尚未验证：需完全停止当前 Run 并重新启动，确认异常消失、HUD 与网格恢复加载，再继续验收上一轮四项视觉/拾取行为。
- 下一步唯一动作：用户完全重新启动地图并回报是否仍有 JS Exception。

## 2026-07-29 — 检查点 073：炙热巨箭塔 LV1 完整路径碰撞伤害修复完成

- 用户明确规则：炙热巨箭特效碰到任何敌方单位都造成伤害；碰撞面积与特效宽度一致；只计算 XY 平面、不考虑地形高低差；路径上的怪物全部受伤；伤害沿用已有攻击伤害计算链。
- 根因一：旧移动波以普通攻击主目标位置作为 `max_distance`，到达主目标后立即结束；主目标后方仍被视觉波覆盖的怪物不再进入碰撞扫描。
- 根因二：旧碰撞调用把普通攻击主目标作为 `excluded` 传入几何模块；如果主目标前没有其他怪，会表现为整条路径没有额外伤害。技能权威描述为“巨箭对路径上的敌人造成100%伤害”，没有主目标例外。
- 根因三：旧碰撞间隔为 `0.03s`，而共享调度器实际以 `0.05s` 驱动；逻辑碰撞前沿可能落后于按 1200 速度移动的视觉特效。
- 实施：`tower_special_skill_system.lua` 让巨箭从塔的位置沿本次目标方向移动到防御塔当前 `GetAttackRange()`，与 `modifier_tower_auto_attack` 的权威索敌范围一致；无有效接口时回退统一全局塔射程。
- 宽度：视觉粒子 CP2 与碰撞扫描共用半宽 `110`；生产几何再叠加敌人模型 hull，表示敌人模型边缘碰到特效即可命中。
- 地形：生产 `tower_skill_geometry.lua::distance_to_segment()` 只读取 `x/y`，不读取 `z`；正负高地单位均按俯视二维路径命中。
- 伤害：继续使用 `modifier_tower_attack_effects::OnAttackLanded()` 已计算的 `payload.damage`，再乘技能配置 `damage_multiplier=1`，通过既有 `TOWER_SKILL_DAMAGE_REQUEST -> damage_service` 物理伤害链结算；未创建第二套攻击公式。
- 命中：不再排除存活主目标；路径波接触主目标时也结算一次路径伤害。主目标若已被普通攻击击杀，则生产几何的存活过滤自然跳过。每支波通过 `hit[entindex]` 保证每个单位最多命中一次。
- 生命周期：碰撞间隔改为与共享调度器一致的 `0.05s`，视觉速度和逻辑步长同步；波到达完整攻击距离后结束，塔被销毁时取消该塔全部活动波。
- 回归：扩展 `test_tower_wave_of_terror_visual.lua`，覆盖延迟接触、主目标、主目标后方、不同 Z 高度、宽度边缘、范围外单位、单波去重、致死主目标和塔销毁取消。
- 新增：`test_tower_skill_geometry.lua` 直接测试生产几何，确认中心线、高低差、宽度加模型 hull、主目标排除参数和路径终点边界。
- 明确通过：`TOWER_WAVE_OF_TERROR_VISUAL_PASS`、`TOWER_SKILL_GEOMETRY_PASS`、`TOWER_MULTI_VISUAL_CONFIG_PASS`、`SCHEDULER_RESTART_PASS`。
- 全量结果：41 项 Lua 测试中 38 项通过；3 项既有无关失败为 `test_hero_combat_stat_projection.lua`、`test_hero_summon_owner.lua`、`test_tree_progression.lua`，分别属于英雄攻速投影、召唤英雄血条和树木等级配置，与本次三个防御塔文件无代码关联。
- 环境说明：Git 只读命令受已知终端桥接超时影响，未虚报 `diff --check` 或状态结果；最终源码、生产几何和测试均已通过 `read_files` 复核。
- 下一步唯一动作：完全停止当前 Run 后重新启动，用同一路径放置主目标、主目标后方怪物和不同高地怪物，确认特效接触时各扣除一次现有攻击力伤害。

## 2026-07-29 — 检查点 073：护甲与攻速完全统一攻击力数字格式

- Git 检查：当前位于 `dev`，`dev/dev_jyd/origin/dev/origin/dev_jyd` 均指向 `35f27a8`，切换分支未丢失已提交工作；工作区实施前干净。
- Stash 检查：`stash@{0}` 仅含 `tools_asset_info.bin`；`stash@{1}` 含较旧的 `combat_stats.vjs_c`、本地化和工具缓存。两项均未应用或删除，避免旧编译产物覆盖当前 HUD。
- 用户确认：护甲和攻速完全照搬攻击力数字文本的样式与定位方式，但护甲 War3 显示值、攻速每秒攻击次数及默认值语义保持不变。
- 源码修改：新增 `applyAuthoritativeNumberStyle()`，攻击、攻速、护甲统一复用 `MonoNumbersFont`、`StatRegionLabel`、14px、`#cccccc`、180px 宽度、右对齐和不可命中设置。
- 定位修改：新增 `nativeNumberAnchor()` 与 `positionRelativeToNativeNumber()`；三项均根据各自原生数字 Label/LabelContainer 的窗口 Y 坐标，使用攻击力既有的 `horizontalAlign=right`、`marginRight=22px`、固定宽度和行高公式。删除攻速/护甲专用的图标左侧 4px 定位函数。
- 数值边界：未修改 `attackText()`、护甲 `formatNumber(snapshot.armor)` 或攻速配置值与 `0.5` 回退逻辑；Valve 原生攻速/护甲 Label 等待期压制保持不变。
- 编译证据：`resourcecompiler.exe -f` 返回 `OK: 1 compiled, 0 failed, 0 skipped`；game 产物 `combat_stats.vjs_c` 为 72432 字节，时间 `2026-07-29 23:52:24`。
- 尚未验证：自动编译不能代替 Workshop Tools 视觉结果；需完全停止当前 Run 并重新启动，快速切换英雄、建筑和农民，确认三项文字格式一致且护甲/攻速行位置正确。

## 2026-07-30 — 检查点 074：攻速与护甲自定义 Text 消失回归修复

- 用户实机证据：属性区域只剩攻速与护甲图标，两个数字均完全消失；用户明确指出官方 Text 之前已隐藏，必须显示项目自己的 Text。
- 根因确认：真正应显示的是 `stats_container` 下项目创建的 `SurvivalAuthoritativeAttackSpeedLabel` 和 `SurvivalAuthoritativeArmorLabel`。上一轮 `applyAuthoritativeNumberStyle()` 每次刷新都先将项目 Label 设为 collapse，随后又依赖已被 `setNativeStatLabelsVisible(..., false)` 隐藏的官方 Text 作为锚点；锚点失败会在写值和设 visible 前提前返回。
- 修复：共享样式函数不再修改 visibility；项目 Label 只在首次创建或权威快照不匹配时 collapse。攻速/护甲改由 `positionRelativeToStatRow()` 使用官方 `AttackSpeed`/`Armor` 行面板的窗口 Y 坐标定位，但实际写值和显示的始终是两个 `SurvivalAuthoritative...Label`。
- 保留边界：官方攻速/护甲 Text 继续永久隐藏；攻击力定位、护甲 War3 显示值、攻速每秒次数与 0.5 回退均未修改。
- 编译证据：`resourcecompiler.exe -f` 返回 `OK: 1 compiled, 0 failed, 0 skipped`。
- 下一步：完全停止当前 Workshop Tools Run 并重新启动，确认两个项目数字恢复显示，再检查其与攻击力数字的横向格式和各自行纵向位置。

## 2026-07-30 — 检查点 075：炙热巨箭原生线性穿透方案实机验收成功

- 用户最终实机确认：“终于成功了”。同一炙热巨箭特效路径上的第一、第二及后续敌方单位现在都能分别受到伤害。
- 历史结论纠正：2026-07-29 检查点 073 记录的 `scheduler.every + tower_skill_geometry.enemies_in_path()` 手写二维移动扫描方案虽然 mock 测试通过，但实机仍只伤害第一个怪物；该方案已被实机证据否定，不再是炙热巨箭的有效实现基线。
- 关键测试盲区：旧 `test_tower_wave_of_terror_visual.lua` 通过替换 `tower_skill_geometry`，人工让一次扫描返回多个单位，只证明 Lua `for` 循环会遍历数组；它没有证明 Dota 引擎会在同一移动视觉上连续报告第二、第三个单位，也没有覆盖投射物命中后的删除语义。
- 粒子取证：本机原始 `vengeful_arcana_wave_of_terror_v2.vpcf` 使用 CP1 作为视觉速度；唯一碰撞相关操作器为 `C_OP_MovementPlaceOnGround` 和 `DEBRIS` 场景组，只负责地面贴合，不会检测敌方单位，也不会向 Lua 触发单位命中回调。视觉粒子不能直接作为伤害碰撞体。
- 官方样例依据：Dota 自带 `conquest/scripts/vscripts/breathe_fire.lua`、`breathe_poison.lua` 通过 `ProjectileManager:CreateLinearProjectile()` 创建单位碰撞，并在 `OnProjectileHit` 末尾 `return false` 以继续穿透后续单位。
- 最终实现：`tower_special_skill_system.lua` 的炙热巨箭改为原生线性投射物；使用 Wave of Terror 作为 `EffectName`，速度 `1200`、距离 `1200`、起止半径 `112`，敌方英雄与普通单位目标过滤，`bDeleteOnHit=false`，不提供视野。
- 多目标命中：每次发射建立唯一 `burning_wave_id`，将权威 `payload.damage * damage_multiplier`、能力句柄和 `hit[entindex]` 保存到活动波状态；共享被动能力的 `OnProjectileHit_ExtraData` 按 `ExtraData` 分流，每次单位回调提交一次伤害并返回 `false`，不会在第一个单位处删除。
- 伤害契约：路径伤害显式为 `DAMAGE_TYPE_PHYSICAL`，继续通过 `TOWER_SKILL_DAMAGE_REQUEST -> tower_skill_effect_adapter -> damage_service -> ApplyDamage`；所有目标基础公式相同，最终扣血分别由各自物理护甲决定。`tower_skill_effect_adapter` 现会继续传递 ability 句柄。
- 时机与地形：命中由引擎线性投射物的空间碰撞前缘触发，不再使用固定提前 `0.3s`；投射方向清零 Z，单位过滤由投射物沿平面路径完成，不以地形高度差作为伤害延迟依据。
- 生命周期：投射物终点、塔销毁和系统重载都会清理活动波；同一单位每支箭最多受伤一次。基于 `距离 / 速度 + grace` 的调度任务只用于状态兜底清理，不参与碰撞判断。
- 回归：重写 `test_tower_wave_of_terror_visual.lua`，捕获真实 `CreateLinearProjectile` 参数，并用同一 `ExtraData` 依次调用第一、第二、第三个单位的能力命中回调；验证三次伤害、三次 `return false`、单波去重、致死主目标后继续命中、终点清理和塔销毁。
- 自动验证：`TOWER_WAVE_OF_TERROR_VISUAL_PASS`、`TOWER_SKILL_GEOMETRY_PASS`、`TOWER_MULTI_VISUAL_CONFIG_PASS`、`SCHEDULER_RESTART_PASS` 及相关 Lua 语法检查通过；全量循环中的炙热巨箭测试通过。另有英雄攻速投影、召唤英雄血条、树等级配置三项既有无关失败。
- 完整技术复盘：`docs/ai/archive/2026-07-30-burning-great-arrow-linear-projectile.md`。

## 2026-07-30 — 检查点 076：多重塔与穿透弩炮缺失饰品组修复完成

- 用户实机截图：多重塔只显示 Medusa 主体，`Jewels of Anamnessa` 五件附件全部缺失；穿透弩炮只显示 Drow Arcana 主体，`Dread Retribution` 七件附件全部缺失；同一系统中的 Vengeful 四件 `prop_dynamic` 附件显示正常。
- 根因：Medusa 与 Drow 资产把 `attachment_entity_class` 配成了 `dota_item_wearable`。当前自定义建筑附件生成链不能依赖该实体类型稳定创建饰品；服务已有失败回退，但只有生成调用抛错或返回无效实体时才触发，静默创建但不渲染时不会回退。
- 修复：在权威源 `data/csv/资源系统/asset_catalog.csv` 中把 Medusa 五件组和 Drow 七件组的附件实体类型改为 `prop_dynamic`，并由真实 Python 3.13 解释器重新生成 `scripts/vscripts/config/generated/asset_catalog.lua`。附件模型路径、主体模型、弹道、环境粒子、技能和数值均未修改。
- 已有生产契约继续复用：`building_visual_service.lua` 为每件附件执行 `SetOwner(unit)` 与 `FollowEntity(unit, true)`；该 `prop_dynamic` 骨骼跟随路径已由 Undying 和当前正常显示的 Vengeful 饰品实机证明。
- 自动验证：配置生成器返回 `SUCCESS: generated 60 Lua config modules`；`BUILDING_VISUAL_SERVICE_PASS`、`TOWER_MULTI_VISUAL_CONFIG_PASS` 和目标 Lua 语法检查通过；目标 `git diff --check` 通过。
- 全量回归：42 项中 39 项通过；3 项既有无关失败仍为英雄攻速投影、召唤英雄血条和树木等级配置，断言内容与检查点 075 记录一致。本任务直接相关测试全部通过。
- 下一步唯一动作：完全停止当前 Workshop Tools Run 并重新启动，分别创建多重塔与穿透弩炮，实机确认 Medusa 五件和 Drow 七件均显示且随攻击、转向和死亡动画正确骨骼跟随。

## 2026-07-30 — 检查点 076：英雄1～10转技能闭环第一阶段完成

- 用户确认的新规则：普通英雄1个专属技能、VIP英雄4个真正专属技能；开局全部锁定，一转挑战成功后解锁当前英雄全部专属技能；二至五转每转公共技能三选一且只选未拥有技能，选中项从本局池中移除；六至十转每转给1点技能点，技能点只能升级公共技能池技能，不能升级专属技能；所有技能最高3级。
- 初始锁定：`hero_initial_skills.csv` 数据行已清空，`hero_definitions.initial_skill_count` 统一为0；`hero_skill_system` 召唤时清除原技能后只同步回城/拾取工具技能，不再提前发放专属技能。
- 一转解锁：`hero_skill_choice_service.grant_exclusive()` 改为按当前英雄专属组批量发放所有 guaranteed 行；普通英雄各1项，齐天大圣与VIP剑圣各4项；重试时跳过已拥有项，避免部分成功后重复升级。
- VIP专属内容：齐天大圣新增斗战、神行、灵猴；VIP剑圣新增疾风剑意、迅影、踏风。当前复用已有属性 Modifier 和原版图标，不开发新特效；所有专属定义 `is_public=false`，技能点入口明确拒绝。
- 二至五转：选择规则限制为等级2～5、3选1、拒绝 owned；技能池服务只返回 `is_public=true` 且 `current==0` 的技能。候选只在选择成功后通过 owned 状态永久排除，未选两项仍可后续出现；同一玩家不能覆盖未完成 offer。
- 六至十转：奖励效果改为每转 `grant_skill_points=1`；升级服务必须同时满足技能定义启用、`is_public=true`、已拥有、未满3级和点数充足，校验成功后才扣点并同步 ability 等级。
- 技能栏：12个公共池技能全部补齐非空 ability_name 和三级被动 KV 壳；`hero_skill_system` 会把项目战斗技能顺序放入槽0开始，回城/拾取动态跟随在技能末尾，避免VIP四专属后新增公共技能与固定槽4/5冲突。`modifier_survival_hero_skill` 已显式 Link/require。
- 奖励时序：新增 `MONSTER_ENCOUNTER_COMPLETED`。`on_each_kill` 奖励仍消费击杀事件；转生 `on_encounter_complete` 奖励只消费完成事件，并按玩家+不可重复 reward profile 加幂等锁。
- 首批伤害复核：炎爆震击、冰霜新星、雷霆连锁继续使用触发时力量+敏捷+智力快照乘三级配置倍率，提交 `DAMAGE_TYPE_PURE`；次级多重攻击不触发，同 attack_id 去重，雷霆连锁目标去重。未新增或修改粒子。
- 配置生成：当前 Shell 无 `py/python`，使用 `.cline_tmp/build_target_configs.ps1` 定向生成本次8份 generated Lua，并保留 `hero_definitions.base_armor -> base_war3_armor` 正式别名语义；生成结果已逐项复核。
- 自动验证：`.cline_tmp/test_rebirth_skill_contract.ps1` 输出 `REBIRTH_SKILL_CONTRACT_PASS`；覆盖初始锁定、普通/VIP专属数量、2～5转规则、6～10转点数、公共/专属边界、12个池技能KV、奖励完成时序/幂等及前三技能伤害契约。限定 `git diff --check` 无错误；当前环境无 Lua 解释器，仍需 Workshop Tools 实机走一至六转验证真实技能栏和伤害。


## 2026-07-30 — 检查点 077：商店白名单与商店专用Tooltip切换完成

- Valve物品Tooltip只支持引擎ItemCost金币，不提供项目木材货币字段；未采用依赖Valve私有动态节点的木材注入方案。
- 商店动态图标关闭hittest/hittestchildren，外层卡片继续显示现有ShopEntryTooltip；该项目Tooltip已经同时显示木材、金币、购买条件和状态。背包与地面物品的官方Tooltip不受影响。
- shop_catalog.lua现在读取generated/shop_entries；普通shop模式仅投影shop_entries中enabled=true、content_id有业务定义且业务definition.enabled未停用的条目。
- shop_entries中的shop_entry_id、category_id、display_name、wood_cost、gold_cost、purchase_limit成为普通商店展示权威；实际物品效果、科技等级和挑战逻辑仍来自各业务定义表。
- 普通商店购买请求增加listed_in_shop服务端校验；research模式和gold_mine_ability路径不受普通商店白名单限制。
- 未列入shop_entries、shop_entries.enabled=0或业务定义停用的内容完全隐藏；仅资源不足的已陈列商品继续显示并置灰。
- 当前shop_entries启用31项，无重复content_id；具体科技等级ID为0项，因此截图中的灰色普通/高级科技等级卡会从普通商店消失。technology分类当前只保留提前通关服务。
- shop_ui.js相比本轮修改前只增加两行命中关闭；强制编译结果：OK: 1 compiled, 0 failed, 0 skipped。
- 验证：SHOP_WHITELIST_CONTRACT_PASS、SHOP_SOURCE_ENCODING_AND_RULES_PASS、SHOP_FINAL_CONTRACT_PASS、SHOP_COMPLETION_CHECK_PASS；Lua限定git diff --check通过。
- 后续维护：普通商店要显示具体科技等级时，在shop_entries.csv新增一行，content_id填写具体technology_id；修改后重新生成shop_entries.lua并重启地图。

## 2026-07-31 — 检查点 078：hero_definitions 中文乱码恢复与编码验证

- 用户报告：`hero_definitions` 表中的中文出现乱码，影响英雄显示名称和备注。实际权威源为 `data/csv/英雄系统/hero_definitions.csv`；生成产物为 `scripts/vscripts/config/generated/hero_definitions.lua`。用户随后确认英雄 `attack_speed = 1.5` 是正确数据，不应因旧测试期望 `2.0` 而修改配置。
- 根因：CSV 中的中文字段说明、五个英雄的 `display_name` 和 `notes` 已经被错误解码后保存为实际乱码，不是 VS Code 单纯显示编码问题。`hero_definitions.lua` 是自动生成文件，因此同步继承乱码。数值、ID、单位名、技能组和列结构未发现损坏。
- 恢复内容：从 Git 权威版本恢复 UTF-8 BOM 的源 CSV；五个名称为 `斧王`、`斯拉克`、`主宰`、`齐天大圣`、`剑圣`；普通英雄备注为“普通英雄，专属技能第一转职成功后解锁”；VIP 英雄备注为“VIP英雄，4个专属技能第一转职成功后解锁”。未修改英雄数值或单位映射。
- 生成链：PowerShell 7 安装后确认 `pwsh.exe` 为 `C:\Program Files\PowerShell\7\pwsh.exe`，版本 `7.6.4`；Python `3.13.14`、Lua `5.4.5`、Git `2.55.0` 可用。使用 `tools.build_configs.build()` 仅重建 `hero_definitions.lua`，输出 `HERO_DEFINITIONS_GENERATED`；禁止手工维护生成 Lua。
- 测试契约：扩展 `scripts/vscripts/tests/test_hero_combat_stat_projection.lua`，覆盖五个英雄的名称、VIP 身份和备注，并将过时的 VIP 攻速期望从 `2.0` 对齐到权威 CSV 的 `1.5`，没有改游戏配置。定向结果：`HERO_COMBAT_STAT_PROJECTION_PASS`、`HERO_DEFINITIONS_ENCODING_CONTRACT_PASS`；目标 Lua 语法检查和 `git diff --check` 通过；目标文件乱码搜索为 0。
- 全量回归：共运行 54 个 `scripts/vscripts/tests/test_*.lua`，51 个通过，3 个失败：`test_addhero_cheat.lua` 测试桩缺少 Dota 全局 `Vector`；`test_hero_passive_attribute_snapshot.lua` 仍按旧的原生三围读取契约；`test_hero_summon_owner.lua` 的统一血条断言与当前召唤实现/历史结果不一致。三项失败均未触及 `hero_definitions` 编码和本任务修改，不能标记为本任务回归通过。
- 复用经验：乱码排查先检查原始字节、BOM、`�`/`��`/`锟斤拷`，再比较 Git 权威源和生成产物；不要对损坏文件直接“转 UTF-8”或用默认编码整文件读写。配置恢复后必须依次执行单文件生成、Lua 语法检查、中文名称/列数/BOM 契约和限定 `git diff --check`，最后重启 Workshop Tools 地图加载新的 Lua 配置。

## 2026-07-31 — 检查点 079：机枪塔三阶段建模与技能视觉恢复并进入最终审计

- 用户要求从上下文超限的上一会话继续箭塔机枪路线建模与特效任务；已直接读取 `C:\Users\li\.cline\data\sessions\1785506625979_s9010`，确认上一轮不是未开始，而是已完成实施并在最终审计时中断。
- 当前实现：机枪塔 LV1～5 使用 Sniper Occultist's Pursuit 五件套；赏金机枪 LV1～5 使用 Bounty Hunter Heartless Hunt 六件套；爆矢加特林 LV1～10 使用 Windranger Compass of the Rising Gale Arcana 主体和五件套。
- 技能视觉：资源增加请求成功后在受击目标播放 Jinada/Cutpurse；爆矢加特林第五次同目标攻击或击杀成功应用/刷新 20%、3 秒攻速 Buff 时，在塔上播放 Focus Fire 起手，持续粒子由 Buff 配置管理。
- 生产引用审计：旧 `tower_gyro`、`tower_tinker`、`asset_proxy_tower_gyro`、`asset_proxy_tower_tinker` 在 `data`/`scripts` 生产范围内无匹配；新三套资产贯穿路线 CSV、生成 Lua、资产目录、代理单位与运行时。
- 自动验证：机枪视觉、资产 bundle、资产预加载、受管攻速 Buff、建筑视觉、箭塔完工、升级 Runtime、选中头像、多重塔、雷电塔、冰霜路线共 11 项定向测试通过；目标 Lua 语法和限定 `git diff --check` 通过。
- 全量回归：60 项中 57 项通过，既有失败仍为 `test_addhero_cheat.lua`、`test_hero_passive_attribute_snapshot.lua`、`test_hero_summon_owner.lua`，与本任务修改文件无交集。
- 最终审计发现并修正：`modifier_tower_attack_effects.lua` 中清空暴击来源与读取冰霜技能被误拼在同一行；语义未改变，改为两行以恢复清晰控制流。
- 尚未验证：Workshop Tools 中套装骨骼跟随、模型皮肤/主体显示、实际攻击弹道、Jinada 金币反馈和 Focus Fire 起手/持续视觉。
- 下一步唯一动作：完成生成配置逐字节一致性和最终限定测试，然后完全停止并重新 Run 实机验收三阶段路线。

## 2026-07-31 — 检查点 080：机枪塔建模与技能视觉自动审计完成

- 生成一致性：使用 `tools.build_configs.build()` 将 `tower_class_machine_gun`、`buff_definitions`、`asset_catalog`、`asset_components`、`asset_effects` 定向生成到临时目录；五份结果与正式 `config/generated` Lua 逐字节一致，输出 `MACHINE_GUN_GENERATED_COMPARE_PASS`。
- 最终回归：机枪视觉测试通过；共享攻击文件关联的死亡塔动画、选择、Templar 视觉和死亡榴弹四项测试全部通过；拼行修复后的目标 Lua 重新解析成功。
- 最终静态检查：本任务源 CSV、生成 Lua、代理 KV、资产运行时、建筑视觉服务、测试和交接文档的限定 `git diff --check` 通过，仅有既有 LF/CRLF 提示，无空白错误。
- 全量状态保持为 60 项中 57 项通过；3 个既有英雄测试失败名单未变化，没有把它们误报为本任务通过或回归。
- 自动实施与审计已完成；尚未确认的唯一范围是 Workshop Tools 中的真实视觉和生命周期表现。
- 下一步唯一动作：完全停止并重新 Run，分别创建机枪塔、赏金机枪和爆矢加特林，检查完整穿戴件、骨骼跟随、攻击弹道、金币到账 Jinada，以及第五次同目标攻击/击杀时 Focus Fire 起手和 3 秒持续视觉。

## 2026-08-02 - 最新恢复检查点：龙卷风阶段性完成（末尾索引）

- 用户确认公共技能 proto_void_pulse 的五级龙卷风任务暂时完成；当前实现作为阶段性可靠基线保留。
- 本次确认不代表最终优化完成或全部Workshop Tools实机验收通过；后续仍有优化空间。
- 当前没有活跃编码动作，不得自动继续修改龙卷风数值、行为或视觉。
- 稳定视觉架构：使用 particles/survival_tornado/survival_tornado_follow.vpcf，由Lua每0.05秒写CP0；不得恢复完整Invoker Tornado粒子的CP1直线推进方案。
- 下一步唯一动作：等待用户指定具体优化项或新的开发任务。
## 2026-08-02 - 检查点：原生英雄生命改用隐藏Modifier补足

- 用户实机确认前一版直接调用`SetBaseMaxHealth/SetMaxHealth/SetHealth`后英雄仍显示120，证明召唤原生英雄的基础生命会在引擎阶段被覆盖；用户批准改用类似装备生命加成的隐藏永久Modifier，并要求把经验写入docs。
- 实施决定：不创建真实隐藏物品，避免占用背包、进入逻辑库存/合成/Tooltip/存档；新增`modifier_survival_hero_base_health`，通过`MODIFIER_PROPERTY_HEALTH_BONUS`补足CSV目标生命。
- 补足公式：先从当前最大生命扣除该Modifier已有旧补足值，得到原生基线，再计算`max(0, configured_target - native_baseline)`；禁止固定加3000，否则原生120会得到3120。
- 生命周期：Modifier隐藏、不可驱散、死亡不移除、重复应用更新同一实例而不叠加；添加/刷新时使用`hero_health_guard.preserve_missing()`，首次召唤保持满血，未来刷新保持已损失生命。
- 装备边界：基础生命Modifier先应用到CSV目标，之后真实`modifier_equipment_effects.health_flat`继续独立叠加。
- 下一步：注册并实现Modifier，移除直接SetHealth最终方案，更新专项测试、契约和AI维护文档，执行完整限定验证。

## 2026-08-02 - 隐藏基础生命Modifier实现与自动验证完成

- 新增并注册`modifier_survival_hero_base_health`：隐藏、不可驱散、永久、死亡不移除，通过`MODIFIER_PROPERTY_HEALTH_BONUS`返回StackCount补充值。
- `hero_stat_adapter.apply_configured_health()`不再调用基础/最大/当前生命Setter作为权威实现。它从当前最大生命扣除旧Modifier补充值得到原生基线，再计算`max(0, target-native)`；通过`hero_health_guard.preserve_missing()`创建或刷新同一Modifier并执行属性重算。
- 普通英雄原生120时补充值为2880，最终目标3000；重复应用仍为2880而不叠加；从3000目标切换到VIP 11000目标时补10880，并保持原有已损失生命。
- `hero_combat_stat_service`诊断扩展为`configured/native/bonus/engine_max/engine_current`；真实装备生命Modifier仍在基础生命Modifier后创建并独立叠加。
- 验证通过：`HERO_CONFIGURED_HEALTH_LUA51_PASS`、`HERO_HEALTH_CONTRACT_PASS`、`HEALTH_CHEAT_LUA51_PASS`；元气弹、毒云、addskill、原生血条相关回归通过；新增/修改Lua通过Lua 5.1语法检查。`modifier_registry.lua`保留既有UTF-8 BOM，并通过临时去BOM副本完成Lua 5.1语法检查；严格UTF-8与BOM保持检查通过。
- 尚未完成：Workshop Tools第二次实机验证。自动测试不能替代原生英雄生命Modifier的引擎表现。

## 2026-08-02 - 隐藏基础生命Modifier用户实机验收成功

- 用户明确反馈：“血量现在正常”，确认`modifier_survival_hero_base_health`第二版在Workshop Tools实际引擎中生效。
- 本次实机结果证明：对于`CreateUnitByName`召唤的原生英雄，CSV目标生命应保留为配置权威，但引擎投影必须使用隐藏永久`MODIFIER_PROPERTY_HEALTH_BONUS`补足，不能依赖直接生命Setter。
- 成功方案的关键边界：动态补足而非固定加3000；扣除旧补充值保证幂等；不创建真实隐藏装备；真实装备生命保持独立叠加；使用`preserve_missing()`保护当前已损失生命语义。
- 验收范围准确限定为“英雄血量现在正常”。用户没有在本次反馈中分别确认普通英雄3000、VIP英雄11000、装备生命叠加、死亡重生或`blood`四种输入，因此这些不得写成已实机通过，只作为按需防回归项。
- 维护结论：隐藏基础生命Modifier方案成为可靠生产基线；直接`SetBaseMaxHealth/SetMaxHealth/SetHealth`方案永久记为失败路径，不得恢复。

## 2026-08-02 - 检查点：陨石坠落五级重做获批实施

- 用户要求开始制作“陨石坠落·被动”：LV1攻击12%概率触发、500范围全属性×3；LV2落地留下3秒熔岩且每秒全属性×1；LV3区域内减速30%；LV5连续两颗且第二颗伤害80%；技能自身造成伤害期间不得再次触发。
- 调查确认旧`proto_meteor`是三级占位实现（8%/13%/20%、0.8秒延迟、低倍率、旧灼烧与眩晕），与新需求冲突；保留`proto_meteor`、`ability_survival_meteor`、公共池身份和图标，整体替换旧数值与行为。
- 用户选择方案A：不滚动；第一颗落在触发时目标位置，第二颗在同一位置晚0.5秒落地；第二颗爆炸和熔岩均为80%；每颗熔岩在落地后第1/2/3秒结算三次；锁持续到最后一颗熔岩结束。
- 补充确认：LV4完整继承LV3；两片熔岩独立伤害但30%减速不叠加；LV1爆炸完成即解锁；锁在概率判定和随机数之前检查，只限制同一英雄的陨石技能，不影响其他公共被动。
- 实现约束：使用触发瞬间逻辑三维快照、现有`deal/deal_group`伤害事务、`enemies_touching_radius` Hull边缘精确AOE、共享Scheduler区域状态和CSV权威配置。
- 工作区变化核对：调查阶段的大量tracked修改已进入提交`c36c56e`；`hero_passive_skill_service.lua`工作区哈希与HEAD哈希均为`3648457b1d2b14e7bd0d615572f5d43ce6bf8b37`，确认不是回滚或意外未提交覆盖，可以在新HEAD上继续。
- 下一步：修改权威CSV与运行配置，定向生成三份Lua，实现陨石状态/锁/熔岩/减速/视觉，补齐KV、Tooltip与专项测试后执行限定验证。

## 2026-08-02 - 陨石坠落实现与自动验证完成

- 配置完成：`hero_skill_definitions.csv`将`proto_meteor`改为五级并更新描述；运行配置同步12%触发、×3爆炸、500半径、0.8秒坠落、3秒熔岩、每秒×1、30%减速、LV5双陨石0.5秒间隔和第二颗80%；Ability KV最高等级改为5，Tooltip发布接入五级行。
- Buff完成：权威`buff_definitions.csv`新增`debuff_hero_meteor_lava_move_slow`，类型为`negative + none + aura`、默认`move_speed_pct=-30`；多个熔岩区域通过共享期望集合只施加一次，离开全部区域立即移除。
- 运行完成：旧三级延迟AOE、中心眩晕和`periodic_area`已移除；新实现使用每英雄独立活动状态和共享0.05秒Scheduler，Lua插值控制基础投射物从1200高度坠落，落地播放基础爆炸，熔岩复用已预缓存的Viper Nethertoxin地面粒子。视觉不承担伤害碰撞。
- 时序完成：目标位置和逻辑三维均在触发时快照；第一颗落地后LV1立即解锁，LV2以上在`land_at+1/2/3`各结算一次熔岩；LV5第二颗同点晚0.5秒落地，爆炸×2.4、熔岩每次×0.8，最后一次结算后解锁。锁在随机判定前检查，不影响不同英雄或其他被动。
- 生成完成：通用生成模块定向重建`hero_skill_definitions.lua`和`buff_definitions.lua`，Tooltip专用生成器重建CSV/Lua；差异仅为陨石目标行和新增Buff行。`METEOR_GENERATED_COMPARE_PASS`证明两份通用生成Lua与临时定向重建逐字节一致。
- 验证完成：`METEOR_STATE_LUA51_PASS`、`METEOR_CONTRACT_PASS`、`METEOR_LUAC_PASS`、`METEOR_STRICT_UTF8_PASS`；奥术弹幕、寒冰锥、魔法弹弓、爆炎弹、移动冰球、毒云、元气弹、脉冲激射和龙卷风专项回归全部通过。
- 尚未验证：Workshop Tools中的实际坠落外观、粒子大小/颜色、双陨石落地手感、500范围视觉匹配、最终引擎扣血和减速表现。自动测试不得描述为实机验证。

## 2026-08-02 - addmonster移速提高用于陨石减速实机辨识

- 用户反馈“移速降低20%不明显”，要求若减速已实现则把`addmonster`单位移速设为600进行测试。
- 复核确认陨石不是20%而是LV3-LV5固定30%：运行配置`lava_move_slow_pct`、权威Buff CSV、生成Buff和Lua状态测试均一致；区域进入应用`value=-30`，重叠不叠加，离开全部区域移除。
- `addmonster`原本对可攻击调试怪硬编码`SetBaseMoveSpeed(250)`；现改为调试常量600，并挂载隐藏不可驱散的`modifier_debug_move_speed_cap`，通过`MODIFIER_PROPERTY_MOVESPEED_MAX/LIMIT`将该调试实例上限提高到600。Modifier不提供绝对移速，因此陨石百分比减速仍参与最终速度；生成通知和日志同步输出移速。显式不可攻击模式继续设置0移速且不挂载上限Modifier。
- 修改仅作用于`addmonster`创建的实例；没有修改`monster_archetypes.csv`、生成怪物配置或`npc_units_custom.txt`，正常波次、挑战和遭遇怪移速保持原值。
- 下一步：冷启动实机使用默认`addmonster`（默认可攻击）观察进入陨石熔岩前后的速度差异；600基础速度在30%减速下理论对比为约600到420，最终引擎显示和速度上限以实机为准。

## 2026-08-02 - 用户确认陨石减速与addmonster测试基准正常

- 用户实机反馈“现在没问题了”，确认可攻击`addmonster`使用600基础移速及600移速上限后，陨石LV3-LV5熔岩30%减速能够正常观察且行为符合预期。
- 本次确认范围是`addmonster`高速测试基准和陨石熔岩减速专项；不得扩大描述为陨石视觉、伤害、双陨石时序及活动锁均已逐项验收。
- 稳定经验：当百分比移速变化在约250的低速怪物上不明显时，可提高调试实例的基础移速并同步解除引擎移速上限，以放大前后差异；上限Modifier不能设置绝对速度，否则可能掩盖被测百分比减速。
- 修改必须限定在调试生成实例，不得为了测试可见性改变`monster_archetypes.csv`、生成怪物配置或`npc_units_custom.txt`，避免污染正常怪物平衡。
- 用户已确认该问题无须继续调整；后续不得因旧的“减速不明显”记录重复实现或擅自改回20%。

## 2026-08-02 - 检查点：地裂冲击五级滚石重做获批实施

- 用户要求制作现有公共技能“地裂冲击·被动”；调查确认应保留`proto_earth_line`、`ability_survival_earth_line`、公共池成员`public_06`、图标与存档身份，将当前三级空壳扩为五级。
- 最终规则：LV1主攻击命中12%概率触发；触发瞬间固定英雄位置为起点、被攻击目标位置为终点，滚石以500码/秒直线移动且不追踪；总宽150，路径真实命中造成触发时逻辑全属性×3纯粹伤害，命中前已被任意来源眩晕则×6；终点爆炸仅为视觉。
- LV2总宽提高到250；LV3起每个路径真实命中单位在伤害后独立30%概率眩晕1秒；LV4完整继承LV3。
- LV5首次真实命中敌人时，以命中位置为中心对300范围额外造成全属性×3纯粹伤害；范围内每个单位按结算前旧眩晕独立翻倍，首敌同时承受路径与范围伤害。额外范围只触发一次，滚石继续穿透至终点；仅路径真实命中单位参与30%新眩晕，范围波及单位不参与。
- 实现约束：权威配置先改CSV并生成Lua；真实路径碰撞使用`CreateLinearProjectile`、`bDeleteOnHit=false`、唯一滚石ID、逐单位去重、回调`return false`和终点/超时清理；伤害复用逻辑属性快照与既有纯粹伤害事务。
- 工作区已有大量非本任务修改和未跟踪测试文件；只做最小增量，不回滚、删除或整理既有修改。
- 下一步：修改权威技能/Tooltip CSV并定向生成，再实现运行配置、线性投射物、KV、Tooltip、预缓存与专项测试。

## 2026-08-02 - 地裂冲击实现与自动验证完成

- 配置与生成完成：权威`hero_skill_definitions.csv`将`proto_earth_line`从三级扩为五级并更新说明；Tooltip权威CSV同步；使用`tools.build_configs.build()`定向生成英雄技能Lua，Tooltip按项目既有定向单行生成方式更新，避免全量生成器规范化历史无关行。英雄技能生成结果逐字节一致，Tooltip生产文件相对基线仅改变目标行。
- 运行完成：旧瞬时`line_targets()`扫描、固定眩晕和延迟二次伤害已移除；新实现使用Tiny岩石`CreateLinearProjectile`，触发时复制英雄起点和被攻击目标位置，速度500、固定距离、不追踪，LV1半径75、LV2起半径125，`bDeleteOnHit=false`且每道滚石逐单位去重。
- 伤害与控制完成：每次路径命中先检查任意来源旧眩晕并按触发时逻辑全属性×3/×6提交既有纯粹伤害事务；LV5首次命中后、LV3新眩晕前，对300范围分别按旧眩晕结算×3/×6额外伤害，首敌重复承受；最后只对路径真实命中单位独立掷30%并眩晕1秒，范围波及单位不参与。
- 生命周期与视觉完成：正常终点和飞行时间+0.25秒兜底共用幂等释放，只播放一次无伤害基础爆炸并清理状态；晚到回调不会重复结算。Tiny岩石与基础投射物爆炸均已显式预缓存，Ability KV和Tooltip Runtime同步五级。
- 专项验证：`EARTH_LINE_STATE_LUA51_PASS`、`EARTH_LINE_CONTRACT_PASS`、`EARTH_LINE_LUAC51_PASS`、`EARTH_LINE_CONFIG_VALIDATE_PASS`、`EARTH_LINE_GENERATED_COMPARE_PASS`、`EARTH_LINE_STRICT_UTF8_PASS`和限定`EARTH_LINE_DIFF_CHECK_PASS`。
- 相关回归：`BLADE_PULSE_STATE_LUA51_PASS`、`MAGIC_SLINGSHOT_TARGETS_LUA51_PASS`、`MAGIC_SLINGSHOT_CONTRACT_PASS`、`ICE_CONE_CONTRACT_PASS`、`SPIRIT_BOMB_STATE_LUA51_PASS`/`SPIRIT_BOMB_CONTRACT_PASS`、`METEOR_STATE_LUA51_PASS`/`METEOR_CONTRACT_PASS`、`MOVING_ICE_BALL_MATH_LUA51_PASS`/`MOVING_ICE_BALL_CONTRACT_PASS`。
- 测试说明：旧脉冲契约仍断言已废弃的复仇之魂粒子，第一次回归在该过时视觉断言处失败，改以当前Lua状态测试验证共享线性投射物；魔法弹弓旧契约最初因Tiny粒子未预缓存失败，地裂采用Tiny岩石并显式预缓存后该完整契约恢复通过。没有为测试修改无关技能行为。
- 尚未验证：Workshop Tools中的Tiny岩石实际滚动观感、固定路线、终点爆炸、150/250引擎碰撞、最终扣血及眩晕。尤其LV2视觉体积是否随线性投射物碰撞半径75→125自动变大没有静态证据；若实机不变，应制作独立可缩放滚石粒子，不能把碰撞测试描述为视觉验收。

## 2026-08-02 - 用户确认地裂冲击暂时完成并沉淀维护经验

- 用户明确要求“技能暂时完成”，并要求将该技能写入`docs`经验，作为后续修改方式。该口径表示接受当前实现作为阶段性稳定基线，不等同于补做或确认此前未逐项完成的Workshop Tools视觉、碰撞和伤害验收。
- 状态调整：`proto_earth_line`不再作为活跃待验任务恢复；后续会话不得因为旧记录中的Tiny岩石观感、150/250碰撞或LV2视觉尺寸待验项而主动继续修改。只有用户明确提出新需求或实机问题时才重新开启。
- 稳定实现经验已写入`PROJECT_CONTEXT.md`：保留`proto_earth_line`、`ability_survival_earth_line`和`public_06`身份；配置从英雄技能/Tooltip权威CSV修改并定向生成；五级数值、Ability KV、Tooltip Runtime和公共被动服务必须同步。
- 运行维护边界：继续使用真实`CreateLinearProjectile`、唯一投射物ID、`bDeleteOnHit=false`、逐单位去重、回调`return false`、触发时逻辑属性与目标位置快照、旧眩晕判定、伤害后新眩晕、LV5首次范围伤害和终点/超时幂等清理；禁止恢复视觉粒子碰撞、固定延迟猜测命中或旧`line_targets()`瞬时扫描。
- 后续修改验证基线：地裂PowerShell契约、Lua 5.1状态测试、`luac5.1 -p`、CSV/生成Lua一致性、严格UTF-8、限定`git diff --check`，并按改动范围运行脉冲激射、魔法弹弓、寒冰锥、元气弹等共享机制回归。Workshop Tools结果必须与自动测试分开记录。


## 2026-08-02 — 四英雄替换补充：地狱火与小游侠继承攻速

- 用户新增要求：末日使者地狱火和黑暗游侠小游侠的攻击速度也继承原英雄。
- 已确认项目战斗快照的 `attack_speed` 单位为每秒攻击次数；两种召唤均使用触发瞬间快照并按100%继承，通过 `SetBaseAttackTime(1 / attack_speed)` 应用，同时记录 `survival_attack_speed`。
- 地狱火仍继承100%攻击力，小游侠仍继承150%攻击力；生命、护甲、无敌、活动锁、五目标攻击和Proc隔离规则未改变。
- 已同步英雄技能与Tooltip权威CSV、定向生成Lua、运行配置、六份本地化镜像及专项测试。
- 自动验证通过：`FREE_HERO_REPLACEMENT_CONTRACT_PASS`、`FREE_HERO_EXCLUSIVE_STATE_LUA51_PASS`、`SUMMON_ATTACK_SPEED_LUAC51_PASS`、`SUMMON_ATTACK_SPEED_GENERATION_CONSISTENCY_PASS`、`SUMMON_ATTACK_SPEED_STRICT_UTF8_PASS`。这些不代表Workshop Tools实机验证。
- 剩余动作：实机比较召唤瞬间英雄与地狱火/小游侠的每秒攻击次数，并检查高攻速下动画和五目标攻击节奏。

## 2026-08-02 — 四英雄替换任务用户验收通过与经验沉淀

- 用户最新确认：“任务做的很成功，需要把经验记录下来”。按用户当前消息最高优先级，将四名免费英雄替换、固定Q槽专属技能以及召唤物攻速继承整体记录为用户验收通过。
- 证据边界：`FREE_HERO_REPLACEMENT_CONTRACT_PASS`、`FREE_HERO_EXCLUSIVE_STATE_LUA51_PASS`、`SUMMON_ATTACK_SPEED_LUAC51_PASS`、生成一致性、严格UTF-8和限定diff检查仍只代表对应自动验证；“任务成功”来自用户明确验收，不虚构用户未提供的控制台日志或逐项测量结果。
- 稳定配置经验：英雄、专属关系、技能、弹道和Tooltip必须先修改`data/csv/`权威源，再定向生成Lua，并同步检查Ability KV、单位KV和实际加载的中英文本地化入口。
- 稳定技能状态经验：免费英雄固定Q槽技能以项目等级0和`locked=true`表示未解锁，引擎Ability保持等级1保证可见并使用`SetActivated(false)`禁用；一转时激活同一个Ability，避免删除重加造成槽位和身份变化。
- 稳定召唤经验：攻击、攻速、生命和护甲继承取触发瞬间的项目战斗快照。`attack_speed`是每秒攻击次数，100%继承对应`SetBaseAttackTime(1 / attack_speed)`，并记录`survival_attack_speed`用于诊断；禁止把该值误当攻速百分比。
- 稳定生命周期经验：持续召唤用“英雄实体+技能ID”建立唯一活动锁，概率判定前先检查锁；实体死亡、失效或到期都必须清锁和清理，避免重复召唤与永久锁死。
- 稳定多目标攻击经验：小游侠次级攻击既要在`PerformAttack`关闭Proc，也要通过攻击record隔离项目自己的装备、技能和攻击事件链，不能只依赖单个引擎布尔参数。
- 稳定模块边界经验：四个免费专属状态集中在`hero_exclusive_passive_service.lua`以规避Lua 5.1单函数局部变量上限，但伤害继续注入并复用主被动服务的既有伤害事务，不创建重复伤害系统。
- 已排除方案：不使用原生三维反推项目属性；不把视觉粒子当碰撞体；不直接手改generated Lua；不为过时旧测试恢复已删除技能或无关预缓存；不把自动测试描述为用户实机验收。
- 文档状态：稳定规则已写入`PROJECT_CONTEXT.md`，`START_HERE.md`和`CURRENT_TASK.md`已清除四英雄任务待办。该任务不再自动恢复，后续等待用户指定新任务或报告明确回归。

## 2026-08-02 - 陨石坠落替换为卡尔Chaos Meteor视觉

- 视觉完成：`proto_meteor`坠落主体从基础投射物替换为`invoker_chaos_meteor_fly.vpcf`。该Valve粒子内部固定以1.3秒约束沿CP0到CP1移动；Lua按技能不变的0.8秒落地时间把CP1延伸至地下，使粒子在权威落地时刻准确穿过目标快照地面位置，CP2.x同步写入0.8秒生命周期。
- 落地完成：基础爆炸替换为`invoker_chaos_meteor.vpcf`，CP0使用触发时目标地面快照，CP1显式写零速度，保留卡尔陨石模型、火焰、碎屑与烟尘并禁止原版地面滚动。飞行粒子以非立即销毁触发EndCap，落地主粒子释放索引后由自身生命周期结束。
- 边界保持：12%触发、0.8秒坠落、500范围、全属性×3纯粹伤害、LV2三次熔岩伤害、LV3 30%减速、LV5第二颗晚0.5秒及80%伤害、Viper熔岩视觉和独立触发锁均未改变；粒子不承担碰撞或伤害。
- 资源与容错：游戏模式显式预缓存卡尔飞行与落地粒子；创建、控制点、销毁和索引释放均隔离视觉错误，视觉失败不阻断权威伤害、熔岩或解锁。
- 验证完成：`METEOR_VISUAL_STATE_PASS`、`METEOR_VISUAL_CONTRACT_PASS`、目标Lua语法、严格UTF-8和限定`git diff --check`通过。状态测试覆盖LV1落地、LV5双陨石0.5秒间隔/第二颗80%伤害、减速清理及视觉失败隔离。爆炎弹、怒雷、元气弹视觉回归通过；移动冰球重复常量及魔法弹弓/毒云过时契约属于合并基线既有失败，未随本任务修改。
- 尚未验证：Workshop Tools中卡尔陨石实际尺寸、空中轨迹、EndCap与落地主粒子叠加观感、落地后是否完全无滚动、LV5双陨石视觉间隔及连续触发后的粒子残留。

## 2026-08-03 — 资源树承伤与防御塔目标限制任务启动

- 用户要求：资源树只承受平A伤害，技能伤害不计入；防御塔不能攻击树，其他怪物可以攻击树。
- 用户进一步确认：这里只保留引擎基础普通攻击伤害；平A触发的影压、反击螺旋、装备附伤、塔技能等额外伤害全部不能伤树。
- 调查确认：树是`enemy_tree`，由`tree_system.lua`创建并永久挂载`modifier_tree_progression`；所有箭塔与转职塔统一保留`survival_building_id == "arrow_tower"`并挂载`modifier_tower_auto_attack`。
- 调查确认：全局`damage_filter_service.lua`已有`damage_category_const`字段，可按引擎伤害类别区分基础攻击与技能/脚本伤害，不使用`inflictor == nil`猜测。
- 调查确认：项目当前没有`SetExecuteOrderFilter`；仅修改塔自动选敌不能覆盖玩家手动右键树，因此计划新增最小OrderFilter服务，并由树承伤规则兜底已发射弹道或引擎竞态。
- 用户已批准实施方案。下一步：实现共享树伤害规则、扩展树与塔modifier、注册OrderFilter并增加专项测试。

## 2026-08-03 — 资源树承伤与防御塔目标限制自动实现完成

- 新增`systems/tree_damage_rules.lua`作为共享身份与承伤规则：`enemy_tree`只放行`DOTA_DAMAGE_CATEGORY_ATTACK`；未知类别失败关闭；`survival_building_id == "arrow_tower"`即使是基础攻击也始终禁止伤树。
- `damage_filter_service.lua`在消费项目pending事务后应用共享树规则，被拦截伤害发布`tree_requires_basic_attack`；因此技能、无Ability脚本伤害与平A触发附伤不会污染后续事务。
- `modifier_tree_progression.lua`增加承伤属性但保留最低1血和耗尽升级调度。全局DamageFilter是类别权威；modifier参数缺少`damage_category`时交给全局过滤器，避免引擎版本差异误拦基础平A；箭塔攻击仍在modifier层直接拦截。
- `modifier_tower_auto_attack.lua`自动搜索跳过树，当前目标为树时清除并重选，攻击开始事件额外停止竞态攻击；新增`tree_attack_order_filter.lua`只拒绝箭塔对树的手动`DOTA_UNIT_ORDER_ATTACK_TARGET`。
- 自动验证通过：`TREE_DAMAGE_RULES_CONTRACT_PASS`、`TREE_DAMAGE_RULES_LUA51_PASS`、`TREE_DAMAGE_RULES_LUAC51_PASS`、`TREE_DAMAGE_RULES_STRICT_UTF8_PASS`、`TREE_DAMAGE_RULES_DIFF_CHECK_PASS`。Lua行为测试覆盖非塔基础平A、技能/未知/塔伤害、DamageFilter事务、手动命令、自动选敌、攻击开始、间隔重选及树升级调度。
- 并发工作区事件：任务期间外部进程把生产与初版文档提交到新HEAD`00bfe05`，同时修改`.gitignore`并产生无关未跟踪`卡牌文本.txt`。按规则暂停后，用户明确选择接受新HEAD、保留外部`.gitignore`并继续验证；未回滚、覆盖或编辑这些外部内容。
- 外部`.gitignore`第103至104行忽略本次`tools/test_tree_damage_rules.lua`与`tools/test_tree_damage_rules_contract.ps1`。两文件仍在磁盘且已执行通过，但未纳入Git状态；用户已明确接受该交付限制。
- 尚未进行Workshop Tools实机验证，不能称为实机通过或用户验收。下一步只验证塔自动/手动忽略树、非塔基础平A扣血、所有额外伤害不扣血，以及树最低1血后的正常升级刷新。

## 2026-08-03 — 新任务检查点：资源树、祭坛、主城、伐木工与修理工分级模型替换

- 用户开启新需求，要求先替换资源树、召唤祭坛、伐木工LV1至LV5及修理工LV1至LV2模型，并明确要求把对应关系写入CSV权威配置。
- 资源树指定为`models/props_tree/mango_tree.vmdl`；召唤祭坛指定为`models/props_structures/tower_good4.vmdl`。伐木工与修理工逐级路径已完整记录在`CURRENT_TASK.md`。
- 主城要求LV1至LV3使用同一模型逐级放大，LV4至LV5换成另一座类似高塔且更神圣的模型；用户授权先参考资源并自行选出一版。
- 当前尚未调查模型配置链或修改生产文件。下一步唯一动作：检查Git状态，读取相关CSV与生成配置，搜索单位创建、升级、SetModel/SetModelScale、KV和预缓存消费链，并验证本机模型资源存在性。

## 2026-08-03 — 模型配置链调查完成并固定第一版主城选型

- 使用Python只读解析当前Dota`pak01_dir.vpk`的VPK v2目录树，共索引383571个文件；用户指定的Mango Tree、tower_good4、五个伐木工和两个修理工模型均确认存在。
- Valve Good Tower模型族实际包含`tower_good.vmdl`、`tower_good2.vmdl`、`tower_good3.vmdl`、`tower_good4.vmdl`，不存在`tower_good1.vmdl`。主城第一版选择LV1至LV3为`tower_good.vmdl`、缩放0.55/0.65/0.75，LV4至LV5为`tower_good3.vmdl`、缩放0.80/0.95；祭坛使用指定`tower_good4.vmdl`并保留0.34缩放。
- 工人权威链：`training_definitions.csv`已有`model_name`列，`worker_system.lua`按具体训练等级创建实体；当前只对修理工应用模型，需要提升为所有单位训练行共用。伐木工LV6至LV8未获模型要求，保持空值和既有KV回退。
- 主城权威等级来自`building_levels.csv`，建造完成和升级均会调用`building_visual_service.apply()`；但该CSV为GB18030且已有编码/生成不一致风险。采用与`wall_visual_levels.csv`相同的独立视觉投影方式，新建UTF-8`building_visual_levels.csv`，由`buildings_config.lua`合并到主城及祭坛等级数据。
- 资源树当前由`tree_config.lua`手写模型，运行时`tree_system.lua`应用；已有`asset_catalog.csv`的`world_resource_tree`身份，因此改为由该CSV生成资产行提供模型，保留既有缩放3。
- 所有新增建筑模型登记到`asset_catalog.csv`并进入现有预加载服务；工人模型由`training_definitions.csv`生成后在游戏模式预缓存阶段遍历预加载。
- 下一步：修改权威CSV和最小运行时适配，定向生成相关Lua，补充模型契约与Lua行为测试。

## 2026-08-03 — 分级模型替换实现与自动验证完成

- 权威CSV完成：`training_definitions.csv`写入伐木工LV1至LV5、修理工LV1至LV2模型；新增`building_visual_levels.csv`保存主城五级与祭坛模型/缩放；新增`world_visual_definitions.csv`保存资源树Mango Tree与缩放3。
- 运行时完成：`worker_system.lua`统一应用任意工人训练行的`model_name`；`tree_config.lua`读取世界视觉生成表；`buildings_config.lua`按建筑和等级合并视觉行，祭坛改为复用`building_levels.csv`等级行并保留2500生命/8点War3护甲回退。
- 引擎边界完成：`npc_units_custom.txt`同步资源树、主城LV1、祭坛、伐木工LV1和修理工LV1回退模型；`addon_game_mode.lua`补修理工单位预缓存，并遍历工人、建筑视觉和世界视觉生成配置去重预缓存模型。
- 方案调整：曾考虑复用`asset_catalog.csv`，中间检查发现其表头已扩展为27列而大量历史行仍为22列，严格生成会失败。已精确撤回本轮对该文件的改动并确认`ASSET_CATALOG_UNTOUCHED_PASS`；没有批量改写历史资产表或有编码风险的`building_levels.csv`。
- 模型取证：从当前Dota VPK v2目录索引确认11个实际引用模型全部存在，输出`UNIT_MODEL_VPK_INDEX_PASS 11`。其中`tower_good1.vmdl`不存在，因此主城低阶使用实际存在的`tower_good.vmdl`。
- 自动验证通过：`UNIT_MODEL_CONFIG_CONTRACT_PASS`、`UNIT_MODEL_CONFIG_LUA51_PASS`、`UNIT_MODEL_ALL_LUAC51_PASS`、`UNIT_MODEL_GENERATED_COMPARE_PASS`、`UNIT_MODEL_ENCODING_AND_COLUMNS_PASS`、`UNIT_MODEL_DIFF_CHECK_PASS`；树规则回归`TREE_DAMAGE_RULES_CONTRACT_PASS`和`TREE_DAMAGE_RULES_LUA51_PASS`通过。
- 编码边界：两个新CSV及生成Lua为严格UTF-8；既有`training_definitions.csv`保持GB18030原编码，只对ASCII模型字段做字节级替换，27列结构完整，未整表转码。
- 尚未验证：Workshop Tools实际尺寸、动画、朝向、主城LV3到LV4切模、祭坛0.34缩放、Mango Tree缩放3及血条位置。下一步完全重启Run后逐项验收，不能把自动测试称为实机通过。

## 2026-08-03 — 紧急修复公共被动服务Lua 5.1顶层local溢出

- 用户在Workshop Tools启动时报告`addon_game_mode.lua:83`无法require`systems/hero_passive_skill_service`；本机`luac5.1 -p`精确复现真实编译错误：第3240行声明时主函数超过200个local。
- 审计确认服务顶层共有202个声明，且该文件在本轮模型任务前没有未提交差异。采用最小行为等价修复：把末尾`trigger`、`roll`、`on_main_attack`改为既有模块表`M`上的内部方法，并同步两处调用和事件订阅引用；顶层声明降至199，未修改CSV、技能数值、随机判定、伤害事务或生命周期。
- 自动验证通过：`hero_passive_skill_service.lua`、`hero_exclusive_passive_service.lua`和`addon_game_mode.lua`的Lua 5.1语法；回音重斩、地裂冲击、陨石、元气弹、龙卷、脉冲激射、爆炎弹、毒云8项Lua 5.1状态测试；`FREE_HERO_EXCLUSIVE_STATE_LUA51_PASS`、`FREE_HERO_REPLACEMENT_CONTRACT_PASS`、严格UTF-8及目标`git diff --check`。
- 自动验证证明原编译阻断已消除，但不等同于Dota实机启动。下一步必须完全停止并重新Run Workshop Tools，先确认地图可进入且控制台不再出现200-local错误，再继续模型尺寸、动画和切模验收。用户原有`卡牌文本.txt`及模型任务全部既有修改均未触碰或回滚。

## 2026-08-03 — 回音重斩替换为Kez Echo Slash纯刀光

- 用户要求为三选一技能`proto_echo_slash`/“回音重斩·被动”增加Kez Echo Slash特效，并明确选择只显示纯斩击刀光：不要Kez英雄残影，也不要原技能的回音复击机制。
- 本机Dota `pak01_dir.vpk`确认完整父粒子`kez_katana_echo_strike.vpcf`会引用Kez英雄残影；最终采用纯刀光子粒子`particles/units/heroes/hero_kez/kez_katana_echo_strike_slash.vpcf`，其运行依赖只有刀光材质和slash spikes子粒子，不依赖Kez英雄模型或残影。
- 生产修改仅替换`echo_slash.particle`并增加显式预缓存。没有调用`kez_echo_slash`、没有添加Kez modifier、声音、延迟复击、额外攻击或额外伤害；1/2/3/3/4波、0.1秒间隔、1秒全程、攻击射程、总宽200、纯粹伤害、穿透和逐波去重全部保持。
- 剑刃震荡的`BLADE_PULSE_PARTICLE`和马格纳斯震荡波预缓存均保留，未被回音重斩视觉替换影响。新增`tools/test_echo_slash_visual_contract.ps1`锁定纯刀光、排除完整回音父粒子/原生技能，并保护两项线性投射物契约。
- 自动验证：`ECHO_SLASH_VISUAL_CONTRACT_PASS`、`BLADE_PULSE_VISUAL_CONTRACT_PASS`、Lua/Luac 5.4.5语法、六个任务文件严格UTF-8及限定`git diff --check`通过。历史记录的`C:\msys64\mingw64\bin\luac5.1.exe`本轮不存在，既有回音重斩状态测试脚本也未保存在当前工作区，因此未宣称本轮Lua 5.1或状态测试通过。
- 尚未验证：Workshop Tools中的纯刀光实际朝向、尺寸、高度、移动速度、连续多波观感及是否完整走完攻击射程；自动契约不能替代引擎视觉验收。

## 2026-08-03 — 伐木工动态资源Tooltip与Lua 5.1全项目验证

- 稳定性边界：继续保留Valve原生技能栏和既有Alt隔离，只把已经具有完整权威runtime投影的`ability_train_lumberjack`加入选择性Tooltip代理；未把修理工、人口训练或通用建造技能扩大接管，也没有新增扫描、永久计时器或Alt事件。
- 费用表现：自定义技能Tooltip使用静态Panorama `Image + Label`分别显示金币和木材；改用项目现有`st2_icon_gold.png`与`st2_icon_wood.png`真实资源图标。金币/木材费用块按大于0独立显隐，两者都为0时隐藏整行，避免显示无意义的0。
- 动态数据：真实`ability_runtime_builder.lua`在Lua 5.1测试桩下确认一级伐木工投影木材10、金币0、人口1；木材恰好10时`can_afford=1`，木材9时`can_afford=0`。服务端训练扣费与点击路由未修改。
- 工具链记录：确认`C:\Program Files\lua\bin\lua5.1.exe`和`luac5.1.exe`均为Lua 5.1.5；PowerShell 7为`C:\Program Files\PowerShell\7\pwsh.exe` 7.6.4，Windows PowerShell为系统5.1.18362.2212。实际路径已写入`.cline/local-toolchain.json`和`KNOWN_ISSUES.md`。
- Lua 5.1全项目验证：首次直接逐文件检查发现仅7个历史Lua文件因UTF-8 BOM在第1字节被PUC Lua 5.1拒绝；字节审计确认BOM后的内容均为严格UTF-8且文件没有既有工作区差异。为保持本次Tooltip改动最小，没有修改这7个生产源文件；最终仅在临时副本中删除三个BOM字节后完成`scripts/vscripts`下306/306个Lua文件的`luac5.1 -p`，结果明确报告`bom_normalized=7`。
- 可重复验证：新增兼容Windows PowerShell 5.1与PowerShell 7的`tools/test_lua51_syntax.ps1`，优先读取本地工具链记录，对无BOM文件直接检查，对BOM文件使用自动清理的临时副本。当前工作树没有任何`test_*.lua`文件，历史文档中的Lua行为测试套件不在仓库内，不能冒充本轮全量行为回归。
- Panorama编译：`ability_tooltip.js`和`ability_tooltip.css`各为`OK: 1 compiled, 0 failed, 0 skipped`；`survival_hud.xml`依赖链为`OK: 9 compiled, 0 failed, 0 skipped`，并实际生成金币/木材`*_png.vtex_c`。升级Tooltip契约和Alt安全契约均在PowerShell 7与Windows PowerShell 5.1通过。
- 尚需实机：完全停止并重新Run Workshop Tools，悬停一级与高等级伐木工确认单木材/金币木材并排、费用实时变化、鼠标与快捷键训练正常；重复按住/松开Alt和快速切换主城/英雄，确认无双Tooltip、无输入残留且不崩溃。自动编译和契约不能替代该实机崩溃验收。

## 2026-08-03 — 伐木工Tooltip主城选择映射修复第一版

- 用户实机截图显示悬停目标仍出现Valve原生“升级主城”Tooltip，未显示伐木工金币/木材；确认原生Tooltip无法读取项目`survival_ability_runtime`中的双资源费用，因此继续使用窄范围选择性自定义Tooltip，不接管整行技能栏。
- 修复`ability_tooltip.js`的官方按钮映射：不再把原始`AbilityN`编号直接当作稠密显示序号，而是收集当前稳定可见的官方按钮锚点、按窗口视觉位置排序，再与当前单位的真实可见ability entindex配对。悬停与点击统一读取代理上绑定的entindex，避免显示伐木工却施放升级主城或反向错位。
- 原子安全回退：每次映射前关闭全部旧`AbilityN`代理；官方按钮数与真实可见技能数不一致时保持Valve原生交互，不启用部分映射。新增去重`[SURVIVAL_TOOLTIP_MAP]`日志，可直接观察`AbilityN->ability_name`或fallback数量。
- 选择恢复：订阅本地`dota_player_update_selected_unit`和`dota_player_update_query_unit`；切换时先关闭旧Tooltip，再以`0/0.016/0.05/0.10/0.20s`有限重试绑定。初次HUD创建单独保留原有`0/0.10/0.35/1.0s`窗口；没有新增永久扫描、哨兵循环或Alt事件。
- 自动验证：`ability_tooltip.js`经Dota资源编译器强制编译为`OK: 1 compiled, 0 failed, 0 skipped`；建筑升级/Tooltip契约与Alt安全契约在PowerShell 7及Windows PowerShell 5.1均通过；全项目Lua 5.1语法`306/306`通过，7个历史BOM仅在临时副本规范化；限定`git diff --check`通过。仍需彻底停止并重新Run后实机确认主城伐木工悬停、点击、快捷键、Alt和快速选中切换。

## 2026-08-03 — 齐天大圣专属技能与七塔合一计划获批

- 用户批准实施齐天大圣固定Q/W/E/R专属技能，分别于1/3/6/10转解锁；召唤时四槽均显示但置灰，达到条件后原位激活。保留现有四个齐天大圣专属技能ID以维持技能槽和存档兼容。
- Q最终确认：主攻击命中10%触发，从本体或唯一分身朝主目标快照方向释放；Lua矩形固定长1200、总宽200。范围内全属性×30纯粹伤害每次均结算；最大生命10%纯粹伤害由同玩家本体与分身共享，每个敌人最多3次，可击杀。原始“当前生命”描述已被用户明确更正为“最大生命”。
- W最终确认：3转解锁，暴击伤害在默认200%上+2000个百分点，裸基础暴击率0%；攻击间隔-0.1秒且最低0.1秒。解锁后每60秒按排除W累计增量的当时逻辑全属性增加2%，永久复利。唯一永久分身优先在城墙附近生成，死亡1秒后重生；无城墙回退本体。实时镜像本体战斗属性并保持生命百分比，护甲固定10，只拥有Q。
- E最终确认：6转解锁后本体最终攻击力独立×3；仅本体主普通攻击实际暴击时对主目标附加全属性×5纯粹伤害，分身、次级攻击、技能与塔均不触发。
- 通用七塔合一最终确认：每条路线终阶塔获得主动合成技能；只使用施法塔建造玩家自己的塔。施法塔必选，其他路线取距离最近者，距离相同按实体ID。原子消耗7塔，在施法塔位置生成唯一无敌终极塔；生命上限、当前生命和护甲分别求和。
- 终极塔保留7条独立攻击流，各自保留路线射程、攻击间隔、弹道和隔离被动状态；基础攻击力为7塔攻击力之和。齐天大圣10转R解锁后，每条攻击流均使用“7塔之和+英雄最终攻击力”，实时继承英雄暴击率和最终暴击伤害，不继承E附伤。
- R主动无冷却，在英雄释放瞬间位置与该玩家城墙位置之间瞬移同一终极塔实体，并保留生命百分比、攻击计时与被动状态。七塔合一本身允许任何英雄使用，R仅负责齐天大圣增强与切换。
- `passN`只允许严格下一转，直接复用正式CSV完整奖励事务，不打Boss；跳级、重复和倒退原子拒绝。
- 调查证据：`hero_exclusive_skills.csv`当前齐天大圣4条均由一转一次发放；`reward_effects.csv`当前仅一转含专属授予；`hero_skill_system.lua`VIP英雄不预创建置灰技能；项目没有英雄普通攻击统一暴击结果事件；七条路线终阶均为第三阶段LV10，塔被动运行依赖独立攻击/计数状态。
- 工作区保护：开始前`git status --short`已有树伤害、模型、多目标和恢复文档修改，以及多个用户未跟踪测试/文本文件。本任务不回滚、不覆盖这些既有修改；文档只做增量追加。
- 下一步最小动作：读取专属奖励适配器、英雄战斗快照计算区和塔攻击事件关键区，先实现CSV分转解锁、`passN`与英雄暴击权威基础。

## 2026-08-03 — 齐天大圣Q/W/E/R、passN与通用七塔合一实现

- CSV权威配置已完成：`hero_exclusive_skills.csv`新增`unlock_rebirth_level`并将齐天大圣四技能设为1/3/6/10；`reward_effects.csv`在3/6/10转新增专属授予；新增`monkey_king_exclusive_runtime.csv`和`tower_fusion_runtime.csv`。生成Lua通过源/生成字节一致性验证。
- 技能槽兼容：保留原四个skill/Ability ID，齐天大圣召唤后预创建固定Q/W/E/R，未解锁置灰；四技能CSV与KV统一最高1级，移除旧射程/攻击/攻速/敏捷占位效果。
- 奖励测试：新增内部正式奖励请求，`passN`严格校验下一转后调用`reward_rebirth_NN`完整事务，不启动Boss。正式Boss完成和命令共享奖励配置及专属授予逻辑。
- 战斗基础：统一研究暴击率、W最终暴击伤害和attack record实际暴击结果；同record幂等掷骰，命中发布实际结果，销毁时清理。E三倍使用独立乘区，不会在刷新时累乘。
- Q/W/E由独立`monkey_king_exclusive_service.lua`管理，避免增加已有199-local公共被动服务压力。Q使用项目伤害事务与Lua矩形；W管理永久成长和唯一分身；E只消费本体实际主暴击。
- 七塔合一由`building_system`批量消费入口和`tower_fusion_service.lua`协作。完整验证后创建主实体与7个隐藏路线代理；二次消费失败会删除新实体且不动原塔。人口视为替换而不释放。
- 7代理各自保存原终阶技能Ability、`tower_skill_runtime`和`modifier_tower_attack_effects`，按独立计时执行真实`PerformAttack`，因此原七路线攻击事件和被动实现均复用且状态隔离。主实体无自然攻击，代理无自然索敌，避免额外第8路攻击。
- R实时读取英雄战斗快照；每路攻击增加英雄最终攻击，路线自身未暴击时才尝试英雄继承暴击。主动移动同一主实体与代理，不重建状态。
- 本地化：更新Panorama/resource/resource-localization中英文六份镜像，保留UTF-8 BOM与CRLF；修复插入时暴露的中间KV结束符缩进后，免费英雄本地化结构契约通过。
- 自动验证通过：`MONKEY_TOWER_CONTRACT_PASS`、`FREE_HERO_REPLACEMENT_CONTRACT_PASS`、`ALT_HERO_ABILITY_ORIGIN_DEV_CONTRACT_OK`、`TREE_DAMAGE_RULES_CONTRACT_PASS`、`WORKER_RANGED_MULTISHOT_CONTRACT_PASS`、`MONKEY_KING_QWE_LUA51_PASS`、`TOWER_FUSION_LUA51_PASS`、`HERO_MULTISHOT_LUA51_PASS`、`MONKEY_TOWER_FINAL_LUAC_PASS`、严格UTF-8、CSV生成一致性及限定`git diff --check`。
- 缺失测试：仓库不存在`test_tower_special_skill_contract.ps1`和`test_tower_magic_supreme_contract.ps1`，因此记录为`SKIP_MISSING`而非通过；相关路线必须重点实机回归。
- 工作区保护：未触碰或回滚开始前已有的树伤害、模型、多目标、AI文档既有修改及用户未跟踪文件。本任务新增文件和增量修改均保留；只删除了本次Python导入产生的`tools/__pycache__`缓存。
- 仍需Workshop Tools实机验收：粒子控制点、Q碰撞/计数、W分身、E暴击、七路线全部弹道和被动、R瞬移与状态保持。未记录为用户验收或制作完成。

# 2026-08-03 - 齐天大圣W分身权威数据复刻修复

- 用户实机反馈分身技能复刻正确，但分身数据与本体不一致，尤其攻速不同。
- 根因一：旧分身Modifier自行读取`base_attack_time`和`equipment_attack_speed_pct`，会混入分身原生英雄攻速，不等于combat system已计算的最终`attack_speed`。
- 根因二：旧分身最大生命使用`SetBaseMaxHealth/SetMaxHealth`，违反项目已实机确认的原生召唤英雄生命投影规则；旧攻击力还把整个逻辑攻击乘`hero_damage_multiplier`，错误放大装备/研究部分。
- 修复后`hero_combat_stat_service`在同一快照发布最终引擎攻击上下界；分身每0.1秒只读取一次该权威快照，复制最终攻击、`SetBaseAttackTime(1 / attack_speed)`、生命Modifier补足、暴击和逻辑三维，并记录`refresh_version`。
- 分身原生三维归零，避免敏捷暗中影响攻速/护甲；固定10 War3护甲、只拥有Q、不进入装备/公共技能/转生/E链保持不变。
- `ui_request_router`增加严格分身身份适配，选中分身时消费owner的同一英雄快照并投影分身实体、生命、固定护甲和最终攻速，不再展示原生单位回退数据。
- 验证通过：`MONKEY_KING_QWE_LUA51_PASS`、`MONKEY_TOWER_CONTRACT_PASS`、`MONKEY_CLONE_LUAC51_PASS`、`HERO_HEALTH_CONTRACT_PASS`、`FREE_HERO_REPLACEMENT_CONTRACT_PASS`、严格UTF-8和限定`git diff --check`。自动验证不等于Workshop Tools实机验证。
- 下一步：冷启动后对照本体与分身的攻击上下界、每秒攻击次数/实际攻击间隔、最大生命、暴击和逻辑三维；同时确认固定10护甲、生命比例刷新、仅Q和死亡1秒重生无回归。

## 2026-08-03 - 回音重斩纯刀光实机失败修正

- 用户实机报告旧视觉“只闪一下或只显示残缺的一小段”。资源反编译确认`kez_katana_echo_strike_slash.vpcf`使用`C_INIT_CreateSequentialPathV2`，要求CP0/CP1两个世界端点，固定粒子寿命0.3秒且连续发射期0.5秒；`CreateLinearProjectile`的`EffectName`不会按该内部子粒子的契约提供控制点。
- 修复后线性投射物不再设置Kez `EffectName`，继续唯一负责1秒路径、总宽200、穿透、逐单位去重和伤害。每道独立创建纯刀光，Lua每0.05秒按同一权威路径推进横向CP0/CP1，并补官方蓝色CP7和发射率CP8。
- 为覆盖完整1秒路径，每道视觉在0.5秒销毁第一实例并从半程创建第二实例；两段仅是视觉生命周期，不增加战斗波、投射物、攻击、命中或伤害。正常终点、投射物回调、超时、服务重置和视觉异常均幂等销毁释放。
- 曾尝试从Valve编译资源反解并重编译1秒项目粒子；Resource Compiler虽报告成功，但反编译产物的emit rate被规范化为0，判定不可用并已删除源与产物，未接入生产。
- 新增`tools/test_echo_slash_visual.lua`和更新后的视觉契约，覆盖起点、半程换段、射程终点、CP7/CP8、幂等清理、视觉失败隔离及与剑刃震荡的资源隔离。自动验证通过：`ECHO_SLASH_VISUAL_STATE_PASS`、`ECHO_SLASH_VISUAL_CONTRACT_PASS`、`BLADE_PULSE_VISUAL_CONTRACT_PASS`和Lua 5.4.5语法；当前仍无Lua 5.1编译器。
- 尚待完全停止并重新Run Workshop Tools，实机确认两段刀光衔接、朝向、宽度、高度、连续多波观感和完整攻击射程。

## 2026-08-03 - 回音重斩第二次实机失败：修正刀光端点方向

- 用户第二次实机截图显示刀光在英雄周围形成大圆弧，两端伴随强白光，仍没有成为沿攻击路径移动的弧形斩。
- 结合截图和Valve资源定义确认新根因：`C_INIT_CreateSequentialPathV2`以CP0/CP1作为带`m_flBulge=100`的斩击路径两端；上一轮Lua却把两点放在移动中心的横向左右各100码，错误地把碰撞宽度当成视觉端点间距，连续发射后叠加成环。
- 本轮最小修正只改变视觉几何：CP0/CP1沿固定投射方向放在移动中心后方/前方各100码；视觉总长200与碰撞总宽200在数值上相同但语义彻底分离，视觉同步函数禁止读取`state.half_width`。两个0.5秒视觉实例、0.05秒同步和所有清理策略保留。
- 权威`CreateLinearProjectile`、1秒射程、总碰撞宽200、穿透、单波去重、多波0.1秒时序、伤害快照与视觉失败隔离均不修改。
- 自动验证通过：`ECHO_SLASH_VISUAL_STATE_PASS`、`ECHO_SLASH_VISUAL_CONTRACT_PASS`、`BLADE_PULSE_VISUAL_CONTRACT_PASS`、Lua 5.4.5生产/测试语法、六个目标文件严格UTF-8、主服务顶层local仍为199及限定`git diff --check`。状态测试同时保护4波绝对时序、无碰撞投射物视觉、500射程、总宽200、穿透、单波去重、跨波命中、纯粹伤害、LV5随机倍率和视觉失败隔离。
- 当前环境三个已知Lua 5.1编译器路径均不存在，不能宣称本轮Lua 5.1编译通过。额外运行的魔法弹弓视觉契约失败于既有`MAGIC_SLINGSHOT_TINY_ATTACK_PARTICLE_REMAINS`：该测试排斥Tiny attack资源，但当前地裂冲击既有视觉正在使用它；本轮未修改这两项，也未为无关陈旧断言改变生产行为。
- 尚待冷启动Workshop Tools，确认大圆环和端点白爆消失，并检查弧线开口方向、总视觉长度、高度、两个0.5秒实例衔接和完整射程。

## 2026-08-03 - 回音重斩改用完整Kez Echo Slash父粒子

- 用户确认当前回音重斩没有正确使用Kez Echo Slash，并明确授权：若不能在去除Kez模型的前提下正确使用特效，可以保留Kez使用完整Echo Slash。此前内部`kez_katana_echo_strike_slash.vpcf`直接投射物和Lua端点驱动方案均正式废弃。
- 生产视觉切换为`particles/units/heroes/hero_kez/kez_katana_echo_strike.vpcf`并同步替换预缓存。该父粒子会包含Kez英雄残影以及ground、movement、streaks、swoosh、wind warp和thickness indicator，符合本轮授权。
- 每道战斗波仍对应两个连续0.5秒视觉实例：第一实例CP0/CP1为触发起点→射程中点，第二实例为中点→完整终点；CP2设置`(权威速度, 200, 1.5)`，CP6沿用Valve预览`(-9.61916,0,0)`，CP7/CP8保留原版蓝色和发射输入。父粒子自行从CP10传播运动位置和朝向给全部子效果。
- 完整父粒子只作为独立视觉层。权威`CreateLinearProjectile`继续无`EffectName`并唯一负责1秒射程、总碰撞宽200、穿透、单波去重和伤害；1/2/3/3/4波、12%/15%触发、0.1秒间隔、全属性×1纯粹伤害和LV5每波独立5%～20%增伤均不修改。没有调用`kez_echo_slash`、Kez modifier、原生声音、攻击或回音复击。
- 最终验证通过：`ECHO_SLASH_VISUAL_STATE_PASS`、`ECHO_SLASH_VISUAL_CONTRACT_PASS`、`BLADE_PULSE_VISUAL_CONTRACT_PASS`、Lua 5.4.5生产/测试语法、七个目标文件严格UTF-8、主服务顶层local仍为199及限定`git diff --check`。状态测试覆盖完整父资源、两阶段CP、CP2/6/7/8、清理、视觉异常隔离、四波时序、碰撞宽度、穿透、去重和纯粹伤害。下一步仅为冷启动Workshop Tools实测完整效果；当前环境无Lua 5.1编译器，未宣称本轮Lua 5.1编译通过。

## 2026-08-03 - 回音重斩末端额外斩击根因与视觉清理修复

- 继续反编译核对完整父粒子、slash和swoosh后确认：父资源只用`C_OP_InstantaneousEmitter`瞬发一个载体，没有延迟发射第二个父载体；该载体的寿命字段为0.5秒，并由`C_OP_BasicMovement`推进，再通过`C_OP_SetChildControlPoints`持续驱动完整子效果。CP1只参与方向/端点契约，不是载体到达后自动停止的硬边界。
- 旧阶段切换与最终清理使用`DestroyParticle(..., false)`，只停止发射而不立即清除已生成载体。载体及其slash/swoosh子系统会在剩余寿命内继续移动，因此表现为斩击到达阶段终点后又向前播放；这比“父粒子延迟再发射一次”更符合资源定义。
- 最小修复仅修改完整Kez视觉父粒子的统一销毁函数：无论阶段切换、正常终点、投射物终点、超时、异常或服务重置，均调用`DestroyParticle(particle, true)`并继续`ReleaseParticleIndex`。没有修改`CreateLinearProjectile`、射程、速度、总宽、穿透、单波去重、波数、0.1秒波间隔、伤害快照或纯粹伤害。
- 状态测试现分别要求第一阶段换段和第二阶段正常收尾立即销毁；PowerShell契约禁止恢复调用方控制的淡出销毁。验证通过：`ECHO_SLASH_VISUAL_STATE_PASS`、`ECHO_SLASH_VISUAL_CONTRACT_PASS`、`BLADE_PULSE_VISUAL_CONTRACT_PASS`、Lua/Luac 5.4.5生产与测试语法、7个目标文件严格UTF-8、主服务顶层local仍为199及限定`git diff --check`。状态测试还保护四波绝对时序、无碰撞投射物视觉、500射程、总宽200、穿透、单波去重、跨波命中、纯粹伤害、LV5倍率和视觉失败隔离。当前无Lua 5.1命令，未宣称Lua 5.1验证；Workshop Tools冷启动实测仍待执行，重点确认末端额外斩击消失以及0.5秒换段是否出现明显断帧。

## 2026-08-03 - 虚空震爆卡尔龙卷风视觉源与契约恢复

- 用户批准为三选一公共技能`proto_void_pulse`/“虚空震爆·被动”使用卡尔原版龙卷主体外观，并保留现有Lua追踪、到达后附着、目标死亡后停在最后位置以及LV5小龙卷规则；本轮不得修改任何战斗数值。
- 调查确认生产主/小龙卷已经统一使用`particles/survival_tornado/survival_tornado_follow.vpcf`，共享状态机每0.05秒写CP0；已有编译产物明确依赖Valve `particles/units/heroes/hero_invoker/invoker_tornado_child.vpcf`。完整`invoker_tornado.vpcf`因内部直线移动无法可靠重定位，继续禁止用于动态追踪视觉。
- 恢复content源`particles/survival_tornado/survival_tornado_follow.vpcf`：仅包含一个卡尔龙卷主体子粒子，没有`C_OP_BasicMovement`、`m_Operators`或CP1速度驱动。新增`tools/test_tornado_visual_contract.ps1`，覆盖技能身份、源依赖、主/小创建、CP0同步、0.05秒间隔、释放、清局和预缓存。
- Resource Compiler强制定向编译结果为`OK: 1 compiled, 0 failed, 0 skipped`；新产物未形成game仓库差异，证明恢复源可重现当前生产二进制。`TORNADO_VISUAL_CONTRACT_PASS`、生产Lua 5.4.5语法、严格UTF-8/尾随空白检查、编译产物卡尔子依赖及限定差异检查通过。
- 10项相邻视觉契约中7项通过；3项既有无关失败为`MAGIC_SLINGSHOT_TINY_ATTACK_PARTICLE_REMAINS`、`MOVING_ICE_BALL_OLD_PROJECTILE_REMAINS`和`POISON_CLOUD_PERSISTENT_VISUAL_CREATION_MISSING`，均来自当前其他技能实现与陈旧测试不一致，本轮未修改。环境仅有Lua 5.4.5，不宣称Lua 5.1验证。
- 尚未验证：完全重启Workshop Tools Run后的卡尔龙卷实际外观、主龙卷追踪与附着、目标死亡后的停留、多个活动龙卷重叠、LV5小龙卷和结束无残留。粒子已预缓存，Lua热加载不足以完成该验收。

## 2026-08-03 - W分身修复经验固化

- 用户要求记录本次经验。已将可复用规则写入`PROJECT_CONTEXT.md`：完整镜像必须消费同一次combat system原子快照；最终攻速直接换算BAT；实际攻击复制最终引擎上下界；原生三维归零；生命复用隐藏Modifier；暴击不得拆分请求；选中UI必须按严格分身身份读取owner快照；数值镜像与装备/技能事件链继承必须隔离。
- `DECISIONS.md`新增长期架构决策43，禁止未来在召唤物侧重新组合中间字段或通过挂本体全套Modifier实现数据复刻。
- 本次仅修改AI经验文档，没有触碰当前工作区中英雄射程、工具技能、拾取、外观和Panorama等其他任务修改。


## 2026-08-04 — 超级防御塔暴击四项科技修复

- 用户最终批准：该科技每级同时增加防御塔暴击几率、防御塔攻击加成、召唤英雄暴击几率和召唤英雄攻击加成，四项均为 `+0.5%`；CSV 每一级介绍必须包含四项，复合功能放在 Lua。
- 调查确认旧 `ARS-07` 已定义四项 `0.005`，但生成科技链只把 `super_tower_crit_pct` 投影为塔暴击；塔/英雄的消费和 `TECHNOLOGY_STATS_CHANGED` 刷新链原本已存在，根因是生成科技聚合迁移不完整。
- `technology_definitions.csv` 的23级累计值改为 `level × 0.5%`，Lv.19 为 `9.5%`、Lv.23 为 `11.5%`；每级 `notes` 以四行列出全部效果。原文件经确认是可逆 GB18030、无替换字符，本轮使用明确解码后安全转换为 UTF-8 BOM。
- `technology_stat_manager.lua` 现将单一科技值同时投影到 `tower.critical_chance_pct`、`tower.attack_bonus_pct`、`hero.critical_chance_pct` 和 `hero.attack_bonus_pct`；不新增自定义伤害或重复 Buff 服务。
- `tools/build_configs.py` 改用 `splitlines(keepends=True)`，使 CSV 引号字段内换行生成成 Lua `\n`，商城现有 `notes` 描述链可按四行显示。
- 新增专项 PowerShell 契约和 Lua 5.1 行为测试；生成逐字节一致、专项契约、Lv.1/Lv.19/Lv.23 四项行为、独立英雄攻击科技共存、Lua 5.1 语法、生成科技减甲回归、严格 UTF-8 与限定 `git diff --check` 全部通过。
- 自动验证不等于 Workshop Tools 实机验证。下一步冷启动购买科技，确认 Tooltip、已有塔/英雄即时刷新、攻击数值与实际暴击率；未经用户确认不记录为验收完成。
- 未回滚或清理工作区其他既有修改；仅删除本轮 Python 生成的 `tools/__pycache__` 副产物。

## 2026-08-04 - 奥术弹幕增加天怒法师秘奥耀光落击特效

- 用户要求为三选一技能`proto_arcane_barrage`/“奥术弹幕·被动”增加天怒法师大招特效。调查本机Dota content确认`skywrath_mage_mystic_flare_ambient.vpcf`会在内部自行随机落击，无法与Lua既有权威随机伤害点逐颗对应，因此未接入该持续ambient父粒子。
- 最终采用单次原版落击`particles/units/heroes/hero_skywrath_mage/skywrath_mage_mystic_flare.vpcf`替换奥术弹幕旧基础爆炸。每颗仍以`PATTACH_WORLDORIGIN`创建，CP0写入既有`landing_position`后释放索引；视觉异常继续由`pcall`隔离，不影响同颗伤害和后续飞弹。
- 只等量重命名现有顶层粒子常量，没有新增顶层local，避免触碰公共被动服务历史199-local边界。启动预缓存新增秘奥耀光资源；`basic_explosion.vpcf`预缓存继续保留，因为毒云死亡爆炸仍独立使用该资源。
- 战斗行为保持：随机落点、LV1/2的5颗、LV3/4的7颗、LV5三轮共21颗、单顺序Scheduler、150伤害范围、实际Hull边缘命中、全属性×2纯粹伤害、活动锁和兜底释放均未修改。
- 新增`tools/test_arcane_barrage_visual_contract.ps1`，锁定秘奥耀光常量与预缓存、每颗CP0权威落点、索引释放、排除ambient随机父粒子、移除旧基础爆炸CP1，以及5/7/21颗、150范围和顺序调度契约。验证通过：`ARCANE_BARRAGE_VISUAL_CONTRACT_PASS`、`hero_passive_skill_service.lua`与`addon_game_mode.lua`的Lua 5.4.5语法、严格UTF-8和限定`git diff --check`。
- 环境限制：当前PATH只有Lua/Luac 5.4.5；历史`.cline/local-toolchain.json`中的Lua 5.1路径及历史统一语法脚本均已不存在，因此未宣称本轮Lua 5.1执行。额外毒云视觉契约失败于既有`POISON_CLOUD_PERSISTENT_VISUAL_CREATION_MISSING`陈旧断言，本轮未修改毒云运行区段或为通过无关测试改变生产行为。
- 尚待实机：完全停止并重新Run Workshop Tools，逐级触发奥术弹幕，确认天怒落击尺寸、亮度、落点与伤害中心一致，LV5连续21颗完整且无明显帧时间问题。
