# Decisions

## 架构决策

1. **CSV 是配置权威来源。** 不只修改生成 Lua；涉及挑战、内容、商店和配方时同步更新对应 CSV，再生成/校验 Lua。
2. **逻辑库存是权威，物品实体是显示壳。** 拾取时登记 `content_id`，只有合成事务成功后才删除材料壳。
3. **所有自动合成统一由 `weapon_synthesis_service` 扫描。** 挑战服务只负责掉落，不直接写装备升级逻辑。
4. **合成必须原子执行。** 材料消耗和产物发放通过库存事务完成，失败不得提前删除材料。
5. **挑战奖励使用服务端权威请求。** 新的内容掉落入口必须校验 challenge/content 配对，避免成为任意物品生成接口。
6. **每个地面奖励具有幂等 key。** 重复死亡/完成事件不能创建重复奖励。
7. **客户端资源快照不具有请求否决权。** `can_afford` 只负责 UI 费用、状态和诊断；由于 NetTable 可能短暂过期，客户端不得因快照资源不足而丢弃点击。服务端 `RESOURCE_TRY_SPEND_REQUEST` 是最终且原子的资源判断。
8. **技能接管按托管身份分流输入。** 自定义技能按钮和 Q/W/E/R/T/Y/U 统一进入 `SurvivalAbilityInput`；明确托管的建筑无目标操作走 `ui_ability_cast_request`，托管点目标建造走 `ui_ability_cast_position_request`，普通英雄技能调用 `Abilities.ExecuteAbility` 交回引擎处理目标模式。
9. **战斗属性 UI 使用显式单位边界。** 运行时 `runtime_armor` 始终是 Dota 实际护甲；发送给 UI 的 `armor` 始终是 War3 显示护甲，并由 `ui/combat_stat_projection.lua` 统一转换。禁止各发布路径自行乘除 3。
10. **英雄面板攻击与引擎普通攻击允许双值投影。** CSV `base_damage_min/max` 是面板逻辑值；`damage_multiplier` 只投影到原生普通攻击的引擎基础攻击，不写入全局 DamageFilter，避免技能、光环和脚本伤害被扩大。
11. **英雄攻速配置权威。** `attack_speed` 表示每秒攻击次数；UI 值由配置 BAT、固定间隔变化和装备攻速百分比计算，禁止通过 `GetSecondsPerAttack()` 反推。
12. **UI 快照投影必须幂等且不修改权威快照。** 投影结果使用 `stat_units_version` 标记，重复同步不得二次放大护甲。
13. **建筑通用规则由生成配置驱动。** `config/buildings_config.lua` 只负责组装运行时结构；`max_count`、`requires_city_level` 和 `population_cost` 必须优先读取 `config/generated/building_definitions.lua`，手写值仅作缺失回退。
14. **建筑数量上限按队伍共享。** 计数键保持为 `counts[team][building_id]`；施工开始后占用名额，建筑死亡或施工失败后释放。`max_count=0` 明确定义为无限制。
15. **Panorama 源码与游戏产物严格分离。** 源码修改在 `content\dota_addons\survival\panorama` 中完成；`game\dota_addons\survival\panorama` 只存放游戏加载的 `.vjs_c`、`.vcss_c`、`.vxml_c` 等编译产物。
16. **Panorama 修改必须强制定向编译并检查汇总。** 对已存在且时间戳可能混乱的产物使用 `resourcecompiler.exe -f`；只有 `compiled > 0` 且 `failed=0` 才作为本轮重新编译的明确证据，单独出现 `skipped` 不作为充分证据。
17. **官方战斗属性覆盖层按字段独立定位。** 攻击力使用 `positionRelativeToStatsContainer()`；攻速与护甲使用 `positionRelativeToOfficialPanel()`。移动攻速/护甲时不得顺带改变攻击力、三围或原生图标。
18. **PowerShell 参数必须跟随可执行程序。** `-NoProfile -ExecutionPolicy ...` 不能作为独立命令；外部调用应以 `powershell.exe` 或可用的 `pwsh` 开头，已在 PowerShell 会话内时可使用调用运算符 `&` 执行脚本。
19. **技能 Tooltip 由项目代理控制，角色属性 Tooltip 取消，背包只接管气泡表现。** 官方 AbilityN 仅作为技能几何/生命周期锚点；攻击、护甲和攻速节点保留显示但关闭命中；官方背包在完整物品输入链完成前不得隐藏或接管操作。
20. **Tooltip 动态内容由权威状态变化驱动。** NetTable 和 CustomGameEvent 更新时只刷新当前可见 Tooltip；禁止使用固定 `0.03s`、`0.35s` 等循环持续重绘动态数据。
21. **人物属性只保留权威显示，不接管结算，也不显示详细 Tooltip。** 保留 Valve `stats_container`、图标和选中单位生命周期；攻击、护甲、攻速和三围继续消费统一服务端投影，禁止为了显示修改引擎属性。
22. **护甲显示继续使用显式双值边界。** 面板值使用 `armor`（War3 显示单位），实际结算使用 `runtime_armor`；即使 Tooltip 已取消，客户端仍不得再次执行 War3/Dota 护甲换算。
23. **物品动态 Tooltip ViewModel 由服务端按 `content_id` 生成。** `survival_weapon_snapshot` 保留旧字段并追加 `tooltip_view_model`；Panorama 只负责渲染，客户端旧字段拼装仅作为热重载兼容回退。
24. **Tooltip 绑定恢复与数据刷新分离。** 选中单位或物品节点结构变化可以触发有限绑定恢复；资源、成长和实例数值变化只刷新当前可见扩展，禁止借数据更新重新扫描完整 HUD。
25. **AI 工作上下文必须增量落盘。** `START_HERE.md` 是唯一恢复入口，`CURRENT_TASK.md` 只保存单一活跃任务，`SESSION_LOG.md` 追加关键研究检查点。不得将长时间计划研究只保留在聊天中，也不得等任务全部完成后才记录结论。
26. **恢复时禁止用猜测填补丢失聊天。** 已确认事实、推断和未知项必须明确分开；缺少断开前任务时应收集最小用户线索并先落盘，而不是根据旧任务摘要擅自续写。
27. **角色属性详细 Tooltip 已取消。** 删除攻击、护甲、攻速、力量、敏捷、智力的悬停详细说明，但必须保留官方图标、项目权威数字覆盖和服务端战斗属性快照链。
28. **背包 Tooltip 只接管表现，不接管物品操作。** 项目气泡消费 `content_id` 与服务端 ViewModel；官方背包继续负责使用、拖放、换位、丢弃和出售，任何悬停绑定都不得用可命中覆盖层阻断这些输入。
29. **挑战材料的引擎物品映射只允许来自 `item_definitions.csv`。** 合成宝石、熔火核心 Lv1～Lv4、冰魂焰魄的地面真实物品创建、背包壳补建和拾取壳采用均读取生成配置；禁止恢复 Lua 手写材料映射。
30. **专属材料实体只有带新地面奖励标记时才能登记逻辑库存。** 掉落服务创建时设置 `survival_ground_reward=true`，成功 Claim 后清除；已有背包材料被玩家丢下再拾取时必须走官方物品移动，不得再次发放 `content_id`。
31. **官方世界物品 Tooltip 通过真实已注册 item ability 提供。** 地面材料使用 `CreateItem(engine_item_name)` 和 `CreateItemOnPositionSync`；`ItemLaunch`/`LaunchLoot` 仅可作为可选运动效果，不是运行时物品定义或 Tooltip 来源。
32. **项目技能接管使用固定 cell、左上角对齐的单行网格。** 每个技能 cell 固定 52×52、间距固定；技能数量只改变整行向右延伸的宽度。整行位置使用官方 `abilities` 容器左上角；Valve `AbilityN`/`AbilityButton` 只用于完整映射、视觉顺序和官方视觉压制，不得再次把官方动态宽高或随数量变化的按钮底边复制到项目行。历史 65×65 基线已被实机判定偏大，不得恢复。
33. **Valve 物品 Tooltip 元数据必须来自静态注册资源。** Lua 实例字段只承载业务身份与权限，不得假设存在运行时名称、说明或图标 setter。排查世界 Tooltip 时必须同时记录 `CreateItem` 请求名、`GetAbilityName()` 实际名和客户端 `$.Localize()` 结果。
34. **本地化文件必须进入引擎标准加载路径。** Valve 游戏/世界 Tooltip 使用 `game/dota_addons/survival/resource/addon_<language>.txt`；Panorama 诊断和自定义 UI 使用 `panorama/localization/addon_<language>.txt`。不得只修改不会被这些消费者加载的 `resource/localization/` 镜像。
35. **英雄商城饰品使用“本机资源取证 + 基础骨骼上的命名 wearable”方案。** 先通过 defindex 确认 Bundle 子物品和槽位，再从当前 `pak01_dir.vpk` 以英雄目录、发布时间开发代号、模型/材质/图标/粒子交叉验证真实路径；展示名不得直接当资源目录名。运行时保留英雄主体骨骼与动画，以项目创建的 `prop_dynamic`、`SetOwner` 和 `FollowEntity(hero, true)` 挂载 wearable。商城视觉像全身套装时也必须尊重实际槽位：`The Hallows Within` 已实机证明是单个大型 Head wearable，不得虚构多个身体组件或用 `SetModel` 替换英雄主体。
36. **项目饰品生命周期必须幂等且严格限定身份。** wearable 和粒子按英雄 entindex 保存；重复应用先销毁/释放项目粒子并删除项目 wearable；粒子通过命名 owner 绑定对应 wearable。开局/重生接入必须校验目标英雄单位名、玩家身份和已初始化 entindex，禁止仅按 Undying 模型或单位名批量应用到修理工、波次怪、僵尸和 Boss。

