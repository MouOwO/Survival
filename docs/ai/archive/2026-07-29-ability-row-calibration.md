# Current Task

## 2026-07-29 当前活跃任务：运行时技能行锚点校准器

### 最新状态覆盖（2026-07-29）

- 用户实机确认：此前以官方 `abilities` 容器左上角作为固定技能行锚点后，所有技能超出原来的技能范围；因此 `grid52_topleft_v3` 的左上角方案已被实机否定，不再把它视为只差验收的最终方案。
- 用户提出中下锚点可能更合理，但明确表示不敢直接确定，希望能自己运行时调整锚点并立即观察分布。
- 用户已批准完整校准方案：九宫格锚点、X/Y 微调、Valve 容器/可见技能/项目行边界框和参数输出。
- 当前实施目标：只改 Panorama 几何表现层，保留固定 52×52、4px 间距、视觉顺序映射、原子接管/整批回退、官方压制、Q/W/E/R/T/Y/U、技能输入和 Tooltip。
- 中下锚点只是校准器的候选值，不在实机比较前固化为长期布局决策。

### 实施计划

1. 在 `hud_takeover.js` 建立统一校准状态与九宫格对齐公式，提供设置锚点、X/Y 微调、重置、显示/隐藏和参数输出 API。
2. 在 HUD XML/CSS 增加游戏内校准面板及非命中的边界可视化层。
3. 调试边界分别显示 Valve `abilities` 容器、Valve 当前可见技能包围范围、项目技能行和锚点十字。
4. 更新源码契约测试，强制编译 JS/CSS/XML，运行定向及 32 项全量测试和限定差异检查。
5. 用户在 Workshop Tools 中比较 1、2、7 技能状态，输出最终 `alignment/offset_x/offset_y` 后再固化正式布局。

### 实施与自动验证结果（2026-07-29）

- `hud_takeover.js` 已实现九宫格同点对齐并固化带版本迁移的正式预设；当前版本为 `grid52_preset_v6`。
- 面板支持九宫格、X/Y ±1/±5、重置、关闭和输出参数；蓝/黄/绿边界与红十字均为非命中调试节点。
- 控制台命令：`survival_ability_calibration` 显示/隐藏面板，`survival_ability_calibration_dump` 输出当前参数。
- 定向测试：`ARROW_TOWER_COMPLETION_PASS`，新增正式预设、迁移、来源和统一重置契约通过。
- 全量测试：`.cline_tmp/preset_v6_all_tests.txt` 末尾为 `ALL_LUA_TESTS total=32 failed=0`。
- 强制编译：`hud_takeover.js` 返回 `OK: 1 compiled, 0 failed, 0 skipped`；产物已刷新到 game 目录。
- game 侧 `hud_takeover.vjs_c` 已于 `2026-07-29 10:38:08 +0800` 刷新，大小 61756 字节；限定 `diff --check` 通过。

### 当前阶段

**正式预设与状态版本迁移已完成自动验证，等待 Workshop Tools 实机验收。**

### 2026-07-29 正式预设修复

- 最新实机截图和日志确认，重新 Run 后界面实际使用 `top_left / X=0 / Y=0`，并非此前调好的 `middle_left / X=5 / Y=35`。
- 根因是 `SurvivalAbilityCalibrationState` 只保存在当前 `CustomUIConfig` 运行时对象中，而源码初始化与 `resetCalibration()` 仍硬编码旧值。
- 用户已明确批准：以事件驱动 v5 为现有行为基线，把 `middle_left / X=5 / Y=35` 作为正式启动和重置预设，并增加预设版本迁移和参数来源日志。
- 保留范围：不改九宫格几何公式，不改 `visualBounds`，不改 52×52、4px、选择事件、有界无闪重试、技能输入和 Tooltip。

### 下一步唯一动作

1. 完全停止 Workshop Tools 并重新 Run。
2. 执行 `survival_ability_calibration_dump`，确认日志为 `build=grid52_preset_v6 preset_version=1 source=preset_default alignment=middle_left offset_x=5 offset_y=35`。
3. 比较 1、3、5、7 技能的位置，并快速切换英雄、农民、建筑和箭塔，验收响应速度与 Valve 原图标是否仍闪现。

---

## 被覆盖的 2026-07-28 状态：固定技能行左上角对齐收尾

