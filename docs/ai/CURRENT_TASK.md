## 当前实施（2026-09-19）：双仓库清理与提交交付

- 用户授权清理 game/content 中可删除的非提交文件，并提交、推送必要改动。清理 5,043 个本地旧输出、日志、缓存和临时诊断文件（4,291,411,948 字节），以及 content 中 1,600 个本机美术快捷方式、2 个生成索引和编辑器历史。保留原始美术交接包、资源源码、运行资源和仍被构建器使用的输入。
- 当前主地图、C6 地图和布局配置继续保留；已认可参考图、实机图和最终验收摘要迁入 `art/maps/c6/`、`docs/ai/validation/20260919/`。历史章节中的临时 `output` 目录已清理，Git 合并备份引用和较早 stash 保留。
- content 的两张当前编辑地图使用 Git LFS。固定地形模板保存为 `maps/templates/c6_terrain_seed.vmap`，优化前 AI 测试基准迁入 fixture；地图生成和回归检查不再依赖已删除的临时快照。默认编译当前 Hammer 源图，只有显式 `-Generate` 才重建 C6。
- 清空缓存后 C6 生成成功，47 个练功房分组数量正确。后续提交检查与资源哈希结果见 `docs/ai/validation/20260919/repository-cleanup.json`；前一步合并的 23 次 UI 编译、68 个语法检查和 16 项回归结果已保留，本轮不重复游戏内验收。

## 历史实施（2026-09-19）：双仓库分支合并与最新 stash 恢复

- 用户要求解决 game/content 已有冲突并 pop stash。先备份冲突三方、工作区、索引和 stash 引用；完成 game `066cfb3a`、content `336e25c` 两个已有分支合并，再对每个仓库执行一次最新 stash pop。历史 stash 保留。
- 处理原有 31+1 个分支冲突及恢复 stash 后 13+1 个冲突。UI 根据合并后的作者源码重新编译，保留当前商店/HTTP/血条修正与新增建筑资源；任务记录合并保留。修复远端重复的 39 条波次预载定义，保留三个仍有效的本地回归测试。8 个旧编译日志只在本地保留。
- 主地图三方审计确认远端改动仅位于旧中央区域；保留最近认可的完整新中央版本。`template_map.vmap` 与 VPK 哈希与本轮之前验收记录完全一致，content 的 14 个 stash 文件全部恢复，game 的 65 个文件均恢复或语义合并，没有文件丢失。
- 23 次 UI 源资源编译、68 个变动 Lua/JS 语法检查、16 项回归通过，活动 UI 作者源与 content 同步检查无差异，两个索引无冲突且 diff --check 通过。城墙快速升级测试按新版第 25 级显示名修正，费用/等级/退款逻辑验收不变。恢复改动保留未提交，不执行远端推送。
- 备份与操作日志：`output/merge_resolution_20260919/`。两仓均有 `refs/codex-backup/merge-20260919/{head,merge,stash}`；最新 stash 处理完成后从 stash 列表移除，原始对象仍可从备份引用恢复。

## 历史实施（2026-09-19）：优化后的中央区域并入主地图

- 用户授权将已认可的中间模型并入主 map。本轮以默认主图 `template_map` 为目标，保持原有外围挑战/转生区与 64×64 Tile Grid，中央从 C6 的 `(-1024, 5376)` 平移到 `(-1024, 0)`。尺寸、四个回折入口、池水/外海、闭合树带、岩石和边缘草丛保持；4545 个中央实体、5 个网格已合入。
- 四个建造者出生点、四个出怪口保留原名迁移；新增 `config/map_layouts/template_map.lua`，同步实际建造范围和资源树坐标。60 个原外围标记及其实体内容逐个核对保持一致。原中央的展示快递模型设为 editorOnly。低面数藤蔓 292 个、中央低植被无阴影 3272 个均继承；之前的怪物 AI 优化代码未改。
- `tools/map_c6/compile-main.ps1` 已编译真实主图，82 项成功、0 失败。`map_c6_sanctuary_check` 和 `map_c6_seam_check` 支持两张图的中心坐标；新增 `map_main_merge_check`。实机 292+204+64=560 项检查全部通过，小地图通过原生 `dota_minimap_create` 同步生成。主图已在 Dota 2 近景显示。
- 新增 `launch_survival_main.cmd`，复用支持 `-MapName template_map` 的启动器；F7 和滚轮用于近景，预览减速 0.001。C6 源文件和 VPK 哈希未变。备份及最终记录在 `output/map_main_merge_20260919/verification.json`，编辑/编译说明在 `tools/map_c6/README.md`。不要在用户继续手工编辑后重新运行此次快照导入脚本。

## 历史实施（2026-09-19）：全部阶梯侧边与延伸平路的矮草

- 用户要求每组阶梯两侧的接缝加草遮盖，同时延伸到前后平路。新增 `tools/map_c6/stair-cover.cjs`，覆盖四组、12 段原生石阶，两侧每段各 12 丛；台阶前后平路边缘也补植，共 396 丛、7 种原生模型，最高约 38 单位。
- 新草叶只可搭入阶梯外侧 40 单位、上下平台外侧 24 单位，中间至少 304 单位视觉净空；384 阶梯原宽、地形和导航保持不变，建筑草地完全留空。原崖顶、崖边、崖脚植物与 47 间练功房保持原布局。
- `rock-surfaces.cjs` 支持完整模型路径与分轴缩放，检查实际台阶网格和遮挡岩石；本版新增植被 340 丛落在土壤上、56 丛落在最外侧石阶上；原生草采用绿色崖边材质组，全部无碰撞。备份、占地与每段覆盖检查、编译、实机图在 `output/map_stair_grass_20260919/`，以 `verification.json` 为最终状态。

- 最终 50 项编译、0 失败；602 项实机检查通过。新增 396 丛植物的完整占地共 8,316 次比较通过，原有地形、建筑区、树木、岩石及已认可植被保持一致。`detail_final.png` 为北侧阶梯实机近景；南侧默认视角被前景树冠遮挡，其旋转排布、实际 VMAP 参数及通行检查已核验。

## 历史实施（2026-09-19）：低过道崖脚的矮草与小植物

- 用户认可上一版原崖边衔接，要求在低过道与悬崖底部增加更小、像路边杂草的植被，并增加植物种类。新建 `tools/map_c6/verge-cover.cjs`，沿四向低路两侧、低位回折外沿布置 472 丛植物，混合 3 种细草、小蕨类、圆叶植物、2 种缩小灌木、少量野花和小蘑菇，共 9 种原生模型。
- 本机 Valve VPK 审计了 11 种候选模型与材质组，并在游戏中比较。选用植被最高约 30 单位，根部位于岩脚前方土壤内；允许草叶覆盖低路最外侧 24 单位，保持中间至少 400 单位视觉净空。448 路宽及导航不变，植物无碰撞，台阶、上平台和建筑空地完全留空。
- 通过独立生成模块与种子保留已认可的全部崖顶／原崖边植被、地形、岩石、树木和 47 间练功房。备份、原生资产审计、覆盖检查、编译与实机图在 `output/map_verge_20260919/`，以 `verification.json` 为最终状态；临时模型展示脚本已移除。
- 最终 48 项编译、0 失败，602 项实机检查通过；9,912 次新增植被完整占地比较通过，472 丛植物的实际 VMAP 参数均已核对。下方过道、正对岩壁与转角三处近景已保存。

## 历史实施（2026-09-19）：原崖边与草地交界的植被衔接

- 用户指出植物仍偏在石头一侧，需要向截图左侧的原悬崖边偏移，让叶片盖过草地与岩岸之间的硬边。`rock-cover.cjs` 将长过道后排从轴距约 342 调至 390（约 48 单位），台阶和转角同样向草地接缝调整，补齐池角折返的低灌木。
- 允许指定崖边叶片搭入建造草地最外侧不超过 48 单位；根部仍处于禁行带，所有植物无碰撞，过道、台阶、平台与池口严格保持净空。用户本轮要求修改了先前“叶片不得触及任何草地”的美术限制，地形与实际建造网格不变。移动后的植物根据实际原生岩面或地形重新落地。
- 岩岸植被现共 1,784 丛（净增 84），其中 408 丛为崖边衔接；旧裸坡灌木同步改用官方绿色／秋色材质组，去掉接缝的近黑斑块。备份、检查、编译与近景在 `output/map_rim_overlap_20260919/`，最终验收以 `verification.json` 为准。
- 最终 46 项编译无失败，602 项实机检查通过。37,464 次完整植物占地比较通过，四区分别有 48 丛叶片跨过草地边线且未超过 48 单位；实际 VMAP 中 2,240 丛植物的姿态、材质组及无碰撞属性核对通过。用户对应角度 `reference_final.png` 及另两处近景已保存。

## 历史实施（2026-09-19）：四向过道岩顶与岩面植被补全

- 用户近景指出旧灌木没有覆盖高起的岩顶和长过道侧壁。本轮增加 `tools/map_c6/rock-surfaces.cjs` 与 `rock-cover.cjs`，从本机 Valve 岩石可见网格获取实际表面位置，避免按地形高度摆放后埋进岩石。
- 四向长过道两侧采用双排冠层、五层交错岩面植被，延续至转角和台阶两侧。6 种原生植被共新增 1,700 丛；根部嵌入岩面 4–6 单位，完整模型包围盒避开全部可玩平面，无碰撞、不改变原有导航。实机对比材质组后，改用官方绿色／橙色 skin 1，崖顶少量粉花 skin 3，修正默认灌木叶片近黑的效果；临时材质样品已清除。原有裸坡地被继续保留。
- 所有建筑区、道路、岩石与地形保留，原 47 间练功房与圆岛林带不变。备份、检查、编译及实机图见 `output/map_lane_cover_20260919/`，最终结果以 `verification.json` 为准。
- 最终编译 46 项、0 失败；602 项实机检查通过，35,700 次植物完整占地与可玩平面比较通过。实际 VMAP 中的 1,700 丛植物位置、角度、材质组和无碰撞设置全部核对通过；四方向实机近景已保存。

## 历史实施（2026-09-18）：原生灌木与地被覆盖裸坡

- 用户要求直接用多种原生灌木覆盖裸露斜面，沿用当前地图风格，避免只用一种植物。新增 `tools/map_c6/slope-cover.cjs` 和 `plant-assets.json`，用 8 种原生模型混合灌木、蕨类、低草与常春藤，覆盖池岸、转角、长石岸和台阶边。
- `build.cjs` 的实体角度支持完整 qangle，原 yaw 调用保持原行为；灌木与地被随坡面倾斜、蕨类较直立，根部嵌入地面。按 Valve 模型真实旋转包围盒避开全部可玩平面，新增植物无碰撞；原地形、岩石、建筑区、47 间练功房、闭合树带和导航保留。
- 独立布局种子不改变原场景随机序列。备份、模型尺寸与哈希、实际 VMAP 植物姿态/区域检查、编译、实机验收和图片见 `output/map_slope_greenery_20260918/`，以 `verification.json` 为最终状态。

## 历史实施（2026-09-18）：台阶岩壁与崖顶自然衔接

- 用户要求处理台阶旁岩石与地面的突兀拼接、尖锐崖缘，允许石头稍高并在地面边缘增加石块，以符合现实中的支撑与分布。第一张图片路径不存在，已说明；第二张图片与实机位置足够推进。
- 新增 `tools/map_c6/cliff-banks.cjs`，用原生岩石真实包围盒限制每组占地，连续叠放内外台阶岩壁与低位转角，替换稀疏悬挂的细长岩块。每区 21 组岩群顶标高 422–459，草地为 384；直路崖顶加入小型半埋石，补齐长石岸与台阶侧壁间的小接头。四区旋转一致，岩石完整包围盒避开建筑区、通路、台阶及平台，原生导航阻挡不变。
- `sanctuary.cjs` 放缓外侧转角地形，`build-sanctuary.cjs` 将陡坡网格细化到 24 单位，补足转角轮廓。保留方池、1400 方形空地、1500 直路、低路与原生台阶、47 间练功房及闭合树带。
- 备份与验收在 `output/map_natural_cliffs_20260918/`，最终记录 `verification.json`。18 组模拟包含新增岩石完整包围盒与垂直叠合检查，修复检查发现的末层上移悬空问题。实机检查、编译与截图以最终记录为准。F7/F8/滚轮相机控制与纯 Dota 2 预览继续保留。

## 历史实施（2026-09-18）：池岸衔接、原生树材质与闭合林带

- 用户反馈中央池口与外围衔接不自然，怀疑树木不是官方材质，并要求整圈陆地外围以树木包裹。修改 `tools/map_c6/sanctuary.cjs`、`build-sanctuary.cjs`、`build.cjs`，新增 `shore.cjs`；保持四区 1400 方形空地、1200 方池、1500 通道、低路与转角台阶、原 47 间练功房。
- 池底与四个低路入口统一到 4，池口两侧低岸肩连至高地；岩块改为原生模型等比缩放、错落组合，替换拉伸后呈尖齿的摆放。外圆网格按完整多边界裁切，不再因单元中心筛选留下缺口。
- 外圈 176 棵树构成闭合树冠带，树干距可用地面最少约 205；辅以内圈树。中央树使用中性 rendercolor、原生材质组；模板全局光参数恢复。读取本机 Valve VPK 审计 4 个树模型、19 个材质变体及无同路径覆盖，确认预览高光开启；部分官方白花与雪叶材质本身无高光。
- 本次备份、16 组几何检查、编译、实机通路/建造/池岸支撑检查及图片在 `output/map_seams_canopy_20260918/`，最终验收以 `verification.json` 为准。陡坡禁行区不能用导航高度代替可见网格，新增 `map_c6_seam_check.lua` 用 `TraceLine` 检查岩面和 176 处树根地面支撑；保留最初诊断误报证据。原生导航阻挡采样不变，空地不新增装饰；F7/F8/滚轮预览控制保持。

## 历史实施（2026-09-18）：干净建造区、低位过道与回折台阶

- 用户要求去掉地面圆圈、清空建造空地的小物件，将点缀集中到边缘；用原生裸岩崖壁替代不自然斜坡，直过道降到水面附近，在拐弯处上台阶。四区统一实施，保留原 1400×1400 空地和 1200 方池。
- 直路高度 24，水面 16（8 单位防穿插）；A→B 长 1500。台阶位于原空地外侧，局部 x=2240..2624、y=64..704，三段爬升到高地 384；下平台和上平台保留平坦建造区域。
- 移除全部可见炮台圈、108 个庭院点缀和四个摆拍英雄；低点缀减少并退到距行走区至少 110 的边缘。原生悬崖模型覆盖岩面，修复陡面 UV 拉伸；原生 GridNav 阻挡保留对应入口路线。
- 本次备份、11 组几何检查、编译与实机验收在 `output/map_clean_cliffs_20260918/`，最终结果以 `verification.json` 为准。41 项编译无失败；106＋292＝398 项主实机检查通过。56 项补充脚印探测中 54 可建，另两项位于场上 Builder 占据的同一点，按预期返回 `unit_blocked`（详见 `occupancy.log`），没有地形错误。上一版记录留存；F7/F8 与滚轮控制延用。

## 历史实施（2026-09-18）：平缓树林与可操作近景

- 按用户要求取消树带额外山脊及内部大块山石，地面连续混合相邻高度，不超过庭院高度 384。保留原生 GridNav 禁行区挡怪，四个回折入口和建造平台保持可用；池岸石边匹配实际地面，补齐收边。
- `preview.json` 默认中近景距离 3200、对准东北玩家区；F7 近景 1800、F8 中央全景 6500、滚轮上下以 400 步长缩放（1200–8000），鼠标碰窗口边缘平移。F7/F8 均能回到固定区域。已检查 F6 为 Panorama Debugger 保留键，因此未用于预览。
- 通过 `window.ps1` 在真实 Dota 窗口发键/滚轮并检查相机数值；默认、F7/F8、上下滚轮、两端限位共 7 项通过。`build-preview.cjs` 生成原生 alias 档位并限制两端，修复 `incrementvar` 到极限后跳回另一端。启动器将鼠标移至窗口中央以防镜头自行漂移。隐藏所有辅助工具窗口，保留 0.001 模拟速度用于看图。
- 本次源地图与生成器备份、平整度/导航模拟、最终 362 项主实机检查、镜头控制验收及近远景图均在 `output/map_smooth_camera_20260918/`；最终记录 `verification.json`。禁行数据与修改前 36,864 点采样一致。

## 历史实施（2026-09-18）：拐角可建造、中央抬高及空地点缀

- 用户澄清：池塘四个斜角没有阶梯是正确的；不在斜角增加入口。中央过道由 128→256、庭院由 256→384，一级增量 128；四个正向入水口按抬高后的高差衔接。
- 实机确认旧版拐角中部可建，外沿部分点因坡度或导航无法建造。现将四个回折端外侧扩为 640×960 的平整平台，与庭院同高 384；两处外沿示意点支持 128×128 和 256×256 建筑占地。高差过渡改到拐角前方。1200 方池、1500 入口位移、1400×1400 空地和圆岛外径保持原设定。
- 空地加入原版零散石材、草叶与细化的草土混合，避开炮台带；测试真实建造许可，装饰不设置碰撞。`mesh.cjs` 增加有限数值坐标检查，避免无效高度传入地图转换器。
- 最终编译、362 项主实机检查（106 原检查＋256 中央/建造检查）、56 项建造前后探测与截图记录在 `output/map_refine_20260918/verification.json` 及同目录日志；改动前 VMAP/VPK/生成器在 `before/`。仍通过 `launch_survival_c6.cmd` 打开中央预览。

## 历史实施（2026-09-17）：09 回折入口与炮台带

- 用户选定 `09 回折入口`，明确四区都复制左下角的入口逻辑，并要求先修效果图、再直接按图建模。修正版已保存为 `output/map_folded_20260917/09_corrected.png`，使用内置 imagegen，提示词同目录 `image-prompt.txt`。
- 中央新布局由同一东→东北模板旋转四次生成；西→西南、南→东南、东→东北、北→西北均真正连接空地。中央水池 1200，水边 A→外侧 B 位移 1500，过道宽 448，四片空地各 1400×1400；半径 3072，过道地高 128、庭院 256，回折处连续抬升。
- 每区清出靠过道的 384 深炮台带，三个齐地石圈仅提示位置，没有预建炮台或占格。用低石沿和原生 GridNav 阻挡分隔过道，树石退到另一侧和外缘。普通波次 marker 放在 A，B 为对应玩家入口，玩家与资源树同步移入新庭院。
- 原 47 间练功房布局完全保留；新增几何模拟验证旋转、平地、128×128 炮台脚印和本区 B 端必经。实机仍使用原 106 项检查，并以更新的 `tests/map_c6_sanctuary_check.lua` 进行 128 项回折与真实建造许可检查。最终产物、实机截图、日志和校验信息见 `output/map_folded_20260917/verification.json`；改动前版本保存在该目录 `before/`。
- 源地图仍为 content 下的 `survival_c6.vmap`，编译后通过根目录 `launch_survival_c6.cmd` 直接预览，镜头距离 6500，保留仅显示 Dota 2 的窗口行为。详见 `tools/map_c6/README.md` 最新章节。

## 历史实施（2026-09-17）：中央方池与四向高地

- 用户已确认本版中央实机效果与布局作为基准，希望树木色彩更丰富。新增需求先做 10 张布局效果图供筛选：四个出怪点位于方池四边中点，再沿对应方向向外约 1500 到玩家区入口，保留原有空地面积并控制圆岛外扩。方案和独立原图保存在 `output/map_concepts_spawn1500_20260917/`，`index.html` 支持两图并排比较；此阶段未改动已确认的 VMAP/VPK。基准截图、地图与关键生成源文件另存于该目录 `approved_baseline/`。
- 最新中央参考：`output/map_sanctuary_20260917/approved_reference.png`。用户明确水池 1200×1200、四向空地轴向纵深约 1400；圆岛半径 2600，四条短坡道 256×448，四条对角水道全部替换成连续山脊与树林。练功房原分组和缩放比例保留。
- `tools/map_c6/sanctuary.cjs`、`build-sanctuary.cjs`、`mesh.cjs` 实现精确尺寸的可编辑网格、实际高差、原生材质混合、树石与花草。土地 128、山脊约 348、池底 4、统一原版河水高度 16。水池直接接入 Radiant Tile Grid 河道水，外围用原生黑色水下遮底形成深水观感。
- 实机迭代修正了巨大白色山石、树冠显示分组、多高度水面错误效果；保留原版资源。新增 `tests/map_c6_sanctuary_check.lua` 检查四向坡道、方池四角、阻挡与高差；最终记录见 `output/map_sanctuary_20260917/verification.json`。
- CMD 入口仍只显示 Dota 2，默认镜头改为中央。预览通过 `host_timescale 0.001` 减慢战斗，避免预览自动结束及暂停灰化；正常游玩需恢复 `host_timescale 1` 或重启游戏。详见 `tools/map_c6/README.md`。
- 本次改动前备份位于 `output/map_build_c6/before_sanctuary_20260917_153909/`；原 `template_map` 保留。美术为可运行的地形版本，不等同于概念图逐像素还原。

## 历史实施（2026-09-15）：C6 地图与原生地表精修

- 最新面积调整：中央 50%、普通练功房 70%、右下 10 间 30%，按面积换算边长，原分组与中心坐标保留。中央水面、入口、树带、出生点、资源树及建造边界同步缩放；减小房内装饰数量并保留水域间隔。新 VPK 编译 443 项、0 失败，冷启动通过 106 项点位/通路、34 处水域间隔、98 个挑战/转生锚点实机检查；记录 `output/map_build_c6/verification_resize.json`。新全景相机完整显示南部房间，仍只显示 Dota 2 预览窗口。
- CMD 入口 `launch_survival_c6.cmd` 已改为默认全图预览，隐藏 HUD/难度界面与工具窗口；新启动添加原生 `-noassetbrowser`。修复 Windows PowerShell 5.1 将普通 MCP stderr 日志当成 NativeCommandError 的问题：进程级独立重定向并按退出码判断，唯一 Lua 回显确认地图就绪。
- 新增独立 `survival_c6`，原生 128×128 Tile Grid；左侧 10＋3、四角各 4、右侧 4、右下 10，另保留参考图四个独立房间。中央四向玩家区围绕可行走的矩形浅水面。
- content 下保存可编辑 VMAP，插件内保存编译 VPK；复现与加载说明见 [地图说明](../../tools/map_c6/README.md)。
- 新增原生 Paint 混合图（草地、道路、踩踏地面与积雪过渡）、花草落叶与完整木栏，修正春花皮肤索引。最终 440 项资源编译、0 失败；通过 MCP 实机执行 106 项点位与水陆通路检查全部通过。新增全景与中央截图、精修前文件备份。
- 已手动安装并注册 `dota2-mcp@1.6.0`，修补 VFCS 握手并配置 VConsole 29001 自动连接，标准 MCP SDK 实测发送、读取和服务端 Lua 成功。当前会话通过 `tools/map_c6/mcp-client.cjs` 使用；`dota_status.running` 可能 unknown，需用 Lua 确认地图。详见地图说明，勿再同时直连 29000。
- 地图仍为可迭代的初版场景，独立天气、新增练功房玩法、景观细节和多人完整流程按后续需求继续。

## 当前新增（2026-09-17）：熔火核心挑战房间

- 按四张参考图制作 30 个自制组件、16 套颜色 / 法线 / 粗糙度 / 反射材质，组合 450 个实例、339476 三角面。玄武岩、焦痕石板、旧铜、暗铁、冷却熔岩和焦灰统一材质；按要求没有自发光、火焰、粒子或局部效果灯。
- 完整 Blender 场景与组件库、独立 Hammer 样板地图和可编辑预制件已生成、安装编译。预览 `output/molten_core_room/index.html`，源文件 `output/molten_core_room/molten_core_room.blend`。
- 编译模型方向、尺度、碰撞、材质输入和布局审计通过。实机入口 / 中央 / 内场导航采样通过，围墙及外侧熔岩槽样本不可行走；实际建造者完成入口、中央和四角之间六段路线，约 19.37 秒。
- 正式主地图与挑战配置未替换。保留挑战 07 现有 entry / home / boss_spawn 标记，另有十个参考刷怪点；传送、正式刷怪及掉落流程未联调。
- 详见 [MOLTEN_CORE_ROOM.md](MOLTEN_CORE_ROOM.md)，资源 / 实机报告位于 `output/molten_core_room/`。

## 上轮新增（2026-09-17）：十字主岛模块化样板

- 按四张主岛参考图制作 41 个自制组件、25 套材质、1689 个摆放实例；四方玩家平台、内岸通道、16 级阶梯、岩壁湿润水线、四色旗帜及樱树 / 原生松树组合。沿用金币练功房的组合材质流程。
- 完整 Blender 场景与组件库、独立 Hammer 地图和预制件已生成、安装编译。预览 `output/main_island/index.html`，源文件 `output/main_island/main_island.blend`。
- 41 个编译模型边界、材质、碰撞与布局审计通过。实机导航采样通过，实际建造者完成四方平台与中央水域之间 8 段路线，约 50.33 秒。
- 平台高 640、水面高 400，中央浅层支撑高 396；新场景中心在原点。正式主地图、CSV 及玩家 / 战斗绑定未替换；约 149 万自制三角面，未做正式多人性能测试。
- 详见 [MAIN_ISLAND.md](MAIN_ISLAND.md)，自动 / 实机报告与截图位于 `output/main_island/`。

## 上轮新增（2026-09-16）：金币练功房模块化样板

- 按四张概念与组件图制作 29 个自制模型，组合 599 个实例；石材、青铜、布料、植被等 15 套颜色 / 法线 / 反射贴图，原生松树复用。无发光、火焰或粒子。
- 完整 Blender 场景和组件库已打包贴图并打开；预览 `output/gold_training_room/index.html`。另有独立 Hammer 地图 `gold_training_room_review.vmap` 和 `maps/prefabs/gold_training_room.vmap`，599 个道具仍独立可编辑。
- 29 个编译模型方向、尺度、材质和碰撞审计通过。实机确认房间显示、入口 / 中央等样本可行走、墙边不可行走，实际建造者完成 900 码室内步行。修复了 FBX 导入轴转换、破损地砖被支撑面遮住和自定义地面缺少 `dota.nav.walkable` 的问题。
- 测试相机已释放并退出测试地图。未替换正式主地图或修改玩法 CSV，传送和刷怪预留十个现有命名标记；完整金币房玩法未联调。
- 详见 [GOLD_TRAINING_ROOM.md](GOLD_TRAINING_ROOM.md)，实际游戏截图 `output/gold_training_room/previews/runtime_complete.png`，自动 / 实机报告同目录。

## 上轮新增（2026-09-16）：城墙摧毁抖动与水晶爆炸

- 已接入真实城墙死亡事件：无阻挡代理抖动蓄光 1 秒，再播放白蓝闪光、扩散光环、44 片立体水晶碎片及爆裂音效；适配十阶模型的实际高度。
- 网格、人口、计数、阻挡立即释放。原有普通模式败北延至死亡后 1.45 秒，让爆炸先显示；结算前释放服务器句柄，有限粒子自然结束。未完成建筑和断线清理不播放，重复死亡防重放，地图重置取消延迟回调。
- 修复死亡建筑被 UI 恢复查询重新登记的问题。6 粒子、1 模型、3 材质编译通过，7 项相关 Lua 回归与编译资源审计通过。
- Workshop 确认十阶视觉与一级真实死亡流程：0.167 秒已释放建筑状态且代理可见，1.167 秒代理已消失而游戏仍进行，随后进入结算且表现/代理/该墙阻挡均为 0。测试相机已释放。未逐一实测全部 30 级死亡。
- 重建、测试边界、截图及报告见 [WALL_DESTRUCTION_EFFECT.md](WALL_DESTRUCTION_EFFECT.md)，资源与实机报告在 `output/wall_destruction/`。

## 上轮修正（2026-09-16）：城墙材质做旧与 2.5 倍高度

- 十阶城墙在网格端仅 Z 轴放大至初版 2.5 倍，保留 248 码宽度、4×4 格、实体比例 1 和 yaw=180。同步碰撞高度 295 码、三套选择盒和流光网格；实际编译尺寸与修改前清单逐款核对通过。
- 新增 `wall_surface_materials.py`：木纹沿每根木料长轴排列，端面年轮、木结、纵裂、褪色；石材有风化凹蚀、矿物色差，金属有氧化与划痕，墙脚有积灰苔痕。颜色、法线、粗糙度由同一表面痕迹烘焙，十阶做旧强度从 1.0 递减至 0.08，高阶石面更平整、金属更干净。
- 保持每款 2K 图集和原有面数，改善图集利用率，按 SurfaceUV 切线方向烘焙法线。已安装编译 10 材质、10 普通模型、10 流光外壳，30 级名称、经济数值与外观对应不变。
- 编译资源审计、20 份正常/流光 FBX 回导通过；直接解码 30 张运行时颜色/法线/反射贴图，排除 UV 填充区后确认均有实际表面变化。四项相关 Lua 回归通过（城墙配置、格子对齐、施工表现、流光外壳）。报告在 `output/reference_walls/verification.json`、`fbx_verification.json`、`surface_verification.json`。
- Workshop 分四批显示十阶模型，检查高度、材质与占地；实际一级城墙 PHYS 顶部为 295。第一批在准备阶段截图，后续截图含测试局结束提示，仅用于渲染检查，不宣称完整升级计时验收。清理确认 `WALL_V2_CLEANUP 0`，相机已释放。
- 新预览仍为 `output/reference_walls/index.html`，新版实机报告为 `runtime_verification.json`。原始高度与旧报告保留在 `before_height_weathering/`。重建和验证说明见 [REFERENCE_WALL_MODELS.md](REFERENCE_WALL_MODELS.md)。

## 上轮制作（2026-09-16）：十阶方垛城墙

- 按用户十张参考图制作原木、木石、青石、青铜、苍蓝、碧玉、赤铜、紫晶、白金、天辉晶冠城墙，共十款；30 个等级每三级换一个模型，名称统一为对应前缀加 `·Ⅰ / ·Ⅱ / ·Ⅲ`。
- 城墙保持 4×4 格（256 码）、现有 yaw=180，无新转向。模型最大宽度 248 码、比例 1.0，独立闭合碰撞体、root 权重与三套选择盒，十套 2K 颜色/法线/表面贴图。玩法数值及原有阻挡规则保留。
- CSV、生成配置、NPC 初始模型、预载目录和施工倍率同步；十款新增流光外壳接入现有从上到下揭幕，注册表共 34 款。原有 24 款建筑不重做。
- 十款编译资源及 FBX 回导审计、原有 24 款资源审计、14 项相关 Lua 回归通过。Workshop 分两批确认十款模型显示和网格尺寸；截图在 `output/reference_walls/runtime_01_05_fixed.png`、`runtime_06_10_visible.png`，后者实际选中建筑显示 `原木城墙·Ⅱ`。本轮未逐一实测全部等级升级/点击及完整流光计时，报告明确区分资源检查与实机范围。
- 展示道具已清理，相机已释放，控制台确认 `WALL_REVIEW_CLEANUP 0`。预览为 `output/reference_walls/index.html`，重建入口 `tools/build_reference_walls.py`、`tools/build_building_white_shells.py`、`tools/sync_reference_wall_config.py`、`tools/install_reference_walls.ps1`。详见 [REFERENCE_WALL_MODELS.md](REFERENCE_WALL_MODELS.md)。

## 上轮修正（2026-09-16）：彩色流光与从上到下揭幕

