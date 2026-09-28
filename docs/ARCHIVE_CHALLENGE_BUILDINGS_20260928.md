# 存档挑战建筑模型与HUD（2026-09-28）

三个独立的Source 2三维模型：1为紫晶拱门祭坛，2为蓝晶三柱试炼台，3为青瓦铜金殿堂祭坛。沿用现有村落石材、青瓦和铜金风格；模型平面最大宽度210，运行缩放1，避免原先三个缩小远古遗迹重复。

模型源：`tools/concept_building_geometry.py` 的 `archive_challenge`，构建入口 `tools/build_concept_buildings.py`。构建和预览：`output/archive_challenge_models_20260928`；源模型、材质已安装到Dota content，编译资产位于game addon的models/materials目录。构建器新增条目追加在原模型之后，保持旧模型的随机种子不变。

配置源：`archive_challenge_rules.csv`新增三个模型字段，同时更新生成Lua、NPC KV及KV生成工具。挑战服务按编号加载模型并预缓存全部三套。

UI：精确识别`npc_archive_challenge_1/2/3`为普通功能建筑，采用现有自适应技能栏；隐藏头像、小窗口缩略图、等级圈、攻击/护甲/攻速、英雄属性、血蓝条、物品栏；保留标题和全部挑战技能。不可升级建筑不显示LV。通过既有无血条修饰器隐藏世界血条。框选遵循现有建筑规则，单击仍能选中。

保留挑战解锁、奖励、技能顺序、所有权和地图位置。没有将挑战BOSS误分类为建筑。

验证：三个模型与三个配套壳模型编译成功；HUD编译13项、0失败；模型路径及编译资产存在、尺寸和面数检查通过；真实模型渲染预览已检查。挑战建筑创建/位置/所有权/模型分配测试、属性显示、建筑HUD及19个框选场景通过。未在运行中的对局验证，重新开局加载新配置与预缓存。

预览：`output/archive_challenge_models_20260928/previews/three_hubs.png`，由真实模型离线渲染，非游戏截图。
