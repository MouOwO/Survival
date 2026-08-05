# Current Task

## 活跃任务（2026-08-05）：N1–N5怪物难度与CSV架构重构

- 用户要求整理N1–N5难度并大规模重构怪物CSV：不同难度的每波属性和组成均可不同；同波可包含普通怪、模型略大的首只领头怪（工作簿称“首怪Boss”）和明显更强、更大的进攻Boss；特殊目标、野外/副本Boss、转生Boss及十戒Boss也必须按N1–N5变化。
- 用户提供权威研究工作簿：`C:\Users\a\Documents\xwechat_files\wxid_4b1ytiieiibm21_17c7\msg\file\2026-08\N1-N5最终逻辑属性对照_倍率同步版(1).xlsx`。工作簿只读，不作为运行时依赖；最终业务权威必须落入`data/csv/`并通过生成工具生成Lua。
- 已确认行为：全部特殊目标和Boss跟随本局开局选择的全局难度；每次遭遇开始时固定`difficulty_id`快照，刷新、阶段切换和完成前不得改变。
- 已确认架构问题：当前`wave_definitions.csv`只有N1；N2由统一倍率派生；N3/N4禁用且无N5；当前Schema不能表达不同难度组成、领头怪与进攻Boss双身份；正式波次忽略CSV的`spawn_interval`；挑战/转生/十戒当前不读取全局难度。
- 已批准方案：CSV化难度定义；拆分波级元数据和波内成员；角色使用`normal/wave_leader/assault_boss`；建立统一难度化遭遇战斗Profile；原型主要保存外观和通用行为；移除统一倍率作为实际数值来源；按N1迁移、N2–N5接入、遭遇难度快照、时序/模型覆盖和完整验证分阶段实施。
- 数据状态边界：工作簿中的“面板确认/顺序确认/规律推定/待复核”等证据状态必须保留，不能把推定值描述为用户确认值。N1仅25个正常波次，N2–N5为30波；提前终局不得伪装成N1正常第30波。
- 当前阶段：用户已批准进入Act模式。先建立标准库OOXML导入审计、CSV Schema和N1迁移基线，再进入生产运行时修改。
- 工作区保护：当前已有19个Panorama编译产物、4个粒子编译产物和一批未跟踪测试/日志文件；这些均不是本任务修改，连续两次状态检查已稳定，禁止触碰或回滚。
- 尚未验证：工作簿各表到规范化CSV的完整映射、全部难度波次组成来源、N1第15波进攻Boss差异、运行时行为、Lua测试及Workshop Tools实机表现。
- 下一步：实现无第三方依赖的OOXML审计工具，输出工作表Schema、状态与异常；据结果定义并生成首批规范化CSV，同时建立生成与迁移契约测试。
- 最新检查点：`tools/audit_n1_n5_workbook.py`已使用Python标准库完成严格OOXML只读审计，输出`N1_N5_WORKBOOK_AUDIT_PASS`，Python语法和严格UTF-8通过。实际第8张表为“本次修正记录”，不是“各难度波次记录”。工作簿只有逐波最低小怪、首怪Boss、进攻Boss属性及特殊目标/转生/十戒属性，没有每波模型、怪种、数量、生成组和生成顺序明细；总览的N1小怪合计202、N2–N5各1270不能反推出组成。
- 当前阻塞：用户明确要求不同难度波次组成不同，但现有工作簿缺少组成权威数据。确认组成来源前不得擅自复制N1、按总数分配或从属性推断模型/数量。
- 用户新增计时规则：选择难度后才开始计时，第一波首只怪在150秒后出现；当前波1–9到下一波首只怪间隔90秒；当前波10起到下一波首只怪间隔150秒，用户已明确10→11也是150秒。波内全部怪生成所花时间不作为波间计时依据。当前`wave_system.lua`在上一波全部生成后才倒计时，必须改为绝对的首只到首只调度。
- 用户新增怪物规则：某个待定位波次包含飞行怪，其护甲为该波“当前护甲”的3倍，CSV备注写“飞行高护甲怪”。现有N1第11/13/16/24波均含混合飞行怪，另有纯飞龙波，当前消息未附新表且未给难度/波次，禁止猜测目标行和“当前护甲”的具体基准。
- 计时阶段实施完成：新增`wave_timing_rules.csv`作为唯一权威，配置为选难度后150秒首波、当前波1–9到下一波90秒、当前波10起到下一波150秒；`wave_system.lua`改为每波开始时立即安排下一波，生成完成不再重新倒计时，因此波内数量不影响相邻首怪时刻。旧`difficulty_config.initial_wave_delay=30`已移除。
- 计时验证完成：`WAVE_TIMING_LUA51_PASS`、`WAVE_TIMING_CONTRACT_PASS`、`WAVE_TIMING_FINAL_LUAC51_PASS`、`WAVE_TIMING_FINAL_GENERATED_COMPARE_PASS`、严格UTF-8和限定`git diff --check`通过；生成注册表已加入`wave_timing_rules`并通过Lua 5.1语法。尚未进行Workshop Tools实机计时验证。
- （已由后续用户提供N3工作簿并批准实施的记录取代）下一步唯一输入：用户重新上传飞行高护甲怪所在波次的表格/截图并注明难度和波次。收到前不修改具体怪物属性或N2–N5组成。
- 用户随后提供`N3按最新波次总表同步(1).xlsx`并批准接入N3：第1–25波沿用N1同波模型，第26–30波依次沿用N1第21–25波模型；同波地面/飞行成员按来源数量比例使用最大余数法确定性分配。工作簿要求飞行但来源波没有飞行原型时，用户确认统一回退`flying_red_gargoyle`。
- N3数量与角色子阶段已实施：`wave_definitions.csv`新增89条N3成员行，普通小怪1270、`wave_leader`27、`assault_boss`6，游戏计划总数1303；角色生成顺序为领头怪→普通怪→进攻Boss。N3第1–10波普通怪各14、第11–29波各59、第30波9；5/10/15/20/25/30波各有1只进攻Boss。
- N3飞行规则已实施：工作簿`AD/AE/AF`分别作为飞行普通怪、飞行领头怪和飞行进攻Boss审计口径；普通飞行成员使用该波War3基准护甲3倍，并在CSV备注“飞行高护甲怪”。领头怪/Boss使用工作簿各自独立护甲，不重复套三倍。
- 护甲显示边界已强化：波次怪保存`survival_war3_armor`和Dota运行时`survival_armor`，写入引擎仅执行一次`War3/3`；普通选中单位UI继续读取当前有效Dota护甲并由统一投影乘回3，因此初始值等于CSV，受到加减甲后动态变化。
- N3已作为30波独立难度启用，`wave_difficulty_builder`在目标难度拥有完整直接CSV时不再从N1倍率派生；正式出怪开始消费成员`spawn_interval`，同时保留已完成的首怪到首怪绝对计时。
- 自动验证通过：`N3_WAVE_CSV_IMPORT_PASS`、独立CSV检查、`N3_WAVE_CONFIG_LUA51_PASS`、`N3_WAVE_CONTRACT_PASS`、`N3_LUAC51_PASS`、`N3_GENERATED_COMPARE_PASS`、波次计时回归、科技减甲状态/触发/契约回归、严格UTF-8和限定`git diff --check`。尚未进行Workshop Tools实机数量、模型、护甲UI和重叠波次验证。
- 当前插入修复（用户已批准实施）：点击敌方单位或树木后，人物属性UI仍显示上一个单位。静态根因是共享`SurvivalSelectionResolver.Resolve()`要求portrait也存在于玩家可控`GetSelectedEntities()`，敌方query单位因此被拒绝并回退旧可控单位，服务端没有收到新entindex请求。
- 已批准边界：新增只供HUD/query使用的`ResolveDisplayUnit()`，允许有效非占位portrait不属于可控选择集合；`combat_stats.js`的属性、名称、生命和快照链使用该入口，技能输入、Builder、Grid和建筑移动继续使用原`Resolve()`，不得让敌方query单位进入施法链。
- 插入修复已完成：`ui_bootstrap.js`发布独立`ResolveDisplayUnit()`，属性HUD可接受不属于玩家可控选择集合的有效敌方/树木portrait；`combat_stats.js`的属性覆盖、名称、等级、生命、请求、NetTable和事件响应过滤统一改用display身份。技能枚举、runtime owner、快捷键和施法校验继续使用原`Resolve()`可控身份。
- 自动验证通过：`SELECTED_UNIT_STATS_REFRESH_CONTRACT_PASS`、`ABILITY_INPUT_LIFECYCLE_CONTRACT_PASS`、`BUILDER_HERO_REPLACEMENT_CONTRACT_PASS`、相关服务端Lua 5.1语法、严格UTF-8以及game/content限定`diff --check`。`ui_bootstrap.js`和`combat_stats.js`强制定向编译各为`1 compiled, 0 failed, 0 skipped`。
- 尚未实机验证：Workshop Tools冷启动后在英雄/不同敌人/树木间快速切换，确认名称、生命、攻击、攻速和护甲立即对应当前portrait；同时点击敌人后按Q/W/E，确认技能输入仍属于原可控单位，不会进入敌方query单位。
- 当前插入修复（用户已批准实施）：转生挑战Boss未击杀时，对应转生商店条目必须记录为进行中并禁止再次购买；英雄从副本A进入副本B后，副本A的延迟刷新不得把英雄拉回；普通材料Boss死亡刷新时保留英雄当前位置，只有`challenge_11`十宗罪/罪渊在仍为当前前台副本时允许按阶段入口重置位置。
- 已确认根因：商店活动遭遇投影只遍历普通`challenge_definitions`，遗漏`rebirth_challenges`；挑战session按玩家+encounter并存但没有唯一前台身份；可重复挑战完成后的2秒刷新回调无条件调用`teleport_to_current()`。
- 已批准边界：转生进行中门禁在服务端购买校验和商店快照同时生效且不得重复扣费；普通副本自动刷新怪物但不移动英雄，主动从商店重进仍传送；`challenge_11`仅在仍为前台session时保留自动阶段传送，离开后旧回调不得拉回。
- 插入修复已完成：`challenge_definitions.csv`新增完成刷新传送策略，普通挑战统一`preserve_position`，仅`challenge_11`为`reset_to_stage_entry`；每玩家前台遭遇身份同时消费普通挑战主动进入和转生Boss成功进入事件，延迟回调校验session、generation及前台身份。商店活动投影纳入`rebirth_challenges`，转生进行中在快照与购买扣费前双重拒绝。
- 自动验证通过：`CHALLENGE_SESSION_FOREGROUND_CONTRACT_PASS`、`CHALLENGE_SESSION_FOREGROUND_LUA51_PASS`、`CHALLENGE_SESSION_CROSS_SERVICE_LUAC51_PASS`、`ADDMONSTER_MOVE_SPEED_CONTRACT_PASS`和定向生成逐字节一致性通过。行为测试覆盖普通Boss保持位置、十宗罪前台阶段重置、进入转生后旧十宗罪回调不拉回及转生活动商店禁用。尚未进行Workshop Tools冷启动实机验证，不得记录为用户验收完成。
- 当前N1-N5主任务继续实施：用户于2026-08-05批准将本机`N4完全正确_倍率同步(1).xlsx`和`N5完全正确_倍率同步(1).xlsx`按已批准N3逻辑接入。N4/N5均使用独立30波CSV；1-25波沿用N1同波模型，26-30波沿用N1第21-25波模型；混合模型按来源数量比例确定性分配；缺少飞行原型时回退`flying_red_gargoyle`；普通飞行怪使用当波普通War3基准护甲3倍；领头怪、普通怪、进攻Boss依次生成，并保留工作簿证据状态。
- N4/N5接入与难度选择UI已完成生产实现：权威CSV和生成Lua各新增N4/N5独立89条成员行；`difficulty_config.lua`启用N4并新增N5直接配置；导入器支持N3-N5并保留工作簿证据状态。开局选择为N1-N5五格横向一排，单格228x72、间距12px，弹窗宽1280px；卡片不再创建或显示描述小字，只保留难度名称和波次数。
- N4/N5自动验证通过：`N4_WAVE_CSV_IMPORT_PASS`、`N5_WAVE_CSV_IMPORT_PASS`、`N4_N5_WAVE_CONFIG_LUA51_PASS`、`N4_N5_WAVE_CONTRACT_PASS`、N3与计时回归、`N4_N5_FINAL_LUAC51_PASS`、生成逐字节一致性、严格UTF-8和game/content限定`diff --check`。`survival_ui.js`与`survival_hud.css`均经Resource Compiler强制定向编译为`1 compiled, 0 failed, 0 skipped`。尚未进行Workshop Tools冷启动实机验证，不得记录为用户验收完成。

---

## 当前状态

- 极寒之刃批量击杀进度修复已由用户在Workshop Tools实机确认“修改成功”，本任务完成，不再恢复为待验收或活跃任务。稳定实现只消费权威`ENGINE_ENTITY_KILLED`，不按可复用victim entindex跨生命周期去重；攻击者沿有界owner链解析玩家归属。服务端快照把实际equipment kill progress与生成武器CSV目标统一投影为标准count/target/remaining，因此物品数字、Tooltip与成长HUD使用同一权威值。自动测试、Lua语法、UTF-8和限定diff均已完成；现有无关全量基线失败及未触碰的Panorama/粒子资产保持原状。等待用户指定下一项任务。

## 已完成任务（2026-08-05）：恢复空格镜头定位并修复挑战镜头回弹

- 用户最新实机确认：空格镜头运动已经正常，但进入挑战后镜头仍会回到英雄传送前消失的位置；此前“挑战不再回弹”的判断被最新反馈推翻。
- 最新根因：项目没有保存或恢复传送前英雄坐标的业务变量。`survival_ui.js`和`shop_ui.js`挑战链先调用`GameUI.SetCameraTarget(hero)`临时锁定英雄，再调用`GameUI.SetCameraTarget(-1)`解除；Dota解除目标后恢复锁定前的自由镜头锚点，表现为回到英雄消失处。
- 用户批准删除整段挑战锁定/释放链。当前实现改为一次性`MoveCameraToEntity(hero)`非锁定聚焦，API缺失或异常才按服务端从CSV入口投影的坐标调用`SetCameraTargetPosition`；挑战CSV、服务端传送和怪物生成保持不变。
- 自动验证完成：`CAMERA_FOCUS_CONTRACT_PASS`、`ABILITY_INPUT_LIFECYCLE_CONTRACT_PASS`、`ui_request_router.lua` Lua 5.1语法和目标文件严格UTF-8通过；`survival_ui.js`与`shop_ui.js`均强制编译为`1 compiled, 0 failed, 0 skipped`。仍需Workshop Tools冷启动实机确认挑战日志为`camera_follow_settled reason=non_locking_focus move_camera_api=function camera_result=move_to_entity`且镜头不再返回英雄传送前位置。
- 用户最终验收：2026-08-05用户明确确认“相机问题已经解决”。空格镜头运动和挑战传送后的镜头停留均视为Workshop Tools实机通过；上条“仍需冷启动确认”由本条验收结果关闭。
- 历史第二轮反馈（已被上方最新实机反馈推翻）：挑战进入日志曾完整出现`camera_follow_start`与`camera_follow_settled reason=arrived camera_result=target_position`，当次未观察到回弹；空格日志持续为`space_select ... camera_result=target_position`，但镜头只缓慢移向英雄。
- 当前Panorama声明确认`SetCameraTargetPosition(vec3, flLerp)`第二参数为插值值，但未定义单位或`0`的特殊语义；当前客户端实机已证明`0.0`不是瞬移。声明同时提供`MoveCameraToEntity(entindex)`，语义为移动到实体但不锁定；Valve本机`npx_2019`示例也使用实体target完成即时聚焦。
- 空格第三版已实施并通过自动验证：选择合法Builder/正式英雄后优先调用`MoveCameraToEntity(target)`，仅在API缺失或抛错时回退`SetCameraTargetPosition(origin, 0.0)`；服务端诊断包含`move_camera_api`，主路径结果为`camera_result=move_to_entity`。用户已确认空格镜头运动正常。
- 用户对第一版修复的最新实机反馈：空格仍不定位、挑战仍回弹，并且普通Workshop Tools服务端控制台没有`[SURVIVAL_SELECTION]`或`[SURVIVAL_CAMERA]`。两组旧日志均为Panorama `$.Msg()`，没有服务端镜像；第一版使用的`GameUI.SetCameraLookAtPosition`也不是当前项目可确认的Dota Panorama接口，并被存在性判断静默跳过。Resource Compiler只证明JS可编译，不能证明运行时API存在。
- 第二版实施完成：三条生产镜头链统一改用`GameUI.SetCameraTargetPosition(position, 0.0)`。空格选择合法Builder/正式英雄后直接定位；挑战共享控制器解除临时`SetCameraTarget`后下一帧落定服务端入口坐标；`shop_ui.js`共享控制器缺失的fallback也不再等待5秒后直接释放回旧位置。旧`SetCameraLookAtPosition`已从三条生产链移除。
- 新增服务端可见`ui_client_diagnostic`：只接受`hud_ready/space_select/camera_follow_start/camera_follow_settled/camera_fallback`白名单阶段，按事件注入的`PlayerID`确定玩家，控制字符替换且单字段限制160字符。实机统一查看`[SURVIVAL_CLIENT_DIAGNOSTIC]`；`camera_api=function camera_result=target_position`才是当前客户端调用成功的证据。
- 第二版自动验证：`CAMERA_FOCUS_CONTRACT_PASS`、输入/Builder契约和`ui_request_router.lua` Lua 5.1语法通过；`ui_bootstrap.js`、`survival_ui.js`、`shop_ui.js`均强制编译为`1 compiled, 0 failed, 0 skipped`。仍需冷启动实机确认API能力、空格定位与首次/重复挑战停留。
- 用户实机反馈：上一轮占位英雄空格保护完成后，按空格只能选中合法单位，缺少Valve默认的镜头定位；购买挑战并传送英雄时，镜头先到英雄处，约0.2秒后又回到传送前位置。
- 静态根因已确认：`ui_bootstrap.js`将`SPACE`覆盖为generation fallback command后只调用`GameUI.SelectUnit()`，没有复刻镜头行为；`survival_ui.js`挑战聚焦使用`SetCameraTarget(hero)`临时跟随，到达后直接`SetCameraTarget(-1)`，解除跟随后自由镜头恢复旧锚点。服务端先生成挑战、再按`challenge_locations.csv`入口传送并回传坐标，传送与CSV链无异常。
- 第一版实施记录（已被第二版替代）：曾使用`SetCameraLookAtPosition()`尝试落定自由镜头；自动契约与编译通过，但用户实机确认两个行为均未生效。该结果不得恢复为有效方案。