- 用户确认白色轮廓可见，但要求反光、彩色光带流动，以及屋顶到地面逐渐显现。24 个外壳改用原生 `hero.vfx`，加入连续的白/青蓝/淡金/淡紫光带、细微法线、高光、边缘光和部分自发光；颜色 UV 由原生时间表达式连续滚动。
- 外壳使用单独的 `_flow.fbx`，复制正常建筑的几何与 root 权重，仅重设高度 UV。正常模型、材质、朝南方向、模型端两倍、实体比例 1、四格占地和碰撞均保留。外壳没有 PHYS 和选择盒，不参与点选及寻路。
- 完成时显示最终建筑，外壳在 1.5 秒内切换 48 个揭幕阶段，独立 alpha UV 让柔和边界从屋顶移向地面；全局 alpha 保持 255，不再整栋一起淡出。各阶段共享颜色、法线与透明纹理，每栋只有一个特效实体。施工/升级、死亡/取消/重置沿用现有生命周期。
- 排查发现 `hero.vfx` 的 `F_DO_NOT_CAST_SHADOWS` 与 `F_TRANSLUCENT` 互斥，前者会让编译器丢掉透明遮罩。已移除该材质开关，保留实体级 `disableshadows=1`。实际运行纹理解码确认：低处 alpha=255、柔边 alpha=88、高处 alpha=0；颜色纹理有多色变化。
- 实机 `template_map` 三个并排主城分别展示全流光、揭幕中段、完整建筑。截图 `output/building_presentation/flow_unpaused_a.png` 中，中间屋顶已显现而墙脚仍被流光覆盖。相隔时间的截图显示光带变化；动态区域平均 RGB 差 19.24，正常模型对照 2.68。`flow_unpaused_b.png` 包含测试局结束界面，仅作为光带变化的辅助证据。清理确认 `FLOW_CLEANUP 0 0`，相机已释放。实机范围为主城三阶段材质，完整计时及升级切模/清理由回归覆盖；此次未把测试局结束后的计时探针当成实机通过。
- 13 项 Lua 回归、24 款外壳编译资源审计及 49 份材质检查通过。新增 `test_building_flow_material.ps1` 直接核验编译后透明开关、动态 UV 字节码、遮罩输入、各阶段偏移以及实际 VTex 像素，防止编译成功但遮罩失效。报告 `verification.json`、`white_shell_verification.json`、`flow_material_verification.json`、`flow_runtime_verification.json` 位于 `output/building_presentation/`。
- 重建：Python `build_building_flow_materials.py` → Blender 后台 `build_building_flow_meshes.py` → Python `build_building_white_shells.py` → PowerShell `install_building_flow.ps1`。只改材质用 `-MaterialsOnly`；只编译外壳用 `-ModelsOnly`；可传 `-ModelNames` 指定外壳。普通建筑 FBX 重建后须重建对应流光 FBX。旧纯白材质与两份粒子仅保留用于非参考模型兼容。

## 上轮修正（2026-09-16）：模型原生朝南与独立白光外壳

- 用户再次反馈施工只有血条、没有白光，以及建筑先朝东再转向。24 款 FBX 已在网格端烘入 -90° 旋转，Source 2 中实体 yaw=0 即朝世界南方（-Y）。44 个等级及预览统一 yaw=0，创建时立即设置配置比例和角度；保持模型端 2 倍、实体比例 1、2×2 四格占地。全量生成器同步采用该网格方向。
- 为 24 款模型分别编译 `_white_shell.vmdl`，复用同一朝南 FBX 和纯白全亮材质，无 PHYS、无选择盒。施工和升级使用独立 `prop_dynamic`，直接复制建筑世界 XYZ、比例与角度，不从隐藏单位的粒子控制点获取模型。完成时显示最终建筑，白色外壳在 0.9 秒内平滑淡出；取消、死亡、重置清理外壳。创建失败时恢复真实模型，避免再次只剩血条。旧粒子仅为非参考模型的兼容路径。
- 本轮已连上 Workshop 并运行 template_map。实际施工服务创建的主城白光可见、与建筑重合；淡出后正门朝南，前后实体角度均 `(0,0,0)`。实机采样 alpha 从 255 降至 246 / 106，1.1 秒时外壳数为 0。截图：`output/building_presentation/white_visible_final.png`、`south_visible_final.png`。早期后台截图停帧，未作为验收证据；前台的新截图已确认画面更新。实机验证范围为一级主城施工/显现，其余模型及升级后的模型匹配由资源审计和回归覆盖。
- 24 个正常模型、24 个白光模型编译通过；24 份 FBX 回导、44 级映射、碰撞与贴图检查通过；13 项表现回归通过。新增白光资源审计验证实际编译材质、与正常模型相同的网格边界、无物理与选择盒。报告 `output/building_presentation/verification.json`、`white_shell_verification.json`、`runtime_verification.json`。
- 重建顺序：`build_reference_buildings.py`（或对旧 FBX 使用幂等的 `bake_reference_building_facing.py`）→ `build_building_white_shells.py` → `install_unique_buildings.ps1 -ModelsOnly` → `sync_reference_building_config.py`。白光材质仍由 `build_building_warp_particles.py` / `install_building_presentation.ps1 -ParticlesOnly` 维护。

## 上轮修正（2026-09-16）：白光不可见的材质修复

- 用户反馈没有白光。直接解码上版运行时材质所引用的 VTex，测得像素为 RGBA `(0,1,0,255)`；上版 `TextureColor "[1 1 1 1]"` 没有生成预期的白色纹理。已确认资源本身有问题，不能归因于未重启 Workshop Tools。
- 改为生成并显式引用 8×8 不透明纯白纹理 `build_white_glow_color.png`，材质使用浮点 `g_flOpacityScale=1.0` 和 `g_flOverbrightFactor=3.0`。安装脚本先同步颜色贴图，再编译白光材质及两个粒子；粒子初始化失败现在输出路径和错误，避免静默失败。
- 新增 `tools/test_building_white_material.ps1`，检查编译后材质依赖并解码实际运行时纹理的每个像素。旧资源测试失败、新资源 RGBA 最小/最大值均为 `(255,255,255,255)`；已纳入 `tools/check_building_presentation.py`，与 12 项运行时回归一起通过。
- 证据：`output/building_presentation/white_material_before_fix.json`、`white_material_verification.json`、`verification.json`。Dota/vconsole 进程存在，但 MCP 未连接，未进行实机验收。需完整退出当前测试局和 Workshop Tools 后重新打开，确保旧材质缓存被清掉。

## 已完成修正（2026-09-16）：模型端放大两倍，白光褪去显现建筑

- 用户反馈四格版本外观太小，要求模型端直接两倍。已将 24 款 ModelDoc 的网格导入比例从 0.01 改为 0.02、物理导入从 1 改为 2，并将 72 组点选盒边界乘二。编译后网格最大宽度约 236 码；实体比例仍 1.0、朝南、逻辑占地仍 2×2。主城模型 PHYS 半径 96，寻路阻挡保留四格版本的 48。
- 用户要求替换闪烁的传送效果。当前为单个稳定白色建筑轮廓，完成后 0.9 秒平滑淡出，显露最终模型。新的全亮透明材质没有原传送材质的折射；停用循环光环、光柱、微粒和开始/结束爆闪。完成先应用模型，再绑定淡出效果，升级使用成功后的模型。
- 已编译 24 模型、2 粒子与 1 白光材质。编译后资源检查及 12 项回归通过；包含单一白光层、最终模型绑定、重复完成防重放和失败/取消清理。本轮 Dota 未连接，未宣称实机消除闪烁；需要新开一局确认。
- 仅调整模型端尺寸的重建入口为 `tools/reference_building_modeldoc.py` 和 `tools/install_unique_buildings.ps1 -ModelsOnly`；白光入口为 `tools/build_building_warp_particles.py` 和 `tools/install_building_presentation.ps1 -ParticlesOnly`。验证报告见 `output/unique_buildings/verification.json`、`output/building_presentation/verification.json`。

## 已完成修正（2026-09-16）：参考图建筑缩小为 2×2、共四格

- 用户反馈模型和占地过大，要求按四个格子安排。七类参考图建筑的 44 个等级统一从 5×5 改为 2×2（128 码），模型等比例从 2.5 改为 1.0，最大宽度由约 295 缩至 118 码；各轴为上一版的 40%。
- 同步权威 CSV、生成 Lua、NPC 初始比例、预载目录、施工比例及模型清单。主城阻挡半径按模型配置比例计算，当前从 120 缩至 48；选择盒和模型凸碰撞体随实体比例匹配，朝南和分级外观保持。
- 预览、提交、树木检测、相邻摆放、搬迁、恢复与释放均使用四格；传送光圈半径读取新占地，建筑虚影读取新比例。本轮无需重建网格、贴图或粒子资源。
- 12 项回归及 24 模型/44 等级资源审计通过，新增四格相邻摆放和占地外树木不阻挡的回归检查。报告 `output/building_presentation/verification.json`、`output/unique_buildings/verification.json`。需要重新开局加载；尚未实机验收本次尺寸。

## 已完成修正（2026-09-16）：按《福佑大乱斗》T 传送调整建筑表现

- 用户明确参考游戏为《福佑大乱斗》，效果为 T 传送。已对照 Bilibili `BV13H9PBAEUd` 的 74–81 秒画面，改为蓝白交叠光环、地面旋纹、轻光柱与建筑透明虚影。属于按画面适配，未验证参考游戏的原始脚本调用。
- 共 10 份自定义粒子，使用 Dota 原生纹理与传送虚影材质。虚影绑定建筑自身模型，并读取配置比例及朝南角度（度）；建造时显示虚影，完成显现，升级成功播放结束闪光。没有新增可选中或碰撞实体。
- 10 份资源重新编译、12 项回归通过；新增初始化朝向和模型绑定失败清理验证，保留完成/取消/死亡/重置时的立即销毁逻辑。报告 `output/building_presentation/verification.json`；仅重建粒子可用 `tools/install_building_presentation.ps1 -ParticlesOnly`。尚未连接实机，需要重新开局查看画面。

## 已完成修正（2026-09-16）：建筑朝南、5×5 占地与传送接入

- 用户认可第四版外观。本轮将七类参考图建筑的 44 个等级及预览统一设为绝对 yaw=-90，正门朝世界 -Y；占地由 2×2 改为 5×5（320 码），匹配约 295 码模型。
- 新增 `core/building_grid_geometry.lua` 处理奇数格半格居中；服务端建造、客户端预览、搬迁和恢复保持一致，全部 25 格检查地形、树木、占用。城墙和箭塔占地保持原值。
- 接入建造和升级的开始、持续、完成阶段；法阵按占地缩放，取消/死亡/重置清理持续特效。最初的青金色版本已由上方记录的《福佑大乱斗》蓝白传送表现替换。
- 12 项回归、客户端吸附、完整模块加载及 24 模型/44 等级资源审计通过；粒子与 Panorama 编译通过。报告 `output/building_presentation/verification.json`，重建入口 `tools/build_building_warp_particles.py`、`tools/install_building_presentation.ps1`。本轮尚未实机验收，需要新开一局查看效果。

## 历史制作（2026-09-16）：参考图建筑第四版、分级主城与 2.5 倍缩放

- 用户确认第三版能够点选。本次按提供图片制作主城五级、农场五级、金矿十种外观、炼金工坊、星象高塔、英雄祭坛、挑战建筑，合计 24 款、44 个玩法等级；金矿按用户确认每 3 个玩法等级更换一次外观。
- 全部采用亮石、青瓦、暖窗、深木与铜饰，2K 独立图集与法线；等比例 2.5 倍，去展示底板。保留 root 与选择盒，新增 24 个闭合凸碰撞体；主城运行时阻挡半径调整为 120。
- 农场与金矿的固定一级外观覆盖已改为逐等级解析。CSV、生成配置、NPC 初始外观与预载通过专用同步脚本维护。重建入口 `tools/build_reference_buildings.py`，资源验收入口 `tools/verify_reference_buildings.py`。
- 最终资源与验证状态查看 `output/unique_buildings/verification.json`、`runtime_verification.json` 和 `fbx_verification.json`。预览 `output/unique_buildings/index.html`；完整说明见 [UNIQUE_BUILDING_MODELS.md](UNIQUE_BUILDING_MODELS.md)。本版尚未实机确认光照、相邻建筑间距与点选手感。

## 历史制作（2026-09-16）：建筑第三版与鼠标点选修复

- 第二版用户实测无法点选：修正为根骨骼蒙皮与 `select_low` / `select_high` 选择盒。已在 Source 2 编译产物中检查实际骨骼和 hitbox 集合。
- 修正双 UV 导出风险，六款改为单一 BuildingAtlas 和独立 1024 像素烘焙贴图，核验编译材质确实启用并引用法线。去除展示底板，普通研究所改为炼金工坊，高级研究所改为三翼能量核心；保持玩法配置和占地兼容。
- 资源编译、FBX 回导、六款/39 等级模型合同与建筑外观服务检查通过。最终游戏内点选与美术效果待完全重启 Tools 后复测；不将编译产物检查标为实机验收。详见 [UNIQUE_BUILDING_MODELS.md](UNIQUE_BUILDING_MODELS.md)。

## 当前制作（2026-09-16）：建筑模型第二轮细化

- 六款建筑增加独立铺石、砌块、叠瓦、窗棂、矿车铁件、吊链、祭坛羽翼和角斗场看台；配套原创 512 像素颜色/法线/反射率贴图及 UV，沿用已有模型路径、124 码占地和缩放。
- 细化模块：`tools/unique_building_detail.py`；完整预览与源模型仍位于 `output/unique_buildings/`。本轮未改玩法配置；实机材质、选择和性能仍待 Workshop 验收。
- 第二轮六款模型、16 个材质及 48 张贴图已编译成功；资源/UV/占地检查、39 个等级模型检查、建筑外观服务和 21 个防御塔阶段回归通过。

## 当前制作（2026-09-15）：五类建筑独立模型

- 已原创制作并编译研究所、高级研究所、金矿、人口农场、英雄祭坛、挑战角斗场六款静态模型；配套材质、Blender 源文件、FBX、VMDL 与渲染预览位于 `output/unique_buildings/`。
- 已通过 CSV 权威源同步初始单位、施工缩放、39 个建筑等级与启动预载；经济与玩法字段检查不变。六款模型、39 个等级合同、现有建筑外观测试及 21 个防御塔阶段回归通过，Source 2 编译通过。
- 待完全重开 Workshop 局确认光照、点选、贴地、移动和升级表现。资源映射及重建步骤见 [UNIQUE_BUILDING_MODELS.md](UNIQUE_BUILDING_MODELS.md)，预览页为 `output/unique_buildings/index.html`。

## 当前修复（2026-09-09）：进入游戏出现原生选人界面

- 实机反馈上次修复后仍进入原生选人。进一步用真实模块加载入口复现 `asset_catalog duplicate asset_id: monster_wave_humanoid_red_axe`：合并后的四份生成资源配置重复包含 39 个资产、174 个组件、47 个特效及 5 个动作修饰，导致 modifier 注册过程中断、引擎 Activate/Precache 回调未定义。已调用现有 CSV 生成器定向重建四份文件，仅移除 265 条重复记录。
- 新增 `tools/check_addon_bootstrap.lua`，只模拟加载期间需要的引擎全局，真实 require 全部入口模块并验证启动参数及 Activate/Precache 回调。完整模块加载、39 个波次外观、25 个存档外观及 21 个塔阶段回归通过；仍待 Workshop Tools 完全停止后重新 Run 实机确认，不将离线加载测试视为进场验收。
- Lua 5.1 编译复现 `addon_game_mode.lua` 的 `initialize_services` 超过 60 个 upvalue，入口整体无法加载，文件顶部跳过选人及强制初始英雄规则无法执行。按原顺序拆分核心/UI 与玩法初始化，消除编译阻断。
- 移除建筑系统、建筑移动、三个建筑 modifier 和建筑闪烁技能共 6 个 Lua 文件的 UTF-8 BOM；不改变业务内容。
- 730 个 Lua 文件语法检查、`ADDON_LAUNCH_BOOTSTRAP_PASS` 和差异检查通过。启动回归测试编译完整入口，并确认业务模块加载前已设置自动指定不朽尸王及跳过选人、策略、展示阶段。
- 保留 CSV 的 60 秒联机准备等待；待完全停止并重新 Run 地图确认直接进场和建造者初始化。

## 当前实施（2026-09-06）：存档挑战 25 项英雄外观

- 已按用户清单接入虚空之影、秘法牢笼、12 项神兽狩猎及三项社交挑战；补入军团“孽龙之怒＋战鬼双刃”。
- 原战斗/奖励字段不变，补齐预载、默认英雄头像和尸体结束清理；资源映射与验证见 [ARCHIVE_MONSTER_COSMETICS.md](ARCHIVE_MONSTER_COSMETICS.md)。

## 当前修复（2026-09-06）：波次怪物死亡饰品与默认头像

- 死亡事件不再立即删除受尸体生命周期管理的英雄饰品；组件、皮肤和动作修饰保留至沉降结束，与主体隐藏同步清理。强制清场仍立即清理，提前失效的尸体也会释放组件。
- Panorama 默认头像白名单补入 monster_wave_，沿用资产声明的标准英雄与空 portrait_item_def；同步 content 源码并重新编译 combat_stats.vjs_c。
- 尸体生命周期（含事件顺序、提前移除、强制清场）、英雄饰品服务、饰品细节、39 项波次外观、波次资源生命周期、21 阶段塔回归通过，Lua 语法与 diff 检查通过。39 项波次头像元数据与前端白名单检查通过。
- 完整选中单位头像测试仍在既有“主宰红色至宝配置”断言失败；移除本次新增断言后同样失败。待实机确认英雄怪物死亡时饰品跟随骨骼，以及默认英雄头像构图。

## 当前修复（2026-09-06）：防御塔英雄外观回退

- 已确认英雄/饰品配置仍在；合并残留的 building_visual_service 原生载体分支会重新隐藏 Building，并在载体失败时回退旧模型。恢复为 Building 本体英雄模型 + prop_dynamic 世界组件，旧载体模块仅用于清理遗留实体和恢复可见性。
- 去掉 asset_catalog 的重复穿戴注册、闪电塔 LV1–5 重复行，以及 12 个重复预载单位定义；21 个塔代理按当前 CSV 重建，移除旧 AttachWearables，保留新波次怪物资源。攻击动作仅发送给真实 Building。
- 新增 test_tower_hero_visual_regression，旧服务可复现模型回退，修复后 21 阶段通过；建筑外观、死亡塔动画、首批饰品、39 项波次怪物测试及 21 阶段/98 穿戴/97 组件合同通过。配置生成、代理同步、Lua 语法验证通过。
- 待完全冷启动 Workshop Tools 后确认自定义英雄塔及饰品实际恢复。

## 当前实施任务（2026-09-06）：39 个波次怪物英雄外观

- 用户确认死亡冲刺对应 orc_longnose_small，帕吉套装为力士七兵；39 项均已完成配置和官方资源核验。
- 新增 39 个独立资产、174 个组件、47 个常驻粒子及 5 个动作修饰；补充怪物皮肤/动作/粒子生命周期，保留战斗字段及原有前五波中立怪规则。
- CSV 验证、七项 Lua 专项测试通过；既有波次集成测试的战斗属性断言失败可在修改前配置复现。待完全冷启动实机验收。
- 映射、实现与验证详见 [WAVE_MONSTER_COSMETICS.md](WAVE_MONSTER_COSMETICS.md)。

## 当前修复（2026-09-06）：防御塔英雄外观回退

- 已确认英雄/饰品配置仍在；合并残留的 building_visual_service 原生载体分支会重新隐藏 Building，并在载体失败时回退旧模型。恢复为 Building 本体英雄模型 + prop_dynamic 世界组件，旧载体模块仅用于清理遗留实体和恢复可见性。
- 去掉 asset_catalog 的重复穿戴注册、闪电塔 LV1–5 重复行，以及 12 个重复预载单位定义；21 个塔代理按当前 CSV 重建，移除旧 AttachWearables，保留新波次怪物资源。攻击动作仅发送给真实 Building。
- 新增 test_tower_hero_visual_regression，旧服务可复现模型回退，修复后 21 阶段通过；建筑外观、死亡塔动画、首批饰品、39 项波次怪物测试及 21 阶段/98 穿戴/97 组件合同通过。配置生成、代理同步、Lua 语法验证通过。
- 待完全冷启动 Workshop Tools 后确认自定义英雄塔及饰品实际恢复。

## 当前实施任务（2026-09-06）：39 个波次怪物英雄外观

- 用户确认死亡冲刺对应 orc_longnose_small，帕吉套装为力士七兵；39 项均已完成配置和官方资源核验。
- 新增 39 个独立资产、174 个组件、47 个常驻粒子及 5 个动作修饰；补充怪物皮肤/动作/粒子生命周期，保留战斗字段及原有前五波中立怪规则。
- CSV 验证、七项 Lua 专项测试通过；既有波次集成测试的战斗属性断言失败可在修改前配置复现。待完全冷启动实机验收。
- 映射、实现与验证详见 [WAVE_MONSTER_COSMETICS.md](WAVE_MONSTER_COSMETICS.md)。

## 当前实施任务补充（2026-09-02）：主宰原生饰品叠加的架构修复

- 对比成功的防御塔 `model_appearance_service` 后确认差异：防御塔通过全局实体表按 owner 管理 `prop_dynamic` 组件；英雄 `ReplaceHeroWithNoTransfer` 会让 Valve 原生 `dota_item_wearable` 在不同引擎路径下脱离 `FirstMoveChild/NextMovePeer`，仅遍历子节点因此漏隐藏，导致主宰自定义饰品与基础饰品叠加。
- `hero_cosmetic_service` 现在保留子节点/GetChildren 去重遍历，并新增 `Entities.FindAllByClassname/FindByClassname` 的 owner/parent 扫描，只对属于当前英雄且不在自定义组件集合中的 `dota_item_wearable` 应用 `SetRenderAlpha(0)`、`AddNoDraw` 和 `EF_NODRAW`；恢复路径同步撤销三种隐藏状态。
- 换模后隐藏继续在 `SetModel/SetOriginalModel` 完成后执行，并增加 0.10/0.35/0.80 秒三次 generation 保护补偿，覆盖 ReplaceHero 异步生成原生 wearable 的时间窗；不隐藏真实英雄实体，不改变英雄技能、数值、头像或选择架构。
- 隐藏 pass 现在记录 `child/global/owner_match/hidden/unmatched_models` 诊断字段，可直接区分“全局扫描未识别 owner”与“换模后晚到的 wearable”；该日志只发生在饰品应用及三次补偿检查，不参与游戏逻辑。
- 用户实机日志已确认四次 pass 均为 `child=0 global=0 owner_match=0 hidden=0`。因此主宰当前叠加的基础部件不是实体归属或延迟生成问题，而是 `juggernaut_arcana.vmdl` 自身的内置网格；继续增加隐藏重试不会改变结果。下一步若要彻底拆除，只能验证该模型是否暴露可控 bodygroup，或改用可拆分的主体资源/自定义模型。
- 已通过英雄饰品服务、选中单位头像和目标 Lua 语法测试；需 Workshop Tools 冷启动重新召唤主宰确认基础头/手/背/腿/武器不再叠加，同时确认自定义五个 `prop_dynamic` 组件仍可见并随骨骼同步。

## 当前实施任务补充（2026-09-02）：主宰“剑心之遗·起源”混搭饰品

- 主宰世界主体改为 `models/heroes/juggernaut/juggernaut_arcana.vmdl`，明确使用官方 `style 1 / skin 1` 红色“起源”版本，并添加 `arcana`、`arcana_style`、`red` 三个官方动作修饰。
- 隐藏 ReplaceHero 生成的默认穿戴，确定性挂载远古流犯头、手、背、腿的四个 Arcana 兼容模型，以及古卷之剑坎图沙（ItemDef `4101`）；这些世界组件按 `prop_dynamic + bone_merge` 创建，避免被英雄原生 wearable 链吞掉。同时挂载红色 Arcana 主体、远古流犯与坎图沙的六个官方常驻粒子，坎图沙剑光 CP0 按官方定义跟随 `attach_sword`。没有使用远古流犯武器或守卫。
- 原生穿戴隐藏同时遍历 `FirstMoveChild/NextMovePeer` 与 `GetChildren()`，按 entindex 去重，只对 `dota_item_wearable` 原生件调用项目已验证的 `AddNoDraw()`（并保留 `EF_NODRAW` 回退）；隐藏动作在 `SetModel/SetOriginalModel` 完成后执行，并在引擎可能异步重建 wearable 的 0.10 秒窗口后按 generation 再补一次，避免主体换模重新暴露默认件；主宰五个自定义 `prop_dynamic` 不会被误隐藏。
- 世界与头像继续分离：仅主宰永久英雄资产额外开放现有自定义 ScenePanel，传入 `npc_dota_hero_juggernaut` 且 `portrait_item_def` 为空，因而 HUD 仍显示标准主宰基础头像；其他普通英雄的原生头像路径不变。
- 自动验证通过 `ASSET_BUNDLE_CONFIG_PASS`、`SELECTED_UNIT_COSMETIC_PORTRAIT_PASS`、`COMBAT_STAT_PROJECTION_PASS`、`BLADEMASTER_PROP_DYNAMIC_CONTRACT_PASS`、目标 Lua 语法、CSV 数量/样式合同，以及 12 个模型/粒子 VPK 路径存在性；`combat_stats.js` 经 Resource Compiler 强制编译为 `1 compiled, 0 failed, 0 skipped`。当前机器没有可用 Python 解释器，故四个本次受影响的生成 Lua 按生成器格式同步更新；仍需 Workshop Tools 完全冷启动确认红色材质、骨骼、剑光、动作和基础头像。

## 当前实施任务补充（2026-09-02）：Boss 非挑战状态 idle 动画恢复

- 实机确认 20 个 Boss 在未进入挑战/待机时主体保持静态。根因是通用 `npc_survival_wave_monster` 在 `SetModel` 换成英雄主体后，部分引擎路径不会自动重启动画图；原先饰品组件的 `DefaultAnim` 不能保证主体同步进入循环 idle。
- `monster_hero_visual_service.apply()` 在 Bundle 成功应用后，对主体和所有 `prop_dynamic + bone_merge` 组件按声明序列依次尝试 `ResetSequenceInfo`、`ResetSequence`、`SetSequence`、`SetAnimation` 并恢复播放速率（best-effort API 回退），默认序列为 `idle`。不改变攻击/移动 AI、战斗数值、挑战流程或资源表。
- `monster_visual_config/service`、Boss 饰品合同、Lua 语法及限定 `git diff --check` 通过；仍需 Workshop Tools 冷启动观察非挑战待机、移动、攻击、死亡重建和饰品骨骼同步。

## 当前实施任务（2026-09-02）：第一批转生与十宗罪 Boss 英雄饰品

- 将 `rebirth_boss_01..10` 的世界主体依次调整为 Undying、Bloodseeker、Dragon Knight、Sven、Bane、Lifestealer、Dark Willow、Grimstroke、Spectre、Doom，并应用失落战矛方阵、血锻狂怒、银龙之祭、暴风之锻裁决者、盛夏传世无休折磨、黑曜恶行、邪魅仙娘、收割者哀歌、幽鬼现世和黑暗预言的黎明。
- 将 `ten_sin_01..10` 的世界主体依次调整为 Necrophos、Riki、Alchemist、Morphling、Ursa、Pudge、Wraith King、Rubick、Queen of Pain、Mars，并应用鼠神、呼啸荒野的渴望、药剂之君混搭、Crown/Blade of Tears、邪魇盛宴、千劫神屠、The One True King、虚幻之境的化身、魔廷新尊和绝世。炼金术士只保留药剂之君的五个非冲突槽位，武器由永世之辉耀（ItemDef `7627`）替换、手臂由拉泽尔的迈达斯指套（ItemDef `9568`）替换，避免同槽重复挂载。
- 沿用怪物默认穿戴链：每个 Boss 使用独立 `monster_boss_*` Bundle，主体写入 `monster_archetypes.csv`，饰品以 `prop_dynamic + bone_merge` 挂到实际怪物；`portrait_unit_name` 显式指向对应标准英雄单位、`portrait_item_def` 保持为空，由独立 ScenePanel 渲染基础头像，世界饰品不会污染头像。未修改生命、攻击、护甲、攻速、移动/攻击类型、技能、波次、挑战或奖励字段。
- 本批次新增 20 个 Bundle、94 个世界组件和 39 个官方常驻粒子；20 个异步代理同时预载主体、组件与粒子。四个依赖特殊主体的至宝（幽鬼、屠夫、冥魂大帝、痛苦女王）使用官方 Arcana body，其他使用对应英雄原生主体；没有可挂载 humanoid 模型的变龙/墓碑等变身物品不伪造世界组件。
- 已验证 153 个去重后的主体/组件/粒子路径全部存在于本机 Dota VPK 索引；全量 CSV 生成器成功，Boss 同步 `--check`、怪物穿戴合同和 AssetBundle 测试通过。`test_wave_monster_visual_integration.lua` 仍在既有生命值断言处失败，与本次饰品配置无关，未为本任务改动。仍需 Workshop Tools 完全冷启动逐个确认骨骼对齐、Arcana 主体动画、常驻粒子、死亡清理、重复生成和 Valve 原生头像。

## 当前实施任务（2026-09-01）：第一批防御塔英雄饰品扩展

- 用户已实机确认死亡路线第一阶段圣堂刺客“暗刃高手”四件套穿戴成功且头像未变化；本轮沿用同一 `原 Building 英雄主体 + prop_dynamic/bone_merge 世界组件 + 独立无饰品头像` 方案扩展另外八个阶段，不修改塔数值、技能、弹道、资源 ID 或 Panorama。
- 死亡路线：第二阶段 Wraith King 使用 Tyrant of the Veil（异界暴君，bundle `29143`）六件套，ItemDef `28604/28626/28628/28629/28630/28631`；第三阶段 Phantom Assassin 使用 Gothic Whisper（蛮夷低语，bundle `21417`）五件套，ItemDef `13476-13480`。
- 冰霜路线：第一阶段 Lich 使用 Ascendance of the Rime Lord（雾凇领主的霜威，bundle `21273`）五件套，ItemDef `9560/9561/12636/12637/12638`；第二阶段 Crystal Maiden 使用 Roost of the Winter Raven（冬鸦之巢，bundle `27600`），采用官方 Arcana 主体、五个 Winter Raven 组件及 Frost Avalanche refit 背部共六组件；第三阶段 Ancient Apparition 使用 Apocalypse Unbound（释放天启，bundle `21508`）四件套，ItemDef `14162-14165`。
- 闪电路线：第一阶段 Zeus 使用官方 Arcana 主体与 Tempest Helm of the Thundergod（雷霆神盔，ItemDef `6914`；捆绑中的 Bare Arms/Chest 是 invisiblebox，不投影为世界组件）；第二阶段 Leshrac 使用 Fruits of Wane（衰亡硕果，bundle `21518`）五件套，ItemDef `14212-14216`；第三阶段 Razor 使用官方 Arcana 主体与 Voidstorm Asylum（太虚风暴玄宇，bundle `23100`）五件套，ItemDef `23095-23099`，Armor/Belt 使用 items_game 指定的 refit 模型。
- 官方 `particle_create` 常驻粒子已按完整 wearable component ID 绑定：异界暴君 3 个、蛮夷低语 4 个、冬鸦之巢 3 个、释放天启 4 个、太虚风暴玄宇 3 个；Lich、Zeus、Leshrac未虚构额外常驻粒子。八个主体、37 个世界组件及 18 个相关常驻粒子（含 Ancient Apparition 原有 Ice Vortex）均已在本机 VPK 索引确认存在。当前合同总量为 21 个阶段、98 条穿戴声明和 97 个有效世界组件；全资源表为 154 个组件、128 条特效。
- 所有阶段继续只设置 `portrait_unit_name`，`portrait_item_def` 全部为空；Arcana 主体只用于世界模型，不向自定义 ScenePanel 传入饰品 ItemDef。自动验证通过：生成器 `--check`、21 阶段投影合同、第一批精确 ItemDef/头像/粒子 owner 专项测试、AssetBundle、FrostRoute、Death/Multi Visual、BuildingVisualService、AssetPreloadService、SelectedUnitCosmeticPortrait 和全部新增 VPK 路径存在性。仍需 Workshop Tools 完全冷启动逐阶段确认骨骼对齐、refit 部件、常驻粒子、攻击/待机动作、升级重建及头像保持原样。

## 当前实施任务（2026-09-02）：主宰“尊享·剑心之遗”二阶段 3D 头像

