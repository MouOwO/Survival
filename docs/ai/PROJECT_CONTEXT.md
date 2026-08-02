# Project Context

## 项目与环境

- 项目：Dota 2 自定义地图 `survival`。
- 工作目录：`d:\steam\steamapps\common\dota 2 beta\game\dota_addons\survival`。
- 服务端主要使用 Lua，配置权威来源位于 `data/csv`，生成配置位于 `scripts/vscripts/config/generated`。
- 配置修改规范：优先修改 CSV，再运行 `build_configs.bat`；运行时服务通过 `core/event_bus.lua` 解耦。
- 内容库存以 `content_id` 为权威身份，Dota 物品实体只是可见背包壳。
- 英雄力量、敏捷、智力是项目逻辑三维：由服务端战斗快照统一计算和发布，不写入 Dota 原生三维。逻辑三维本身不提供攻速、护甲、生命、魔法或主属性攻击，只供 UI 和明确按三维结算的技能/装备效果读取。
- Panorama 源码不在当前 `game` 插件目录中，而在对应的内容目录：`D:\steam\steamapps\common\dota 2 beta\content\dota_addons\survival\panorama`。
- 游戏实际加载的 Panorama 编译产物位于：`D:\steam\steamapps\common\dota 2 beta\game\dota_addons\survival\panorama`。
- Lua 5.1 语法检查器位于 `C:\msys64\mingw64\bin\luac5.1.exe`，已验证版本为 Lua 5.1.5。该目录当前不一定在 PATH；不得仅因 `Get-Command luac` 或 `where luac` 无结果就断言环境没有 Luac，必须优先探测并使用这个绝对路径。

## AI 会话恢复协议

- 所有新会话必须首先读取 `docs/ai/START_HERE.md`，再按其中顺序恢复上下文。
- `docs/ai/CURRENT_TASK.md` 只描述一个活跃任务；完成或被替换后整体迁入 `docs/ai/archive/`。
- 深度研究不能只存在于聊天中；关键证据、排除项、未决问题和下一步必须持续追加到 `docs/ai/SESSION_LOG.md`。
- 用户需求发生变化、完成关键调查、作出重要决策、准备大范围修改/验证或会话可能中断时，必须先写检查点。
- 如果持久化文档与模糊会话记忆冲突，以文档中的用户原始需求和最新检查点为准，并向用户明确冲突，不得猜测。

## 常用命令与配置链

- Lua 文件语法检查使用：
  ```powershell
  & "C:\msys64\mingw64\bin\luac5.1.exe" -p "D:\steam\steamapps\common\dota 2 beta\game\dota_addons\survival\scripts\vscripts\path\to\file.lua"
  ```
