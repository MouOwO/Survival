# Current Task

## 当前实施任务（2026-08-11）：玩家级塔上限、零消耗七塔合一、多终极塔迁移与城墙失败

- 用户已在 Plan 阶段确认并切换 Act：每玩家最多7座未转职基础箭塔；每玩家每条转职路线最多5座，并使用玩家级预占阻止并发第6座；转职完成释放基础塔名额，死亡/取消释放计数或预占。
- 七塔合一要求同一玩家七条路线各有一座满级且从未参与过合成的塔；材料塔不销毁、不降级，但成功后永久标记为已参与。每玩家最多5座终极塔，合成资格和技能状态随候选塔及终极塔数量动态刷新。
- 齐天大圣R迁移该玩家全部终极塔并保留相对位置；任一目标footprint非法时整组拒绝，不允许部分移动。
- 失败条件改为任意已完工`wall`被摧毁时以一次性全局闩锁判定全队失败；施工中城墙不触发。移除已完工`main_city`死亡直接失败。
- 配置数值必须先写`data/csv/`再生成；不得直接手改生成Lua。需同步Runtime UI、Ability状态和本地化，并增加玩家隔离、上下限、并发预占、五组合成、材料一次性、多塔原子迁移及城墙失败专项测试。
- 实现完成：建筑数量、路线计数与并发预占统一使用`player_id`；基础箭塔仍读取CSV上限7，路线读取全局CSV上限5。达到路线5座时该玩家所有满级基础塔动态移除对应转职Ability，跌回4座后恢复，服务端仍原子拒绝第6座。
- 合成完成：CSV新增每玩家终极塔上限5并生成Lua；七路线各稳定选择一座同玩家满级未参与塔，创建终极塔后原子永久标记七座材料，材料不销毁、不降级、不释放人口。失败删除新终极塔/代理且不标记材料；已参与塔不再获得合成Ability。
- 多终极塔完成：融合服务保存玩家终极塔集合；齐天大圣R整组保留相对位置迁移。迁移前完成区域、边界、地形、树木、其他单位、Grid占用和组内footprint重叠校验，任一失败时零移动；只忽略同组终极塔/代理和当前锚点。
- 失败条件完成：已完工`wall`死亡经全局一次性闩锁设置坏人方胜利；施工中城墙和已完工`main_city`死亡均不直接失败。施工失败不会提前消耗城墙整局一次性建造状态。
- UI与本地化完成：Runtime发布玩家级路线计数、七路线未参与候选数、终极塔当前数量/上限和材料不消耗规则；中英文六份Ability本地化镜像已同步。
- 自动验证通过：`PLAYER_TOWER_FUSION_RULES_LUA51_PASS`、`PLAYER_TOWER_FUSION_CONTRACT_PASS`、目标Lua 5.1语法（`building_system.lua`按既有BOM去除后检查）、`addon_game_mode.lua`语法、融合CSV/生成Lua逐字节一致、严格UTF-8/本地化BOM及限定`git diff --check`。覆盖玩家隔离、7/8基础塔、4/5/6路线塔、并发预占、五轮合成、材料一次性、终极塔上限回收、多塔原子迁移和城墙失败闩锁。
- 尚未Workshop Tools实机验收：需完全冷启动，双玩家分别验证数量隔离/Ability动态恢复，连续五轮合成的实体与攻击流，齐天大圣R多塔往返/非法落点，以及施工中城墙、主城和已完工城墙三类死亡结果。自动测试不能称为实机验证。
- 恢复冲突：此前文件顶部仍记录第7塔路线任务；本轮以用户当前批准的插入任务为最高优先级，旧记录保留为历史上下文但不作为当前实施目标。

## 当前实施任务（2026-08-12）：凤凰终级激光视觉修复与冰塔技能调整

- 2026-08-12第二次实机反馈：Phoenix Sun Ray方案仍有问题，用户要求彻底停用凤凰激光资源，Phoenix直接沿用已成功的普通激光塔Tinker Laser；寒冰尖塔现有冰锥只有落地爆炸，需要补充清晰的空中下落过程。
- 用户实机确认防空塔LV1-LV10天怒至宝第二分支及其余阶段内容全部通过；当前仅剩终级Phoenix红色缺材质和Solar Forge Sun Ray表现错误。
- Phoenix保留现有塔模型组件，但彻底停用Solar Forge Sun Ray；专用配置与普通五级激光一致，使用Tinker Laser和segmented短段重播，Gameplay数值不变。
- 冰霜攻击LV1-LV5保留主目标原生普通攻击全额伤害，半径内其他目标只承受该次攻击50%的物理范围伤害；范围内所有目标继续减速25%持续2秒。
- 寒冰尖塔LV1-LV5保留10/12/14/16/16%触发率、每波触发时攻击力50%的物理伤害和25%减速，统一为300码、每1秒一波、共4波；每波先从落点上方700单位生成Frost Avalanche冰片并在0.35秒内下落，落地后播放爆炸并结算伤害。
- 权威数值与资源配置继续来自`data/csv/`；自动验证不等于Workshop Tools实机验收，最终需冷启动确认Phoenix使用Tinker Laser表现正常，以及寒冰尖塔落冰观感。
- 实现完成：Phoenix专用激光回退为`particles/units/heroes/hero_tinker/tinker_laser.vpcf`和`segmented`模式，起止高度、刷新和保留时长均与`laser_lv05:default`一致；不再进入Sun Ray continuous分支。
- 冰霜攻击五级均从CSV读取`damage_multiplier=0.5`，只对非主目标提交范围物理伤害，主目标不重复结算；寒冰尖塔五级统一300码、4秒、1秒间隔、每波50%攻击力，去除持续雪场。下落段从CSV读取`maiden_freezing_field_snow_arcana1_shard.vpcf`，落地段继续读取Frost Avalanche explosion。
- 自动验证通过：本轮两个CSV定向生成、`FROST_TOWER_ROUTE_PASS`（含4个高空冰片、逐步下落、落地后4波伤害与爆炸）、`PHOENIX_LASER_CONTRACT_PASS`、`ASSET_BUNDLE_CONFIG_PASS`、下落冰片VPK路径、相关Lua 5.1语法及限定`git diff --check`。尚需Workshop Tools冷启动确认下落冰片尺寸、朝向和可见度。

## 当前实施任务（2026-08-12）：闪电塔双倍攻速伤害实验与攻击动画同步

- 用户要求为伤害猜想进行临时实验：闪电路线全部20级的基础攻速由每秒1次提高为每秒2次。
- 每次持有 `lightning_strike_` 的塔开始普通攻击时，主动播放2倍速 `ACT_DOTA_ATTACK`，使闪电链释放节奏与攻击频率同步；不改变0.1秒连锁跳跃间隔、伤害倍率和触发链。
- 权威数值必须来自 `data/csv/建筑与工人系统/防御塔/tower_class_lightning.csv` 并重新生成 Lua。该CSV当前存在本轮之前的乱码修改，用户已明确选择恢复正常文本后实施全部20级改动。
- 自动验收应覆盖20行CSV/生成Lua攻速均为2、闪电攻击动画倍率为2、非闪电塔不进入该动画分支、现有闪电伤害与触发链专项测试、Lua 5.1语法和限定差异检查；Workshop Tools负责最终视觉节奏验收。
- 实现完成：闪电路线CSV已从错误的GB18030工作树编码无损转换回UTF-8 BOM，20行中文与资源字段完整保留；全部等级基础攻速设为2并已重新生成配置。持有`lightning_strike_`的塔在攻击开始时调用`StartGestureWithPlaybackRate(ACT_DOTA_ATTACK, 2)`，API不可用时回退普通`StartGesture`；非闪电死亡塔仍走原动画分支。
- 自动验证通过：84模块配置生成、`TOWER_LIGHTNING_VISUAL_PASS`、`LIGHTNING_FROST_PHYSICAL_CONTRACT_PASS`、CSV与生成Lua各20行攻速精确为2、CSV UTF-8 BOM与中文名称检查、两个目标Lua 5.1语法及限定`git diff --check`。尚未进行Workshop Tools实机动画节奏验收。

## 当前实施任务（2026-08-11）：闪电/寒冰塔技能恢复物理伤害并保留收窄后的闪电触发链

