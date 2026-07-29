# Project Context

## 项目与环境

- 项目：Dota 2 自定义地图 `survival`。
- 工作目录：`d:\steam\steamapps\common\dota 2 beta\game\dota_addons\survival`。
- 服务端主要使用 Lua，配置权威来源位于 `data/csv`，生成配置位于 `scripts/vscripts/config/generated`。
- 配置修改规范：优先修改 CSV，再运行 `build_configs.bat`；运行时服务通过 `core/event_bus.lua` 解耦。
- 内容库存以 `content_id` 为权威身份，Dota 物品实体只是可见背包壳。
- Panorama 源码不在当前 `game` 插件目录中，而在对应的内容目录：`D:\steam\steamapps\common\dota 2 beta\content\dota_addons\survival\panorama`。
- 游戏实际加载的 Panorama 编译产物位于：`D:\steam\steamapps\common\dota 2 beta\game\dota_addons\survival\panorama`。

## AI 会话恢复协议

- 所有新会话必须首先读取 `docs/ai/START_HERE.md`，再按其中顺序恢复上下文。
- `docs/ai/CURRENT_TASK.md` 只描述一个活跃任务；完成或被替换后整体迁入 `docs/ai/archive/`。
- 深度研究不能只存在于聊天中；关键证据、排除项、未决问题和下一步必须持续追加到 `docs/ai/SESSION_LOG.md`。
- 用户需求发生变化、完成关键调查、作出重要决策、准备大范围修改/验证或会话可能中断时，必须先写检查点。
- 如果持久化文档与模糊会话记忆冲突，以文档中的用户原始需求和最新检查点为准，并向用户明确冲突，不得猜测。

## 常用命令与配置链

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

## 当前熔火装备升级链

- `狱火熔铠Lv1 + 熔火核心Lv1 → 狱火熔铠Lv2`
- `狱火熔铠Lv2 + 熔火核心Lv2 → 狱火熔铠Lv3`
- `狱火熔铠Lv3 + 熔火核心Lv3 → 狱火熔铠Lv4`
- `狱火熔铠Lv4 + 熔火核心Lv4 → 狱火熔铠Lvmax`

四段升级配方及挑战 07/08 的材料来源均已闭环，并通过地面掉落、自动合成与错误恢复回归测试。