- 用户要求主宰（Juggernaut）在穿戴“尊享·剑心之遗（Bladeform Legacy）”后，小头像同时显示主体和五件 3D 饰品，并使用二阶段 Origins 外观。
- `asset_catalog.csv`、`asset_components.csv`、`asset_effects.csv` 与 `hero_cosmetics_config.lua` 已切换到 `juggernaut_arcana.vmdl`、四件 armor_for_the_favorite 部件和 Katz 武器（`skin=1`），保留 Arcana 常驻/出生特效与 `arcana` 动作修饰器；生成配置已同步。
- Panorama 新增仅针对 `hero_permanent_hero_blademaster + npc_dota_hero_juggernaut` 的独立 Scene overlay，挂载到原生头像同层并隐藏原生像素，其他英雄/单位继续使用 Valve 原生头像。
- 追加修复 `ui_request_router.apply_portrait_metadata` 的资源白名单：原逻辑只允许 21 个原生塔穿戴阶段发布头像元数据，会把永久英雄的主宰资源清空；现在仅额外放行 `hero_permanent_hero_blademaster`，避免其他英雄误进入自定义头像链。
- 由于既有 ISSUE-007 记录显示 `portrait_world_unit` 在当前运行时可能找不到实体并黑屏，曾制作静态 `prop_dynamic` 主体 + 五个 `bone_merge` 饰品场景并修正官方 `debut_camera` 挂点；实机截图显示该自制相机仍不适合主宰构图，因此当前 Panorama 改用 Dota 自带 `backgrounds/hero_showcase_juggernaut_arcana` 场景，优先使用官方主宰相机和模型构图。自制 v3 地图包保留作后续备用。
- 自动验证通过：英雄饰品 Lua 行为测试（5 组件、4 出生特效、武器二阶段材质）、全项目 Lua 5.1 语法（496 文件）、VMAP 资源编译（7 compiled, 0 failed）和 Panorama 强制编译（9 compiled, 0 failed）。仍需 Workshop Tools 冷启动进入游戏确认模型骨骼对齐、相机裁切、特效可见性及小头像切换恢复。

## 当前实施任务（2026-09-02）：知识之书增加三围后的英雄生命投影修复

- 修复知识之书/超级知识之书触发全属性重算后，英雄最大生命增加但当前生命仍停留在购买前数值，导致生命百分比下降的问题。
- 根因是 `hero_combat_stat_service.recalculate()` 在属性健康投影完成后，仍用重算前的旧当前生命调用 `hero_health_guard.protect_value()`，把合法的生命增加误判为引擎回填并回退。
- 现改为按城墙升级同一语义计算：保留重算前的绝对缺失生命值；满血英雄随最大生命增加保持满血，受伤英雄保持相同缺失生命值。若引擎重算暂时未补足当前生命，会在最终保护前恢复预期值。
- 新增 `tools/test_hero_health_guard.lua` 覆盖满血、受伤、低血、无变化和最大生命下降场景。登记的 Lua 5.1 编译器路径失效，但本机备用路径可用，已完成项目语法、行为测试与 `git diff --check`；仍需 Workshop Tools 冷启动确认实际血条百分比和数值。

## 当前实施任务（2026-09-01）：死亡之塔“暗刃高手”世界饰品试装

- 用户要求仅替换死亡路线第一阶段“死亡之塔”的世界模型饰品，观察英雄主体塔能否使用圣堂刺客“暗刃高手（Darkblade Adept）”套装；头像不得随饰品变化。主体仍为 `models/heroes/lanaya/lanaya.vmdl`，不修改塔数值、技能、弹道或阶段路由。
- `asset_native_wearables.csv` 已将该阶段的三件默认饰品替换为本机 `items_game.txt` 核对过的四件套：护甲 ItemDef `28624`、头部 `28735`、肩部 `28736`、武器 `28738`。世界显示继续由原 Building 上的四个 `prop_dynamic + bone_merge` 组件完成；bundle ItemDef `29158` 仅作为套装身份核对证据，不写入运行时或头像配置。
- 套装的肩部、肩后辉光和武器三个官方常驻粒子已进入 `asset_effects.csv`，分别绑定对应世界组件；四个模型和三个粒子均已在本机 Dota VPK 资源索引确认存在，并进入初始预载/代理预缓存。当前合同总量为 21 个阶段、95 条穿戴声明和 94 个有效世界组件。
- 头像链保持独立：`portrait_unit_name=npc_dota_hero_templar_assassin`，`portrait_item_def` 为空，没有改动 Panorama 文件或 `DOTAScenePanel.SetUnit` 参数。因此本次只改变世界中的死亡之塔外观，不会主动更换头像饰品。
- 自动验证通过：塔穿戴投影合同与 `--check`、AssetBundle、DeathTowerTemplarVisual、TowerMultiVisual、BuildingVisualService、AssetPreloadService、SelectedUnitCosmeticPortrait、资源索引存在性和限定 `git diff --check`。仍需 Workshop Tools 完全冷启动，实机确认四件套骨骼对齐、攻击/待机动作、三个常驻粒子位置、升级/重复生成清理，以及头像确实保持原样。

## 当前实施任务（2026-08-31）：怪物默认英雄穿戴 CSV 与正式波次精确预载收口

- 已严格核对 `building_challenge_definitions.csv`、`asset_catalog.csv`、`asset_components.csv` 和 `monster_archetypes.csv`：有效数据行分别为 20、27、15、26 列，默认穿戴资源 ID 只位于各自表头的最后字段；五套默认穿戴资产的组件均为 `prop_dynamic` + `bone_merge`，资产行不再重复填写 `attachment_models`。
- 已补齐生成器的目标 CSV 行宽拒绝校验和默认穿戴引用校验：缺失资产、模型不匹配、错误 `load_group`、主体/组件重复表达、组件类型或挂载模式错误都会在生成前失败；四个受影响生成 Lua 已按 CSV 定向重生成。
- `asset_preload_service.resources_for_assets()` 现在按精确 `asset_id` 展开主体、组件、粒子和音效，并让所有子资源保留所属资产身份；正式波次 W6-W30 从当前波次原型收集 `default_wearable_asset_id` 后与模型/视觉资源合并进入同一预载队列，W1-W5 保持中性视觉排除。
- 自动验证通过：默认穿戴 Python 合同、精确默认穿戴预载、MonsterHeroVisual、AssetBundle、基础 AssetPreload、urgent 并行预载、波次模型生命周期、挑战预载/视觉服务、目标 Lua 5.1 语法、严格 UTF-8/BOM/CSV 行宽和 `git diff --check`。无关的 `test_challenge_monster_visual_config.lua` 旧射程断言与 `test_wave_monster_visual_integration.lua` 旧护甲断言未被本任务改动。
- 生成器全量输出中的无关 churn 已恢复；四个任务产物和用户既有的 `builder_definitions.lua` 变更保留。仍需 Workshop Tools 冷启动验证预载错误、穿戴骨骼对齐/动画、重复生成和所有清理路径；自动合同或 Lua 模拟不等于引擎实机验收。

## 当前实施任务（2026-08-30）：原 Building 世界外观与 21 阶段组件恢复

- Portrait 全局污染修复：普通单位、英雄和怪物现在完全沿用 Valve 原生 Portrait；仅 CSV 投影出的 21 个 `tower_*` 阶段启用独立 `SurvivalTowerPortraitOverlay` / `SurvivalTowerPortraitScene`，并调用 `portrait_unit_name -> DOTAScenePanel.SetUnit(...)`。移除了普通英雄的 Movie/Image 自定义运行时和隐藏旧 ScenePanel，不修改世界模型方案。
- 根因是旧 Portrait 逻辑把 Monkey King/Juggernaut 也纳入自定义分支，并且 `officialPortraitPanel()` 找不到视觉子节点时可能回退到共享 `PortraitGroup`，随后单一全局状态把共享节点设为 `opacity=0.01`；Valve 选择切换/重建后该值无法可靠恢复，造成所有单位头像继承分辨率/清晰度异常。
- 现已禁止 `PortraitGroup` 作为 opacity 目标；塔显示期间只把实际原生 `DOTAScenePanel` 视觉叶节点设为 `opacity=0`，并按节点记录原值，在塔切换、普通单位切换、重建和上下文关闭时恢复。塔专用 overlay 会临时挂到该原生 Scene 的直接父容器、排在原生 Scene 之后并继承其 `z-index`，从而与原生画像处于同一 HUD 层；隐藏时收回 XML 宿主，避免热重载遗留游离面板。仍保留对旧版本精确 `0.01` 残留的清理，不改原生尺寸、transform 或全局 UI scale。塔 overlay 保持完整矩形、局部 `overflow: clip` 和不透明底层遮罩；旧版`0.80`缩放保持移除，当前仅塔Scene内容采用独立`0.90`构图缩放。
- 箭塔选择过渡不再调用完整隐藏后短暂恢复原生 Scene。客户端按稳定单位名 `building_arrow_tower` 或所有塔阶段共有的 `ability_destroy_arrow_tower` 立即识别目标；新快照等待期间保持原生 Scene `opacity=0`、折叠自定义 Scene 内容并显示现有不透明 overlay 背景，快照到达后直接 `SetUnit` 显示新塔。普通英雄/单位仍在确认不是箭塔时恢复 Valve 原生画像，不新增轮询或全局永久遮罩。
- 同一箭塔实体重复选择时严格按 `entindex + 当前权威快照 + portraitKey` 做身份短路，不再折叠或重显自定义 Scene、不进入过渡遮罩，也不重复调用 `SetUnit`。原生锚点、可见性或透明度的瞬时变化不得把同一实体误判为画像切换；0.10 秒既有哨兵独立负责几何与 Valve HUD 重建自愈。现有 `activePortraitKey` 继续保证相同画像资产不重置 Scene。可见的 `DOTAScenePanel` 仍由引擎逐帧绘制，因此该优化降低的是重复状态切换和 Scene 重置成本，不宣称停止 GPU 帧渲染。
- 本轮自动验证：`SELECTED_UNIT_COSMETIC_PORTRAIT_PASS`、`NATIVE_PORTRAIT_RUNTIME_CONTRACT_PASS`、HUD XML 单一 `DOTAScenePanel` 解析、目标 Panorama JS/CSS/XML 强制编译和 UTF-8/diff 检查通过；尚需 Workshop Tools 冷启动确认普通单位清晰度、塔黑边及切换后 opacity 的最终实机表现。
- 用户已确认当前版本达到阶段性满意状态，以上 Portrait 隔离方案和自动验证结果作为当前基线记录；Workshop Tools 冷启动实机验证仍保留为后续事项，不将其等同于已完成的实机验收。

- 本轮目标是让21个Stage由原Building承载英雄主体、骨骼、选择、移动和攻击；`asset_native_wearable_stages.csv`与`asset_native_wearables.csv`仍是阶段/穿戴数据源，93条有效模型记录投影到`asset_components.csv`，运行时统一生成`prop_dynamic`并执行`SetOwner(Building) -> FollowEntity(Building, true)`。
- `async_unit_name`和代理KV只承担主体与穿戴模型预载，不参与世界显示；历史`native_wearable_carrier_service.lua`仅保留为兼容测试文件，生产路径不再引用独立carrier。Io的模型空记录合法地生成零组件。
- `model_appearance_service`按Building对象、组件签名和实体marker复用/恢复组件；阶段替换先完整创建新组件，成功后再清理旧组件，失败保留旧完整外观。死亡、融合、清理和热重载会移除组件及残留旧carrier，不改变Building业务实体。
- Portrait身份继续使用`portrait_unit_name -> DOTAScenePanel.SetUnit(portraitUnit, "default", false)`；塔专用Scene内容按用户确认的`0.90`基线从中心缩放，overlay矩形、裁切、角标、单位名和原生Portrait不缩放。覆盖层显示时将实际原生 Scene 透明度可逆设为 `0`，并把自定义 Scene overlay 挂到同一直接父层；隐藏、普通单位切换和上下文重载时恢复原生透明度、收回 overlay 并清除Scene inline transform。
- 已完成：TA及21阶段CSV投影、原Building主体/攻击/移动解绑、组件服务事务与live恢复、Io零组件、Stage/Bundle/Building/Portrait契约同步。
- 自动验证：`HERO_BODY_STAGE_CONTRACT_PASS stages=21 wearables=94 components=93`、`ASSET_BUNDLE_CONFIG_PASS`、`BUILDING_VISUAL_SERVICE_PASS`、`ASSET_PRELOAD_SERVICE_PASS`、`DEATH_TOWER_ANIMATION_CONTRACT_PASS`、`NATIVE_WEARABLE_CARRIER_SERVICE_PASS`兼容夹具、Portrait合同、目标Lua 5.1（BOM剥离副本）和`build_tower_native_wearable_units.py --check`通过；`combat_stats.js`经Resource Compiler强制编译为`1 compiled, 0 failed, 0 skipped`，生产代码carrier引用扫描和`git diff --check`通过。完整配置CheckOnly仍被既有无关`rogue_reward_effects.lua`的单个U+FFFD阻断；尚需Workshop Tools冷启动实机验证。

## 当前实施任务（2026-08-29）：玩家建墙期限与断线判负

- 用户要求限定修改：开局后 150 秒内未建造城墙的参与玩家直接判负并停止其后续出怪；断线玩家保留 20 秒恢复窗口，超过 20 秒判负；若断线 20 秒内其已完工城墙被摧毁，也立即判负。
- 150 秒期限复用 `wave_timing_config.initial_delay_seconds`，其权威值来自 `data/csv/怪物与波次系统/wave_timing_rules.csv`，本轮不修改 CSV 或生成配置。
- 判负状态在 `multiplayer_player_service` 中幂等维护；判负后复用既有 `PLAYER_DISCONNECTED` 资产/波次清理链。所有参与玩家均判负后才触发全局失败。
- 本轮未修改碰撞屏障、怪物 AI、目标回退、正常在线玩家城墙失败入口及其他玩法逻辑。
- 自动验证已通过：`MULTIPLAYER_PLAYER_DEFEAT_LUA51_PASS`、`MULTIPLAYER_PLAYER_ISOLATION_CONTRACT_PASS`、`WAVE_EARLY_FINAL_PASS`、目标 `luac5.1`、CSV/生成配置期限一致、严格 UTF-8 和限定 `git diff --check`。
- 尚需 Workshop Tools 双客户端确认：150 秒未建墙、断线 20 秒判负、断线窗口内墙毁坏判负、判负玩家停止出怪且其他在线玩家继续运行。

## 当前实施任务（2026-08-29）：玩家退出资产清理、出怪通道停用与多人日志修复

- 用户要求在玩家直接退出/断线后销毁该玩家的 Builder、建筑及其他玩家资产，并永久停用该玩家本局对应的普通波次出怪通道；其他仍在线玩家及其出怪通道必须继续运行。
- 同步处理实机日志：`modifier_single_health_bar.lua:20` 对缺少 `SetTableValue` 的 NetTable 对象调用报错；`MonsterSpawnMarker` 在 `template_map` 仍查找旧全局 `monsterborn/monsterorn`，导致多人普通波次无法从 `player_slots.csv` 权威映射的 `monsterborn_player1..4` 出怪。
- 本任务与既有多人隔离任务合并实施：Builder progression 改为按 `player_id`，唯一 ExecuteOrderFilter 增加服务端所有权门禁，并审计自定义建造/维修/伐木入口。
- 修改前工作区已有用户改动：`.gitignore` 被修改、`tests/lua/test_rogue_rewards_08_18.lua` 被删除；本任务不得触碰、恢复或覆盖。
- 生产实现已完成：断线事件发布 `PLAYER_DISCONNECTED`；Builder 直接移除，全部注册建筑和工人按既有死亡清理链销毁；断线城墙带清理标记，不触发其他玩家的全局失败；对应普通波次通道永久停用且已生成波次怪移除。正式战斗英雄因主英雄复活契约未盲目 `ForceKill`，不在本轮退出清理范围。
- 普通波次按当前活动玩家将同一批次扩展到各自 CSV `wave_spawn_marker`，怪物绑定所属 `player_id` 和该玩家城墙；挑战建筑怪也按玩家通道生成。真实游戏不再查找旧全局 `monsterborn/monsterorn`；该回退只保留给无 `PlayerResource` 的纯 Lua 旧测试。
- Builder progression 已从同队共享改为 `state_by_player`；唯一 ExecuteOrderFilter 在维修/伐木副作用前检查全部命令单位权威 owner，拒绝跨玩家、混合 owner 和未解析实体，issuer `-1`/系统命令保持放行。Grid 自定义事件原有注册 Builder 对照保持使用。
- `modifier_single_health_bar` 发布前验证 `CustomNetTables.SetTableValue` 是否为函数，运行时 NetTable 方法不可用时安静跳过；全仓未发现生产代码覆盖 `CustomNetTables` 全局。
- 自动验证通过：`MULTIPLAYER_PLAYER_ISOLATION_CONTRACT_PASS`、4 项新增 Lua 5.1 行为测试、`WAVE_EARLY_FINAL_PASS`、目标 Lua 5.1 语法（`building_system.lua` 按既有去 BOM 临时副本）、严格 UTF-8、Player Slots CSV/生成 Lua 一致和限定 `diff --check`。既有 `test_wave_difficulty_builder.lua`、`test_wave_difficulty_selection.lua` 在当前配置期望处失败；`test_wave_monster_visual_integration.lua` 的护甲断言在 HEAD 基线同样失败，均未为本任务修改。
- 尚需双机 Workshop 冷启动：确认两个 Marker 同时出怪并各自攻击对应城墙；Player 1 退出后 Builder、建筑、工人和其波次怪消失，Player 0 继续出怪且不判负；控制他人/混合框选命令被拒绝；控制台不再出现 `SetTableValue` 和旧 `monsterborn/monsterorn` 日志。

## 当前实施任务（2026-08-28）：双玩家独立 Builder 出生与血条异常修复

- 用户已实机确认 LAN 双机联机、PlayerID 和双方操作同步成功；新问题是 Player 0 有真实 Builder，Player 1 只能看到地下且不可移动的 Undying 占位英雄，并伴随 `modifier_single_health_bar.lua:45 IsAlive` 错误。
- 根因闭环：`template_map.vmap` 原有 `monsterborn_player1..4`，但缺少全部 `player_0_builder_spawn..player_3_builder_spawn`。Player 0 因 CSV 允许旧坐标回退仍能创建 `npc_survival_builder_proxy`；Player 1 按 CSV 失败关闭，真实 Builder 未创建，HUD 暴露了被取消控制、禁移动并移至地下的英雄替换锚点。
- Content 地图现新增四个 `info_target`：Player 0 `(0,0,256)`、Player 1 `(0,-256,256)`、Player 2 `(0,-512,256)`、Player 3 `(0,256,256)`。Y 轴沿用既有四条 `monsterborn_player1..4` 通道映射，X/Z 使用 Player 0 已验证的 Builder 侧旧出生位置；未把 Builder 放到怪物出生端。
- `template_map.vmap` 已完成 KeyValues2 -> binary -> KeyValues2 DMX 往返检查，四个 Builder Marker 和四个波次 Marker 均唯一；Resource Compiler 返回 `OK: 191 compiled, 0 failed, 0 skipped`，生成 `maps/template_map.vpk`。
- `modifier_single_health_bar` 现在在发布前验证 parent 的实体索引、生命、存活和队伍方法，生命周期结束或不完整 handle 不再调用不存在的 `IsAlive()`；专项 Lua 5.1 测试覆盖不完整 parent 安静跳过及正常投影。
- 用户已将权威 `multiplayer_rules.csv` 的 `setup_wait_seconds` 调整为 60，当前生成 Lua 与 CSV 定向重建结果逐字节一致。
- 自动验证通过：`MULTIPLAYER_BUILDER_MARKERS_CONTRACT_PASS`、`MULTIPLAYER_PLAYER_SERVICE_LUA51_PASS`、`SINGLE_HEALTH_BAR_MODIFIER_LUA51_PASS`、目标 `luac5.1`、CSV/生成一致性、目标严格 UTF-8、双仓限定 `diff --check` 和地图编译。仍需双机 Workshop 冷启动确认 Player 1 出现真实 `BUILDER_READY`、位置/模型/控制权正确且血条错误不再出现。

## 当前实施任务（2026-08-29）：七路线原生 Dota 塔模型替换

- 用户已批准将七条防御塔路线从英雄主体/穿戴视觉替换为七个互不重复的 Dota 原生塔模型；每条路线的全部 20 个升级等级统一使用同一模型，融合/肉山塔保持不变。
- 权威映射为：死亡 `tower_dragon_black.vmdl`、冰霜 `tower_radiant_rock_golem.vmdl`、闪电 `tower_dragon_white.vmdl`、机枪 `tower_upgrade.vmdl`、多重 `tower_good2.vmdl`、神秘/激光 `tower_bad.vmdl`、防空 `tower_dire_rock_golem.vmdl`。完整路径已在本机 VPK 索引确认存在。
- 所有既有 `model_asset_id` 必须保持不变，以继续驱动弹道、技能粒子和运行时分支；玩法数值、费用、人口、技能、升级描述、融合配置均不得改变。删除路线资产的英雄穿戴、饰品常驻粒子、英雄头像元数据和仅适用于英雄主体的手动攻击动作，保留攻击弹道及全部技能效果。
- 验证范围：七路线模型唯一性、路线内阶段一致性、21 个资源 ID 保留、英雄资源清理、预载代理、融合 Roshan 配置、CSV 生成、Lua 5.1 语法、专项行为测试和 `git diff --check`。自动验证不能替代 Workshop Tools 冷启动后的尺寸、碰撞、待机/攻击/死亡动作、升级、清理和融合塔实机验收。

## 当前实施任务（2026-08-28）：死亡、多重与激光塔九阶段恢复原生英雄外观

- 用户要求将死亡塔、多重塔和激光塔三个阶段链的九个视觉阶段恢复为指定英雄主体与官方原生穿戴，同时保持既有技能、伤害、弹道和激光行为不变。基础数据继续以 `data/csv/` 为唯一权威来源，生成 Lua 只能通过 `build_configs.ps1` 重建。
- 当前 CSV 映射依次为 Templar Assassin、Wraith King、Phantom Assassin、Vengeful Spirit、Luna、Medusa、Storm Spirit、Io 和 Tinker；原生组件数固定为 `3/6/5/4/6/5/3/0/6`，所有 `portrait_item_def` 为空。Io 使用原生无穿戴主体，不新增组件或资产特效；激光继续统一读取 `tower_laser_effects.csv` 的 Tinker Laser。
- 当前 CSV 生成合同总量为 `asset_components=116`、`asset_effects=118`；旧测试的 `>=126/137` 阈值属于历史饰品数据，必须改为精确 CSV 合同，禁止通过虚构资源补齐。需补充 `asset_proxy_tower_laser_od_blackgate` 的 Io 主体预载，并删除测试中的 Drow Arcana、Death Prophet 等过期外观预期。
- 自动验证范围包括完整 CSV 生成、Lua 5.1 语法、九阶段路由/bundle/预载/头像聚焦测试、旧外观引用审计和限定 `git diff --check`。自动化结果不等于 Dota 实机验收；最终仍需完全退出 Dota 后冷启动，逐阶段确认世界模型、原生穿戴、头像、弹道和持续激光表现。
- 本轮验证通过：九项专项 Lua 行为测试全部通过（含已按当前无 Phoenix 专属覆盖合同同步的 `test_phoenix_laser_contract.lua`）；128 个 Lua 文件通过 Lua 5.1 语法检查；8 个目标生成模块与 CSV 临时重建结果逐字节一致；三份塔路线 CSV 的非视觉字段无差异；目标运行时范围无已退役 Phoenix/Muerta/Drow Arcana 资源引用；`git diff --check` 通过。
- `build_configs.ps1 -CheckOnly` 仍仅被既有无关 `scripts/vscripts/config/generated/rogue_reward_effects.lua` 的单个 `U+FFFD` 阻断；本任务目标文件严格 UTF-8 解码无替换字符。完整生成目录共 109 个 Lua，其中该无关文件是唯一编码异常，未为本任务修改。

## 当前实施任务（2026-08-29）：七路线原生 Dota 塔模型替换

- 用户已批准将七条防御塔路线从英雄主体/穿戴视觉替换为七个互不重复的 Dota 原生塔模型；每条路线的全部 20 个升级等级统一使用同一模型，融合/肉山塔保持不变。
- 权威映射为：死亡 `tower_dragon_black.vmdl`、冰霜 `tower_radiant_rock_golem.vmdl`、闪电 `tower_dragon_white.vmdl`、机枪 `tower_upgrade.vmdl`、多重 `tower_good2.vmdl`、神秘/激光 `tower_bad.vmdl`、防空 `tower_dire_rock_golem.vmdl`。完整路径已在本机 VPK 索引确认存在。
- 所有既有 `model_asset_id` 必须保持不变，以继续驱动弹道、技能粒子和运行时分支；玩法数值、费用、人口、技能、升级描述、融合配置均不得改变。删除路线资产的英雄穿戴、饰品常驻粒子、英雄头像元数据和仅适用于英雄主体的手动攻击动作，保留攻击弹道及全部技能效果。
- 验证范围：七路线模型唯一性、路线内阶段一致性、21 个资源 ID 保留、英雄资源清理、预载代理、融合 Roshan 配置、CSV 生成、Lua 5.1 语法、专项行为测试和 `git diff --check`。自动验证不能替代 Workshop Tools 冷启动后的尺寸、碰撞、待机/攻击/死亡动作、升级、清理和融合塔实机验收。

## 当前实施任务（2026-08-28）：死亡、多重与激光塔九阶段恢复原生英雄外观

- 用户要求将死亡塔、多重塔和激光塔三个阶段链的九个视觉阶段恢复为指定英雄主体与官方原生穿戴，同时保持既有技能、伤害、弹道和激光行为不变。基础数据继续以 `data/csv/` 为唯一权威来源，生成 Lua 只能通过 `build_configs.ps1` 重建。
- 当前 CSV 映射依次为 Templar Assassin、Wraith King、Phantom Assassin、Vengeful Spirit、Luna、Medusa、Storm Spirit、Io 和 Tinker；原生组件数固定为 `3/6/5/4/6/5/3/0/6`，所有 `portrait_item_def` 为空。Io 使用原生无穿戴主体，不新增组件或资产特效；激光继续统一读取 `tower_laser_effects.csv` 的 Tinker Laser。
- 当前 CSV 生成合同总量为 `asset_components=116`、`asset_effects=118`；旧测试的 `>=126/137` 阈值属于历史饰品数据，必须改为精确 CSV 合同，禁止通过虚构资源补齐。需补充 `asset_proxy_tower_laser_od_blackgate` 的 Io 主体预载，并删除测试中的 Drow Arcana、Death Prophet 等过期外观预期。
- 自动验证范围包括完整 CSV 生成、Lua 5.1 语法、九阶段路由/bundle/预载/头像聚焦测试、旧外观引用审计和限定 `git diff --check`。自动化结果不等于 Dota 实机验收；最终仍需完全退出 Dota 后冷启动，逐阶段确认世界模型、原生穿戴、头像、弹道和持续激光表现。
- 本轮验证通过：九项专项 Lua 行为测试全部通过（含已按当前无 Phoenix 专属覆盖合同同步的 `test_phoenix_laser_contract.lua`）；128 个 Lua 文件通过 Lua 5.1 语法检查；8 个目标生成模块与 CSV 临时重建结果逐字节一致；三份塔路线 CSV 的非视觉字段无差异；目标运行时范围无已退役 Phoenix/Muerta/Drow Arcana 资源引用；`git diff --check` 通过。
- `build_configs.ps1 -CheckOnly` 仍仅被既有无关 `scripts/vscripts/config/generated/rogue_reward_effects.lua` 的单个 `U+FFFD` 阻断；本任务目标文件严格 UTF-8 解码无替换字符。完整生成目录共 109 个 Lua，其中该无关文件是唯一编码异常，未为本任务修改。

## 已完成任务（2026-08-28）：研究所所有研究技能排除 A 键
## 当前实施任务补充（2026-08-28）：恢复主宰原生摄像机

- 用户确认前序主宰摄像机修改在本次外观恢复后仍然生效，要求恢复剑圣（Juggernaut）的标准原生摄像机设定。
- 根因是 `scripts/vscripts/addon_game_mode.lua` 在全局 `configure_game_rules()` 中调用 `SetCameraDistanceOverride(1500)`；该覆盖并非主宰专属，而是影响整个自定义游戏。
- 最小修复已移除该全局覆盖，不新增相机数值，不修改主宰外观、头像、技能、永久分身或任何 CSV；移除覆盖后由 Dota 引擎恢复原生摄像机链路。
- 自动验证需覆盖 Lua 5.1 语法、主宰资源/头像契约和限定 `git diff --check`；最终镜头距离、视角高度及跟随表现仍需 Dota 完全退出后的冷启动实机确认。

## 当前实施任务补充（2026-08-28）：主宰头像残留与齐天大圣确定性原生外观

- 用户冷启动实机反馈：选中主宰后官方头像区域仍显示上一个单位；齐天大圣世界外观未恢复。用户批准对齐天大圣当前外观链进行大修，同时必须保留既有 WebM 头像、永久分身战斗行为和已暂存的无碰撞修改。
- 主宰头像根因包含两层：`ui_bootstrap.js::ResolveDisplayUnit()` 原先无条件优先可能滞后的 `GetLocalPlayerPortraitUnit()`；现按选择/查询事件维护显示身份模式，普通选择优先 `GetSelectedEntities()`，查询事件才优先 Portrait Unit，同一次真实选择后的 250ms 内拒绝伴随 query 事件把身份切回旧 Portrait。HUD 覆盖层继续按 CSV `portrait_unit_name` 和当前实体双重门禁：齐天大圣显示 WebM，主宰显示内置 `npc_dota_hero_juggernaut` 静态头像，其他单位保持 Valve 原生头像；`portraits_custom.txt` 中 Juggernaut 不再设置 `PortraitHideHero=1`。
- 齐天大圣外观基础数据继续以资源 CSV 为权威：`asset_catalog.csv` 固定原生主体和本机 `items_game.txt` 已确认的四个官方 `default_item` 模型（Head 594、Armor 608、Weapon 609、Shoulders 657）；`asset_components.csv` 将四件定义为 `dota_item_wearable`，`asset_effects.csv` 不包含齐天大圣项目粒子。运行时隐藏 `ReplaceHeroWith`/`CreateUnitByName` 已实例化的旧 wearable，强制 CSV 原生主体，再事务挂载四件原生 wearable；本体和永久分身复用同一外观服务，不恢复 Demon Trickster。
- `asset_proxy_hero_monkey_king` 仅预载原生主体加四件默认 wearable；CSV 已重建 `asset_catalog.lua`、`asset_components.lua`、`asset_effects.lua`。完整生成器成功写出 109 个模块，最终仍仅被既有无关 `generated/rogue_reward_effects.lua` 的 U+FFFD 阻断。
- 自动验证通过：`HERO_COSMETIC_SERVICE_PASS`、`SELECTED_UNIT_COSMETIC_PORTRAIT_PASS`、`HERO_ASSET_PRELOAD_SERVICE_PASS`、`MONKEY_KING_W_ER_CONTRACT_PASS`、相关 Lua 5.1 语法、HUD XML 解析和双仓限定 `diff --check`。`ui_bootstrap.js`、`combat_stats.js`、HUD CSS 各 `1 compiled, 0 failed`，HUD XML 完整依赖链 `9 compiled, 0 failed`。工作区既有且被忽略的 `test_asset_bundle_config.lua` 仍按旧永久英雄组件总量契约阻断；未修改该测试或无关防御塔数据。仍需 Dota 完全停止后冷启动，实机确认主宰头像切换及齐天大圣本体/分身外观。

## 当前实施任务（2026-08-28）：恢复剑圣原生模型与默认穿戴

- 用户要求恢复剑圣（Blademaster/Juggernaut）的原生主体模型和默认穿戴，同时保留齐天大圣的自定义 WebM 头像、分身行为及既有 staged 修改。
- 权威 `data/csv/资源系统/asset_catalog.csv` 现将 `hero_permanent_hero_blademaster` 设置为原生 `models/heroes/juggernaut/juggernaut.vmdl`，并仅预载主宰原生主体加五个默认 wearable 模型；`asset_components.csv` 和 `asset_effects.csv` 不再包含主宰项目饰品或 Arcana 粒子。
- `hero_cosmetics_config.lua` 删除剑圣 `body_model/body_skin` 覆盖并设置 `hide_default_wearables=false`；`asset_proxy_hero_blademaster` 同步只预载六个原生模型。生成 Lua 由 `build_configs.ps1` 从 CSV 重建，未直接编辑生成文件。
- 新增/扩展 `test_selected_unit_cosmetic_portrait.lua` 回归断言，固定主宰原生模型、默认资源、无项目组件/粒子和无头像 `portrait_item_def`，并继续检查齐天大圣头像元数据无 bundle 依赖及现有 WebM 链路。
- 自动验证：头像/资源专项 Lua 5.1.5 行为测试、外观服务 Lua 5.1.5 行为测试、5 个目标 Lua `luac5.1 -p` 和限定 `git diff --check` 通过。完整 `build_configs.ps1` 已成功生成 109 个配置模块，但最终 `CONFIG_VERIFY files=109 bad_utf8=1` 仍被既有无关 `rogue_reward_effects.lua` 的 U+FFFD 阻断；尚未进行 Dota 冷启动实机确认。

