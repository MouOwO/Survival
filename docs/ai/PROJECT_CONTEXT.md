# Project Context

## 英雄原生Wearable预载经验（2026-08-20）

- `ReplaceHeroWithNoTransfer()` 可能在英雄替换时实例化 Dota 原生默认 wearable；即使英雄主体和代理已预载，未声明的肩甲、手臂、头部、武器、披风等模型仍会产生 `nonresident model` 警告或加载时序问题。
- 处理流程必须先从 CSV 权威数据确认英雄主体和所有实际默认 wearable，再把 wearable 模型写入 `data/csv/资源系统/asset_catalog.csv` 对应英雄 bundle 的 `attachment_models`，通过生成器更新 `config/generated/asset_catalog.lua`，并同步 `scripts/npc/npc_units_custom.txt` 中同名 `asset_proxy_hero_*` 的 `precache` 块。
- 原生 wearable 只用于预载，禁止加入 `asset_components.csv` 或项目运行时 cosmetic 挂载列表，否则会与 Dota 原生 wearable 重复创建。资源完成状态必须覆盖主体、附件、粒子和声音的显式请求，并在精确 `PrecacheUnitByNameAsync()` 代理回调后才发布 bundle `READY`。
- 自动契约和 Lua 5.1 模拟只能证明声明、生成和门禁逻辑；只有 Workshop Tools 完全冷启动并实际召唤目标英雄后，才能确认模型告警消失、最终外观正确和真实加载时序。用户已确认本次 Shadow Fiend/Drow Ranger 修复实机成功。

## 玩家数据库玩法属性字段（2026-08-20）

- `data/csv/玩家档案系统/player_gameplay_stats.csv` 是玩家开局经济、英雄、防御塔、城墙和伐木工 35 个属性的唯一默认值来源；`scripts/vscripts/config/generated/player_gameplay_stats.lua` 由生成器产生，禁止直接手改。
- `player_id` 在数据库属性表中是 64 位小写十六进制 HMAC-SHA256 伪名文本，外部原始身份来自服务端 `PlayerResource:GetSteamAccountID()`；Dota 本局 `PlayerID` 槽位不得作为永久数据库主键。
- 百分比字段使用百分点存储，`15` 表示 `15%`；整数资源/生命/攻击/积分使用 `bigint`，可带小数的速率、效率、护甲和攻击间隔使用 `numeric(20,6)`。百分比边界按 CSV 与 migration 约束执行。
- `player_gameplay_stats` 由 `ensure_player_gameplay_stats` 首次幂等创建，属性进入档案私有 `save.gameplay_stats`，不得进入公开 NetTable。
- `online_seconds_total` 是玩家永久累计在线总秒数，默认值来自同一份玩家属性 CSV。数据库心跳 RPC 只累计同一 `session_id` 租约内的有效相邻心跳差值；首次、新 session、超租约和掉线间隔均为 0，重复 `request_id` 返回已保存响应且不得再次更新统计。钓鱼响应中的 `elapsed_seconds` 仍是奖励倒计时差值，不是永久在线总时长。
- 当前真实 Supabase 项目已执行两份 migration，并于 2026-08-20 通过 Secret key + REST RPC 验证档案初始化、36字段、在线时长累计、幂等、租约排他、超租约接管、revision和公开数据隔离。Automation 9001 定义已同步到该测试项目；这不等于生产奖励启用，也不等于 Workshop Tools 实机通过。

## 正式波次与练功房怪物碰撞边界（2026-08-19）

- `global_rules.csv.wave_ground_monster_hull_radius`只作为正式/默认地面怪基础Hull，当前为32；四个练功房成员必须由`encounter_members.csv.collision_profile=practice`显式识别，并读取独立的`practice_monster_hull_radius`，当前为12。不得通过硬编码遭遇ID、成员ID前缀或共享原型推断练功房身份。
- 练功房保留单位间碰撞，不启用`NO_UNIT_COLLISION`。由于`CreateUnitByName(..., true, ...)`会在创建阶段先按默认Hull执行clear-space，练功房必须关闭该默认行为，先应用profile Hull，再显式调用`FindClearSpaceForUnit()`；其他挑战成员维持原生成时序。后续若实机仍拥挤，必须由用户确认后再单独评估练功房专属无单位碰撞，不能影响正式波次。

## 全部怪物碰撞与精英/Boss攻击范围统一（2026-08-15）

- 未配置独立碰撞profile的怪物按移动类型使用与小怪相同的基础HullRadius：地面怪统一读取`global_rules.csv.wave_ground_monster_hull_radius=32`，飞行怪统一为10；不再为精英、领头怪、Boss或研究所挑战怪保留0 Hull和无单位碰撞。正式波次、挑战副本、野外/转生遭遇及研究所挑战生成边界均消费同一碰撞解析器；练功房例外以上方2026-08-19章节为准。
- `monster_archetypes.csv`中全部`rank=elite/boss`原型，以及`building_challenge_definitions.csv`中全部Boss，攻击范围均在原值上增加36并生成到Lua。新增或修改怪物时必须先维护CSV，运行时不得再次叠加36。

## 伐木工融合与性格技能边界（2026-08-18）

## Tooltip 技能接入标准流程（2026-08-18）

- 用户已实机确认本流程的 Tooltip 显示正常。以后任何新技能、动态挂载技能或被动技能接入 Tooltip，必须沿用以下完整链路：先在对应业务 CSV 中登记 Ability ID、名称、描述和图标等基础数据；再运行 `build_tooltip_definitions.py` 生成统一 Tooltip CSV/Lua；由 `client_data_service.lua` 投影到 `survival_ability_data`/`survival_tooltips`；在 `ability_tooltip.js` 中加入正确的自定义接管范围和单位/Ability 判定；在 `hud_takeover.js` 中确保技能面板、代理绑定、首次悬停初始化和原生 Tooltip 抑制路径覆盖该技能；必要时同步 `combat_stats.js` 的技能枚举/快捷键投影。
- Content Panorama 源码修改后，必须使用 Resource Compiler 强制编译对应 Game 侧 `.vjs_c` 产物，确认每个目标为 `OK: 1 compiled, 0 failed, 0 skipped`；同时执行 Tooltip CSV/Lua 生成校验、严格 UTF-8、相关契约和 `git diff --check`。
- 新技能不得只补 Valve localization 或只补 CSV 文案；必须验证“未使用任何技能前首次选中/首次悬停”“技能使用后刷新”“动态 Ability/被动 Ability”三种状态均由自定义 Tooltip 接管。最终必须进行 Workshop Tools 冷启动实机验收，确认没有原生 Tooltip 回退、显示内容正确且技能映射未改变。

- 普通伐木工融合配方权威源是`lumberjack_fusion_definitions.csv`，训练阶段`max_count`与融合所需数量保持独立。LV1为5合1，LV2-LV8为3合1；LV1/LV2要求主城LV4，LV3-LV8要求主城LV5；材料必须同玩家、同队、同训练等级、存活且不是超级伐木工。
- 融合资源费用也只来自该CSV：LV1/LV2为10000/20000木材，LV3-LV8为30000/40000/50000/60000/70000/80000木材及5000/8000/15000/30000/40000/50000金币。服务端先锁材料并通过`RESOURCE_TRY_SPEND_REQUEST`原子扣费，目标创建/注册/提交任一步失败都用`RESOURCE_ADD_REQUEST`按原额退款。
- 超级伐木工进入`worker_system`同一注册、树攻击、科技刷新和死亡人口释放链。目标攻击力取材料各自当前`survival_attack_min`之和；注册时剥离已包含的单个科技攻击增量，再按融合数量投影未来科技，避免重复叠加。目标BAT在注册时直接应用基础间隔减0.5秒。合成先预校验并锁定材料，再扣资源、创建并配置目标，最后由工人注册表一次提交材料替换和净人口释放；失败目标必须静默回滚注册，禁止依赖异步死亡事件补事务。
- 11项性格定义以`lumberjack_personality_definitions.csv`为权威。超级LV1-LV7每次从完整池等概率随机挂载1项，允许重复；LV8无性格。超级攻击与基础采集量汇总材料基础值，科技和树等级增益按材料数量投影，每击成长的全局累计只提交一次，避免`n²`放大。


## 持久化在线计时钓鱼奖励边界（2026-08-17）

- 信任链固定为Dota服务端Lua -> 仅loopback监听且Bearer认证的Python API -> Supabase PostgreSQL。Steam Account ID由服务端`PlayerResource:GetSteamAccountID()`解析；Lua和客户端不得持有Supabase URL、service-role key或数据库凭据。
- 局外 HTTP/档案钓鱼的表仍属于玩家档案域并参与数据库定义校验；局内钓鱼使用`data/csv/挑战与奖励系统/fishing_system_rules.csv`和`fishing_reward_definitions.csv`，只作为本局抽奖配置，不写入数据库。
- 在线时间只由同一session租约内相邻心跳差值累计。首次、新session、超租约和离线时间均扣0秒；单账号只允许一个活动租约，异常断线最多等待15秒接管且等待期间冻结。
- grant历史、永久聚合、档案revision、下个区间和幂等响应必须在`heartbeat_fishing_session()`一个数据库事务中提交。`reward_grants`不可变，`player_effect_totals`是当前投影；Lua使用同一request ID重试并按grant ID做同局应用去重。
- 永久效果通过`permanent_reward_effect_service`从既有已校验档案`save.permanent_effects`恢复，不能混入单局科技或挑战状态。当前适配键为英雄全属性/攻击、伐木工攻速百分比和金矿收益百分比。团队资源未玩家隔离前，禁止把玩家永久开局资源直接加入共享team账户。
- 即时资源尚无数据库提交后Lua崩溃的持久投递ack，生产不得启用immediate奖励。当前三条歧义奖励全部禁用；生产池为空导致API启动失败是有意失败关闭。
- 钓鱼grant必须由Lua按本地CSV生成定义复核版本、ID、效果、scope、enabled和整数数值范围。永久效果仅在中奖玩家档案快照及其独立永久投影成功后发布一次`FISHING_REWARD_GRANTED`；即时资源因当前账户仍是team-scoped而在共享账户写入前失败关闭。成功事件只含白名单业务字段，不能携带raw grant、账号、Token、档案或definition hash。
- 钓鱼成功公告由`FISHING_REWARD_GRANTED`订阅者构造，只使用服务端玩家名、CSV `display_name`和已校验amount，并通过显式`UI_NOTIFICATION.audience="all"`广播。UI路由只有该显式值才调用`Send_ServerToAllClients`，其他通知继续定向；客户端只接收`message/level`。自动化fixture固定definition version 9001/10秒，Lua端仅在Tools Mode且`survival_fishing_reward_fixture=automation_9001`时加载。

## Builder第六业务槽与研究/挑战建筑并存边界（2026-08-15）

- 建筑前置身份必须从`builder_ability_stages.csv`生成配置投影到`buildings_config.lua`，不得在具体建筑定义中重复手写。普通研究所的`requires_building_id`为空；高级研究所和挑战建筑均为`building_research_lab`。误把普通研究所前置写成自身会让`building_system.can_place()`在Grid地形校验前固定拒绝，随后全部footprint格被统一标红，表现与碰撞或地形阻挡相同；排查全红时必须先比较同位置其他建筑并检查业务错误。
- `builder_ability_stages.csv`是Builder槽位与建筑前置的唯一权威源。普通和高级研究所共用`slot_order=2`并按普通研究所完工替换；独立挑战建筑使用`slot_order=6`且要求普通研究所完工，不替换任一研究所。
- Builder六个业务槽按CSV `slot_order=1..6`保持相对连续，`ability_survival_builder_blink`紧随第六业务槽；它们不再绑定绝对engine index。实机Builder可能由未知非管理Ability占用index 0，此时管理域自然位于`1..7`。同步必须保留所有非管理Ability，以首个现有管理Ability为管理域起点；完全无管理实例时从真实`GetAbilityCount()`之后自然追加。正确布局保持实体以保留冷却，异常布局才清理管理实例并按相对顺序重建，不能依赖`FindAbilityByName()`掩盖同名重复。
- 动态`npc_dota_creature`的`SetAbilityIndex()`不保证在同一同步调用内立即反映到严格槽位枚举。Builder重建时必须先对`AddAbility()`实际返回的实例写入等级、隐藏和激活状态，再验证布局；布局瞬时失败可记录并由后续同步自愈，但不得提前返回而留下0级/未激活的整排灰按钮。行为测试必须模拟拒绝即时换位，不能只使用理想化槽位Mock。
- 最新实机进一步证明“失败后反复重建并等待自愈”仍不可靠，可能留下重复箭塔或错误槽枚举。当前稳定策略是在动态管理域内让六个业务相对槽始终各有一个自然添加的业务Ability或隐藏占位Ability，Blink最后自然添加；Builder生产同步禁止调用`SetAbilityIndex()`。隐藏占位固定Lv.1、隐藏、未激活，并纳入管理域清理和完整布局校验。
- Builder Panorama快捷键不得再读取瞬时engine slot。`ability_runtime_builder.lua`必须从生成`builder_ability_stages.lua`按Ability名称发布`builder_slot_order`，标签与键盘输入共同消费该字段映射`1..6 -> Q/W/E/R/T/A`；Blink仍按名称映射D。这样CSV仍是唯一业务槽权威源。
- 实机已证明使用`DOTA_UNIT_CAP_MOVE_NONE`真实静态建筑作为Grid预览时，仅加`MODIFIER_STATE_NO_UNIT_COLLISION`和`SetHullRadius(0)`仍可能让预览后的网格持续全红。项目Grid预览统一创建专用地面移动型`npc_survival_grid_preview_proxy`，再由预览Modifier固定、禁交互并写0 Hull；模型和缩放从生成建筑配置投影。真实完工建筑继续使用KV Hull、逻辑footprint和Grid占用，禁止用修改真实建筑Hull掩盖预览问题。
- 普通研究所自前置修复已由用户于2026-08-15明确确认解决并通过实机验收。后续若再次出现普通研究所四格固定全红，先检查生成Builder阶段和`buildings_config.lua`运行投影是否仍使普通研究所`requires_building_id=nil`，再检查专用预览代理与地形；不得直接恢复普通研究所自身前置，也不得把本任务重新列为待验收。
- Panorama识别`npc_survival_builder_proxy`后按runtime `builder_slot_order=1..6`映射`Q/W/E/R/T/A`，Blink按名称固定映射`D`；视觉标签和键盘分发必须消费同一映射，禁止读取绝对engine index推导业务键。所有客户端实体Ability枚举必须受`survival_ability_runtime["unit:<entindex>"].ability_count`限制；固定24/64扫描只允许用于枚举Valve `AbilityN` HUD节点。
- 恢复stash或解决二进制Panorama冲突时，`.vjs_c/.vcss_c/.vxml_c`必须从最终合并后的content源强制重编译，禁止直接采用ours/theirs。HUD XML递归编译产生的无关依赖副产物应恢复到任务前index，只保留目标产物。

## 全部怪物碰撞与精英/Boss攻击范围统一（2026-08-15）

- 所有怪物按移动类型使用与小怪相同的基础HullRadius：地面怪统一读取`global_rules.csv.wave_ground_monster_hull_radius=32`，飞行怪统一为10；不再为精英、领头怪、Boss或研究所挑战怪保留0 Hull和无单位碰撞。正式波次、挑战副本、野外/转生遭遇及研究所挑战生成边界均消费同一碰撞解析器。
- `monster_archetypes.csv`中全部`rank=elite/boss`原型，以及`building_challenge_definitions.csv`中全部Boss，攻击范围均在原值上增加36并生成到Lua。新增或修改怪物时必须先维护CSV，运行时不得再次叠加36。

## 城墙War3护甲、正式波次碰撞与D位移截断（2026-08-15）

- 城墙基础护甲来自`building_levels.csv.war3_armor`；科技`super_wall_armor_flat`和山岭巨人`challenge_wall_armor_flat`虽然在既有聚合层按Dota单位`/3`保存，但投影到城墙自定义护甲状态时必须乘回3。城墙原生Dota护甲固定为0，全部物理伤害由唯一Damage Filter按`1/(1+0.02*max(0,有效War3护甲))`结算并忽略原生护甲；百分比穿甲先作用于War3护甲。
- 正式波次所有地面怪不区分普通、精英、领头怪或Boss，基础HullRadius统一从`global_rules.csv.wave_ground_monster_hull_radius`读取，当前为32。飞行怪及研究所挑战怪的旧特殊碰撞规则已被上方2026-08-15统一规则替代。`scalemonster`只按缓存的基础Hull非累计缩放，不能修改模型缩放。
- 建造者和防御塔D实际最大位移1000，英雄D实际最大位移800。鼠标目标超范围时，过滤与执行都必须用公共helper沿光标方向截断到最大距离，再执行原有地形、占用、旅行状态等校验；不得返回距离超限。防御塔的Ability与Panorama请求入口都执行该规则，最终移动继续通过`building_system.relocate_building()`。

## 挑战怪碰撞、挑战建筑视觉与Toggle输入边界（2026-08-14）

