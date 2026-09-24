# C6 地图第一版

## 当前源文件与编译包校验（2026-09-24）

`compile-main.ps1` 只编译当前已保存的 Hammer 地图，完成后检查源文件在构建期间没有变化，并逐项校验 VPK 资源 CRC、包内记录的 VMAP 源 CRC。校验不通过时构建命令报错，不能仅以 VPK 修改时间作为同步依据。需要本机 Node.js；报告位于 `output/map_main_merge_20260919/package_verification.json`。

只检查现有地图、不重编译：

```powershell
node tools/map_c6/verify-map-package.cjs --report output/map_package_verification.json
node tools/map_c6/verify-map-package.cjs --self-test
```

此检查不代替游戏内的视觉、寻路和小地图拍摄验证。编译包已同步后，已运行的测试局仍需退出并重新加载地图。

## 小地图更新（2026-09-23）

地图编译不会重新拍摄小地图。`template_map` 当前使用 `resource/overviews/template_map.txt` → `materials/overviews/template_map.vmat` → `template_map.tga`，只重新编译旧 TGA 仍会显示旧布局。

保存 Hammer 地图后，先关闭当前地图测试，运行 `tools/map_c6/compile-main.ps1`，再用 `launch_template_map.cmd` 打开刚编译的地图。确认 Workshop 已进入 `template_map`，在 game 仓库根目录执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/repair_minimap_client.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/verify_minimap_sync.ps1 -ExpectedOutputSize 2048 -CheckCompilerDependencies
```

修复脚本确认当前地图后，备份现有小地图资源到忽略的 `output/minimap_refresh_*/before/`，调用引擎重新拍摄 2048×2048 TGA，必要时只编译当前小地图材质。它会检查真实材质依赖、完整像素、生成时间、世界坐标范围及编译依赖，确认 VMAP 和 VPK 在生成期间未变，并写入 `after.json`。它不会执行 Git 恢复、覆盖源地图或重编整张地图。`-WhatIf` 可检查操作计划，不连接控制台或生成资源。

当前世界范围为 ±16384，overview 的 `pos_x=-16384`、`pos_y=16384`、`scale=32`；输出像素数量与该世界坐标映射分别校验。脚本通过后还需在游戏中核对海岸、房间轮廓及玩家标记位置；资源检查不代替视觉或寻路验收。客户端仍缓存旧图时，退出本次测试后重新打开地图。

离线脚本回归：`powershell -NoProfile -ExecutionPolicy Bypass -File tools/test_minimap_sync.ps1`。

## 当前：V4 布局（2026-09-20）

`template_map.vmap` 按确认的 V4 重排，维持 128×128 格、每格 256 单位。中央完成稿位置及内部结构保持不变。三个副本改在左上方一列，中心约为 (-5248,10752)、(-5248,8704)、(-5120,6656)，对应合成宝石、冰烬挽歌、火焰巨魔；避开中央环岛岸线。

普通练功房为 **4 位玩家 × 4 类房间**，左上/右上/左下/右下分别对应引擎玩家 0/1/2/3。每排依次木材、金币、属性、大属性。左侧 1～10 转排成一列，右侧十戒为两列五排。右下另有四间 15 倍练功房和四座独立火山岛。

右侧两大陆之间另有两个独立挑战岛：冰之幽魂（06，中心 10624,2304）恢复原雪地岛，熔火核心 Lv1–3（07，中心 14336,2304）保持已完成模型的原尺寸。右侧模式大陆整体南移 2048，范围改为 X=8960～15872、Y=-6144～0；七宗罪入口和刷怪点同步移动。06 不再借用右上雪地大陆，07 不再占用右下第一座火山岛。左侧火焰巨魔（08）保持原位置。

新原生大陆包含夜魇左上、雪地右上、天辉左下 A、四向连通的左下 B、右侧模式区。雪地与左下 A 各四块 1792×1536 的场地，依次靠右、左、右、左；对应出怪点在另一侧，同 Y、同高度，入口预留 480 单位缺口。出怪点/入口/中心名为 `v4_northeast_field_N_spawn/gate/center` 和 `v4_southwest_a_field_N_spawn/gate/center`。这些模式区域提供地图标记；不凭布局新增尚未定义的模式战斗规则。

普通挑战入口、归位点及怪物出生点由 `systems/player_room_locations.lua` 解析到 `player_N_challenge_01..04_*`；15 倍房使用 `player_N_endless_cycle_sanctum_*`。公共 Boss 与老地图兼容名保留。英雄召唤使用各组木材房内的 `player_N_hero_spawn`。

`build-layout-v4.cjs` 是有备份输入的单次布局迁移器，不是覆盖 Hammer 后续手工修改的常规构建命令。输入备份和输出清单位于 `output/map_layout_v4/`；日常编译仍运行 `compile-main.ps1`。测试使用 `lua scripts/vscripts/tests/test_player_room_locations.lua` 和实机命令 `script_reload_code tests/map_c6_layout_v4_check`。下方 128 布局一节记录的是 V4 之前的中间版本，旧坐标及旧测试不作为当前验收标准。

大陆基底保留原生 Tile Grid；天辉铺装、草雪场地使用带顶点混合通道的可编辑 Hammer 面片，已完成的小型房间继续使用原有模型。最终编译 238 成功、0 失败，实机点位、导航、传送、路径及岛间隔离检查 1333 项通过。实际俯视图见 `art/maps/c6/layout_v4_challenges_topdown.png`，2048 原图见 `layout_v4_challenges_topdown_full.png`，验收记录见 `docs/ai/validation/20260920/map-layout-v4.json`。

## 2026-09-20 主地图 128×128 布局

当前 `template_map` 已扩展为 128×128 原生地形格，每格 256 单位，边界为 ±16384。空白区统一为原生水域，海底同步扩展。中央完成稿整体向北平移 4096，建造边界、资源树、建造者点和出怪点同步迁移。公共场地只移动位置，保留已有模型、材质、碰撞和内部间距。

四角新增尺寸相同的独立练功房，复用木材房完整组件；本轮按“每位玩家一间”实施。显示 player1～4 对应引擎 ID 0～3，依次为左上、右上、左下、右下。英雄召唤优先使用 `player_N_hero_spawn`，各房另有 `player_N_training_entry/home/target` 标记。没有专属标记的其他地图继续使用祭坛附近出生。此轮没有新增房内刷怪规则。

十转入口为 `rebirth_10_entry`，左侧 (-13100,4096)；十戒入口为 `challenge_11_stage_10_entry`，右侧 (12544,5910)。原公共挑战入口名保持不变，小地图范围已同步。

双击 `launch_template_map.cmd` 打开实机；F7 近景、F8 中央全貌、F9 整张地图鸟瞰。从 Hammer 启动的无 `-addon` 参数进程通过实际 Workshop 地图回显确认后也可复用。若 Hammer 仍显示修改前的文档，应关闭该旧文档并从磁盘重新打开，避免旧内容覆盖新布局。

验证：地图编译 229 成功、0 失败；`tests/manual_integrated_arenas_check` 对 30 场地检查 235 项，`tests/map_layout128_check` 检查四玩家实际传送、中央入口、原生挑战路径及海域阻挡 38 项，全部通过。记录见 `docs/ai/validation/20260920/map-layout128.json`。

`relayout-128.cjs` 是本次快照迁移工具，输入为当天备份和原集成清单；不能作为日常地图生成命令重复覆盖后续 Hammer 编辑。正常修改仍使用 `compile-main.ps1` 编译当前源地图。

## 清理后的正式文件与重建

game 仓库保存运行 VPK、布局配置、地图生成器、预览脚本和回归测试；content 仓库保存 `maps/template_map.vmap`、`maps/survival_c6.vmap` 和固定基础模板 `maps/templates/c6_terrain_seed.vmap`。两仓应检出配套提交。基础模板独立于编辑后的主地图，删除临时 `output` 不影响重建。

双击 `launch_template_map.cmd` 查看主地图（`launch_survival_main.cmd` 为同一入口），`launch_survival_c6.cmd` 查看 C6；F7 近景、F8 中央全貌、滚轮缩放。预览需要 Node.js 与本地 Dota 2 Workshop Tools。`launch.ps1` 使用仓库内 `console.cjs`，直接连接游戏开发控制台 `127.0.0.1:29000` 并用本次唯一 Lua 回显确认地图载入；当前启动流程不要求安装 MCP 或打开 VConsole。

`compile-main.ps1` 和 `compile.ps1` 默认编译 content 中当前保存的对应地图；只有 `compile.ps1 -Generate` 才重新生成 C6。不要在需要保留 Hammer 手工编辑时使用 `-Generate`。`prepare-ai-check.cjs` 的优化前基准已作为 fixture 保存，仍可独立生成检查脚本。

确认的设计参考与实机图位于 `art/maps/c6/`，最终验收摘要位于 `docs/ai/validation/20260919/`。一次性的快照合并、诊断脚本、旧编译输出、截图和备份已清理。下方历史章节中的 `output/...` 表示当时的临时目录，清理后不再作为构建输入或当前交付文件。

## 2026-09-19 主地图外围 26 个场地集成

主地图入口是根目录 `launch_template_map.cmd` 或 `launch_survival_main.cmd`，地图名仍是 `template_map`。六间练功房为木材、金币、属性、大属性、低阶熔火和高阶熔火；两间熔火复用同套模型，分别绑定 `challenge_07`、`challenge_08`。另有一至十转擂台和一至十戒场地，共 26 区。它们放在原外围岛位，中央池塘、四片建造区、通路和其他挑战区保留。

| 场地 | 主体占地（游戏单位） | 高度与外围装饰 |
| --- | --- | --- |
| 六间练功房 | 900×900 正方形 | 地面 Z=128，墙高保留；外侧树、岩石和后方传送凹位会超出主体。完整模型包围范围约 1228–1298 宽、1247–1258 深。 |
| 一至十转 | 1000×550 | 台基 Z=16，第 N 转台面 Z=16+N×14；各层自身高度保持，完整模型在该占地内。 |
| 一至十戒 | 700×700 正方形，含围墙 | 内部净空 612×612；地面 Z=58，模型水线与主图海面 Z=16 对齐。外岸及植被完整范围约 1130×1130。 |

上述主体尺寸与包含装饰的完整包围范围分开检查，不能只用 700 或 900 的方框判断模型是否重叠。训练房对所有模块的位置和模型本身同时缩放 X/Y；正交朝向交换对应局部缩放轴。后方三段弧墙统一使用 XY 等比缩放，保持弧段接缝连续并与两端墙柱搭接；地坪仍是 900×900。其他斜向装饰采用近似分轴缩放，验证读取它们最终实际变换后的包围范围。

### 日常编辑、编译与打开

在 Hammer 编辑并保存 `content/dota_addons/survival/maps/template_map.vmap`。先断开该地图的游戏测试，再在 game 仓库根目录执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/map_c6/compile-main.ps1
```

