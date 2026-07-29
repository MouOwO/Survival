# Archived Tasks: Tooltip Refactor and Prior Work

> 本文件由原 `docs/ai/CURRENT_TASK.md` 于 2026-07-28 原样归档。除标题与本说明外，以下内容保留迁移时状态，可能同时包含多代任务，不再作为当前恢复入口。

## 状态

**Tooltip 分阶段重构已完成，Lua 回归测试、语法检查和 Panorama 强制编译均已通过。**

## 当前任务：Tooltip 事件驱动与原生 HUD 扩展

1. 保留 Valve 原生人物属性区域，只接管攻击、护甲、攻速、力量、敏捷和智力的项目逻辑 Tooltip。
2. 护甲显示继续使用 War3 UI 值，实际减伤说明基于 `runtime_armor`，不得修改引擎护甲或核心伤害结算。
3. 技能和物品 Tooltip 改为“原生基础信息优先，复杂实例数据使用自定义扩展层”，避免长期全量压制原生 Tooltip。
4. 成长进度、装备实例和运行时费用等动态内容必须由 NetTable/CustomGameEvent 变化驱动可见 Tooltip 更新，不再依靠固定周期重绘。
5. 官方 HUD 节点在选中单位切换时可能被 Valve 重建；允许使用低频、按需的绑定恢复作为兼容兜底，但禁止恢复 `0.03s`/`0.35s` 的持续刷新循环。

## 当前检查点 1：基线审计

- `ability_tooltip.js` 当前每 `1.0s` 扫描绑定，每 `0.35s` 重绘可见 Tooltip。
- 物品悬停期间当前每 `0.03s` 调用隐藏原生 Tooltip，并递归关闭物品槽后代命中。
- `combat_stats.js` 已有 `selectedUnitSnapshot`，并同时接收英雄 NetTable 与 `ui_selected_unit_stats_snapshot` 即时事件。
- `combat_stat_projection.lua` 已统一输出 `armor`、`runtime_armor`、`armor_unit` 和 `stat_units_version`。
- 已完成第一阶段人物属性 Tooltip：
  - `combat_stat_projection.lua` 新增 `stat_tooltips`，同时保留旧平铺字段；
  - 护甲标题使用 War3 显示值，实际物理减伤根据 `runtime_armor` 使用 Dota 护甲公式计算；
  - 新增 `hero_stat_tooltip.js`，使用 Valve `DOTAShowTitleTextTooltip` 显示攻击、护甲、攻速和三围说明；
  - `combat_stats.js` 通过共享 `SurvivalCombatStatsStore` 在快照到达时发布，在选中单位变化时清空；
  - 三围 Tooltip 绑定项目创建的逻辑属性行，不恢复已隐藏的原生 `stragiint`。
- 已扩展 `test_combat_stat_projection.lua`，覆盖 Tooltip ViewModel、负护甲和重复投影；测试输出为 `COMBAT_STAT_PROJECTION_PASS`。

## 当前检查点 2：技能/物品事件驱动扩展

- 已删除 `ability_tooltip.js` 的物品 `0.03s` 原生压制循环、可见 Tooltip `0.35s` 重绘循环和永久 `1.0s` 绑定扫描。
- 普通技能与普通物品恢复 Valve 原生 Tooltip；只有存在服务端运行时状态的能力、托管建筑操作和带项目 `content_id` 的物品显示“项目扩展”侧栏。
- 项目技能/物品不再用自定义面板替代原生基础说明：官方 Tooltip 显示名称、图标和基础描述，项目侧栏显示动态费用、状态、成长和实例字段。
- 新增 `ui/tooltip_view_model.lua`；`weapon_synthesis_snapshot_service.lua` 在 `survival_weapon_snapshot.tooltip_view_model` 中发布按 `content_id` 聚合的动态字段。
- 当前成长扩展覆盖：当前/剩余进度、累计成长攻击、每次攻击进度和锻造锤数量；旧平铺快照字段继续保留，客户端还有热重载兼容回退。
- 可见扩展仅在 `survival_ability_runtime`、`survival_weapon_snapshot`、`survival_inventory_item_identity` 或 `ui_weapon_synthesis_snapshot` 变化时刷新。
- HUD 绑定恢复仅在首次加载有限重试、选中单位实际变化和物品身份节点变化时触发；成长/资源变化不会重复扫描官方 HUD。
- 托管建筑技能的透明点击代理和 `ui_ability_cast_request` 链完整保留。
- 新增 `test_tooltip_view_model.lua`，测试输出为 `TOOLTIP_VIEW_MODEL_PASS`。

