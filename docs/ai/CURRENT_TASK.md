# Current Task

## 活跃任务（2026-08-03）：资源树仅承受基础平A，防御塔禁止攻击树

- 用户要求`enemy_tree`只承受引擎基础普通攻击伤害；任何技能、脚本、持续、范围及平A触发的技能/装备附伤都不得扣树生命。
- 英雄、伐木工、波次怪、挑战怪和召唤物等非防御塔单位的基础平A仍可伤树。
- 所有箭塔与转职塔使用统一身份`survival_building_id == "arrow_tower"`：不得自动选择树，不得通过玩家手动攻击命令攻击树，已在飞行中的塔弹道也不得扣树生命。
- 用户已确认边界并批准实施：只保留引擎基础平A伤害；所有攻击触发附伤均不计入树伤害。
- 计划扩展既有`modifier_tree_progression`承伤规则，复用全局伤害过滤器的`damage_category_const`，扩展`modifier_tower_auto_attack`选敌，并新增最小OrderFilter服务拦截塔对树的手动攻击命令。
- 本任务无新增策划数值，不修改已有编码风险的建筑CSV，也不直接修改generated Lua。
- 验证至少包含专项PowerShell契约、Lua 5.1行为测试、`luac5.1 -p`、树/塔/伤害回归、严格UTF-8和限定`git diff --check`；自动验证不能替代Workshop Tools中的塔选敌、右键命令与实际扣血验收。

### 实施结果与当前状态

- 已新增共享规则`systems/tree_damage_rules.lua`：只把`DOTA_DAMAGE_CATEGORY_ATTACK`视为树可承受的基础攻击类别；未知或缺失类别在全局DamageFilter中失败关闭；`survival_building_id == "arrow_tower"`始终禁止伤树。
- `modifier_tree_progression.lua`保留最低1血与耗尽升级调度，并增加承伤属性作为第二层保护。全局DamageFilter是伤害类别权威；考虑部分引擎版本可能不向modifier属性参数提供`damage_category`，modifier在类别缺失时交由全局过滤器判断，但仍直接拦截可识别的箭塔攻击。
- `modifier_tower_auto_attack.lua`已从自动搜索中排除树；当前目标或强制目标是树时会清除并重新选择合法敌人；攻击开始事件另行停止塔对树的竞态攻击。
- 已新增`systems/tree_attack_order_filter.lua`并由`addon_game_mode.lua`启动注册，只拒绝箭塔单位对`enemy_tree`的`DOTA_UNIT_ORDER_ATTACK_TARGET`，其他单位、目标和命令不变。
- 专项验证通过：`TREE_DAMAGE_RULES_CONTRACT_PASS`、`TREE_DAMAGE_RULES_LUA51_PASS`、`TREE_DAMAGE_RULES_LUAC51_PASS`、`TREE_DAMAGE_RULES_STRICT_UTF8_PASS`和`TREE_DAMAGE_RULES_DIFF_CHECK_PASS`。行为测试覆盖英雄/怪物/召唤物基础平A放行、技能/未知脚本/塔平A拦截、DamageFilter事务消费、手动命令过滤、自动选敌跳过树、攻击开始清理、间隔重新选敌以及最低1血后的升级调度。
- 工作期间外部进程将生产改动提交为`00bfe05`并修改`.gitignore`；用户明确选择接受新HEAD、保留外部`.gitignore`并继续验证。两个专项测试文件仍在磁盘并已执行通过，但被外部`.gitignore`第103至104行忽略，未纳入Git状态。
- 尚未完成Workshop Tools实机验证，不能记录为制作完成或用户验收。需验证：各转职塔自动忽略树；右键/攻击命令无法令塔攻击树；其他单位基础平A可扣树生命；技能、平A触发技能/装备附伤与无Ability脚本伤害不扣树生命；树到1血后仍正常升级刷新。

## 已完成任务（2026-08-02）：四名免费英雄替换

