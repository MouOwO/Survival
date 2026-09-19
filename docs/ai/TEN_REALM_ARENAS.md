# 一至十戒 · 模型与独立验看地图

用户已认可 [700 × 700 概念图](../../output/ten_realm_arena_concepts_v2_700x700/index.html)，首版模型已制作。资产命名空间为 `ten_realm_arenas`，输出目录为 `output/ten_realm_arenas/`。当前 Blender 几何与编译资源静态验证通过，实机尚未验看；具体结果见下方验证记录。

## 模型规格

- 十处正方形场地主体均为 **700 × 700 游戏单位，包含围墙**。自然岸地、浅滩、岩石和植被向主体外延伸，全部模型水平边界受限于局部 ±580。
- 四面实体闭合、上方露天；中央 **612 × 612** 保留连续平整战斗净空。地面局部 Z=0，外部水位局部 Z=-42；墙高按各地貌规格。
- 每戒导出一个独立模型 `models/ten_realm_arenas/realm_01.vmdl` 至 `realm_10.vmdl`，使用各自几何、法线、反射与材质。模型自带碰撞；光效与发光不在本轮范围内。
- 入口局部地面位置 `[0,-234,0]`，Boss 生成位置 `[0,234,0]`。Hammer 标记在相应地面上方 24 单位，便于落点放置。
- 规格源：[ten_realm_spec.py](../../tools/ten_realm_spec.py)。这套十戒资产与一至十转 `ascension_arenas` 是不同内容。

| 戒数 | 模型 | 主题 |
| --- | --- | --- |
| 1 | `realm_01` | 黄沙古垒 |
| 2 | `realm_02` | 林间古环 |
| 3 | `realm_03` | 沼泽沉垣 |
| 4 | `realm_04` | 赤岩断谷 |
| 5 | `realm_05` | 霜雪寒垒 |
| 6 | `realm_06` | 潮礁碧湾 |
| 7 | `realm_07` | 熔岩黑岸 |
| 8 | `realm_08` | 紫晶岩庭 |
| 9 | `realm_09` | 天辉圣庭 |
| 10 | `realm_10` | 夜魇荒庭 |

## 地图、预制件与水面

总览地图：`ten_realm_arenas_review`，8192 × 8192，水平边界为 ±4096。十戒按两列五排布置，X 为 ±700，Y 为 -2560、-1280、0、1280、2560。模型整体加 Z=128，因此地面为 Z=128，海面为 Z=86。排布校验使用包含岸线、植被在内的实际模型边界，不只比较 700 × 700 主体。

十个预制件位于 `maps/prefabs/ten_realm_arena_01.vmap` 至 `ten_realm_arena_10.vmap`。每个在局部原点 `[0,0,0]`，包含一个模型、一块隐藏导航支撑，以及入口、Boss 生成、验看中心三个标记。没有烘焙总览的 Z=128 偏移、灯光、出生实体或整片海面；装配到其他地图时按局部 `water_z=-42` 对接该地图的水面。

每处导航支撑为 612 × 612，顶面比地面低 0.75，厚 4。材质 `floor_support.vmat` 带 `dota.nav.walkable=1` 和 `mapbuilder.nodraw=1`，提供不可见的稳定可走面。总览使用 32 × 32 隐藏地形瓦片与 128 × 128 个 64 单位导航格，只有各内场开放，外岸和水域关闭。

总览共用一块独立非实体水面，使用已验证的主岛 `multiblend.vfx` 海水材质流程：滚动波纹、法线、反射，`mapbuilder.nonsolid=1`、`mapbuilder.water=1`。模板及三张依赖复制到本资产命名空间，使用 `ocean_*` 文件名，避免覆盖房间模型自身的 `water_*` 材质。水面没有导航支撑，也没有工作室地板铺在海上。

标记名：

- `challenge_11_stage_01_entry` 至 `challenge_11_stage_10_entry`
- `challenge_11_stage_01_spawn` 至 `challenge_11_stage_10_spawn`
- `ten_realm_arena_01_center` 至 `ten_realm_arena_10_center`

保留既有阶段标记契约用于后续接入；本轮不修改运行时挑战配置、CSV、`addoninfo.txt` 或正式 `template_map`。

