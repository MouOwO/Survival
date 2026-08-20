# AI Session Recovery - Start Here

> 这是新会话的唯一恢复入口。当前只恢复多人联机工程；旧任务全部暂停并已归档。

## 最新任务检查点（2026-08-20）

- 玩家数据库字段链路已新增 `online_seconds_total`：CSV、生成 Lua、Python 初始化、Supabase schema/RPC、Lua 档案补字段和心跳累计契约均已更新。
- 自动验证通过：Python 16 项单元测试、在线时长模拟边界、`GAMEPLAY_STATS_CONTRACT_PASS`、`PLAYER_PROFILE_CONTRACT_PASS`、Lua 5.1 档案行为、目标 `luac5.1`、严格 UTF-8、CSV/生成 Lua 一致和限定 `diff --check`。
- 真实 Supabase 与本机 Python API 已于 2026-08-20 联调通过：Automation 9001 启动同步定义成功，`/v1/profile` 返回 36 个 CSV 字段；首次心跳累计 0、同 session 租约内约 2 秒累计 2、重复 `request_id` 不重复累计、活跃租约拒绝新 session、超租约新 session 不累计离线间隔，最终 profile/revision 一致且公开数据不含 `gameplay_stats`。测试进程已停止，Workshop Tools HTTP Provider 实机联调仍待执行。

## 当前任务

- 当前插入任务（2026-08-20，高级伐木工“效率”综合采集量加成自动验证完成）：`ability_lumberjack_personality_efficiency`已从攻击间隔减少30%改为当前综合采集量增加30%。基础、树等级、科技和固定加成先汇总，按伐木工实体累计小数余数后发放整数木材，暴击/10倍倍率保持后置；CSV、生成Lua、统一Tooltip和六份本地化已同步。专项Lua 5.1行为/契约、伐木工融合契约、语法、生成一致、严格UTF-8和限定diff通过；下一步Workshop Tools冷启动验收实际产量、浮字和Tooltip。
- 当前插入任务（2026-08-19，练功房怪物碰撞 profile 自动验证完成）：正式地面波次怪继续使用CSV权威Hull 32；四个练功房成员由`encounter_members.csv.collision_profile=practice`显式归类，使用独立CSV规则Hull 12并保留单位间碰撞。练功房创建时关闭默认clear-space，先应用12 Hull再显式`FindClearSpaceForUnit()`，其他挑战成员保持原放置时序。专项契约、Lua 5.1行为/语法、18列CSV schema、定向生成逐字节一致、严格UTF-8和限定diff通过；下一步Workshop Tools冷启动分别观察正式波次与四个练功房的初始站位和移动拥挤，自动验证不等于引擎实机验收。
- 当前复核任务（2026-08-19，英雄永久异步预载与召唤READY门禁）：生产实现已存在且本轮重新核对通过；六英雄bundle、代理KV、饰品/常驻粒子、渐进加载和按玩家generation召唤门禁一致，目标契约、Lua 5.1语法、目标生成一致、严格UTF-8与限定diff通过。全量配置CheckOnly仍受无关既有`rogue_reward_effects.lua`替换字符阻断。下一步完全Stop并冷启动Workshop Tools，记录六bundle READY时序、帧尖峰/显存，测试两玩家同英雄并发、加载中改选、失败重试和六英雄最终外观；未经实机不得称为完成。
- 当前修复进度（2026-08-19，英雄bundle资源完成门禁）：已补齐Doom 7项、Shadow Fiend 1项、Axe 5项ReplaceHero原生穿戴预载依赖，并让bundle READY覆盖CSV主体/附件/粒子/声音资源请求后再等待代理回调；当前VPK索引21个目标模型全部存在。专项Lua 5.1、契约、生成一致、严格UTF-8、VPK索引和限定diff通过。下一步完全Stop并冷启动Workshop Tools，分别观察三英雄替换时序、模型告警和Axe `Hero_Axe.Footsteps.Automaton`音效告警；未经实机不得称为完成。
- 当前生命周期修正（2026-08-19）：英雄bundle静态资源已改为在地图`Precache(context)`有效上下文注册，运行期不再调用`PrecacheResource(..., nil)`；bundle仍只在精确代理异步回调后READY，启动注册失败会FAILED且不启动代理。专项行为、契约、Lua 5.1语法、严格UTF-8与限定diff通过；下一步Workshop Tools完全Stop后冷启动验证Doom、Shadow Fiend、Axe及多人客户端时序。
- 已完成资源依赖修复（2026-08-20用户实机验收）：Shadow Fiend新增3项、Drow Ranger新增7项ReplaceHero原生穿戴模型，已同步权威CSV、生成Lua、代理KV和专项契约/行为测试；用户确认两名英雄模型成功加载。后续新增英雄默认穿戴时，复用CSV登记、生成配置、代理KV `precache`、只预载不重复挂载、精确代理回调后READY的完整流程。
- 当前插入任务（2026-08-18，伐木工点击融合完成自动验证）：普通LV1五合一、LV2-LV8三合一生成对应超级伐木工；独立CSV管理8级配方和11项性格，LV1-LV7每次从11项性格池等概率随机抽取1项且允许重复，LV8无技能。服务端同玩家/同队/同级预校验、施法者等级匹配、pending锁、目标先建后原子提交、净人口释放及失败无副作用已接入；规则/事务/生产注册投影Lua 5.1、契约、语法、CSV生成一致、UTF-8和限定diff通过。下一步Workshop Tools冷启动逐级验收，未经实机确认不得记录完成。
- 本次Tooltip增量已接入同一任务：两份伐木工CSV生成的8条融合/11条性格Ability定义现在进入`survival_ability_data`，静态统一Tooltip与原有英雄/防御塔/专用Ability配置保持明确覆盖顺序；专项契约覆盖数量、LV8空技能、key去重和CSV/Lua/runtime投影。下一步仍为Workshop Tools冷启动后悬停动态融合与性格技能。