- 用户已批准将原有非VIP英雄替换为末日使者、影魔、斧王、黑暗游侠；齐天大圣与剑圣两名VIP英雄保持不变。
- 四名免费英雄沿用普通模板：逻辑三维及成长100、基础攻击20、攻速0.7、War3护甲1、移速2000、生命3000；末日/斧王射程500，影魔/黑暗游侠射程1200。
- 四个专属技能均为1级、固定Q槽；召唤英雄时可见但置灰，一转成功后原位激活，不能用公共技能点升级。
- 末日：主攻击命中10%概率召唤术士地狱火，持续10秒，继承触发时100%权威攻击力、攻击速度、最大生命和运行时护甲，不继承英雄/装备附加攻击效果。地狱火活动期间跳过概率判定，死亡或到期后解锁。
- 影魔：主攻击命中10%概率在目标位置造成250范围影压；本次先加层再伤害，1至5层分别为全属性×27.5/30/32.5/35/37.5纯粹伤害；每层独立持续3秒，最多5层。
- 斧王：主攻击命中10%概率以攻击目标为中心触发400范围反击螺旋，造成触发时全属性×30纯粹伤害。
- 黑暗游侠：主攻击命中10%概率召唤无敌小游侠，持续10秒，继承触发时150%权威攻击力和100%攻击速度；每次攻击主目标并攻击射程内最近另外4个敌人，次级攻击不得触发英雄/装备/技能Proc。小游侠活动期间跳过概率判定，到期或实体失效后解锁。
- CSV是权威源；先修改英雄定义、专属关系、技能定义、弹道和Tooltip CSV，再生成Lua。不得覆盖`hero_skill_definitions.csv`中已有的公共技能完整五级描述修改。
- 用户已于2026-08-02明确确认任务成功并验收通过；该结论是用户验收，不应与自动测试或逐项引擎诊断混为一谈。

### 实施结果

- 已完成权威CSV、生成Lua、祭坛按钮、召唤脚本、Ability KV、专用召唤单位KV、中英文三套本地化镜像与预缓存替换；生产入口不再引用斯拉克或主宰。
- 四名免费英雄召唤后会在Q槽预创建项目等级0的专属技能；引擎壳保持1级可见但`SetActivated(false)`，一转授予时同一技能原位切换到项目等级1并激活。VIP英雄不预创建，保留原一转四专属顺序。
- 新增`hero_exclusive_passive_service.lua`管理四技能运行状态；伤害仍注入并复用`hero_passive_skill_service.lua`既有`deal_group -> combat_events.DEAL_REQUEST`事务。
- 地狱火和小游侠使用唯一活动锁，概率调用前先检查召唤实体存活与到期；影压使用每目标独立到期时间数组；小游侠次级攻击通过攻击record标记与`PerformAttack(..., bProcessProcs=false, ...)`隔离。
- 地狱火和小游侠均读取触发瞬间战斗快照中的权威`attack_speed`（每秒攻击次数），按100%继承并通过`SetBaseAttackTime(1 / attack_speed)`应用；同步记录`survival_attack_speed`供实机诊断。
- 已通过：`FREE_HERO_REPLACEMENT_CONTRACT_PASS`、`FREE_HERO_EXCLUSIVE_STATE_LUA51_PASS`、`FREE_HERO_ALL_CHANGED_LUAC51_PASS`、`FREE_HERO_GENERATION_CONSISTENCY_PASS`、`FREE_HERO_KV_UNIQUENESS_PASS`、`FREE_HERO_TASK_FILES_STRICT_UTF8_PASS`、`FREE_HERO_LOCALIZATION_STRUCTURE_PASS`、限定`git diff --check`，以及英雄生命/原生Ability保留/addskill和多项公共被动回归。
- 已知测试边界：用户实施前已有的未跟踪`test_blade_pulse_contract.ps1`仍断言已批准删除的旧`ability_survival_axe_exclusive`；`test_flame_burst_contract.ps1`要求HEAD中原本就未预缓存的Dragon Slave粒子。未修改无关生产逻辑迎合这两条旧断言。
- 完成结论：用户已确认整体任务成功；不再保留本任务待办，也不得依据旧验收清单自动恢复。只有用户以后报告具体回归或提出新需求时才重新开启。

## 最新状态（2026-08-02）

## 活跃任务（2026-08-02）

新增公共技能 `proto_echo_slash` / “回音重斩·被动”。用户已确认：LV1攻击命中12%概率，发射1道总宽200的弧形斩，路径所有单位受到触发时全属性×1伤害；LV2波数+1、概率15%、波间隔0.1秒；LV3波数再+1；LV4完整继承LV3；LV5波数再+1，每波独立随机提高5%～20%伤害。斩击从触发英雄位置朝被攻击目标当时位置固定方向移动，距离等于攻击触发时英雄攻击射程，1秒走完全程；每道波真实穿透命中并独立去重，复用项目逻辑属性快照和既有纯粹伤害事务。计划新增 `public_13`，复用 `proto_blade_nova` 的线性投射物机制；用户已批准开始实施。