## 当前实施任务（2026-08-26）：LAN 多人活动槽位与初始化诊断

**状态：已完成（用户确认）**

- 用户追加确认普通与高级研究所的研究技能均不得占用 `A`，统一从 `Q/W/E/R/T/S` 顺序继续分配。
- 当前映射为：普通研究所 `Q/W/E/R/T/S`；高级研究所 `Q/W/E/R/T/S/D/F/G/H`。`D` 继续保留给 Builder/英雄 Blink 与箭塔移动，未改 Builder 技能映射。
- 已同步修改 `combat_stats.js` 的官方角标、研究输入命中映射，`hud_takeover.js` 的研究角标，以及 `ui_bootstrap.js` 的 `H` fallback 注册；CSV 备注与生成 Lua 同步更新，Ability KV/XML 未修改。
- 三份 Panorama 源码已重新编译为游戏侧 `.vjs_c`，均为 `OK: 1 compiled, 0 failed, 0 skipped`；CSV/生成 Lua 映射、严格 UTF-8、生成 Lua `luac5.1` 和限定 `git diff --check` 已通过。
- 全量 `build_configs.ps1` 已完成 CSV→Lua 生成，但最终全量 UTF-8 门禁被仓库既有的其他生成 Lua `U+FFFD` 阻断；已清理本轮无关生成差异，仅保留研究所 CSV 对应生成 Lua。
- 用户已确认本任务完成。此前列出的 Workshop Tools 冷启动项目属于后续运行回归建议，不再作为本任务阻塞项；自动验证结果仍不得表述为新的 WORKSHOP 实机验证。
- 可复用经验：研究所快捷键必须同时检查运行时映射、HUD 角标、Panorama fallback 注册、CSV 备注和生成 Lua；配置修改先改 `data/csv/`，再定向重建生成结果。全量生成器可能改写无关生成文件，收尾时应按任务开始状态清理无关差异，并单独报告既有乱码门禁问题。

## 当前实施任务（2026-08-27）：多人启动窗口、槽位 Marker 与双机验证

- 本轮已将多人启动等待窗口纳入权威 `multiplayer_rules.csv`，默认 `setup_wait_seconds=15`；`addon_game_mode.lua` 不再在 `Activate()` 同步结束 setup，而是在等待期间接收并分配连接玩家，结束前再次批量分配。
- `player_slots.csv` 已显式映射：player 0..3 -> `monsterborn_player1..4`，并由项目生成器定向重建 `multiplayer_rules.lua` 与 `player_slots.lua`，未直接手改生成配置。
- Hammer 仍缺少或尚未确认 `player_0_builder_spawn` 至 `player_3_builder_spawn`；本轮没有伪造地图实体，也没有开始改造 `wave_system.lua` 的全局城墙、出生与统计状态。
- 下一可靠检查点：编译含四个 Builder marker 的地图后，通过 Hidden/Friends Only 大厅让 A/B 在启动前加入；确认 A/B 分别为 PlayerID 0/1、双方 `hero_ready`/`BUILDER_READY`、Builder 位置和所有权、彼此实体可见性。
- 自动验证只覆盖 CSV/生成配置、Lua 5.1 行为、语法和静态契约；UDP、地图 marker、实体同步与控制权必须在 Workshop Tools 双机实测。

## 前序实施（2026-08-26）：LAN 多人活动槽位与初始化诊断

- 用户确认 PC-B 曾通过 `connect 192.168.1.134:27015` 加载 `template_map`，但双方无英雄/Builder，随后快速出现“与主机的连接受到干扰”；该结果只证明地图加载，不证明活动玩家槽位或同步会话成立。
- 根因审计发现生产入口只在 `Activate()` 固定分配玩家0；`player_connect_full` 到达英雄选择后会跳过分队。实施边界是：在 `FinishCustomGameSetup()` 前分配全部已连接玩家，兼容连接事件字段解析，并增加分队/英雄/断开结构化日志；不修改CSV多人容量、API loopback、Session、数据库或生成配置。
- 晚于 setup 的裸 IP 直连不能被代码安全伪装成大厅活动玩家；若日志报告 `assignment_window_closed`，必须使用 Hidden/Friends Only 大厅让两名玩家在启动前进入好人方槽位。自动测试只能验证 Lua 行为和静态契约，稳定 UDP、实际 PlayerID、英雄/Builder可见性仍需 Workshop Tools 双机验收。
- 实施完成：新增 `multiplayer_player_service.lua`，统一解析 `PlayerID/playerid/userid`、在 setup 窗口内分配已连接玩家并记录结构化日志；`addon_game_mode.lua` 在配置阶段和 `FinishCustomGameSetup()` 前调用该服务，并记录连接、英雄就绪和断开解析结果。新增 Lua 5.1 行为测试覆盖直接字段、userid 回退、批量分配、晚加入拒绝和非法 ID。
- 自动验证通过：`MULTIPLAYER_PLAYER_SERVICE_LUA51_PASS`、`MULTIPLAYER_PLAYER_LUAC_PASS`、`ADDON_GAME_MODE_LUAC_PASS`、`MULTIPLAYER_PLAYER_CONTRACT_PASS`、`CSV_GENERATED_MULTIPLAYER_RULES_PASS`、`STRICT_UTF8_PASS` 和限定 `TARGET_DIFF_CHECK_PASS`。这些结果不是 Workshop Tools 双机验证；UDP 稳定性、实际活动槽位和玩家1地图 Marker 仍待实机确认。

## 当前实施任务（2026-08-29）：Templar Assassin 死亡塔头像场景探针

- 隔离 sibling addon `survival_ta_portrait_probe` 已改为可玩运行时探针：Lua 生成一个播放 `idle` 的 TA `prop_dynamic` 主体和三个 CSV 穿戴 `prop_dynamic`；每件穿戴严格按生产顺序执行 `SetOwner(body)` 后 `FollowEntity(body, true)`，且不接收独立动画命令。正式 `survival` 运行逻辑和生产 CSV 未为探针改写。
- 主体模型、动画和缩放来自 `asset_catalog.csv`，死亡塔引用由 `tower_class_death.csv` 交叉确认；三个穿戴的模型、实体类型、`bone_merge` 元数据、缩放和排序来自 `asset_components.csv`。spike 自己的 `scene.csv` 只提供地图、变换、镜头和灯光参数；生成器据此输出 `ta_portrait_probe_runtime_config.lua`，运行时 Lua 不硬编码模型路径。
- 静态 `DOTAScenePanel` 已降级为有明确标签的 body-only 渲染基线，不再承载穿戴或骨骼跟随结论。生成 VMAP 只包含 `worldspawn`、一个静态 TA body、一个 `env_global_light` 和一个 `point_camera`；最终 `default_ents.vents_c` 经 `resourceinfo` 解码确认恰好一个 `prop_dynamic`，三个穿戴模型和 `ta_portrait_wearable_*` 实体均不存在。
- 已新增 `tools/build_ta_portrait_probe.ps1`、`tools/test_ta_portrait_probe_contract.ps1` 和 `ui/ta_portrait_probe`；生成目标严格限定为 `content/dota_addons/survival_ta_portrait_probe` 与 `game/dota_addons/survival_ta_portrait_probe`，入口地图为 `ta_portrait_probe_lab`，背景场景为 `ta_portrait/templar_assassin`。
- 运行时加入重复初始化保护、实体/序列/API 结果校验、失败清理、命名实体清理、结构化日志和 NetTable readiness；自动状态固定为 `visual_verdict=pending`。Panorama 只有在 body entindex 与三个穿戴均就绪后才锁定运行时主体镜头，并要求人工观察多个不同 `idle` 帧后记录结果。
- 自动验证通过：源与生成后 `TA_PORTRAIT_PROBE_CONTRACT_PASS`、两个 PowerShell AST 解析、源/生成运行时与生成配置 Lua 5.1 语法、限定 `git diff --check`。Resource Compiler 通过：入口地图 `13 compiled, 0 failed`、body-only scene `7 compiled, 0 failed`、5 个 Panorama 资源各 `1 compiled, 0 failed`；所有 VPK 与 Panorama 编译产物均已生成且非空。
- 编译器仍输出本机官方开发资源的 `ERROR_FILEOPEN`、`Leaked KeyValues blocks: 162` 和未签名提示（缺少 `src/devtools/bin/certificates/game/dota/vpk.publickey.vdf`）；目标资源汇总为 0 failed，VPK 已生成且不早于内容 VMAP。上述工具噪声和未签名状态均不是 Workshop Tools 实机通过证据。
- 旧截图 `%TEMP%\survival_ta_portrait_probe_frame_a.png`、`frame_b.png`、`pass.png` 生成时间早于本轮运行时探针构建，且画面仍是旧版中央大型静态 ScenePanel 与旧按钮文案，不能作为本轮证据。最终仍需完全停止 Workshop Tools 后冷启动 `survival_ta_portrait_probe/ta_portrait_probe_lab`，确认 `BODY_ANIMATION_APPLIED`、三个有序 `ATTACHED`、`READY ... visual_verdict=pending`、运行时镜头构图，以及头发/肩部/护甲在多个不同帧中随对应骨骼变形；只有人工完成该观察后才能记录 PASS。

## 当前实施任务（2026-08-27）：Cosmetic Portrait Phase 2A 能力尖峰

- 仅以普通英雄 Axe 验证 `DOTAScenePanel`/`portrait_world_unit` 能否渲染多个官方经济物品 ItemDef；当前客户端 `items_game.txt` 已确认 Head `22217`、Armor `22215`、Weapon `22218`、Belt `22216`、Arms `22219`。
- 第一优先级是审计当前 Workshop Tools/Hammer 的 `portrait_world_unit` 实体契约：真实 ItemDef/DefIndex 字段、多饰品形式、style/skin 与默认 wearable 行为。字段契约确认前不得创建推测性 `.vmap`，不得把 ItemDef 传给旧 `SetUnit` 第二参数。
- 若实体不存在、没有经济 ItemDef 能力或合法字段无法确认，立即停止 Phase 2A；不得切换英雄或技术路线。能力确认后只按 Base Axe → Head → Head+Weapon → 五件逐级测试，每级失败即停止。
- 实验必须与生产 HUD、世界模型和饰品系统隔离；不得修改 `template_map.vmap`、`combat_stats.js`、`survival_hud.xml`、CSV schema、`hero_cosmetic_service.lua`、剑圣、齐天大圣或现有世界 `prop_dynamic` 饰品系统；Phase 2A 完成后不自动进入 Phase 2B。

### Phase 2A 当前实施状态（2026-08-27）

- 已在 `ui/portrait_world_unit_phase2a` 建立隔离源，并由 `data/axe_stages.csv` 作为阶段、ItemDef、style、镜头和期望结果的唯一生成输入；没有修改生产 CSV 或生产 addon 的 Manifest/HUD。
- 已生成 sibling addon `survival_phase2a`：可玩入口为 `phase2a_lab`，场景资源依次为 `phase2a_portrait/axe_base`、`axe_head`、`axe_head_weapon` 和 `axe_all_five`。当前只激活 Base；B 的 `portrait_world_unit` 已按 `base_minimal` 契约使用 `MapUnitName=npc_dota_hero_axe`、`m_iTeamNum=2`、`ModelScale=1`、`StartDisabled=0`、`skip_background_entities=1`、`suppress_intro_effects=1`、`skip_pet_spawn=1`、`spawn_wearable_item_defs=0`，无 `EnableAutoStyles`、非必要背景/动画/courier 选项、`item_def0..7`、`style_index0..7`、`activity`、`activity_modifier` 或 cosmetic 字段；`parentname`/`parentAttachmentName` 为空。没有使用 `SetUnit` 传 ItemDef，也没有添加 `skin_override`。
- 当前 Base-only 契约执行 `tools/test_portrait_world_unit_phase2a_contract.ps1 -GeneratedContentRoot ...\survival_phase2a` 输出 `PORTRAIT_WORLD_UNIT_PHASE2A_CONTRACT_PASS`；PowerShell 解析、生成 XML 解析和限定 `git diff --check` 通过。B `axe_base` 单独重新编译为 `OK: 7 compiled, 0 failed`，VPK 非空且不早于源 VMAP。
- 已冷启动并进入 `survival_phase2a/phase2a_lab` 的 Stage 1 `Base Axe`；VConsole 出现 `[PHASE2A] LOAD stage=base map=phase2a_portrait/axe_base expected=none`，未再出现 `DATA_INVALID`，证明 `Phase2APortraitData` 的单 Base 固定数组及 A/B/C 绑定已被运行时消费者接受。
- 用户已人工确认正式环境 Axe 基准：世界模型正常；正式左下 `Portrait` 为基础 Axe；当前未同步自定义饰品。该截图/状态仅作为 `Phase 2A Baseline`，不作为隔离 Test 1 或 Head `22217` 的渲染通过证据。
- 当前执行边界：先在隔离 addon 中完成 Test 1（Base Axe）并填写五项观察；仅当 Test 1 PASS 后加载 Head `22217`，随后停止，不测试 Weapon、其余 ItemDef 或 Phase 2B。保持正式 HUD、世界 `prop_dynamic` 系统、Juggernaut 和 Monkey King 不变。
- 本轮已将隔离 CSV 镜头改为精确瞄准 `portrait_world_unit` 原点 `(0 0 -1.7000000477)` 的 `11.553546 171.313448 0.000000`，构建器强制唯一相机名为 `hero_camera`、两个父级字段为空，并拒绝 `loadout_camera_model` 与旧 `herocamera`；Panorama 四个静态绑定同步为 `hero_camera`。
- 历史相机/绑定修复曾完成四阶段资源编译；当前执行边界已收紧为 Base-only，后续 Head/Weapon/五件 scene 均不生成、不编译、不激活。
- WORKSHOP 实机结论保持 A `DirectUnitSanity=PASS`、B `portrait_world_unit Background=FAIL/黑屏`、C `Prop_dynamic Background Control=PASS`；本轮没有重新判定外观、wearable、Style 0 或动画，也没有加载 Head `22217`。
- Renderer Sanity 已扩展为 Base-only 三面板：A `DirectUnitSanity`（仅 `unit="npc_dota_hero_axe"`）、B `BackgroundSceneSanity`（`map="phase2a_portrait/axe_base" camera="hero_camera"`）和 C `BackgroundPropControl`（`map="phase2a_portrait/axe_prop_control" camera="hero_camera"`）。C scene 由独立 `renderer_sanity_control.csv` 生成，只含 Axe `prop_dynamic`、普通 `red_box` `prop_dynamic`、无 parent `point_camera` 和 `env_global_light`，不含 `portrait_world_unit` 或 ItemDef；不修改 B 的既有 `hero_camera`。
- 用户已实机确认 A 可见（PASS）、B 纯黑（FAIL）、C 可见（PASS），且 `map_enable_portrait_worlds => Portrait world usage: Enabled`。按用户规则只修正并复测 B Base 实体契约，不进入 Head `22217`、Weapon、其它 ItemDef、Phase 2B 或正式 `survival`。
- 用户最新实机确认：A `DirectUnitSanity=PASS`、B `portrait_world_unit Background=FAIL/黑屏`、C `Prop_dynamic Background Control=PASS`。由此确认 DOTAScenePanel renderer、直接英雄、background map、camera、light 和 scene packaging 均正常，当前唯一剩余失败点是 B 的 `portrait_world_unit` 实体契约；本轮暂停 ItemDef `22217`。
- 本轮实体契约审计确认 B 原先虽使用正确的 `MapUnitName`，但继承了官方 prefab 的 `m_iTeamNum=4`、`spawn_wearable_item_defs=1`、`activity`/`activity_modifier` 和 `item_def`/`style_index` 字段。已将 `data/axe_stages.csv` 与生成器改为 CSV 驱动的 Base-only 最小配置，并在生成后契约中禁止 `unit_name`、`NPCScriptName`、`CustomNPCName`、`model`、`hero`、`arcana`、`persona`、`cosmetic` 及 parent 关系。
- 本轮选择性构建已重新生成并编译 B `axe_base`：Resource Compiler `7 compiled, 0 failed`，B `.vpk` 非空且不早于内容 `.vmap`；C 场景编译汇总为 `7 compiled, 0 failed`，但 C `.vpk` 写入被当前 Dota 实例占用而未覆盖，故完整构建命令最终因 C 新鲜度检查失败。Panorama 五项资源均 `1 compiled, 0 failed`。Head `axe_head.vmap/.vpk` 仍不存在，未生成或编译 `22217`。
- 编译后实体 lump `axe_base.vpk/.../entities/default_ents.vents_c` 已通过 `resourceinfo` 确认包含 `classname=portrait_world_unit`、`MapUnitName=npc_dota_hero_axe` 和 `[PR#]phase2a_axe_portrait_unit`。在同一 Stage 1 运行会话中只读执行 `ent_find portrait_world_unit` 与 `ent_find phase2a_axe_portrait_unit`，两者均输出 `Found 0 matches.`；没有执行 `ent_fire`、`ent_setpos`、`ent_setang` 或 `ent_create`。最终结论：`PORTRAIT_RUNTIME_ENTITY_MISSING`。
- 本轮执行 `tools/build_portrait_world_unit_phase2a.ps1 -SceneAndPanoramaOnly`：首次编译实际成功但新鲜度校验错误地把场景 `.vpk` 当作源文件而失败；构建器已修正为内容侧 `.vmap` 对游戏侧 `.vpk`，并新增契约断言锁定选择性模式、非空输出和时间戳校验。修正后输出 `PORTRAIT_WORLD_UNIT_PHASE2A_BUILD_PASS`；B `axe_base.vpk`、C `axe_prop_control.vpk` 各 `7 compiled, 0 failed`，五个 Panorama 资源各 `1 compiled, 0 failed`，所有目标产物均非空且不早于源文件。
- 选择性编译保持 `phase2a_lab.vmap/.vpk` 不变，`axe_head.vmap/.vpk` 不存在，B/C 生成物继续不含 Head `22217`（C 也不含 `portrait_world_unit`）。Resource Compiler 日志仍有官方开发资源的通用 `ERROR_FILEOPEN` 启动警告，但目标资源汇总均为 `0 failed`；该警告不能作为场景实机通过证据。
- `HEAD_RESOURCE_COUNT=0`；`axe_head.vmap/.vpk` 仍不存在，运行数据 `expectedItems=none`。Phase 2A 按运行时实体缺失结论停止，不调查 Head `22217`、Weapon、其它 ItemDef 或 Phase 2B，也不修改正式 `survival`。
- 最终分层审计：修复后的 `axe_base.vpk` `resourceinfo -all` 输出为 5,778 bytes，实体 lump 包含 `portrait_world_unit`、`MapUnitName=npc_dota_hero_axe`、`[PR#]phase2a_axe_portrait_unit`、`[PR#]hero_camera` 和 `[PR#]light_hero`；Base 内容 VMAP/游戏 VPK 时间戳分别为 `2026-08-27T14:50:47.2377143Z` / `2026-08-27T14:50:48.7675234Z`。
- 为绕开运行中实例对正式控制 VPK 的锁定，独立命名的 `axe_prop_control_verify_20260827` 编译结果为 `7 compiled, 0 failed`；其 `resourceinfo -all` 输出为 3,997 bytes，实体 lump 具有 Axe、`prop_control_red_box`、`prop_control_key_light`、`hero_camera`，弱引用同时包含 `models/heroes/axe/axe.vmdl` 和 `models/props_gameplay/red_box.vmdl`。临时 `.vmap/.vpk` 已删除，`C:\Users\li\AppData\Local\Temp\phase2a_*_default_ents_all*.txt` 证据保留。
- 正式 `axe_prop_control.vpk` 的 `resourceinfo -all` 读取成功但仍为旧产物：3,826 bytes、弱引用只有 Axe 而没有 `models/props_gameplay/red_box.vmdl`；其时间戳 `2026-08-27T13:00:22.3510906Z` 早于内容 VMAP `2026-08-27T14:50:47.3955253Z`，`CONTROL_GAME_IS_FRESH=0`。当前 Dota PID `22760` 仍以 `-addon survival_phase2a -tools -steam -map phase2a_lab` 运行并持有该输出，未强制终止进程或覆盖用户正在使用的 VPK。
- 因正式控制 VPK 尚未刷新，修复后的 Base/控制场景尚未完成同一冷启动下的 A/B/C 实机复测；现有运行日志和 `ent_find` 结果不能证明本轮正式控制 VPK 已加载。待 Dota 释放锁后，仅重跑 `build_portrait_world_unit_phase2a.ps1 -SceneAndPanoramaOnly`，随后重新审计正式控制 lump 并再决定是否进行运行时验收；继续禁止加载 Head `22217`、Weapon、其他 ItemDef 或 Phase 2B。
- 最终复跑使用内容侧 `D:\steam\steamapps\common\dota 2 beta\content\dota_addons\survival_phase2a` 作为 `-GeneratedContentRoot`，输出 `PORTRAIT_WORLD_UNIT_PHASE2A_CONTRACT_PASS`；此前把游戏侧编译目录作为该参数导致的 `MISSING_FILE` 已确认是验证参数错误，不是生成文件缺失。
- 最终自动验证完成：源契约与内容侧生成后契约均输出 `PORTRAIT_WORLD_UNIT_PHASE2A_CONTRACT_PASS`；生成 Panorama XML 解析、两个 Phase 2A PowerShell 文件解析、七个目标 CSV/Markdown/PowerShell/任务文档的严格 UTF-8、无行尾空白和终止 LF 检查，以及限定 `git diff --check` 均通过。

## 当前实施任务（2026-08-27）：选中单位头像重构 Phase 1

- 服务端 `ui_request_router.lua` 新增共享 `apply_portrait_metadata(unit, snapshot)`；元数据只从 `asset_catalog.csv` 的生成配置读取，按当前 `survival_model_asset_id`、权威英雄 ID、严格 `survival_monkey_king_clone == true` 身份解析。
- `model_asset_id`、`portrait_unit_name`、`portrait_item_def` 在无有效资产时统一为空字符串；不得保留旧快照值，也不按单位名猜测齐天大圣分身身份。
- 普通单位 `unit_combat_snapshot()`、英雄 `hero_ui_snapshot()` 和 `HERO_COMBAT_STATS_CHANGED` 即时推送均应用同一元数据 helper；`combat_stat_projection.for_ui()` 的浅拷贝保留三个字段且不修改 combat service 权威快照。
- Panorama 仅删除快照回调内不存在的 `showNativePortrait()` 调用；既有齐天大圣 WebM 覆盖层、Valve 原生头像回退、世界模型和 wearable 生命周期不变。本阶段未修改 CSV、生成配置或英雄饰品服务。
- 自动验证：六英雄/显式资产/缺失资产/普通 fallback/齐天大圣本体与严格分身身份的 Lua 模拟测试通过，投影字段保留测试通过，三个目标 Lua 5.1 语法通过，`combat_stats.js` 强制编译为 `OK: 1 compiled, 0 failed, 0 skipped`。最终仍需 Workshop Tools 冷启动实机确认英雄、分身、建筑和无头像单位切换。

## 当前实施任务（2026-08-26）：齐天大圣基础原生模型与头像

- 齐天大圣原生 `DOTAScenePanel` 动画实机表现不稳定，已批准改用录制的 WebM 动态头像；资源来源为外部录制素材，接入后仅齐天大圣使用视频，其他英雄和建筑保留原生头像链路并可回退。
- 已放弃不受当前 Panorama 解析器支持的 `DOTAUnitImage` 和静态图片路径；齐天大圣使用独立 `MoviePanel` 覆盖官方头像，其他英雄和建筑继续由 Valve 原生头像链路显示，不传入任何饰品定义或 Bundle。
- 权威 `asset_catalog.csv` 已清空齐天大圣 `portrait_item_def`；`asset_components.csv` 和 `asset_effects.csv` 已删除齐天大圣四件 Demon Trickster 组件及四条 ambient 粒子。`hero_cosmetics_config.lua` 同步为空外观，世界模型只保留基础原生模型；其他英雄和建筑外观不变。
- `hero_cosmetic_service.lua` 已移除齐天大圣专属饰品预载 READY 门禁，避免基础原生模型因已删除的饰品事务被阻断。
- 验证范围：CSV/生成一致性、头像专项测试、Lua 5.1 语法、Panorama 编译、限定 `git diff --check`；最终仍需 Workshop Tools 冷启动实机确认。
- WebM 不再挂载于固定折叠的 `SurvivalHeroBottomHUD`；现由 `SurvivalHUDRoot` 下独立、无点击命中的覆盖层承载，并按 Valve 官方 portrait 候选节点的窗口坐标和实际 UI scale 同步几何。
- 覆盖层仅在当前权威快照实体等于实际显示实体且 `portrait_unit_name=npc_dota_hero_monkey_king` 时显示；选择切换或其他英雄、建筑、无单位状态只折叠自定义视频，不修改 Valve 官方头像节点。
- 选择事件会立即隐藏旧视频状态，100ms sentinel 负责处理 Valve portrait 节点重建及分辨率/UI scale 几何变化；播放按单位状态去重，继续强制循环和静音。
- 自动验证完成：`SELECTED_UNIT_COSMETIC_PORTRAIT_PASS`、专项测试 Lua 5.1 语法、content/game 限定 `git diff --check` 均通过；`combat_stats.js`、`survival_hud.css` 分别为 `OK: 1 compiled, 0 failed`，native CSS 为 `OK: 5 compiled, 0 failed`，HUD XML 依赖链为 `OK: 9 compiled, 0 failed`。尚未执行 Workshop Tools 冷启动实机头像对齐、切换、重生、循环和静音验收。

## 当前实施任务（2026-08-24）：剑圣 Q/E 原生视觉施法

- 用户批准将 Q/E 改为真实原生技能视觉施法：Q 使用隐藏的 Legion Commander 施放 `legion_commander_overwhelming_odds`，E 在目标点创建可见的 Juggernaut 施放 `juggernaut_blade_fury`。
- 两类短生命周期实体均使用 `survival_visual_only` 标记、不可控、禁攻、零碰撞和无视野范围；Q 隐藏主体及 wearable，E 保留完整主宰模型与原生技能特效。施法结束、拥有者死亡、实体死亡或服务重置时清理。
- `damage_filter_service.lua` 在消费战斗事务前拒绝视觉实体造成的所有伤害；Q 原有 600 范围复制伤害和 E 原有后端 tick 伤害继续通过 `DEAL_REQUEST`，数值仍来自 `blademaster_exclusive_runtime.csv`。
- 已删除 Q/E 手工粒子、E 外圈粒子和 `e_visual_outer_count` 配置；预加载改为原生 Legion Commander/Juggernaut 单位。生成配置已同步。
- 自动验证：专项契约、目标 Lua 5.1 语法、PowerShell 语法和限定 `git diff --check` 已通过；完整配置生成成功但既有全局 `CONFIG_VERIFY files=108 bad_utf8=1` 仍阻断脚本最终状态。尚未执行 Workshop Tools 冷启动实机视觉与伤害验收。
- 用户反馈 Q 暴击时没有特效。根因定位为点目标原生技能使用 `CastAbilityOnPosition` 施法时，临时军团同时处于不可控/隐藏状态，Workshop Tools 可能只接受动作而未执行原生 Ability 效果。现改为优先提交 `DOTA_UNIT_ORDER_CAST_POSITION` 引擎位置施法订单，显式激活原生 Ability，订单提交后再隐藏军团；旧 API 仅作兼容回退。
- 本轮修复验证：`BLADEMASTER_EXCLUSIVE_CONTRACT_PASS`、剑圣服务 Lua 5.1、PowerShell 契约语法通过；仍需冷启动实机确认暴击时 Q 完整特效出现且军团不可见。

## 当前实施任务（2026-08-24）：齐天大圣 W 分身无视单位碰撞

- 用户批准齐天大圣二技能永久守家分身新增无视单位碰撞，使其能够穿过城墙周围由隐藏单位组成的碰撞屏障返回守家位置。
- 实现边界：在既有 `modifier_monkey_king_clone` 上声明 `MODIFIER_STATE_NO_UNIT_COLLISION=true`，并保留分身创建与同步阶段的 `SetHullRadius(0)` 兜底；不修改其他英雄、普通单位、城墙屏障几何或齐天大圣技能数值。
- 本需求不新增基础数值，既有齐天大圣运行参数继续以 `data/csv/英雄系统/monkey_king_exclusive_runtime.csv` 为权威源，不修改自动生成 Lua。
- 验证范围：齐天大圣 W/E/R 专项契约、分身 Modifier Lua 5.1 语法、严格 UTF-8 和限定 `git diff --check`。自动验证不等于 Workshop Tools 实机验收，仍需冷启动确认分身能穿过城墙并回到守家区域。
- 自动验证完成：`MONKEY_KING_W_ER_CONTRACT_PASS`、`MONKEY_KING_CLONE_NO_COLLISION_LUA51_PASS`、分身 Modifier `luac5.1 -p`、`STRICT_UTF8_PASS` 和限定 `git diff --check` 均通过；尚未执行 Workshop Tools 实机验证。

## 本轮实机结果（2026-08-24）：终局未观察到失败回调或 API 业务请求

- 本次 Workshop Tools 对局约运行 `74` 秒后进入 `DOTA_GAMERULES_STATE_POST_GAME`；用户提供的日志只包含 Dota 原生 `Target NPC is dead` / `invalid order (19)`、终局统计和 Match signout 信息。
- 当前没有观察到 Survival 业务日志 `game_end_final_requested`、`player_disconnect`、`HTTP final=true`、final callback 完成或 API checkpoint/final 请求摘要，因此本次不能证明 `FINALIZING -> CLOSED`、最终结算或数据库持久化发生。
- `Target NPC is dead` 只能说明游戏代码向已死亡 NPC 执行了无效订单，不能作为在线 session 失败回调、断线回调或 API 失败的证据；它与 Survival finalization 链路暂时分开记录。
- `http://127.0.0.1:8765/health` 返回 HTTP 200 只证明 API 进程可达，不证明本局 Lua 发出了业务 HTTP 请求，也不证明 Supabase 收到或提交了 final 请求。
- 当前实机结论为“失败且断点未知”，不是“API 成功”或“终局 final 已完成”。由于没有业务请求日志，暂不能区分 game_end 入口未执行、日志未采集、Provider 未初始化、请求未发送，还是回调在请求后丢失。
- 明日恢复顺序：先冷启动并确认服务端日志文件/控制台采集方式；再用单玩家最短复现确认 session 创建和 60 秒 checkpoint；随后分别观察 `game_end` 入口、HTTP 发出、HTTP 状态、callback 和 `final=true`；最后才恢复双玩家断线/重连与 180 秒 lease 测试。

## 本轮实施（2026-08-24）：多人断线 session 隔离与 60 秒租约检查

- 已将权威 `data/csv/玩家档案系统/fishing_system_rules.csv` 调整为 60 秒 online checkpoint、180 秒 online lease；奖励周期仍为 600 秒，并已通过生成器同步 `fishing_system_rules.lua`。
- 在线服务现在区分 `ACTIVE`、`FINALIZING`、`CLOSED`；断线玩家的旧 session 从可重连表摘除但保留在 finalizing 表中，最终请求完成后关闭。重连可立即创建新的 `session_id`，永久累计时间仍由后端按账号/session 规则恢复，断线间隔不累计。
- `player_disconnect` 继续只调用对应玩家的 `online_time_service.disconnect()`，没有新增 defeat 或全局 `GAME_FINISHED`；`game_end -> finish()` 仍逐玩家 final，重复 final 通过 session 状态和对象身份抑制。
- 自动验证：`LUAC_PASS`、`ONLINE_TIME_DEBUG_CHECKPOINT_LUA51_PASS`、`CSV_GENERATED_FISHING_RULES_PASS`、`STRICT_UTF8_PASS` 和限定 `git diff --check` 通过。尚未启动本机 API，也未进行 Workshop Tools 双玩家断线/重连实机验收。