## 活跃任务（2026-08-04）：未召唤英雄时屏蔽空格选中占位英雄

- 用户最新实机反馈：尚未通过祭坛召唤正式战斗英雄时按空格，会重新选中隐藏的开局 Undying 占位英雄，HUD 显示“建造者”、原生属性和技能；该内部替换锚点不能被玩家选中或通过空格暴露。
- 修复必须从 Builder CSV 身份、占位英雄生命周期、现有选择恢复和 Panorama 全局按键入口核对；仅在 `placeholder/replacing` 阶段屏蔽占位英雄选择，正式英雄召唤后空格选择英雄必须恢复正常，且不得使用会阻止建筑、工人、Builder 或正式英雄正常选择的永久全局 Selection Override。
- 当前仅有 Workshop Tools 截图证据；现有占位 Modifier 已声明 `MODIFIER_STATE_UNSELECTABLE`，但实机证明 Valve 默认主英雄选择仍可直接选中引擎占位英雄。当前确认需由 Panorama 唯一输入所有者接管 `SPACE`：占位阶段选择 CSV Builder，正式替换后选择引擎正式英雄；同时兼容 `SetKeyPressedCallback` 不可用时的 fallback keybind。
- 实施完成：`ui_bootstrap.js` 注册最高优先级 `placeholder_space_guard` 并把 `SPACE` 纳入 generation fallback keybind。按空格时读取引擎主英雄：仍为 Undying 占位锚点则只选择 `survival_builder_identity` 发布的 Builder，身份尚未到达时也消费输入并阻止穿透；替换完成后选择正式英雄。未使用轮询或 `SetOverrideSelectionEntity`。`custom_net_tables.txt`同步补齐既有 Builder 身份表声明。
- 自动验证通过：`ABILITY_INPUT_LIFECYCLE_CONTRACT_PASS`、`BUILDER_HERO_REPLACEMENT_CONTRACT_PASS/LUA51_PASS`、占位服务 Lua 5.1 语法和 `ui_bootstrap.js` Resource Compiler 强制编译（`1 compiled, 0 failed, 0 skipped`）。尚需 Workshop Tools 完全停止后 Run，分别在召唤前后按空格确认选择目标；自动契约与编译不能替代引擎输入验收。

## 活跃任务（2026-08-04）：小游侠同步新版多目标出手逻辑

- 用户要求黑暗游侠召唤的小游侠从旧版“主箭命中后补射”同步为新版“正式出手时主箭与另外4箭并列发射”。权威`hero_skill_definitions.csv`保持固定总计5目标，不改继承攻击/攻速、持续时间、无敌或Tooltip。
- 根因是tracker的`OnAttackLanded`仍调用`on_drow_companion_attack_landed()`。修复还必须阻止小游侠发布英雄`HERO_MAIN_ATTACK_FIRED`，否则会错误消费owner的转生3～6目标逻辑并与自身固定5目标叠加。
- 最小实现：tracker在`OnAttack`优先按`survival_drow_companion`分流，只有非次级主攻击调用召唤物出手函数，随后返回；落地阶段仅清理次级record。补专项行为/递归测试及契约，保留所有真实普通攻击独立结算。
- 实施与自动验证完成：小游侠现在在`MODIFIER_EVENT_ON_ATTACK`调用固定五目标逻辑，落地阶段不再补射，也不发布英雄转生出手事件。专项嵌套行为、相关攻击回归、免费英雄与多目标契约、Lua 5.1语法、CSV/运行配置/生成Lua一致性及严格UTF-8通过。下一步Workshop Tools冷启动确认视觉同步和真实独立结算。

## 活跃任务（2026-08-04）：转生多目标普通攻击改为并列发射

- 用户批准将一转后多目标普通攻击从“主目标命中后补射”改为“主攻击正式出手时同时向主目标和其他目标发射”。一至四转总目标3/4/5/6、包含主目标、各目标独立普通攻击结算以及次级攻击不触发项目主攻击业务的既有规则不变。
- 静态根因：`hero_progression_system.lua::trigger_multishot()`当前订阅`HERO_MAIN_ATTACK_LANDED`，在主箭真实命中后才调用次级`PerformAttack()`。批准方案是在攻击追踪Modifier的`MODIFIER_EVENT_ON_ATTACK`阶段发布新的主攻击出手事件，次级record不得发布该事件，成长、技能、装备和研究等命中消费者继续留在`HERO_MAIN_ATTACK_LANDED`。
- 黑暗游侠Buff图标与多目标逻辑分开处理。项目已检查的基础Modifier均隐藏；原生Ability被保留但隐藏停用，可能仍有intrinsic modifier。本轮只输出黑暗游侠可见Modifier及来源Ability诊断，未唯一确认前不删除任何Modifier。
- 实施完成：`HERO_MAIN_ATTACK_FIRED`由攻击追踪Modifier在`MODIFIER_EVENT_ON_ATTACK`发布，多目标处理只订阅该事件；同步次级标志与secondary record共同防递归。真实命中事件及其成长、公共技能、装备和研究消费者未迁移。
- 自动验证通过：多目标Lua 5.1行为/递归模拟、PowerShell契约、相关攻击与猴王回归、目标Lua 5.1语法、CSV与生成Lua一致性及严格UTF-8。尚需Workshop Tools冷启动确认视觉时点，并提供`[DROW_VISIBLE_MODIFIER]`日志归因Buff图标。

## 活跃任务（2026-08-04）：祭坛召唤英雄按钮无法点击

- 用户最新实机反馈：祭坛当前无法召唤英雄，表现为祭坛技能按钮无法点击；要求优先修复。
- 当前仅确认 UI 输入症状，尚未确认断点位于祭坛 CSV/生成配置、Ability runtime 发布、Panorama 按钮接管、服务端祭坛动作路由或 `ReplaceHeroWithNoTransfer()`。调查必须从 `data/csv/商店系统/altar_actions.csv` 权威源开始，并沿生成配置、祭坛 Ability、runtime owner、统一 `SurvivalAbilityInput` 和英雄替换链逐段核对。
- 修改边界：只修复祭坛召唤直接相关逻辑并补专项回归；保留当前 Builder、建筑 Grid、普通英雄 Ability 与科技研究行为，不清理两仓既有修改。
- 已确认权威链：`altar_actions.csv::altar_select_hero`只描述选择语义，实际召唤规则来自`hero_summon_rules.csv`，六个英雄Ability来自`buildings_config.lua`和`hero_summon_projection.lua`映射。CSV/生成Lua、Ability KV、祭坛Ability列表均存在，不能通过给`altar_actions.csv`伪造Ability修复。
- 静态根因：项目已经明确记录`npc_dota_creature`建筑的动态Lua Ability通过`CastAbilityNoTarget()`不可靠进入`OnSpellStart`，服务端路由已为塔、普通升级和金矿提供直接权威分发，但遗漏`ability_summon_*`，因此祭坛点击即使到达统一输入也可能只产生无效原生施法命令。
- 当前修复：`hero_summon_projection`暴露现有Ability到hero_id反向查询；`ui_request_router`验证祭坛身份、Ability归属、玩家ownership和可施放状态后直接请求`HERO_SUMMON_REQUEST`，失败回滚冷却并通知；客户端显式将召唤和祭坛旅行Ability列为托管建筑动作，避免runtime短暂缺失时回退原生路径。专项契约与严格UTF-8通过，`combat_stats.js`单文件编译为`1 compiled, 0 failed, 0 skipped`，完整HUD链为`9 compiled, 0 failed, 0 skipped`。
- 最终自动验证：`ALTAR_SUMMON_INPUT_CONTRACT_PASS`、`BUILDER_HERO_REPLACEMENT_CONTRACT_PASS/LUA51_PASS`、`FREE_HERO_REPLACEMENT_CONTRACT_PASS`、目标生产Lua的`ALTAR_LUAC51_PASS`、严格UTF-8和两仓限定`git diff --check`均通过。尚未称为实机验证；下一步完全Stop后Run，选中祭坛点击任一免费英雄，确认客户端`SEND_NO_TARGET`、服务端`ALTAR_SUMMON_DISPATCHED hero=<id> ok=true`、占位英雄替换和正式英雄选中。
- 独立遗留：当前磁盘`scripts/custom_net_tables.txt`缺少`survival_builder_identity`，导致既有`test_ability_input_lifecycle_contract.ps1`在`BUILDER_IDENTITY_NETTABLE_UNDECLARED`失败；该表不参与祭坛召唤路由，本轮未把Builder NetTable修复混入当前任务。

## 活跃任务（2026-08-04）：Undying 建造者代理与祭坛英雄替换首版

