# 01 架构、权威源与工程工作方式

事实截点：2026-10-24；根目录路径见 `data/context.json`。现有架构是 Dota 原生 Lua 5.1／KV／Modifier／Panorama，域服务＋事件总线＋调度器，Python HTTP 入口及 PostgreSQL RPC。历史本地方案通过 Supabase RPC，后续存在阿里云部署与 WS4 独立服务；不要照搬旧 `127.0.0.1:8765` 作为当前线上拓扑，也不要把 Python 项目称作已经迁移到 FastAPI。

## 权威与调用方向

| 层 | 负责 | 关键限制 |
| --- | --- | --- |
| `data/csv/`、战斗 v3 规格 | 经济、技能、商品、默认属性、模式和怪物输入 | 按生成链更新，不直接手改派生 Lua/KV |
| Dota server Lua | 真实玩家身份、单位归属、战斗与局内资源、请求验证 | 同队不等于同一所有者；本机承载仍可被主机修改 |
| Panorama | 发购买/升级/选择意图，显示私有/公开投影 | 不接 SQL，不持有内部 Bearer，不决定价格或奖励 |
| Python API/授权 sidecar | 受限身份通道、协议校验、领域服务与数据库调用 | loopback 只属于运行该进程的机器；不能凭房主身份推定位置 |
| PostgreSQL／受限 RPC | 永久档案、不可变操作凭据、订单交付及版本 | 函数白名单、锁与同事务提交；不让游戏角色直接写支付表 |
| Workshop/签名发行物 | 运行资源分发与版本可审计性 | Git push、上传完成、Steam下载、原生验收分别核对 |

开局分为引擎阶段和项目业务状态。`admission_complete` 取决于真实参局名单、身份、预载与客户端握手；选模式后才加载模式档案，`gameplay_gate` 再放行玩法。引擎已进入游戏不等于业务已可建造。旧认证/预载回调必须携带账号、session、generation 并重新核对，失败保留原档案及可重试状态，不以空档案放行。

## 领域模块与维护定位

| 领域 | 主要位置 |
| --- | --- |
| 全局生命周期 | `scripts/vscripts/addon_game_mode.lua`、`core/events.lua`、`event_bus.lua`、`scheduler.lua` |
| 进房/选模式 | `systems/startup_loading_service.lua`、`match_setup_service.lua`、`team_difficulty_service.lua` |
| 玩家档案 | `systems/player_profile_service.lua`、`player_profile_providers/http_fishing_provider.lua`、`server/archive_backend/` |
| 经营与战斗 | `systems/building_system.lua`、`worker_training_queue_service.lua`、`combat/`、`wave_system.lua` |
| 账号奖励/合作结算 | `archive_cooperative_reward_service.lua` 及 archive 领域队列、reducer、RPC |
| 网页身份 | `systems/player_web_auth.lua`、`server/player_web_auth/`、`server/workshop_test/` |
| 商城/支付 | `systems/commerce_service.lua`、`payment_service.lua`、`server/payment_backend/`、`server/aliyun/database/` |
| 源码和资源 | game 的 `panorama/src/`、content 的 `panorama/`／`maps/`，对应 game 编译资源 |
| 发布与运维 | `publishing/workshop/`、`tools/workshop_test/`、构建/签名/分卷工具 |

有同名副本、别名或历史脚本时，先确认实际加载入口、签名清单与调用点，不能因为文件存在就认为它正在使用。所有者与活动任务记录在任务维度，先查 git status、diff、受影响文件和并行任务，避免覆盖他人工作。

## 长期工程约束

- 延续唯一订单过滤、伤害权威与属性投影；新增技能接现有服务、事务和事件，不再建第二套伤害或库存状态。
- 调度任务具有生命周期和代际：取消执行中任务、同 ID 替换、reset 后旧回调不能复活；旧退订句柄不能删除新局同编号订阅。粒子、实体、监听和异步预载都有结束路径。
- 业务失败按事务回滚；单位/资源创建先登记归属再完成配置，异常能回收或复用半成品。重复点击、HTTP 丢包、重连、跨日和并发购买均不重复扣费或发奖。
- 性能优化先分辨 Lua 开销、客户端 GPU、主机消息处理和网络抖动。删除空闲常驻工作、变化才刷新、复用缓存；不靠少算伤害、漏发奖励、降低游戏规则精度取得“改善”。模拟操作量不是实机 FPS。
- UI 视觉细节不进入常驻上下文；保留生命周期、私有数据范围、服务端业务状态和实际编译入口。显示数值正确不证明原生 setter/伤害/到账成功。

现有回归入口 `tools/run_runtime_regression.py` 可按其帮助指定 Lua 5.1；Lua/Node模拟、后端单元、数据库事务、原生资源读取、Tools实机、普通游廊、多人公网和真实付款为不同验证层。新改动选相关检查并做必要实机，记录没有验证的层。此次知识整理只校对文件与资料，没有重跑全部游戏/支付回归。

## 原项目双仓交付规则

game：`D:\SteamLibrary\steamapps\common\dota 2 beta\game\dota_addons\survival`；content：`D:\SteamLibrary\steamapps\common\dota 2 beta\content\dota_addons\Survival`。两仓独立，遵守各自 `.gitattributes`，地图等现有 LFS 继续 LFS。

用户固定流程：检查两边分支、上游、dirty、ahead/behind 和 stash；未提交改动用唯一说明 `stash push --include-untracked` 并记对象；按当前策略 pull；只 pop 本次 stash，确认原数据恢复；只暂存本次任务文件，检查并 commit；push 后核对远端。干净时不创建空 stash/commit，不清历史 stash、不重置/强推。遇冲突保留数据后解决。

本次知识包放在忽略输出目录后导出桌面，没有需要提交的源码更改；没有为了导出而 stash/pull 正在协作的工作区。`data/repository_snapshot.json` 区分本轮关键认证提交和整理时最新 HEAD，列出保留改动。现有 `docs/ai/` 恢复资料含旧阶段与旧拓扑，只按领域查阅并用当前实现核对，不整体当作最新事实。

来源：`AGENTS.md`、`docs/RUNTIME_REFACTOR.md`、`docs/STARTUP_LOADING.md`、`docs/ai/PROJECT_CONTEXT.md`、`docs/ai/registry/README.md`、当前 core/域服务，以及模块02–06列出的源码与发布回执。