## 本次修复（2026-08-23）：断开事件字段诊断与 game_end final 结算

- 已根据 Workshop Tools 日志确认：checkpoint HTTP 已返回 200，游戏结束不应期待额外 player_disconnect；最终请求由 game_end -> online_time_service.finish() 发起。
- player_disconnect 入口现在记录原始 PlayerID/playerid/userid/UserID 解析结果，并在没有直接 PlayerID 时尝试通过 PlayerInstanceFromIndex(userid) 回退解析；无法解析时明确记录 disconnect_ignored。
- 在线服务增加 checkpoint 开始、session/provider/account 缺失、断开请求、在途 final 排队和 game_end final 入口日志；业务请求与 final 排队语义保持不变。
- 自动验证：在线服务 luac5.1 和 FISHING_REWARD_CONTRACT_PASS 通过；完整 addon 的 luac5.1 仍被既有 initialize_services 超过 60 个 upvalue 限制阻断，尚不能称全文件语法通过。仍需 Workshop Tools 实机确认 game_end_final_requested、HTTP final=true、callback 完成和 API 收到单个 final 请求。

## 当前修复项（2026-08-24）：齐天大圣与剑圣专属技能未进入技能栏

- 本轮追加用户需求：修复齐天大圣R Tooltip，删除已废弃的“主动无冷却，在英雄当前位置与城墙之间移动同一座终极塔”描述；以英雄技能CSV为权威，统一中英文本地化镜像。
- 本轮同时继续处理剑圣视觉与暴击门控：Q仅消费最终暴击攻击伤害事件；E通过独立视觉半径控制点扩大原生剑刃风暴粒子。Workshop Tools当前仍无法连接，自动检查不能替代实机验收。

- 用户纠正问题方向：当前首要故障不是技能数值或攻击触发，而是专属 Ability 没有进入原生技能栏。
- 根因：英雄原生 Ability 仅被隐藏但仍占据低位实体槽；专属技能动态追加后依赖真实引擎中不可靠的`SetAbilityIndex()`换位，导致服务端能找到 Ability 但原生`AbilityN`没有对应按钮。
- 修复方案：`hero_skill_system.lua`以专属/公共技能和三个工具技能构造权威顺序，移除原生及过期 Ability；发现实体槽位不一致时保存冷却，并严格按权威顺序重新`AddAbility()`，确保齐天大圣和剑圣的四个专属技能真实占据Q/W/E/R。
- 验证范围：Lua 5.1语法、技能栏顺序契约、齐天大圣/剑圣专项契约和限定`git diff --check`；Workshop Tools仍需冷启动确认原生按钮实际出现、锁定置灰及解锁激活。

- 本轮用户确认截图对应英雄为剑圣，截图中的“踏风/增加移动速度”是旧版剑圣R文案，不是齐天大圣技能。本轮已移除英雄技能同步中的全部`SetAbilityIndex()`调用，并将剑圣Q/W/E/R在正式中英文资源中的Tooltip同步到当前CSV；齐天大圣CSV与运行配置本轮不改，仅保留工作区既有修改。
- 本轮验证：剑圣专项契约、`hero_skill_system.lua` Lua 5.1语法和`git diff --check`通过；`test_alt_hero_ability_contract.ps1`仍在既有Builder-stage断言处提前失败，未触及剑圣断言。Workshop Tools仍需冷启动实机确认剑圣Q/W/E/R、锁定显示和解锁激活。
- 本轮新增剑圣视觉：Q 触发在主目标位置创建 Legion Commander `legion_commander_odds.vpcf`，E 触发在主目标位置创建 Juggernaut `juggernaut_blade_fury.vpcf`，E 粒子与风暴生命周期同步清理；两个粒子已加入 `addon_game_mode.lua` 的地图预加载。伤害与触发概率未改。

## 当前实施任务（2026-08-24）：齐天大圣 W/E/R 方案调整

- 用户批准调整齐天大圣专属技能：E 增加20%暴击率、最终攻击力保持独立3倍乘区，并仅在本体主普通攻击实际暴击时对主目标追加逻辑全属性×5纯粹伤害；W 改为2000%暴击伤害、攻击间隔减少0.1秒、每60秒永久复利增加2%全属性，并维持唯一永久守家镜像；R 终极塔继承英雄最终攻击与暴击伤害。
- 用户确认 W 分身暴击口径：完整继承本体最终暴击率；分身暴击伤害由本体存档暴击伤害加成再额外增加750%。存档相关数值必须通过现有英雄权威战斗快照计算，不读取或反推Dota原生三维。
- 实施以`data/csv/英雄系统/monkey_king_exclusive_runtime.csv`和英雄技能说明CSV为权威源，重新生成Lua；运行时复用`monkey_king_exclusive_service.lua`、`hero_combat_stat_service.lua`、`tower_fusion_service.lua`及既有最终暴击事件，不新建重复战斗系统。
- 验证范围：CSV/生成Lua一致、W唯一永久分身和Q隔离、分身暴击继承、E本体主暴击边界、R最终攻击/暴击伤害继承、Lua 5.1行为与语法、相关回归及限定`git diff --check`。自动验证不等于Workshop Tools实机验收。

## 当前联调状态（2026-08-23）：多人生产联调阻塞
## 当前修复项（2026-08-23）：资源树、十宗罪预生成与箭塔手动选敌

- `data/csv/资源系统/world_visual_definitions.csv`中的资源树`model_scale`已从3调整为1.5，并由生成器同步`config/generated/world_visual_definitions.lua`；基础模型和位置未变。
- `modifier_single_health_bar`已回退到修改前的原生引擎血条实现；移除超大生命值自定义NetTable、`MODIFIER_STATE_NO_HEALTH_BAR`和对应Panorama编译资源改动。
- 十宗罪继续由CSV定义成员、模型和数值；英雄召唤后一次性创建十个Boss，使用隐藏的无敌/眩晕/定身阶段Modifier停留在房间内，正式进入挑战后按阶段解除对应Boss限制并复用实体。
- 十宗罪击杀确认并完成材料处理后，直接在击杀回调中激活下一层预生成Boss并执行阶段入口传送，不再经过0秒调度器等待；其他挑战刷新时序保持不变。
- 箭塔保留建筑身份和玩家控制能力，仅允许拥有者右键指定合法攻击目标；移动类订单被拒绝，目标失效后恢复自动索敌。
- `challenge_asset_preload_service.lua`仍在`HERO_READY`后从生成的`encounter_members`、`monster_archetypes`和CSV资产目录收集挑战模型并异步预载。尚未执行Workshop Tools冷启动，仍需实测树尺寸、原生血条、十宗罪预生成/激活时序和箭塔右键选敌。

## 当前修复项（2026-08-23）：VIP英雄基础攻速与普通英雄统一

- 用户反馈：VIP英雄剑圣和齐天大圣的实际攻速远高于普通英雄小黑和影魔。
- 根因：`data/csv/英雄系统/hero_definitions.csv`中两名VIP英雄的基础`attack_speed`为1.5，普通英雄为0.7；项目该字段表示每秒攻击次数。
- 本轮修复：将`hero_monkey_king`和`hero_blademaster`的基础`attack_speed`统一调整为0.7，并重新生成英雄配置；保留剑圣转生后“迅影”等独立专属攻速效果。
- 验证要求：CSV生成配置一致性、VIP/普通英雄基础攻速定向契约、Lua 5.1语法和限定`git diff --check`；Workshop Tools冷启动后仍需实测实际攻击间隔。

## 当前修复项（2026-08-22）：防御塔销毁占格未返还与挑战房间刷怪范围过大

- 当前进度已推进到“Supabase 迁移核对 + 生产双玩家端到端联调”，暂时卡在多人联调阶段；本次记录作为后续会话恢复的最新任务状态。
- 已完成后端配置、启动脚本、环境模板和 Lua API 调用链复核；已确认 Python API 绑定 `127.0.0.1:8765`，数据库访问由主机 API 完成。
- 已确认推荐 LAN 拓扑：主机运行 Dota、Lua、Python API 和 Supabase 访问；其他玩家只加入主机创建的 Dota 对局，不直接调用主机 API。
- 已确认玩家永久身份使用服务端 `PlayerResource:GetSteamAccountID()`，经过共享服务端 pepper 派生数据库身份；Dota 本局 `PlayerID` 仅用于本局槽位和命令参数，不能作为数据库主键。
- 已确认现有自动化和玩法代码已覆盖 checkpoint 奖励、最终结算、`grant_id`/`request_id` 幂等和重连档案恢复；这些结果不等于生产双玩家实机验收。
- 当前阻塞：独立数据库仓库中的 migration `202608230006` 与 `202608230007` 尚未确认在目标 Supabase 按顺序执行，且需要先核对其依赖迁移；迁移状态确认前不进行生产结论判断。
- 多人生产验收必须去掉 `-Automation9001` 和 `-Workshop60Seconds`，使用两个不同 Steam 账号验证独立档案、session、在线累计、checkpoint、600 秒奖励、断线/结束结算、重连恢复、跨玩家隔离、重复请求和 API 重启。
- 若未来要求其他电脑直接调用 API，需要另立任务设计 LAN 绑定、认证、网络限制、防火墙和 TLS；当前不得把 API 改为 `0.0.0.0`。

## 当前任务（2026-08-23）：正式在线奖励切换为十分钟派发

- 用户已确认 Workshop Tools 中生产 version 3 奖励、档案永久效果、防御塔每秒攻击力投影和客户端公告完整出现。
- 已批准正式配置采用：每 600 秒派发一次奖励；定期 checkpoint 从 60 秒降低为 300 秒；租约调整为 450 秒；正常断开和对局结束发送 `final=true` 立即结算。
- 实施必须以 `data/csv/玩家档案系统/fishing_system_rules.csv` 为权威源并重新生成 Lua。退出上报不能替代定期 checkpoint，因为崩溃、断电和网络异常不保证执行退出回调。
- 已完成正式切换：CSV 与生成 Lua 为 checkpoint 300 秒、租约 450 秒、奖励区间固定 600 秒；`player_disconnect` 和 `game_end` 均触发 final 结算。
- Lua 对在途 checkpoint 的退出请求使用 `final_requested` 排队，避免并发请求丢失最终结算；API 新增严格 `final` 布尔校验与透传，Supabase 前向 migration 在幂等结算后按账号/session 删除活动租约。
- 自动验证已通过：29 项后端 unittest、Lua 5.1 行为、目标 Lua 语法、CSV/生成 Lua 契约、严格 UTF-8 和限定 `git diff --check`。尚需执行新 Supabase migration 并进行 Workshop Tools 冷启动实机验证。

## 本次修复（2026-08-23）：在线奖励本地校验诊断与公告事件常量

- 已确认 `online_time_service.lua` 的 grant 校验此前对所有拒绝只返回 `nil`，无法区分奖励 ID、启用状态、scope、版本和数值范围问题；同时缺少 `grant_id` 时仍可能进入 validated 列表后被静默跳过。
- 已增加无敏感数据的 `grant_rejected` 原因日志，并将缺少 `grant_id` 纳入校验失败；日志只输出 reward ID、definition version、amount 和拒绝原因。
- 已补齐 `events.UI_NOTIFICATION = "ui.notification"`。现有 `ui_request_router.lua` 已订阅该事件，并仅对显式 `audience="all"` 调用 `Send_ServerToAllClients`，因此星之庇佑公告可到达现有 Panorama 通知容器。
- 已扩展 `tools/test_online_time_debug_checkpoint.lua`：覆盖合法 grant、未知/禁用奖励、缺少 grant ID、scope/version 不匹配及数值上下界拒绝。
- 当前验证：在线时长 Lua 5.1 行为测试通过；相关 Lua 文件语法检查通过；UI 路由语法检查通过；限定 `git diff --check` 通过。Supabase REST 只读查询仍受现有凭据 401 阻断，未将本地检查称为远端数据库验证；Workshop Tools 永久效果、重登录和公告仍需实机确认。

## 本轮诊断（2026-08-23）：在线里程碑 grant ID 版本冲突

- 已确认 `checkpoint_online_time(...)` 的旧 milestone ID 仅由 `account_id + milestone` 生成；定义版本从旧奖励切换到星之庇佑时可能复用同一 `grant_id`，由 `grant_out_of_match_reward` 正确拒绝为 `grant_id_conflict`，外层 API 映射为 HTTP 502。
- 数据库仓库新增前向迁移 `D:\survival_database\supabase\migrations\202608230006_include_definition_version_in_online_grant_id.sql`：将新 ID 绑定 `definition_version`，不删除、更新或覆盖 `reward_grants` 历史账本。
- 已增加数据库契约测试，要求迁移重编译七参数 `checkpoint_online_time`，检查旧表达式替换为 `:star:v<definition_version>:<milestone>`，并禁止修改历史 grant。
- 只读 Supabase REST 查询因当前 `.env` key 返回 401，尚未取得真实 `reward_grants` 行、definition hash 或远端迁移状态；8765 API 当前未监听。不得将本地 SQL/单元结果称为远端数据库验证。
- 当前验证：Python 28 项单元测试通过；目标 Lua 5.1 语法检查通过；新增 SQL/测试文件严格 UTF-8 与限定 `git diff --check` 通过。PowerShell 契约测试曾因 Dota 进程锁定星之庇佑 CSV 未完成，需释放文件锁后重跑；Workshop Tools 实机和迁移执行仍待完成。

## 本次修复（2026-08-23）：首次登录 gameplay stats 正间隔初始化

- 已确认首次登录自动绑定 Steam Account ID 和重复登录幂等链路保持不变；实际 502 根因是 `tower_attack_interval=0` 触发数据库 `> 0` 检查约束。
- 已修复权威 CSV 的 `tower_attack_interval` 默认值/最小值为 `1.7 / 0.01`，恢复本批损坏的中文 UTF-8 与其他被归零的历史默认值，并保留现有两个星之庇佑字段；已按 CSV 重新生成 `player_gameplay_stats.lua`。
- 独立数据库新增 `202608230005_fix_gameplay_stats_attack_interval.sql`：缺失或非正间隔统一回退 `1.7`，保留 Steam 派生账号创建和两层 `on conflict ... do nothing` 幂等行为，不放宽数据库约束。
- 自动验证：目标 Lua 语法、目标文件严格 UTF-8、CSV/生成 Lua 关键字段一致性通过；完整后端测试与 Supabase migration/Workshop Tools 实机仍需继续确认，数据库迁移尚未在目标 Supabase 执行。

## 当前任务（2026-08-23）：删除旧局内钓鱼数据库持久化链路

- 已确认删除范围仅为旧 `fishing_states`、`fishing_sessions`、`fishing_idempotency`、`heartbeat_fishing_session(...)` RPC、Python `/v1/fishing/heartbeat` 入口和 Lua Provider 遗留 heartbeat 方法。
- 必须完整保留星之庇佑在线链路：`online_time_sessions`、`online_time_idempotency`、`checkpoint_online_time(...)`、`reward_grants`、`player_effect_totals`、`star_blessing_reward_definition_sets`、`star_blessing_reward_definitions` 及对应同步、发奖和档案投影。
- 实施方式为新增前向 Supabase 清理迁移，不改写既有历史迁移；局内 `fishing_reward_service.lua` 不依赖数据库，不在删除范围。
- 当前状态：代码与迁移已实施，自动验证完成。数据库迁移尚未在目标 Supabase 执行，Workshop Tools 实机仍需单独验证；当前会话已完成静态、单元和 Lua 检查。

## 本次需求复核（2026-08-23）：首次登录自动建档与跨电脑数据库验证

- 已确认该功能主体已经存在：`HERO_READY`触发档案加载，Lua服务端读取`PlayerResource:GetSteamAccountID(player_id)`，HTTP `POST /v1/profile`在同一请求内执行“确保账号存在 + 返回档案”。首次请求通过`ensure_player_gameplay_stats`幂等创建`survival_players`和`player_gameplay_stats`；已有Steam Account ID直接返回已有档案。
- 当前永久数据库键不是Dota本局`PlayerID`，也不是数据库中的原始Steam Account ID，而是Python使用稳定`FISHING_ACCOUNT_ID_PEPPER`计算的64位小写HMAC-SHA256伪名。该pepper必须在所有独立主机上保持一致且不得随意更换。
- `player_gameplay_stats.csv`是36个局内玩法字段的权威默认值源。当前数据库表字段为完整非空玩法字段，首次档案会返回完整`save.gameplay_stats`；“有内容才下发、无内容省略”应先限定到成就、库存、外观等可选分区，不能直接套用到核心玩法数值。
- 已完成真实Python API -> Supabase联调和Workshop Tools HTTP Provider到服务端grant的部分实机验证。仍未完成真实Steam账号冷启动、同账号二次登录、双账号隔离、断线重连/API重启、第二台电脑独立主机和正式商品支付发货验收。
- 下一步需求输入：确认数据库不可用时是拒绝进入、只读默认档案降级还是允许进入但关闭永久系统；确认商品类型（永久权益/库存/订阅/礼包）、订单幂等键、退款撤销和多处同时登录规则。未确认前不新增支付或商品发货 schema。

## 本次修复（2026-08-23）：在线 checkpoint 跨 Run 幂等 ID 复用

- 远端数据确认 Workshop Tools 每次 Run 都重新生成 `session_id=game-1-player-0` 及相同序号的 `request_id`；`online_time_idempotency` 因而直接返回历史 JSON，跳过当前累计与60秒奖励里程碑循环。这同时解释了重复出现的 `119/178/238/299` 以及旧响应缺字段导致的 `online_seconds_total=None`。
- `online_time_service.lua` 现为每次 Lua 模块生命周期生成包含引擎随机片段的 runtime nonce，并写入 session ID；同一 session 的 request ID 继续按序递增，重新初始化后不再复用旧 session/request ID。API 允许的字符集和128字符上限保持满足；未修改 CSV、生成配置、Supabase 数据或历史幂等记录。
- Lua 5.1 行为测试已覆盖 runtime nonce、同 session 稳定性、request ID 递增和重新初始化唯一性。`ONLINE_TIME_DEBUG_CHECKPOINT_LUA51_PASS`、目标 `luac5.1` 语法、`FISHING_REWARD_CONTRACT_PASS`、严格 UTF-8 与限定 `git diff --check` 通过。
- 已完成 `production_60s` Workshop Tools 回归：日志出现 `elapsed_seconds=39 online_seconds_total=930 grant_count=1 validated_grant_count=1`。这证明新 session ID、Python API、Supabase version 3 grant 和 Lua 本地定义校验已贯通；仍需在同一回归中确认 `profile_refresh_completed`、永久效果投影、公告和重复 grant 发布去重，不能把 `validated_grant_count=1` 单独称为完整奖励验收。

## 本次日志分析与修复（2026-08-22）：奖励 grant 的 pgcrypto schema 解析错误

- 已记录本轮 checkpoint 联调日志：普通 checkpoint 多次返回 `200`；四次在达到在线奖励里程碑时返回 `502`，Supabase 明确报 `42883 function digest(text, unknown) does not exist`；另有两次返回 `503 supabase_unavailable: no_detail`，后续请求恢复 `200`。
- 根因已确认：`grant_out_of_match_reward` 使用 `SECURITY DEFINER SET search_path = public`，但目标 Supabase 的 `pgcrypto` 常见安装位置为 `extensions` schema，奖励触发时无法解析未限定的 `digest()`；因此非奖励 checkpoint 正常，奖励 checkpoint 才失败。
- 已将源 migration 的函数 search path 改为 `public, extensions`，并新增 `D:\survival_database\supabase\migrations\202608220003_fix_reward_grant_pgcrypto_search_path.sql`，用于直接修复已部署目标项目，无需重写奖励函数。
- 当前必须动作：在目标 Supabase 项目执行 `202608220003_fix_reward_grant_pgcrypto_search_path.sql`（若迁移工具按序执行，也需确认 `202608210002` 已执行），然后重启 API，再用 Automation9001 验证 checkpoint 返回的 `grants`、永久效果和公告。
- 当前新 RPC 客户端对重复传输失败生成的 503 必定带 `function/transport/attempts` 详情；本批日志仍显示 `no_detail`，说明运行中的 API 很可能尚未重启、仍在使用旧代码。仍未确认目标项目实际 extension schema、RPC 锁等待/延迟、503 的具体传输根因、Dota 断线重连/API 重启和多人并发行为。上述日志没有暴露 request ID/延迟，不能仅凭 HTTP 状态完成实机验收。


## 本次修复（2026-08-22）：Supabase RPC 响应前断连

- 日志显示 `RemoteDisconnected` 发生在 `urllib.request.urlopen()` 读取 HTTP 响应头之前，原实现未捕获该异常，导致 checkpoint 路由返回未分类的 500。
- `D:\survival_database\backend\fishing_api\supabase.py` 现将响应前的 `RemoteDisconnected`、连接重置、BrokenPipe、超时和 `URLError` 做一次 100ms 有界重试；仍失败时返回 503 `supabase_unavailable`，并记录 RPC 名称、传输异常类型和尝试次数。明确的 HTTP 4xx/5xx 不重试，保留数据库错误详情。
- 新增两项断连行为测试；Python unittest 共25项、compileall和限定 `git diff --check` 通过。Python客户端实际调用目标 Supabase 已返回预期的 `400 P0001 gameplay_stats_payload_invalid`，证明当前网络、凭据和 RPC 路由可达。
- 运行中的 API 进程必须重启后才会加载修复。仍需观察重启后的真实 checkpoint 日志；若再次出现 `supabase_unavailable`，请提供同一时间段的 API 日志和 request ID。

## 本次联调修正（2026-08-22）：Automation9001 一分钟内奖励检查

- 已确认原有 Automation9001 夹具的奖励间隔为 10 秒，但在线检查点 RPC 原先把 600 秒硬编码在 SQL 中，且客户端每 60 秒才发送一次 checkpoint，因此单靠启动夹具不会在一分钟内正确发奖。
- 后端 checkpoint 现在传入规则 CSV 的 `reward_interval_min/max_seconds`；Supabase migration `202608210002_online_time_checkpoints.sql` 改为按 `p_interval_max_seconds` 结算里程碑。生产仍由 CSV 的 60 至 600 秒控制，Automation9001 在第一个约 60 秒检查点一次性返回已达到的 10 秒测试里程碑。
- Python 未处理异常现在记录 traceback，便于定位日志中的 500；新增 checkpoint 参数契约测试。后端 23 项 unittest、Python compileall、Lua 5.1 语法和数据库 migration 静态检查通过。
- 运行前必须将该 migration 在目标 Supabase 项目重新执行；否则远端仍是旧 RPC 签名。Workshop Tools 仍需用 `-Automation9001`、`http_fishing` 和 `survival_fishing_reward_fixture automation_9001` 实测奖励返回、永久效果刷新和公告。

## 本次修复（2026-08-22）：在线检查点超时与断开连接处理

- Python API 的默认 Supabase RPC 超时从 8 秒调整为 20 秒，当前 `.env` 同步为 20 秒；Dota HTTP Provider 的绝对超时调整为 30 秒，避免客户端与后端同时在 8 秒边界主动断开。
- `server.py` 的响应写入现在捕获 `BrokenPipeError`/`ConnectionResetError`，客户端提前断开时只记录简短信息，不再产生次生线程 traceback。
- 新增 Supabase RPC 超时单元测试；后端 22 项测试、Python 编译、Lua 5.1 语法、CSV 版本契约和限定 `git diff --check` 已通过。
- 当前 CSV 权威源与启用奖励版本均为 `3`。仍需在目标 Supabase 项目直接检查 RPC、锁等待和实际延迟，并在 Workshop Tools 做断线/重连实机验证。

## 当前任务（2026-08-22）：星之庇佑钓鱼奖励数据更新

## 本轮实施（2026-08-23）：星之庇佑共享奖励定义与紧凑 Grant 契约

- 新增 `D:\survival_database\supabase\migrations\202608230001_star_blessing_reward_definitions.sql`：创建星之庇佑定义集/定义表，同版本 hash 冲突、重复 ID、非 `star_blessing_*` ID 和非永久 scope 均失败关闭；先重编译 grant/checkpoint/heartbeat 依赖，再删除旧定义表。
- 后端默认同步 `star_blessing_reward_definitions.csv`，调用 `sync_star_blessing_reward_definitions`；grant/checkpoint/heartbeat HTTP 不再返回 profile、effect、展示字段或 hash，只返回 `grant_id/reward_id/amount/definition_version`。
- Lua 收到紧凑 grant 后按本地生成星之庇佑定义校验，再刷新玩家档案；档案快照和 `permanent_reward_effect_service` 投影完成后才发布 `FISHING_REWARD_GRANTED`。Automation9001 已改为 `star_blessing_automation_9001` + `hero_all_attributes_flat`。
- 用户已在目标 Supabase 项目执行 `202608230001_star_blessing_reward_definitions.sql`；当前阶段进入 Workshop Tools HTTP Provider 联调。执行后仍需用 API 健康检查和定义同步日志确认迁移无误，并重启 API 使最新代码生效。
- 联调命令保持为：`survival_player_profile_provider http_fishing`、`survival_fishing_api_token <本机FISHING_API_TOKEN>`、`survival_fishing_reward_fixture automation_9001`。`http_fishing` 是 Provider 名，`automation_9001` 是 Tools fixture 选择值；实际奖励 ID 才是 `star_blessing_automation_9001`。
- 自动验证通过：Python 25 项 unittest、Python compileall、PowerShell `FISHING_REWARD_CONTRACT_PASS`、SQL 静态契约、目标 Lua `LUAC_PASS`、严格 UTF-8 和双仓限定 `git diff --check`。远端 migration 已由用户执行，但本轮尚未取得远端 SQL 执行结果，也尚未完成 Workshop Tools 实机验证。

## 本轮实施（2026-08-23）：checkpoint 诊断与 Tools 快速触发

- Python API `server.py` 现在对 `/v1/online-time/checkpoint` 记录非敏感摘要：`elapsed_seconds`、`online_seconds_total`、grant 数量和 reward ID；不记录账号、Token 或 `grant_id`。
- Lua checkpoint 增加响应、grant 本地校验、档案刷新、永久投影、grant 发布和公告日志。Automation9001 的 `hero_all_attributes_flat` 投影值会在 `profile_refresh_completed` 中输出；公告由 `star_blessing_reward_service` 单独发布，旧 `fishing_reward_service` 忽略 `star_blessing_*`，避免重复公告。
- 新增 Tools-only 命令 `survival_online_checkpoint_now [player_id]`，精确要求 `IsInToolsMode()`、`survival_fishing_reward_fixture=automation_9001`、`survival_player_profile_provider=http_fishing` 和已有 HERO_READY session；命令只触发既有 checkpoint 函数。
- 自动验证通过：Python 26 项 unittest、Python compileall、`ONLINE_TIME_DEBUG_CHECKPOINT_LUA51_PASS`、目标 Lua `luac5.1 -p`、`FISHING_REWARD_CONTRACT_PASS`、严格 UTF-8 和双仓限定 `git diff --check`。仍未完成 Workshop Tools 实机 grant、永久属性、公告和重复 grant_id 验收。
- 真实 API/Supabase 探针通过：同 session 首次响应 `elapsed_seconds=0/online_seconds_total=0/grants=[]`，约 11 秒后响应 `elapsed_seconds=11/online_seconds_total=11` 并返回 Automation9001 grant；相同 request ID 重放保持同一业务响应，profile revision 保持 1 且 `save.permanent_effects.hero_all_attributes_flat=5`。这确认数据库 grant、永久聚合和请求幂等，但不等于 Workshop Tools 实机验证。
- API 已在本轮代码后以 `start_fishing_api.ps1 -Automation9001` 重启，当前监听 `127.0.0.1:8765`；新日志已输出安全摘要。下一步在 Workshop Tools 的 HERO_READY 后执行 `survival_online_checkpoint_now 0`，观察 Lua 阶段日志、英雄逻辑三维 +5、全员公告及重复响应不重复发布。

## 本轮实机结果（2026-08-23）：Workshop Tools checkpoint 已贯通至 grant 返回

- 用户在 Workshop Tools 的 HERO_READY 会话中执行 `survival_online_checkpoint_now 0`；`0` 已确认是正确的 Dota `PlayerID` 槽位参数，Lua 内部通过 `PlayerResource:GetSteamAccountID(0)` 解析永久账号身份，不应改传 Steam ID。
- 实机日志确认在线时长链路有效：`online_seconds_total` 从 `476`、`596` 增长到 `656`，并出现 `elapsed_seconds=60`；这证明 Tools -> Lua -> HTTP Provider -> Python API -> Supabase 的身份、租约和累计逻辑已实际工作。
- API 实机日志 `checkpoint_response elapsed_seconds=60 online_seconds_total=656 grant_count=6 reward_ids=test_hero_attack_flat` 确认 Supabase 在一次检查点返回了 6 个 grant；从 596 到 656 跨过 600、610、620、630、640、650 六个 10 秒里程碑，数量符合 Automation9001 的间隔计算。
- 当前不是“没有 grant”，而是服务端返回的 `test_hero_attack_flat` 与 Lua Automation9001 本地权威定义预期的 `star_blessing_automation_9001` 不一致；因此 Lua 本地 `validated_grant_count` 预计为 0，不应继续到档案刷新、永久属性投影、`grant_published` 和全员公告。
- 本次已完成 Workshop Tools 到服务端 grant 返回的实机联调；尚未完成星之庇佑奖励定义一致性、Lua `hero_all_attributes_flat=5`、全员公告和重复 grant 发布去重验收。当前服务端/数据库 definition version 9001 的实际定义仍需核对，不能记录为完整奖励功能验收。

- 用户确认删除错误且尚未接入的 `通用存档` 内容；已删除临时 `archive_reward_definitions.csv`，不再保留独立通用存档配置。
- 桌面文件 `C:\Users\UserComputer\Desktop\通关存档效果(1).csv` 实际是 ZIP/OOXML 工作簿而非文本 CSV，已直接解析其中唯一工作表，恢复 26 条星之庇佑/钓鱼奖励。
- 已用这 26 条工作簿记录重写 `data/csv/玩家档案系统/fishing_reward_definitions.csv`，保留名称、进度、识别状态、效果和原始数值；工作簿未提供权重，暂按每条 `weight=1`。
- 已接入且启用的效果仅包括当前服务/字段能明确消费的初始木材、墙生命、英雄全属性、墙伤害格挡、金矿效率、每秒木材、伐木工攻速、伐木效率和英雄攻击减甲；其余效果保留在 CSV 但 `enabled=0`，备注标记待接入。
- 定义版本已提升为 `3`；本轮未生成 `fishing_reward_definitions.lua`，未修改钓鱼运行时、数据库或 Supabase 定义。

## 当前插入任务（2026-08-21）：局内钓鱼抽奖系统

## 本次难度选择与在线时长联调结果（2026-08-21）

- 已修复难度选择 UI 的确定性事件名断链：服务端 `ui_snapshot_service.lua` 实际发送 `survival_ui_private_snapshot`，Panorama 原先只订阅不存在的 `ui_state_snapshot`；现已改为订阅实际事件并重新编译 `survival_ui.vjs_c`。
- API 已通过 `D:\survival_database\start_fishing_api.ps1 -Automation9001` 启动并实测监听 `127.0.0.1:8765`。`GET /health` 返回 200；合法认证和 payload 的 `/v1/online-time/checkpoint` 返回 502 `supabase_rpc_rejected`，证明路由已命中，原 404 已排除；畸形 `account_id` 返回 400 `account_id_invalid`。
- 后端 `server.py` 现将 CSV 规则中的 `online_time_lease_seconds` 显式传入 `FishingApplication`，不再使用应用默认值。
- 自动验证：Python 20 项单元测试通过；目标 Panorama Resource Compiler 返回 `OK: 1 compiled, 0 failed, 0 skipped`；`difficulty_config.lua` 和 `wave_system.lua` 的 `luac5.1` 语法通过。当前仓库没有独立 `test_wave_difficulty.lua`，因此未将不存在的行为测试记为通过。
- 剩余事项：502 需要检查 Supabase RPC/远端 migration 或函数权限；需 Workshop Tools 完全冷启动验证难度面板、N1-N5 选择、选择后倒计时/波次启动、断线与重连。API 测试进程已停止，未覆盖用户已有未提交修改。

