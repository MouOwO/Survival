# 技能槽切换横向位置修复

2026-10-13。修复已编译接入当前 survival 的 content/game；没有提交或推送。原工作区已有大量用户和前序任务改动，本次完整保留。

原实现根据选中单位类型、可见技能数和生产队列重新居中。研究所技能从0项异步到10项时，还会再次改位置。新实现共用首个技能槽的屏幕锚点：后续技能向右排列，队列空间不足时移到上方；小高度采用有界滚动视口。保留原头像位置、业务输入、技能补位与 Tooltip。

单独 topnav 热载还暴露快捷键镜像 map 清空、原 combat 标签签名仍命中的问题。新HUD通过现有 `SurvivalAbilityHotkeys.Refresh()` 有界回放：最多4次/代；不重建主动/被动判断，不每tick强制刷新。原生防御塔主动 Q/D/G 和伐木工Q已恢复，被动两槽仍无键。

## 实际运行证据

已实际打开原始PNG查看并独立按像素核对（1600×900、PID62740/HWND3086882）：

- `design_refs/menus_v10/work/native/skill_switch_final_tower_hotkeys_resource45.png`：首槽金边x719–769，y768，5槽键为Q/空/空/D/G。
- `design_refs/menus_v10/work/native/skill_switch_final_worker_resource45.png`：首槽金边x719–769，y801，单槽键Q。
- 两图首槽横向差 **0px**。纵向差来自紧凑HUD高度，不是横向跳动。标题和文字未遮住技能。
- `skill_switch_before_resource45.png` 和中间 `skill_switch_final_current_resource45.png` 的高级研究所行757→719，后者曾缺主动键；它保留为中间失败证据，不是最终keys全通过图。

独立原生图审查：`output/ui_refresh_audit_20261013/resource45_native_hotkey_tower_worker_review.json`。英雄/主城/最终研究所keys、小高度实际滚动和活跃生产队列尚未取得新版原生截图；前台检查失败即拒绝捕获。没有把被拒绝的操作或模拟器图当实际截图，没有从视觉证据宣称FPS提高。

## 修改与检查

正式源码：

| 文件 | 最终SHA256前缀 | 作用 |
| --- | --- | --- |
| panorama/src/scripts/custom_game/geometry_remaining_5d5c1152eb.js | e733ef5b | 共用技能栏屏幕锚点与布局几何 |
| panorama/src/scripts/custom_game/topnav_remaining_5d5c1152eb.js | 29c3bbc1 | 原生技能/文本/镜像同步布局，有界热载键恢复 |
| panorama/src/scripts/custom_game/production_progress.js | db912a4f | 队列独立侧置/上置及有界滚动视口 |

对应三个 `panorama/scripts/custom_game/*.vjs_c` 已编译；content的同名源码与工作区SHA一致。构建工具新增 selection/hotkey 定向组。新只读截图工具不含输入/焦点功能；focus工具有SkipCursorCenter，删除了对SearchUI的ESC输入。

- `node tools/test_ability_anchor_stability.cjs`：630几何场景、10个完整实际IIFE视口，通过。单位切换、0→32项、满级消失/补位、热载及原生产输入不变；稳定时技能栏位置/宽度写入0。是VM计数，不是原生FPS。
- `node tools/test_topnav_hotkey_mirror_recovery.cjs`：完整真实combat+topnav IIFE，同实体热载旧源负对照确实失败；主动/被动、晚到writer/技能/原生锚点、异常次数上限通过。稳定10秒额外writer调用0，未施法。
- JS语法、对应生产HUD/布局/热路回归通过，编译日志0failed、输出新鲜、输入SHA一致。

## 可恢复检查点与继续验证

修改前完整脏源保存在 `output/ui_refresh_audit_20261013/ability_anchor_before_20261013_083850_811060`；技能锚点最终冻结在 `ability_anchor_final_frozen_20261013_090352_531926`。快捷键热载修改前/最终源在 `hotkey_mirror_before_20261013_094210_463689` / `hotkey_mirror_final_frozen_20261013_095304_492953`。

最终构建：`output/four_operation_extreme_20261012/ui_selection_build_20261013_090843_705` 与 `ui_hotkey_build_20261013_100147_746`，各含原content/编译产物备份、manifest和日志。恢复时只取本次对应文件，不用git reset丢弃其它改动。

后续保持这些源冻结，先确认当前Tools世界/窗口前台再对英雄→塔→工人→高级研究所→主城快速切换截图；用当前真实queue状态检查取消/退款/tooltip，另测小高度滚动。新工具只接受安全PNG文件名并拒绝覆盖。当前总体高负载30FPS目标尚未达到，性能任务恢复点见 `docs/ai/tasks/four_operation_extreme_20261012/Plan.md`。