- 本节的研究所挑战怪0 Hull规则已被上方2026-08-15统一碰撞规则替代；挑战怪仍不进入正式波次`enemies`集合。
- 动态`npc_dota_creature`建筑的Toggle不能只实现Lua `OnToggle()`。Panorama托管动作必须识别该Ability，允许`DOTA_ABILITY_BEHAVIOR_TOGGLE`行为位通过无选点分发；`ui_request_router`验证实体归属、建筑身份和Ability归属后直达权威服务，并同步引擎Toggle外观。服务端调用`ToggleAbility()`前必须设置重入标记，避免`OnToggle()`再次反向提交。
- 同一动态建筑的完工尺寸和施工覆盖必须成对配置：`building_visual_levels.csv`定义模型/完工`model_scale`，`building_construction_rules.csv`定义施工粒子、时间和`build_visual_scale`，再由正式生成器生成Lua。缺少施工行会回退到缩放1，造成施工与完工尺寸不一致；不得为单一建筑绕开`building_construction_visual_service`另写施工特效。
- 本轮任务已由用户于2026-08-14明确确认完成，其中挑战怪0 Hull规则已在2026-08-15被新需求替代。若自动Toggle失效，按“Panorama托管识别 -> Toggle行为位放行 -> `ui_request_router`直达分发 -> `OnToggle`重入保护”的顺序排查；若建筑施工尺寸跳变，先比较两张CSV的缩放值，不新增旁路实现。

## 研究所建筑技能与Builder W替换边界（2026-08-15）

- 研究技能身份、所属建筑、链顺序和槽位唯一权威源为`research_lab_abilities.csv`。普通研究所固定六槽：`Q`速度低/高级链、`W`普通伐木效率、`E`防御塔低/高级链、`R`城墙低/高级链、`T`高级伐木效率、`A`伐木暴击；只有速度/防御塔/城墙在普通科技满10级后同槽替换。高级研究所固定`Q/W/E/R/T/A/S/D/F/G`十槽。
- 未解锁、研究中和满级科技都保留Ability与固定槽位，通过`SetActivated(false)`置灰；前置或转生满足后激活同一个Ability。不得再以删除满级Ability表达完成状态，也不得恢复高级研究所Panorama 5x2特殊布局。
- 两类研究所固定使用Valve原生Ability按钮视觉，项目52px技能接管必须对研究所无条件关闭。固定槽位/快捷键属于运行时输入规则，不依赖自定义按钮绘制；原生按钮角标按`research_slot_order`和`research_building_id`投影固定键位。
- 研究科技使用独立于Valve `AbilityN`祖先树的透明代理：保留原生按钮视觉和禁用遮罩，代理屏蔽Valve原生Tooltip并显示项目Tooltip，同时承接左键研究和高级研究所右键窗口。代理映射失败必须整批失败关闭，避免部分按钮出现双Tooltip或点击分流。
- 高级研究所即使运行时权威配置有十槽，Valve HUD也可能只创建部分真实`AbilityN`按钮。代理枚举上限必须来自研究运行时签名：已有按钮使用真实窗口矩形，尾部缺失槽位按最后两个真实按钮的水平步距外推，步距无效时回退按钮宽度；外推槽只使用显式窗口矩形做定位和光标命中，禁止访问空Valve锚点。代理Tooltip与左键项目输入必须共同消费同一槽位投影。
- 研究科技Tooltip标题读取`research_lab_abilities.csv.display_name`，当前科技等级单独显示；描述、累计效果、升级后效果、等级上限和前置由服务端消费`technology_definitions.csv`后发布。Panorama不得维护第二套高级科技效果字典，研究Tooltip不得显示Ability内部名、施法类型或稳定`RS-*`/`ARS-*`编号。
- `technology_definitions.csv`及其生成Lua是研究等级、逐级费用、累计效果、科技前置和转生要求唯一权威源。`research_technology_config.lua`只允许作为稳定`RS-*`/`ARS-*`身份和效果单位转换适配层，不得重新维护线性费用或等级常量。
- 普通研究范围是九个非金矿组，高级研究范围是十个`researcher_*`组；`gold_mine_efficiency`和`gold_mine_crit`只能由金矿能力链消费，不进入任一研究所。
- Builder W阶段唯一权威源为`builder_ability_stages.csv`：主城完成后先显示普通研究所建造；只有普通研究所发布完工`BUILDING_CREATED`后才替换为高级研究所建造。主城Lv.4控制激活状态，不控制提前显示；建造系统还必须验证前置研究所已完工，不能接受施工中计数。
- 研究点击必须从当前Ability映射反查可信科技组，并验证Ability属于来源建筑、建筑已完工、building ID匹配、owner/team匹配且Ability可用，再进入现有团队共享2秒研究事务。客户端运行时和技能增删只投影服务端状态，不自行提交等级。
- 高级研究所视觉与尺寸保持`models/props_structures/radiant_ancient001.vmdl`、`model_scale=0.34`、`2x2` footprint和`AbilityLayout 12`。左键研究技能直接研究；右键高级研究技能打开高级研究窗口，窗口右键卡片切换自动研究。

## 神秘塔激光Tick权威边界（2026-08-13）

- `tower_skill_definitions.csv`是生产激光Tick间隔的唯一权威源；`laser_lv01-lv05`统一使用`damage_interval=1`，与神秘路线录像实验的1秒模型一致。不得在运行时、Tooltip或测试中另写0.5秒等级常量。
- 生产首次锁定目标时仍由攻击开始事件立即执行首个Tick，后续Tick按CSV的1秒间隔调度；本次数值修正不改变首次Tick、基础倍率、每秒5%成长、500%封顶、切换目标重置或魔能之眼事件链。
- 对照LV2第7波时必须区分生产基础攻击`1401`与离线录像实验面板输入`1501`。这是独立数据差异，不得通过修改激光间隔之外的生产攻击力补偿。

## 建筑升级粒子生命周期边界（2026-08-13）

- 建筑等级升级和箭塔转职统一由`building_upgrade_process.lua`管理约1秒事务；施工粒子路径来自`building_construction_rules.csv`经生成配置进入`state.definition.build_particle`，不得在升级系统中另写第二套路径。
- 升级完成、取消、reset、实体失效和粒子创建中途失败都必须立即`DestroyParticle(id, true)`，然后独立调用一次`ReleaseParticleIndex(id)`。保存的粒子ID应在引擎调用前清空，避免迟到回调、取消与reset重复释放；销毁失败也不能阻断释放尝试。
- 当前神秘塔崩溃排障临时输出最多64条`BuildingUpgradeParticle`日志，包含粒子ID、建筑entindex、生命周期状态和清理细节。Workshop Tools确认后应移除或恢复默认关闭，不能长期把升级成功日志做成无界输出。

## 激光基础倍率与路线继承边界（2026-08-13）

- `tower_skill_definitions.csv`是生产激光基础倍率唯一权威源：`laser_lv01-lv05`固定为`1.0/1.2/1.4/1.6/1.8`；`tower_laser_damage.lua`只负责读取快照倍率、按完整秒数增长并执行上限，不在运行时重复硬编码等级数值。
- `tower_class_mystery.csv`的神秘之塔LV1-LV5继续映射`laser_lv01`至`laser_lv05`；魔能炮和魔能之眼技能链继续继承`laser_lv05`，因此基础激光倍率为`1.8`。修改技能倍率时必须同时检查路线映射、Tooltip、六份本地化和离线实验CSV。
- `war3_damage_calculator_mystery_experiment.csv`的神秘路线预设使用`1/1.2/1.4/1.6/1.8`，魔能炮与魔能之眼预设保持`1.8`；该CSV只嵌入离线HTML，不生成生产Lua或注册配置索引。
## 离线Survival伤害计算器数据与生成边界（2026-08-13）

- 独立工具入口为`tools/war3_damage_calculator/index.html`，必须保持`file://`直接打开可用，不依赖服务器、npm、CDN或Panorama，也不得把其计算模型接入地图运行时伤害链。
- 项目怪物正护甲系数、War3到Dota线性投影和当前Dota护甲曲线常量的权威源是`data/csv/公共规则/war3_damage_calculator_rules.csv`。修改后运行`tools/build_war3_damage_calculator.ps1`，同步更新单文件HTML中的标记常量、生成Lua和配置索引；标记常量与生成Lua禁止手改。
- 计算器支持多个攻击单位，各自只配置每秒攻击次数并沿独立时间轴在0秒首次命中；所有单位共享基础/当前攻击力与命中后永久成长。同刻命中共享成长前攻击力，整个同刻事件结算后才按平A数量累计成长。
- 暴击必须按生产attack record的独立随机概率建模。当前离线工具以每击期望倍率累计到离散命中阈值，显示期望暴击/非暴击次数；不得恢复全局前`N`次固定暴击。结果名称必须保持“期望伤害达标时间”，不能描述为某局保证值或随机停止时间的严格数学期望。
- 固定减甲先改变War3显示护甲，百分比物理护甲无视再缩放剩余正护甲。明确项目怪物正护甲使用`1/(1+0.02W)`目标曲线；零/负护甲以`W/3`运行时投影使用当前Dota曲线。工具不处理最终伤害科技、Boss减伤、光环、技能、闪避、格挡、回血、前摇或弹道时间。
- 神秘路线录像反推数据的独立权威源为`data/csv/公共规则/war3_damage_calculator_mystery_experiment.csv`。它只能嵌入离线HTML，不生成Lua、不注册`config/generated/index.lua`，也不得用于修改生产塔CSV或运行时技能。
- 神秘实验预设直接使用录像/工作簿面板攻击力；正式`tower_class_mystery.csv`少100的内部原因未唯一证明前，不得从实验工具反推生产补偿。默认模型为`t=0`普攻、`t=1`激光，之后各1秒一次；激光每Tick+0.05、最高5.0且换目标重置。
- 魔能炮实验层按每次击杀独立保存`触发时间+5秒`，五级上限4/5/6/7/7，致死事件结束后才新增。魔能之眼原版实验只由普通攻击触发，按塔到主目标线段和可调半宽筛选其他单位，主目标排除并逐单位按护甲结算。
- 路径半宽96不是原版权威值；魔能炮增伤是否传递给魔能之眼也未唯一确认。页面必须保留可调半宽和显式开关，默认关闭增伤传递，不得把实验选择写成已证实生产规则。

## 离线伤害计算器复用方法（2026-08-14）

- 计算器的通用方法是“CSV权威参数 + 单文件JavaScript离散事件模拟”，不是把最终伤害套入一个连续时间公式。先确认业务输入属于生产规则还是录像/工作簿实验；生产规则读取`war3_damage_calculator_rules.csv`及其他业务CSV，神秘路线实验读取`war3_damage_calculator_mystery_experiment.csv`，两者不得互相补值。
- 伤害计算顺序固定为：War3显示护甲先减固定减甲；只对剩余正护甲施加百分比无视，零/负护甲保持原值。War3护甲先按`DotaArmor = W / 3`投影，当前Dota承伤曲线为`1 - 0.06 × DotaArmor / (1 + 0.06 × abs(DotaArmor))`；正护甲下它严格化简为项目目标`1 / (1 + 0.02 × W)`。
- 普攻结果按攻击事件计算：每个攻击单位独立维护下一次命中时间，所有单位从`t=0`开始；取最早时间，合并同刻攻击，使用该事件开始时的当前攻击力和护甲倍率。暴击使用每击期望倍率`1 + 暴击率 × (暴击倍率 - 1)`，暴击次数包含在总平A次数内，不模拟固定“第几次暴击”或伪造随机停止时间。
- 成长在事件伤害结算后生效；同刻命中共享成长前攻击力，整个同刻批次结束后按命中数累计成长。成长可按固定值或基础攻击力百分比计算。达到生命阈值时返回离散事件时间、总命中数、期望暴击/非暴击次数、致死事件伤害和累计伤害，并将结果称为“期望伤害达标时间”。
- 神秘路线实验单独维护普通攻击与激光两个下一事件时间：默认`t=0`普攻、`t=1`激光首跳，后续按各自间隔推进；同刻时按显式`attack_first`或`laser_first`顺序结算。激光每个目标维护独立Tick索引，切换目标后重置；魔能炮层以每次致死事件结束后的`time + duration`独立过期时间保存，并在新增层前先使用已有层数，禁止本次击杀反向增强本次伤害。
- 路径类附伤必须按几何边界逐单位筛选并逐目标护甲结算：目标需满足`0 <= x <= distance`且`abs(y) <= halfWidth`；主目标排除。路径半宽、层数是否传递等仍是实验开关，未被证实前不能升级为生产规则。
- 实现复用流程：修改对应CSV后运行`tools/build_war3_damage_calculator.ps1`；该脚本校验CSV schema/类型/数量和正值，将规则嵌入HTML并生成必要Lua。随后运行`tools/test_war3_damage_calculator_contract.ps1`，检查生成稳定性、生产索引隔离、Lua 5.1语法，并用Edge桌面和移动视口执行页面断言。新增实验时至少覆盖护甲正/零/负值、固定减甲顺序、同刻事件、首击时间、成长、目标切换重置、层独立过期、路径边界和无效输入。

## 建筑等级名称与护甲展示边界（2026-08-12）

- `building_levels.csv.display_name`是主城与城墙各等级名称的权威源。创建、热恢复、升级提交和公开状态发布必须按当前等级解析；箭塔路线/转职名称及其他建筑的动态`payload.display_name`行为不得被该规则覆盖。
- `building_levels.csv.war3_armor`是原始业务护甲；`buildings_config.lua`中的`armor`仍是经项目War3到Dota规则换算后的引擎运行护甲。不得为了Tooltip改回原始值驱动引擎护甲。
- 城墙升级Tooltip展示相邻等级`war3_armor`的原始差值；其他建筑继续展示运行时`armor`差值。修改相关字段时必须从CSV生成链验证，禁止直接手改`config/generated/building_levels.lua`。
- 当前`building_levels.csv`使用CP936/GBK编码。读取和定向生成必须沿用生成器编码回退并检查乱码；不得以系统默认编码整文件重写。


## 原生技能栏快捷键标签所有权（2026-08-12）

- Valve原生技能栏和输入链必须保持启用；`ui_bootstrap.js`的HUD隐藏配置继续使用`abilities: false`，不得为了自定义标签隐藏或重建整条技能栏。
- 项目快捷键标签由`combat_stats.js`创建在当前原生`AbilityN`按钮内。普通技能按项目可见顺序映射`Q/W/E/R/T/Y/U`；工具技能按Ability身份映射`D/F/F2`，工具视觉顺序继续为`D -> F2 -> F`。快捷键分配顺序与原生面板定位是两个边界：前者消费分类后的业务可见顺序；后者必须收集当前可见且尺寸有效的原生按钮锚点，按窗口几何从左到右排序后逐一配对。引擎槽、压缩数组下标和`AbilityN`节点编号均不得互相直接推导。标签必须不参与父布局、不可命中且保持不透明；原生`HotkeyContainer`只允许透明压制并关闭命中，禁止折叠布局或隐藏整个Ability面板。
- 原生快捷键压制必须可逆：第一次压制前保存Valve容器原有`opacity/hittest/hittestchildren`，当前映射设为`opacity=0`且不可命中；标签清理、无有效选中单位或面板复用时恢复保存值。刷新签名必须同时包含当前单位、引擎槽、ability entindex、Ability名称和解析到的原生面板顺序；即使签名不变，也必须检查目标标签及原生压制状态，以恢复同ID面板重建或Valve样式回写。选择事件和Ability runtime事件用于即时触发，既有0.25秒HUD生命周期执行变化/完整性检查，原1秒技能刷新作为原生子面板晚创建兜底。
- 纯Panorama标签任务不修改业务CSV或生成Lua。自动契约和Resource Compiler只能证明静态边界与构建，最终仍需Workshop Tools冷启动验证只剩项目标签后的实际字母、面板复用及鼠标/键盘输入。

## Source 2 addon目录大小写与file-mod身份（2026-08-12）

- Game与Content下的addon物理目录必须统一使用全小写`dota_addons/survival`，并与编译资源内部file-mod身份保持一致。Windows文件访问虽然通常不区分大小写，但Source 2资产索引、ManifestResource和按需编译会区分这两个身份。
- 已复现的错误边界是物理目录`Survival`配合编译身份`dota_addons/survival`：引擎持续输出`file mod 'dota_addons/survival' is invalid`，小地图花屏，并可能阻断Panorama资源按需编译。用户在Game/Content统一改为小写`survival`后实机确认小地图恢复正常。
- 后续迁移、脚本和文档不得恢复大写`Survival`，不得通过复制、junction或并存目录创建第二个大小写身份。资源异常排查应先核对两个物理目录、编译资源ManifestResource及`tools_asset_info.bin`，再判断VTEX、VMAT或Panorama源本身。

## 玩家档案Provider、版本协议与隐私边界（2026-08-12）