## 本次联调恢复检查点（2026-08-21）

- 已确认数据库仓库位于 `D:\survival_database`，架构仍为 `Dota server Lua -> 127.0.0.1:8765 Python API -> Supabase PostgreSQL`；客户端不直接连接 Supabase。
- `player_profile_service.lua` 已注册 `survival_player_profile_provider`、`survival_fishing_api_token`、`survival_fishing_reward_fixture` 三个 ConVar；Provider 在每次 `load_player()` 前解析，支持晚设置 `http_fishing`、Provider ID 切换和测试注入 Provider，默认仍为 CSV 规则中的 `local_fixture`。
- 本机 `.env` 已生成到 `D:\survival_database\.env`，随机 Token/pepper 和当前 addon/Python 路径已写入；`SUPABASE_URL` 与 `SUPABASE_SECRET_KEY` 仍为空，未写入或暴露凭据，因此真实 API 尚未启动。
- 本轮自动验证通过：`PLAYER_PROFILE_PROVIDER_SELECTION_LUA51_PASS`、`PROFILE_FISHING_LUA51_PASS`、`FISHING_REWARD_CONTRACT_PASS`、Python 20 项单元测试、严格 UTF-8 和限定 `git diff --check`。已修正后端测试对局内奖励 CSV 的过时 schema 预期；局内钓鱼 CSV 不被后端局外奖励 loader 复用。
- 下一步：用户填写 `.env` 的 Supabase URL/Secret key 后启动 `start_fishing_api.ps1 -Automation9001`，再在 Workshop Tools 冷启动前设置 `http_fishing`、匹配 API Token 和 `automation_9001`，验证真实 Steam Account ID 档案加载、心跳、重连和 API 重启恢复。自动验证不等于 Supabase 或引擎实机验收。

- 用户确认每名在线好人方玩家在难度选择成功后的480秒整数倍节点分别独立抽奖；0秒不触发，每份结果通过全体系统播报展示给所有玩家。
- 截图数据共27行、原始出现次数129；用户确认删除B级“名称待复核/奖励正文待复核”，将S级“鬼森子”按增加伐木工攻速4倍处理，将SS级普通金枪鱼按伐木工攻速5%处理。删除后正式池26行、总权重128。
- 实现边界：新增局内钓鱼CSV和独立Lua服务，不复用需要HTTP/数据库的局外`fishing_reward_service`；资源奖励沿用现有team-scoped资源事务，测试命令为`fish <钓鱼ID>`和`fish random`。
- 本轮完成后记录CSV生成、Lua 5.1语法、定向行为测试和Workshop Tools实机验证边界。

## 当前任务（2026-08-20）：终极之塔聚合技能自定义 Tooltip

- 用户已批准执行。已确认自定义 Tooltip 链路由 `survival_ability_data`、`survival_tooltips` 和 `ability_tooltip.js` 共同完成；终极塔属于 `building_*` 单位，现有 `managedUpgrade()` 已覆盖其悬停接管，不新增独立 Panorama 气泡系统。
- 当前缺口是 `data/csv/公共规则/tooltip_definitions.csv` 缺少 `ultimate_tower_passive_1..5` 有效数据。本轮将以该 CSV 为权威源补齐五条聚合技能 Tooltip，并定向生成 `config/generated/tooltip_definitions.lua`。
- 图二对应数据采用既有终极塔专项契约规定的五个标题、复合描述和图标；动态等级、运行时字段继续复用现有 Ability Tooltip 渲染链。
- 自动验证和 Workshop Tools 冷启动结果将在本任务完成后追加；自动检查不能替代引擎实机验收。
- 已完成实现：CSV 中仅保留五条 `ultimate_tower_passive_1..5` 聚合 Tooltip 定义，并重新生成 Tooltip Lua；同步更新中英文原生回退文案，删除 `npc_abilities_custom.txt` 中残留的 `ultimate_tower_passive_6/7` KV。现有 `ability_tooltip.js` 的 `managedUpgrade()` 接管链未修改。
- 自动验证通过：`ULTIMATE_TOWER_SKILL_BAR_CONTRACT_PASS`、五条 CSV 唯一性/生成内容检查、目标 Lua 5.1 语法、KV 括号结构、严格 UTF-8、生成一致性和限定 `git diff --check`。尚未进行 Workshop Tools 冷启动实机悬停验收。
- 实机插入回归：用户截图确认主城已建成后仅 `Q` 建造防御塔缺失，其余 Builder 技能正常。已定位到删除终极塔旧 `ultimate_tower_passive_6/7` 时误删相邻的 `ability_survival_builder_slot_6_placeholder` 完整块及 `ability_build_arrow_tower` 定义头，导致箭塔建造字段串入 `slot_5_placeholder`；KV 大括号仍平衡，所以原结构检查未发现语义串块。
- 用户已批准完整修复与终极塔同轮回归。实施边界为恢复上述两个原有独立 KV 定义，并扩展专项契约，结构化读取 Builder 阶段 CSV 后校验所有启用 Ability 和六个占位 Ability 均存在唯一顶层 KV 定义，同时固定检查箭塔建造块的脚本、行为、图标和等级；终极塔仅保留五个聚合技能，既有融合与 Tooltip 实现不回退。
- 修复与自动回归已完成：`ability_survival_builder_slot_6_placeholder` 和 `ability_build_arrow_tower` 已恢复为独立 KV 块；专项契约现在校验 Builder CSV 启用 Ability、六个占位 Ability、终极塔五个聚合 Ability 的顶层定义唯一性，并固定检查箭塔建造块字段归属及禁止 `ultimate_tower_passive_6/7`。`ULTIMATE_TOWER_SKILL_BAR_CONTRACT_PASS`、`BUILDER_ABILITY_SLOTS_LUA51_PASS`、箭塔 Ability Lua 5.1 语法、KV 引号感知括号结构、目标严格 UTF-8 和限定 `git diff --check` 通过。
- 全量 `build_configs.ps1 -CheckOnly` 未通过：现有 105 个生成 Lua 中唯一失败文件仍为无关的 `config/generated/rogue_reward_effects.lua`，含历史 U+FFFD；本轮未修改该数据来绕过检查。最终仍需 Workshop Tools 完全停止后冷启动，依次确认 `Q` 建造防御塔、七路线建造、终极塔融合、五个聚合技能、两个工具技能和五个自定义 Tooltip；自动验证不等于引擎实机验收。
- 用户随后确认自定义 Tooltip 已出现但 Valve 原生 Ability Tooltip 仍会同时显示。历史实现对 source panel、祖先及 `AbilityButton/ButtonWell/AbilityImage` owner 派发隐藏事件，并在悬停期间重复压制；当前生产版仅对代理单次隐藏，Valve 祖先异步重建 Tooltip 后会重新出现。生产配置仍为 `abilities:false/abilityTooltips:true`，故修复位于选择性外置代理，不启用完整技能栏接管。
- 已恢复 owner-aware 原生 Tooltip 隐藏，并以 `nativeTooltipSuppressionSerial` 将 `0/30/80/160/300ms` 有限压制及现有 50ms 悬停会话绑定到当前 Ability/source panel；鼠标退出、切换技能、渲染失败和 context shutdown 会使旧回调失效。项目技能不存在 `DOTAShowAbilityTooltip` 回退，CSV Tooltip 与动态等级渲染链未修改。
- 自动验证通过：`ULTIMATE_TOWER_SKILL_BAR_CONTRACT_PASS`、专项 PowerShell 语法、目标严格 UTF-8、content/game 限定 `diff --check`；`ability_tooltip.js` 强制编译为 `OK: 1 compiled, 0 failed, 0 skipped`，产物 101135 字节、时间 `2026-08-20 17:50:13`。输入生命周期回归被既有无关 `BUILDING_D_CONFLICT_GUARD_MISSING` 阻断；高级研究契约自身含历史编码损坏，PowerShell 无法解析，均未改无关文件迎合。仍需 Workshop Tools 完全 Stop 后冷启动确认五个终极塔技能只显示自定义 Tooltip、长悬停和 Alt 不恢复原生层，并复测动态等级与点击行为。

## 当前插入任务（2026-08-20）：高级伐木工“效率”改为综合采集量加成

- 用户确认`ability_lumberjack_personality_efficiency`不再减少攻击间隔，改为每次采集按当前综合采集数量的130%结算，即基础采集量、资源树等级收益、科技收益及固定采集加成先汇总，再增加30%。
- 小数按伐木工实体独立累计余数：每次只发放整数木材，长期收益保持接近130%；该倍率在现有采集暴击和“天选之子”10倍倍率之前结算。权威数值和文案继续来自`lumberjack_personality_definitions.csv`。
- 实施范围限定为性格CSV/生成配置、伐木工采集载荷、资源树结算、Tooltip同步和专项测试；不得触碰工作区中其他既有未提交修改。完成后执行CSV生成一致、Lua 5.1行为/语法、契约、严格UTF-8和限定`git diff --check`，Workshop Tools仍需冷启动实机验收。
- 生产实现与自动验证已完成：CSV效果类型改为`wood_total_bonus_pct=30`，伐木工AI通过`TREE_HIT`传递，资源树在综合整数采集量形成后按实体保存小数余数，并在资源成功入账后提交余数；暴击及10倍倍率继续位于其后。统一Tooltip和六份本地化已同步。`LUMBERJACK_EFFICIENCY_LUA51_PASS`、`LUMBERJACK_EFFICIENCY_CONTRACT_PASS`、`LUMBERJACK_FUSION_CONTRACT_PASS`、目标Lua 5.1语法、CSV/生成Lua一致、严格UTF-8及限定`git diff --check`通过；尚需Workshop Tools冷启动确认LV7性格实际产量序列、浮字和Tooltip，自动验证不等于实机验收。

## 当前任务（2026-08-20）：玩家永久累计在线时长接入

- 已在既有 35 个玩法属性字段基础上新增 `online_seconds_total`，CSV 默认值为整数 `0`，单位为秒，仍由 `data/csv/玩家档案系统/player_gameplay_stats.csv` 权威定义；生成配置已重建。
- Dota 本局 `PlayerID` 仅是 `0..3` 的槽位整数；正式永久身份使用服务端 `PlayerResource:GetSteamAccountID()`，Python API 接收数字字符串并以 HMAC-SHA256 生成 64 位十六进制文本，数据库 `player_gameplay_stats.player_id` 使用该文本外键，不保存原始 Steam Account ID。
- Supabase migration `D:\survival_database\supabase\migrations\202608200001_player_gameplay_stats.sql` 增加非负 `online_seconds_total`、旧列兼容 `ALTER TABLE`、初始化默认 `0`，并在同名 migration 末尾覆盖心跳 RPC。
- 心跳只在同一 `session_id`、上次心跳存在且差值不超过租约时按相邻差值累计；首次、新 session、超租约和掉线间隔累计 `0`。幂等 `request_id` 在数据库事务最前返回原响应，因此重试不重复累计。`elapsed_seconds` 仍只用于钓鱼奖励倒计时。
- Python `/v1/profile` 和心跳继续通过 `save.gameplay_stats` 返回累计值；Lua 档案服务会按 CSV 默认值补齐旧档案缺失字段，不覆盖已有统计。在线时长不进入公开 NetTable。
- 自动验证通过：后端 16 项 Python 单元测试、在线时长五类边界模拟、`GAMEPLAY_STATS_CONTRACT_PASS`、`PLAYER_PROFILE_CONTRACT_PASS`、`PLAYER_PROFILE_SERVICE_LUA51_PASS`、目标 Lua 5.1 语法、Fixture/CSV 生成一致、严格 UTF-8 和限定 `git diff --check`。
- 真实 Supabase/Python API 联调已通过：Automation 9001 启动时 `sync_fishing_reward_definitions` 成功；专用测试账号的 `/v1/profile` 初始化返回 schema 1、36 个玩法字段、初始在线时长 0；首次心跳累计 0、同 session 约 2 秒相邻心跳累计 2、重复 `request_id` 返回完全相同响应且不重复累计、活跃租约期间新 session 被拒绝、租约后新 session 不累计离线间隔，最终 profile 总值 2、revision 1，公开区不含 `gameplay_stats`。API测试进程已停止。
- 既有 `test_fishing_contract.ps1` 本轮仍在“玩家即时奖励必须在共享资源写入前失败关闭”断言处失败；目标玩法字段文件和本轮改动未修改该既有资源边界，未为本任务越界调整。
- 尚未完成 Workshop Tools 实机 HTTP Provider 联调。当前 Dota/Tools 未运行，默认档案规则仍为 `local_fixture`；下一步需在 Tools Mode 显式启用 `http_fishing`、本机API token与`automation_9001`，验证真实Steam Account ID、重连、API重启及Supabase故障恢复，未经实机确认不得称为游戏端验收。

## 当前插入任务（2026-08-19）：练功房怪物独立碰撞 profile

- 用户确认四个练功房怪物使用Hull半径12并保留单位间碰撞；正式地面波次怪继续使用32，不启用练功房专属`NO_UNIT_COLLISION`。
- 权威数据已调整：`global_rules.csv`删除重复的旧`wave_ground_monster_hull_radius=30`行，保留唯一32并新增`practice_monster_hull_radius=12`；`encounter_members.csv`新增`collision_profile`列，仅四个`practice_*`成员填写`practice`，其余挑战成员为空。两份生成Lua均由项目生成器定向重建。
- `wave_monster_collision.lua`按成员profile选择练功房Hull，正式波次、飞行怪和建筑挑战怪规则保持独立。`challenge_session_service.lua`仅对练功房关闭`CreateUnitByName`默认clear-space，先应用12 Hull再显式`FindClearSpaceForUnit()`；其他挑战成员仍按旧时序在放置后应用Hull。
- 自动验证通过：`PRACTICE_MONSTER_COLLISION_CONTRACT_PASS`、`PRACTICE_MONSTER_COLLISION_LUA51_PASS`、目标Lua 5.1语法、18列成员CSV schema、两份生成Lua逐字节一致、目标严格UTF-8及限定`git diff --check`。挑战profile契约的本任务部分输出`CHALLENGE_COMBAT_PROFILES_LUA51_PASS`后，被既有无关N2转生护甲断言阻断；全量配置`CheckOnly`被既有`generated/rogue_reward_effects.lua`的U+FFFD阻断，本轮未越界修复。尚需Workshop Tools冷启动分别验收正式波次Hull 32及四个练功房的初始分散、移动和接敌表现。

## 当前任务（2026-08-19）：七塔合一点击无响应

- 用户再次实测确认回退后仍点不动，要求以历史可用版本为准停止盲目回退。已定位确切基线提交`0a69953`（2026-08-18“最终塔提交”）：该版本销毁七塔后在施法塔精确原点创建新终极塔，并非保留原实体变身。当前确定性阻断是安全事务在消费前检查原点网格时把新终极塔entindex作为单值`ignore_entindex`，而逻辑网格真正记录的是尚未消费的施法塔，因此返回`build_cell_occupied`。复核启动链确认真实处理器是`grid_placement_system.lua`而非旧`grid_system.lua`：单值参数负责逻辑占格，集合参数负责附近实体扫描。用户批准保留prepare→consume→commit安全事务；最终预检查以施法塔entindex作为单值忽略，并以集合忽略预创建终极塔及七座即将消费的材料塔，同时保留点击直派、CSV技能和失败清理；另修复`move_state()`成功路径缺少返回值。
- 用户否定将终极塔纳入建筑系统的融合替换事务，要求回归此前可以直接召唤终极塔的实现。已撤销`ultimate_tower`建筑定义、Builder owner、建筑注册和融合替换事件，恢复由`tower_fusion_service.lua`直接`CreateUnitByName()`，按`prepare → BUILDING_FUSION_CONSUME_REQUEST → commit`完成初始化、材料消费和占格；点击直派修复继续保留。
- 用户实机确认服务端点击直派方案仍失败，并指出终极塔没有进入绑定真实Builder的建筑预建造/注册生命周期。复查确认上一方案只修请求入口，`tower_fusion_service.lua`仍自行`CreateUnitByName`、占格和维护状态，绕过`building_system`建筑注册；旧事务测试Mock了创建实体，无法证明引擎建筑生命周期。另确认旧代码传入的`ignore_entindexes`未被`grid_system.lua`实现，所谓忽略七座材料塔的网格预验证实际无效。
- 已批准改为建筑系统权威的融合替换事务：从CSV取得终极塔建筑身份与占地，真实Builder作为创建owner；prepare阶段不消费材料，融合服务完成专属属性/技能初始化后再commit，建筑系统重新验证并消费七塔、注册成品和占格；失败rollback保留材料。终极塔不进入Builder普通技能栏。
- 用户实机确认七条路线资格显示`7/7`且点击后施法塔有动作，但材料塔未被消费、终极塔未生成。该表现说明客户端施法请求已发出，但动态`npc_dota_creature`上的`ability_tower_fusion`可能只接受了施法动作而未可靠进入`OnSpellStart()`。
- 已批准按最小范围修复：`ui_request_router.lua`在完成玩家归属、Ability实体身份、激活/隐藏/可施放校验后，直接派发权威`TOWER_FUSION_REQUEST`，保留Ability自身`OnSpellStart()`作为非自定义UI入口的回退；融合CSV、七塔选择、消耗及prepare/consume/commit事务不变。新增点击路由专项契约和融合成功/失败诊断日志，仍需Workshop Tools完全冷启动实测。
- 自动验证已通过：两个生产Lua文件的Lua 5.1语法检查、`TOWER_FUSION_TRANSACTION_LUA51_PASS`、`TOWER_FUSION_CAST_ROUTE_CONTRACT_PASS`、`ULTIMATE_TOWER_SKILL_BAR_CONTRACT_PASS`、严格UTF-8检查及限定范围`git diff --check`。这些检查不是Dota引擎实机验证。

## 前一任务（2026-08-19）：神秘之塔转职闪退排查

- 用户确认转职神秘之塔会闪退并已批准执行最小修复。权威路线CSV的神秘塔LV1-5引用不存在的`model_asset_id=tower_laser_keeper_forgotten`，而权威`asset_catalog.csv`及生成Lua只有已预载的基础资源`tower_keeper_of_the_light`；本轮不启用未落入资源CSV的临时饰品迁移数据。
- 最小修复将神秘塔LV1-5统一指向`tower_keeper_of_the_light`并重新生成Lua；专项契约校验神秘路线每个`model_asset_id`均存在于资源CSV、首阶段模型/资源固定一致，并将激光伤害间隔期望同步为技能CSV当前权威值1秒。自动验证不能替代Workshop Tools完全冷启动后的转职实机回归。

## 当前插入任务（2026-08-18）：伐木工性格结算、融合技能实时刷新与被动技能 Tooltip

- 用户已批准进入执行模式。“手很重”改为每次采集有1%概率减少资源树最大生命值的1%，概率和百分比均以`lumberjack_personality_definitions.csv`的`effect_value`为权威；整数伤害向下取整且最低1点，继续通过树木最低生命/耗尽升级链处理，不直接杀死资源树实体。
- 原地融合后必须立即重发目标伐木工的`survival_ability_runtime`和真实`ability_count`，清理已移除融合Ability并发布新性格Ability，使当前选中单位的技能栏和自定义Tooltip无需重新选择即可刷新。
- 性格等被动Ability保留图标与悬停Tooltip，但统一不显示Q/W/E/R等快捷键，也不得进入键盘主动施法槽位；主动融合技能和既有工具技能快捷键语义保持不变。
- 本轮同时完成已批准的“啦啦队”修复：所属玩家英雄和全部箭塔获得CSV驱动的可叠加百分比攻速Buff，并提供可见UI状态。修改必须保留game/content两个仓库现有未提交Tooltip改动，完成后执行CSV/Tooltip生成、Lua 5.1测试与语法、专项契约、Panorama强制编译、严格UTF-8和双仓限定diff检查；Workshop Tools冷启动仍作为最终实机验收。
- 生产实现已完成：“手很重”仅在木材/金币成功入账后判定，按`floor(max_health * effect_value / 100)`且最低1点扣血，Heavy Hand与普通攻击耗尽均保持`TREE_DEPLETED`通知，Heavy Hand到1点时调用树实体权威升级回调；融合后的目标工人立即重发Ability runtime、材料工人与普通死亡工人的旧runtime显式发布`removed=1`，并更新目标真实`ability_count`；Panorama被动Ability不显示快捷键且不消耗后续主动技能序号；“啦啦队”按同玩家隔离并将每个CSV百分比叠加为可见百分比攻速Modifier。
- 用户补充确认“啦啦队”也必须影响伐木工。目标范围现为所属玩家英雄、箭塔以及工人注册表中全部`worker_type=lumberjack`的普通/超级伐木工（包含啦啦队自身）；修理工保持排除，同队其他玩家单位仍由`player_id`隔离。
- 2026-08-18修复早建箭塔漏享“啦啦队”：原刷新仅依赖`FindUnitsInRadius(DOTA_UNIT_TARGET_ALL, FLAG_NONE)`，建筑实体可能未进入该扫描结果，且后续无状态变化时不会补投射。现保留英雄/伐木工扫描，并额外通过建筑系统权威`BUILDING_LIST_REQUEST`按玩家枚举已完成箭塔、解析实体并去重应用同一CSV驱动Modifier；不扩大到其他建筑。

## 当前任务（2026-08-19）：暂时关闭 Builder 开局三选一自动弹窗

- 用户确认 Builder/Boss 双池和 21 张 Builder 卡目前表现无异常；该结论记录为当前阶段实机反馈，但不扩大解释为所有卡牌边界均已逐项验收。
- Builder 已有专门的肉鸽奖励入口 `ability_survival_rogue_reward`，因此 `rogue_reward_service.lua` 暂时注释 `BUILDER_READY` 自动创建 `builder_start` offer 的订阅。Builder 创建完成时不再写入活动奖励 NetTable，也不会自动显示三选一 UI。
- 专门入口仍通过 `ROGUE_REWARD_OPEN_REQUEST`、`source="builder"` 创建并显示 Builder offer；Boss 奖励、双池隔离、可见 offer 门控、队列提升、领取、重抽和效果运行时保持原逻辑。
- 自动订阅代码完整保留为逐行注释，并说明恢复方法；后续需要重新启用开局自动弹出时，取消该代码块注释即可，预留的 `builder_ready` 标记继续负责一次性触发和失败重试。

## 本次任务（2026-08-18）：Builder 开局肉鸽奖励固定 G 键并修复刷新/输入/Tooltip

- `builder_ability_stages.csv` 将 `ability_survival_rogue_reward` 从 W 业务槽改为独立 `slot_order=7`；Builder 的六个建筑槽和 Blink 仍由原有布局管理，肉鸽 Ability 在布局完成后单独追加，因此建墙阶段刷新不会删除或复制未消费奖励。
- 奖励消费状态仍由 `rogue_reward_service` 权威维护；`builder_progression_system` 是唯一 Ability 移除者。成功打开后发布 `ROGUE_REWARD_CHANGED`，同步立即移除肉鸽 Ability，后续阶段刷新不会恢复。
- `rogue_reward_rules.csv` 新增 Tooltip 名称、描述和图标字段；`build_tooltip_definitions.py` 从该 CSV 生成统一 Tooltip CSV/Lua，runtime 显示名称、描述和 G 快捷键字段均来自生成配置。
- `combat_stats.js`、`hud_takeover.js`、`ability_tooltip.js` 将 Builder `slot_order=7` 统一投影为 G；Builder D/G 键盘路由先按 Ability 名称解析，不再依赖压缩后的显示序号；肉鸽奖励加入 G utility 映射。`ability_tooltip.js` 禁止项目技能回退到原生 Ability Tooltip，`hud_takeover.js` 增加仅针对当前自定义技能的有界异步原生 Tooltip 抑制。三份 content 源已强制编译到 game 产物。
- 自动验证：Ability utility 顺序契约通过；三份 Panorama Resource Compiler 各 `1 compiled, 0 failed, 0 skipped`，目标源码严格 UTF-8 与 `git diff --check` 通过。肉鸽集成契约在既有事件名断言 `ROGUE_EVENT_MISSING_ROGUE_REWARD_OPEN_REQUEST` 处提前失败，未将其误报为通过；`test_ability_input_lifecycle_contract.ps1` 仍受既有 `building_move.js` 的无关 `BUILDER_D_CONFLICT_GUARD_MISSING` 阻断，未修改无关文件。
- 本轮 Tooltip 修复已由用户实机确认显示正常：`ability_tooltip.js`将普通伐木工融合技能`ability_fuse_lumberjack_01..08`和超级伐木工性格被动`ability_lumberjack_personality_*`纳入自定义范围；`ability_tooltip.js`、`hud_takeover.js`、`combat_stats.js`在单位runtime计数尚未到达时使用24槽有界引擎回退，修复Builder及动态伐木工首次选中/首次悬停仍走原生Tooltip的问题。伐木工完整接管scope已纳入代理绑定。三份JS强制编译均为`OK: 1 compiled, 0 failed, 0 skipped`；高级研究所契约、严格UTF-8和`git diff --check`通过。`test_ability_input_lifecycle_contract.ps1`仍仅因既有`BUILDER_D_CONFLICT_GUARD_MISSING`失败。
- 后续所有新技能 Tooltip 必须复用 `PROJECT_CONTEXT.md` 与 `DECISIONS.md` 记录的 CSV→生成配置→runtime NetTable→Panorama 接管→强制编译→Workshop Tools 冷启动验收流程。
- Builder 的 G 标签、建墙后 G Ability 保留、鼠标点击/G 键触发和消费后只移除一次仍属于独立的后续实机验收项。

## 当前任务补充（2026-08-18）：融合运行时错误与七塔批量升级卡顿定位

- 已获用户批准进入执行模式。本轮先实施低风险诊断与幂等同步：`building_upgrade_system.lua`增加源码指纹，确认Workshop Tools实际加载版本；`tower_ability_sync.lua`以CSV生成路线行的`record_id/active_skill_ids/skill_ids/融合状态`生成签名，同一实体配置未变化时跳过Remove/AddAbility重建，并记录同步开始、跳过、结束及耗时。
- 当前源码全局搜索未发现`GetBaseAttackTime()`调用；用户日志中的旧签名错误说明实机仍可能加载旧脚本或未冷启动。本轮不在Lua中重新调用该Native getter，攻速继续只取CSV路线数据。

- 用户实机日志确认：七类转职塔均已成功施法，材料塔的`BuildingUpgradeParticle`销毁/释放链全部执行；终极融合请求最后仍被`scripts/vscripts/systems/tower_fusion_service.lua:211`阻断。
- 已确认阻断根因：`CreateUnitByName()`返回的是普通单位实体，当前项目/Dota单位API没有`SetInvulnerable`方法。删除该无效调用；终极塔创建继续使用CSV生成配置`tower_fusion_runtime.csv`中的`unit_name/model_name/route_ids`，不新增Lua硬编码基础数据。
- 已确认普通升级卡顿的代码路径：`building_batch_upgrade_service.lua`逐塔同步提交七个升级请求；每个请求在升级完成时进入`building_upgrade_system.lua:apply_tower_level()`，即使CSV目标行的模型与上一等级相同，也会调用`tower_ability_sync.sync()`。该同步会清理并重建管理技能，随后`tower_utility_ability_sync.sync()`遍历24个Ability槽并重新处理辅助技能。七座塔在相近完成时间集中执行这些实体操作，会造成同帧脚本/网络同步峰值，因此“模型不变化也卡”与模型加载并不矛盾。
- `building_visual_service.matches()`会跳过相同模型路径的`SetModel`，模型变化不是普通升级必经步骤；模型异步预载只在资源未Ready时排队。因此当前日志中的Monkey King附件资源错误不是七塔普通升级卡顿的充分根因，而是独立的英雄附件资源加载问题。
- 本轮已保留技能槽顺序语义，并将无变化的同步改为基于CSV签名的幂等短路；Workshop Tools仍需记录七塔升级完成时间、`tower_ability_sync.sync()`耗时和最终技能显示状态，以确认同帧峰值是否下降且动作没有回归。
- 静态验证已通过：`tower_fusion_service.lua` Lua 5.1语法、现有`BUILDING_BATCH_UPGRADE_CONTRACT_PASS`和限定文件`git diff --check`。当前未发现独立的箭塔融合契约脚本；融合成功、终极塔位置/属性/能力及七塔实际卡顿仍需冷启动Workshop Tools实机确认。
- 2026-08-19复核并加固融合事务：旧版普通单位实体调用不存在的`SetInvulnerable`会在七塔消费后中断创建；当前源码已删除该API。融合现改为先按CSV配置预创建并完整初始化终极塔、忽略七座待消费材料验证原点网格，成功后才请求销毁七塔并提交占格/runtime；初始化异常或网格失败不消费材料，消费失败会删除预创建实体。专项契约禁止无效API并约束prepare→consume→commit顺序；仍需Workshop Tools完全冷启动确认实机加载新脚本。

## 当前插入任务（2026-08-18）：普通伐木工点击合成超级伐木工

- 普通伐木工LV1使用5合1，LV2-LV8使用3合1；每级普通伐木工挂载对应无目标融合Ability，只有同玩家、同队、同等级、存活且未参与其他融合的普通伐木工可作为材料。LV1/LV2要求主城LV4并消耗10000/20000木材；LV3-LV8要求主城LV5并消耗30000/40000/50000/60000/70000/80000木材及5000/8000/15000/30000/40000/50000金币。失败不改变材料、资源或人口，服务端按caster加pending锁防重复请求。
- 配方和11项性格技能分别以`lumberjack_fusion_definitions.csv`、`lumberjack_personality_definitions.csv`为权威源。超级LV1-LV7每次从完整11项性格池等概率随机抽取1项，允许不同超级伐木工重复；超级LV8无性格技能。
- 超级伐木工攻击力汇总每个材料当前科技后攻击力，合成注册时剥离已包含的单个科技攻击增量，之后按材料数`n`重新投影，避免科技重复计算；基础采集量同样汇总，攻击间隔按对应普通单位间隔减少0.5秒。每击成长、减甲、效率和树等级收益按材料数`n`投影。
- 用户后续明确要求原地融合：点击施法的普通伐木工固定作为超级伐木工目标，保留实体、位置、朝向和`entindex`，不再创建新单位；其他材料消失，目标模型缩放为1.5倍。融合人口不返还，目标继承全部材料实际人口总和，因此LV1五合一仍占5人口、LV2-LV8三合一仍占3人口，最终死亡时再由既有工人死亡链一次性返还。
- 原地融合自动验证通过：`LUMBERJACK_IN_PLACE_FUSION_CONTRACT_PASS`、`WORKER_SYSTEM_TRAINING_PASS`、`LUMBERJACK_MANUAL_CONTROL_PASS`、两个目标Lua的Lua 5.1语法、严格UTF-8和限定`git diff --check`。`test_lumberjack_sound.lua`仍因既有测试fixture缺少`modifier_lumberjack_ai.lua:174`所需字段而失败，本轮未修改无关音效/AI生产逻辑。仍需Workshop Tools冷启动确认点击目标原地变为1.5倍、其他材料消失、无碰撞卡位、人口融合前后不变且目标死亡后一次性返还。
- 自动验证通过：`LUMBERJACK_FUSION_CONTRACT_PASS`、`LUMBERJACK_FUSION_RULES_LUA51_PASS`、`LUMBERJACK_FUSION_TRANSACTION_LUA51_PASS`、`LUMBERJACK_FUSION_WORKER_PROJECTION_LUA51_PASS`、目标Lua 5.1语法、严格UTF-8、定向CSV生成与限定`git diff --check`；规则/事务/生产注册投影测试覆盖主城等级、施法者等级错配、资源不足、提交失败退款、不同材料攻击快照、科技不重复计算、LV1五合一、LV2-LV8三合一和BAT减少。既有`test_repair_worker_percentage_contract.ps1`仍因修理工独立数值契约失败，本任务未修改该无关回归。尚未Workshop Tools冷启动实测融合按钮、模型/技能栏、性格实际触发、光环叠加、人口和死亡释放。
- Tooltip已补齐：融合LV1-LV8以及11项性格技能均在`resource`、`resource/localization`、`panorama/localization`的中英文入口拥有标题和说明；性格中文名称/说明由`lumberjack_personality_definitions.csv`逐字校验。`LUMBERJACK_FUSION_CONTRACT_PASS`、目标Lua 5.1语法、严格UTF-8和限定`git diff --check`通过；未修改数值继承逻辑，仍需Workshop Tools确认实际悬停显示。
- Tooltip中央数据链已补齐：`build_tooltip_definitions.py`现在从两份伐木工CSV生成8条融合和11条性格Ability行，`client_data_service.lua`将统一Ability Tooltip投影到`survival_ability_data`，保留既有技能配置覆盖优先级；契约增加8+11行、LV8无性格、生成CSV/Lua和重复key校验。自动验证完成后仍需Workshop Tools确认动态挂载技能的实际悬停显示。

