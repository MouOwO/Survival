# Known Issues

## 当前已知问题

0. **Modifier承伤参数中的`damage_category`可能误报真实远程平A。**
   - 2026-08-03实机表现：伐木工远程攻击树会触发木材绿字并增加木材，证明`OnAttackLanded`正常，但树生命完全不减少。
   - 根因是`modifier_tree_progression`曾用`MODIFIER_PROPERTY_INCOMING_DAMAGE_PERCENTAGE`的`params.damage_category`再次分类伤害；该字段可能为`0`或其他非权威值，导致真实平A被返回`-100%`清零。
   - 第一轮误判：曾认为全局DamageFilter始终提供`damage_category_const`，但该保证只存在于项目Mock，不存在于实机接口；移除Modifier分类后实机仍不掉血，证明DamageFilter对缺失类别继续失败关闭。
   - 修复原则：明确类别按`DOTA_DAMAGE_CATEGORY_ATTACK`判断；缺失/0类别使用树Modifier在`ON_ATTACK_START`登记的一次性真实攻击凭证。不能只靠inflictor为空，也不得用`ApplyDamage`补伤害掩盖根因。`TREE_DAMAGE_FILTER`限次日志用于输出实际类别、inflictor、凭证与无敌状态。

0. **提交新增`require`时可能遗漏对应新模块文件。**
   - 2026-08-03提交`85ce4eb`在`building_upgrade_system.lua`新增`require("systems/building_upgrade_process")`及四个接口调用，但Git历史和工作区均没有对应文件，导致地图在`addon_game_mode.lua`加载阶段立即终止。
   - 排查真实`module not found`时应同时执行`git ls-files`、Git历史对象搜索和全项目require解析；不能只注释require绕过业务流程。当前缺失模块已补齐并有Lua 5.1行为测试。
   - 防复发检查：新增静态`require`后，必须确认目标文件出现在`git status --short`或`git ls-files`中，并对“目标模块、直接调用方、`addon_game_mode.lua`”执行Lua 5.1语法检查。动态拼接模块名不能由简单正则完整验证，必须单独核对配置来源。

0. **Lua 5.1会把被require模块的编译失败同时显示为`module not found`。**
   - 2026-08-03实际表现为`module 'systems/hero_passive_skill_service' not found`，同一条搜索诊断后紧跟真实原因`main function has more than 200 local variables`。
   - 根因是主服务顶层chunk拥有202个local；已将三个末尾入口挂到模块表，使声明数降至199并通过`luac5.1 -p`。排查同类问题必须优先阅读`module not found`后附带的目标文件编译错误。
   - 结论：文件存在只能排除“真实缺失”，不能证明模块可加载；必须继续检查Lua 5.1语法、顶层local数量、BOM/非法字节和目标模块的传递依赖。

0. **`SESSION_LOG.md`历史内容已有3个`U+FFFD`替换字符。**
   - 2026-08-02严格UTF-8检查确认整份文件可以正常解码，但本次四英雄验收记录之前的历史区域已有3个Unicode替换字符；本次新增经验段落不含乱码。
   - 不得通过另存编码或整文件转码掩盖损坏，也不得猜测原文。未来若要修复，必须从可信历史副本恢复对应文本，并单独验证差异。

0. **Valve完整Invoker Tornado粒子不能作为Lua逐帧追踪视觉。**
   - `particles/units/heroes/hero_invoker/invoker_tornado.vpcf`会按创建时控制点在内部自行直线推进；后续更新CP0/CP1不能可靠重定位已经发射的内部粒子。
   - 实机会表现为Lua伤害中心继续运行、状态测试通过，但画面龙卷仍沿初始直线飞走。
   - `proto_void_pulse`现使用项目粒子`particles/survival_tornado/survival_tornado_follow.vpcf`，只承载`invoker_tornado_child.vpcf`且没有移动算子；位置完全由Lua更新CP0。
   - 修改该粒子后必须用Resource Compiler强制编译到game目录，并完全重启Workshop Tools Run；热加载Lua不能替换已经预缓存的粒子资源。

