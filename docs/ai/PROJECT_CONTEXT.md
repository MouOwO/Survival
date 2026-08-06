# Project Context

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
- 主城与召唤祭坛视觉权威源是`building_visual_levels.csv`；`buildings_config.lua`按`building_id+level`合并到`building_levels.csv`的战斗等级数据，建造完成和升级均复用`building_visual_service.apply()`。
- 普通建筑视觉表可直接使用`model_name/model_scale/model_yaw`，不强制进入复杂塔套装的`asset_catalog.csv`。当前`asset_catalog.csv`存在27列表头与大量22列历史行不一致，未修复前不得为普通模型任务强行生成或批量补列。
- 新增分级模型必须同步：CSV、生成Lua、运行时消费者、模型预缓存和单位KV的LV1回退；模型路径需从当前`pak01_dir.vpk`索引确认，自动验证不能代替Workshop Tools中的尺寸、动画和朝向验收。
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
- 工作目录：`d:\steam\steamapps\common\dota 2 beta\game\dota_addons\survival`。
- 服务端主要使用 Lua，配置权威来源位于 `data/csv`，生成配置位于 `scripts/vscripts/config/generated`。
- 配置修改规范：优先修改 CSV，再运行 `build_configs.bat`；运行时服务通过 `core/event_bus.lua` 解耦。
- 内容库存以 `content_id` 为权威身份，Dota 物品实体只是可见背包壳。
- 英雄力量、敏捷、智力是项目逻辑三维：由服务端战斗快照统一计算和发布，不写入 Dota 原生三维。逻辑三维本身不提供攻速、护甲、生命、魔法或主属性攻击，只供 UI 和明确按三维结算的技能/装备效果读取。
- Panorama 源码不在当前 `game` 插件目录中，而在对应的内容目录：`D:\steam\steamapps\common\dota 2 beta\content\dota_addons\survival\panorama`。
- 游戏实际加载的 Panorama 编译产物位于：`D:\steam\steamapps\common\dota 2 beta\game\dota_addons\survival\panorama`。
- 当前Lua 5.1解释器/检查器为`C:\msys64\mingw64\bin\lua5.1.exe`与`C:\msys64\mingw64\bin\luac5.1.exe`，均已在2026-08-04实际执行确认版本5.1.5；目录未加入PATH，必须使用绝对路径。旧`C:\Program Files\lua\bin`记录当前已失效。

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
10. 防御塔升级按钮会随 `RESOURCE_CHANGED` 实时刷新；`population_delta` 只表示升级后的最大人口奖励，不参与升级成本判断。
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
