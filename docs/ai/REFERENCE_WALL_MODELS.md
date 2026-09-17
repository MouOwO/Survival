# 十阶参考图城墙

更新：2026-09-16。按用户提供的十张方垛参考图制作，30 个玩法等级每三级使用一个模型。四面采用相同结构，保留城墙原有方向与 4×4 格占地。

## 第二版：材质做旧与 2.5 倍高度

- 用户要求十阶城墙体现从旧到新的材质变化。木材改为沿每根木料长轴投影，横梁横纹、立柱纵纹、截面年轮；加入木结、纵裂、褪色、积灰和墙脚苔痕。
- 石材加入矿物色差、细裂纹与凹蚀，金属加入氧化、铜绿、锈迹和划痕。颜色、法线、粗糙度来自相同的表面痕迹；粗糙度不再按材质使用单一数值。
- 十阶做旧强度从 1.0 递减为 0.08；高阶保留细小使用痕迹，同时提高象牙石面和金属的抛光感。每块木材、砌石还有独立明暗变化，降低重复贴图感。
- 模型顶点仅 Z 轴乘以 2.5。横向 248 码、4×4 格、实体比例 1.0、yaw=180 不变；碰撞高度、选择盒高度和流光网格同步。原始尺寸快照在 `output/reference_walls/before_height_weathering/manifest.json`，审计比较快照和实际编译边界，防止重复放大。
- UV 图集减小无效间距，让主要表面获得更多像素；法线按独立 SurfaceUV 的切线方向烘焙到最终图集。依旧使用每款一套 2K 贴图，没有增加模型面数。

## 等级与命名

每行依次使用 `·Ⅰ`、`·Ⅱ`、`·Ⅲ`，例如 1–3 级为 `原木城墙·Ⅰ`、`原木城墙·Ⅱ`、`原木城墙·Ⅲ`。

| 大等级 | 玩法等级 | 名称前缀 | 模型 |
| --- | --- | --- | --- |
| 1 | 1–3 | 原木城墙 | wall_lv01 |
| 2 | 4–6 | 木石城墙 | wall_lv02 |
| 3 | 7–9 | 青石城墙 | wall_lv03 |
| 4 | 10–12 | 青铜城墙 | wall_lv04 |
| 5 | 13–15 | 苍蓝城墙 | wall_lv05 |
| 6 | 16–18 | 碧玉城墙 | wall_lv06 |
| 7 | 19–21 | 赤铜城墙 | wall_lv07 |
| 8 | 22–24 | 紫晶城墙 | wall_lv08 |
| 9 | 25–27 | 白金城墙 | wall_lv09 |
| 10 | 28–30 | 天辉晶冠城墙 | wall_lv10 |

运行时路径为 `models/survival_buildings/wall_lvXX.vmdl`。CSV 的名称、等级模型、预载目录和初始 NPC 模型已同步；费用、生命、护甲、升级条件等数值保持原值。

## 网格、尺寸和碰撞

- 4×4 格是 16 个 64 码格子，总宽度 256 码。模型最大横向宽度 248 码，实体比例 1.0，施工外壳也为 1.0。
- FBX 使用 0.01 导入比例，没有烘入新转向；保留既有 `model_yaw=180`，没有套用其他建筑的朝南修正。
- 每款包含 root 骨骼与权重，以及 `default`、`select_low`、`select_high` 三套选择盒。
- 编译 PHYS 为闭合箱体，水平边界 ±122 码，底部 Z=0；第二版顶部由 118 码同步提升至 295 码。原有单位 `hull_radius=256` 和城墙寻路阻挡逻辑保持；它与网格占地、模型 PHYS 是不同配置。
- 方垛包含砌石、木板、平台、垛口、角柱、金属包边与分阶徽记；高阶增加宝石和晶冠。四边结构一致，便于相邻摆放。

## 材质与施工表现

每款使用独立 2048×2048 图集，保留颜色、法线、AO、粗糙度、反射率源图。运行时 `global_lit_simple.vfx` 启用法线和高光，AO 合入颜色，粗糙度转换为反射率。木纹、端面年轮、石材裂纹与金属表面细节均参与烘焙。十款共 214,852 个三角面。

十款城墙各有独立 `_flow.fbx` 和 `_white_shell.vmdl`，与正常模型几何一致，使用高度 UV 接入现有彩色流光和从上至下揭幕。外壳不包含碰撞或选择盒，共享 49 份流光材质。外壳注册表从 24 款扩充为 34 款，原有建筑模型未重做。

## 源文件与重建