### 最新状态覆盖（2026-07-28 23:19）

- 用户最新实机确认：单技能与多技能图标大小相同，地面 Tooltip 已成功；只剩多技能技能行更高，要求按左上角对齐修复。
- 根因：固定行虽然为 52×52，但 `measureFixedRowGeometry()` 仍用 Valve 内部按钮包围盒的底边定位；内部按钮会随技能数量上下移动。
- 已实施：整行改用官方 `abilities` 容器左上角作为 `x/y`，技能数量只改变向右延伸的固定行宽；视觉顺序映射、原子接管、整批回退、官方压制和技能输入保持不变。
- 版本标识：`build=grid52_topleft_v3|cell=52|gap=4`。
- 自动验证：`ARROW_TOWER_COMPLETION_PASS`；`ALL_LUA_TESTS total=32 failed=0`；`hud_takeover.js` 强制编译 `OK: 1 compiled, 0 failed, 0 skipped`，产物时间 `2026-07-28 23:19:30 +0800`；限定 `diff --check` 通过。
- 尚未确认：Workshop Tools 中 1、2、7 个技能是否最终共享同一左边和顶边。
- 下一步唯一动作：完全停止 Workshop Tools 并重新 Run；先确认日志为 `grid52_topleft_v3`，再对比 1 个与 7 个技能的左边/顶边。

---

## 历史任务基线：小尺寸固定技能网格与地面物品本地化加载修复

### 用户最新反馈与批准

- 实机确认技能数量会改变项目图标大小：1～2 个技能较大，7 个技能较小。用户要求改成 Unity `GridLayout + ContentSizeFitter` 等价结构，每个 cell 固定大小。
- 实机地面物品仍只显示官方 Tooltip 外框、图标和“技能：被动”，标题与说明为空；此前“专属真实地面物品已修复官方 Tooltip”的视觉结论无效。
- 用户询问能否运行时 `CreateItem` 后给任意名称、说明、图标赋值，或通过官方编辑器完成；已确认官方 UI 依赖注册物品名对应的静态 KV 与本地化，Lua 实例字段不是 Tooltip 元数据。
- 最新实机确认 65×65 明显偏大，用户要求按此前小图标尺寸修正。
- 两类日志已返回：掉落 requested/actual 一致；六种材料本地化全部返回原始 `#token`。
- 本轮采用固定 52×52 技能行，并把完整本地化同步到游戏与 Panorama 标准加载路径。
- 用户再次贴出的日志仍只有六种材料，没有最新版 control 字段；已确认这是旧 HUD 日志，不能作为 52px 与标准本地化修复后的验收结果。

### 已确认事实

1. `hud_takeover.js` 的 `applyOfficialGeometry()` 直接把 Valve 锚点的 `geometry.width/height` 赋给项目按钮，因此 cell 会随技能数量和官方可用空间变化。
2. 历史 65×65 技能槽基线经实机判定偏大；当前固定值改为 52×52，技能数量只影响整行宽度和居中位置。
3. 视觉顺序映射、原子接管、整批回退与官方按钮压制必须保留；固定尺寸不能恢复按 `AbilityN` 稠密索引映射。
4. `challenge_equipment_reward_service.lua` 已按 CSV 调用 `CreateItem(engine_item_name)` 和 `CreateItemOnPositionSync`，并非仍统一创建通用奖励。
5. `item.survival_content_id` 等字段只供服务端逻辑使用；Valve 世界 Tooltip 不会自动读取这些字段作为名称、说明或图标。
6. 六种材料已有静态 KV 和文本内容，但完整文件误放在 `resource/localization/`；标准根目录英文仍是模板、中文缺失，因此引擎和客户端都没有加载 token。

### 实施范围

- `content/dota_addons/survival/panorama/scripts/custom_game/hud_takeover.js`
  - 固定技能行 cell 改为 52×52、固定间距，整行以官方技能组中心和底部基准定位。
  - Valve 几何只用于完整映射、整组中心/基准和官方视觉压制，不再决定 cell 宽高。
  - 增加一次性材料本地化 token 诊断。
- `content/dota_addons/survival/panorama/styles/custom_game/ability_tooltip.css`
  - 固定技能 cell 尺寸并声明固定行布局语义。
- `scripts/vscripts/systems/challenge_equipment_reward_service.lua`
  - 掉落创建日志增加 requested/actual engine item name。
