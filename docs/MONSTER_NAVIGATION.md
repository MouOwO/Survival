# 怪物沿主岛低地通道寻路

## 2026-09-26：楼梯通行与建筑禁建分开

主岛四处楼梯必须保持 `GridNav` 可通行，供地面怪物从低地到高台寻路。将楼梯 Paint GridNav 涂成红色会同时阻断怪物，不能用作建筑禁建标记。建筑禁建现在由 `build_forbidden_regions.csv` 中仅适用于 `template_map` 的四个楼梯及转角区域处理；预览和最终建造都调用同一服务端区域校验。Hammer 保存导航修改后仍须重新编译地图，并重新载入游戏。

建造格还会检查地面高度：`template_map` 仅允许接近四块 Z=384 建造草坪的地面（误差 16），同一格内继续要求高度差不超过 48。四处楼梯及其高处平台交界仍由禁建区域覆盖，避免仅凭高度放过最后一级台阶。正式波次怪（含 Boss 和飞行战斗分类）统一使用 Hull 半径 32，保留单位间碰撞；固定出生点依赖生成后按完整 Hull 执行的 `FindClearSpaceForUnit` 寻找空位。建筑挑战怪的零碰撞规则和练功房怪的独立半径不变。正式地面怪的城墙接敌沿用四个横向槽位。以上代码改动需冷启动新局才会作用于新生成怪物。

## 2026-09-24：楼梯转角导航断口

用户确认怪物卡在低过道转向玩家高台/楼梯处。读取当前游戏 VPK，四条阶梯共 203 个修复格仍处于旧的阻行状态；历史实机采样也在楼梯有真实地面（24～366 高度）的位置返回不可通行。当前源图已修正这些格子，但上次编译被游戏占用而未成功写入。

本轮直接编译当前 `template_map.vmap`，不运行地形生成器、不覆盖 Hammer 修缮：318 项成功、0 失败、1 跳过；包内 323 个资源 CRC 和源图 CRC 匹配。四条走廊共 300 个采样格在源图通行，其中实际新解除阻挡 203 格。原 68 个 mesh 的几何保持一致；不要根据本章节数字推断怪物实机走完整条路线已验收，最终运行检查状态见 [性能与导航验证记录](ai/validation/20260924/combat_performance.json)。

脚本仍采用地面移动和引擎寻路。城墙 AI 已有相同移动/攻击命令去重，未发现需要在楼梯增设强制瞬移或恢复飞行的依据。群体互相拥挤与单点地图不通是两件事，需要在更新后的地图继续观察。

**注意：下方 9 月 22 日“无需编译”结论只适用于当时的地图。** 后续手工修缮后要重新编译。旧 `manual_monster_navigation_check` 中相对刷怪点固定偏移的地形断言已落后于新的标记位置；本次使用 `manual_spawn_land_check` 和实际 marker 配对的 GridNav 路径检查，不能把旧固定偏移的报错直接认定为新地图错误。

## 2026-09-22 修复

部分进攻 Boss、首怪和普通飞行怪的 `movement_type` / `movement_type_override` 是 `flying`。旧生成代码将该战斗分类直接转换成引擎的 `DOTA_UNIT_CAP_MOVE_FLY`，导致怪物绕过地面导航阻挡，直接追向高地城墙。模型大小不是这里的寻路开关。

`systems/monster_navigation_policy.lua` 统一让可移动怪物使用 `DOTA_UNIT_CAP_MOVE_GROUND`，覆盖普通波次、建筑挑战、练功房、野外及转生挑战的生成入口。生成时先设置地面移动，再执行 `FindClearSpaceForUnit`，避免首次放置沿用原单位的飞行移动能力。

飞行战斗分类仍保留在原有 `survival_movement_type` / `survival_movement_type_override` 字段中。防空塔继续按这些字段选敌；模型、缩放、碰撞半径、攻击数值和城墙攻击逻辑不由此修改。无尽练功建筑的静止设置不受影响。

## 地图检查

检查的是当前 `content/dota_addons/survival/maps/template_map.vmap`，不是重新运行旧地图生成器：

- 主岛采用原生 Tile Grid 的 `gridnavFlags` 控制禁行区域。
- 四条低路与高地之间共 176 个关键阻挡格完整。
- 按实际导航格做不允许对角穿角的寻路检查，四路均能经外侧台阶到达自家高地。

因此本次修复不需要新增透明碰撞墙，也不需要重新编译地图。透明外观或模型物理碰撞本身不能替代 Dota 地面导航阻挡。

以上是源地图静态检查，不等于当前编译地图中的实机行走验收。

## 验证和生效

本地回归：

```text
lua scripts/vscripts/tests/test_monster_ground_navigation.lua
lua scripts/vscripts/tests/test_practice_difficulty_profiles.lua
lua scripts/vscripts/tests/test_challenge_unit_names.lua
```

关闭旧测试局后，通过项目正常联调入口 `launch_aliyun_test_game.cmd` 新开一局，让 Lua 模块和新生成怪物使用修复。已经生成的旧单位不会由文件编辑自动改成地面移动。

在 Workshop Tools 的服务器控制台执行只读检查：

```text
script_reload_code tests/manual_monster_navigation_check
```

脚本检查当前四路低道、台阶、边缘阻挡及存活怪物的移动能力；不生成或移动单位、不推进波次、不读写玩家存档。没有存活怪物时，单位部分只能标记未验证。

实机应观察：大 Boss 和飞行怪从刷怪点沿低道前行，绕到外侧台阶，再接近城墙；飞行怪仍可被防空塔选中。移动能力和导航采样通过，也不能代替观察实际追击轨迹。

## 以后在 Hammer 调整路线

使用 Hammer 打开当前 `content/dota_addons/survival/maps/template_map.vmap`，进入 **Tile Editor → Paint GridNav**，通过 **GridNav Layers** 查看导航。高低差陡边使用 **Block All**，保留低道、转弯与台阶开口；不要直接把整个通道涂成禁行。当前地图使用 Tile Grid 内的导航数据，无需额外创建透明模型。

保存后，退出占用该地图的测试局，再从 game 插件目录执行：

```powershell
powershell -ExecutionPolicy Bypass -File tools/map_c6/compile-main.ps1
```

这个命令编译当前 Hammer 文件。不传 `-SourceMap`，不运行 `build-layout-v4.cjs` 等旧布局生成器，以免覆盖后续手工编辑。重新开局后再次执行只读检查，并实际观察怪物路线。
