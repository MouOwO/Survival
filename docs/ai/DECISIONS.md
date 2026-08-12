# Decisions

## 2026-08-12：玩家档案协议先行并通过可替换Provider接入

- 决定：外围档案固定采用“稳定`account_id` + versioned snapshot/incremental”协议；当前本地Fixture、后续Mock HTTP和正式数据库都必须经过同一`player_profile_service`校验与提交边界。
- 决定：`schema_version/revision/base_revision/update_id`是协议必需字段。增量严格连续且幂等，缺口或乱序重拉快照；快照不能用较低revision覆盖当前状态，异步请求用generation拒绝迟到回调。
- 决定：付费权益默认关闭并由验证后的档案原子投影。客户端和Lua请求不得声明支付成功；正式支付只能由后端验签、订单幂等和数据库事务生成权益revision。
- 决定：完整档案不进入Custom Net Tables。客户端只看到CSV白名单公开投影；新增公开字段必须先经过隐私审计并修改权威CSV。
- 原因：这样可以先用假数据验证多人按账号隔离和现有商城权益链，又不会把本局`player_id`、客户端声明或临时Mock结构固化为正式数据库接口。

## 2026-08-11：逐波模型最终唯一，当前共享模型只作为可删除兼容层

- 决定：最终版每个正式波次必须拥有自己的实际模型资源清单；预载、`SetModel/SetOriginalModel`和生命周期释放全部消费同一解析结果，不得依赖前一波曾经加载同路径。当前Visage普通飞行覆盖及其他跨波英雄模型复用属于资源未定稿阶段的临时兼容，代码必须使用`TODO(FINAL_WAVE_MODELS)`说明删除条件。
- 决定：每次正式波次建立独立资源会话，按会话统计pending/alive并持有模型Lua租约。会话生成完成且所属怪物全部结束后释放会话引用；多个波次重叠时不得按全局当前波编号释放。dev跳波仍清理实体视觉与任务，但模型租约保持驻留，不执行波次模型release。
- 决定：禁止把`asset_preload.retire()`当作模型delete。它只改变项目Lua状态且会拒绝后续请求，不证明Source 2资源池已卸载模型。当前release函数只清除项目可控引用并标记`TODO(SOURCE2_MODEL_UNLOAD)`；只有未来获得安全引擎卸载API或可卸载资源包方案后才允许实现真正模型卸载。
- 决定：下一波模型在倒计时开始立即异步请求，并在正式提前窗口再次幂等复核；urgent请求可与后台塔/城墙流并行，不能因后台流占用而错过首只怪。该调整只改变资源准备提前量，不改变波次计时、成员、数量、顺序和生成间隔。
- 原因：W12开发跳波实际存在“预载基础红龙模型、出生切换Visage”的双解析冲突；正式流程只提前4秒且urgent仍受后台请求阻塞，也存在冷资源竞态。统一实际模型解析、逐波会话和提前请求能修复当前错误，并为后续逐波唯一模型替换留下明确弃用路径。

## 2026-08-11：W11恢复批准混合构成，普通飞行使用角色限定模型与Hull

- 决定：2026-08-10的“W11纯地面15+44”是临时BUG隔离方案，现由本决定取代。N1-N5 W11普通怪最终固定为10只`beast_green_large`、30只`skeleton_bone`和19只`flying_red_gargoyle`，合计59；领头怪和进攻Boss不计入59。
- 决定：正式混合波按移动类别调度，每轮2只地面后1只飞行；地面和飞行类别内部各自round-robin。成员类别耗尽后继续输出剩余成员，禁止因原型数量不同变成3地+1飞或丢失单位。
- 决定：普通飞行视觉与碰撞按“正式波次`member_role=normal`且最终移动类型为`flying`”限定。该范围读取`normal_flying_model_path`并统一使用Visage飞行模型，基础Hull为10且保留单位碰撞；飞行领头怪、精英、Boss、十罪和挑战怪继续读取原`model_path`并保持既有Hull 0/无单位碰撞边界。
- 原因：原故障不是“W11不应存在飞行怪”，而是旧成员与新成员重复叠加造成118只，以及普通飞行怪使用共享走地模型和Hull 0/无碰撞。直接删除飞行种或覆盖共享原型都会改变已批准构成或越界影响非普通角色。
- 防复发：`wave_id`全局唯一，生成器拒绝重复ID并校验实际存在的W11-W30普通怪总数为59；N1/N3-N5导入器复用模板前按ID保留最终定义。测试必须覆盖W11精确`10/30/19`、五难度W11/W13/W24真实顺序、普通飞行与非普通飞行角色边界、Hull非累计缩放、VPK/预载和CSV生成一致性。