- 用户要求回滚魔法伤害版本：闪电打击和冰霜攻击恢复原生物理主攻击，后续跳跃、冰霜范围伤害、暴风雪、落雷和电圈均恢复物理伤害并进入护甲结算。
- 闪电塔落雷只由闪电打击造成击杀时触发；普通攻击、落雷和电圈击杀不得触发新的落雷。
- 电圈只由落雷命中事件触发；闪电打击直接命中、电圈自身伤害和其他来源不得触发电圈，电圈不得递归。
- 伤害来源必须显式保留在本次技能伤害事务边界内，不能继续按“当前塔是 attacker”推断落雷触发来源。
- 权威技能说明继续来自 `data/csv/建筑与工人系统/防御塔/tower_skill_definitions.csv`，生成 Lua、Tooltip 和本地化镜像必须由现有生成链同步产出。
- 自动验收覆盖原生主攻击未被抑制、相关脚本伤害使用 `DAMAGE_TYPE_PHYSICAL`、闪电击杀/落雷/电圈触发边界、配置生成一致性、Lua 5.1 语法、严格编码和限定 `git diff --check`；Workshop Tools 冷启动仍是最终护甲实机验收。
- 实现完成：Modifier 不再抑制闪电打击/冰霜攻击的引擎原生攻击，闪电首目标不再提交额外脚本伤害；连锁跳跃、冰霜范围、暴风雪、落雷和电圈均通过物理伤害结算。闪电打击主目标或跳跃致死后仍直接启动一次落雷，旧的全局 `OnDeath` 落雷入口保持移除。
- 电圈入口继续硬校验 `source == "lightning_storm"`；闪电打击不发布 `TOWER_LIGHTNING_HIT`，生产 Modifier 仅剩落雷发布点，电圈伤害不发布命中事件，因此不递归。
- 权威塔技能 CSV、生成技能 Lua、Tooltip CSV/Lua及六份中英本地化镜像已同步为物理伤害文案；专项生产契约同步改为验证物理伤害。
- 尚未进行 Workshop Tools 实机验收。需用不同物理护甲敌人确认主目标及技能伤害随护甲变化、闪电主目标没有双伤、闪电跳跃击杀触发一次落雷、普通攻击/落雷/电圈击杀不触发落雷，以及仅落雷命中能触发电圈。

## 当前实施任务（2026-08-11）：第7塔路线由魔法塔重构为防空塔

- 用户已批准实施：将当前第7路线“魔法塔→大魔法塔→魔法至尊”重构为“防空塔→防空火炮→空域霸主”，基础数值、升级费用、人口占用与阶段等级沿用当前CSV。
- 飞行身份严格读取怪物权威CSV投影：`movement_type == "flying"`或`movement_type_override == "flying"`任一成立。第7路线自动索敌、手动攻击、竞态伤害兜底及七塔合一第7路都只能攻击飞行单位。
- 防空炮等级1至5每轮对同一目标发射`4/5/6/7/7`枚飞弹，每枚为独立普通攻击并享受对空伤害+90%；塔面板攻速保持1。目标死亡后本轮剩余飞弹停止且不转射，随后重新索敌开启下一轮；额外普通攻击必须隔离递归。
- 防空火炮等级1至5的每枚真实命中独立以`10%/12%/14%/16%/16%`概率眩晕飞行单位3秒。
- 空域霸主半径500：范围内敌方单位最终承伤提高20%，其中飞行单位攻击速度额外降低20%；同名效果不叠加，离开范围恢复，攻速变化通过现有`UNIT_COMBAT_STATS_CHANGED`链同步到敌方选中单位UI。
- 策划数值只写入`data/csv/`权威源；生成Lua不得直接编辑。实现后新增专项Lua/契约测试，并执行配置生成一致性、Lua 5.1语法、严格编码及限定`git diff --check`。自动测试不等于Workshop Tools实机验收。
- 实现与自动验证完成：防空路线、技能、Tooltip、本地化、飞行索敌/手动命令/伤害竞态兜底、七塔合一第7路、额外普通攻击序列、每弹眩晕和空域光环均已接入。正式波次、普通遭遇及挑战会话三条生成边界都会保存CSV飞行身份；挑战会话同时按该身份设置引擎移动能力。
- `ANTI_AIR_TOWER_LUA51_PASS`覆盖`0.1s`飞弹调度、`4`枚总数、递归隔离、目标死亡停止、每弹独立眩晕及双光环；`ANTI_AIR_DAMAGE_FILTER_LUA51_PASS`证明最终加法伤害项交换顺序结果不变，并锁定空域`1.2`在Boss与其他最终倍率之后相乘。
- 通过：`ANTI_AIR_TOWER_CONTRACT_PASS`、配置生成84模块成功、目标Lua 5.1语法、`BUFF_MANAGER_NONSTACKING_PASS`、`WAVE_FLYING_COLLISION_PASS`、`WAVE_SPECIAL_MIXED_WAVES_PASS`、严格UTF-8及限定`git diff --check`。既有`test_tower_class_fusion_counts.lua`在加载带BOM的`building_system.lua`时被Lua 5.1解析器阻断，未进入业务断言；本轮未改该既有文件。尚未进行Workshop Tools实机验收。
- 2026-08-11紧急启动修复：防空改动曾删除`tower_magic_supreme_system`的`require`与`init()`，但`M.precache()`仍首先调用其`precache(context)`，导致预载入口在同步加载主城和`npc_dota_hero_monkey_king`前中断；表现为主城预建筑error模型，以及猴王本体、武器、头发、护甲和肩部资源未加载。现已恢复模块绑定和初始化，并新增`ADDON_PRECACHE_CONTRACT_PASS`锁定模块生命周期及主城/猴王同步预载项；`addon_game_mode.lua`通过Lua 5.1语法检查。仍需完全停止旧会话后冷启动Workshop Tools确认引擎资源恢复，热重载不能证明启动预载已重跑。

## 已完成实现（2026-08-11）：修理工自杀返还占用人口

- 用户批准为普通和高级修理工增加同一个即时无目标自杀技能；点击后立即死亡，不弹确认、不吟唱。
- 权威训练数据继续来自`data/csv/建筑与工人系统/training_definitions.csv`。两级修理工各占用1人口，并由CSV声明主动技能。
- 技能只负责杀死当前施法修理工；`worker_system.lua`现有工人死亡链负责恰好释放该实体记录的`population_cost`。示例验收为`12/13 -> 11/13`。
- 自杀不调用资源增加或训练失败退款入口，已消耗金币和木材均不返还；累计训练次数、阶段解锁状态也不倒退。
- 实现完成：新增CSV驱动的`ability_repairer_suicide`，训练创建逻辑按`active_skill_ids`挂载并升至1级；技能只对已标记修理工执行`ForceKill(false)`，人口仍由既有死亡链恰好释放一次，技能代码不调用人口或资源变更入口。
- 自动验证完成：真实技能行为桩覆盖普通/高级两级技能挂载、即时死亡、`12/13 -> 11/13`、重复死亡不重复释放、木材金币不变和训练进度不倒退；专项契约、修理工百分比/右键回归、工人训练回归、目标Lua 5.1语法、配置生成与CheckOnly、严格编码、Python编译和限定`git diff --check`通过。尚未进行Workshop Tools实机验收；需完全停止当前测试会话并重新Run后分别训练两级修理工点击技能确认。
- 2026-08-11实机反馈修复：自毁现在经`WORKER_DISMISS_REQUEST`同步执行死亡与幂等登记清理，人口不再依赖死亡实体句柄仍有效；引擎死亡桥同时传递`victim_entindex`作为自然死亡兜底。修理工`max_count`改为限制当前存活数量，历史训练总数继续保留但不再永久禁用按钮；高级修理工从`2/2`死亡一名后恢复为`1/2`并可重新支付1000金币、1人口训练。

## 当前插入任务（2026-08-11）：闪电魔塔击杀风暴即时伤害与纯视觉雷柱

