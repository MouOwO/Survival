# Current Task

## 当前插入任务（2026-08-08）：金矿升级后固定模型尺寸

- 用户实测金矿升级后模型尺寸恢复原状，要求直接固定模型大小。
- 根因确认：金矿升级由`gold_mine_system.lua`独立提交，`gold_mine_config.level_data()`只返回`building_levels.csv`等级行；各级虽有相同`model_name`，但没有`model_scale`，因此升级时`building_visual.apply()`拿不到权威`0.34`。
- 实施边界：继续以`building_visual_levels.csv`的金矿视觉行为权威，不向30行等级CSV重复写缩放；由`gold_mine_config`把固定视觉字段投影到所有等级，保证手动/自动升级每次提交都重新应用`radiant_ancient001.vmdl / 0.34`。不修改收益、费用、生命、护甲、技能或升级时序。
- 生产实现完成：`gold_mine_config.lua`读取生成的`building_visual_levels.lua`，选择启用的金矿LV1视觉行，并在`level_data()`中把`model_asset_id/model_name/model_scale/model_yaw`投影到每个金矿等级。既有手动/自动升级提交继续统一调用`building_visual.apply()`，每次完成后都会重新设置`radiant_ancient001.vmdl / 0.34`。
- 自动验证通过：`GOLD_MINE_FIXED_VISUAL_LUA51_PASS`、`SIX_GAMEPLAY_FIXES_LUA51_PASS/CONTRACT_PASS`、相关Lua 5.1语法、视觉CSV与生成Lua逐字节一致、严格UTF-8及限定`git diff --check`。
- 尚未Workshop Tools实机验收。需完全停止并重新Run后连续升级金矿，确认模型和0.34尺寸不再恢复，同时核对手动/自动升级、收益和技能无回归。

## 当前插入任务（2026-08-08）：金矿替换为可选中动态建筑模型

- 用户实测当前金矿无法通过鼠标选择。静态审计确认`building_gold_mine`运行配置已有`selectable=true`，没有金矿专属`MODIFIER_STATE_UNSELECTABLE`；问题集中在当前`tower_good4.vmdl`缺少可靠单位选择命中边界，而不是建筑Hull或业务选择开关。
- 用户已批准将金矿完工模型替换为项目已确认可选中的`models/props_structures/radiant_ancient001.vmdl`，模型缩放为`0.34`；施工视觉同步使用`0.34`，避免完工时尺寸跳变。
- 修改边界：保留金矿现有建筑ID、单位ID、技能、等级、收益、成本、人口占用、数量上限和存档身份；不引入选择代理，不通过修改Hull冒充选择修复。
- 权威源必须先修改`building_visual_levels.csv`和`building_construction_rules.csv`，再定向重建生成Lua；`npc_units_custom.txt`只同步首帧/异常回退模型与缩放。
- 生产实现完成：金矿视觉CSV与施工规则CSV均改为`radiant_ancient001.vmdl / 0.34`，两份生成Lua通过项目生成器定向重建；`npc_units_custom.txt`同步首帧/异常回退模型与缩放。金矿现有`selectable=true`及全部业务身份和数值保持不变。
- 自动验证通过：`SIX_GAMEPLAY_FIXES_CONTRACT_PASS`、`SIX_GAMEPLAY_FIXES_LUA51_PASS`、`UNIT_MODEL_CONFIG_LUA51_PASS`、两份生成Lua逐字节一致、相关Lua 5.1语法、严格UTF-8和限定`git diff --check`。`building_system.lua`保留既有UTF-8 BOM，使用临时去BOM副本完成语法检查，未重写生产编码。
- 全局单位模型旧契约在更新过时的`tower_good4`要求后，仍只失败于任务前已知的无关伐木工CSV缺项`creep_bad_melee_cavern_mega.vmdl`；本任务未修改无关伐木工数据迎合测试。
- 尚未Workshop Tools实机验收。必须完全停止并重新Run后，确认完工金矿可通过鼠标点击模型主体选中、五个技能正常显示，且施工/完工尺寸、收益、升级、血条、上限和人口占用无回归。

## 当前插入任务（2026-08-08）：城墙升级增加最大生命差值