## 2026-08-10：英雄移动使用白名单，建筑额外使用禁建黑名单

- 决定：`build_forbidden_regions.csv`统一保存`hero_movable`和`building_forbidden`两类区域；英雄目的地只消费前者，建筑footprint同时消费前者联集覆盖和后者相交拒绝。
- 决定：正式战斗英雄以`survival_hero_id`为身份；Builder、工人、怪物、建筑和占位英雄不受移动白名单约束。非法普通移动/攻击移动提前拒绝，其他运行时越界停止并拉回最后合法位置。
- 决定：没有有效`hero_movable`业务行表示白名单未启用，英雄和建筑沿用旧地图导航与Grid规则；存在至少一个有效区域后才启用严格白名单。`building_forbidden`始终独立生效。区域策略拒绝建筑时仍返回完整红色footprint cells。
- 原因：CSV schema的存在不等于地图已选择启用白名单；空配置失败关闭会让地图不可移动、不可建造并使Grid消失。显式按有效行启用既保持旧地图可玩，又不需要猜测Hammer边界，且保留后续严格约束能力。

## 2026-08-09：怪物护甲保持线性投影与Damage Filter曲线补偿

- 决定：波次、挑战和调试怪的War3护甲继续通过`armor_balance.from_war3()`线性`/3`写入运行时护甲；Damage Filter只补偿War3目标承伤曲线与当前Dota曲线的倍率差。
- 决定：现代非线性映射和版本化反投影可保留为正交兼容API，但不得仅因并发合并而给现有怪物入口写入现代映射身份。117 War3护甲的已验收运行时值固定为39，而非现代映射约34.32。
- 原因：属性投影与伤害曲线补偿属于两个独立边界；非线性重映射会改变已通过用户测试验收的固定基准，并影响科技减甲和UI反投影语义。
- 合并规则：遇到stash/merge冲突时先比较base、ours、theirs及全仓调用方，以已验收行为为权威，保留不改变该行为的正交API，并重跑专项、调用链回归、Lua 5.1语法、生成一致性和编码检查。

## 2026-08-10：N2-N5 W11移除错误飞行变体（已被2026-08-11决定取代）

- 决定：N2-N5 W11普通怪固定为15只`beast_green_large`和44只`skeleton_bone`，删除19只`flying_red_gargoyle`；普通怪总数仍为59，领头怪保持1只且不改变属性。
- 原因：用户实机确认W11模型错误且整批出现飞行单位的穿地形、可叠加行为；当前N1 W11权威同波模型已是纯地面构成，N2-N5残留飞行成员属于旧映射。
- 防复发：N2-N5导入器只对W11忽略旧工作簿普通飞行数量，并只使用N1同波普通成员模板。该决定是对下方“数量同步时怪种不变”的后续BUG修正，不影响其他合法飞行波。
- 失效说明：本条仅保留历史排障原因，不得继续作为生产规则。后续实现必须使用上方2026-08-11的`10地A + 30地B + 19飞行`、角色限定模型和Hull规则。

## 2026-08-09：所有难度从W11起每个已存在波次普通怪统一为59只