- 用户最终确认：任意归因于当前闪电塔的伤害造成击杀时，以死亡位置为圆心立即查询一次500范围敌人，按LV1至LV5分别造成触发时塔攻击快照110%/120%/130%/140%/150%的物理伤害。每个范围目标只受伤一次并只发布一次`TOWER_LIGHTNING_HIT`；风暴伤害保持原塔归因，可继续触发连锁风暴。
- 已完成生产实现：权威`tower_skill_definitions.csv`把五级`damage_timing`改为`instant`、倍率改为1.1至1.5，只保留`strike_count=5/6/7/8/9`作为视觉次数，删除`damage_increment_per_strike`和`damage_multiplier_cap`。`modifier_tower_attack_effects.lua`在触发栈内完成单次范围查询、伤害和命中事件；后续调度回调只在一秒内创建随机雷柱粒子，不查询敌人、不调用伤害服务、不发布命中事件。
- 独立“雷电扩散LV1”生产逻辑未修改：每个原始雷电命中事件独立30%判定，对目标周围200范围其他敌人造成该次伤害200%，扩散伤害标记为secondary且不重新发布`TOWER_LIGHTNING_HIT`，因此不递归。
- 已同步：定向生成`tower_skill_definitions.lua`，统一生成Tooltip CSV/Lua，六份中英本地化镜像同步五级即时倍率和纯视觉雷柱说明；塔配置README明确`strike_count`只表示视觉次数。技能ID和最高等级未变化，Ability KV无需修改。
- 自动验证通过：`LIGHTNING_TOWER_KILL_TRIGGER_LUA51_PASS/CONTRACT_PASS`，覆盖五级倍率、触发栈内即时伤害、单次范围查询、双目标各一次伤害/事件、5至9道视觉、视觉零查询/零伤害/零事件、原塔归因、连锁风暴，以及扩散30%/200%/排除原目标/非递归；怪物War3护甲、终极塔和本地化回归通过。5个目标Lua语法、塔技能和Tooltip生成逐字节一致、CSV 19列结构、配置CheckOnly、15个目标文件严格UTF-8/BOM及限定diff通过。
- 尚需Workshop Tools完全冷启动：确认LV1至LV5击杀瞬间立即跳血一次，实际倍率和物理护甲链正确；一秒内仅显示5至9道随机雷柱且不再追加伤害/扩散判定；多个目标各结算一次；风暴击杀继续连锁；独立雷电扩散保持每目标一次30%判定。自动测试不能替代引擎实机验收。

## 当前插入任务（2026-08-11）：Ability Tooltip 几何诊断作用域异常

- Workshop Tools 实机日志确认 `ability_tooltip.js:997` 在 `scheduleExternalGeometryDiagnostic(binding)` 的异步回调中读取未定义的 `active.engineSlot`，触发 `Uncaught ReferenceError: active is not defined` 并中断当次 Panorama 脚本回调。
- 权威 Tooltip CSV `data/csv/公共规则/tooltip_definitions.csv` 内容正常；问题属于 Panorama 客户端代码作用域错误，不修改 CSV、生成 Lua 或 Tooltip 业务数据。
- 已确认当前 content 源码与 game 编译产物均包含错误引用。最小修复为改用当前函数参数 `binding.engineSlot`，随后强制重编译 `ability_tooltip.js` 并执行源码、产物、UTF-8 和限定差异检查。
- 现有 `test_memory_lifecycle_contract.ps1` 当前先失败于无关的 `SURVIVAL_UI_CONTEXT_GUARD_MISSING`，本轮必须单独报告该既有阻断，不能把专项字符串检查冒充完整生命周期契约通过。
- 已完成：`content/.../ability_tooltip.js:997` 已改为 `binding.engineSlot`，Resource Compiler 强制编译结果为 `OK: 1 compiled, 0 failed, 0 skipped`；源码和编译产物目标函数体作用域契约、`ABILITY_INPUT_LIFECYCLE_CONTRACT_PASS`、严格 UTF-8 和限定 `git diff --check` 通过。仍需完全停止并重新 Run Workshop Tools，确认冷启动日志不再出现 `active is not defined`。

## 当前插入任务（2026-08-11）：逐波模型资源会话、W12预载修复与临时兼容TODO

- 用户确认最终目标是每个正式波次拥有独立的最终模型配置，不依赖前一波已经加载的模型。当前`normal_flying_model_path`把多波普通飞行怪统一映射到Visage，只是模型尚未逐波定稿期间的临时兼容层，必须标记`TODO(FINAL_WAVE_MODELS)`；待逐波模型表完整后删除该字段、共享模型租约兼容和相关分支。
- 已定位W12错误的确定根因：正式预载和出生使用`model_path_for()`，但`monster<N>`开发跳波仍直接读取`definition.model_path`。因此`monster12`预载Dragon Knight/旧飞行基础模型，出生却`SetModel()`为Visage，触发`requested is not loaded and may have been deleted`。修复必须让正式预载、开发预载和出生设置消费同一实际模型解析。
- 资源生命周期采用波次会话和Lua租约：每波独立登记planned/pending/alive及实际模型集合；生成完成且该会话怪物全部死亡后调用统一release边界，清除本波Lua引用、回调身份、附件/粒子/实体生命周期状态。波次重叠时按会话身份结算，禁止只看全局`current_wave`提前释放其他波。
- `release`不等于Source 2强卸载。Workshop Lua当前没有公开、安全的`UnloadModel/UnloadResource`；现有`asset_preload.retire()`只会把Lua状态永久置为`RETIRED`并阻止以后重载，不能作为波次delete。实现必须标记`TODO(SOURCE2_MODEL_UNLOAD)`，未来只有在Valve提供安全卸载API或项目迁移到可卸载独立资源包后才能接入真正模型卸载。
- dev模式继续清理怪物实体、附件、粒子、任务和会话对象，但不释放模型租约、不调用`retire()`；反复`monster<N>`可复用已加载资源。正式波次在倒计时开始即独立请求下一波资源，并在配置的4秒窗口幂等复核；urgent波次请求不得被塔/城墙后台串行流阻塞，且不得改变倒计时、数量、顺序或生成间隔。
- 实现与自动验证完成：`monster12`开发预载现使用与出生一致的Visage解析；正式波次拥有独立session/共享路径租约，pending或alive非零时拒绝release，重叠波只释放已完成session，dev释放session身份但保留resident模型租约。urgent请求可与后台流并行；Visage资产权威`first_use_wave`由14更正为8并定向生成Lua。
- 通过：`WAVE_MODEL_RESOURCE_LIFECYCLE_PASS`、`ASSET_PRELOAD_URGENT_PARALLEL_PASS`、`WAVE_MODEL_RESOURCE_LIFECYCLE_CONTRACT_PASS`、`WAVE_MONSTER_VISUAL_INTEGRATION_PASS`、`ASSET_PRELOAD_GRADUAL_PASS`、`DEV_ASSET_PRELOAD_PASS`、`WAVE_EARLY_FINAL_PASS`、`WAVE_SPECIAL_MIXED_WAVES_PASS`、`WAVE_SPAWN_SEQUENCE_PASS`、`WAVE_FLYING_COLLISION_PASS`、`WAVE_MONSTER_MODEL_RESOURCES_PASS`、资产生成逐字节一致、配置CheckOnly、目标Lua/Luac 5.4.5语法、Python编译和限定`git diff --check`。本机无Lua 5.1，不宣称Lua 5.1验证。
- 既有非本轮失败：`test_wave_difficulty_builder.lua`仍要求旧N1最终波批次数；`test_wave_difficulty_selection.lua`仍把当前已启用N3当作非法难度；`test_asset_preload_service.lua`仍硬编码旧后台流总数26而当前生产为9。本轮未修改这些过时业务基线。用户2026-08-11后续观察中暂未再发现加载问题，记为阶段性有效而非永久保证；未来新增逐波模型后仍需冷启动分别执行`monster<N>`和正式目标波，核对首只怪及`phase=countdown_start`/`phase=lead_review`日志。完整复发排查经验见`WAVE_MODEL_LOADING_TROUBLESHOOTING.md`。

## 已完成插入任务（2026-08-11）：正式波次数量、混合顺序、飞行模型与Hull修正

- 根因确认并修复：N1-N5 W11均同时保留旧59只成员和新59只混合成员，导致运行时普通怪实际为118只。权威CSV现删除旧重复行，全表`wave_id`唯一；五个难度W11均严格为`beast_green_large ×10 + skeleton_bone ×30 + flying_red_gargoyle ×19 = 59`，不含领头怪和进攻Boss。
- `tools/build_configs.py`新增生成边界失败关闭：拒绝重复`wave_id`，并要求N1-N5中所有实际存在的W11-W30波次普通怪严格为59。N1与N3-N5导入器在复用现有模板前按`wave_id`保留最终定义，防止再次叠加旧数据。
- 混合出怪以移动类别建立独立轮转队列，正式规则为每2只地面后1只飞行；两种地面原型表现为`地A → 地B → 飞`，一种地面原型表现为`地 → 地 → 飞`，任一类别耗尽后确定性输出剩余成员。五个难度W11/W13/W24共15个真实混合波已逐位置验证。
- `monster_archetypes.csv`新增`normal_flying_model_path`。只有正式波次`normal + flying`成员使用该专用字段，当前统一为Visage飞行模型；预载与出生模型使用同一解析。飞行领头怪、精英、Boss、十罪和挑战怪仍使用共享原`model_path`，未扩大修改范围。
- 正式普通飞行怪基础Hull改为10并保留单位碰撞；飞行领头怪、精英和Boss继续Hull 0与无单位碰撞。`scalemonster`以基础Hull非累计缩放，专项覆盖`10×4=40`后改为`10×0.5=5`。
- 自动验证通过：`WAVE_SPECIAL_MIXED_WAVES_PASS`、`WAVE_SPAWN_SEQUENCE_PASS mixed_waves=25 special_mixed_waves=15`、`WAVE_FLYING_COLLISION_PASS`、`WAVE_MONSTER_MODEL_RESOURCES_PASS`、`WAVE_GENERATED_BYTE_MATCH_PASS count=2`、严格UTF-8、Python编译、Lua/Luac 5.4.5语法及限定`git diff --check`。当前机器没有可执行Lua 5.1，因此不宣称本轮Lua 5.1验证。
- 尚待Workshop Tools完全冷启动实测：跳到W11核对实际59只构成和`2地+1飞`顺序，确认普通飞行怪显示Visage模型、不会相互完全叠加，并观察Hull 10及`scalemonster`倍率下的真实拥挤/阻挡。自动验证不能记录为引擎实机验收。

