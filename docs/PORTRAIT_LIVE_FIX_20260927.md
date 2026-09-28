# 头像实机诊断与修复

本次已通过 127.0.0.1:29000 接入正在运行的 Dota 2 Workshop Tools，读取实际 Panorama 节点并截图对照。没有重开地图或修改英雄属性。

## 横线

前两次仅根据静态代码排查，没有解决实际横线。此次先确认 `RightSideHeroBlur` 已隐藏但横线仍在；实际节点树中，原生 `xp`（DOTAXP）和 `unitbadge`（DOTAUnitHeroBadge）仍覆盖放大后的头像。隐藏这两个节点后，同一只 Doom 的横线消失。现在每次正常 HUD 刷新持续清理它们，自定义金边、等级牌、技能及多选保持正常。

实机证据：`output/portrait_live_20260927/doom_focused.png`（修复前）与 `badges_hidden_focused.png`（移除原生 XP/徽章后）。

## 背景

给 3D 背景材质换测试色没有改变实际头像，但给 Panorama 容器贴图换测试色后，测试色确实显示在 Doom 背后。实际显示底板来自 `PortraitContainer` 和 `SurvivalTowerPortraitOverlay`，因此前两次仅改材质/配置没有命中这个显示层。

现在这两个容器共用 `panorama/images/custom_game/portraits/portrait_slate_backdrop_png.vtex_c`，源图为暗蓝灰磨砂底板，保留轻微边缘倒角，不再使用空泛的径向光晕。所有类型单位共用这一显示路径，仍是动态 3D 模型。旧 3D 材质别名同步到新底板，供原生后台配置使用。

测试色证据：`background_probe.png`（3D 材质测试未改变头像）与 `panorama_probe.png`（实际容器测试成功）。测试色已恢复为正式图，并确认 content、仓库 PNG 和材质源图片一致。

## 三秒脸谱

原生沉默／禁用物品脸谱恢复。每个选中实体、每个状态独立计时，显示 3000 毫秒后以 250 毫秒淡出；持续状态不会反复弹出，切换回来和原生节点重建不重新计时；状态结束后再次施加可重新提示。两种状态同时存在时只显示一个脸谱，防止重叠。

## 验证与清理

4 项回归检查通过：三秒计时与原生层清理、连续头像同步、HUD 回调、多选恢复。新图片通过 HUD CSS 依赖编译，不能把 PNG 本身当独立 resourcecompiler 输入。

临时隐藏模型、隐藏徽章的测试命令已从源码移除。保留仅在 Workshop Tools 注册、带会话时间戳的只读 `survival_portrait_inspect_<timestamp>`，用于以后检查真实节点；不会自动修改任何内容。所有暂时的测试颜色都已恢复。

不需要 Hammer 才能修改这类窗口。当前问题属于 Panorama 叠层和背景显示路径；如果以后要把底板改成真正的 3D 房间或场景，才需要另建头像场景地图。
