# 修仙组件库：首版资源与组合样板

打开 `index.html` 查看实际模型渲染、Source 2 截图、独立贴图和平铺检查。

本轮制作了可复用的第一版组件库和独立样板，尚未替换 `survival_world_v2` 主地图。造型、表面细节与云的细节密度比概念图简化；此版本用于实际尺度下评审资源，不应当作全图美术完成稿。

## 内容

- 26 个模型：直岸、内外转角、台阶、坡道、三种铺装过渡、直栏/转角/端柱、阵纹台、亭阁、门楼、石灯、香炉、两种松树、两种桃花、三块岩石、蕨草/草丛/灌木。
- 每个模型另有一个简化 FBX 和独立 ModelDoc 资源。简化版需手动选用，尚未设置自动距离切换。
- 10 套独立 1024² 表面贴图：石板、岩壁、青瓦、木、草、土、草土混合、铜、阵纹、水；包括彩色、法线、高度、粗糙度、反射率，部分另有遮罩。
- 几何树叶、桃花使用另外两套材质；叶片轮廓由网格实现。独立的叶片/花瓣透明 PNG 作为备用资源提供，没有将整张参考板贴到模型上。
- C01 底云、C02 厚云、C03 云带、C04 薄雾，各有 Blender 体积密度源场景、1536×896 RGBA 原始烘焙及 2048² 引擎用透明补边版本。
- 独立 Source 2 测试地图 `xianxia_kit_review`，包含局部组合和逐件展示台。

## 文件与使用

| 内容 | 路径 |
|---|---|
| 可编辑模型库 | `xianxia_library.blend` |
| Blender 局部组合 | `xianxia_assembly.blend` |
| 模型与简化模型 | `models/*.fbx` |
| ModelDoc 源文件 | `source_models/*.vmdl` |
| 材质源文件 | `source_materials/*.vmat` |
| 云粒子源文件 | `source_particles/*.vpcf` |
| 云体积源场景 | `clouds/*.blend` |
| 原始概念参考 | `references/`，仅供参考，生成器不读取这些图 |

编译后的资源已安装到本 addon 的 `models/xianxia_kit`、`materials/xianxia_kit` 和 `particles/xianxia_kit`。对应可编辑源资源位于 `content/dota_addons/survival` 下的同名子目录。

在 Dota 控制台运行：

```text
dota_launch_custom_game survival xianxia_kit_review
```

此测试地图会自动关闭战争迷雾，固定清晨时间并截图。仅地图名匹配时启用，不影响主地图玩法。

## 接口、坐标与通行

- 以 Source 单位建模。直岸名义宽度 512、深度 128，顶面局部 Z=0，侧壁底部 Z=-248。岩面允许少量交叠，铺装顶面应对齐，不能互相覆盖。
- 转角是 L 形组合，使用 `asset_manifest.json` 的范围与 Blender 模型核对放置；不要将直岸交叉重叠代替转角。
- 台阶/坡道净宽 384，高差 128，水平长度 256；上端 Y=128、Z=0，下端 Y=-128、Z=-128。
- 庭院摆件以地面 Z=0 为基准。低栏高约 88；门楼净开口约 582。
- FBX 在导出时烘焙了 -90° Z 轴转换，用来抵消本地 Source 2 FBX 导入方向差异。配套 ModelDoc 的 `import_scale=0.01`。直接回导 FBX 到 Blender 时会看到此转换，编辑优先使用 `.blend`。
- 这些摆件没有自动生成碰撞体。地图中的台阶应另外配合连续坡道碰撞和 GridNav，栏杆/树木是否阻挡应按玩法决定。主地图的既有通行数据本轮未改动。

## 材质与验证

- 彩色 PNG 使用 sRGB；法线、粗糙度、高度、反射率、遮罩使用线性数据。
- 法线为 +Y 切线空间，由独立周期高度场生成，不是由概念图颜色推算。法线单位长度与两轴重复边界有数值检查，见 `validation.json`；同时提供所有材质的 2×2 拼接预览。
- Source 2 固体使用 `global_lit_simple.vfx`。粗糙度原图独立保留；引擎的反射率图为适配此着色器的近似，不是完整金属度/粗糙度 PBR 管线。
- 水面使用原生 `water_dota.vfx` 和本轮生成的独立波纹法线、高度噪声；岸边泡沫与全图流场尚未制作。
- 云的透明边缘直接解码 PNG 检查，四像素边框的 Alpha 均为零；透明补边不拉伸原图。
- 模型、材质、云粒子/云贴图与测试地图均有独立编译日志。`geometry_validation.json` 记录网格数据检查。

## 云与当前美术限制

云在 Blender 中是真实的程序化体积密度，游戏中是烘焙的屏幕朝向云片。其光照与俯视角固定；不同角度近看、无限放大、密集叠放都会暴露平面、重复和透明叠加问题。C03/C04 是连续云带原型，细节仍比概念图概括。

当前资源适用于稀疏的边界样板验证。达到概念图那种近景云团层次，还需更细致的多视角云图集（建议至少 4 个轮廓变体、2 个俯仰角、独立密度/深度数据），或专门的运行时云着色器。不要靠复制更多本轮云片去掩盖这个差距。

最终引擎截图中，厚云仍显团块、薄云偏线条，尚不适合全图铺设；透明边缘检查通过不等于美术表现达标。测试水底已统一青蓝底色，消除了原先条纹，但水面细节仍较弱，尚未达到参考水面的层次。

树木与建筑也是可继续雕琢的首版：瓦片端头、石材破损、松针团簇与树皮微细节尚未达到概念图精度。应先选定在实际游戏镜头下有效的轮廓，再逐件细化并替换全图。

## 重建

1. 在 Blender 执行 `tools/xianxia_kit_materials.py`。
2. 在独立命名空间执行 `tools/xianxia_kit_models.py`，依次调用 `terrain()`、`architecture()`、`vegetation()`、`save_library()`；将命名空间存入 `bpy.app.driver_namespace['xxkit']`。
3. 执行 `tools/xianxia_kit_lod.py`；`xianxia_kit_render.py` 生成独立预览。
4. `xianxia_kit_clouds.py` 烘焙云；支持 `--resume`、`--ribbons`，优先本机 HIP 显卡。
5. `xianxia_kit_qa.py` 检查表面数据；`node tools/xianxia_kit_gallery.cjs` 检查原始云 Alpha 并补齐引擎尺寸。
6. `node tools/xianxia_kit_source2.cjs --clouds` 与 `node tools/xianxia_kit_demo.cjs` 生成引擎源资源。
7. 编译材质、云 `.vtex`、模型、粒子，再编译测试地图。只编译粒子不会自动替代云 `.vtex` 的显式编译。