## 生成、安装与打开

先由 Blender 管线完成模型、材质和 `asset_manifest.json`，再生成地图：

```powershell
node tools/build_ten_realm_arena_map.cjs
```

生成器写入输出目录下的 `source/materials/ten_realm_arenas/`、独立 review 地图、十个 prefab、`layout.json` 与 `map_manifest.json`。依赖已存在的 `output/zombie_island_v1/source_template.vmap` 与主岛海水源材质及 PNG。

安装到 Source2 content 并编译：

```powershell
powershell -ExecutionPolicy Bypass -File tools/install_ten_realm_arenas.ps1
```

安装器先检查所有相对路径，只允许本命名空间的模型/材质、独立 review 地图及十个 prefab；随后复制源文件并依次编译 `.vmat`、`.vmdl` 和地图。地图编译要求新写入的 VPK，并记录 `compile.json` 的时间与 SHA-256。`-SkipMap` 可只执行资源安装编译；它不表示地图已更新。

游戏控制台打开：

```text
dota_launch_custom_game survival ten_realm_arenas_review
```

快捷入口（对应文件生成后可用）：

```powershell
powershell -ExecutionPolicy Bypass -File tools/open_scene.ps1 -Scene ten_realms -Action preview
powershell -ExecutionPolicy Bypass -File tools/open_scene.ps1 -Scene ten_realms -Action blender
powershell -ExecutionPolicy Bypass -File tools/open_scene.ps1 -Scene ten_realms -Action map
powershell -ExecutionPolicy Bypass -File tools/open_scene.ps1 -Scene ten_realms -Action prefab
powershell -ExecutionPolicy Bypass -File tools/open_scene.ps1 -Scene ten_realms -Action game
powershell -ExecutionPolicy Bypass -File tools/open_scene.ps1 -Scene ten_realms -Action review
```

`prefab` 快捷入口定位一戒；其余九个在同一目录。Blender 工程约定为 `output/ten_realm_arenas/ten_realm_arenas.blend`，网页入口为该目录的 `index.html`。

### 游戏内逐戒验看

地图加载后，`-Action review` 复制启动指令。以下指令只可用于 Workshop Tools 的 `ten_realm_arenas_review`，默认查看一戒；不加载或修改正式挑战逻辑，也不传送英雄，只切换验看镜头。

```text
ent_fire 0 RunScriptCode "require('tests/manual_ten_realm_arena_review').start()"
ent_fire 0 RunScriptCode "require('tests/manual_ten_realm_arena_review').stage(9)"
ent_fire 0 RunScriptCode "require('tests/manual_ten_realm_arena_review').overview()"
ent_fire 0 RunScriptCode "require('tests/manual_ten_realm_arena_review').finish()"
```

`start(1)` 至 `start(10)` 可直接指定初始戒数；启动后 `stage(1..10)` 切换至对应场地全景，`overview()` 看十戒总览。脚本复用既有 30 个入口、生成点与中心标记，控制台输出当前场地三个点的地面高度及导航状态供人工观察，不将这些打印信息当作移动测试通过记录。`finish()` 清理临时镜头、视野和验看任务，恢复普通镜头距离 1134。验看期间临时取消未建城墙倒计时，作用范围仅为此独立测试地图。

## 实际模型验看图库

[模型图库](../../output/ten_realm_arenas/index.html) 展示实际 Blender 模型渲染，顶部为十戒总览，下方十张卡片分别可切换整体、俯视、材质细节和已确认的 700 × 700 概念图。模型渲染与概念参考在图片上分别标注；点击可放大，左右方向键切换戒数，上下方向键切换视图，Esc 关闭。

预览文件约定：

- `previews/all_realms.png`：完整模型总览。
- `previews/realm_01_hero.png` 至 `realm_10_hero.png`：各戒实际模型整体视图。
- `previews/realm_01_top.png` 至 `realm_10_top.png`：各戒实际模型俯视图。
- `previews/realm_01_detail.png` 至 `realm_10_detail.png`：各戒材质与边缘细节。
- 对照概念保留于 `../ten_realm_arena_concepts_v2_700x700/realm_01.png` 至 `realm_10.png`。

模型与预览完成后生成页面：