- 当前插入任务（2026-08-17，肉鸽奖励 UI、通用效果运行时与指定三卡调试入口完成自动验证）：四张权威 CSV 已覆盖 31 张卡、31 个效果、38 个强类型参数和 21 条生命周期规则；服务端 offer/token/队列、Panorama 独立 overlay、Boss 全有效玩家发放及 `rogue <card_id1> <card_id2> <card_id3>`正式运行时调试链已接入。当前只启用 `fiscal_subsidy`、`radiant_sapling`、`fortifications`，尚未 Workshop Tools 冷启动或双客户端验收。后续开发先读 `ROGUE_REWARD_INTEGRATION.md`，实机基线命令为 `rogue fiscal_subsidy radiant_sapling fortifications`。
- 当前插入任务（2026-08-17，持久化在线计时钓鱼奖励纵向切片自动验证完成）：已实现CSV权威定义、Supabase单事务grant/永久聚合/冻结计时/幂等migration、Python 3.14 loopback鉴权API、Steam Account ID Lua HTTP Provider、在线session租约和永久效果独立投影。生产奖励因完整清单缺失及三条定义待复核而全部禁用并失败关闭；本机无PostgreSQL/Supabase CLI且未提供项目凭据，尚未执行远端migration或Workshop Tools实机。详细阻断、测试与启动步骤见`CURRENT_TASK.md`顶部和`FISHING_REWARD_INTEGRATION.md`。
- 当前插入任务（2026-08-15，Builder动态管理域与全链路安全枚举完成自动验证）：Builder服务端仅枚举`0..GetAbilityCount()-1`，保留index 0等非管理Ability，并以动态起点连续维护六个CSV业务槽与尾随Blink；快捷键仍由`builder_slot_order`投影`Q/W/E/R/T/A`和名称映射`D`。四份Panorama实体Ability访问统一消费runtime `ability_count`，固定24/64仅保留为HUD节点枚举。专项行为/契约、研究与Grid回归、Lua 5.1语法、CSV生成一致、双仓限定检查和四份JS强制编译通过；下一步冷启动短测高级研究所和农场并确认无`invalid index`或布局重建失败。
- 当前插入任务（2026-08-15，Ability runtime重建与安全枚举完成自动验证）：已恢复`upgrade_level(..., display)`及默认空表；服务端通过`survival_ability_runtime`的`unit:<entindex>`发布真实`GetAbilityCount()`并在销毁时清理，两份Panorama仅按该元数据访问实体Ability，不再固定探测无效索引。高级研究所十槽HUD几何外推保持不变。专项Lua 5.1、契约、研究回归、语法、UTF-8、限定diff和两份JS强制编译均通过；下一步冷启动Workshop Tools确认runtime重建、主城Tooltip及控制台无`8..17`索引告警。
- 当前插入任务（2026-08-15，研究所十槽Tooltip代理几何与图标修复完成自动验证）：普通/高级研究所代理按运行时权威签名枚举六/十槽；Valve仅提供部分按钮锚点时，第七至第十槽由最后两个真实按钮的水平步距外推为窗口矩形，透明代理继续负责自定义Tooltip及项目左键输入。ARS-01/Q图标已在权威CSV、生成Lua和Ability KV统一为`furion_force_of_nature`。专项契约、三项Lua 5.1行为、输入生命周期、目标Lua语法、CSV生成逐字节一致、严格UTF-8、限定diff及`ability_tooltip.js`强制编译通过；下一步冷启动Workshop Tools验收十槽实际几何、Tooltip、左右键和链式替换。
- 已完成任务（2026-08-15，研究所Grid全红与无法建造）：用户已明确确认问题解决并通过实机验收。最终根因是普通研究所曾被误配`requires_building_id = "building_research_lab"`自前置，导致业务校验固定拒绝并把四格全部标红；运行配置现统一从CSV生成`builder_ability_stages.lua`投影建筑前置，普通研究所无前置，高级研究所和挑战建筑仍要求已完工普通研究所。专用预览代理继续保留，相关Lua 5.1、契约、CSV生成一致、语法、UTF-8和限定检查均通过；本问题不得再恢复为待Workshop Tools验收项。
- 历史中间结论（2026-08-15，已被后续根因覆盖）：真实静态建筑预览即使使用0 Hull仍不能解决研究所固定全红，因此引入了专用地面移动型`npc_survival_grid_preview_proxy`。该代理仍是当前预览架构的一部分，但最终解除建造阻断的是上方CSV前置投影修复，不得重新把Hull判断当作本问题最终根因。
- 当前最高优先级（2026-08-15，Builder整排置灰与Grid回归已修复并完成自动验证）：除Tooltip代理曾误回退Valve原生点目标外，完整布局重建还会在真实引擎未即时接受`SetAbilityIndex()`时提前返回，使新建城墙与Blink停留0级/未激活并整排置灰。现在`ability_build_*`仍无条件进入项目输入，且每个重建Ability在严格槽位验证前立即写入Lv.1、可见和阶段激活；槽位失败不再留下灰按钮，后续同步可自愈。相关契约/Lua 5.1/语法/CSV一致/UTF-8/限定diff及上一轮`ability_tooltip.js`强制编译通过。下一步必须完全Stop并重新Run Workshop Tools，先确认按钮不灰、Q城墙Grid和一次完整建造，再复测后续建筑。
- 当前插入任务（2026-08-15，Builder Ability同步纠正完成自动验证）：六个CSV业务槽连续占用engine index`0..5`并显示`Q/W/E/R/T/A`，Blink固定index 6并按名称显示/输入`D`。服务端会保留正确布局实体，异常布局清理重复/过期技能并按权威顺序重建、按名称恢复剩余冷却；Panorama保留Valve按钮，只显示项目快捷键和托管技能自定义Tooltip。专项Lua 5.1/契约、生成一致性、严格UTF-8、限定diff及3份Panorama JS编译通过。下一步完全冷启动Workshop Tools验收七个槽位、输入、冷却和单Tooltip，详见`CURRENT_TASK.md`顶部。
- 已完成任务（2026-08-14，挑战怪零碰撞、挑战建筑统一视觉与自动Toggle）：五种挑战怪在专属生成边界固定0 Hull并启用无单位碰撞；挑战建筑保持2x2占地，完工与施工统一为`radiant_ancient001.vmdl / 0.34`且复用公共施工服务；自动Toggle已补齐Panorama托管、行为位放行、服务端直达分发和`OnToggle`重入保护。挑战专项、正式波次碰撞/顺序回归、Lua 5.1、CSV生成、JS编译、UTF-8和限定diff均通过。用户已明确表示任务完成，不再恢复为待验收项；复发排查顺序见`PROJECT_CONTEXT.md`顶部。
- 当前插入任务（2026-08-15，研究科技原生按钮与Tooltip调整完成自动验证）：普通/高级研究所现在固定使用Valve原生Ability按钮视觉，项目52px接管对研究所无条件关闭；独立透明代理继续屏蔽Valve原生Tooltip、显示CSV驱动的项目科技Tooltip并处理左键研究和高级研究所右键窗口。标题读取`research_lab_abilities.csv.display_name`，当前科技等级单独显示，“施法类型/科技编号”已移除；原生按钮角标同步固定`QWERTASDFG`。Lua 5.1、契约、生成一致性、严格UTF-8、限定diff和四份Panorama资源编译通过，下一步冷启动Workshop Tools验收，详见`CURRENT_TASK.md`顶部。
- 当前插入任务（2026-08-15，研究所科技最终分组与单行技能栏完成自动验证）：普通研究所现固定六槽`Q/W/E/R/T/A`，速度/塔/墙三链满10级同槽切换高级科技，其余三项固定槽；未解锁和满级均保留置灰。高级研究所固定十槽`Q/W/E/R/T/A/S/D/F/G`并改用52px单行技能栏，金矿科技排除。科技等级、费用、前置、转生和效果统一消费`technology_definitions.csv`生成配置；高级塔/墙前置修为10，英雄三项修为3转。专项Lua 5.1/契约、生成一致、UTF-8、资源编译和限定检查完成；下一步完全冷启动Workshop Tools验收，详见`CURRENT_TASK.md`顶部。
- 前一研究所建造阻断修复已由上方最终分组方案接续；其中“五链、满级移除、两行布局”记录已废止，不得作为当前实现恢复。Builder W完工后替换、高级研究所模型/缩放/占地、2秒事务、来源验证和自动研究仍保留。
- 当前插入任务（2026-08-14，神秘塔LV4攻击W10 Boss高甲公式修复完成自动验证）：当前Dota护甲曲线已确认为`1 - 0.06A/(1+0.06|A|)`；War3护甲按`A=W/3`投影后，正甲原生结算天然等于`1/(1+0.02W)`，怪物普通物理补偿应为1。权威计算器规则CSV已改为`0.06/1/0.06`，`armor_balance.lua`改为消费生成规则，生成Lua和单文件HTML已重建；117/477/4990护甲、W10 60000生命与神秘塔LV4 3801攻击/1秒普攻/1.6起始激光回归通过，离散模拟`t=44`达到60044.259962。专项契约/Lua 5.1、计算器Edge双视口62项、激光、研究减甲、毒云、塔射程、超级塔科技、语法、生成一致、UTF-8及限定diff检查通过；下一步完全冷启动Workshop Tools，以单座LV4神秘之塔实测W10 Boss约45～46秒，自动模拟不能替代引擎实机验证。
- 已完成任务（2026-08-14，神秘塔激光1秒Tick及计算器方法）：用户确认问题已解决。此前权威`tower_skill_definitions.csv`的`laser_lv01-lv05`已统一恢复1秒，生成配置、Tooltip、本地化和专项测试已同步；计算器的CSV数据边界、护甲公式、离散事件时间轴、暴击期望、成长、激光重置、击杀层和路径附伤方法已沉淀到`PROJECT_CONTEXT.md`/`DECISIONS.md`，后续数值复算直接复用。不要再把该问题列为待Workshop Tools验收。
- 当前插入任务（2026-08-13，神秘塔升级崩溃最小修复待实机确认）：两份当前minidump均为`particles.dll`近同偏移空读，升级完成边界的施工传送粒子原使用`DestroyParticle(id, false)`后立即释放。`building_upgrade_process.lua`现对完成、取消、reset、实体失效和创建失败统一先清空状态，再`DestroyParticle(id, true)`并独立尝试一次`ReleaseParticleIndex`；临时启用最多64条`BuildingUpgradeParticle`生命周期日志。专项契约/Lua 5.1、相关建筑回归、语法、CSV字段生成一致、UTF-8和限定diff已通过；下一步必须冷启动Workshop Tools测试神秘塔转职，自动测试不能证明native崩溃已消失。
- 当前插入任务（2026-08-13，激光基础倍率同步与自动验证完成）：生产激光基础倍率已按`laser_lv01-lv05=1.0/1.2/1.4/1.6/1.8`同步到权威技能CSV、生成技能配置、Tooltip、六份本地化和离线War3计算器；魔能炮与魔能之眼继续继承`laser_lv05=1.8`。生产运行时算法、路线映射和连续命中增长/500%封顶/切换重置规则未改。专项契约、Lua 5.1、计算器Edge双视口59项断言、生成CheckOnly、UTF-8、PowerShell/Python语法及限定diff已通过；尚需Workshop Tools冷启动确认实际扣血和Tooltip表现，不能记录为实机验收。
- 当前插入任务（2026-08-13，离线实验实现与自动验证完成）：`tools/war3_damage_calculator/index.html`新增独立“神秘路线录像实验”，20个录像/工作簿面板预设来自`war3_damage_calculator_mystery_experiment.csv`且不生成/注册生产Lua。默认`t=0`普攻、`t=1`激光，支持同刻顺序、激光成长/重置、魔能炮独立5秒层和魔能之眼路径逐甲；增伤是否传递保留开关。Edge桌面/移动59项断言及生成、Lua 5.1语法、UTF-8、diff通过，下一步用户双击页面继续录像对照，不能记录为原版算法已唯一证明或用户验收。
- 当前插入任务（2026-08-13，生产实现与自动验证完成）：单文件离线计算器位于`tools/war3_damage_calculator/index.html`，已按用户最新要求放弃外部“苟发育”算法并切换到Survival当前生产口径。暴击按attack record独立概率和百分比暴伤计算每击期望值；固定减甲后做正护甲百分比无视；项目怪物正护甲使用`1/(1+0.02W)`，零/负护甲按`W/3`进入当前Dota曲线。动态多攻击单位、共享成长、0秒首击和离散时间轴保留；Edge 31项断言及桌面/移动视口、CSV生成、Lua 5.1和PowerShell语法通过，当前只待用户双击页面确认使用体验。
- 当前插入任务（2026-08-12，file-mod大小写迁移待关闭VS Code后收尾）：Workshop Tools实机证明Game/Content物理目录`Survival`与编译资源`dota_addons/survival`冲突，导致`file mod ... is invalid`刷屏并阻断小地图/Panorama按需编译。旧`tools_asset_info.bin`已移出并备份；VTEX已对齐Valve overview schema，VTEX/VMAT定向编译各`1 compiled, 0 failed, 0 skipped`，但`resourceinfo`仍报告大写ManifestResource。当前VS Code工作区句柄阻止根目录大小写改名，下一步唯一动作是关闭VS Code和Workshop Tools后执行`tools/finalize_addon_file_mod_case.ps1`，取得`ADDON_FILE_MOD_CASE_FINALIZE_PASS`后再冷启动实机确认告警停止和小地图正常。按用户要求未重编译HUD、Panorama或粒子既有修改。
- 当前插入任务（2026-08-13，生产实现与自动验证完成）：Valve原生技能栏和输入保持启用，项目标签按可见按钮几何顺序与业务技能原子配对。为隔离疑似`W/E/D/F/R`的Valve文字层，每个已映射Ability面板的原生`HotkeyContainer`现在只设`opacity=0`并关闭命中，不折叠布局；清理、无有效选择或面板复用时恢复Valve原值。标签与原生压制状态均纳入0.25秒完整性检查。专项契约、替代英雄回归、PowerShell解析、相关Lua 5.1语法、严格UTF-8、限定diff、编译产物符号和`combat_stats.vjs_c`定向编译通过；下一步Workshop Tools完全冷启动，直接观察仅剩的`SurvivalAbilityHotkey`实际字母并复测输入，尚未实机验收。
- 已完成插入任务（2026-08-12）：Game/Content物理目录已统一为全小写`survival`。用户Workshop Tools实机确认小地图恢复正常，根因确定为物理目录`Survival`与编译资源`dota_addons/survival`的file-mod大小写身份冲突；后续不得恢复大写addon目录名。现有小地图源和编译产物保持不变。
- 已完成插入任务（2026-08-12，用户实机验收通过）：`combat_stats.js`无有效选中单位分支已从不存在的`refreshOfficialReturnHomeHotkey()`改用现有`refreshOfficialUtilityHotkeys([])`，保留后续1秒刷新。专项契约、严格UTF-8、限定diff通过，`combat_stats.vjs_c`定向编译为`1 compiled, 0 failed, 0 skipped`；用户确认Workshop Tools中不再出现该ReferenceError，任务关闭。