- 永久档案使用稳定字符串`account_id`；Dota `player_id`只作为本局槽位，禁止成为数据库主键。正式身份可直用Steam Account ID或映射自有账号ID，但Lua协议不依赖具体方案。
- Provider只负责`resolve_account_id`和`fetch_snapshot`传输；快照/增量JSON解析、schema校验、账号绑定、revision、update_id、原子提交、权益投影和公开投影统一归`player_profile_service`。未来HTTP Provider不得复制业务校验。
- 付费权益默认失败关闭。加载开始、网络失败、非法JSON、账号错配或schema不支持时均不能继承测试默认权限；只有服务端验证通过的档案快照/增量可以原子替换`player_entitlement_service`状态。支付成功只能由后端验签后转成新权益revision。
- 完整档案只保存在Lua服务端。`survival_player_public_profiles`只能发布`player_profile_public_fields.csv`白名单，禁止发布账号、完整权益、成就、存档、库存、订单、金额、签名或token。
- 正式Supabase账号键由独立Python后端计算`HMAC-SHA256(FISHING_ACCOUNT_ID_PEPPER, Steam Account ID)`，数据库只保存64位小写十六进制假名。Python向Lua恢复当前请求的原始账号ID以维持Provider绑定协议。pepper必须长期稳定、单独备份且仅存在服务端密钥环境；普通无密钥SHA-256不足以抵抗可枚举Steam ID反查。
- 钓鱼Python API和Supabase migration位于独立`D:\survival_database`仓库；addon的`data/csv/`仍是生产配置唯一权威源，后端通过`SURVIVAL_ADDON_ROOT`读取，禁止复制第二份生产奖励CSV。
- 增量要求`base_revision == current_revision`且`revision == base_revision + 1`；`update_id`有界幂等。缺口/乱序返回`reload_required`，未知分区失败，JSON null只删除字段。旧完整快照、旧请求迟到回调和同局重复账号绑定都失败关闭。完整约定见`PLAYER_PROFILE_INTEGRATION.md`。

## 雷电塔连锁与击杀风暴边界（2026-08-11）

- `MODIFIER_EVENT_ON_DEATH`是全局事件。防御塔的击杀触发效果必须以`params.attacker == 当前塔对象`作为权威身份，不能按同队、同玩家或任意敌方死亡推断；其他塔、英雄和其他单位击杀不得触发当前塔效果。
- 闪电魔塔`lightning_storm_lv01`至`lv05`的权威触发类型为`on_kill`，含义是任意归因于该塔的伤害造成击杀。业务配置先改`tower_skill_definitions.csv`，再生成技能Lua和统一Tooltip，不得直接手改生成文件。
- 雷电风暴伤害继续把生成风暴的塔作为`damage_service`攻击者，因此风暴击杀属于该塔击杀并可继续生成风暴。修改死亡事件、伤害归因或塔代理时必须回归本塔击杀、其他单位击杀和风暴连锁三条边界。
- 闪电打击每跳范围来自技能行`area`，当前为400；从上一目标位置以`FIND_CLOSEST`查找并跳过已命中单位。不得恢复为硬编码200或以塔位置重新选目标。
- 闪电魔塔伤害倍率直接来自技能CSV的`damage_multiplier`，LV1至LV5为1.1/1.2/1.3/1.4/1.5；击杀触发栈内只查询一次死亡点500范围，并按触发瞬间塔攻击快照立即对每个目标结算一次物理伤害。每目标只发布一次`TOWER_LIGHTNING_HIT`，因此最多进行一次雷电扩散判定。
- `strike_count`只表示一秒内5/6/7/8/9道视觉雷柱。视觉点可在死亡点500半径圆内按面积均匀随机，但视觉调度不得查询敌人、造成伤害或发布命中事件；旧`damage_increment_per_strike`、`damage_multiplier_cap`和逐雷柱伤害规则已删除，不得恢复。
- 独立`lightning_diffusion_lv01`保持每个原始雷电命中独立30%判定，对目标周围200范围其他敌人造成该次伤害200%。扩散伤害必须标记为secondary且不发布`TOWER_LIGHTNING_HIT`，禁止递归扩散。

## 逐波模型资源会话与临时兼容删除边界（2026-08-11）

- 最终资源架构是`difficulty_id + wave_number + wave session`拥有独立实际模型集合。正式预载、开发跳波预载和出生`SetModel/SetOriginalModel`必须调用同一解析；任何新增模型覆盖都必须同时进入这三条路径及资源代理/VPK校验。
- 当前`monster_archetypes.normal_flying_model_path=Visage`及跨波英雄模型复用是模型尚未逐波定稿时的临时兼容。生产代码以`TODO(FINAL_WAVE_MODELS)`标记；删除条件是权威配置已为每个正式波成员提供最终模型、代理和本地资源验证，届时删除共享飞行覆盖字段、模型租约兼容及对应测试例外。
- 每波运行会话以唯一session身份保存planned/pending/alive和模型租约。出生成功单位必须回写session身份，死亡只结算所属session；生成完成且pending/alive均为0后释放会话。提前最终波、强制清场和重新初始化必须显式结束相关会话，禁止永久保存可复用entindex。
- 波次release只释放Lua层会话、租约、回调身份和项目可控的实体/附件/粒子引用。Dota Workshop Lua没有已确认安全的模型强卸载API；`asset_preload.retire()`不会卸载`.vmdl`且会阻止后续加载，因此波次系统不得调用它。`TODO(SOURCE2_MODEL_UNLOAD)`只有在Valve提供安全接口或项目采用可卸载独立资源包后才能替换。
- dev模式必须继续删除旧怪实体、附件、粒子和调度任务，避免测试堆积；但不释放模型租约、不把资源置为RETIRED。正式下一波在倒计时开始请求资源，4秒窗口只做幂等复核；urgent模型请求不等待后台塔/墙流，资源准备不得改变出怪业务时序。

## 英雄移动白名单与建筑禁建黑名单边界（2026-08-10）

- 区域权威源为`data/csv/建筑与工人系统/build_forbidden_regions.csv`。`region_type=hero_movable`定义战斗英雄可移动区域联集，`region_type=building_forbidden`定义建筑禁建黑名单；形状只允许`circle`和按边界顺序定义的凸`quadrilateral`。生成器和运行时均校验类型、坐标、正半径和凸性，禁止直接手改生成Lua。
- 只有祭坛替换产生且已写`survival_hero_id`的正式战斗英雄受移动白名单约束。Builder、伐木工、修理工、建筑、怪物和隐藏占位英雄不按`IsHero()`或队伍猜测身份，也不受英雄白名单约束。
- 英雄目的地只校验导航与`hero_movable`，不得把`building_forbidden`用于拒绝英雄移动。存在有效`hero_movable`时，建筑footprint必须完整位于区域联集内；无有效行时白名单未启用，英雄和建筑沿用既有导航与Grid规则。`building_forbidden`始终独立拒绝相交footprint，之后继续Grid边界、地形、坡度、树木、单位、占用和所有权校验。
- 英雄普通移动/攻击移动目标由项目唯一组合Order Filter提前拒绝；追击、击退和脚本位移由0.05秒生命周期守卫处理。守卫以单位对象为生命周期身份保存最后合法位置，越界时停止并精确拉回；不得永久保存可复用entindex，也不得宣称普通寻路路径全程受白名单约束。
- 祭坛、挑战、练功房等有副作用流程必须在英雄替换、怪物/目标生成和扣费前预验证目标；传送后还要验证`FindClearSpaceForUnit`产生的最终位置，失败时精确恢复原点。终极塔等建筑锚点必须校验自身footprint，不能用单位点校验替代。
- 区域策略拒绝建筑时必须返回完整footprint cells并统一标记区域错误，使Panorama仍能渲染红色Grid；不得通过提前返回空`cells`隐藏反馈。Hammer中心Marker和`challenge_locations.csv.room_radius`不能推断区域边界，获得可靠边界前不得填猜测坐标。

## 怪物尸体、详细日志与本地化性能边界（2026-08-09）

- 可安全删除的怪物必须由明确生成入口标记，不能按敌方队伍或通用单位名猜测。死亡业务继续以同步`ENGINE_ENTITY_KILLED`完成波次计数、奖励、掉落、成长和连锁技能；尸体视觉与实体删除只能在该事件栈退出后的scheduler阶段开始。强制清场可显式设置`survival_wave_cleanup`并立即删除，不进入死亡动画。
- 尸体时序来自`global_rules.csv`：当前原地保留0.6秒、0.8秒内下沉160码、共享0.05秒更新，隐藏后0.05秒安全移除。所有活动尸体共享一个scheduler任务，不为每只尸体创建永久Think；状态以单位对象为生命周期身份并在移除后释放，禁止跨生命周期永久保存entindex。
- 高频攻击、伤害和短间隔技能路径不得默认格式化并输出成功明细。`runtime_detailed_diagnostics=0`时详细日志包装器必须在`string.format()`之前返回；错误、有限次诊断、用户操作结果和低频聚合仍保留。排障时从CSV显式开启并冷启动，不在生产路径临时散落无界`print`。
- Panorama动态本地化必须在当前HUD context内使用固定上限缓存；当前四个helper最多保存256个token字符串结果，缺失token缓存为空，避免高频刷新持续请求同一无效token。Tooltip逐次SHOW、定位、映射、游标、恢复等详细日志默认关闭，仅在`SurvivalTooltipDetailedDiagnostics === true`时输出；错误、施法诊断和低频内存聚合不受影响。
- Source 2本地化token按大小写不敏感方式冲突检查。为兼容历史调用保留大小写变体时，各变体必须使用完全相同的文本；精确单位token必须同步到game侧`resource`/`resource/localization`/`panorama/localization`和content侧Panorama源。单位项目显示名仍先维护`data/csv/公共规则/unit_display_names.csv`，再定向生成对应Lua，禁止只手改生成文件。

## 同步动作结果与异步冷却事务（2026-08-09）

- 会直接决定Ability冷却是否保留的训练、建造受理、建筑升级和箭塔转职必须使用`event_bus.request/handle_request`返回结构化`{ ok = ... }`，不能依赖同栈`emit/subscribe`后观察载荷副作用。迁移期handler可继续写`payload.result`兼容旧调用者，但新调用者优先使用request返回值。
- 原生Dota Ability进入`OnSpellStart()`时引擎已处理冷却，因此同步拒绝、handler缺失或handler异常无结果时由Ability调用`EndCooldown()`；Panorama直接权威提交没有引擎施法流程，只能在同步受理成功后显式`StartCooldown()`。批量升级逐栋正式受理成功后才启动对应Ability冷却。
- 排队建造的同步成功只代表移动任务已受理，不代表建筑已创建。异步阶段必须把`source_ability`绑定到具有唯一生命周期的build task，并用幂等settled标记保证Builder死亡、位置失效、实体创建失败或施工失败等竞争路径至多回滚一次冷却。已扣费后的失败必须同时一次性退还木材、金币和人口；成功完成后清除退款与冷却上下文。
- 有限工人训练阶段按成功创建历史推进，不按当前活体数量判断。不同训练prefix和team必须拥有独立tracker；只有单位实体成功创建后记录进度。最终有限阶段达到CSV上限后保留当前tier完成快照并拒绝继续训练；`max_count=-1`表示无限阶段，永远不进入完成态。

## N1 W11–W25波次数量规则（2026-08-09）

- `wave_definitions.csv`中N1第11–25波每波`normal`普通怪总数固定为59；`wave_leader`精英每波保持1只，`assault_boss`只在W15/W20/W25各1只。59只只统计普通怪，不包含精英和进攻Boss。
- 同波存在多种普通怪时，以修改前CSV数量为比例，使用最大余数法确定性放大到59；余数相同按CSV原顺序补齐。不得改变怪种、属性、角色、生成顺序、移动类型或模型缩放来完成数量同步。
- N1仍只有25波，本N1阶段记录当时不意味着新增N1 W26–W30；其“暂不改变N2–N5波次数量”边界已由下方全难度波次数量规则覆盖。配置修改必须先改CSV，再通过`tools.build_configs.build()`生成`wave_definitions.lua`。

## 全难度波次数量规则（2026-08-09）

- 所有难度W1–W10保留各自原始普通怪数量；从W11起，每个难度中实际存在的波次普通怪总数固定为59。N1实际存在W1–W25，N2–N5实际存在W1–W30。
- 因此N2–N5 W11–W30均应为59只普通怪；当前四个W30已从原始9只统一调整为59只。`wave_leader`和`assault_boss`是独立成员，不计入59只普通怪，并保持原有数量。
- 多怪种波次以修改前普通怪数量为比例，使用最大余数法确定性分配到59；单一普通怪种直接设为59。不得借此改变怪种、属性、角色、出怪顺序、移动类型或模型缩放。
- 业务配置必须先修改`data/csv/怪物与波次系统/wave_definitions.csv`，再通过`tools.build_configs.build()`定向生成`scripts/vscripts/config/generated/wave_definitions.lua`并进行一致性校验。
- 2026-08-11批准的最终W11规则覆盖此前“纯地面15+44”临时修正：N1-N5 W11普通怪统一为`beast_green_large ×10 + skeleton_bone ×30 + flying_red_gargoyle ×19 = 59`。59只仍不包含`wave_leader`和`assault_boss`；W12及其他有明确证据的飞行波保持各自配置。

## 正式波次混合出怪、飞行模型与Hull边界（2026-08-11）

- `wave_definitions.csv.wave_id`必须全局唯一。旧成员和新成员使用同一ID同时残留时，运行时会把两行都计入波次，即使生成Lua的`by_id`只保留后者也无法消除`rows`中的重复生成。`tools/build_configs.py`必须在生成边界拒绝重复ID，并校验N1-N5中所有实际存在的W11-W30波次普通怪总数严格为59。
- N1/N3-N5工作簿导入器从现有波次抽取模板前必须按`wave_id`保留最终定义，防止中断导入或人工合并再次把旧模板与新模板叠加。业务修改仍以CSV为权威，生成Lua不得手改；数量契约必须同时检查逐波总数、W11精确组成和全表ID唯一性。
- 正式普通怪的混合出怪按移动类别调度，而不是简单遍历全部原型：地面成员先进入一个内部轮转队列，飞行成员进入另一个队列；每轮取2只地面再取1只飞行。两种地面原型时表现为`地A → 地B → 飞`；一种地面原型时表现为`地 → 地 → 飞`；即使W24有三种地面原型也仍是每2只地面后1只飞行。任一类别耗尽后必须确定性输出另一类别剩余成员，不丢怪、不重复怪。
- 飞行视觉覆盖只适用于正式波次中`member_role=normal`且最终移动类型为`flying`的成员。`monster_archetypes.csv.normal_flying_model_path`是该范围的专用模型字段，当前12个正式普通飞行原型统一使用可靠的Visage飞行模型；预载与实际`SetModel/SetOriginalModel`必须消费同一个解析结果。原`model_path`继续服务共享原型的`wave_leader`、精英、Boss、十罪和挑战怪，禁止为修普通飞行模型直接覆盖共享基础模型。
- 正式普通飞行怪基础Hull为10且保留单位碰撞；飞行领头怪、精英和Boss继续沿用Hull 0与无单位碰撞。Hull角色判断必须同时看最终移动类型和成员角色，不能只按`movement_type=flying`一刀切。`scalemonster`继续保存基础Hull身份并以该基准非累计缩放，例如先4倍得到40，再改0.5倍必须得到5而不是20。
- 自动验证必须覆盖五个难度的真实W11/W13/W24逐位置周期、类别耗尽、Hull非累计缩放、普通飞行与飞行领头怪边界、Visage模型的本地VPK/资源目录/代理预载契约、CSV与生成Lua逐字节一致性。自动测试不能替代Workshop Tools冷启动；实机仍需观察59只数量、2地+1飞视觉顺序、飞行模型及Hull 10的拥挤和阻挡表现。

## 怪物物理伤害曲线边界（2026-08-14）
## 怪物物理伤害曲线边界（2026-08-14修正）

- 怪物CSV保存War3护甲。波次、挑战和调试怪在生成边界把引擎护甲设为0，并保存自定义映射身份及基础、有效、最低War3护甲字段；固定减甲只维护War3状态，不再投影Dota护甲bonus。UI直接显示当前有效War3护甲。
- 唯一Damage Filter对全部命中明确项目怪物的物理伤害应用`X / (1 + 0.02 * max(0, A))`并追加忽略原生物理护甲flag，伤害类型仍保持物理。百分比穿甲先在War3域缩放正护甲；负护甲保留状态/UI但不增伤。魔法、纯粹和非项目怪物目标不变；禁止递归`ApplyDamage`或增加第二个Filter。
- 固定数学基准为117 War3护甲：`801 -> 239.82`、`1401 -> 419.46`。实机旧结果`801 -> 262`证明现代映射值仍被引擎护甲曲线二次结算，因此不得恢复现代映射或旧曲线补偿。自动数学测试不能替代Workshop Tools冷启动，仍需确认Filter输出等于最终扣血。
- 怪物CSV保存War3显示护甲，生成/出生边界继续通过`armor_balance.from_war3()`除以3写入Dota运行时护甲，UI继续通过`to_war3()`反向显示。当前Dota承伤曲线是`1 - 0.06A/(1+0.06|A|)`；正甲下`A=W/3`天然等于项目目标`1/(1+0.02W)`。本条覆盖2026-08-09关于当前Dota使用`0.052/0.9/0.048`曲线和需要额外补偿的旧结论。
- `war3_damage_calculator_rules.csv`是War3正甲系数、线性投影和Dota曲线常量的唯一权威源；`armor_balance.lua`必须消费对应生成配置。`from_war3_modern()`和版本化反投影作为兼容API保留并从同一规则通式求解；当前参数下正甲映射同样退化为`W/3`。
- `global_rules.csv.monster_war3_armor_damage_enabled=1`和现有Damage Filter入口继续保留以兼容开关及物理护甲无视。普通项目怪物正甲物理伤害的曲线补偿应恒为1；护甲无视补偿仍为“有效护甲承伤倍率/原护甲承伤倍率”。不得写忽略物理护甲flag、递归`ApplyDamage`或再乘完整War3减伤倍率。
- 固定高甲回归覆盖117、477、4990 War3护甲，三者普通补偿均为1。W10基准为60000生命/477护甲与单座神秘塔LV4的3801攻击、1秒普攻、1.6起始且每秒+0.05激光；生产首跳模型在`t=44`累计约60044.26伤害。仍须Workshop Tools完全冷启动确认实际约45～46秒和极高护甲引擎表现。