- 标准本地化入口
  - 游戏：`resource/addon_english.txt`、`resource/addon_schinese.txt`。
  - Panorama：`content/.../panorama/localization/addon_english.txt`、`addon_schinese.txt`，并同步游戏目录文本产物。
- 定向测试
  - 固定 52×52 和禁止继承 Valve 宽高的源码防回归。
  - 掉落测试模拟 `GetAbilityName()` 并确认返回/诊断使用实际引擎身份。
- 同步更新 `docs/ai`。

### 验收标准

1. 1、2、7 个技能都保持 52×52；只改变整行宽度，行围绕官方技能区域居中。
2. 七技能保持 `Q/W/E/R/T/Y/U`，无残留 Valve 技能按钮；映射不完整时整批回退官方 UI。
3. 服务端日志同时显示 requested 与 actual item name，测试确认两者一致。
4. 客户端初始化只输出一次六种材料名称/说明 token 的解析结果，不增加高频轮询。
5. 六个 CSV 映射均对应 KV 定义，并且中英文名称与说明存在于实际加载的游戏/Panorama 标准路径。
6. Panorama 强制编译 `compiled > 0`、`failed=0`；相关 Lua 语法、定向/全量测试和限定 `diff --check` 通过。
7. 完全停止并重启 Workshop Tools 后实机确认技能尺寸与挑战 05/07/08/09 地面 Tooltip。

### 当前阶段

**52px、标准本地化路径和不可混淆的版本诊断已完成自动验证；等待完全重启后的实机验收。**

### 下一步唯一动作

- 完全停止 Workshop Tools 并重新 Run。
- 依次选择 1、2、7 个可见技能的单位，确认 cell 始终为小尺寸固定值，七技能连续显示 `Q/W/E/R/T/Y/U` 且没有 Valve 残留按钮。
- 首条 `[SURVIVAL_GROUND_ITEM_LOCALIZATION]` 必须以 `build=grid52_loc_v2|cell=52|gap=4` 开头；否则当前 Run 仍是旧 HUD，不能用于验收。
- 触发挑战 05 地面掉落；同一条新版日志中的 control 与材料 token 应输出真实文本而非 `#token`，官方世界 Tooltip 应显示标题与说明。

### 实施与自动验证结果

- HUD：`SurvivalAbilityTakeoverRow` cell 已由偏大的 65×65 修正为固定 52×52，间距 4px；整行继续根据完整官方锚点组的中心和底部定位。
- 原子行为：映射失败时折叠整行并恢复全部 Valve UI；成功时整批显示固定行并压制全部对应官方按钮。
- 物品诊断：服务端日志增加 `requested_item`/`actual_item`；返回结果公开实际引擎物品名。客户端只在 HUD 初始化输出一次六种材料的名称与说明解析值。
- 静态契约：测试覆盖六个 CSV 映射、六个 KV 注册及中英文名称/说明 token。
- 定向测试：`ARROW_TOWER_COMPLETION_PASS`、`MOLTEN_CORE_GROUND_DROP_PASS`。
- 全量测试：`ALL_LUA_TESTS total=32 failed=0`。
- 语法与差异：相关 `luac -p` 通过；game/content 限定 `diff --check` 通过，仅有既有 LF/CRLF 提示。
- Panorama 编译：`hud_takeover.js` 为 `1 compiled`；`ability_tooltip.css` 为 `1 compiled`；`survival_hud.xml` 加载链为 `7 compiled`；全部 `0 failed / 0 skipped`。
- 本轮追加验证：标准游戏/Panorama 中英文词典结构、括号、引号与关键 token 校验通过；`ARROW_TOWER_COMPLETION_PASS`、`MOLTEN_CORE_GROUND_DROP_PASS`、Lua 语法和 `ALL_LUA_TESTS total=32 failed=0`；JS/CSS 于 22:30:57～22:30:58 强制编译，各 `1 compiled, 0 failed, 0 skipped`。
- 本轮编译产物时间：`2026-07-28 22:30:57～22:30:58 +0800`。
- 断连后最终补强：一次性诊断新增 `build=grid52_loc_v2|cell=52|gap=4`，并保留 `addon_game_name` 与通用挑战奖励 control；源码测试增加版本/尺寸防回归断言。
- 最终自动验证：`ARROW_TOWER_COMPLETION_PASS`、`MOLTEN_CORE_GROUND_DROP_PASS`、`ALL_LUA_TESTS total=32 failed=0`；更新后的 `hud_takeover.js` 为 `1 compiled, 0 failed, 0 skipped`，HUD XML 加载链为 `7 compiled, 0 failed, 0 skipped`。
- 最终编译产物时间：`2026-07-28 23:05:38 +0800`；`hud_takeover.vjs_c`、`ability_tooltip.vcss_c`、`survival_hud.vxml_c` 均已刷新。