- 当前插入任务（2026-08-11，生产实现与自动验证完成）：基础箭塔/路线计数及并发预占已改为玩家作用域；七塔合一支持每玩家最多5座终极塔，材料不消耗且每座永久仅参与一次；齐天大圣R整组原子迁移全部终极塔并保留相对位置；任意已完工城墙死亡一次性触发全队失败，施工墙和主城不直接失败。专项Lua 5.1/契约、语法、生成一致、UTF-8/BOM和限定diff通过；下一步Workshop Tools完全冷启动实机验收，详见`CURRENT_TASK.md`顶部。
- 当前实施任务（2026-08-12）：外围玩家档案本地Fixture纵向切片已完成生产实现，包含CSV schema/公开白名单/开发账号映射、JSON Fixture生成、统一Provider、完整快照与增量revision/update_id、异步generation、VIP失败关闭、服务端私有档案和公开NetTable。专项Lua 5.1与契约已通过；真实HTTP、数据库、支付、Steam身份和写回尚未实现。下一步冷启动Workshop Tools验证玩家0 VIP、玩家1非VIP和公开表字段；详细协议见`PLAYER_PROFILE_INTEGRATION.md`。
- 逐波模型加载经验已沉淀到`WAVE_MODEL_LOADING_TROUBLESHOOTING.md`，包括W12 Visage告警的确定根因、CSV优先原则、正式/dev/出生统一解析、session租约、urgent并行、禁止误用`asset_preload.retire()`、复发排查顺序和未来逐波换模清单。用户2026-08-11后续观察中暂未再发现加载问题；只能记为阶段性有效，新增模型后仍需冷启动分别验证`monster<N>`与正式波次。
- 当前插入任务（2026-08-11）：闪电魔塔击杀风暴已改为死亡点500范围即时单次物理伤害，LV1至LV5使用触发时塔攻击快照110%/120%/130%/140%/150%；每目标只受伤和发布一次`TOWER_LIGHTNING_HIT`。随后一秒内5/6/7/8/9道雷柱仅作视觉，不查询敌人、不伤害、不触发扩散。原塔归因、风暴连锁击杀及独立雷电扩散30%/200%/非递归规则保留。CSV、生成Lua、Tooltip和六份本地化已同步；专项Lua 5.1行为/契约、相关回归、5个Lua语法、生成逐字节一致、配置CheckOnly、UTF-8/BOM和限定diff通过。下一步Workshop Tools冷启动实测即时伤害时点、物理护甲结果、纯视觉雷柱数量、扩散和连锁风暴，尚未实机验收。
- 当前插入任务（2026-08-11）：`ability_tooltip.js:997` 的几何诊断越作用域 `active.engineSlot` 已修正为函数参数 `binding.engineSlot`，并强制重编译 `ability_tooltip.vjs_c`。源码/产物作用域契约、输入生命周期契约、严格UTF-8和限定diff通过；完整内存生命周期契约仍被既有无关`SURVIVAL_UI_CONTEXT_GUARD_MISSING`阻断。下一步完全冷启动Workshop Tools确认不再出现`active is not defined`，尚未实机验收。
- 当前插入任务（2026-08-10）：本地化缺失/重复token已按最小范围修复。`npc_survival_builder_proxy`和`npc_survival_repairer`已从`unit_display_names.csv`补齐并生成；game六份本地化镜像和content两份Panorama源中的精确单位token、挑战奖励大小写别名、金矿/英雄祭坛显示值已同步。专项契约、冲突扫描、结构、生成一致性、Lua 5.1语法及UTF-8/BOM通过；仍需Workshop Tools完全冷启动确认`FindSafe`与重复token引擎告警消失，尚未实机验收。
- 当前插入任务（2026-08-10）：空区域配置兼容修复已实施。没有有效`hero_movable`时白名单不启用，英雄和建筑沿用旧导航/Grid规则；配置有效行后才启用严格白名单，`building_forbidden`始终独立生效。区域拒绝现在返回完整红色footprint cells，不再让Grid消失。CSV生成、专项契约/Lua 5.1行为和目标语法已通过，仍需Workshop Tools冷启动确认Grid显示、合法建造与拒绝红格；Hammer真实边界只阻断新白名单启用，不阻断当前地图可玩性。
- 已完成插入任务（2026-08-09）：怪物物理伤害按当前Dota护甲曲线补偿到War3目标曲线，且并发stash冲突已解决。117 War3护甲继续线性投影为39运行时护甲；现代非线性映射辅助API保留但不用于波次、挑战或调试怪。`monster_war3_armor_damage_enabled=1`只对明确项目怪物的正护甲物理伤害乘目标曲线/引擎曲线差值，随后仍由引擎结算。固定基准最终倍率约0.299401、理论23.79秒；专项Lua 5.1/契约/语法及科技减甲、毒云回归通过。用户明确确认固定样本测试验收通过，但未提供精确击杀秒数或日志；极高护甲怪仍需独立抽样。
- 当前插入任务（2026-08-09）：怪物尸体、运行时日志和Panorama本地化性能优化已完成生产实现及自动验证。明确标记的波次/挑战/调试怪死亡结算后按CSV保留0.6秒、共享任务下沉0.8秒/160码、隐藏并安全移除；强制清场仍立即删除。运行时成功路径详细日志默认关闭且惰性格式化，Tooltip详细日志默认关闭，四个动态本地化入口使用256项有界缓存。专项Lua 5.1行为/契约、全项目356个Lua语法、生成一致性、UTF-8、配置检查和两仓diff通过；4份Panorama产物均强制编译成功。下一步Workshop Tools冷启动批量击杀并对比实体/日志/帧时间，尚未实机验收。
- 当前插入任务（2026-08-09）：工人训练、建筑提交、普通升级、箭塔升级/转职已改为同步`event_bus.request/handle_request`结果。修理工按team独立消费CSV两级进度（LV1成功5次后进入LV2，LV2成功2次后保留最终完成态并拒绝继续训练），伐木工最终`max_count=-1`无限行为不变；只有单位创建成功才推进进度，创建失败继续退款。建造移动/施工异步失败保存`source_ability`并以独立幂等事务恰好回滚一次冷却，扣费后的创建/施工失败同时退木材、金币和人口。专项Lua 5.1行为、PowerShell契约、目标语法、CSV/生成字段、严格UTF-8、配置CheckOnly和限定diff通过；下一步Workshop Tools冷启动实测失败冷却、资源退款和两级修理工，尚未实机验收。
- 已完成当前任务（2026-08-09）：N1第11–25波以及N2–N5第11–30波普通怪均已调整为每波59只；多怪种按修改前数量比例使用最大余数法确定性放大，单怪种直接设为59。每波`wave_leader`精英和`assault_boss`数量均保持不变。权威`wave_definitions.csv`和生成`wave_definitions.lua`已同步；专项数量契约、Lua 5.1行为、语法、生成逐字节一致、严格UTF-8/BOM及限定diff检查通过。所有难度W1–W10保持原始普通怪数量，仍需Workshop Tools冷启动确认实际生成数量。
- 当前插入任务（2026-08-09）：正式后续波次资源已改为目标波首只敌人出现前4秒异步预载。首波、练功房、塔和城墙启动/后台边界按批准范围保留；敌方`zombie_stream`后台批量加载关闭。专项契约、Lua 5.1行为、语法、生成一致性、严格UTF-8和限定`diff --check`通过；尚未Workshop Tools实机确认4秒日志、模型视觉和首只敌人时刻。
- 当前插入任务（2026-08-08）：`monster19`实机已证明3秒门禁按预期输出`ready_after_buffer elapsed=3.00`，但仍显示红色`ERROR`。本机VPK索引确认最终根因是旧`models/heroes/tiny/tiny.vmdl`不存在；现已从权威CSV改为实际存在的`models/heroes/tiny/tiny_01/tiny_01.vmdl`，重建资产/怪物生成Lua并同步异步代理KV。3秒固定缓冲与连续命令generation门禁继续保留。下一步完全冷启动Workshop Tools复测W19模型和快速`monster19`/`monster20`；新路径尚未实机验收。
- 当前插入任务（2026-08-08）：N1 W13-W18客户端闪退的直接证据是`dota2_2026_0808_033038_0_V8_hiting_max_memory_limit__512_MB.mdmp`，Lua 16 MiB高水位不是同一内存池。用户新日志确认119次Tooltip几何诊断`active`越作用域异常和1次Combat不存在函数调用；两项已修复，`inventory_tooltip.js`也纳入generation/context门禁。Panorama现于启动1秒/5秒及之后60秒输出聚合，默认关闭高频Tooltip长诊断和200次游标探针。下一步必须完全冷启动，先验证出英雄5秒不再异常/退出，再跑N1到W20并核对`[SURVIVAL_MEMORY]`与新dump；尚未实机证明闪退解决。
- 当前插入任务（2026-08-08）：多选箭塔跨路线批量升级已按最新要求完成生产实现和自动验证。基础塔及不同转职塔以共同`arrow_tower`身份混选，各沿自身路线；Q按下一等级费用、W按直升当前阶段最高级累计费用报价，并按木材→金币→entindex升序尝试。客户端只提交最多64个去重候选，服务端逐塔重验owner/建筑/Ability并原子扣费；资源不足等失败跳过，成功受理后才启动冷却。专项Lua 5.1/契约、相关回归、语法、UTF-8和Panorama强制编译通过，下一步Workshop Tools冷启动实测，尚未用户验收。
- 当前插入任务（2026-08-08）：多选金矿批量协调已完成生产实现和自动验证。Q按各矿权威下一等级费用，以木材→金币→entindex排序逐矿原子升级；W/E每次批量请求只购买1级玩家共享科技，成功后同步有效候选冷却；自动按钮按明确目标状态批量开启/停止，混合状态幂等。同一玩家自动矿由最小entindex协调共享科技，其余矿只独立升级本体。沿用现有最多64个候选协议，无Panorama改动。专项批量/自动协调Lua 5.1、契约、箭塔及商店科技回归和目标语法通过；下一步Workshop Tools冷启动实测鼠标、Q/W/E快捷键、部分资源、混合自动状态及多人owner隔离，尚未用户验收。
- 当前插入任务（2026-08-08）：金矿升级后尺寸恢复原状的问题已完成生产修复和自动验证。`gold_mine_config`现把`building_visual_levels.csv`金矿LV1固定视觉投影到全部等级，手动/自动升级提交后均重新应用`radiant_ancient001.vmdl / 0.34`；专项Lua 5.1/契约、语法、生成一致性、UTF-8与限定diff通过。下一步Workshop Tools冷启动连续升级实测，尚未用户验收。
- 当前插入任务（2026-08-08）：金矿已从`tower_good4.vmdl / 1.0`替换为项目已确认可选中的`radiant_ancient001.vmdl / 0.34`，施工视觉、权威CSV、定向生成Lua和单位KV首帧回退已同步；金矿`selectable=true`及全部业务身份/数值保持不变。专项契约/Lua 5.1、生成一致性、语法、UTF-8与限定diff通过；下一步Workshop Tools冷启动验证鼠标命中和五个技能，尚未实机验收。
- 当前插入任务（2026-08-08）：城墙升级生命已由“保持百分比”改为“当前生命增加最大生命差值”；`100/200`升级到上限`400`后为`300/400`。提交瞬间读取即时生命，等级与科技后的最终实际上限共同参与差值；仅修改城墙，CSV生命数值和其他建筑升级行为保持不变。专项Lua 5.1行为/契约/语法、全项目Lua 5.1语法、邻近修理回归、UTF-8与限定diff已通过，仍需Workshop Tools实测。
- 已完成并经用户确认（2026-08-08）：人口训练权威CSV保持原始数据，阶段1至5各`max_count=5`，阶段6为`max_count=100`并启用。运行时按team共享、按`training_id`独立计数，当前CSV阶段达到自身上限后才顺序加载下一阶段；农场等级只校验前置条件。服务端和Tooltip共用CSV递增费用与阶段内进度。用户已明确反馈问题解决，该人口训练修复记为实机验收通过，不再恢复为活跃任务。组合任务中的城墙碰撞与迁移重锚仍保持独立待验收状态。
- - 当前插入任务（2026-08-07）：城墙基础Hull为256；用户实测并确认波次怪角色Hull为普通32、精英64、Boss无碰撞，`scalemonster <倍数>`按角色基准不累计作用于当前及之后波次怪且不改模型；研究所/农场施工、实际视觉及KV回退与英雄祭坛统一为`radiant_ancient001.vmdl`缩放0.34。该任务当时的“金矿保持原生缩放1”已被上方2026-08-08最新金矿可选模型要求替代。专项Lua 5.1/契约、目标Lua语法和diff检查通过；单位模型旧契约仍被无关伐木工CSV缺项阻断，下一步Workshop Tools实测真实碰撞与模型尺寸，尚未用户验收。
- 前序六项玩法修复（2026-08-07）：无声金矿飘字、农场/金矿1/5上限、CSV首发顺序和农场Tooltip实现保持完成；其中金矿旧`0.0875`和后续原生缩放1均已被上方2026-08-08最新`radiant_ancient001.vmdl / 0.34`替代，城墙Hull基准128已替换为256。其他专项验证结果保持有效，仍待Workshop Tools合并验收。
- 当前活跃任务（2026-08-06）：第1-5波数据驱动怪物视觉系统已完成生产实现和自动验证。新增独立视觉资产/组件/效果/波次CSV及生成Lua；按`wave_number + member_role + normal_index`解析，`normal`使用主/辅候选、`wave_leader`使用小Boss、`assault_boss`使用阶段Boss并回退小Boss。W4/W5辅助候选已录入，但未经批准的普通怪混编比例保持`support_every_nth=0`，当前不启用；没有运行时领头怪的波次不会新增Boss。11项模型与10个异步预载代理均通过本机VPK/KV检查，启动预载W1-5并在游戏中排队下一波。`wave_definitions.csv`和`monster_archetypes.csv`无改动。专项解析/服务/波次接入/清理/预载、Lua语法、生成一致性、UTF-8和限定diff通过；下一步Workshop Tools冷启动重点验收W5模型、缩放、动画与性能。
- 当前活跃任务（2026-08-05）：箭塔建造资源成本已完成生产修复和自动验证。工作簿7条路线共175个成本节点与塔CSV全部一致，只有建造适配层错误回退80木材+20金币；现改为从生成的`arrow_tower_base.lua`首级行读取0金币+50木材，服务端扣费与UI共享该值。专项契约/Lua 5.1、工作簿审计、生成一致性、相关回归、语法、UTF-8和限定diff通过；下一步Workshop Tools冷启动确认按钮与实际扣费。
- 当前活跃任务（2026-08-05）：所有防御塔基础攻击/索敌距离由权威`global_rules.csv`统一为1000，射程科技继续叠加。用户实测10000过快后，基础箭塔最终弹速改为5000；其他转职塔恢复修改前速度：神秘/机枪/多重/对空1250，死亡/冰霜/闪电100000，全局倍率恢复1；终极融合继承来源塔速度。专项契约、Lua 5.1、融合回归、语法、生成一致性和UTF-8通过；下一步Workshop Tools冷启动实测。
- 当前活跃任务（2026-08-05）：`N1按最新波次总表同步(1).xlsx`中的现有游戏内容已完成生产同步和自动验证。N1现有70条直接成员行，覆盖25波，普通202、首怪21、进攻Boss5、总228；Profile维持150条矩阵并更新N1四练功房、工作簿五类特殊目标、转生和十戒，工作簿未列的七宗罪材料怪保持既有批准值。存档挑战继续忽略。N1/N2-N5波次、Profile、转生行为、计时、Lua 5.1、生成一致性、UTF-8和限定diff通过；全量生成仍被既有物品CSV类型错位阻断。下一步Workshop Tools冷启动实机验收N1。
- 当前活跃任务（2026-08-05）：`N2按最新波次总表同步(1).xlsx`中的现有游戏内容已完成生产同步和自动验证。N2现有89条独立波次成员（普通1270、领头27、进攻Boss6、总1303），停止N1倍率派生；Profile扩展为150条并覆盖练功房、特殊目标、转生和十戒，N2使用工作簿值，其他难度保持同步前原型值。存档挑战按用户要求忽略；已有wave ID不迁移。下一步Workshop Tools冷启动实机核对N2波次与全部已接入目标。额外发现未修改的转生商店前台旧回归测试失败，未计入本任务通过。
- 当前最新任务（2026-08-05）：Undying外观的独立Builder建造技能从W修正到Q及工具技能尾部排序已完成生产修改和自动验证。阶段系统先按正确CSV添加建造技能，再创建Blink到D；Panorama现将普通技能与D/F/F2工具技能分离，普通技能独占Q/W/E/R/T/Y/U，工具技能稳定追加到尾部。Builder为建造技能后接最后一位Blink D；正式英雄为普通技能后接回城F2、最后拾取F。专项排序/输入/Builder契约与Lua 5.1、语法、CSV生成一致性、UTF-8和两份JS强制编译通过。下一步Workshop Tools冷启动确认视觉顺序、标签、鼠标和实际快捷键，尚未实机验收。
- 最新任务完成（2026-08-05）：开局资源与基础伐木效率修正已获用户明确验收通过。开局金币0、木材10及相关基础规则来自`global_rules.csv`；农民CSV基础效率`1/2/3/5/10/20/40/80`保持不变；资源树收益从LV2开始每级+1，LV1不再整体额外+1。生产修改、自动验证和Workshop Tools用户验收均已完成，不得恢复为活跃或待验收任务；等待用户指定下一项任务。
- 最新任务收束（2026-08-05）：用户反馈“范围拾取F + Builder建造槽位/CD”任务基本完成并要求记录经验。当前仓库已确认F归属、旧英雄圆心300拾取的所有权/排序/满栏停止，以及城墙→主城连续使用Q的CSV阶段槽位；但代码仍是无目标拾取且建造KV固定0.5秒CD，尚未体现鼠标点1000/300 AOE和施工期独立CD。经验已写入`PROJECT_CONTEXT.md`和`SESSION_LOG.md`；后续不得把“基本完成”误记为全部细项实机验收，继续前先核对实际运行分支/产物。
- 当前活跃任务（2026-08-05）：按用户提供的工作簿与截图重构N1–N5怪物难度数据。练功房与六类特殊目标已完成50条`challenge_combat_profiles.csv`录入、生成Lua和挑战运行时接入；遭遇创建时固定全局难度快照，刷新沿用快照，Profile缺行失败关闭，War3护甲只在生成边界换算一次。专项契约/Lua 5.1、挑战与N3-N5回归、Luac 5.1、定向生成一致性、严格UTF-8和限定diff均通过；下一步Workshop Tools冷启动逐难度核对四个练功房及六类特殊目标，尚未实机验收。
- 最新可靠检查点：用户补充的`N3按最新波次总表同步(1).xlsx`已作为N3数量与属性来源接入；N3模型映射、飞行回退和26–30波来源均由用户明确批准。权威CSV现包含N3普通小怪1270、领头怪27、进攻Boss6，总计划1303；N3独立30波难度已启用，飞行普通怪使用本波War3基准护甲3倍。Lua 5.1、契约、生成一致性、计时/减甲回归、UTF-8和限定diff均通过；下一步Workshop Tools冷启动验证每波实际数量、模型、领头怪首发、护甲UI及波次重叠。
- 最新可靠检查点：N4、N5已按本机`N4完全正确_倍率同步(1).xlsx`和`N5完全正确_倍率同步(1).xlsx`接入独立30波CSV。两者各包含普通怪1270、领头怪27、进攻Boss6，总计划1303；沿用已批准N3模型映射、确定性数量分配、飞行回退、普通飞行怪三倍War3护甲和角色顺序。开局难度选择现启用N1-N5，五格横向一排且不显示描述小字。专项Lua 5.1/契约、N3与计时回归、Lua 5.1语法、生成一致性、严格UTF-8、Panorama强制编译和限定diff均通过；下一步Workshop Tools冷启动验证N4/N5实际出怪与五格布局。
- 插入修复检查点：敌方单位和树木属性UI复用上一个单位的问题已完成生产修复和自动验证。根因是可控输入解析器拒绝不在`GetSelectedEntities()`中的敌方portrait；现新增HUD专用`ResolveDisplayUnit()`，属性/名称/生命/快照链使用display身份，技能与Builder输入继续使用可控`Resolve()`。专项/输入回归、Lua 5.1语法、严格UTF-8、限定diff和两个JS强制定向编译通过；下一步冷启动快速切换英雄、敌人和树木，并确认点击敌人后Q/W/E仍由可控单位处理。
- 插入修复检查点：转生挑战进行中重复购买、副本切换后旧回调拉回英雄及普通Boss刷新错误传送已完成生产修复和自动验证。商店快照与扣费前均拒绝活动中的转生挑战；每玩家唯一前台遭遇覆盖普通挑战与转生进入，延迟刷新校验session/generation/前台身份；普通挑战刷新保留位置，仅仍在前台的`challenge_11`重置到阶段入口。专项契约、Lua 5.1行为、相关回归、生成一致性、语法和UTF-8通过；下一步Workshop Tools冷启动实测重复点击转生购买、普通Boss刷新、十宗罪阶段刷新及十宗罪→转生切换，尚未用户验收。
- 本任务工作区保护基线：已有19个Panorama编译产物、4个粒子编译产物和一批未跟踪测试/日志文件，不属于本任务；用户停止Workshop Tools后连续两次`git status --short`一致。后续不得触碰、回滚或纳入本任务交付。
- 传说：深渊审判焰爆被动已由用户确认没有问题，不再作为活跃或待验收任务恢复。稳定实现只消费`HERO_MAIN_ATTACK_LANDED`并排除次级攻击，以`attack_id`有界去重；触发时读取`HERO_COMBAT_STATS_GET_REQUEST`逻辑三维，以佩戴英雄为500范围中心，逐目标提交全属性×50魔法伤害，并在英雄处播放一次焰爆粒子和声音。完整维护边界见`PROJECT_CONTEXT.md`和`DECISIONS.md`。
- 极寒之刃批量击杀进度修复已由用户在Workshop Tools确认成功，不再作为活跃或待验收任务恢复。稳定规则：成长只消费`ENGINE_ENTITY_KILLED`，不得按victim entindex跨实体生命周期永久去重；召唤/代理攻击沿有界owner链归属玩家；物品charges、Tooltip与成长HUD统一消费服务端投影的实际equipment progress、CSV target和现场remaining。完整根因、测试和验收记录见`PROJECT_CONTEXT.md`、`KNOWN_ISSUES.md`及`SESSION_LOG.md`顶部。
- 相机任务已由用户于2026-08-05在Workshop Tools明确确认解决，不再作为活跃任务恢复：空格定位使用`MoveCameraToEntity(target)`；挑战镜头已删除`SetCameraTarget(hero)`→`SetCameraTarget(-1)`锁定/释放链，改为一次性非锁定聚焦，镜头不再返回英雄传送前位置。稳定规则见`PROJECT_CONTEXT.md`，引擎陷阱见`KNOWN_ISSUES.md`；等待用户指定下一项任务。
- 已否定检查点：第一版曾使用`SetCameraLookAtPosition`并只有Panorama本地日志；虽然静态契约与编译通过，用户实机确认空格不定位、挑战仍回弹。该方案已被上方第二版替代，不得恢复。
- 关联前置修复：未召唤正式英雄时按空格选中隐藏 Undying 占位锚点的问题已完成生产修复和自动验证。Panorama 唯一输入所有者现在接管 `SPACE`：占位阶段选择 CSV Builder，正式英雄替换后选择正式英雄，并覆盖 fallback keybind；Builder身份NetTable声明已补齐。专项契约、Lua 5.1行为/语法和Resource Compiler强制编译通过。下一步完全停止后 Run，召唤前后各按空格并核对`[SURVIVAL_SELECTION] SPACE_SELECT`日志；尚未实机验收。
- 当前最新任务：黑暗游侠专属小游侠已同步新版多目标逻辑，在`MODIFIER_EVENT_ON_ATTACK`正式出手时固定向主目标和最近另外4个敌人并列发箭；落地阶段不再补射，小游侠也不发布英雄转生出手事件。专项嵌套行为、相关回归、契约、Lua 5.1语法、CSV/运行/生成一致性和UTF-8通过。下一步Workshop Tools冷启动确认5箭视觉同步、各目标独立结算和次级附带效果隔离。
- 当前最新任务：转生多目标普通攻击已从主箭命中后补射改为`MODIFIER_EVENT_ON_ATTACK`正式出手时并列发射，生产修改和专项/相关回归、Lua 5.1语法、CSV一致性及UTF-8验证通过；真实命中业务和次级attack record隔离保留。下一步Workshop Tools冷启动确认主/次级箭视觉同步、独立结算与技能隔离，并提供`[DROW_VISIBLE_MODIFIER]`日志归因黑暗游侠Buff图标；未归因前不删除Modifier。
- 待实机验收：祭坛召唤按钮修复已完成代码和自动验证，等待Workshop Tools冷启动实机确认。根因是creature祭坛动态Lua Ability经`CastAbilityNoTarget()`不可靠进入`OnSpellStart`，而服务端直接权威分发遗漏`ability_summon_*`；现复用既有Ability→hero_id映射直达`HERO_SUMMON_REQUEST`，客户端也显式托管召唤/旅行按钮。下一步选中祭坛点击免费英雄，确认`SEND_NO_TARGET`、`ALTAR_SUMMON_DISPATCHED ... ok=true`及正式英雄替换。此前缺失的`survival_builder_identity` NetTable声明已在空格选择修复中补齐，相关输入生命周期契约恢复通过。
- 科技研究进度与完成时序修复已完成代码、专项测试和资源编译，当前等待Workshop Tools冷启动实机验收：开始时服务端校验并立即扣费，但2秒研究期内保持旧等级/旧效果；同队同时只能研究一项；进度卡只显示径向遮罩、不显示`2 → 0`数字；结束后才提交等级、重算效果并提示“已完成研究”。提交异常会恢复旧等级并退款，迟到/重复回调不能二次升级。旧`technology_cooldown_*`协议字段暂时保留，但语义已改为研究进度。下一步完全停止并重新Run Workshop Tools，逐项确认扣费、团队互斥、无数字进度、延迟生效和完成提示；未经用户实机确认不得记录为验收完成。
- 用户已在 Workshop Tools 确认 Builder 当前可以正常建造，`builder_not_owned`、Grid 校验与建造提交主链视为实机通过；尚未据此推定城墙 Q 升级、完整 Q/W/E/R/T+D 或连续两次 Run 均已验收。6 个 Panorama 二进制生成物曾残留 Git `UU` stages，现已全部从当前 content JS 权威源强制重编译并精确暂存为 stage 0，未选择整仓 ours/theirs、未提交、未触碰其他既有修改。
- Builder ownership/槽位/建筑选择最新补丁已完成自动验证：普通 creature 的业务身份改由 `builder_service` 注册实体和 `survival_player_id` 权威解析，Grid/Building/建筑 Ability 路由不再假设 `GetPlayerOwnerID()` 有效；CSV `slot_order` 显式映射五个建造槽 index `0..4`，Blink 独立 index `5`。Grid、建筑移动与托管 Ability 输入统一当前选择解析并拒绝跨选择 runtime owner。专项 Lua 5.1/契约/语法/UTF-8/限定 diff 通过，四个 Panorama JS 均强制编译成功。下一步冷启动 Workshop Tools 验证 Q Grid、建造提交、城墙控制与 Q 升级、最终 Q/W/E/R/T + D。
- 最新可靠检查点：占位 Undying 物理/选择残留与 Grid 永久等待修复已完成自动验证。专用生命周期 Modifier 使占位锚点不可选择、无单位碰撞、命令受限且不可移动；Grid validate 的早期错误现在携带原 session/request/Ability/request anchor 返回，不再被客户端按默认 `(0,0)` 静默丢弃。客户端与服务端已有完整 `[GridPlacement]` 请求级日志。Builder专项契约/Lua 5.1行为与语法、输入/utility/Alt契约、严格UTF-8、两仓限定diff和 Grid Panorama 强制编译均通过。下一步完全停止 Workshop Tools 后 Run，验证移动无阻挡、W/图标网格和提交；若失败，提供同次操作的 `[SURVIVAL_INPUT]`、`[SURVIVAL_CAST]`、`[GridPlacement][CLIENT/SERVER]` 日志。
- 当前活跃任务为 Undying 建造者代理、祭坛英雄替换及其 Panorama 输入修复：生产代码与自动验证已完成。独立 `npc_survival_builder_proxy` 承接建造、D Blink、修理、选择和 UI；Ability runtime owner 现在是托管施法权威 caster，建造点击/快捷键强制进入冻结 Builder/Ability 身份的 Grid session。`ui_bootstrap.js` 每次 HUD generation 无条件重建唯一 dispatcher 与 generation keybind，消除第二次 Run stale callback。专项契约/Lua 5.1、相关回归、Lua语法、严格UTF-8和6个Panorama强制编译均通过。下一步完全停止并连续 Run Workshop Tools 两次，验证所有权、选择、全部快捷键、建筑点击、Grid、替换和死亡复活；首版不宣称代理为真实 courier class。
- 英雄最终伤害原生飘字分流已由用户确认完成，不再作为待验收任务恢复：普通攻击使用`OVERHEAD_ALERT_BONUS_SPELL_DAMAGE`白字，暴击使用`OVERHEAD_ALERT_CRITICAL`原生表现，带有效Ability的正式技能伤害使用`OVERHEAD_ALERT_DAMAGE`红字；三者均显示最终`OnTakeDamage.params.damage`，上一版Panorama暴击链已移除。稳定经验见`PROJECT_CONTEXT.md`。
- 齐天大圣E全属性×5暴击附伤修复已由用户实机确认数据正常，本任务完成且不得恢复为活跃任务。稳定方案是在最终`OnTakeDamage`阶段消费已确认的主攻击暴击身份并发布`HERO_FINAL_CRITICAL_ATTACK_DAMAGE`，不在较晚`OnAttackLanded`读取可能已销毁的record；次级攻击与W分身排除，伤害事务失败输出`MONKEY_KING_E_DAMAGE_FAILED`。长期规则见`PROJECT_CONTEXT.md`。
- 当前活跃任务为“超级防御塔暴击”四项效果修复。代码与自动验证已完成：每级同时增加防御塔暴击/攻击和召唤英雄暴击/攻击各 `0.5%`，CSV 的23级均有四行说明，生成科技 Lua 复合投影接入现有塔与英雄刷新/攻击链。下一步完全停止并重新 Run Workshop Tools，实机确认 Tooltip、已有单位即时刷新、实际攻击值和暴击率；未经用户确认不得记录为验收完成。
- 当前活跃任务为英雄实际射程与工具技能归属修正。用户最新批准齐天大圣由30000速度远程弹道改为近战式无飞行弹道结算，攻击/索敌仍为1000；CSV、生成Lua、运行时分流和自动验证已完成。Undying只保留D闪烁并修复D键；召唤英雄不拥有D，保留F范围拾取和F2回城。当前等待Workshop Tools实机验收，未经用户确认不得记录为制作完成。
- 三选一公共技能`proto_arcane_barrage`/“奥术弹幕·被动”已将每颗随机落击从基础爆炸替换为天怒法师秘奥耀光单次落击`skywrath_mage_mystic_flare.vpcf`；每颗CP0仍绑定Lua权威伤害落点，未接入会自行随机落点的持续ambient父粒子。5/7/21颗、调度、150伤害范围、全属性伤害和活动锁均未修改；专项契约、Lua 5.4.5语法、严格UTF-8和限定检查通过，下一步冷启动Workshop Tools实测连续落击外观、落点一致性和21颗性能。
- 齐天大圣W分身数据复刻实机反馈已完成代码修复和自动验证：攻击、最终攻速、生命、暴击及逻辑三维统一消费本体同一份`HERO_COMBAT_STATS_GET_REQUEST`快照；生命复用隐藏生命Modifier，分身选中面板也适配同一快照。下一步Workshop Tools确认本体/分身攻击、攻速、生命、暴击、三维面板一致且固定10护甲、仅Q隔离未回归。
- 齐天大圣Q/W/E/R专属技能、严格顺序`passN`与通用七塔合一已完成代码和自动验证；当前状态为等待Workshop Tools实机验收，不得描述为制作完成。Q/W/E/R分别1/3/6/10转解锁，四槽固定置灰；终极塔使用7个隔离代理执行真实路线攻击并由R继承英雄攻击/暴击。详细实现、测试与实机清单见`CURRENT_TASK.md`顶部。
- 资源树第二轮紧急修复待实机确认：第一轮移除Modifier重复分类后仍不掉血，现确认实机DamageFilter不保证`damage_category_const`，旧Mock错误掩盖缺字段拦截。已新增`ON_ATTACK_START`一次性真实攻击凭证，缺类别平A凭凭证放行，塔/技能/无凭证脚本伤害继续拒绝，并输出限次`TREE_DAMAGE_FILTER`诊断。
- 第一轮树Modifier重复分类修复已被实机证实不充分，勿再恢复“DamageFilter类别字段始终存在”的假设；下一步冷启动验证第二轮真实攻击凭证方案。
- 三选一公共技能`proto_void_pulse`/“虚空震爆·被动”的卡尔龙卷风视觉维护已完成：恢复content源`particles/survival_tornado/survival_tornado_follow.vpcf`，仅引用Valve `invoker_tornado_child.vpcf`且不含内部移动算子；生产主/小龙卷继续由Lua每0.05秒写CP0追踪。Resource Compiler强制编译为`1 compiled, 0 failed, 0 skipped`，新视觉契约、Lua 5.4.5语法、严格UTF-8和限定检查通过；下一步完全重启Workshop Tools Run确认视觉追踪、附着、死亡停留和LV5分裂。
- 紧急启动阻断已修复：提交`85ce4eb`引用但漏提交的`systems/building_upgrade_process.lua`已补齐；`building_upgrade_system.lua`与`addon_game_mode.lua` Lua 5.1语法、升级完成/重复拒绝/销毁取消/重置/失效建筑行为均通过。下一步必须完全停止并重新Run Workshop Tools确认不再出现`module not found`。
- 当前新增实现待实机验收：资源树初始位置改为`(448,64,128)`；伐木工LV1-LV8统一0.5次/秒、400射程、远程空弹道，LV3与LV6-LV8模型已替换；修理工保持纯修理但距离属性为400；其他五英雄保持远程，齐天大圣改为1000码近战式即时结算；一至四转普攻总目标数为3/4/5/6并按目标护甲独立结算。CSV、生成配置、运行时、KV、专项测试和相关回归已通过，下一步Workshop Tools冷启动验收。
- 紧急阻断已修复：`hero_passive_skill_service.lua`曾因顶层chunk拥有202个local而超过Lua 5.1的200-local上限，导致`addon_game_mode.lua`无法加载。末尾`trigger/roll/on_main_attack`现改为模块表方法，顶层声明降至199；Lua 5.1语法、8项公共技能状态和四英雄专属回归已通过。仍需完全停止并重新Run Workshop Tools确认地图实际进入。
- 当前活跃任务：资源树、召唤祭坛、主城、伐木工LV1至LV5及修理工LV1至LV2模型替换。CSV权威配置、定向生成、运行时应用、KV首帧回退与模型预缓存已完成；11个模型均在当前Dota VPK中确认存在，专项合同、Lua 5.1行为/语法、生成一致性、编码列数、限定diff及树伤害回归通过。下一步在Workshop Tools确认树尺寸、工人动画、主城五级缩放/切模及祭坛尺寸，未经实机验证和用户确认不得记录为制作完成。
- 活跃任务：把现有单人服务器权威玩法逐步改造成最多4人的个人防线联机玩法。
- 当前阶段：阶段1生产实现与自动验证完成，等待Workshop Tools单人冷启动验收。
- 玩法权威：每玩家独立经济、建筑、Builder、英雄和波次怪；空间共享；城墙可集中建造；怪物绑定所属玩家城墙；英雄可跨区支援；不能控制他人单位。
- 网络权威：客户端只发送操作意图，Lua服务端校验并执行，Dota 2引擎同步实体结果。