- `tools/wall_asset_spec.py`：十阶名称及 30 级映射。
- `tools/reference_wall_geometry.py`：几何与配色。
- `tools/wall_surface_materials.py`：分材质表面纹理、随等级减弱的做旧、木料投影与墙脚污痕。
- `tools/build_reference_walls.py`：Blender 生成、烘焙、FBX/ModelDoc/碰撞导出。
- `tools/sync_reference_wall_config.py`：定向同步 CSV、生成 Lua、NPC 初始模型；首轮配置快照保存在输出目录。
- `tools/install_reference_walls.ps1`：同步到 content 并编译城墙材质、普通模型和外壳。

重建顺序（在项目根目录执行，使用本机 Blender/Python 路径）：

```text
blender --background --python tools/build_reference_walls.py
python tools/build_building_white_shells.py
python tools/sync_reference_wall_config.py
powershell -File tools/install_reference_walls.ps1
python tools/verify_reference_walls.py
blender --background --python tools/verify_reference_wall_fbx.py
blender --background --python tools/verify_wall_surface_textures.py
```

单款重建可给 Blender 脚本传 `-- wall_lv01`，安装脚本可传 `-ModelNames wall_lv01`。流光材质共享现有建筑资源；全新环境还需按 [建筑说明](UNIQUE_BUILDING_MODELS.md) 生成并安装共享流光材质。

完整 `.blend`、贴图、源模型和预览在 `output/reference_walls/`。十款预览入口为该目录的 `index.html`。

## 第二版验证结果

- 十款编译网格的高度逐一与初版快照比较，均为 2.5 倍；PHYS 与三套选择盒高度通过审计，4×4 占地及 30 级配置保持。
- 二十份普通/流光 FBX 回导通过，包含 root 权重、单 UV、几何重合和随新高度变化的揭幕坐标。
- `surface_verification.json` 检查十款实际编译后的颜色、法线、反射贴图，共 30 张。先排除图集填充区，再验证像素变化；法线图不是中性纯色，反射不是单一常数。该检查确认资源生效，美术观感另由预览和实机观察判断。
- 本轮运行四项 Lua 回归：城墙等级配置、网格对齐、施工表现、流光外壳，全部通过。没有修改玩法逻辑或数值。
- `runtime_verification.json` 为第二版实机记录。第一至三阶截图 `runtime_v2_first3.png` 在准备阶段；第四至六阶 `runtime_v2_middle_verified.png`、第七至九阶 `runtime_v2_high_verified.png`、第十阶 `runtime_v2_final_verified.png` 带有结束界面提示，仅用于材质和模型显示检查，局部顶部有界面遮挡。完整模型外观可看 Blender 预览。
- 实机一级模型碰撞顶部读数为 295 码，确认新资产已加载。未逐级手动点击全部 30 级，也未实测每款完整施工计时；对应逻辑由资源与回归检查覆盖。清理确认 `WALL_V2_CLEANUP 0`。

## 初版验证记录（历史）

城墙死亡表现已新增 1 秒抖动与水晶爆炸，接入、重建和验证说明见 [WALL_DESTRUCTION_EFFECT.md](WALL_DESTRUCTION_EFFECT.md)。模型高度变化后需同步重建该效果的高度注册表。

- `verification.json`：十款实际编译资源、贴图依赖、PHYS、选择盒、49 阶外壳材质及 30 级 CSV 映射通过；配置快照核对确认经济数值未变。这是离线报告，实机结论另存。
- `fbx_verification.json`：十款正常与流光 FBX 回导通过，核对 root 权重、单 UV、网格边界和高度遮罩方向。
- 原有 24 款建筑资源审计通过。表现检查的 13 项 Lua 回归和独立城墙配置回归通过，合计 14 项。
- `before_height_weathering/runtime_verification.json`：在 Workshop 的 `template_map` 分两批显示十款模型，确认贴图可加载、阶段外观可区分且轮廓位于 4×4 网格内；截图为 `runtime_01_05_fixed.png` 和 `runtime_06_10_visible.png`。后者还能看到实际选中建筑显示 `原木城墙·Ⅱ`。前一张带有测试局结束提示，不作为建造流程计时证据。
- 本轮实机范围是十款模型渲染和尺寸检查，并非逐一手动点击或升级全部 30 级，也未逐款实测完整流光计时。选择盒、升级映射和特效生命周期由资源审计及回归覆盖。
- 临时展示道具已删除，相机已释放，控制台确认 `WALL_REVIEW_CLEANUP 0`。`tests/manual_reference_walls.lua` 是显式 Tools 测试入口，生产逻辑不加载它。
- 另一次运行旧 `test_wall_hull_radius.lua` 在本轮迁移前即因测试环境缺少 `Vector` 模拟失败；其主城半径断言也落后于现行配置。本轮没有更改该测试及原有碰撞逻辑，不将其计入通过项。