## 当前插入任务（2026-08-10）：本地化缺失与重复 token 告警清理

- 用户提供冷启动日志：`npc_survival_repairer`、`npc_survival_builder_proxy` 缺失精确本地化 token；挑战通用奖励说明、`building_gold_mine`和`building_hero_altar`存在大小写不敏感同名但文本不同的重复定义。
- 已完成最小范围修复：单位显示名先补入`unit_display_names.csv`并定向生成；六份game本地化镜像和两份content Panorama源已同步；历史大小写别名继续保留但值已统一；中英文建筑占位值分别改为可显示名称。未修改Lua运行逻辑、启动规则、modifier bootstrap或fingerprint日志。
- 性能边界：这些告警主要发生在本地化加载/热重载阶段，不是逐帧热路径；本任务目标是消除重复日志、避免覆盖顺序导致错误显示，并防止缺失token被重复请求，不能把静态清理夸大为已证明的帧率提升。
- 自动验证结果：`LOCALIZATION_TOKEN_INTEGRITY_CONTRACT_PASS`、八文件大小写不敏感冲突扫描、结构检查、定向生成逐字节一致、生成Lua 5.1语法、严格UTF-8/BOM和Builder替换回归通过。既有免费英雄替换契约在无关的`FREE_HERO_STRENGTH_INVALID_hero_shadow_fiend`断言失败；未修改英雄CSV或其生成配置。
- 剩余验证：必须完全退出并冷启动Workshop Tools，确认日志中的`FindSafe`缺失token与`Ignoring duplicate token`告警不再出现；自动检查不能替代引擎本地化装载验证。

## 当前插入任务（2026-08-10）：英雄移动白名单与建筑禁建黑名单

- 用户当前消息已明确批准从Plan切换到Act并实施本任务；该指令优先于本文后部仍记录的“多人阶段1等待验收”。多人任务保持原状态暂停，本轮只修改区域、目的地、Grid、传送、命令过滤和英雄边界守卫直接相关内容。
- 已批准模型：`build_forbidden_regions.csv`使用`region_type=hero_movable|building_forbidden`，支持`circle`和按边界顺序定义的凸`quadrilateral`。召唤祭坛产生的正式战斗英雄受移动白名单约束；Builder、伐木工、修理工、建筑、怪物和隐藏占位英雄不受英雄白名单约束。
- 英雄普通移动/攻击移动的非法目标在Order Filter提前拒绝；追击、击退和脚本位移等运行时越界由生命周期守卫停止动作并拉回最后合法位置。普通寻路不承诺整条路径都位于白名单内。
- 空区域配置必须保持游戏可玩：没有启用的`hero_movable`时白名单视为未启用，英雄沿用既有导航，建筑沿用既有Grid边界、地形、坡度、树木、单位、占用和所有权校验；不得猜测坐标或伪造超大区域。
- 一旦存在有效`hero_movable`，建筑footprint必须完整位于其区域联集内；`building_forbidden`始终独立生效，与白名单是否启用无关。区域策略拒绝时仍必须返回完整footprint cells并全部标红，不能用空`cells`隐藏Grid。
- 工作区已有本任务前置草稿：目的地/Grid/传送相关tracked文件有未提交修改，CSV、生成Lua、区域服务和目的地服务为未跟踪文件。本轮在其基础上审计和完成，不回滚其他既有修改。
- 本机有效工具链已重新探测：Python 3.11.9位于`C:\Users\a\.workbuddy\binaries\python\versions\3.11.9\python.exe`，Lua/Luac 5.1位于`C:\msys64\mingw64\bin`，PowerShell 7.6.4位于`C:\Program Files\PowerShell\7\pwsh.exe`；`.cline/local-toolchain.json`现有路径失效，需同步修正。
- 本轮实现结果：已完成CSV schema、生成、区域几何服务、英雄/建筑策略分离、统一目的地校验、Grid footprint白名单/黑名单、移动/攻击移动Order Filter、英雄生命周期回退、祭坛/挑战/练功房/回城/球状闪电/终极塔锚点接入。`build_forbidden_regions.csv`当前无启用业务行，因此运行时保持旧地图导航与Grid建造规则；后续写入真实`hero_movable`后自动启用严格白名单。
- 本次兼容修复自动验证：区域PowerShell契约、区域Lua 5.1几何/Grid行为、英雄身份/回退/移动过滤、Builder替换与Ability槽位、多人Builder、输入生命周期、祭坛输入、树规则、终极塔数学、相机契约、目标Lua 5.1语法、配置CheckOnly、区域CSV定向生成逐字节一致、生产/测试严格UTF-8、本轮文档新增行无替换字符及限定`git diff --check`通过。既有Builder移速测试仍要求600但当前CSV为500，既有Builder utility契约仍要求Monkey射程1000；两项失败均未修改本任务区域代码或权威数据。
- 剩余验证：需Workshop Tools冷启动确认当前空配置下Grid正常显示、合法地点可建造，区域拒绝时Grid保持显示并标红。Hammer真实边界仍是启用新白名单能力所需的数据，但不再阻断当前地图可玩性。

## 已完成插入任务（2026-08-09）：怪物护甲并发冲突解决

- 用户确认此前“117 War3护甲保持线性投影为39运行时护甲，并在Damage Filter中只补偿War3目标曲线/当前Dota曲线差值”的方案已通过测试验收。本次处理`armor_balance.lua`与当前分支现代非线性映射的stash恢复冲突，以该已验收行为为准，并同步核对波次、挑战、调试怪、科技减甲和UI映射身份，不能只删除冲突标记。
- 已完成兼容合并：保留`from_war3_modern()`、版本化反投影等正交辅助API，但波次、挑战和调试怪继续使用`from_war3()`线性`/3`边界且不写现代映射身份，117保持39而非约34.32；英雄临时减甲UI继续线性反投影。怪物护甲专项、科技减甲和毒云Lua 5.1行为/契约及目标语法已通过。用户明确确认此前固定样本测试验收通过，未提供精确击杀秒数或日志，因此只记录验收结论，不虚构测量值。

## 已完成插入任务（2026-08-09）：怪物物理伤害按War3目标曲线补偿

- 权威CSV基准为`n1_wave_05_5b`的20000生命/117 War3护甲，以及`arrow_tower_lv05`的401攻击/1次每秒。117继续经既有生成/出生边界`/3`投影为39 Dota运行时护甲；目标承伤倍率为`1/(1+0.02*117)=0.299401`，7塔理论击杀时间约23.79秒。
- 已纠正前一轮错误假设：当前Dota正护甲曲线不是旧式`1/(1+0.06*A)`。39运行时护甲的当前原生承伤倍率约0.2684，单靠引擎约需26.55秒。`monster_war3_armor_damage_enabled=1`现只对明确标记的项目怪物物理伤害应用“War3目标倍率/当前Dota倍率”的预护甲补偿，随后仍由引擎正常结算护甲；117样本下401先补偿为约447.32，原生护甲后约120.06。不开忽略护甲flag、不递归`ApplyDamage`，避免旧实现先手动减甲再被引擎二次减伤。
- 为保证固定基准中的“7塔每秒各命中1次”成立，`global_rules.csv.base_arrow_tower_cannot_miss=1`通过现有塔公共Modifier赋予未转职基础箭塔必中；严格以`survival_building_id=arrow_tower`且`tower_class`为空限制范围，七条转职路线、终极塔代理、英雄、工人和其他单位不受影响。伤害、攻速、护甲和弹道数值未改。
- 复用`global_rules.csv.runtime_detailed_diagnostics`增加默认关闭的限量诊断：`MONSTER_PHYSICAL_DAMAGE_FILTER`记录进入原生护甲阶段前的伤害、flags、运行时护甲、生命和Filter倍率；`TOWER_ATTACK_RESULT`分别累计每座塔前20次landed/failed。诊断不参与伤害或命中计算。
- 自动验证通过：`MONSTER_WAR3_ARMOR_DAMAGE_LUA51_PASS/CONTRACT_PASS`、117护甲固定数学基准、开关关闭/非怪物/非物理/非正护甲边界、基础塔必中范围、科技减甲、毒云、树伤害、塔射程/弹速、箭塔成本与融合回归，以及目标Lua 5.1语法。用户已明确确认固定样本测试验收通过；未提供精确击杀秒数或日志。项目CSV最高存在4990 War3护甲，极高护甲下的引擎上限行为仍需后续独立抽样，固定样本验收不能替代该边界验证。
## 当前紧急修复（2026-08-10）：N2-N5 W11错误飞行怪恢复为地面怪

