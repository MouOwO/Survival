# 金币练功房 · 模块化样板

## 材质修订：gold_surface_response_v2

本次只更新金币练功房的材质与预览。几何、UV、碰撞、房间布局和地图光照保持原样；主岛、熔火核心及其他建筑未采用此修订。

- 验看入口：`output/gold_training_room/material_review/index.html`，提供石材/金币、石材/铜盆的同角度前后滑动对比。对比图为同光照的 Blender Cycles 渲染，游戏截图单独标注。
- 已查明：原编译材质已启用并绑定法线与高光。`global_lit_simple.vfx` 的 Reflectance 是线性 R 通道强度；它没有 PBR Roughness / Metallic 输入，因此 Blender 粗糙度不会直接带进游戏。旧算法让石面反射几乎恒定在约 0.025，材质之间的反射差异不足。
- 改动：石材增加中等尺度表面起伏、矿物孔隙和磨损面的反射变化；天然岩石更粗糙；青铜和金币按氧化/磨亮区域分别控制高光；木纹凹凸加强，布料保持哑光。统一法线方向约定，Blender 端只做一次 DirectX → OpenGL 的 G 通道翻转。
- 保留原生道具使用的 `global_lit_simple`，显式写入浮点型 `g_flSpecularIntensity` / `g_flBumpStrength`；`g_flSpecularBloom=0.0`。未添加自发光或粒子。Roughness / Metallic PNG 用于 Blender 预览，游戏读取独立的 Reflectance 遮罩；两种着色器并非完全等价。
- 独立实现：`tools/gold_room_materials.py`。共享的 `wall_surface_materials.py` 未更改，防止其他房间重建时一起变化。
- 已通过实际编译资源检查：29 个模型、15 套材质、599 个实例；高光浮点参数、纹理依赖、安装源文件一致性、模型边界、碰撞和可行走支撑属性均通过。实机截图及本轮验证结果见 `material_review/`；旧的 `previews/runtime_complete.png` 是上一轮基准图。
- 本轮已加载独立游戏地图，但截图被难度选择 / 判负界面遮挡，没有完成无遮挡的游戏近景对比。此限制记录在 `material_review/runtime_verification.json`，遮挡截图不作为画质验收图，也不放进材质对比页。

仅更新现有房间材质时：

1. Blender 后台运行 `tools/refine_gold_room_materials.py`，更新贴图、打包场景和同条件预览。
2. `tools/install_gold_training_room.ps1 -MaterialsOnly`，只同步本房间材质；不覆盖地图、模型和 `floor_support.vmat`。
3. Blender 后台运行 `tools/refresh_gold_room_cards.py` 更新组件卡片；运行 `tools/verify_gold_training_room.py` 检查实际编译资源。
4. `node tools/build_gold_material_review.cjs` 与 `node tools/build_gold_room_gallery.cjs` 更新预览页。

## 交付

按用户提供的四张参考图搭建封闭练功房：后侧半圆传送台、中央金属刷怪地纹、石墙、金币标识碑、青铜火盆、外围岩石与植被。全部为可编辑网格；没有制作发光、火焰或粒子。

- 预览：`output/gold_training_room/index.html`，含全景、俯视、近景、29 张组件卡片。
- Blender：`output/gold_training_room/gold_training_room.blend`，贴图已打包；含 `Gold Practice Room - assembled` 和 `B01-B16 Modular Library` 两个场景。
- Hammer 独立地图：`content/dota_addons/survival/maps/gold_training_room_review.vmap`。
- Hammer 房间预制件：`content/dota_addons/survival/maps/prefabs/gold_training_room.vmap`。保留独立组件和地面支撑，不含预览灯光、出生点、背景地面。
- 源文件备份：`output/gold_training_room/source/`；编译地图 `maps/gold_training_room_review.vpk`。
- 自制模型目录：`models/gold_training_room/`；材质目录：`materials/gold_training_room/`。

共 29 个自制组件、599 个摆放实例、约 36 万个自制三角面。15 套 1024×1024 表面贴图（颜色、法线、粗糙度及 Source 2 反射图），另有共享砂浆贴图的可行走地面材质。B15 松树复用原生 `models/props_foliage/tree_pine01.vmdl`；Blender 中有实际原生模型预览副本。

## 模块与尺寸