## 当前插入任务（2026-08-17）：修复建造密令无法领取

- 实机发现点击`construction_order`后奖励界面不关闭。根因是`rogue_effect_registry.lua`中`grant_building_upgrade_action`被重复注册，后置旧handler覆盖了已实现的额度handler，并尝试创建已经删除的`item_survival_rogue_construction_order`，导致效果事务失败。
- 删除后置旧handler，保留由`rogue_effect_state_service`登记下一次建筑升级额度的唯一实现；验证需覆盖重复注册/旧道具引用、专项Lua 5.1测试、语法检查和建筑批量升级契约。Workshop Tools领取与升级效果仍需实机复验。

## 当前任务（2026-08-17）：新增肉鸽奖励卡牌 8-18

- `nuclear_bomb`实机使用闪退修复：确认实现中没有粒子、声音或屏幕效果；风险点为`OnSpellStart`遍历实体时同步批量`ForceKill`，并在同一施法栈移除正在执行的Item，导致死亡奖励、波次/挑战结算和尸体链集中重入。现改为施放时只快照并停用Item，按CSV的每批4只、间隔0.05秒从后续scheduler帧分批正常击杀，完成后再移除Item；每批重新校验实体、怪物标记与Boss身份。
- `nuclear_bomb`漏杀保护修复：第五波首个怪的CSV身份是`wave_leader`，此前仅存在于`MONSTER_SPAWNED`事件载荷，未写入单位实体，核弹无法识别。正式波次出生现在同步保存`survival_monster_role`和`survival_is_boss`；核弹统一排除`wave_leader`、`assault_boss`、通用Boss标记和`modifier_boss`。
- 实现并启用`nuclear_bomb`至`training_dummy`范围内用户明确指定的11张卡；全部基础数值、阶段时长、次数和目标范围继续以肉鸽CSV为权威。
- `bounty_order`只作用于挑战建筑召唤的五类挑战怪物，不影响英雄、转生或其他挑战；后续5次挑战建筑怪物成功结算时先正常发奖，再额外发放同一份奖励，失败不消费次数。
- `command_change`为下一次肉鸽卡牌选择额外增加1次刷新；`internship_certificate`为初级修理工训练上限永久增加2，不即时赠送修理工。
- 主动道具、攻击投影、吸血阶段、护甲无视、金币事务和30秒训练靶均复用现有Builder、建筑报价、英雄/塔战斗、资源和生命周期入口。自动测试必须与Workshop Tools实机验收明确区分。

## 当前任务（2026-08-17）：新增五张肉鸽卡牌

- 实现并启用`infrastructure_maniac`、`gunpowder_splash`、`kick_when_down`、`tower_network`、`corrosive_shield`，基础数值和目标定义继续以独立肉鸽CSV为权威。
- `infrastructure_maniac`免费串行完成3次随机单级建筑升级；每次完成后重新计算候选，允许同一建筑重复入选。候选必须通过`BUILDING_UPGRADE_QUOTE_REQUEST`，因此包含可继续升级的城墙、基础箭塔和已转职箭塔，自动排除施工中、升级中、已满级、前置不满足及等待转职的基础箭塔；候选耗尽时按已成功次数正常完成，不等待未来建筑。
- `gunpowder_splash`使CSV定义的穿透弩炮路线永久提高30%伤害，覆盖已有、后续转职和升级重算，不影响其他防御塔。
- `kick_when_down`使持卡玩家造成的所有合法伤害在目标怪物当前受到移动速度降低时提高50%；多个减速只触发一次，攻击速度降低等非移速效果不算。
- `tower_network`在领取瞬间统计该玩家最终路线满阶防御塔，每座固定增加全塔5%攻击，最多50%；领取后的建造、升级和销毁不改变快照。
- `corrosive_shield`按玩家隔离开启：怪物每次对持卡玩家拥有的单位正式发动普通攻击时，自身永久降低1点War3护甲。城墙只是该玩家单位之一；攻击未持卡玩家单位不触发。同一次攻击最多触发一次，技能/持续伤害不触发，减甲持续至怪物死亡并与其他减甲来源合并。
- 验证必须覆盖候选不足/升级中/等待转职、弩炮路线投影、减速识别、满阶快照、多人目标归属与腐蚀减甲去重；自动测试不等于Workshop Tools实机验收。

## 当前任务（2026-08-17）：Boss 肉鸽奖励三选一

- 用户批准实现独立肉鸽奖励系统：正式波次 Boss 死亡后触发三选一；建造者拥有一次性“开局三选一”技能，点击后打开界面并永久移除。
- 卡牌定义、效果、显示名、说明、图标、启用状态和抽取规则必须以独立 CSV 为权威。外部工作簿“肉鸽卡牌效果库”的31张卡全部录入；无法准确映射当前项目概念或原文不完整的卡先保留并禁用，不擅自改写。
- 每次 offer 展示3张互不重复的卡并提供1次免费重抽。只有实际领取过的卡永久排除；仅展示或被重抽替换的卡未来仍可出现。服务端维护玩家会话、token、队列和幂等校验。
- `冰封城墙`按清晰录像值采用攻速-15%；`炮塔串联`按每座满阶防御塔全塔攻击+5%、最多+50%。Panorama 仅借鉴 Balatro 的窄高卡、悬停抬升放大和翻牌节奏，不复制第三方GPL代码或素材。
- 验证必须区分Lua模拟测试、静态契约、Lua 5.1语法、Panorama编译和Workshop Tools实机验收；自动测试不得描述为引擎实测。
- 生产实现完成：31张原始卡全部进入独立卡牌CSV，效果和抽取规则分别由独立CSV管理；首版启用可准确接入当前系统的`防御工事`、`璀璨树苗`、`财政补贴`3张，其余28张保留原描述并注明停用原因。当前首轮可稳定展示3张，领取后卡池按“已领取永久排除”缩小；在更多卡启用前不通过重复已领取卡强行补足3张。
- 服务端会话按玩家维护当前offer、已领取集合、一次免费重抽、递增token和Boss奖励队列。重抽只替换当前展示并使旧token失效；未领取或被重抽的卡不进入永久排除。正式波次Boss只消费`wave_system`登记的`meta.is_boss`，击杀者无法解析时向有效Radiant玩家分别排队。
- 建造者开局第2业务槽新增一次性技能。服务端成功创建或排队奖励后记录已消费，立即触发Builder权威布局同步并永久替换为隐藏占位；动态creature技能通过UI路由直达同一服务端请求，Lua`OnSpellStart`保留为原生施放入口。
- 效果首版完成：金币和当前木材百分比走既有资源事务；防御塔攻速进入`technology_stat_manager`独立rogue永久层并沿既有`TECHNOLOGY_STATS_CHANGED`刷新所有塔。Panorama为独立overlay，整卡点击领取，使用Dota Ability图标、窄高牌面、悬停抬升缩放、翻牌和错峰入场，不含第三方代码或素材。
- 自动验证通过：`ROGUE_REWARD_SERVICE_LUA51_PASS`覆盖三卡去重、一次重抽、旧token、防重复领取、未领取可再出现、队列提升和3种效果；目标Lua 5.1语法、97模块配置`--check-only`、31卡/3启用契约、严格UTF-8和限定`git diff --check`通过。新JS、CSS、XML及manifest加载链均为`1 compiled, 0 failed, 0 skipped`。
- 2026-08-18接入修复：`core/events.lua`补齐六个肉鸽请求/变更事件常量，避免服务、Builder同步、主动技能与Boss派发使用空事件名；`ability_runtime_service.lua`从生成的Builder阶段配置按技能名发布`builder_slot_order`，开局肉鸽技能固定投影为W槽。Builder行为测试新增开局W显示、消费后真实技能移除、隐藏占位和后续同步不恢复覆盖；专项契约同时锁定奖励服务初始化、主动技能统一请求、正式波次Boss向活动玩家派发及CSV槽位来源。
- 验证边界：尚未Workshop Tools冷启动实测开局技能槽、Boss击杀触发、连续奖励排队、三卡点击、重抽动画、资源到账与塔攻速实际刷新；自动测试和Resource Compiler结果不等于引擎实机验收。

# 当前任务（2026-08-16）：挑战怪失败判定与零碰撞体

- 用户确认挑战怪召唤后存活达到60秒，或城墙当前生命严格低于最大生命50%时挑战失败；恰好50%不失败。失败保留本次技能冷却，不发奖励，也不消耗本局该类挑战次数。
- 用户追加确认所有挑战怪Hull碰撞体为0。四项基础数据已写入`global_rules.csv`并定向生成：挑战怪Hull 0、挑战存活时限60秒、城墙失败阈值50%、城墙生命检查间隔0.1秒；运行时不硬编码判定数值。每个挑战实例使用独立生命周期ID和具名检查/超时任务，统一结算入口先标记状态、取消任务并移除奖励映射，再删除失败单位，死亡回调按单位身份幂等处理。
- 挑战次数递增已从生成路径移动到正常击杀奖励路径。即时低血失败返回`ok=false, cast_consumed=true`，手动能力据此保留引擎冷却；自动召唤显式启动冷却后停止本轮扫描。死亡事件再次检查`>=60秒`与城墙低血，覆盖定时任务和死亡同帧边界。
- 自动验证通过：`WAVE_FLYING_COLLISION_PASS`、`BUILDING_CHALLENGE_SERVICE_LUA51_PASS`、`BUILDING_CHALLENGE_ABILITY_FACTORY_LUA51_PASS`、`BUILDING_CHALLENGE_CONTRACT_PASS`、配置`CheckOnly`、目标生成一致性、Lua 5.1语法及限定`diff --check`。碰撞测试覆盖地面/飞行挑战怪profile及实际`SetHullRadius(0)`调用；失败行为测试覆盖即时/延迟低血、50%边界、定时和死亡同帧60秒边界、正常击杀、重复死亡、奖励、挑战次数、手动/自动冷却。尚未执行Workshop Tools实机验证，自动测试不等于引擎实机验收。

# 前序任务（2026-08-16）：挑战建筑怪物补齐 N1-N5 数据与实例显示名

- 用户确认`building_challenge_waves.csv`需要覆盖N1-N5，并采用临时方案：N2-N5完整复制N1战斗数值，只区分`difficulty_id`和唯一ID，不引入未经确认的难度倍率。
- 实施范围：权威CSV扩展为5难度x5种挑战怪x20次挑战共500行；`challenge_wave_id`改为`n*_challenge_monster_**_wave_**`，新增`difficulty_id`和`display_name`。显示名必须与`building_challenge_definitions.csv`对应，召唤按`wave_system.get_difficulty()`消费，并投影为实例`survival_display_name`供现有选中单位UI读取。
- 保留工作区已有的N1山岭巨人第1次`health=6000`，修复该CSV现有中文乱码；不覆盖或回退正在进行的挑战怪碰撞修改。验证覆盖500行矩阵、ID唯一、难度索引、跨表显示名一致、N2-N5临时复制N1、实例显示名、生成一致性、Lua 5.1语法、UTF-8及限定diff。
- 实施完成：CSV现为500行严格矩阵，ID从`n1_challenge_monster_01_wave_01`到`n5_challenge_monster_05_wave_20`；五种显示名分别从定义表同步为山岭巨人、树人、红龙、剑圣、炼金。挑战服务按当前全局难度、怪物ID和独立挑战次数三维查行，并为实例保存难度与显示名；原`health=6000`保留，CSV中文编码恢复为UTF-8 BOM。
- 自动验证通过：`BUILDING_CHALLENGE_CONTRACT_PASS definitions=5 rows=500 difficulties=5 waves=20 rewards=8`、`BUILDING_CHALLENGE_SERVICE_LUA51_PASS`、矩阵/唯一ID/UTF-8审计、两个目标Lua的Lua 5.1语法、94模块正式生成、95生成Lua无U+FFFD、配置`CheckOnly`及限定`diff --check`通过。尚未Workshop Tools冷启动实测N1-N5分别召唤属性与选中面板名称，自动验证不等于引擎实机验收。

# 当前任务（2026-08-16）：挑战怪与正式波次同时生成时卡住

- 用户确认采用推荐方案：仅关闭挑战怪的单位碰撞，保留挑战怪基础Hull、移动、攻击、奖励和正式波次怪之间的原有碰撞行为。
- 已确认根因：`wave_system.spawn_challenge_monster()`虽设置了挑战身份字段，但`wave_monster_collision.profile()`当前始终返回`no_unit_collision=false`，导致挑战怪仍会占用正式波次怪的实体碰撞空间和城墙接敌通道。
- 实施边界：挑战身份由运行时生成边界显式传给共享碰撞profile；基础生命、攻击、护甲、模型、数量和生成时序继续来自现有CSV及其生成Lua，不新增硬编码战斗数值。
- 自动验证完成：挑战profile行为、`modifier_enemy_wall_ai`的`NO_UNIT_COLLISION`状态、Lua 5.1语法、挑战契约、生成配置完整性和限定`git diff --check`均通过；未修改CSV或生成Lua。Workshop Tools仍需实测同时生成时的移动与攻击表现。

## 当前实施任务（2026-08-16）：恢复多重塔中间六级数据

- 用户确认恢复`multi_tower_lv05`及`piercing_ballista_lv01`至`piercing_ballista_lv05`共6条缺失记录，并沿用当前炙热巨箭/多重攻击规则整理技能继承。
- 权威数据只修改`data/csv/建筑与工人系统/防御塔/tower_class_multi.csv`：多重塔LV5使用`multi_attack_lv05`；穿透弩炮各级继承`multi_attack_lv05`并使用同级`piercing_ballista`；炙热巨箭LV1-LV10继续使用`multi_attack_lv05|piercing_ballista_lv05|burning_great_arrow_lv01`，由运行时维持巨箭结算主目标、多重攻击仅结算额外目标。
- 前两阶段继续隐藏原生普通攻击弹道与伤害，恢复记录不重新填写`projectile_model`；移动与拆除继续作为`active_skill_ids`最后两个技能。验证包括三阶段等级连续性、技能引用、CSV与生成Lua一致、相关多重塔契约、Lua 5.1语法及限定`diff --check`；自动验证不能称为Workshop Tools实机验收。
- 实施与自动验证完成：多重路线现为多重塔LV1-LV5、穿透弩炮LV1-LV5、炙热巨箭LV1-LV10共20条连续记录，6条恢复数据已定向生成到`tower_class_multi.lua`。结构/唯一性、技能引用、`TOWER_MULTI_ATTACK_RUNTIME_PASS`、`TOWER_MULTI_DAMAGE_CONFIG_PASS`、`TOWER_MULTI_DAMAGE_RUNTIME_PASS`、`ARROW_TOWER_UTILITY_CONTRACT_PASS`及生成Lua的Lua 5.1语法通过。`test_tower_multi_visual_config.lua`完成多重路线断言后仍失败于既有无关死亡塔资产包`tower_death_templar_assassin`不完整，本轮未修改该资源；尚需Workshop Tools冷启动逐阶段升级验收。

## 当前实施任务（2026-08-16）：金矿两个科技误报未拥有

- 用户实机反馈金矿“提升采金效率”和“提升采金暴击”均无法点击，返回未拥有；已批准按金矿权威CSV与现有Ability购买链修复。
- 根因确认：`purchase_next_technology()`已将Ability传入的`entindex`规范化转发为`source_entindex`，但`purchase()`的金矿ownership校验仍读取已不存在的`payload.entindex`，导致`BUILDING_QUERY_REQUEST`始终查询空实体并返回`gold_mine_not_owned`。
- 实施边界：购买校验统一消费`source_entindex`并兼容旧`entindex`直调；保留建筑ID、player owner、科技组和来源校验。不修改`technology_definitions.csv`中的费用、等级、效果、前置或研究所分组。验证包括金矿专项契约、相关Lua行为回归、Lua 5.1语法及限定`diff --check`；自动验证不能称为Workshop Tools实机验收。
- 实施与自动验证完成：金矿ownership查询现消费规范化的`source_entindex`并兼容直接`entindex`；生产购买链Lua 5.1行为测试覆盖采金效率、采金暴击和非owner拒绝。`GOLD_MINE_TECHNOLOGY_OWNERSHIP_LUA51_PASS`、批量升级、自动协调、专项契约、研究事务、目标Lua语法及限定`diff --check`通过。两个既有研究测试仍分别失败于缺少当前必需的高级研究所来源实体，以及旧断言要求高级速度在Lv.5解锁而当前CSV权威要求Lv.10；均未执行金矿分支，本轮未修改。尚需Workshop Tools冷启动实机点击W/E验收。

## 当前实施任务（2026-08-16）：转职塔移动与拆除技能右置

- 用户实机反馈基础箭塔的移动与拆除技能已经位于技能栏右侧，但转职后的防御塔没有继承该布局优化；已批准统一修复全部转职路线。
- 权威技能集合与顺序必须来自各防御塔CSV的`active_skill_ids`；移动`ability_building_blink`位于拆除`ability_destroy_arrow_tower`左侧，二者保持为所有其他可见塔技能之后的最后两个技能。
- 实施边界：只修复转职及升级时的运行时Ability排列与必要契约，不修改塔数值、技能效果、升级费用、移动/拆除权限或HUD视觉样式。验证包括基础箭塔与全部转职路线、转职后顺序、CSV与生成Lua一致、Lua 5.1语法、相关契约及限定`diff --check`；自动验证不能称为Workshop Tools实机验收。
- 实现完成：`tower_ability_sync.lua`在挂载转职路线技能前先清除移动/拆除，主体技能占用低位空槽后再按CSV顺序重加移动、拆除，消除Source 2复用低位Ability索引导致工具技能滞留在左侧的问题；基础箭塔和全部转职塔仍只从CSV读取技能集合与顺序。
- 自动验证完成：真实生产同步模块的Lua 5.1行为桩验证转职后顺序为升级、路线技能、移动、拆除；八份塔CSV及对应生成Lua专项契约、三个目标Lua语法和限定`git diff --check`通过。既有`test_arrow_tower_completion.lua`因工作区已有`building_system.lua`首字节被MSYS Lua识别为非法字符而在加载阶段失败，未执行到本次逻辑；尚未进行Workshop Tools冷启动实机HUD验收。
- 本轮修复：融合资格判断现先于Ability挂载，满足七条路线均为CSV最大等级且未参与融合时，按`ability_tower_fusion`、CSV主动技能、CSV路线技能、移动、拆除的顺序重建受管理Ability；不调用动态建筑上不可靠的`SetAbilityIndex()`，保留Panorama的`D`移动输入路径。融合服务既有的并发锁、创建后消费与创建失败回滚继续保留。
- 本轮自动验证：目标技能同步、工具同步、融合服务和融合Ability的Lua 5.1语法通过；`ARROW_TOWER_UTILITY_CONTRACT_PASS`通过；未运行Workshop Tools，因此能力栏原生索引、Q/D显示、Roshan模型、七路攻击和实机融合点击仍待冷启动验收。
- 本轮回归修复：融合消费现在接收并校验玩家当前全部箭塔，按拆除生命周期逐一`ForceKill(false)`并在消费前确认拆除Ability可用；融合技能刷新覆盖玩家所有符合条件的终阶路线塔；终极塔直接创建在施法塔原点，不再改投附近网格。Panorama按Ability身份固定移动为`D`、拆除为`G`，避免显示引擎默认`T/Y`。

## 当前实施任务（2026-08-16）：城墙四点均匀接敌寻路

- 用户实机反馈首版最外两个槽位与城墙上下端模型相卡，且128槽间距恰好给第五只Hull 32走地怪留下插入空间；要求四点向中间稍微收窄并禁止第五只插入前排。
- 二次调整：槽间距从128收为112，四点横向偏移由`±192/±64`改为`±168/±56`；到位阈值从56收为24以减少前排漂移；等待排距从96增至160，使第五只首排等待点从墙外384移至448，不进入城墙攻击边界。怪物Hull、城墙Hull、攻击范围和模型保持不变。
- 三次调整：用户实机确认112间距下仍只有中间两只持续攻击，批准只将槽间距收为80，四点横向偏移改为`±120/±40`，优先让外侧怪避开城墙两端模型。法向偏移288、到位阈值24、等待排距160、Hull、攻击范围、模型和模型缩放均保持不变；仍需冷启动实机确认四只持续攻击。
- 四次优化：用户实机确认地面怪攻击动画仍会卡顿。代码诊断确认地面怪未到槽位或在攻击中因碰撞漂出24范围时，`0.5s` AI Tick会重复清空强制攻击目标并重发相同移动命令，能够持续打断攻击动画。现按槽位/队列身份与目标坐标去重移动命令，同一导航目标只下达一次；到达24范围后锁定接敌状态，新增CSV权威退出阈值48，只有漂移超过48才单次恢复移动。等待怪晋升槽位和切换城墙时会重置瞬态导航状态。
- 用户确认当前城墙偶发只有两只走地怪攻击，模型拥堵导致后续怪物无法接近；批准沿城墙同一侧均匀分布四个接敌位置，不偏向上下两端，目标为稳定四只走地怪同时攻击。
- 实施边界：仅正式走地怪使用四槽寻路；飞行怪保持直接攻击城墙。四个位置按城墙运行时朝向计算，首个占位怪确定接敌侧；前四只独占槽位，后续怪物在对应槽位外侧排队，槽位释放后再补位。不得修改怪物数量、攻击范围、Hull、模型或模型缩放。
- 基础位置参数必须来自`global_rules.csv`并生成到Lua；运行时不得写死地图坐标。验证范围包括四槽均匀分布、同侧、去重、死亡释放、第五只排队、飞行绕过、Lua 5.1语法、CSV生成一致和限定`diff --check`。自动验证不能称为Workshop Tools实机验收。
- 实施完成：新增每座城墙独立的四槽与等待队列状态；根据首只走地怪相对城墙的来向，从城墙两个局部轴中选择同侧法向，另一轴按80间距均匀布置四槽。前四只走地怪先移动至槽位再攻击，后续怪物按每行四只、向外160间距排队；死亡、目标切换和Modifier销毁均释放占用。飞行怪继续直接强制攻击城墙。
- 五次调整：用户反馈第二排攻击距离可越过第一排命中城墙。正式地面怪原型CSV攻击距离最高为236；本轮仅将第一排法向偏移从288外移至384，使第一排位于384、第一等待行位于544，保持槽间距80、排队间距160、到位/退出阈值24/48和移动去重逻辑不变，目标是阻断第二排越过第一排攻击城墙。
- 六次修复：用户确认四槽占满后后续地面怪会转攻其他单位。根因是排队分支提前返回，且移动命令会清除强制攻击目标；现将接敌位置降级为纯移动/占位提示，所有地面怪在接近、排队和补位期间始终锁定对应城墙，移动命令不再清除城墙目标。固定四槽不再限制城墙仇恨资格；动态接敌带和地面Hull负责实际空间占位，空旷位置可继续展开更多单位。
- 调试显示：当前工程没有独立透明格子/小墙实体，新增调试开关绘制真实地面怪Hull、四个推荐接敌格和排队格；图形颜色分别为蓝色、空闲绿色/占用红色/排队黄色，统一抬高96单位。修正几何前保持开关开启，确认后将`wall_engagement_debug_enabled`改为0即可关闭。
- 七次调整：用户实机确认应为三个实际接敌格、四条边界，并认为怪物离墙384过远。权威CSV将实际槽位改为3、法向偏移先收近至288，槽间距80和排队间距160不变；三个绿色/红色圆仍表示可占用槽位，另以四条青色短线表示纯调试边界，边界不参与`claim`、排队或攻击逻辑。第一等待行相应位于448。需冷启动观察收近后第二排是否因攻击距离覆盖城墙而直接攻击；若出现则优先增加前排攻击资格约束，不把调试边界误做碰撞实体。
- 权威CSV当前为槽位数3、槽间距80、墙外偏移288、到位阈值24、退出阈值48、排队间距160并生成到`global_rules.lua`。专项行为测试覆盖前三只占位、第四只排队、三槽死亡补位、三圆四边界绘制及排队怪持续锁定城墙；仍需执行Lua 5.1行为/语法、配置定向生成一致、UTF-8和限定`diff --check`。自动验证不等于Workshop Tools实机验收。

## 当前实施任务（2026-08-16）：高级伐木效率金币与木材费用交换

- 用户确认研究所科技“高级伐木效率”的金币消耗与木材消耗填反，并批准交换全部30级费用。
- 权威数据仅修改`data/csv/建筑与工人系统/technology_definitions.csv`中`advanced_lumberjack_efficiency_01`至`advanced_lumberjack_efficiency_30`的`gold_cost`与`wood_cost`；随后通过现有CSV生成链同步Lua。
- 验证范围：30级费用逐行交换、相邻科技不变、CSV与生成Lua一致、相关研究所契约、Lua 5.1语法、配置检查及限定`git diff --check`。自动验证不能称为Workshop Tools实机验收。`CSV_ADVANCED_LUMBERJACK_PASS`、`GENERATED_ADVANCED_LUMBERJACK_PASS`、`ADVANCED_RESEARCH_LAB_CONTRACT_PASS`、Lua 5.1语法、配置生成和`git diff --check`均已通过。

## 当前实施任务（2026-08-17）：持久化在线计时钓鱼奖励纵向切片

- 用户已批准进入Act模式。目标链路固定为Dota服务端Lua -> 本机带共享令牌认证的Python JSON API -> Supabase PostgreSQL；客户端和Lua均不得持有Supabase URL或数据库密钥。
- 计时语义固定为只累计在线租约时间、离线冻结、重连恢复剩余秒数；成功发放后重新抽取60至600秒。发放历史使用append-only grant，永久效果使用独立聚合投影，二者与下一计时器必须由单个数据库RPC原子提交。
- 本轮工作区保护基线：已有`.cline/content_survival`、`building_challenge_waves.csv`及其生成Lua修改，并有大量未跟踪旧测试文件；均不属于本任务，不得覆盖、回滚或清理。
- 当前恢复摘要只保留三条待复核定义：`奖励正文待复核`、`增加伐木工攻速4倍（待复核）`、`伐木工攻速5%`的符号/含义；仓库和会话文档中没有完整生产奖励清单。实现不得猜测缺失数值，待复核行必须保持禁用，自动测试使用独立fixture定义验证纵向链路。
- 实施范围：CSV schema与生成Lua、Supabase migration/原子RPC、Python 3.14标准库API、Lua 5.1 HTTP Provider/在线租约服务、档案revision复用、永久效果独立投影、幂等/重连/失败恢复测试、严格UTF-8与限定差异检查。没有Supabase项目和服务端密钥时只能完成静态、模拟和本机HTTP验证，不能称为远端数据库或Workshop Tools实机验证。
- 实施完成：新增两张CSV及生成Lua；migration包含Steam Account ID账号、不可变定义版本、单账号session租约、冻结计时器、append-only grant、永久聚合、幂等响应和单事务发放RPC；Python 3.14标准库API实现loopback绑定、Bearer认证、严格环境配置、CSV SHA-256同步和Supabase REST/RPC；Lua HTTP Provider复用既有快照/revision校验，心跳只在`http_fishing` override下启用，断线/连接状态停止租约，同一request/grant按ID重试去重。
- 永久效果独立投影已接入`hero_all_attributes_flat`、`hero_attack_flat`、`lumberjack_attack_speed_pct`和`gold_mine_income_pct`。即时金币/木材/人口上限仅保证同局Lua session按grant ID幂等，跨进程提交后崩溃仍需持久outbox/ack；团队资源尚未完成玩家隔离，因此永久开局资源不得投影到共享团队账户。
- 自动验证通过：Python 5项单元/真实loopback HTTP测试、`FISHING_REWARD_LUA51_PASS`、`FISHING_REWARD_CONTRACT_PASS`、原档案Lua 5.1与PowerShell回归、14个目标Lua的`luac5.1 -p`、Python compileall、两张CSV定向生成逐字节一致、严格UTF-8及限定`git diff --check`。本机无`psql`和Supabase CLI，migration仅完成静态契约检查；未执行远端Supabase或Workshop Tools实机验证。
- 下一步阻断：用户提供完整确认后的奖励表并解决三条待复核定义，创建Supabase项目并提供仅Python进程可见的`SUPABASE_URL`/`SUPABASE_SERVICE_ROLE_KEY`及本机API token。之后才能启用生产定义、实际执行migration、启动API并进行断线重连/并发/重启/数据库故障与Dota HTTP实机验收。
- 2026-08-17后续实施完成：即时/永久grant统一为“本地应用成功后按grant ID仅发布一次`FISHING_REWARD_GRANTED`”。Lua从本地CSV生成定义复核版本、reward/effect/scope/enabled和amount范围；永久路径要求中奖玩家的档案快照及永久投影已成功，即时路径因现有team-scoped资源账户不能保证owner-only而在共享写入前明确失败关闭。
- 安全公告已接入：grant订阅者仅使用服务端玩家名、CSV `display_name`和已校验数值构造`UI_NOTIFICATION audience=all`；UI路由仅对显式全员通知广播且只转发`message/level`，既有个人通知保持定向。Panorama现有`NotificationContainer`可直接渲染，无需修改Content资源。
- 新增独立测试CSV fixture：definition version 9001、固定10秒及永久`hero_attack_flat +5`；即时金币失败关闭由Lua行为测试覆盖，不进入数据库fixture池。对应Lua配置由同一CSV生成器生成，只有Tools Mode且ConVar精确为`automation_9001`时可加载，生产CSV继续全部禁用。
- 本轮新增验证通过：`FISHING_REWARD_LUA51_PASS`、`UI_NOTIFICATION_AUDIENCE_LUA51_PASS`、`FISHING_REWARD_CONTRACT_PASS`、Python 5项unittest/loopback HTTP、玩家档案Lua/契约回归、初始资源和人口训练回归、目标Lua 5.1语法、Python compileall、生产/fixture CSV生成逐字节一致、严格UTF-8及限定`git diff --check`。这些不是Supabase或Workshop Tools实机验证。
- 2026-08-17部署迁移：`backend/`、`supabase/`和后端环境模板已迁至独立`D:\survival_database`仓库，addon继续唯一持有生产CSV及生成Lua。Python通过`SURVIVAL_ADDON_ROOT`读取权威CSV；独立启动脚本保持loopback、加载本机`.env`并收紧NTFS ACL，支持`-Automation9001`测试fixture。
- 正式数据库账号改为Python边界的`HMAC-SHA256`假名，Supabase不保存原始Steam Account ID，Lua响应仍恢复原始ID以保留既有绑定校验。`FISHING_ACCOUNT_ID_PEPPER`是稳定账号映射密钥，必须独立生成、备份且不得上线后直接更换。新`SUPABASE_SECRET_KEY`和legacy service-role均兼容。
- 当前仍缺真实Supabase项目、URL和Secret Key，生产奖励CSV仍全部禁用；远端migration、API实际启动、Dota双客户端与故障场景仍未验证。
- 迁移后本机`.env`已由初始化脚本生成64字符随机API Token和独立pepper，ACL仅允许当前Windows用户与`SYSTEM`，并确认被目标仓库Git忽略；`SUPABASE_URL`和Secret Key仍为空，因此启动脚本按预期失败关闭。最终自动验证通过：Python 9项、跨仓钓鱼契约、钓鱼/公告/档案/初始资源/人口Lua回归、目标Lua 5.1语法、Python编译、PowerShell解析、CSV生成逐字节一致、数据库仓严格UTF-8/空白检查及限定diff检查。未执行远端Supabase或Workshop Tools实机验证。

## 当前实施任务（2026-08-15）：英雄永久异步预载与召唤READY门禁