---

## 被本任务覆盖的历史记录

以下内容保留为历史证据，不再代表当前活跃结论。

## 2026-07-28 历史任务：箭塔技能 UI 双重显示与槽位跳号

### 用户最新反馈与批准

- 实机截图中同时出现项目大按钮和 Valve 官方小按钮。
- 项目按钮连续视觉位置显示 `Q/W/T`，不是 `Q/W/E`；右侧官方小按钮图标对应 `ability_tower_class_4` 的 `sniper_take_aim` 与 `ability_tower_class_6` 的 `lich_frost_nova`。
- 用户已确认实施完整方案：视觉顺序映射、原子接管/整批回退、强化官方视觉压制、服务端转职能力确定顺序、状态变化映射日志、编译和回归验证。

### 已确认根因

1. `visibleAbilities()` 按实体槽位生成稠密技能数组，但刷新仍使用稠密 `displayIndex` 直接查 `Ability0/Ability1/...`。
2. 箭塔 5 级时 `tower_ability_sync.lua` 删除原升级技能，随后 `building_upgrade_system.lua` 动态追加七个转职技能；Valve HUD 可复用、重建或保留带空洞的 `AbilityN` 节点。
3. 当前刷新逐槽执行定位、压制和代理更新；任何中间槽缺失只折叠该代理，不会撤销已提交槽，也不会恢复其余官方按钮，因此能形成半项目、半官方 UI。
4. 官方压制只查固定内部 ID；缺少 `ButtonWell` 时没有可靠压制实际 `AbilityButton`。
5. `pairs(class_options)` 为数组转职配置引入不必要的能力添加/清理顺序风险。

### 实施范围

- `content/dota_addons/survival/panorama/scripts/custom_game/hud_takeover.js`
  - 枚举有效 `Ability0..Ability23`，读取内部按钮锚点并按窗口 X/Y 视觉顺序排序。
  - 完整构造技能与官方按钮映射后再一次性提交；任一数量、锚点、几何或代理创建校验失败时折叠全部项目代理并恢复全部官方按钮。
  - 快捷键按最终视觉顺序生成 `Q/W/E/R/T/Y/U`，不再由 Valve 节点 ID 决定。
  - `ButtonWell` 缺失时压制实际 `AbilityButton`。
  - 新增仅映射签名变化时输出的 `[SURVIVAL_TAKEOVER_MAP]`。
- `scripts/vscripts/systems/building_upgrade_system.lua`
  - 转职数组遍历改为确定性的 `ipairs()`。
- `scripts/vscripts/systems/tower_ability_sync.lua`
  - 转职能力清理遍历同样改为确定性的 `ipairs()`。
- 同步更新 `docs/ai` 恢复文档。

### 验收标准

1. 5 级箭塔七个项目技能连续显示 `Q/W/E/R/T/Y/U`。
2. 不再同时显示任何 Valve 官方技能图标。
3. 项目按钮均使用其当前视觉官方锚点的真实按钮尺寸，不因 `AbilityN` 空洞取错节点。
4. HUD 动态重排期间若映射不完整，只显示完整官方 UI，不出现混合 UI；稳定后自动恢复完整项目代理。
5. 英雄、农民、普通建筑和转职后箭塔没有几何、Tooltip、点击或快捷键回归。
6. Panorama 强制编译 `compiled > 0`、`failed=0`；Lua 语法、现有全量测试和限定 `diff --check` 通过。

### 当前阶段

**用户已批准，正在实施。**

### 下一步唯一动作

- 完成代码编辑和自动验证；随后完全停止并重新 Run，实机检查七技能箭塔及选择切换。

## 2026-07-28 新任务：专属真实地面物品与官方 Tooltip

### 用户批准的架构

