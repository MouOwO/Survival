# 表现资源与 Tools 验收

本目录保存可重新生成的粒子源文件、导入资源来源、依赖闭包和编译校验记录。正式游戏使用 `particles/survival/.../*.vpcf_c`；这里的 source 文件用于内容工程编译。

## 来源核实

- 守望轮回谷参考包：创意工坊 `570/3164617180/3164617180.vpk`。可确认 `aura_dark`、`aura_durable`、`aura_evil`、`qualification_build_t04_base` 的资源内容与依赖；包内游戏脚本为加密模块，因此不能把粒子文件名当作某个职业实际装备规则的证明。
- 参考基础远程塔的明文单位配置引用 Valve `ranged_badguy`、`ranged_goodguy`、`ghost_base_attack`。这证明相关塔使用原生弹道，但不表示所有稀有度使用同一套弹道。
- 棱角陨石确认来自 **Rubick 至宝的方块模型**，不是已证实的 Slark 皮肤。原生粒子 `particles/units/heroes/hero_rubick/rubick_chaos_meteor_fly.vpcf` 的 RERL 直接引用 `models/items/rubick/rubick_arcana/rubick_arcana_cube.vmdl`；其飞行算子使用固定 1.5 秒轨迹。
- 原生 Rubick 的火焰子粒子仍包含固定绿色，不能仅设置母粒子颜色控制点就把整套效果变成火焰色。本项目保留方块模型与轨迹，使用原生 Invoker 飞行火焰、亮光、烟和火星子粒子组成暖色版本。

参考导入清单见 [valley_reference/import_manifest.json](valley_reference/import_manifest.json)，资源与 CP 证据见 [valley_reference/resource_catalog.json](valley_reference/resource_catalog.json)。导入器验证完整非 Valve 依赖闭包，并拒绝覆盖不同内容的既有资源。

## 塔底座和武器

2026-10-01 最新底座使用 `particles/survival/towers/bases/`，配置入口见 `tower_visual_profiles.csv`。R/SR/SSR/UR 半径为 96/100/112/128，降低加法泛光和透明度；SR/SSR 使用各职业独立的内圈纹样，防空改为圆形准心，神秘塔保留奥术符纹。N 无底座；普通 R/SR/SSR 为 1/2/2 个顶层句柄，红星 SSR 与 UR 最多 3 个，计入子系统最多 6 个 sprite，维持旧版上限。29 个资源已编译并核对 source/content、编译 DATA 和依赖，生命周期模拟通过；本版草地观感与实际战斗仍待冷启验收，旧截图不作为新版证据。细节与重建入口见 [tower_bases/README.md](tower_bases/README.md)。

统一 CP0 跟随塔、CP1.x 半径、CP1.z 透明度、CP2 RGB；光环平铺在地面。D 移动跟随原实体，不重建同样式底座。上一级旧资源保留兼容，当前对局不会热替换它们。

旧版冷启截图发现半径 64 的光环容易被塔身和草丛遮住，当时将 R/SR/SSR/UR 调为 96/112/128/144，粒子离地高度为 12–16。死亡黑心半径为主环的 0.65 倍；使用官方 `enigma_blackhole_m` 已采用的 `particle_modulate_03` 纹理和 MOD2X 混合，维持软暗中心。霜底座使用原生 `groundcracks_light` 细冰裂纹；霜与雷电边圈使用原生 `particle_ring_softouter`，透明度仅为主图案的 0.20，避免硬质选中圈观感。截图中独立矩形暗块经移动 N5 石塔后同步移动，已确认是石塔模型阴影，并非粒子缺陷（`output/map_build_c6/tower_shadow_probe.png`）。旧版冷启已检查 R、SR、SSR 展示，截图保存在 [review](review/screenshots_manifest.json)；SSR 第 3 槽缺席是死亡测试的预期结果。该验收覆盖旧版正式表现服务的显示样本，不代表已实测正常付费升级或多人、UR 迁移流程。

武器资源在 `particles/survival/weapons/weapon_{glow,trail,shards}.vpcf`。真实主手装备的系列与等级决定颜色、半径、发射量和层数；不修改攻击伤害或覆盖现有武器技能的投射物。5 个系列末阶的辉光半径分别为 10 / 15 / 20 / 25 / 30，常驻系统数分别为 2 / 2 / 3 / 3 / 3。