## 最后可靠检查点

- 2026-08-20真实 Supabase/Python API 联调已通过，证明两份 migration 的核心表、5个RPC、Secret key权限、档案初始化和在线时长租约/幂等语义可用。Automation 9001 已向当前测试项目同步定义；默认`local_fixture`档案路径与生产禁用奖励保持不变。尚未执行Workshop Tools HTTP Provider双客户端、重连和API重启实机，不得宣称游戏端上线。
- 同日后端与Supabase文件已迁到独立`D:\survival_database`仓库，生产CSV仍只在addon。Python经`SURVIVAL_ADDON_ROOT`读取CSV，并以独立pepper对Steam Account ID做HMAC后入库；目标仓库提供loopback安全启动脚本和9001 fixture开关。本机`.env`现已配置真实 Project URL 与新版 Secret key，凭据只保存在该忽略文件且不得进入Lua、聊天或Git。
- 2026-08-12玩家档案Fixture纵向切片代码与自动测试完成；已增加公开投影成功日志，可直接核对玩家0/1的Fixture账号、revision及公开白名单字段。VIP权威CSV默认关闭，Mock账号验证后再投影。尚未Workshop Tools实机验证，也未接HTTP/数据库。
- 2026-08-12 Game/Content物理目录已统一为全小写`survival`，用户Workshop Tools实机确认小地图正常显示。旧混合大小写资产索引备份仍位于`C:\Users\UserComputer\AppData\Local\Temp\survival_file_mod_backup_20260812_151927`；该问题已关闭，不再恢复为活跃迁移任务。
- 2026-08-10空区域配置兼容策略已落地：CSV无启用`hero_movable`业务行时保持旧地图导航与Grid建造，区域拒绝仍返回可渲染红格；等待Workshop Tools实机验证。
- 2026-08-06已完成代码库只读审计并建立完整任务清单。
- `addon_game_mode.lua`和`addoninfo.txt`已开放4名好人方玩家。
- Builder已经按player注册并保存`survival_player_id`，是多人身份改造的可复用基础。
- 资源、Builder阶段、建筑上限和波次仍存在team或全局单例状态，尚未迁移。
- 地图源存在`template_map.vmap`和`survival_dev.vmap`，当前只确认历史波次marker `monsterborn`，尚未建立4套玩家marker。
- 旧`CURRENT_TASK.md`与旧`START_HERE.md`已归档为`docs/ai/archive/2026-08-06-pre-multiplayer-*.md`，不得作为活跃任务恢复。