- 地面掉落物继续使用 Valve 官方世界物品 Tooltip、鼠标命中与拾取交互。
- 挑战材料不再统一创建 `item_survival_challenge_reward`，改为按业务 `content_id` 创建已在 `npc_items_custom.txt` 注册的专属真实 Dota 物品。
- 背包内继续使用项目现有 `inventory_tooltip.js` 气泡，不重写官方物品使用、拖放、换位、丢弃或出售。
- `ItemLaunch`/`LaunchLoot` 只视为可选掉落动画，不作为物品定义或 Tooltip 方案。
- 不实施不稳定的“鼠标坐标反查世界物品实体”轮询方案。

### 实施边界

1. 在 `data/csv/物品系统/item_definitions.csv` 增加 `engine_item_name`，作为材料业务 ID 到引擎物品名的唯一权威映射。
2. 地面掉落服务按该映射创建专属物品；映射缺失时失败关闭，不退回通用物品。
3. 抽离通用挑战材料 Claim 流程，复用现有所有者校验、可见壳采用、逻辑库存登记、重复合并、失败回退和自动合成触发。
4. 新地面奖励设置 `survival_ground_reward=true`；成功登记后清除该标记，避免背包材料丢下再捡时重复增加逻辑库存。
5. `item_survival_challenge_reward` 仅保留兼容路径。

### 当前阶段

**完整实施与自动验证已完成；等待 Workshop Tools 完全停止并重新 Run 后实机验收。**

### 已完成

- `item_definitions.csv` 新增 `engine_item_name`，覆盖合成宝石、熔火核心 Lv1～Lv4、冰魂焰魄；生成 Lua 可从 CSV 逐字节重现。
- `challenge_equipment_reward_service.lua` 按 CSV 创建专属真实物品，映射缺失返回 `challenge_ground_reward_item_mapping_missing`，不会回退通用物品。
- 新增共享 `challenge_ground_reward_claim.lua`；通用兼容物品与六个专属材料壳复用同一套所有者校验、壳采用、逻辑库存登记、合并、失败释放和自动合成触发。
- `weapon_equipment_service.lua` 删除手写材料壳映射，壳创建与采用均读取 CSV 生成配置。
- `addon_game_mode.lua` 只对新地面奖励标记或未登记的通用兼容物品执行 Claim；Claim 失败时将同一实体放回英雄脚下。
- 中英文官方物品 Tooltip 已补齐专属材料名称和说明。
- 新增共享 Claim、真实壳采用、映射缺失失败关闭和挑战 05/07/08/09 专属掉落回归测试。

### 自动验证

- `ALL_LUA_TESTS total=32 failed=0`。
- 相关 Lua 文件 `luac -p` 通过。
- `item_definitions.csv` 临时重建产物与正式 `item_definitions.lua` 逐字节一致。
- 限定 `git diff --check` 通过，仅有既有 LF/CRLF 工作区提示。

### 尚未验证

- 助手无法直接观察 Workshop Tools 中 Valve 世界物品 Tooltip 的最终视觉、鼠标命中与真实交互。
- 必须实机确认已有材料丢下再捡不会重复增加逻辑库存，并确认挑战 07 多次掉落在背包中正确合并数量。

### 下一步唯一动作

- 完全停止并重新 Run；按挑战 05、07、08、09 逐项验证专属地面 Tooltip、拾取、背包气泡、重复合并、丢弃再拾取不复制和满足配方时自动合成。

## 用户原始需求

用户在最新实机截图基础上要求：

1. 当前技能 UI 缺少边框，需要补充技能槽边框。
2. 修复 Bug：第一座箭塔升到 5 级后，转职技能起初是亮的，但稍后会置灰；第二座箭塔升到 5 级再转职没有问题。
3. 继续完成物品栏的项目气泡 UI，同时保留官方物品栏全部交互。
4. 角色栏鼠标悬停详细数据 Tooltip 直接删除，不再使用，以减少工作量。
5. 用户已批准先前回复中列出的实施顺序：持久化检查点、箭塔回归测试与根因修复、技能边框、角色 Tooltip 删除、独立物品 Tooltip、编译与验收。

## 验收标准

最终验收必须确认：