### 本任务实施边界

- 权威配置先修改 `data/csv/英雄系统/hero_skill_definitions.csv`、`data/csv/英雄系统/hero_skill_pool_members.csv` 和 `data/csv/公共规则/tooltip_definitions.csv`，再定向生成对应 Lua。
- 运行配置位于 `scripts/vscripts/config/hero_passive_skill_definitions.lua`；真实碰撞和伤害位于 `scripts/vscripts/systems/hero_passive_skill_service.lua`；能力路由复用 `scripts/vscripts/abilities/survival_hero_skill.lua`。
- LV5每道波分别随机抽取5%～20%增伤；同次触发固定起点、目标方向、距离和全属性快照。未额外设置活动锁，允许不同攻击触发并行。
- 尚未验证：弧形斩粒子的实际视觉资源、Workshop Tools 中的宽度/连续波观感和真实引擎碰撞；自动测试不能替代实机验收。

### 当前实施结果

- 已新增 `proto_echo_slash`、`ability_survival_echo_slash`、公共池成员 `public_13` 和五级 Tooltip。
- 三份权威CSV已更新并定向生成英雄技能、公共池和Tooltip Lua；生成比较逐字节一致。
- 运行时使用马格纳斯震荡波粒子和独立线性投射物状态；每道波 `bDeleteOnHit=false`、独立去重、回调返回false，终点和超时均可清理。
- 多波使用绝对时间校正的单链调度；LV5每波创建时独立抽取5%～20%增伤，触发时逻辑全属性快照在整次技能中保持不变。
- 自动验证通过：`ECHO_SLASH_STATE_LUA51_PASS`、`ECHO_SLASH_CONTRACT_PASS`、`ECHO_SLASH_LUAC51_PASS`、配置Lua 5.1验证、CSV生成比较、严格UTF-8、限定`git diff --check`、脉冲激射/地裂/魔法弹弓共享回归。
- 脉冲激射完整PowerShell契约存在既有陈旧预缓存断言，仍要求已废弃的Vengeful粒子；其Lua 5.1状态测试通过，本任务未修改该旧测试。
- 剩余动作仅为Workshop Tools实机验证；尚不能记录为引擎验证或用户验收完成。

用户已明确确认现有公共技能`proto_earth_line`五级“地裂冲击·被动”暂时完成。当前基线停止继续调整，不再把Workshop Tools逐项验证恢复为活跃任务；只有用户以后明确提出地裂冲击的新需求或报告实机问题时，才按下述维护方式重新开启。

### 地裂冲击自动验证

- `EARTH_LINE_STATE_LUA51_PASS` / `EARTH_LINE_CONTRACT_PASS`。
- `EARTH_LINE_LUAC51_PASS`：运行配置、两份生成Lua、公共被动服务、Tooltip运行服务、游戏模式和专项状态测试通过Lua 5.1语法检查。
- `EARTH_LINE_GENERATED_COMPARE_PASS`：英雄技能生成Lua与权威CSV逐字节一致；Tooltip生成行与权威CSV一致且生产生成文件仅改变地裂目标行。
- 严格UTF-8、乱码标记检查和限定`git diff --check`通过。
- 脉冲激射、魔法弹弓、寒冰锥、元气弹、陨石坠落和移动冰球相关回归通过。

### 地裂冲击后续修改入口

- 配置或文案修改必须先改`data/csv/英雄系统/hero_skill_definitions.csv`和`data/csv/公共规则/tooltip_definitions.csv`，再定向生成对应Lua；禁止直接维护生成Lua。
- 数值和等级行为修改同步检查`scripts/vscripts/config/hero_passive_skill_definitions.lua`、`scripts/npc/npc_abilities_custom.txt`和`scripts/vscripts/ui/ability_runtime_service.lua`。
- 移动、碰撞、伤害、眩晕、首次范围伤害或清理规则修改集中在`scripts/vscripts/systems/hero_passive_skill_service.lua`，继续复用线性投射物、逻辑属性快照和现有伤害事务，不恢复旧`line_targets()`瞬时扫描。
- 修改后至少运行`tools/test_earth_line_contract.ps1`、`tools/test_earth_line_state.lua`、Lua 5.1语法检查、CSV生成一致性、严格UTF-8、限定`git diff --check`以及相关公共技能回归。
- Tiny岩石视觉、150/250引擎碰撞和LV2视觉尺寸属于未来发生相关问题时再执行的Workshop Tools检查项；当前不作为阻止“暂时完成”的待办。

