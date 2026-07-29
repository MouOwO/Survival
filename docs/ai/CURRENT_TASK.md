# Current Task

## 当前任务

以最小修改量调整头顶血条与项目 Tooltip：

1. 头顶血条宽度缩短为原来的二分之一，并保持单位中心对齐。
2. 头顶血条整体向上移动约 20px。
3. 隐藏第一张截图中的 Valve 官方“攻击 / 防御”属性汇总面板。
4. 技能与背包项目 Tooltip 统一采用：中心横坐标与悬停图标中心一致，Tooltip 下边缘距图标上边缘 10px。
5. 修复重复点击同一单位时名称先空后恢复，以及多次切换后攻速/护甲权威文字漂移。

## 已确认实施边界

- 血条仅修改 `hero_world_health_bar.js/.css` 的宽度与定位常量，不改高度、颜色或更新逻辑。
- 技能与背包 Tooltip 已共用 `tooltip_position.js::PlaceAbove()`，只修改共享公式。
- 官方属性汇总面板的三个属性子节点已关闭命中，但共同父节点 `stats_container` 仍可命中；只在现有属性可见性刷新路径中补充关闭该只读父节点及子树命中。
- 不隐藏官方底栏，不修改技能输入，不接管或阻断背包使用、拖放、换位、丢弃和出售。
- Panorama 源码只修改 content 目录；game 目录仅接收强制定向编译产物。
- 选择事件先比较 portrait unit entindex；相同单位不清空名称或快照，真正切换才立即刷新并请求权威数据。
- 移除人物面板永久 0.25 秒完整轮询；生命/魔法保留独立轻量刷新，名称、头像和战斗属性由选择/快照事件驱动。
- 攻速与护甲文字完全复用攻击力数字文本的样式和原生数字 Label 定位规则；三项使用同一固定宽度、右对齐、右边距和行高公式。

## 当前状态

**攻速/护甲自定义 Label 消失回归已修复并重新编译，等待完全重启后实机验收。**

## 验收标准

- 血条宽度为 62px，水平中心保持不变，垂直位置比当前高 20px。
- 技能与背包项目 Tooltip 均按图标中心对齐，垂直间距为 10px，并保留屏幕边缘约束。
- 悬停官方属性区域不再显示“攻击 / 防御”汇总面板，权威攻击、攻速和护甲数字仍可见。
- 重复点击同一单位时名称不闪空；切换单位时由选择事件立即刷新并请求权威快照。
- 多次切换后攻速/护甲文字不累积漂移，并与攻击力数字保持完全相同的文本样式和定位方式。
- 所有修改资源强制编译为 `compiled > 0, failed=0, skipped=0`；限定差异检查通过。

## 下一步唯一动作

- 完全停止当前 Run 并重新启动，先确认不再出现 `combat_stats.js` JS Exception 且 HUD/网格恢复，再验收真实图标间距、原生 Text、装备刷新与拾取特效。

## 实施与验证结果

- `hero_world_health_bar.css`：宽度 `124px → 62px`。
- `hero_world_health_bar.js`：水平半宽偏移 `62 → 31`，垂直偏移 `-6 → -26`。
- `tooltip_position.js::PlaceAbove()`：统一为图标/Tooltip 中心 X 对齐，Tooltip 下边缘距图标上边缘 10px；保留动态尺寸复测与 12px 屏幕边界。
- `combat_stats.js::updateOfficialStatsVisibility()`：关闭 `stats_container` 的 `hittest` 与 `hittestchildren`，保留属性数字显示。
- 四个 Panorama 资源分别强制编译成功：每项均为 `OK: 1 compiled, 0 failed, 0 skipped`。
- 源码契约：`UI_MINIMAL_CHANGE_CONTRACT_PASS`。
- 限定检查：`CONTENT_DIFF_CHECK_PASS`、`DOCS_DIFF_CHECK_PASS`。
- 四个 game 编译产物均已刷新；未修改 XML、Lua、CSV、技能输入或背包操作链。
- `combat_stats.js` 选择事件现在使用 `observedSelectedUnit` 去重，并保留 `0/0.016/0.05/0.10/0.20s` 有限重试等待 portrait unit 与 Valve 属性行稳定；重试期间不再清空名称或快照。
- `refreshHeroPanel()` 已改为一次性事件刷新；永久 0.25 秒循环仅由 `refreshHeroVitalsTick()` 更新生命/魔法，不再重做名称、头像、Tooltip 绑定或服务端请求。
- 攻速/护甲权威文字最终改为与攻击力共用原生数字 Label 锚定、固定宽度、右对齐、右边距和行高规则；不再使用真实图标候选定位。
- `combat_stats.js` 最新强制编译：`OK: 1 compiled, 0 failed, 0 skipped`；产物 72432 字节，时间 2026-07-29 23:52:24。
- 历史 `FINAL_SELECTION_EVENT_ICON_ANCHOR_PASS` 方案已被本次原生数字 Label 统一定位方案替代。
- 旧的攻速/护甲图标候选筛选仍供其他逻辑属性定位使用，但不再参与攻速或护甲权威数字定位。
- Valve 攻速/护甲原始 Label 在项目快照等待期也始终 collapse，不再恢复可见。
- `ui_weapon_synthesis_snapshot` 到达后强制请求当前选中单位权威属性，确保装备聚合完成后 UI 立即刷新。
- `addon_game_mode.lua` 拾取解析改为事件英雄、权威召唤英雄和原生英雄候选中实际持有 item 的单位优先，并在 Claim 前绑定 purchaser 到实际拾取者。
- 验证：`HUD_EQUIPMENT_PICKUP_CONTRACT_PASS`、`PICKUP_ACTUAL_HOLDER_CONTRACT_PASS`、`COMBAT_STATS_DIFF_CHECK_PASS`、`PICKUP_DOCS_DIFF_CHECK_PASS`；`combat_stats.js` 编译为 `1 compiled, 0 failed, 0 skipped`。
- 最新文字格式修复：攻击、攻速、护甲共用 `applyAuthoritativeNumberStyle()` 和 `positionRelativeToNativeNumber()`；护甲、攻速数值语义保持不变。`combat_stats.vjs_c` 强制编译为 `1 compiled, 0 failed, 0 skipped`。
- 消失回归修复：`applyAuthoritativeNumberStyle()` 不再在每次刷新时隐藏项目 Label；`SurvivalAuthoritativeAttackSpeedLabel` 与 `SurvivalAuthoritativeArmorLabel` 仅首次创建或快照不匹配时 collapse。二者使用官方属性行面板的纵向几何定位，不再依赖已隐藏的官方 Text，最终明确写值并设为 visible。