## 正式波次目标资源预载边界（2026-08-09）

- 正式波次首波继续依赖启动预载；后续目标波在目标倒计时开始立即进入异步资源队列，并在首只敌人计划出现前`wave_timing_rules.csv.formal_wave_preload_lead_seconds`秒（当前4秒）幂等复核。预载不得改变倒计时、首只敌人时刻、成员数量、顺序或生成间隔。
- 目标波资源必须从当前难度构建后的`wave_definitions`成员、`monster_archetypes.csv`模型和视觉CSV解析；主体模型、组件模型、粒子及已在`asset_sounds.csv`配置的音效按`resource_type:path`统一去重。空音效CSV不得填入猜测路径。
- `asset_preload_service`是正式波、开发跳波和视觉队列共享的资源去重边界。主体模型可使用`PrecacheUnitByNameAsync`代理；组件模型、粒子和音效不得因主体代理回调而被错误标记READY，必须按各自路径处理。
- 正常敌方`zombie_stream`不再后台批量加载；`tower_stream`和`wall_stream`继续保留。启动视觉预载只保留W1，练功房模型通过`asset_catalog.csv`的`initial_required`继续启动预载。
- 正式倒计时不得继承开发跳波的`dev_preloading`、READY检查、3秒缓冲或失败开放门禁。开发跳波仍保持原有3秒固定渲染缓冲和generation/settled清理策略。

## 开发跳波资源加载边界（2026-08-08）

- 正常波次依靠倒计时和上一波开始时的`queue_wave_assets()`获得下一波预载提前量；`monster<N>`/`monster <N>`属于随机跳波开发路径，不能假设此前波次已经加载目标模型。
- 开发跳波必须从当前难度生成后的波次成员读取archetype，再从生成的`monster_archetypes.lua`取得模型路径并通过CSV生成的`asset_catalog`映射到异步代理；同一模型必须去重。Lua资源READY回调不等于客户端模型已可渲染；开发跳波固定等待`wave_timing_rules.csv.dev_wave_preload_timeout_seconds`定义的完整渲染缓冲（当前3秒）后再出怪。READY只影响结束日志；FAILED、RETIRED、映射缺失或超时在缓冲结束后仅于dev路径失败开放，不得永久卡住测试。
- 开发预载门禁必须同时拥有请求generation、一次性settled身份和可取消的命名scheduler任务。快速连续输入不同波次时旧轮询不得出旧波；超时后的迟到READY状态不得二次生成。额外波次视觉继续排队，但遵循既有“视觉失败不阻断原型怪生成”边界。

## 城墙升级生命增量语义（2026-08-08）
## 运行时内存诊断与Panorama生命周期（2026-08-08）

- Dota自定义游戏中的Lua VM高水位、Panorama/V8堆和模型/显存资源池必须分开判断。`LUA Memory usage warning`跨过16 MiB不等于客户端因Lua OOM退出；文件名明确为`V8_hiting_max_memory_limit__512_MB.mdmp`的转储应优先按Panorama JS、Panel和V8闭包生命周期排查。
- 长期Panorama递归调度必须绑定当前HUD context身份。`survival_hud.xml`先加载`ui_bootstrap.js`建立`SurvivalInputLifecycleGeneration`，后续模块捕获该generation和自己的context Panel；每次调度与高频事件入口都必须同时验证generation仍为当前值且Panel有效。旧context可以暂时仍被引擎订阅持有，但不得继续安排递归任务、创建Panel或改写UI。
- 运行诊断只能保存固定大小的当前标量：pending/peak调度、累计事件、活动通知和代理Panel数量等；禁止为了诊断保留逐事件或逐波历史。Lua波次采样只读取`collectgarbage("count")`及服务当前计数，不应每波执行`collectgarbage("collect")`掩盖真实保留状态。
- Panorama短时崩溃诊断不能只依赖60秒周期采样；HUD应在启动约1秒和5秒输出固定大小早期样本，之后再按60秒低频聚合。技能、背包Tooltip等所有拥有延迟回调或NetTable/GameEvent订阅的HUD模块都必须使用同一generation/context门禁，不能只保护主HUD脚本。
- Tooltip逐次SHOW、游标祖先链、代理几何、绑定映射与恢复签名属于详细诊断，不应默认常驻构造和输出。当前统一由`SurvivalTooltipDetailedDiagnostics === true`显式开启；真正异常、施法诊断和`[SURVIVAL_MEMORY][PANORAMA]`低频聚合保持输出。
- 内存问题的自动契约和Resource Compiler只能证明门禁、计数和语法/构建成立，不能证明V8堆实际稳定。最终必须冷启动Workshop Tools运行足够长时间，比较相同阶段基线并检查是否生成新V8 heap-limit dump。

## 多选建筑批量升级语义（2026-08-08）

- HUD仍以主选中建筑技能为入口。普通建筑按相同`survival_building_id`匹配；所有箭塔以共同`survival_building_id == "arrow_tower"`匹配，不要求`survival_tower_class`相同，基础塔和各转职塔可混选并沿自身路线升级。
- 箭塔Q与W都批量：Q按下一等级费用报价，W按直升各塔当前阶段最高级的累计费用报价。协调器固定按木材、金币、entindex升序逐塔尝试，不按客户端选择顺序消费资源。
- Panorama的`Players.GetSelectedEntities()`只作为最多64个去重候选提交。服务端必须逐栋重新验证有效存活、`survival_player_id/GetPlayerOwnerID()`、建筑ID、对应Q/W Ability和可施放状态；禁止信任客户端列表直接扣费或升级。
- 只读报价必须与正式升级共享`tower_routes.stage_end_level/row_at_level/cost_to`目标和费用语义，不得扣费、启动升级或改冷却。正式提交继续复用`BUILDING_UPGRADE_REQUEST`、升级过程和`RESOURCE_TRY_SPEND_REQUEST`原子扣费。
- 每栋失败只跳过并继续后续候选，已成功开始升级的建筑不回滚；只有正式请求成功受理后才启动对应Ability冷却。防御塔转职、融合、金矿科技/自动升级、训练及其他特殊操作不得隐式批量。

## 多选金矿批量升级语义（2026-08-08）

- 金矿Q与箭塔批量升级共享“客户端候选不权威、服务端逐栋重验、权威报价排序、失败继续、成功后冷却”原则，但不能复用箭塔路线语义。金矿本体等级是每矿独立状态，Q只读取`gold_mine_config.mine_upgrade_cost(current_level)`的下一等级费用，并按木材、金币、entindex升序提交现有原子扣费与升级过程。
- 金矿W/E不是每矿独立升级，而是玩家共享的`gold_mine_efficiency/gold_mine_crit`科技。一次批量意图无论选中多少矿都只能调用一次`TECHNOLOGY_PURCHASE_NEXT_REQUEST`、购买最多1级；成功后仅对请求前通过owner/建筑/Ability/施放状态校验的候选同步冷却，失败不得冷却。禁止按矿循环购买共享科技。
- 自动升级批量操作必须传明确`enabled=true/false`目标，不得逐矿toggle导致混合状态反转。已处于目标状态的有效金矿计为幂等保持；待变更矿仍须校验对应开启/停止Ability。自动按钮刷新会立即隐藏旧Ability，因此变更成功后禁止继续操作旧Ability句柄启动冷却。
- 多座自动矿各自负责本体升级。共享科技由同一玩家所有已开启自动矿中entindex最小者协调；非协调矿不得购买共享科技，即使自身本体已满级。科技购买成功后的本地状态只消费同步`TECHNOLOGY_CHANGED`，不能再手工递增缓存造成状态漂移。

## 城墙升级生命比例语义（2026-08-08）

- 城墙等级生命值权威源仍是`building_levels.csv`。城墙升级完成提交时，必须读取提交前一瞬间的当前生命与实际最大生命，应用新等级及当前科技后的最终实际最大生命，再计算`最大生命增量=新最大生命-旧最大生命`，最终`新当前生命=旧当前生命+最大生命增量`；不得保持旧生命百分比或无条件回满。
- 该公式等价于保持已损失的固定生命值不变。例如`100/200`升级到最大生命`400`时，增量为`200`，最终为`300/400`。仍存活城墙的结果夹紧到`1..新最大生命`；升级施工期间受到的伤害必须进入提交时快照，不得在点击升级时提前锁定生命。
- 该语义仅适用于城墙。主城、农场、防御塔继续保持各自既有升级行为，不能通过全局修改`apply_common()`顺带改变其他建筑。

## 城墙固定锚点与人口训练阶段权威（2026-08-08）

- 人口训练的阶段、每阶段次数、基础费用、递增费用、人口增加和农场等级要求以`training_definitions.csv`中`enabled=true`且`training_type=population_upgrade`的行作为唯一业务权威，并按`level`排序。当前阶段1至5各`max_count=5`，阶段6为`max_count=100`且启用；不得为修复阶段加载而改写这些业务数据。
- 人口训练运行计数按team共享、按`training_id`独立保存。自动训练必须从阶段1开始，选择第一个未达到自身`max_count`的启用阶段；只有当前阶段满额后才顺序加载下一阶段。农场等级只校验当前阶段前置条件，禁止用`farm_level + 1`直接推导训练ID或跳过未完成阶段。
- 人口训练事务必须先校验当前阶段和农场等级，再按`base_cost + stage_count * increment`由资源服务扣费，之后才推进次数和增加人口。Tooltip和按钮状态消费同一个`WORKER_TRAINING_GET_REQUEST`投影，并由`WORKER_CHANGED`刷新农场Runtime。
- 城墙位置身份保存在实体`survival_fixed_position`。施工完成建立初始锚点，已有城墙恢复时补建锚点；碰撞/物理位移只恢复到当前锚点。成功主动迁移是唯一会替换锚点的常规路径，必须继续同步网格释放、重算和占用；不能用永久禁止迁移来解决自动位移。

## 第1-5波怪物视觉系统边界（2026-08-06）

- 波次怪物视觉权威源是`monster_visual_assets.csv`、`monster_visual_components.csv`、`monster_visual_effects.csv`和`wave_visual_definitions.csv`；历史`asset_catalog.csv`不承担这套新视觉业务。当前只覆盖W1-W5，11个自包含模型均由本机`pak01_dir.vpk`验证。
- 视觉按实际生成实例的`wave_number + member_role + normal_index`解析。`normal`按可配置确定性周期选择主力/辅助；`wave_leader`只映射实际领头成员的小Boss视觉；`assault_boss`映射阶段Boss并回退小Boss。视觉表不得创建成员、Boss或改变角色、数量、战斗、移动、攻击、计时字段。
- W4/W5辅助候选已配置，但普通怪主辅分布尚未获批，因此`support_every_nth=0`是当前生产边界；不得擅自恢复曾讨论的4:1。Hellbear与Smasher当前共享同一完整模型，只通过0.95/1.35缩放区分；W5阶段Boss使用1.75的Spirit Bear。
- 启动阶段通过`PrecacheResource`预载W1-W5全部视觉资源；每个独立模型在`npc_units_custom.txt`有resource-only代理，运行期下一波可通过`PrecacheUnitByNameAsync`幂等排队。附件和持续粒子必须按单位生命周期记录，重新应用、死亡和提前终局清理时立即销毁/释放；单单位粒子硬上限当前为2。
- 视觉解析或应用失败不得阻断怪物生成。运行边界保留原型模型作为最终回退，`wave_definitions.csv`与`monster_archetypes.csv`继续作为数量和战斗权威，不得为了视觉修改。

## 箭塔建造与升级成本权威边界（2026-08-05）

- 箭塔建造、基础升级、转职和七条路线升级的金币/木材权威源是`data/csv/建筑与工人系统/防御塔/`下的`arrow_tower_base.csv`和七份`tower_class_*.csv`。`upgrade_gold/upgrade_wood`表示升到该行等级实际支付的资源；基础箭塔首级行同时表示建造成本，当前为0金币、50木材。
- `building_levels.csv`不包含箭塔等级，不能用`build_cost("building_arrow_tower", ...)`读取箭塔建造费，也不能保留另一份手写业务回退。`buildings_config.lua`必须从生成的`arrow_tower_base.lua`首级行投影`arrow_tower.build_cost`；`building_system.lua`服务端扣费和`ability_runtime_builder.lua`UI费用都消费该对象。
- 2026-08-05提供的工作簿7条路线各25个成本节点，共175个节点，已与现有塔CSV逐项核对且完全一致；只有旧建造适配层的80木材+20金币回退错误，升级CSV不应随该修复改动。

## 防御塔基础射程与弹速倍率（2026-08-05）

- 所有防御塔的基础攻击距离、基础索敌距离、基础箭塔原始弹速、无独立字段转职塔默认弹速和全局弹速倍率权威源是`data/csv/公共规则/global_rules.csv`。当前值分别为1000、1000、5000、1250和1；基础箭塔最终弹速为5000。`config/global_rules.lua`只负责投影生成配置，基础箭塔单位KV只保留创建首帧回退。
- 防御塔射程科技继续在基础1000上加算，实际攻击距离为`1000 + attack_range_bonus`；索敌距离必须至少覆盖实际攻击距离。不得把“基础射程1000”误解为封顶1000。
- 弹速投影必须保存原始弹速身份并保持幂等：路线显式弹速使用CSV值，缺失时只在首次应用读取引擎基础弹速；最终弹速为原始弹速乘全局倍率。升级、科技刷新和热重载不得读取已经翻倍的运行值再次乘倍率。
- 基础箭塔与转职塔弹速必须分开解析：基础LV1-LV5使用`tower_base_projectile_speed=5000`；无独立字段的神秘/机枪/多重/对空路线转职后使用`tower_route_default_projectile_speed=1250`；死亡/冰霜/闪电使用路线CSV的100000。终极融合塔七路代理继承来源塔最终弹速，不得在融合边界再次乘倍率；神秘激光路线最终切换近战式结算。

## N1最新工作簿同步规则（2026-08-05）

- N1与N2-N5数量结构不同：N1权威工作簿是25波，普通怪202、首怪Boss21、进攻Boss5，总计划228；不得套用N2-N5的30波/1303模板。
- N1波次在`wave_definitions.csv`中使用直接难度成员及`normal`、`wave_leader`、`assault_boss`身份。W5起首怪独立于普通怪，W5/10/15/20/25的进攻Boss也独立计数；运行排序保持首怪、普通、进攻Boss。
- N1工作簿小怪主表是同波三项最低权威值，三项不要求来自同一模型。若明细没有完整的模型与数量映射，不得猜测拆成运行变体；CSV按主表最低值驱动，明细仅作证据。
- 当前N1 Profile关键值：十转Boss为生命840400000、攻击37040396、War3护甲340；十戒10为生命140200000、攻击10000000、War3护甲1400。工作簿未列`seven_sins_minion`，继续保持此前批准值18209920/1200000/400。

## 初始资源与资源树伐木收益边界（2026-08-05）

- 队伍开局金币、木材、已用人口和人口上限的权威源是`data/csv/公共规则/global_rules.csv`，由生成的`global_rules.lua`经`config/global_rules.lua`投影到`config/resources_config.lua`。当前值为金币0、木材10、人口0/0；不得恢复为`resources_config.lua`手写业务初值。
- 农民各等级基础伐木效率权威源仍是`training_definitions.csv.wood_per_hit`，当前LV1至LV8为`1/2/3/5/10/20/40/80`。科技收益在`modifier_lumberjack_ai`中并入基础命中载荷，资源树等级收益在`tree_system.lua`统一追加，不能把两者再写回训练基础值。
- 资源树等级收益语义是“从LV2起每级+1”，公式为`max(0, tree_level - 1) * tree_lumber_efficiency_buff_per_level`。资源树LV1必须为额外+0，否则所有农民和英雄采集会从开局整体多1；LV2为+1、LV3为+2。每级值与英雄基础伐木收益也来自`global_rules.csv`。

## 范围拾取与Builder建造技能的跨层边界（2026-08-05）

