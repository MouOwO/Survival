# Known Issues

Last Reviewed: 2026-08-25

本文件只记录当前仍存在的问题。已解决和历史问题见 `archive/2026-08-25-pre-knowledge-refactor/KNOWN_ISSUES.md` 与 `SESSION_LOG.md`。

## ISSUE-001

**Status:** TESTING

**Priority:** P0

**Symptom:** Workshop Tools 终局曾进入 `POST_GAME`，但未观察到 Survival final HTTP callback 或 `session_closed`。

**Known Cause:** `game_end` 在该实机路径不能作为唯一终局入口；项目已增加 `POST_GAME` 和已完工城墙毁坏入口。

**Current Workaround:** 使用幂等 `online_time_service.finish(source)` 覆盖 `wall_destroyed`、`POST_GAME` 和 `game_end`。

**Next Action:** 冷启动 Workshop Tools，分别验证正常终局和城墙毁坏，关联 Dota 日志、HTTP 200、`final=true` 与唯一 `session_closed`。

**Last Verified:** 2026-08-24；STATIC / CONTRACT / SIMULATION 通过，WORKSHOP 未复验。

## ISSUE-002

**Status:** BLOCKED

**Priority:** P0

**Symptom:** 生产双玩家端到端联调尚未完成。

**Known Cause:** 需要两个真实 Steam 账号和完整主机环境。

**Current Workaround:** 单玩家 Tools、Python 和 Supabase 测试只用于分层验证，不作为生产双玩家验收。

**Next Action:** 验证双账号建档、独立 session/累计、checkpoint/奖励、终局、重连、幂等、API 重启和跨玩家隔离。

**Last Verified:** 2026-08-24。

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