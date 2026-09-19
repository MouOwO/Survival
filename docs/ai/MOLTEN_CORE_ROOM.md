# 熔火核心挑战房间

## 交付范围

按用户四张熔火核心参考图制作独立模块化房间，沿用金币练功房的组合材质流程。用户明确要求不用发光：本轮没有发光材质、火焰、粒子、局部效果灯。熔岩槽采用冷却外壳与暗橙裂隙的普通受光颜色，传送嵌件采用青色铜面，中央纹样采用铜质平面嵌纹。

- 预览：`output/molten_core_room/index.html`。
- Blender 源文件：`output/molten_core_room/molten_core_room.blend`，所有用到的图片已打包。
- 两个场景：`Molten Core Room - assembled` 完整组合；`F01-F16 Modular Library` 独立组件库。
- FBX / ModelDoc / 碰撞源文件：`output/molten_core_room/source/models/molten_core_room/`。
- 材质 / 贴图：`output/molten_core_room/source/materials/molten_core_room/`。
- Hammer 独立地图：`source/maps/molten_core_room_review.vmap`。
- Hammer 预制件：`source/maps/prefabs/molten_core_room.vmap`。

新资源使用独立 `molten_core_room` 命名空间。正式地图、已有主岛 / 金币房、CSV、挑战服务未修改。预制件仍是独立实例组合，包含行走支撑与命名标记；不包含样板地图的环境光、地图边界和测试出生实体。

## 组件

30 个自制组件，16 套 1024×1024 材质。各套包含颜色、法线、粗糙度和游戏反射贴图。完整组合包含 450 个实例、339476 个三角面。

| 参考项 | 制作内容 |
| --- | --- |
| F01–F02 | 两款标准玄武岩地砖、焦痕地砖、半圆传送龛铺地 |
| F03–F06 | 256 / 128 码直墙、包铜墙柱与可拆柱顶、90 度转角、60 度弧墙 |
| F07 | 低矮传送石环、独立青铜嵌片，无门框 |
| F08 | 中央刷怪平铺铜纹，几何最高点低于地面上方 1 码 |
| F09 | 熔岩槽直段、转角、封闭端头，独立直段 / 转角表面 |
| F10 | 炉火支架与空火盆，盆中冷却炭块，无火焰 |
| F11 | 标识碑主体与独立铜质火焰徽记 |
| F12 | 大、中、小、扁平四种火山岩 |
| F13 | 玄武岩、焦黑石、暗铁、旧铜、氧化铜、熔岩等材质族 |
| F14 | 火山碎石组、不规则焦灰接地片 |
| F15 | 按用户要求省略光效和粒子 |
| F16 | 墙角组装示范、入口挂旗；另有外围焦灰基底 |

大岩石集中在外角，熔岩槽位于墙外。内部焦灰只集中在墙脚；内场保持通行净空。入口背墙由三个 60 度模块组成，中间接缝加包铜短柱。

## 材质

### 材质打磨 v2

按已确认的金币房材质响应方案，新增独立的 `tools/molten_room_materials.py`。玄武岩区分断面磨损、裂缝和火山孔隙；焦石覆灰区域保持哑光；铜器区分青绿氧化层与裸露磨亮铜面；暗铁保留锻造凹痕。冷却熔岩的外壳与暗橙裂隙具有不同反射，仍为普通受光材质，无自发光、火焰或粒子。

引擎使用 `global_lit_simple` 的线性 R 反射遮罩，并明确设置浮点 `g_flSpecularIntensity`、`g_flBumpStrength` 与零 `g_flSpecularBloom`。法线按既有 UV 尺度生成；DirectX 法线仅在 Blender 节点中翻转一次 G。粗糙度和金属度贴图用于 Blender，未虚称引擎接受 PBR 粗糙度输入。

`output/molten_core_room/material_review/index.html` 是同光照、同相机的 Blender 前后对比，另更新完整房间预览。几何、UV、碰撞、布局和地图光照均不变。新材质没有重新做实机画面对比；此前 `runtime_verification.json` 记录的是原来的导航检查，不能视为新版材质的实机验收。

只刷新材质，不重建模型或地图：

```powershell
& 'D:/magic and love/软件/Blender/blender.exe' --background --python tools/refine_molten_room_materials.py
& tools/install_molten_core_room.ps1 -MaterialsOnly
& 'D:/magic and love/软件/Blender/5.2/python/bin/python.exe' -B -X utf8 tools/verify_molten_core_room.py
```

