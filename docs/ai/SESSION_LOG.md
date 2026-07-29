# Session Checkpoint Log

> 仅追加关键检查点。记录研究过程，而不只是任务完成后的总结。

## 2026-07-28 — 检查点 001：确认上下文丢失风险

- 用户最新要求：多次断开和界面关闭导致深度计划讨论丢失；希望解决即使重读四份上下文文档仍无法恢复断点的问题。
- 已读取：`PROJECT_CONTEXT.md`、原 `CURRENT_TASK.md`、`DECISIONS.md`、`KNOWN_ISSUES.md`。
- 新确认事实：四份文档保存了此前已完成的工程结论，但没有“最后一条用户要求、断开前正在研究什么、尚未定案证据、下一步唯一动作”。
- 已确认历史工程状态：Tooltip 事件驱动重构已完成；29 个 Lua 测试通过；相关 Panorama 资源已强制编译；仍有 Workshop Tools 实机确认项。
- 已排除：不能恢复已关闭界面的聊天原文；不能声称记得未落盘内容；不能从历史 Tooltip 总结推断断开前的新任务。
- 用户决策：批准先建立抗断连文档系统，再重建丢失任务。
- 下一步：迁移旧任务历史，创建唯一恢复入口和追加式检查点日志。

## 2026-07-28 — 检查点 002：开始实施恢复系统

- 工作区事实：`docs/ai` 当前整体为 Git 未跟踪目录；没有可依赖的上下文文档版本历史。
- 修改边界：只修改 `docs/ai`，不修改游戏代码、配置或 Panorama 源码。
- 迁移策略：原 `CURRENT_TASK.md` 移至 `docs/ai/archive/2026-07-28-tooltip-and-prior-tasks.md`，仅改归档标题并添加说明，保留其余历史内容。
- 新结构：`START_HERE.md` 为唯一入口；`CURRENT_TASK.md` 只包含当前恢复任务；`SESSION_LOG.md` 追加研究检查点。
- 尚未确认：断开前具体任务内容。
- 下一步：更新长期协议文档，复读文件并执行限定路径验证。

## 2026-07-28 — 检查点 003：恢复系统验证完成

- 已建立：`START_HERE.md` 唯一恢复入口、单一活跃任务格式的 `CURRENT_TASK.md`、追加式 `SESSION_LOG.md` 和 `archive/` 历史归档。
- 长期协议：`PROJECT_CONTEXT.md`、`DECISIONS.md` 和 `KNOWN_ISSUES.md` 已登记恢复顺序、强制检查点和禁止猜测原则。
- 归档验证：原任务记录的开头与末尾均已复读，历史 Tooltip、属性、建筑和输入链内容仍保留。
- 格式验证：7 个 Markdown 文件存在；限定路径 `git diff --check` 无报错；独立尾随空白检查无结果。
- 代码影响：没有修改游戏代码、配置、CSV 或 Panorama 源码，因此无需运行游戏代码测试或资源编译。
- 剩余风险：`docs/ai` 整体仍未被 Git 跟踪；界面关闭不会删除文件，但清理未跟踪文件仍可能删除这些文档。
- 尚未确认：断开前具体任务内容。
- 下一步唯一动作：请用户提供最小线索；收到后先追加检查点，再开始代码调查。
## 2026-07-28 — 检查点 004：恢复 Tooltip 完全自主控制需求

- 用户要求：Tooltip 完全由项目自主控制；方向是替换原生底部角色 UI，因为原生技能悬停会自动显示 Valve Tooltip。
- 上一轮用户约提供 10 张 Panorama 节点截图后会话断开。原图当前不可见，项目目录也未找到图片文件。
- 已发现替代证据：.cline_tmp 节点 ID、Tooltip 备份与 diff，以及历史自定义底栏。
- 本轮只分析与更新 docs/ai，不修改游戏 UI。

## 2026-07-28 — 检查点 005：Tooltip 全接管分析完成

- 当前根因：自定义 SurvivalHeroBottomHUD 被折叠；官方 abilities 可见且可命中；物品栏完全由官方 HUD 拥有。
- 当前普通技能调用 Valve Ability Tooltip；托管建筑技能用 0.08 秒循环压制原生 Tooltip；人物属性使用 Valve TitleText Tooltip。
- 可复用基础：历史技能槽采用 Button 加 DOTAAbilityImage 且图像 hittest=false；现有服务端输入链支持无目标与点目标。
- 结构风险：折叠 AbilitiesAndStatBranch 会破坏 flow 布局并导致物品栏滑位。
- 技能风险：单位目标、toggle、autocast 等行为未在自定义链中实现，必须先枚举验证。
- 物品风险：没有自定义主动使用、拖放、丢弃、出售或拆分链，不可直接隐藏官方物品栏。
- 推荐：先接管技能区与人物属性，再单独完成物品全交互接管，最后清理官方节点扫描与 Tooltip 压制。
- 下一步：等待用户确认首轮范围；推荐阶段 A 到 C。

## 2026-07-28 — 检查点 006：明确四类 Tooltip 接管目标与最小运行时证据

- 人物属性：保留官方攻击力等图标与当前权威数字显示，关闭官方悬停气泡，改由项目悬停代理显示自定义 Tooltip。
- 技能：关闭 Valve 技能 Tooltip 触发源，项目悬停显示自定义 Tooltip，同时保留点击、快捷键、冷却与等级等功能。
- 物品栏：使用项目 Tooltip，但必须保留物品主动使用、拖放、换位与其他原生交互。
- 地面掉落物：先调查世界物品官方 Tooltip 能否被替换；若不能，研究光标下世界实体检测与自定义屏幕 Tooltip 等替代方案。
- 当前源码候选：Damage；AbilityN 下的 AbilityButton、ButtonWell、AbilityImage；inventory_slot_N 及其 DOTAItemImage 后代。
- 地面物品事实：挑战奖励通过 CreateItemOnPositionSync 创建，并以物品实体 entindex 发布 survival_inventory_item_identity。
- 工具限制：助手不能直接连接用户当前运行中的 Panorama Debugger；需要最小定向截图与一次地面物品控制台诊断。
- 下一步：用户提供 Damage、Ability0、inventory_slot_0 三组展开树截图，以及地面掉落物悬停诊断。

## 2026-07-28 — 检查点 007：用户批准人物属性与技能接管试点

- 用户已把 `图片1.png` 至 `图片7.png` 放在桌面并按顺序提供；当前节点证据足够启动人物属性与技能试点，不再把额外 Debugger 截图作为开工前置条件。
- 用户批准推荐范围：阶段 0～3，即建立可回滚接管基线、人物属性 Tooltip 完全自定义、技能显示/悬停/鼠标输入完全接管，并在验证后清理对应旧兼容路径。
- 本轮明确不做：隐藏官方背包、重写物品主动使用/拖放/换位/丢弃，以及地面掉落物悬停；这些保留为后续独立阶段。
- `DOTAAbilityTooltip` 展开截图可在自定义骨架完成后用于视觉校准（标题、描述、费用、冷却、属性区及尺寸），但不能恢复 Valve 内部代码或替代项目 ViewModel。
- 安全边界：保留官方底栏几何与背包交互；技能项目代理必须位于原生 `AbilityN` 祖先树之外；未知 AbilityBehavior 不得误按无目标技能发送。
- 下一步：核对加载顺序与现有定位工具，实施 Panorama 试点，强制定向编译并输出实机验收矩阵。

## 2026-07-28 — 检查点 008：接口中断后的精确恢复状态

- 用户报告接口请求错误并要求继续执行；该错误发生在编辑工具请求期间，不是 Dota、资源编译器或项目代码的运行错误。
- 中断前已成功修改：`ui_bootstrap.js` 增加阶段开关（abilities/stats=true、inventory=false）；`ability_tooltip.js` 在技能接管模式下停止绑定 Valve AbilityN；`survival_hud.xml` 增加独立技能/属性代理层并加载 `hud_takeover.js`；`ability_tooltip.css` 增加接管层样式。
- 中断前未成功修改：`hero_stat_tooltip.js`。原因是补丁工具拒绝同一补丁中对同一路径先 Delete 再 Add；原文件应仍保持 Valve TitleText Tooltip 实现。
- 尚未创建/修改：`hud_takeover.js`、`combat_stats.js` 的普通技能订单分流；尚未执行任何 Panorama 编译。
- 恢复动作：先复读实际文件确认磁盘状态，再用普通 Update 修改属性 Tooltip，随后完成技能接管控制器、施法安全分流和强制编译。

## 2026-07-28 — 检查点 009：人物属性 Tooltip 源码接管已写入

- `hero_stat_tooltip.js` 已从 Valve `DOTAShowTitleTextTooltip` 事件改为项目 `CustomHeroStatTooltip` 面板。
- 属性输入代理位于独立 `SurvivalStatTakeoverLayer`，以官方 Damage/Armor/AttackSpeed 和项目三围覆盖行为几何锚点；锚点本身关闭命中，避免进入 Valve Tooltip 触发树。
- 属性内容仍只消费 `SurvivalCombatStatsStore` 的服务端投影；未新增客户端护甲单位换算。
- 已保留 `SetTakeoverEnabled()` 回滚入口；关闭后隐藏代理并恢复官方目标命中。
- 尚未编译或实机验证；下一步唯一动作是创建独立技能接管控制器。

## 2026-07-28 — 检查点 010：独立技能接管控制器已创建

- 新增 `hud_takeover.js`：自定义技能按钮位于 `SurvivalAbilityTakeoverLayer`，官方 AbilityN 仅作为几何锚点并保持 flow 占位；官方槽位使用 opacity=0 且关闭命中，不执行 collapse。
- 首版已实现可见能力枚举、图标、Q/W/E/R/T/Y/U 或 F2、等级、魔法费用、冷却数字/遮罩、被动/不可用/资源不足状态，以及 `SetEnabled(false)` 回滚入口。
- 控制器只调用统一 `SurvivalAbilityInput.ExecuteAbility`，本步骤未擅自改变服务端施法路由。
- 复核发现：旧 `ability_tooltip.js` 在接管模式下提前退出，其私有 render 不可复用；新控制器当前必须补上独立 Tooltip 渲染函数后才能认为悬停闭环完成。
- 尚未编译；下一步唯一动作：迁移必要的 Tooltip ViewModel 渲染到 `hud_takeover.js`，然后处理普通/托管技能安全施法分流。

## 2026-07-28 — 检查点 011：技能 Tooltip 渲染与安全施法分流已写入

- `hud_takeover.js` 已独立渲染 `CustomAbilityTooltip`，消费 `survival_ability_data`、`survival_tooltips` 和 `survival_ability_runtime`，显示名称、等级、描述、金币/木材费用、施法类型、魔法、冷却、运行时字段和状态。
- `combat_stats.js` 已增加托管身份/建筑白名单判定：托管无目标和建造点目标继续走服务端权威事件；普通无目标/点目标技能改走 Panorama 原生单位订单。
- 被动技能和未支持的单位目标/切换等 behavior 会安全拒绝并记录诊断，不再误按无目标技能发送。
- 点目标状态已增加 `managed` 标记；`ability_survival_return_home` 点击转到现有回城请求，并向新控制器公开 `SurvivalReturnHomeInput.Request`。
- 尚未编译；下一步唯一动作：完整复核职责链，修复任何物品 Tooltip 回归或 XML/API 对应问题后强制编译。

## 2026-07-28 — 检查点 012：编译前职责链复核完成

- 直接读取正式 `ability_tooltip.js` 后确认：正式文件当前只有技能绑定，没有背包物品绑定；物品代码只存在于 `.cline_tmp` 候选残留。因而接管模式下提前退出不会关闭正式物品绑定，官方背包仍完整由 Valve 负责。
- XML 中技能/属性代理层与两个项目 Tooltip 均位于项目 HUD 根层，且 `hud_takeover.js` 在 `combat_stats.js` 后加载，统一输入 API 在控制器启动前已建立。
- 修正被动/不可用技能悬停：自定义 Button 始终保持 enabled，点击回调内部拒绝施法，避免禁用 Button 导致 Tooltip 悬停丢失。
- 回滚边界仍为 `SurvivalHudTakeover.abilities/stats`；inventory 保持 false。
- 下一步唯一动作：强制编译所有改动 Panorama 资源并进行限定静态验证；失败时按单文件错误修复，不重跑未知状态写命令。

## 2026-07-28 — 检查点 013：终端类型差异导致编译命令未可靠执行

