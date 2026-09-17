# 本地参考地图研究

参考包：`D:/steam/steamapps/workshop/content/570/2103079229/2103079229.vpk`

发布信息：Treasure and Truth V1.5 Heroic Mode & Soul Stand System，源目录 tatdemo1。

只提取、检查地图及资源依赖，没有运行参考包的 Lua。主地图、场景 prefab 位于 extracted/maps；用 Source2Viewer CLI 20.0 解出主地图，再用 Valve dmxconvert 转成可读格式。

`asset_usage.json` 是场景中的模型与实体引用统计；`native_resource_audit.json` 对照本地 Dota pak01_dir.vpk 检查资源是否存在。场景中共有 2636 个不同模型引用，其中 362 个可直接从 Dota 本体取得；其余大量引用是编译生成的场景网格，并不等于独立制作的建筑资源。

高频原生环境资源包括河岸岩石、营火碎石、春季灌木、蕨类、花草、橡树、雪松，以及 TI10 崖壁、石柱和藤蔓。新版直接引用这些原生资源和原生 tileset 地面网格，没有复制参考地图的任务、技能、怪物配置和完整地图布局。

`lighting.json` 保存参考图的 env_global_light / ent_dota_lightinfo 参数，供核对日光、环境光和雾设置。新版替换了其地图专用流场路径，采用独立的自然日光参数。

生成工具：tools/build_survival_world_v2.cjs；地图源文件：output/survival_world_v2/survival_world_v2.vmap。
