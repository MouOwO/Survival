# 02 核心玩法与数值维护契约

核对时间：2026-10-28（北京时间）。本次只读核对桌面 20261024 知识包、本仓库 CSV/Lua 和近期验证文档，没有启动游戏、运行交易或检查云数据库。本文的“当前源码”指开发工作区；某个冻结工坊版本是否包含同样配置，须另查其签名清单与发布记录。

路径以 game 仓库为根；`core/`、`systems/`、`config/`、`combat/`、`research/` 均为 `scripts/vscripts/` 下的缩写。可编辑地图单独位于 content 仓库。

证据分三层：**已确认规则**是用户决定；**源码已核对**是本次读取到的实现/配置；**实机已验证**只能引用明确版本和范围的现场证据，不能由前两者推导。旧知识包中的“仅单人、普通游廊多人未验证”已过期：2026102708 有原生双人入口、登录与云档证据，2709 有加入方手机扫码商品/金额正确的用户确认；2802 地图版只有本轮主机载图烟测，不等于全图、完整守波、双人布局或付款到账验收。当前发布状态以 `publishing/workshop/test_listing.json` 及相应 release_record 为准。

## 1. 游戏主循环与玩家归属

主循环为：真实玩家就绪 → 身份/资源准入 → 房主选择模式及队伍可用难度 → 对应战斗档案就绪 → 基地经营、工人与塔、英雄构筑 → 波次与挑战 → 个人败退或通关 → 存档挑战与持久结算。

队友同阵营，但经济、人口、建筑、英雄、训练、装备、怪物计数和奖励按真实 `player_id`/账号隔离。不要把全队合作理解成共享同一个钱包、档案、月卡或认证凭据。实体归属必须由服务器记录和引擎句柄确认，不能使用客户端上报的 PlayerID、选中目标或最先到达的请求替代权限。

启动有两道业务门禁：第一道确认完整真人名单、认证、实际资源预载和客户端握手；选模式后第二道 `gameplay_gate` 等待该模式档案，才释放建造者/英雄业务初始化和项目 `GAME_STARTED`。引擎阶段仍可能自行进入 `GAME_IN_PROGRESS`，这不是业务已放行的证据。当前原生自动入口另有跨换图完整名单屏障，详见模块10。

源码入口：`scripts/vscripts/addon_game_mode.lua`、`systems/startup_loading_service.lua`、`systems/match_setup_service.lua`、`systems/team_difficulty_service.lua`、`systems/player_profile_service.lua`（后文省略路径均位于 `scripts/vscripts/`）。

## 2. 模式、难度与验收局隔离

当前 `config/mode_release_config.lua` 开放 `standard` 常规、`pure` 纯净、`rich` 丰饶、`cold` 极寒；`scourge/ruins/celestial/fishing` 有部分配置不代表战斗模式已经发布。当前 v3 难度行范围为常规/纯净 N1–N10、丰饶 N1–N30、极寒 N1–N50；具体总波数取该模式、难度的 `human_monster_spec` 行，不能沿用旧 `waves_config.lua` 的通用30波回退。

**当前开发配置 `all_difficulties_unlocked=true` 仍存在。** 它对已发布模式开启全难度只读验收，绕过正常入场进度/额度，并把账户写入隔离到本局结束。不能通过中途改开关把验收收益变成正式存档，也不能把该开发配置当成线上冻结包的实际开关。

正常进度规则（上述验收开关关闭后）是：丰饶入场需任意已认证战斗模式持久通关 N3，极寒需 N5；入场后 N1–N4 开放，N5起要求**所选模式**前一难度已通关。缺独立模式进度表表示后端未支持；显式空表不继承别的模式成绩。常规仅在专属表不存在时兼容旧 `clear_counts`。队伍权限取完整参局真人名单的交集，掉线不能偷偷移出名单来提高难度权限；全局与模式日限额共同约束正常入场。

丰饶/极寒沿用常规战斗投影，但持久模式身份与通关表独立；纯净压制历史永久战斗加成，资格和商城仍使用认证的永久账号视图。维护入口：`config/mode_progression.lua`、`config/difficulty_config.lua`、`config/mode_release_config.lua`、`systems/match_setup_service.lua`、`systems/player_profile_service.lua`。

## 3. 金币、木材、人口与建筑

`systems/resource_system.lua` 的账户按玩家维护。CSV 的兜底初始值为金币0、木材10、已用人口0、人口上限0；实际初始化还会应用档案、建筑与权益，不能把兜底值硬编码成所有玩家最终开局资源。档案 `initial_wood` 是完整起始值，不是额外再发一次基础木材；档案重复刷新只应用有意义的差额。

局内金币/木材/人口与商城钱包、积分是不同业务数据；购买成功不能直接修改客户端数字来代替服务端资源或永久档案事务。资源不足、前置不足、排队待扣款和真实交易失败应保留不同状态。

