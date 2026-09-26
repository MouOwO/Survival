# 初级箭塔 LV1–LV5 模型替换

2026-09-26。根据用户认可的概念方向制作了五个实际 3D 模型：石砌塔身、木制弩机、青色旗帜；随等级增加塔高、城垛、扶壁和金属装饰。

## 已安装

- 五套独立 FBX / ModelDoc 模型与 2048 贴图，编译到 `models/survival_buildings/arrow_tower_lv01..05.vmdl_c`。
- 五套建造白色轮廓，沿用现有高度渐显效果，大小和位置与完成模型一致。
- 修正 FBX 导入的 90 度旋转：弩机朝向 +X；攻击发射点在弩箭前端。包含 idle 动作、命中点和选取 hitbox。
- CSV、资源注册、初建单位 Model、初建属性适配器和升级路线均指向对应等级模型；开局预加载五级资源。
- 五级动态 3D 头像按编译后的真实尺寸设置相机，沿用统一深色背景。
- 原战斗数值、费用、2×2 建造占地不变。高级转职塔配置与其他建筑保持原值。

真实模型渲染预览：`previews/arrow_towers_actual.jpg`（Blender 渲染，并非游戏截图）。可编辑场景：`arrow_towers.blend`。

## 验证

- 5 个模型 + 5 个建造轮廓全部编译成功，0 failed。
- `verify_assets.py` 通过：尺寸、正向、挂点、材质依赖、idle、白色轮廓对齐、CSV 修改范围；原有全部头像配置保持原值，新增 5 个。
- `test_visual_progression.lua` 通过：真实配置与资源预加载服务、初建模型选择、逐级切换、重复刷新、跨级切换。
- `test_tower_class_preflight.lua`、`test_builder_tower_rebuild.lua` 通过。
- `test_tower_upgrade_targeting.lua` 的旧测试夹具缺少 `DOTA_UNIT_TARGET_BUILDING`，在实际建造检查前失败。使用本次修改前的配置复现相同失败，记录见 `baseline_test_note.txt`。不能将此项报告为通过；生产建造位置逻辑没有改动。
- Python 制作脚本语法通过。实际 Dota 2 对局中的模型与头像尚未实机验收。

## 加载与复现

需要重新开局加载新增单位模型、预缓存和头像配置。当前对局可能继续使用旧缓存；没有关闭用户游戏。

1. 使用 Blender 4.2 后台运行 `tools/build_arrow_tower_models.py` 生成实体模型与贴图。
2. 运行 `tools/build_building_white_shells.py` 生成建造轮廓与映射。
3. 运行此目录 `install_models.ps1` 同步 content 源资源并调用 Source 2 resourcecompiler。
4. 运行 `tools/build_unit_portraits.py` 更新模型头像相机。

Blender 官方便携包 SHA256 已核对：`b6e72874f8cb5c4ed77f9b03d7f1fde851b9455a7ff02a1e1119c876318ebc65`。
本次修改前的项目文件保存在 `before/`，安装前的同名 content 文件保存在 `content_before/`。没有重置或提交用户工作区。
