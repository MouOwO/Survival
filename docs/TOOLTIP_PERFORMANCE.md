# 选中单位时的技能 UI 优化与验收

## 本次调整

- 同一同步刷新共用技能、运行时数据快照；下一次回调重新读取，避免升级或切换单位后沿用旧数据。
- 正常技能栏连续稳定后停止完整绑定。保留原生 HUD 晚到、重建和运行时数据分批到达的恢复能力。
- 默认关闭详细绑定/几何日志和十秒鼠标诊断；技能悬停恢复、点击与失效检查保留。
- 同帧重复选择事件合并。快捷键映射共用；稳定后跳过清空、重写，继续检查原生 HUD 的异步更新。

## 本地验证

```powershell
node tools/test_ability_tooltip_recovery.cjs
node tools/test_ability_tooltip_stability.cjs
node tools/test_ability_hover_bounds.cjs
node tools/test_hero_skill_upgrade.cjs
node tools/test_combat_selection_recovery.cjs
node tools/test_combat_stats_callbacks.cjs
```

`tools/build_tooltip_performance.ps1` 仅同步、编译两个修改的 JS，并备份原 content 源文件和 game 编译资源。不会编译地图或重启游戏。

## 实机验收

重新加载本地测试地图的 HUD 后，在客户端控制台执行 `survival_tooltip_perf`，保存一次计数；来回选择主城、英雄、防御塔各十次，再执行一次。

- `passes`：完整绑定次数；`panelScans`：完整面板扫描次数。
- `guardChecks`：轻量的稳定性检查次数，不等同于重新绑定。
- `settled` / `exhausted`：稳定完成 / 重试窗口耗尽次数。
- `totalMs`、`maxMs`、`averageMs`：JS 绑定耗时，**不代表 GPU 耗时或整帧时间**。

检查技能点击、悬停、加点、建筑升级/转职、研究键位、F2、多选、快速切换单位；尤其检查升级后鼠标不动仍能看到新技能提示。记录同样操作下的实际帧时间，以及系统可用内存、Dota 驻留内存和磁盘换页活动，才能确认卡顿来源。

默认不输出逐次恢复日志。需要复查几何/悬停时执行 `survival_tooltip_diagnostics 1`；完成后执行 `survival_tooltip_diagnostics 0`。关闭详细日志不会关闭功能所需的恢复。

确定性模拟测试只能证明工作量减少和上述行为分支；无法替代实机帧时间或显存/内存泄漏验证。

### 2026-09-24 对照结果

同一模拟环境中，排除启动过程后切换一次四技能单位，再推进 11 秒：

| 指标 | 优化前 | 优化后 |
| --- | ---: | ---: |
| 完整绑定 | 8 | 2 |
| 完整面板扫描 | 16 | 2 |
| 技能槽读取 | 1288 | 20 |
| 调度回调 | 220 | 12 |

可用 `node tools/test_ability_tooltip_recovery.cjs --measure` 测量当前版本；环境变量 `SURVIVAL_TOOLTIP_TEST_SOURCE` 可指定备份源文件以运行同一负载。详细结果见 `docs/ai/validation/20260924/tooltip_performance.json`。

本次本地六组测试与两个 JS 的资源编译均通过。实机控制台连接 `127.0.0.1:29000` 返回连接拒绝，尚未取得优化后的实际帧时间。

## 回退

从对应 `output/tooltip_perf_20260924/build_时间/` 取出两个 `.js` 和 `.vjs_c`，分别恢复到 `content/.../panorama/scripts/custom_game/` 和 `game/.../panorama/scripts/custom_game/`；仓库中的 `panorama/src/scripts/custom_game/` 同步恢复对应 `.js`，然后重新加载 HUD。不要用整仓回退覆盖其它未提交工作。
