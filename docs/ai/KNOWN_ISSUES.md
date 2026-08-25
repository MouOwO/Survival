# Known Issues

Last Reviewed: 2026-08-25

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

**Status:** BLOCKED

**Priority:** P0

**Symptom:** 正常发布 Arcade 的 Game Server/Lua 主机、Lobby Owner、Python 主机和 loopback 边界未知，生产双玩家端到端联调尚未完成。

**Known Cause:** 当前只有本地 Workshop 同机证据；通用 Steamworks 文档不能证明 Dota Arcade 的具体分配模型，需要两个或三个真实 Steam 账号和发布 Lobby 实验。

**Current Workaround:** 正常 Arcade 归类为 `MODEL-D`；单玩家 Tools、Python 和 Supabase 测试只用于分层验证，不作为生产双玩家验收，也不继续扩展生产 Session 架构。

**Next Action:** 先执行 `architecture/MULTIPLAYER_TOPOLOGY_REPORT.md` 的最小发布 Lobby 实验，确认 Lua 执行主机与 `127.0.0.1:8765` 归属；再验证双账号建档、独立 session/累计、owner/non-owner 离开、终局、重连、幂等、API 重启和跨玩家隔离。

**Last Verified:** 2026-08-25；STATIC INVESTIGATION，未完成 PRODUCTION 验证。

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