- 召唤英雄工具技能`ability_survival_pickup_materials`固定由F触发；物品拾取必须保留现有玩家所有权过滤、二维距离排序、同距离entindex稳定排序、装备栏`0..8`容量检查和满栏立即停止。真实地面物品继续通过`AddItem`进入既有Claim/逻辑库存/防复制链，虚拟升阶材料继续走自身服务，不能为了范围拾取直接删除实体或手写库存发放。
- “范围拾取”存在两个不同几何概念，必须分别建模和测试：英雄到鼠标目标点的最大施法距离，以及鼠标点周围的拾取AOE半径。Ability KV/运行Ability必须是点目标并提供AOE预览，服务端搜索函数必须显式接收目标位置；如果仍使用`caster:GetAbsOrigin()`，即使UI显示AOE也只是错误视觉。当前用户目标口径为施法距离1000、目标点AOE半径300。
- Builder技能槽位以`data/csv/建筑与工人系统/builder_ability_stages.csv`为权威：`slot_order=1`映射Ability index 0/Q；城墙完成后主城替换同一Q链，主城完成后再展开五个建造槽，D闪烁固定index 5。不得把旧`builder_ability_rules.csv`或Ability自然添加顺序当成槽位权威。
- 施工时间以`building_construction_rules.csv::build_time`为业务来源。若技能CD用于表现施工期，CD必须绑定“本次施法的具体Ability实例”和该建筑施工事务，失败/取消时恢复，完成时自然结束或校正；不能用Builder全局锁阻止其他建筑，也不能只修改KV固定CD而与CSV施工时间漂移。专项测试至少要覆盖当前技能施工中不可再次使用、其他建造技能仍可使用、失败不残留CD、多个建筑并行施工互不覆盖。
- 用户对本任务的当前反馈是“基本完成”，不是逐项实机验收声明。当前仓库可确认F归属、旧英雄圆心300拾取、满栏停止及城墙/主城Q槽位；点目标1000/300 AOE和施工期独立CD仍需在继续工作前核对实际运行分支与产物。

## N2工作簿同步边界（2026-08-05）

- `N2按最新波次总表同步(1).xlsx`覆盖波次、练功房、特殊Boss/材料怪、转生Boss、十戒Boss及尚未接入的存档挑战。当前实施只同步游戏已经存在的内容；“存档挑战独立表”在缺少现有遭遇、模型、地点、入口和奖励链时明确忽略，不能据名称自行创建玩法。
- N2必须使用`wave_definitions.csv`中的完整30波直接数据，不再从N1倍率派生。目标总数与N3-N5一致：普通怪1270、`wave_leader`27、`assault_boss`6、总计划1303。
- `wave_id`是唯一行身份但不是运行时波次分组或角色判断的业务键。已有N1旧格式与N3-N5角色格式不为可读性批量迁移；新增N2使用现行角色格式，并通过契约保证唯一性及难度、波次、角色一致。

## 挑战战斗Profile与难度快照（2026-08-05）

- `data/csv/挑战与奖励系统/challenge_combat_profiles.csv`是练功房、特殊目标、转生Boss及十戒Boss的难度战斗数值权威源，键为`difficulty_id + member_id`；当前覆盖30个目标×N1-N5=150条。模型、移动速度、射程、攻速和奖励仍由现有成员/怪物原型控制，Profile只覆盖生命、攻击和War3护甲。
- 挑战遭遇创建时通过`WAVE_STATE_GET_REQUEST`读取`wave_system`当前`difficulty_id`并写入session；维持数量和死亡刷新都继续调用`spawn_member(session, member)`，因此必须沿用session快照，不能在刷新时重新读取可能变化的全局状态。纯Lua启动阶段尚未注册波次handler时只回退`difficulty_config.default_id`；handler存在但状态异常仍失败关闭。
- Profile表中不存在的成员继续使用怪物原型战斗值；成员一旦进入Profile表，该难度缺行必须返回`challenge_combat_profile_missing:<member>:<difficulty>`并在session生成任何单位前失败，禁止静默回退N1或生成部分遭遇。
- CSV存储War3护甲，`challenge_session_service.apply_combat_stats()`仅在单位生成边界调用一次`armor_balance.from_war3()`。不得把Profile生成Lua预先除3，也不得让UI或刷新链重复换算。
- 已确认特殊目标成员映射：合成宝石=`challenge_05_boss`、冰之幽魂=`challenge_06_ice_wraith`、熔火核心小怪=`challenge_07_molten_minion`、火焰巨魔=`challenge_08_boss`、冰烬挽歌=`challenge_09_boss`、精华小怪=`seven_sins_minion`。N1七宗罪按用户批准沿用生命18209920、攻击1200000、War3护甲400；N5木头怪生命按截图原值15000保留。

## N3-N5独立波次导入与难度选择（2026-08-05）

- `data/csv/怪物与波次系统/wave_definitions.csv`是N2-N5波次成员的运行权威源。N2-N5各自拥有30波直接数据，每个难度均为普通怪1270、`wave_leader`27、`assault_boss`6，总计划1303；完整直接CSV存在时`wave_difficulty_builder`不得回退到N1倍率派生。
- N2-N5使用同一已批准模型规则：1-25波沿用N1同波模型，26-30波依次沿用N1第21-25波模型；同波混合模型按N1来源数量比例使用最大余数法确定性分配。工作簿要求飞行但来源波没有飞行原型时使用`flying_red_gargoyle`；普通飞行怪使用该波普通War3基准护甲3倍，领头怪和进攻Boss使用各自工作簿护甲。
- `tools/import_n3_wave_workbook.py`保留旧N3默认入口，并通过`--difficulty N2|N3|N4|N5`定向重写单一难度。导入必须从对应`N*波次总表`读取30波，保留属性、飞行和对齐证据到CSV备注，不直接修改生成Lua。
- 难度选项由`config/difficulty_config.lua::client_options()`按N1-N5顺序发布。Panorama难度卡只显示`display_name`和`subtitle/total_waves`，不创建描述Label；当前固定为五格横向一排，每格228x72、间距12px、弹窗宽1280px。修改后必须强制定向编译`survival_ui.js`和`survival_hud.css`。

## 深渊审判主攻击焰爆装备触发（2026-08-05）

- 传说：深渊审判`weapon_legend_abyss_00`至`weapon_legend_abyss_10`的焰爆配置统一为主攻击命中时10%概率、佩戴英雄周围500范围、逻辑全属性总和×50魔法伤害。用户已确认当前实机行为没有问题，本任务完成；不得恢复为以受击目标为中心，也不得改回Dota原生`GetStrength/GetAgility/GetIntellect`。
- 攻击触发边界使用`HERO_MAIN_ATTACK_LANDED`，而不是同时包含主攻击和次级攻击的兼容事件`WEAPON_ATTACK_LANDED`。上游攻击追踪器只为非次级攻击发布主攻击事件，消费服务仍必须防御性拒绝`is_main_attack=false`或`is_multishot_secondary=true`，保证多重攻击、分身次级箭和其他派生攻击不额外掷骰。
- 每次有效主攻击只进行一次概率判定。去重优先使用攻击追踪器生成的`attack_id`，不能把裸Dota record当作整局唯一身份；record会循环复用。最近攻击去重集合必须有界，避免长局随攻击次数无限增长。
- 按全属性结算的装备效果在触发时请求`HERO_COMBAT_STATS_GET_REQUEST`，从同一权威快照读取`strength/agility/intellect`并现场求和。该口径自然包含装备和永久成长；不得从引擎原生三维拼装，也不得提前缓存一份会落后于成长事件的属性值。
- AoE中心是佩戴英雄触发瞬间的`GetAbsOrigin()`，范围查询只负责返回500内敌方英雄和普通单位；每个目标分别进入`combat_events.DEAL_REQUEST`，保持`DAMAGE_TYPE_MAGICAL`、`can_crit=false`和`equipment_proc`标签。调用方必须逐目标检查`result.success`并汇总`blocked_reason`，不能因部分事务失败而伪报全部成功。
- 焰爆表现使用已预缓存的`warlock_rain_of_chaos_explosion.vpcf`和`Hero_Warlock.RainOfChaos`，在佩戴英雄位置每次成功触发只播放一次。粒子和声音通过`pcall`与权威伤害隔离；视觉失败不能阻断范围伤害，视觉粒子也不能承担命中判定。
- 诊断使用有界`[EQUIPMENT_FLAME_BURST]`日志，包含玩家、record、装备阶段、三维、总属性、倍率、计算伤害、半径、目标数、成功数和失败原因。最小回归矩阵覆盖全部11阶配置、佩戴/未佩戴、概率通过/失败、同次攻击去重、record复用、旧事件与次级攻击隔离、权威属性公式、佩戴者中心500范围、逐目标魔法事务及单次粒子/声音。

## 击杀成长事件与UI权威进度（2026-08-05）

- 极寒之刃`valid_enemy_kill_count`的唯一权威输入是`ENGINE_ENTITY_KILLED`。不得同时订阅派生`MONSTER_KILLED`后再用victim entindex做跨整局去重；Dota会在旧单位移除后复用entindex，新敌人的合法死亡会因此被永久忽略。用户已在Workshop Tools确认修复成功。
- 攻击归属从attacker开始沿最多8层`GetOwnerEntity()`解析，优先读取业务显式`survival_player_id`，再读取有效`GetPlayerOwnerID()`，并用实体集合阻止owner循环。友军判断优先使用`PlayerResource:GetTeam(player_id)`，避免中立team的thinker或damage proxy绕过过滤；真实英雄、建筑和无法归属玩家的死亡不计数。
- 极寒实际进度保存在`EQUIPMENT_GROWTH_GET_REQUEST.progress[content_id]`；通用`WEAPON_GROWTH_GET_REQUEST`不负责该击杀计数。`weapon_synthesis_snapshot_service.lua`必须在发布边界把实际值投影为标准`growth.stage_attack_count`，从生成武器CSV读取target（无有效值统一回退200），并现场计算remaining。`survival_weapon_growth`、`survival_weapon_snapshot.growth`和Tooltip ViewModel必须消费同一投影。
- Panorama现有NetTable订阅已经是事件驱动；批量击杀同帧内多次服务端写入时，客户端只呈现最终累计快照是正确行为。不要增加高频轮询来解决服务端计数丢失或状态源分裂。
- 最小回归矩阵必须覆盖：派生怪物事件不二次计数；新敌人复用entindex仍计数；多层召唤/伤害代理归属；友军、英雄、建筑、无owner和循环owner不计数；批量达到阈值后正确结转升级；CSV目标与200回退；物品charges、Tooltip与HUD的count/target/remaining一致。

## 科技研究两阶段事务与进度UI（2026-08-04）

- 普通研究科技不是“购买成功后附带2秒冷却”，而是服务端权威的两阶段事务。`research_technology_service.lua::BeginUpgrade()`负责完整校验并通过`RESOURCE_TRY_SPEND_REQUEST`立即扣除金币/木材，然后创建一次性`pending_transactions[transaction_id]`；此阶段不得写入科技等级、重算效果、发布`LEVEL_CHANGED/EFFECTS_CHANGED`或提示研究完成。
- `shop_system.lua`是2秒研究流程协调器，不是等级权威。它在Begin成功后按队伍保存唯一活动事务和进度来源，向同队已打开研究页的玩家推送进度，并拒绝所有队友开始另一项普通研究。计时结束只携带服务端生成的`transaction_id`请求Commit，不由客户端提交目标等级、费用或完成状态。
- `CommitUpgrade()`在处理前先移除pending事务，使迟到或重复回调得到`research_transaction_not_found`而不能二次升级。提交前必须确认当前等级仍等于Begin快照；随后将等级提升和`effects:Recalculate()`视为同一提交单元。等级漂移、等级写入异常或效果重算异常时恢复旧等级、重新计算旧效果并退还Begin阶段已扣资源；只有成功提交后才发布等级/效果事件、同步客户端并提示“已完成研究”。
- `RollbackUpgrade()`用于计时任务无法取得Commit响应或流程被显式取消时释放一次性事务并退款。商店完成回调无论成功失败都必须清除队伍活动事务、进度截止时间和来源字段；成功后才写`purchased_count`。不能通过只延迟成功提示来伪造研究耗时，否则等级和效果仍会提前生效。
- 为降低现有快照、增量补丁和Panorama协议的改动风险，`technology_cooldown_remaining/total/until/source_group/source_entry/sequence`字段名暂时保留，但其业务语义统一为“团队科技研究进度”。新代码不得按购买后冷却理解这些字段，也不得在进度期间允许同队研究其他科技。
- Panorama只表现服务端进度：购买响应显示“已开始研究”，径向遮罩只覆盖`technology_cooldown_source_group`对应卡片，其他科技因团队研究锁不可点击。中央秒数Label、`Math.ceil(remaining)`和对应CSS已删除；不要用客户端倒计时归零直接升级或显示完成，完成状态必须来自新的服务端快照/通知。
- 兼容入口`RequestUpgrade()`仍保留Begin后立即Commit的同步语义，供未迁移的内部调用使用；研究商店必须明确调用`UPGRADE_BEGIN_REQUESTED`与`UPGRADE_COMMIT_REQUESTED`。以后扩展研究取消、建筑销毁中断或断线恢复时，应围绕服务端事务生命周期扩展，不能绕回客户端延时后发起一次普通购买。
- 最小回归矩阵必须覆盖：Begin立即扣费但等级/效果不变；2秒后仅提交一次；同队第二玩家被拒；完成前无成功提示；Rollback退款；效果提交异常恢复等级并退款；重复完成回调幂等；径向动画存在且无数字；完整/增量快照都保留研究来源和sequence。专项Lua测试和静态Panorama契约不能替代Workshop Tools中的真实计时、团队同步和最终视觉验收。

## Panorama 输入生命周期与 Ability caster（2026-08-04）

- Grid validate 的错误响应必须保留原请求身份和原请求坐标锚点。服务端即使在 caster、Ability、profile 或参数校验阶段提前失败，也必须回传 `session_id/request_id/ability_name/request_anchor_x/request_anchor_y/error`；客户端按这些请求字段拒绝过期响应，不能用仅在几何校验成功后才存在的结果 anchor 过滤错误，否则 UI 会永久停在“正在验证建筑占地……”。Grid 诊断按 Begin、请求、响应和拒绝原因输出，不在无请求时逐帧刷屏。
- 开局引擎主英雄占位符不能只用 `AddNoDraw()` 隐藏；必须同时隐藏其 `dota_item_wearable` 子实体、取消玩家控制、禁攻并移出可见区域，而且隔离函数只能在明确的 `placeholder` 生命周期执行。英雄替换失败回滚到 `placeholder` 时必须重新隔离；提交 `combat_ready` 后禁止再对正式英雄执行。
- Builder 快捷键的单位身份不得直接取 `GetLocalPlayerPortraitUnit()`。服务端应发布 CSV 定义的 Builder entindex；客户端统一解析实际 `Players.GetSelectedEntities()`、Portrait 和权威 Builder。当实际选中 Builder 而 Portrait 仍为占位 Undying 时必须选择 Builder；建筑、工人和正式英雄选择不得被永久覆盖。点击和快捷键必须调用同一选择解析器后再枚举 Ability。
- HUD展示身份与可控输入身份必须分离。敌方单位和树木可成为`GetLocalPlayerPortraitUnit()`，但不会进入玩家的`GetSelectedEntities()`；属性、名称、等级、生命和选中单位快照链必须使用`ResolveDisplayUnit()`接受有效非占位portrait，技能枚举、快捷键、Grid和建筑移动必须继续使用`Resolve()`可控身份。不得为了修复敌方属性刷新而让query portrait成为Ability caster，也不得用可控集合过滤HUD portrait。
- `GameUI.CustomUIConfig()` 会跨 Workshop Tools Run 保留字段，但旧 Panorama context 的 JS callback 已失效。不得用持久化的 `SurvivalKeyDispatcherBound/SurvivalMouseDispatcherBound` boolean 跳过新 HUD 绑定，也不得让多个脚本分别调用全局 `SetKeyPressedCallback/SetMouseCallback/CreateCustomKeyBind`。唯一全局所有者是最早加载的 `ui_bootstrap.js`：每次 HUD generation 建立新 handler map、无条件替换 callback，并创建带 generation 的 fallback commands；业务模块只按稳定 ID 和优先级注册。
- 托管 Ability 输入必须先确定 Ability entindex，再读取 `survival_ability_runtime[ability_entindex].owner_entindex`，并验证该单位槽位中确实存在同一 Ability。该 owner 是 Builder、建筑升级/训练/祭坛/金矿动作的 caster；Portrait Unit/玩家英雄只能用于普通英雄 Ability fallback，不能覆盖有效 runtime owner。
- 鼠标与快捷键必须调用同一个 `SurvivalAbilityInput.ExecuteAbility()`。`ability_build_*` 与 runtime owner 为 `building_*` 的普通单位 Ability 需要官方 AbilityN 上的透明代理；建造技能不能回退原生点目标，否则会绕过项目 Grid validation/commit。
- 点目标/Grid 会话必须在 Begin 时固定 caster entindex、Ability entindex/name 和 session id；活动期间不得逐帧从 `GetLocalPlayerPortraitUnit()` 重算 Builder。建筑移动 D 的高优先级 handler 只在当前选中建筑可移动或已进入移动状态时消费，否则 D 继续交给 Builder Blink。
- `npc_survival_builder_proxy` 和项目建筑是普通 creature，`GetPlayerOwnerID()` 不能作为业务 ownership 权威。Builder 必须由 `builder_service` 注册表按玩家和实体双向校验，并把权威 ID 写入 `survival_player_id`；Grid、建造提交和建筑托管 Ability 路由读取该身份。引擎 `SetPlayerID/SetOwner/SetControllableByPlayer` 仍用于控制表现，但不能替代业务注册身份。
- Builder 建造技能顺序来自 `data/csv/建筑与工人系统/builder_ability_stages.csv::slot_order`，运行时必须显式投影为 Ability index `slot_order - 1`。当前设计为五个建造技能 index `0..4`，项目输入 Q/W/E/R/T；Builder Blink 使用独立 index `5` 并按名称路由 D，不能再依赖 `AddAbility()` 自动排列。
- Panorama技能栏不得用包含工具技能的稠密可见序号直接分配Q/W/E/R/T/Y/U。应先按实体槽位收集可见Ability，再分为普通技能和按名称路由的工具技能；普通技能保持原顺序并独占普通快捷键索引，工具技能稳定追加到尾部。当前固定尾部优先级为Builder Blink D、正式英雄回城F2、正式英雄拾取F；Builder只拥有Blink，因此D是最后一位，正式英雄最后两位固定为回城F2、拾取F。HUD代理顺序、左上角标签、官方槽运行时定位和键盘输入必须共用该分类规则。
- `MODIFIER_STATE_UNSELECTABLE`不能保证 Valve 默认“选择主英雄”命令不选中引擎占位英雄。项目的空格输入由`ui_bootstrap.js`唯一输入所有者接管：`Players.GetPlayerHeroEntityIndex()`仍为`npc_dota_hero_undying`时选择`survival_builder_identity`发布的CSV Builder；正式替换后选择实际英雄。Builder身份尚未发布时也必须消费空格，不能让默认命令穿透到占位锚点；禁止用永久`SetOverrideSelectionEntity`或轮询纠正选择。
- 自定义`SPACE`覆盖Valve默认主英雄命令时，`GameUI.SelectUnit()`只复刻选择，不会自动定位镜头。空格定位优先使用Dota Panorama的`MoveCameraToEntity(target)`，该API按声明移动到实体但不锁定；API缺失或异常时才用`Entities.GetAbsOrigin(target)`和`SetCameraTargetPosition(position, 0.0)`兼容回退。当前客户端实机证明后者即使`flLerp=0.0`仍会慢速插值，不能再描述为瞬移。`SetCameraLookAtPosition`也已被实机否定，禁止恢复。
- 挑战传送禁止使用`SetCameraTarget(hero)`再`SetCameraTarget(-1)`的临时锁定链；当前客户端实机证明解除目标会恢复锁定前自由镜头锚点，即英雄传送前消失位置。挑战购买成功后应一次性调用`MoveCameraToEntity(hero)`非锁定聚焦，API缺失或异常时才使用服务端从`challenge_locations.csv`入口投影的坐标调用`SetCameraTargetPosition(position, 0.0)`。共享控制器缺失的`shop_ui.js` fallback必须保持相同非锁定语义。
- Panorama `$.Msg()`不等于Workshop Tools服务端日志。需要用户从普通服务端控制台核对的客户端输入/镜头诊断，应通过白名单CustomGameEvent镜像到Lua，并使用事件注入的`PlayerID`、控制字符清理和字段长度限制；当前统一前缀为`[SURVIVAL_CLIENT_DIAGNOSTIC]`。