- 用户报告部分电脑执行`addhero`时客户端闪退，怀疑英雄主体、饰品组件和常驻粒子在`ReplaceHeroWithNoTransfer()`后同帧集中实例化造成冷资源峰值。调查确认六个英雄主体已在地图`Precache`阶段同步预载，英雄饰品也由`hero_cosmetic_service.precache()`同步预载，但尚未纳入游戏开始后的异步完整bundle队列。
- 代码库没有`collectgarbage("collect")`或`ForceGarbageCollection`；现有`collectgarbage("count")`只读取Lua内存。Workshop Lua没有已确认安全的运行时模型卸载API，`asset_preload.retire()`仅改变项目Lua状态且阻止后续请求，不能描述为Source 2资源卸载。
- 用户批准方案：六个英雄及其饰品/粒子以CSV资源bundle为权威，在`GAME_STARTED`后宽松分帧异步加载，`resident_policy=permanent`，整局不调用项目退休/释放路径。目标英雄未READY时，`addhero`和祭坛召唤返回已受理等待态，提示“英雄资源准备中”；READY后重新执行完整权威校验并自动召唤，失败则清理等待态、明确提示并允许重试。
- 并发语义：同一bundle全局去重；同一玩家重复选择同一英雄幂等；改选另一英雄时最新请求覆盖旧请求；不同玩家互不覆盖。不得修改英雄平衡、资格、ownership、`HERO_SUMMONED`载荷和正式英雄cosmetics生命周期。
- 验证范围：CSV/生成Lua一致性、完整代理KV依赖、开局渐进调度、多人/覆盖/失败重试门禁、`addhero`完成时序、祭坛回归、Lua 5.1语法、配置CheckOnly、严格UTF-8和限定`git diff --check`。自动验证不能替代Workshop Tools冷启动下的帧时间、显存和闪退验证。
- 实施完成：六个战斗英雄已从`addon_game_mode.precache()`同步单位列表移除；CSV新增`hero_permanent`永久bundle，精确保留现有Axe Searing Annihilator五件套、Monkey King Demon Trickster四件套/四条ambient、Blademaster Cyclopean Marauder五件套，Doom/Shadow Fiend/Drow仅使用原生主体。六个`asset_proxy_hero_*`的KV依赖与CSV一致，运行时cosmetics改为从CSV bundle读取，Builder继续保持原生外观。
- `hero_asset_preload_service`在`GAME_STARTED`启动30秒渐进窗口（80%窗口内发出六项请求），召唤时目标bundle升级为urgent并允许FAILED重试。`hero_summon_system`按玩家保存generation等待项：同英雄重复幂等且合并完成回调，改选覆盖旧项，多玩家隔离；READY后重新执行祭坛、主城、VIP、位置和重复召唤校验，再进入`ReplaceHeroWithNoTransfer()`，并显式恢复owner/control兜底。
- `addhero`在资源等待时不再提前加钱、解锁商城或显示测试环境完成；异步召唤成功后才执行这些动作。正常祭坛Ability对pending保持已受理语义，资源失败会提示并清理等待项，后续请求可重试。
- 自动验证通过：`HERO_ASSET_PRELOAD_SERVICE_PASS`、`HERO_SUMMON_PRELOAD_GATE_PASS`、`HERO_SUMMON_OWNER_PASS`、`ADDHERO_CHEAT_PASS`、`HERO_COSMETIC_SERVICE_PASS`、`ASSET_PRELOAD_GRADUAL_PASS`、`HERO_ASSET_PRELOAD_CONTRACT_PASS`、`ADDON_PRECACHE_CONTRACT_PASS`、目标Lua 5.1语法和限定`git diff --check`。仍需Workshop Tools完全Stop后冷启动，记录六bundle READY时序/帧尖峰，分别测试两名玩家改选和同时召唤，并检查客户端闪退与新`.mdmp`；未执行前不得称为引擎实机通过。
- 2026-08-19续会话复核：当前磁盘生产实现与上述记录一致，无需重复修改。六条`hero_permanent`权威CSV、14个饰品组件、猴王4条常驻粒子、六个精确代理KV和运行时cosmetics逐项一致；召唤门禁确认同英雄请求合并、改选generation覆盖、READY后重走完整校验、FAILED清理可重试及多玩家隔离。新执行的定向契约输出`HERO_RESOURCE_TARGET_CONTRACT_PASS bundles=6 components=14 persistent_effects=4`，10个相关生产/生成Lua输出`HERO_RESOURCE_LUAC51_PASS files=10`，三份目标生成Lua临时重建逐行一致，目标严格UTF-8和限定diff通过。全量`build_configs.ps1 -CheckOnly`仍被无关既有`config/generated/rogue_reward_effects.lua`中的`U+FFFD`替换字符阻断，本轮未越界修改；Workshop Tools冷启动、多客户端并发、帧尖峰、显存、外观和闪退仍未实机验证。
- 2026-08-19资源缺失修复：`asset_preload_service`现在在代理异步请求前展开并调用bundle的主体模型、CSV附件模型、粒子和声音资源；显式资源请求抛错时bundle进入FAILED且不启动代理，代理回调完成后才发布READY。Doom补齐7个ReplaceHero原生穿戴模型，Shadow Fiend补齐原生`nevermore/wings`，Axe补齐5个原生穿戴模型；这些依赖仅进入`asset_catalog.csv`预载列表和代理KV，不进入`asset_components.csv`，因此不会被项目重复挂载。当前安装VPK确认目标21个模型全部存在；Automaton音效事件仍未写入CSV，因为只有攻击音频文件索引，尚未证明事件映射。新Lua行为/契约、7个Lua 5.1语法、CSV生成字节一致、严格UTF-8、VPK索引和限定diff通过；仍需Workshop Tools冷启动确认ReplaceHero时序、模型告警和`Hero_Axe.Footsteps.Automaton`独立告警。
- 2026-08-19生命周期修正：已删除运行期`PrecacheResource(..., nil)`。`hero_permanent`的CSV主体/附件/粒子/声音统一在地图`M.precache(context)`有效上下文注册，但静态注册不提前发布bundle READY；运行期仅以`PrecacheUnitByNameAsync`代理回调作为完成门禁。启动注册失败会保留资源FAILED并使对应bundle以`resource_precache_failed`失败，代理不会启动；无代理的direct运行时资源请求明确FAILED。专项Lua 5.1行为/语法、PowerShell契约、严格UTF-8和限定diff通过；仍需Workshop Tools完全Stop后冷启动验证Doom、Shadow Fiend、Axe资源告警、READY时序及多客户端行为。
- 2026-08-19影魔/黑暗游侠默认穿戴补齐：Shadow Fiend新增`shadow_fiend_shoulders`、`shadow_fiend_arms`、`shadow_fiend_head`三项原生预载依赖；Drow Ranger新增`drow_weapon`、`drow_cape`、`drow_bracer`、`drow_armor`、`drow_legs`、`drow_haircowl`、`drow_quiver`七项原生预载依赖。十项资源均只进入`asset_catalog.csv`附件列表和对应代理KV，不进入项目饰品组件，避免ReplaceHero后重复挂载。目标生成逐字节一致、资源契约、Lua行为、Lua 5.1语法、严格UTF-8和限定diff通过；当前环境仅确认`pak01_dir.vpk`文件存在，因无VPK目录读取工具未将十项路径记为VPK存在性通过。仍需Workshop Tools完全冷启动召唤Shadow Fiend/Drow Ranger确认nonresident告警消失、精确代理回调前保持LOADING以及最终原生外观。
- 2026-08-20用户实机验收：用户确认 Shadow Fiend 与 Drow Ranger 模型成功加载。上述十项原生 wearable 预载依赖、CSV 到生成 Lua、代理 KV 和 READY 门禁链路验证完成，本任务不再处于待验收状态。后续英雄默认穿戴资源继续遵循“CSV 权威登记、生成配置、代理 precache、只预载不重复挂载、精确代理回调后 READY”的流程。

# Current Task

Last Updated: 2026-08-25

## Current Milestone

**Backend Integration**：完成 Dota 2 游戏端与 Python HTTP Server / Supabase 的 Session、在线 checkpoint 和终局结算闭环。

Sprint 范围和门禁见 `CURRENT_SPRINT.md`。

## P0

### TASK-001 Player Session

- Status: `DONE`
- Owner: `@xxx`
- Dependency: None
- Detail: `tasks/TASK-001.md`
- Blocker: None；2026-08-25 用户确认城墙毁坏最终结算验收通过。

### TASK-002 Online Checkpoint

- Status: `READY`
- Owner: `@xxx`
- Dependency: `TASK-001 must be DONE`
- Detail: `tasks/TASK-002.md`
- Blocker: None；进入实现前仍需登记 Affected Files。

### TASK-003 Offline Finalization

- Status: `READY`
- Owner: `UNASSIGNED`
- Dependency: `TASK-001 must be DONE`
- Detail: `tasks/TASK-003.md`
- Blocker: 需要分配唯一 Owner 并登记 Affected Files。

## P1

### TASK-004 Attribute Sync

- Status: `BACKLOG`
- Owner: `UNASSIGNED`
- Dependency: `TASK-001 must be DONE`
- Detail: `tasks/TASK-004.md`

### TASK-005 Attribute Purchase

- Status: `BACKLOG`
- Owner: `UNASSIGNED`
- Dependency: `TASK-004 must be DONE`
- Detail: `tasks/TASK-005.md`

## Current Blockers

1. 正常发布 Arcade 的 Game Server/Lua 主机与 `127.0.0.1` 归属仍为 `MODEL-D`；生产 Session Foundation 必须先完成 `architecture/MULTIPLAYER_TOPOLOGY_REPORT.md` 的最小发布 Lobby 实验。
2. `TASK-003` 尚未分配唯一 Owner；`TASK-002`、`TASK-003` 和 `TASK-004` 进入实现前仍需登记 Affected Files。
3. Dota 终局后的 `session_closed` callback 尚未完全观察到，但不阻断已通过的本地 Workshop 城墙毁坏服务端 final 持久化验收。
4. 生产双玩家端到端验收尚未完成，作为独立后续工作保留。

## Collaboration Chain

```text
PROJECT -> CURRENT_SPRINT -> CURRENT_TASK -> TASK -> Files -> Tests
```

- `PROJECT_CONTEXT.md`：稳定项目事实。
- `CURRENT_SPRINT.md`：当前迭代范围和门禁。
- 本文件：Task 状态、Owner 和依赖索引。
- `tasks/TASK-xxx.md`：目标、Affected Files、Testing Matrix 和交接信息。

## Dispatch Rules

- 一个 Task 只能有一个 Primary Owner；Owner 表示当前主要推进责任，不是权限系统。
- 其他成员可以 Review、Debug、修复、提出改动或接手；AI 不得仅因 Owner 不同而自动拒绝。
- `Dependency != DONE` 时不得进入实现。
- 修改前必须检查 Affected Files、Git 状态、当前 diff、Task progress 和其他 `IN_PROGRESS` Task 的文件冲突。
- 可能产生文件冲突时输出 `TASK COLLISION WARNING`，说明冲突范围并交由人决定；不自动覆盖或回滚他人修改。
- 状态必须按 `IN_PROGRESS -> REVIEW -> TESTING -> DONE` 推进；代码完成不等于 DONE。

## Next Recommended Action

`TASK-001` 的本地 Workshop 验收已完成。涉及生产 Session 的下一步是执行拓扑报告中的发布 Lobby 实验；其他任务启动前确认唯一 Owner、Affected Files 和对应 Testing Matrix。

## History

重构前的任务调度规则保存在 `archive/2026-08-25-pre-knowledge-refactor/CURRENT_TASK.md`；更早的大量开发日志保存在 `archive/2026-08-24-pre-task-registry-current-task.md`。
## 当前实施任务补充（2026-09-02）：主宰基部保留与齐天大圣饰品

- 主宰永久英雄资源现在仅保留 `models/heroes/juggernaut/juggernaut_arcana.vmdl` 的红色起源 `model_skin=1` 基部及其主体常驻粒子；移除远古流犯头/手/背/腿、古卷之剑坎图沙的五个 `prop_dynamic` 组件、五个专属粒子和对应预缓存，避免与 Arcana 内置网格叠加。头像仍为 `npc_dota_hero_juggernaut` 原生基础头像。
- 齐天大圣永久英雄资源改为主体 `models/heroes/monkey_king/monkey_king.vmdl` 加四个确定性 `prop_dynamic + bone_merge` 组件：伏魔行者铠甲（ItemDef `13008`）、擎天大圣头部（ItemDef `34183`）、伏魔行者肩铠（ItemDef `13545`）和伏魔行者战棍（ItemDef `13546`）。护甲、肩部、战棍使用本机 `items_game` 对应的三个官方常驻粒子；擎天大圣头部未声明额外常驻粒子，不虚构粒子。头像继续使用 `npc_dota_hero_monkey_king`，不传入饰品 ItemDef。
- 组件和粒子均通过资产 CSV、生成 Lua、异步代理 KV 同步；Monkey King 自定义件使用 `prop_dynamic`，因此不会被原生 `dota_item_wearable` 隐藏扫描误伤。自动测试已同步到新的组件/粒子计数与模型路径；仍需 Workshop Tools 冷启动确认齐天大圣头部骨骼位置、战棍动作、三项粒子和主宰仅显示红色基部。
## 当前实施任务（2026-09-02）：英雄饰品批次修正（斧王、黑暗游侠与 DOOM）

- 按用户最新更正，取消此前误加的斯拉克“渊海绝影”预备配置；本轮保留斧王“熔焰之拳”和黑暗游侠“漂泊群岛异客”。
- 末日使者永久英雄资源改为永恒血神魔嗣套组（ItemDef `21033`）：世界主体仍为 Doom 英雄模型，七个官方部件以 `prop_dynamic + bone_merge` 挂载；战斧和头盔均选择 style 1 的 alternate 模型，并为全部部件设置 `model_skin=1`。
- Doom 武器绑定物品声明的 `particles/units/heroes/hero_doom_bringer/doom_bringer_ambient.vpcf` 常驻粒子；头像继续只使用 `npc_dota_hero_doom_bringer` 原生头像，不传入饰品 ItemDef。
- 同步更新 `asset_catalog.csv`、`asset_components.csv`、`asset_effects.csv`、生成 Lua、Doom 代理预载 KV 与选中单位饰品合同；移除所有 `hero_permanent_hero_slark`、`shadow_deep_*` 和 `fall20_slark` 残留。
- 自动验证已通过 AssetBundle、SelectedUnitCosmeticPortrait、HeroCosmeticService、HeroAssetPreloadService、目标 Lua 语法和 `git diff --check`；仍需 Workshop Tools 冷启动确认 Doom 头盔/战斧分支骨骼、粒子与原生头像显示。
## 当前实施任务（2026-09-02）：基础字段词条整理与玩家档案字段扩展

- 将 `基础字段条.txt` 的 120 条词条按作用对象、触发时机和数值类型去重：保留 84 个可用增量字段，保留现有 `starjoy_points`、`online_seconds_total` 和基础 `tower_attack_interval` 系统字段；明确删除箭塔生命与箭塔伐木减甲条目。
- 在 `player_gameplay_stats.csv` 中加入英雄、箭塔、金矿、伐木工、城墙、全局战斗等新字段，并以 `# TODO` 注释保留尚未确定的每秒回血、英雄生命护甲组合加成、初级强化科技和英雄初始金币。
- 字段表只负责定义类型、默认值、范围与持久化身份；礼包/购买/抽奖的 `delta` 增量协议、`order <field_id> <delta>` 作弊命令以及 Supabase 服务端原子更新留待后续任务实现。本轮不直接联调数据库。
- Python 配置生成器在当前机器没有可用 Python 3，因此按生成器格式同步更新 `generated/player_gameplay_stats.lua`；已通过 Lua 语法、87 个字段唯一性、CSV 行宽和 `git diff --check` 检查。
## 当前实施任务（2026-09-02）：玩家 gameplay_stats 本地增量包与 `order` 作弊码

- 新增 `player_gameplay_stats_order_service`，把 `order <field_id> <delta>` 转换为带 `schema_version/account_id/base_revision/revision/update_id` 的本地模拟服务端 JSON 包，并复用 `player_profile_service.apply_incremental` 的 JSON 解码、幂等和 revision 校验链路。
- 词条 ID、数值类型、最小/最大值均以 `player_gameplay_stats.csv` 生成配置为准；成功后更新玩家档案中的 `save.gameplay_stats`，发布既有 `PLAYER_PROFILE_CHANGED` 事件，因此资源系统会立即刷新本局资源。`initial_wood`/`initial_gold` 的增量会即时加入当前木材/金币，同时保留到本进程的本地 fixture 覆盖，后续重新加载档案仍会带上增量。
- `local_fixture_provider` 增加进程内 `persist_gameplay_stats` 覆盖层，作为暂不联调 Supabase/阿里云时的临时服务端存储；替换正式 Provider 时该可选接口自然失效，不改变 profile provider 合同。
- 资源初始化补齐 `initial_gold` 的增量处理，并保留每秒木材/金币和人口上限的既有事件刷新；profile 增量路径新增完整 gameplay_stats 合法性校验。
- 用法示例：`order initial_wood 10`；成功日志会输出模拟 JSON 包，失败时返回字段不存在、类型不匹配、越界或档案未加载等明确原因。当前仅实现本地内存模拟，不会写入 Supabase；正式联调时只需让服务端返回同形状的增量 JSON。
- 已用 Lua 5.1 独立夹具验证：JSON 包生成/解码、revision 幂等、初始木材从 10 增至 20、Provider 重载后仍保持 20，以及资源事件链可接收增量；目标 Lua 文件通过 `luac -p` 和 `git diff --check`。
## 当前实施任务补充（2026-09-02）：gameplay_stats 运行时字段接线修复

- 根因确认：`order` 增量包正确写入 `profile.save.gameplay_stats`，但英雄、箭塔、城墙和工人的既有消费者只读取 `profile.save.permanent_effects`，所以档案值与运行时数值长期断开。`permanent_reward_effect_service` 现将两个分区按字段相加后统一投影，并继续通过既有 `PERMANENT_REWARD_EFFECTS_CHANGED` 驱动已生成单位即时重算。
- 资源与采集：`initial_population_cap` 增量会立刻调整当前人口上限并发布 HUD 快照；伐木工基础采集、固定效率、攻速、间隔、范围、成长、暴击与最终收益只接入伐木工链，英雄砍树继续固定使用英雄基础采集值；金矿百分比、固定产量、最终产量、收益间隔和建造上限均接入生产/建造链。
- 英雄、塔与城墙：英雄初始攻击、攻击/伤害成长、三围成长、攻速、间隔、范围、生命、护甲、暴击、最终伤害、固定伤害和攻击减甲均进入真实运行时；英雄伤害成长只统计英雄本体。箭塔攻击/攻速/间隔/范围/成长/暴击/减甲/最终伤害，以及城墙生命、护甲、每秒成长、回血、减伤和固定格挡已接入现有重算与伤害过滤链；共享友军护甲和敌军初始减甲同步作用于当前及后续实体。
- 新增的运行时增长只保存在本局内存，账号基础值仍由 `gameplay_stats`/未来服务端数据库持久化；本轮未连接 Supabase。目标 Lua 均通过 `luac -p`；伐木工、金矿、英雄面板、护甲映射和自定义怪物护甲专项测试通过，另以临时独立夹具验证了 gameplay_stats/permanent_effects 合并、英雄/塔/墙增长及人口即时刷新。`test_armor_balance.lua` 的既有 modern-asymptote 断言仍失败，相关配置未由本任务修改；Workshop Tools 冷启动实机仍需验证数值表现。
## 当前实施任务补充（2026-09-02）：英雄攻击减甲单位与重复事件修复

- `hero_attack_armor_reduction` 的设计语义是“英雄每次成功普通攻击命中目标，固定减少目标一段护甲”，效果累积但受目标自身最小护甲限制；它不是一次性清空，也不是百分比字段。
- 发现并修复单位错配：`player_gameplay_stats` 中的护甲字段按可见 War3 护甲值记录，而 `modifier_research_armor_reduction` 的参数是 Dota 运行时护甲值。英雄、箭塔、伐木工和全局固定减甲在进入 modifier 前统一转换，避免被再次放大约 3 倍。
- `research_armor_reduction_service` 增加 `attack_id + attacker + target` 去重，同一攻击事件重复派发时只处理一次；百分比减甲仍按目标当前 War3 护甲计算，并转换后进入同一 modifier。
- `hero_attack_armor_reduction` 默认值仍为 `0`；例如 `order hero_attack_armor_reduction 1` 表示每次英雄普攻减少 1 点 War3 护甲，而不是 3 点。已通过减甲映射、英雄战斗投影和目标 Lua 语法检查。

## 当前实施任务补充（2026-09-02）：gameplay_stats 单词条隔离测试命令

- 新增 `ordertest <field_id> <absolute_value>`。它与增量命令 `order` 分离：每次调用都会将其他 gameplay stats 展开为中性值，只把目标字段设为指定绝对值；模拟服务端 JSON 的 `changes.save.gameplay_stats` 和本地 fixture 持久层均只保存目标字段。
- 隔离期间不合并 `save.permanent_effects`，并清零英雄/箭塔/城墙的本局字段成长计数；英雄减甲测试还会清除现有目标上的累计减甲 modifier，并暂时排除科技减甲，避免旧状态污染首击结果。
- 新增 `orderreset`，恢复 `player_gameplay_stats.csv` 的全字段默认值并退出隔离；普通 `order` 仍保持原有增量语义。唯一不能置零的 `tower_attack_interval` 因 schema 最小值为 `0.01`，隔离展开时保留其默认中性值 `1.7`。
- Lua 语法、减甲映射/战斗投影回归、稀疏 JSON 合同和档案中性展开测试均通过；用户已在 Workshop Tools 实机确认 `ordertest hero_attack_armor_reduction 10` 的单词条隔离逻辑解决了减甲测试问题。

## 当前实施任务补充（2026-09-02）：单词条隔离实机验收完成

- 用户确认单词条隔离测试已解决原有问题：测试指定字段时不会再被其他 JSON 字段、永久奖励、科技减甲或上一轮累计 Modifier 污染。
- `ordertest hero_attack_armor_reduction 10` 现作为英雄攻击减甲的标准排错入口；`orderreset` 用于恢复字段表默认值。该项进入已验收状态，后续若出现数值偏差可直接基于单字段日志继续定位。

## 当前实施任务补充（2026-09-02）：英雄面板百分比基数修正

- `hero_attack_bonus_pct` 现在以包含武器、融合装备、属性和其他固定攻击来源的当前英雄面板攻击力为百分比基数；融合装备的攻击力不再被排除在百分比计算之外。
- `hero_health_bonus_pct` 现在以包含配置生命、属性生命和融合装备生命的当前面板生命值为基数；`hero_armor_bonus_pct` 现在以包含装备护甲及英雄/团队固定护甲的当前面板护甲为基数。
- `hero_damage_reduction_pct` 继续在伤害过滤层按英雄实际承受的当前伤害结算，并限制在 0%–100%；不再依赖英雄裸属性或裸面板记录。
- 百分比计算使用可重算的面板组成值，装备只增不减的融合模型不会因重复刷新产生累计乘算；字段说明已同步到 CSV 和生成 Lua。目标 Lua 语法、Combat Stat、Armor Reduction/Mapping 回归通过；仍需 Workshop Tools 实机检查带装备英雄的四项面板数值。

## 当前实施任务补充（2026-09-02）：防御塔攻速与护甲 UI 即时刷新

- 修复 `tower_attack_speed_bonus_pct` 只改变引擎 `BaseAttackTime`、未同步自定义 ScanPanel 数据的问题：箭塔每次科技/档案效果重算后，同时更新 `survival_attack_speed` 与 `survival_attack_interval`，随后由既有 `BUILDING_CHANGED` 快照立即推送新攻速。
- 审计护甲刷新链：英雄面板护甲继续由 `HERO_COMBAT_STATS_CHANGED` 推送；墙体护甲通过 `PERMANENT_REWARD_EFFECTS_CHANGED -> BUILDING_CHANGED` 推送；攻击固定减甲、毒云百分比减甲及隔离测试清除旧减甲均通过 `UNIT_COMBAT_STATS_CHANGED` 推送。
- 补齐 `enemy_initial_armor_reduction` 对当前已选怪物的 `UNIT_COMBAT_STATS_CHANGED` 派发，并在重算敌军初始护甲时保留已有固定减甲、最低护甲和毒云百分比状态，不再把有效护甲直接覆盖为新的基础护甲。
- 修复自定义 War3 护甲单位收到减甲事件时误读引擎原生 `0` 护甲占位值的问题；ScanPanel 现在读取与伤害过滤一致的 `survival_effective_war3_armor`。
- 攻速 Aura 仅续期且数值/层数未变化时不再派发冗余 UI 刷新，避免相同单位无意义重渲染。目标 Lua 语法检查及塔攻速快照、选中单位攻速/护甲推送、敌军初始护甲事件、护甲映射、毒云与 gameplay stats 隔离专项测试通过；仍需 Workshop Tools 实机验证连续选中箭塔/怪物时的即时数值变化。

## 当前实施任务补充（2026-09-02）：伐木工攻击成长 ScanPanel 即时刷新

- `lumberjack_attack_growth` 的成长计算原本已经正确写入伐木工的 `survival_attack_min/max`，但 `refresh_worker_technology()` 没有在攻击面板发生变化时派发 `UNIT_COMBAT_STATS_CHANGED`，因此选中的伐木工 UI 会延迟到下一次请求才更新。
- 现在科技学习、`order`/`ordertest` 更新或每次砍树触发成长后，只要攻击力缓存实际变化，就复用同一 `UNIT_COMBAT_STATS_CHANGED` 事件立即刷新 ScanPanel；数值和层数未变化时不派发冗余事件。
- 目标 Lua 语法、伐木工训练、档案隔离和选中单位推送回归通过；`lumberjack_attack_growth` 仍保持“每次攻击后增加”的语义，命令执行本身只改变下一次攻击的成长量，不会凭空增加当前攻击力。

## 当前实施任务补充（2026-09-02）：本地 JSON 模拟档案跨重启加载

- 实机复核发现首次实现没有真正写入 `data/mock/player_profiles.json`：`order` 先成功更新局内档案，随后文件持久化失败，但命令层忽略了 `persist_error`，仍显示普通成功提示；原实现同时只尝试两个相对路径，无法覆盖 Dota 从 `game/bin/win64` 等目录启动的情况。
- `local_fixture_provider` 现在枚举 addon root、`game/`、`game/dota/`、`game/bin/win64/` 对应路径，优先使用脚本绝对来源推导路径，并为当前本地工作区保留显式回退；读取成功后记录唯一实体路径，写入时只回写该路径，避免在错误工作目录生成同名文件。
- `order`/`ordertest`/`orderreset` 只有在文件写入成功后才显示“已写入本地 JSON”；失败时会在游戏通知与 `[GameplayStats]` 日志中直接给出 `fixture_file_io_unavailable`、`fixture_file_not_resolved` 或带路径的写入错误，明确提示本局有效但重启不保留。
- JSON 文件传输当前是本地文件模拟服务端包；代码中已加入 `TODO(HTTP/Supabase integration)`，后续验收通过后只替换 Provider 的读写实现，不改变 JSON 解码、revision、幂等和档案服务契约。
- 已通过目标 Lua 语法与内存文件持久化测试；需实机重新执行一次 `order initial_wood 10`，先确认提示为“已写入本地 JSON”且文件出现 `save.gameplay_stats.initial_wood`，再完全重启验证读取。若提示 `fixture_file_io_unavailable`，说明当前 Dota VScript VM 禁止 Lua 文件 I/O，必须改用本地桥接进程或后续 HTTP Provider，不能继续伪装为写入成功。

## 当前实施任务补充（2026-09-02）：VScript 文件持久化能力确认

- 实机日志已返回 `fixture_file_io_unavailable`。这不是 Windows ACL 或 `data/mock` 路径权限错误，而是 Dota VScript VM 中 `io`/`io.open` 不可用，代码无法从 Lua 直接打开任何本地文件。
- `game/dota/save` 目录在安装目录中确实存在且操作系统权限可写，但它不是向 VScript 暴露的 Unity `persistentDataPath`；当前没有可用的通用 Lua 文件写入接口可以把 JSON 写入该目录。
- 因此“游戏内命令直接改写 `data/mock/player_profiles.json`”无法仅靠 addon Lua 完成。保留当前失败提示和 `TODO(HTTP/Supabase integration)`，避免把只更新内存误认为跨重启持久化。若继续保持无 HTTP 的测试方案，需要另行决定本地桥接进程（监听游戏日志/命令并写 JSON）或改用引擎归档 ConVar 作为临时存储；两者都不是 VScript 直接 JSON 写入。

## 当前实施任务补充（2026-09-02）：本地 JSON 桥接进程与重置命令

- 新增 `tools/local_fixture_bridge.ps1`。它监听 Dota 的 `game/dota/console.log` 中专用 `PERSIST_BRIDGE` 行，把 `order`、`ordertest`、`order reset` 产生的 gameplay stats 快照写回 `data/mock/player_profiles.json`；使用临时文件替换，避免写入半截 JSON。
- 启动 Workshop Tools 时需要带 `-condebug`，然后在 addon 根目录运行：`powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\local_fixture_bridge.ps1`。桥接进程从日志末尾开始监听，不会把旧历史订单重新覆盖到当前档案；按 revision 拒绝迟到事件。
- `order reset` 现在与 `orderreset` 等价，恢复字段表默认值（绝大多数为 0），并通过相同桥接事件持久化。桥接进程未启动时，游戏仍会显示“等待桥接写入 JSON”，不会伪报物理文件已写入。
- 桥接脚本仅为本地测试替代方案，后续服务端验收时继续按 `TODO(HTTP/Supabase integration)` 替换 Provider，不改变增量包契约。

## 当前实施任务补充（2026-09-03）：箭塔攻击间隔面板攻速同步

- `tower_attack_interval`/`tower_attack_interval_reduction` 的最终计算本来已经写入箭塔 `SetBaseAttackTime` 与 `survival_attack_speed`；问题出在选中单位请求时优先调用引擎 `GetAttacksPerSecond`，部分引擎帧仍返回旧值，覆盖了刚计算出的项目缓存。
- `ui_request_router.effective_attack_speed()` 现在对 `survival_building_id == "arrow_tower"` 优先使用项目最终攻速缓存；`BUILDING_CHANGED` 同时携带最终 `attack_interval`，自定义 ScanPanel 通过攻速计算出的间隔与实际 BAT 保持一致。
- 注意：`tower_attack_interval` 是“绝对攻击间隔上限”（默认 1.7 秒），减少量词条应使用 `tower_attack_interval_reduction`；`order` 是增量命令，单字段精确测试可使用 `ordertest tower_attack_interval 0.5`。目标 Lua 语法和战斗面板投影回归通过，仍需实机选中箭塔验证。

## 当前实施任务补充（2026-09-03）：恢复英雄攻击属性效率的独立字段语义

- 用户确认 `hero_attack_attribute_efficiency_pct` 只作用于 `hero_attribute_growth`（每次普通攻击成长），不作用于 `hero_attributes_per_damage`（每次造成伤害成长）。
- 已撤销上一版对伤害成长的效率换算，恢复两个字段独立处理；普通攻击同时造成伤害时，攻击成长按效率换算，伤害成长保持原始数值。
- `test_hero_attack_attribute_efficiency.lua` 已同步覆盖该边界：伤害成长 10 在效率 200% 时仍为 10，普通攻击成长 1 在效率 200% 时为 3。
- 已通过目标 Lua 语法、效率行为测试、战斗面板投影和 gameplay stats 订单隔离回归。

## 当前实施任务补充（2026-09-03）：金矿收益间隔减少改为真实生产频率

- `gold_mine_income_interval_reduction` 原本在固定 1 秒总计时器中按 `production_interval / effective_interval` 放大单次发放量；当有效间隔为 0.05 秒时，33 金币被错误合并成单次 660 金币。
- 金矿现在为每个实体建立独立生产调度，减少量只缩短两次生产之间的间隔；每次生产仍按当前金矿等级、科技和词条计算一次正常/暴击产量，不再把多个周期折算到一跳中。
- 词条或科技更新时，仅在有效间隔实际变化时重排该金矿计时器，普通收益/属性等其他档案事件不会反复重置生产计时。
- 已通过金矿间隔行为测试、金矿自动升级回归、目标 Lua 语法和战斗面板投影测试。
