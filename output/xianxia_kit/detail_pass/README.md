# 本轮组件与主地图接入

六个增量 Blender 模型沿用已确认的独立材质。概念板没有作为贴图使用。

- a01_pavilion_detail：青瓦亭阁，补斗拱曲撑、外向瓦当。
- v01_pine_rooted_0 / 1：两种松树，补渐细根系；游戏实例使用较暗的色调融入场景。
- t08_platform_edge / corner：256 单位接口、128 单位厚度的直线和转角收边，已编译入资源库，尚未全图装配。
- t08_stair_cheek：256 单位长、八级、每级下降 16 单位；只用于既有侧楼梯外侧。底面为 -128，顶面从 0 逐级下降。

主地图接入范围：替换原有少量亭阁与其附近装饰松树，八条主岛侧楼梯外侧增加收边。没有新增火焰或动态灯；这些装饰无碰撞。活动平台、出生点、水道、台阶和地形网格沿用现有布局。

源文件：`xianxia_detail_modules.blend`；独立 FBX 在 `models/`，Source 2 源定义在 `source_models/`。单位为 Source 单位，ModelDoc 导入比例 0.01。所有使用的材质名称指向 `materials/xianxia_kit/xx_*.vmat`。

`geometry_validation.json` 检查有限坐标、退化面和台阶高度。`previews/` 是 Blender 组件预览，主地图实际表现以 `../../survival_world_v2/cloud_detail_review.html` 中实机截图为准。

云限制：六种独立密度场烘焙成透明贴图，主地图使用 24 个外围云组和 10 个内部云带/薄雾。云片朝向镜头，光照为固定烘焙，不能任意绕看或无限放大。远景灰蓝色底面用于消除黑色虚空，不是真正的体积云海。当前仍保留山体和大量露出的地形，尚不能视为概念图的完整云海效果。

还原资料在 `../../survival_world_v2/before_cloud_integration_v2/`，包括原主地图源文件/编译包、旧云粒子源文件/编译资源及修改前截图。不要覆盖该目录。