初版的 `molten_surface_materials.py` 在项目既有 `wall_surface_materials.py` 基础上加入可平铺的矿物裂隙、玄武岩孔洞和冷却外壳。颜色、法线与粗糙度由同一套表面痕迹生成，旧铜有氧化斑和划痕，石材实体倒角使用克制的磨损亮边。

全部 VMAT 为普通 `global_lit_simple.vfx`，带法线与反射输入；没有 fullbright、自发光或纹理滚动。Blender BSDF 的 Emission Strength 为 0。预览中的照明仅为场景环境光。

## 尺寸与接入

| 项目 | 数值 |
| --- | --- |
| 内场基准 | 2048 × 2304 Source 码 |
| 地砖模块 | 256 × 256，包含 3 × 3 块石板 |
| 直墙标准节距 | 256；半段 128 |
| 墙顶 | 地面上方 186 |
| Blender 地面 | Z=0 |
| Hammer 样板地面 | Z=128 |
| 连续行走支撑 | Z=127.25，低于石板表面 |
| 传送底座中心 | 本地 `(0, 1096, 0)` |
| 中央地纹中心 | 本地 `(0, -140, 0)` |

FBX 导出预先做轴校正；编译后 yaw=0 与 Blender 组件方向对应。墙体、墙柱与标识碑有简化碰撞；地板由连续世界支撑提供导航。支撑使用 `dota.nav.walkable` 和 `mapbuilder.nodraw`，避免穿插显示。

当前挑战 07 配置使用 `challenge_07_entry`、`challenge_07_home`、`challenge_07_boss_spawn`；三个名称均保留。另有 `challenge_07_spawn_01` 至 `10` 共十个美术摆放参考点，未自动修改原有刷怪配置。正式合并时应随房间整体平移标记和行走支撑，并避免与原地图同名标记重复。

本轮只建立资源与独立样板，未把传送、维持怪物数量、掉落和战斗逻辑接入测试地图。

## 验证记录

资源检查输出为 `output/molten_core_room/verification.json`，直接读取编译后的模型和材质，核对尺度 / 方向、碰撞、法线 / 反射、无发光、中央纹样厚度、外侧熔岩槽位置及标记。

实机结果及实际范围见同目录 `runtime_verification.json`；页面中的 Blender 效果图与 Workshop 实际截图分别标注。不将资源编译成功等同于正式玩法联调完成。

本轮编译资源检查通过。Workshop 实测入口、中央及内场采样点可行走，围墙和外侧熔岩槽样本不可行走。实际建造者完成“传送底座 → 中央 → 左下 → 右下 → 右上 → 左上 → 传送底座”六段路线，耗时约 19.37 秒；没有启用真实挑战刷怪与掉落流程。

检查结束后已恢复建造者原位置 / 速度，释放测试相机与定时器并退出独立地图。Blender 当前打开完整房间；切换前的工作场景副本保存在 `blender_before_molten_room.blend`。

## 重建

工作目录为 game addon `survival`。编译地图前退出当前测试局，释放地图 VPK。

```powershell
& 'D:/magic and love/软件/Blender/blender.exe' --background --python tools/build_molten_core_room.py
& 'D:/magic and love/软件/Blender/blender.exe' --background --python tools/render_molten_room_library.py
node tools/build_molten_core_room_map.cjs
& tools/install_molten_core_room.ps1
& 'D:/magic and love/软件/Blender/5.2/python/bin/python.exe' -X utf8 tools/verify_molten_core_room.py
node tools/build_molten_room_gallery.cjs
```

建模复用项目 `GoldKit` 的基础几何，传送龛裁切轮廓复用金币房的已验证轮廓；独立制作玄武岩墙体、包铜件、熔岩槽与功能组件。地图生成复用现有 VMAP 序列化代码和 `output/zombie_island_v1/source_template.vmap`。不依赖外部生成模型服务。

仅在独立 `molten_core_room_review`、Workshop Tools 模式运行：

```lua
require('tests/manual_molten_room_review').start()
-- 实际建造者出现后，检查入口、中心和四角之间行走：
require('tests/manual_molten_room_review').probe()
require('tests/manual_molten_room_review').finish()
```

助手会临时关闭“未建城墙”失败倒计时，检查结束时恢复建造者原位置 / 速度、相机并清理检查定时器。它不启动真实挑战服务。
