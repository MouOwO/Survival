# 木材、属性与大属性练功房

三个独立房间沿用用户认可的金币练功房材质处理与照明条件，补齐各自的模型主题和普通受光材质。金币房作为基准；熔火核心另有独立的材质打磨与对比页。

## 验看入口

- 总览：[练功房材质与主题](../../output/training_rooms/index.html)。
- [木材练功房](../../output/wood_training_room/index.html)：顺纹木梁、错缝木板、原木端面、锯架和木材纹章。
- [属性练功房](../../output/attribute_training_room/index.html)：浅冷石材、翠玉矿物、三瓣成长纹、银铜嵌件。
- [大属性练功房](../../output/greater_attribute_training_room/index.html)：深色矿石、蓝紫晶体、三晶冠与分层银金饰边。
- [熔火核心材质对比](../../output/molten_core_room/material_review/index.html)。
- [金币练功房材质基准](../../output/gold_training_room/material_review/index.html)。

图集中的全景、俯视、材料近景和入口近景均为 Blender 渲染；三个新房间沿用金币房的照明条件。图片可点击打开原图。实际 Source 2 着色与 Blender 不完全相同，不能把这些图片作为游戏实机截图。

项目根目录的「打开地图测试.cmd」提供 `wood`、`attribute`、`greater` 房间入口。

## 场景与地图

| 房间 | 独立测试地图 | Blender 文件（output 下） | Hammer 预制件（content 下） | 标记前缀 |
| --- | --- | --- | --- | --- |
| 木材 | `wood_training_room_review` | `wood_training_room/wood_training_room.blend` | `maps/prefabs/wood_training_room.vmap` | `challenge_01` |
| 属性 | `attribute_training_room_review` | `attribute_training_room/attribute_training_room.blend` | `maps/prefabs/attribute_training_room.vmap` | `challenge_03` |
| 大属性 | `greater_attribute_training_room_review` | `greater_attribute_training_room/greater_attribute_training_room.blend` | `maps/prefabs/greater_attribute_training_room.vmap` | `challenge_04` |

Workshop 控制台分别运行：

```text
dota_launch_custom_game survival wood_training_room_review
dota_launch_custom_game survival attribute_training_room_review
dota_launch_custom_game survival greater_attribute_training_room_review
```

每个房间独立保存 31 个自制模块、603 个场景实例，内场 2048 × 2304；Blender 铺地 Z=0，Hammer 铺地 Z=128。碰撞、连续行走支撑、入口与八个刷怪点沿用金币房的空间约定；每个房间包含自己的 `entry`、`home`、`spawn_01` 至 `spawn_08` 共十个标记。原生松树复用 `models/props_foliage/tree_pine01.vmdl`。

模型、材质和贴图分别位于各自的 `models/<namespace>/` 与 `materials/<namespace>/`。源文件镜像在 `output/<namespace>/source/`；地图位于 `source/maps/`。各目录的 `asset_manifest.json`、`material_manifest.json`、`room_layout.json` 和 `map_manifest.json` 是具体清单。

这些是独立可编辑样板，没有替换正式 `template_map`、奖励、刷怪、传送或其他玩法。合入正式地图时应整体移入预制件及配套支撑、标记，并避免同名标记重复。

## 主题与材质

- 木材房更换 16 个模块的几何，木板顺纹与端面年轮使用不同材质和 UV 方向；原木、树皮、锯架、铁件及木材徽记为真实网格。木纹凹槽、节疤和裂缝偏哑光，磨亮木面保留柔和反光，铁箍单独表现磨损。
- 属性房的墙柱、地纹、标识碑、浮雕和旗帜改为翠玉三瓣成长纹；额外大小翠玉矿簇只放在外围。
- 大属性房用三晶冠、六边形地纹、切面蓝紫晶簇与分层银金饰边区分等级。中央地面收窄明暗范围，浅色石缘主要位于外围，保持战斗区域清晰。
- 所有表面均为普通受光材质，无自发光、粒子或局部效果灯。

材质修订为 `themed_training_surfaces_v1`，生成器为 `tools/training_room_materials.py`。沿用已确认的 `global_lit_simple.vfx`：启用法线与高光，显式写入浮点型 `g_flSpecularIntensity`、`g_flBumpStrength`，并将 `g_flSpecularBloom` 置零。

游戏读取独立的线性 R 通道 Reflectance 强度遮罩；粗糙度和金属度 PNG 供 Blender 预览使用，不作为该游戏 shader 不支持的 PBR 输入。法线遵循 DirectX 约定，Blender 节点中仅翻转一次 G 通道。表面颜色、凹凸和反射变化根据同一组木纹、磨损、孔隙或氧化分布生成。

共享金币几何、金币材质、主岛及正式建筑不在此生成器中被覆盖。属性几何只扩展实例自身的材质键，不修改金币共享 PALETTE。

## 验证范围

各房间实际编译结果以最新 `verification.json` 为准，不从源文件存在推断编译成功：

- [木材房验证](../../output/wood_training_room/verification.json)
- [属性房验证](../../output/attribute_training_room/verification.json)
- [大属性房验证](../../output/greater_attribute_training_room/verification.json)

验证器检查实际 `.vmdl_c` 边界、材质依赖与碰撞块，实际 `.vmat_c` 的法线/高光参数与纹理依赖，安装源文件一致性，地面 `dota.nav.walkable` 属性、场景实例与标记，以及地图 VPK 载荷 CRC。行走支撑位于铺地顶面下方 0.75 单位，板缝中露出灰浆。

`status: PASS` 表示以上资源与静态布局检查通过。`runtime_verified: false` 明确表示没有把游戏中的外观、导航与完整战斗联调作为通过项；此图集不宣称已完成实机验收。应在对应独立地图中另行验看材料、入口行走和刷怪空间。

## 重建与安装

在 game 项目根目录执行。Blender 和 Python 路径按本机安装调整；以下使用项目当前 Blender 安装路径。

```powershell
# 1. 分别生成三个独立场景、贴图、模型和四张预览图。
& 'D:/magic and love/软件/Blender/blender.exe' --background --python tools/build_themed_training_rooms.py -- wood
& 'D:/magic and love/软件/Blender/blender.exe' --background --python tools/build_themed_training_rooms.py -- attribute
& 'D:/magic and love/软件/Blender/blender.exe' --background --python tools/build_themed_training_rooms.py -- greater_attribute

# 2. 生成三张独立测试地图与对应预制件。
node tools/build_themed_training_room_maps.cjs

# 3. 退出正在占用对应 VPK 的测试局，再同步 source 至 content 并编译。
powershell -NoProfile -ExecutionPolicy Bypass -File tools/install_themed_training_rooms.ps1 -Theme all

# 4. 审计实际编译资源和地图载荷。
& 'D:/magic and love/软件/Blender/5.2/python/bin/python.exe' -B -X utf8 tools/verify_themed_training_rooms.py

# 5. 用最新的预览、清单和验证结果生成离线图库。
node tools/build_themed_training_gallery.cjs
```

安装器支持 `-Theme wood`、`-Theme attribute`、`-Theme greater_attribute`；`-SkipMap` 只省略地图编译，仍同步源文件并编译模型及材质。验证器支持 `--theme wood` / `attribute` / `greater_attribute` 单房检查。

不要在 VPK 被游戏占用时判断地图编译成功。安装脚本会检查实际 VPK 更新时间和写入结果。Blender 生成器需要已保存的 `output/gold_training_room/gold_training_room.blend` 作为照明、相机与原生松树预览来源，不会覆盖它。