- 编译请求使用了 PowerShell `$rc = ...; & $rc` 语法，但终端桥接实际显示为 Git Bash；已捕获的明确结果是 `bash: syntax error near unexpected token '&'`，不能认定任何资源已重新编译。
- 同批后续命令出现输出捕获超时；按环境规则，必须先检查产物时间戳和残留 `resourcecompiler` 进程，禁止直接重复写命令。
- 静态复核进一步确认：正式 `ability_tooltip.js` 当前只有技能绑定，物品绑定只在 `.cline_tmp` 候选文件中；本轮官方背包职责没有被正式脚本接管或移除。
- 施法分流将收紧：普通非托管技能交还 `Abilities.ExecuteAbility`，由引擎继续处理普通点目标/单位目标/切换行为；只有托管建造和建筑操作使用项目自定义服务端事件。
- 下一步唯一动作：检查编译产物/进程状态，修正普通技能执行路径，再以 Git Bash 兼容命令逐个强制编译。

## 2026-07-28 — 检查点 014：技能与人物属性接管试点完成静态验收

- `ui_bootstrap.js` 的阶段开关最终为 abilities=true、stats=true、inventory=false；背包与地面物品不在本轮接管范围。
- 新增 `hud_takeover.js`，独立技能层覆盖官方 AbilityN 的实际几何；官方槽位保留 flow 占位但 opacity=0 且关闭命中。自定义槽负责图标、快捷键、等级、魔法、冷却、被动/不可用/资源不足状态、项目 Tooltip 和点击。
- `hero_stat_tooltip.js` 使用独立属性代理和 `CustomHeroStatTooltip`，消费服务端 `stat_tooltips` 投影，不触发 Valve TitleText Tooltip，也不改变结算单位边界。
- 最终施法分流：普通非托管技能使用 `Abilities.ExecuteAbility`；托管建筑无目标技能走 `ui_ability_cast_request`；托管建造点目标走 `ui_ability_cast_position_request`；回城走既有 `ui_return_home_request`。
- 强制编译结果：`ui_bootstrap.js`、`ability_tooltip.js`、`hero_stat_tooltip.js`、`combat_stats.js`、`hud_takeover.js`、`ability_tooltip.css` 均为 `OK: 1 compiled, 0 failed, 0 skipped`；`survival_hud.xml` 为 `OK: 7 compiled, 0 failed, 0 skipped`。
- 完整 7 个目标资源于 2026-07-28 16:02:47 编译；随后修复 Valve 重建 AbilityN 时的回滚状态缓存，并再次编译 `hud_takeover.vjs_c` 与 XML，最终时间戳为 16:06:08。XML 中 `CustomAbilityTooltip`、`SurvivalAbilityTakeoverLayer`、`SurvivalStatTakeoverLayer`、`CustomHeroStatTooltip` 均且仅出现一次；源码中无 `PrepareUnitOrders`/`dotaunitorder_t` 残留。
- 限制：当前 PATH 没有 node，未执行 `node --check`；Dota `resourcecompiler.exe` 已实际编译全部 Panorama JS。尚未进行游戏内视觉与输入验收。
- 下一步唯一动作：重新 Run 地图，依次验证英雄/建筑/农民、普通与托管技能、人物属性、官方背包、选择切换、分辨率/HUD 比例和第二次 Run；若失败，提供代理层/官方锚点 Debugger 截图与相关控制台日志。

## 2026-07-28 — 检查点 015：再次断开后的恢复确认

- 用户最新要求：界面再次断开，要求继续尝试恢复，不希望重新复述此前的深度讨论。
- 恢复依据：重新读取 `START_HERE.md`、`CURRENT_TASK.md`、`SESSION_LOG.md` 最近检查点和相关 `KNOWN_ISSUES.md`；没有使用跨会话记忆填补缺口。
- 新确认事实：上一轮聊天曾表示准备新增检查点并继续自动复核，但磁盘日志仍停在检查点 014，因此这些后续动作不能视为已经执行。
- 产物证据：`content/.../hud_takeover.js` 时间为 16:05:32；游戏目录 `hud_takeover.vjs_c` 与 `survival_hud.vxml_c` 时间均为 16:06:08，与检查点 014 一致。没有发现断开后新增的本轮源码或编译结果。
- 当前可靠状态：阶段 0～3 的源码实施与强制编译已经完成；技能和人物属性由项目代理层接管，官方背包仍由 Valve 负责。
- 尚未验证：Workshop Tools 中的视觉对齐、项目 Tooltip、鼠标与快捷键施法、英雄/建筑/农民选择切换、HUD 比例/分辨率变化、官方背包交互和第二次 Run。
- 已排除：不把编译成功冒充实机通过；不在没有实机异常证据时继续猜测性修改布局；不接管本轮范围外的物品栏与地面物品。
- 下一步唯一动作：在 Workshop Tools 重新 Run 地图，按 `CURRENT_TASK.md` 验收标准 1～8 实机验证；若失败，记录对应代理层/官方锚点截图与 `[SURVIVAL_TAKEOVER]`、`[SURVIVAL_CAST]` 日志后再进行定向修复。

## 2026-07-28 — 检查点 016：用户批准按恢复计划执行

- 用户最新要求：在重新读取持久化上下文并复述恢复计划后，明确选择“按上述恢复计划开始执行”。
- 当前可靠起点：阶段 0～3 源码实施与强制编译已完成；技能和人物属性由项目代理层接管，官方背包仍由 Valve 负责。
- 本轮执行边界：先做非破坏性静态复核和 Workshop Tools 实机验收；只有获得明确的游戏内异常、节点坐标或 `[SURVIVAL_TAKEOVER]`/`[SURVIVAL_CAST]` 日志证据后才定向修改。
- 禁止事项：不执行全局 reset/checkout/clean；不覆盖工作区其他任务修改；不把物品栏或地面物品接管混入本轮。
- 尚未验证：英雄、建筑、农民的代理层几何和 Tooltip，全部技能输入类型，人物属性 Tooltip，官方背包交互，选择切换、HUD 比例/分辨率变化及第二次 Run。
- 下一步唯一动作：复核 7 个接管相关 Panorama 源资源、加载顺序和编译产物，然后进入 Workshop Tools 验收矩阵。

## 2026-07-28 — 检查点 017：接管静态复核完成，进入实机验收

- 已复核接管开关：`SurvivalHudTakeover` 为 `abilities=true`、`stats=true`、`inventory=false`。
- 已复核加载顺序：`ui_bootstrap.js` 先建立开关，旧 `ability_tooltip.js` 在技能接管模式下停止绑定 Valve `AbilityN`，随后加载属性代理、统一输入控制器和 `hud_takeover.js`。
- 已复核职责边界：技能和人物属性由独立代理层负责；官方背包没有启用项目接管，仍保留 Valve 输入与物品 Tooltip。
- 编译产物证据：7 个目标产物均存在且大小非零；时间戳统一为 `2026-07-28 16:06:08`，与检查点 014/015 一致。
- XML 唯一性证据：`CustomAbilityTooltip`、`SurvivalAbilityTakeoverLayer`、`SurvivalStatTakeoverLayer`、`CustomHeroStatTooltip` 均且仅出现一次。
- 本轮没有修改 Panorama 源码、CSS 或 XML，只追加恢复日志，因此无需因本轮记录变更重新编译资源。
- 工具限制：终端桥接再次对部分只读命令出现 30 秒无输出超时，无法据此判断 Dota 进程状态；助手也无法直接观察 Workshop Tools 可视界面。不能把静态复核冒充实机通过。
- 下一步唯一动作：用户在 Workshop Tools 重新 Run 地图并执行 `CURRENT_TASK.md` 验收标准 1～8；按首个失败类别返回画面/日志后再定向修复，若全部通过则记录最终验收并归档任务。

## 2026-07-28 — 检查点 018：实机发现技能槽几何与箭塔转职失败

- 用户实机结果：英雄、建筑、农民的全部技能槽位置异常；箭塔 5 级无法完成转职升级。
- 事实与推断边界：全单位共同偏移表明共享坐标系、UI scale 或接管层根节点几何是首要调查方向，但尚未获得节点坐标截图，不能直接断言具体偏移量。箭塔转职失败可能发生在客户端能力映射、托管请求、服务端路由、资源扣费或升级任务中的任一环节，尚未定位。
- 本轮调查边界：分别追踪 Panorama 技能代理定位链和箭塔 5 级转职完整调用链；不修改官方背包或地面物品。
- 下一步唯一动作：读取技能代理坐标实现、XML/CSS 根层结构、箭塔转职技能配置与服务端路由，结合相关 diff 找到可验证的根因；若代码不足以确定几何根因，再索取最小 Panorama Debugger 坐标证据。

## 2026-07-28 — 检查点 019：确认技能锚点查找回归，准备定向修复

- 已确认技能几何共同根因候选：正式 `hud_takeover.js` 使用 HUD 根节点直接 `FindChildTraverse("AbilityN")`；旧节点调查实现则先限定到官方 `abilities` / `AbilitiesAndStatBranch` 容器。HUD 中同名节点可能来自隐藏模板或其他分支，全树首个匹配不能作为可见技能槽锚点。
- 修复策略：新增官方技能容器解析函数，只在该容器内查找 `AbilityN`；每次刷新重新解析以兼容 Valve HUD 重建，不缓存跨 Run 节点。
- 箭塔链已确认：5 级会添加并激活 `ability_tower_class_1..7`；客户端将其识别为托管无目标技能；服务端校验后发送 `TOWER_CLASS_REQUEST`；`building_upgrade_system` 消费事件并执行权威扣费与路线切换。
- 当前未确认：箭塔失败是否只是错误代理位置导致点击错位，或服务端仍有独立失败。没有 `[SURVIVAL_CAST]` 日志前不改权威转职逻辑。
- 下一步唯一动作：确认 5 级箭塔可见技能数量后修改技能锚点解析，强制编译 `hud_takeover.js` 与 HUD XML，并复测全单位位置和箭塔转职。

## 2026-07-28 — 检查点 020：官方技能容器锚点修复已编译

- 已修改 `content/.../hud_takeover.js`：新增 `officialAbilitiesContainer()`，优先从 `AbilitiesAndStatBranch` 内解析官方 `abilities` 容器；`AbilityN` 只在该容器内查找，不再使用整个 HUD 树的首个同名节点。
- HUD 重建兼容：容器与槽位每次刷新重新解析，不缓存跨 Run 的 Valve 节点；新增 `[SURVIVAL_TAKEOVER] anchor_state=` 状态变化诊断，可区分容器缺失、特定槽缺失和可用槽数量。
- 已确认 5 级基础箭塔会移除两个普通升级能力并显示 7 个转职能力，正好对应 Q/W/E/R/T/Y/U；配置没有第 8 个无锚点能力。
- 编译证据：定向 `hud_takeover.js` 为 `OK: 1 compiled, 0 failed, 0 skipped`；HUD XML 加载链为 `OK: 7 compiled, 0 failed, 0 skipped`。
- 最终产物：`hud_takeover.vjs_c` 与 `survival_hud.vxml_c` 时间戳均更新为 2026-07-28 17:52:14，大小分别为 20357 和 8028 字节。
- 尚未修改箭塔权威转职逻辑：现有代码已具备 5 级按钮添加、客户端托管分流、服务端 `TOWER_CLASS_REQUEST` 路由与消费者；需先排除技能代理错位导致的点击错误。
- 下一步唯一动作：停止当前 Run 后重新 Run，复测英雄/建筑/农民技能槽位置和 5 级箭塔转职；若位置恢复但转职仍失败，收集 `[SURVIVAL_CAST]` 与 UI 通知后定向修复服务端链。

## 2026-07-28 — 检查点 021：箭塔转职恢复，技能几何仍异常

- 用户复测结果：技能槽位置仍异常，但箭塔 5 级转职已经恢复。
- 已确认：箭塔服务端权威转职链无需修改；先前失败由错误锚点/点击代理错位引起，官方技能容器限定修复已恢复实际点击目标。
- 剩余唯一故障：英雄、建筑、农民共用的技能代理几何仍不正确。
- 根因范围：`placeOverOfficial()` 的窗口坐标与 UI scale 换算、代理层局部坐标空间，或官方容器内最终锚点层级；没有偏移方向、尺寸和节点坐标证据前不能安全写固定补偿。
- 下一步唯一动作：复核完整几何算法并恢复桌面节点截图；若旧材料不足，采集一张当前 `SurvivalAbilityTakeoverLayer` 与对应 `AbilityN` 的 Panorama Debugger 几何截图或等价坐标日志。

## 2026-07-28 — 检查点 022：一次性技能几何诊断已编译

