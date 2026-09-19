# 一至十转擂台 · 尺寸扩展版

依据用户认可的十张概念图制作，提供十个独立模型、碰撞、材质、Blender 工程及专用验看地图。

当前版本：`ascension_arenas_v2_1000x550`。原设计图尺寸 **700 × 350**，现模型已按追加要求扩大为 **1000 × 550**（长增加 300、宽增加 200）；高度保持不变。原概念 PNG 保留历史尺寸，未重新绘制。

## 打开

- 浏览器：`output/ascension_arenas/index.html`，每转可切换整体、俯视、侧视和概念图。
- Blender：`output/ascension_arenas/ascension_arenas.blend`，场景 `00 - All ten arenas` 为总览，其余十个场景逐转独立展示，贴图已打包。
- 快捷入口：项目根目录 `打开地图测试.cmd` → **一至十转擂台**。
- Hammer 地图：content 工程 `maps/ascension_arenas_review.vmap`。
- 可复用预制件：content 工程 `maps/prefabs/ascension_arena_01.vmap` 至 `ascension_arena_10.vmap`，均在局部原点。

游戏控制台加载：

```text
dota_launch_custom_game survival ascension_arenas_review
```

进入地图后开启总览、查看某一转、结束验看：

```text
ent_fire 0 RunScriptCode "require('tests/manual_ascension_arena_review').start()"
ent_fire 0 RunScriptCode "require('tests/manual_ascension_arena_review').focus(10)"
ent_fire 0 RunScriptCode "require('tests/manual_ascension_arena_review').finish()"
```

验看工具仅在指定 Tools 地图手动启用；其间提供视野与镜头控制，并临时取消未建城墙倒计时。

## 尺寸与主题

所有实体装饰收在 **1000 × 550** 整体占地内。每转增加一层 14 单位的低台层，单侧逐层内缩 1.5；边沿装饰不计作额外台层。碰撞逐层建造，中央保留平坦连续的战斗面。各转台面高度、层数和预览抬升高度沿用原版；本次扩展的是长宽。

图库的“整体占地”和“中央净空”从当前 `asset_manifest.json` 的 `meta.footprint`、`meta.clear_combat_size` 读取。切换“原设计图”时看到的 700 × 350 标注属于历史概念尺寸，不代表当前模型边界。

| 转数 | 模型 | 主材料 | 台面高度 |
| --- | --- | --- | --- |
| 1 | 夯土试武台 | 夯土、碎石、旧木桩 | 14 |
| 2 | 木垒练武台 | 泥地、木框、铁箍 | 28 |
| 3 | 青石比武台 | 粗青石 | 42 |
| 4 | 砌石演武台 | 规整砌石、旧铜 | 56 |
| 5 | 白石晋阶台 | 浅白石、细金属嵌线 | 70 |
| 6 | 青玉试炼台 | 青玉、白石 | 84 |
| 7 | 玄晶登阶台 | 冷灰矿石、烟蓝晶体 | 98 |
| 8 | 天玉凌空台 | 天玉、局部云面 | 112 |
| 9 | 流云登仙台 | 以云面为主、玉石边框 | 126 |
| 10 | 太虚云擂 | 实体云面、少量金玉角饰 | 140 |

八至十转在验看场景中分别抬起 10、20、30 单位表达轻盈感；这只是摆放偏移，独立模型底部仍为 Z=0。十转主体是有厚度的云层几何，不使用透明雾或白光遮住石台。

## 材质和工程

- Source 2 使用 `global_lit_simple.vfx`、颜色图、DirectX 法线图、线性 R 通道反射遮罩；全部无自发光。
- 木材按构件长轴铺木纹，端面使用年轮。石材保留磨损、凹坑与反光变化；玉石及金属有对应的反射差别。
- 云使用单独的蓝白云纹、柔和法线与珍珠色亮部，不沿用石材裂纹。
- Blender 的粗糙度和金属度贴图用于预览；引擎反射采用单独遮罩。两种渲染器的光照结果需分别验看。
- `asset_manifest.json` 记录实际模型边界、面数、材质、碰撞及原始几何中的台层范围；`material_manifest.json` 记录贴图与 shader 参数。

复现命令：

```powershell
& 'D:/magic and love/软件/Blender/blender.exe' --background --threads 8 --python tools/build_ascension_arenas.py
node tools/build_ascension_arena_map.cjs
./tools/install_ascension_arenas.ps1
& 'D:/magic and love/软件/Blender/5.2/python/bin/python.exe' -B -X utf8 tools/verify_ascension_arenas.py
node tools/build_ascension_gallery.cjs
```

源资产生成在 `output/ascension_arenas/source`，安装脚本只复制本套资源至 content 并编译至 game。现有正式地图及转生玩法绑定仍由原项目管理；本轮提供独立验看资产。练功房 **900 × 900** 的尺寸要求另行记录，没有把原练功房宣称为已经完成调整。

## 验证范围

以 `output/ascension_arenas/verification.json` 的实际结果为准：包括十个编译模型、物理碰撞、材质依赖与参数、层数/边界、安装源一致性和地图 VPK 完整性。浏览器图片是 Blender 实际模型渲染。尚需在游戏内确认行走、相机遮挡与最终光照，不将静态资源检查等同于实机验收。