此命令编译 content 中当前保存的源图，无需 `output` 中的旧资产清单或临时预览。完成后双击 `launch_template_map.cmd`；正常游戏也可在控制台执行：

```text
host_timescale 1
r_drawpanorama 1
dota_launch_custom_game survival template_map
```

启动器默认近景仍对准中央，F8 查看中央全貌；外围区域的可走性、传送和实机画面需要另外检查，打开中央预览不等于验收全部房间。

### 一次性导入器与重新生成

`integrate-arenas.cjs` 读取现有主图和 content 中的房间 prefab，输出 `output/map_arena_integration_20260919/template_integrated.vmap` 与 `integration_manifest.json`。它不安装或编译地图；遇到已经含 `arena_integration_` 实体的输入会拒绝重复导入，避免叠加两套模型。空间合同保存在可版本化的 `arena-assets.json`，其中记录源资产清单哈希和原生松树资源哈希；当前 Valve 包中的松树也必须与记录一致。

普通 Hammer 编辑后直接编译即可。只有需要重新执行整套导入时，才取 **content 仓库提交 `926379c`** 中的合入前主图作为输入。这会以该历史主图重做导入，不包含之后手工编辑的改动，因此先保留当前源图。以下命令只将历史文件导出至临时目录，不切换或覆盖 content 工作区：