1. **`build_configs.bat` 当前可能因 Windows Python 别名挂起。**
   - 当前 PATH 首个 `python.exe` 是 `C:\Users\li\AppData\Local\Microsoft\WindowsApps\python.exe`，执行 `python --version` 无输出。
   - 可用解释器是 Python Launcher：`py -V` 返回 Python 3.13.14。
   - 本次已使用 `py` 调用 `tools.build_configs.build()` 定向生成所有相关 Lua，并确认生成内容正确。
   - 建议后续把 `build_configs.bat` 的解释器改为 `py -3`，或修正 PATH 后再运行完整构建。
2. **完整 `build_configs.bat` 曾返回 `CONFIG_BUILD_FAILED`。**
   - 目标 CSV 对应的生成 Lua 已正确生成并通过定向 `build()` 校验。
   - 失败与全局 Tooltip 前置生成/当前工作区大量既有修改有关，不能把该失败误判为挑战 07 配置无效。
   - 后续仍应在干净环境中运行完整生成器并确认 `CONFIG_BUILD_PASS`。

3. **工作区存在大量本任务之外的修改和未跟踪文件。**
   - 禁止为了本任务执行全局 reset/checkout。
   - 只修改明确相关文件，验证时使用限定路径。

4. **代码搜索索引不完整。**
   - `search_codebase` 对部分 `scripts/vscripts` 文件无结果；已知文件优先使用 `read_files`，必要时使用限定目录的命令搜索。

5. **`building_definitions.csv` 当前存在编码及源表/生成表不一致风险。**
   - 源 CSV 的中文名称和备注当前显示为乱码字节，继续直接保存或全量生成可能污染本地化文本。
   - 源 CSV 中 `building_farm.max_count` 当前为 `1`，但生成的 `building_definitions.lua` 仍为 `0`；运行时按生成配置读取，因此农场当前仍是无限制。
   - 箭塔不存在该不一致：源 CSV 和生成 Lua 都是 `max_count=7`，运行时现已正确采用。
   - 后续应先用 UTF-8 正确恢复 CSV 中文内容，再运行配置生成器并校验所有建筑行。

6. **Panorama 辅助校验工具和编译输出存在环境差异。**
   - 当前终端 PATH 中没有 `node`，执行 `node --check` 会提示命令不存在；可依赖 Dota `resourcecompiler.exe` 的实际编译结果校验 Panorama JS。
   - 不带 `-f` 的资源编译可能报告 `0 compiled, 1 skipped`，即使产物时间戳发生变化也容易造成判断歧义；后续定向修改应使用 `-f` 并确认 `1 compiled, 0 failed, 0 skipped`。

7. **终端桥接偶尔会回显旧终端内容或出现输出捕获超时。**
   - 不能把回显中的旧 PASS 当作当前命令成功证据。
   - 最终结论应优先依据当前命令退出状态、明确的测试 PASS、`ALL_LUA_TESTS total=... failed=0`、资源编译器汇总和源码复核。

8. **PowerShell 命令若从 `-NoProfile` 开始会被当作不存在的命令。**
   - 正确外部调用为 `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "...\build_configs.ps1"`。
   - 该报错属于命令行入口错误，不是表格内容错误。

9. **Tooltip 重构期间存在 Valve HUD 节点重建兼容风险。**
   - `AbilityN` 和物品槽会在选中单位变化或 HUD 重载时被 Valve 复用/重建。
   - 新实现应优先使用状态变化触发重新绑定，并保留低频按需恢复；不能依赖一次绑定永久有效，也不能恢复高频全树扫描。
   - 角色属性详细 Tooltip 已删除；只需验证官方攻击/护甲/攻速节点关闭命中后仍正常显示权威数值。

10. **技能代理层和背包气泡仍需要 Workshop Tools 实机验证。**
   - `SurvivalAbilityTakeoverLayer` 根据官方锚点的窗口坐标与 UI scale 定位；编译成功不能证明所有分辨率、HUD 比例和选择单位类型都无偏移。
   - 必须验证英雄、建筑、农民、选择切换、窗口缩放和第二次 Run；若偏移，需要同时截图代理节点与对应官方锚点，不能凭肉眼猜固定像素。
   - 普通非托管技能已交给 `Abilities.ExecuteAbility`；单位目标、点目标、切换和自动施法的实际输入状态仍需逐类实机确认。
   - 官方背包操作明确未接管，但项目气泡已绑定其悬停；任何使用、拖放、换位、丢弃、出售或原生物品 Tooltip 回归都应视为阻断问题。