- 用户实机反馈第十一关模型错误，怪物表现为飞行单位：可穿地形并相互叠加。审计确认运行时按成员逐只设置移动能力，W1-W5视觉覆盖不处理W11；根因是N2-N5 W11残留19只`flying_red_gargoyle`旧成员，而当前N1 W11权威模型只有`beast_green_large`和`skeleton_bone`两种地面怪。
- 权威CSV已将N2-N5 W11普通怪统一为`beast_green_large=15`、`skeleton_bone=44`，删除四条飞行成员及三倍飞行护甲，普通怪总数仍为59；领头怪保持1只且所有运行字段不变。生成Lua已定向同步。
- `import_n3_wave_workbook.py`仅对W11应用批准校正：普通飞行数量强制为0并只使用N1同波`member_role=normal`模板，防止旧工作簿重新生成飞行怪或把领头怪混入普通模板。W12及其他合法飞行波不受影响。
- 自动验证通过：`WAVE_11_GROUND_MONSTERS_PASS`、模型资源检查、生成逐字节一致、配置CheckOnly、生成Lua语法、严格UTF-8/BOM、限定范围与`diff --check`。既有未跟踪`test_wave_monster_visual_integration.lua`在业务断言前失败于旧预载桩缺少`dev_wave_preload_timeout_seconds`，本任务未修改该测试或无关预载逻辑。尚需Workshop Tools完全冷启动后跳到W11，确认模型、地形阻挡、单位碰撞和59只数量。

## 当前插入任务（2026-08-09）：怪物尸体生命周期优化

- 用户需求：怪物死亡完成业务结算后，不再让大量尸体长期留在地表；采用短暂保留、平滑下沉、`AddNoDraw()`隐藏并安全移除实体的方式，降低高密度波次中的模型、阴影和实体管理开销。
- 实现边界：先审计CSV权威配置、引擎死亡事件、波次/挑战奖励与计数调用链；仅清理明确属于项目怪物的死亡实体，不影响英雄、工人、建筑、召唤物、掉落物或死亡结算。下沉/清理时序必须数据驱动，任务可取消且按单位生命周期去重。
- 生产实现：新增`monster_corpse_lifecycle_service`。波次怪、挑战/转生怪和`addmonster`调试怪以显式单位身份加入清理链；`ENGINE_ENTITY_KILLED`同步业务结算完成后，尸体按CSV保留0.6秒、由单个共享0.05秒任务在0.8秒内下沉160码，随后`AddNoDraw()`并延迟0.05秒`UTIL_Remove()`。强制波次清场继续立即删除，英雄、工人、建筑、召唤物、训练目标和掉落物不受影响；状态以单位对象为生命周期身份，不永久保存可复用entindex。
- 日志与本地化：`global_rules.csv.runtime_detailed_diagnostics=0`默认关闭防御塔成功效果明细及两类英雄攻击追踪日志，塔日志在开关关闭时连`string.format()`也不执行；错误、施法请求、DamageFilter限次诊断和低频内存聚合保留。四个Panorama本地化helper按HUD context缓存最多256个token，缺失token同样缓存为空，避免持续重复请求；Tooltip SHOW/RECOVERY等详细日志及背包恢复日志仅在`SurvivalTooltipDetailedDiagnostics === true`时输出。
- 自动验证：`MONSTER_CORPSE_LIFECYCLE_LUA51_PASS`、`MONSTER_CORPSE_LIFECYCLE_CONTRACT_PASS`、`PERFORMANCE_LOG_LOCALIZATION_CONTRACT_PASS`、`GLOBAL_RULES_GENERATED_MATCH_PASS`、全项目356个Lua文件的Lua 5.1语法检查、18个目标文件严格UTF-8；`SESSION_LOG.md`历史3个替换字符数量保持不变且本轮新增段为0、配置`CheckOnly`及game/content限定`diff --check`通过。4份Panorama JS分别强制编译为`1 compiled, 0 failed, 0 skipped`。当前工作区没有文档历史提到的塔技能Lua测试文件，相关测试枚举为0，未将其误报为回归通过。
- 尚需Workshop Tools冷启动实测：批量击杀波次怪、挑战怪和`addmonster`，确认约0.6秒后开始下沉、约1.45秒后实体消失且奖励/掉落/击杀成长/波次计数不回归；确认英雄、工人、建筑和掉落物不会被清理；反复悬停技能并观察控制台不再持续输出Tooltip详细日志或localization错误；对比相同刷怪场景的尸体数量、控制台行数、服务器帧时间与客户端帧率。未经实机结果不能称为性能改善已验收。

## 当前插入任务（2026-08-09）：训练、建造与升级同步结果事务

- 需求：工人训练、建筑提交、普通/批量升级必须同步返回结构化结果；请求缺失或失败时不得保留Ability冷却。排队建造后发生的异步失败必须恰好回滚一次冷却，并在已扣费时完整退还资源/人口。修理工不能继续按同`training_id`活体数量永久卡在第一阶段，必须按权威CSV顺序推进；最终阶段完成后保留完成态并拒绝继续训练，伐木工最终无限阶段保持不变。
- 生产实现：`WORKER_TRAIN_REQUEST`、`BUILD_REQUEST`、`BUILDING_UPGRADE_REQUEST`和`TOWER_CLASS_REQUEST`全部改为`handle_request`，调用者改用`request`。升级handler继续写`payload.result`并同时返回结果，批量升级以返回值优先、`payload.result`兼容。原生训练/建造/升级Ability在无结果或`ok~=true`时`EndCooldown()`；Panorama直接提交仅在同步受理后启动冷却。
- 修理工进度：`worker_training_progress.create()`按prefix泛化，修理工与伐木工拥有独立按team状态和reset生命周期。修理工自动请求从CSV当前tier解析；LV1成功创建5次后进入LV2，LV2成功2次后最终快照保持`completed=1`并在扣费前拒绝。活体死亡不倒退训练历史；单位创建失败在资源/人口退款后不记录成功。伐木工CSV最终`train_lumberjack_08.max_count=-1`仍不完成且可无限累计。
- 建造事务：同步提交只表示移动任务已受理。任务保存`source_ability`；Builder死亡、二次位置失效、移动命令/实体创建失败、施工中建筑死亡等失败路径由`core/action_cooldown_rollback.once()`按task身份幂等回滚。实体已创建后的施工失败退木材、金币和人口；成功完成后清除退款与冷却上下文。
- 自动验证通过：`ACTION_COOLDOWN_ROLLBACK_LUA51_PASS`、`WORKER_TRAINING_PROGRESS_LUA51_PASS`、`SYNCHRONOUS_ABILITY_RESULTS_LUA51_PASS`、`REPAIR_WORKER_PERCENTAGE_MATH_OK/CONTRACT_OK`、`SYNCHRONOUS_ACTION_CONTRACT_PASS`、目标`LUAC51_PASS`、`TRAINING_CSV_GENERATED_FIELDS_PASS`、严格UTF-8、配置`CheckOnly`和限定`DIFF_CHECK_PASS`。`building_system.lua`保留项目既有UTF-8 BOM，语法检查使用仅验证用临时无BOM副本，没有改写生产编码。
- 尚需Workshop Tools冷启动实测：修理工连续训练5+2次的模型/数值/最终拒绝；资源不足和实体创建失败不消耗冷却且退款；Builder移动途中死亡、位置失效、施工中建筑死亡只回滚一次冷却并完整退款；普通升级、批量升级和箭塔转职失败不保留冷却。未经实机结果不能记录为用户验收。

## 已完成当前任务（2026-08-09）：统一N2–N5 W30普通怪为59只

