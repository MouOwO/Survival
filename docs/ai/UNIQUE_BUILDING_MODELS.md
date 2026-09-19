# 参考图建筑模型（第四版）

城墙新增十款模型另见 [REFERENCE_WALL_MODELS.md](REFERENCE_WALL_MODELS.md)。本文件描述原有 24 款建筑；共享流光注册表目前共 34 款。

更新：2026-09-16。用户已确认第三版可以点选，本次保留 root 骨骼与三套选择盒，按新参考图重做外观、放大并增加分级模型。

## 本次交付

| 建筑 | 外观数 | 资源名称 | 进阶结构 |
| --- | ---: | --- | --- |
| 主城 | 5 | main_city_lv01–05 | 木石议事厅、双翼执政厅、古树议厅、古树王庭、翠晶圣城 |
| 人口农场 | 5 | population_farm_lv01–05 | 粮仓、农舍、双院庄屋、风车庄园、温室大庄园 |
| 金矿 | 10 | gold_mine_lv01–10 | 露脉、支护、双洞、阶岩、卷扬、索道、环轨、深井、巨脉、金脉圣山 |
| 科技研究所 | 1 | research_lab | 炼金工坊、青瓦坡顶、蒸馏罐、炉窑、药剂工作台 |
| 高级研究所 | 1 | advanced_research_lab | 石砌高塔、开顶星仪、望远镜、观测室 |
| 英雄祭坛 | 1 | hero_altar | 圣剑、石翼、双柱、青色旗帜 |
| 挑战建筑 | 1 | challenge_arena | 石砌竞技围墙、双门塔、交叉双剑 |

全部模型路径在 `models/survival_buildings/`。金矿依用户明确选择，每三个玩法等级使用一种外观：1–3 级使用一级外观，28–30 级使用十级外观。覆盖合计 44 个玩法等级。

## 尺寸、选择与碰撞

- 用户最新要求将四格版本的模型直接放大两倍。24 款 ModelDoc 的网格导入比例从 0.01 改为 0.02，编译后最大横向尺寸从约 118 增至 236 码。实体 `model_scale` 保持 1.0，四格占地保持；FBX、贴图和 UV 无需重烘焙。
- 保留根骨骼 `root`，全顶点单骨骼权重；`default`、`select_low`、`select_high` 三组选择盒的各轴边界同步乘二，共 72 组。
- 24 款均包含独立、闭合的八边形凸碰撞体；ModelDoc 的物理导入比例同步从 1 改为 2。主城编译模型 PHYS 半径为 96，单位寻路阻挡半径仍为 48，以保留四格的逻辑摆放。其余建筑沿用原有单位移动阻挡策略。
- ModelDoc OBJ 导入按 Y 向上处理，作者端输出 `(x,z,-y)`，确保最终 PHYS 块为 Z 向上并贴地。验证脚本直接检查编译后二进制的碰撞边界。
- 不做展示底板；仅保留台阶、墙脚、矿轨、菜畦和采矿工作平台。低于地面的岩石顶点压到地面，避免抬高整个建筑。
- 七类参考图建筑逻辑占地为 2×2 格（128 码），放大后的建筑轮廓可超出占格边缘；城墙仍 4×4，箭塔仍 2×2。偶数占地居中于格线交点；预览、提交、搬迁、状态恢复和释放共用坐标规则，全部四格参与树木和地形检查。费用、生命、护甲、人口、收益、升级条件不变。
- 24 款 FBX 已将 -90° 旋转烘入网格，导入 Source 2 后原生朝世界南方（-Y）。44 个等级和预览统一 `model_yaw=0`；创建时立即应用比例和角度，不再依赖异步外观加载修正朝向。`bake_reference_building_facing.py` 通过清单标记避免重复旋转，旧 FBX 保存在 `before_south_bake/`；全量生成器直接生成新方向。

## 材质与源文件

亮色石材、青绿色瓦与旗帜、暖窗、木梁和铜饰形成统一配色；实际几何包含瓦片、砌石、窗棂、门框、结构支撑和专属设备。

每模型一份 2048×2048 独立 UV 图集，烘焙颜色、切线法线、AO、粗糙度与反射率。运行时 `global_lit_simple` 使用颜色、法线和反射率；AO 合入颜色，粗糙度用于生成反射率。法线按 Source 2 的 -Y 约定导出。原始 2K 图、VMAT、FBX、VMDL、碰撞 OBJ、预览与完整 Blender 文件保留在 `output/unique_buildings/`。

## 运行时接入

- CSV 为权威，定向生成五份 Lua：`building_definitions`、`building_visual_levels`、`building_levels`、`building_construction_rules`、`asset_catalog`；占格数、角度和白光阶段特效均保存在 CSV。
- 修复农场、金矿强制回退一级固定模型的旧逻辑；现在按照当前等级查对应外观。
- 初始 NPC 模型、升级模型、施工倍率与预载目录保持一致。
- 24 个模型进入初始常驻预载。旧固定农场、金矿资源保留在磁盘，旧预载条目停用。
- 正常建筑仍使用原有单位模型。施工和升级期间临时创建一个无碰撞、无选择盒的流光外壳实体，完成后从屋顶向下揭幕并销毁。模型为静态建筑，风车与卷扬机构尚无运作动画。

## 重建