- 已核对用户提供的 7 张旧 Panorama Debugger 截图：确认官方 `Ability0`、`Damage`、`inventory_slot_0` 节点树，但截图没有运行时几何属性，无法计算当前偏移。
- 已确认 XML/CSS：`SurvivalAbilityTakeoverLayer` 是 `SurvivalHUDRoot` 的直接子节点，声明为全屏 `100% x 100%`、`position: 0 0`。
- 已在 `hud_takeover.js` 增加状态去重的 `[SURVIVAL_GEOMETRY]` 诊断，仅记录 `Ability0`：官方槽与父节点、窗口坐标、布局尺寸、UI scale；接管层与父节点；计算局部矩形；自定义槽应用后的实际窗口坐标与尺寸。
- 诊断不会改变现有几何公式，不会修改技能输入或箭塔逻辑；仅在几何签名变化时输出，避免 0.5 秒刷新刷屏。
- 写入期间终端曾返回瞬时 2635 字节状态；随后已确认源文件完整闭合，共 528 行 / 22635 字节，不存在截断。
- 编译证据：诊断版 `hud_takeover.js` 为 `OK: 1 compiled, 0 failed, 0 skipped`；HUD XML 加载链为 `OK: 7 compiled, 0 failed, 0 skipped`。
- 下一步唯一动作：停止当前 Run 后重新 Run，复制首条完整 `[SURVIVAL_GEOMETRY]` 日志；据此修正窗口坐标到代理层局部坐标的公式。

## 2026-07-28 — 检查点 023：确认锚点层级错误，用户批准原版 UI 调查模式

- 用户提供完整日志：官方 `Ability0` 与自定义槽窗口左上角均为 `723,1200`，证明 `GetPositionWithinWindow()`、代理层原点及当前位置换算能够对齐左上角；此前优先怀疑全屏坐标系的方向已被证据排除。
- 日志同时显示官方 `Ability0` 为 `72x200`、自定义实际为 `80x222`、双方 UI scale 为 `1.111111...`。事实：`Ability0` 是远高于技能图标的复合外壳；推断：其内包含图标、按钮、升级等多个组件，不能作为最终按钮矩形。另有重复尺寸缩放风险，需要子节点数据继续确认。
- 旧调查代码保留候选顺序 `AbilityButton -> ButtonWell -> AbilityImage -> AbilityN`，进一步支持应调查内部可见/可点击子节点，而非继续为 `AbilityN` 写固定补偿。
- 用户明确批准：先只实施“恢复原版技能 UI + 自动日志”的调查模式；在数据出来前不修改正式接管几何公式，不提前决定升级按钮的最终接管方式。
- 已开始实施临时 `abilitySurvey` 开关：调查模式恢复官方技能槽、隐藏自定义代理，并准备自动输出 `Ability0` 完整子树与所有槽位的 `AbilityButton`/`ButtonWell`/`AbilityImage` 候选摘要。
- 下一步唯一动作：完成源码复核与强制编译；用户重新 Run 后采集英雄有技能点、农民/普通建筑、5 级七技能箭塔三种原版 UI 状态的调查日志与截图。

## 2026-07-28 — 检查点 024：原版技能 UI 调查模式已完成并强制编译

- `ui_bootstrap.js` 的 `SurvivalHudTakeover` 新增临时 `abilitySurvey: true`。调查模式不进入正式 `ensureSlot/placeOverOfficial/suppressOfficial` 路径，恢复 Valve `AbilityN` 显示与命中并折叠现有自定义技能代理。
- `hud_takeover.js` 新增自动调查日志：`[SURVIVAL_ABILITY_SURVEY_BEGIN]`、`[SURVIVAL_ABILITY_SLOT]`、`[SURVIVAL_ABILITY_CANDIDATE]`、`[SURVIVAL_ABILITY_TREE]`、`[SURVIVAL_ABILITY_SURVEY_END]`。
- `Ability0` 递归子树逐节点输出路径、类型、classes、窗口坐标、布局尺寸、UI scale、offset、可见性、CSS opacity/visibility、命中状态、CSS position/size 和子节点数量；所有可见槽额外输出 `AbilityButton`、`ButtonWell`、`AbilityImage` 候选摘要。
- 日志按选中单位、技能列表、树结构和候选几何签名去重；缺失 `Ability0` 状态也去重。可调用 `GameUI.CustomUIConfig().SurvivalAbilityTakeover.DumpSurvey()` 强制重新导出。
- 可靠性处理：`GetClasses()` 同时兼容数组与字符串；调查模式不永久改写自定义槽命中属性；NetTable 监听在调查模式下不再更新旧代理槽。
- 编译证据：`ui_bootstrap.js` 为 `OK: 1 compiled, 0 failed, 0 skipped`；`hud_takeover.js` 为同样结果；HUD XML 加载链为 `OK: 7 compiled, 0 failed, 0 skipped`。
- 调查边界：没有修改正式技能定位公式、技能输入路由、人物属性接管、箭塔权威逻辑或 Valve 原生物品栏。
- 下一步唯一动作：用户停止并重新 Run，依次采集有未分配技能点的英雄、农民/普通建筑、5 级七技能箭塔的原版底栏截图及对应完整同编号调查日志。

## 2026-07-28 — 检查点 025：首份原版 Ability0 子树样本已取得

- 用户提供了单位 `489`、唯一可见技能 `ability_build_wall` 的完整调查日志，包含 `dump=1` 与 `dump=2`，每份均有 87 个 `Ability0` 子树节点和完整 BEGIN/END。
- `dump=1` 发生于 `initial_0.35`，`Ability0` 窗口 Y 为 `1200`；随后 `dump=2` 在 `geometry_tick` 稳定为 Y=`944`，其所有内部节点同步上移 256。结论：首个 dump 是 HUD 布局中的瞬时状态，后续应以稳定后的 `dump=2` 为几何依据。
- 稳定样本确认：`Ability0` 是 `72x200` 的复合容器，窗口位置 `723,944`；真正按钮热区 `AbilityButton` 为 `70x71`，窗口位置 `725,1045`，`hittest=true`；`ButtonWell` 与它矩形完全相同但 `hittest=false`；`AbilityImage` 是内部留边后的 `54x55`，窗口位置 `733,1053`。
- 节点职责已确认：`LevelUpTab` 是按钮区域上方的独立兄弟组件，稳定矩形 `70x40 @ 725,1000`；`AbilityLevelContainer` 是独立等级点区域 `13x10 @ 753,1116`；`HotkeyContainer`、`AbilityCharges` 与 `ButtonWell` 同属 `ButtonWithLevelUpTab` 下的兄弟节点。
- 因此正式代理的首选几何锚点应为 `AbilityButton`（回退 `ButtonWell`），不是 `AbilityImage`，更不是 `Ability0`。`AbilityImage` 仅代表图像内芯，若以它为按钮会丢失边框与完整点击热区。
- 尺寸证据继续支持重复缩放判断：锚点的 `actuallayoutwidth/height=70x71` 是窗口实际矩形；代理层本地 CSS 尺寸应除以代理层累计 UI scale，而不应再次乘源节点 scale。
- 正式隐藏边界不能继续把整个 `Ability0` 设为 opacity 0，否则会一并隐藏 `LevelUpTab` 和等级点。后续需按组件隐藏 `ButtonWell`/按钮视觉，并单独决定 Hotkey、Charges、LevelUpLight 等兄弟组件的保留或替换。
- 尚未验证：该样本对应用户所述三类状态中的哪一类；英雄多技能/未分配技能点、普通建筑和 5 级七技能箭塔是否维持相同 `AbilityButton` 结构与尺寸。
- 下一步唯一动作：确认本样本的单位类别并继续采集剩余两类状态；在至少取得七技能箭塔的所有候选槽摘要前，不提交正式锚点修复。

## 2026-07-28 — 检查点 026：首份样本确认为农民/建造单位

- 用户确认检查点 025 的 `ability_build_wall` 样本来自农民/建造单位。
- 农民单槽结构已验证：`AbilityButton` 是完整 `70x71` 按钮热区，`ButtonWell` 同矩形，`AbilityImage` 是内部 `54x55` 图像；`LevelUpTab` 与等级点属于 `Ability0` 内独立组件。
- 当前不需要再次采集农民完整 87 节点子树。后续状态若候选路径和尺寸相同，只需 BEGIN、SLOT、CANDIDATE、END 与底栏截图；仅在树结构或候选节点缺失时再导出完整 TREE。
- 下一优先样本为 5 级七技能箭塔，用于验证 `Ability0..Ability6` 的横向位置、尺寸、间距、候选节点存在性，以及七槽布局是否缩放或压缩。
- 在七技能箭塔样本取得前不修改正式接管；普通英雄样本用于随后确认原生升级组件和英雄多技能布局。
- 下一步唯一动作：选中 5 级七技能箭塔，强制或自动导出一次稳定调查日志，并提供 BEGIN、7 条 SLOT、21 条 CANDIDATE、END 和一张底栏截图。

## 2026-07-28 — 检查点 027：5 级七技能箭塔布局已确认

- 用户提供稳定 `dump=16`：单位 `226`，7 个可见转职技能，BEGIN/END 完整，包含 7 条 SLOT、21 条候选节点和 `Ability0` 完整 87 节点树。
- 七个外层槽 `Ability0..Ability6` 的窗口 X 依次为 `680,744,808,872,936,1000,1064`，固定步长 `64`；每个外层槽均为 `64x200`。这证明 Valve 在七技能布局中按技能数量压缩槽宽。
- 七个 `AbilityButton` 的窗口 X 依次为 `683,747,811,875,939,1003,1067`，固定步长 `64`；全部为 `60x60`、Y=`1048`、`hittest=true`。按钮之间实际窗口间隙为 `4`。
- 七个 `ButtonWell` 与对应 `AbilityButton` 矩形完全相同，均为 `60x60`，但 `hittest=false`；七个 `AbilityImage` 均为 `54x54`，相对按钮内缩 `3px`。
- 与农民单槽样本对比：农民 `AbilityButton=70x71`、外层槽 `72x200`；七技能箭塔 `AbilityButton=60x60`、外层槽 `64x200`。结论：按钮大小、外层槽宽、图像留边会随可见技能数量动态变化，正式实现不得写死固定像素尺寸。
- 节点路径在农民与七技能箭塔中保持一致：`AbilityN/ButtonAndLevel/ButtonWithLevelUpTab/ButtonWell/ButtonSize/AbilityButton`。因此首选锚点规则稳定为 `AbilityButton`，回退 `ButtonWell`；布局位置和尺寸必须每槽实时读取。
- 七技能 `Ability0` 中 `LevelUpTab=60x40 @ 683,1001`，`ButtonWell=60x60 @ 683,1048`；它们仍是兄弟组件。继续确认不能把整个 `AbilityN` 隐藏，否则会同时破坏升级区域及其他官方组件。
- 尺寸换算应直接从锚点窗口实际尺寸进入代理层局部单位：`localWidth = anchor.actuallayoutwidth / layer.actualuiscale_x`、`localHeight = anchor.actuallayoutheight / layer.actualuiscale_y`。位置仍使用 `(anchorWindow - layerWindow) / layerScale`。
- 正式修复方案已具备两项核心证据：动态选择内部 `AbilityButton` 锚点；移除源 scale 的重复尺寸乘法。尚需普通英雄样本确认英雄多技能布局、升级按钮可见状态及是否维持同一路径。
- 下一步唯一动作：采集一个有多个技能、最好有未分配技能点的普通英雄稳定 dump；只需 BEGIN、SLOT、CANDIDATE、END，并说明升级加号是否可见。之后即可实施正式自适应接管修复。

## 2026-07-28 — 检查点 028：普通英雄样本不要求激活升级加号

- 用户说明：项目当前尚未实现用于增加英雄经验值的调试命令，因此现阶段只能采集“没有未分配技能点”的多技能英雄；无法方便地让原版升级加号进入可点击状态。
- 决定：不为本轮几何调查临时增加经验值/升级调试命令，避免把服务端调试功能混入技能代理锚点修复。
- 没有未分配技能点的多技能英雄仍足以验证：英雄 `AbilityN` 与 `AbilityButton` 路径、可见槽数量、动态按钮尺寸、横向步长、每槽候选节点存在性，以及与农民/七技能箭塔的结构一致性。
- 升级按钮激活态不再作为正式几何修复的前置条件。现有证据已确认 `LevelUpTab` 是 `AbilityButton` 上方的独立兄弟组件；正式修复不得覆盖或整体隐藏该区域。
- 未验证项单独保留：英雄获得未分配技能点后，原版 `LevelUpTab` 的显示、命中和升级操作是否正常。该项应在经验/升级链可测试后纳入功能验收，而不是阻塞当前锚点修复。
- 下一步唯一动作：采集一个没有未分配技能点的多技能普通英雄稳定 dump，只需 BEGIN、所有 SLOT、所有 CANDIDATE、END，并提供一张底栏截图或说明可见技能数量。

## 2026-07-28 — 检查点 029：普通英雄样本完成，批准的几何调查具备实施条件

