# 建筑升级完成效果

升级完成统一使用官方 `particles/generic_hero_status/hero_levelup.vpcf`，挂载在建筑原点，粒子自然结束并立即释放脚本句柄。地图预加载阶段加载该粒子。原先升级完成的建造闪光已替换，施工与升级过程动画仍按现有定义执行。

17 个建筑/防御塔升级音效配置统一使用 `General.LevelUp`，资源文件为 `soundevents/game_sounds_ui_imported.vsndevts`。已从本机 Dota 2 VPK 解码核实，此事件使用 `sounds/ui/power_up_06.vsnd`，与 `General.MaleLevelUp` 相同；原来的 `General.LevelUp.Bonus` 使用另一段奖励升级音效。保留现有批量升级音效限流。

成功回调结束后仅播放一次粒子；失败返回 false、抛错、取消、死亡或实体移除均不播放。城墙、主城、农场、金矿、普通塔和转职塔共用完成流程。

验证：

- `test_building_upgrade_effect.lua`：成功、重复回调、失败、取消、死亡、删除、粒子释放和全部升级音效配置通过。
- 建筑升级生命周期、城墙快捷升级、金矿奖励升级、防御塔转职预检查通过；修改的 Lua 语法和 diff 检查通过。
- 当前游戏内对现有城墙调用新粒子与官方音效成功（`UPGRADE_EFFECT_ENGINE_PASS`），未改变建筑等级、资源或碰撞。
- 旧 `test_tower_upgrade_targeting.lua` 在施工阶段因测试缺少 `DOTA_UNIT_TARGET_BUILDING` 报错；替换成本次修改前的升级模块也同样失败，属于已有测试环境问题。补充常量后还缺少可用施工位置环境，未计为通过。

重新运行地图后完整加载新的音效配置、模块和预加载资源。最终视听效果需要在实际升级时确认。
