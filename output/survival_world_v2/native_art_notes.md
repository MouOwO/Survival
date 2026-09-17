# 官方环境资源选型 · 2026-09-13

依据：本机 Dota 原生 `game/dota/pak01_dir.vpk` 的实际目录、反编译材质及贴图。用户参考图的具体地形皮肤无法仅凭截图确认。

|需求|已核实的官方资源|本轮使用方式|
|---|---|---|
|鲜蓝河水|`materials/water/water_econ_dota_blue.vmat`|沿用官方流动法线、折射和颜色，在本项目中启用蓝色水雾；替换原生模板的水面材质，保留水位|
|细密鲜绿草地|`maps/ti10_assets/blends/mod_radiant_ti10_000.vmat`|原岛直接使用；其他区域使用其中 grass_ti10_01 颜色与同名 reveal 遮罩，配合原生法线|
|神殿石板|同一 TI10 材质的 `radiant_stone_ti10_01`|草地与石板使用同一连续网格上的权重混合|
|火山区|`materials/blends/mod_dire_lava_000.vmat`；原生 basalt_00、lava_01、lava_02|借鉴玄武岩夹发亮裂缝的组合，调整本项目已有混合材质的裂缝配色|
|牢笼地面|`models/props_structures/grate001.vmdl`、`cage001.vmdl`|冷色旧石板配铁栅和牢笼实物；格栅贴图是模型 UV 图集，不能当成无缝地砖直接平铺|
|彩色树木|`models/props_tree/newbloom_tree.vmdl`、`maps/journey_assets/props/trees/journey_maple/journey_maple02.vmdl`、`maps/ti10_assets/trees/ti10_goldenbirch001.vmdl`|花树、秋枫与金桦分区点缀|
|晶体环境|`maps/cavern_assets/models/crystals/crystal03.vmdl`|雪地房间边缘的小规模晶簇|

还找到水下珊瑚地表、暗礁牢笼和多种洞穴混合地面，清单见 `../reference_asset_study/native_art_inventory.json` 与 `native_art_extended.txt`。这些备选资源没有全部加入地图。

自然过渡来自匹配纹理的 reveal 遮罩、连续网格上的渐变权重、共享边缘材质和少量植物碎石。更换成另一套颜色贴图本身不会自动消除边界。植物点缀在边缘成组出现，保留出生点和战斗中央的视野。

官方参考：[2016 不朽庭院](https://www.dota2.com/international2016/battlepass/)、[2017 暗礁地形与河水染色](https://www.dota2.com/international2017/battlepass/)、[Valve 工坊地形混合绘制更新](https://store.steampowered.com/news/14680/)。实际使用资源以本机核查为准。

本轮开始前的地图、材质、生成器及截图保存在 `before_native_art/`。几何布局、水位和寻路规则沿用上一版；实机结果见 `verification.json` 和截图。该地图仍是环境审阅测试图，战斗与传送逻辑尚未全部迁移。