- 决定：W1–W10保留原始普通怪数量；N1 W11–W25、N2–N5 W11–W30每波普通怪固定为59只。精英`wave_leader`和进攻Boss`assault_boss`不计入59只，数量保持原配置。
- 决定：多怪种按旧数量比例使用最大余数法确定性放大，单怪种直接设为59；不改变怪种、属性、成员角色、出怪顺序、移动类型或模型缩放。
- 原因：统一N1–N5中后期正式波次的普通怪节奏，同时保留前10波原始难度曲线和特殊成员配置。
- 边界：N1没有W26–W30；N2–N5的W30原始普通怪为9只，现按用户确认的W11–W30规则统一改为59只。

## 2026-08-09：N1 W11–W25普通怪统一为59只

- 决定：N1第11–25波每波普通怪统一为59只；多怪种按原数量比例使用最大余数法分配，精英`wave_leader`和进攻Boss`assault_boss`数量不变。
- 原因：用户要求让此前只有7–8只普通怪的N1中后期波次与59只普通怪的正式波次口径同步，同时保留怪种构成和特殊成员数量。
- 边界：本决定只覆盖旧N1工作簿的普通怪数量结论，不推翻其怪种、属性和角色证据；N1仍为25波，不新增N1最终波。“不修改N2–N5”是本阶段的历史边界，后续已由全难度W11起59只的决定覆盖。

## 2026-08-05：N1波次按25波独立工作簿直接配置

- 决定：N1不再被视为N2-N5的模型模板旧数据，而是按最新N1工作簿配置25波直接成员，成员身份和排序与N2-N5统一。
- 原因：N1工作簿明确汇总202个普通怪、21个首怪Boss、5个进攻Boss，总228；旧CSV仅209且没有首怪独立身份。复用30波/1303硬编码会改变N1原始玩法。
- 边界：保留可复用的既有模型映射；工作簿没有模型证据时只采用项目已批准回退，不创建新模型。没有可执行模型/数量映射的属性变体不进入运行CSV。

## 架构决策