## 最终验证结果

- 全量 29 个 `scripts/vscripts/tests/test_*.lua`：`ALL_LUA_TESTS total=29 failed=0`。
- `combat_stat_projection.lua`、`tooltip_view_model.lua`、`weapon_synthesis_snapshot_service.lua`：`luac -p` 成功。
- `git diff --check`：通过，仅有 Git 的 LF/CRLF 工作区提示，无空白错误。
- `ability_tooltip.js`：`OK: 1 compiled, 0 failed, 0 skipped`。
- `hero_stat_tooltip.js`：`OK: 1 compiled, 0 failed, 0 skipped`。
- `combat_stats.js`：`OK: 1 compiled, 0 failed, 0 skipped`。
- `ability_tooltip.css`：`OK: 1 compiled, 0 failed, 0 skipped`。
- `survival_hud.xml` 及依赖：`OK: 7 compiled, 0 failed, 0 skipped`。
- 编译产物已更新到 `D:\steam\steamapps\common\dota 2 beta\game\dota_addons\survival\panorama`，时间戳为 2026-07-28 09:21:58（本地时间）。

## 仍需实机确认

- Workshop Tools 中分别选中英雄、建筑和农民，确认六项人物属性 Tooltip 均绑定到正确行。
- 在常用 16:9 分辨率及不同 HUD 比例下，确认 Valve 原生 Tooltip 与右侧“项目扩展”不重叠。
- 确认当前 Dota 客户端版本支持 `DOTAShowAbilityTooltipForEntityIndex`，项目物品能同时显示原生基础层和项目扩展层。

## 用户当前需求

1. 截图中英雄面板的攻速数值和护甲数值需要同时向上移动 6px。
2. 不能影响攻击力、力量、敏捷、智力或原生图标的位置。
3. Panorama 源码修改后必须重新编译游戏目录中的 `.vjs_c`。

## 本次定位与实施结果

- 截图中的攻速和护甲并非独立 XML 面板，而是 `combat_stats.js` 挂载到官方 `AttackSpeed`、`Armor` 行上的权威文本覆盖层。
- 源码文件位于 `D:\steam\steamapps\common\dota 2 beta\content\dota_addons\survival\panorama\scripts\custom_game\combat_stats.js`。
- 两项数值共用 `positionRelativeToOfficialPanel()`；垂直偏移由相对原生行的 `+3px` 改为 `-3px`，净效果为向上 6px。
- 攻击力使用另一套 `positionRelativeToStatsContainer()`，本次没有修改；属性三围和图标也没有修改。
- 已使用 `resourcecompiler.exe -f` 强制生成 `game\dota_addons\survival\panorama\scripts\custom_game\combat_stats.vjs_c`。
- 编译结果为 `OK: 1 compiled, 0 failed, 0 skipped`。
- Node 当前不在 PATH，未使用 `node --check`；Dota 资源编译器成功完成 Panorama JS 编译校验。

## 上一任务：建筑数量配置

1. `building_definitions.csv` 中的建筑最大数量必须被实际建造逻辑采用。
2. 箭塔 `max_count=7` 表示整个友军队伍最多同时拥有 7 个箭塔。
3. 其他建筑的 `max_count`、`requires_city_level`、`population_cost` 也应统一从生成配置读取，避免重复手写。

## 上一任务根因

1. `building_definitions.csv` 和生成的 `building_definitions.lua` 中箭塔均已是 `max_count=7`。
2. `building_system.lua` 实际读取的是手写适配层 `config/buildings_config.lua`。
3. 该适配层把箭塔 `max_count` 固定为 `0`；在服务端语义中 `0` 表示无限制，所以第 8 个箭塔不会被拒绝。

## 上一任务实施结果