## 活跃任务（2026-08-02）

将公共技能`proto_meteor`重做为五级“陨石坠落·被动”，保留Ability ID `ability_survival_meteor`、公共池身份、图标和存档兼容性。

## 用户已确认边界

- LV1普通攻击命中12%概率触发，记录目标当时的地面位置；陨石坠落后原地爆炸，不进行卡尔原版陨石的滚动。500半径造成触发时逻辑全属性×3纯粹伤害。
- LV2每颗陨石留下500半径、持续3秒的熔岩区域；落地后第1/2/3秒各造成一次触发时全属性×1纯粹伤害，落地瞬间不额外结算熔岩伤害。
- LV3熔岩区域内敌人降低30%移动速度；离开所有区域立即移除，多个区域重叠不叠加。
- LV4完整继承LV3，无新增效果。
- LV5在同一记录位置连续落下两颗陨石，第二颗比第一颗晚0.5秒落地；第二颗爆炸和熔岩伤害均为80%，即×2.4和每秒×0.8。两片熔岩独立造成伤害。
- 同一英雄从触发成功到最后一颗陨石的最后一次熔岩伤害完成前，不再进行该技能的12%概率判定；LV1在爆炸完成后解锁。锁不影响其他被动技能。
- 所有伤害复用触发瞬间的同一份项目逻辑三维快照、既有伤害服务和Ability句柄。

## 当前状态

**CSV、运行配置、被动服务、Ability KV、Tooltip、Buff、定向生成和自动测试均已完成。用户已于2026-08-02实机确认`addmonster` 600移速测试基准下的熔岩30%减速正常；其余表现仍按用户后续验收结论记录。**
- 元气弹飞行视觉已替换为 Sven Storm Hammer 完整追踪弹体；LV5独立20%范围爆炸已替换为 Storm Hammer 原生爆炸，权威伤害范围继续读取技能定义的250码。

## 工作区保护

- 调查阶段后出现最新提交`c36c56e`；已确认目标服务工作区哈希与HEAD一致，属于既有改动安全提交，不是回滚或外部未提交覆盖。
- 当前仍有大量未跟踪测试文件；不得删除、覆盖或顺带整理。本任务仅新增陨石专项测试并修改直接相关文件。
将公共技能 `proto_flame_burst` Lv5 三颗随机溅射小火球的视觉从莉娜龙破斩替换为 Snapfire Mortimer Kisses，保留显示名“爆炎弹·被动”、Ability ID `ability_survival_flame_burst`、公共池身份及全部五级战斗规则。
- `SPIRIT_BOMB_VISUAL_STATE_PASS` / `SPIRIT_BOMB_VISUAL_CONTRACT_PASS`
- 元气弹视觉生产Lua与新状态测试通过当前Lua/Luac 5.4.5语法；四个任务文件通过严格UTF-8、无BOM和尾随空白检查；限定`git diff --check`通过。
- `SPIRIT_BOMB_STATE_LUA51_PASS` / `SPIRIT_BOMB_CONTRACT_PASS`
- `POISON_CLOUD_STATE_LUA51_PASS` / `POISON_CLOUD_CONTRACT_PASS`
- 奥术弹幕、魔法弹弓、爆炎弹、移动冰球、寒冰锥、脉冲激射和龙卷风相关回归通过。
- 8个相关Lua文件通过 `luac5.1 -p`；12个相关源/生成/测试文件通过严格UTF-8检查；CSV与生成Lua的元气弹字段一致；限定范围 `git diff --check` 通过。
- 完整生成器在本任务无关的 `item_definitions.csv` 历史列错位处失败；已使用同一生成模块定向重建英雄技能，并使用Tooltip专用生成器重建Tooltip。生成内容差异仅包含本任务两份目标Lua。

## 自动验证结果