当前 `data/csv/建筑与工人系统/building_definitions.csv`：墙、主城、农场、普通/高级研究所、挑战建筑、祭坛基础各1；金矿基础5、主城3级、占2人口；祭坛和高级研究所需主城4级。高级研究所与挑战还检查已完成的普通研究所。每玩家防御塔总计7座，包含基础塔、转职塔、终极塔；每路线5座是另一层限制。订单/施工预占名额，转职不释放，死亡/销毁才释放。部分权益可改变金矿等上限，价格以实际等级/科技行和执行服务为准，不能仅看 notes。

金矿按所属玩家发金币，产量、效率、暴击、周期、永久修正分层计算。`gold_mine_config.lua` 实际读取生成的 `building_levels`、`technology_definitions` 等表，不能看到另一个 `gold_mine_levels.csv` 文件就认定它是唯一运行来源。`gold_mine_rules.csv` 当前字段为周期1秒、`crit_multiplier=2`；同一行旧注释仍写“130%”，文案与字段不一致时沿配置和服务调用链核对，不能据注释擅改经济。

维护入口：`systems/building_system.lua`、`systems/building_population_service.lua`、`systems/player_tower_limit_service.lua`、`systems/gold_mine_system.lua`、`config/gold_mine_config.lua`。

## 4. 训练、合成与研究

主城串行训练队列容量当前默认7（1个当前任务、6个等待位）。入队预占训练数量，队首实际启动时扣货币与人口；待资源队首不是已完成训练。取消/失败只退已扣部分一次，旧计时回调以代际失效。队列快照和限额必须计入已排队任务，不能再把 active_job 重复加一次。

普通伐木工八阶的当前 CSV 基础值如下，权益/局内效果另算：

| 阶 | 木材 | 金币 | 人口 | 每次采木 | 基础数量上限 |
| --- | ---: | ---: | ---: | ---: | ---: |
| 1 | 10 | 0 | 1 | 1 | 5 |
| 2 | 100 | 0 | 1 | 2 | 3 |
| 3 | 500 | 0 | 1 | 3 | 3 |
| 4 | 1000 | 0 | 2 | 5 | 3 |
| 5 | 5000 | 100 | 3 | 10 | 3 |
| 6 | 12000 | 1000 | 3 | 20 | 3 |
| 7 | 30000 | 3000 | 3 | 40 | 3 |
| 8 | 50000 | 5000 | 3 | 80 | -1（不按普通有限数量处理） |

以上训练耗时字段均为1秒。超级工人由**同阶**普通工人合成：一阶需5名，二至八阶需3名；不是合成后自动升下一阶。前七阶配置性格池，第八阶无性格；材料、拥有者、主城和费用都在服务器复核。修理工只修复合法归属的受损建筑。

研究状态/效果按玩家维护；普通与高级研究所、自动研究、取消、前置和排队各走服务端逻辑。客户端钱包延迟不能吞掉合法操作，也不能因为按钮能点就认定已经扣费或升级成功；不足资源等待和前置未解锁分开处理。主要入口：`systems/worker_training_queue_service.lua`、`systems/lumberjack_fusion_service.lua`、`research/research_technology_service.lua`。

## 5. 防御塔与伤害结算

基础箭塔阶段末分七路线：死亡/暴击、神秘/激光、闪电、机枪、多重、冰霜、防空。显示品级不决定内部升级索引。快速跨级升级累加跨越行的金币/木材费用，人口只付当前到目标占用差额。终极“万象归一”需本人七路线终阶塔各1，防重入且每玩家最多1座。

索敌排除资源树、友军、死亡单位，检查真实距离及防空资格；优先 BOSS/进攻BOSS/波次首领，再比较距离和稳定索引，训练假人仅作无真实敌人的回退。不能为修复停攻重新放开原生乱打资源树。攻击节奏以秒为单位，固定减间隔和百分比攻速按既有顺序处理；动画播放和表现弹道不产生额外伤害授权。

伤害沿 `combat/damage_service.lua`、`combat/damage_filter_service.lua` 的事务路径区分普攻、持续、溅射、反射、纯表现。保留原始攻击者/目标；护甲、大数值缩放和倍率还原只处理一次，表现命中不得重复提交真实伤害。入口另见 `config/tower_route_config.lua`、`systems/tower_fusion_service.lua`、`systems/tower_targeting.lua`、`combat/attack_cadence.lua`、`config/armor_balance.lua`。

## 6. 英雄、装备、转生与局内构筑

每玩家最多1个战斗英雄，祭坛需主城4级；召唤检查归属、败退、权益、已有英雄、落点，异步模型预载后再检查。当前6个启用英雄为末日使者、光之守卫、斧王、黑暗游侠、齐天大圣、剑圣。历史 `hero_shadow_fiend` 实际显示光之守卫，不能按内部ID猜名字；道具解锁付费英雄不等于给全局 VIP。