- 用户提供全能骑士单位 `323` 的完整 `dump=1/2`。稳定样本为 `dump=2`：4 个官方技能槽 `Ability0..Ability3`，外层均为 `72x200`，窗口 X=`771,843,915,987`、步长 `72`。
- 当前 `visibleAbilities()` 错误枚举出 12 个条目：4 个真实技能加 8 个 `special_bonus_*` 天赋；官方 HUD 只创建 4 个 `AbilityN`。正式修复必须过滤天赋，否则代理列表、快捷键和缺失锚点诊断都会错误。
- 英雄槽 0、1、3 的 `AbilityButton=70x71`；槽 2 的被动技能 `omniknight_hammer_of_purity` 为 `AbilityButton=64x64 @ 919,1048`，而同槽 `ButtonWell` 仍为 `70x71 @ 917,1045`。结论：即使同一英雄同一排，真实按钮矩形也可因技能表现类型不同；必须逐槽读取 `AbilityButton`，不能以 `ButtonWell` 或槽数量统一推算。
- 英雄 `Ability0` 路径与农民/箭塔一致；`LevelUpTab=70x40 @ 773,1000`，是按钮上方独立兄弟组件。日志中的 `LevelUpBurstFXContainer`、`LevelUpTab` 和 `LevelUpButton` 均为 visible，说明升级相关区域确实独立存在，正式接管不得整体隐藏 `AbilityN`。
- 三类样本现已齐全：农民单槽、七技能箭塔、四技能英雄（含不同尺寸被动槽）。调查结果足以实施正式自适应修复；无需继续收集布局数据。
- 实施方案：关闭 `abilitySurvey`；过滤 `special_bonus_*`；每槽选择 `AbilityButton || ButtonWell`；位置使用窗口差除代理层 scale；尺寸使用锚点 `actuallayoutwidth/height` 除代理层 scale；仅抑制 `ButtonWell`/按钮区域与项目已替代的官方热键/等级视觉，保留 `LevelUpTab`。
- 下一步唯一动作：修改 `ui_bootstrap.js` 与 `hud_takeover.js`，强制编译 JS/XML，重新 Run 验证英雄、农民和七技能箭塔的对齐、Tooltip、点击与升级区域保留情况。

## 2026-07-28 — 检查点 030：自适应技能按钮锚点修复已实施并编译

- 用户澄清全能骑士样本是存在未分配技能点的状态。日志也提供直接证据：英雄 `LevelUpBurstFXContainer=visible true, 72x89` 并生成 `LevelUpBurstFX` 场景节点；此前农民样本该容器为 `visible=false, 0x0`。因此升级提示激活态已经采集，无需再为本轮调查增加经验命令。
- `ui_bootstrap.js` 已将临时 `abilitySurvey` 默认值切回 `false`，恢复正式技能代理；调查代码和 `SetSurveyEnabled`/`DumpSurvey` 接口保留为可回滚诊断入口。
- `visibleAbilities()` 已过滤名称以 `special_bonus_` 开头的天赋。全能骑士正式代理将只映射 4 个真实官方槽，不再错误创建/诊断 8 个天赋槽。
- 新增 `officialAbilityAnchor(panel)`：逐槽优先选择内部 `AbilityButton`，缺失时回退 `ButtonWell`，最终才回退外层面板。英雄被动槽的 `64x64`、普通技能的 `70x71`、七技能箭塔的 `60x60` 都会分别按实测矩形处理。
- `placeOverOfficial()` 已移除源节点 scale 的重复乘法。位置公式为 `(anchorWindow-layerWindow)/layerScale`；CSS 本地尺寸为 `anchor.actuallayoutwidth/height / layerScale`，保留三位小数以减少 UI scale 取整误差。
- 官方压制从“整个 `AbilityN` opacity=0 且关闭全部命中”改为仅压制项目已经替代的 `ButtonWell`、`HotkeyContainer`、`AbilityCharges`、`AbilityLevelContainer`。`LevelUpTab`、`LevelUpButton`、`LevelUpBurstFXContainer` 未被压制，升级加号和提示区域得以保留。
- 官方状态存储改为每槽多节点数组，切回调查模式或关闭接管时可逐节点恢复 opacity/hittest/hittestchildren。
- 编译证据：`ui_bootstrap.js` 为 `OK: 1 compiled, 0 failed, 0 skipped`；`hud_takeover.js` 同样通过；HUD XML 加载链为 `OK: 7 compiled, 0 failed, 0 skipped`。
- 静态边界：未修改人物属性接管、技能输入路由、箭塔权威逻辑、物品栏或服务端经验功能。实机视觉、Tooltip、点击和升级按钮命中仍需重新 Run 验收。
- 下一步唯一动作：停止并重新 Run，依次选择有未分配技能点的英雄、农民和 5 级七技能箭塔；检查自定义按钮是否逐槽精确覆盖、无放大偏移、Tooltip/点击正常且英雄升级加号仍显示可点击。

## 2026-07-28 — 检查点 031：实机仍加载修复前技能几何代码

- 用户重新实机测试后提供截图与完整日志：`official=Ability0 source=723,1200 source_size=72x200 source_scale=1.111111... calculated=651,1080 72x200 custom_actual=723,1200 custom_size=80x222`。截图中单个技能代理仍纵向覆盖整个复合槽，图标下方存在大块黑色区域。
- 事实：日志中官方与自定义左上角同为 `723,1200`，再次证明窗口位置到代理层局部位置的换算正确；当前错误仍是外层 `Ability0` 锚点与重复尺寸缩放。
- 事实：磁盘上的正式 `content/.../hud_takeover.js` 已优先选择 `AbilityButton`，尺寸使用 `anchor.actuallayoutwidth/height / layerScale`，且诊断函数接收该内部锚点。若运行的是当前源码，日志不应再出现 `official=Ability0 source_size=72x200 custom_size=80x222`。
- 结论：本次日志来自修复前的运行时代码；不是新自适应公式产生的新几何错误。当前 Run/HUD 上下文没有加载最新 `hud_takeover.vjs_c`，或加载到旧缓存/旧产物。
- 下一步唯一动作：重新强制编译 `ui_bootstrap.js`、`hud_takeover.js` 与 `survival_hud.xml` 加载链，确认零失败后完全停止当前 Run 再启动；新日志必须先确认 `official=AbilityButton`，然后才继续判断视觉几何。

## 2026-07-28 — 检查点 032：用户批准底栏 UI 收尾新范围

- 用户最新实机基线：当前截图中的技能代理已显示，但技能槽缺少清晰边框；由于未重新启动 Workshop Tools，截图保持当前运行时原样，用户明确要求按此继续。
- 新 Bug：第一座箭塔升到 5 级后，转职技能开始是亮的，稍后置灰；第二座箭塔升到 5 级再转职正常。
- 新范围：继续物品栏项目气泡 UI；角色栏攻击、护甲、攻速、力量、敏捷、智力的悬停详细 Tooltip 整体删除，以减少工作量。
- 保留边界：角色栏图标与权威数值继续保留；官方背包的使用、拖放、换位、丢弃和出售继续由 Valve 负责；地面掉落物 Tooltip 不进入本轮。
- 已确认事实：客户端技能代理只在 Runtime `removed=1` 或 `available=0` 时置灰；项目已有 `survival_inventory_item_identity`、`survival_item_tooltips` 和 `tooltip_view_model` 数据基础。
- 当前推断：箭塔“稍后置灰”很可能来自延迟 Runtime 快照或错误/过期的单位状态；具体根因尚未通过测试确认。
- 已排除：不通过 CSS 强制保持转职技能点亮；不为了物品气泡重写官方背包输入；不删除 `combat_stats.js` 的权威数值显示链。
- 工作区风险：存在大量本任务之外的修改和未跟踪文件；后续只编辑明确相关文件，不执行全局 reset/checkout。
- 用户决策：已批准按“检查点 → 箭塔测试/根因 → 技能边框 → 删除属性 Tooltip → 独立物品气泡 → 编译测试”的计划执行。
- 下一步唯一动作：读取实际 Panorama、Runtime、建筑升级与测试文件，先建立首座/第二座箭塔延迟刷新回归测试。

## 2026-07-28 — 检查点 033：首座箭塔延迟置灰根因已测试并修复

- 新测试序列：同队两座箭塔；第一座 Runtime 缓存仍为 1 级，但单位实体已达到 5 级；第二座正常为 5 级；随后触发延迟 `RESOURCE_CHANGED` 全队刷新。
- 修复前证据：`test_tower_upgrade_runtime_refresh.lua` 明确失败于“first tower class ability regressed to unavailable after delayed refresh”。
- 根因：`ability_runtime_service.lua` 在资源事件中直接重发 `state_by_unit` 缓存；箭塔升级系统虽已先写 `unit.survival_level` / `unit.survival_tower_class`，Runtime 发布前没有与实体权威字段对账。
- 修复：仅对箭塔在每次 Runtime 发布前读取自身实体的权威等级、路线与显示名；不改变 `tower_class()` 可用规则，不用客户端 CSS 强制点亮，也不共享两座塔的状态。
- 修复后证据：扩展后的 `TOWER_UPGRADE_RUNTIME_REFRESH_PASS` 通过；首塔和第二塔的 `owner_entindex`、`current_level=5`、`available=1` 均分别断言。
- 尚未完成：技能边框、属性 Tooltip 删除、独立物品 Tooltip Panorama 实施与编译。
- 下一步唯一动作：按已确认职责边界完成限定 Panorama 编辑，然后强制定向编译和回归测试。

## 2026-07-28 — 检查点 034：底栏 UI 收尾实施与自动验证完成

- 技能边框：`ability_tooltip.css` 的代理槽改为 2px 浅色边框与暗色阴影；hover 使用金色边框和光晕；被动、资源不足继续有独立边框状态。
- 属性 Tooltip：删除 `hero_stat_tooltip.js`，从 HUD XML 移除脚本、`SurvivalStatTakeoverLayer` 和 `CustomHeroStatTooltip`，删除对应 CSS 和旧 `hero_stat_tooltip.vjs_c`；`combat_stats.js` 仍写入攻击、护甲、攻速与三围权威数字。
- 物品气泡：新增 `inventory_tooltip.js`、`inventory_tooltip.css` 和 `CustomInventoryItemTooltip` XML；静态字段读取 `survival_item_tooltips`，身份读取 `survival_inventory_item_identity`，动态成长读取 `survival_weapon_snapshot.tooltip_view_model.items[content_id]`。
- 交互边界：控制器只设置 `onmouseover/onmouseout`，不设置 `onactivate`，不关闭槽或 ItemImage 命中，不创建覆盖背包的代理层；绑定恢复只扫描 6 个槽并由初始有限重试、选择变化、身份/快照变化和鼠标移出触发。
- 原生物品 Tooltip 压制：悬停当帧与 50ms 后有限隐藏一次，不使用 0.03/0.35 秒永久循环。
- Panorama 编译：`ui_bootstrap.js`、`combat_stats.js`、`inventory_tooltip.js`、`ability_tooltip.css`、`inventory_tooltip.css` 均获得 `1 compiled, 0 failed, 0 skipped`；最终 HUD XML 加载链获得 `7 compiled, 0 failed, 0 skipped`。
- Lua 验证：`ALL_LUA_TESTS total=30 failed=0`；箭塔定向测试通过；相关 Lua 文件 `luac -p` 通过。
- 静态验证：game/content 两侧限定 `git diff --check` 均无空白错误，仅有既有 LF/CRLF 提示；新编译产物均存在且非空，旧属性 Tooltip 产物不存在。
- 尚未验证：助手无法直接观察 Workshop Tools；技能边框视觉、Valve 物品 Tooltip 是否在当前 HUD 版本完全消失、物品使用/拖放/换位/丢弃/出售，以及两座真实箭塔延迟状态仍需重新 Run 实机确认。
- 下一步唯一动作：完全停止并重新 Run，按 `CURRENT_TASK.md` 的四组实机项目验收；若物品仍出现双 Tooltip，提供官方槽展开树与截图，不要用关闭 ItemImage 命中作为修复。

## 2026-07-28 — 检查点 035：属性 Tooltip 删除边界补齐

- 最终复核发现：只删除自定义属性代理仍可能让 Valve 的 `Damage`、`AttackSpeed`、`Armor` 节点恢复原生悬停 Tooltip。
- 补丁：`combat_stats.js` 在保留三个节点可见、图标和权威数字覆盖的同时，将它们设为 `hittest=false`、`hittestchildren=false`；三围项目行原本就是非命中。
- 该补丁不创建属性代理、不显示 Tooltip、不改变服务端快照或任何结算值。
- 编译证据：最终 `combat_stats.js` 为 `1 compiled, 0 failed, 0 skipped`；HUD XML 加载链为 `7 compiled, 0 failed, 0 skipped`。
- 恢复文档已同步清理旧冲突：不再把 `hero_stat_tooltip.js`、`SurvivalStatTakeoverLayer` 或属性 Tooltip 作为当前实现/待验收项。
- 下一步唯一动作不变：完全停止并重新 Run，执行底栏视觉、双塔 Runtime、背包气泡/操作和无属性 Tooltip 实机验收。

## 2026-07-28 — 检查点 036：批准专属真实地面物品方案