- 多文件检查应逐个调用并在任一文件失败时终止；`luac5.1 -p` 成功时通常没有标准输出，应结合退出代码0判断通过。
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
- 公共技能 `proto_frost_nova` 已保留原ID并重做为五级“移动冰球”：主攻击命中12%概率触发，LV1以360速度直线飞向原目标触发位置，每0.5秒对300范围造成触发时全属性×2纯粹伤害；LV2速度540，每碰撞不同敌人使周期基础伤害+5%，最多10层；LV3范围350且所有飞行结束情形固定爆炸全属性×3，LV4继承；LV5最大移动距离为初始英雄到原目标距离的150%，在该范围随机索敌追踪，每实际移动100码使周期基础伤害+10%。LV5目标死亡后不重新索敌，而是锁定死亡位置并直线飞去后爆炸。周期成长不影响固定×3爆炸；活动冰球由一个0.05秒共享任务推进。
- 公共技能 `proto_flame_burst` 已保留原ID并重做为五级“爆炎弹”：主攻击命中15%概率在目标触发位置对500范围造成触发时全属性×4纯粹伤害；LV2每个主爆炸命中敌人获得一层3秒点燃，在第1/2/3秒结算且每层总倍率精确为×2.2，重复点燃替换旧层；LV3最多5层且每层快照与生命周期独立，第6层替换最早到期层，LV4继承；LV5主爆炸后同时喷射3颗小火球，0.5秒后同时落在中心200半径的均匀随机位置，每颗对250范围造成×3并分别施加点燃。小火球重叠时直接伤害和点燃均逐颗结算；三球共用一个同步落地任务。用户已实机确认整体效果良好并批准固化当前实现，除非后续出现明确问题不得主动改动。
- 公共技能 `proto_poison_cloud` 已保留原ID并重做为五级“毒云”：LV1/2主攻击命中12%概率在目标触发位置生成固定400范围毒云5秒，第1至第5秒各造成触发时全属性×1纯粹伤害；LV2起每次Tick增加20%实时总护甲降低，最多3层60%，离开、替换或到期立即移除；LV3触发率20%且持续7秒共7次，LV4继承；LV5毒云内敌人死亡时在死亡位置产生300范围×3纯粹伤害并允许连锁，每个死亡单位只触发一次。同一英雄只有一个毒云，新云替换旧云。实机确认`MODIFIER_PROPERTY_PHYSICAL_ARMOR_TOTAL_PERCENTAGE`未可靠反映到项目自定义护甲UI读取的`GetPhysicalArmorValue(false)`，现使用已验证的`MODIFIER_PROPERTY_PHYSICAL_ARMOR_BONUS`，每次共享同步先加回毒云自身旧减甲，再按排除毒云后的实时护甲绝对值重算20%/40%/60%；不得改回进入时护甲快照或不可靠的总百分比属性。
- 公共技能 `proto_blade_nova` 已保留原ID、`ability_survival_blade_nova`和显示名“剑刃震荡·被动”，重做为五级“脉冲激射”：LV1主攻击命中15%概率沿触发瞬间英雄面向发射总宽200、长度为英雄攻击射程的穿透脉冲，对路径内敌人造成触发时全属性×4纯粹伤害；LV2每道最先命中的目标伤害翻倍；LV3按目标沿脉冲方向的投影距离线性提高，近端×4、末端最高×8；LV4完整继承LV3；LV5射程提高50%，每次触发30%概率将单道替换为同路径完全重合的3道脉冲，每道独立结算首目标、命中去重与完整伤害，同一敌人可承受3次且无衰减。实现使用原生`CreateLinearProjectile`、半宽100、`bDeleteOnHit=false`，并按实际射程动态计算速度使脉冲固定1秒走完全段。用户已于2026-08-02确认技能制作完成，除非出现明确新需求或实机问题，不主动修改当前基线。
- 英雄科技攻击减甲 `researcher_hero_armor_reduction` 使用War3显示护甲配置并由`armor_balance.from_war3`转换为Dota结算护甲；19级为每击9.5显示护甲（约3.1667底层护甲）。普通波次怪、挑战怪、遭遇怪及`addmonster`未显式配置`minimum_armor`时不得写入默认护甲下限；只有树木和明确配置下限的单位才限制累计减甲。科技减甲UI事件必须延迟到下一Scheduler帧，并在项目英雄权威快照路径覆盖当前有效护甲字段。
- 魔法弹弓的射程读取不得只依赖 `GetAttackRange()`：当前 `CreateUnitByName`召唤英雄由`hero_stat_adapter`通过`Script_SetAttackRange`写入配置，但实机曾读取到`GetAttackRange()==0`。权威回退顺序包含`unit.survival_attack_range`、`Script_GetAttackRange()`、`GetAttackRange()`和`config/generated/hero_definitions.lua`的`attack_range`，取最大有效正数；本次合法命中的敌方主目标始终作为保底候选。实机已确认`range=3000 selected=1 launched=1`，尚待确认`MAGIC_SLINGSHOT_HIT`。
- `hero_skill_pool_members.csv` 使用 UTF-8 BOM，以兼容 Office/Excel 双击打开；配置生成器的 `utf-8-sig` 读取保持兼容。
- 英雄伤害测试面板除原“累计/最近伤害”外，独立显示英雄技能的累计伤害、最近一次伤害和命中次数；统计使用 `OnTakeDamage` 的最终实际伤害，被动技能伤害请求必须携带对应 Ability handle 以区别普通攻击。
- 测试聊天命令 `addskill` 将当前玩家技能点直接设置为10；未召唤英雄时拒绝执行，重复输入仍保持10点。
- 英雄公共技能池独立上限为3，英雄总技能容量仍为配置中的10；候选生成和最终授予均由服务端检查，达到3个后转生随机技能奖励正常跳过，技能点奖励不受影响。
- 重构采用分阶段可回滚方式：先建立共享快照/Tooltip ViewModel，再接管人物逻辑属性悬停，最后将技能/物品 Tooltip 改为原生优先与事件驱动扩展。
- 角色属性详细 Tooltip 已按用户最新要求删除；`combat_stats.js` 继续直接显示服务端权威攻击、护甲、攻速与三围数值，不再发布 `SurvivalCombatStatsStore`。
- 第二阶段已新增 `ui/tooltip_view_model.lua`，由 `weapon_synthesis_snapshot_service.lua` 把动态物品字段发布到 `survival_weapon_snapshot.tooltip_view_model`。
- 技能由独立 `hud_takeover.js` 代理完全控制 Tooltip；背包由独立 `inventory_tooltip.js` 在保留 Valve 操作的前提下显示项目气泡，动态内容只在权威状态变化时重绘。
- 最新最终验证：30 个 Lua 测试全部通过，相关 Lua 语法检查和限定路径 `git diff --check` 通过；本轮相关 JS/CSS 和 HUD XML 已强制编译到游戏目录，均为零失败、零跳过。

## 已完成的重要工作

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