- `METEOR_STATE_LUA51_PASS` / `METEOR_CONTRACT_PASS`。
- `METEOR_LUAC_PASS`：运行配置、公共被动服务、Tooltip服务、三份生成Lua和专项状态测试通过Lua 5.1语法检查。
- `METEOR_GENERATED_COMPARE_PASS`：英雄技能和Buff生成Lua与权威CSV定向重建结果逐字节一致；Tooltip专用生成器通过并仅改变陨石目标行。
- 奥术弹幕、寒冰锥、魔法弹弓、爆炎弹、移动冰球、毒云、元气弹、脉冲激射和龙卷风专项回归全部通过。
- 本任务12个核心源/生成/测试文件通过严格UTF-8和乱码检查；限定`git diff --check`通过。
**陨石坠落视觉现由卡尔Chaos Meteor飞行粒子负责0.8秒坠落，落地时立即清除卡尔陨石并衔接术士Rain of Chaos纯爆炸粒子；不创建地狱火单位。**
- 术士爆炸使用独立ID和注册表管理，完整播放3.1秒后强制销毁并释放；LV1解锁不会提前截断爆炸，LV5两次爆炸独立清理，`clear_meteors()`会取消任务并立即清除全部残留，迟到回调幂等。
- 本轮验证：`METEOR_VISUAL_STATE_PASS`、`METEOR_VISUAL_CONTRACT_PASS`和目标Lua 5.4语法通过；爆炎弹、怒雷、元气弹视觉状态/契约及剑刃震荡视觉契约通过。合并基线中的移动冰球重复粒子常量仍导致其Puck Orb状态断言失败，本任务未修改该无关区域。

## 剩余动作

- 陨石LV3-LV5减速专项已验收：实际数值为30%而非20%；可攻击`addmonster`使用600基础移速和600移速上限后，用户实机确认减速正常。正常波次怪物未改变，不可攻击调试怪仍为0移速。
- 冷重启Workshop Tools，确认多目标Storm Hammer弹体均正确追踪、普通命中自带EndCap爆裂、LV5额外爆炸位置正确且连续触发无粒子残留。
- 完全重启 Workshop Tools Run，实机验证追踪视觉、5/7/9目标数量、每颗命中伤害与治疗、LV5独立爆炸及毒云活动期间不重触发。
- 自动测试、契约检查和Lua模拟不能替代实机验证；只有用户明确确认后才能记录为完成验收。

## 元气弹已确认边界

- LV1主攻击命中12%概率触发，在英雄普攻范围内选择最近最多5个敌人并分别发射追踪投射物；每颗真实命中造成触发时逻辑全属性×4纯粹伤害。
- LV2每颗真实命中恢复英雄5%最大生命值；按实际命中数累计并不超过最大生命值。
- LV3基础目标上限提高到7，每次触发另有10%概率提高到9；LV4完整继承LV3，无新增效果。
- LV5每颗命中独立20%概率在目标位置产生250范围爆炸，范围内所有敌人受到该颗基础伤害60%的额外纯粹伤害；原命中目标重复计算爆炸伤害。
- 攻击射程复用现有运行缓存、Script API、引擎API和英雄生成配置回退；投射物使用 `CreateTrackingProjectile` 和真实命中回调。

## 毒云新增边界

- 同一英雄已有活动毒云时，不再进行该技能的再次触发判定，也不替换旧毒云；仅在旧毒云自然结束或清理后允许再次触发。

## 已确认边界

- LV1主攻击命中15%概率触发；主龙卷从攻击者位置出发，以500速度实时追踪原攻击目标当前位置。
- 主龙卷第一次到达目标后附着跟随：目标移动时龙卷中心直接同步目标当前位置，不再产生500速度追赶距离。
- 原攻击目标在到达前死亡时，主龙卷继续移动到目标最后存活位置；在附着后死亡时，龙卷固定在死亡位置。两种情况均静止等待3秒结束。
- 主龙卷在t=0/1/2结算三次；每次实时读取攻击者当前逻辑力量、敏捷、智力总和，对中心300范围内每个敌人最多造成一次全属性×2纯粹伤害。
- 龙卷影响范围为中心600。LV3起范围内敌人降低20%移动速度；被主龙卷命中的敌人在仍处于600范围时额外降低15%，总计35%；离开范围立即移除对应效果。
- LV2仅完整继承当前速度500与LV1效果；LV4完整继承LV3，无新增效果。
- LV5主龙卷结束时统计仍存活且曾被主龙卷命中的不同目标。每个目标对应一个无上限小龙卷，从主龙卷结束位置朝随机目标方向移动。
- 小龙卷持续2秒，速度500、影响范围600、命中范围300、t=0/1结算；每次实时属性伤害为主龙卷的60%，即全属性×1.2纯粹伤害。
- 小龙卷只施加范围20%减速，不施加主龙卷命中额外15%减速，也不继续分裂。
- “随机目标方向”使用主龙卷结束时仍存活的已命中目标作为方向候选。
- 飞行主体使用 `particles/units/heroes/hero_snapfire/hero_snapfire_ultimate.vpcf`，CP0为主爆炸中心，CP1为按随机落点与0.5秒飞行时间计算的速度。
- 落地瞬时冲击使用 `particles/units/heroes/hero_snapfire/hero_snapfire_ultimate_impact.vpcf`，CP3为权威随机落点。
- 不使用持续3.1秒的`hero_snapfire_ultimate_linger.vpcf`，也不使用原生半径约428的`hero_snapfire_ultimate_calldown.vpcf`，避免错误暗示持续伤害或错误范围。
- 不改变15%触发、500主爆炸范围与×4伤害、点燃规则、LV5三颗、200随机落点、0.5秒同步落地、250溅射范围、×3伤害及逐颗点燃结算。
- 粒子只负责表现；随机落点、同步时序、目标查询、伤害和点燃继续由Lua权威逻辑负责。

