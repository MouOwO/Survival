> 历史记录：本文件描述上一轮圆岛版本。本轮已改为四向凹形岛和十字水道，详见 cross_island_notes.md；最新验收见 verification.json。

# 材质与浅水区修订

本轮沿用 `survival_world_v2` 的功能区布局。修订前的地图、源文件、布局及截图保存在 `before_transitions`。

- 主岛独立使用等比例世界坐标，半径 4608；中央湖面为 2048 × 2048 的正方形。八个营地环绕主岛，取消中央营地与湖岸间的多余台阶。
- 湖区保留与岸边一致的导航高度；底面与岸边连续，水面高出连续底面 20 单位，提供可穿行的浅水效果。深水外海和山地继续禁止通行。
- 原先独立覆盖的硬边铺装换成连续三角网格，按距离写入约 280 单位宽的材质混合带。使用 Dota 原生的土、草、碎石、石板、积雪、玄武岩和熔岩贴图。
- 森林采用草土、碎石与石板的组合；雪地采用积雪、融雪碎石和草地边缘；火山采用玄武岩、灰烬色碎石与局部熔岩；腐化区域采用暗土、苔草与暗色岩石。
- 从本地原生地形模板确认荷叶来自 `lily_pads` 等模型。四个项目专用模板副本共禁用 28 个荷叶实体，保留其他岸边效果。
- 练功房保留顶部较低、下方较高的配置。十诫区域保留石柱，其余练功房取消统一石柱装饰。

研究依据：`output/reference_asset_study/tatdemo1_text.vmap` 中的地面材质及场景资源；`radiant_basic_text.vmap` 中的 `VertexPaintBlendParams`、`VertexPaintBlendParams1`、`VertexPaintTintColor`；原生 `mod_radiant_path_000.vmat` 的土、草、石材四层设置。混合权重 XYZ 对应第 1、2、3 层，第 0 层为剩余量；已对照 Source 2 Viewer 官方 `Renderer/Shaders/multiblend.frag.slang` 核对。反编译参考图中的部分顶点数据已经烘焙，因此具体数据编码以可编辑的原生模板为准。

生成顺序：

1. `node tools/prepare_world_v2_transitions.cjs`
2. `node tools/build_survival_world_v2.cjs`
3. `node tools/verify_world_v2_transitions.cjs`
4. 将 `source_materials`、`source_tilesets` 和地图源文件复制到 addon 对应的 content 目录。
5. **先单独编译六份新材质，再编译地图**。地图编译不会自动生成外部材质文件。
6. 加载游戏后执行自动截图和通行验证，再导出图库。仅代码/材质修改与地图几何修改的编译范围不同。

几何检查见 `geometry_verification.json`；实际游戏验证与截图时间以 `verification.json` 和 `screenshot_manifest.json` 为准。

最终实机验收：136 个导航采样全部通过，其中 50 个覆盖湖面与岸边的横纵穿行；连续底面高度均为 396。两条跨湖寻路均通过。顶部 / 下方对应练功房实际地面高度分别为 268 / 652。9 张截图均晚于地图及最新材质编译时间。