- 用户确认新语义：升级完成时计算`最大生命增量=新最大生命-旧最大生命`，并令`新当前生命=旧当前生命+最大生命增量`。例如`100/200`升级到最大生命`400`，最终为`300/400`，不再保持旧生命百分比。
- 修改范围仅限城墙；主城、农场和防御塔继续保持既有升级行为。存活城墙结果夹紧到`1..新最大生命`，升级过程中的受伤必须计入提交瞬间的旧当前生命。
- 根因是上一版`building_health_projection.lua`按生命百分比投影。城墙提交路径现捕获即时当前/最大生命，并把等级数据与当前科技重算后的最终实际最大生命一并纳入增量计算；不修改`building_levels.csv`权威数值。
- 生产实现完成：`apply_maximum_health_increase()`以最终实际最大生命差值增加当前生命；其他建筑未接入该投影。专项行为测试和契约测试覆盖`100/200 -> 300/400`、满血、1血、无增量、合法夹紧、科技后最终上限及城墙专用边界。
- 自动验证通过：`WALL_UPGRADE_HEALTH_LUA51_PASS`、`WALL_UPGRADE_HEALTH_CONTRACT_PASS`、`WALL_UPGRADE_HEALTH_LUAC51_PASS`、全项目351个生产Lua的Lua 5.1语法检查、修理工百分比行为/契约回归、严格UTF-8及限定`git diff --check`。任务前未跟踪的旧`test_building_upgrade_contract.ps1`仍失败于其过时断言要求`local duration`，而当前HEAD一直使用等价的`state.duration`；升级流程生产文件与HEAD一致，本轮未修改该无关测试迎合。仍需Workshop Tools实机验收残血城墙升级后的实际血条数值。

## 已完成并经用户确认（2026-08-08）：人口训练按CSV阶段内次数顺序推进

- 用户确认`training_definitions.csv`原始人口训练数据正确：人口训练1至5各可成功使用5次，人口训练6可成功使用100次且保持启用；上一轮将前五阶段改为各1次并禁用第六阶段属于错误修改，必须恢复原始CSV并定向重建生成Lua。
- 已定位原始运行时根因：`train_population_auto`曾使用`math.max(2, farm_level + 1)`选择训练ID，导致人口训练1永远不加载，并错误地由农场等级直接跳选阶段。
- 目标行为：按启用CSV行的`level`顺序选择第一个未达到自身`max_count`的阶段；当前阶段达到上限后才加载下一阶段。计数按team共享、按`training_id`独立保存；农场等级只校验当前阶段前置条件，不负责跳阶段。
- 服务端扣费和Tooltip费用均使用`wood_cost/gold_cost + 当前阶段成功次数 * 对应increment`；扣费失败不得推进次数或增加人口。人口训练6达到100次后才进入全部完成状态。
- 实现及自动验证完成：CSV与生成Lua已恢复原始权威数据；`worker_system.lua`按阶段独立次数顺序推进，Tooltip投影阶段内进度和递增费用；专项Lua 5.1、PowerShell契约、相关回归、Lua语法和生成一致性均通过。
- 用户于2026-08-08明确反馈“问题已经解决了”，人口训练首次加载、阶段内次数和顺序推进修复记为用户实机验收通过；该人口训练问题不再作为活跃任务恢复。此确认不代表城墙锚点或其他组合项目已验收。

## 已纠正的旧结论（2026-08-08）：城墙固定锚点与人口训练阶段

