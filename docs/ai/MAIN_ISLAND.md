# 十字主岛模块化样板

## 交付

2026-09-17，按用户四张主岛概念 / 组件图，沿用金币练功房的建模与组合材质流程制作。

- 预览：`output/main_island/index.html`。
- Blender：`output/main_island/main_island.blend`，贴图已打包。两个场景分别是完整组合和独立组件库。
- 41 个自制模型，25 套 1024×1024 颜色、法线、粗糙度及反射贴图，1689 个摆放实例。原生松树另外复用。
- 可编辑源文件：`output/main_island/source/models/main_island/`、`source/materials/main_island/`。
- 独立 Hammer 地图：`source/maps/main_island_review.vmap`；预制件：`source/maps/prefabs/main_island.vmap`。
- 源资源已同步到项目的 `content/dota_addons/survival/`，模型 / 材质和独立测试地图已编译到 game 目录。
- 正式主地图、建筑 CSV、出生与战斗逻辑未替换。

## 组件与布局

| 参考编号 | 实现 |
| --- | --- |
| M01–M03 | 玩家平台、左右连接通道、16 级迎敌踏步及独立侧帮 |
| M04–M06 | 内岸直墙、内外折角、外岸转角基体 |
| M07–M09 | 干净 / 磨损 / 苔痕石板，直线 / 转角 / 端头压顶，三种岩壁轮廓 |
| M10–M12 | 干湿石土过渡、湿润岸带、独立水线、水面及中央涡纹表面 |
| M13–M15 | 外围矮墙与短柱，青绿 / 灰蓝 / 暖赭 / 淡紫红旗帜，三种岩石 |
| M16–M17 | 两种自制樱树、原生松树，草丛、蕨类、矮灌木、花和苔痕 |
| M18 | 单侧平台组装示范，见玩家平台近景；不另做不可拆解的大模型 |

四个玩家平台围绕中央十字水域，通道和阶梯净空内不摆树木。矮墙与主要植被放在外围。旗布与旗杆独立，能单独更换颜色。

以已有主岛范围及主平台 / 水面高度为尺度基准，重新制作参考图布局。样板统一平台高度；没有直接保留旧地形所有局部高差。

| 项目 | Source 单位 |
| --- | --- |
| 样板中心 | `(0, 0, 0)` |
| 整体平移到旧主岛中心 | `(-1152, 2688, 0)` |
| 岛体 XY 边界 | 各方向约 ±4864 |
| 平台表面 | Z=640 |
| 水面 | Z=400 |
| 中央浅层行走支撑 | Z=396 |
| 阶梯净宽 / 水平长度 | 576 / 512 |
| 阶梯高差 / 级数 | 244 / 16 |
| 石板基本间距 | 128 |
| 岸墙 / 岩壁模块基本长度 | 256 |

中央水下支撑保留迎敌通路，与水面视觉独立。外围海域不可行走。平台行走支撑顶面 639.1，略低于石板；专用材质同时具有 `dota.nav.walkable` 和 `mapbuilder.nodraw`，避免支撑遮住石板或在远景出现深度重叠。

预制件包含平台 / 阶梯支撑、中央浅层支撑和水面。原地图已有水面时应选择需要的部件合并，避免叠加海面。预制件不带样板地图的环境光和测试出生实体。

12 个预留标记分别为四方的 `main_island_player_N_builder_spawn`、`main_island_player_N_gate`、`main_island_player_N_attack_entry`。这些是美术样板标记，尚未绑定正式玩法。正式合并时还需要核对塔位、建造网格、出生位置、攻击路线和地图边界。

## 材质与源文件

- 石板采用暖灰主色、真实倒角、局部色差及表面风化。岩壁深灰，靠水区域增加深色湿润带。金属、旗布、树木各有独立表面。
- 沿用 `gold_room_geometry.py` 和 `wall_surface_materials.py` 的自制几何 / 程序材质基础，没有覆盖金币练功房文件。
- 水面使用项目已有 Dota 原生水法线与新深蓝颜色重新组合；运行时海面使用已有 ocean shader 的滚动波纹。中央涡纹是独立 UV 扭转表面，**不包含真正旋转水流、流体模拟或水流玩法**。
- 松树复用 `models/props_foliage/tree_pine01.vmdl`，Blender 中使用项目已提取的同款预览网格。其余本轮组件为自制。
- FBX 导出前烘入轴校正，Source 2 中 yaw=0 与 Blender 场景布局一致。碰撞 OBJ 使用对应坐标转换。
- 大平台和踏步由地图支撑提供连续行走碰撞，岸墙等阻挡件使用简化碰撞体。小植被没有额外碰撞。
- 组合自制网格约 149 万三角面，不含原生松树。尚未进行正式多人战斗性能测试和距离 LOD 优化。

## 验证

- `verification.json`：41 个编译模型的边界误差均小于 0.05 码；材质依赖、法线 / 反射、碰撞、实例、标记、中央净空和地图编译检查通过。
- `runtime_verification.json`：在 `main_island_review` 实机采样四方平台、阶梯、入水处等 28 点及中心，均可行走；外海与侧边边界样本不可行走。
- 实际建造者完成“北 → 中央 → 西 → 中央 → 南 → 中央 → 东 → 中央 → 北”8 段路线，约 50.33 秒。测试只验证该样板的几何通行，不代表正式刷怪、建造或战斗联调。
- 游戏截图在 `previews/runtime_overview.png` 和 `previews/runtime_platform.png`；Blender 效果预览与游戏截图在页面中分别标注。
- 检查结束后已恢复建造者原位置 / 速度、释放相机与检查定时器并退出测试局；Blender 当前打开完整主岛场景。

## 重建

工作目录为 game addon 的 `survival`。编译地图前先退出当前测试局，释放 VPK 文件。

```powershell
& 'D:/magic and love/软件/Blender/blender.exe' --background --python tools/build_main_island.py
& 'D:/magic and love/软件/Blender/blender.exe' --background --python tools/render_main_island_library.py
node tools/build_main_island_map.cjs
& tools/install_main_island.ps1
& 'D:/magic and love/软件/Blender/5.2/python/bin/python.exe' -X utf8 tools/verify_main_island.py
node tools/build_main_island_gallery.cjs
```

地图生成器复用 `build_zombie_abyss_map.cjs` 的 VMAP 序列化函数及项目已有模板。清理旧项目输出时，需保留这些生成依赖和原生松树 / 水材质源文件。

仅在独立地图、Workshop Tools 中运行人工检查助手：

```lua
require('tests/manual_main_island_review').start()
-- 等实际建造者出现后：
require('tests/manual_main_island_review').probe()
-- 完成检查后恢复单位、相机并清理检查定时器：
require('tests/manual_main_island_review').finish()
```