## 游戏行为决策

1. 合成宝石、熔火核心和其他非武器材料允许丢弃；武器不可丢弃。
2. 召唤英雄必须具有正确玩家 owner，但不能通过禁止选择建筑/农民来解决 owner 问题。
3. 挑战 07 使用与冰霜之地相同的 `maintain_count` 刷新方式：场内维持 10 只，成员配置的 0.5 秒刷新优先于通用挑战 2 秒规则。
4. 挑战 07 每只怪物独立进行 20% 判定，只掉落 `material_molten_core_01`；Lv2/Lv3 由 3 合 1 配方产生。
5. 挑战 08 是单 Boss 挑战；Boss 完成奖励应直接掉落 `material_molten_core_04`，不再使用旧的抽象升级宝石 `item_molten_upgrade_gem_04`。
6. 挑战 08 的 Lv4 核心应复用挑战 05/09 的地面奖励流程：Boss 死亡位置掉落、拾取入库、满足配方自动合成。

## 测试决策

- 随机概率通过注入固定随机函数测试边界，不依赖实际随机结果。
- 地面奖励测试必须覆盖权限校验、challenge/content 白名单、正确 owner/content_id 和幂等。
- 合成测试必须覆盖首次合成后继续合成、错误恢复和跨配方连续触发。
- 战斗属性测试必须同时覆盖逻辑显示值、引擎投影值、护甲双向转换和重复投影幂等性。
- 建筑配置测试必须覆盖生成字段进入运行时配置、达到上限拒绝、队伍隔离、死亡释放名额和零值无限制。
- Panorama 修改必须至少检查源码目标行、资源编译器汇总、编译产物时间戳/状态，以及限定路径的 `git diff --check`。
- 专属地面材料测试必须覆盖 CSV 映射、映射缺失失败关闭、真实引擎物品名、地面标记、首次壳采用、重复合并、登记失败释放和成功后清除防复制标记。