- 已确认行为：城墙施工完成后固定在初始位置；碰撞或物理推移必须恢复；已有主动迁移继续可用，且每次成功迁移后以新位置作为固定锚点。
- 人口训练上一轮“全局五次、禁用阶段6”的结论已被用户明确纠正，不再有效；以本文顶部“按CSV阶段内次数顺序推进”为准。
- 原始CSV数据保持阶段1至5各5次、阶段6共100次且启用；运行时按阶段独立计数并满额后顺序推进。
- Tooltip Runtime动态发布当前阶段、阶段内进度、本次递增费用、人口增加、本次条件和下一阶段农场等级要求；所有CSV阶段完成后`available=0`、`can_afford=0`。Panorama继续使用已有托管白名单。
- 城墙完工和热恢复路径均设置`survival_fixed_position`并复用`modifier_building_stationary`周期恢复偏移；主动迁移在移动前更新该锚点，原有网格释放/占用和移动Ability保留。
- 自动验证通过：`POPULATION_TRAINING_LUA51_PASS`、`WALL_POSITION_ANCHOR_LUA51_PASS`、`POPULATION_WALL_CONTRACT_PASS`、`SIX_GAMEPLAY_FIXES_LUA51_PASS/CONTRACT_PASS`、修理工契约、Builder槽位回归、目标Lua 5.1语法、训练配置定向生成逐字节一致、严格UTF-8和限定`git diff --check`。`ability_tooltip.js`经Resource Compiler强制编译为`1 compiled, 0 failed, 0 skipped`。
- Node不在PATH，未执行`node --check`；正式Panorama Resource Compiler已完成语法/资源编译验证。生产建筑Lua原有UTF-8 BOM由测试临时内存去除后完成Lua 5.1行为/语法验证，没有重写既有文件编码。
- 人口训练已由用户确认解决。尚未Workshop Tools实机验收的范围仅保留：怪物或单位碰撞压力下城墙不漂移，以及主动迁移后固定在新位置。
- 无关阻断保持不变：单位模型旧契约仍引用缺失的`creep_bad_melee_cavern_mega.vmdl`，本任务未修改该数据。

## 插入活跃任务（2026-08-07）：城墙与怪物Hull调试、普通建筑原生模型尺寸

- 用户确认城墙基础Hull应直接为256；现有`scale`继续只调整选中己方城墙Hull，因此目标语义为`scale 1=256`，不改变模型。
- 已核对波次怪共用单位KV已有`BoundsHullName=DOTA_HULL_SIZE_SMALL`，当前并非无碰撞；怪物CSV没有Hull字段且生成链没有`SetHullRadius()`覆盖。新增`scalemonster <倍数>`只改变当前存活及之后生成波次怪的Hull，倍率1恢复每只怪首次读取到的原生Hull，禁止累计且不改变模型。
- 用户最新要求：研究所和人口农场的预建造模型、实际模型都与英雄祭坛相同，统一使用`radiant_ancient001.vmdl`和`ModelScale=0.34`；金矿保持上一要求的原生模型缩放1。
- 用户最新实测确认怪物碰撞体：普通小怪Hull 32，精英怪Hull 64，Boss无碰撞体。`scalemonster <倍数>`以这三个角色基准为准，不累计；Boss基准为0，任何正倍率仍无碰撞。
- 生产实现与自动验证已完成：城墙基础Hull为256；研究所/农场CSV施工视觉、运行视觉、生成Lua与KV回退均与英雄祭坛为0.34；新增角色Hull应用与`scalemonster`命令作用于当前及后续波次怪。
- 验证通过：`SIX_GAMEPLAY_FIXES_LUA51_PASS`、`SIX_GAMEPLAY_FIXES_CONTRACT_PASS`、`BUILDER_ABILITY_SLOTS_LUA51_PASS`、`UNIT_MODEL_CONFIG_LUA51_PASS`、`WAVE_TIMING_LUA51_PASS/WAVE_TIMING_CONTRACT_PASS`、`TASK_LUAC51_PASS count=6`、`BUILDING_VISUAL_BYTE_MATCH_PASS`、`TASK_STRICT_UTF8_PASS files=12`及限定`TASK_DIFF_CHECK_PASS`。
- 既有`test_unit_model_config_contract.ps1`仍只失败于本任务之前已知的无关伐木工模型CSV缺项`models/creeps/lane_creeps/creep_bad_melee/creep_bad_melee_cavern_mega.vmdl`，未修改无关数据迎合。
- 尚未Workshop Tools验收：确认默认城墙Hull 256的堵路效果；依次使用`scalemonster 1`及若干倍率观察怪物拥挤/穿行并记录通知中的原生/当前Hull；确认研究所、农场、金矿原生模型视觉尺寸。自动测试不能称为实机验证。

## 插入活跃任务（2026-08-07）：建筑、金矿反馈、城墙碰撞与波次首发规则

用户批准同时实施以下六项修复；本任务优先于下方多人阶段1待验收动作，但不得提前开展多人阶段4状态迁移：

