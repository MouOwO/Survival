# 僵尸岛深渊地图 V1

2026-09-12：第一版可运行地形原型，地图名 `zombie_abyss_v1`，addon 为 `survival`。

按用户确认的小地图布局搭建：5 片禁行水域、中央小岛、东北高台、左侧独立区域、西南十字岛、26 个小型练功平台。黑色间隙为禁行深渊。总体宽 21760、高 12288 Source 单位。

这是地形原型：基础地面、崖壁、树石点缀、暗色照明已经落地，岸线及材质混合仍需美术细化。尚未接入现有刷怪、挑战房、Boss 和跨区域传送流程；直接开始波次不能视为完整玩法测试。原有地图及业务代码未因本地图搭建而修改。

## 文件

- `ingame_overview.png`：当前版本实机全景截图。
- `zombie_abyss_v1.vmap`：可在 Hammer 打开的地图源文件副本。
- `layout.json`：区域多边形、坐标、高度和练功房布局。
- `verification.txt`：最新游戏内地形检查输出，43 个抽样点全部通过；不等同于每个导航网格都经过遍历检查。
- `../../maps/zombie_abyss_v1.vpk`：已编译地图包。
- `../../tools/build_zombie_abyss_map.cjs`：确定性地形生成器，读取本目录 `source_template.vmap` 的 Hammer 元数据与原生网格结构。
- `../../scripts/vscripts/maps/zombie_abyss_v1_verify.lua`：手动调用的地形验证脚本，不自动接入业务逻辑。

Workshop Tools 使用的源文件位于 `D:/steam/steamapps/common/dota 2 beta/content/dota_addons/survival/maps/zombie_abyss_v1.vmap`。

## 重新生成和测试

1. 在 addon 根目录执行 `node tools/build_zombie_abyss_map.cjs`。
2. 将生成的 VMAP 复制到上面的 content/maps 路径。
3. 先通过 MCP `dota_disconnect` 退出正在运行的地图，释放旧地图包。
4. MCP `dota_compile_asset` 参数：addon=`survival`、target=`maps/zombie_abyss_v1.vmap`、force=`true`。确认 maps/zombie_abyss_v1.vpk 的修改时间确实更新。
5. MCP `dota_launch_game` 参数：addon=`survival`、map=`zombie_abyss_v1`。现有项目预载较多，启动轮询超时不一定表示失败。
6. 进入游戏后 MCP `dota_run_lua` 执行 `DoIncludeScript('maps/zombie_abyss_v1_verify',getfenv())`。

当前测试会话已暂停、界面已恢复、镜头距离为 2500。可以使用游戏暂停键继续，或通过 MCP 执行 `PauseGame(false)`；但本版本尚未适配波次点位，建议优先查看地形。