## 英雄普通攻击最终伤害飘字（2026-08-04）

- 召唤英雄伤害飘字以`OnTakeDamage.params.damage`为唯一数值口径，该值已经过引擎护甲与项目最终伤害层结算。普通攻击使用原生`OVERHEAD_ALERT_BONUS_SPELL_DAMAGE`，暴击使用原生`OVERHEAD_ALERT_CRITICAL`，带有效Ability inflictor的正式技能伤害使用红色`OVERHEAD_ALERT_DAMAGE`；无Ability的脚本或装备附伤不显示为技能伤害。暴击身份按`attacker + record`保存到record销毁，普通攻击显示再按victim去重。不得恢复会额外显示减甲前数值的英雄`MODIFIER_PROPERTY_PREATTACK_CRITICALSTRIKE`。
- 用户已在Workshop Tools确认上述原生伤害显示方案完成。当前客户端中`OVERHEAD_ALERT_BONUS_SPELL_DAMAGE`可作为普通攻击白字，`OVERHEAD_ALERT_CRITICAL`保留原生暴击表现，`OVERHEAD_ALERT_DAMAGE`用于技能红字强调。以后调整飘字必须继续使用最终伤害、避免同一命中重复显示，并区分静态枚举契约与客户端实际视觉。
- 攻击触发的额外技能伤害若要进入技能红字路径，统一伤害请求必须携带对应Ability，使`OnTakeDamage.params.inflictor`有效；不能把所有`ability=nil`脚本伤害都标为技能，否则装备光环等兼容伤害会被误报。
- 无尽训练目标的`data/csv/商店系统/altar_actions.csv::target_armor=100000`是生成请求权威值；Dota引擎可能将最终有效护甲约束到约千点，普通选中单位UI应继续读取`GetPhysicalArmorValue(false)`并投影为War3显示值，不得用CSV请求值覆盖运行时有效护甲。

## Attack record lifecycle

- Dota attack record 数值会在长时间或高攻速攻击后循环复用，不能把裸record当作进程生命周期内永久唯一ID。record级状态至少要包含攻击者身份，并在每次`ON_ATTACK_RECORD`建立新一代时重置同键的上一代短期状态。
- 实机不能假设`MODIFIER_PROPERTY_DAMAGEOUTGOING_PERCENTAGE`回调参数包含attack record；需要record级判定时应在`MODIFIER_EVENT_ON_ATTACK_RECORD`建立状态，getter只消费已经建立的本次攻击倍率。最终命中身份继续由`OnTakeDamage.params.record`关联，并在`ON_ATTACK_RECORD_DESTROY`清理。
- 需要与最终伤害使用同一暴击身份的攻击触发效果，必须在`OnTakeDamage`仍持有有效`attacker + record`状态时完成判断和发布，不得延迟到`OnAttackLanded`再次读取该record。齐天大圣E已采用`HERO_FINAL_CRITICAL_ATTACK_DAMAGE`：在最终攻击伤害按`record + victim`去重并排除次级攻击后发布，本体E再读取触发瞬间逻辑三维并提交全属性×5纯粹伤害。
- 用户于2026-08-04在Workshop Tools确认修复后的齐天大圣E数据正常：本体主普通攻击暴击能够触发独立的全属性×5额外伤害。伤害请求必须携带`ability_survival_monkey_king_swiftness`并检查统一伤害事务`result.success`；不得恢复旧的`HERO_MAIN_ATTACK_LANDED.critical`延迟消费路径。

## 复合生成科技效果（2026-08-04）

- `researcher_super_tower_crit` 的权威等级、成本、累计百分比和 Tooltip 文案来自 `data/csv/建筑与工人系统/technology_definitions.csv`；每级累计值是 `level × 0.5%`，说明必须同时列出防御塔暴击、防御塔攻击、召唤英雄暴击和召唤英雄攻击四项。
- 该科技在 CSV 中保留单一 `effect_type=super_tower_crit_pct`，四项派生由 `technology_stat_manager.lua` 统一完成。不得为此另建塔 Buff、英雄 Buff 或自定义伤害链。
- 塔属性由 `building_upgrade_system.lua` 在 `TECHNOLOGY_STATS_CHANGED` 后刷新，暴击由 `modifier_tower_attack_effects.lua` 结算；英雄属性由 `hero_combat_stat_service.lua` 同事件刷新，暴击由 `modifier_weapon_stat_projection.lua` 按 attack record 结算。
- CSV 引号字段可包含 Tooltip 换行；`tools/build_configs.py` 必须使用 `splitlines(keepends=True)` 交给 `csv.reader`，否则字段内换行会被静默删除并导致生成 Tooltip 四段文字粘连。

## Lua模块加载故障排查（2026-08-03）

- Dota日志中的`module not found`至少有两类根因，必须先分类，不能直接修改`package.path`或注释`require`：
  - **模块真实缺失**：调用方新增了静态`require`，但目标`.lua`没有进入工作区或Git。`building_upgrade_process.lua`即属于此类；提交`85ce4eb`加入调用却漏提交文件。
  - **目标模块编译失败**：文件存在，但Lua 5.1语法、200个活跃local上限、非法字节等问题使`require`失败，Dota同时显示`module not found`。`hero_passive_skill_service.lua`超过顶层local上限即属于此类。
- 固定排查顺序：
  1. 将模块名映射为`scripts/vscripts`下的实际文件路径，检查大小写和文件是否存在；
  2. 执行`git ls-files`确认文件是否被跟踪，再用`git log --all --full-history`和`git rev-list --all --objects`确认是否曾存在；
  3. 完整阅读`module not found`之后的诊断，查找目标文件编译错误；
  4. 使用项目指定的`luac5.1 -p`检查目标模块、直接调用方和`addon_game_mode.lua`；
  5. 扫描新增的静态`require("...")`目标是否全部存在，动态拼接的`require`必须单独按生成配置核对；
  6. 补齐目标模块的接口契约和行为测试，不得通过注释`require`、返回空表或跳过初始化临时解除报错；
  7. 完全停止并重新Run Workshop Tools。静态检查和Lua模拟通过不等于引擎启动验证通过。
- 新增模块的提交必须同时包含：模块文件、调用方、相关测试和必要文档。提交前至少检查`git status --short`、静态require解析、Lua 5.1语法和限定`git diff --check`。

## Lua 5.1顶层local上限（2026-08-03）

- Lua 5.1单个函数（包括模块主chunk）最多允许200个活跃local；`hero_passive_skill_service.lua`曾在第201个声明处编译失败，使Dota把真实编译错误包装成`module not found`并阻断`addon_game_mode.lua`加载。
- 该服务末尾的内部入口使用既有模块表`M._trigger/M._roll/M._on_main_attack`保存，不再占用顶层local槽；当前源码顶层声明为199。后续增加公共技能函数前必须运行`luac5.1 -p`，不能只依赖较新Lua版本或把首行`module not found`误判为路径问题。

## 世界、工人和普通建筑分级模型配置（2026-08-03）

- 资源树视觉权威源是`data/csv/资源系统/world_visual_definitions.csv`，由`config/tree_config.lua`读取生成表并由`tree_system.lua`应用；单位KV只保留首帧/异常回退。
- 伐木工和修理工分级模型直接使用`training_definitions.csv.model_name`，`worker_system.lua`在具体训练行创建实体后统一应用。不要为工人另建重复等级视觉表。
- 主城、召唤祭坛、研究所、农场与金矿的普通建筑视觉权威源是`building_visual_levels.csv`。普通建筑由`buildings_config.lua`按`building_id+level`合并到战斗等级数据；金矿使用独立`gold_mine_system`升级链，因此`gold_mine_config.level_data()`必须把金矿固定视觉行投影到全部等级。两条提交链最终均复用`building_visual_service.apply()`。
- 项目创建的模型组件统一由`visual/model_appearance_service.lua`管理实体句柄；`Apply/Refresh`先清理旧组件，任一声明组件创建或绑定失败时清理本轮部分结果并返回失败，`Clear`负责死亡和删除生命周期。组件路径继续以`asset_components.csv`为权威，预载继续复用`asset_preload_service`；成功明细仅在`survival_model_appearance_debug=1`时输出。
- 普通建筑视觉表可直接使用`model_name/model_scale/model_yaw`，不强制进入复杂塔套装的`asset_catalog.csv`。当前`asset_catalog.csv`存在27列表头与大量22列历史行不一致，未修复前不得为普通模型任务强行生成或批量补列。
- 新增分级模型必须同步：CSV、生成Lua、运行时消费者、模型预缓存和单位KV的LV1回退；模型路径需从当前`pak01_dir.vpk`索引确认，自动验证不能代替Workshop Tools中的尺寸、动画和朝向验收。
- 当前Dota不包含`models/heroes/tiny/tiny.vmdl_c`；基础Tiny有效主体是`models/heroes/tiny/tiny_01/tiny_01.vmdl_c`。W18/W19灰色傀儡、九转Boss、`monster_tiny`资产和`asset_proxy_monster_tiny`必须保持该路径一致。异步预载READY回调不能作为路径存在或客户端可渲染的证据。
- 研究所、人口农场与金矿的视觉权威值现与英雄祭坛一致，均使用`radiant_ancient001.vmdl`、`model_scale=0.34`；施工规则和单位KV首帧回退也必须保持0.34。金矿使用该模型是为了提供可靠的单位选择命中边界；`selectable=true`和建筑Hull不能为缺少选择hitbox的静态模型补出可靠鼠标命中。金矿LV1视觉是全部金矿等级的固定视觉，手动和自动升级提交必须重新投影模型、缩放和朝向，禁止因等级行缺少`model_scale`恢复原始尺寸。
- Builder数量上限以`builder_ability_stages.csv.max_building_count`控制Ability存在性：达到上限应移除技能，建筑销毁释放容量后恢复；等级不足或其他非数量条件仍保持置灰。底层`buildings_config`的`max_count`必须与CSV一致，不能只修UI层。
- 城墙Hull调试命令只允许当前玩家注册拥有的选中城墙；`scale 1`使用建筑定义中的基础Hull（当前256），倍率不得基于上次结果累乘，也不得调用模型缩放。
- 波次怪共用单位KV保留原生`DOTA_HULL_SIZE_SMALL`；`scalemonster <倍数>`只用于调试Hull，以每只怪首次`GetHullRadius()`结果为不累乘基准，同时更新当前存活怪与之后生成怪，倍率1恢复原生Hull。该命令不得改变怪物模型、战斗CSV或波次数值，地图重新初始化后倍率恢复1。
- 工人攻击距离使用`training_definitions.csv.attack_range`。伐木工当前统一为每秒0.5次、400射程、远程能力和空自定义弹道；修理工虽然同样投影400距离，但稳定身份仍是纯修理单位，运行时和KV必须保持`NO_ATTACK`。修理距离由独立的`repair_range`控制，当前两级均为200，并按修理工与建筑碰撞体边缘间距判断，边缘间距小于等于200时可修理。

## 英雄转生多目标普通攻击（2026-08-03）

- `reward_effects.csv`是转生多目标数权威源：一转解锁并把总目标数设为3，二/三/四转依次增加到4/5/6，五转以后不再增加；`hero_progression_system`同时封顶6以防旧存档或异常奖励越界。
- 总目标数包含主目标。次级目标使用引擎`PerformAttack`逐个独立结算，因此每个目标按自身护甲处理；次级攻击关闭Proc并在`modifier_weapon_attack_tracker`按attack record标记，不发布项目主攻击事件，避免递归多目标、公共技能、成长和主攻击装备效果。
- 多目标选择与次级`PerformAttack`必须由`MODIFIER_EVENT_ON_ATTACK`发布的`HERO_MAIN_ATTACK_FIRED`触发，使主箭和次级箭在正式出手点并列发射；不得恢复为订阅`HERO_MAIN_ATTACK_LANDED`，否则视觉会退化为主目标命中后补射。属性成长、技能、装备和研究等真实命中业务继续消费`HERO_MAIN_ATTACK_LANDED`。
- 主目标可在原平A落地时死亡；只要攻击事件中的主目标实体和敌方身份仍有效，多目标仍应继续选择存活的其他敌人。目标查询范围读取`survival_attack_range`、`Script_GetAttackRange()`和`GetAttackRange()`最大有效值。

## 英雄攻击能力与弹道配置（2026-08-03）

- `data/csv/英雄系统/hero_attack_projectiles.csv`同时是英雄弹道和攻击能力的权威源；`attack_capability`显式使用`melee`或`ranged`，禁止用0速度、空速度或极高速度隐式表达即时结算。
- `hero_stat_adapter.lua`按该字段投影引擎能力。`melee`表示无飞行弹道、攻击前摇结束时由引擎直接结算；`ranged`继续消费`projectile_speed`和可选`projectile_model`。
- 攻击能力与攻击距离是独立配置：近战能力仍可通过`modifier_survival_hero_attack_range`获得CSV指定的远距离。当前齐天大圣为`melee`且攻击/索敌1000；不应为了即时结算另写伤害或绕过原生普通攻击事件链。

## 资源树承伤与箭塔目标规则（2026-08-03）

