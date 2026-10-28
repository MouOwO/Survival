# 10 运行时、原生引擎与资源身份契约

核对时间：2026-10-28（北京时间）。本次只读核对当前实现、20261024知识包与近期原生入口/地图发布记录；没有启动游戏、复测支付、加载地图或连接数据库。本文件保存长期代码边界和定位入口，具体版本、回执和待测状态以对应发布记录为准。

路径以 game 仓库为根；`core/`、`systems/`、`config/`、`combat/`、`research/` 均为 `scripts/vscripts/` 下的缩写。提到 content 时指独立的地图/美术/Panorama源仓库。

## 1. 引擎可信身份与业务身份分层

引擎的连接状态、真实 player entity、Steam AccountID、单位拥有者与房主权限是权限输入。SteamID64、AccountID、Dota PlayerID、实体 entindex、业务 account_id 和 match_session_id 是不同类型，不能混用。客户端传入房主标志、账号、价格、奖励数或已登录状态不能授予权限。

长期实体状态绑定真实句柄、world、事件总线generation和任务token，不能仅用可能复用的entindex。跨换图Lua VM、重连、改账号、重建面板和异步预载都会改变生命周期；每个回调复核当前归属与代际，不能把同一数值索引认定为同一个实体。

状态枚举也分层：引擎 `GAME_IN_PROGRESS` 不代表项目身份/资源/模式档案已就绪。业务 `GAME_STARTED` 由项目门禁释放；Gameplay、post-clear冻结、账户待保存和引擎终局是不同状态。修复“卡住”不能跳过门禁或人工伪造就绪事件。

## 2. 原生多人入口与HTTP的已验证路径

当前项目有服务端 `ws4_entry` → 同工坊 `template_map` 的一次性原生换图路径，入口分支在 `addon_game_mode.lua` 显式加载 `systems/native_cloud_handoff.lua`。单独 require 模块不启动认证、存档或HTTP，不授予支付权限。

经过真实验证的服务器命令形状为：

```text
changelevel template_map gamemode=15 customgamemode=3824360109 nomapvalidation=1 ws4_native_roster=<服务器记录的原始真人AccountID名单>
```

它只能由受信服务器控制，账号名单来自引擎枚举，不能从客户端拼命令。裸 `changelevel template_map` 会丢失addon上下文，历史曾造成地图缺失和原生崩溃；逐客户端裸 `dota_launch_custom_game` 会把队伍拆成各自单人局，不能当作多人接入修复。

这里的HTTP问题要保留首个失败层：历史普通GC Local Host入口中，HTTP工厂返回nil，尚未请求网站；服务端原生换图后的上下文实测可创建请求并收到200。不能把这种情况一概归因于网站拒绝、Steam登录失效、永久官方禁HTTP、缺少自建对局服务器或付费才支持多人。HTTP库存在也不保证每种引擎上下文均可用；未来Dota更新需重新验证，不能把当前经验写成永恒官方政策。

历史2026102708在普通Steam、无-dev/Tools、禁作弊的原游廊双人局，验证了同局自动入口、两名真人进入目标图、各自登录和云档读回。2709在加入方验证手机扫码商品/金额正确；它不是完整真实付款到账验证。2802地图版记录主机从原条目载图烟测，未补验本次双人布局、迟加入/重连、全图通行或完整守波。入口换图会销毁旧GC房间对象，不能据已有两人连接成功推断后续好友加入/房间重连已完善。

证据与维护：`docs/native_arcade_cloud_20261027.md`、`docs/guest_payment_qr_20261027.md`、`docs/map_resources_20261028.md`，当前 `publishing/workshop/test_listing.json` 与其 release_record。网站/PWA、存档HTTP服务、支付回调与实际Dota对局进程是不同服务职责；网站能做身份、房间与调度业务，不能单独代替运行引擎对局的进程。

## 3. 真正存在的原生API与跨换图名单屏障

当前接口核对与经验必须保存：

| API/数据 | 用途与边界 |
| --- | --- |
| `PlayerResource:GetPlayerCount()` | 原生资源名单计数，包含尚未分配/仍加载的槽位；配合完整枚举，不能只看已分队在线人类数 |
| `GameRules:State_Get()` | 等待原生加载进入SETUP后才允许入口处理；终局拒绝，不凭首个玩家出现猜已加载 |
| `GetGameSessionConfigValue(key, default)` | 服务端读取固定 `ws4_native_roster` map option；不是客户端自报身份或认证凭据 |
| `SendToServerConsole` | 受控服务端发送完整固定换图命令；消费一次性latch后才调用，不能无限重试 |
| `GetSteamAccountID/IsValidPlayerID/IsFakeClient/GetTeam/GetPlayer/GetConnectionState` | 联合确认名单、实体、连接与归属；任一API缺失或类型异常均失败关闭 |
| `CreateHTTPRequestScriptVM` | provider实际创建HTTP请求；工厂nil、连接失败、HTTP状态失败和业务错误分开记录 |