1. **CSV 是配置权威来源。** 不只修改生成 Lua；涉及挑战、内容、商店和配方时同步更新对应 CSV，再生成/校验 Lua。
2. **逻辑库存是权威，物品实体是显示壳。** 拾取时登记 `content_id`，只有合成事务成功后才删除材料壳。
3. **所有自动合成统一由 `weapon_synthesis_service` 扫描。** 挑战服务只负责掉落，不直接写装备升级逻辑。
4. **合成必须原子执行。** 材料消耗和产物发放通过库存事务完成，失败不得提前删除材料。
5. **挑战奖励使用服务端权威请求。** 新的内容掉落入口必须校验 challenge/content 配对，避免成为任意物品生成接口。
6. **每个地面奖励具有幂等 key。** 重复死亡/完成事件不能创建重复奖励。
7. **客户端资源快照不具有请求否决权。** `can_afford` 只负责 UI 费用、状态和诊断；由于 NetTable 可能短暂过期，客户端不得因快照资源不足而丢弃点击。服务端 `RESOURCE_TRY_SPEND_REQUEST` 是最终且原子的资源判断。
8. **技能接管按托管身份分流输入。** 自定义技能按钮和 Q/W/E/R/T/Y/U 统一进入 `SurvivalAbilityInput`；明确托管的建筑无目标操作走 `ui_ability_cast_request`，托管点目标建造走 `ui_ability_cast_position_request`，普通英雄技能调用 `Abilities.ExecuteAbility` 交回引擎处理目标模式。
9. **战斗属性 UI 使用显式单位边界。** 运行时 `runtime_armor` 始终是 Dota 实际护甲；发送给 UI 的 `armor` 始终是 War3 显示护甲，并由 `ui/combat_stat_projection.lua` 统一转换。禁止各发布路径自行乘除 3。
10. **英雄面板攻击与引擎普通攻击允许双值投影。** CSV `base_damage_min/max` 是面板逻辑值；`damage_multiplier` 只投影到原生普通攻击的引擎基础攻击，不写入全局 DamageFilter，避免技能、光环和脚本伤害被扩大。
11. **英雄攻速配置权威。** `attack_speed` 表示每秒攻击次数；UI 值由配置 BAT、固定间隔变化和装备攻速百分比计算，禁止通过 `GetSecondsPerAttack()` 反推。
12. **UI 快照投影必须幂等且不修改权威快照。** 投影结果使用 `stat_units_version` 标记，重复同步不得二次放大护甲。
13. **建筑通用规则由生成配置驱动。** `config/buildings_config.lua` 只负责组装运行时结构；`max_count`、`requires_city_level` 和 `population_cost` 必须优先读取 `config/generated/building_definitions.lua`，手写值仅作缺失回退。
14. **建筑数量上限按队伍共享。** 计数键保持为 `counts[team][building_id]`；施工开始后占用名额，建筑死亡或施工失败后释放。`max_count=0` 明确定义为无限制。
15. **Panorama 源码与游戏产物严格分离。** 源码修改在 `content\dota_addons\survival\panorama` 中完成；`game\dota_addons\survival\panorama` 只存放游戏加载的 `.vjs_c`、`.vcss_c`、`.vxml_c` 等编译产物。
16. **Panorama 修改必须强制定向编译并检查汇总。** 对已存在且时间戳可能混乱的产物使用 `resourcecompiler.exe -f`；只有 `compiled > 0` 且 `failed=0` 才作为本轮重新编译的明确证据，单独出现 `skipped` 不作为充分证据。
17. **官方攻击、攻速与护甲覆盖层统一采用攻击力数字格式。** 三项共用权威数字样式和原生数字 Label 定位规则；护甲与攻速不得再使用图标候选位置推算。统一仅限文本表现，不改变三项数值语义、三围或原生图标。
18. **PowerShell 参数必须跟随可执行程序。** `-NoProfile -ExecutionPolicy ...` 不能作为独立命令；外部调用应以 `powershell.exe` 或可用的 `pwsh` 开头，已在 PowerShell 会话内时可使用调用运算符 `&` 执行脚本。
19. **技能 Tooltip 由项目代理控制，角色属性 Tooltip 取消，背包只接管气泡表现。** 官方 AbilityN 仅作为技能几何/生命周期锚点；攻击、护甲和攻速节点保留显示但关闭命中；官方背包在完整物品输入链完成前不得隐藏或接管操作。
20. **Tooltip 动态内容由权威状态变化驱动。** NetTable 和 CustomGameEvent 更新时只刷新当前可见 Tooltip；禁止使用固定 `0.03s`、`0.35s` 等循环持续重绘动态数据。
21. **人物属性只保留权威显示，不接管结算，也不显示详细 Tooltip。** 保留 Valve `stats_container`、图标和选中单位生命周期；攻击、护甲、攻速和三围继续消费统一服务端投影，禁止为了显示修改引擎属性。
22. **护甲显示继续使用显式双值边界。** 面板值使用 `armor`（War3 显示单位），实际结算使用 `runtime_armor`；即使 Tooltip 已取消，客户端仍不得再次执行 War3/Dota 护甲换算。
23. **物品动态 Tooltip ViewModel 由服务端按 `content_id` 生成。** `survival_weapon_snapshot` 保留旧字段并追加 `tooltip_view_model`；Panorama 只负责渲染，客户端旧字段拼装仅作为热重载兼容回退。
24. **Tooltip 绑定恢复与数据刷新分离。** 选中单位或物品节点结构变化可以触发有限绑定恢复；资源、成长和实例数值变化只刷新当前可见扩展，禁止借数据更新重新扫描完整 HUD。
25. **AI 工作上下文必须增量落盘。** `START_HERE.md` 是唯一恢复入口，`CURRENT_TASK.md` 只保存单一活跃任务，`SESSION_LOG.md` 追加关键研究检查点。不得将长时间计划研究只保留在聊天中，也不得等任务全部完成后才记录结论。
26. **恢复时禁止用猜测填补丢失聊天。** 已确认事实、推断和未知项必须明确分开；缺少断开前任务时应收集最小用户线索并先落盘，而不是根据旧任务摘要擅自续写。
27. **角色属性详细 Tooltip 已取消。** 删除攻击、护甲、攻速、力量、敏捷、智力的悬停详细说明，但必须保留官方图标、项目权威数字覆盖和服务端战斗属性快照链。
28. **背包 Tooltip 只接管表现，不接管物品操作。** 项目气泡消费 `content_id` 与服务端 ViewModel；官方背包继续负责使用、拖放、换位、丢弃和出售，任何悬停绑定都不得用可命中覆盖层阻断这些输入。
29. **挑战材料的引擎物品映射只允许来自 `item_definitions.csv`。** 合成宝石、熔火核心 Lv1～Lv4、冰魂焰魄的地面真实物品创建、背包壳补建和拾取壳采用均读取生成配置；禁止恢复 Lua 手写材料映射。
30. **专属材料实体只有带新地面奖励标记时才能登记逻辑库存。** 掉落服务创建时设置 `survival_ground_reward=true`，成功 Claim 后清除；已有背包材料被玩家丢下再拾取时必须走官方物品移动，不得再次发放 `content_id`。
31. **官方世界物品 Tooltip 通过真实已注册 item ability 提供。** 地面材料使用 `CreateItem(engine_item_name)` 和 `CreateItemOnPositionSync`；`ItemLaunch`/`LaunchLoot` 仅可作为可选运动效果，不是运行时物品定义或 Tooltip 来源。
32. **项目技能接管使用固定 cell、左上角对齐的单行网格。** 每个技能 cell 固定 52×52、间距固定；技能数量只改变整行向右延伸的宽度。整行位置使用官方 `abilities` 容器左上角；Valve `AbilityN`/`AbilityButton` 只用于完整映射、视觉顺序和官方视觉压制，不得再次把官方动态宽高或随数量变化的按钮底边复制到项目行。历史 65×65 基线已被实机判定偏大，不得恢复。
33. **Valve 物品 Tooltip 元数据必须来自静态注册资源。** Lua 实例字段只承载业务身份与权限，不得假设存在运行时名称、说明或图标 setter。排查世界 Tooltip 时必须同时记录 `CreateItem` 请求名、`GetAbilityName()` 实际名和客户端 `$.Localize()` 结果。
34. **本地化文件必须进入引擎标准加载路径。** Valve 游戏/世界 Tooltip 使用 `game/dota_addons/survival/resource/addon_<language>.txt`；Panorama 诊断和自定义 UI 使用 `panorama/localization/addon_<language>.txt`。不得只修改不会被这些消费者加载的 `resource/localization/` 镜像。
35. **英雄商城饰品使用“本机资源取证 + 基础骨骼上的命名 wearable”方案。** 先通过 defindex 确认 Bundle 子物品和槽位，再从当前 `pak01_dir.vpk` 以英雄目录、发布时间开发代号、模型/材质/图标/粒子交叉验证真实路径；展示名不得直接当资源目录名。运行时保留英雄主体骨骼与动画，以项目创建的 `prop_dynamic`、`SetOwner` 和 `FollowEntity(hero, true)` 挂载 wearable。商城视觉像全身套装时也必须尊重实际槽位：`The Hallows Within` 已实机证明是单个大型 Head wearable，不得虚构多个身体组件或用 `SetModel` 替换英雄主体。
36. **项目饰品生命周期必须幂等且严格限定身份。** wearable 和粒子按英雄 entindex 保存；重复应用先销毁/释放项目粒子并删除项目 wearable；粒子通过命名 owner 绑定对应 wearable。开局/重生接入必须校验目标英雄单位名、玩家身份和已初始化 entindex，禁止仅按 Undying 模型或单位名批量应用到修理工、波次怪、僵尸和 Boss。
37. **需要逐单位穿透命中的移动路径技能使用引擎线性投射物。** `ParticleManager:CreateParticle()` 创建的 VPCF 只是视觉系统；粒子中的 `C_OP_MovementPlaceOnGround`、场景碰撞组或渲染包围范围不能当作 Lua 可监听的单位伤害碰撞体。类似维鲁斯 Q、火焰吐息或炙热巨箭的直线穿透技能，应使用 `ProjectileManager:CreateLinearProjectile()`，显式设置起止半径、距离、速度和目标过滤；穿透技能必须同时设置 `bDeleteOnHit=false`，并在每次 `OnProjectileHit[_ExtraData]` 单位回调中返回 `false`。每支投射物用唯一 ID 保存权威伤害和已命中 entindex，逐目标进入既有伤害服务；禁止用固定时间提前量或视觉粒子原点推算命中。
38. **英雄三维是项目逻辑数据，不是 Dota 原生属性。** 力量、敏捷、智力及全属性只保存在 progression、装备聚合和战斗属性快照中，用于 UI 与明确声明按三维结算的技能/装备效果。禁止调用 `ModifyStrength/ModifyAgility/ModifyIntellect`，也禁止通过 modifier 的原生三维 bonus 投影逻辑三维，否则会隐式改变攻速、护甲、生命、魔法和主属性攻击。技能必须通过 `HERO_COMBAT_STATS_GET_REQUEST` 读取逻辑三维，禁止优先读取 `GetStrength/GetAgility/GetIntellect`。
39. **技能逻辑状态与引擎 ability 同步必须事务化。** 授予或升级技能时，`levels/order/skill_points/version` 与 `AddAbility/SetLevel/SetAbilityIndex` 属于同一个事务；引擎同步异常必须回滚逻辑状态并恢复旧 ability 集合。禁止先永久提交逻辑状态、再把可能抛错的引擎同步留在事务之外。Lua `ipairs` 循环需要索引时不得用 `_` 丢弃后再引用未定义的 `index`。
40. **模块加载顶层不得假设 GameModeEntity 已存在。** `GameRules:GetGameModeEntity()` 在 `Activate()` 前可能返回 nil；依赖 GameModeEntity 的启动规则应在顶层安全标记 deferred，并在 `Activate()` 阶段强制成功，否则中止初始化，禁止带着半配置状态继续运行。
41. **英雄战斗属性快照必须原子刷新并拒绝倒退。** 英雄攻击、护甲、攻速和逻辑三维来自同一份 `hero_combat_stat_service` 权威快照；选中单位即时响应不得用某一引擎帧的 `GetPhysicalArmorValue()` 或其他临时值覆盖其中单个字段。英雄快照携带单调 `refresh_version`，Panorama 同一选中单位只接受不旧于当前版本的快照；已有版本后到达的无版本快照也必须拒绝。非英雄单位仍可通过独立运行时快照反映临时 modifier。
42. **含中文的配置 CSV 必须使用明确编码链并从权威源恢复。** `data/csv` 中的中文配置统一按 UTF-8/UTF-8 BOM 读取（构建器可兼容 `utf-8-sig`、UTF-8 和历史 GB18030/GBK 输入），生成 Lua 必须由 `tools/build_configs.py` 重新生成，禁止手改 `scripts/vscripts/config/generated`。发现 `�`、`��`、`锟斤拷` 或类似 CP936/GBK 误解码文本时，不能只“另存为 UTF-8”掩盖损坏，必须从 Git 或其他已确认权威源恢复中文，再做编码、列数、生成结果和 Lua 语法校验。PowerShell 读写中文源码时必须确认使用 PowerShell 7 或明确的 UTF-8 字节读写，禁止用 Windows PowerShell 5.1 默认编码整文件重写。
43. **带移动父载体的分段视觉必须在阶段边界立即销毁。** `DestroyParticle(index, false)`只停止发射，不会清除已生成且仍有寿命的父载体或其子系统；若父粒子通过`C_OP_BasicMovement`和`C_OP_SetChildControlPoints`驱动完整子效果，已有载体会越过Lua定义的阶段终点继续外推。此类纯视觉实例在换段、正常终点、异常和重置时统一使用`DestroyParticle(index, true)`后再`ReleaseParticleIndex`；视觉清理不得改变权威投射物、命中、伤害、波数或时序。

