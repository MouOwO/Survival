# 多选单位头像

## 行为

- 单选保留原有大头像和等级标记。
- 多选在同一个头像框里展示紧凑网格，保留原生生命条、魔法条、当前单位高亮、点击选择与分页。
- 复用 Dota 的 `DOTAMultiUnitCanvas` 和 `DOTAMultiUnitFrame`；不为每个单位新建 ScenePanel。
- 按原生两列、三列、四列布局缩放共同父节点，头像图像、状态条和点击区域一起缩放。
- 多选时关闭建筑自定义大头像覆盖层及等级标记，防止遮住小头像。
- 切回单选、HUD 重建或原生节点暂时失效时恢复临时样式和交互状态。默认透明度恢复为明确的 `1`，避免 Panorama 拒绝空字符串后留下空白。

## 文件

- `panorama/src/scripts/custom_game/multiselect_portraits.js`：布局与恢复控制器。
- `panorama/src/scripts/custom_game/topnav_remaining_5d5c1152eb.js`：现用 HUD 接入、头像框基准和等级标记显示。
- `panorama/src/scripts/custom_game/combat_stats.js`：多选时停止单个建筑的自定义头像覆盖。
- `panorama/src/layout/custom_game/survival_hud.xml`：加载控制器。
- `tools/build_multiselect_portraits.ps1`：备份并同步上述四份源码到 content，调用 ResourceCompiler 编译。

## 验证

```powershell
node tools/test_multiselect_portraits.cjs
node tools/test_handoff_refresh.cjs
node tools/test_combat_stats_callbacks.cjs
```

覆盖选择列表格式、两/三/四列、原生点击和分页绑定、默认与非默认透明度恢复、原生节点重建、挂载后节点/布局失效再恢复。

2026-09-23 在正在暂停的测试对局中验证：三名伐木工小头像显示、点击第二个头像选中一个单位、单选大头像恢复。保持对局暂停，未重开地图。大量单位分页仅做自动化验证，尚未在本局实测。

实机截图在 `output/map_build_c6/multiselect_final_multi.png` 和 `multiselect_final_single.png`；原生状态诊断在 `output/multiselect_portraits/`。这些输出用于本地验收，不作为游戏资源。

诊断控制器：`GameUI.CustomUIConfig().SurvivalMultiSelectionPortraits.Inspect()`。

编译后在 Workshop Tools 中热更新。若修改 HUD 时游戏在后台，切回前台让 Panorama 完成后续刷新；不需要重启后端。