```powershell
git -C '../../../content/dota_addons/survival' lfs fetch origin 926379c --include='maps/template_map.vmap'
@'
from pathlib import Path
import subprocess

root = Path.cwd()
content = (root / '../../../content/dota_addons/survival').resolve()
destination = root / 'output/map_arena_rebuild/template_before_926379c.vmap'
pointer = subprocess.check_output([
    'git', '-C', str(content), 'show', '926379c:maps/template_map.vmap'
])
data = subprocess.check_output(
    ['git', '-C', str(content), 'lfs', 'smudge'], input=pointer
)
if b'dmx encoding binary' not in data[:100]:
    raise SystemExit('LFS binary map was not resolved; stop before integration.')
destination.parent.mkdir(parents=True, exist_ok=True)
destination.write_bytes(data)
print(destination)
'@ | python -B -

node tools/map_c6/integrate-arenas.cjs --source=output/map_arena_rebuild/template_before_926379c.vmap
node tools/map_c6/verify-arenas.cjs --baseline output/map_arena_integration_20260919/template_before_text.vmap
```

验证器使用导入器转换后的文本基线；不要把 Git 导出的二进制 VMAP 直接传给文本检查器。

确认清单和独立静态检查后，再显式安装该输出并编译。`-SourceMap` 会备份当前主图和 VPK，再写入 content：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/map_c6/compile-main.ps1 -SourceMap output/map_arena_integration_20260919/template_integrated.vmap
node tools/map_c6/verify-arenas.cjs --baseline output/map_arena_integration_20260919/template_before_text.vmap --vpk maps/template_map.vpk
```

本轮生成清单记录 3328 个道具、126 个新标记和 3308 个白名单可走格；替换 52 个旧目标标记，修正十转出生点旧拼写。静态检查覆盖完整模型间距、坐标边界、标记唯一性、原五个网格及非目标实体保留、地形数组修改白名单。**静态通过与 DMX 转换通过不代表实机通过**；编译结果、实际 GridNav、碰撞高度和传送结果分别以本轮验证报告为准。以下中央区域历史验收数字不代表这 26 个新增场地的实机结果。

### 外围场地实机检查

加载 Workshop 的 `template_map` 后，在游戏开发控制台执行：

```text
sv_cheats 1
script_reload_code tests/manual_integrated_arenas_check
```

入口只在服务端 Workshop 主地图执行，每次重新载入探针；读取标记、地面和寻路状态，不移动或生成单位、不修改存档。输出前缀为 `[INTEGRATED_ARENAS]`，最终应为 `SUMMARY PASS areas=26 checked=207 failed=0`。保留该次完整控制台日志，以便确认检查的是当前地图；模块也将本次结果保存在 `INTEGRATED_ARENAS_LAST_REPORT`。

正式入口实机日志已独立复核：26 个场地、207 项检查全部通过，覆盖 126 个实际标记、各房间地面高度与 GridNav、入口到刷怪点/四角路径、外围水域阻挡，以及 325 对区域之间的寻路隔离。摘要和原日志 SHA256 见 [arena_runtime.json](../../docs/ai/validation/20260919/arena_runtime.json)。此次运行使用上面的正式 `script_reload_code` 入口，控制台确认收到了预期输出。验证范围是地图几何与导航，未完成挑战业务通关、奖励结算、多人和压力测试。

## 2026-09-19 中央区域并入主地图 template_map（外围集成前版本）

主地图仍为 `template_map`。将已优化的 C6 中央区域整体平移 `(0, -5376, 0)`，中央池心位于 `(-1024, 0)`；方池 1200、四块空地约 1400×1400、A→B 距离 1500、低路 24、高地 384 均保持原尺寸。原主地图 64×64 Tile Grid、外围挑战/转生区域及 60 个原有外围标记保持不变。已迁移四组玩家/怪物出生标记、资源树与实际建造范围。合入 4545 个中央实体和 5 个地形/水底网格，保留原生植被、封闭树带与近景减面成果。

双击根目录 `launch_survival_main.cmd`，只显示主地图的 Dota 2 近景预览。F7 回到近景，滚轮缩放，F8 查看中央全貌。预览沿用 `host_timescale 0.001`；正常游戏使用控制台 `host_timescale 1`、`r_drawpanorama 1`、`dota_launch_custom_game survival template_map`。旧 `launch_survival_c6.cmd` 仍可查看完整 C6 源图，其 VMAP/VPK 哈希未变。

在 Hammer 编辑 `content/dota_addons/survival/maps/template_map.vmap`。保存后可用 `powershell -NoProfile -ExecutionPolicy Bypass -File tools/map_c6/compile-main.ps1` 编译当前源图；编译前先断开这张地图的测试。一次性快照导入已完成，其脚本随临时文件清理。小地图由引擎 `dota_minimap_create` 重新生成。

主地图 82 项资源编译、0 失败；实机 292 项中央通路/建造检查、204 项接缝/树根支撑检查、64 项主图集成检查全部通过，共 560 项。原有外围实体内容逐个核对未变。最终摘要与文件哈希见 `docs/ai/validation/20260919/main-map.json`，实机图见 `art/maps/c6/main-close.png` 和 `main-pool.png`；旧临时备份与日志已清理。

## 2026-09-19 全部阶梯侧边与延伸平路的矮草（历史）

按用户截图，新增 `stair-cover.cjs`，对四组阶梯、共 12 段原生石阶的左右两侧逐段补植矮草与小灌木，并延伸至上下平路的边缘。共 396 丛、7 种原生模型；288 丛沿石阶侧边，108 丛分布在上下接路处，每段每侧有 12 丛。使用原生绿色崖边草材质组、低灌木、小蕨类与圆叶植物形成错落的低植被，最高约 38 单位。

新增植被可搭入石阶最外侧 40 单位、上下平台最外侧 24 单位，阶梯中间保留至少 304 单位视觉净空；384 原宽、地形及导航均不变。建筑草地和低长过道保持原样。新排布独立，不改变已认可的崖顶、崖边与崖脚植被。

`rock-surfaces.cjs` 增加完整模型路径及分轴缩放支持，以检查原生台阶实际网格和侧边岩石是否遮挡新植物；原岩石计算顺序保持一致。新增植物根据实际模型网格落地，其中 340 丛在土壤上，56 丛在最外侧石阶上；根部埋入 1.5 单位，无碰撞。备份、检查、编译及四向近景见 `output/map_stair_grass_20260919/`，最终以 `verification.json` 为准。

最终 50 项编译、0 失败；602 项实机检查通过。新增 396 丛植物的完整占地共 8,316 次比较通过，原有地形、建筑区、树木、岩石及已认可植被保持一致。`detail_final.png` 为北侧阶梯实机近景；南侧默认视角被前景树冠遮挡，其旋转排布、实际 VMAP 参数及通行检查已核验。

## 2026-09-19 低过道崖脚的矮草与小植物（历史）

用户认可崖顶衔接，要求再处理低过道与悬崖底部的接缝。新增 `verge-cover.cjs`，沿四向低路两侧及外侧折角布置原生矮草与小植物。以三种细草簇为主，混合小蕨类、圆叶植物、两种缩小的绿灌木，少量石缝配野花与小蘑菇，共 9 种原生模型、472 丛。实机对比 11 种候选模型后挑选，模型尺寸与哈希直接读取本机 Valve VPK；根部在真实岩脚前方的土壤内，植物最高约 30 单位。

草叶仅可搭入低路最外侧 24 单位，路中央至少 400 单位保持视觉净空，原路面宽 448 与 GridNav 完全不变。根部在禁行边带，所有植物无碰撞；台阶、上平台与建筑空地严格留空。新排布使用独立种子，已获认可的崖顶／原崖边植物、岩石、树木、地形与 47 间练功房全部保留。

候选原生模型、材质组、临时样品照片、备份、检查和实机验收见 `output/map_verge_20260919/`，最终以 `verification.json` 为准。临时样品脚本已移除。

最终 48 项编译、0 失败，602 项实机检查通过。472 丛新增植物的完整占地与保护区域共 9,912 次比较通过，实际 VMAP 的位置、角度、原生材质组、无碰撞属性核对通过。近景为 `south_final.png`、`west_final.png`、`bend_final.png`。

## 2026-09-19 原崖边与草地交界的植被衔接（历史）

按用户截图，将后排岩顶灌木向原悬崖的草地侧移动约 48 单位，而非继续只覆盖石头正面。长过道后排从距路轴约 342 移至 390，台阶内侧与转角同步向草地接缝调整，池角增加连续折返的低灌木。移动后的根部重新取原生岩面与地形中较高的支撑面；不会保留旧石头高度而悬空。

本轮允许低矮叶片覆盖建筑草地最外侧不超过 48 单位，植物根部仍在禁行边带、装饰无碰撞，过道、台阶、平台、池口全部保留完整净空。地形与建造网格没有改变。此范围是用户本轮要求叶片跨过原崖边后的调整，替代旧版“所有叶片都不能搭到草地”的限制；中央建造空地保持干净。

当前岩岸植被共 1,784 丛，其中 408 丛用于原崖边衔接；相较上一版净增 84 丛。旧裸坡灌木同步采用已核对的官方绿色／秋色材质组，消除接缝处近黑的旧灌木。备份、几何检查、编译与实机验收见 `output/map_rim_overlap_20260919/verification.json` 及同目录。

最终 46 项编译无失败，602 项实机检查通过；独立占地检查 37,464 次，通过四区各 48 丛叶片跨过草地边缘且不侵入内部的核对。实际 VMAP 中 2,240 丛岩岸及裸坡植物的位置、角度、原生材质组和无碰撞属性均已确认。`reference_final.png` 对应本轮用户截图位置，`opposite_final.png` 与 `west_final.png` 为另外两处近景。

## 2026-09-19 四向过道岩顶与岩壁植被（历史）

用户近景显示，旧版贴地灌木被高出地形的岩石遮住，长过道两侧仍有大片裸岩。本轮新增 `rock-surfaces.cjs`，直接从本机 Valve VPK 读取原生岩石的可见三角面；`rock-cover.cjs` 对实际摆放后的岩顶及过道侧岩面发射采样射线，将植物根部埋入真实岩面，而不是下面的地形。

四向过道均补齐双排交错冠层、五层岩面植被，并延续到回折处和台阶两侧。混合原生绿灌木、春秋灌木、蕨类、常春藤 6 种模型；新增 1,700 丛，使用原生材质与中性颜色。实机对比后，普通灌木采用原生绿色 skin 1，秋灌木采用原生橙色 skin 1，崖顶少量混入粉花 skin 3，避免默认 skin 0 的近黑色叶片形成斑块。完整旋转包围盒避开所有过道、台阶、平台、方池与建筑空地，全部无碰撞。保留原地形、原岩石、47 间练功房、闭合树带及导航。

备份、占地与实际 VMAP 检查、编译记录和实机近景存放在 `output/map_lane_cover_20260919/`；最终验收以该目录 `verification.json` 为准。

最终编译 46 项、0 失败；602 项实机检查通过。新增 1,700 丛植物的实际 VMAP 位置、角度、材质组与无碰撞属性核对通过，完整模型占地与可玩平面的 35,700 次比较通过。四个方向的实机近景分别为 `east_final.png`、`south_final.png`、`west_final.png`、`north_final.png`；临时材质展示样品已经移除。

## 2026-09-18 原生灌木与地被覆盖裸坡（历史）

按用户指定思路，用多种原生植物覆盖池岸、转角、台阶边和长石岸的裸露斜面。`slope-cover.cjs` 混合两种绿灌木、春季与秋季灌木、两种蕨类、低草丛及常春藤，共 8 种模型；大小和组合错落，绿色为主，灌木与地被分层。常春藤和低灌木按坡面法线倾斜，蕨类保持较直立，根部埋入地面 2 单位。

`plant-assets.json` 的尺寸从本机 Valve VPK 的 MDAT 提取，保留来源哈希。每株植物按完整旋转包围盒自动缩小，避开水陆通道、台阶、建筑空地及上下平台；全部为原生材质、中性颜色、无碰撞装饰。新增植被使用独立确定性排布，不改变原树木、岩壁、地形和导航。

本次备份、模型查验、覆盖范围与 VMAP 实际姿态检查、编译及实机图片在 `output/map_slope_greenery_20260918/`，最终结果以 `verification.json` 为准。入口及 F7/F8/滚轮预览控制继续保留。

最终新增 456 株／丛原生植被，8 种模型；44 项编译无失败，602 项实机检查通过。完整植物包围盒与可玩区域的 9,576 次比较通过，实际 VMAP 中全部新增植物的角度、位置、无碰撞设置和原生颜色已核对。最终近景为 `bank_close.png`、`pool_final.png`、`stairs_final.png`，全景为 `overview_final.png`。

## 2026-09-18 台阶岩壁与崖顶自然衔接（历史）

根据用户台阶近景，移除台阶两侧六块孤立的细长岩石，改为从当地低地连续叠合到崖顶的原生岩群。内侧、外侧、低位转角及接头每区共 21 组，顶部高度 422–459，比草地高 38–75；大小、朝向和高低错开。直路旁草地边缘增加小型半埋石，所有石块均留在禁行带内，未侵入建筑空地或台阶。

新增 `cliff-banks.cjs` 使用本机 Valve 模型包围盒计算旋转后的占地、等比缩放与居中位置。岩层逐段重叠，末层向下压入；避免上移末层后产生悬空缝。低位转角外侧的地形过渡放宽，陡坡网格细化到不超过 24 单位，减少大三角折面，外圆岸线仍使用 16 单位细分。

四个区域统一实施，保留原有台阶宽度、平坦建筑区、低位通道、方池和闭合林带。本次备份、18 组几何与岩石占地/叠合检查、编译及实机记录在 `output/map_natural_cliffs_20260918/`，以该目录 `verification.json` 为准。第一张用户图片路径已核实不存在，本轮参考第二张图片和实际游戏近景。

最终编译 42 项、0 失败；冷启动后 602 项实机检查全部通过。每区新岩岸配置包含 113 块原生岩石，完整占地与可玩区域无交叉；21 组叠合柱从局部低地连续覆盖至崖顶。最终近景 `stairs_final.png`、`stairs_other_angle.png` 和全景 `overview_final.png` 均在同一验收目录。

## 2026-09-18 池岸衔接、原生树材质与闭合林带（历史）

修复四个池口底面与低位通道之间的 4 单位高度差。池边高台端头降为低岸肩，再衔接 384 高地；通道旁的裸岩坡退入禁行带，原生岩块采用等比缩放，错开形状、朝向和高度。池口、直路、回折台阶及 1400×1400 建造空地的通行与建造范围保留，空地没有新增装饰。

圆岛岸线网格裁切到完整的圆形多边界，补齐旧版按单元中心筛选时遗漏的岸边地面。外围固定布置 176 棵相互覆盖树冠的原生橡树、秋叶树和春花树，辅以交错内排；外圈树干距可用地面最少约 205 单位。圆周闭合，拐弯通路仍在林带内。

从本机 Valve `pak01_dir.vpk` 核对 4 种树模型和 19 个材质变体，未发现插件内同路径替换。多数叶片材质启用法线与高光，部分官方白花／雪叶变体本身不启用高光。预览的 `r_deferred_specular` 已开启，`mat_fullbright` 为 0。中央树移除额外染色，恢复原生材质颜色；全局光照恢复安装模板的参数。预览模式没有统一关闭树叶高光，具体亮泽仍取决于原材质和光照方向。

本次备份、原生资源审计、16 组几何检查、编译记录和实机截图保存于 `output/map_seams_canopy_20260918/`，以 `verification.json` 为最终结果。新增 `tests/map_c6_seam_check.lua` 检查池口及全部外圈树根支撑。陡坡禁行区的 `GetGroundHeight` 不代表可见岩面，支撑检测采用真实 `TraceLine` 地面碰撞；初次仅用导航高度导致的误报保留在 `seams_before.log`，没有降低实际碰撞检查的要求。

最终编译 42 项、0 失败；冷启动后 106＋292＋204＝602 项实机检查全部通过。外圈 176 处实际岩面高度为 184.32–196.41，树根原点为 164，均埋入地面。最终图片为同目录 `pool_final.png`、`overview_final.png`，当前 Dota 2 窗口已加载新版。

## 2026-09-18 干净建造空地、低位过道与转角台阶（历史）

按用户最新实机反馈，移除中央空地的圆圈、石板、落叶、草丛和摆拍英雄模型；编辑锚点保留为不可见 marker。低矮点缀只放在距可通行地面至少 110 单位的边缘树林，建造空地保留原来的 1400×1400 尺寸和 384 高度。

四条直过道降到 24，原版水面为 16，留 8 单位避免水面穿插；水边 A 通过短缓接连到直路，A→B 的 1500 距离保留。回折向外绕到局部 x=2432，再由 y=64→704 的三段原生台阶上升到 384。台阶宽 384，位于原空地外侧。下平台和上平台分别保持平整，新增位置示意不再绘制圆圈。台阶本身用于通行，不作为平地建筑位置。

取消笔直高石沿，裸露高差采用原版 `river_rock001` 材质、交错叠放的 `riveredge_rock003a` 岩块和 `riveredge_rock_wall002a` 台阶侧壁；陡面改用竖向贴图坐标，避免旧版草皮拉伸和条纹，池岸朝向水面封闭。树林顶部没有额外山脊。通过原生 GridNav 限定回折路线，台阶侧面禁止绕行。

生成源仍为 `sanctuary.cjs` 和 `build-sanctuary.cjs`。本次修改前备份、几何模拟、最终编译和实机验收位于 `output/map_clean_cliffs_20260918/`；最终状态以该目录 `verification.json` 为准。镜头仍支持 F7/F8、滚轮限位缩放和窗口边缘平移。

## 2026-09-18 平缓树林与镜头控制（历史）

树带不再额外抬高山脊。原来的最近区域取高会在交界产生突变，现在连续混合相邻地面高度，树林地面不高于 384 的庭院，树带内部的大块山石也移除。外缘保留低岸石，方池岸壁按实际地面收边。原生 Tile Grid 的 GridNav 禁行数据保持一致，挡怪不依赖尖锐山体或树是否被砍倒；回折入口与建造平台仍按现有路线使用。

通过 `launch_survival_c6.cmd` 打开后，默认以 3200 距离对准东北玩家区。预览键位已在实际窗口中验证：**F7 玩家区近景（1800）、F8 中央全景（6500）、滚轮上拉近/下拉远（每格 400，范围 1200–8000）**。鼠标移到窗口边缘平移镜头。F7/F8 同时把视角拉回对应区域，可在移到水域后快速找回地图。F6 是 Workshop Tools 的 Panorama 调试器快捷键，不作为地图预览键。

这些绑定由 `preview.json` 在每次预览启动时应用；用 `node tools/map_c6/build-preview.cjs` 可重新生成。滚轮采用原生 alias 距离档位，到 1200/8000 即停，避免 `incrementvar` 到极限后绕回另一端。缩放延迟关闭，仍以 0.001 模拟速度防止战斗流程自动结束。启动器将鼠标放到窗口中央，避免启用边缘移动后刚进入就漂移。仅显示 Dota 2，隐藏 Asset Browser、VConsole 与 Panorama Debugger。

本次备份、平整度/导航模拟、最终实机检查和 F7/F8 近远景截图位于 `output/map_smooth_camera_20260918/`，最终结果以 `verification.json` 为准。36,864 个禁行采样与上一版一致；平整度验证独立检查树带无附加峰顶和高度突变。原有 362 项实机通路/建造检查继续使用。

## 2026-09-18 拐角建造平台、抬高与空地点缀（历史）

用户确认池塘四个斜角没有阶梯是正确结构，本次不在斜角新增入口。中央过道由 128 抬到 256，庭院由 256 抬到 384，按一级 128 单位调整；原有四个正向入水口延长为两段原版台阶衔接。方池边长 1200、A→B 位移 1500、四片空地各 1400×1400、岛半径 3072 保留。

改动前实测回折中段已有可建位置，但外沿 `(2368,256)`、`(2368,576)` 的四旋转采样会因坡度或导航被拒。现在每个 B 外侧有 640×960 平台，与庭院同高 384，坡道放在拐角前的 1664–1984 段。每区外沿新增两处示意位置 `(2432,64)`、`(2432,512)`，同时验证 128×128 炮台与 256×256 建筑占地；原有炮台带保持平整。符号坐标以中央为原点、东→东北为模板，再顺时针旋转至其余三区。

空地增加原版零散石板、低碎石、草丛、花瓣和落叶，并细化草土顶点混合；装饰没有阻挡碰撞，仍通过实际建造系统检查。生成器增加非数值坐标检查，避免非法高度进入引擎地图转换器。

本次备份、建造前后探测、实机截图、编译及最终验收在 `output/map_refine_20260918/`。`tests/map_c6_sanctuary_check.lua` 现有 256 项检查，覆盖四区、原炮台带、拐角两种占地和装饰处建造许可；另保留原 106 项点位/通路检查。`tests/map_c6_corner_probe.lua` 仅诊断，不创建建筑、不占格。最终结果以该目录 `verification.json` 为准。根目录 CMD 启动方式与纯 Dota 2 预览窗口继续使用。

## 2026-09-17 回折入口与炮台预留带（历史）

用户选定 09 回折入口后，先用内置 imagegen 编辑并保存 `output/map_folded_20260917/09_corrected.png`，提示词在同目录 `image-prompt.txt`；随后按该图建模。四区统一采用原图左下角结构的旋转副本：西入口向南进入西南空地、南入口向东进入东南空地、东入口向北进入东北空地、北入口向西进入西北空地。各通路从中央水边 A 向外 1500 到 B，再回折进入本区，四片平地仍各为 1400×1400。

中央河水保持 1200×1200；过道宽 448、高 128，庭院高 256，回折处有连续坡道。每区靠过道的一侧预留 384 深的平整炮台带，三个齐地石圈只是位置示意，实际建造使用原有网格系统；不预占建筑格。矮石沿与原生 GridNav 隔开道路和炮台带，怪物通过 B 端绕入，树石布置在另一侧及庭院外缘。全岛半径 3072，原 47 间练功房的位置、数量和缩放比例保留。

`sanctuary.cjs` 是统一尺寸、旋转、高度、阻挡和地表混合的来源，`build-sanctuary.cjs` 输出可编辑地形、原生资源和 A/B/炮台示意锚点。玩家与普通波次 marker 名称及槽位保持原有对应关系；波次点移到水边 A，玩家位于对应回折庭院，资源树移入东北空地。所有中央树木使用 `always_use_showcase_tree`，春花 skin 为实际组名 `11`，橙色秋树组为 `2`。中央与外围仍共用原版河水高度 16，池底 4，外围保留水下遮底处理。

默认 CMD 启动器对准中央，镜头距离 6500，仅显示 Dota 2 窗口。验证记录、修正版效果图和最终实机图集中在 `output/map_folded_20260917/`；改动前源地图、编译地图与生成器保存在其 `before/`。`check-geometry.cjs` 验证旋转一致、建造脚印及 B 端必经的几何连通性；实机执行 `tests/map_c6_check` 和 `tests/map_c6_sanctuary_check`，后者通过现有 `GRID_CAN_PLACE_REQUEST` 验证 12 个炮台位的真实建造许可。最终验收以该目录 `verification.json` 为准。美术基于原生素材，并非效果图的逐像素复制；多人完整玩法与压力测试不属于本次地形验收。

## 2026-09-17 中央地形第一版（历史）

中央按 `output/map_sanctuary_20260917/approved_reference.png` 重做。水池严格为 1200×1200 游戏单位，东南西北四块空地的轴向设计纵深为 1400，四条入口长 256、宽 448；整体圆岛半径 2600。四条对角山脊连续连接池角与外侧树林，代替全部四条分隔水道。此前中央面积减半的方案由本次明确尺寸覆盖，练功房数量、位置与缩放比例保留。

`sanctuary.cjs` 集中管理尺寸、高度与地表混合；`build-sanctuary.cjs` 布置中央场景；`mesh.cjs` 生成可在 Hammer 编辑的多边形地形和原生顶点混合数据。四片平地高度 128，山脊最高约 348，池底 4，原版河水高度 16。平地、坡道和山脊有实际地形与寻路数据。

水池直接使用 Valve Radiant Tile Grid 的原版河水，池底为原版河床石材。全图保持统一水面高度，避免不同高度水面造成错误折射。外围使用水下黑色原生材质遮底，形成看不见河床的深水观感；这是视觉处理。树木、秋叶、春花、松树、岸石、台阶、石柱及地被均引用已安装的 Dota 原版资源，没有导入概念图贴图或第三方模型。

默认 `launch_survival_c6.cmd` 现在对准中央区域，仍只显示 Dota 2 窗口。预览在英雄载入后把模拟速度设为 0.001，避免战斗流程很快结束；没有使用会使画面灰化的暂停模式。正常游玩前在控制台执行 `host_timescale 1` 并重新加载地图；关闭游戏再正常启动也会恢复。全图查看可执行 `host_timescale 1`、`dota_camera_distance 34000`、`dota_camera_set_lookatpos -1024 -6500`，镜头到位后再设 `host_timescale 0.001`。

原地图备份：`output/map_build_c6/before_sanctuary_20260917_153909/`。最终一轮增量编译 38 项、0 失败，CMD 冷启动返回 0；实机通过 106 项原有点位/通路检查和 52 项中央地形检查，并核对 47 间练功房布局未变。验收文件与最终实机截图保存在 `output/map_sanctuary_20260917/verification.json`、`verification.log`、`central_final.png`。本次重点是中央地形；树木密度、石材细节与光照仍可根据实机效果继续精修。

用户确认参考：`output/map-concepts-20260914-round3/C6.png`。

地图名 `survival_c6`，原生 Dota Tile Grid 为 128×128，每格 256 游戏单位。源文件位于同一 Dota 安装目录的 `content/dota_addons/survival/maps/survival_c6.vmap`，编译产物为本插件的 `maps/survival_c6.vpk`。原 `template_map` 保留。

## 布局

| 区域 | 练功房数量 |
|---|---:|
| 左侧长列＋内侧短列 | 10＋3 |
| 中央方形区域的左上、右上、左下、右下横排 | 各 4 |
| 右侧竖排 | 4 |
| 右下独立小房，两排五间 | 10 |
| C6 保留的星形岛两间、最右侧一间、南侧一间 | 4 |

共 47 间，其中主要要求的分组为 43 间。中央圆岛由相接的树带分成上、下、左、右四块，中央矩形以原版水面材质覆盖齐平的浅水底，保留四向水陆通路。中央南侧装饰横台、东南四房下方草地取消为水域；左侧大块平原、右上四处林地与星形岛沿用 C6。

`layout.cjs` 是生成布局的坐标来源。`water_surface.vmap` 是从已安装的 Valve Radiant tileset 提取的水面网格片段，由生成器放置；它不是供 Hammer 单独打开的完整地图。`build.cjs` 生成可编辑原生地形、实体、已有挑战的命名锚点和地图专属 Lua 配置。已使用原版树木（春花与秋叶皮肤）、雪松、木围栏、石柱、塔、火焰与营地资源。

### 2026-09-15 面积调整

中央占地缩为上一版的 50%，普通练功房为 70%，右下两排共 10 间为 30%。比例指面积，长宽按比例的平方根缩放；房间中心、数量、分组不变。中央水面、树带、玩家点、入口、资源树与建造边界同步调整。原生地形岸线按 256 单位格点生成，实际岸边有取整差异。

缩小后房间之间最窄设计间距约 465 游戏单位，34 处分组内间隔采样为水域；小房间减少树木与地表装饰，角色展示模型保持原尺寸。上一版 VMAP、VPK、生成器和布局配置备份于 `output/map_build_c6/before_resize_20260915/`。本次几何记录见 `resize_geometry.json`。

本次编译 443 项、0 失败，VPK 成功更新并冷启动加载。实机通过 106 项点位/水陆通路、34 处水域间隔、98 个已有挑战/转生锚点检查。记录为 `verification_resize.json`、`verification_resize_summary.log`；实机截图为 `overview_resize_c6.png` 和 `central_resize_c6.png`。全景相机更新为距离 34000、观察点 (-1024, -6500)，完整显示最南侧房间。

## C6 源图的打开与重新生成

直接双击插件根目录的 `launch_survival_c6.cmd`，或在 CMD 执行其完整路径。默认是纯画面预览：自动加载 C6、开启白天与全图视野、切到全景、隐藏 HUD 和难度选择界面，只显示 Dota 2 窗口。

启动参数使用 `-tools -noassetbrowser` 和 `+dota_launch_custom_game survival survival_c6`，冷启动直接指定地图；复用已有 Tools 进程时会隐藏 Asset Browser 窗口。当前启动器通过 `console.cjs` 直接连接游戏控制台 TCP 端口，分别重定向 stdout/stderr 并检查退出码，兼容 Windows PowerShell 5.1。收到本次唯一 Lua 回显后才应用相机。已有 VConsole 或其他控制台客户端占用 `29000` 时，先断开该客户端再启动。

C6 预览日志为 `output/map_build_c6/launcher.log`、`launcher.stderr.log`；主地图对应日志位于 `output/map_main_merge_20260919/`。相机设置在 `preview.json`。恢复正常游玩可重新启动游戏，或执行 `host_timescale 1`、`r_drawpanorama 1` 后重新加载地图。

历史记录：2026-09-15 曾在旧 MCP 启动方案下使用 CMD → Windows PowerShell 5.1 验证入口和窗口显示；该记录不代表当前机器安装了 MCP，也不替代当前直接 TCP 启动器的验证。

Workshop Tools 控制台：

```text
dota_launch_custom_game survival survival_c6
```

Hammer 可直接打开上述 content 下的 `.vmap`。生成脚本会覆盖该文件，手工精修前请另存一份。

在插件根目录执行（需要 Node.js 与已安装的 Dota Workshop Tools）：

编译前关闭占用 `survival_c6.vpk` 的 Workshop 游戏实例。编译器可能在最后 VPK 写入失败时仍返回资源编译 0 失败，脚本现已额外检查文件占用、打包失败日志和 VPK 修改时间。

```powershell
./tools/map_c6/compile.ps1 -Generate
```

生成脚本从固定的 `maps/templates/c6_terrain_seed.vmap` 解码原生地形配置，并读取游戏 VPK 中的资源目录。编译日志、生成布局清单和点位清单在 `output/map_build_c6/`。正常保存后的 C6 编译使用 `compile.ps1`，仅明确重建时才加 `-Generate`。

## 实机检查

2026-09-15 验证：编译 435 项、0 失败；加载到 `survival_c6` 后，106 项检查全部通过（102 个点位检查和 4 条水陆通路）。记录见 `output/map_build_c6/verification.log`。

加载地图后，可在 Tools 控制台执行：

```text
sv_cheats 1
script_reload_code tests/map_c6_check
```

检查全部练功房入口、怪物点、四名玩家出生点、波次点的地面高度及可通行性，并验证四个入口到中央水域的寻路。

仅查看美术时可执行 `script_reload_code tests/map_c6_preview`，启用白天和全图视野。全景相机需先执行 `r_farz 100000`，否则远处地形会被裁剪。正常游玩恢复 `r_farz -1` 和 `dota_camera_distance 1200`。

## 第一版范围

已有挑战/转生的入口与生成锚点已布置。房间里的斧王和石头人为展示比例的模型；新增房间的玩法、独立天气与怪物配置尚需按后续玩法分配。原有建造范围和资源树配置仅在 `survival_c6` 下切换到新坐标。

这是可加载、可编辑的第一版地图。布局与原版资源已落地；水色、悬崖层次、花草与局部地表过渡仍可在 Hammer 中继续贴近参考图精修。完整多人挑战流程与性能压力测试尚未验收。

## 2026-09-15 原版资源与地表精修

- `paint.cjs` 在原生 1025×1025 Paint 图上写入 32 单位采样的材质权重、轻微调色和草密度。中央四向道路、玩家空地、练功房踩踏地面、林缘与草地之间有渐变；高度与水陆逻辑保持不变。可在 Hammer 用 Shift+V 继续编辑，并非贴一张效果图。
- 增加原版花、蕨、草丛、花瓣、落叶与岸石；活动中心留空。完整木栏替换破损木条。春花树使用实际的第 3 个材质组索引（组名为 11），修复先前按组名填皮肤造成的外观错误。
- 验证记录：`output/map_build_c6/verification_detail.log`、`verification_detail.json`；图片：`central_detail_c6.png`、`overview_detail_c6.png`。以关闭游戏后成功写入的 VPK 和冷启动实机检查作为最终验收，不能只依据资源编译统计。
- 精修前 VMAP、VPK、生成器和截图备份在 `output/map_build_c6/before_detail_20260915/`。自动生成会覆盖 content 源地图，手工编辑时请另存。

### 历史可选工具：dota2-mcp（2026-09-15）

旧开发环境曾使用 npm `dota2-mcp@1.6.0` 和 Codex MCP 注册；这是历史配置，不是当前机器的安装记录或启动前置条件。当前一键入口使用直接 TCP 控制台流程。

保留的 `patch-mcp.cjs`、`mcp-client.cjs` 仅供主动选择旧 MCP 方案时参考。旧方案曾补充 VFCS 握手、调整 VConsole 设备端口，并用 `GetMapName()` 回显确认地图；相关临时备份路径可能已清理。若另外部署该方案，需要自行确认其依赖、设备端口与实际工具定义，并避免与当前 `console.cjs` 同时占用 `29000`。

参考：[dota2-mcp 上游](https://github.com/Demon673/dota2-mcp)、[Dota 官方地形混合说明](https://www.dota2.com.cn/wiki/Dota_2_Workshop_Tools/Level_Design/Terrain_Blending.htm)、[Codex MCP 配置](https://learn.chatgpt.com/docs/extend/mcp?surface=cli)。