11. **聊天界面关闭会丢失尚未落盘的研究上下文。**
   - 当前系统无法恢复已关闭界面的聊天原文，也不能依赖跨会话记忆。
   - 既有总结文档只能恢复已经写入的结论，不能恢复尚未记录的候选方案、证据和用户最新要求。
   - 后续必须遵守 `START_HERE.md` 的检查点协议；若发生断开，从 `SESSION_LOG.md` 最后一个检查点继续，禁止凭旧任务摘要猜测。

12. **`docs/ai` 当前整体未被 Git 跟踪。**
   - 文档已经写入本地磁盘，因此普通聊天界面关闭后仍可恢复。
   - 但 `git clean`、手动清理未跟踪文件或工作目录损坏仍可能删除这些记录。
   - 未经用户明确要求不得擅自暂存或提交；后续应由用户决定是否将 `docs/ai` 纳入版本控制或单独备份。

13. **Valve 技能节点 ID 在能力动态增删后不保证连续或等于视觉顺序。**
   - 箭塔 5 级会删除升级技能并动态追加七个转职技能，实机已出现项目 `Q/W/T` 与剩余官方按钮共存。
   - 技能接管不得再把稠密显示序号直接拼成 `AbilityN`；必须枚举有效官方按钮、按屏幕视觉位置排序，并在完整映射后原子提交。
   - 映射不完整时必须整批恢复官方 UI，禁止保留半项目、半官方状态。

16. **Lua 5.1 工具必须使用当前已验证的绝对路径。**
    - 2026-08-03已确认`C:\Program Files\lua\bin\lua5.1.exe`与`C:\Program Files\lua\bin\luac5.1.exe`均为Lua 5.1.5；旧`C:\msys64\mingw64\bin`路径仍为失效历史路径。
    - 当前终端PATH尚未包含Lua 5.1目录，自动验证必须使用上述绝对路径，不能因`Get-Command luac5.1`无结果而误判编译器不存在。
    - PowerShell 7当前路径为`C:\Program Files\PowerShell\7\pwsh.exe`，版本7.6.4；Windows PowerShell 5.1仍位于系统默认路径。
    - 当前有7个历史Lua源文件带UTF-8 BOM，PUC Lua 5.1会在第1字节拒绝；`tools/test_lua51_syntax.ps1`只对临时副本移除BOM再检查，不修改生产源文件，并在结果中报告`bom_normalized`数量。
    - Luac只能证明对应版本语法可解析，不能替代Dota API、Scheduler、粒子、伤害和UI的Workshop Tools实机验证。

17. **召唤英雄的攻击射程写入与读取接口不对称。**
    - `hero_stat_adapter.lua`使用`Script_SetAttackRange(attack_range)`应用英雄CSV配置，但实机确认同一单位的`GetAttackRange()`可能返回0；英雄仍能正常普通攻击，因此0不是权威实际射程。
    - 依赖攻击射程的功能不得只调用`GetAttackRange()`；魔法弹弓当前依次兼容`survival_attack_range`、`Script_GetAttackRange()`、`GetAttackRange()`和`hero_definitions.attack_range`，取最大有效值。
    - 设置配置射程时必须同步保存`unit.survival_attack_range`。即使全部射程来源异常为0，本次已经合法命中的敌方主目标也不得被目标查询提前丢弃。
    - 该问题曾表现为`MAGIC_SLINGSHOT_ROLL success=true`后紧跟`reason=no_targets range=0 primary=<entindex>`；修复后实机为`range=3000 selected=1 launched=1`。