- 用户明确稳定节奏：所有难度W1–W10保留原始普通怪数量；从W11起，每个已存在波次固定59只普通怪。N1截止W25，N2–N5截止W30；59只不包含`wave_leader`精英和`assault_boss`。
- 权威CSV与生成Lua审计确认：N2–N5 W11–W29均已是59只，只有四个难度的W30仍各为9只普通怪。四个W30都只有一个普通怪种`flying_red_gargoyle`，因此只需把对应普通怪行从9改为59，无比例取整歧义。
- 批准修改边界：只修改`n2_wave_30_30n1`、`n3_wave_30_30n1`、`n4_wave_30_30n1`、`n5_wave_30_30n1`的数量和备注，再从CSV定向生成`wave_definitions.lua`。精英、Boss、怪种、属性、顺序和其他难度数据保持不变。
- 验证通过：N1 W11–W25和N2–N5 W11–W30普通怪逐波59；W1–W10相对修改前不变；角色数量不变；Lua 5.1行为/语法、生成逐字节一致、严格UTF-8、CSV列数及限定`git diff --check`通过。旧N1–N5扩展契约仍硬编码修改前普通怪总数202/1270和总计划228/1303，分别失败于`N1_NORMAL_TOTAL_INVALID`、`N2/N3/N4/N5_NORMAL_TOTAL_INVALID`，未修改这些用户已有未跟踪测试文件。
- 尚未执行Workshop Tools实机验证；需要冷启动后确认N2–N5 W30实际生成59只普通飞行怪，以及W30的领头怪和进攻Boss仍各1只。

## 前阶段完成记录（2026-08-09）：N1 W11–W25普通怪同步为59只

- 前一阶段CSV核算确认只有N1 W11–W25普通怪不足59；随后按用户明确的统一节奏补齐N2–N5 W30。N1没有W26–W30；N2–N5 W11–W29原本已经是59，W30由9只普通怪统一调整为59只。
- 同波多种普通怪按修改前`monster_count`比例使用最大余数法确定性分配到总计59只，余数相同按CSV原顺序补齐。只修改31条`member_role=normal`行的数量和备注；怪种、属性、顺序、移动、缩放及其他字段不变。
- `wave_leader`作为精英怪保持N1 W11–W25每波1只；`assault_boss`只在W15/W20/W25各保留1只，其余目标波为0。故普通波计划总数为60，含进攻Boss波计划总数为61。
- 已从权威`data/csv/怪物与波次系统/wave_definitions.csv`定向生成`scripts/vscripts/config/generated/wave_definitions.lua`，没有直接手改生成文件。
- 验证通过：`TARGET_ONLY_DIFF_PASS changed_rows=31`、`N1_W11_W25_COUNT_CONTRACT_PASS`、`N1_W11_W25_LUA51_PASS`、`WAVE_DEFINITIONS_LUAC51_PASS`、`WAVE_DEFINITIONS_GENERATED_MATCH_PASS`、`WAVE_DEFINITIONS_STRICT_UTF8_BOM_PASS`。旧N2/N3扩展测试仍分别失败于任务前已有的领头怪排序断言和`ROLE_ORDER`文本断言，本次未修改无关排序逻辑或旧未跟踪测试。
- 尚未执行Workshop Tools实机验证；需要完全停止并重新Run地图，重点用N1 W11、W13、W16、W18、W24确认多怪种比例和实际生成总数，并确认精英/Boss数量不变。

## 历史任务（2026-08-09）：正式波次资源提前4秒异步预载（首次请求时点已被2026-08-11方案取代）

- 历史实现曾只在目标波倒计时剩余`wave_timing_rules.csv.formal_wave_preload_lead_seconds=4`时首次排队。2026-08-11 W12修复后，目标波在倒计时开始立即首次请求，4秒窗口仅作幂等复核；首波和练功房启动预载继续保留。
- 目标资源从当前难度生成后的波次成员读取`monster_archetypes.csv`模型，再合并目标波视觉CSV解析出的模型、组件模型、粒子和`asset_sounds.csv`实际音效资源；按`resource_type:path`统一去重。当前`asset_sounds.csv`无实际记录，因此未添加虚构音效路径。
- `asset_preload_service`保留主体模型的`PrecacheUnitByNameAsync`异步代理；附件模型、粒子和音效按各自资源路径处理，并在服务内跨正式波次/视觉服务统一去重。敌方`zombie_stream`后台批量流已关闭，塔和城墙`tower_stream/wall_stream`保留。
- `addon_game_mode.precache()`的怪物视觉启动范围收紧到W1；W2-W4练功房模型仍由`asset_catalog.csv`的`initial_required`启动包保留。正式倒计时不读取开发跳波的READY/3秒门禁，出怪数量、顺序和时间不变。
- 新增`test_formal_wave_preload.lua`、`test_formal_wave_preload_contract.ps1`和`test_wave_asset_resource_queue.lua`，覆盖首波保留、4秒触发、目标波隔离、Bundle资源展开、跨调用去重、后台流边界和正式流程不继承调试门禁。
- 自动验证：`FORMAL_WAVE_PRELOAD_CONTRACT_PASS`、`FORMAL_WAVE_PRELOAD_LUA51_PASS`、`WAVE_ASSET_RESOURCE_QUEUE_LUA51_PASS`、`DEV_WAVE_PRELOAD_CONTRACT_PASS`、`WAVE_TIMING_CONTRACT_PASS`、目标生成逐字节一致、目标严格UTF-8、目标Lua 5.1语法和限定`git diff --check`通过。
- 扩展验证中N1-N5旧波次契约仍分别失败于任务前已有的“领头怪必须排第一”断言；本任务未修改`wave_definitions.csv`、`monster_archetypes.csv`或其生成Lua。全项目354个Lua文件中348个直接通过`luac5.1`，6个既有BOM文件去除BOM后临时语法通过，未改写这些无关文件。
- 历史验收日志已由新双阶段日志取代：冷启动应同时观察`phase=countdown_start`和`phase=lead_review`（后者约剩4秒），确认目标波模型/组件/粒子实际显示、首只敌人时刻不变，并观察无敌方后台批量预载。

## 当前插入任务（2026-08-08）：`monster<N>`开发跳波预载窗口

- 用户实机复测确认`monster19`会输出`ready_after_buffer elapsed=3.00`并按时生成，但单位仍显示红色`ERROR`；这证明3秒门禁正常执行，剩余问题不是等待不足。
- 最终根因已由本机当前Dota `pak01_dir.vpk`目录索引确认：旧路径`models/heroes/tiny/tiny.vmdl_c`不存在，而`models/heroes/tiny/tiny_01/tiny_01.vmdl_c`存在。`PrecacheUnitByNameAsync()`对引用无效模型的代理仍可能回调READY，因此`ready_after_buffer`不能证明模型路径有效。
- 已批准边界：仅影响`monster<N>`/`monster <N>`开发跳波；复用现有`asset_preload_service`、`monster_visual_service`与`scheduler`。无论资源是否已就绪都固定等待满3秒渲染缓冲，3秒结束时未就绪或加载失败则失败开放；连续命令只允许最后一次生效，迟到状态不得二次出怪。正常波次倒计时、数量、属性、模型映射和正式出怪时序保持不变。
- 工作区保护：用户确认当前`building_levels.csv`修改与`wall_upgrade.xlsx`删除均为其有意改动，本任务完整保留且不触碰；大量既有未跟踪测试文件同样不清理、不覆盖。
- 生产实现完成：`wave_timing_rules.csv`新增`dev_wave_preload_timeout_seconds=3`并定向生成；`debug_spawn_wave()`现进入`dev_preloading`，按目标波CSV archetype模型去重并通过`asset_preload_service`紧急排队，同时排队波次视觉。原型资源状态只用于3秒结束时诊断；即使全部READY也等待完整3秒，FAILED/RETIRED/模型未注册或超时在缓冲结束后失败开放。独立settled锁、generation token及命名scheduler任务共同防止迟到轮询二次出怪和旧命令覆盖新命令。
- Tiny路径修复从权威CSV落地：`monster_tiny`、`golem_gray_small`、`golem_gray_large`及同样引用旧路径的`rebirth_boss_09`统一改为`models/heroes/tiny/tiny_01/tiny_01.vmdl`，定向重建两个生成Lua并同步`asset_proxy_monster_tiny`。专项契约同时禁止恢复不存在的旧路径；最终自动验证结果见本节后续记录。
- 既有回归未通过且未越界修复：未跟踪`test_wave_timing_contract.ps1`硬编码要求基线`late_interval_seconds=150`，但任务前权威CSV/生成Lua均为90；未跟踪`test_n1_wave_config.lua`仍失败于既有“W5起领头怪必须排首位”断言。本任务未修改这两个业务数据或用户测试。
- 编码修复：本次必须修改的`wave_timing_rules.csv`在Git基线已含真实`U+FFFD`替换字符；已依据可正常读取的生成Lua字段语义恢复该文件4行中文并统一为严格UTF-8，没有改动既有波次计时数值。
- 当前状态：3秒门禁已有用户实机日志证明按时执行；无效Tiny路径修复的专项Lua 5.1行为、PowerShell契约、Lua 5.1语法、VPK索引、定向生成逐字节一致、严格UTF-8和限定`diff --check`均通过。下一步必须完全冷启动Workshop Tools后输入`monster19`，确认Tiny LV1主体正常显示而非红色`ERROR`；再快速连续输入`monster19`、`monster20`确认只出最后一波。