- 用户最终问题：地面物品 Tooltip 若只能由官方 UI 可靠显示，是否可直接创建一个能被官方 Tooltip 识别的真实物品；并询问 `ItemLaunch` 是否可用于此目的。
- 已确认：`CreateItem` 创建已注册的真实 Dota item ability，`CreateItemOnPositionSync` 创建承载它的地面物理容器；官方世界 Tooltip 根据引擎物品名读取 KV 和本地化。`ItemLaunch` 类接口只负责掉落运动/动画，不负责运行时定义新物品。
- 当前根因：`challenge_equipment_reward_service.lua` 对所有挑战材料统一创建 `item_survival_challenge_reward`，所以官方 Tooltip 只能显示笼统的“挑战奖励”。
- 已确认基础：项目已有合成宝石、熔火核心 Lv1～Lv4、冰魂焰魄六个专属壳 KV 与本地化；但这些壳当前只是视觉类，真正的采用、库存登记、合并和自动合成逻辑只在通用奖励的 `Claim()` 中。
- 配置决策：在 `data/csv/物品系统/item_definitions.csv` 增加 `engine_item_name`，复用武器表已有模式；通用 CSV 生成器会自动透传新增列，不创建第二份手写映射。
- 安全决策：新地面奖励带 `survival_ground_reward=true`，成功登记后清除；拾取入口不能只按专属物品名判断，否则玩家把已有材料丢下再捡会复制逻辑库存。
- 用户批准：按完整方案实施“专属真实地面物品 + 官方地面 Tooltip + 项目背包 Tooltip”；不实施世界鼠标实体轮询。
- 下一步唯一动作：实施 CSV 映射、共享 Claim、专属掉落和拾取回归测试，并完成全量自动验证。

## 2026-07-28 — 检查点 037：专属真实地面物品实施完成

- 配置：`data/csv/物品系统/item_definitions.csv` 新增末尾列 `engine_item_name`；六种材料映射到 `item_survival_synthesis_gem_shell`、熔火核心 01～04 壳和 `item_survival_ice_soul_ember_shell`。使用 `py -3` 定向生成 `config/generated/item_definitions.lua`，临时重建文件与正式产物逐字节一致。
- 掉落：`challenge_equipment_reward_service.lua` 不再创建通用 `item_survival_challenge_reward`，而是按 CSV 创建专属物品；映射缺失失败关闭并返回 `challenge_ground_reward_item_mapping_missing`。
- Claim：新增 `items/challenge_ground_reward_claim.lua`，通用兼容物品和六个专属壳共享所有者校验、ID 规范化、可见壳采用、逻辑库存登记、重复合并、失败释放、合成事件和通知。
- 防复制：新掉落实体设置 `survival_ground_reward=true`；成功登记后设置为 `false`。拾取入口只处理该标记或未登记的通用兼容物品，因此已有背包材料丢下再捡不会重复发放逻辑库存。
- 失败回退：`addon_game_mode.lua` 现在检查 `Claim()` 返回值；登记失败且实体仍有效时，把同一实体放回英雄脚下，不创建副本。
- 单一来源：`weapon_equipment_service.lua` 删除手写材料壳表，补建、采用和同步判断统一读取 `item_definitions` 生成配置。最终源码复核曾发现采用入口残留旧变量引用，已修正并新增服务级回归测试。
- Tooltip：中英文补齐熔火核心 Lv1～Lv4 与冰魂焰魄的 `item_...`、`DOTA_Tooltip_ability_...`、`DOTA_Tooltip_Ability_...` 名称和说明；合成宝石沿用并保留既有完整键。
- 测试：新增 `test_challenge_ground_reward_claim.lua`、`test_material_shell_adoption.lua`；扩展 `test_molten_core_ground_drop.lua` 覆盖挑战 05/07/08/09、幂等和映射缺失失败关闭。
- 验证：`ALL_LUA_TESTS total=32 failed=0`；相关 Lua `luac -p` 成功；CSV 可重现生成成功；限定 `git diff --check` 通过，仅有 LF/CRLF 提示；限定源码搜索无 `material_shells` 或 `CreateItem("item_survival_challenge_reward")` 残留。
- 尚未验证：Valve 世界物品 Tooltip 的最终视觉与鼠标命中只能在 Workshop Tools 中观察；还需实机确认装备栏满回落、重复材料数量显示、已有材料丢弃再拾取不复制和自动合成后的实体清理。
- 下一步唯一动作：完全停止并重新 Run，先验收挑战 05/07/08/09 的专属地面 Tooltip 与拾取全链，再执行既有底栏 UI、双塔 Runtime、背包操作和无属性 Tooltip 验收。

## 2026-07-28 — 检查点 038：箭塔技能代理与官方 UI 同时出现，用户批准完整修复

- 用户最新反馈：箭塔底栏同时出现项目大按钮和 Valve 官方小按钮，并询问是否为此前 `[SURVIVAL_GEOMETRY]` 调查取错图片尺寸或布局。
- 截图直接证据：项目按钮的连续视觉位置显示 `Q/W/T`；右侧官方小图标分别吻合 `ability_tower_class_4` 的 `sniper_take_aim` 和 `ability_tower_class_6` 的 `lich_frost_nova`，因此不是物品栏或无关 HUD。
- 已确认事实：当前 `hud_takeover.js` 已以内部 `AbilityButton` 为几何锚点并移除重复 scale，旧 `72x200 Ability0` 外壳问题不是本次唯一或主要根因。
- 已确认根因：实体技能数组被稠密化后，刷新仍以 `displayIndex` 直接查 `AbilityN`；箭塔 5 级删除原升级技能并动态追加七个转职技能时，Valve 节点可出现 ID 空洞/复用/重排。当前逐槽立即提交会让成功槽保持项目 UI、失败槽折叠代理、未压制槽继续显示官方 UI。
- 已确认附加风险：官方压制缺少 `ButtonWell` 时不会可靠隐藏实际 `AbilityButton`；服务端两处对数组 `class_options` 使用 `pairs()`。
- 已排除：不再针对特定 `Ability2/Ability3` 写硬编码补丁；不通过固定像素缩小项目按钮；不隐藏整个官方技能容器；不改变技能施法与费用权威语义。
- 用户决策：明确“确认”视觉顺序映射、原子接管/整批回退、确定性服务端顺序、状态变化映射日志和完整编译测试计划。
- 编辑边界：只修改 `hud_takeover.js`、`building_upgrade_system.lua`、`tower_ability_sync.lua` 和恢复文档；工作区大量其他修改不得 reset/checkout。
- 下一步唯一动作：实施限定编辑，强制编译 Panorama，运行 Lua 语法、全量测试和限定静态检查。

## 2026-07-28 — 检查点 039：原子技能接管已实施，终端验证通道异常

- 已实施 `hud_takeover.js`：枚举 `Ability0..Ability23` 中具有有效内部视觉/几何的节点，按窗口 X/Y 排序，预先校验数量、代理槽和全部几何后才整批提交。
- 原子行为：每轮先恢复上一代官方节点；映射失败时折叠全部项目代理并保留完整官方 UI；映射成功时按视觉顺序生成 `Q/W/E/R/T/Y/U`、覆盖全部按钮并统一压制官方视觉。
- 官方压制：优先压制 `ButtonWell`，不存在时压制实际 `AbilityButton`；继续独立压制官方热键、充能和等级容器，保留 `LevelUpTab`。
- 诊断：新增状态去重的 `[SURVIVAL_TAKEOVER_MAP]`，记录单位、模式、官方节点 ID、锚点尺寸/坐标和视觉映射；旧 `anchor_state` 失败信息改为真实预检原因。
- 服务端：`building_upgrade_system.lua` 添加转职能力和 `tower_ability_sync.lua` 清理转职能力均由 `pairs()` 改为数组确定顺序 `ipairs()`；`test_arrow_tower_completion.lua` 增加源码级防回归断言。
- 当前有效验证：限定 Lua/docs `git diff --check` 已通过，仅有既有 LF/CRLF 提示；源码回读确认文件完整闭合。
- 工具异常：资源编译、Lua 语法、定向测试和全量测试四个独立命令均在 30 秒被终端桥接统一超时；后续连 `py -3` 文件元数据和进程查询也超时。全量新日志没有创建，因此不能把此次超时视为 PASS 或代码 FAIL，也不能直接重复写入/编译命令。
- 尚未验证：本轮 `hud_takeover.vjs_c` 是否已实际更新、Lua 语法、两个定向测试、32 个全量测试和最终限定差异。
- 下一步唯一动作：先用最小只读命令确认终端恢复；再只补跑缺失证据，不重复已有明确成功项。

## 2026-07-28 — 检查点 040：固定技能网格与地面物品 Tooltip 失败实证

- 用户最新实机反馈：1～2 个技能时项目图标较大、7 个技能时较小；用户要求采用 Unity `GridLayout + ContentSizeFitter` 等价结构，固定每个 cell 大小。
- 截图直接证据：地面物品的 Valve Tooltip 只显示物品图标和“技能：被动”，标题与说明为空；此前“专属真实物品已修复世界 Tooltip”的视觉结论被推翻。
- 代码证据：`hud_takeover.js` 的 `applyOfficialGeometry()` 仍执行 `customPanel.style.width/height = geometry.width/height`，所以项目 cell 必然继承 Valve 动态尺寸。
- 代码证据：`challenge_equipment_reward_service.lua` 已调用 `CreateItem(engine_item_name)`，CSV、KV 和中英文本地化也已有六种材料静态定义；问题不是尚未使用 `CreateItem`。
- 架构结论：Lua 实例上的 `survival_content_id` 等字段不会成为 Valve Tooltip 元数据；没有采用虚构的运行时名称/说明/图标 setter。继续走静态注册 item ability，并诊断 requested/actual item name 与客户端本地化加载。
- 用户批准：固定 65×65 技能行、保留视觉顺序和原子接管、增加服务端物品身份日志与客户端一次性本地化诊断、补测试、强制编译和全量验证。
- 修改边界：不重写世界鼠标命中、拾取、背包操作、技能施法或费用语义；不 reset/checkout 工作区其他改动。
- 下一步唯一动作：实施固定技能行和诊断，完成定向/全量测试与资源编译，再完全停止 Workshop Tools 重启实机验收。

## 2026-07-28 — 检查点 041：固定技能行与物品诊断实施、自动验证完成

- HUD 实施：`survival_hud.xml` 新增 `SurvivalAbilityTakeoverRow`；`ability_tooltip.css` 固定 cell 为 65×65、间距 4px；`hud_takeover.js` 使用整组官方锚点的包围宽度中心和底部定位固定行，不再复制单个 Valve 锚点宽高。
- 原子行为保留：每次刷新先恢复上一代官方状态；映射失败时折叠整行并保留完整 Valve UI；成功后整批显示固定行并压制所有对应官方按钮。
- 物品诊断：服务端 `[CHALLENGE_REWARD_DROP]` 增加 `requested_item` 与 `actual_item`；客户端 HUD 初始化增加一次性 `[SURVIVAL_GROUND_ITEM_LOCALIZATION]`，覆盖六种材料名称与说明 token。
- 静态契约：`test_molten_core_ground_drop.lua` 现在校验六个 CSV 映射、KV 注册和中英文本地化；`test_arrow_tower_completion.lua` 校验固定 65×65、行容器存在且源码不再复制 Valve 动态宽度。
- 定向验证：`ARROW_TOWER_COMPLETION_PASS`、`MOLTEN_CORE_GROUND_DROP_PASS`；掉落测试中挑战 05/07/08/09 的 requested/actual item 全部一致。
- 全量验证：`ALL_LUA_TESTS total=32 failed=0`；相关 `luac -p` 成功；game/content 限定 `DIFF_CHECK_PASS`，仅有 LF/CRLF 提示。
- Panorama 强制编译：`hud_takeover.js` 与 `ability_tooltip.css` 各 `1 compiled, 0 failed, 0 skipped`；`survival_hud.xml` 加载链 `7 compiled, 0 failed, 0 skipped`。目标产物时间为 22:10:32～22:10:33。
- 事实边界：自动证据证明静态定义完整、实际创建名正确，但不能证明 Valve 世界 Tooltip 已显示名称与说明；该视觉问题仍未解决，必须完全重启后依据客户端本地化日志继续判断。
- 下一步唯一动作：完全停止 Workshop Tools 并重新 Run；验收 1/2/7 技能固定尺寸，触发挑战 05/07/08/09，保存两类新诊断日志与 Tooltip 截图。

## 2026-07-28 — 检查点 042：实机反馈推翻 65px 基线并定位本地化加载路径