14. **项目技能 cell 曾继承 Valve 动态按钮尺寸，第一版固定尺寸仍偏大。**
   - 实机确认 1～2 个技能时图标较大、7 个技能时图标较小。
   - 根因是 `applyOfficialGeometry()` 把官方锚点的动态 `geometry.width/height` 直接赋给项目按钮。
   - 65×65 在当前 UI scale 下约显示为 72×72，实机已判定明显偏大；源码与编译产物现已修正为固定 52×52。
   - 最新实机已确认 1 个与多个技能的图标大小相同；剩余高度差来自固定行仍跟随 Valve 内部按钮底边。
   - 源码现改为使用官方 `abilities` 容器左上角作为固定行原点，内部按钮只用于视觉顺序、完整映射和压制；仍需完全重启后确认 1、2、7 个技能的左边和顶边一致。

15. **专属真实地面物品的 Valve 世界 Tooltip 因本地化文件未进入标准加载路径而为空。**
   - 最新实机只显示图标和“技能：被动”，没有标题与说明；此前自动测试不能作为视觉修复证据。
   - 自动测试已确认六个 CSV 映射、KV 注册、中英文 token 完整，且挑战 05/07/08/09 的 `requested_item` 与 `actual_item` 一致。
   - 最新日志已确认六种材料 token 全部原样返回 `#token`；根目录 `resource/addon_english.txt` 仍是模板且缺少 `resource/addon_schinese.txt`，完整文本误放在 `resource/localization/`。
   - 游戏根目录与 Panorama 标准本地化入口现已同步完整中英文 token；用户最新实机已确认地面 Tooltip 成功。
   - 禁止虚构运行时 `SetDisplayName`、`SetDescription` 或 `SetTooltipIcon` 接口；Lua 实例字段不是官方 Tooltip 元数据。

## 已解决但需要防回归的问题