1. 金矿模型缩放曾改为当前 `0.35` 的四分之一，即 `0.0875`；该历史目标已被上方用户最新“恢复模型原生缩放1”要求取代。
2. 金矿产出关闭原生金币飘字自带声音，但保留无声自定义金币飘字；普通与暴击均不得播放金币音效。
3. 农场最多建造1座；金矿最多建造5座；达到各自上限后从Builder移除对应建造技能，建筑销毁释放名额后允许恢复技能。
4. 聊天命令 `scale <number>` 调整当前选中的己方城墙Hull倍率；`1`为首次捕获的基础碰撞半径，`2`为两倍，模型外观不变。
5. 每波按 `assault_boss -> wave_leader -> normal` 生成；CSV `spawn_order` 为权威，不新增或删除任何成员，不改变数量、属性与时间字段。
6. 农场建造Tooltip显示权威首级成本：100木材、0金币，并移除“可重复建造”的错误说明。

### 已确认实现边界

- 当前金矿KV `ModelScale=0.35`，目标为 `0.0875`。
- 金矿产出声音来自 `SendOverheadEventMessage(... OVERHEAD_ALERT_GOLD ...)`，该接口无法单独静音；用户选择新增Panorama无声飘字。
- `building_definitions.csv`与当前生成Lua中的农场 `max_count` 已为1；错误仍存在于Builder阶段 `max_building_count=0`、旧说明及技能同步行为。
- 当前波次运行排序硬编码为 `wave_leader -> normal -> assault_boss`，必须停止覆盖CSV顺序。
- 当前多人建筑计数仍按team，本轮保持现状；不得借本任务扩大为未批准的多人阶段4重构。
- 工作区基线包含大量既有未跟踪 `tools/test_*` 文件，必须保留且不得清理、覆盖或纳入本轮修改。

### 验证要求

- 建筑/Builder/Tooltip/金矿飘字/城墙Hull/波次顺序专项PowerShell契约与Lua 5.1行为测试。
- CSV定向生成与生成Lua逐字节一致性；相关Lua `luac5.1`语法检查。
- Panorama JS/CSS与HUD XML强制编译，要求 `compiled > 0`、`failed=0`。
- 严格UTF-8、限定范围 `git diff --check`、最终文件复读与双仓库状态检查。
- 自动测试与资源编译不能称为Workshop Tools实机验证；金矿尺寸、无声飘字、技能移除、Hull碰撞和实际出怪顺序仍需冷启动实机验收。

### 实施状态（2026-08-07）

- 生产实现与自动验证已完成，尚未Workshop Tools实机验收。
- 金矿无声收入飘字实现保持不变；本段原有`tower_good4.vmdl / 0.0875`视觉结果已被上方最新原生缩放1要求取代。
- 农场运行上限和Builder阶段上限均为1，金矿为5；达到数量上限时移除对应Ability，`BUILDING_DESTROYED`释放名额后按原槽位恢复。等级不足等非数量条件继续使用原有置灰语义。
- `scale`的选择同步、服务端所有权验证与`0.25..4`范围保持不变；本段原有基准Hull 128已被上方最新基准256要求取代，仍不改变模型。
- 波次CSV共426个成员，仅335个`spawn_order`发生变化，按wave_id比较确认其他字段0变化；145个难度波次组均按`assault_boss -> wave_leader -> normal`。运行Builder停止按角色硬编码覆盖CSV。
- Tooltip生成器从建筑CSV映射建造技能，再从`building_levels.csv`投影首级成本；农场运行Tooltip与本地化均显示100木材、0金币。
- 自动验证通过：`SIX_GAMEPLAY_FIXES_LUA51_PASS`、`SIX_GAMEPLAY_FIXES_CONTRACT_PASS`、`BUILDER_ABILITY_SLOTS_LUA51_PASS`、`SIX_GAMEPLAY_FIXES_LUAC51_PASS count=8`、`WAVE_CSV_FIELDS_AND_ORDER_PASS rows=426 groups=145 changed_orders=335`、`TARGET_GENERATED_BYTE_MATCH_PASS count=4`、`TASK_STRICT_UTF8_PASS files=30`、`WAVE_TIMING_LUA51_PASS/WAVE_TIMING_CONTRACT_PASS`、Python工具语法、Tooltip幂等生成和双仓`diff --check`。
- Resource Compiler：新JS与CSS各`1 compiled, 0 failed, 0 skipped`，HUD XML链`9 compiled, 0 failed, 0 skipped`；依赖链自动改写的无关既有产物已按用户授权恢复，只保留本任务三个目标产物。
- 旧未跟踪N1/N2/N3/N4-N5波次测试仍断言leader首发或assault boss末发，与本轮批准需求直接冲突，未覆盖用户已有测试；本轮专项行为测试覆盖五个难度的新顺序。既有单位模型契约另失败于无关伐木工模型CSV缺失，本轮未修改无关配置。
- 待实机：金矿尺寸改按上方最新“模型原生缩放1”验收；普通/暴击产出有数字且完全无金币音效；第1农场/第5金矿后技能消失且销毁后恢复；选中己方墙执行`scale 1/2/0.5`的真实寻路碰撞且模型不变（当前基准256）；进攻Boss、领头、普通实际首发顺序；农场Tooltip视觉成本。