## 尚未确认

- Hammer中东南西北4个玩家槽位的最终位置和marker名称。
- 当前Dota版本下未发布addon的最佳两客户端加入入口，需要在阶段2用两台机器实测。
- 支援击杀的成长和额外奖励归属，阶段6前必须由用户确认或写入CSV规则。
- 同一挑战是否允许多名玩家并发进入同一个挑战实例，阶段7前确认。
- 正式档案键直接使用Steam Account ID，还是由后端映射为自有账号ID。

## 下一步唯一动作

完全冷启动Workshop Tools：启动`start_fishing_api.ps1 -Automation9001`，在服务端设置`survival_player_profile_provider http_fishing`、`survival_fishing_api_token <本机FISHING_API_TOKEN>`和`survival_fishing_reward_fixture automation_9001`，验证真实Steam Account ID档案加载、相邻心跳累计、重复请求、断线重连、API重启和Supabase故障恢复。生产奖励CSV仍全禁用，不得作为正式奖励验收；Automation 9001 仅限Tools Mode。

## 恢复顺序

1. `docs/ai/START_HERE.md`

2. `docs/ai/CURRENT_TASK.md`
3. `docs/ai/PROJECT_CONTEXT.md`
4. `docs/ai/DECISIONS.md`
5. `docs/ai/KNOWN_ISSUES.md`
6. 涉及肉鸽卡牌、效果运行时、奖励 UI 或调试命令时读取`docs/ai/ROGUE_REWARD_INTEGRATION.md`
7. 涉及波次模型加载、预载或换模时读取`docs/ai/WAVE_MODEL_LOADING_TROUBLESHOOTING.md`和`docs/ai/WAVE_MODEL_RESOURCE_LIFECYCLE.md`
8. 仅需历史证据时读取`docs/ai/SESSION_LOG.md`和`docs/ai/archive/`

恢复后先向用户复述当前阶段、最后检查点、未知项和下一步，再修改代码。