- 最新实机反馈：用户确认“现在可以正常建造”，因此 Builder 注册 ownership、Grid validate/commit 和 Building 创建主链已通过 Workshop Tools 实机验证。仍需用户后续按需要确认选中城墙 Q 是否稳定执行 `ability_upgrade_wall`、最终 Q/W/E/R/T+D 布局及连续第二次 Run 输入生命周期；这些未确认项不得写成已验收。
- 冲突收尾：`ability_tooltip.vjs_c`、`building_move.vjs_c`、`combat_stats.vjs_c`、`game_info_panel.vjs_c`、`survival_grid_placement.vjs_c`、`survival_ui.vjs_c` 曾为 Git `UU` 二进制冲突。6 个文件均以对应当前 content JS 源强制重编译，结果各 `1 compiled, 0 failed, 0 skipped`，再仅对这 6 个产物执行 `git add` 清除 unmerged stages；当前均为普通 stage 0 修改，没有 merge commit。
- 最新 ownership/槽位/建筑选择修复已完成生产实现与自动验证：普通 creature Builder 不再依赖 `GetPlayerOwnerID()`，`builder_service` 按注册实体返回权威 `player_id/team`，Grid validate/commit 与 Building 创建链均校验同一注册 Builder 并传播玩家 ID；建筑和 Builder 将权威 ID 保存为 `survival_player_id`，建筑 no-target Ability 路由优先读取该字段。CSV `slot_order` 现显式投影建造技能 index `0..4`，Blink 保留 index `5`，项目输入语义为 Q/W/E/R/T + D。
- Panorama Grid 和建筑移动不再读取 Portrait-only 选择，统一使用 `SurvivalSelectionResolver`；托管 Ability 要求 runtime owner 与当前解析选择一致，选中城墙后不得回退 Builder。fallback keybind 新增 command/apply/trigger 诊断。`builder_ability_rules.csv` 经审计当前无运行消费者且仍使用陈旧 `building_wall/building_main_city` 业务 ID，本轮未把它当作运行权威、也未扩大无消费者表迁移。
- 验证通过：`BUILDER_OWNERSHIP_LUA51_PASS`、`BUILDER_ABILITY_SLOTS_LUA51_PASS`、`BUILDER_HERO_REPLACEMENT_LUA51_PASS/CONTRACT_PASS`、`ABILITY_INPUT_LIFECYCLE_CONTRACT_PASS`、Builder utility、Alt Ability 契约、相关 Lua 5.1 语法、严格 UTF-8 和限定 diff；`ui_bootstrap.js`、`combat_stats.js`、`survival_grid_placement.js`、`building_move.js` 均强制编译为 `1 compiled, 0 failed, 0 skipped`。尚未 Workshop Tools 实机验证，下一步冷启动后验证 Q 城墙 Grid、提交、城墙可控、选中城墙 Q 升级、最终 Q/W/E/R/T 与 D Blink。
- 用户已批准继续修复占位实体碰撞/选择与 Grid 永久等待，并允许在不能唯一定位时增加完整请求级日志后提供实机日志复查。当前新增静态根因：占位隔离未设置不可选择、无单位碰撞和无移动能力；Grid caster/Ability 早期失败响应使用默认 anchor `(0,0)`，会被客户端当前 anchor 过滤并永久显示“正在验证建筑占地……”。实施边界为专用生命周期隔离 Modifier、Grid session/request 权威响应与状态变化日志，不改变 CSV Builder 身份、64码网格或英雄替换架构。
- 本轮实施与自动验证已完成：新增 `modifier_survival_placeholder_anchor`，占位锚点现在不可选择、无单位碰撞、命令受限、不可移动、无血条且不上小地图；`hero_anchor_service` 仅在 placeholder 注册/重生/替换失败回滚时应用。Grid 服务端所有已接受 validate 请求均回显原请求 anchor 与 session/request/Ability 身份，客户端按请求 anchor 接收错误结果，不再把 caster/Ability 早期错误静默丢弃；客户端与服务端新增完整请求级诊断。
- 验证通过：`BUILDER_HERO_REPLACEMENT_LUA51_PASS`、`BUILDER_HERO_REPLACEMENT_CONTRACT_PASS`、`ABILITY_INPUT_LIFECYCLE_CONTRACT_PASS`、`BUILDER_UTILITY_CONTRACT_PASS`、`ALT_HERO_ABILITY_ORIGIN_DEV_CONTRACT_OK`、相关生产 Lua `luac5.1 -p`、生产/测试目标文件严格 UTF-8且无替换字符、本轮文档新增行无替换字符、game/content 限定 `git diff --check`；`survival_grid_placement.js` 强制编译为 `1 compiled, 0 failed, 0 skipped`。`SESSION_LOG.md` 整文件仍保留已记录的3个历史 `U+FFFD`，本轮未猜测改写。尚未称为实机验证，下一步完全停止后 Run，测试移动碰撞、W与图标、网格与提交；若仍失败，提供同一次操作的 `[SURVIVAL_INPUT]`、`[SURVIVAL_CAST]` 和 `[GridPlacement][CLIENT/SERVER]` 日志。
- 最新 Workshop Tools 实机失败：开局同时出现基础模型 Builder Proxy 与仍带原生技能/可残留 wearable 的占位 Undying；只有鼠标点击建造图标能进入 Grid，Q/W/E/R 快捷键不能建造。用户已批准按静态根因分析继续修复。
- 已确认根因：`AddNoDraw()`与地下移动没有隔离占位英雄的 wearable、控制/选择和 Portrait 身份；快捷键又在解析 Ability entindex 前从 `GetLocalPlayerPortraitUnit()` 枚举可见技能，因此可能先取得占位 Undying 原生 Ability，后续 runtime owner 无法纠正错误 Ability 身份。当前实施边界是完整隔离占位英雄、发布权威 Builder entindex，并让点击/快捷键共用基于实际选择集合的单位解析；不使用永久 Selection Override。
- 本轮生产修复已完成：`hero_anchor_service.isolate_placeholder()` 在注册、重生和替换失败回滚时统一隐藏占位主体及所有 `dota_item_wearable`、取消玩家控制、禁攻并移至地下；仅 `placeholder` 阶段允许执行，不会隐藏 `combat_ready` 正式英雄。`builder_service.lua` 向 `survival_builder_identity[player_<id>]` 发布 CSV Builder entindex。
- `ui_bootstrap.js` 新增唯一 `SurvivalSelectionResolver`：读取 `Players.GetSelectedEntities()`、Portrait 和权威 Builder；实际选中 Builder 时拒绝占位 Undying Portrait，建筑/工人/正式英雄选择仍保持当前单位。`combat_stats.js` 与 `ability_tooltip.js` 共用该解析器；快捷键诊断现输出 dispatcher generation、selection、portrait、resolved unit/name、Builder、display slot、Ability name/entindex 和 runtime owner。
- 自动验证通过：Builder 替换/输入生命周期/工具技能/Alt/免费英雄替换 PowerShell 契约，Builder Lua 5.1 隔离与生命周期行为，相关生产 Lua 的 `luac5.1` 语法，Builder CSV/生成 Lua 身份一致性，严格 UTF-8，以及 game/content 两仓限定 `git diff --check`。`ui_bootstrap.js`、`ability_tooltip.js`、`combat_stats.js` 强制编译均为 `1 compiled, 0 failed, 0 skipped`。首次 CSV 临时检查误把 `#中文表头/#types` 元数据算作业务行，修正过滤规则后通过，未修改数据。
- 仍需完全停止 Workshop Tools 后连续 Run 两次实机验证：画面只能看到可控 Builder Proxy；占位 Undying/wearable 不可见、不可选、不可通过 HUD/Portrait 暴露；Q/W/E/R 与相同图标都解析为 Builder 的 `ability_build_*` 并进入 Grid；D/F、建筑操作、建筑移动 D、普通选择及祭坛 `ReplaceHeroWithNoTransfer()` 正常。控制台必须能看到对应 `[SURVIVAL_INPUT] KEY` 和完整 `[SURVIVAL_CAST][CLIENT] HOTKEY` 身份日志。
- 用户已批准合并修复 Workshop Tools 输入回归：Builder 快捷键无效、建筑技能无法点击、Builder 建造绕过网格，以及第二次 Run 后 Q/W/E/R/T/Y/U 仅鼠标可用。生产修复和自动验证已完成：`ui_bootstrap.js` 每次 HUD generation 无条件重建唯一 Key/Mouse dispatcher 和 generation 专属 fallback keybind；业务模块按稳定 ID/优先级注册，不再依赖跨 Run 的 `*DispatcherBound` boolean 或匿名 handler 数组。
- `combat_stats.js` 先解析 Ability runtime 并验证 `owner_entindex` 确实拥有该 Ability，再将该 owner 固定为 caster；Builder 不再被 Hero-only UI 过滤。`ability_tooltip.js` 的官方技能透明代理覆盖 `ability_build_*` 和所有 runtime owner 为 `building_*` 的建筑操作，鼠标点击与快捷键进入同一个 `SurvivalAbilityInput.ExecuteAbility()`。
- 点目标状态固定 `unit/ability/name`；Grid session 从该状态读取 Builder 与 Ability，不再逐帧重新读取 Portrait Unit。`ability_build_*` 必须进入自定义 Grid，建筑升级/训练/祭坛/金矿操作保留建筑自身 caster。建筑移动 D 仅在当前选中可移动建筑时消费，否则继续分发给 Builder Blink。
- 自动验证通过：`ABILITY_INPUT_LIFECYCLE_CONTRACT_PASS`、`ALT_HERO_ABILITY_ORIGIN_DEV_CONTRACT_OK`、`BUILDER_HERO_REPLACEMENT_CONTRACT_PASS/LUA51_PASS`、`BUILDER_UTILITY_CONTRACT_PASS`、相关 Lua `LUAC_PASS`、严格 UTF-8 和限定 diff；6 个修改过的 Panorama JS 强制编译均为 `1 compiled, 0 failed, 0 skipped`。仍须在两次连续 Workshop Tools Run 中实机验证全部鼠标/键盘/网格/caster 流程，建筑 HUD anchor/count 假设也只能实机确认。
- 用户批准先实现一版验证：开局 Undying 只作为引擎主英雄占位符；独立 Builder Proxy 承接建造技能、Blink、修理和施工；祭坛选择英雄时使用 `PlayerResource:ReplaceHeroWithNoTransfer()` 将占位 Undying 替换为正式战斗英雄。
- 首版 Builder Proxy 使用普通自定义可控单位和 Undying 模型，不宣称 `IsCourier()==true`；待身份解耦和替换链实机稳定后，再单独验证真正 courier class，避免同时引入两个引擎变量。
- 必须保持 `HERO_SUMMONED` 事件契约不变，使现有技能、属性、装备、成长、奖励和 UI 消费者继续绑定替换后的正式英雄。
- 禁止使用永久全局 Selection Override；Builder 创建后仅一次性选中，不能阻止后续选择建筑、工人和战斗英雄。
- 当前阶段：首版生产代码与自动验证已完成，尚未完成 Workshop Tools 实机验证。Builder 为 `npc_survival_builder_proxy` 普通可控单位，权威身份来自 `data/csv/建筑与工人系统/builder_definitions.csv`；开局 Undying 隐藏并移至地下，仅保留为引擎替换锚点。
- `builder_service.lua` 提供 Builder 注册表和 `BUILDER_READY/BUILDER_GET_REQUEST`；阶段技能、修理 AI、Grid caster fallback 和 Ability Runtime 均已迁移。Builder 创建与正式英雄替换后各执行一次客户端 `GameUI.SelectUnit`，没有永久 Selection Override。
- `hero_anchor_service.lua` 管理 `placeholder/replacing/combat_ready`；`hero_summon_system.lua` 使用 `ReplaceHeroWithNoTransfer()`、重复请求锁和提交顺序保护，继续发布原格式 `HERO_SUMMONED`。
- 自动验证通过：`BUILDER_HERO_REPLACEMENT_CONTRACT_PASS`、`BUILDER_HERO_REPLACEMENT_LUA51_PASS`、`BUILDER_UTILITY_CONTRACT_PASS`、`ALT_HERO_ABILITY_ORIGIN_DEV_CONTRACT_OK`、`FREE_HERO_REPLACEMENT_CONTRACT_PASS`、相关 Lua 5.1 语法、Builder CSV/生成 Lua 一致性和限定 diff；两个 Panorama JS 均强制编译为 `1 compiled, 0 failed, 0 skipped`。
- 下一步必须完全停止并连续重新 Run Workshop Tools 两次，验证 Builder 首次选中、建筑/工人可切换、Q/W/E/R/T/Y/U、Builder D/F、建筑移动 D、F2/TAB、建筑按钮 caster、所有建造强制 Grid、替换后的 HUD/所有权/死亡复活/技能物品不转移。未经实机确认不得称为完成或真实 courier。
- 工作区已有未跟踪测试文件，本任务不得覆盖或清理。

## 已完成任务（2026-08-04）：齐天大圣E附伤确认与测试入口

- 用户于2026-08-04完成修复版Workshop Tools复测并确认数据正常：齐天大圣本体主普通攻击暴击时，全属性×5额外伤害已正常触发。本任务已实机验收完成，不再作为活跃任务恢复。
- 用户实机确认Bug：执行`unlock e`后原生暴击数字正常出现，但没有E的全属性×5额外伤害。此前自动测试只分别验证record暴击和E公式，没有覆盖实机`OnTakeDamage`、record生命周期、`OnAttackLanded`的先后顺序，不能再描述为E实机有效。
- 根因修复：E不再等到较晚的`HERO_MAIN_ATTACK_LANDED`重新读取可能已销毁的attack record；改为在最终`OnTakeDamage`已确认暴击身份并完成record+victim去重的同一时点发布`HERO_FINAL_CRITICAL_ATTACK_DAMAGE`。次级attack record在发布前排除，E继续只接受齐天大圣本体主攻击。
- E现在检查统一伤害事务`result.success`；失败输出`MONKEY_KING_E_DAMAGE_FAILED`及record、计算伤害和阻断原因，不再静默返回成功。
- 修复版自动验证通过：`MONKEY_KING_E_TRIGGER_LUA51_PASS`直接覆盖最终暴击事件→技能状态→逻辑三维快照→全属性×5→携带E Ability的纯粹伤害事务，并覆盖分身/锁定/事务失败；伤害飘字Lua/契约、猴王塔契约、QWE数学、unlock E、超级塔暴击、多目标和近战回归均通过。相关生产/测试Lua 5.1语法、CSV/生成Lua倍率5一致性、严格UTF-8和限定`diff --check`通过。
- 修复版Workshop Tools实机复测已通过；`unlock e`保留为后续回归测试入口。若未来回归，收集`MONKEY_KING_E_DAMAGE_FAILED`和`HERO_ATTACK_DAMAGE_NUMBER`日志。
- 用户已确认英雄原生伤害飘字做好；该任务已沉淀到`PROJECT_CONTEXT.md`，不再恢复为待视觉验收。
- 权威CSV与生成Lua确认E为6转技能，最终攻击独立×3；仅齐天大圣本体主普通攻击实际暴击时，对主目标追加触发瞬间逻辑全属性×5纯粹伤害。
- 已被实机推翻的旧实现：`monkey_king_exclusive_service.lua`曾消费`HERO_MAIN_ATTACK_LANDED.critical`；静态调用链虽携带`ability_survival_monkey_king_swiftness`，但跨事件读取record导致E未触发。该路径已由顶部最终伤害事件方案取代。
- 用户批准新增`unlock e`：仅对当前玩家已召唤的齐天大圣生效，只用正式技能授予请求把固定槽E从锁定Lv.0激活为Lv.1；不修改转生等级、不补发转生奖励，重复输入幂等成功。
- 已完成实现和自动验证：`UNLOCK_E_LUA51_PASS`、`MONKEY_TOWER_CONTRACT_PASS`、`ADDSKILL_CONTRACT_PASS`、`MONKEY_KING_QWE_LUA51_PASS`、英雄伤害飘字Lua/契约、超级塔暴击Lua/契约和英雄多目标回归均通过；相关生产与测试Lua 5.1语法、CSV/生成Lua E数值一致性、严格UTF-8及限定`diff --check`通过。
- 首轮Workshop Tools确认旧E路径失败；修复版随后由用户确认数据正常。两次结果均保留，用于区分旧路径失败与最终方案验收通过。

## 活跃任务（2026-08-04）：英雄普通攻击最终伤害飘字统一

### 最新批准的显示调整（2026-08-04）

- 用户确认普通攻击最终伤害显示为引擎普通字号红字；暴击最终伤害显示为约普通数字2倍大小的橙色粗体字，以颜色和尺寸同时区分。
- `SendOverheadEventMessage`没有字号参数，因此普通攻击继续使用`OVERHEAD_ALERT_DAMAGE`，暴击在最终伤害去重成功后改为仅向攻击者所属玩家发送Panorama自定义事件；暴击不得再发送引擎`OVERHEAD_ALERT_CRITICAL`，避免重复显示。
- Panorama按目标entindex读取世界位置并投影到屏幕，数字向上漂浮淡出；目标失效、离屏或生命周期结束时必须清理。
- 数值仍唯一来自`OnTakeDamage.params.damage`，不得修改暴击率、暴击倍率、伤害、护甲、技能隔离、attack record状态或多目标逐受击单位去重。
- 用户已批准实施；当前进入生产代码、Panorama源、定向资源编译、专项测试和回归验证阶段，尚未完成Workshop Tools实机验收。

### 用户确认的实机事实与口径

- 英雄面板攻击约`1115`；目标项目UI护甲约`3333`（对应约`1111` Dota运行时护甲，Dota内置面板约显示`1000`）。
- 普通平A最终扣血约`17`但没有白色飘字；暴击原生橙字显示减甲前`2564`，最终扣血和`OnTakeDamage`测试面板均为`38`。
- 现有伤害与护甲结算本身符合高护甲减伤预期；问题是Valve原生暴击字与项目最终伤害统计语义不一致，并且普通小额平A没有稳定飘字。
- 用户批准：保持`altar_actions.csv`训练目标现有护甲和所有单位各自护甲不变；所有召唤英雄普通攻击按`OnTakeDamage`最终实际扣血显示，普通攻击白字、暴击橙字，小额伤害也显示。

### 实施计划

1. 保留attack record唯一暴击掷骰，但移除会产生减甲前橙字的`PREATTACK_CRITICALSTRIKE`，改用仅作用于对应普通攻击record的攻击伤害倍率。
2. 在最终`OnTakeDamage`事件按同一record读取暴击身份，以最终实际伤害发送白色或橙色飘字，并在显示后清理record。
3. 本体、齐天大圣W分身与多目标次级攻击均按各自真实命中显示；技能和脚本伤害不得进入普通攻击飘字。
4. 增加Lua 5.1行为与PowerShell契约测试，并运行相关英雄攻击、分身、科技暴击回归、语法、严格UTF-8及限定差异检查。

### 当前结果