- 用户最新反馈：完全重启后的技能图标仍明显偏大，要求按此前“小图标”尺寸修正；挑战 05 地面掉落仍显示官方空 Tooltip，并提供两类诊断日志。
- 掉落实体事实：`[CHALLENGE_REWARD_DROP]` 中 `requested_item=item_survival_synthesis_gem_shell` 与 `actual_item=item_survival_synthesis_gem_shell` 一致，因此掉落服务、CSV 映射和 `CreateItem` 实际身份不是本次 Tooltip 空白根因。
- 客户端事实：`[SURVIVAL_GROUND_ITEM_LOCALIZATION]` 中六种材料的名称与说明全部原样返回 `#token`，证明客户端没有加载这些本地化 token；该日志只输出一次符合预期，不是诊断循环问题。
- 加载路径根因：完整中英文文件位于非标准的 `resource/localization/addon_*.txt`；引擎实际读取的根目录 `resource/addon_english.txt` 仍是 `YOUR ADDON NAME` 模板，且根目录没有 `addon_schinese.txt`。同机 Valve 示例均把游戏本地化放在 `resource/addon_<language>.txt`。
- Panorama 边界：一次性 `$.Localize()` 诊断同时需要标准 `panorama/localization/addon_<language>.txt` 词典；本项目此前没有该标准目录文件。
- 尺寸结论：65 Panorama px 在当前 `1.111...` UI scale 下约为 72 屏幕 px，与截图中的偏大尺寸一致。按用户指出的“小图标”视觉基线，本轮改为固定 52×52，间距继续为 4px；仍禁止继承 Valve 动态宽高。
- 已排除：没有把长行读取工具的截断显示误判为英文引号缺失；逐行扫描确认中英文源文件均无奇数引号行。
- 下一步唯一动作：同步标准游戏/Panorama 本地化入口，修改 52×52 源码与测试，强制编译 Panorama，并执行定向/全量回归。

## 2026-07-28 — 检查点 043：52px 与标准本地化入口修复验证完成

- 技能源码：`hud_takeover.js` 的 `fixedCellSize` 与 `ability_tooltip.css` 的 row/slot 宽高均为 52；4px 间距、固定行居中、视觉顺序映射、原子接管/整批回退均保留。
- 本地化源码：完整 `lang/Tokens` 中英文已进入 `game/.../resource/addon_english.txt` 与 `addon_schinese.txt`；完整平铺 `dota` 中英文已进入 content 和 game 两侧 `panorama/localization/addon_*.txt`。
- 诊断增强：一次性 `[SURVIVAL_GROUND_ITEM_LOCALIZATION]` 现在先输出 `addon_game_name` 与通用挑战奖励 token 两个 control，再输出六种材料，便于区分整份词典和单个材料 token 的加载状态。
- 静态验证：六个标准词典文件均为 UTF-8 BOM；游戏文件括号为 2/2，Panorama 文件为 1/1；奇数引号行均为 0；关键合成宝石中英文存在；游戏文件与原 `resource/localization/` 文本逐字节一致。
- 定向验证：`ARROW_TOWER_COMPLETION_PASS`、`MOLTEN_CORE_GROUND_DROP_PASS`；挑战 05/07/08/09 requested/actual engine item 全部一致；相关 `luac -p` 成功。
- 全量验证：新日志 `.cline_tmp/ground_item_localization_fix_all_tests.txt` 末尾为 `ALL_LUA_TESTS total=32 failed=0`。
- Panorama 强制编译：`hud_takeover.js` 与 `ability_tooltip.css` 各为 `OK: 1 compiled, 0 failed, 0 skipped`；产物时间 `22:30:57～22:30:58`。game/content 限定 `diff --check` 通过，仅有既有 LF/CRLF 提示。
- 尚未验证：自动验证不能证明 52px 最终视觉或 Valve 世界 Tooltip 已显示；必须完全停止 Workshop Tools 后重新 Run。
- 下一步唯一动作：实机选择 1/2/7 技能单位并触发挑战 05；确认小尺寸固定、control/材料 token 均解析为真实文本、世界 Tooltip 显示标题与说明。

## 2026-07-28 — 检查点 044：服务中断后恢复与用户日志版本判定

- 用户要求确认任务是否完成，并再次提供一条只包含六种材料的 `[SURVIVAL_GROUND_ITEM_LOCALIZATION]` 日志，以及挑战 05 的 `[CHALLENGE_REWARD_DROP]` 日志；随后上游服务暂时不可用，用户要求继续之前任务。
- 任务状态：未完成。用户实机仍报告技能尺寸明显偏大、官方地面物品 Tooltip 为空。
- 掉落实体事实：`requested_item=item_survival_synthesis_gem_shell` 与 `actual_item=item_survival_synthesis_gem_shell` 一致，掉落实体身份链正常。
- 版本判定：用户日志没有检查点 043 最新源码新增的 `addon_game_name` 与通用挑战奖励两个 control，因此该日志不是最新诊断格式，极可能来自旧 `hud_takeover.vjs_c`；对应画面也不能证明当前 52px 产物实际已加载。
- 尚未确认：Workshop Tools 当前 Run 究竟加载了哪个时间戳的 VJS/VCSS；最新版标准本地化文件是否被当前进程读取；52px 若确实加载后是否仍偏大。
- 下一步唯一动作：核对源码、编译产物和 HUD 加载链，重新强制编译相关 Panorama 资源，再以包含 control 的新日志进行实机版本确认。

## 2026-07-28 — 检查点 045：版本化诊断与最终自动验证完成

- 用户在服务恢复后再次询问任务是否完成，并要求未完成则继续。当前任务整体仍需实机验收，但所有可由助手执行的代码、编译与自动测试工作已完成。
- 版本防混淆：`hud_takeover.js` 新增 `takeoverBuild="grid52_loc_v2"`；一次性日志现在以 `build=grid52_loc_v2|cell=52|gap=4` 开头，随后输出 `addon_game_name`、通用挑战奖励 control 和六种材料 token。
- 尺寸证据：历史 `OfficialOverlayOnly_20260722_0004` 的旧自定义技能槽明确为 65×65；用户报告的偏大画面与无 control 的旧日志相匹配。当前源码和 CSS 均为固定 52×52，未找到可证明应采用其他像素值的可靠历史证据，因此不凭猜测继续缩放。
- 防回归测试：`test_arrow_tower_completion.lua` 新增 build 标识和运行时 cell 尺寸日志断言，原有固定 52px、固定行和禁止继承 Valve 动态宽度断言保留。
- 定向测试：`ARROW_TOWER_COMPLETION_PASS`、`MOLTEN_CORE_GROUND_DROP_PASS`；后者继续确认挑战 05/07/08/09 requested/actual engine item 一致。
- 全量测试：`ALL_LUA_TESTS total=32 failed=0`。
- Panorama：更新后的 `hud_takeover.js` 为 `OK: 1 compiled, 0 failed, 0 skipped`；HUD XML 加载链为 `OK: 7 compiled, 0 failed, 0 skipped`。最终 `hud_takeover.vjs_c`、`ability_tooltip.vcss_c`、`survival_hud.vxml_c` 时间均为 2026-07-28 23:05:38 +0800。
- 差异检查：限定 game/content `diff --check` 成功，仅有既有 LF/CRLF 提示。
- 尚未确认：助手无法直接观察 Workshop Tools。必须完全停止后重新 Run；若首条本地化日志没有 `build=grid52_loc_v2|cell=52|gap=4`，说明仍未加载最终产物。只有版本标识正确后，技能视觉与世界 Tooltip 结果才是有效验收样本。
- 下一步唯一动作：用户完全停止并重新 Run，返回首条带 build 标识的本地化日志，并确认 1/2/7 技能尺寸与挑战 05 地面 Tooltip。

## 2026-07-28 — 检查点 046：最终实机确认尺寸与地面 Tooltip，剩余技能行垂直基准问题

- 用户最新实机反馈：单技能与多技能的图标大小已经相同，地面 Tooltip 已成功；仅剩多技能状态的技能行明显更高，用户要求按左上角对齐修复最后这个小问题。
- 源码事实：`ability_tooltip.css` 中行高和 cell 均固定为 52px；高度差不是内容撑开或尺寸回归。
- 根因证据：`hud_takeover.js` 的 `measureFixedRowGeometry()` 仍按内部 Valve 按钮包围盒执行水平居中和底边对齐：`x = left + ((right - left) - width) / 2`、`y = bottom - fixedCellSize`。Valve 单技能与多技能布局会改变内部按钮的垂直位置，因此项目固定行仍随数量上下移动。
- 修复决定：整行改用稳定的官方 `abilities` 容器左上角作为原点，技能数量只向右扩展固定行宽；内部 `AbilityButton` 继续只负责视觉顺序映射、完整性校验和官方视觉压制。
- 修改边界：不改 52×52、4px 间距、技能输入/Tooltip、地面物品 Tooltip、本地化或服务端逻辑。
- 尚未验证：新的左上角基准在 Workshop Tools 中的最终视觉位置。
- 下一步唯一动作：修改 JS/CSS 与源码防回归断言，强制编译相关 Panorama 资源并运行定向/全量验证。

## 2026-07-28 — 检查点 047：技能行左上角对齐实施与自动验证完成

- Panorama 实施：`hud_takeover.js` 新增 `officialAbilitiesRowAnchor()`，固定行 `x/y` 直接采用官方 `abilities` 容器几何；删除内部按钮包围盒的水平居中和底边定位。行宽仍为 `数量×52 + 间距×4`，仅向右延伸。
- 兼容边界：逐槽 `AbilityButton` 几何校验、视觉顺序映射、原子接管/整批回退、官方压制、`Q/W/E/R/T/Y/U`、Tooltip 与施法输入均未改变。
- 版本防混淆：`takeoverBuild` 更新为 `grid52_topleft_v3`；最新一次性日志应以 `build=grid52_topleft_v3|cell=52|gap=4` 开头。
- 防回归测试：`test_arrow_tower_completion.lua` 断言必须使用 `officialAbilitiesRowAnchor` 的 `x/y`，且 JS 源码不得再含 `bottom - fixedCellSize`。
- 定向验证：`ARROW_TOWER_COMPLETION_PASS`。
- 全量验证：`.cline_tmp/ability_topleft_v3_all_tests.txt` 末尾为 `ALL_LUA_TESTS total=32 failed=0`。
- Panorama 强制编译：`hud_takeover.js` 为 `OK: 1 compiled, 0 failed, 0 skipped`；游戏产物 `panorama/scripts/custom_game/hud_takeover.vjs_c` 时间为 `2026-07-28 23:19:30 +0800`，大小 44883 字节。
- 差异与源码复核：game/content 限定 `diff --check` 成功；源码回读确认固定 52×52、4px 间距和左上角公式完整。
- 尚未确认：助手无法直接观察 Workshop Tools；1、2、7 个技能的最终左边/顶边一致性仍需重新 Run 实机确认。
- 下一步唯一动作：完全停止 Workshop Tools 并重新 Run；确认 `grid52_topleft_v3` 版本标识后，对比 1 个与 7 个技能的左边和顶边。

## 2026-07-29 — 检查点 048：左上角方案被实机否定，批准运行时锚点校准器

- 用户补充断线前的最新实机结论：此前已经提供截图；采用官方 `abilities` 容器左上角后，所有项目技能超出原来的技能范围。因此检查点 047 的代码/编译事实仍有效，但“左上角只差最终验收”的结论已被实机证据推翻。
- 用户候选想法：以中下位置作为锚点可能更合理，但用户不希望继续猜测，希望能在游戏中自己调整锚点并直接看 1、2、7 技能的实际分布。
- 源码调查：最终位置只由 `measureFixedRowGeometry()` 生成并由 `row.style.position` 应用；现有 `geometryTick()` 每 0.5 秒刷新，适合接入统一运行时校准状态。`SurvivalAbilityTakeover` 也已有 `Refresh`、`DumpSurvey` 和 `SetSurveyEnabled` API 模式可复用。
- 已排除：仅在 Panorama Debugger 修改 `style.position`，因为 0.5 秒几何刷新会覆盖临时值，且无法可靠输出可固化参数；也不直接把中下候选写死为最终决策。
- 用户批准完整方案：九宫格锚点、X/Y ±1/±5 微调、Valve `abilities` 容器/可见技能包围范围/项目行边界框、锚点十字、实时数据、重置/关闭和参数日志输出。
- 修改边界：只改 Panorama JS/CSS/XML 和源码契约测试；保持 52×52、4px、视觉顺序、原子接管/整批回退、官方压制、快捷键、技能输入、Tooltip、背包和地面物品逻辑不变。
- 下一步唯一动作：实施校准器并完成强制编译、定向/全量测试和限定差异检查，再交由用户实机输出最终参数。

## 2026-07-29 — 检查点 049：运行时锚点校准器实施完成，准备资源编译