## 活跃任务（2026-08-06）：多人联机系统

### 用户确认的玩法

- 目标支持最多4名玩家；第一轮先做2人纵向切片，再扩展到4人。
- 所有玩家属于好人方，但每名玩家拥有独立的经济、人口、建筑、Builder、英雄、科技、成长状态和一套波次怪物。
- 战场空间共享，玩家初始区域按东南西北等固定槽位配置；区域只决定出生位置，不决定业务归属。
- 玩家可以把自己的城墙建到其他玩家区域，与其他城墙集中防守。这是允许的玩家策略，不应被区域限制阻止。
- 每批怪物绑定其所属玩家，并始终攻击该玩家自己的城墙实体；不得按最近城墙、固定区域或最后创建的城墙选目标。
- 英雄允许跨区域支援其他玩家并攻击其他玩家所属的波次怪。
- 玩家不能控制他人的英雄、Builder、工人、建筑、防御塔、召唤物或其他可控单位。
- 所有客户端只提交操作意图；资源、建造、波次、伤害、奖励和胜负由服务端权威结算。Dota 2引擎负责同步实体、位置、生命、Modifier、攻击和投射物，不另做客户端独立模拟或lockstep。

### 核心身份边界

- `player_id`：资源、建筑、单位、怪物、挑战和奖励的业务归属权威。
- `slot_id/lane_id`：玩家初始出生点和波次出生点，只表示地图槽位。
- `team`：仅表示Dota敌我阵营；不能继续作为玩家经济、建筑上限、Builder阶段或波次状态的唯一键。
- 单位归属和单位当前位置必须分离。移动到别人区域不会改变owner。
- 客户端payload中的`player_id`不可信；Custom Game Event必须从事件来源获得真实玩家身份，并校验caster、ability、target和业务状态归属。

## 多人联机任务清单

### 阶段1：多人配置、玩家上下文与身份基础（进行中）

#### 生产改造

- [x] 新增CSV权威多人规则，配置最大玩家数、初始实现人数、共享波次时钟、英雄跨区支援等长期规则。
- [x] 新增CSV权威玩家槽位，配置`player_id`、`slot_id`、Builder出生marker、波次出生marker、旧地图回退和启用状态。
- [x] 生成对应Lua配置，禁止直接手改生成文件。
- [x] 新增`player_context_service`，统一提供玩家槽位、marker解析、单位owner登记、owner查询和ownership校验。
- [x] `addoninfo.txt`和启动规则改为最多4名好人方玩家；保持坏人方玩家数为0。
- [x] Builder创建改为按玩家槽位解析出生点，并继续设置`SetPlayerID`、`SetOwner`、`SetControllableByPlayer`和`survival_player_id`。
- [x] 玩家0允许旧地图坐标兼容回退；玩家1至3缺少marker时必须失败关闭并输出明确日志，禁止全部叠在`(0,0)`。
- [x] 保持单人旧地图可启动，阶段1不宣称独立经济、独立波次或完整联机已完成。

#### 自动验证

- [x] PowerShell契约：CSV、生成Lua、最大玩家数、服务初始化和Builder接入一致。
- [x] Lua 5.1行为：4个槽位、marker优先、玩家0旧回退、非0玩家缺marker失败、owner登记和跨玩家拒绝。
- [x] `luac5.1`语法检查。
- [x] CSV与生成Lua逐字节一致性。
- [x] 严格UTF-8和限定`git diff --check`。