1. 英雄、建筑和农民的可见技能槽均与官方底栏几何对齐，且悬停不再出现 Valve 技能 Tooltip。
2. 项目技能 Tooltip 正确显示名称、等级、描述、金币/木材费用、魔法、冷却、运行时字段及可用状态。
3. Q/W/E/R/T/Y/U、鼠标点击、F2 回城、托管无目标技能和托管点目标建造均可用。
4. 普通英雄无目标、点目标、单位目标及切换技能继续由 Dota 引擎输入状态处理。
5. 被动与不可用技能仍可悬停查看，但点击不会错误发送施法请求。
6. 攻击、护甲、攻速、力量、敏捷、智力不再显示详细 Tooltip，但图标和服务端权威数值继续正常显示。
7. 背包物品显示项目气泡；官方背包的使用、拖放、交换、丢弃和出售没有回归。
8. 第一座和第二座箭塔分别升到 5 级后，转职技能经过延迟 Runtime 刷新仍保持正确可用状态，塔之间状态隔离。
9. 选择单位切换、HUD 比例/分辨率变化及第二次 Run 后，代理层会重新对齐且快捷键仍有效。

## 当前阶段

**源码实施、强制编译和自动测试均已完成。当前只剩 Workshop Tools 重新 Run 后的实机视觉与交互验收。**

## 已确认事实

- 当前用户目标与此前归档中的“保留 Valve 原生 Tooltip 基础层”决策不同，属于明确的新需求，应重新评估并在用户批准后替代旧决策。
- 当前会话附件中没有直接显示此前上传的 10 张截图。
- 项目目录限定图片搜索没有发现截图文件。
- 工作区存在疑似断开前调查残留：`.cline_tmp/current_hud_ids.txt`、`.cline_tmp/tooltip_full_override_20260728/`、`.cline_tmp/ability_tooltip.source.js`。
- 当前 Panorama 源码已有自定义底栏与 Tooltip 相关文件，包括 `survival_hud.xml`、`survival_hud.css`、`combat_stats.js`、`ability_tooltip.js`、`hud_takeover.js` 和 `inventory_tooltip.js`；`hero_stat_tooltip.js` 已按最新需求删除。
- 搜索结果显示当前或历史 UI 中存在 `SurvivalCenterBlock`、`SurvivalHeroPortrait`、`SurvivalHeroStats`、`SurvivalNativeAbilityInsetRight` 等自定义节点，说明项目已经不是完全使用原生底栏。

## 已排除方案

- 不声称仍能看到没有出现在当前会话附件或项目磁盘中的原始截图。
- 不根据旧的“原生基础层 + 扩展侧栏”结论继续实施，因为用户现已明确要求完全自主控制。
- 不在完成节点结构、功能职责和输入链分析前直接隐藏整个原生底栏。
- 不仅通过高频发送 Tooltip 隐藏事件来压制原生 Tooltip；该方式此前已证明脆弱且性能较差。

## 实施前调查结论（历史基线）

- 原始 10 张截图当前不可访问，无法逐张重看。
- 节点 ID、历史 UI 备份、Tooltip diff 与当前源码足以恢复核心问题。
- 自定义 SurvivalHeroBottomHUD 当前被折叠，官方技能与物品节点仍拥有输入。
- 普通技能和人物属性仍调用 Valve Tooltip；托管建筑技能仍靠循环压制原生 Tooltip。
- 历史自定义技能槽可作为全接管基础。
- 自定义施法链明确支持无目标与点目标；其他行为需要先枚举并补齐。
- 自定义物品栏没有使用、拖放、丢弃、出售或拆分链，不能直接替换官方物品交互。
- 折叠 AbilitiesAndStatBranch 会破坏官方 flow 布局，必须保留占位或完整接管 center_block。

## 尚未决定

- 实机验收若发现特定分辨率或 HUD 比例偏移，是否改为事件驱动几何更新，或保留当前低频几何恢复。
- 当前槽与 ItemImage 的非拦截悬停绑定在实机中若仍出现双 Tooltip，需要依据实际节点树继续调整隐藏事件，不得关闭 ItemImage 命中。

## 修改范围

源码修改限定在 `content\\dota_addons\\survival\\panorama` 的相关 JS/CSS/XML、箭塔 Runtime 相关 Lua 和定向测试；`game\\dota_addons\\survival\\panorama` 只接收对应编译产物。不得重写物品交互或混入地面物品 Tooltip。

## 验证要求