- `hud_takeover.js`：版本更新为 `grid52_calibrator_v4`；增加九宫格归一化锚点模型，同一锚点同时作用于 Valve `abilities` 容器与固定技能行，再叠加运行时 X/Y 偏移。默认仍为旧左上角/0,0，避免未开启调试时出现未经实机选择的新布局。
- 运行时 API：增加 `SetCalibrationAlignment`、`NudgeCalibration`、`ResetCalibration`、`SetCalibrationVisible`、`ToggleCalibration`、`DumpCalibration` 和 `GetCalibration`；控制台命令 `survival_ability_calibration` 切换面板，`survival_ability_calibration_dump` 输出参数。
- 游戏内面板：增加九宫格按钮、X/Y ±1/±5、实时容器/原生技能/项目行矩形、重置、关闭和输出参数按钮。
- 可视边界：蓝框为 Valve `abilities` 容器、黄框为当前有效 Valve 技能包围范围、绿框为项目固定技能行、红十字为容器选定锚点；所有边界节点关闭命中，不阻断技能点击。
- 保留边界：cell 仍为 52×52、间距 4px；视觉顺序映射、完整映射校验、原子接管/整批回退、官方压制、快捷键、技能点击与 Tooltip 路径未修改。
- 自动验证现状：限定 game/content `diff --check` 通过（仅既有 LF/CRLF 提示）；`test_arrow_tower_completion.lua` 已返回 `ARROW_TOWER_COMPLETION_PASS`。
- 下一步唯一动作：强制编译 `hud_takeover.js`、`ability_tooltip.css` 和 `survival_hud.xml`，检查每项 `compiled > 0`、`failed=0`，再运行全量回归。

## 2026-07-29 — 检查点 050：校准器 Panorama 资源强制编译成功

- `hud_takeover.js` 强制编译：`OK: 1 compiled, 0 failed, 0 skipped`。
- `ability_tooltip.css` 强制编译：`OK: 1 compiled, 0 failed, 0 skipped`。
- `survival_hud.xml` 加载链强制编译：`OK: 7 compiled, 0 failed, 0 skipped`；JS/CSS/XML 均通过资源编译器实际解析。
- 定向源码契约仍为 `ARROW_TOWER_COMPLETION_PASS`。
- 下一步唯一动作：运行 32 项全量 Lua 回归、核对新编译产物元数据并完成最终限定 `diff --check` 和源码回读。

## 2026-07-29 — 检查点 051：运行时锚点校准器自动验证全部完成

- 全量回归：新日志 `.cline_tmp/ability_calibrator_v4_all_tests.txt` 末尾为 `ALL_LUA_TESTS total=32 failed=0`；32 个测试逐项均为 PASS。
- 编译产物：`hud_takeover.vjs_c` 55243 字节、`ability_tooltip.vcss_c` 16064 字节、`survival_hud.vxml_c` 9725 字节，三者时间均为 `2026-07-29 08:54:12 +0800`。
- 最终源码回读：九宫格公式按容器/项目行同一归一化点对齐；X/Y 偏移实时进入最终 `row.style.position`；面板 XML API 名称与 JS 导出一致；边界节点均关闭命中。
- 保留契约：52×52、4px、完整映射、原子接管/回退、官方压制、输入与 Tooltip 路径保持不变；默认面板隐藏且保持 `top_left/0,0`，未擅自固化中下候选。
- 最终限定 `diff --check` 通过，仅有既有 LF/CRLF 提示。
- 实机入口：完全停止并重新 Run 后，在控制台执行 `survival_ability_calibration`；满意后点击“输出当前参数”或执行 `survival_ability_calibration_dump`。
- 尚未验证：助手无法直接观察 Workshop Tools；最终锚点和偏移必须由用户比较 1、2、7 技能状态后确认。
- 下一步唯一动作：用户返回完整 `[SURVIVAL_ABILITY_CALIBRATION] build=grid52_calibrator_v4 ...` 日志；根据实机结果固化最终布局，并决定移除还是默认关闭校准 UI。

## 2026-07-29 — 检查点 052：收到三技能校准参数并定位切换延迟/原生图标闪现

- 用户实机输出：`build=grid52_calibrator_v4 alignment=middle_left offset_x=5 offset_y=35 ability_count=3 anchor=652.5,939.6 container_rect=652.5,849.6,190.8x180 visual_rect=652.5,940.5,192.6x63.9 row_rect=657.5,948.6,164x52`；用户认为该版本较好看。当前证据明确覆盖 3 个技能。
- 用户新增问题：切换选中目标时项目 UI 更新明显慢于原版，且有时 Valve 原技能图标先出现，随后才替换为项目图标。
- 源码根因：`runtimeTick()` 每 0.10 秒只更新已接管槽内容；完整技能发现、映射和官方视觉压制仅由 `geometryTick()` 每 0.50 秒调用 `refresh()`。`hud_takeover.js` 当前没有选中单位变化事件订阅，因此切换最差延迟接近 0.5 秒。
- 闪现机制：Valve 先重建/复用新单位的 `AbilityN`，项目层在下一次 0.5 秒刷新前尚未压制这些新视觉节点；映射尚不完整时现有安全回退还会恢复官方视觉，因此原版图标可短暂出现。
- 已排除：把完整 24 槽 HUD 扫描永久提高到 0.03 秒。该方案持续增加扫描与样式写入，仍无法消除 Valve 重建与扫描之间的闪现窗口，并违背事件驱动边界。

## 2026-07-29 — 检查点 053：批准事件驱动无闪切换，准备实施

- 用户明确批准：事件监听触发是正确思路，立即按该方案修复选中目标响应慢和原版技能图标闪现。
- 额外源码确认：`prepareTakeover()` 当前校验技能数量、代理槽和 Valve 几何，但不校验 Valve 节点已经完成新单位内容重建；因此选择事件同一帧不能把新技能数据直接提交到可能仍属于旧单位的视觉节点。
- 实施决定：选中/查询单位事件与 0.10 秒轻量实体哨兵共同触发有界过渡；先隐藏旧项目行、关闭 Tooltip，并临时隐藏官方 `abilities` 容器。随后按 `0/0.016/0.05/0.10/0.20s` 有限刷新，只有完整映射稳定后才原子显示新项目行。
- 安全边界：官方容器过渡状态必须完整保存并恢复；超过短暂宽限仍映射失败则恢复 Valve UI，避免永久无技能按钮。0.5 秒低频几何恢复保留，不增加永久高频 24 槽扫描。
- 校准边界：本次只修响应生命周期；`middle_left/+5/+35` 保留为用户已确认的三技能候选，不擅自改变其他技能数量参数。
- 下一步唯一动作：修改 `hud_takeover.js` 与定向源码契约，强制编译并执行定向/全量回归。

## 2026-07-29 — 检查点 054：事件驱动无闪切换代码完成，准备强制编译

- `hud_takeover.js` 版本更新为 `grid52_selection_events_v5`。
- 即时触发：订阅 `dota_player_update_selected_unit` 与 `dota_player_update_query_unit`；额外 0.10 秒 `selectedUnitSentinel()` 只比较 portrait unit entindex，不执行完整 HUD 扫描。
- 过渡行为：单位变化立即关闭旧 Tooltip、折叠旧项目行并把当前 Valve `abilities` 容器设为透明且关闭命中；容器仍参与布局，因此可继续读取新节点几何。
- 有界重试：严格使用 `0/0.016/0.05/0.10/0.20s`；serial 取消旧单位回调，同单位事件/哨兵在活动窗口内去重。完整映射后原子显示项目行；最终失败恢复 Valve 容器。
- 保留边界：现有逐节点 `rememberOfficial/restoreOfficial` 仍负责正式压制状态；0.5 秒 `geometryTick` 保留为低频恢复，没有引入永久 0.03 秒扫描；校准公式和用户三技能候选参数语义未修改。
- 自动验证现状：更新后的 `test_arrow_tower_completion.lua` 已返回 `ARROW_TOWER_COMPLETION_PASS`；限定源码 `diff --check` 未报告空白错误。
- 下一步唯一动作：强制编译 `hud_takeover.js`，再运行 32 项全量回归、产物检查和最终源码复核。

## 2026-07-29 — 检查点 055：事件驱动无闪切换自动验证完成

- 最终版本：`grid52_selection_events_v5`。
- 实施结果：`dota_player_update_selected_unit` 与 `dota_player_update_query_unit` 立即触发选中切换；0.10 秒哨兵只比较 portrait unit entindex。切换时立即关闭 Tooltip、隐藏旧项目行并透明化 Valve `abilities` 容器。
- 有界过渡：`0/0.016/0.05/0.10/0.20s` 有限重试；同单位重复事件去重，serial 取消旧切换回调。过渡中的暂时 0 技能或数量不匹配继续保持透明，最终成功原子显示项目行，最终失败恢复 Valve UI。
- 性能边界：0.5 秒低频 `geometryTick` 保留为容错；没有永久 0.03 秒完整技能扫描。0.10 秒哨兵不遍历 HUD 或技能槽。
- 定向测试：最终 `ARROW_TOWER_COMPLETION_PASS`，并覆盖事件名、有界延迟、过渡压制恢复、临时空帧和禁止高频扫描。
- Panorama 强制编译：最终 `hud_takeover.js` 为 `OK: 1 compiled, 0 failed, 0 skipped`。
- 全量回归：`.cline_tmp/selection_events_v5_final_all_tests.txt` 末尾为 `ALL_LUA_TESTS total=32 failed=0`。
- 最终产物：`panorama/scripts/custom_game/hud_takeover.vjs_c` 时间 `2026-07-29 09:25:23 +0800`，大小 60732 字节。
- 最终限定 `diff --check` 通过，无空白错误。
- 尚未验证：助手无法直接观察 Workshop Tools；切换响应速度和 Valve 原图标是否完全不再闪现需要实机确认。
- 下一步唯一动作：完全停止并重新 Run，确认 `grid52_selection_events_v5`，快速切换英雄/农民/建筑/七技能箭塔；若仍闪现，返回 `[SURVIVAL_TAKEOVER_SELECTION]` begin/end 日志与单位组合。

## 2026-07-29 — 检查点 056：确认重新 Run 丢失校准状态并批准固化正式预设

- 用户最新反馈：重新 Run 后截图中的技能行仍明显偏离，询问动态调整为什么不理想、是否需要 Panorama Debugger；随后明确批准按恢复出的最小方案执行。
- 新实机证据：当前运行参数回到了 `top_left / X=0 / Y=0`，而用户此前认为较好看的参数为 `middle_left / X=5 / Y=35`。因此当前截图不能用于评价正确参数下的五技能布局。
- 已确认根因：`hud_takeover.js` 启动默认值和 `resetCalibration()` 均硬编码 `top_left / 0 / 0`；用户调出的参数只存在于当次 `CustomUIConfig` 状态，完全重启 Workshop Tools 后会丢失。
- 实施决定：建立唯一正式预设 `middle_left / 5 / 35`；启动默认和重置共用它；增加预设版本，旧状态首次加载新版时迁移，同一 Run 内后续微调保留；日志增加预设版本和参数来源。
- 保留边界：不改现有九宫格公式和 `visualBounds`，不改 v5 事件监听、0.10 秒哨兵、有限重试、无闪压制、52×52、4px、输入与 Tooltip。
- 已排除：现在使用 Panorama Debugger 继续调查。当前已有直接源码证据证明是状态回退；只有正确预设下多技能仍异常时才评估几何模型。
- 下一步唯一动作：修改 `hud_takeover.js` 和 `test_arrow_tower_completion.lua`，随后强制编译并执行定向/全量验证。

## 2026-07-29 — 检查点 057：正式预设与版本迁移代码完成，准备强制编译

- `hud_takeover.js` 版本更新为 `grid52_preset_v6`，新增唯一 `calibrationPreset`：`version=1 / middle_left / X=5 / Y=35`。
- 初始化行为：没有旧状态时来源为 `preset_default`；旧状态没有当前版本时来源为 `preset_migration` 并迁移一次；版本一致时保留当前 Run 内状态，不重复覆盖用户微调；非法值回退来源为 `preset_recovery`。
- 交互行为：九宫格和 X/Y 微调把来源标记为 `runtime_adjustment`；“重置”调用同一 `applyCalibrationPreset()` 并标记 `preset_reset`，不再包含独立的 `top_left / 0 / 0` 硬编码。
- 诊断行为：`[SURVIVAL_ABILITY_CALIBRATION]` 新增 `preset_version` 与 `source`；`GetCalibration()` 同步返回这两个字段。
- 防回归契约：`test_arrow_tower_completion.lua` 新增 v6 build、正式值、统一重置、版本迁移和诊断来源断言；原 v5 选择事件、有界重试、0.5 秒容错、禁止 0.03 秒扫描、九宫格公式、52×52 断言全部保留。
- 快速验证：更新后的定向测试返回 `ARROW_TOWER_COMPLETION_PASS`；game/content 限定 `diff --check` 未报告空白错误。一次只读编译器路径探测因终端兼容超时，没有写入文件，将直接使用项目已知绝对路径强制编译。
- 下一步唯一动作：强制编译 `hud_takeover.js` 并核对 `1 compiled, 0 failed, 0 skipped`，再运行 32 项全量回归与最终复核。