- 已完成生产代码：本体和齐天大圣W分身均按attack record掷骰并通过`DAMAGEOUTGOING_PERCENTAGE`应用暴击倍率，不再使用会产生减甲前Valve橙字的`PREATTACK_CRITICALSTRIKE`。
- 已完成最终飘字基础链：仅普通攻击record进入显示路径，使用`OnTakeDamage.params.damage`，按`record + victim`去重，多目标不同受击单位分别显示，技能伤害排除。最新显示层为普通引擎红字、暴击Panorama橙色2倍粗体字。
- 已保留`data/csv/商店系统/altar_actions.csv`训练目标`target_armor=100000`；契约同时锁定源CSV、生成Lua和训练服务消费者。选中面板继续显示引擎实际运行时护甲的War3投影，不强行显示CSV请求值。
- 自动验证通过：专项Lua/契约、英雄多重攻击、猴王QWE/近战/塔契约、超级塔暴击、研究减甲和多重攻击回归、Lua 5.1语法、严格UTF-8与限定`git diff --check`。
- 未完成Workshop Tools实机验证。下一步冷启动地图，确认普通最终`17`显示白字、暴击最终`38`显示橙字、旧减甲前`2564`不再出现，并检查本体、W分身、多目标及技能伤害无重复/误标。
- 首轮实机复测失败：用户观察到疑似首次暴击没有数字，且之后所有攻击数字停止显示；所提供日志无Lua错误段，包含真实攻击damage_category=nil。当前需取得暴击时刻附近的完整控制台错误或确认无错误，再区分暴击显示API异常与overhead队列互斥。
- 用户确认控制台完全无红色错误。已加入最多80条[HERO_ATTACK_DAMAGE_NUMBER]限次诊断，记录roll/show/dedup/clear、record、暴击身份、最终伤害和style；诊断版通过Lua 5.1行为、语法、契约、严格UTF-8和限定diff检查。下一步只需冷启动复现并提供该前缀日志。
- 最新实机日志已确认两个根因：`DAMAGEOUTGOING_PERCENTAGE`实机回调没有可用record，整轮没有任何`action=roll`，因此科技配置虽已进入英雄快照，但攻击消费层暴击实际等效0%；`addspeed`后Dota从0开始循环复用record，旧显示去重状态使新一代攻击连续进入`action=dedup`，解释暴击后所有飘字停止。
- 已按用户批准完成修复：本体和齐天大圣W分身在`ON_ATTACK_RECORD`按权威战斗快照掷骰，再由无record参数的outgoing getter消费本次攻击倍率；新record建立时重置同攻击者同编号上一代显示状态。暴击和显示状态键改为`attacker entindex + record`，避免本体、分身或多英雄相同record互相覆盖；最终显示仍按victim去重。
- 诊断`roll`现明确打印`chance`。权威CSV中`researcher_super_tower_crit_01/19/23`分别为`0.5%/9.5%/11.5%`；`addtechnology`设置传入科技ID的具体等级，不会自动加满。实机高概率验证必须使用`addtechnology researcher_super_tower_crit_23`，下一轮应看到`roll ... chance=11.5`。
- 修复版自动验证通过：`HERO_ATTACK_DAMAGE_NUMBERS_LUA51_PASS`、`HERO_ATTACK_DAMAGE_NUMBERS_CONTRACT_PASS`、`SUPER_TOWER_CRIT_LUA51_PASS`、`SUPER_TOWER_CRIT_CONTRACT_PASS`、`SUPER_TOWER_CRIT_GENERATED_COMPARE_PASS`、英雄多重攻击、猴王QWE/近战/塔、研究减甲回归、相关Lua 5.1语法和严格UTF-8。仍需冷启动Workshop Tools验证`roll → show → clear`引擎时序、暴击最终伤害翻倍以及record循环后持续飘字；自动测试不等于实机验收。
- 已完成最新显示层实现：普通攻击继续调用`OVERHEAD_ALERT_DAMAGE`显示普通字号红字；暴击不再调用`OVERHEAD_ALERT_CRITICAL`，只向攻击者所属玩家发送`survival_critical_damage_number`，负载为目标entindex和四舍五入后的最终伤害。Panorama使用48px橙色粗体字，逐帧跟随目标头顶、向上漂浮72px并在1秒内淡出清理。
- 新增Panorama源`critical_damage_numbers.js/css`并接入`survival_hud.xml`；Resource Compiler强制编译JS/CSS均为`1 compiled, 0 failed, 0 skipped`，HUD XML加载链为`7 compiled, 0 failed, 0 skipped`。
- 最新验证通过：`HERO_ATTACK_DAMAGE_NUMBERS_LUA51_PASS`、`HERO_ATTACK_DAMAGE_NUMBERS_CONTRACT_PASS`、`SUPER_TOWER_CRIT_LUA51_PASS`、`SUPER_TOWER_CRIT_CONTRACT_PASS`、`HERO_MULTISHOT_LUA51_PASS`、`MONKEY_KING_QWE_LUA51_PASS`、`MONKEY_MELEE_ATTACK_LUA51_PASS`、猴王塔/工人多目标契约、相关生产Lua 5.1语法、严格UTF-8和限定`git diff --check`。仍需Workshop Tools冷启动确认实际字号约2倍、橙色位置、杀怪时显示、无重复、连续暴击和record循环后持续显示。
- 用户随后改为要求全部使用原生字体，并批准最终分流：普通攻击使用`OVERHEAD_ALERT_BONUS_SPELL_DAMAGE`作为白字候选，暴击使用`OVERHEAD_ALERT_CRITICAL`恢复原生暴击字体/动画，带有效`params.inflictor`的正式技能伤害使用已确认醒目的红色`OVERHEAD_ALERT_DAMAGE`；无Ability的脚本或装备附伤不进入技能飘字。
- 原生显示仍只消费最终`OnTakeDamage.params.damage`；没有恢复会显示减甲前伤害的`MODIFIER_PROPERTY_PREATTACK_CRITICALSTRIKE`。普通攻击继续按`attacker + record + victim`去重，本体和齐天大圣W分身共用同一规则；上一版`survival_critical_damage_number`事件、Panorama源、HUD引用和编译产物已移除。
- 最新原生分流验证通过：专项Lua 5.1行为/契约、超级塔暴击、英雄多目标、猴王QWE/近战/塔、相关Lua 5.1语法和严格UTF-8均通过；`survival_hud.xml`强制资源编译为`OK: 7 compiled, 0 failed, 0 skipped`。Valve公开文档未记录`BONUS_SPELL_DAMAGE`的视觉颜色，必须在Workshop Tools冷启动确认普通攻击确为白字、暴击为原生效果、技能红字足够凸显且三者均无重复。

## 活跃任务（2026-08-04）：超级防御塔暴击四项科技效果修复

### 用户已批准需求

- `researcher_super_tower_crit` 每一级同时提升所有防御塔暴击几率、防御塔攻击加成、召唤英雄暴击几率、召唤英雄攻击加成，四项均为每级 `+0.5%`。
- 权威科技 CSV 的每一级介绍必须明确包含上述四项；具体复合效果允许保留在 Lua 中，不要求为四项效果新增 CSV 数值字段。
- “英雄”作用对象指祭坛召唤的项目战斗英雄；保留原生普通攻击、暴击及攻击事件链，不新增自定义攻击伤害。

### 调查检查点

- 旧 `research_technology_config.lua` 的 `ARS-07` 已定义四项 `0.005` 每级效果，证明原设计即为四项各 `0.5%`。
- 当前生成科技权威链只把 CSV 的 `super_tower_crit_pct` 投影为防御塔暴击率；`technology_stat_manager.lua` 未派生防御塔攻击、英雄暴击和英雄攻击，并且英雄科技初始结构缺少 `critical_chance_pct`。
- 防御塔消费与刷新链已存在：`building_upgrade_system.lua` 消费塔攻击百分比和暴击率，并在 `TECHNOLOGY_STATS_CHANGED` 后刷新玩家所有已登记箭塔；`modifier_tower_attack_effects.lua` 负责研究暴击。
- 召唤英雄消费与刷新链已存在：`hero_combat_stat_service.lua` 消费英雄攻击百分比和暴击率，并在科技变化后重算；`modifier_weapon_stat_projection.lua` 按原生 attack record 结算暴击。
- 当前 CSV 错误配置为每级累计 `1%` 且说明只包含防御塔暴击；应修正为每级累计 `0.5%`，Lv.23 为 `11.5%`，并为每一级写明四项说明。

### 实施计划

1. 修改 `technology_definitions.csv` 中该科技 Lv.1-Lv.23 的累计值和四项说明。
2. 使用项目生成器定向重建 `generated/technology_definitions.lua`，不直接手改生成文件。
3. 在 `technology_stat_manager.lua` 将 `super_tower_crit_pct` 同时投影到塔/英雄的暴击率与攻击百分比。
4. 新增 PowerShell 契约与 Lua 5.1 行为测试，并执行生成一致性、语法、严格 UTF-8 和限定差异验证。

### 实施结果与当前状态

- 权威 CSV 的 Lv.1-Lv.23 已统一为每级 `0.5%`，累计值为 `level × 0.5%`；Lv.19 为 `9.5%`，Lv.23 为 `11.5%`。
- 每一级 `notes` 均明确分四行写入防御塔暴击、防御塔攻击、召唤英雄暴击和召唤英雄攻击四项 `+0.5%`；商城现有描述链直接消费生成行 `notes`。
- `technology_stat_manager.lua` 将单一 `super_tower_crit_pct` 同时投影为 `tower.critical_chance_pct`、`tower.attack_bonus_pct`、`hero.critical_chance_pct` 和 `hero.attack_bonus_pct`，并补齐英雄暴击零值结构。
- 防御塔继续由现有建筑刷新与塔暴击 Modifier 消费；召唤英雄继续由权威战斗快照和 attack record 暴击 Modifier 消费。未新增自定义伤害、重复 Buff 服务或旁路攻击事件。
- CSV 原文件为可逆 GB18030、无替换字符；本轮使用明确 GB18030 解码后转为 UTF-8 BOM。通用生成器改为保留 CSV 引号字段内换行，使生成 Lua 的 Tooltip 文本保留 `\n`。

### 自动验证结果

- `SUPER_TOWER_CRIT_GENERATED_COMPARE_PASS`：CSV 定向生成与生成 Lua 逐字节一致。
- `SUPER_TOWER_CRIT_CONTRACT_PASS`：23级数值、四项说明、四项映射及塔/英雄消费刷新链静态契约通过。
- `SUPER_TOWER_CRIT_LUA51_PASS`：Lv.1/Lv.19/Lv.23 四项行为与独立英雄攻击科技共存模拟通过。
- `SUPER_TOWER_CRIT_LUAC51_PASS`：生产映射和专项测试 Lua 5.1 语法通过。
- `RESEARCH_ARMOR_REDUCTION_CONTRACT_PASS` 与 `TECHNOLOGY_STAT_MANAGER_GENERATED_LEVELS_LUA51_PASS`：现有生成科技等级/减甲回归通过。
- `SUPER_TOWER_CRIT_STRICT_UTF8_PASS` 与 `SUPER_TOWER_CRIT_DIFF_CHECK_PASS`。

### 剩余实机验收

- 完全停止并重新 Run Workshop Tools，购买若干等级后确认 Tooltip 四行文本和每级 `+0.5%`。
- 对购买前后同一防御塔和召唤英雄记录攻击值，确认每级提高 `0.5%`；分别用足够攻击次数统计两类单位的暴击率变化。
- 确认已有防御塔、已召唤英雄会在购买后立即刷新；科技前召唤与科技后召唤得到相同结果。
- 自动测试不等于引擎实机验证，未经用户确认不得记录为验收完成。

## 活跃任务（2026-08-03）：英雄实际射程与Undying/召唤英雄工具技能修正

### 用户已批准需求

- 用户于2026-08-03进一步确认：齐天大圣1000码攻击不能只追求高速远程弹道，而要改成近战英雄式的无飞行弹道即时结算；保留攻击前摇、1000攻击距离和1000索敌距离。
- 用户此前要求齐天大圣攻击/索敌距离保持1000，并将弹道速度从3000提高到30000；该高速远程方案已被最新批准的近战式无弹道结算取代。
- 修复原生近战英雄虽配置远程能力但实际攻击命令仍按近战距离处理的问题；所有英雄的实际射程必须来自`hero_definitions.csv`。
- 用户实机反馈并修正需求：开局`npc_dota_hero_undying`建造者只拥有D键1000码点目标闪烁，不拥有拾取和回城技能；当前D键不可用必须修复。
- 祭坛召唤战斗英雄不拥有D闪烁，保留F键300范围拾取和F2回城；F2继续复用现有召唤英雄查询及主城安全落点服务。
- F拾取所有该玩家允许拾取的真实地面物品，按距召唤英雄由近到远处理；背包不足时停止，剩余物品保持在地面。
- 修复只有头冠、没有身体但仍可攻击树的异常表现。已确认头冠是跟随Undying主体的`prop_dynamic`，真正攻击者是主体；建造者必须设为`DOTA_UNIT_CAP_NO_ATTACK`并恢复稳定主体显示。

### 实施边界

- CSV是英雄射程和技能说明的权威源；生成Lua不得手改。
- 挑战地面奖励继续复用现有Claim、逻辑库存和`survival_ground_reward`防复制边界；普通物品使用官方背包拾取。
- Undying只授予D闪烁；召唤英雄只保留F拾取和F2回城，不授予D闪烁。
- 不增加空气弹道或手动补树伤害，不回滚当前`HEAD 187e732`及工作区既有未跟踪测试文件。
- 自动测试不能代替Workshop Tools中的实际攻击距离、快捷键、闪烁落点、拾取和外观验收。

### 当前状态

- 旧D/F/T方案已被用户实机反馈取代；技能归属、D输入和F2输入已完成修正并通过自动验证，射程、拾取事务、外观与NO_ATTACK实现继续保留。齐天大圣无弹道即时结算已完成代码与自动验证，等待Workshop Tools实机验收。

### 齐天大圣无弹道调查检查点（2026-08-03）

- `hero_stat_adapter.lua`当前只要配置存在就把英雄设为`DOTA_UNIT_CAP_RANGED_ATTACK`；无速度分支也仍强制远程，因此不能把速度留空或设0来表达近战。
- 已采用方案：在权威`hero_attack_projectiles.csv`新增显式`attack_capability`字段；齐天大圣配置`melee`，其他英雄配置`ranged`。运行时按字段投影攻击能力，近战分支清空可见弹道并在攻击前摇结束时由引擎直接结算。
- 1000攻击距离继续由`modifier_survival_hero_attack_range`覆盖，1000索敌继续来自`hero_definitions.csv`；不另写伤害，不绕过普通攻击、暴击、多目标和技能事件链。
- 已排除方案：继续提高30000速度仍会创建远程弹道，无法完全消除视觉差异；使用空值/0作为近战暗号会与旧回退语义冲突且数据不明确。
- 尚未验证：原生近战能力配合1000基础射程覆盖后的实际攻击命令、动画与命中时点只能在Workshop Tools冷启动后确认。

### 实施结果（2026-08-03）

- `hero_definitions.csv`及生成Lua中的齐天大圣攻击距离、索敌距离均为1000；`hero_attack_projectiles.csv`新增显式`attack_capability`列，齐天大圣配置为`melee`且不再配置弹道速度，其他五英雄保持`ranged`及原弹道配置。
- `hero_stat_adapter.lua`按CSV攻击能力分流：`melee`清空远程弹道名并设置`DOTA_UNIT_CAP_MELEE_ATTACK`，使攻击前摇结束时直接结算；远程英雄继续设置弹速、可选模型和`DOTA_UNIT_CAP_RANGED_ATTACK`。
- 隐藏永久`modifier_survival_hero_attack_range`继续通过`MODIFIER_PROPERTY_ATTACK_RANGE_BASE_OVERRIDE`把CSV基础射程投影为引擎实际射程；保留`survival_attack_range`与1000索敌范围，不另写伤害或绕过原生攻击事件链。
- 开局Undying只获得D键1000码点目标闪烁；策略会清除旧热重载实体残留的拾取/回城Ability，并把闪烁固定到四个建造技能后的D槽。D按Ability名称绑定，补齐`+/-`自定义命令，并明确通过`Abilities.ExecuteAbility`进入引擎原生点目标模式。
- 召唤英雄继续由`hero_skill_system`获得回城和拾取Ability，不获得闪烁；F按Ability名称触发拾取，F2通过`ui_return_home_request`只查询并施放当前玩家的召唤英雄回城Ability。
- F把虚拟升阶材料和真实`dota_item_drop`放入同一二维距离+entindex稳定排序序列。
- 真实物品拾取保留自定义owner、Purchaser、OwnerEntity和PlayerOwner所有权校验；挑战地面奖励仍先进入官方背包，再由既有拾取事件执行Claim和防复制事务。装备栏0至8无空位时停止，后续物品不删除、不移动。
- Panorama显示身份为Undying闪烁D、召唤英雄拾取F和回城F2；回城按钮与F2统一进入服务端召唤英雄查询路径。`combat_stats.js`与`hud_takeover.js`已强制编译。
- Undying初始化和重生均设为`DOTA_UNIT_CAP_NO_ATTACK`；移除异常Hallows头冠prop/粒子配置，恢复原生主体和wearable可见性，并在热重载时明确清除旧`EF_NODRAW`。

### 自动验证结果