武器辉光和尾迹使用 RGB 与 Alpha 都有柔和径向衰减的 `particle_glow_01`，CP 标量映射显式设置 MULT×1。实机放大控制点显示原先胸口挂点会遮挡小粒子，剑圣的 `attach_sword` 已核实索引为 `2`；运行时按 `attach_attack1`、`attach_weapon`、`attach_sword`、`attach_hitloc` 顺序选有效挂点，全部粒子维持深度测试。最新冷启的五组状态均为 `attach_sword`、句柄数为 2 / 2 / 3 / 3 / 3，[实机截图](review/weapons_verified.png) 可见小型彩色剑柄辉光。这是受限的第一版效果，不夸大为完整刀身特效，也不表示所有英雄或所有攻击拖尾都已实测。空模型会延迟绑定，模型和挂点变化才重新绑定。

纹理混合方式按原始资源区分：只有 Alpha 保存图案的雪花、叶片、准心、地面符号使用 Alpha 混合，避免加色混合将透明区域显示成白色方块。亮纹理使用加色混合。旧版球形初始化算子经 `vpcf45` 编译迁移为 `C_INIT_CreateWithinSphereTransform`，编译 DATA 再次检查迁移结果；每帧读取 CP 透明度和半径，避免初始化时 CP 尚未设置导致始终透明。

资源生成及验证入口：

```text
node tools/map_c6/build-tower-base-particles.cjs
node tools/map_c6/build-weapon-visual-particles.cjs
node tools/map_c6/verify-visual-particles.cjs
```

先将生成的 vpcf 源同步到 content 工程对应目录并用 Valve resourcecompiler 编译，再执行最后一个命令。验证器检查依赖存在、算子迁移、颜色/透明度/半径契约、混合模式，并写入 [tower_bases/validation.json](tower_bases/validation.json) 和 [weapon_visuals/validation.json](weapon_visuals/validation.json)。编译通过与模拟通过不代表实际画面验收通过，需冷启 Tools 后确认。

## 持续激光

2026-10-01 新入口为 `particles/survival/towers/laser_beam.vpcf`。使用 Valve 原生 Phoenix sunray / Wisp tether 已核实的持续路径结构，配合 `beam_hotwhite` 束芯、`beam_hotblue2` 蓝色外沿和两个小型命中光点。CP9 绑定塔攻击挂点，CP1 绑定目标身体挂点，由粒子引擎逐帧维护路径；缺少挂点时保留原有高度回退。没有普通淡出或分段重播，换目标、死亡、D 重置时立即销毁；暂时创建失败时每 0.5 秒重试，不重置伤害计时。

五行 `tower_laser_effects.csv` 改用 `continuous`；`addon_game_mode.precache` 从生成配置去重预载激光资源。原有伤害、射程、0.03 秒状态观察不变，CSV 的 0.12/0.18 秒分段参数仍保留供旧模式兼容，新模式不使用。整束为 1 个 Lua 句柄、4 个集合、最多 26 个节点；90 秒模拟创建 1 次，持续期间销毁 0 次，命中含首击共 91 次，绑定成功后无世界坐标覆盖。上述为编译/模拟结论，未测得新版 FPS 或实际视觉质量。

```text
node tools/map_c6/build-laser-visual-particles.cjs
node tools/map_c6/verify-laser-visual.cjs --compiled --log-dir output/tower_vfx_polish_20261001
```

生成后先同步到 content，再以 Valve resourcecompiler 编译四个资源。源清单见 [laser/manifest.json](laser/manifest.json)，验证见 [laser/validation.json](laser/validation.json)。当前用户的暂停对局保留，必须完整重启 Tools 后开新局验收；旧四塔移动截图只证明上一版跟随能力，不证明新光束的观感。

## 武器实机预览

```lua
script require("tests/manual_weapon_visual_review").run()
script SURVIVAL_WEAPON_VISUAL_REVIEW:status()
script SURVIVAL_WEAPON_VISUAL_REVIEW:swing()
script SURVIVAL_WEAPON_VISUAL_REVIEW:move(5,120,0)
script require("tests/manual_weapon_visual_review").cleanup()
```

默认在 `(320,4800)` 横排 5 个原生剑圣显示单位，可传入 `{origin=Vector(x,y,z)}`。调用真实 `weapon_visual_service.preview` 的同一 profile/升级比例/挂点逻辑，预览状态独立于玩家装备。不会发送装备变更或英雄召唤事件。单次原生异步预载完成后才生成单位，并检查地形与占位；重复加载回调、取消、跨世界和清理均有保护。挥剑只是动画，移动为短距离表现预览，无攻击目标或伤害。

## 陨石实机预览