## 2026-07-29 — 检查点 058：v6 Panorama 强制编译成功

- 使用绝对路径执行 `resourcecompiler.exe -f`，输入为 content 侧 `panorama/scripts/custom_game/hud_takeover.js`，输出为 game 侧 `panorama/scripts/custom_game/hud_takeover.vjs_c`。
- 编译结果：`OK: 1 compiled, 0 failed, 0 skipped`；更新后的版本迁移、正式预设与事件驱动代码均通过 Dota Panorama 资源编译器解析。
- 下一步唯一动作：运行 32 项全量 Lua 回归，随后核对产物元数据、最终源码和限定差异。

## 2026-07-29 — 检查点 059：正式预设修复验证完成

- 定向契约：`lua scripts/vscripts/tests/test_arrow_tower_completion.lua` 返回 `ARROW_TOWER_COMPLETION_PASS`。
- 全量回归：目录当前包含 32 个 `scripts/vscripts/tests/test_*.lua`；先完成的 31 项与补跑的 `test_addhero_cheat.lua` 均通过，`.cline_tmp/preset_v6_all_tests.txt` 末尾为 `ALL_LUA_TESTS total=32 failed=0`。
- Panorama 强制编译：`hud_takeover.js` 返回 `OK: 1 compiled, 0 failed, 0 skipped`；game 产物 `panorama/scripts/custom_game/hud_takeover.vjs_c` 已刷新，大小 61756 字节。
- 源码复核：正式预设唯一值为 `middle_left / 5 / 35`；启动迁移、运行时微调、重置和诊断来源均存在；源码中不再存在旧的 `calibration.alignment = top_left`、`offsetX = 0`、`offsetY = 0` 默认赋值。
- 差异复核：目标 game 文档/测试和 content HUD 源码的限定 `diff --check` 已通过；工作区其他既有修改未清理、未回退。
- 实机边界：助手无法直接观察 Workshop Tools；下一步只需完全停止并重新 Run，确认首条 `[SURVIVAL_ABILITY_CALIBRATION]` 为 `grid52_preset_v6`、`preset_version=1`、`source=preset_default`、`middle_left`、`5`、`35`，再比较不同技能数量。

## 2026-07-29 — 检查点 060：恢复执行模式并复核实施边界

- 用户最新要求：思考完成后转入执行模式开始编码，并已批准按恢复出的计划继续。
- 源码复核：`hud_takeover.js` 已包含 `grid52_preset_v6`、唯一正式预设 `middle_left / X=5 / Y=35`、版本迁移、统一重置、参数来源诊断和 `survival_ability_calibration_dump`；对应测试契约也已存在。
- 事实与边界：批准的编码工作在检查点 057～059 已经落地，本轮没有发现仍需补写的代码；重复修改会无意义地扩大风险，因此只追加恢复检查点并重新执行测试、强制编译和产物复核。
- 工作区状态：`docs/ai`、定向测试和 `hud_takeover.js` 存在既有未跟踪状态，相关 XML/CSS 存在既有修改；本轮不暂存、不提交、不清理、不回退。
- 尚未验证：Workshop Tools 中正确预设下 1、3、5、7 技能位置、快速切换响应和 Valve 图标闪现情况。
- 下一步唯一动作：重新运行定向与 32 项全量测试，强制编译 `hud_takeover.js`，核对产物与限定差异后等待实机验收。

## 2026-07-29 — 检查点 061：终端桥接 Shell 不一致

- 新工具事实：定向 Lua 测试已明确返回 `ARROW_TOWER_COMPLETION_PASS`；随后使用 PowerShell 语法的全量测试和资源编译请求在 30 秒处超时，预期新日志未创建，不能视为已执行或代码失败。
- 根因证据：后续命令回显为 Git Bash `MINGW64` 提示符；PowerShell 变量在嵌套调用前被错误展开，说明当前桥接会话与声明的 PowerShell 环境不一致。
- 禁止误判：不使用超时输出证明 PASS/FAIL，不原样重复写入型命令，不把旧检查点的 PASS 当成本轮新证据。
- 调整方案：改用明确的 Git Bash 可执行文件调用和 POSIX 路径；全量测试拆分为短批次，资源编译后单独核对产物。
- 下一步唯一动作：先用只读 Bash 命令确认测试清单、Lua/编译器进程和产物元数据，再执行缺失验证。

## 2026-07-29 — 检查点 062：执行模式验证完成，等待实机验收

- 定向验证：`lua scripts/vscripts/tests/test_arrow_tower_completion.lua` 返回 `ARROW_TOWER_COMPLETION_PASS`。
- 全量验证：32 个 Lua 测试拆为 4 个 8 项批次执行，`.cline_tmp/preset_v6_exec_batch1.txt` 至 `batch4.txt` 均返回 `total=8 failed=0`；合计 `32/32` 通过。
- Panorama 编译：通过独立 `powershell.exe -NoProfile` 调用资源编译器强制编译 `hud_takeover.js`，结果为 `OK: 1 compiled, 0 failed, 0 skipped`；game 产物大小 `61756` 字节，时间 `2026-07-29 11:28:24 +08:00`。
- 源码契约：v6 正式预设、版本迁移、统一重置、诊断输出、事件驱动选择切换、有界无闪重试和固定 52×52 cell 均已由源码/定向测试确认存在。
- 差异/格式：game 侧 `diff --check` 返回 0；game 定向文件和 content 三个目标文件逐文件尾随空白检查均为 0。content 仓库的 `git diff --check` 因终端桥接在 30 秒处超时，未将其误记为通过或失败。
- 工作区边界：未暂存、未提交、未清理、未回退任何既有修改；本轮只新增本检查点和测试日志，并刷新编译产物。
- 尚未验证：Workshop Tools 完全重启后的首条校准日志，以及 1、3、5、7 技能位置、不同单位切换响应和 Valve 图标闪现情况。
- 下一步唯一动作：用户完全停止 Workshop Tools 后重新 Run，执行 `survival_ability_calibration_dump`，确认 `grid52_preset_v6 / preset_version=1 / source=preset_default / middle_left / 5 / 35`，再进行实机验收。

## 2026-07-29 — 检查点 063：新任务覆盖为 Undying 建造者 Immortal 外观

- 用户最新要求：只给玩家开局的 Undying 建造者使用 `The Hallows Within Bundle`；本轮实现角色模型、环境特效和可安全恢复的姿势动画，墓碑/僵尸只记录资源。
- 已确认物品定义：Bundle `21800`；`The Hallows Within` `14963`（Head）；`The Hallows Within Tombstone` `14994`（Tombstone）。
- 关键语义：该 Bundle 不是多个身体槽组件；角色外观主要是单个大型 Head wearable。墓碑、墓碑环境特效和专属僵尸属于独立技能资产。
- 代码证据：`addon_game_mode.lua` 强制 `npc_dota_hero_undying` 并在 `initialize_survival_hero()` 发布 `HERO_READY`；现有 `hero_cosmetic_service.lua` 已支持模型 wearable，但没有开局建造者接入、粒子生命周期和重复应用清理。
- 用户批准：进入执行模式，按角色本体优先范围实施。
- 安全边界：不影响修理工、波次怪、普通僵尸、Boss 或祭坛英雄；不强行替换主体骨骼模型；不修改建造者玩法属性。
- 文档迁移：旧技能行任务已复制到 `docs/ai/archive/2026-07-29-ability-row-calibration.md`。
- 尚未确认：本机 VPK 中 defindex `14963` 的模型、粒子、attachment 和动画 modifier 精确路径。
- 下一步唯一动作：只读解析 VPK 中的 Undying 模型/粒子和物品 schema 候选，验证资源后再修改游戏运行逻辑。

## 2026-07-29 — 检查点 064：The Hallows Within 代码与资源契约完成

- 本机 VPK 取证：角色模型为 `models/items/undying/undying_fall20_immortal_head/undying_fall20_immortal_head.vmdl`；主环境粒子为 `particles/econ/items/undying/fall20_undying_head/fall20_undying_head_ambient.vpcf`。两者对应的编译资源均存在于当前 `pak01_dir.vpk`。
- 已记录但未运行：`undying_fall20_immortal_tombstone.vmdl`、`undying_fall20_immortal_minion.vmdl`、`fall20_undying_tombstone_ambient.vpcf`。
- 配置实施：`hero_cosmetics_config.lua` 增加独立 `builder_undying`，使用命名组件 `hallows_head`，主环境粒子绑定该 wearable。
- 服务实施：`hero_cosmetic_service.lua` 保持旧字符串 wearable 配置兼容；新增命名组件、项目自有 wearable/粒子状态、重复应用清理、`DestroyParticle`、`ReleaseParticleIndex`、`UTIL_Remove` 回退和 `clear()`。
- 开局接入：`addon_game_mode.lua::initialize_survival_hero()` 只在 `unit_name == SURVIVAL_FORCE_HERO` 时应用 `builder_undying`，且发生在 `HERO_READY` 前。普通 Undying 怪物不会进入该路径。
- 重生恢复：新增 `npc_spawned` 监听；只有单位名是强制 Undying 且 `ready_hero_entindex_by_player[player_id]` 等于当前 entindex 时才幂等重建，初次未初始化英雄和普通 Undying 怪物均被排除。
- 动画决策：官方页面确认 Head 饰品绑定轻微姿势调整，但没有找到可安全调用的独立 Lua 动画 modifier；不替换主体骨骼模型，不调用猜测接口，保留原版动画和 wearable 骨骼跟随。
- 新增测试：`scripts/vscripts/tests/test_hero_cosmetic_service.lua` 覆盖模型/粒子预缓存、默认 wearable 隐藏、Owner/FollowEntity、命名粒子 owner、重复应用与显式清理。
- 可执行验证：`.cline_tmp/test_hallows_within_contract.ps1` 返回 `HALLOWS_WITHIN_CONTRACT_PASS`；目标 `git diff --check` 返回 `TARGET_DIFF_CHECK_PASS`。
- 环境限制：当前 PowerShell PATH 和常见安装路径均无 `lua`、`luac`、`luajit`；WSL 探测超时。未把无法执行的 Lua 测试和语法检查伪记为通过。当前磁盘中的测试目录只有原 `test_hero_health_guard.lua` 和本轮新增测试，与历史 32 项文档环境不同。
- 尚未验证：Workshop Tools 中大型 wearable 的实际覆盖、环境粒子 attachment、移动/建造/死亡/重生动画，以及第二次 Run 是否无重复。
- 下一步唯一动作：完全停止 Workshop Tools 后重新 Run，实机验收开局建造者；如异常，返回 `[Survival][INFO][HeroCosmetic] builder_undying applied wearables=... particles=...` 日志和截图。

## 2026-07-29 — 检查点 065：用户实机确认部件饰品上线成功

- 用户原话：`部件饰品上线成功，记录成功的经验`。
- 实机确认范围：开局 Undying 建造者成功显示 `The Hallows Within` 部件饰品。
- 由实机结果直接证明：`undying_fall20_immortal_head.vmdl` 路径正确；`SpawnEntityFromTableSynchronous("prop_dynamic")` 可创建该大型 Head wearable；`SetOwner` 与 `FollowEntity(hero, true)` 能让其跟随建造者骨骼；在 `HERO_READY` 前应用的时机有效。
- 不扩大结论：用户没有在本次反馈中分别确认环境粒子、死亡/重生或第二次 Run，三项继续作为防回归检查，不写成已实机通过。
- 可复用资源定位经验：先用公开 defindex 确认 Bundle/子物品和槽位，再从本机 `pak01_dir.vpk` 按英雄目录、发布时间开发代号和模型/材质/图标/粒子交叉验证；展示名与内部目录名不同是常态。
- 可复用模型经验：商城视觉上像“全身套装”不代表存在多个身体组件。本套英雄外观实际是 Head 槽 defindex `14963` 的单个大型 wearable；墓碑 defindex `14994` 是独立技能槽资产。
- 可复用运行时经验：保留原英雄主体骨骼与动画，以项目创建的 `prop_dynamic` 做 bone merge；不要用 `SetModel` 把英雄主体直接换成 wearable，也不要猜测官方 econ 动画 modifier。
- 可复用生命周期经验：项目创建的 wearable/粒子必须按 hero entindex 保存；重复应用先清理项目自有实体和粒子；重生恢复必须同时校验强制英雄单位名、玩家 ID 和已初始化 entindex，避免影响外形相同的怪物。
- 可复用粒子经验：粒子配置应通过命名 `owner` 绑定到对应 wearable，而不是一律绑定英雄原点；主粒子负责引用子粒子，运行时只需预缓存和创建已确认的入口 `.vpcf`。
- 任务状态：角色部件饰品主目标完成并实机验收成功；任务归档到 `docs/ai/archive/2026-07-29-undying-hallows-within.md`。
- 下一步唯一动作：等待用户新任务。