| 分类 | 内容 |
| --- | --- |
| B01–B02 | 两种标准地坪、破损地坪、半圆壁龛铺地 |
| B03–B06 | 256 / 128 直墙、普通 / 金币墙柱、90° 转角、60° 弧墙 |
| B07–B10 | 传送台、中央嵌纹、金币碑 / 独立浮雕、火盆基座 / 铜盆 |
| B11–B14 | 大中小岩石、碎石、接地块、两种草丛、蕨类、两种灌木 |
| B15–B16 | 原生松树、挂旗、苔痕；另有薄层外围接地网格 |

房间净铺地尺寸为 2048×2304，中央保持开阔。地坪模块 256×256，内含四块 128 码石板；直墙高 176；三片 60° 弧墙拼成后部半圆。Blender 地面 Z=0；Hammer 中整体 Z+128。所有位置、角度和比例见 `room_layout.json`，可按实例继续调整。

石材做了倒角、缺口、凹蚀法线、温冷色差和墙脚苔痕；青铜、金色嵌件有氧化与反射变化；布旗保留青绿色。没有把参考图直接贴在平面上。

## 碰撞、行走与玩法边界

墙、柱、金币碑具有闭合碰撞。转角采用两个凸体，弧墙按曲线拆成五个凸体，避免一个大凸包封住壁龛。草木、嵌纹等装饰不阻挡。

行走平面由配套世界网格提供，支撑面 Z=127.25，略低于破损地砖表面。`floor_support.vmat` 必须保留 `Attributes { "dota.nav.walkable" "1" }`；仅有世界网格碰撞不足以生成 Dota 可行走区域。

预制件含 `challenge_02_entry`、`challenge_02_home` 和 `challenge_02_spawn_01` 至 `08` 共十个标记。名称沿用现有金币房配置。合并到正式地图时应一起移动这些标记和支撑网格，并在主地图中确认边界的导航网格。不要保留两套同名金币房标记。

本轮完成独立场景与组件，未将它替换进正式主地图，未改 CSV、奖励、传送或刷怪逻辑；完整玩法联调不是本轮验证结论。

## 已验证

- 29 个实际编译模型的 XYZ 边界逐一比对 Blender 清单，误差小于 0.04；材质依赖和碰撞块存在性通过。
- 15 套材质具有实际颜色 / 法线变化及反射贴图；无发光开关。地面支撑的可行走属性在编译材质中存在。
- 599 个道具实例、十个玩法标记、独立地图与预制件结构检查通过；VPK 写入和编译结果均成功。
- Workshop 实际加载 `gold_training_room_review`：全房间可见；入口、归位点、两个刷怪点、中央与靠东侧室内点可行走；东墙及墙外样本不可行走。
- 实际建造者从 `(0,0,127.25)` 步行到 `(0,899.993896,127.25)`，确认室内可移动。
- 游戏内截图 `previews/runtime_complete.png`。该图保留正常 HUD。完整战斗、所有刷怪点、奖励流程和性能基准未逐项验证。
- 调试相机与视野已释放，测试地图已退出。Blender 中保留完成的房间。

自动审计见 `verification.json`；实机范围见 `runtime_verification.json`。早期 `runtime_overview.png` / `runtime_final.png` 是调整中截图，不作为最终验收图。

## 重建

1. Blender 后台运行 `tools/build_gold_training_room.py`，生成网格、贴图、模型源文件、完整场景和房间预览。
2. Blender 后台运行 `tools/render_gold_room_library.py`，生成组件卡片并整理组件库。
3. `node tools/build_gold_training_room_map.cjs`，生成独立地图、预制件和可行走支撑材质。
4. 先退出当前预览局，再运行 `tools/install_gold_training_room.ps1`，同步至 content 并编译。不要在地图 VPK 被游戏占用时编译；脚本会检查实际写入时间，防止把“0 failed”误当成 VPK 已更新。
5. 用 Blender 自带 Python 运行 `tools/verify_gold_training_room.py`；运行 `node tools/build_gold_room_gallery.cjs` 更新预览页。

依赖已有 `reference_building_geometry.py`、`wall_surface_materials.py` 和 `output/zombie_island_v1/source_template.vmap`。原生松树的预览 GLB 位于 `native_preview/`。FBX 导出时预烘 -90° Z 旋转来抵消 Source 2 导入转换，碰撞 OBJ 使用同一空间约定，不要单独旋转 Hammer 道具来补偿。

可选 Tools 检查助手 `scripts/vscripts/tests/manual_gold_room_review.lua` 只允许在这张独立地图执行：`.start()` 设置观察相机并临时取消无城墙败北倒计时，`.inspect()` 打印采样点导航，`.finish()` 释放相机与视野。它不会被正常玩法自动加载。重新开局恢复正常倒计时。