## 验证结果

- `TORNADO_STATE_LUA51_PASS`
- `TORNADO_CONTRACT_PASS`
- `FLAME_BURST_STATE_LUA51_PASS` / `FLAME_BURST_CONTRACT_PASS`
- `POISON_CLOUD_STATE_LUA51_PASS` / `POISON_CLOUD_CONTRACT_PASS`
- `MOVING_ICE_BALL_MATH_LUA51_PASS` / `MOVING_ICE_BALL_CONTRACT_PASS`
- `MAGIC_SLINGSHOT_TARGETS_LUA51_PASS` / `MAGIC_SLINGSHOT_CONTRACT_PASS`
- `ICE_CONE_CONTRACT_PASS`
- `BLADE_PULSE_STATE_LUA51_PASS` / `BLADE_PULSE_CONTRACT_PASS`
- 相关生产、配置和测试 Lua 均通过 `luac5.1 -p`；严格 UTF-8 检查通过；限定范围 `git diff --check` 通过；CSV与生成Lua关键字段一致。
- Workshop Tools冷启动确认三颗Mortimer Kisses弹体的朝向、速度、同步落地、CP3冲击位置、重叠表现及无粒子残留。
- 当前历史Lua 5.1编译器路径已失效；目标Lua已通过当前可用Lua 5.4.5语法检查，不能宣称Lua 5.1验证通过。
- 全量63个Lua测试中54个通过、9个既有无关测试失败；目标爆炎弹状态测试及全部相邻视觉状态/契约均通过，失败清单已记录在`SESSION_LOG.md`。

## 后续优化与剩余确认

- 后续继续本任务时，再按用户指定重点优化龙卷视觉、追踪手感或其他表现；不得在没有明确需求时主动改变当前行为和数值。
- 尚未记录为最终用户验收的项目包括：完全重启Workshop Tools Run后的龙卷追踪、到达后附着、目标死亡后的最后位置、范围减速、实时属性伤害和LV5分裂方向。
- 若仍异常，收集同一龙卷ID的`[HeroTornado] event=spawn/attached/target_dead/finish`日志；普通`[CombatDamage]`日志只能证明伤害事务，不能证明视觉位置。

## 恢复规则

- 当前任务处于“阶段性完成/暂停优化”状态，不是活跃编码任务。
- 新会话不得自动继续修改；只有用户明确要求继续优化该技能时，才恢复为活跃任务。
- 恢复时以本文件中的已确认边界和`PROJECT_CONTEXT.md`中的稳定粒子架构为基线。

## 工作区保护

- 工作区已有大量用户未提交修改，目标服务和游戏模式文件在本任务前已处于修改状态。
- 只在当前内容基础上替换目标粒子常量和对应预缓存，不回滚、覆盖或顺带清理其他修改。
- 完全重启 Workshop Tools Run，实机验证卡尔Chaos Meteor从空中坠落并在落地时消失、同点衔接术士Rain of Chaos纯爆炸且不出现地狱火单位、爆炸约3.1秒后无残留、Viper Nethertoxin熔岩继续存在、双陨石0.5秒落地间隔、500范围、3次跳伤、30%减速进入/离开和活动期间不重触发。
- 自动契约、Lua模拟和语法检查不能证明Dota粒子的实际尺寸、颜色、落地手感或引擎最终扣血；只有用户明确确认后才能记录为实机验收完成。