```powershell
node tools/build_ten_realm_model_gallery.cjs
```

图库读取 `asset_manifest.json` 的实际三角面、材质数、碰撞体数及 bounds。每卡分别显示 700 × 700 含围墙主体、612 × 612 战斗净空和包含岸线/植被的真实外缘尺寸。本轮约定每场 5 个简化碰撞体，页面显示资产清单中的真实记录。

`verification.json` 与 `blend_check.json` 用于显示资源/地图静态验证和 Blender 工程检查状态，只有显式 `status=PASS` 才标为通过；记录缺失显示“等待验证”。这不是额外审批流程，也不代表游戏内画面已经通过实机验证。页面提供 Blender 工程、原图、概念图集和可复制的独立测试地图命令。

## 布局清单接口

地图生成器消费 `asset_manifest.json` 的十项数组。每项包含 `name`、实际局部 `bounds`、`materials`、正整数 `collision_count`（兼容同值 `collision_hulls`、数值 `collision` 或碰撞数组），以及完整 `meta` 规格。

`layout.json` 的 `schema_version=1`：

| 字段 | 内容 / 验证用途 |
| --- | --- |
| `namespace`, `review`, `base_z` | 资产命名空间、总览地图名、模型整体高度偏移 |
| `footprint`, `clear_combat_size` | 主体 700 × 700 与内场 612 × 612 |
| `review_bounds`, `occupied_bounds`, `envelopes` | 总览边界、全部模型占用边界、各模型含岸线的二维边界 |
| `min_envelope_clearance` | 实际模型边界之间的最小间隙；生成时检查重叠与越界 |
| `placements[]` | 各模型 `rank/name/model/origin/yaw/scale`、地面/水位、墙高、局部与世界边界、碰撞数、支撑高度及标记名 |
| `supports[]` | 各隐藏支撑的 `rank/name/material/polygon/bounds/size/top/bottom`，可对照 VMAP 真实网格坐标 |
| `markers[]` | 共 30 个；每项 `rank/name/kind/origin/local_floor_position/spawn_clearance`，高度包含 24 单位落点余量 |
| `prefabs[]` | 十个局部原点预制件；包含各自 `placement/supports/markers` 和不包含海面的 `water` 接口 |
| `walkable_support` | 支撑材质、0.75 下沉、4 单位厚度、不可见属性 |
| `water` | 海水材质与三个贴图依赖、世界/局部水位、网格 bounds、非实体和不参与导航标记 |
| `navigation` | 瓦片数、导航格数、64 单位格尺寸、原点、可走/禁止标记值、总开放格数与各戒开放格数、十个区域 polygon |
| `open_grid_cells`, `open_cells_by_rank` | 导航计数的便捷顶层字段 |
| `main_map_modified`, `runtime_verified` | 均为 false；静态生成不能作为正式地图修改或实机测试证明 |

`map_manifest.json` 汇总 review 名称、十个 prefab 路径、10 个模型实例、30 个标记、支撑数、边界、完整 `water/navigation` 字段及 `mainMapModified/runtimeVerified=false`。

## 当前验证结果与实机范围

2026-09-18 当前首版记录：

- **10 个独立模型，共 943,588 个三角面**；每个模型 **5 个碰撞体**，共 50 个。
- **50 套材质**通过编译资源检查。Blender 工程检查覆盖其中 48 个实际引用材质；这两个数量对应不同检查范围。
- [blend_check.json](../../output/ten_realm_arenas/blend_check.json)：**PASS**，完成 **14,660 条几何射线**检查，报告总三角面为 943,588。
- [verification.json](../../output/ten_realm_arenas/verification.json)：**PASS**，模型编译边界、PHYS 碰撞、材质法线/反射、安装源一致性、导航支撑、独立海面、30 个标记、10 个 prefab 及地图 VPK 检查完成；编译模型三角面总数与资产清单一致。
- 以上两份记录均明确 `runtime_verified=false`。**尚未实机运行验看**；游戏 helper 当前只完成语法与文件/标记引用检查，不能作为实机测试结果。

实机仍需单独确认英雄落点、四边阻挡、战斗内场通行、水岸接缝和最终光照。后续重建后以最新 JSON 验证记录为准。
