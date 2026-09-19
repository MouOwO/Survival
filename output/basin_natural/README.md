# 单平台自然石岸样板

地图源文件：`content/dota_addons/survival/maps/survival_basin_natural.vmap`。
用户手工源文件 `survival_basin_native.vmap` 未覆盖。

中央顶面与水岸为同一块可编辑的 Hammer 网格，名称 `ART_Editable_Slate_And_Shore`。
它不是导入的静态模型，带有 VertexPaintBlendParams / VertexPaintTintColor，使用多层材质。
原生外围和西侧台阶使用独立复制的 `maps/tilesets/survival_natural_slate.vmap`。

材质：`materials/basin_natural/ground.vmat`。
石地颜色、法线和粗糙度分别由 Blender 石块几何独立烘焙，2048×2048。
法线约定 +X / -Y / +Z。已检查横纵拼接边缘，结果见 texture_checks.json。
当前 Dota multiblend 材质使用独立的 reflectance 控制；粗糙度原图作为源资产保留，没有冒充 reflectance 数据直接接入。
建模源文件：`materials/natural_slate.blend`（本文件旁的 output 目录内）。

测试范围：画面与地面通行样板，不是完整玩法地图；怪物波次和四方向城墙规则尚未迁入本样板。
预览截图由游戏自动生成，截图和地图编译时间记录于 capture_manifest.json。
