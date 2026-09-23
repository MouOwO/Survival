# 副本原生地形与四通道粉刷

地图：`content/dota_addons/survival/maps/template_map.vmap`。

五个副本采用官方冬季地形组件的插件内副本：`maps/tilesets/survival_challenge_native.vmap`，位于地图原本空闲的第 4 个 tileset 槽。其他三个地形槽未替换。官方安装目录的文件没有修改。

## 材质通道

| 材质 | Channel 0 | Channel 1 | Channel 2 | Channel 3 |
|---|---|---|---|---|
| `materials/challenge_native/snow_blend.vmat` | 灰色裸岩 | 官方积雪 | 冰质湿地 | 冰岸碎岩 |
| `materials/challenge_native/volcanic_blend.vmat` | 冷却玄武岩 | 玄武岩 | 灰色碎土 | 熔岩 |
| `materials/challenge_native/waterfire_blend.vmat` | 玄武岩 | 冰岸碎岩 | 冰质湿地 | 熔岩 |

全部颜色纹理、混合遮罩、反射与发光贴图来自已安装的官方资源。它们重新组合成独立材质，没有使用概念图或重新绘制数据贴图。地面启用世界坐标贴图，各通道取消滚动，避免每块地形重新起算纹理造成接缝。熔岩只占局部，战斗区保留稳定的岩地。

冬季组件原有的平面冰水材质替换为周围海域相同的官方 `water_flow.vmat`，斜面冰材质归入岸坡。流水和地面分开，不把水 shader 塞入地面混合通道。

## 在 Hammer 中继续刷

1. 外部修改地图后，关闭旧文档并从磁盘重新打开 `template_map.vmap`，避免旧文档覆盖新内容。
2. 按 **Shift+V** 进入粉刷工具，在副本地面 **Shift+右键** 拾取混合材质。
3. 选择 **Blend**，先用较低 Strength 和较大 Radius 试刷一个通道，再缩小笔刷补局部。
4. 优先限定 **Selected Objects / Selected Faces**，不要对全图 Flood Fill。
5. 雪地以 Channel 1 为主，少量 Channel 2、3 打散；熔火以 Channel 1 为主，用 Channel 2 形成灰色斑块，Channel 3 只刷少量熔岩。

官方操作说明：[Terrain Blending](https://www.dota2.com.cn/wiki/Dota_2_Workshop_Tools/Level_Design/Terrain_Blending.htm)。

## 尺寸与导航

`challenge_XX_playable_min/max` 是 1049×1049 的设计边界。引擎寻路格为 64 单位，目前只开放完全处于该边界内的格子，因此实际寻路方格为 1024×1024，不会扩展到 1088。外围原生岸坡可以更大，但均禁止移动。

`Shift+C` 用于原生地形造型；材质粉刷不会自动改变移动边界。不要随意清除外围导航阻挡。入口、归位点和刷怪点仍沿用原有 `challenge_05..09_*` 命名。

## 构建与验证

`prepare-challenge-native.cjs`、`build-challenge-native.cjs` 是本次定点迁移工具，使用 `output/challenge_native/` 的保存快照；不能当日常生成器覆盖后续手工编辑。日常编译使用 `tools/map_c6/compile-main.ps1`。

实机验证入口：`script_reload_code tests/map_c6_challenge_native_check`，覆盖五个场地内的密集采样、外围禁止移动、设计边界、入口与刷怪点、实际传送和岛间隔离。