- 资源树单位身份是`GetUnitName() == "enemy_tree"`；箭塔及全部转职塔的稳定身份是`survival_building_id == "arrow_tower"`，不要只按引擎单位名识别转职塔。
- 树可承受的伤害严格限定为引擎`DOTA_DAMAGE_CATEGORY_ATTACK`。不要用`inflictor == nil`或伤害类型猜测基础平A；技能、脚本、持续、范围和平A触发的技能/装备附伤均不得伤树，未知类别失败关闭。
- 树伤害类别的权威入口是全局`combat/damage_filter_service.lua`，共享规则位于`systems/tree_damage_rules.lua`。`modifier_tree_progression`提供第二层保护并继续负责最低1血与耗尽升级，不能另建重复树modifier。
- 箭塔禁止攻击树需要三层同时存在：`modifier_tower_auto_attack`自动目标排除与当前目标清理；`tree_attack_order_filter.lua`手动攻击命令拒绝；树承伤规则拦截已发射弹道和竞态伤害。
- `MODIFIER_PROPERTY_INCOMING_DAMAGE_PERCENTAGE`的`params.damage_category`不是伤害类别权威；实机DamageFilter也不保证提供`damage_category_const`。此前Mock测试人为注入该字段，造成自动测试通过而真实平A被“未知类别失败关闭”。明确类别存在时仍按`DOTA_DAMAGE_CATEGORY_ATTACK`判断；类别缺失/0时必须使用项目登记的真实攻击凭证，不能只靠inflictor为空猜测。
- 真实攻击凭证由树Modifier的`ON_ATTACK_START`按“攻击者+树”登记，短生命周期且一次性消费；失败/record销毁时清理。箭塔不得登记，DamageFilter中的箭塔身份拦截优先。缺类别伤害仅在无inflictor且成功消费凭证时放行，防止同次攻击后续无凭证脚本附伤重复利用。
- 判断“远程平A是否真实落地”可观察`modifier_lumberjack_ai:OnAttackLanded`产生的木材绿字：若木材增加但树不扣生命，说明弹道和攻击落地正常，应排查后续承伤过滤，不能误改投射物或额外调用`ApplyDamage`补伤害。

## 免费英雄与一转专属技能（2026-08-02）

- 当前正式英雄池为四名免费英雄`hero_doom`、`hero_shadow_fiend`、`hero_axe`、`hero_drow_ranger`，以及两名VIP英雄`hero_monkey_king`、`hero_blademaster`。
- 免费英雄专属技能在召唤时以项目等级0、`locked=true`进入技能状态和Q槽；引擎Ability使用等级1保证图标可见，但`SetActivated(false)`。一转授予必须解锁同一条目而不是删除重加。
- VIP专属不使用开局预创建规则，继续在一转后按`hero_exclusive_skills.csv`顺序授予四个技能。
- 四个免费专属的状态与召唤生命周期集中在`systems/hero_exclusive_passive_service.lua`，伤害通过主被动服务注入的既有`deal_group`提交，不得另建伤害事务。
- 专属召唤单位为`npc_survival_doom_infernal`与`npc_survival_drow_companion`；它们不是项目战斗英雄，不应挂英雄装备、成长或公共被动服务。
- 召唤物继承值必须取触发瞬间的`HERO_COMBAT_STATS_GET_REQUEST`权威快照，不从召唤物原生属性或英雄`GetStrength/GetAgility/GetIntellect`反推。当前地狱火继承100%攻击力、攻速、最大生命和运行时护甲；小游侠继承150%攻击力与100%攻速。
- 项目`attack_speed`表示每秒攻击次数，不是Dota攻速加成百分比。召唤物继承时先按`attack_speed_inherit_pct`计算，再用`SetBaseAttackTime(1 / attack_speed)`写入引擎，并同步保存`unit.survival_attack_speed`供UI、日志和实机诊断；非正数不得参与除法或覆盖单位BAT。
- 有持续时间且禁止重复召唤的技能，应以“英雄实体+技能ID”为唯一活动身份，同时检查召唤实体存活和到期时间；死亡、失效或到期必须清锁并清理实体。概率判定应在活动锁检查之后，避免存续期间无意义消耗随机数。
- 多目标召唤攻击必须区分主攻击与次级攻击。小游侠次级攻击使用`PerformAttack`关闭Proc，并通过攻击record标记隔离项目装备、英雄技能和其他攻击附带效果；只关闭引擎Proc不足以证明项目事件链不会重复触发。
- 小游侠固定五目标普通攻击与英雄转生多目标使用相同的“正式出手时并列发射”时点，但身份和目标数必须隔离：tracker在`MODIFIER_EVENT_ON_ATTACK`先按`survival_drow_companion`分流，主攻击调用小游侠固定五目标逻辑后直接返回，不能发布`HERO_MAIN_ATTACK_FIRED`；`OnAttackLanded`只清理record，禁止恢复命中后补射。
- “开局可见但未解锁”的固定槽技能使用项目等级0与`locked=true`表达业务状态，引擎Ability保持等级1以显示图标，并用`SetActivated(false)`禁用；解锁时激活同一个Ability，禁止删除重加导致槽位、Tooltip或存档身份漂移。
- 四英雄任务的可靠验证闭环包括：权威英雄/专属/技能/弹道/Tooltip CSV，定向生成Lua，Ability与单位KV、本地化镜像、Lua 5.1语法与行为测试、PowerShell契约、生成一致性、严格UTF-8和限定`git diff --check`。自动测试必须与用户验收分开记录；本任务已于2026-08-02获得用户明确成功确认。

## 召唤英雄与永久分身的完整战斗数据镜像（2026-08-03）

- 当需求是“分身数据与本体完全一致”时，权威来源必须是本体同一次`HERO_COMBAT_STATS_GET_REQUEST`返回的原子快照。攻击、最终攻速、暴击、逻辑三维、最大生命和`refresh_version`必须一起读取、一起应用，禁止每个Modifier分别请求快照，否则一次刷新可能混用不同版本。
- `attack_speed`是combat system已经计算完成的每秒攻击次数。完整镜像必须直接使用`SetBaseAttackTime(1 / attack_speed)`；禁止在分身侧重新组合`base_attack_time + equipment_attack_speed_pct`，因为分身原生英雄的基础100攻速、敏捷或其他原生状态仍可能参与引擎计算，造成二次投影和本体/分身漂移。
- 需要复制本体实际普通攻击时，不能简单使用`attack_min/max * hero_damage_multiplier`。本体引擎攻击由基础攻击倍率层和装备/研究附加攻击层共同组成，粗略乘法会错误放大附加部分。应由`hero_combat_stat_service`在权威快照中发布最终引擎攻击上下界，分身只复制结果，不在召唤物服务中重复实现攻击公式，也不挂会触发装备业务链的本体Modifier。
- 原生英雄分身必须把原生力量、敏捷、智力保持为0。项目逻辑三维只缓存和显示，不通过Dota原生三维投影；否则敏捷会额外改变攻速和护甲，力量会改变生命，主属性还可能改变攻击，导致数据看似已复制但实际结算继续偏移。
- `CreateUnitByName`创建的原生英雄分身同样不能依赖`SetBaseMaxHealth/SetMaxHealth`维持目标生命。应复用`modifier_survival_hero_base_health`动态补足：从当前最大生命扣除旧补充值得到原生基线，再计算新补充值；刷新后按新最大生命恢复原生命百分比，保证重复同步幂等。
- 暴击可由分身专用Modifier执行，但概率和倍率必须使用服务同步进去的同一份缓存快照，不得在暴击回调中再次请求combat system。这样一次攻击不会与攻击力、攻速或三维使用不同`refresh_version`。
- 战斗实体正确不代表选中面板正确。`ui_request_router`默认只把本体英雄entindex识别为英雄权威快照；永久分身必须使用严格身份标记（当前为`survival_monkey_king_clone`），按owner读取同一英雄快照，再替换分身entindex、实际最大生命、最终攻速、固定护甲和显示名。禁止为显示逻辑三维而写入原生三维。
- 完整镜像与业务链继承是两件事。分身可以复制最终数值，但仍应使用专用攻击Modifier和身份标记，明确隔离装备触发、公共技能、转生成长、英雄主攻击事件及未授权的专属技能；不能通过给分身挂本体全套Modifier来“省事复刻”。
- 自动测试至少覆盖：最终攻速到BAT换算、生命补足幂等、最终引擎攻击字段存在、禁止攻速百分比二次投影、禁止Modifier拆分请求快照、分身UI严格身份/owner映射，以及Lua 5.1语法。上述检查不能替代Workshop Tools中对HUD、实际攻击间隔、平A伤害、暴击和生命比例的实机对照。

## 项目与环境

- 项目：Dota 2 自定义地图 `survival`。
- 规范工作目录：`E:\steam\steamapps\common\dota 2 beta\game\dota_addons\survival`。Source 2编译资源会规范化为小写file mod；Game/Content物理插件目录也必须保持精确全小写，禁止再次创建`Survival`大小写变体。
- 服务端主要使用 Lua，配置权威来源位于 `data/csv`，生成配置位于 `scripts/vscripts/config/generated`。
- 配置修改规范：优先修改 CSV，再运行 `build_configs.bat`；运行时服务通过 `core/event_bus.lua` 解耦。
- 内容库存以 `content_id` 为权威身份，Dota 物品实体只是可见背包壳。
- 英雄力量、敏捷、智力是项目逻辑三维：由服务端战斗快照统一计算和发布，不写入 Dota 原生三维。逻辑三维本身不提供攻速、护甲、生命、魔法或主属性攻击，只供 UI 和明确按三维结算的技能/装备效果读取。
- Panorama 源码不在当前 `game` 插件目录中，而在对应的内容目录：`E:\steam\steamapps\common\dota 2 beta\content\dota_addons\survival\panorama`。
- 游戏实际加载的 Panorama 编译产物位于：`E:\steam\steamapps\common\dota 2 beta\game\dota_addons\survival\panorama`。
- 当前Lua 5.1解释器/检查器为`C:\msys64\msys64\bin\lua5.1.exe`与`C:\msys64\msys64\bin\luac5.1.exe`，均已在2026-08-12实际执行确认版本5.1.5；目录未加入PATH，必须使用绝对路径。当前Python为`C:\Users\UserComputer\.workbuddy\binaries\python\versions\3.14.3\python.exe`，PowerShell 7为`C:\Program Files\PowerShell\7\pwsh.exe`。

## AI 会话恢复协议

- 所有新会话必须首先读取 `docs/ai/START_HERE.md`，再按其中顺序恢复上下文。
- `docs/ai/CURRENT_TASK.md` 只描述一个活跃任务；完成或被替换后整体迁入 `docs/ai/archive/`。
- 深度研究不能只存在于聊天中；关键证据、排除项、未决问题和下一步必须持续追加到 `docs/ai/SESSION_LOG.md`。
- 用户需求发生变化、完成关键调查、作出重要决策、准备大范围修改/验证或会话可能中断时，必须先写检查点。
- 如果持久化文档与模糊会话记忆冲突，以文档中的用户原始需求和最新检查点为准，并向用户明确冲突，不得猜测。

## 常用命令与配置链

- 当前可用的Lua 5.4语法检查使用：
  ```powershell
  $luac = Join-Path (Split-Path (Get-Command lua).Source -Parent) "luac.exe"
  & $luac -p "D:\steam\steamapps\common\dota 2 beta\game\dota_addons\survival\scripts\vscripts\path\to\file.lua"
  ```
- 多文件检查应逐个调用并在任一文件失败时终止；`luac -p`成功时通常没有标准输出，应结合退出代码0判断通过。需要Lua 5.1兼容结论时必须先恢复并实际运行5.1编译器。
- 在 PowerShell 中不能从 `-NoProfile` 开始执行命令；该参数必须属于 PowerShell 可执行程序。正确形式：
  ```powershell
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "D:\steam\steamapps\common\dota 2 beta\game\dota_addons\survival\build_configs.ps1"
  ```
- 如果已经位于 PowerShell 会话，也可以直接调用脚本：
  ```powershell
  & "D:\steam\steamapps\common\dota 2 beta\game\dota_addons\survival\build_configs.ps1"
  ```
- `-NoProfile : 无法识别` 是命令缺少 `powershell.exe`/`pwsh` 前缀，不代表 CSV 表格本身有错误。
- 建筑配置链为：`data/csv/建筑与工人系统/building_definitions.csv` → `scripts/vscripts/config/generated/building_definitions.lua` → `scripts/vscripts/config/buildings_config.lua` → `scripts/vscripts/systems/building_system.lua`。
- 排查“表格改了但游戏没生效”时，必须依次检查源 CSV、生成 Lua、运行时适配层和最终消费者，不能只确认生成文件。
- Panorama JS 修改后必须编译到 `game` 目录；定向强制编译示例：
  ```text
  resourcecompiler.exe -f -game "D:/steam/steamapps/common/dota 2 beta/game/dota" -i "D:/steam/steamapps/common/dota 2 beta/content/dota_addons/survival/panorama/scripts/custom_game/combat_stats.js" -o "D:/steam/steamapps/common/dota 2 beta/game/dota_addons/survival/panorama/scripts/custom_game/combat_stats.vjs_c"
  ```
- 编译成功的明确依据应为 `OK: 1 compiled, 0 failed, 0 skipped`；修改后需重新 Run 地图或重新加载 HUD。

## 当前物品与合成架构

- 权威库存：`scripts/vscripts/systems/content_inventory_service.lua`。
- 原子库存事务：`scripts/vscripts/systems/inventory_transaction_service.lua`。
- 自动合成：`scripts/vscripts/systems/weapon_synthesis_service.lua`。
- 配方来源：
  - `data/csv/物品系统/recipes.csv`
  - `data/csv/物品系统/recipe_ingredients.csv`
- 挑战地面奖励：`scripts/vscripts/systems/challenge_equipment_reward_service.lua`。
- 挑战物品拾取：`scripts/vscripts/items/item_survival_challenge_reward_runtime.lua`。
- 挑战会话与怪物死亡：`scripts/vscripts/systems/challenge_session_service.lua`。

## 当前 Tooltip 重构基线（2026-07-28）

