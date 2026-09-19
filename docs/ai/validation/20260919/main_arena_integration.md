# 主地图场景整合验收

## 交付

运行地图为 `maps/template_map.vpk`，Hammer 源图为 content 仓库的 `maps/template_map.vmap`。双击 game 根目录 `launch_template_map.cmd` 打开；原 `launch_survival_main.cmd` 同样可用。

- 六间练功房：木材、金币、属性、大属性，以及两间熔火挑战房；主体 900×900。
- 一至十转：十个独立模型，主体 1000×550，保留逐阶抬高的台面。
- 一至十戒：十个独立模型，主体 700×700，岸边装饰及水线一起导入。
- 中央五个网格和 4574 个非目标实体逐字保留；替换 52 个旧目标标记，新增 126 个标记、3328 个模型实例。
- 按实际变换后的完整模型范围检查，包含外围岩石和植被；26 区无重叠，最小间距 **915.484 游戏单位**。弧形后墙的相邻接缝已修正。

## 验证

1. 最终源图 SHA256：`4adaa5f6c817ab758b957b18438ba8c6ad53ff8586cda05d8fd14726039540cd`。
2. Workshop 编译：231 项成功，0 项失败；VPK 50,035,621 字节。
3. 独立编译核验：235 个资源 CRC、168 个自定义模型引用、126 个实际编译标记通过；编译源 CRC 与本次 DMX 源图一致，均为 `1262649909`。清除预览产生的无关缓存后再次核验通过。
4. 正式实机入口 `script_reload_code tests/manual_integrated_arenas_check`：26 区、207 项全部通过；2,436 个地面/导航采样、256 条内部路径、104 个水域阻挡采样、325 对区域隔离均通过。详见 [arena_runtime.json](arena_runtime.json)。
5. 主地图快捷启动完整流程实测返回 0，并收到本次唯一 Lua 就绪回显；使用直接 TCP 控制台，无需另装 MCP。
6. 已查看主岛、金币/木材/熔火房、一转/十转、二戒/十戒实机截图。截图保存在本机 `output/map_build_c6/integrated_*.png`。

本轮验证地图位置、模型加载、地面和寻路；未验证完整挑战通关、奖励结算、多人压力测试或实际英雄逐点行走。沿用主地图既有光照，高阶白云台面仍有较亮高光，未在本轮改动其材质或全局光照。

## 版本同步及服务器

game 从 `1dee4607` 快进至 `696e5cc3`，content 从 `768c3d4` 快进至 `926379c`，保留本地资源后解决冲突。资源与后端适配提交分别为 game `47b1e5ea`、content `6081277`，均已推送；此文档和最终主地图属于后续整合提交。

ECS 只读复核通过：current 仍为 `20260919-test03`，API 和数据库服务 active，health、数据库 readiness、归档配置 hash 均正常。没有切换游戏至 ECS，没有迁移数据库或改动 Supabase。新版抽奖协议与旧 test03 的兼容限制见 [服务器影响检查](../../../ALIYUN_UPSTREAM_COMPATIBILITY.md)。

本机四个受权限保护的数据库试验导出目录已完整移至 `D:/survival_database/local_test_exports/20260919-preserved/`，避免 Workshop 扫描失败；备份内容和服务器数据未删除。校验工具提取的临时资源改放系统临时目录并自动清理。

## 回退与继续编辑

只回退本轮地图时，将 content 的 `maps/template_map.vmap` 恢复到 `6081277` 对应文件，将 game 的 `maps/template_map.vpk` 恢复到 `47b1e5ea` 对应文件，再以新提交保存。不要重置其他已经同步的后端或玩法代码。

正常在 Hammer 编辑当前源图后运行 `tools/map_c6/compile-main.ps1`。整套重新导入需要显式使用历史基线；步骤见 [地图工具说明](../../../../tools/map_c6/README.md)。