#### Workshop Tools验收

- [ ] 单人冷启动保持正常，玩家0 Builder仍能生成和建造。
- [ ] 地图加入玩家1 marker后，两客户端分别生成在自己的槽位。
- [ ] 日志能看到每名玩家的`player_id/slot_id/builder_spawn_marker/entindex`。

### 阶段2：两人纵向切片

- [ ] Hammer地图增加至少2套Builder出生marker和波次出生marker；最终预留4套。
- [ ] 两名玩家分别生成占位英雄、Builder和初始UI。
- [ ] 两人可同时建墙、主城和箭塔，状态不互相覆盖。
- [ ] 两人无法通过鼠标、快捷键、框选或原生命令控制对方单位。
- [ ] 双方资源显示与服务端状态一致。
- [ ] 完成两客户端Workshop Tools实机验收后再进入全面状态迁移。

### 阶段3：统一服务端命令权限

- [ ] 将现有树木攻击Order Filter迁入唯一组合`ExecuteOrderFilter`，避免多个模块互相覆盖。
- [ ] 对移动、攻击、停止、巡逻、施法、拾取、丢弃和多单位命令检查全部命令单位的owner。
- [ ] 审计全部Custom Game Event入口，统一从事件来源取得PlayerID。
- [ ] 校验客户端传入的entindex、ability、target、位置、session和请求顺序。
- [ ] 增加伪造他人单位、混合编队、迟到请求和重复请求测试。

### 阶段4：个人经济、建筑与成长状态

- [ ] 资源账户从`accounts[team]`迁为`accounts[player_id]`：金币、木材、人口和人口上限全部独立。
- [ ] Builder阶段从`state_by_team`迁为`state_by_player`。
- [ ] 建筑数量、城墙一次性状态、主城等级和建筑上限按玩家计算。
- [ ] 工人训练、金矿、科技等级和研究事务按玩家隔离。
- [ ] 塔升级、转职、科技加成和七塔融合只消费同一玩家的塔。
- [ ] 回城查找玩家自己的主城，不再使用`main_city_for_team()`。
- [ ] UI快照和NetTable key按玩家投影；客户端资源快照仍无服务端否决权。

### 阶段5：每玩家独立波次实例

- [ ] 全局单例`wave_system`拆为`state_by_player/enemies_by_player/wall_by_player/spawn_marker_by_player/generation_token_by_player`。
- [ ] 每名活跃玩家每波生成独立的一份怪物。
- [ ] 第一版使用全局统一难度和统一波次开始时钟，个人保存计划数、已生成、存活、击杀和失败状态。
- [ ] 每只怪保存`survival_wave_player_id`、波次号和目标城墙身份。
- [ ] 怪物只追踪所属玩家的城墙实体；城墙建在其他区域或与他人城墙重叠时仍保持正确目标。
- [ ] 城墙销毁、重建、移动和实体失效时更新该玩家怪物目标，不影响其他玩家。
- [ ] 波次UI展示本地玩家状态，并可按需求展示队友概要。

### 阶段6：失败、胜利、支援和奖励归属

- [ ] 某玩家城墙死亡后只淘汰该玩家、停止其后续波次并清理其波次怪；其他玩家继续。
- [ ] 所有玩家淘汰时失败；所有仍活跃玩家完成最终波次时胜利。
- [ ] 英雄可自由跨区域支援，不改变单位owner。
- [ ] 基础波次经济建议归怪物所属玩家，避免支援抢最后一击破坏其经济。
- [ ] 击杀成长、装备触发和支援奖励另行明确，必须通过CSV配置后实施。

### 阶段7：挑战、商店、装备与UI多人回归

- [ ] 审计转生、十戒、练功房、特殊挑战和同一挑战并发规则。
- [ ] 审计地面掉落、Claim、背包、装备实例、合成和成长归属。
- [ ] 审计英雄召唤、技能选择、商店购买、科技、通知、Tooltip和自定义NetTable。
- [ ] 同一`encounter_id`如允许多人同时开启，运行身份必须包含player/session，不能继续全局唯一覆盖。
- [ ] Custom Net Tables只用于客户端可读UI快照，不存放需要保密的数据或高频操作日志。