- `BUILDER_UTILITY_CONTRACT_PASS`
- `WORKER_RANGED_MULTISHOT_CONTRACT_PASS`
- `MONKEY_MELEE_ATTACK_LUA51_PASS`
- `MONKEY_MELEE_TEST_LUAC51_PASS`
- `MONKEY_MELEE_LUAC51_PASS`
- `HERO_ATTACK_PROJECTILES_GENERATED_COMPARE_PASS`
- `MONKEY_MELEE_STRICT_UTF8_PASS`
- `MONKEY_MELEE_DIFF_CHECK_PASS`
- `HERO_MULTISHOT_LUA51_PASS`
- `GROUND_ITEM_PICKUP_LUA51_PASS`
- `BUILDER_UTILITY_LUAC51_PASS`
- `HERO_DEFINITIONS_GENERATED_COMPARE_PASS`
- 本轮7个非历史文档目标文件严格UTF-8通过；`SESSION_LOG.md`当前3个`U+FFFD`与`KNOWN_ISSUES.md`记录的既有历史数量一致，本轮新增段为0。
- `ALT_HERO_ABILITY_ORIGIN_DEV_CONTRACT_OK`
- `FREE_HERO_REPLACEMENT_CONTRACT_PASS`
- `HERO_HEALTH_CONTRACT_PASS`
- `HERO_CONFIGURED_HEALTH_LUA51_PASS`
- `FREE_HERO_EXCLUSIVE_STATE_LUA51_PASS`
- Panorama两个JS均为`OK: 1 compiled, 0 failed, 0 skipped`；限定`git diff --check`通过。
- 全量`tools/build_configs.py`被既有无关`item_definitions.csv`错误`invalid number: equipment_iron_armor_01`阻断；本任务使用同一生成器`build()`定向生成`hero_definitions.lua`并逐字节比较通过。失败命令触碰但内容未变化的Tooltip/Buff/Reward生成文件经`git diff --quiet`确认均为0。
- `.cline/local-toolchain.json`记录的`C:\Program Files\lua\bin`路径已失效；本次实际使用`C:\msys64\mingw64\bin\lua5.1.exe`与`luac5.1.exe`，版本均为Lua 5.1.5。

### 剩余实机验收

- 完全停止并重新Run Workshop Tools，重新召唤齐天大圣，确认攻击/索敌距离均为1000，攻击前摇结束时直接命中且不再出现飞行弹道或高速远程攻击的视觉差异。
- 回归确认齐天大圣的普通攻击伤害、暴击、攻击命中事件、专属/公共技能触发和转生多目标攻击仍正常；自动行为测试只证明Lua投影契约，不等于引擎实机验证。
- 选中开局Undying，确认只显示D闪烁，没有拾取和回城技能；D可进入点目标模式。
- 验证D在1000边界、阻挡地形、可通行落点、起终点闪光与投射物闪避的实际表现。
- 选中召唤英雄，确认没有D闪烁，F拾取和F2回城均稳定；在300范围内混放挑战材料、普通物品和他人物品，确认距离顺序、所有权、防复制、最后一格和满包停止。
- 确认Undying主体与默认外观稳定显示、无漂浮头冠，且无法自动或手动攻击资源树；死亡重生后保持一致。

---

## 已被当前任务取代的历史活跃段：齐天大圣Q/W/E/R专属技能与七塔合一

- 用户已批准实施齐天大圣四个固定Q/W/E/R专属技能，以及所有英雄均可使用的通用七塔合一系统。
- 四技能召唤时固定显示但置灰，分别在1/3/6/10转原位激活；复用现有四个齐天大圣专属技能ID，禁止公共技能点升级。
- Q「棍式」：本体或W分身主攻击命中时10%概率触发；从触发者位置朝主目标快照方向释放原版Boundless Strike视觉。Lua权威伤害矩形固定长1200、总宽200。范围敌人受到触发时逻辑全属性×30纯粹伤害；另受最大生命10%纯粹伤害，可击杀。额外生命伤害由同玩家本体与分身共享计数，每个敌人整局最多3次；属性伤害不限次数。
- W「混沌神猿」：3转解锁后暴击伤害在项目默认200%上增加2000个百分点，最终裸基础倍率为2200%；裸基础暴击率仍为0%。固定攻击间隔减少0.1秒，最终间隔最低0.1秒。解锁后每满60秒，以当时排除W自身累计增量的逻辑全属性为基数永久增加2%，持续复利，死亡期间继续计时。
- W解锁时在玩家城墙附近召唤唯一永久分身；无城墙时回退本体身边。分身死亡1秒后按同样规则重生，场上最多1个。分身实时镜像本体攻击、最终攻速/攻击间隔、暴击、逻辑三维、最大生命等，刷新时保持生命百分比；护甲固定10，只拥有Q，不进入公共技能、装备触发、转生成长和其他专属技能链。
- E「齐天」：6转解锁后，本体最终攻击力使用独立永久×3乘区。仅本体主普通攻击实际暴击时，对主目标追加触发瞬间逻辑全属性×5纯粹伤害；分身、次级多重攻击、技能和塔不触发。
- 七塔合一是通用功能，不要求齐天大圣。每条路线的终阶塔获得主动合成Ability；施法塔必选，其余每条路线选择同一建造玩家距离施法塔最近的终阶塔，距离相同时按实体ID确定。原子消耗7塔，在施法塔位置创建唯一无敌终极塔。
- 终极塔最大生命、当前生命和护甲分别等于参与7塔对应数值之和。终极塔保留7条独立攻击计时，每条使用原路线终阶塔的射程、间隔、弹道和隔离被动状态。基础攻击力为7塔最终攻击力之和。
- R「身外化身」：10转解锁，是常驻被动增强与主动无目标切换的混合技能。终极塔每条攻击流的单次攻击力均为“7塔攻击力之和+该玩家齐天大圣当前最终攻击力”，并实时继承英雄暴击率和最终暴击伤害（含W加成），不继承E附伤。主动无冷却，在本体释放瞬间位置与该玩家城墙当前位置间瞬移同一终极塔实体，保留生命百分比、7路计时和全部被动状态。
- 多人归属按施法塔建造玩家隔离：只消耗该玩家自己的7塔，只绑定该玩家的齐天大圣、城墙和R。
- 新测试聊天命令`passN`仅当`N == 当前转生等级+1`时成功；不打Boss，直接复用正式`reward_rebirth_NN` CSV完整奖励事务。跳级、重复、倒退必须原子拒绝且不产生部分奖励。
- CSV仍是全部技能数值、解锁级别和终极塔配置权威源；生成Lua不得手改。现有部分旧塔CSV中文已损坏，只允许字节安全的必要字段修改，不得整表转码或猜测恢复旧中文。

### 已完成调查与实施顺序

- 已确认现有齐天大圣4个专属技能ID、VIP一转一次性授予旧行为、英雄技能固定槽同步、转生奖励CSV、英雄主攻击事件、项目战斗快照、七条塔路线、终阶等级、塔被动运行服务和聊天命令解析链。
- 当前项目没有统一的英雄普通攻击暴击结果事件，也没有七塔合一实现；必须先扩展权威战斗快照和attack record，再实现E与R暴击继承。
- 实施顺序：先完成CSV解锁链、`passN`与英雄暴击/固定间隔基础能力；再完成Q/W/E；最后实现七塔原子合成、7路攻击与R位置切换。
- 自动测试不能替代Workshop Tools对Boundless Strike控制点、分身模型/重生、7路弹道、塔被动和瞬移落点的实机验证。

### 实施结果（2026-08-03）

- 已完成CSV权威分转解锁：齐天大圣原四个专属技能ID分别配置为1/3/6/10转；四槽召唤后固定显示，未解锁时置灰并显示对应转生提示。四技能统一为1级，Ability KV最高等级同步为1。
- 已完成严格顺序`passN`：仅允许`N == 当前转生+1`，通过新增内部`MONSTER_REWARD_GRANT_REQUEST`复用正式`reward_rebirth_NN`奖励方案，不启动Boss。3/6/10转CSV新增专属授予效果，正式通关与测试命令走同一奖励链。
- 已完成统一普通攻击暴击权威记录：研究暴击率进入英雄战斗快照；`modifier_weapon_stat_projection`按attack record唯一掷骰并保存倍率，`modifier_weapon_attack_tracker`在命中事件发布实际`critical/critical_multiplier`并在record销毁时清理。研究Modifier旧的独立200%掷骰已移除。
- 已完成Q：本体与W分身主攻击10%触发；Lua按1200×总宽200矩形判定，造成全属性×30加目标最大生命10%纯粹伤害。生命伤害次数按玩家+敌人共享，最多3次且只在伤害事务成功时计数。接入原版Monkey King Strike粒子并预缓存，但控制点仍待实机确认。
- 已完成W：暴击伤害2200%、BAT固定减少0.1秒并保底0.1；每60秒按排除W自身累计值的当前逻辑三维分别增加2%。唯一永久分身优先生成在玩家城墙附近，无墙回退本体；死亡1秒后重生。每0.1秒镜像本体生命上限/生命比例、最终攻击、BAT、攻速与暴击，War3护甲固定10，只保留Q并使用专用攻击Modifier，不发布英雄主攻击事件。
- 已完成E：英雄战斗快照与引擎基础/附加攻击投影均应用独立×3乘区且不会重复累乘；仅本体主攻击事件的实际暴击对主目标追加全属性×5纯粹伤害。
- 已完成通用七塔合一：每条路线终阶塔同步无目标合成Ability。施法塔必选；其他路线按同玩家、距离最近、实体ID平局排序选择。建筑系统二次验证7条互异终阶路线后批量注销并释放网格；新塔或代理创建失败、二次消费失败时不消费原塔。
- 已完成终极塔：主实体无敌，最大生命/当前生命/护甲分别求和，基础攻击为7塔最终攻击总和。七个隐藏无敌代理各自持有原路线终阶技能Ability、`modifier_tower_attack_effects`和独立被动状态；服务按各代理实时攻击间隔调度真实`PerformAttack`，复用原路线射程、弹道及全部现有攻击事件/被动服务。
- 已完成R：终极塔各路攻击实时增加齐天大圣当前最终攻击，并只在路线固有暴击未触发时继承英雄暴击率/最终暴击伤害；不进入E附伤。R主动明确0魔耗、0冷却，在英雄与玩家城墙之间移动同一主实体和7代理，不重建状态或重置7路计时。
- 已更新技能CSV/生成Tooltip、六份中英文本地化镜像、Ability KV和启动预缓存。新增专项契约及Lua 5.1数学测试。

### 自动验证结果

- `MONKEY_TOWER_CONTRACT_PASS`
- `FREE_HERO_REPLACEMENT_CONTRACT_PASS`
- `ALT_HERO_ABILITY_ORIGIN_DEV_CONTRACT_OK`
- `TREE_DAMAGE_RULES_CONTRACT_PASS`
- `WORKER_RANGED_MULTISHOT_CONTRACT_PASS`
- `MONKEY_KING_QWE_LUA51_PASS`
- `TOWER_FUSION_LUA51_PASS`
- `HERO_MULTISHOT_LUA51_PASS`
- `MONKEY_TOWER_FINAL_LUAC_PASS`
- `MONKEY_TOWER_GENERATION_UTF8_PASS`及`MONKEY_TOWER_FINAL_STRICT_UTF8_PASS`
- 限定`git diff --check`通过。既有工具目录没有塔特殊技能/魔法至尊专项脚本，因此这两项显示`SKIP_MISSING`，未冒充通过。

### 剩余实机验收

- Workshop Tools冷启动确认服务注册、四槽置灰与`pass1`至`pass10`正式奖励链。
- 验证Boundless Strike粒子控制点、1200×200碰撞边界、共享3次生命伤害计数及可击杀表现。
- 验证W分身模型、城墙附近出生、1秒重生、10护甲、生命比例镜像、只触发Q且不触发公共/装备/E。
- 验证E实际暴击附伤与三倍最终攻击HUD/伤害一致。
- 验证七塔选择、原子消费、七路不同弹道/射程/攻速，以及死亡/神秘/闪电/机枪/多重/冰霜/魔法路线全部被动状态隔离。
- 验证R的实时攻击与暴击继承、城墙/英雄两点切换、同实体生命比例和7路计时保持。

### 实机反馈修复（2026-08-03）：W分身战斗数据未完整复刻

- 用户实机确认W分身技能复刻正确，但战斗数据与本体不一致，尤其攻击速度不同。
- 已定位旧实现错误：分身攻速重新组合`base_attack_time + equipment_attack_speed_pct`，会混入分身原生英雄攻速，而不是直接投影`HERO_COMBAT_STATS_GET_REQUEST.attack_speed`最终值；生命还使用项目已实机证实不可靠的原生英雄最大生命Setter。
- 修复口径：每次同步只消费一份本体权威战斗快照；攻击力、最大生命、最终攻速、暴击和逻辑三维来自同一刷新版本。攻速按项目每秒攻击次数直接投影为`SetBaseAttackTime(1 / attack_speed)`，生命复用已验证的隐藏永久生命Modifier动态补足；固定10 War3护甲和仅Q隔离规则保持不变。
- 实施完成：`hero_combat_stat_service`在同一原子快照中发布本体最终引擎攻击上下界；分身直接复制该值，避免旧实现错误放大装备/研究攻击。
- 分身最终攻速直接消费快照`attack_speed`并投影为`SetBaseAttackTime(1 / attack_speed)`，移除了`base_attack_time + equipment_attack_speed_pct`二次组合；原生三维归零，逻辑三维仅缓存快照值，不污染Dota原生属性。
- 分身最大生命改为复用已实机验证的`modifier_survival_hero_base_health`动态补足方案，刷新保持生命比例；暴击与其余数据消费同一刷新版本的缓存快照。
- 选中分身时，`ui_request_router`按严格分身身份读取owner的同一英雄快照，并替换分身实体、生命、固定10 War3护甲和最终攻速，因此面板不再回退到原生英雄数据。
- 自动验证通过：`MONKEY_KING_QWE_LUA51_PASS`、`MONKEY_TOWER_CONTRACT_PASS`、`MONKEY_CLONE_LUAC51_PASS`、`HERO_HEALTH_CONTRACT_PASS`、`FREE_HERO_REPLACEMENT_CONTRACT_PASS`、严格UTF-8及限定`git diff --check`。尚未经过Workshop Tools修复后实机确认。

## 紧急修复（2026-08-03）：伐木工平A树只加木材但不扣生命

- 用户实机确认伐木工攻击树时会出现木材绿字并增加木材，证明远程攻击真实落地且`MODIFIER_EVENT_ON_ATTACK_LANDED`正常；问题不是空弹道或攻击命令。
- 第一轮只移除`modifier_tree_progression`的非权威类别二次判断后，用户实机确认树仍不掉血，证明全局DamageFilter也在拦截。
- 二次根因：现有Mock测试人为提供`damage_category_const`，但实机DamageFilter不保证存在该字段；旧规则对缺失/0类别失败关闭，因此真实平A仍被拦截。此前“DamageFilter始终提供该字段”的项目经验错误，现已更正。
- 当前修复：树Modifier在`ON_ATTACK_START`登记短生命周期、一次性的真实攻击凭证；DamageFilter类别缺失/0且无inflictor时，仅消费匹配凭证后放行。箭塔不能登记凭证且身份拦截优先；技能、有inflictor伤害和无凭证脚本伤害继续拒绝。加入限20次`TREE_DAMAGE_FILTER`诊断输出类别、inflictor、凭证和实体无敌状态。

## 紧急修复（2026-08-03）：缺失建筑升级流程模块阻断地图启动

- Workshop Tools报错：`building_upgrade_system.lua:12`无法加载`systems/building_upgrade_process`，导致`addon_game_mode.lua`终止。
- 根因确认：提交`85ce4eb`向`building_upgrade_system.lua`加入`begin/is_active/cancel_by_entindex/reset`调用，但对应模块从未进入Git历史或当前工作区。
- 已补齐`building_upgrade_process.lua`：使用现有`scheduler`管理1秒升级事务，维护每建筑唯一活动状态、目标等级/模型状态、可选升级粒子、视觉预加载状态回调、完成/销毁取消/重置清理与旧回调失效保护。
- Lua 5.1启动链语法与专项行为测试通过；仍需完全停止并重新Run Workshop Tools确认引擎实际启动。

## 活跃任务（2026-08-03）：树位置、工人远程属性、全英雄远程与转生多目标普攻