## 当前插入任务（2026-08-08）：Lua高水位与W13-W18客户端闪退调查

- 用户提供`出英雄5秒后闪退.txt`并于2026-08-08批准第二轮最小修复。完整日志约4.62 MB/41789行，共120次JS Exception：119次为`ability_tooltip.js`几何诊断错误引用未定义`active.engineSlot`，1次为`combat_stats.js`无效单位分支调用不存在的`refreshOfficialReturnHomeHotkey`。日志生成于17:05，早于17:20-17:30第一轮生命周期源码和产物，因此不能否定第一轮门禁；但两个错误仍存在于当前源码/编译产物，必须修复。
- 第二轮批准边界：修复两个确定性ReferenceError；把`inventory_tooltip.js`纳入同一generation/context门禁和有界计数；Panorama聚合在启动约1秒、5秒及之后每60秒输出，覆盖短时崩溃；默认关闭Tooltip逐次SHOW/CURSOR/HITBOX等高频长诊断和200次游标探针，只保留错误、必要状态及低频聚合。扩展契约并强制编译四份JS。不修改CSV、波次数量/模型、Lua GC策略或用户既有其他改动。
- 第二轮生产实现完成：几何诊断改用作用域内`binding.engineSlot`；无效单位分支改为已有`refreshOfficialUtilityHotkeys([])`并继续受保护递归。`inventory_tooltip.js`的全部延迟、hover、NetTable和GameEvent入口现验证HUD generation/context，并发布pending/peak/recovery固定计数。聚合新增`startup_1s/startup_5s/periodic_60s`及inventory/游标探针字段；Tooltip详细SHOW/CURSOR/HITBOX/GEOMETRY/MAP/BIND/RECOVERY和背包恢复日志默认关闭，且默认不启动200次游标探针。
- 第二轮自动验证通过：`MEMORY_LIFECYCLE_CONTRACT_PASS`、`ABILITY_INPUT_LIFECYCLE_CONTRACT_PASS`、`ABILITY_UTILITY_ORDER_CONTRACT_PASS`、`SCHEDULER_DIAGNOSTICS_LUA51_PASS`、目标Lua `luac5.1 -p`、严格UTF-8、编译产物静态契约及两仓限定`diff --check`。`ability_tooltip.js`、`combat_stats.js`、`survival_ui.js`、`inventory_tooltip.js`分别由Resource Compiler强制编译为`1 compiled, 0 failed, 0 skipped`。这些只证明静态契约、Lua模拟/语法和构建通过，不是Workshop Tools实机验证。
- 最终状态检查期间新出现`monster_archetypes.csv`及对应生成Lua的怪物速度修改，用户已明确确认是其有意修改；本轮完整保留且未触碰。`SESSION_LOG.md`历史未提交段落存在既有`U+FFFD`替换字符，不在本轮新增记录中；本轮目标源码与新增文档段落严格UTF-8通过，未越界重写历史日志。
- 用户报告N1第13至18波附近客户端闪退，并观察到`LUA Memory usage warning`首次跨过16 MiB。当前没有普通文本log，但已在`game/bin/win64`找到同时间的`dota2_2026_0808_033038_0_V8_hiting_max_memory_limit__512_MB.mdmp`及4秒后的breakpoint转储。
- 初步结论：直接闪退证据指向Panorama JavaScript所在V8 VM达到512 MiB，不得把Lua 16 MiB高水位、V8 512 MiB上限和模型/显存资源池混为一谈。权威`wave_definitions.csv`与`monster_archetypes.csv`确认N1 W13-W18每波仅8至10只、1至2种模型；新增组装视觉仅覆盖W1-W5，因此模型数量不是当前第一嫌疑。
- 用户已批准实施低开销诊断和生命周期门禁：Lua只在波次开始、生成完成和活怪归零时输出当前Lua KiB、活怪、scheduler任务和视觉状态计数，不强制Full GC、不保存历史；Panorama复用`ui_bootstrap.js`的HUD generation，使旧context的长期调度和事件入口失败关闭，并发布固定大小的当前计数。
- 修改边界：不降低CSV怪物数量、不替换W13-W18模型、不修改生成配置、不通过每波`collectgarbage("collect")`掩盖泄漏；保留批量升级及其他既有未提交修改。完成后需冷启动Workshop Tools连续运行至少到W20，比较每波后Lua基线与Panorama诊断，并确认不再生成V8 512 MiB转储。
- 生产实现完成：`scheduler.task_count()`和`monster_visual_service.active_state_count()`提供只读计数；`wave_system`在波次开始、生成完成和活怪归零时输出`[SURVIVAL_MEMORY][LUA]`，包含波次、游戏时间、Lua KiB、alive/pending、敌人表、scheduler和视觉状态。没有调用Full GC，也没有保存样本历史。
- Panorama的`survival_ui.js`、`combat_stats.js`和`ability_tooltip.js`统一以`SurvivalInputLifecycleGeneration + context Panel`校验当前HUD身份。所有原始`$.Schedule`集中到`scheduleActive()`；旧context回调到期后只退出，不再递归。高频NetTable/GameEvent入口同样失败关闭。固定计数包含pending/peak调度、通知Panel、选择事件、Tooltip恢复/Runtime事件和代理Panel；`survival_ui`每60秒输出一条聚合`[SURVIVAL_MEMORY][PANORAMA]`，不保留历史。
- 自动验证通过：`MEMORY_LIFECYCLE_CONTRACT_PASS`、`SCHEDULER_DIAGNOSTICS_LUA51_PASS`、`WAVE_TIMING_LUA51_PASS/CONTRACT_PASS`、`ABILITY_INPUT_LIFECYCLE_CONTRACT_PASS`、`BUILDING_BATCH_UPGRADE_CONTRACT_PASS`、目标Lua 5.1语法、严格UTF-8及game/content限定`diff --check`。三份Panorama JS均由Resource Compiler强制编译为`1 compiled, 0 failed, 0 skipped`。
- 无关失败：`test_n1_wave_config.lua`当前失败于既有“W5起领头怪必须排首位”断言，目标CSV/生成波次数据不在本轮diff中，未为内存任务改数据或测试。尚未完成Workshop Tools实机内存验证，也尚未证明V8泄漏根因完全消除。
- 下一步实机清单：完全停止并重新Run，先召唤英雄并观察至少10秒，确认不再出现`active is not defined`、`refreshOfficialReturnHomeHotkey is not defined`或立即退出，并保存`startup_1s/startup_5s`样本；再冷启动N1连续运行到至少W20，低选择活动跑一轮，高频切换英雄/建筑/怪物并反复悬停技能再跑一轮。逐波保存两类`SURVIVAL_MEMORY`日志，重点比较`wave_cleared`的Lua KiB基线、scheduler/visuals是否回落、Panorama pending/peak/proxies/inventory是否有界，并检查`game/bin/win64`是否新增`V8_hiting_max_memory_limit__512_MB`转储。

## 当前插入任务（2026-08-08）：多选箭塔跨路线批量升级

- 用户最终确认Q/W都需要批量：Q=`ability_upgrade_tower_lv01`按各塔下一等级费用；W=`ability_upgrade_tower_max`按各塔直升当前阶段最高级的累计费用。基础箭塔与不同转职路线可以混选，各塔沿自身路线升级。
- 箭塔候选只要求共同`survival_building_id == "arrow_tower"`，不得再按`survival_tower_class`排除跨路线候选。普通建筑仍按同一`building_id`匹配；转职、融合、金矿科技/自动升级、训练等非Q/W入口不参与。
- `ability_tooltip.js`与`combat_stats.js`现向`ui_ability_cast_request`附带最多64个去重选择候选。客户端列表不具权威性；服务端逐塔校验存活、owner、建筑ID、对应Q/W Ability及可施放状态。
- `building_upgrade_system`新增只读权威报价request：Q返回下一等级目标与费用，W返回当前阶段末目标与累计费用；报价不扣费、不启动升级、不修改冷却。协调器按木材升序、金币升序、entindex升序排列候选。
- 轮到每塔时重新校验并提交既有`BUILDING_UPGRADE_REQUEST`，由现有`RESOURCE_TRY_SPEND_REQUEST`原子扣费。失败只跳过并继续，已成功项目不回滚；仅正式升级成功受理后启动该塔对应Ability冷却。
- 自动验证通过：`BUILDING_BATCH_UPGRADE_LUA51_PASS`、`BUILDING_BATCH_UPGRADE_CONTRACT_PASS`、目标`luac5.1 -p`、升级流程/塔Runtime/人口配置回归、配置CheckOnly、严格UTF-8和两仓`diff --check`。两个Panorama JS均由Resource Compiler强制编译为`1 compiled, 0 failed, 0 skipped`。
- 既有`test_building_state_recovery.lua`在加载未修改的BOM版`building_system.lua`首字节时被裸Lua 5.1拒绝，未进入本任务代码；没有为迎合该无关编码问题改写生产文件。尚需Workshop Tools冷启动实测跨路线Q/W、部分资源、鼠标/快捷键与多人owner隔离。

