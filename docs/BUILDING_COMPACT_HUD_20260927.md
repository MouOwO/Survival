# 建筑精简 HUD（2026-09-27）

按用户本轮规则，选中建筑时使用紧凑操作面板：

- 隐藏原生与自定义模型头像、头像边框、圆形等级牌、三属性区、物品栏与六个物品框；隐藏蓝条，城墙之外也隐藏血条。
- 城墙在血条上方显示等级；血条下方显示当前防御、防御加成及生命加成。
- 箭塔在原血条行显示等级，在下方显示当前攻击与攻击加成；转职塔使用当前路线等级。
- 其它建筑仅在原血条行显示等级。建筑名称去掉末尾 LV 或罗马阶段等级，不修改技能说明里的升级信息。
- 建筑面板宽度按技能数量计算，不留下头像与背包空框。英雄、怪物与工人的几何布局保持原样；切回它们恢复原生头像、血蓝条、背包等。
- 加成数字来自只读快照：当前有效值减对应等级基础值。城墙使用 War3 护甲单位；箭塔优先使用科技重算时记录的真实基础攻击，覆盖进阶路线和附加效果，不改变战斗计算。

验证：test_building_hud、test_building_stat_display、test_unit_stat_visibility、test_handoff_refresh、test_ability_hover_bounds、test_production_hud、test_combat_stats_callbacks、test_multiselect_portraits、test_building_upgrade_lifecycle、test_production_ui_router、test_research_runtime_projection 通过。界面编译 13 成功、0 失败；git diff --check 通过。

已同步本机 content 源码与 game 编译文件。测试时 Dota 未运行，未进行实机视觉验收；下一场新对局加载服务端新增展示字段，无需重启整台电脑。