```lua
script require("tests/manual_meteor_visual_review").run({level=5,count=1})
script SURVIVAL_METEOR_VISUAL_REVIEW:status()
script require("tests/manual_meteor_visual_review").cleanup()
```

默认落点 `(320,3400)`，可传 `{origin=Vector(x,y,z),level=1,count=3}`。等级和次数均为 1–5。使用两个无玩家归属的友军生物 proxy；目标隐藏，施法者只用于粒子和音效归属。不会占用建筑、工人或正式英雄的注册状态。

该预览直接调用真实 `hero_passive_skill_service._test.runners.proto_meteor`。属性快照全为 0；配置只复制并清零减速，不修改正式配置。半径 500、下落 0.8 秒、3 秒熔岩、末阶第二颗延迟 0.5 秒均来自原服务与原配置。所有粒子路径、音效、生成和延迟回收均走实际服务。原生 1.5 秒轨迹通过向地下延伸 CP1，在实际 0.8 秒落地时间穿过地面。

必须在无怪物进入的空场检查：启动、预载完成、每次重复施放前都会拒绝半径 884 内出现其他单位的位置。零伤害本身不阻止真实技能服务发布命中事件，因此应暂停波次或在隔离区域使用，不应在战斗中运行本预览。预览不修改生产伤害函数，也不屏蔽全局事件总线。

`cleanup()` 取消后续重复，等待当前陨石、熔岩与尾部爆炸自然结束，再删除自己的两个 proxy；返回 `pending=true` 表示正在等待。它不调用 `clear_meteors()`，不会清除其他施法者的陨石。单次播放完成会自动回收 proxy，保留 status 供查看。

2026-10-01 最终冷启预览已通过：[方块、暖焰与落地效果](review/meteor_impact_verified.png)、[无水平密纹的熔岩地面](review/meteor_ground_verified.png)。同次双陨石已共用一套地面视觉，持续到第二颗熔岩结束；两颗各自的伤害、减速与时序不变。单纯共用视觉、将旧 `C_INIT_PositionOffset` 从 7/9 提至 32/40，均未消除密纹；最终改用 `C_OP_SetToCP`，编译 DATA 确认为浮点偏移 `[0.0,0.0,32.0]` / `[0.0,0.0,40.0]` 后，实机密纹消失，深度测试保持原状。该修复组合已实测成立，但未证明整数向量是唯一底层原因。验收范围是空场隔离 fixture 的真实表现链路，不等同于正常英雄完整实战或多人性能验收。[陨石验证记录](../../docs/ai/validation/20260930/meteor_visuals.json)只在全部粒子 source/compiled 哈希仍一致时保留此 Workshop 结论；资源变化后验证器自动撤销该通过状态。

## 自动验证

以下脚本用 Lua 5.1 执行，模拟引擎对象但调用实际服务和实际配置：

```text
lua5.1 scripts/vscripts/tests/test_weapon_visual_service.lua
lua5.1 scripts/vscripts/tests/test_manual_weapon_visual_fixture.lua
lua5.1 scripts/vscripts/tests/test_meteor_visual_timing.lua
lua5.1 scripts/vscripts/tests/test_manual_meteor_visual_fixture.lua
```

- 武器：主手与玩家隔离、等级 99/等级 0 的真实进阶、命中间隔、死亡与重生、重入清理、跨世界句柄、独立预览。
- 武器 fixture：5 系列最大层级参数、异步取消与超时、重复回调、地形与占位、移动不重建粒子、无装备/召唤事件。
- 陨石：落点时序、半径、熔岩周期、第二颗比例，以及资源失败时仍保持战斗时序。
- 陨石 fixture：真实 runner、零属性、空场无全局事件、次数限制、只回收自己的 proxy、清理期间其他施法者的陨石继续运行。

实机截图与最终冷启验收见 [集成记录](../../docs/ai/validation/20260930/presentation_integration.json)；本目录将模拟结果与实际画面证据分别记录，并列明尚未验收的范围。

Tools 编译同路径资源会干扰当局已有粒子。01:14 编译后、01:15 截图中旧底座消失，但服务仍持有句柄；这不能证明粒子只有一分钟寿命。DATA 中常驻寿命为 999999、无普通 Decay。最终冷启在未重编同路径资源的情况下，已完成镜头离开超过 60 秒再返回的 R 底座检查，效果仍可见（[截图](review/towers_r_verified.png)）。死亡后的 1.25 秒检查同时通过粒子零句柄与头顶等级移除；这不外推为所有长时间、多人或性能场景均已通过。
