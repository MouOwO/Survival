# Known Issues

Last Reviewed: 2026-08-27

本文件只记录当前仍存在的问题。已解决和历史问题见 `archive/2026-08-25-pre-knowledge-refactor/KNOWN_ISSUES.md` 与 `SESSION_LOG.md`。

## ISSUE-001

**Status:** RESOLVED FOR ACCEPTED SCOPE

**Priority:** P0

**Symptom:** Workshop Tools 城墙毁坏后曾无法确认最终在线结算是否发出。

**Known Cause:** `game_end` 在该实机路径不能作为唯一终局入口；项目已增加 `POST_GAME` 和已完工城墙毁坏入口。

**Current Workaround:** 使用幂等 `online_time_service.finish(source)` 覆盖 `wall_destroyed`、`POST_GAME` 和 `game_end`。

**Next Action:** 无。城墙毁坏范围已由用户验收通过；`session_closed` 仅作为失败局后的本地 callback 观测项保留，不阻断服务端结算。

**Last Verified:** 2026-08-25；WORKSHOP 城墙毁坏、`final=true`、API HTTP 200 和在线时间持久化已由用户确认。

## ISSUE-002

**Status:** TESTING

**Priority:** P0

**Symptom:** 正常发布 Arcade 的 Game Server/Lua 主机、Lobby Owner、Python 主机和 loopback 边界仍未知。LAN 裸 IP 双机现已取得独立 PlayerID 并可观察双方操作同步，但 Player 1 的独立 Builder 修复仍待双机冷启动验收。

**Known Cause:** Builder 缺失已定位为地图缺少 `player_1_builder_spawn`，不是 PlayerID 或网络同步失败；Player 0 依靠旧坐标回退掩盖了同一地图缺口。正常发布 Arcade 的具体分配模型仍需要两个或三个真实 Steam 账号和发布 Lobby 实验。

**Current Workaround:** 正常 Arcade 继续归类为 `MODEL-D`。LAN setup 权威窗口现为 60 秒，`template_map` 已新增四个 Builder Marker 并重建 VPK；服务端结构化日志区分分队成功、`assignment_window_closed`、英雄就绪、Builder 就绪和断开字段解析。

**Next Action:** 双机冷启动确认双方 `hero_ready`/`BUILDER_READY`、`monsterborn_player1/2` 各自出怪并攻击对应城墙、双方只能控制自己的单位；Player 1 退出后其 Builder/建筑/工人/波次怪消失且通道停用，Player 0 继续运行不判负。确认不再出现 `modifier_single_health_bar SetTableValue` 和旧 `monsterborn/monsterorn` 日志后，再执行最小发布 Lobby 实验。

**Last Verified:** 2026-08-29；用户确认 LAN 双机独立 PlayerID 和操作同步；玩家隔离、断线清理、波次通道和日志修复为 STATIC/CONTRACT/SIMULATION/LUAC，尚未完成修复后的双机 WORKSHOP 或 PRODUCTION 验证。

## ISSUE-003

**Status:** TESTING

**Priority:** P2

**Symptom:** 新增或替换逐波模型时可能出现 `requested is not loaded and may have been deleted`。

**Known Cause:** 历史根因是正式预载、开发预载与出生模型解析不一致，并存在 urgent 请求被后台流阻塞的风险。

**Current Workaround:** 三条路径共享模型解析，使用波次 session/租约和 urgent 并行；禁止调用 `asset_preload.retire()` 作为卸载修复。

**Next Action:** 每次新增模型后冷启动分别验证 `monster<N>` 和正式波次第一只怪。

**Last Verified:** 2026-08-11 用户后续运行未见复发；不代表未来模型永久验证。

## ISSUE-004

**Status:** TESTING

**Priority:** P2

**Symptom:** 神秘塔升级边界历史 minidump 指向 `particles.dll` 空指针读取。

**Known Cause:** UNKNOWN；第一嫌疑是升级传送粒子延迟销毁生命周期。

**Current Workaround:** 项目侧已改为立即销毁并单次释放。

**Next Action:** Workshop Tools 冷启动按无 Alt、Alt、其他路线顺序做单变量复验。

**Last Verified:** 2026-08-13；自动 Lua 测试不能证明 Source 2 粒子线程已修复。

## ISSUE-005

**Status:** BLOCKED

**Priority:** P2

**Symptom:** 地图没有可确认的严格英雄移动白名单 / 建筑禁建边界数据。

**Known Cause:** Hammer 地图中未发现可证明为边界的成组 marker；相关 CSV 没有启用业务行。

**Current Workaround:** 空 `hero_movable` 沿用旧地图导航和 Grid 规则；`building_forbidden` 独立生效。

**Next Action:** 由人工确认 Hammer 边界点或提供坐标，再写入 CSV 并生成配置。

**Last Verified:** 2026-08-10。

## ISSUE-006

**Status:** TODO

**Priority:** P3

**Symptom:** `.cline/local-toolchain.json` 的绝对路径会随工作区或 MSYS 安装位置漂移。

**Known Cause:** 本地工具链文件使用机器绝对路径。

**Current Workaround:** 使用前检查路径存在并输出版本；失效时再搜索。

**Next Action:** 保持当前检测流程，不因 PATH 缺失直接判定工具不可用。

**Last Verified:** 2026-08-25，本机四个配置路径均存在。

## ISSUE-007

**Status:** BLOCKED

**Priority:** P2

**Symptom:** 用户实机确认隔离 `survival_phase2a/phase2a_lab` 的 A `DirectUnitSanity` 可见、B `portrait_world_unit Background` 纯黑、C `Prop_dynamic Background Control` 可见。A/B/C 分层结果已将当前失败点收敛到 B 的 `portrait_world_unit` 实体契约。

**Known Cause:** Base 最小实体契约、相机、灯光、background map、scene packaging 和 C `prop_dynamic` 对照均已通过静态或实机检查。编译后 `default_ents.vents_c` 明确包含 `portrait_world_unit`、`npc_dota_hero_axe` 和 `[PR#]phase2a_axe_portrait_unit`，但 Stage 1 运行时执行 `ent_find portrait_world_unit` 与 `ent_find phase2a_axe_portrait_unit` 均返回 `Found 0 matches.`；当前工具运行时没有把该编译实体暴露为可查找实体。

**Current Workaround:** 按 Phase 2A 首个失败即停止规则，不加载 Head `22217` 或后续 ItemDef；正式 HUD、世界模型和生产饰品系统不受影响。

**Next Action:** 当前结论固定为 `PORTRAIT_RUNTIME_ENTITY_MISSING` 并停止 Phase 2A。除非另立任务取得官方 portrait world 运行时加载/实体系统契约的新证据，否则不再调整 B、不加载 Head `22217`、Weapon、其它 ItemDef 或 Phase 2B，也不修改正式 `survival`。

**Last Verified:** 2026-08-27；`DATA_INVALID` 已消失并出现单 Base `[PHASE2A] LOAD`。A=PASS、B=FAIL/黑屏、C=PASS；编译实体 lump 含目标 classname、Axe unit name 和 targetname，但两条只读 `ent_find` 均为 0。`HEAD_RESOURCE_COUNT=0`，未加载 `22217`。