- `buildings_config.lua` 的统一组装阶段现在从生成配置读取 `max_count`、`requires_city_level` 和 `population_cost`。
- 原有手写值只作为生成字段缺失时的兼容回退。
- `building_system.lua` 使用数值安全的统一上限判断；`max_count=0` 继续表示无限制。
- 建筑数量继续按 `counts[team][building_id]` 统计，箭塔 7 个上限为全队共享。
- 建筑开始施工、成功创建单位后立即占用数量名额；建筑死亡或施工实体失效后释放名额。
- 新增 `test_building_max_count_config.lua`，覆盖生成字段映射、箭塔第 8 个请求拒绝、队伍隔离、死亡释放名额和零值无限制。
- `test_building_max_count_config.lua`、`test_building_population_config.lua`、`test_arrow_tower_completion.lua` 均通过。
- 全量 26 个 Lua 测试全部通过，`luac -p` 与 `git diff --check` 通过。

## 上一任务：战斗属性投影

1. 战斗属性面板的护甲沿用 War3 数值语义；底层 Dota 护甲只负责实际结算。
2. 齐天大圣等英雄的面板基础攻击显示 CSV 原值，不显示 `damage_multiplier` 放大后的引擎值。
3. 英雄原生普通攻击仍保留既有 `damage_multiplier` 实战效果，不能扩大到技能或装备光环。
4. 英雄攻速必须直接由 CSV `attack_speed`、固定攻击间隔变化和装备攻速百分比计算，不读取引擎当前帧反推。
5. 选中单位事件、实时属性变化、建筑推送和英雄 NetTable 必须使用同一属性单位投影。

## 上一任务根因

1. 服务端曾把 `GetPhysicalArmorValue(false)` 的 Dota 底层护甲直接发送给 UI，导致配置 `10` 显示为约 `3.33`。
2. 装备 `armor_flat=10` 又被 Modifier 直接作为 Dota `+10`，显示语义和实际结算单位混在一起。
3. 英雄 `damage_multiplier` 在生成战斗快照前已乘到基础攻击，齐天大圣 CSV `1000` 因而显示为 `1150`。
4. 英雄攻速曾读取 `GetSecondsPerAttack()`，使 UI 依赖引擎当前帧状态而非配置权威值。
5. 建筑即时/延迟推送、英雄 NetTable 和实时减甲推送各自组装数据，缺少统一 UI 单位边界。

## 上一任务实施结果

- `config/armor_balance.lua` 增加 Dota 护甲到 War3 显示护甲的反向转换。
- 新增 `ui/combat_stat_projection.lua`，统一生成 `armor`、`runtime_armor`、`armor_unit` 和 `stat_units_version`。
- 选中单位请求、实时属性变化、建筑即时/延迟推送以及英雄 NetTable 全部通过统一投影。
- 英雄快照的基础攻击保持 CSV 逻辑值；齐天大圣面板为 `1000`，剑圣面板为 `1000`。
- 原生普通攻击仍把英雄倍率投影到引擎基础攻击：齐天大圣 `1150`，剑圣 `1100`；倍率不进入全局 DamageFilter，因此不会额外放大技能和装备光环。
- 新增 `systems/hero_combat_stat_math.lua`，由配置 BAT 和装备攻速百分比直接计算每秒攻击次数。
- 装备护甲在 `modifier_equipment_effects.lua` 写入引擎时执行 `War3 / 3`，UI 再统一投影回 War3 显示值。
- 建筑首次创建和升级推送显式发布 `runtime_armor`，不再复用含义不明确的 `armor` 字段。
- 新增 `test_combat_stat_projection.lua`、`test_hero_combat_stat_projection.lua`，并扩展 `test_arrow_tower_completion.lua`。
- 相关文件通过 `luac -p`；相关测试、全量 Lua 测试和 `git diff --check` 均返回成功。

## 上一任务记录

1. 防御塔升级资源不足时应明确显示费用和不足状态，但按钮保持可点击；服务端使用最新资源进行最终判断。
2. 第一次和第二次从 Workshop Tools Run 地图时行为必须一致。
3. 重复 Run 后 Q/W/E/R/T/Y/U 快捷键仍须可施放当前选中单位的可见技能。
4. 增加足够日志，便于区分服务端资源状态、NetTable 发布、客户端按钮映射和快捷键绑定问题。
5. 资源不足时按钮保持可点击；点击仍到达服务端，由最新权威资源账户决定成功或失败。