逻辑背包、装备实例和物品ID是业务实体，原生物品只是载体。合成按玩家锁与 `request_id` 幂等，全量验料后在一次变更中扣料/产出；装备属性由统一服务聚合，避免逻辑装备与原生外壳加两遍。HTTP 权威房间不能本地改 save 后假报永久保存成功。

转生按挑战有效奖励依序推进；二至四转三选一，排除已有/满级，单次候选去重，公共技能容量10。开局建造者与 BOSS 肉鸽池分开按玩家维护，未选或重抽不等于永久移出池；效果需完整生命周期。十转年轮圣殿当前入场5万金币、持续每秒5万，15倍只作用于指定攻击/属性成长收益；暗影界仍只有传送，怪物和掉落未启用。个人房间 marker 优先，但仍有旧共享点回退，不能宣称所有地图都物理隔离。

入口：`systems/hero_summon_system.lua`、`systems/content_inventory_service.lua`、`systems/inventory_transaction_service.lua`、`systems/weapon_synthesis_service.lua`、`systems/equipment_instance_service.lua`、`systems/equipment_stat_aggregation_service.lua`、`systems/training_room_service.lua`、`systems/player_room_locations.lua`，以及英雄/物品/挑战类 CSV。

## 7. 波次、红翼修正、败退与终局

正式 v3 战斗数值优先链为 `wave_difficulty_builder.build` → `human_wave_profile.build` → `config/human_monster_rules.lua` → 生成的 `human_monster_spec.lua`。普通波次 CSV 此路径提供模型/路由模板，不再直接决定最终数值；`rich_stat_variants` 被清除，避免后续出生时再次覆盖公式结果。

**用户已确认：丰饶 N10 第8波红翼飞行恶魔小怪，最终生命1,420,000，攻击160,000。** 当前人话 v3 JSON 的 `special_rotation_stat_overrides` 与生成 Lua 都包含 `rich / difficulty=10 / wave_number=8 / position=2` 的这一覆盖，构造器在模式倍率之后覆盖生命/攻击，护甲/攻速保持原算法。只作用于该轮换位置的小怪，文档记录该路径20只，不改首怪、地面怪或其他模式/难度。

本次也核对了**旧 CSV 的实际值**：`rich_wave_definitions.csv` 的 `n10_wave_08_8n2` 仍为38只、生命224000、攻击25167；`8L` 首怪为2240000/100647，`8N1` 地面普通行为224000/25167。这不是“CSV已改成142万/16万”，也不能因此删掉正式 v3 覆盖或再乘倍率。维护时先判断命中哪条构造路径。双源依据为 `data/balance/human_spec_v3/human_spec.json`、同目录 v3 工作簿和 `tools/import_human_monster_spec.py`；说明见 `docs/balance/rich_n10_wave08_health_20261026.md`。本次没有重跑出生或原生数值验收，亦不据开发源码断言每个历史冻结包都包含新覆盖。

波次通道、目标墙、存活数和持续超限失败按玩家管理：当前90只、连续超限10秒，回落则重置；`global_rules.csv` 的“全场共享/全员失败”旧注释不覆盖 `wave_system.lua` 的个人实现。已完成墙死亡只淘汰登记所属玩家，归属缺失不能猜成0号，施工死亡不按成墙失败；败者观战，其余继续，全员失败才结束。

终局要求最后一波已全部生成、无生成失败、无待生成、无存活怪，漏生怪不能算胜利。胜利只结算一次，先冻结普通战斗及合格获胜名单，再逐玩家提交通关并衔接存档挑战。合作共享基础事件/随机结果，月卡、上限与凭据仍属每个玩家；未确认的账户命令保持待保存，不能用本地奖励动画替代数据库提交。

## 8. 继续开发时的操作入口

普通数值先改 `data/csv/`，再由 `tools/build_configs.py` 生成，禁止手改生成 Lua。v3 战斗双输入用 `tools/import_human_monster_spec.py` 交叉校验后生成 `normalized.json` 与 `human_monster_spec.lua`，修正只应用一次。CSV 有中文说明/类型行和 UTF-8、GB18030 历史编码，读取需沿现有导入器，不能把 `#types` 当业务行或批量重编码。

相关回归入口包括 `scripts/vscripts/tests/test_startup_loading_service.lua`、`test_difficulty_unlocks.lua`、`test_worker_training_queue.lua`，以及波次人口/终局、塔索敌、伤害事务、英雄归属、墙导航专项。本文只定位现有入口，不表示这些测试本轮已跑。修改哪个模块就验证其事务、多人归属和原生行为；模拟通过不替代真实碰撞、完整守波或异地延迟验收。

永久成长、抽奖、每日额度与账号事务见模块03；引擎 API、生命周期、原生入口与发布资源身份见模块10。未发布模式、暗影界战斗掉落、完整多人长局、迟加入/重连与独立网络基础设施保持独立待验事项。