- 逐项复核节点结构与事件链。
- 计划中必须包含 Workshop Tools 实机节点验证。
- 实施后必须强制定向编译 Panorama 资源并确认 `compiled > 0`、`failed=0`。
- 必须验证英雄、建筑、农民、不同技能类型、物品主动/被动、选择单位切换和第二次 Run。

## 建议实施计划

以下为已执行计划：

1. 建立箭塔 Runtime 双塔延迟刷新回归测试并修复陈旧缓存。
2. 强化技能代理边框，不改变几何和输入。
3. 删除属性详细 Tooltip，保留并关闭只读属性节点的悬停命中。
4. 新增独立背包项目气泡，不接管物品操作。
5. 强制编译、全量 Lua 回归并输出实机验收矩阵。

## 下一步

- 完全停止当前 Run 并重新启动地图，确保加载最终 VJS/VCSS/VXML。
- 第一座箭塔升到 5 级后至少等待一次资源变化，确认七个转职技能持续正确可用；第二座重复同样流程并确认塔间隔离。
- 悬停技能确认 2px 边框与金色 hover；悬停普通物品、装备和材料确认只显示项目气泡。
- 逐项验证物品使用、拖放、换位、丢弃和出售；确认角色攻击/护甲/攻速/三围仍显示权威数字但不再弹详细 Tooltip。

## 最后检查点

- 日期：2026-07-28
- 完整日志证明官方 `Ability0` 与自定义槽窗口左上角均为 `723,1200`；`Ability0` 布局尺寸为 `72x200`，自定义实际尺寸为 `80x222`，UI scale 为 `1.111111...`。
- 结论：位置坐标转换能够对齐左上角；当前主要错误是把复合 `Ability0` 外壳当成按钮锚点，另有尺寸重复缩放风险。
- 正式修复已完成：过滤天赋、逐槽锚定 `AbilityButton`、移除重复 scale、按内部组件压制官方视觉并保留 `LevelUpTab`。
- 该段为技能几何修复时的历史检查点；其后箭塔 Runtime、属性 Tooltip 和背包气泡已按最新范围继续修改。

## 最新实机反馈

- 用户提供的新日志仍为 `official=Ability0 source_size=72x200 custom_size=80x222`，与检查点 023 的修复前日志一致。
- 当前 content 源码按 `AbilityButton` 定位且已移除重复缩放，因此该日志证明当前 Run 没有执行最新源码对应的编译产物。
- 必须重新强制编译并完全停止/重启 Run；只有新日志出现 `official=AbilityButton` 后，才属于当前实现的有效验收样本。

## 2026-07-28 最新范围覆盖

- 当前截图被用户明确指定为最新实机基线，即使 Workshop Tools 尚未重新启动，也应以截图中的实际 UI 缺失为本轮视觉输入。
- 技能边框需要补足。
- 第一座箭塔 5 级转职技能存在延迟置灰 Bug；第二座正常是重要对照样本。
- 物品栏项目气泡进入本轮；官方物品交互仍是不可破坏边界。
- 角色属性详细 Tooltip 整体删除；角色图标、攻击/护甲/攻速/三围数值与服务端快照不得删除。
- 地面掉落物 Tooltip 不进入本轮。

## 实施结果

- `scripts/vscripts/ui/ability_runtime_service.lua`：箭塔 Runtime 每次发布前读取自身 `survival_level`、`survival_tower_class` 和显示名，避免资源事件重放陈旧缓存。
- `scripts/vscripts/tests/test_tower_upgrade_runtime_refresh.lua`：覆盖两座箭塔、首塔陈旧缓存、延迟资源刷新、5 级转职按钮持续可用与 owner 隔离。
- `content/.../ability_tooltip.css`：技能槽默认 2px 浅色边框，hover 金色边框与光晕。
- `content/.../inventory_tooltip.js/.css` 与 `survival_hud.xml`：独立项目物品气泡；按状态事件刷新，不接管物品操作。
- 删除 `content/.../hero_stat_tooltip.js`、属性代理 XML/CSS 与 `game/.../hero_stat_tooltip.vjs_c`；`combat_stats.js` 权威数值写入保留。
- 自动验证：30 个 Lua 测试零失败；Lua 语法和限定 diff 检查通过；相关 Panorama 资源强制编译零失败、零跳过。