1. 首次成功合成后 pending 锁未释放，第二次合成不再扫描。
2. 召唤英雄 owner 为 -1，挑战材料无法认领。
3. 通过改变英雄选择模型修 owner 时导致建筑和农民不可选择；该方案已判定失败，不可恢复。
4. 合成宝石拾取即消失；现在应在背包显示，仅合成成功后消耗。
5. Dota 原生 Tooltip 显示 `#dota...` 或旧气泡；项目已有自定义 Tooltip/本地化改动，后续调整需避免退回原生气泡。
6. `GetIntellect` 参数数量错误导致 `hero.main_attack_landed` handler 报错。
7. challenge 08 旧配置奖励为 `item_molten_upgrade_gem_04`，且没有进入 Boss 地面材料流程；现已改为掉落 `material_molten_core_04`。
8. 最终配方虽存在但仍标记为推断；现已正式确认并验证 `狱火熔铠Lv4 + 熔火核心Lv4 → 狱火熔铠Lvmax`。
9. 防御塔升级资源足够后仍保持置灰；现已修正真实资源判断、人口奖励语义和客户端可见能力槽位映射。
10. Workshop Tools 第二次 Run 后 Q/W/E/R/T/Y/U 快捷键失效；现已让每次 HUD 上下文生成独立命令并重新接管按键分发器。
11. 建筑技能可能出现 Q 有效但原生按钮鼠标点击无效果；现已为托管建筑操作增加透明按钮代理，并统一转发至自定义服务端请求。
12. `can_afford` 状态延迟曾让实际资源足够时客户端直接丢弃点击；现只将其用于提示，服务端权威扣费仍拒绝真实资源不足且不会产生扣费副作用。
13. 箭塔完工时曾直接索引不存在的 `definition.levels`，导致施工任务在技能重新激活和 `BUILDING_CREATED` 发布前终止；现已兼容 `pre_class_levels`，并将技能激活前移。
14. 战斗属性 UI 曾直接显示 Dota 底层护甲，配置护甲 `10` 会显示为约 `3.33`；现已统一在 UI 边界转换回 War3 显示单位。
15. 装备护甲曾把 War3 显示值直接作为 Dota Modifier 护甲；现已在写入引擎时除以 3，并由 UI 投影恢复显示值。
16. 齐天大圣 CSV 基础攻击 `1000` 曾因 `damage_multiplier=1.15` 在面板显示为 `1150`；现面板保持 `1000`，原生普通攻击仍保留 `1150` 的既有实战投影。
17. 英雄攻速曾依赖 `GetSecondsPerAttack()` 的当前帧结果；现已改为配置驱动并覆盖装备攻速百分比。
18. 建筑最大数量曾在 `buildings_config.lua` 中重复硬编码，导致箭塔生成配置 `max_count=7` 被运行时 `0` 覆盖为无限制；现已统一读取生成配置，并增加全队上限回归测试。
19. 英雄面板的权威攻速与护甲数值曾比期望位置低 6px；现已在 `combat_stats.js` 的共享二级属性定位函数中由 `+3px` 调整为 `-3px`，并强制重新编译 `combat_stats.vjs_c`。
20. 技能/物品 Tooltip 曾使用永久 `1.0s` 绑定扫描、`0.35s` 可见重绘和物品悬停 `0.03s` 原生压制；现已改为有限绑定恢复与 NetTable/事件驱动刷新。
21. 项目技能/物品曾统一采用“原生基础层 + 项目扩展层”；当前技能与背包气泡均由项目表现层控制，角色属性详细 Tooltip 已取消。
22. Tooltip 重构自动验证曾因终端桥接超时而缺少输出；最新已获得 `ALL_LUA_TESTS total=30 failed=0`、Lua 语法检查成功和资源编译器零失败汇总。
23. 技能/属性接管试点曾多次因接口请求中断；现已通过 `SESSION_LOG.md` 检查点 008～014 恢复并完成，后续不得回退到中断前的半成品判断。
24. 第一座箭塔 5 级转职技能曾在延迟资源刷新后置灰；根因是 Runtime 重发陈旧单位缓存。现已在发布前与箭塔实体权威等级/路线对账，并加入两塔隔离回归测试；仍需 Workshop Tools 实机确认。
25. 角色属性详细 Tooltip 已按用户要求删除；后续不得因旧文档恢复 `hero_stat_tooltip.js`、`SurvivalStatTakeoverLayer` 或 `CustomHeroStatTooltip`。权威数字显示链必须继续保留。
26. 背包项目气泡现直接绑定官方槽及其 ItemImage 的悬停事件，但不改变命中和操作事件；不同 Valve HUD 版本中仍需实机确认原生物品 Tooltip 被完全压制且拖放不回归。
27. 挑战材料已改为专属真实地面物品，自动测试确认映射、Claim、合并和防复制边界；最新实机已确认 Valve 世界物品 Tooltip 的名称/说明仍为空，因此 Tooltip 视觉问题重新列为当前未解决项。鼠标命中、装备栏满时回落，以及“已有材料丢下再捡不复制”也仍需完全重启后实机确认。
28. Git Bash 终端桥接可能在清空 `.cline_tmp` 日志时报告 `Device or resource busy`，但后续测试循环仍会执行；最终结论必须以新日志中的逐项记录和末尾 `ALL_LUA_TESTS total=... failed=0` 为准，不要仅看开头重定向警告。
29. `The Hallows Within` 大型 Head wearable 已由用户实机确认上线成功；后续不得回退为主体 `SetModel` 替换，也不得把该物品误拆成不存在的多身体槽组件。环境粒子、死亡/重生和第二次 Run 尚未被用户分别确认，继续作为防回归验收项。

## 2026-08-02 原生召唤英雄基础生命Setter会被引擎覆盖

- 可复现表现：普通召唤英雄CSV目标生命为3000，即使Lua依次调用`SetBaseMaxHealth(3000)`、`SetMaxHealth(3000)`、`SetHealth(3000)`，Workshop Tools实机最终仍显示原生120生命。
- 静态测试和Lua Mock只能证明调用顺序，不能证明Dota原生英雄初始化后会保留Setter结果；此前自动测试通过但实机失败，后续不得将Mock描述为引擎验证。
- 已采用的规避方案：使用`MODIFIER_PROPERTY_HEALTH_BONUS`隐藏永久Modifier补足到CSV目标，因为现有真实装备生命加成已由实机证明有效。
- 已解决：隐藏永久Modifier第二版已由用户在Workshop Tools中确认英雄血量正常。后续防回归时查看`[HERO_CONFIGURED_HEALTH]`中的`configured/native/bonus/engine_max/engine_current`，不得恢复直接Setter方案。