1. Blender 后台运行 `tools/build_reference_buildings.py`。参数 `-- 模型名...` 可重建指定模型并保留其余模型和 Blender 场景。
2. Python 运行 `tools/build_building_flow_materials.py`；Blender 后台运行 `tools/build_building_flow_meshes.py`，从正常 FBX 复制带高度 UV 的 `_flow.fbx`；Python 运行 `tools/build_building_white_shells.py` 生成外壳 ModelDoc 与 Lua 映射。PowerShell 运行 `tools/install_building_flow.ps1` 安装材质及外壳，再用 `tools/install_unique_buildings.ps1` 安装正常模型。只改流光材质使用流光安装器 `-MaterialsOnly`，只编译外壳使用 `-ModelsOnly`；`-ModelNames` 可限制模型范围。正常 FBX 重建后必须同步重建对应流光 FBX。
3. Python 运行 `tools/sync_reference_building_config.py`，同步 CSV、五份生成配置与 NPC 初始值。
4. Python 运行 `tools/verify_reference_buildings.py`，检查最终 PHYS、选择盒、材质纹理依赖、44 级映射及非视觉数据，生成预览页与报告。
5. Blender 后台运行 `tools/verify_unique_building_fbx.py`，回导检查每模型唯一 UV、材质、root 权重。
6. Lua 运行 `test_unique_building_models.lua`、`test_farm_fixed_visual.lua`、现有建筑外观、施工、金矿升级和塔/英雄外观回归。

预览入口：`output/unique_buildings/index.html`。报告：`verification.json`、`fbx_verification.json`，各资源编译日志和二进制转储也在同目录。

## 验收边界

第四版最终离线检查通过：24 个编译模型、24 份材质与 72 个运行时纹理依赖、24 个 PHYS 碰撞体、24 份 FBX 回导、44 个玩法等级映射；七项针对本次改动的运行时回归全部通过。24 款合计 773,546 三角面，单款 8,948–60,861；尚未进行游戏内帧耗测量。

上一轮额外检查中，`test_building_state_recovery.lua` 的旧塔数量断言未通过；该测试按队伍 2 查询，而生产计数以玩家 0 为键。本轮未调整此计数逻辑。施工测试已修正 CRLF 字符串比较，并改为验证当前传送表现的生命周期，现已通过。

本轮已在 Workshop 的 template_map 验证一级主城白光可见、淡出后正常显现，以及 yaw=0 时正门朝南。其余级别的外观、相邻建筑间距和性能尚未逐一实机验收。Blender 预览与实机截图分别保存在 `output/unique_buildings/previews/` 和 `output/building_presentation/`。

## 建造与升级流光揭幕（2026-09-16）

- CSV 中 `white_build_channel` / `white_build_reveal` 标识保留。24 款参考模型由 `building_white_shell.lua` 创建一个独立流光外壳；完成时露出最终模型，并用 1.5 秒从屋顶向地面逐渐消除外壳。全局 alpha 始终为 255，方向来自高度遮罩，不再使用整栋淡出。非参考模型继续走原有粒子兼容路径。
- 每款 `_white_shell.vmdl` 引用独立的 `_flow.fbx`，复制正常建筑几何与 root 权重，仅重设 UV：Source 2 中 V 从地面的 0.05 线性增至屋顶的 0.40。原建筑 FBX、UV、贴图、朝南方向、模型端两倍、四格占地与碰撞保持不变。外壳网格和正常建筑边界相同，运行时扩张 0.6% 避免重合；无 PHYS、无选择盒，实体 solid=0、不投影。
- 原生 `hero.vfx` 材质包含连续白、青蓝、淡金和淡紫光带、细微法线、高光、边缘光及部分自发光，保留几何明暗。原生 `time()` 表达式持续滚动颜色 UV；透明 UV 独立，施工期间不移动透明度，避免闪烁。
- 49 个共享材质 `build_flow_00` 至 `build_flow_48` 仅揭幕偏移不同；每栋一个外壳实体。完成阶段每 0.03 秒按实际经过时间推进材质组，在 1.5 秒后清理。各阶段共享三张 512 像素输入贴图；编译器将高度透明遮罩装入颜色纹理 alpha。遮罩软边跨建筑高度约 14%，屋顶先出现、墙面与地基随后出现。
- **原生材质约束：**`F_DO_NOT_CAST_SHADOWS` 与 `F_TRANSLUCENT` 互斥，同时设置会悄悄丢掉透明纹理并编译成 DXT1。材质中仅设置透明开关，禁用阴影由实体 `disableshadows=1` 完成。实际编译颜色纹理为 DXT5，已解码验证低位 alpha=255、软边 alpha=88、高位 alpha=0。
- 外壳直接复制世界 XYZ、比例和配置角度，不设置父实体，避免 `AddNoDraw` 隐藏外壳。升级完成回调后查最终模型映射；取消、死亡、重置清理外壳及跟踪任务。创建失败输出错误并恢复真实模型。预载阶段加载全部 24 个外壳。
- 生成及安装见上方重建步骤。`build_building_warp_particles.py` / `install_building_presentation.ps1 -ParticlesOnly` 仅维护非参考模型的旧纯白粒子兼容路径；原生流光资源由 `install_building_flow.ps1` 维护。
- 13 项 Lua 回归、24 款编译外壳检查及 49 个编译材质检查通过。`verify_building_white_shells.py` 核验网格边界、材质组、无碰撞和选择盒；`test_building_flow_material.ps1` 核验编译材质、动态 UV 字节码、实际纹理像素和揭幕顺序。报告在 `output/building_presentation/`。
- 实机截图 `flow_unpaused_a.png` 展示并排主城全流光/半揭幕/正常模型；中间屋顶已露出，墙脚仍被流光覆盖。后续画面确认光带随时间移动，`flow_unpaused_b.png` 同时包含测试局结束界面。实机范围为主城三阶段材质；自动计时、升级切模、取消及死亡由回归覆盖，未声称全部 24 款逐一实机验收。清理确认测试外壳和对照实体均为零，相机已释放。Tools 专用 `tests/manual_building_presentation.flow_fixture()` 可重现三阶段，`clear_fixture()` 清理；该模块不被正式游戏加载。