- 用户确认资源树初始位置改为`(448, 64, 128)`。
- 伐木工LV1至LV8的权威攻速统一为每秒`0.5`次（基础攻击间隔2秒），攻击范围统一为400，改为远程攻击能力但不显示弹道；修理工保持纯修理、`NO_ATTACK`，只统一400距离属性。
- 伐木工LV3坏模型替换为`models/creeps/lane_creeps/creep_bad_melee/creep_bad_flagbearer.vmdl`；LV6、LV7、LV8依次使用用户指定的Dire Bird Mega、Crystal Bad Melee和Mega Greevil模型。
- 所有项目英雄（包括齐天大圣和剑圣）统一使用远程攻击能力；射程和弹道继续由英雄CSV独立配置。
- 转生多目标普通攻击总目标数（包含主目标）为：一转3、二转4、三转5、四转及以后6。每个次级目标由引擎独立执行普通攻击并按各自护甲结算；次级攻击必须通过现有attack record隔离，不再触发项目技能、装备效果、成长或递归多目标。
- CSV仍是配置权威；生成Lua不得手改。自动验证不能替代Workshop Tools中的模型动画、瞬发攻击表现、射程和多目标实际结算验收。

### 实施结果与当前状态

- `world_visual_definitions.csv`已增加树初始坐标并生成配置，运行时位置改为`(448, 64, 128)`。
- `training_definitions.csv`已增加`attack_range`权威列；八级伐木工均为`attack_rate=0.5`和`attack_range=400`，LV3/LV6/LV7/LV8模型已替换。修理工两级均投影400距离，但运行时和KV继续保持`NO_ATTACK`；实际修理最大有效间距统一为模型边缘间距200码。
- 伐木工运行时改为远程攻击能力、10000速度和空弹道名；KV首帧回退同步为远程、400射程、2秒AttackRate。四个新增模型已从当前Dota VPK v2目录索引确认存在。
- 工人科技刷新已改为保存并复用每个训练行的基础攻速，攻速科技继续在0.5次/秒基线上计算，不会被旧全局1.0回退覆盖；全局工人缺失配置回退也同步为0.5。
- 六名项目英雄均由`hero_attack_projectiles.csv`提供正弹道速度并统一切换远程能力；影魔/黑暗游侠保留现有可见弹道，末日/斧王/齐天大圣/剑圣使用空自定义弹道名。
- 转生奖励CSV已规范为一转总目标3，二至四转各+1，五转以后+0；运行时额外封顶6。次级目标通过`PerformAttack`逐目标独立结算并由现有attack record标记为secondary，不发布`HERO_MAIN_ATTACK_LANDED`，因此不递归触发多目标、项目技能、成长或主攻击装备事件。
- 自动验证通过：`WORKER_RANGED_MULTISHOT_CONTRACT_PASS`、`HERO_MULTISHOT_LUA51_PASS`、`WORKER_MODEL_VPK_PASS 4`、`WORKER_MULTISHOT_FINAL_LUAC51_PASS`、`WORKER_MULTISHOT_FINAL_GENERATION_ENCODING_PASS`、树伤害合同/行为、免费英雄合同/行为、魔法弹弓目标行为、研究减甲合同/行为以及限定`git diff --check`。
- 用户已有未跟踪旧模型合同仍要求已批准替换的LV3坏模型，因此单独失败为过期断言；未修改该用户文件。尚需Workshop Tools冷启动验收模型动画、伐木工瞬发无弹道、六英雄远程表现、树位置及一至四转对不同护甲目标的实际独立伤害。

## 活跃任务（2026-08-03）：资源树、祭坛、主城、伐木工与修理工分级模型替换

- 用户要求先替换以下模型，并将模型映射写入`data/csv/`权威配置，再通过项目生成链同步运行配置：
  - 资源树：`models/props_tree/mango_tree.vmdl`；
  - 召唤祭坛：`models/props_structures/tower_good4.vmdl`；
  - 伐木工LV1：`models/creeps/lane_creeps/creep_radiant_melee/radiant_melee.vmdl`；
  - 伐木工LV2：`models/creeps/lane_creeps/creep_bird_radiant/creep_bird_radiant_melee.vmdl`；
  - 伐木工LV3：`models/creeps/lane_creeps/creep_bad_melee/creep_bad_melee_cavern_mega.vmdl`；
  - 伐木工LV4：`models/creeps/lane_creeps/creep_2021_radiant/creep_2021_radiant_melee_mega.vmdl`；
  - 伐木工LV5：`models/creeps/lane_creeps/creep_dire_hulk/creep_dire_diretide_ancient_hulk.vmdl`；
  - 修理工LV1：`models/creeps/neutral_creeps/n_creep_eimermole/n_creep_eimermole.vmdl`；
  - 修理工LV2：`models/creeps/neutral_creeps/n_creep_eimermole/n_creep_eimermole_lamp.vmdl`。
- 主城第一版已完成资源取证并固定为：LV1至LV3使用`models/props_structures/tower_good.vmdl`，缩放依次为0.55/0.65/0.75；LV4至LV5切换为更修长的`models/props_structures/tower_good3.vmdl`，缩放依次为0.80/0.95。祭坛使用指定的`tower_good4.vmdl`并暂时沿用当前0.34缩放。`tower_good1.vmdl`在当前VPK中不存在，不能使用。
- 当前Dota`pak01_dir.vpk`已确认用户指定的九个模型以及主城`tower_good.vmdl`、`tower_good3.vmdl`全部存在。资源树保留既有运行时缩放3；本轮未指定的伐木工LV6至LV8保持原状，不编造模型。
- 配置落点已确定：工人使用既有`training_definitions.csv.model_name`；资源树使用新增UTF-8的`world_visual_definitions.csv`；主城与祭坛使用新增UTF-8的`building_visual_levels.csv`并由`building_visual_service`消费，避免重写当前GB18030且有已知风险的`building_levels.csv`和结构不一致的`asset_catalog.csv`。
- 修改前必须调查相关CSV、生成Lua、单位KV、运行时模型/缩放消费位置、预缓存和现有测试；原则上不直接修改`config/generated/`。
- 验证至少包含模型路径存在性、CSV与生成配置一致性、相关Lua语法、专项契约、严格UTF-8、限定`git diff --check`；模型实际尺寸、动画、骨骼、碰撞和高塔观感仍需Workshop Tools实机验收。

### 实施结果与当前状态

- 2026-08-03实机启动前发现紧急阻断：`addon_game_mode.lua`加载`hero_passive_skill_service.lua`时，Lua 5.1报告主chunk超过200个local。已将末尾`trigger`、`roll`和`on_main_attack`改为既有模块表`M`的方法并同步内部引用，顶层声明由202降至199，未改变随机、事件订阅或技能结算行为。
- 紧急修复自动验证通过：主服务、专属服务和`addon_game_mode.lua`的`luac5.1 -p`；回音重斩、地裂冲击、陨石、元气弹、龙卷、脉冲、爆炎、毒云8项Lua 5.1状态回归；四英雄专属状态/契约；严格UTF-8和限定diff检查。仍需完全重启Workshop Tools确认实际地图可进入。
- 已新增`building_visual_levels.csv`：主城LV1至LV3使用`tower_good.vmdl`并按0.55/0.65/0.75逐级放大；LV4至LV5切换`tower_good3.vmdl`并使用0.80/0.95；召唤祭坛使用`tower_good4.vmdl`和0.34缩放。
- 已新增`world_visual_definitions.csv`：资源树由CSV提供`mango_tree.vmdl`和既有缩放3；`tree_config.lua`不再手写树模型。
- `training_definitions.csv`已写入伐木工LV1至LV5和修理工LV1至LV2模型；`worker_system.lua`对所有工人统一应用训练行的`model_name`。未指定的伐木工LV6至LV8继续使用单位KV回退模型。
- `npc_units_custom.txt`同步资源树、主城、祭坛、伐木工LV1和修理工LV1的引擎创建壳回退模型；分级切换仍由CSV与Lua权威控制。`addon_game_mode.lua`会从三份生成配置中去重预缓存全部模型，并补充修理工单位预缓存。
- `asset_catalog.csv`因历史表头27列而多数既有行只有22列，不能在本任务安全生成；已排除该落点并确认该文件没有本轮差异。本任务改用两个结构完整的独立UTF-8视觉CSV，未重写有编码风险的`building_levels.csv`。
- 自动验证通过：`UNIT_MODEL_CONFIG_CONTRACT_PASS`、`UNIT_MODEL_CONFIG_LUA51_PASS`、`UNIT_MODEL_ALL_LUAC51_PASS`、`UNIT_MODEL_GENERATED_COMPARE_PASS`、`UNIT_MODEL_VPK_INDEX_PASS 11`、`UNIT_MODEL_ENCODING_AND_COLUMNS_PASS`、`UNIT_MODEL_DIFF_CHECK_PASS`；资源树承伤回归`TREE_DAMAGE_RULES_CONTRACT_PASS`和`TREE_DAMAGE_RULES_LUA51_PASS`通过。
- 尚未进行Workshop Tools实机验收。需确认Mango Tree在缩放3下的尺寸与血条位置；五级伐木工和两级修理工动画/朝向；主城LV1至LV5的尺寸、切模和神圣高塔观感；祭坛0.34缩放是否合适；模型碰撞仍由单位壳而非视觉模型决定。

## 已完成实现、待实机验收（2026-08-03）：资源树仅承受基础平A，防御塔禁止攻击树

## 已完成实现、待实机验收（2026-08-03）：资源树仅承受基础平A，防御塔禁止攻击树

- 用户要求`enemy_tree`只承受引擎基础普通攻击伤害；任何技能、脚本、持续、范围及平A触发的技能/装备附伤都不得扣树生命。
- 英雄、伐木工、波次怪、挑战怪和召唤物等非防御塔单位的基础平A仍可伤树。
- 所有箭塔与转职塔使用统一身份`survival_building_id == "arrow_tower"`：不得自动选择树，不得通过玩家手动攻击命令攻击树，已在飞行中的塔弹道也不得扣树生命。
- 用户已确认边界并批准实施：只保留引擎基础平A伤害；所有攻击触发附伤均不计入树伤害。
- 计划扩展既有`modifier_tree_progression`承伤规则，复用全局伤害过滤器的`damage_category_const`，扩展`modifier_tower_auto_attack`选敌，并新增最小OrderFilter服务拦截塔对树的手动攻击命令。
- 本任务无新增策划数值，不修改已有编码风险的建筑CSV，也不直接修改generated Lua。
- 验证至少包含专项PowerShell契约、Lua 5.1行为测试、`luac5.1 -p`、树/塔/伤害回归、严格UTF-8和限定`git diff --check`；自动验证不能替代Workshop Tools中的塔选敌、右键命令与实际扣血验收。

### 实施结果与当前状态

- 已新增共享规则`systems/tree_damage_rules.lua`：只把`DOTA_DAMAGE_CATEGORY_ATTACK`视为树可承受的基础攻击类别；未知或缺失类别在全局DamageFilter中失败关闭；`survival_building_id == "arrow_tower"`始终禁止伤树。
- `modifier_tree_progression.lua`保留最低1血与耗尽升级调度，并增加承伤属性作为第二层保护。全局DamageFilter是伤害类别权威；考虑部分引擎版本可能不向modifier属性参数提供`damage_category`，modifier在类别缺失时交由全局过滤器判断，但仍直接拦截可识别的箭塔攻击。
- `modifier_tower_auto_attack.lua`已从自动搜索中排除树；当前目标或强制目标是树时会清除并重新选择合法敌人；攻击开始事件另行停止塔对树的竞态攻击。
- 已新增`systems/tree_attack_order_filter.lua`并由`addon_game_mode.lua`启动注册，只拒绝箭塔单位对`enemy_tree`的`DOTA_UNIT_ORDER_ATTACK_TARGET`，其他单位、目标和命令不变。
- 专项验证通过：`TREE_DAMAGE_RULES_CONTRACT_PASS`、`TREE_DAMAGE_RULES_LUA51_PASS`、`TREE_DAMAGE_RULES_LUAC51_PASS`、`TREE_DAMAGE_RULES_STRICT_UTF8_PASS`和`TREE_DAMAGE_RULES_DIFF_CHECK_PASS`。行为测试覆盖英雄/怪物/召唤物基础平A放行、技能/未知脚本/塔平A拦截、DamageFilter事务消费、手动命令过滤、自动选敌跳过树、攻击开始清理、间隔重新选敌以及最低1血后的升级调度。
- 工作期间外部进程将生产改动提交为`00bfe05`并修改`.gitignore`；用户明确选择接受新HEAD、保留外部`.gitignore`并继续验证。两个专项测试文件仍在磁盘并已执行通过，但被外部`.gitignore`第103至104行忽略，未纳入Git状态。
- 尚未完成Workshop Tools实机验证，不能记录为制作完成或用户验收。需验证：各转职塔自动忽略树；右键/攻击命令无法令塔攻击树；其他单位基础平A可扣树生命；技能、平A触发技能/装备附伤与无Ability脚本伤害不扣树生命；树到1血后仍正常升级刷新。

## 已完成任务（2026-08-02）：四名免费英雄替换

- 用户已批准将原有非VIP英雄替换为末日使者、影魔、斧王、黑暗游侠；齐天大圣与剑圣两名VIP英雄保持不变。
- 四名免费英雄沿用普通模板：逻辑三维及成长100、基础攻击20、攻速0.7、War3护甲1、移速2000、生命3000；末日/斧王射程500，影魔/黑暗游侠射程1200。
- 四个专属技能均为1级、固定Q槽；召唤英雄时可见但置灰，一转成功后原位激活，不能用公共技能点升级。
- 末日：主攻击命中10%概率召唤术士地狱火，持续10秒，继承触发时100%权威攻击力、攻击速度、最大生命和运行时护甲，不继承英雄/装备附加攻击效果。地狱火活动期间跳过概率判定，死亡或到期后解锁。
- 影魔：主攻击命中10%概率在目标位置造成250范围影压；本次先加层再伤害，1至5层分别为全属性×27.5/30/32.5/35/37.5纯粹伤害；每层独立持续3秒，最多5层。
- 斧王：主攻击命中10%概率以攻击目标为中心触发400范围反击螺旋，造成触发时全属性×30纯粹伤害。
- 黑暗游侠：主攻击命中10%概率召唤无敌小游侠，持续10秒，继承触发时150%权威攻击力和100%攻击速度；每次攻击主目标并攻击射程内最近另外4个敌人，次级攻击不得触发英雄/装备/技能Proc。小游侠活动期间跳过概率判定，到期或实体失效后解锁。
- CSV是权威源；先修改英雄定义、专属关系、技能定义、弹道和Tooltip CSV，再生成Lua。不得覆盖`hero_skill_definitions.csv`中已有的公共技能完整五级描述修改。
- 用户已于2026-08-02明确确认任务成功并验收通过；该结论是用户验收，不应与自动测试或逐项引擎诊断混为一谈。

### 实施结果

- 已完成权威CSV、生成Lua、祭坛按钮、召唤脚本、Ability KV、专用召唤单位KV、中英文三套本地化镜像与预缓存替换；生产入口不再引用斯拉克或主宰。
- 四名免费英雄召唤后会在Q槽预创建项目等级0的专属技能；引擎壳保持1级可见但`SetActivated(false)`，一转授予时同一技能原位切换到项目等级1并激活。VIP英雄不预创建，保留原一转四专属顺序。
- 新增`hero_exclusive_passive_service.lua`管理四技能运行状态；伤害仍注入并复用`hero_passive_skill_service.lua`既有`deal_group -> combat_events.DEAL_REQUEST`事务。
- 地狱火和小游侠使用唯一活动锁，概率调用前先检查召唤实体存活与到期；影压使用每目标独立到期时间数组；小游侠次级攻击通过攻击record标记与`PerformAttack(..., bProcessProcs=false, ...)`隔离。
- 地狱火和小游侠均读取触发瞬间战斗快照中的权威`attack_speed`（每秒攻击次数），按100%继承并通过`SetBaseAttackTime(1 / attack_speed)`应用；同步记录`survival_attack_speed`供实机诊断。
- 已通过：`FREE_HERO_REPLACEMENT_CONTRACT_PASS`、`FREE_HERO_EXCLUSIVE_STATE_LUA51_PASS`、`FREE_HERO_ALL_CHANGED_LUAC51_PASS`、`FREE_HERO_GENERATION_CONSISTENCY_PASS`、`FREE_HERO_KV_UNIQUENESS_PASS`、`FREE_HERO_TASK_FILES_STRICT_UTF8_PASS`、`FREE_HERO_LOCALIZATION_STRUCTURE_PASS`、限定`git diff --check`，以及英雄生命/原生Ability保留/addskill和多项公共被动回归。
- 已知测试边界：用户实施前已有的未跟踪`test_blade_pulse_contract.ps1`仍断言已批准删除的旧`ability_survival_axe_exclusive`；`test_flame_burst_contract.ps1`要求HEAD中原本就未预缓存的Dragon Slave粒子。未修改无关生产逻辑迎合这两条旧断言。
- 完成结论：用户已确认整体任务成功；不再保留本任务待办，也不得依据旧验收清单自动恢复。只有用户以后报告具体回归或提出新需求时才重新开启。