## 上一任务根因

1. 防御塔运行时曾将 `can_afford` 固定为 `1`，状态与真实资源不一致。
2. `population_delta` 是升级后的最大人口奖励，却被 UI 当成升级消耗参与可负担判断。
3. 客户端收到运行时 NetTable 更新后，用实体能力槽位查找 Valve 的 `AbilityN` 可见槽位；隐藏或被动能力会令二者错位，导致旧 `DOTADisabled` 未被清除。
4. `GameUI.CustomUIConfig()` 会跨 Workshop Tools Run 保留，但其中旧 Panorama 上下文的按键回调已失效；第二次 Run 跳过重绑后快捷键不可用。
5. 原生技能按钮鼠标点击依赖 Dota 的 `OnSpellStart`，但建筑上的动态 Lua 技能并不稳定；Q/W/E 则直接发送自定义施放请求，因此会出现快捷键有效而鼠标无效果。
6. Tooltip 悬停层会参与原生技能按钮命中；若没有明确点击转发，内部面板可能吃掉鼠标事件。

## 上一任务实施结果

- 修复箭塔完工回调直接索引不存在的 `definition.levels`；完工等级数据现在兼容箭塔的 `pre_class_levels`。
- 完工技能激活已前移到可选模型数据读取之前，避免视觉配置异常令升级技能永久保留施工期 `SetActivated(false)`。
- 新增 `test_arrow_tower_completion.lua`，覆盖箭塔完工等级解析和技能激活顺序。
- 防御塔升级恢复真实的木材/金币判断，并明确不把 `population_delta` 当作成本。
- `RESOURCE_CHANGED` 会重新发布所有同队单位的能力运行时状态和新 `resource_version`。
- 客户端按当前选中单位的可见能力顺序定位 Valve `AbilityN` 面板，正确更新或清除 `DOTADisabled`。
- 每次 HUD 加载生成独立输入代号、独立控制台命令，并无条件替换当前按键分发器。
- `can_afford` 保留为显示和诊断数据，但不再写入 `DOTADisabled`，也不再作为客户端发送请求前的硬门禁。
- Tooltip 在受管理建筑技能的原生 `AbilityN` 槽位上创建透明点击代理，动态解析当前可见能力，并转发到与快捷键相同的 `SurvivalAbilityInput.ExecuteAbility()`。
- 普通英雄技能、建造点目标技能和其他非托管技能继续走 Valve 原生输入，不被点击代理接管。
- 城墙、主城、农场升级也在服务端路由中采用与防御塔相同的直接权威分发，规避动态 Lua `OnSpellStart` 不稳定。
- 新增 `test_resource_authoritative_spend.lua`，覆盖资源不足不扣费，以及服务端资源后来足够时可接受请求。
- `combat_stats.js` 与 `ability_tooltip.js` 已通过 Dota `resourcecompiler.exe` 编译为游戏目录中的 `.vjs_c`。
- 新增 `test_tower_upgrade_runtime_refresh.lua`，覆盖满人口、资源不足到刚好足够的状态翻转。

## 定位日志

- 服务端能力状态：`[TOWER_UPGRADE_RUNTIME]`
- 服务端资源触发刷新：`[ABILITY_RUNTIME_RESOURCE_REFRESH]`
- 客户端按钮映射：`[TOWER_UPGRADE_RUNTIME][CLIENT]`
- 每次 Run 的输入绑定：`[SURVIVAL_INPUT] BOUND`
- 按键到达当前上下文：`[SURVIVAL_INPUT] KEY`
- 施放请求及结果：`[SURVIVAL_CAST][CLIENT]`、`[SURVIVAL_CAST][SERVER]`
- 原生按钮代理入口：`[SURVIVAL_CAST][CLIENT] OFFICIAL_BUTTON`
- 客户端快照提示资源不足但仍发送：`LOCAL_RESOURCE_LOW request_sent=1`

正常情况下，资源达到成本后，同一 `ability_entindex` 的服务端和客户端日志应显示更大的 `resource_version`，且 `can_afford` 从 `0` 变为 `1`；每次 Run 都应出现不同 `generation` 的 `[SURVIVAL_INPUT] BOUND`。