44. **英雄即时普通攻击使用显式近战能力，不使用极高弹速模拟。** `hero_attack_projectiles.csv.attack_capability`是攻击能力权威字段；需要攻击前摇后立即结算时配置`melee`并保留原生攻击链，攻击距离由独立CSV射程和现有射程Modifier投影。禁止通过30000等极高速度、0速度暗号或手写伤害模拟近战即时命中。
45. **英雄普通攻击飘字只显示最终实际伤害。** 暴击概率与倍率保持attack record身份并通过仅作用于普通攻击的`MODIFIER_PROPERTY_DAMAGEOUTGOING_PERCENTAGE`投影，避免Valve原生`PREATTACK_CRITICALSTRIKE`显示减甲前数值；护甲、吸血、攻击事件和项目DamageFilter仍走原链路。最终`OnTakeDamage.params.damage`决定白色普通字或橙色暴击字，技能与脚本伤害不得伪装为平A飘字。
46. **科技研究必须在进度结束后原子提交等级和效果。** Begin阶段由服务端完成条件校验与原子扣费，只创建一次性事务，不改变等级、效果或发布完成事件；同一队伍在事务结束前只能存在一项研究。计时结束后以服务端`transaction_id`提交，提交异常必须恢复旧等级/效果并退款，重复或迟到回调不得二次升级。成功提示、等级事件和效果刷新只能发生在Commit成功后。Panorama只显示服务端研究进度，禁止用客户端倒计时决定升级；旧`technology_cooldown_*`字段仅作为兼容名称保留，其语义为研究进度而非购买后冷却。
47. **Panorama HUD展示选择与Ability输入选择使用不同身份边界。** HUD属性链使用有效非占位portrait，即使敌方单位或树木不在`Players.GetSelectedEntities()`；技能、Builder、Grid和建筑移动只使用可控选择解析器。两条链可以共享底层工具，但不得共用一个会拒绝敌方query单位或允许敌方成为caster的最终解析结果。
48. **攻击触发的装备范围效果以主攻击业务事件和战斗快照为权威。** 只响应`HERO_MAIN_ATTACK_LANDED`并防御性排除次级攻击；每次业务攻击按`attack_id`有界去重，不能永久保存可复用的裸record。按三维结算时必须在触发点读取`HERO_COMBAT_STATS_GET_REQUEST`，AoE中心由效果语义明确指定，逐目标进入统一伤害事务并检查结果。粒子和声音只提供一次性反馈，必须与权威范围查询和伤害隔离。
51. **转职塔人口使用占有模型。** 防御塔 CSV 使用 `population_cost`（人口消耗），生成 Lua 映射为 `population_occupied`（人口占有）。基础箭塔占有 0，任意转职塔等级占有 1；升级按目标与当前占有差额原子结算，塔死亡或融合时释放，禁止再将该字段增加到人口上限。
49. **遭遇难度战斗值按目标身份和难度快照解析。** 练功房、特殊目标、转生Boss及十戒Boss的生命、攻击、War3护甲来自`challenge_combat_profiles.csv`的`difficulty_id + member_id`行；挑战session固定`wave_system`难度，独立转生生成在创建Boss前读取同一难度。已纳入Profile的目标缺少当前难度行时必须在生成单位前失败关闭，禁止回退原型或其他难度；未纳入Profile的旧遭遇继续使用原型。War3护甲只在单位生成边界转换一次。
50. **完整复刻本体的召唤英雄或永久分身必须镜像combat system最终结果。** 同一次`HERO_COMBAT_STATS_GET_REQUEST`快照是攻击、最终攻速、暴击、逻辑三维和最大生命的唯一原子来源；召唤物侧不得重新组合BAT、装备攻速百分比、伤害倍率或原生三维。需要实际普通攻击值时由`hero_combat_stat_service`发布最终引擎攻击上下界；生命复用隐藏生命Modifier；选中UI按严格分身身份读取owner快照。数值镜像不得通过挂本体全套Modifier实现，装备、公共技能、转生和其他事件链必须继续显式隔离。
## 游戏行为决策