**不要重新引入 `GameRules:GetCustomGamePlayerCount`：该API在本次原生环境不存在。** 早期测试夹具曾错误提供它，导致候选准备阶段遗漏。夹具必须检查缺API路径，也不能用 `GetNumConnectedHumanPlayers` 替代尚未分配的原始名单数量。`script` 不是这里可依赖的Dota控制台执行入口；Tools诊断沿既有 `tools/map_c6/console.cjs` 的受控 `script_reload_code`，不能将诊断能力带进生产。

`native_cloud_handoff.lua` 只接受目标地图、受限production配置、四账号名单、容量4、非Tools、服务器与 `sv_cheats=0`，并等待名单稳定及最终复核。目标VM的 `native_cloud_roster.lua` 负责等待原名单全部真人回来，**不是**Steam/PWA身份授权。

当前源码有显式 `release_profile.native_cloud_roster_required`。required=true时空option、缺API、同world中option/配置改变均拒绝，不能“缺option就按单人继续”。无required标记的旧/helper路径可以返回not_required，但仍须走自己的认证/资源门禁。正常自动开局、startup发现/ready检查、档案与玩法释放都要尊重名单屏障，防止慢客户端在主机已进入阶段10后才分队，重现 `assignment_window_closed` 或错误team5问题。

相关模块：`systems/native_cloud_handoff.lua`、`native_cloud_roster.lua`、`native_setup_auto_start.lua`、`startup_loading_service.lua`。测试在 `tools/native_arcade_cloud_20261027/`；已有纯夹具通过和真实两人证据须分别保存。

## 4. 离线作弊与联网禁作弊

用户明确要求：**离线模式可用作弊码，联网模式不可用。** 当前 `core/release_policy.lua` 只在受信 `channel=development`、服务器 `IsInToolsMode()==true`、且配置显式 `player_web_auth.enabled=false` 时允许开发入口；缺失/异常配置拒绝。生产版即使通过Tools启动，也不能取得开发授权；`sv_cheats`、房主和客户端字段不能替代构建身份。

离线provider只在本局内存中保存，不接HTTP、不接真实凭据、不读取任意fixture存档、不能写云档。联网助手与原生游廊都必须保留服务器禁作弊及业务侧拒绝；不能为了诊断在线局直接开 `sv_cheats`、放宽测试白名单或载入热重载命令。

输入和诊断仅在显式开发范围生效。原生多人的连接能力、网页登录是否需要再次授权、商城是否开放、存档能否写入是不同开关，不能相互作为跳过其他门禁的理由。

## 5. 事件、调度器和modifier

`core/event_bus.lua` 保留当前分发快照：回调中增删订阅只影响后续emit；嵌套事件结束后，`after_dispatch(key, callback)` 合并同键投影，避免界面读到半成品。reset更换generation，旧订阅不能误删新世界订阅，旧待办不能继续执行。不能依赖表遍历的偶然订阅顺序完成跨服务事务；隔离某个处理器异常也不等于整笔业务成功。

`core/scheduler.lua` 与 `deadline_queue.lua` 使用索引最小堆，只取到期任务，取消/替换立即删节点，不积累延迟取消残骸。同ID显式新任务优先于旧回调返回的重复间隔；clear使执行中的旧任务失效，init每局重绑引擎Think。先收集本轮到期批次，回调中新加的零延迟任务不插入当前批次。0.05秒Think不是逐帧承诺；Tools CPU采样不等于整帧耗时或实机FPS。

`core/modifier_registry.lua` 先加载全部定义、验证最终class，再统一 `LinkLuaModifier`；加载链可能替换class表，不能只以require成功作为绑定成功。ensure复用已有实例，创建失败最多每5秒重试。初始化需获得真实game-mode entity；重启/换图不沿用旧modifier注册状态。

现有回归：`tools/test_event_bus_after_dispatch.lua`、`test_event_bus_dispatch_cache.lua`、`test_deadline_scheduler.lua`、`test_scheduler_replacement.lua`、`scripts/vscripts/tests/test_modifier_registry.lua`。本次整理未重跑。

## 6. 实体、生命值与效果生命周期

`core/target_history.lua` 将命中历史绑定真实句柄/world/generation/token。预算清扫不能删同玩家后继桶；reset先撤销归属，再取消任务/调用原生清理，防重入触碰新状态。强引用随失效/到期清扫释放，不能为防entindex复用而无限持有实体。