### 阶段8：四人、掉线重连、性能和最终回归

- [ ] 从2人扩展到4人并完成东南西北槽位。
- [ ] 玩家加载速度不同、掉线、重连和永久退出均有明确生命周期。
- [ ] 重连恢复自己的Builder、英雄、建筑、资源、波次和UI。
- [ ] 多人同帧建造、扣费、研究、挑战和奖励事务保持原子与幂等。
- [ ] 检查4份波次实体量、投射物、Modifier、NetTable和Panorama性能。
- [ ] 完成两台或多台真实客户端实机验收；Mock和单机多实例不能替代最终网络验收。

## 编辑器联机验收方案

- 不需要先发布Workshop。开发地图可以在Workshop Tools中由主机启动本地服务器/大厅，其他Steam客户端加入。
- 推荐使用两台电脑、两个Steam账号、同一局域网；两台机器都安装相同Dota 2 Workshop Tools和完全一致的addon内容/编译产物。
- 主机通过Workshop Tools启动addon和`template_map`；客户端使用Steam好友加入、开发大厅或控制台`connect <主机局域网IP>:27015`，具体可用入口以当前Dota版本实测为准。
- 主机防火墙需允许`dota2.exe`，必要时开放UDP/TCP 27015；不得把能进入地图误认为业务联机验收通过。
- 一台电脑多客户端只适合辅助检查，需要多Steam实例/账号且性能与输入焦点限制明显；最终验收仍建议两台电脑。
- 每轮联机测试必须确认两端使用相同文件版本，并分别保存服务端控制台日志和客户端截图/录像。

## 当前检查点

- 当前阶段：阶段1生产实现与自动验证完成，等待Workshop Tools单人冷启动验收。
- 当前地图源存在`template_map.vmap`和`survival_dev.vmap`，运行产物为`maps/template_map.vpk`。
- 已确认旧地图只有单个历史波次marker `monsterborn`；尚未确认4套玩家marker。
- 当前启动规则和`addoninfo.txt`已开放4名好人方玩家；后续玩家由`player_connect_full`分配到好人方。
- 旧`CURRENT_TASK.md`和旧`START_HERE.md`已完整归档到`docs/ai/archive/2026-08-06-pre-multiplayer-*.md`；旧任务全部暂停，不得自动恢复。
- 工作区已有大量未跟踪测试文件，属于用户既有内容，本任务不得覆盖、清理或纳入交付。

## 下一步唯一动作

用户在Workshop Tools冷启动`template_map`做阶段1单人兼容验收：确认玩家0 Builder正常生成、可选择并可建造，日志包含`[MULTIPLAYER_CONTEXT]`与`[BUILDER_READY] player=0 slot=east ... source=legacy_coordinates`。通过后进入Hammer双槽位和两客户端联机测试。
## 阶段1自动验证记录（2026-08-06）

- `MULTIPLAYER_CONTEXT_CONTRACT_PASS`：CSV、生成Lua、服务接入和4人启动契约通过。
- `MULTIPLAYER_CONTEXT_LUA51_PASS`：4槽位、marker优先、玩家0旧回退、非0缺marker失败、owner冲突和跨玩家拒绝通过。
- `MULTIPLAYER_BUILDER_INTEGRATION_LUA51_PASS`：玩家0 Builder旧地图生成、CSV移速保持、owner登记和玩家1缺marker拒绝通过。
- `MULTIPLAYER_LUAC51_PASS`：本轮Lua生产文件、生成文件和专项测试语法通过。
- `MULTIPLAYER_GENERATED_CONFIG_MATCH_PASS`：两份CSV临时重生成结果与提交生成Lua逐字节一致。
- `MULTIPLAYER_STRICT_UTF8_PASS`和限定`git diff --check`通过。
- 未跟踪既有`test_builder_ownership.lua`失败于硬编码期望Builder移速600，而当前权威CSV和生成Lua均为300；本轮未修改移动速度逻辑。
- 未跟踪既有`test_builder_utility_contract.ps1`失败于`MONKEY_CSV_RANGE_1000_MISSING`；与本轮多人身份改造无关，未修改该测试或Monkey配置。
- 尚未执行Workshop Tools实机验证，不能称为联机或单人实机验收通过。