## 当前插入任务（2026-08-08）：多选金矿Q/W/E与自动升级批量协调

- 用户最终要求：全选多座金矿时，Q按每矿权威下一等级费用逐矿升级；W/E是玩家共享科技，一次批量请求只购买1级；自动升级按钮按明确目标状态批量开启或停止，混合状态下已处于目标状态的金矿幂等跳过。
- 生产实现完成：新增`gold_mine_batch_upgrade_service.lua`。客户端沿用现有最多64个去重`selected_entindexes`载荷；服务端重新验证存活、owner、`gold_mine`身份、对应Ability、升级中和可施放状态。Q先读取`gold_mine_system`只读报价，按木材、金币、entindex升序逐矿调用原升级事务；失败继续，成功受理后才冷却。
- W/E只从请求发生前的有效候选中选择entindex最小金矿作为购买来源，调用一次现有`TECHNOLOGY_PURCHASE_NEXT_REQUEST`原子扣费/发放；成功后对全部有效候选同步对应Ability冷却，失败不冷却。批量服务只发一次汇总通知，商店请求使用显式静默标志避免重复提示。
- 自动升级底层兼容旧单矿toggle，同时接受`enabled=true/false`明确状态。批量开启/停止不会对已处于目标状态的矿反向切换；同一玩家全部自动矿中entindex最小者协调共享科技购买，其他自动矿继续独立升级本体并等待协调者，科技缓存只由权威`TECHNOLOGY_CHANGED`更新。
- 自动验证通过：`GOLD_MINE_BATCH_UPGRADE_LUA51_PASS`、`GOLD_MINE_AUTO_COORDINATOR_LUA51_PASS`、`GOLD_MINE_BATCH_UPGRADE_CONTRACT_PASS`、箭塔批量回归、四项商店/研究科技回归及目标Lua 5.1语法。Panorama协议未修改，因此未重新编译JS。尚需Workshop Tools冷启动实测鼠标按钮、Q/W/E快捷键、部分资源、混合自动状态和多人owner隔离。

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

## 已完成待实机验收（2026-08-12）：死亡/闪电/激光/防空塔阶段饰品与凤凰激光

- CSV权威源已更新：死亡塔一阶段使用Templar Assassin `Darkblade Adept`四件套；闪电二阶段使用基础Leshrac，三阶段使用Razor `Voidstorm Asylum` Arcana主体与五件套；激光三阶段依次使用Keeper of the Light `Forgotten Renegade`、Outworld Destroyer `Blackgate Sentinel`、Phoenix基础主体加`Solar Forge`头和`Solar Gyre`翅膀；防空三阶段依次使用Gyrocopter `Swooping Elder`、Batrider `Empiric Incendiary`、Skywrath Mage至宝`The Devotions of Dragonus`第二分支“天怒一族尊主”。
- `items_schinese.txt`与`items_game.txt`交叉确认：劫烧狂客为`Empiric Incendiary` Bundle 21239；天怒目标为Bundle 22277“倾天之战：扎贡纳斯的献身”，核心翅膀物品18539负责替换`skywrath_arcana.vmdl`主体，Style Unlock 27601解锁style 1 / skin 1。空域霸主现使用至宝主体、18539-18544六件组件、第二分支常驻粒子与`skywrath_arcana_base_attack_v2.vpcf`弹道；旧版将其误判为单件`Empyrean`（物品6892）的结论已作废。
- 闪电链`lightning_strike_lv01-lv05.area`统一为500；雷暴`lightning_storm_lv01-lv05.area`统一为300，并同步描述。保留任务前已有的闪电塔全阶段`base_attack_speed=2`及其余物理伤害/技能链修改。
- `tower_laser_effects.csv`改用`effect_key`索引，保留五条技能默认Tinker Laser行，并增加`laser_lv05:tower_laser_phoenix_solar`；运行时按`skill_id + survival_model_asset_id`优先选择，找不到时回退技能默认，因此只有Phoenix阶段使用Solar Forge Sun Ray。
- Phoenix激光继续同步CP9/CP0源点与CP1目标点；本机资源定义没有要求额外控制点，因此未扩展未经验证的控制点逻辑。新增八个精确主体预载代理，组件和粒子继续由资源子表预载链负责。
- `tools/build_configs.py`成功生成84个Lua配置模块。自动验证通过：`ASSET_BUNDLE_CONFIG_PASS`、`TOWER_LIGHTNING_VISUAL_PASS`、`DEATH_TOWER_TEMPLAR_VISUAL_PASS`、`ANTI_AIR_TOWER_LUA51_PASS`、`TOWER_STAGE_VISUAL_ROUTES_PASS`、`TOWER_SKILL_GEOMETRY_PASS`、`ANTI_AIR_TOWER_CONTRACT_PASS`、`RESOURCE_PATH_CHECK_PASS`、`LIGHTNING_RANGE_CONTRACT_PASS`、`PHOENIX_LASER_CONTRACT_PASS`、相关Lua 5.1语法与`git diff --check`。
- 路线Gameplay列对比：死亡、激光、防空除模型字段外0差异；闪电仅保留任务开始前已有的20条攻速`1 -> 2`差异。本轮未修改其他塔数值、伤害、眩晕、光环、费用、人口或升级逻辑。
- 天怒至宝纠正专项验证通过：`ASSET_BUNDLE_CONFIG_PASS`、`TOWER_STAGE_VISUAL_ROUTES_PASS`、`ANTI_AIR_TOWER_LUA51_PASS`、`ANTI_AIR_SKYWRATH_CSV_CONTRACT_PASS`、`ANTI_AIR_GAMEPLAY_COLUMNS_UNCHANGED_PASS`、`SKYWRATH_ARCANA_STYLE1_RESOURCE_PATH_PASS`（主体、六件组件、四个粒子共11条VPK资源）、相关Lua 5.1语法及`git diff --check`。未跟踪的旧`tools/test_anti_air_tower_contract.ps1`在Windows PowerShell 5.1中因无BOM UTF-8中文路径被误解码，于`Import-Csv`前失败；其数值契约由Lua测试和独立CSV列对比覆盖，本次未修改该无关脚本。
- 尚未Workshop Tools冷启动实机验收。需要完全停止并重新Run，逐阶段确认组件骨骼合并、模型尺寸、动作、头像、升级换模，以及Phoenix Solar Forge Sun Ray的源点、目标点、持续重播和停止攻击/目标死亡时清理。

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

- 当前插入任务：区域生产实现与自动验证完成，真实Hammer边界坐标缺失导致CSV保持空业务行；运行时按批准策略失败关闭，尚不能Workshop Tools实机验收。
- 当前阶段：阶段1生产实现与自动验证完成，等待Workshop Tools单人冷启动验收。
- 当前地图源存在`template_map.vmap`和`survival_dev.vmap`，运行产物为`maps/template_map.vpk`。
- 已确认旧地图只有单个历史波次marker `monsterborn`；尚未确认4套玩家marker。
- 当前启动规则和`addoninfo.txt`已开放4名好人方玩家；后续玩家由`player_connect_full`分配到好人方。
- 旧`CURRENT_TASK.md`和旧`START_HERE.md`已完整归档到`docs/ai/archive/2026-08-06-pre-multiplayer-*.md`；旧任务全部暂停，不得自动恢复。
- 工作区已有大量未跟踪测试文件，属于用户既有内容，本任务不得覆盖、清理或纳入交付。

## 下一步唯一动作

先进行Workshop Tools冷启动区域实机验证，确认空配置下Grid显示和合法建造恢复、非法区域仍显示红格。Hammer真实边界取得后再更新权威CSV并定向生成，以启用严格白名单；多人阶段1保持暂停，等待当前插入任务实机结果。
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