`core/hero_health_guard.lua` 将最大生命变化与治疗分开：`preserve_current`保当前值，`preserve_missing`保已损失血量（最大生命加多少，当前生命相应加多少），不是保旧百分比。主动治疗先 `allow_healing()` 撤销旧保护；延迟任务只在仍拥有最新代际时修正异常补满，不能抵消正常回血/吸血。

肉鸽CSV只引用注册的effect/event/predicate，不能执行自由Lua。grant、effect instance、phase instance、target binding分别管理幂等、阶段与目标。新机制先扩handler与生成契约，再接配置；资源和属性仍走既有业务服务。结束效果需要清理到期任务、目标绑定与handler，不能只隐藏卡牌。源：`systems/rogue_effect_runtime_service.lua`、`rogue_effect_registry.lua`、`rogue_event_registry.lua`、`rogue_predicate_registry.lua`。

## 7. 在线时长、预载和终局清理

`systems/online_time_service.lua` 将active/finalizing分离；首次、新session、超租约间隔不直接累计；断线只结算对应玩家，已有请求未完成则排队final，回调检查代际，重连不能接收旧身份结果。时长按可信检查点和持久凭据入账，不按客户端帧数或网页打开时间发奖励。旧 `game_end` 不可靠促成多个终局入口，并不表示所有退出/崩溃路径已验收。

`asset_preload_service.lua` 与 `startup_asset_preload_service.lua` 让正式出生、调试出生和预载共享模型解析，urgent请求不能被后台批次阻塞，旧session/回调可失效。`retire()`只是逻辑状态，不是引擎卸载，更不能证明从未加载的资源已经存在。资源列表、模型组件、皮肤与实际载体必须配套；新增模型要冷启动检查。

墙和导航依赖真实地图、障碍登记及碰撞；近战接触位负责正面攻击/候位/补位，障碍释放恢复底层地形并处理重叠引用。不能靠瞬移、隐形第二层实体、叠第二排或随意关碰撞掩盖路径错误。Lua夹具不能证明引擎不堵路，地图更新后应分别验证GridNav、地面高度、墙生死与路径恢复。

## 8. 源地图、编译地图、发布包是三种身份

content的可编辑 `maps/template_map.vmap`、game的编译 `maps/template_map.vpk`、外层工坊VPK和签名清单必须分别识别。文件mtime或“编译文件存在”不足以证明与当前Hammer源码匹配。既有 `tools/map_c6/verify-map-package.cjs` 核对内部资源CRC与嵌入原始源码CRC；通过只能证明编译对应和包完整，不能当作实际地图行为通过。

2026102802记录的例子：当前可编辑图SHA256为 `4e62350c1bf08e663f5217885f26652918c2e09296a829f29a987ba8a14dccdc`，旧编译图仍带源CRC736803486；重新编译后的307条CRC通过，源CRC3557144492与当前源码匹配。正式包仅替换主地图，保留认证、支付、二维码、布局及180个受保护模块。长期维护应保留“源码→编译证据→签名清单→官方下载→原生范围”的链条，而不把本例摘要硬编码成下一版期望。

外层发布沿现有 `stream_workshop_vpk.py`、`incremental_vpk.py` 的只读验证/新目录构建：保持原版不可变，替换资源使用独立文件；未改分卷可只读硬链接复用，**禁止在硬链接文件上改属性、截断或覆盖**。重写哪个卷按实际路径归属/容量确定，不能永远假设只重建0卷。Ed25519发布签名、CRC/双hash/MD5、官方下载、原生加载和多人玩法分别留证，任一层通过不自动包含后一层。

game/content两仓配套提交推送，地图LFS继续沿原属性。固定同步顺序及用户原有改动保护读各仓 `AGENTS.md`，不在知识库复用某次102项脏文件数量作为永远规则。密钥、令牌、完整授权URL、原始交易/账号隐私、本机缓存和日志不进入新项目运行包或公开上下文。

## 9. 恢复新任务时应怎样取证

先读本模块、02/03和当前发布记录，再从对应source file进入调用链。保存首个失败层：资源读取错误、API缺失、身份拒绝、HTTP状态、业务错误、数据库冲突、UI未知数据、引擎崩溃不要混为一个原因。历史粒子重复释放模拟复现不是所有particles.dll崩溃的唯一根因；“编译实体存在、运行ent_find为0”应停在实体加载层，不继续堆饰品掩盖问题。

源码、自动夹具、隔离数据库、helper实机、普通工坊单人/双人、真实付款/到账分别标范围。不要为测试变绿补造不存在的原生API、放松准入、手补死亡事件、假造HTTP200、管理员改余额或把旧版回执转记为新版。多人/迟加入/重连、完整长局、账号权限、服务脱离作者电脑运行和实际付费交付仍按各自最新证据独立验收。