## 最新状态（2026-08-02）

## 活跃任务（2026-08-02）

新增公共技能 `proto_echo_slash` / “回音重斩·被动”。用户已确认：LV1攻击命中12%概率，发射1道总宽200的弧形斩，路径所有单位受到触发时全属性×1伤害；LV2波数+1、概率15%、波间隔0.1秒；LV3波数再+1；LV4完整继承LV3；LV5波数再+1，每波独立随机提高5%～20%伤害。斩击从触发英雄位置朝被攻击目标当时位置固定方向移动，距离等于攻击触发时英雄攻击射程，1秒走完全程；每道波真实穿透命中并独立去重，复用项目逻辑属性快照和既有纯粹伤害事务。计划新增 `public_13`，复用 `proto_blade_nova` 的线性投射物机制；用户已批准开始实施。

### 本任务实施边界

- 权威配置先修改 `data/csv/英雄系统/hero_skill_definitions.csv`、`data/csv/英雄系统/hero_skill_pool_members.csv` 和 `data/csv/公共规则/tooltip_definitions.csv`，再定向生成对应 Lua。
- 运行配置位于 `scripts/vscripts/config/hero_passive_skill_definitions.lua`；真实碰撞和伤害位于 `scripts/vscripts/systems/hero_passive_skill_service.lua`；能力路由复用 `scripts/vscripts/abilities/survival_hero_skill.lua`。
- LV5每道波分别随机抽取5%～20%增伤；同次触发固定起点、目标方向、距离和全属性快照。未额外设置活动锁，允许不同攻击触发并行。
- 2026-08-03视觉方案最终调整：内部纯刀光`kez_katana_echo_strike_slash.vpcf`无论作为投射物`EffectName`还是Lua独立驱动都不能可靠还原原版，实机先后出现残缺小段、大圆环和端点白爆。用户明确授权：若不能移除Kez模型，可保留Kez并使用完整Echo Slash。因此内部子粒子路线废弃，改用完整父粒子`particles/units/heroes/hero_kez/kez_katana_echo_strike.vpcf`，允许其自带Kez英雄残影及ground/movement/streaks/swoosh等完整子效果。
- 完整父粒子仍只作为独立视觉层；明确不调用`kez_echo_slash`、不添加Kez modifier、不播放原生声音，也不接入原技能攻击、回音复击或伤害。项目权威线性投射物继续唯一负责碰撞和结算。
- 2026-08-03末端额外斩击根因已由资源数据收敛：完整父粒子创建时瞬发一个固定寿命0.5秒的移动载体，并通过子控制点驱动slash/swoosh；旧`DestroyParticle(..., false)`不会杀死已有载体，因此它会在换段或最终收尾后继续向前。父资源没有延迟发射第二个父载体，CP1也不是终止边界。视觉统一清理现强制`DestroyParticle(..., true)`并继续释放索引，战斗层不变。
- 尚未验证：Workshop Tools中末端额外斩击是否消失，以及立即销毁后Kez模型、朝向、尺寸、高度、两个0.5秒实例衔接及连续多波观感；自动测试不能替代实机验收。

### 当前实施结果

- 已新增 `proto_echo_slash`、`ability_survival_echo_slash`、公共池成员 `public_13` 和五级 Tooltip。
- 三份权威CSV已更新并定向生成英雄技能、公共池和Tooltip Lua；生成比较逐字节一致。
- 运行时将碰撞投射物与视觉彻底分离：原生线性投射物不设置Kez `EffectName`，仍负责碰撞、穿透和伤害；Lua为每道波独立创建完整Echo Slash父粒子。第一实例CP0/CP1为触发起点→射程中点，第二实例为射程中点→完整终点；CP2按父粒子契约设置为`(权威速度, 200, 1.5)`，并补Valve预览CP6、蓝色CP7和CP8。两个0.5秒完整视觉实例合计覆盖1秒路径；这不是额外战斗波，不增加攻击、命中或伤害。
- 多波使用绝对时间校正的单链调度；LV5每波创建时独立抽取5%～20%增伤，触发时逻辑全属性快照在整次技能中保持不变。
- 自动验证通过：`ECHO_SLASH_STATE_LUA51_PASS`、`ECHO_SLASH_CONTRACT_PASS`、`ECHO_SLASH_LUAC51_PASS`、配置Lua 5.1验证、CSV生成比较、严格UTF-8、限定`git diff --check`、脉冲激射/地裂/魔法弹弓共享回归。
- 2026-08-03完整父粒子调整验证通过：`ECHO_SLASH_VISUAL_STATE_PASS`、`ECHO_SLASH_VISUAL_CONTRACT_PASS`、`BLADE_PULSE_VISUAL_CONTRACT_PASS`、Lua 5.4.5生产/测试语法、严格UTF-8、主服务顶层local仍为199及限定`git diff --check`。状态测试覆盖完整父资源、两段CP0/CP1、CP2/6/7/8、正常/重置/异常清理及全部战斗保护。历史Lua 5.1工具绝对路径仍不存在，因此不会把本轮编译写成Lua 5.1通过。
- 末端额外斩击修复后上述三项专项/相邻回归再次通过；Lua/Luac 5.4.5生产与测试语法、7个目标文件严格UTF-8、顶层local 199和限定`git diff --check`通过。状态测试新增锁定第一阶段换段及第二阶段正常收尾均立即销毁。当前仅发现Lua 5.4.5，无可用Lua 5.1命令，因此不宣称本轮Lua 5.1验证。
- 脉冲激射完整PowerShell契约存在既有陈旧预缓存断言，仍要求已废弃的Vengeful粒子；其Lua 5.1状态测试通过，本任务未修改该旧测试。
- 剩余动作仅为冷启动Workshop Tools，确认完整Kez Echo Slash在换段和终点不再额外向前播放，并验证立即销毁是否产生断帧、Kez模型、朝向、尺寸、高度、两段衔接和完整射程；尚不能记录为引擎验证或用户验收完成。

## 活跃任务（2026-08-03）：地裂冲击卡尔陨石滚动视觉

用户明确重新开启公共技能`proto_earth_line`五级“地裂冲击·被动”，要求移动视觉使用卡尔混沌陨石落地后向前滚动的部分。已批准实施：使用项目滚动父粒子`particles/survival_earth_line/survival_earth_line_chaos_meteor.vpcf`替换现有Tiny移动外观；该资源复用Valve陨石模型与滚动火焰/拖尾/烟尘，排除落地瞬时冲击子效果，并将原版固定0.2秒主载体寿命改为由CP2.x接收地裂真实飞行时长。父粒子只作为独立视觉层，CP0使用触发起点、CP1使用地裂固定方向×权威速度500。原生无视觉线性投射物继续唯一负责碰撞、穿透和伤害。

### 本轮不可改变边界

- 不播放卡尔坠落段，不调用卡尔原生技能，不增加燃烧、声音、伤害或单位。
- 保持12%触发、固定起终点、速度500、总宽150/250、逐单位去重、旧眩晕翻倍、LV3眩晕、LV5首次命中范围伤害及终点无伤害爆炸。
- 正常终点、超时兜底和服务重置必须立即销毁并释放移动父粒子；视觉失败不得阻断权威投射物。
- 主服务当前Lua 5.1顶层local为199；新增状态、常量和方法必须挂在既有`earth_rock`表，不增加模块级local。

此前用户已确认现有公共技能`proto_earth_line`五级“地裂冲击·被动”暂时完成；本次只因上述明确新视觉需求重新开启，不恢复其他旧视觉/碰撞待办。

### 地裂冲击自动验证

- `EARTH_LINE_VISUAL_STATE_PASS`：覆盖无视觉碰撞体、CP0起点、CP1权威速度、CP2完整飞行时长、穿透、逐单位去重、旧眩晕×6、LV5首次命中范围伤害、正常终点/超时/重置清理、迟到回调幂等、并行实例隔离及视觉异常不阻断碰撞投射物。
- `EARTH_LINE_VISUAL_CONTRACT_PASS`：锁定项目粒子源、Valve陨石模型、CP1速度、CP2寿命、贴地、滚动旋转、滚动子效果、禁止land冲击与屏幕震动、预缓存、无Tiny生产引用和全部原战斗数值。
- Resource Compiler强制定向编译结果为`OK: 1 compiled, 0 failed, 0 skipped`；game产物`particles/survival_earth_line/survival_earth_line_chaos_meteor.vpcf_c`存在。
- 生产服务、Ability入口、游戏模式和专项状态测试通过当前Lua/Luac 5.4.5语法；主服务顶层local仍为199。当前环境没有Lua 5.1工具，因此不宣称本轮Lua 5.1验证。
- 回音重斩、陨石坠落、元气弹三项状态测试及回音重斩、脉冲激射、魔法弹弓、陨石坠落、元气弹五项视觉契约通过。移动冰球视觉契约仍因本任务前已有的旧基础弹体常量失败，地裂差异未触碰该区域。
- 7个任务文件严格UTF-8、限定`git diff --check`和粒子编译产物存在性检查通过。

### 地裂冲击后续修改入口

- 配置或文案修改必须先改`data/csv/英雄系统/hero_skill_definitions.csv`和`data/csv/公共规则/tooltip_definitions.csv`，再定向生成对应Lua；禁止直接维护生成Lua。
- 数值和等级行为修改同步检查`scripts/vscripts/config/hero_passive_skill_definitions.lua`、`scripts/npc/npc_abilities_custom.txt`和`scripts/vscripts/ui/ability_runtime_service.lua`。
- 移动、碰撞、伤害、眩晕、首次范围伤害或清理规则修改集中在`scripts/vscripts/systems/hero_passive_skill_service.lua`，继续复用线性投射物、逻辑属性快照和现有伤害事务，不恢复旧`line_targets()`瞬时扫描。
- 修改后至少运行`tools/test_earth_line_visual_contract.ps1`、`scripts/vscripts/tests/test_earth_line_visual.lua`、可用的Lua语法检查、Resource Compiler强制编译、严格UTF-8、限定`git diff --check`以及相关公共技能回归。
- 当前唯一剩余动作是Workshop Tools冷启动实机验收：确认卡尔陨石尺寸/高度、贴地、固定方向、500速度与碰撞同步、完整路径连续、并行实例以及正常终点/超时后无残留；自动测试不能替代引擎验收。

## 活跃任务（2026-08-02）

将公共技能`proto_meteor`重做为五级“陨石坠落·被动”，保留Ability ID `ability_survival_meteor`、公共池身份、图标和存档兼容性。

## 用户已确认边界

- LV1普通攻击命中12%概率触发，记录目标当时的地面位置；陨石坠落后原地爆炸，不进行卡尔原版陨石的滚动。500半径造成触发时逻辑全属性×3纯粹伤害。
- LV2每颗陨石留下500半径、持续3秒的熔岩区域；落地后第1/2/3秒各造成一次触发时全属性×1纯粹伤害，落地瞬间不额外结算熔岩伤害。
- LV3熔岩区域内敌人降低30%移动速度；离开所有区域立即移除，多个区域重叠不叠加。
- LV4完整继承LV3，无新增效果。
- LV5在同一记录位置连续落下两颗陨石，第二颗比第一颗晚0.5秒落地；第二颗爆炸和熔岩伤害均为80%，即×2.4和每秒×0.8。两片熔岩独立造成伤害。
- 同一英雄从触发成功到最后一颗陨石的最后一次熔岩伤害完成前，不再进行该技能的12%概率判定；LV1在爆炸完成后解锁。锁不影响其他被动技能。
- 所有伤害复用触发瞬间的同一份项目逻辑三维快照、既有伤害服务和Ability句柄。

## 当前状态

**CSV、运行配置、被动服务、Ability KV、Tooltip、Buff、定向生成和自动测试均已完成。用户已于2026-08-02实机确认`addmonster` 600移速测试基准下的熔岩30%减速正常；其余表现仍按用户后续验收结论记录。**
- 元气弹飞行视觉已替换为 Sven Storm Hammer 完整追踪弹体；LV5独立20%范围爆炸已替换为 Storm Hammer 原生爆炸，权威伤害范围继续读取技能定义的250码。

## 工作区保护

- 调查阶段后出现最新提交`c36c56e`；已确认目标服务工作区哈希与HEAD一致，属于既有改动安全提交，不是回滚或外部未提交覆盖。
- 当前仍有大量未跟踪测试文件；不得删除、覆盖或顺带整理。本任务仅新增陨石专项测试并修改直接相关文件。
将公共技能 `proto_flame_burst` Lv5 三颗随机溅射小火球的视觉从莉娜龙破斩替换为 Snapfire Mortimer Kisses，保留显示名“爆炎弹·被动”、Ability ID `ability_survival_flame_burst`、公共池身份及全部五级战斗规则。
- `SPIRIT_BOMB_VISUAL_STATE_PASS` / `SPIRIT_BOMB_VISUAL_CONTRACT_PASS`
- 元气弹视觉生产Lua与新状态测试通过当前Lua/Luac 5.4.5语法；四个任务文件通过严格UTF-8、无BOM和尾随空白检查；限定`git diff --check`通过。
- `SPIRIT_BOMB_STATE_LUA51_PASS` / `SPIRIT_BOMB_CONTRACT_PASS`
- `POISON_CLOUD_STATE_LUA51_PASS` / `POISON_CLOUD_CONTRACT_PASS`
- 奥术弹幕、魔法弹弓、爆炎弹、移动冰球、寒冰锥、脉冲激射和龙卷风相关回归通过。
- 8个相关Lua文件通过 `luac5.1 -p`；12个相关源/生成/测试文件通过严格UTF-8检查；CSV与生成Lua的元气弹字段一致；限定范围 `git diff --check` 通过。
- 完整生成器在本任务无关的 `item_definitions.csv` 历史列错位处失败；已使用同一生成模块定向重建英雄技能，并使用Tooltip专用生成器重建Tooltip。生成内容差异仅包含本任务两份目标Lua。

## 自动验证结果

- `METEOR_STATE_LUA51_PASS` / `METEOR_CONTRACT_PASS`。
- `METEOR_LUAC_PASS`：运行配置、公共被动服务、Tooltip服务、三份生成Lua和专项状态测试通过Lua 5.1语法检查。
- `METEOR_GENERATED_COMPARE_PASS`：英雄技能和Buff生成Lua与权威CSV定向重建结果逐字节一致；Tooltip专用生成器通过并仅改变陨石目标行。
- 奥术弹幕、寒冰锥、魔法弹弓、爆炎弹、移动冰球、毒云、元气弹、脉冲激射和龙卷风专项回归全部通过。
- 本任务12个核心源/生成/测试文件通过严格UTF-8和乱码检查；限定`git diff --check`通过。
**陨石坠落视觉现由卡尔Chaos Meteor飞行粒子负责0.8秒坠落，落地时立即清除卡尔陨石并衔接术士Rain of Chaos纯爆炸粒子；不创建地狱火单位。**
- 术士爆炸使用独立ID和注册表管理，完整播放3.1秒后强制销毁并释放；LV1解锁不会提前截断爆炸，LV5两次爆炸独立清理，`clear_meteors()`会取消任务并立即清除全部残留，迟到回调幂等。
- 本轮验证：`METEOR_VISUAL_STATE_PASS`、`METEOR_VISUAL_CONTRACT_PASS`和目标Lua 5.4语法通过；爆炎弹、怒雷、元气弹视觉状态/契约及剑刃震荡视觉契约通过。合并基线中的移动冰球重复粒子常量仍导致其Puck Orb状态断言失败，本任务未修改该无关区域。