1. 合成宝石、熔火核心和其他非武器材料允许丢弃；武器不可丢弃。
2. 召唤英雄必须具有正确玩家 owner，但不能通过禁止选择建筑/农民来解决 owner 问题。
3. 挑战 07 使用与冰霜之地相同的 `maintain_count` 刷新方式：场内维持 10 只，成员配置的 0.5 秒刷新优先于通用挑战 2 秒规则。
4. 挑战 07 每只怪物独立进行 20% 判定，只掉落 `material_molten_core_01`；Lv2/Lv3 由 3 合 1 配方产生。
5. 挑战 08 是单 Boss 挑战；Boss 完成奖励应直接掉落 `material_molten_core_04`，不再使用旧的抽象升级宝石 `item_molten_upgrade_gem_04`。
6. 挑战 08 的 Lv4 核心应复用挑战 05/09 的地面奖励流程：Boss 死亡位置掉落、拾取入库、满足配方自动合成。

## 测试决策

- 随机概率通过注入固定随机函数测试边界，不依赖实际随机结果。
- 地面奖励测试必须覆盖权限校验、challenge/content 白名单、正确 owner/content_id 和幂等。
- 合成测试必须覆盖首次合成后继续合成、错误恢复和跨配方连续触发。
- 战斗属性测试必须同时覆盖逻辑显示值、引擎投影值、护甲双向转换和重复投影幂等性。
- 建筑配置测试必须覆盖生成字段进入运行时配置、达到上限拒绝、队伍隔离、死亡释放名额和零值无限制。
- Panorama 修改必须至少检查源码目标行、资源编译器汇总、编译产物时间戳/状态，以及限定路径的 `git diff --check`。
- 专属地面材料测试必须覆盖 CSV 映射、映射缺失失败关闭、真实引擎物品名、地面标记、首次壳采用、重复合并、登记失败释放和成功后清除防复制标记。
- 穿透线性投射物测试必须模拟同一 `ExtraData` 依次命中第一、第二、第三个单位，断言每次回调返回 `false`、每个单位各产生一次伤害、同一单位单波去重、终点/塔销毁后状态失效。只 mock `enemies_in_path()` 返回多个单位不能证明 Dota 引擎会产生后续单位命中回调。

## 2026-08-02 英雄基础生命投影决策

- CSV仍是英雄目标基础生命权威源，公式为`floor(base_health × max_health_multiplier × hero_meta_max_health_multiplier)`。
- `CreateUnitByName`召唤的原生英雄不得依赖`SetBaseMaxHealth/SetMaxHealth/SetHealth`维持权威基础生命；实机已证明引擎会恢复原生120生命。
- 使用隐藏、不可驱散、死亡不移除的`modifier_survival_hero_base_health`和`MODIFIER_PROPERTY_HEALTH_BONUS`，动态将原生最大生命补足到CSV目标。
- 补足必须扣除同一Modifier的旧补充值以保证重复应用幂等；不得固定增加CSV值，也不得创建会进入背包、库存、合成、Tooltip或存档的真实隐藏装备。
- 玩家真实装备生命在CSV目标基础生命之上继续独立叠加。