- 本轮目标是保留 Valve 原生 HUD、技能/物品基础 Tooltip 和人物属性布局，只为项目特有的动态实例数据与逻辑属性增加扩展层。
- 当前 `content/.../ability_tooltip.js` 仍包含三条高频时间驱动路径：每 `1.0s` 扫描官方技能/背包节点、每 `0.35s` 重绘可见 Tooltip、物品悬停时每 `0.03s` 强制关闭原生 Tooltip。
- 当前人物属性数字已经由 `combat_stats.js` 使用服务端快照覆盖；护甲 UI 值为 War3 显示单位，`runtime_armor` 为 Dota 实际结算单位。
- 英雄、建筑和普通选中单位都通过 `ui/combat_stat_projection.lua` 生成统一 UI 属性投影，因此人物逻辑属性 Tooltip 不得自行乘除护甲或重新读取引擎临时值。
- 英雄攻击、护甲、攻速和三维必须作为带 `refresh_version` 的原子快照刷新；即时选中单位响应不得用引擎瞬时字段覆盖英雄权威快照，客户端必须拒绝同单位迟到的旧版本或无版本快照。
- 英雄 HUD 护甲直接使用装备聚合的完整 War3 阶段值；装备护甲为 0 时才回退英雄配置基础护甲。`runtime_armor` 仅保留为 Dota 实际结算/诊断值，不得反向决定同帧 HUD 数字。
- 公共技能 `proto_chain_lightning` 已重做为五级“怒雷”：等级1为20%概率的全属性×3主目标落雷与400范围50%扩散；等级2增加3秒可刷新标记及再次命中全属性×1.5；等级3触发率45%且标记降低15%基础攻击力；等级4无变化；等级5连续三道并优先不同目标，重复主目标从第二道起伤害减半。
- 公共技能 `proto_arcane_barrage` 已重做为五级“奥术弹幕”：攻击时10%概率对触发瞬间的目标位置炮击；等级1在500落点半径内用1秒落5颗，等级2收束至200，等级3/4每轮7颗，等级5在3秒内每秒一轮共21颗；每颗在地面播放简单爆炸并对150范围造成触发时全属性×2纯粹伤害。AOE先以“爆炸半径+最大Hull”执行 `FIND_ANY_ORDER` 宽查询，再按XY平方距离 `dx²+dy² <= (爆炸半径+当前敌人HullRadius)²` 精确过滤；不得恢复平方根距离、候选排序或把最大Hull统一作为最终命中半径。同一英雄从施法开始到最后一颗结算前不再进行该技能的概率判定，活动锁同时具备按时过期与延迟任务双重兜底。等级5的21颗飞弹由一个绝对时间校正的顺序Scheduler任务驱动，不得恢复为21个独立任务。
- 公共技能 `proto_ice_cone` 已重做为五级“寒冰锥”：攻击命中15%概率在目标触发位置固定生成500范围暴风雪；等级1至4在0/1/2秒各落冰一次并锁3秒，等级5在0/1/2/3/4秒各落冰一次并锁5秒；每次造成触发时全属性×1纯粹伤害。等级2至4施加不可叠加可刷新的20%攻速降低3秒，等级5提高至40%；等级3起每次落冰对每个命中敌人独立20%概率冻结1秒，等级4完整继承等级3。AOE复用按敌人实际Hull边缘的二维精确命中；一场暴风雪只使用一个顺序Scheduler任务和一个结束释放任务。
- 公共技能 `proto_magic_slingshot` 已重做为五级“魔法弹弓”：任意主攻击命中敌人后10%概率触发，选择英雄攻击射程内最近的最多5名敌人；5仅为上限，范围内1/3名敌人就分别发射1/3颗。等级2未眩晕优先，等级3命中瞬间先检查目标旧眩晕并以全属性×6或×3结算，再施加本次眩晕，等级4继承等级3；等级5生成半径200持续3秒碎石区，每秒全属性×1.2纯粹伤害，区域内30%唯一减速，离开全部区域立即移除，已有区域内命中不生成新区。所有伤害使用触发时逻辑全属性快照。
- 公共技能 `proto_holy_pulse` 保留原Ability ID `ability_survival_holy_pulse`和公共池成员`public_10`，已重做为五级“元气弹”：攻击命中12%概率向普攻范围内最近最多5个目标发射追踪投射物，每颗真实命中造成触发时逻辑全属性×4纯粹伤害；LV2每颗命中恢复5%最大生命；LV3基础7目标且每次触发10%概率提高到9，LV4继承；LV5每颗命中独立20%概率对250范围追加基础伤害60%，原命中目标也重复承受爆炸伤害。索敌复用魔法弹弓已验证的攻击射程回退和Hull边界策略。
- 公共技能 `proto_poison_cloud` 对每个英雄只允许一个活动毒云；活动期间在概率判定前直接跳过，不替换、不刷新旧毒云，旧云自然结束或清理后才允许再次触发。
- 公共技能 `proto_frost_nova` 已保留原ID并重做为五级“移动冰球”：主攻击命中12%概率触发，LV1以360速度直线飞向原目标触发位置，每0.5秒对300范围造成触发时全属性×2纯粹伤害；LV2速度540，每碰撞不同敌人使周期基础伤害+5%，最多10层；LV3范围350且所有飞行结束情形固定爆炸全属性×3，LV4继承；LV5最大移动距离为初始英雄到原目标距离的150%，在该范围随机索敌追踪，每实际移动100码使周期基础伤害+10%。LV5目标死亡后不重新索敌，而是锁定死亡位置并直线飞去后爆炸。周期成长不影响固定×3爆炸；活动冰球由一个0.05秒共享任务推进。
- 公共技能 `proto_flame_burst` 已保留原ID并重做为五级“爆炎弹”：主攻击命中15%概率在目标触发位置对500范围造成触发时全属性×4纯粹伤害；LV2每个主爆炸命中敌人获得一层3秒点燃，在第1/2/3秒结算且每层总倍率精确为×2.2，重复点燃替换旧层；LV3最多5层且每层快照与生命周期独立，第6层替换最早到期层，LV4继承；LV5主爆炸后同时喷射3颗小火球，0.5秒后同时落在中心200半径的均匀随机位置，每颗对250范围造成×3并分别施加点燃。小火球重叠时直接伤害和点燃均逐颗结算；三球共用一个同步落地任务。用户已实机确认整体效果良好并批准固化当前实现，除非后续出现明确问题不得主动改动。
- 公共技能 `proto_poison_cloud` 已保留原ID并重做为五级“毒云”：LV1/2主攻击命中12%概率在目标触发位置生成固定400范围毒云5秒，第1至第5秒各造成触发时全属性×1纯粹伤害；LV2起每次Tick增加20%实时总护甲降低，最多3层60%，离开、替换或到期立即移除；LV3触发率20%且持续7秒共7次，LV4继承；LV5毒云内敌人死亡时在死亡位置产生300范围×3纯粹伤害并允许连锁，每个死亡单位只触发一次。同一英雄只有一个毒云，新云替换旧云。实机确认`MODIFIER_PROPERTY_PHYSICAL_ARMOR_TOTAL_PERCENTAGE`未可靠反映到项目自定义护甲UI读取的`GetPhysicalArmorValue(false)`，现使用已验证的`MODIFIER_PROPERTY_PHYSICAL_ARMOR_BONUS`，每次共享同步先加回毒云自身旧减甲，再按排除毒云后的实时护甲绝对值重算20%/40%/60%；不得改回进入时护甲快照或不可靠的总百分比属性。
- 公共技能 `proto_blade_nova` 已保留原ID、`ability_survival_blade_nova`和显示名“剑刃震荡·被动”，重做为五级“脉冲激射”：LV1主攻击命中15%概率沿触发瞬间英雄面向发射总宽200、长度为英雄攻击射程的穿透脉冲，对路径内敌人造成触发时全属性×4纯粹伤害；LV2每道最先命中的目标伤害翻倍；LV3按目标沿脉冲方向的投影距离线性提高，近端×4、末端最高×8；LV4完整继承LV3；LV5射程提高50%，每次触发30%概率将单道替换为同路径完全重合的3道脉冲，每道独立结算首目标、命中去重与完整伤害，同一敌人可承受3次且无衰减。实现使用原生`CreateLinearProjectile`、半宽100、`bDeleteOnHit=false`，并按实际射程动态计算速度使脉冲固定1秒走完全段。用户已于2026-08-02确认技能制作完成，除非出现明确新需求或实机问题，不主动修改当前基线。
- 公共技能`proto_earth_line`已保留原Ability ID`ability_survival_earth_line`和公共池成员`public_06`，重做为五级“地裂冲击”：攻击命中12%概率从攻击者触发位置向目标触发位置释放Tiny岩石线性投射物，速度500且不追踪；LV1总宽150、LV2起250；每个路径单位每道去重，造成触发时逻辑全属性×3纯粹伤害，命中前已被任意来源眩晕则×6；LV3起伤害后独立30%眩晕1秒，LV4继承；LV5首次真实命中位置300范围额外造成×3/旧眩晕×6，首敌重复承受范围伤害，范围单位不参与新眩晕，滚石继续穿透。终点爆炸仅为视觉；实现使用唯一投射物ID、`bDeleteOnHit=false`、回调`return false`、终点/超时幂等清理和触发时逻辑三维快照。用户已于2026-08-02确认技能暂时完成，当前实现是稳定基线；LV2视觉体积是否随碰撞半径变化未单独实机确认，但不再作为活跃待办。
- 地裂冲击后续维护方式：技能身份、最高等级和概述以`data/csv/英雄系统/hero_skill_definitions.csv`为权威，基础Tooltip以`data/csv/公共规则/tooltip_definitions.csv`为权威，修改后定向生成`scripts/vscripts/config/generated/hero_skill_definitions.lua`和目标Tooltip行；五级数值与逐级说明维护在`scripts/vscripts/config/hero_passive_skill_definitions.lua`；引擎等级同步检查`scripts/npc/npc_abilities_custom.txt`；五级Tooltip发布检查`scripts/vscripts/ui/ability_runtime_service.lua`；投射物、逐单位去重、旧眩晕快照、伤害后眩晕、LV5首次范围伤害和幂等释放维护在`scripts/vscripts/systems/hero_passive_skill_service.lua`。不得直接手改生成Lua，不得改回粒子推算碰撞或`line_targets()`瞬时扫描。每次修改至少运行地裂契约/Lua 5.1状态测试、`luac5.1 -p`、生成一致性、严格UTF-8、限定`git diff --check`和共享投射物/眩晕回归；视觉尺寸与实际碰撞只能由Workshop Tools确认。
- 英雄科技攻击减甲 `researcher_hero_armor_reduction` 使用War3显示护甲配置并由`armor_balance.from_war3`转换为Dota结算护甲；19级为每击9.5显示护甲（约3.1667底层护甲）。普通波次怪、挑战怪、遭遇怪及`addmonster`未显式配置`minimum_armor`时不得写入默认护甲下限；只有树木和明确配置下限的单位才限制累计减甲。科技减甲UI事件必须延迟到下一Scheduler帧，并在项目英雄权威快照路径覆盖当前有效护甲字段。
- 魔法弹弓的射程读取不得只依赖 `GetAttackRange()`：当前 `CreateUnitByName`召唤英雄由`hero_stat_adapter`通过`Script_SetAttackRange`写入配置，但实机曾读取到`GetAttackRange()==0`。权威回退顺序包含`unit.survival_attack_range`、`Script_GetAttackRange()`、`GetAttackRange()`和`config/generated/hero_definitions.lua`的`attack_range`，取最大有效正数；本次合法命中的敌方主目标始终作为保底候选。实机已确认`range=3000 selected=1 launched=1`，尚待确认`MAGIC_SLINGSHOT_HIT`。
- `hero_skill_pool_members.csv` 使用 UTF-8 BOM，以兼容 Office/Excel 双击打开；配置生成器的 `utf-8-sig` 读取保持兼容。
- 英雄伤害测试面板除原“累计/最近伤害”外，独立显示英雄技能的累计伤害、最近一次伤害和命中次数；统计使用 `OnTakeDamage` 的最终实际伤害，被动技能伤害请求必须携带对应 Ability handle 以区别普通攻击。
- 公共技能`proto_void_pulse`的追踪龙卷视觉使用项目粒子`particles/survival_tornado/survival_tornado_follow.vpcf`，只引用Valve的`invoker_tornado_child.vpcf`子效果且不含内部移动算子；Lua权威状态每0.05秒写CP0。不得恢复为完整`invoker_tornado.vpcf`并尝试动态修改CP1追踪。
- 接入Valve移动父粒子前必须读取content源码确认主载体的发射方式、寿命、内部移动与EndCap，不能只根据粒子名称或预览判断。`invoker_chaos_meteor.vpcf`主载体固定寿命仅0.2秒，速度500时只覆盖约100码；`proto_earth_line`因此使用项目变体`particles/survival_earth_line/survival_earth_line_chaos_meteor.vpcf`，由CP2.x接收权威飞行时长并移除落地冲击子效果。修改项目粒子后必须Resource Compiler强制编译并冷重启Workshop Tools，Lua热加载不能完成验收。
- 公共技能`proto_meteor`已重做为五级“陨石坠落”：攻击命中12%概率在目标快照位置坠落，0.8秒后500范围爆炸并造成触发时全属性×3纯粹伤害；LV2起留下3秒熔岩，在落地后第1/2/3秒各造成×1；LV3起区域内唯一减速30%，离开全部区域立即移除；LV4无新增；LV5同点晚0.5秒落下第二颗，其爆炸和熔岩均为80%。每英雄从触发到最后一次熔岩结算维持独立锁，概率判定前跳过；LV1落地即解锁。视觉使用卡尔`invoker_chaos_meteor_fly.vpcf`完成坠落，权威落地时立即清除卡尔粒子并在同点播放术士`warlock_rain_of_chaos_explosion.vpcf`纯爆炸；不创建地狱火单位，也不使用包含11秒烧焦地面的完整Rain of Chaos父粒子。爆炸由独立注册表保留3.1秒后强制销毁释放，清局立即回收；LV2起继续使用Viper Nethertoxin地面区域。粒子只负责表现，伤害碰撞仍由Lua状态与Hull精确AOE权威决定。
- `addmonster`的可攻击调试怪使用600基础移速，并通过仅作用于该实例的`modifier_debug_move_speed_cap`把`MODIFIER_PROPERTY_MOVESPEED_MAX/LIMIT`提高到600；不可攻击模式仍为0。该Modifier不得提供绝对移速，以保证技能百分比减速继续参与最终速度。此方案已用于验证陨石熔岩30%减速，用户实机确认从高速基准观察时效果正常；不得为测试效果修改正常怪物CSV、生成怪物配置或`npc_units_custom.txt`。
- 测试聊天命令 `addskill` 将当前玩家技能点直接设置为10；未召唤英雄时拒绝执行，重复输入仍保持10点。
- 英雄公共技能池独立上限为3，英雄总技能容量仍为配置中的10；候选生成和最终授予均由服务端检查，达到3个后转生随机技能奖励正常跳过，技能点奖励不受影响。
- 重构采用分阶段可回滚方式：先建立共享快照/Tooltip ViewModel，再接管人物逻辑属性悬停，最后将技能/物品 Tooltip 改为原生优先与事件驱动扩展。
- 角色属性详细 Tooltip 已按用户最新要求删除；`combat_stats.js` 继续直接显示服务端权威攻击、护甲、攻速与三围数值，不再发布 `SurvivalCombatStatsStore`。
- 第二阶段已新增 `ui/tooltip_view_model.lua`，由 `weapon_synthesis_snapshot_service.lua` 把动态物品字段发布到 `survival_weapon_snapshot.tooltip_view_model`。
- 技能由独立 `hud_takeover.js` 代理完全控制 Tooltip；背包由独立 `inventory_tooltip.js` 在保留 Valve 操作的前提下显示项目气泡，动态内容只在权威状态变化时重绘。
- 最新最终验证：30 个 Lua 测试全部通过，相关 Lua 语法检查和限定路径 `git diff --check` 通过；本轮相关 JS/CSS 和 HUD XML 已强制编译到游戏目录，均为零失败、零跳过。

## 已完成的重要工作

- 召唤战斗英雄的权威目标基础生命由`hero_definitions.csv`的`base_health × max_health_multiplier × hero_meta_max_health_multiplier`计算；普通英雄当前为3000，齐天大圣/剑圣为11000。原生英雄实机证明直接`SetBaseMaxHealth/SetMaxHealth/SetHealth`会被引擎恢复为120，因此目标生命由隐藏永久`modifier_survival_hero_base_health`通过`MODIFIER_PROPERTY_HEALTH_BONUS`补足：补充值=`目标生命-(当前最大生命-旧补充值)`。真实装备`health_flat`随后独立叠加；禁止改成固定加3000或真实隐藏物品。该隐藏Modifier方案已由用户在Workshop Tools中确认英雄血量正常。
- 测试聊天命令`blood`只作用于当前玩家召唤的战斗英雄：`+/-数值`固定增减，`+/-百分比%`按执行时当前最大生命计算；加血不超过最大生命，减血最低保留1点，合法加血会使延迟生命保护失效。

1. 合成宝石和挑战材料可以作为可见物品直接拾取并保留在英雄背包中；只有原子合成成功后才消耗。
2. 修复自动合成检查在首次成功后可能遗留 pending 状态、导致后续配方不再执行的问题，并加入错误恢复测试。
3. 修复召唤英雄 `GetPlayerOwnerID() == -1` 导致挑战奖励无法认领的问题；没有采用“把英雄设为唯一可选单位”的破坏性方案，建筑与农民仍可选择。
4. 增加测试作弊码 `addhero`：生成齐天大圣、解锁商城、给予大量金币和木材。
5. 修复英雄被动属性读取 API 参数错误（`GetIntellect` 等接口参数与 Dota API 对齐）。
6. 材料允许丢弃；武器保持不可丢弃策略。
7. 挑战 07 已改为场内维持 10 只熔火怪物，死亡后 0.5 秒补充，每只授权击杀独立 20% 概率掉落熔火核心 Lv1。
8. 挑战 07 的 Lv1 核心复用现有地面奖励、拾取、背包壳和自动合成链；`3×Lv1→Lv2`、`3×Lv2→Lv3` 配方有效。
9. 挑战 08 Boss 现在会在死亡位置掉落 `material_molten_core_04`；拾取后进入背包，并可与狱火熔铠 Lv4 自动合成 Lvmax。
10. 防御塔升级按钮会随 `RESOURCE_CHANGED` 实时刷新；塔 CSV 的 `population_cost` 生成到 Lua 后命名为 `population_occupied`。基础箭塔占有 0，所有转职塔占有 1；首次转职原子占用 1 人口，后续升级不重复占用，死亡或融合时释放。
11. Panorama 快捷键绑定必须按 HUD 上下文重建，不能用跨 Workshop Tools Run 保留的 `CustomUIConfig` 标志跳过注册。
12. 受运行时管理的建筑技能，原生按钮鼠标点击与 Q/W/E 快捷键统一发送 `ui_ability_cast_request`；客户端 `can_afford` 只用于费用/资源提示，不能阻止请求，最终资源判断由服务端原子扣费负责。
13. 英雄和建筑战斗属性 UI 已统一单位投影：运行时护甲使用 Dota 单位，面板护甲使用 War3 显示单位；英雄面板攻击保持 CSV 值，原生普通攻击仍保留英雄倍率投影。
14. 建筑的 `max_count`、`requires_city_level` 和 `population_cost` 已由生成的 `building_definitions.lua` 驱动；箭塔全队共享上限为 7。
15. 建筑数量在施工单位创建后立即占位，建筑死亡或施工实体失效后释放；`max_count=0` 表示无限制。
16. 官方 HUD 上的权威攻击、攻速与护甲数值由 `content/.../combat_stats.js` 动态覆盖；三项共用攻击力数字的样式和原生数字 Label 定位规则，攻速与护甲不再按图标猜测位置。
17. Tooltip 当前边界：技能完全由项目代理控制；背包显示项目物品气泡但操作仍由 Valve 负责；角色属性详细 Tooltip 已取消；所有动态字段使用事件驱动刷新。
18. 英雄伤害测试面板已拆分技能伤害；`addskill` 可将技能点设为10；公共技能池最多拥有3个技能，但专属/功能技能继续使用总容量规则。

## 当前熔火装备升级链

- `狱火熔铠Lv1 + 熔火核心Lv1 → 狱火熔铠Lv2`
- `狱火熔铠Lv2 + 熔火核心Lv2 → 狱火熔铠Lv3`
- `狱火熔铠Lv3 + 熔火核心Lv3 → 狱火熔铠Lv4`
- `狱火熔铠Lv4 + 熔火核心Lv4 → 狱火熔铠Lvmax`

四段升级配方及挑战 07/08 的材料来源均已闭环，并通过地面掉落、自动合成与错误恢复回归测试。