## 剩余动作

- 陨石LV3-LV5减速专项已验收：实际数值为30%而非20%；可攻击`addmonster`使用600基础移速和600移速上限后，用户实机确认减速正常。正常波次怪物未改变，不可攻击调试怪仍为0移速。
- 冷重启Workshop Tools，确认多目标Storm Hammer弹体均正确追踪、普通命中自带EndCap爆裂、LV5额外爆炸位置正确且连续触发无粒子残留。
- 完全重启 Workshop Tools Run，实机验证追踪视觉、5/7/9目标数量、每颗命中伤害与治疗、LV5独立爆炸及毒云活动期间不重触发。
- 自动测试、契约检查和Lua模拟不能替代实机验证；只有用户明确确认后才能记录为完成验收。

## 元气弹已确认边界

- LV1主攻击命中12%概率触发，在英雄普攻范围内选择最近最多5个敌人并分别发射追踪投射物；每颗真实命中造成触发时逻辑全属性×4纯粹伤害。
- LV2每颗真实命中恢复英雄5%最大生命值；按实际命中数累计并不超过最大生命值。
- LV3基础目标上限提高到7，每次触发另有10%概率提高到9；LV4完整继承LV3，无新增效果。
- LV5每颗命中独立20%概率在目标位置产生250范围爆炸，范围内所有敌人受到该颗基础伤害60%的额外纯粹伤害；原命中目标重复计算爆炸伤害。
- 攻击射程复用现有运行缓存、Script API、引擎API和英雄生成配置回退；投射物使用 `CreateTrackingProjectile` 和真实命中回调。

## 毒云新增边界

- 同一英雄已有活动毒云时，不再进行该技能的再次触发判定，也不替换旧毒云；仅在旧毒云自然结束或清理后允许再次触发。

## 已确认边界

- LV1主攻击命中15%概率触发；主龙卷从攻击者位置出发，以500速度实时追踪原攻击目标当前位置。
- 主龙卷第一次到达目标后附着跟随：目标移动时龙卷中心直接同步目标当前位置，不再产生500速度追赶距离。
- 原攻击目标在到达前死亡时，主龙卷继续移动到目标最后存活位置；在附着后死亡时，龙卷固定在死亡位置。两种情况均静止等待3秒结束。
- 主龙卷在t=0/1/2结算三次；每次实时读取攻击者当前逻辑力量、敏捷、智力总和，对中心300范围内每个敌人最多造成一次全属性×2纯粹伤害。
- 龙卷影响范围为中心600。LV3起范围内敌人降低20%移动速度；被主龙卷命中的敌人在仍处于600范围时额外降低15%，总计35%；离开范围立即移除对应效果。
- LV2仅完整继承当前速度500与LV1效果；LV4完整继承LV3，无新增效果。
- LV5主龙卷结束时统计仍存活且曾被主龙卷命中的不同目标。每个目标对应一个无上限小龙卷，从主龙卷结束位置朝随机目标方向移动。
- 小龙卷持续2秒，速度500、影响范围600、命中范围300、t=0/1结算；每次实时属性伤害为主龙卷的60%，即全属性×1.2纯粹伤害。
- 小龙卷只施加范围20%减速，不施加主龙卷命中额外15%减速，也不继续分裂。
- “随机目标方向”使用主龙卷结束时仍存活的已命中目标作为方向候选。
- 飞行主体使用 `particles/units/heroes/hero_snapfire/hero_snapfire_ultimate.vpcf`，CP0为主爆炸中心，CP1为按随机落点与0.5秒飞行时间计算的速度。
- 落地瞬时冲击使用 `particles/units/heroes/hero_snapfire/hero_snapfire_ultimate_impact.vpcf`，CP3为权威随机落点。
- 不使用持续3.1秒的`hero_snapfire_ultimate_linger.vpcf`，也不使用原生半径约428的`hero_snapfire_ultimate_calldown.vpcf`，避免错误暗示持续伤害或错误范围。
- 不改变15%触发、500主爆炸范围与×4伤害、点燃规则、LV5三颗、200随机落点、0.5秒同步落地、250溅射范围、×3伤害及逐颗点燃结算。
- 粒子只负责表现；随机落点、同步时序、目标查询、伤害和点燃继续由Lua权威逻辑负责。

## 验证结果

- `TORNADO_STATE_LUA51_PASS`
- `TORNADO_CONTRACT_PASS`
- `FLAME_BURST_STATE_LUA51_PASS` / `FLAME_BURST_CONTRACT_PASS`
- `POISON_CLOUD_STATE_LUA51_PASS` / `POISON_CLOUD_CONTRACT_PASS`
- `MOVING_ICE_BALL_MATH_LUA51_PASS` / `MOVING_ICE_BALL_CONTRACT_PASS`
- `MAGIC_SLINGSHOT_TARGETS_LUA51_PASS` / `MAGIC_SLINGSHOT_CONTRACT_PASS`
- `ICE_CONE_CONTRACT_PASS`
- `BLADE_PULSE_STATE_LUA51_PASS` / `BLADE_PULSE_CONTRACT_PASS`
- 相关生产、配置和测试 Lua 均通过 `luac5.1 -p`；严格 UTF-8 检查通过；限定范围 `git diff --check` 通过；CSV与生成Lua关键字段一致。
- Workshop Tools冷启动确认三颗Mortimer Kisses弹体的朝向、速度、同步落地、CP3冲击位置、重叠表现及无粒子残留。
- 该检查点执行时历史Lua 5.1路径不可用，只完成了Lua 5.4.5检查；2026-08-03已在`C:\Program Files\lua\bin`恢复Lua 5.1.5工具，并完成当前`scripts/vscripts`全部306个Lua文件的`luac5.1 -p`验证。
- 全量63个Lua测试中54个通过、9个既有无关测试失败；目标爆炎弹状态测试及全部相邻视觉状态/契约均通过，失败清单已记录在`SESSION_LOG.md`。

## 后续优化与剩余确认

- 2026-08-03用户批准为`proto_void_pulse`使用卡尔原版龙卷主体外观，同时保留可靠的Lua追踪与附着架构。已恢复可维护content源`particles/survival_tornado/survival_tornado_follow.vpcf`：父粒子只引用`particles/units/heroes/hero_invoker/invoker_tornado_child.vpcf`，没有`C_OP_BasicMovement`或其他内部位移算子。
- 生产代码无需重写：主龙卷与LV5小龙卷已经统一创建项目粒子，共享调度器每0.05秒只写CP0，结束与清局均销毁释放；`addon_game_mode.lua`也已预缓存项目粒子。完整`invoker_tornado.vpcf`不会接入，因为其实机内部直线推进会脱离Lua权威伤害中心。
- 新增`tools/test_tornado_visual_contract.ps1`，锁定三选一身份、卡尔子粒子依赖、禁止完整父粒子、主/小龙卷创建、CP0同步、释放与预缓存。Resource Compiler强制编译结果为`1 compiled, 0 failed, 0 skipped`，生成产物与game仓库已有跟踪产物无差异；契约、Lua 5.4.5语法、严格UTF-8、编译依赖和限定检查通过。
- 相邻视觉契约共10项，7项通过；3项既有无关失败分别为魔法弹弓测试全局排斥地裂冲击正在使用的Tiny资源、移动冰球旧断言、毒云旧创建模式断言。本任务没有为这些陈旧断言修改其他技能。当前没有Lua 5.1命令，因此不宣称本轮Lua 5.1验证通过。
- 后续继续本任务时，再按用户指定重点优化龙卷视觉、追踪手感或其他表现；不得在没有明确需求时主动改变当前行为和数值。
- 尚未记录为最终用户验收的项目包括：完全重启Workshop Tools Run后的龙卷追踪、到达后附着、目标死亡后的最后位置、范围减速、实时属性伤害和LV5分裂方向。
- 若仍异常，收集同一龙卷ID的`[HeroTornado] event=spawn/attached/target_dead/finish`日志；普通`[CombatDamage]`日志只能证明伤害事务，不能证明视觉位置。

## 恢复规则

- 当前任务处于“阶段性完成/暂停优化”状态，不是活跃编码任务。
- 新会话不得自动继续修改；只有用户明确要求继续优化该技能时，才恢复为活跃任务。
- 恢复时以本文件中的已确认边界和`PROJECT_CONTEXT.md`中的稳定粒子架构为基线。

## 工作区保护

- 工作区已有大量用户未提交修改，目标服务和游戏模式文件在本任务前已处于修改状态。
- 只在当前内容基础上替换目标粒子常量和对应预缓存，不回滚、覆盖或顺带清理其他修改。
- 完全重启 Workshop Tools Run，实机验证卡尔Chaos Meteor从空中坠落并在落地时消失、同点衔接术士Rain of Chaos纯爆炸且不出现地狱火单位、爆炸约3.1秒后无残留、Viper Nethertoxin熔岩继续存在、双陨石0.5秒落地间隔、500范围、3次跳伤、30%减速进入/离开和活动期间不重触发。
- 自动契约、Lua模拟和语法检查不能证明Dota粒子的实际尺寸、颜色、落地手感或引擎最终扣血；只有用户明确确认后才能记录为实机验收完成。

## 活跃任务（2026-08-04）：齐天大圣棍式棒击大地视觉对齐

- 用户实机报告齐天大圣专属Q“棍式”的砸棍主体与地面特效没有重合。调查定位到`scripts/vscripts/systems/monkey_king_exclusive_service.lua`：原版`monkey_king_strike.vpcf`只收到CP0起点及CP1/CP2终点，没有收到本次Q权威方向对应的CP0 Forward；视觉和Lua矩形虽共用端点，但砸棍子效果缺少可靠朝向。
- 已实施最小视觉修复：同一次Q触发计算的`origin/direction/length`同时驱动视觉和Lua矩形；视觉CP0、CP1、CP2只对Z使用`GetGroundPosition`贴地，X/Y保持权威起终点；CP0通过`SetParticleControlForward`写入归一化水平攻击方向。本体与分身继续共用同一个`trigger_q()`路径。
- 战斗边界不变：10%触发、1200长度、200总宽、全属性×30纯粹伤害、10%最大生命纯粹伤害、每目标最多3次共享计数和Lua矩形判定均未修改；没有把粒子改为碰撞或伤害权威。
- 视觉创建及控制点写入使用受保护调用。失败时立即销毁已创建粒子并尝试释放索引，视觉异常不会中断后续Q伤害事务。
- 新增`tools/test_monkey_king_boundless_visual.lua`和`tools/test_monkey_king_boundless_visual_contract.ps1`。状态测试覆盖斜向CP0 Forward、起终点地面Z、1200路径、同位置时英雄Forward兜底、分身复用、粒子异常清理及伤害继续；静态契约锁定原版粒子与预缓存、同源视觉/伤害几何、原Q数值和Lua矩形。
- 自动验证通过：`MONKEY_KING_BOUNDLESS_VISUAL_STATE_PASS`、`MONKEY_KING_BOUNDLESS_VISUAL_CONTRACT_PASS`、`ALT_HERO_ABILITY_ORIGIN_DEV_CONTRACT_OK`、生产/测试/游戏模式Lua与Luac 5.4.5语法、任务代码与测试严格UTF-8及限定`git diff --check`。`SESSION_LOG.md`可严格UTF-8解码且本轮新增段无`U+FFFD`，未改写该文件已记录的3个历史替换字符。当前Lua 5.1历史路径均不存在，不宣称Lua 5.1验证。
- 尚待完全停止并重新Run Workshop Tools实机验收：本体与分身在八个水平朝向、平地/坡面及连续触发时，确认砸棍主体、地面线效和1200×200实际命中方向重合，结束后无粒子残留。自动测试不能证明原版VPCF内部模型最终画面；若仍有固定内部偏移，再进入项目包装粒子阶段，不添加经验性世界坐标偏移。

### 新增快速落棍动画（2026-08-04）

- 用户确认原偏离问题已修复，并批准新增“极快棍体从半空砸向地面”的完整同步方案：先播放落棍，约0.14秒落地时再同时播放原版地面棒击并结算伤害；落地帧按触发时固定的1200×200矩形重新扫描，因此敌人可以走出躲避或走入受击。
- 新增content源`particles/survival_monkey_king/survival_monkey_king_staff_drop.vpcf`及game编译产物。项目粒子派生自Valve `monkey_king_strike_cast_modelonly.vpcf`的模型表现参数，直接复用`models/props_items/monkey_king_bar01.vmdl`和金箍棒特效材质；单载体从路径地面中点上方800高度以CP2速度在0.14秒内下落，不含Children、地面冲击、震屏、碰撞或战斗逻辑。
- `trigger_q()`现在在触发时快照固定`origin/direction/length/total_width`和全属性伤害，创建独立落棍实例；落地回调先清理落棍、播放当前已对齐的完整`monkey_king_strike.vpcf`，再按固定几何扫描。最大生命部分读取落地目标当前最大生命；10%触发、1200×200、全属性×30、最大生命10%、每目标最多3次共享计数和纯粹伤害数值均未改变，但结算时机按用户批准延后约0.14秒。
- 本体与分身继续共用同一个`trigger_q()`；并行实例使用独立ID和任务。落棍或地面视觉失败均不阻断落地伤害；攻击者实体已删除时取消；服务重置会取消全部未落地任务、销毁释放活动落棍，迟到回调幂等。
- 项目落棍粒子已加入`addon_game_mode.lua`预缓存。Resource Compiler强制定向编译为`OK: 1 compiled, 0 failed, 0 skipped`；编译DATA和依赖检查确认0.14秒寿命、CP2速度、基础移动、模型渲染、Valve模型/材质且无Children。
- 更新专项状态与静态/资源契约。验证通过：`MONKEY_KING_BOUNDLESS_VISUAL_STATE_PASS`、`MONKEY_KING_BOUNDLESS_VISUAL_CONTRACT_PASS`、`ALT_HERO_ABILITY_ORIGIN_DEV_CONTRACT_OK`、目标Lua/Luac 5.4.5语法、严格UTF-8/末尾换行/尾随空白及限定`git diff --check`。历史Lua 5.1路径不存在，不宣称Lua 5.1验证。
- 尚待完全停止并重新Run Workshop Tools实机验收：确认800高度、0.14秒速度、棍体比例/材质/俯仰、八方向、坡地、本体/分身、连续并行、空中棍与地面棍衔接、落地帧伤害和结束无残留。自动测试不能证明粒子最终姿态与手感。

### 落棍力量感优化（2026-08-04）

- 用户实机反馈0.14秒匀速砸棍过快，希望增加下砸过程并强调力量感；用户批准采用更利落的0.28秒加速重砸方案，而不是单纯延长匀速慢放。
- 落棍高度由800提高到1000，总时长由0.14秒提高到0.28秒，CP2初始向下速度改为350；项目VPCF的`C_OP_BasicMovement`增加Z轴`-23010`加速度。理论0.28秒位移为999.992、末速度约6793，形成前段可辨认、中后段持续加速、末段高速撞地的运动曲线。
- 完整地面棒击、落地重扫和伤害继续与落棍结束同步，故用户已批准的伤害延迟由约0.14秒调整为约0.28秒。触发时固定1200×200几何、落地帧目标重扫、属性快照、当前最大生命、共享3次计数以及全部概率/范围/倍率均未改变。
- 更新专项状态和资源契约，锁定1000高度、0.28秒、350初速、负Z加速度、运动方程与大于6700的末速度。Resource Compiler强制编译为`OK: 1 compiled, 0 failed, 0 skipped`；编译DATA确认新寿命、CP2、负Z加速度和Valve模型。
- 验证通过：`MONKEY_KING_STAFF_DROP_ACCELERATED_DATA_PASS`、`MONKEY_KING_BOUNDLESS_VISUAL_STATE_PASS`、`MONKEY_KING_BOUNDLESS_VISUAL_CONTRACT_PASS`、`ALT_HERO_ABILITY_ORIGIN_DEV_CONTRACT_OK`及目标Lua/Luac 5.4.5语法。仍需Workshop Tools冷启动确认加速曲线、力量感、调度帧衔接、八方向、坡地、本体/分身、并行与无残留。
