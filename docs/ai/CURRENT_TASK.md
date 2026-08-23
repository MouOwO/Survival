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

## 当前插入任务（2026-08-21）：局内钓鱼抽奖系统

- 已读取用户提供的 `D:\tooltip文件夹\钓到物奖励效果统计.csv`。文件实际是 WPS OLE/BIFF 工作簿而非文本 CSV，已通过 WPS COM 只读提取 `Sheet1`：原始 27 条记录、出现次数合计 129。
- 已按确认口径整理为项目权威 `data/csv/玩家档案系统/fishing_reward_definitions.csv`：删除待复核 B 级条目，修订 `鬼索子` 为伐木工攻速提高 4 倍、普通 `金枪鱼` 为伐木工攻速+5%，正式池 26 条、总权重 128；基础数据全部来自 CSV。
- 新增独立 `systems/fishing_service.lua`，不复用局外 HTTP/档案钓鱼服务。首次难度选择成功事件后启动计时，0 秒不抽奖，之后每 480 秒遍历在线玩家并独立按权重抽奖；结果通过 `UI_NOTIFICATION` 的 `audience="all"` 全体播报。
- 奖励投影复用资源事务、`TECHNOLOGY_STATS_ROGUE_ADD_REQUEST` 和现有建筑列表/实体接口；持续金币/木材由局内服务按秒结算，墙生命奖励保留到后续新建墙。`fish <reward_id|random>` 已接入作弊命令。
- 自动验证通过：配置生成成功、26 条/128 权重/无待复核行/局内间隔 480 秒、Lua 5.1 行为测试 `FISHING_SERVICE_PASS`、目标 Lua 语法 `FISHING_FINAL_LUA_PASS` 和限定 `git diff --check`。尚未进行 Workshop Tools 冷启动、多人实机播报和实体效果验收。

## 当前插入任务（2026-08-15）：Builder动态管理域与全链路Ability安全枚举

- Workshop Tools实机日志确认Builder的`GetAbilityCount()`并不必然为64；`builder_progression_system.lua`把固定63作为最低扫描上限，才导致每次同步访问不存在的`8..63`。失败同步会在布局校验、冷却快照、清理和重建后校验中重复枚举，因而同一问题出现四组越界告警。
- 实机Builder的engine index 0由未知非管理Ability占用，项目管理的六个CSV业务槽与Blink自然位于`1..7`。现有绝对`0..6`验证会把有效布局判错并反复重建；修复必须保留非管理Ability，以首个现有管理Ability为管理域起点，无管理实例时从实际Ability数量之后自然追加，并只验证管理域内的相对连续顺序。业务快捷键继续以CSV生成runtime字段`builder_slot_order`为权威，不读取绝对engine index。
- `hud_takeover.js`和`survival_grid_placement.js`仍固定调用实体Ability槽`0..23`；本轮统一改为消费`survival_ability_runtime["unit:<entindex>"].ability_count`。固定24/64上限只允许枚举Valve `AbilityN` HUD面板节点，禁止用于`Entities.GetAbility()`。
- 自动验证范围：index 0非管理Ability保留、重复/过期管理实例清理、建筑上限技能与占位替换、冷却保留、正确布局幂等、服务端与Panorama禁止越界访问、Lua 5.1语法、相关PowerShell契约、Panorama资源编译、严格UTF-8及双仓限定`git diff --check`。最终仍需Workshop Tools冷启动验证高级研究所与农场流程，并确认控制台无`invalid index`和Builder布局重建失败。
- 实施完成：服务端单次同步先按真实数量生成Ability快照，校验、冷却捕获和清理复用该快照，重建后仅再安全枚举一次；布局诊断现包含`ability_count`、`domain_start`、有效槽清单和期望布局。四份Panorama实体访问统一消费runtime数量，`hud_takeover.js`收到当前单位数量元数据变化时会重建可见槽。
- 自动验证通过：`BUILDER_ABILITY_SLOTS_LUA51_PASS`、`BUILDER_ABILITY_SYNC_CONTRACT_PASS`、`BUILDER_CHALLENGE_MERGE_CONTRACT_PASS`、`ABILITY_RUNTIME_PUBLISH_LUA51_PASS/CONTRACT_PASS`、研究所runtime/Ability同步/高级研究/Grid相关Lua 5.1与契约、输入生命周期、utility顺序、目标Lua 5.1语法、Builder CSV生成9行一致及双仓限定`diff --check`。四份Panorama JS均强制编译为`1 compiled, 0 failed, 0 skipped`。`test_builder_hero_replacement_contract.ps1`通过本轮相对域断言后仍被前序英雄异步预载实现中的显式`SetOwner()`触发旧的`HERO_OWNER_MANUAL_TRANSFER_FORBIDDEN`阻断；对应Builder英雄替换Lua行为通过，本轮未修改无关召唤ownership逻辑。
- 尚需Workshop Tools完全Stop并冷启动：建造普通研究所后短测高级研究所，建造/销毁农场验证技能移除恢复，并确认控制台不再出现`invalid index`或`failed to rebuild authoritative ability layout`。自动测试与资源编译不能称为引擎实机验证或用户验收。

## 当前插入任务（2026-08-15）：Ability runtime重建与Panorama安全枚举修复

- 合并冲突使`ability_runtime_builder.lua`的`upgrade_level()`丢失`display`参数和默认值，城市升级构建runtime时访问`display.health`报错；现已恢复参数并用空表作为其他建筑调用的兼容默认值。主城继续隐藏生命/护甲，城墙等其他建筑仍默认显示。
- `ability_runtime_service.lua`现以`unit:<entindex>`元数据发布服务端真实`unit:GetAbilityCount()`，单位销毁时清零并写`removed=1`。`ability_tooltip.js`和`combat_stats.js`仅在元数据到达后按该数量调用`Entities.GetAbility(unit, slot)`，不再固定探测引擎Ability槽；高级研究所第七至第十槽的Valve面板几何外推继续保留，它只枚举HUD节点，不访问实体Ability API。
- 新增Ability runtime发布行为测试与独立契约，覆盖真实数量、零数量、销毁清理、builder参数恢复、tooltip/combat全部实体扫描边界和固定HUD面板枚举保留。自动验证通过：`ABILITY_RUNTIME_PUBLISH_LUA51_PASS`、`ABILITY_RUNTIME_CONTRACT_PASS`、`RESEARCH_LAB_RUNTIME_LUA51_PASS`、`ADVANCED_RESEARCH_LAB_CONTRACT_PASS`、相关研究回归、目标Lua 5.1语法、严格UTF-8及双仓限定`diff --check`。`ability_tooltip.js`和`combat_stats.js`均强制编译为`1 compiled, 0 failed, 0 skipped`。
- 尚需Workshop Tools完全冷启动：选中Builder、普通/高级研究所及英雄，确认runtime正常重建、主城Tooltip字段正确，并观察控制台不再出现无效Ability索引`8..17`访问。自动验证和资源编译不能称为引擎实机验收。

## 当前插入任务（2026-08-15）：主城升级Tooltip隐藏生命与护甲变化

- 用户要求“升级主城”技能Tooltip不再显示生命、护甲的升级前后变化，等级、人口上限、资源费用、状态等其他内容保持现状。
- 数据边界：主城实际生命、护甲、人口和升级费用继续读取`building_levels.csv`并照常结算；仅调整`ability_upgrade_city`运行时Tooltip字段，不影响城墙、农场、金矿或防御塔升级Tooltip。
- 验证要求：增加专项Lua测试，锁定主城字段过滤和其他建筑回归；执行Lua 5.1语法、严格UTF-8及限定`diff --check`。自动验证不等于Workshop Tools实机Tooltip验收。
- 实施完成：`ability_upgrade_city`调用通用建筑升级视图模型时显式关闭生命、护甲字段；主城实际升级数值与结算未改，通用逻辑的其他调用继续默认显示原字段。
- 自动验证通过：`CITY_UPGRADE_TOOLTIP_FIELDS_PASS`、生产与测试Lua 5.1语法、目标文件严格UTF-8及限定`diff --check`。尚需Workshop Tools冷启动或脚本热重载后悬停“升级主城”确认最终视觉；自动测试不等于引擎实机验收。

## 当前插入任务（2026-08-15）：城墙同时攻击地面怪数量由五只收紧为四只

- 用户实机确认当前城墙可同时被五只地面怪攻击，批准通过小幅增大正式地面波次怪碰撞体，将同时攻击数量收紧为四只。
- 实施边界：城墙Hull继续保持256；正式地面普通怪、领头怪、精英和Boss的基础Hull由29调整为32，并改由`global_rules.csv`权威配置；不修改攻击距离、模型或模型缩放。普通飞行怪Hull 10、特殊飞行怪Hull 0及五种挑战怪固定Hull 0保持不变。
- 验证要求：更新地面/飞行碰撞专项测试，执行CSV生成一致性、Lua 5.1行为与语法、严格UTF-8和限定`diff --check`。自动验证不等于Workshop Tools实机确认四只同时攻击。
- 实施完成：`global_rules.csv`新增`wave_ground_monster_hull_radius=32`并定向生成；`wave_monster_collision`改为读取该权威配置，正式地面普通、领头、精英和Boss统一从29增至32。城墙、飞行怪、挑战怪、攻击距离和模型配置均未修改。
- 自动验证通过：`WALL_COLLISION_BLINK_LUA51_PASS`、`WAVE_FLYING_COLLISION_PASS`、目标Lua 5.1语法、`GLOBAL_RULES_BYTE_MATCH_PASS`、严格UTF-8及限定`diff --check`。尚需Workshop Tools完全冷启动观察城墙周围实际站位，确认同时攻击者由五只变为四只。

## 当前插入任务（2026-08-15）：研究所十槽Tooltip代理几何、点击路由与ARS-01图标

- 生产实现完成：`ability_tooltip.js`按研究运行时权威签名枚举普通六槽和高级十槽，不再把Valve当前已创建的Ability按钮数量误当作研究槽总数。真实槽继续读取Valve按钮几何；缺失槽位根据最后两个真实按钮的水平步距外推，步距无效时回退到按钮宽度，并用显式窗口矩形定位透明代理、执行光标命中，绝不访问不存在的Valve锚点。
- 自定义Tooltip和点击路由已覆盖真实槽与外推虚拟槽。左键统一进入项目研究输入；高级研究所右键窗口、自动研究和既有链式替换协议保持。ARS-01/Q图标已从权威`research_lab_abilities.csv`改为`furion_force_of_nature`，定向生成Lua与Ability KV同步，KV继续保留UTF-8 BOM。
- 自动验证通过：`ADVANCED_RESEARCH_LAB_CONTRACT_PASS`、`ADVANCED_RESEARCH_LAB_LUA51_PASS`、`RESEARCH_LAB_ABILITY_SYNC_LUA51_PASS`、`RESEARCH_LAB_RUNTIME_LUA51_PASS`、`ABILITY_INPUT_LIFECYCLE_CONTRACT_PASS`；目标Lua通过`luac5.1 -p`，PowerShell契约通过语法解析，CSV与生成Lua逐字节一致，三层ARS-01图标一致，目标文件严格UTF-8且BOM约定不变，双仓限定`git diff --check`通过。
- `ability_tooltip.js`已由Resource Compiler定向强制编译为`1 compiled, 0 failed, 0 skipped`；`ability_tooltip.vjs_c`非空、时间戳晚于源码且SHA-256为`896B033C05F1533962D8CC41752E63270514DFC5FC146780AEAA75D3CD088D47`。尚未Workshop Tools实机验证；下一步完全冷启动，逐项检查普通/高级研究所`Q/W/E/R/T/A/S/D/F/G`的实际几何、自定义Tooltip、左右键、链式替换和第七至第十槽命中。

## 已完成插入任务（2026-08-15）：研究所Grid常红与Builder快捷键错位修复

- 三次实机反馈：专用地面移动型Grid预览代理上线后，普通研究所在空旷合法地形仍四格全红，而同位置人口农场可显示合法网格。根因已从Git历史和运行调用链确认：高级研究所接入时误把`requires_building_id = "building_research_lab"`同时写入普通研究所定义，使普通研究所要求“先完成普通研究所”。`building_system.can_place()`在地形校验前固定拒绝，Grid router再把该业务错误强制投影为四个红格，因此此前两轮Hull修复无法生效。
- 当前实施：建筑运行配置改为从CSV生成的`builder_ability_stages.lua`按`building_id`投影`requires_building_id`。普通研究所CSV前置为空，运行时必须清除自前置；高级研究所和挑战建筑继续要求已完工普通研究所。保留专用预览代理，不修改已实机确认正确的W/A/D快捷键、费用、占地或真实建筑碰撞。
- 本轮自动验证完成：真实运行配置加载结果为普通研究所`requires_building_id=nil`、高级研究所和挑战建筑均为`building_research_lab`；`BUILDING_PREREQUISITE_PROJECTION_LUA51_PASS`、研究所Grid、Builder槽位、高级研究所、挑战建筑、研究runtime/同步、禁建区域、建筑等级与箭塔费用等11项Lua 5.1回归通过，7项直接相关PowerShell契约通过，Builder前置CSV与生成Lua逐建筑一致，生产/测试目标严格UTF-8、本轮新增文档行无替换字符且限定`diff --check`通过。`building_system.lua`既有UTF-8 BOM仍会让本机`luac5.1`直接报首字节错误，本轮未修改该文件；去BOM内存源码语法检查通过。用户随后明确确认普通研究所全红且无法建造的问题已解决，本任务通过用户实机验收并关闭，不得再恢复为待验收项。高级研究所和挑战建筑的前置关系已有自动契约保护，但本次用户确认不扩展为对这两项行为的单独实机验收。
- 二次实机反馈：Builder全部技能按键现已正确，包含研究所`W`、挑战建筑`A`和Blink`D`，快捷键冲突已实机排除。研究所标题和2x2预览均正确出现，但空旷位置仍持续全红、无法建造，证明上一轮只给真实研究所预览写入0 Hull不足以解决引擎导航阻挡。
- 当前修复：Grid预览不再创建`building_research_lab`或其他真实静态建筑单位，统一创建专用`npc_survival_grid_preview_proxy`。代理KV使用地面移动能力，由现有预览Modifier固定、禁用交互并写入0 Hull；显示模型和缩放继续从CSV生成的建筑等级配置投影。这样预览不再以`DOTA_UNIT_CAP_MOVE_NONE`静态建筑身份参与`GridNav:IsBlocked()`，真实完工研究所仍保留Barracks Hull和2x2占地。
- 冲突复核：`builder_ability_stages.csv`及生成Lua仍为普通/高级研究所`slot_order=2`、挑战建筑`slot_order=6`；两个Ability分别绑定`building_research_lab`与`building_challenge`，Grid profile按Ability名称独立建立。没有修改已经正确并经用户实机确认的`W/A`热键配置。
- 本轮自动验证通过：`RESEARCH_LAB_GRID_PREVIEW_LUA51_PASS/CONTRACT_PASS`、Builder槽位、挑战合并、研究所runtime/Ability同步、禁建区域等相关Lua 5.1行为测试，5项相关PowerShell契约，目标Lua 5.1语法，9行Builder CSV/生成Lua槽位一致，NPC KV结构、生产/测试目标严格UTF-8和限定`diff --check`。`CURRENT_TASK.md`整文件仍保留此前已记录的1处历史U+FFFD，本轮新增文档行不含替换字符。该轮当时仍待冷启动验证且未解决固定全红，最终已由顶部自前置修复及用户实机验收覆盖。
- 最新实机反馈：普通研究所进入放置后所有Grid格持续红色，无法建造；主城完成后的Builder技能栏同时出现Q/W均为箭塔，后续建筑快捷键整体错误，只有按Ability名称路由的Blink/D正确。
- CSV核对：`builder_ability_stages.csv`仍明确箭塔/研究所/农场/祭坛/金矿/挑战为`slot_order=1/2/3/4/5/6`；研究所`building_levels.csv`为100木材、主城Lv.1前置，施工/视觉CSV均启用且2x2占地配置完整。没有修改这些正确的权威业务数值，生成Builder阶段9行逐项一致。
- 研究所Grid根因与修复：研究所预览复用`building_research_lab`静态creature，KV Hull为`DOTA_HULL_SIZE_BARRACKS`。预览Modifier虽声明`NO_UNIT_COLLISION`，大型静态Hull仍可能让同一位置的`GridNav:IsBlocked()`持续成立。`grid_placement_router.lua`现在只在预览实体边界写`SetHullRadius(0)`；真实完工研究所继续保留KV Hull、2x2逻辑占地和Grid占用。
- Builder根因与修复：动态`npc_dota_creature`不保证同步接受`SetAbilityIndex()`；上一轮失败后继续整组重建会反复移除/添加管理域，真实引擎可能留下同名实例或错误枚举，形成Q/W重复箭塔。现在同步为六个CSV业务槽创建隐藏占位Ability，严格按index 0..5自然添加当前业务技能/占位，再自然添加Blink到index 6，生产代码不再调用`SetAbilityIndex()`。占位Ability固定Lv.1、隐藏、未激活，不进入可见技能栏。
- 客户端保护：`ability_runtime_builder.lua`直接从生成`builder_ability_stages.lua`投影`builder_slot_order`；`combat_stats.js`和`hud_takeover.js`按该CSV槽位字段显示/分发`Q/W/E/R/T/A`，Blink继续按名称为D，不再把真实引擎的短暂错槽当作业务快捷键权威。
- 自动验证通过：`BUILDER_ABILITY_SLOTS_LUA51_PASS`、`RESEARCH_LAB_GRID_PREVIEW_LUA51_PASS/CONTRACT_PASS`、Builder runtime槽位Lua 5.1、研究所/高级研究所/挑战/英雄替换/六项玩法/禁建区域相关Lua 5.1回归、7项相关PowerShell契约、目标Lua 5.1语法、Builder CSV生成9行一致、严格UTF-8；`combat_stats.js`与`hud_takeover.js`均强制编译为`1 compiled, 0 failed, 0 skipped`。该轮快捷键已通过实机确认，但研究所Grid当时仍未解决；最终建造问题已由顶部自前置修复及用户实机验收关闭。

## 当前插入任务（2026-08-15）：Builder 六业务槽、Blink 与 Tooltip 同步纠正

- 二次实机回归（2026-08-15）：用户截图确认Builder城墙与Blink按钮同时置灰，因而上一轮点击代理修复后仍不能进入建造。权威CSV中开局城墙`required_city_level=0`且runtime独立检查为`available=1/can_afford=1`，置灰不来自资源、前置或客户端runtime判定。
- 根因与修复：严格布局同步在`AddAbility()`和`SetAbilityIndex()`后立即执行`layout_is_valid()`；真实`npc_dota_creature`动态技能槽重排可能不会即时生效，验证失败后旧代码提前返回，使新建Ability停留在默认0级/未激活状态，城墙与Blink因此整排置灰。现在每个`AddAbility()`返回的真实实例会立即写入Lv.1、可见和阶段激活状态，再独立验证槽位；槽位瞬时失败只记录诊断，不再留下禁用技能，后续同步仍可重建并自愈布局。
- 新增行为回归模拟引擎拒绝即时`SetAbilityIndex()`：严格布局失败时城墙与Blink仍必须Lv.1、可见、激活；恢复换位后下一次同步必须回到城墙index 0、Blink index 6。`BUILDER_ABILITY_SLOTS_LUA51_PASS`、Builder同步/输入/挑战/英雄替换契约、挑战与英雄替换Lua 5.1、Builder/Grid请求路由Lua 5.1语法、CSV生成9行一致、严格UTF-8及限定`diff --check`通过。仍需完全Stop并重新Run Workshop Tools确认按钮不再置灰、Q立即出现Grid并能完成一次城墙建造。
- 紧急实机回归（2026-08-15）：用户反馈城墙及后续所有建筑点击后均无法建造，且项目网格完全不出现。权威Builder阶段CSV和施工规则保持启用，服务端同步也会将当前建造Ability设为1级、可见并按阶段激活；阻断位于Panorama透明Tooltip代理的左键分流。
- 根因与修复：代理曾仅在`managedUpgrade()`命中有效runtime时调用统一`SurvivalAbilityInput`；Builder Ability刚重建或runtime键短暂未同步时，`ability_build_*`会误回退`Abilities.ExecuteAbility()`，绕过`SurvivalPointTargetState`和Grid validation/commit。现在所有`ability_build_*`按Ability身份无条件进入统一项目输入，只有非项目托管技能才允许走Valve原生执行。
- 紧急修复自动验证通过：`ABILITY_INPUT_LIFECYCLE_CONTRACT_PASS`、`BUILDER_ABILITY_SYNC_CONTRACT_PASS`、`BUILDER_CHALLENGE_MERGE_CONTRACT_PASS`、`BUILDER_HERO_REPLACEMENT_CONTRACT_PASS`，Builder槽位/英雄替换/挑战建筑Lua 5.1行为，Builder/Grid目标Lua 5.1语法、生产源码/测试严格UTF-8且无替换字符、文档新增段落无新增替换字符和限定`diff --check`通过；`ability_tooltip.js`强制编译为`1 compiled, 0 failed, 0 skipped`，产物包含新分流符号。`CURRENT_TASK.md`整文件仍有1处既有历史U+FFFD，本次未猜测恢复。仍需完全Stop并重新Run Workshop Tools，确认城墙点击立即出现网格且可完成建造，再依次复测后续建筑。
- 用户已批准纠正 Builder Ability 同步：`builder_ability_stages.csv` 的六个业务槽 `slot_order=1..6` 必须顺序占用 engine index `0..5`，`ability_survival_builder_blink` 固定 engine index `6`；最终标签和输入为 `Q/W/E/R/T/A/D`，不得继续为 Blink 跳过 index 5。
- 服务端同步必须枚举真实 Ability 实例并校验完整布局。布局正确时保留现有 Ability 实体，只刷新等级、隐藏和激活状态；存在错槽、过期技能或任意同名重复时，清理 Builder 管理域并按权威目标顺序确定性重建，同时尽可能按技能名恢复目标技能剩余冷却。
- Panorama 保留 Valve 原生 Ability 面板，只投影稳定快捷键标签和输入。Builder engine index `0..5` 映射 `Q/W/E/R/T/A`，Blink 名称映射 `D`；显示与输入必须消费同一映射，不得按可见技能稠密下标猜测。
- 项目托管 Ability 只显示自定义 Tooltip。原生 Tooltip 压制和自定义 Tooltip 状态必须在 mouseout、选择或 Ability 变化、代理禁用、面板删除和脚本关闭时可靠清理；非托管 Ability 继续使用 Valve 原生 Tooltip。
- 实现完成：服务端按CSV目标布局枚举并校验真实Ability实例；正确布局保持实体，异常布局只清理Builder管理域并顺序重建，去除重复/过期技能，按名称恢复最长剩余冷却并执行重建后验证。最终业务槽为engine index`0..5`，Blink固定index 6。
- 实现完成：`combat_stats.js`和`hud_takeover.js`统一显示/输入`Q/W/E/R/T/A/D`。Valve原生按钮按窗口几何与可见Ability原子配对，项目统一显示`SurvivalAbilityHotkey`并保存/压制原生Hotkey；旧context或清理时恢复。Tooltip透明代理只覆盖托管技能，托管渲染失败不回退原生Tooltip，所有退出路径统一释放状态。
- 自动验证通过：Builder槽位、挑战合并、英雄替换、高级研究所与研究同步/运行时Lua 5.1行为，Builder同步/挑战/英雄替换/输入生命周期/utility顺序/高级研究所/Alt PowerShell契约，目标Lua 5.1语法，CSV与生成Lua一致，严格UTF-8和限定`diff --check`。`combat_stats.js`、`ability_tooltip.js`、`hud_takeover.js`均强制编译为`1 compiled, 0 failed, 0 skipped`并通过产物符号检查。
- 验证边界：`test_builder_utility_contract.ps1`在进入本次UI断言前失败于既有齐天大圣CSV射程断言；`test_memory_lifecycle_contract.ps1`失败于既有`survival_ui.js`缺少context门禁，均未修改无关文件迎合。最终七槽显示、`Q/W/E/R/T/A/D`输入、引擎内冷却恢复和单一自定义Tooltip仍需Workshop Tools完全冷启动实机确认。

## 当前插入任务（2026-08-15）：stash 冲突恢复、Builder 固定槽位与研究/挑战建筑并存

- 背景：`stash@{0}`恢复到更新后的`dev`后产生19个`UU`，同时全量生成器误执行留下无关生成文件工作区噪音。合并目标是保留上游五种挑战、自动Toggle和最新城墙数据，同时保留stash的普通/高级研究所、研究Ability和Tooltip代理。
- 合并完成：权威CSV同时保留普通研究所、高级研究所和独立挑战建筑。该任务当时把`slot_order=6`投影到engine index 6并跳过index 5；此槽位实现已被顶部当前任务纠正为六个业务槽`0..5`、Blink index 6。
- 运行链完成：KV、建筑配置、启动链和UI路由同时保留高级研究与挑战功能；启动补齐`ability_challenge_monster_05`。挑战Toggle与研究Ability直达分发并存；挑战建筑完工后拥有01-05和自动Toggle，高级研究所保持12槽原生Ability布局。
- Panorama完成：该任务当时按`npc_survival_builder_proxy`实体槽`0/1/2/3/4/6 -> Q/W/E/R/T/A`映射；此映射已被顶部当前任务纠正为`0/1/2/3/4/5 -> Q/W/E/R/T/A`，Blink按名称固定`D`。Toggle行为位512和冲突产物重编译结论保持不变。
- 自动验证通过：正式生成94模块；`BUILDER_ABILITY_SLOTS_LUA51_PASS`、`ADVANCED_RESEARCH_LAB_LUA51/CONTRACT_PASS`、研究同步/运行时、`BUILDING_CHALLENGE_MERGE_LUA51_PASS`、`BUILDER_CHALLENGE_MERGE_CONTRACT_PASS`、Ability输入/utility契约、目标Lua 5.1语法和限定diff检查通过。4个JS与2个CSS各`1 compiled, 0 failed`，HUD XML加载链`9 compiled, 0 failed`。
- Git冲突状态：19个`UU`、index unmerged entries和文本冲突标记均已清零；误生成的无关工作区差异已按当前index恢复。用户原有研究所、文档、商店、Tooltip和其他未跟踪测试修改均保留，未提交。
- 尚未Workshop Tools实机验证：冷启动后依次确认研究所完工时W高级研究与A挑战建筑同时出现、D/A输入不漂移、挑战01-05和自动Toggle、普通/高级研究Ability、切换单位后的标签清理与第二次Run输入生命周期。自动验证不能称为引擎或用户验收。

## 当前插入任务（2026-08-15）：按录像提取工作簿校正城墙全等级血量

- 用户要求按`C:\Users\li\Downloads\城墙全等级血量护甲数据_2026-08-15.xlsx`修正当前城墙血量；工作簿含1-30级、对应`1-1`至`10-3`的权威血量与护甲。
- 批准边界：只将工作簿D列血量按等级写入`building_levels.csv`的`building_wall_lv01-lv30.health`；工作簿E列护甲即使与当前CSV有差异也不修改，费用、名称、模型和其他建筑保持不变。
- 实施完成：LV1原值2000已一致，LV2-LV30共29个`health`已按工作簿更新，最终LV30为900000；`armor`及其他字段未改。使用正式生成器定向重建`building_levels.lua`。
- 自动验证通过：Excel/CSV/生成Lua的30级血量三方逐项一致，当前护甲序列保持不变；CSV严格UTF-8 BOM且无U+FFFD，配置CheckOnly、生成Lua与生命增量模块Lua 5.1语法、残血/满血升级增量行为和限定`diff --check`通过。既有未跟踪`test_building_upgrade_process.lua`仍在粒子清理处要求已废弃的`DestroyParticle(..., false)`，而生产实现为已批准的`true`，故该旧测试在进入血量逻辑前失败，未改测试迎合。尚未Workshop Tools实机逐级查看血条。

## 当前插入任务（2026-08-15）：恢复 CSV 中文乱码

- 用户反馈 CSV 中大量中文文本乱码，要求恢复。
- 当前 `data/csv` 下 93 份受版本控制 CSV 均无未提交修改；工作区其他源码与文档存在既有未提交改动，必须保留。
- 修复边界：以 CSV 为权威源，先执行全量字节编码、U+FFFD、典型错码和 CSV 结构审计；对有损乱码从 Git 历史中最后完好的同业务记录/字段恢复，不覆盖当前数值、结构或后来新增配置；修复后重建配置并验证严格 UTF-8、无乱码特征、CSV 可解析、生成一致性和限定 diff。
- 修复完成：实际共93份CSV。`building_definitions.csv`与`building_levels.csv`的243个受污染单元格（合计1301个U+FFFD）已分别从最后结构兼容的完好历史版本按行列/主键恢复；7份GB18030表无损转为UTF-8 BOM，其余缺BOM表补齐BOM。语义审计确认除上述两张建筑表的乱码恢复外无单元格内容变化。
- 自动验证通过：93份CSV全部严格UTF-8 BOM、0个U+FFFD、0个CSV解析错误；正式生成93模块并通过CheckOnly，94份生成Lua编码检查及Lua 5.1语法均通过。仅两份对应建筑生成Lua有真实内容差异；未覆盖工作区既有无关修改。需完全重启当前Dota 2测试会话后再观察游戏内中文，自动检查不等于引擎实机验收。

## 当前任务（2026-08-15）：城墙新护甲公式、地面波次怪统一碰撞与D位移截断

- 用户已批准实施三项调整：城墙物理承伤接入怪物当前使用的War3护甲公式；正式波次所有地面怪（普通、精英、领头怪、地面Boss）统一使用第一波小怪当前实际HullRadius 29；建造者、英雄、防御塔的D位移在鼠标落点超范围时沿该方向移动到最大距离，不再显示距离超限。
- 数据边界：城墙基础护甲继续读取`building_levels.csv.war3_armor`，科技`super_wall_armor_flat`和挑战奖励继续由`technology_stat_manager`聚合；禁止写死护甲。碰撞只改实际Hull，不改模型或`model_scale`；五种挑战怪继续固定Hull 0，飞行怪保持现有碰撞规则。
- 位移边界：建造者/防御塔最大距离1000，英雄球状传送最大距离800；过滤与实际施法必须校验同一个截断落点。地形不可达、不平坦、网格占用、旅行中等原有拒绝继续保留，防御塔继续经过`building_system.relocate_building()`。
- 验证要求：新增或扩展城墙护甲、波次碰撞和三类位移专项测试；执行Lua 5.1语法、相关Mock/契约、CSV生成一致性、编码与限定diff检查。自动验证不得称为Workshop Tools实机验证。
- 实现完成：城墙创建、恢复、升级、科技与挑战奖励刷新统一写入War3护甲身份并将原生Dota护甲归零；Damage Filter对城墙物理伤害应用`1/(1+0.02*有效War3护甲)`并设置忽略原生护甲，百分比穿甲继续先作用于War3护甲。科技与挑战层既有`/3`聚合在消费时乘回3，CSV基础与奖励单位保持权威。
- 实现完成：正式波次碰撞配置仅按飞行类别保留10/0，所有地面普通、精英、领头怪和Boss均为29；`monster_hull_scale`仍缓存基础Hull后非累计缩放，挑战怪独立Hull 0链未改，模型缩放未改。
- 实现完成：公共`blink_destination`用于建造者、英雄、防御塔过滤和执行；超范围目标沿鼠标方向截断到1000/800。防御塔Panorama权威请求入口也执行同一截断，随后继续做网格/占用校验并通过`building_system.relocate_building()`移动；其他失败条件保留。
- 自动验证通过：`WALL_DAMAGE_FILTER_LUA51_PASS`、`WALL_COLLISION_BLINK_LUA51_PASS`、`WAVE_FLYING_COLLISION_PASS`、12个目标Lua 5.1语法、目标严格UTF-8、移动KV括号/单定义、CSV全量重建与索引逻辑内容一致、限定`git diff --check`。旧`test_hero_ball_lightning_contract.py`仍在读取既有非UTF-8科技CSV时失败，未进入位移断言；本轮专项Lua已覆盖800截断。尚未Workshop Tools实机验证城墙伤害、波次拥挤移动和三类D技能。

## 当前任务（2026-08-14）：箭塔移动与确认销毁工具技能

- 用户已批准实施：仅基础箭塔及全部转职/升级形态增加移动D和无偿销毁G；城墙与其他建筑不包含。
- 槽位规则：现有升级、转职和战斗技能优先；6格栏至少空2格时显示移动与销毁，仅空1格时只显示销毁，无空格时两者隐藏且快捷键不得绕过；销毁始终排在最后。
- 移动继续使用现有1000范围、网格占用与平坦地形校验，移除城墙适用范围及独立备用按钮。销毁必须弹出确认框，只允许鼠标点击按钮确认，Esc取消；不得注册、处理或占用Enter。服务端验证所有权、箭塔身份、存活、非施工状态及可见技能后调用`ForceKill(false)`，不返还资源，沿既有死亡链释放网格、人口和数量名额。
- 自动实现完成：8份箭塔CSV共139个设计行均在既有主动技能末尾追加移动与销毁；统一同步器按6格可见技能数重排工具技能，保证升级/转职/战斗技能优先、销毁最后，并对隐藏技能同时停用。移动仅允许箭塔，继续复用1000范围、网格占用和地形校验；旧城墙范围与独立右下角按钮已移除。
- 销毁实现完成：G或技能点击只打开确认框，只能鼠标点击按钮确认，Esc/按钮取消；Enter未注册且不会被该功能处理。选择变化、单位失效或技能隐藏会自动取消。服务端重新验证玩家所有权、箭塔身份、存活、非施工状态及销毁技能可见可用后`ForceKill(false)`，不调用退款入口，沿既有死亡链释放网格、人口和数量名额。
- 自动验证通过：`ARROW_TOWER_UTILITY_CONTRACT_PASS`、93模块CSV生成与`--check-only`、目标及生成Lua 5.1语法（原带BOM的`building_system.lua`使用无BOM临时副本）、KV括号/技能定义、限定`git diff --check`。4个Panorama JS各`1 compiled, 0 failed`，HUD XML加载链`9 compiled, 0 failed`，CSS单独`1 compiled, 0 failed`；6个对应game编译产物已更新。
- 待Workshop Tools冷启动实机验收：基础塔1-5、7条路线不同等级/技能数量下的2空槽/1空槽/0空槽显示；D移动成功与越界/占用拒绝；G打开、鼠标确认、Esc取消、Enter完全不受影响、切换选择；销毁后资源不返还且网格、人口、基础塔/路线数量名额恢复。自动测试和编译不得称为引擎实机验证或用户验收。
- 实机检查发现基础箭塔名称显示为`����1-5`。根因是批量追加工具技能时，基础塔、冰霜和机枪三份权威CSV已有中文字段被写成U+FFFD，生成Lua原样传播；现从最后正确UTF-8历史版本按`record_id`和字段位置仅恢复受污染文本，保留当前数值、模型与工具技能，并新增8份塔CSV及生成Lua禁止U+FFFD、基础塔逐级名称精确匹配的契约。

## 已完成任务（2026-08-14）：挑战怪碰撞、建筑施工一致性与自动召唤输入

- 用户实测提出三项问题：五种挑战怪必须始终使用0碰撞体以避免卡怪；挑战建筑的占地、模型大小和施工特效需要与普通建筑一致，并统一消费现有建筑施工接口；自动召唤Toggle点击后没有执行自动判断。
- 当时将挑战怪固定为0 Hull；该碰撞规则已被2026-08-15“全部怪物与小怪碰撞体相同”的新需求替代，建筑施工与自动召唤部分仍有效。
- 挑战建筑继续使用普通2x2占地、`radiant_ancient001.vmdl`和KV回退缩放0.34；权威视觉CSV新增完工缩放0.34，施工CSV新增同一缩放及统一传送开始/持续特效，继续由`building_construction_visual_service`消费，不创建专属施工实现。正式生成器已重建93个Lua模块，目标生成行已复核。
- 自动召唤根因是两层遗漏：主HUD未把挑战Toggle列为托管建筑动作，且无目标分发只接受`NO_TARGET`行为位，会在客户端以`unsupported behavior`拒绝Toggle；服务端也未提供creature建筑的直达分发。现两套HUD入口均托管该Ability，主HUD允许Toggle行为位；路由完成ownership/建筑/Ability校验后切换权威自动状态并同步引擎Toggle，重入标记阻止`OnToggle()`二次反向请求。
- 自动验证通过：`BUILDING_CHALLENGE_CONTRACT/SERVICE/REWARDS_LUA51_PASS`、`WAVE_FLYING_COLLISION_PASS`、`WAVE_SPAWN_SEQUENCE_PASS`、目标Lua 5.1语法、正式CSV生成93模块、两个Panorama JS各`1 compiled, 0 failed, 0 skipped`及双仓限定`git diff --check`。挑战独立次数、冷却、成长、剑圣前置、奖励和正式波次隔离语义保持不变。
- 完成状态：用户于2026-08-14明确表示任务完成，本任务关闭且不得在后续会话中自动恢复为活跃或待验收任务，除非用户报告具体回归。此前自动验证证明静态跨层契约、Lua Mock行为、语法、生成配置及JS编译通过；用户未提供逐项Workshop Tools日志，因此记录为用户确认完成，不追加虚构的逐项引擎测试数据。

## 已完成自动实现（2026-08-14）：五种挑战怪独立进度与正式奖励纠正

- 用户纠正挑战进度与正式wave完全无关：山岭巨人、树人、红龙、剑圣、炼金各自按队伍维护本局挑战次数，最多20次；成功召唤第N只读取该怪第N条挑战CSV，生命为`N*1000`、War3护甲为`N*10`。
- 五种召唤技能独立冷却依次为100/110/120/130/140秒，仍共享手动/自动入口且同队同类最多存活1只。剑圣额外要求主城LV5，所有校验由服务端执行。
- 奖励按截图纠正为CSV权威：山岭巨人每次城墙护甲+3、生命+1%；树人箭塔攻击`+100*挑战次数`、攻击+1%；红龙伐木效率+1；剑圣英雄全属性`+1000*挑战次数`、攻击`+2000*挑战次数`；炼金金矿收益+2%。
- 生产实现完成：挑战定义自包含五种模型与战斗外观，不修改历史本地代码页怪物原型CSV；正式波次 getter 已从挑战服务依赖中移除。成功生成第N只时立即冻结独立挑战次数，建筑重建不重置次数或同类存活限制；达到20次后拒绝继续召唤。自动模式会跳过已满20次或主城前置不足的种类，继续检查后续种类，每Tick仍最多成功召唤一种。
- 奖励实现完成：通用奖励解释器按召唤时冻结的挑战次数缩放CSV效果；建筑/经济奖励进入`technology_stat_manager`独立challenge层，与研究科技和运行时成长合并且不被科技重算覆盖。山岭巨人War3护甲+3投影为Dota护甲+1；箭塔、城墙、英雄、伐木工沿既有`TECHNOLOGY_STATS_CHANGED`刷新，金矿产量额外消费挑战收益百分比。
- 自动验证通过：`BUILDING_CHALLENGE_CONTRACT/SERVICE/REWARDS_LUA51_PASS`、100行生成矩阵、正式波次飞行碰撞与生成顺序、怪物奖励回城、目标Lua 5.1语法、KV括号、六套本地化12个挑战token镜像、严格UTF-8及限定`git diff --check`。历史怪物原型CSV和生成Lua已确认相对任务前逐字节无变化。
- 验证边界：旧`test_gold_mine_income_numbers_contract.ps1`仍失败于content HUD任务前缺少`SurvivalInputLifecycleGeneration`，与本次服务端金矿收益公式无关，未越界修改。尚未Workshop Tools冷启动实测六个按钮、五种独立CD/20次进度、五模型、剑圣主城LV5、自动跳过、城墙AI、正式波次隔离和五种奖励实际到账。

## 当前插入任务（2026-08-15）：研究科技 Tooltip 与原生技能按钮恢复

- 用户实机确认上一轮研究所分组、固定槽位和单行排列整体完成，当前只调整表现层。
- 科技自定义 Tooltip 标题必须读取 `research_lab_abilities.csv.display_name`，例如“伐木工攻击成长”；当前科技等级继续单独显示。研究科技 Tooltip 删除“施法类型”和“科技编号”，其余费用、累计效果、升级后效果、等级上限、前置和状态保留。
- 普通与高级研究所技能按钮改回 Valve 原生 Ability 视觉，不再使用项目 52px 自定义按钮外观。固定槽位、`Q/W/E/R/T/A` 与 `Q/W/E/R/T/A/S/D/F/G` 输入、锁定/研究中/满级置灰、左键研究、右键高级窗口和自动研究必须保持。
- Valve 原生 Ability Tooltip 必须被屏蔽；透明代理继续负责项目自定义 Tooltip 和托管点击，且不得形成双 Tooltip。
- 生产实现完成：研究运行时发布`research_lab_abilities.csv.display_name`和服务端生成的科技描述/字段；研究字段删除“科技编号”并增加CSV前置说明。Panorama标题消费运行时名称，科技等级单独显示；研究所无条件绕过项目52px技能接管，独立透明代理负责自定义Tooltip、原生Tooltip压制、左键和高级研究所右键窗口。原生按钮角标按运行时固定槽位显示`Q/W/E/R/T/A/S/D/F/G`。
- 自动验证通过：`RESEARCH_LAB_RUNTIME_LUA51_PASS`、`RESEARCH_LAB_ABILITY_SYNC_LUA51_PASS`、`ADVANCED_RESEARCH_LAB_LUA51/CONTRACT_PASS`、Ability输入/utility顺序、研究减甲、超级塔暴击、目标Lua 5.1语法、PowerShell语法、两份CSV生成逐字节一致、严格UTF-8和限定`diff --check`。`ability_tooltip.js`、`combat_stats.js`、`hud_takeover.js`、`ui_bootstrap.js`均强制编译为`1 compiled, 0 failed, 0 skipped`。
- `technology_definitions.csv`结构化审计完成：schema与UTF-8 BOM不变；相对`HEAD`删除的20行仅为`tower_attack`/`wall_health`旧Lv.11-Lv.20，240行字段变化只涉及显式`prerequisite_id`、高级链衔接等级10和三组英雄科技3转，没有费用、效果、名称或图标漂移。
- 尚未Workshop Tools实机验证。下一步完全冷启动，确认普通六槽和高级十槽均为Valve原生按钮、固定角标与输入一致、锁定/研究中/满级置灰正常、自定义Tooltip标题/字段正确且无Valve双Tooltip，并验证左键研究、右键高级窗口、自动研究和完成后即时刷新。

## 当前插入任务（2026-08-15）：研究所科技分组、前置、快捷键与技能栏重构

- 用户批准普通研究所固定六槽`Q/W/E/R/T/A`：速度低/高级链、普通伐木效率、防御塔低/高级链、城墙低/高级链、高级伐木效率、伐木暴击。只有速度/防御塔/城墙在普通科技满10级后同槽切换高级科技；未解锁和满级科技均保留原槽并置灰。
- 高级研究所固定十槽`Q/W/E/R/T/A/S/D/F/G`，只显示排除普通九组和金矿两组后的十组`ARS-01..10`科技。已删除Panorama专属5x2布局，统一使用建造者同款52px单行技能栏；右键高级研究技能仍打开高级研究窗口并保留自动研究。
- 权威`technology_definitions.csv`已把高级防御塔/城墙衔接等级统一为10，三项英雄科技转生要求统一为3；`research_lab_abilities.csv`已写入六槽/十槽顺序。两份生成Lua均由CSV定向重建并逐字节一致。
- `research_technology_config.lua`改为消费生成科技定义的兼容适配层，仅保留稳定`RS-*`/`ARS-*`身份和效果类型转换；等级、逐级费用、前置、转生和累计效果不再手写。Repository、Service、Ability运行时、Tooltip和商店继续消费同一适配定义。
- Ability同步在研究开始、完成、资源和转生变化时刷新；未解锁、研究中和满级均调用`SetActivated(false)`，满足条件后恢复。满级运行时仍发布固定槽位/建筑/科技组身份，快捷键不会退回普通稠密序号。
- 自动验证通过：研究同步/运行时/高级研究Lua 5.1、19科技420级调试事务、研究分组`9/10/2`、高级窗口十组隔离、研究减甲、超级塔暴击、Builder槽位、Ability输入生命周期/utility顺序、PowerShell契约、目标Lua 5.1语法、CSV生成逐字节一致、严格UTF-8和高级单行静态检查。`combat_stats.js`、`hud_takeover.js`、`ability_tooltip.css`定向资源编译均为`1 compiled, 0 failed, 0 skipped`。
- 尚未执行Workshop Tools实机验证。下一步完全冷启动，逐项确认普通六槽、三条同槽切换、锁定/满级置灰恢复、高级十槽单行、`QWERTASDFG`输入、右键窗口和自动研究；自动测试不能称为引擎实机验收。

## 前一插入任务（2026-08-15）：研究所技能与高级研究所建造实机阻断

- Workshop Tools 冷启动实机发现 `combat_stats.js:1057` 调用不存在的 `refreshOfficialReturnHomeHotkey([])`，导致 `refreshAbilities()` 初始化中断，普通研究所技能栏未能正常刷新。
- 当前工作区同时存在高级研究所实现漂移：权威 `builder_ability_stages.csv` 的 W 后继仍是无运行实现的 `ability_build_challenge`，生成 Builder 阶段缺少 `requires_building_id`，且研究所 Ability 同步/高级研究所建筑定义尚未完整接入启动链。
- 实施完成：无效选择分支改为已有 `refreshOfficialUtilityHotkeys([])`；普通研究所5条科技链与高级研究所10项科技均从 `research_lab_abilities.csv` 初始化、固定槽位并在研究开始/完成时同步。研究 Ability 请求重新验证 Ability、完工建筑、building ID、owner/team、激活状态及来源，再复用原2秒研究事务；高级研究右键窗口与自动研究队列恢复。
- Builder W 现在只在普通研究所完工后替换为 `ability_build_advanced_research_lab`；主城不足Lv.4时置灰，达到Lv.4后激活。建造系统再次验证已完工普通研究所，不能用施工中计数绕过。高级研究所保留 `radiant_ancient001.vmdl`、`0.34` 缩放、`2x2` 占地和 `AbilityLayout 12`。
- 自动验证通过：`RESEARCH_LAB_ABILITY_SYNC_LUA51_PASS`、`RESEARCH_LAB_RUNTIME_LUA51_PASS`、`ADVANCED_RESEARCH_LAB_LUA51/CONTRACT_PASS`、`BUILDER_ABILITY_SLOTS_LUA51_PASS`、Ability输入/utility顺序契约、19项研究Ability KV覆盖、CSV/生成结构与高级研究所成本/视觉一致、目标Lua 5.1语法、严格UTF-8和双仓限定`diff --check`。`combat_stats.js`、`hud_takeover.js`、`shop_ui.js`均强制编译为`1 compiled, 0 failed, 0 skipped`。
- 两项额外宽泛回归仍为无关既有失败：`test_builder_ownership.lua`要求当前CSV Builder移速；`test_builder_utility_contract.ps1`要求猴王CSV射程1000。相关生产数据不在本轮差异中，未为研究所任务修改。下一步完全停止并冷启动Workshop Tools，确认不再出现该ReferenceError、普通研究所Q/W/E/R/T、完工后Builder W替换、高级研究所建造与QWERT/ASDFG布局；自动验证不能称为引擎实机验收。

## 当前插入任务（2026-08-14）：神秘塔LV4攻击W10 Boss高护甲补偿修复

- 根因来自提交`462eb84`加入的怪物物理伤害曲线补偿，不是激光间隔、重复Modifier、光环或缓存。当前Dota护甲承伤曲线为`1 - 0.06A/(1+0.06|A|)`；项目继续按`A=W/3`投影War3护甲，因此正甲原生承伤已经严格等于目标`1/(1+0.02W)`，无需额外普通物理补偿。
- 原规则`0.052/0.9/0.048`使W10 Boss的477 War3护甲投影为159后产生约3.06624倍错误预补偿，解释单座LV4神秘塔从预期45～46秒缩短到20多秒。权威`war3_damage_calculator_rules.csv`现改为`numerator=0.06/base=1/denominator=0.06`，`armor_balance.lua`统一消费生成规则，不再重复硬编码引擎曲线。
- 现有Damage Filter、怪物身份开关和物理护甲无视入口保留。普通项目怪物物理伤害在117/477/4990 War3护甲下补偿均为1；有物理护甲无视时仍按有效护甲倍率与原生护甲倍率之比预补偿。`from_war3_modern()`兼容API也按同一生成规则求解，当前参数下自然退化为线性`W/3`。
- W10回归直接读取生成配置：`n1_wave_10_10b`为60000生命/477护甲，`mystery_tower_lv04`为3801攻击/每秒1次，`laser_lv04`为1.6起始倍率/每秒增长0.05。按生产首次锁定立即激光Tick的离散模型，`t=44`累计60044.259962伤害，覆盖预期约45～46秒实机计时。
- 自动验证通过：`MONSTER_WAR3_ARMOR_DAMAGE_LUA51/CONTRACT_PASS`、`WAR3_DAMAGE_CALCULATOR_CONTRACT_PASS`（Edge 1440/390各62项）、`TOWER_LASER_BASE_MULTIPLIER_LUA51/CONTRACT_PASS`、研究减甲、毒云、塔射程、超级塔科技和六项玩法回归；目标Lua 5.1语法、生成Build/CheckOnly、严格UTF-8及限定`git diff --check`通过。研究减甲与毒云旧包装器需要按既有约定设置项目`LUA_PATH`后运行，业务断言通过。
- 下一步：完全停止并冷启动Workshop Tools，只放置单座LV4神秘之塔攻击N1 W10进攻Boss，记录从首次伤害到死亡的时间与`MONSTER_PHYSICAL_DAMAGE_FILTER`样本；目标约45～46秒，`armor_compensation`应为1。自动测试和离散模拟不能称为引擎实机验证或用户验收。

## 已完成任务（2026-08-14）：研究所前置的挑战建筑

- 生产实现完成：新增最多1座、消耗100木材且不可升级的挑战建筑；研究所完成后Builder的W槽由研究所替换为挑战建筑。Builder投影与`building_system`服务端均校验前置，客户端直接提交不能绕过。
- 建筑提供4个手动召唤技能和1个自动Toggle。完工时四技能均进入150秒CD；手动与自动共享技能CD。自动模式每秒检查一次，每Tick最多按CSV固定顺序召唤一种。
- `building_challenge_waves.csv`显式配置1-30波×4种共120条记录，首版统一为生命200、攻击2、War3护甲2、每秒攻击1次和Boss身份；四种外观来自已确认怪物原型并在Addon Precache阶段显式预载。
- `building_challenge_service.lua`按team维护同种最多1只的存活身份，建筑摧毁重建也不能绕过。`wave_system.spawn_challenge_monster()`复用正式出生Marker、战斗属性投影、Boss碰撞、尸体生命周期及攻击城墙AI，但不登记正式`enemies`，不修改波次planned/pending/spawned/alive/killed/boss_alive，不进入胜利或正式怪物奖励链。
- 奖励复用通用CSV效果解释器：`reward_building_challenge_wood_1000`当前仅启用`add_wood=1000`，归建筑所属玩家team；既有英雄成长效果类型可供后续扩展，本轮未擅自发放研究Buff。
- 自动验证通过：正式全量CSV生成93个Lua模块；`BUILDING_CHALLENGE_CONTRACT_PASS`、`BUILDING_CHALLENGE_SERVICE_LUA51_PASS`、120行生成矩阵、奖励配置、目标Lua 5.1语法、严格UTF-8、KV括号、限定`git diff --check`、怪物奖励、波次碰撞和生成顺序回归通过。`building_system.lua`因历史UTF-8 BOM使用去BOM临时副本通过Lua 5.1语法。
- 验证边界：全量`build_configs.ps1 -CheckOnly`仍因历史`building_definitions.lua`和`building_levels.lua`含字面U+FFFD报告`bad_utf8=2`；本轮新增挑战行及核心文件严格UTF-8通过，未越界重写历史损坏数据。尚未Workshop Tools实机验证W槽替换、五个按钮、独立CD、四秒自动顺序、模型、城墙AI、波次隔离和木材到账。

## 当前实施任务（2026-08-14）：机枪每秒轮次与逐跳独立暴击

- 用户已批准将三条机枪路线改为防空弹幕式脚本轮次：原生攻击每秒只启动一轮，隐藏原生弹道、声音、命中特效与伤害；每轮首跳立即结算，目标死亡后取消该轮剩余跳且不转射。
- LV1-LV5每轮固定为`6/7/8/8/8`跳，相邻跳伤间隔为`0.178571/0.15625/0.138889/0.125/0.125`秒。权威数值先写入`tower_skill_definitions.csv`，三条路线原生`base_attack_speed`恢复为每秒一轮，再定向生成Lua。
- 每一跳独立调用现有通用塔暴击查询及科技/继承暴击链；只有触发暴击的当前跳按通用倍率结算，不得将暴击扩散到整轮或后续跳。赏金金币和爆矢同目标五次计数按有效伤害跳触发，击杀Buff仍按实际击杀触发。
- 爆矢加特林攻速Buff不突破引擎BAT，改为使轮内间隔除以`1 + bonus_pct/100`。销毁、升级迁移和显式重置必须取消所有待执行机枪跳伤；自动验证与Workshop Tools冷启动实机验证严格区分。
- 实施完成：三条路线20行原生攻击频率统一为每秒1轮；机枪五级技能由CSV配置`6/7/8/8/8`跳及`0.178571/0.15625/0.138889/0.125/0.125`秒间隔。原生弹道、声音、命中特效、伤害和原生暴击均被抑制，逐跳脚本伤害独立调用通用暴击链；赏金、爆矢计数和击杀Buff已迁移到有效跳/实际击杀边界。
- 爆矢Buff效果类型改为`machine_gun_interval_pct`，托管Buff仍保留20点值、3秒刷新、图标和特效，但不再投影原生攻击速度；轮内下一跳实时读取该值并按`interval / 1.2`调度。升级应用路线弹道后会再次按最终`skill_ids`清空机枪弹道，避免已有Modifier升级时被写回。
- 自动验证通过：`TOWER_MACHINE_GUN_VISUAL_PASS`、`MACHINE_GUN_ATTACK_INTERVAL_CONTRACT_PASS`、`TOWER_UPGRADE_RUNTIME_REFRESH_PASS`、`TOWER_ANTI_AIR_BARRAGE_PASS`、配置Build/CheckOnly、7个目标Lua 5.1语法、机枪路线CP936解析及限定`git diff --check`。两项无关旧测试未计为通过：防空PowerShell契约错误地按UTF-8读取CP936 CSV；箭塔完成测试的Lua 5.1加载器不接受既有`building_system.lua` UTF-8 BOM。
- 尚需完全停止并冷启动Workshop Tools，实测三条路线、LV1-LV5跳数/时点、逐跳暴击、赏金逐跳金币、爆矢第五跳加速与击杀刷新、目标提前死亡、升级/销毁清理，以及非机枪塔回归；自动测试不等于引擎实机验证或用户验收。

## 已完成任务（2026-08-14）：神秘塔激光Tick恢复为1秒及计算器方法沉淀

- 用户确认神秘塔普通攻击的`base_attack_speed=1`本来就是1秒间隔；LV2第7波差异来自生产激光`damage_interval=0.5`，而离线录像实验按1秒激光间隔计算。提交`f92e6c9`曾把`laser_lv01-lv05`从1秒改成0.5秒。
- 本次决定以离线录像实验的1秒模型为准：五级激光统一恢复`damage_interval=1`；基础倍率`1.0/1.2/1.4/1.6/1.8`、同目标每秒递增5%、500%封顶、目标切换重置、首次锁定立即Tick和魔能之眼150码附伤规则均不改变。
- 权威源只修改`tower_skill_definitions.csv`，再通过现有生成链同步技能Lua、Tooltip和六份中英文本地化；专项契约与Lua 5.1数学测试同步要求1秒Tick。下方此前“0.5秒激光”条目由本条取代，不得恢复为当前行为。
- LV2生产基础攻击为`1401`，离线实验面板输入为`1501`；间隔统一后仍须在比较结果时保留这100点独立输入差异，不能把它误判为Tick修复未生效。
- 实施完成：权威技能CSV、生成技能Lua、Tooltip CSV/Lua、六份中英本地化及专项测试均已同步为1秒Tick；运行时继续在伤害计算和调度两处消费`laser.damage_interval`，未新增硬编码间隔。
- 自动验证通过：`TOWER_LASER_BASE_MULTIPLIER_CONTRACT_PASS`、`TOWER_LASER_BASE_MULTIPLIER_LUA51_PASS`、`WAR3_DAMAGE_CALCULATOR_CONTRACT_PASS`（Edge 1440/390各59项）、生成哈希稳定、目标Lua 5.1语法、Python/PowerShell语法、严格UTF-8解码、CSV BOM及限定`git diff --check`。`DECISIONS.md`和`SESSION_LOG.md`中各有3个用于说明乱码检查的既有字面`U+FFFD`，Git基线数量相同，本轮未重写历史内容。
- 离线复算：按23护甲、6000生命、默认`t=0`普攻及`t=1`激光首跳，生产攻击1401与实验攻击1501都在`t=3`激光事件达到阈值，累计伤害分别约6477.226与6939.555。用户已确认问题没有了；这些数值仍作为后续复算的生产输入与实验输入对照，不把自动计算结果描述为独立的引擎实机验证。
- 用户已确认问题没有了。本任务关闭，不再等待该激光问题的Workshop Tools验收；后续类似数值复算统一参考`PROJECT_CONTEXT.md`中的“离线伤害计算器复用方法”和`DECISIONS.md`中的计算器决策。

## 当前插入任务（2026-08-13）：神秘塔升级触发particles.dll崩溃

- 用户提供的两份当前minidump均为读取空指针访问冲突，落在`particles.dll+0x19F6FF/+0x19F70F`附近；崩溃稳定发生在箭塔约1秒升级完成为神秘塔的边界。战斗数值、激光倍率和权威CSV未显示为根因，native符号栈仍不可用。
- 最小生产修复已实施：`building_upgrade_process.lua`的统一清理从`DestroyParticle(id, false)`改为`DestroyParticle(id, true)`；完成、建筑销毁取消、reset、升级回调发现实体失效及粒子控制点创建失败均清空保存ID，并将销毁和`ReleaseParticleIndex`放在独立保护调用中，确保每个已创建索引最多释放一次且销毁异常不阻断释放。
- 临时诊断默认开启且全局最多64条，日志scope为`BuildingUpgradeParticle`，记录`event/entindex/particle_id/state/detail`；正常完成的状态为`complete`，取消记录实际reason，创建失败记录`create_failed`。该日志用于下一轮A/B，确认后应移除或恢复默认关闭。
- 权威`building_construction_rules.csv`及生成`building_construction_rules.lua`未修改；专项契约从CSV解析`arrow_tower`并逐项核对`build_particle/build_start_particle/build_loop_particle`生成结果，当前升级仍使用CSV定义的`particles/items2_fx/teleport_start.vpcf`。
- 自动验证通过：`BUILDING_UPGRADE_PARTICLE_CONTRACT_PASS`、`BUILDING_UPGRADE_PROCESS_LUA51_PASS`、`BUILDING_UPGRADE_PARTICLE_LUAC51_PASS`、PowerShell语法、严格UTF-8和限定`git diff --check`；`BUILDING_LEVEL_IDENTITY_LUA51/CONTRACT_PASS`、`SIX_GAMEPLAY_FIXES_LUA51/CONTRACT_PASS`、`ARROW_TOWER_COST_LUA51/CONTRACT_PASS`回归通过。
- 两项既有批量升级测试保持失败且与本轮无关：Lua Mock缺`event_bus.request`；PowerShell契约仍要求已删除的客户端selection snapshot。本轮未修改批量服务、Panorama或旧测试迎合。
- 下一步：完全停止并冷启动Workshop Tools，不按Alt、不悬停Tooltip完成一次基础箭塔到神秘塔转职，保存`BuildingUpgradeParticle`日志并确认客户端不退出；再分别按住Alt、测试其他路线。若仍崩溃，保存新dump并对比`particles.dll+0x19F6FF`，随后按既定A/B先禁用升级传送粒子，再隔离神秘塔四个bone-merged组件和`abilityTooltips=false`。未经实机结果不能称为崩溃已修复或用户验收。

## 当前插入任务（2026-08-13）：激光基础倍率同步到生产与离线模型

- 用户要求将激光基础倍率统一为`laser_lv01-lv05=1.0/1.2/1.4/1.6/1.8`，并同步生产技能配置、Tooltip/本地化及离线War3伤害实验模型。
- 权威源为`data/csv/建筑与工人系统/防御塔/tower_skill_definitions.csv`和`data/csv/公共规则/war3_damage_calculator_mystery_experiment.csv`；生成技能Lua、Tooltip、六份本地化和单文件HTML均由现有生成链更新。魔能炮和魔能之眼继续使用`laser_lv05=1.8`，神秘路线`mystery_tower_lv01-lv05`映射及运行时激光算法不变。
- 连续命中增长、每完整秒增加`0.05`、`5.00`封顶、切换主目标重置和魔能炮层规则均保持不变；离线计算器验证样本因LV2基础倍率降低而同步为默认延迟模型约3秒击杀。
- 实现完成：新增生产激光倍率PowerShell契约和Lua 5.1数学测试；更新离线计算器契约覆盖完整五级序列及后续路线继承。`TOWER_LASER_BASE_MULTIPLIER_CONTRACT_PASS`、`TOWER_LASER_BASE_MULTIPLIER_LUA51_PASS`、`WAR3_DAMAGE_CALCULATOR_CONTRACT_PASS`（Edge 1440/390各59项）、生成Build/CheckOnly、目标Lua 5.1语法、严格UTF-8、Python/PowerShell语法及限定`git diff --check`已通过。
- 尚未Workshop Tools冷启动确认实际激光扣血、Tooltip显示和路线实机表现；自动契约、模拟测试和Lua语法检查不能替代引擎实机验证或用户验收。

## 当前插入任务（2026-08-13）：神秘之塔原版录像反推离线实验模型

- 用户已批准进入Act模式。目标是在现有单文件离线计算器中加入与生产配置完全隔离的神秘之塔、魔能炮、魔能之眼离散事件实验模型；本任务原先不得修改生产Lua、`tower_class_mystery.csv`或正式技能配置，后续用户任务已明确要求同步生产激光基础倍率，当前任务条目以顶部最新条目为准。
- 实验面板攻击力直接采用录像/工作簿最终面板值。正式路线CSV对应行均少100的内部原因尚未唯一证明，实验工具不得通过修改正式数据或运行时补偿来掩盖该差异。
- 已确认原版时间线：普通攻击与激光并行且均约每秒结算；默认`t=0`普攻、锁定后`t=1`激光首跳。当前离线实验同步使用生产要求的激光基础倍率`100%/120%/140%/160%/180%`，每次有效Tick增加`0.05`，最高`500%`；切换目标后成长重置。
- 魔能炮每次符合条件的击杀新增独立持续5秒的10%增伤层，各级上限`4/5/6/7/7`。致死事件使用新增层之前的快照，不允许新层反向增强本次伤害；同刻普通攻击与激光的先后顺序必须可配置并在事件明细中可见。
- 魔能之眼由普通攻击触发，只伤害塔与主目标线段路径内的其他单位，主目标明确排除；倍率30%，路径目标按各自护甲独立结算。路径半宽默认96仅来自旧实现近似值，属于可调实验参数，不记录为原版权威值。
- 魔能炮增伤是否传递给魔能之眼仍无唯一录像证据，必须保留显式实验开关。0.5秒激光、立即首跳和目标周围150范围AOE均属于后续改造，不得作为原版默认值。
- 已新增`data/csv/公共规则/war3_damage_calculator_mystery_experiment.csv`作为离线实验权威源，20个预设由`tools/build_war3_damage_calculator.ps1`嵌入HTML；生成器和专项契约确认该CSV不进入生产生成Lua或`config/generated/index.lua`。
- 页面保留通用计算器并新增独立神秘路线模式、录像面板预设、可配置首跳/同刻顺序、连续主目标、逐事件明细、独立层过期、路径目标CSV式输入和魔能之眼增伤传递开关。README已同步实验边界和使用口径。
- 自动验证通过：神秘LV2第7波`1501攻击/6000生命/23护甲`在默认延迟首跳模型中于3秒达到击杀阈值；激光成长/500%封顶/切换重置、真实`t=0/t=1`击杀层在`t=5/t=6`独立过期、7层上限、致死事件后加层、路径主目标排除/线段半宽/逐甲、增伤传递开关及同刻顺序均有浏览器断言。
- `WAR3_DAMAGE_CALCULATOR_CONTRACT_PASS`已通过，Edge在1440px与390px实际执行59项断言；生成Build/CheckOnly、PowerShell语法、通用规则生成Lua的Lua 5.1语法、严格UTF-8和限定`git diff --check`通过。该实验CSV仍不生成生产Lua；生产激光倍率同步见顶部最新任务条目。
- 当前状态：离线实验工具实现和自动验证完成，等待用户双击`tools/war3_damage_calculator/index.html`选择“神秘路线录像实验”确认交互与模型是否便于继续对照录像。自动测试不等于原版算法已被唯一证明，也不等于用户验收。

## 当前插入任务（2026-08-13）：计算器改用 Survival 当前战斗算法

- 用户放弃查找“苟发育”外部算法，明确要求计算器以本项目当前生产公式为准。旧版经典TFT `0.06/0.94`护甲和“前N次固定暴击”口径已被本条覆盖，不得恢复。
- 当前面板物理攻击力作为普通攻击输入；项目现有英雄CSV `damage_multiplier=1`，装备、研究、成长和英雄专属攻击乘区已体现在面板快照，计算器不得重复乘算。
- 暴击与生产`modifier_weapon_stat_projection`一致：每个attack record按`critical_chance_pct`独立随机判定，暴击伤害使用`critical_damage_pct`。离线工具按`1 + 暴击率 × (暴击倍率 - 1)`累计每击期望伤害，并显示期望暴击/非暴击次数；结果是期望伤害达标时间，不冒充某局实战或随机停止时间的严格数学期望。
- 固定减甲先改变怪物War3显示护甲，百分比物理护甲无视再缩放剩余正护甲；零/负护甲不受百分比无视。正护甲按项目怪物目标曲线`1/(1+0.02×War3护甲)`，零/负护甲先按`1/3`投影到运行时护甲，再沿当前Dota曲线结算。
- 保留工具既有用途：动态多个攻击单位、各自每秒攻击次数、0秒首击、共享当前攻击力、命中后固定/基础百分比成长和同刻批量结算。最终伤害科技、Boss减伤、光环、技能、闪避、格挡、回血、前摇和弹道不在普通攻击基础估算范围。
- 权威常量位于`data/csv/公共规则/war3_damage_calculator_rules.csv`，生成脚本同步单文件HTML、生成Lua和配置索引；禁止直接手改生成常量。
- 实施完成：页面字段、核心公式、README、生成器和专项契约均已切换到当前项目算法。Edge在1440px与390px视口实际执行31项页面断言通过；生成Build/CheckOnly、PowerShell语法、生成Lua语法、生产怪物护甲及研究减甲Lua 5.1行为回归、10个任务文件严格UTF-8和限定diff检查通过。
- 既有未跟踪回归脚本的两个启动问题保持不变：怪物护甲PowerShell契约用单行字符串匹配生产中的等价多行调用，研究减甲PowerShell契约未设置项目`LUA_PATH`。前者对应Lua行为测试通过；后者按项目历史约定补充进程级`LUA_PATH`后，state/trigger/generated-levels三个Lua 5.1测试全部通过。本任务未修改这些既有测试迎合文本或环境问题。
- 当前状态：代码与自动验证完成，等待用户直接双击`tools/war3_damage_calculator/index.html`确认字段和使用体验；自动浏览器测试不等于Workshop Tools实机验证或用户验收。

## 当前任务（2026-08-14）：怪物物理伤害改用项目 War3 护甲公式

- 用户实机确认无任何科技时，`801`攻击命中`117` War3护甲怪物扣血`262`；该结果与`34.322`运行时护甲按引擎`0.06`曲线结算一致，证明此前现代非线性映射并未得到目标`240`。
- 用户批准怪物物理伤害不再依赖Dota原生护甲曲线或护甲映射。所有命中明确项目怪物的物理伤害统一按`X / (1 + 0.02 * max(0, A))`结算，`A`为CSV派生的当前有效War3护甲；负护甲保留状态/UI值，但伤害按0护甲处理，不提供额外增伤。
- 实施边界：保持`DAMAGE_TYPE_PHYSICAL`，在唯一Damage Filter内结算并追加忽略原生物理护甲flag；不递归`ApplyDamage`、不创建第二个Filter。普通攻击和项目物理技能使用同一规则，魔法/纯粹及非怪物目标不变。百分比穿甲先在War3域缩放有效正护甲。
- 当前状态：生产实现与自动验证完成。怪物生成边界引擎护甲归零；Damage Filter统一处理物理攻击/技能、穿甲和忽略原生护甲flag；固定减甲与毒云百分比减甲维护有效War3护甲；选中单位UI和诊断使用同一权威值。
- 自动验证通过：`CUSTOM_MONSTER_ARMOR_PASS`、`CUSTOM_MONSTER_POISON_ARMOR_PASS`、`ARMOR_REDUCTION_MAPPING_PASS`、`ARMOR_MAPPING_CONTRACT_PASS`、`COMBAT_STAT_PROJECTION_PASS`、`DAMAGE_TRANSACTION_ARMOR_IGNORE_PASS`、目标Lua 5.1语法、配置全量生成与`CheckOnly`、目标严格UTF-8及限定`git diff --check`。数学基准为`117`护甲下`801 -> 239.82`、`1401 -> 419.46`。
- 尚需Workshop Tools完全停止当前会话后冷启动实测：确认`801`最终扣血约`240`，`MONSTER_PHYSICAL_DAMAGE_FILTER.filtered_damage`等于最终扣血；再抽样30%穿甲、物理技能、科技/毒云减甲、负护甲及非怪物隔离。自动测试不等于引擎实机验证。

## 当前任务（2026-08-14）：怪物物理伤害改用项目 War3 护甲公式

- 用户实机确认无任何科技时，`801`攻击命中`117` War3护甲怪物扣血`262`；该结果与`34.322`运行时护甲按引擎`0.06`曲线结算一致，证明此前现代非线性映射并未得到目标`240`。
- 用户批准怪物物理伤害不再依赖Dota原生护甲曲线或护甲映射。所有命中明确项目怪物的物理伤害统一按`X / (1 + 0.02 * max(0, A))`结算，`A`为CSV派生的当前有效War3护甲；负护甲保留状态/UI值，但伤害按0护甲处理，不提供额外增伤。
- 实施边界：保持`DAMAGE_TYPE_PHYSICAL`，在唯一Damage Filter内结算并追加忽略原生物理护甲flag；不递归`ApplyDamage`、不创建第二个Filter。普通攻击和项目物理技能使用同一规则，魔法/纯粹及非怪物目标不变。百分比穿甲先在War3域缩放有效正护甲。
- 当前状态：生产实现与自动验证完成。怪物生成边界引擎护甲归零；Damage Filter统一处理物理攻击/技能、穿甲和忽略原生护甲flag；固定减甲与毒云百分比减甲维护有效War3护甲；选中单位UI和诊断使用同一权威值。
- 自动验证通过：`CUSTOM_MONSTER_ARMOR_PASS`、`CUSTOM_MONSTER_POISON_ARMOR_PASS`、`ARMOR_REDUCTION_MAPPING_PASS`、`ARMOR_MAPPING_CONTRACT_PASS`、`COMBAT_STAT_PROJECTION_PASS`、`DAMAGE_TRANSACTION_ARMOR_IGNORE_PASS`、目标Lua 5.1语法、配置全量生成与`CheckOnly`、目标严格UTF-8及限定`git diff --check`。数学基准为`117`护甲下`801 -> 239.82`、`1401 -> 419.46`。
- 尚需Workshop Tools完全停止当前会话后冷启动实测：确认`801`最终扣血约`240`，`MONSTER_PHYSICAL_DAMAGE_FILTER.filtered_damage`等于最终扣血；再抽样30%穿甲、物理技能、科技/毒云减甲、负护甲及非怪物隔离。自动测试不等于引擎实机验证。

## 当前插入任务（2026-08-12）：原生技能栏项目快捷键标签

- 目标：保留Valve原生技能栏与输入链，由项目在每个当前可见Ability面板上显示权威快捷键标签。普通技能按项目可见顺序使用`Q/W/E/R/T/Y/U`；工具技能按Ability身份使用`D/F/F2`，现有工具图标顺序`D -> F2 -> F`不变。
- 最新Workshop Tools截图推翻了“引擎槽`N`必然对应原生面板`AbilityN`”的旧结论：Builder使用`AbilityLayout "12"`，技能栏左侧存在额外原生组件；初始业务技能仍位于引擎槽`0`，Blink仍位于槽`5`，但实际两个可见按钮可对应`Ability1/Ability2`，旧实现因此留下Valve原生`W/E`。本轮只修正显示目标解析，不修改CSV、生成Lua、Ability KV、引擎槽、输入处理或HUD架构。
- 生产实现完成：原工具技能覆盖层已泛化为`SurvivalAbilityHotkey`。每次重贴先清空当前标签与旧`SurvivalUtilityHotkey`；当前映射面板的原生`HotkeyContainer`仅设`opacity=0`并关闭自身及子级命中，不使用`collapse`，不影响按钮布局、图标、冷却、等级、充能或升级按钮。压制前保存Valve原有`opacity/hittest/hittestchildren`，清理、无有效选中单位或面板复用时恢复原值。
- 显示目标已与引擎槽解耦：只收集当前可见、尺寸有效且不属于旧HUD的原生`AbilityN`按钮锚点，按窗口几何从左到右排序，再与项目业务可见技能顺序逐一配对；数量不一致时原子失败并重试。标签与`DOTADisabled`共用同一配对结果，不再使用`entry.slot -> AbilityN`或压缩下标定位。
- 刷新签名同时包含`selected unit + engine slot + ability entindex + ability name`和本轮原生面板顺序；选择事件会强制重贴，Ability runtime事件与既有0.25秒HUD生命周期同时检查技能替换、面板顺序变化、标签完整性和原生`HotkeyContainer`压制状态，原1秒刷新保留为晚创建兜底。`ui_bootstrap.js`继续保持`abilities: false`。
- 自动验证完成：Resource Compiler输出`OK: 1 compiled, 0 failed, 0 skipped`，产物84450字节并包含几何映射、原生快捷键压制/恢复和完整性检查符号；`COMBAT_STATS_UTILITY_HOTKEY_CONTRACT_PASS`覆盖Builder CSV/生成Lua、初始`Ability1/Ability2`错位场景、槽洞、英雄`D/F2/F`映射及压制/恢复行为，`ALT_HERO_ABILITY_ORIGIN_DEV_CONTRACT_OK`、PowerShell解析、相关2个Lua的Luac 5.1语法、严格UTF-8、编译产物符号及Game/Content限定`git diff --check`通过。未修改CSV或生成Lua。
- 剩余：Workshop Tools完全冷启动，确认疑似Valve原生`W/E/D/F/R`消失后，逐个记录仅剩`SurvivalAbilityHotkey`显示的字母；同时验证Builder/正式英雄/建筑切换、技能替换和重排、Ability面板复用，以及鼠标和`Q/W/E/R/T/Y/U/D/F/F2`输入仍正常。自动契约与资源编译不是实机视觉验收。

## 已完成插入任务（2026-08-12）：主城/城墙等级名称与城墙原始护甲Tooltip

- 目标：主城和城墙的单位名称随当前等级使用权威`building_levels.csv.display_name`；城墙升级Tooltip使用相邻等级CSV原始`war3_armor`差值，例如`10 -> 15 (+5)`。
- 实现完成：`buildings_config.lua`在保留Dota换算后`armor`作为引擎运行值的同时透传`war3_armor`；`building_system.lua`在创建、热恢复、状态发布和变更同步时解析等级名称；`building_upgrade_system.lua`在城墙/主城升级提交与发布时同步等级名称。
- 名称重算严格限定`wall/main_city`。箭塔继续保留路线/转职名称，其他建筑继续接受原有`payload.display_name`，没有扩大名称行为范围。
- `ability_runtime_builder.lua`仅对城墙使用`war3_armor`计算Tooltip差值；主城和其他建筑仍沿用运行时Dota护甲差值。权威CSV为CP936/GBK，本轮未修改CSV或`config/generated`。
- 自动验证通过：`BUILDING_LEVEL_IDENTITY_LUA51_PASS`、`BUILDING_LEVEL_IDENTITY_CONTRACT_PASS`、`BUILDING_UPGRADE_PROCESS_LUA51_PASS`、`SIX_GAMEPLAY_FIXES_LUA51_PASS/CONTRACT_PASS`、5个目标Lua的Lua 5.1语法、配置`CheckOnly`、`building_levels.lua`定向生成逐字节一致、源CSV CP936解码与乱码标记检查、6个任务文件严格UTF-8及限定`git diff --check`。
- 无关既有失败保持不变：两份批量升级旧测试分别缺少当前`event_bus.request` Mock并要求已删除的客户端selection snapshot；旧城墙健康测试仍调用已删除的`apply_preserved_ratio`；单位模型旧契约仍缺伐木工模型CSV项。未修改这些无关测试或数据迎合。
- 用户于2026-08-12明确确认问题圆满完成，本任务已验收并关闭；后续会话不得再将其恢复为活跃任务。

## 已完成插入任务（2026-08-12）：combat_stats无效快捷键刷新调用

- 用户实机日志确认`combat_stats.js:1057`在无有效选中单位分支调用不存在的`refreshOfficialReturnHomeHotkey([])`，随后抛出ReferenceError并跳过该轮脚本。当前Content源码和Game编译产物均包含旧符号，不能按历史文档中的“已修复”结论忽略。
- 最小修复只把该分支改为项目现有且正常分支已使用的`refreshOfficialUtilityHotkeys([])`，保留后续1秒调度、技能运行状态和快捷键映射逻辑。定向重编译`combat_stats.vjs_c`，不修改CSV、小地图、粒子或其他Panorama文件。
- 生产修改与自动验证完成：源码和编译产物均不再包含`refreshOfficialReturnHomeHotkey`且保留`refreshOfficialUtilityHotkeys`；专项契约输出`COMBAT_STATS_UTILITY_HOTKEY_CONTRACT_PASS`，Resource Compiler输出`OK: 1 compiled, 0 failed, 0 skipped`。目标源码、测试及本轮文档严格UTF-8通过，Game/Content限定`git diff --check`通过。
- 用户已在Workshop Tools实机确认修复后不再出现`refreshOfficialReturnHomeHotkey is not defined`。该ReferenceError任务已通过用户验收并关闭；专项契约继续作为旧符号回归门禁。

## 已完成插入任务（2026-08-12）：热重载 Modifier 注册与小地图显式纹理

- 历史失败表现为冷启动持续输出`file mod 'dota_addons/survival' is invalid`，小地图花屏且Panorama按需编译受阻。根因已确定为Game/Content物理目录`Survival`与编译资源`dota_addons/survival`的file-mod大小写身份冲突，不是TGA文件头或单独VTEX扩展名损坏。
- Game/Content物理目录现已统一为全小写`dota_addons/survival`。用户Workshop Tools实机确认小地图恢复正常，该问题已验收关闭；后续不得把目录改回大写`Survival`，也不得创建大小写并存的第二个addon身份。
- 旧`tools_asset_info.bin`备份仍位于`C:\Users\UserComputer\AppData\Local\Temp\survival_file_mod_backup_20260812_151927`。本次JS修复不修改或重编译现有小地图VTEX/VMAT、HUD依赖链及粒子资源。
- 用户实机日志显示 Mango Tree 模型缺少 `attach_hitloc`，以及召唤猴王后多个英雄核心 Modifier 被引擎判定为 unknown；同时存在 `modifier_single_health_bar` 重复告警。
- 权威资源树模型继续来自 `data/csv/资源系统/world_visual_definitions.csv`，本任务不擅自更换模型或修改树木数值。
- 审计确认 `modifier_single_health_bar` 只剩兼容标记，已不负责自定义血条，可停用自动附加链；其余攻击上限、CSV射程/生命、装备、暴击和科技 Modifier 仍在生产使用，不得注释。
- 最小修复：完整 Modifier 注册只保留在地图启动边界；英雄替换前仅验证Lua类并对缺类模块定向恢复，失败关闭；停用旧血条标记服务；项目粒子仅在模型确有 attachment 时绑定，否则回退世界坐标；增加专项契约并执行 Lua 5.1、编码和限定差异验证。
- 实施完成：`addon_game_mode.lua`不再初始化废弃`unit_health_bar_service`，英雄替换不再附加`modifier_single_health_bar`。启动入口现在为每次脚本加载分配递增generation，`modifier_registry.register(generation)`在每代完整执行一次`LinkLuaModifier()`、同代重复调用去重；普通`addhero`继续只调用`ensure_available()`，正常路径零次链接。缺类时按模块路径清除`package.loaded`并重载一次，随后由注册器重新链接该模块声明的全部Modifier；恢复失败在`hero_anchor_service.begin_replacement()`前返回`modifier_registry_unavailable`。
- 英雄替换的CSV基础属性应用现在受`pcall`保护；提交前按英雄CSV检查攻击上限、攻击射程、基础生命及条件性法力Modifier是否实际存在。添加异常或实体缺失返回`hero_modifier_apply_failed`，不写召唤成功状态、不发布`HERO_SUMMONED`。装备效果、攻击投影和攻击追踪仍由既有`hero_combat_stat_service`在同步`HERO_SUMMONED`链创建，科技Modifier继续按条件性效果运行，未复制第二套服务。
- 猴王四件Cult of the Demon Trickster饰品继续使用原模型、`material_group="1"`、四个环境粒子、Owner和`FollowEntity`骨骼跟随；`hero_cosmetic_service`只移除了`prop_dynamic`创建参数中的`DefaultAnim="idle"`，避免模型不存在该序列时产生四次告警。
- Mango Tree权威CSV及生成Lua继续保持`models/props_tree/mango_tree.vmdl`、缩放3。自定义魔法塔粒子会先用`ScriptLookupAttachment`确认`attach_attack1/attach_hitloc`存在，缺失时改用实体世界坐标，不再强绑不存在的attachment。
- 小地图Content源`materials/overviews/template_map.vtex`保持Valve overview schema：同目录相对输入`./template_map.tga`、声明`DXT1`及官方clear color/dimension/clamp/LOD字段；`template_map.vmat`继续引用显式VTEX。Game/Content全小写后，用户已实机确认该资源链正常显示。
- 小地图契约继续锁定Game/Content目录精确小写、源VTEX相对路径和DXT1声明、编译产物file-mod大小写、`resourceinfo` ManifestResource以及资产索引不得含大写身份。当前额外复跑仍失败于既有`template_map_tga_d9088edf.vtex_c`残留，未为本次JS任务删除或修改该资源；这项静态残留不否定用户已确认的小地图实机显示正常。`.cline/local-toolchain.json`使用实际E盘工作区、Python 3.14.3、Lua/Luac 5.1.5和PowerShell 7.6.4路径。
- Mango Tree继续保持`models/props_tree/mango_tree.vmdl`、缩放3、现有数值和原生攻击链。用户已决定接受原生攻击特效对该资产缺少`attach_hitloc`的无功能影响引擎告警；项目自定义魔法塔粒子的attachment回退仍保留。16 MiB Lua内存信息仅记为高水位提示，当前没有泄漏证据。
- 小地图大小写任务已关闭。Modifier与猴王饰品仍按原实机清单单独验证；Source 2注册与资源管理器时序只能由引擎验证，自动测试不能称为实机验收。
## 当前实施任务（2026-08-13）：炙热巨箭公式与普通攻击完全抑制

- 用户已批准实施并确认穿透编号从`n=0`开始：第n个路径命中目标的技能伤害基数为`Attack × 3.24 × 0.8^n`，再按目标30%穿甲后的War3物理护甲曲线`1 / (1 + 0.02 × A × 0.7)`结算。
- `3.24 = 1.8 × 1.8`是完整技能基础倍率；炙热巨箭不再额外区分地面/飞行目标，也不再使用100%/80%/60%/40%/20%/0%的线性衰减。
- 炙热巨箭阶段保留普通攻击动作作为技能发射节拍，但普通攻击伤害必须为0，普通攻击弹道、普通攻击音效和普通命中特效必须不可见；唯一输出来自现有Wave of Terror线性穿透技能投射物。
- 实施边界：权威数值先改CSV并生成Lua；巨箭改在攻击开始事件发射并快照攻击力；30%穿甲按单笔技能伤害事务处理，不给目标留下可见或持续减甲状态，也不影响其他伤害。
- 当前状态：实施与自动验证完成。权威CSV及生成Lua已更新；巨箭在攻击开始时快照攻击力/方向并按`3.24 × 0.8^n`逐个唯一目标结算；30%穿甲从`piercing_ballista_lv05` CSV字段进入单笔伤害事务；普通攻击伤害、弹道、音效、暴击和命中附加逻辑已抑制；空弹道在创建、升级与迁移恢复时可主动清除旧资产。
- 自动验证：专项公式/视觉投射物/穿甲数学/事务隔离/配置/技能链测试通过；相关多重伤害、几何、激光和机枪回归通过；12个相关Lua文件通过Lua 5.1语法检查（两个既有BOM文件以去BOM临时副本检查）；配置生成`CheckOnly`、UTF-8校验及`git diff --check`通过。
- 已知非本任务阻塞：`test_tower_multi_visual_config.lua`通过炙热巨箭相关断言后，在既有死亡塔资源包`tower_death_templar_assassin`完整性断言失败；`tools/test_tower_skill_sound_config.py`因当前工作区其他技能族缺声音配置失败。未修改无关资源来规避这两项失败。
- 待Workshop Tools实机验收：确认普通攻击动作仍按节拍播放但没有普通弹道/声音/命中特效；Wave of Terror巨箭可见并继续穿透；按测试护甲样本核对实际扣血；确认升级到炙热阶段后旧霜箭弹道消失。自动测试不能称为引擎实机验证。

## 当前实施任务（2026-08-13）：炙热巨箭单发与激光首击判定、魔能之眼建模

- 用户已批准实施：多重路线升级为炙热巨箭塔后不再执行多重射击；多重塔与穿透弩炮阶段保持现有多重攻击，炙热巨箭阶段继续保留满级穿透弩炮护甲忽略与炙热巨箭路径穿透。
- 激光在锁定新目标的攻击开始事件中立即执行首个伤害Tick，使激光判定和魔能之眼150码AOE先于基础攻击命中；同一目标后续普通攻击不得重复首Tick，切换目标后重置并立即结算。该历史实现的后续0.5秒Tick已被本文件顶部最新任务恢复为1秒，同目标每完整1秒增长5%，最高500%。
- 魔能之眼LV1-LV10由Phoenix建模改为死亡先知主体与“光明尸衣之魂”（Soul of the Brightshroud，Bundle 21346）五件可穿戴组件；套装恶灵属于ability_ultimate替换模型，不作为塔身静态组件。激光视觉继续使用已验证的Tinker Laser。
- 实现与自动验证完成：权威CSV及生成Lua已同步；`BURNING_GREAT_ARROW_SKILL_CHAIN_PASS`、`TOWER_LASER_ATTACK_START_PASS`、`TOWER_LASER_DAMAGE_PASS`、`TOWER_ARCANE_EYE_PASS`、`ASSET_BUNDLE_CONFIG_PASS`、`MYSTERY_TOWER_CONTRACT_PASS`、Lua 5.1语法、配置生成/`CheckOnly`、目标UTF-8、五件光明尸衣VPK路径、有效生产文件无Phoenix残留及限定`git diff --check`通过。既有综合视觉测试仍被任务前死亡路线Bundle缺失阻断，本轮独立专项已覆盖多重技能链；最终仍需Workshop Tools完全冷启动确认实际判定顺序、150码AOE、模型五组件与Tinker Laser挂点。

## 当前实施任务（2026-08-13）：防空弹幕周期与防空火炮眩晕概率

- 用户已批准实施：防空路线只攻击飞行单位并保持每秒启动一轮完整弹幕；防空炮LV1-LV5弹数为4/5/6/7/7，相邻发射间隔为0.333/0.25/0.2/0.167/0.167秒，首发不额外延迟。
- 防空火炮每枚真实普通攻击命中飞行单位时独立判定眩晕，LV1-LV5概率改为2%/3%/4%/5%/5%；现有3秒持续时间、目标死亡后停止剩余飞弹且不转射的规则保持不变。第三阶段继续继承满级7发、0.167秒和5%眩晕。
- 权威数值先写入`data/csv/`再生成Lua；同步Tooltip与中英文本地化。自动验证需覆盖20级每秒一轮、五级弹数/间隔、首发时点、目标死亡取消、只对飞行单位以及五级眩晕概率。
- 引擎追踪弹道的实际命中时刻仍受距离和目标移动影响；自动测试验证脚本发射调度，最终需Workshop Tools冷启动测量实际命中节奏，不能将自动测试描述为实机验证。
- 实现完成：`tower_skill_definitions.csv`新增独立`barrage_interval`字段，五级配置为0.333/0.25/0.2/0.167/0.167秒；运行时按首发后的绝对偏移并行调度每枚后续真实普通攻击，7发尾弹1.002秒不会阻塞下一轮，销毁、迁移和显式重置会取消全部待执行飞弹。
- 防空火炮五级概率已改为2%/3%/4%/5%/5%，每枚真实命中继续独立判定并仅对飞行单位施加3秒眩晕；第三阶段继承满级配置。Tooltip CSV/Lua及六份中英本地化已同步。
- 自动验证通过：`ANTI_AIR_TOWER_CONTRACT_PASS`、`TOWER_ANTI_AIR_BARRAGE_PASS`、目标Lua 5.1语法、85项CSV生成、86个生成Lua UTF-8检查、目标生成文件二次哈希稳定、配置`CheckOnly`、防空本地化目标token三镜像一致、严格UTF-8/BOM及限定`git diff --check`。尚未Workshop Tools实机验收。

## 已被后续修正取代（2026-08-13）：神秘路线攻击间隔与魔能之眼范围触发

- 历史实现曾让神秘路线普通攻击保持1秒间隔，并把`laser_lv01-lv05`改为每0.5秒结算一次；该激光间隔已被本文件顶部最新任务恢复为1秒。
- 魔能之眼移除普通攻击命中时对塔与目标之间路径单位造成伤害的旧行为；改为每次激光伤害结算时，以激光主目标为圆心，使150码内其他敌方单位承受本次激光主目标伤害的30%。主目标不得重复承受魔能之眼伤害。
- 权威数值必须先写入`data/csv/`再生成Lua；同步Tooltip与中英文本地化。当前自动验证须覆盖全路线1秒普攻、五级激光1秒Tick、每Tick递增5%、150码圆形查询、排除主目标、30%伤害以及未学习技能不触发。
- 自动测试不能称为Workshop Tools实机验证；最终仍需冷启动确认普通攻击与激光并行节奏、连续锁定递增、切换目标重置及魔能之眼实际范围扣血。
- 当前行为：神秘路线20级继续保持`base_attack_speed=1`；五级激光由顶部最新任务统一恢复为每1秒结算，倍率每Tick增加5%且仍封顶500%。激光每次结算发布权威伤害快照；魔能之眼仅响应该事件，以主目标为圆心查询150码，排除主目标后对其他敌人提交30%物理技能伤害，致死Tick仍会在目标最终位置触发。
- CSV、生成Lua、Tooltip及六份中英文本地化已同步。自动验证通过：`MYSTERY_TOWER_CONTRACT_PASS`、`TOWER_LASER_DAMAGE_PASS`、`TOWER_ARCANE_EYE_PASS`、死亡塔与路径几何相关回归、目标Lua 5.1语法、85项CSV生成日志、86个生成Lua二次哈希稳定、严格UTF-8、本地化一致性及限定`git diff --check`。仓库当前不存在历史文档提及的Phoenix专项脚本，因此该项未能重跑；本轮未修改激光视觉CSV。
- 尚未Workshop Tools实机验收：需完全冷启动确认普通攻击与激光后续Tick均为1秒一次、锁定同目标每Tick增长5%，并用不同护甲的密集目标确认150码内其他单位独立承受本次激光30%的物理伤害。

## 当前实施任务（2026-08-13）：死亡路线攻击间隔与死神榴弹炮单体追加暴击

- 用户已批准实施：死亡路线全部20级基础攻击间隔统一为0.8秒，对应CSV `base_attack_speed=1.25`次/秒。
- 死神榴弹炮移除原暴击后300范围200%伤害；改为每次普通攻击暴击命中时独立进行10%判定，成功后仅对原目标追加一次与本次实际暴击伤害完全相同的物理伤害。
- 追加伤害复用`TOWER_ATTACK_LANDED`的权威暴击伤害快照；5倍暴击追加5倍，碎骨重炮10倍暴击追加10倍。追加伤害走技能伤害请求，不生成第二次普通攻击、不重新暴击、不递归触发死神榴弹炮。
- 权威数值必须先写入`data/csv/`再生成Lua；同步Tooltip与中英文本地化。自动验证需覆盖20级0.8秒、10%成功/失败、仅原目标、实际暴击伤害快照、未学习技能和无AOE查询。
- 实现完成：死亡路线20级CSV与生成Lua的`base_attack_speed`均为1.25，对应基础攻击间隔0.8秒。死神榴弹炮仅在暴击命中后进行10%判定，成功时对原目标追加等于该次实际暴击伤害快照的物理技能伤害；已移除范围查询和200%范围伤害。
- Tooltip CSV、生成Lua及中英文六份本地化已同步。专项验证通过：`DEATH_TOWER_BALANCE_CONTRACT_PASS`、`TOWER_DEATH_GRENADE_PASS`、死亡塔动画/选择/Templar视觉回归、目标Lua 5.1语法、生成配置结构化断言、二次生成哈希稳定、严格UTF-8/单BOM及限定`git diff --check`。
- 尚未Workshop Tools实机验收：需完全冷启动确认死亡路线各阶段实际攻击间隔为0.8秒，并通过多次暴击观察死神榴弹炮仅约10%触发、只追加原目标等额暴击伤害且不再造成AOE。自动测试不能称为实机验证。

## 当前实施任务（2026-08-13）：多重塔伤害、攻击间隔与炙热巨箭递减穿透

- 用户已批准实施：多重路线全部阶段攻击间隔统一为1.07秒；多重攻击基础伤害提高5%，对地面单位再乘1.8，最终为189%攻击力物理伤害；目标数为LV1-LV5依次4/5/6/7/7。
- 炙热巨箭继续使用现有原生线性穿透投射物，按命中顺序以每穿透一个目标递减20个百分点，基础倍率依次为100%/80%/60%/40%/20%/0%；对地面单位将当前层倍率再乘1.8。
- 穿透弩炮现有15/20/25/30/30%无视护甲配置与运行时Buff链保持不变。
- 权威数值必须先写入`data/csv/`再生成Lua；同步Tooltip与本地化。自动验证需覆盖1.07秒全路线、4/5/6/7/7目标、空中/地面倍率、巨箭逐层递减和穿透弩炮回归。
- 当前状态：实现与自动验证已完成；专项配置、空地倍率、巨箭六层递减/去重、Lua 5.1语法、配置生成/CheckOnly、本地化、UTF-8和限定diff检查通过。仍需完全停止当前Dota测试会话并冷启动Workshop Tools实机验收攻击间隔、实际扣血、投射物命中顺序和穿透弩炮减甲。

## 当前实施任务（2026-08-11）：玩家级塔上限、零消耗七塔合一、多终极塔迁移与城墙失败

- 用户已在 Plan 阶段确认并切换 Act：每玩家最多7座未转职基础箭塔；每玩家每条转职路线最多5座，并使用玩家级预占阻止并发第6座；转职完成释放基础塔名额，死亡/取消释放计数或预占。
- 七塔合一要求同一玩家七条路线各有一座满级且从未参与过合成的塔；材料塔不销毁、不降级，但成功后永久标记为已参与。每玩家最多5座终极塔，合成资格和技能状态随候选塔及终极塔数量动态刷新。
- 齐天大圣R迁移该玩家全部终极塔并保留相对位置；任一目标footprint非法时整组拒绝，不允许部分移动。
- 失败条件改为任意已完工`wall`被摧毁时以一次性全局闩锁判定全队失败；施工中城墙不触发。移除已完工`main_city`死亡直接失败。
- 配置数值必须先写`data/csv/`再生成；不得直接手改生成Lua。需同步Runtime UI、Ability状态和本地化，并增加玩家隔离、上下限、并发预占、五组合成、材料一次性、多塔原子迁移及城墙失败专项测试。
- 实现完成：建筑数量、路线计数与并发预占统一使用`player_id`；基础箭塔仍读取CSV上限7，路线读取全局CSV上限5。达到路线5座时该玩家所有满级基础塔动态移除对应转职Ability，跌回4座后恢复，服务端仍原子拒绝第6座。
- 合成完成：CSV新增每玩家终极塔上限5并生成Lua；七路线各稳定选择一座同玩家满级未参与塔，创建终极塔后原子永久标记七座材料，材料不销毁、不降级、不释放人口。失败删除新终极塔/代理且不标记材料；已参与塔不再获得合成Ability。
- 多终极塔完成：融合服务保存玩家终极塔集合；齐天大圣R整组保留相对位置迁移。迁移前完成区域、边界、地形、树木、其他单位、Grid占用和组内footprint重叠校验，任一失败时零移动；只忽略同组终极塔/代理和当前锚点。
- 失败条件完成：已完工`wall`死亡经全局一次性闩锁设置坏人方胜利；施工中城墙和已完工`main_city`死亡均不直接失败。施工失败不会提前消耗城墙整局一次性建造状态。
- UI与本地化完成：Runtime发布玩家级路线计数、七路线未参与候选数、终极塔当前数量/上限和材料不消耗规则；中英文六份Ability本地化镜像已同步。
- 自动验证通过：`PLAYER_TOWER_FUSION_RULES_LUA51_PASS`、`PLAYER_TOWER_FUSION_CONTRACT_PASS`、目标Lua 5.1语法（`building_system.lua`按既有BOM去除后检查）、`addon_game_mode.lua`语法、融合CSV/生成Lua逐字节一致、严格UTF-8/本地化BOM及限定`git diff --check`。覆盖玩家隔离、7/8基础塔、4/5/6路线塔、并发预占、五轮合成、材料一次性、终极塔上限回收、多塔原子迁移和城墙失败闩锁。
- 尚未Workshop Tools实机验收：需完全冷启动，双玩家分别验证数量隔离/Ability动态恢复，连续五轮合成的实体与攻击流，齐天大圣R多塔往返/非法落点，以及施工中城墙、主城和已完工城墙三类死亡结果。自动测试不能称为实机验证。
- 恢复冲突：此前文件顶部仍记录第7塔路线任务；本轮以用户当前批准的插入任务为最高优先级，旧记录保留为历史上下文但不作为当前实施目标。

## 当前实施任务（2026-08-12）：凤凰终级激光视觉修复与冰塔技能调整

- 2026-08-12第二次实机反馈：Phoenix Sun Ray方案仍有问题，用户要求彻底停用凤凰激光资源，Phoenix直接沿用已成功的普通激光塔Tinker Laser；寒冰尖塔现有冰锥只有落地爆炸，需要补充清晰的空中下落过程。
- 用户实机确认防空塔LV1-LV10天怒至宝第二分支及其余阶段内容全部通过；当前仅剩终级Phoenix红色缺材质和Solar Forge Sun Ray表现错误。
- Phoenix保留现有塔模型组件，但彻底停用Solar Forge Sun Ray；专用配置与普通五级激光一致，使用Tinker Laser和segmented短段重播，Gameplay数值不变。
- 冰霜攻击LV1-LV5保留主目标原生普通攻击全额伤害，半径内其他目标只承受该次攻击50%的物理范围伤害；范围内所有目标继续减速25%持续2秒。
- 寒冰尖塔LV1-LV5保留10/12/14/16/16%触发率、每波触发时攻击力50%的物理伤害和25%减速，统一为300码、每1秒一波、共4波；每波先从落点上方700单位生成Frost Avalanche冰片并在0.35秒内下落，落地后播放爆炸并结算伤害。
- 权威数值与资源配置继续来自`data/csv/`；自动验证不等于Workshop Tools实机验收，最终需冷启动确认Phoenix使用Tinker Laser表现正常，以及寒冰尖塔落冰观感。
- 实现完成：Phoenix专用激光回退为`particles/units/heroes/hero_tinker/tinker_laser.vpcf`和`segmented`模式，起止高度、刷新和保留时长均与`laser_lv05:default`一致；不再进入Sun Ray continuous分支。
- 冰霜攻击五级均从CSV读取`damage_multiplier=0.5`，只对非主目标提交范围物理伤害，主目标不重复结算；寒冰尖塔五级统一300码、4秒、1秒间隔、每波50%攻击力，去除持续雪场。下落段从CSV读取`maiden_freezing_field_snow_arcana1_shard.vpcf`，落地段继续读取Frost Avalanche explosion。
- 自动验证通过：本轮两个CSV定向生成、`FROST_TOWER_ROUTE_PASS`（含4个高空冰片、逐步下落、落地后4波伤害与爆炸）、`PHOENIX_LASER_CONTRACT_PASS`、`ASSET_BUNDLE_CONFIG_PASS`、下落冰片VPK路径、相关Lua 5.1语法及限定`git diff --check`。尚需Workshop Tools冷启动确认下落冰片尺寸、朝向和可见度。

## 当前实施任务（2026-08-12）：闪电塔双倍攻速伤害实验与攻击动画同步

- 用户要求为伤害猜想进行临时实验：闪电路线全部20级的基础攻速由每秒1次提高为每秒2次。
- 每次持有 `lightning_strike_` 的塔开始普通攻击时，主动播放2倍速 `ACT_DOTA_ATTACK`，使闪电链释放节奏与攻击频率同步；不改变0.1秒连锁跳跃间隔、伤害倍率和触发链。
- 权威数值必须来自 `data/csv/建筑与工人系统/防御塔/tower_class_lightning.csv` 并重新生成 Lua。该CSV当前存在本轮之前的乱码修改，用户已明确选择恢复正常文本后实施全部20级改动。
- 自动验收应覆盖20行CSV/生成Lua攻速均为2、闪电攻击动画倍率为2、非闪电塔不进入该动画分支、现有闪电伤害与触发链专项测试、Lua 5.1语法和限定差异检查；Workshop Tools负责最终视觉节奏验收。
- 实现完成：闪电路线CSV已从错误的GB18030工作树编码无损转换回UTF-8 BOM，20行中文与资源字段完整保留；全部等级基础攻速设为2并已重新生成配置。持有`lightning_strike_`的塔在攻击开始时调用`StartGestureWithPlaybackRate(ACT_DOTA_ATTACK, 2)`，API不可用时回退普通`StartGesture`；非闪电死亡塔仍走原动画分支。
- 自动验证通过：84模块配置生成、`TOWER_LIGHTNING_VISUAL_PASS`、`LIGHTNING_FROST_PHYSICAL_CONTRACT_PASS`、CSV与生成Lua各20行攻速精确为2、CSV UTF-8 BOM与中文名称检查、两个目标Lua 5.1语法及限定`git diff --check`。尚未进行Workshop Tools实机动画节奏验收。

## 当前实施任务（2026-08-11）：闪电/寒冰塔技能恢复物理伤害并保留收窄后的闪电触发链

- 用户要求回滚魔法伤害版本：闪电打击和冰霜攻击恢复原生物理主攻击，后续跳跃、冰霜范围伤害、暴风雪、落雷和电圈均恢复物理伤害并进入护甲结算。
- 闪电塔落雷只由闪电打击造成击杀时触发；普通攻击、落雷和电圈击杀不得触发新的落雷。
- 电圈只由落雷命中事件触发；闪电打击直接命中、电圈自身伤害和其他来源不得触发电圈，电圈不得递归。
- 伤害来源必须显式保留在本次技能伤害事务边界内，不能继续按“当前塔是 attacker”推断落雷触发来源。
- 权威技能说明继续来自 `data/csv/建筑与工人系统/防御塔/tower_skill_definitions.csv`，生成 Lua、Tooltip 和本地化镜像必须由现有生成链同步产出。
- 自动验收覆盖原生主攻击未被抑制、相关脚本伤害使用 `DAMAGE_TYPE_PHYSICAL`、闪电击杀/落雷/电圈触发边界、配置生成一致性、Lua 5.1 语法、严格编码和限定 `git diff --check`；Workshop Tools 冷启动仍是最终护甲实机验收。
- 实现完成：Modifier 不再抑制闪电打击/冰霜攻击的引擎原生攻击，闪电首目标不再提交额外脚本伤害；连锁跳跃、冰霜范围、暴风雪、落雷和电圈均通过物理伤害结算。闪电打击主目标或跳跃致死后仍直接启动一次落雷，旧的全局 `OnDeath` 落雷入口保持移除。
- 电圈入口继续硬校验 `source == "lightning_storm"`；闪电打击不发布 `TOWER_LIGHTNING_HIT`，生产 Modifier 仅剩落雷发布点，电圈伤害不发布命中事件，因此不递归。
- 权威塔技能 CSV、生成技能 Lua、Tooltip CSV/Lua及六份中英本地化镜像已同步为物理伤害文案；专项生产契约同步改为验证物理伤害。
- 尚未进行 Workshop Tools 实机验收。需用不同物理护甲敌人确认主目标及技能伤害随护甲变化、闪电主目标没有双伤、闪电跳跃击杀触发一次落雷、普通攻击/落雷/电圈击杀不触发落雷，以及仅落雷命中能触发电圈。

## 当前实施任务（2026-08-12）：外围玩家档案Mock纵向切片

- 用户批准先按稳定远端协议实现本地假数据版，覆盖付费权益、成就、长期存档和同局公开投影；正式数据库、支付回调、HTTP读取和游戏结果写回暂不实施。
- 权威业务定义继续来自`data/csv/`：档案运行规则、开发账号映射、成就定义和公开字段白名单均使用CSV；玩家样本值来自`data/mock/player_profiles.json`。
- 运行时必须通过统一Provider接口加载JSON，完整档案只保存在Lua服务端；Custom Net Tables只发布白名单公开字段，不得发布订单、金额、鉴权信息、完整库存或私有存档。
- 首版实现完整快照、`revision/update_id`增量、幂等、迟到更新拒绝、版本缺口要求重新拉取，以及现有`player_entitlement_service`原子投影。未来HTTP Provider必须复用同一JSON解析、schema校验和提交入口。
- 自动验证至少包含Lua 5.1 JSON/快照/增量行为、PowerShell契约、CSV生成与JSON生成一致性、现有商城权益回归、Lua 5.1语法、严格UTF-8和限定`git diff --check`。Workshop Tools验证只确认引擎初始化与NetTable发布，不等同远端数据库验证。
- 首版生产实现已完成：统一JSON解码、Fixture Provider、完整快照、增量事务、账号绑定、代际去重、旧快照/迟到回调拒绝、VIP失败关闭、服务端完整档案查询、公开白名单NetTable及变更元事件均已接入。VIP CSV默认值已从测试期true改为false；只有验证通过的档案可授予。
- 已归档（2026-08-12）样本账号：玩家0=`mock_account_10001`（VIP、N2、120成就分），玩家1=`mock_account_10002`（非VIP、N1、0分），玩家2/3为预留非VIP空样本；这些仅属于`local_fixture`，不代表正式Steam账号。
- 已归档的旧限制：当时尚未实施真实Steam身份解析、Mock HTTP和正式数据库。当前真实HTTP、Supabase和Steam身份链路已接入；支付回调、存档写回和长期库存投影仍未完成。
- 已归档的自动验证记录：`PLAYER_PROFILE_SERVICE_LUA51_PASS`、`PLAYER_PROFILE_CONTRACT_PASS`等历史结果不等于Workshop Tools、双客户端或后端实机验证；当前验证边界以本文件顶部为准。

## 当前实施任务（2026-08-11）：第7塔路线由魔法塔重构为防空塔

- 用户已批准实施：将当前第7路线“魔法塔→大魔法塔→魔法至尊”重构为“防空塔→防空火炮→空域霸主”，基础数值、升级费用、人口占用与阶段等级沿用当前CSV。
- 飞行身份严格读取怪物权威CSV投影：`movement_type == "flying"`或`movement_type_override == "flying"`任一成立。第7路线自动索敌、手动攻击、竞态伤害兜底及七塔合一第7路都只能攻击飞行单位。
- 防空炮等级1至5每轮对同一目标发射`4/5/6/7/7`枚飞弹，每枚为独立普通攻击并享受对空伤害+90%；塔面板攻速保持1。目标死亡后本轮剩余飞弹停止且不转射，随后重新索敌开启下一轮；额外普通攻击必须隔离递归。
- 防空火炮等级1至5的每枚真实命中独立以`10%/12%/14%/16%/16%`概率眩晕飞行单位3秒。
- 空域霸主半径500：范围内敌方单位最终承伤提高20%，其中飞行单位攻击速度额外降低20%；同名效果不叠加，离开范围恢复，攻速变化通过现有`UNIT_COMBAT_STATS_CHANGED`链同步到敌方选中单位UI。
- 策划数值只写入`data/csv/`权威源；生成Lua不得直接编辑。实现后新增专项Lua/契约测试，并执行配置生成一致性、Lua 5.1语法、严格编码及限定`git diff --check`。自动测试不等于Workshop Tools实机验收。
- 实现与自动验证完成：防空路线、技能、Tooltip、本地化、飞行索敌/手动命令/伤害竞态兜底、七塔合一第7路、额外普通攻击序列、每弹眩晕和空域光环均已接入。正式波次、普通遭遇及挑战会话三条生成边界都会保存CSV飞行身份；挑战会话同时按该身份设置引擎移动能力。
- `ANTI_AIR_TOWER_LUA51_PASS`覆盖`0.1s`飞弹调度、`4`枚总数、递归隔离、目标死亡停止、每弹独立眩晕及双光环；`ANTI_AIR_DAMAGE_FILTER_LUA51_PASS`证明最终加法伤害项交换顺序结果不变，并锁定空域`1.2`在Boss与其他最终倍率之后相乘。
- 通过：`ANTI_AIR_TOWER_CONTRACT_PASS`、配置生成84模块成功、目标Lua 5.1语法、`BUFF_MANAGER_NONSTACKING_PASS`、`WAVE_FLYING_COLLISION_PASS`、`WAVE_SPECIAL_MIXED_WAVES_PASS`、严格UTF-8及限定`git diff --check`。既有`test_tower_class_fusion_counts.lua`在加载带BOM的`building_system.lua`时被Lua 5.1解析器阻断，未进入业务断言；本轮未改该既有文件。尚未进行Workshop Tools实机验收。
- 2026-08-11紧急启动修复：防空改动曾删除`tower_magic_supreme_system`的`require`与`init()`，但`M.precache()`仍首先调用其`precache(context)`，导致预载入口在同步加载主城和`npc_dota_hero_monkey_king`前中断；表现为主城预建筑error模型，以及猴王本体、武器、头发、护甲和肩部资源未加载。现已恢复模块绑定和初始化，并新增`ADDON_PRECACHE_CONTRACT_PASS`锁定模块生命周期及主城/猴王同步预载项；`addon_game_mode.lua`通过Lua 5.1语法检查。仍需完全停止旧会话后冷启动Workshop Tools确认引擎资源恢复，热重载不能证明启动预载已重跑。

## 已完成实现（2026-08-11）：修理工自杀返还占用人口

- 用户批准为普通和高级修理工增加同一个即时无目标自杀技能；点击后立即死亡，不弹确认、不吟唱。
- 权威训练数据继续来自`data/csv/建筑与工人系统/training_definitions.csv`。两级修理工各占用1人口，并由CSV声明主动技能。
- 技能只负责杀死当前施法修理工；`worker_system.lua`现有工人死亡链负责恰好释放该实体记录的`population_cost`。示例验收为`12/13 -> 11/13`。
- 自杀不调用资源增加或训练失败退款入口，已消耗金币和木材均不返还；累计训练次数、阶段解锁状态也不倒退。
- 实现完成：新增CSV驱动的`ability_repairer_suicide`，训练创建逻辑按`active_skill_ids`挂载并升至1级；技能只对已标记修理工执行`ForceKill(false)`，人口仍由既有死亡链恰好释放一次，技能代码不调用人口或资源变更入口。
- 自动验证完成：真实技能行为桩覆盖普通/高级两级技能挂载、即时死亡、`12/13 -> 11/13`、重复死亡不重复释放、木材金币不变和训练进度不倒退；专项契约、修理工百分比/右键回归、工人训练回归、目标Lua 5.1语法、配置生成与CheckOnly、严格编码、Python编译和限定`git diff --check`通过。尚未进行Workshop Tools实机验收；需完全停止当前测试会话并重新Run后分别训练两级修理工点击技能确认。
- 2026-08-11实机反馈修复：自毁现在经`WORKER_DISMISS_REQUEST`同步执行死亡与幂等登记清理，人口不再依赖死亡实体句柄仍有效；引擎死亡桥同时传递`victim_entindex`作为自然死亡兜底。修理工`max_count`改为限制当前存活数量，历史训练总数继续保留但不再永久禁用按钮；高级修理工从`2/2`死亡一名后恢复为`1/2`并可重新支付1000金币、1人口训练。

## 当前插入任务（2026-08-11）：闪电魔塔击杀风暴即时伤害与纯视觉雷柱

- 用户最终确认：任意归因于当前闪电塔的伤害造成击杀时，以死亡位置为圆心立即查询一次500范围敌人，按LV1至LV5分别造成触发时塔攻击快照110%/120%/130%/140%/150%的物理伤害。每个范围目标只受伤一次并只发布一次`TOWER_LIGHTNING_HIT`；风暴伤害保持原塔归因，可继续触发连锁风暴。
- 已完成生产实现：权威`tower_skill_definitions.csv`把五级`damage_timing`改为`instant`、倍率改为1.1至1.5，只保留`strike_count=5/6/7/8/9`作为视觉次数，删除`damage_increment_per_strike`和`damage_multiplier_cap`。`modifier_tower_attack_effects.lua`在触发栈内完成单次范围查询、伤害和命中事件；后续调度回调只在一秒内创建随机雷柱粒子，不查询敌人、不调用伤害服务、不发布命中事件。
- 独立“雷电扩散LV1”生产逻辑未修改：每个原始雷电命中事件独立30%判定，对目标周围200范围其他敌人造成该次伤害200%，扩散伤害标记为secondary且不重新发布`TOWER_LIGHTNING_HIT`，因此不递归。
- 已同步：定向生成`tower_skill_definitions.lua`，统一生成Tooltip CSV/Lua，六份中英本地化镜像同步五级即时倍率和纯视觉雷柱说明；塔配置README明确`strike_count`只表示视觉次数。技能ID和最高等级未变化，Ability KV无需修改。
- 自动验证通过：`LIGHTNING_TOWER_KILL_TRIGGER_LUA51_PASS/CONTRACT_PASS`，覆盖五级倍率、触发栈内即时伤害、单次范围查询、双目标各一次伤害/事件、5至9道视觉、视觉零查询/零伤害/零事件、原塔归因、连锁风暴，以及扩散30%/200%/排除原目标/非递归；怪物War3护甲、终极塔和本地化回归通过。5个目标Lua语法、塔技能和Tooltip生成逐字节一致、CSV 19列结构、配置CheckOnly、15个目标文件严格UTF-8/BOM及限定diff通过。
- 尚需Workshop Tools完全冷启动：确认LV1至LV5击杀瞬间立即跳血一次，实际倍率和物理护甲链正确；一秒内仅显示5至9道随机雷柱且不再追加伤害/扩散判定；多个目标各结算一次；风暴击杀继续连锁；独立雷电扩散保持每目标一次30%判定。自动测试不能替代引擎实机验收。

## 当前修复任务（2026-08-18）：善于发现与融合后伐木工战斗属性UI刷新

- 根因确认：融合目标沿用已有永久`modifier_lumberjack_ai`，再次`AddNewModifier`只刷新同名Modifier；原实现没有`OnRefresh`，因此融合后新增性格参数没有写入实际攻击实例。“善于发现”的CSV、生成配置、`TREE_HIT`金币载荷和资源服务均存在，但运行时`gold_per_hit_flat`仍保持旧值0。
- 修复：`modifier_lumberjack_ai`统一由参数应用函数处理`OnCreated/OnRefresh`，使“善于发现”每次成功采集增加CSV配置的10金币，并同时保证其他融合性格参数可即时刷新。
- 融合属性投影：伐木工重算最终攻击间隔后同步写回`survival_attack_speed`；融合完成且科技、性格和啦啦队重算结束后派发`UNIT_COMBAT_STATS_CHANGED`。现有`ui_request_router`只对当前选中该实体的玩家即时推送`ui_selected_unit_stats_snapshot`，攻击力与每秒攻击次数不再停留在融合前快照。
- 自动验证通过：目标Lua 5.1语法、`LUMBERJACK_DISCOVERER_GOLD_CONTRACT_PASS`、`LUMBERJACK_PERSONALITY_RUNTIME_CONTRACT_PASS`及限定`git diff --check`。仍需Workshop Tools冷启动确认每次成功采集金币+10、头顶金币数字，以及融合时保持选中状态后攻击力/攻速立即更新。
- 2026-08-18追加修复：自我PUA每次成功采集后的攻击力成长原本已正确写入实体和`survival_attack_min/max`，但没有派发战斗属性刷新事件。现于成长重算完成后派发`UNIT_COMBAT_STATS_CHANGED`，由现有选中单位快照链即时刷新攻击力UI；成长数值仍完全读取CSV的每次+5，科技成长逻辑不变。
- 2026-08-18表现修复：“善于发现”不再调用官方`OVERHEAD_ALERT_GOLD`。资源增加成功后改为向所属玩家发送金矿既有的`survival_gold_mine_income_number`，目标实体为触发采集的伐木工，复用金矿黄色上浮金币数字；`critical=0`且全链不调用声音API，因此没有音效。金币结算和CSV每次+10保持不变。

## 当前插入任务（2026-08-11）：Ability Tooltip 几何诊断作用域异常

- Workshop Tools 实机日志确认 `ability_tooltip.js:997` 在 `scheduleExternalGeometryDiagnostic(binding)` 的异步回调中读取未定义的 `active.engineSlot`，触发 `Uncaught ReferenceError: active is not defined` 并中断当次 Panorama 脚本回调。
- 权威 Tooltip CSV `data/csv/公共规则/tooltip_definitions.csv` 内容正常；问题属于 Panorama 客户端代码作用域错误，不修改 CSV、生成 Lua 或 Tooltip 业务数据。
- 已确认当前 content 源码与 game 编译产物均包含错误引用。最小修复为改用当前函数参数 `binding.engineSlot`，随后强制重编译 `ability_tooltip.js` 并执行源码、产物、UTF-8 和限定差异检查。
- 现有 `test_memory_lifecycle_contract.ps1` 当前先失败于无关的 `SURVIVAL_UI_CONTEXT_GUARD_MISSING`，本轮必须单独报告该既有阻断，不能把专项字符串检查冒充完整生命周期契约通过。
- 已完成：`content/.../ability_tooltip.js:997` 已改为 `binding.engineSlot`，Resource Compiler 强制编译结果为 `OK: 1 compiled, 0 failed, 0 skipped`；源码和编译产物目标函数体作用域契约、`ABILITY_INPUT_LIFECYCLE_CONTRACT_PASS`、严格 UTF-8 和限定 `git diff --check` 通过。仍需完全停止并重新 Run Workshop Tools，确认冷启动日志不再出现 `active is not defined`。

## 当前插入任务（2026-08-11）：逐波模型资源会话、W12预载修复与临时兼容TODO

- 用户确认最终目标是每个正式波次拥有独立的最终模型配置，不依赖前一波已经加载的模型。当前`normal_flying_model_path`把多波普通飞行怪统一映射到Visage，只是模型尚未逐波定稿期间的临时兼容层，必须标记`TODO(FINAL_WAVE_MODELS)`；待逐波模型表完整后删除该字段、共享模型租约兼容和相关分支。
- 已定位W12错误的确定根因：正式预载和出生使用`model_path_for()`，但`monster<N>`开发跳波仍直接读取`definition.model_path`。因此`monster12`预载Dragon Knight/旧飞行基础模型，出生却`SetModel()`为Visage，触发`requested is not loaded and may have been deleted`。修复必须让正式预载、开发预载和出生设置消费同一实际模型解析。
- 资源生命周期采用波次会话和Lua租约：每波独立登记planned/pending/alive及实际模型集合；生成完成且该会话怪物全部死亡后调用统一release边界，清除本波Lua引用、回调身份、附件/粒子/实体生命周期状态。波次重叠时按会话身份结算，禁止只看全局`current_wave`提前释放其他波。
- `release`不等于Source 2强卸载。Workshop Lua当前没有公开、安全的`UnloadModel/UnloadResource`；现有`asset_preload.retire()`只会把Lua状态永久置为`RETIRED`并阻止以后重载，不能作为波次delete。实现必须标记`TODO(SOURCE2_MODEL_UNLOAD)`，未来只有在Valve提供安全卸载API或项目迁移到可卸载独立资源包后才能接入真正模型卸载。
- dev模式继续清理怪物实体、附件、粒子、任务和会话对象，但不释放模型租约、不调用`retire()`；反复`monster<N>`可复用已加载资源。正式波次在倒计时开始即独立请求下一波资源，并在配置的4秒窗口幂等复核；urgent波次请求不得被塔/城墙后台串行流阻塞，且不得改变倒计时、数量、顺序或生成间隔。
- 实现与自动验证完成：`monster12`开发预载现使用与出生一致的Visage解析；正式波次拥有独立session/共享路径租约，pending或alive非零时拒绝release，重叠波只释放已完成session，dev释放session身份但保留resident模型租约。urgent请求可与后台流并行；Visage资产权威`first_use_wave`由14更正为8并定向生成Lua。
- 通过：`WAVE_MODEL_RESOURCE_LIFECYCLE_PASS`、`ASSET_PRELOAD_URGENT_PARALLEL_PASS`、`WAVE_MODEL_RESOURCE_LIFECYCLE_CONTRACT_PASS`、`WAVE_MONSTER_VISUAL_INTEGRATION_PASS`、`ASSET_PRELOAD_GRADUAL_PASS`、`DEV_ASSET_PRELOAD_PASS`、`WAVE_EARLY_FINAL_PASS`、`WAVE_SPECIAL_MIXED_WAVES_PASS`、`WAVE_SPAWN_SEQUENCE_PASS`、`WAVE_FLYING_COLLISION_PASS`、`WAVE_MONSTER_MODEL_RESOURCES_PASS`、资产生成逐字节一致、配置CheckOnly、目标Lua/Luac 5.4.5语法、Python编译和限定`git diff --check`。本机无Lua 5.1，不宣称Lua 5.1验证。
- 既有非本轮失败：`test_wave_difficulty_builder.lua`仍要求旧N1最终波批次数；`test_wave_difficulty_selection.lua`仍把当前已启用N3当作非法难度；`test_asset_preload_service.lua`仍硬编码旧后台流总数26而当前生产为9。本轮未修改这些过时业务基线。用户2026-08-11后续观察中暂未再发现加载问题，记为阶段性有效而非永久保证；未来新增逐波模型后仍需冷启动分别执行`monster<N>`和正式目标波，核对首只怪及`phase=countdown_start`/`phase=lead_review`日志。完整复发排查经验见`WAVE_MODEL_LOADING_TROUBLESHOOTING.md`。

## 已完成插入任务（2026-08-11）：正式波次数量、混合顺序、飞行模型与Hull修正

- 根因确认并修复：N1-N5 W11均同时保留旧59只成员和新59只混合成员，导致运行时普通怪实际为118只。权威CSV现删除旧重复行，全表`wave_id`唯一；五个难度W11均严格为`beast_green_large ×10 + skeleton_bone ×30 + flying_red_gargoyle ×19 = 59`，不含领头怪和进攻Boss。
- `tools/build_configs.py`新增生成边界失败关闭：拒绝重复`wave_id`，并要求N1-N5中所有实际存在的W11-W30波次普通怪严格为59。N1与N3-N5导入器在复用现有模板前按`wave_id`保留最终定义，防止再次叠加旧数据。
- 混合出怪以移动类别建立独立轮转队列，正式规则为每2只地面后1只飞行；两种地面原型表现为`地A → 地B → 飞`，一种地面原型表现为`地 → 地 → 飞`，任一类别耗尽后确定性输出剩余成员。五个难度W11/W13/W24共15个真实混合波已逐位置验证。
- `monster_archetypes.csv`新增`normal_flying_model_path`。只有正式波次`normal + flying`成员使用该专用字段，当前统一为Visage飞行模型；预载与出生模型使用同一解析。飞行领头怪、精英、Boss、十罪和挑战怪仍使用共享原`model_path`，未扩大修改范围。
- 正式普通飞行怪基础Hull改为10并保留单位碰撞；飞行领头怪、精英和Boss继续Hull 0与无单位碰撞。`scalemonster`以基础Hull非累计缩放，专项覆盖`10×4=40`后改为`10×0.5=5`。
- 自动验证通过：`WAVE_SPECIAL_MIXED_WAVES_PASS`、`WAVE_SPAWN_SEQUENCE_PASS mixed_waves=25 special_mixed_waves=15`、`WAVE_FLYING_COLLISION_PASS`、`WAVE_MONSTER_MODEL_RESOURCES_PASS`、`WAVE_GENERATED_BYTE_MATCH_PASS count=2`、严格UTF-8、Python编译、Lua/Luac 5.4.5语法及限定`git diff --check`。当前机器没有可执行Lua 5.1，因此不宣称本轮Lua 5.1验证。
- 尚待Workshop Tools完全冷启动实测：跳到W11核对实际59只构成和`2地+1飞`顺序，确认普通飞行怪显示Visage模型、不会相互完全叠加，并观察Hull 10及`scalemonster`倍率下的真实拥挤/阻挡。自动验证不能记录为引擎实机验收。

## 当前插入任务（2026-08-10）：本地化缺失与重复 token 告警清理

- 用户提供冷启动日志：`npc_survival_repairer`、`npc_survival_builder_proxy` 缺失精确本地化 token；挑战通用奖励说明、`building_gold_mine`和`building_hero_altar`存在大小写不敏感同名但文本不同的重复定义。
- 已完成最小范围修复：单位显示名先补入`unit_display_names.csv`并定向生成；六份game本地化镜像和两份content Panorama源已同步；历史大小写别名继续保留但值已统一；中英文建筑占位值分别改为可显示名称。未修改Lua运行逻辑、启动规则、modifier bootstrap或fingerprint日志。
- 性能边界：这些告警主要发生在本地化加载/热重载阶段，不是逐帧热路径；本任务目标是消除重复日志、避免覆盖顺序导致错误显示，并防止缺失token被重复请求，不能把静态清理夸大为已证明的帧率提升。
- 自动验证结果：`LOCALIZATION_TOKEN_INTEGRITY_CONTRACT_PASS`、八文件大小写不敏感冲突扫描、结构检查、定向生成逐字节一致、生成Lua 5.1语法、严格UTF-8/BOM和Builder替换回归通过。既有免费英雄替换契约在无关的`FREE_HERO_STRENGTH_INVALID_hero_shadow_fiend`断言失败；未修改英雄CSV或其生成配置。
- 剩余验证：必须完全退出并冷启动Workshop Tools，确认日志中的`FindSafe`缺失token与`Ignoring duplicate token`告警不再出现；自动检查不能替代引擎本地化装载验证。

## 当前插入任务（2026-08-10）：英雄移动白名单与建筑禁建黑名单

- 用户当前消息已明确批准从Plan切换到Act并实施本任务；该指令优先于本文后部仍记录的“多人阶段1等待验收”。多人任务保持原状态暂停，本轮只修改区域、目的地、Grid、传送、命令过滤和英雄边界守卫直接相关内容。
- 已批准模型：`build_forbidden_regions.csv`使用`region_type=hero_movable|building_forbidden`，支持`circle`和按边界顺序定义的凸`quadrilateral`。召唤祭坛产生的正式战斗英雄受移动白名单约束；Builder、伐木工、修理工、建筑、怪物和隐藏占位英雄不受英雄白名单约束。
- 英雄普通移动/攻击移动的非法目标在Order Filter提前拒绝；追击、击退和脚本位移等运行时越界由生命周期守卫停止动作并拉回最后合法位置。普通寻路不承诺整条路径都位于白名单内。
- 空区域配置必须保持游戏可玩：没有启用的`hero_movable`时白名单视为未启用，英雄沿用既有导航，建筑沿用既有Grid边界、地形、坡度、树木、单位、占用和所有权校验；不得猜测坐标或伪造超大区域。
- 一旦存在有效`hero_movable`，建筑footprint必须完整位于其区域联集内；`building_forbidden`始终独立生效，与白名单是否启用无关。区域策略拒绝时仍必须返回完整footprint cells并全部标红，不能用空`cells`隐藏Grid。
- 工作区已有本任务前置草稿：目的地/Grid/传送相关tracked文件有未提交修改，CSV、生成Lua、区域服务和目的地服务为未跟踪文件。本轮在其基础上审计和完成，不回滚其他既有修改。
- 本机有效工具链已重新探测：Python 3.11.9位于`C:\Users\a\.workbuddy\binaries\python\versions\3.11.9\python.exe`，Lua/Luac 5.1位于`C:\msys64\mingw64\bin`，PowerShell 7.6.4位于`C:\Program Files\PowerShell\7\pwsh.exe`；`.cline/local-toolchain.json`现有路径失效，需同步修正。
- 本轮实现结果：已完成CSV schema、生成、区域几何服务、英雄/建筑策略分离、统一目的地校验、Grid footprint白名单/黑名单、移动/攻击移动Order Filter、英雄生命周期回退、祭坛/挑战/练功房/回城/球状闪电/终极塔锚点接入。`build_forbidden_regions.csv`当前无启用业务行，因此运行时保持旧地图导航与Grid建造规则；后续写入真实`hero_movable`后自动启用严格白名单。
- 本次兼容修复自动验证：区域PowerShell契约、区域Lua 5.1几何/Grid行为、英雄身份/回退/移动过滤、Builder替换与Ability槽位、多人Builder、输入生命周期、祭坛输入、树规则、终极塔数学、相机契约、目标Lua 5.1语法、配置CheckOnly、区域CSV定向生成逐字节一致、生产/测试严格UTF-8、本轮文档新增行无替换字符及限定`git diff --check`通过。既有Builder移速测试仍要求600但当前CSV为500，既有Builder utility契约仍要求Monkey射程1000；两项失败均未修改本任务区域代码或权威数据。
- 剩余验证：需Workshop Tools冷启动确认当前空配置下Grid正常显示、合法地点可建造，区域拒绝时Grid保持显示并标红。Hammer真实边界仍是启用新白名单能力所需的数据，但不再阻断当前地图可玩性。

## 已完成插入任务（2026-08-09）：怪物护甲并发冲突解决

- 用户确认此前“117 War3护甲保持线性投影为39运行时护甲，并在Damage Filter中只补偿War3目标曲线/当前Dota曲线差值”的方案已通过测试验收。本次处理`armor_balance.lua`与当前分支现代非线性映射的stash恢复冲突，以该已验收行为为准，并同步核对波次、挑战、调试怪、科技减甲和UI映射身份，不能只删除冲突标记。
- 已完成兼容合并：保留`from_war3_modern()`、版本化反投影等正交辅助API，但波次、挑战和调试怪继续使用`from_war3()`线性`/3`边界且不写现代映射身份，117保持39而非约34.32；英雄临时减甲UI继续线性反投影。怪物护甲专项、科技减甲和毒云Lua 5.1行为/契约及目标语法已通过。用户明确确认此前固定样本测试验收通过，未提供精确击杀秒数或日志，因此只记录验收结论，不虚构测量值。

## 已完成插入任务（2026-08-09）：怪物物理伤害按War3目标曲线补偿

- 权威CSV基准为`n1_wave_05_5b`的20000生命/117 War3护甲，以及`arrow_tower_lv05`的401攻击/1次每秒。117继续经既有生成/出生边界`/3`投影为39 Dota运行时护甲；目标承伤倍率为`1/(1+0.02*117)=0.299401`，7塔理论击杀时间约23.79秒。
- 已纠正前一轮错误假设：当前Dota正护甲曲线不是旧式`1/(1+0.06*A)`。39运行时护甲的当前原生承伤倍率约0.2684，单靠引擎约需26.55秒。`monster_war3_armor_damage_enabled=1`现只对明确标记的项目怪物物理伤害应用“War3目标倍率/当前Dota倍率”的预护甲补偿，随后仍由引擎正常结算护甲；117样本下401先补偿为约447.32，原生护甲后约120.06。不开忽略护甲flag、不递归`ApplyDamage`，避免旧实现先手动减甲再被引擎二次减伤。
- 为保证固定基准中的“7塔每秒各命中1次”成立，`global_rules.csv.base_arrow_tower_cannot_miss=1`通过现有塔公共Modifier赋予未转职基础箭塔必中；严格以`survival_building_id=arrow_tower`且`tower_class`为空限制范围，七条转职路线、终极塔代理、英雄、工人和其他单位不受影响。伤害、攻速、护甲和弹道数值未改。
- 复用`global_rules.csv.runtime_detailed_diagnostics`增加默认关闭的限量诊断：`MONSTER_PHYSICAL_DAMAGE_FILTER`记录进入原生护甲阶段前的伤害、flags、运行时护甲、生命和Filter倍率；`TOWER_ATTACK_RESULT`分别累计每座塔前20次landed/failed。诊断不参与伤害或命中计算。
- 自动验证通过：`MONSTER_WAR3_ARMOR_DAMAGE_LUA51_PASS/CONTRACT_PASS`、117护甲固定数学基准、开关关闭/非怪物/非物理/非正护甲边界、基础塔必中范围、科技减甲、毒云、树伤害、塔射程/弹速、箭塔成本与融合回归，以及目标Lua 5.1语法。用户已明确确认固定样本测试验收通过；未提供精确击杀秒数或日志。项目CSV最高存在4990 War3护甲，极高护甲下的引擎上限行为仍需后续独立抽样，固定样本验收不能替代该边界验证。
## 当前紧急修复（2026-08-10）：N2-N5 W11错误飞行怪恢复为地面怪

- 用户实机反馈第十一关模型错误，怪物表现为飞行单位：可穿地形并相互叠加。审计确认运行时按成员逐只设置移动能力，W1-W5视觉覆盖不处理W11；根因是N2-N5 W11残留19只`flying_red_gargoyle`旧成员，而当前N1 W11权威模型只有`beast_green_large`和`skeleton_bone`两种地面怪。
- 权威CSV已将N2-N5 W11普通怪统一为`beast_green_large=15`、`skeleton_bone=44`，删除四条飞行成员及三倍飞行护甲，普通怪总数仍为59；领头怪保持1只且所有运行字段不变。生成Lua已定向同步。
- `import_n3_wave_workbook.py`仅对W11应用批准校正：普通飞行数量强制为0并只使用N1同波`member_role=normal`模板，防止旧工作簿重新生成飞行怪或把领头怪混入普通模板。W12及其他合法飞行波不受影响。
- 自动验证通过：`WAVE_11_GROUND_MONSTERS_PASS`、模型资源检查、生成逐字节一致、配置CheckOnly、生成Lua语法、严格UTF-8/BOM、限定范围与`diff --check`。既有未跟踪`test_wave_monster_visual_integration.lua`在业务断言前失败于旧预载桩缺少`dev_wave_preload_timeout_seconds`，本任务未修改该测试或无关预载逻辑。尚需Workshop Tools完全冷启动后跳到W11，确认模型、地形阻挡、单位碰撞和59只数量。

## 当前插入任务（2026-08-09）：怪物尸体生命周期优化

- 用户需求：怪物死亡完成业务结算后，不再让大量尸体长期留在地表；采用短暂保留、平滑下沉、`AddNoDraw()`隐藏并安全移除实体的方式，降低高密度波次中的模型、阴影和实体管理开销。
- 实现边界：先审计CSV权威配置、引擎死亡事件、波次/挑战奖励与计数调用链；仅清理明确属于项目怪物的死亡实体，不影响英雄、工人、建筑、召唤物、掉落物或死亡结算。下沉/清理时序必须数据驱动，任务可取消且按单位生命周期去重。
- 生产实现：新增`monster_corpse_lifecycle_service`。波次怪、挑战/转生怪和`addmonster`调试怪以显式单位身份加入清理链；`ENGINE_ENTITY_KILLED`同步业务结算完成后，尸体按CSV保留0.6秒、由单个共享0.05秒任务在0.8秒内下沉160码，随后`AddNoDraw()`并延迟0.05秒`UTIL_Remove()`。强制波次清场继续立即删除，英雄、工人、建筑、召唤物、训练目标和掉落物不受影响；状态以单位对象为生命周期身份，不永久保存可复用entindex。
- 日志与本地化：`global_rules.csv.runtime_detailed_diagnostics=0`默认关闭防御塔成功效果明细及两类英雄攻击追踪日志，塔日志在开关关闭时连`string.format()`也不执行；错误、施法请求、DamageFilter限次诊断和低频内存聚合保留。四个Panorama本地化helper按HUD context缓存最多256个token，缺失token同样缓存为空，避免持续重复请求；Tooltip SHOW/RECOVERY等详细日志及背包恢复日志仅在`SurvivalTooltipDetailedDiagnostics === true`时输出。
- 自动验证：`MONSTER_CORPSE_LIFECYCLE_LUA51_PASS`、`MONSTER_CORPSE_LIFECYCLE_CONTRACT_PASS`、`PERFORMANCE_LOG_LOCALIZATION_CONTRACT_PASS`、`GLOBAL_RULES_GENERATED_MATCH_PASS`、全项目356个Lua文件的Lua 5.1语法检查、18个目标文件严格UTF-8；`SESSION_LOG.md`历史3个替换字符数量保持不变且本轮新增段为0、配置`CheckOnly`及game/content限定`diff --check`通过。4份Panorama JS分别强制编译为`1 compiled, 0 failed, 0 skipped`。当前工作区没有文档历史提到的塔技能Lua测试文件，相关测试枚举为0，未将其误报为回归通过。
- 尚需Workshop Tools冷启动实测：批量击杀波次怪、挑战怪和`addmonster`，确认约0.6秒后开始下沉、约1.45秒后实体消失且奖励/掉落/击杀成长/波次计数不回归；确认英雄、工人、建筑和掉落物不会被清理；反复悬停技能并观察控制台不再持续输出Tooltip详细日志或localization错误；对比相同刷怪场景的尸体数量、控制台行数、服务器帧时间与客户端帧率。未经实机结果不能称为性能改善已验收。

## 当前插入任务（2026-08-09）：训练、建造与升级同步结果事务

- 需求：工人训练、建筑提交、普通/批量升级必须同步返回结构化结果；请求缺失或失败时不得保留Ability冷却。排队建造后发生的异步失败必须恰好回滚一次冷却，并在已扣费时完整退还资源/人口。修理工不能继续按同`training_id`活体数量永久卡在第一阶段，必须按权威CSV顺序推进；最终阶段完成后保留完成态并拒绝继续训练，伐木工最终无限阶段保持不变。
- 生产实现：`WORKER_TRAIN_REQUEST`、`BUILD_REQUEST`、`BUILDING_UPGRADE_REQUEST`和`TOWER_CLASS_REQUEST`全部改为`handle_request`，调用者改用`request`。升级handler继续写`payload.result`并同时返回结果，批量升级以返回值优先、`payload.result`兼容。原生训练/建造/升级Ability在无结果或`ok~=true`时`EndCooldown()`；Panorama直接提交仅在同步受理后启动冷却。
- 修理工进度：`worker_training_progress.create()`按prefix泛化，修理工与伐木工拥有独立按team状态和reset生命周期。修理工自动请求从CSV当前tier解析；LV1成功创建5次后进入LV2，LV2成功2次后最终快照保持`completed=1`并在扣费前拒绝。活体死亡不倒退训练历史；单位创建失败在资源/人口退款后不记录成功。伐木工CSV最终`train_lumberjack_08.max_count=-1`仍不完成且可无限累计。
- 建造事务：同步提交只表示移动任务已受理。任务保存`source_ability`；Builder死亡、二次位置失效、移动命令/实体创建失败、施工中建筑死亡等失败路径由`core/action_cooldown_rollback.once()`按task身份幂等回滚。实体已创建后的施工失败退木材、金币和人口；成功完成后清除退款与冷却上下文。
- 自动验证通过：`ACTION_COOLDOWN_ROLLBACK_LUA51_PASS`、`WORKER_TRAINING_PROGRESS_LUA51_PASS`、`SYNCHRONOUS_ABILITY_RESULTS_LUA51_PASS`、`REPAIR_WORKER_PERCENTAGE_MATH_OK/CONTRACT_OK`、`SYNCHRONOUS_ACTION_CONTRACT_PASS`、目标`LUAC51_PASS`、`TRAINING_CSV_GENERATED_FIELDS_PASS`、严格UTF-8、配置`CheckOnly`和限定`DIFF_CHECK_PASS`。`building_system.lua`保留项目既有UTF-8 BOM，语法检查使用仅验证用临时无BOM副本，没有改写生产编码。
- 尚需Workshop Tools冷启动实测：修理工连续训练5+2次的模型/数值/最终拒绝；资源不足和实体创建失败不消耗冷却且退款；Builder移动途中死亡、位置失效、施工中建筑死亡只回滚一次冷却并完整退款；普通升级、批量升级和箭塔转职失败不保留冷却。未经实机结果不能记录为用户验收。

## 已完成当前任务（2026-08-09）：统一N2–N5 W30普通怪为59只

- 用户明确稳定节奏：所有难度W1–W10保留原始普通怪数量；从W11起，每个已存在波次固定59只普通怪。N1截止W25，N2–N5截止W30；59只不包含`wave_leader`精英和`assault_boss`。
- 权威CSV与生成Lua审计确认：N2–N5 W11–W29均已是59只，只有四个难度的W30仍各为9只普通怪。四个W30都只有一个普通怪种`flying_red_gargoyle`，因此只需把对应普通怪行从9改为59，无比例取整歧义。
- 批准修改边界：只修改`n2_wave_30_30n1`、`n3_wave_30_30n1`、`n4_wave_30_30n1`、`n5_wave_30_30n1`的数量和备注，再从CSV定向生成`wave_definitions.lua`。精英、Boss、怪种、属性、顺序和其他难度数据保持不变。
- 验证通过：N1 W11–W25和N2–N5 W11–W30普通怪逐波59；W1–W10相对修改前不变；角色数量不变；Lua 5.1行为/语法、生成逐字节一致、严格UTF-8、CSV列数及限定`git diff --check`通过。旧N1–N5扩展契约仍硬编码修改前普通怪总数202/1270和总计划228/1303，分别失败于`N1_NORMAL_TOTAL_INVALID`、`N2/N3/N4/N5_NORMAL_TOTAL_INVALID`，未修改这些用户已有未跟踪测试文件。
- 尚未执行Workshop Tools实机验证；需要冷启动后确认N2–N5 W30实际生成59只普通飞行怪，以及W30的领头怪和进攻Boss仍各1只。

## 前阶段完成记录（2026-08-09）：N1 W11–W25普通怪同步为59只

- 前一阶段CSV核算确认只有N1 W11–W25普通怪不足59；随后按用户明确的统一节奏补齐N2–N5 W30。N1没有W26–W30；N2–N5 W11–W29原本已经是59，W30由9只普通怪统一调整为59只。
- 同波多种普通怪按修改前`monster_count`比例使用最大余数法确定性分配到总计59只，余数相同按CSV原顺序补齐。只修改31条`member_role=normal`行的数量和备注；怪种、属性、顺序、移动、缩放及其他字段不变。
- `wave_leader`作为精英怪保持N1 W11–W25每波1只；`assault_boss`只在W15/W20/W25各保留1只，其余目标波为0。故普通波计划总数为60，含进攻Boss波计划总数为61。
- 已从权威`data/csv/怪物与波次系统/wave_definitions.csv`定向生成`scripts/vscripts/config/generated/wave_definitions.lua`，没有直接手改生成文件。
- 验证通过：`TARGET_ONLY_DIFF_PASS changed_rows=31`、`N1_W11_W25_COUNT_CONTRACT_PASS`、`N1_W11_W25_LUA51_PASS`、`WAVE_DEFINITIONS_LUAC51_PASS`、`WAVE_DEFINITIONS_GENERATED_MATCH_PASS`、`WAVE_DEFINITIONS_STRICT_UTF8_BOM_PASS`。旧N2/N3扩展测试仍分别失败于任务前已有的领头怪排序断言和`ROLE_ORDER`文本断言，本次未修改无关排序逻辑或旧未跟踪测试。
- 尚未执行Workshop Tools实机验证；需要完全停止并重新Run地图，重点用N1 W11、W13、W16、W18、W24确认多怪种比例和实际生成总数，并确认精英/Boss数量不变。

## 历史任务（2026-08-09）：正式波次资源提前4秒异步预载（首次请求时点已被2026-08-11方案取代）

- 历史实现曾只在目标波倒计时剩余`wave_timing_rules.csv.formal_wave_preload_lead_seconds=4`时首次排队。2026-08-11 W12修复后，目标波在倒计时开始立即首次请求，4秒窗口仅作幂等复核；首波和练功房启动预载继续保留。
- 目标资源从当前难度生成后的波次成员读取`monster_archetypes.csv`模型，再合并目标波视觉CSV解析出的模型、组件模型、粒子和`asset_sounds.csv`实际音效资源；按`resource_type:path`统一去重。当前`asset_sounds.csv`无实际记录，因此未添加虚构音效路径。
- `asset_preload_service`保留主体模型的`PrecacheUnitByNameAsync`异步代理；附件模型、粒子和音效按各自资源路径处理，并在服务内跨正式波次/视觉服务统一去重。敌方`zombie_stream`后台批量流已关闭，塔和城墙`tower_stream/wall_stream`保留。
- `addon_game_mode.precache()`的怪物视觉启动范围收紧到W1；W2-W4练功房模型仍由`asset_catalog.csv`的`initial_required`启动包保留。正式倒计时不读取开发跳波的READY/3秒门禁，出怪数量、顺序和时间不变。
- 新增`test_formal_wave_preload.lua`、`test_formal_wave_preload_contract.ps1`和`test_wave_asset_resource_queue.lua`，覆盖首波保留、4秒触发、目标波隔离、Bundle资源展开、跨调用去重、后台流边界和正式流程不继承调试门禁。
- 自动验证：`FORMAL_WAVE_PRELOAD_CONTRACT_PASS`、`FORMAL_WAVE_PRELOAD_LUA51_PASS`、`WAVE_ASSET_RESOURCE_QUEUE_LUA51_PASS`、`DEV_WAVE_PRELOAD_CONTRACT_PASS`、`WAVE_TIMING_CONTRACT_PASS`、目标生成逐字节一致、目标严格UTF-8、目标Lua 5.1语法和限定`git diff --check`通过。
- 扩展验证中N1-N5旧波次契约仍分别失败于任务前已有的“领头怪必须排第一”断言；本任务未修改`wave_definitions.csv`、`monster_archetypes.csv`或其生成Lua。全项目354个Lua文件中348个直接通过`luac5.1`，6个既有BOM文件去除BOM后临时语法通过，未改写这些无关文件。
- 历史验收日志已由新双阶段日志取代：冷启动应同时观察`phase=countdown_start`和`phase=lead_review`（后者约剩4秒），确认目标波模型/组件/粒子实际显示、首只敌人时刻不变，并观察无敌方后台批量预载。

## 当前插入任务（2026-08-08）：`monster<N>`开发跳波预载窗口

- 用户实机复测确认`monster19`会输出`ready_after_buffer elapsed=3.00`并按时生成，但单位仍显示红色`ERROR`；这证明3秒门禁正常执行，剩余问题不是等待不足。
- 最终根因已由本机当前Dota `pak01_dir.vpk`目录索引确认：旧路径`models/heroes/tiny/tiny.vmdl_c`不存在，而`models/heroes/tiny/tiny_01/tiny_01.vmdl_c`存在。`PrecacheUnitByNameAsync()`对引用无效模型的代理仍可能回调READY，因此`ready_after_buffer`不能证明模型路径有效。
- 已批准边界：仅影响`monster<N>`/`monster <N>`开发跳波；复用现有`asset_preload_service`、`monster_visual_service`与`scheduler`。无论资源是否已就绪都固定等待满3秒渲染缓冲，3秒结束时未就绪或加载失败则失败开放；连续命令只允许最后一次生效，迟到状态不得二次出怪。正常波次倒计时、数量、属性、模型映射和正式出怪时序保持不变。
- 工作区保护：用户确认当前`building_levels.csv`修改与`wall_upgrade.xlsx`删除均为其有意改动，本任务完整保留且不触碰；大量既有未跟踪测试文件同样不清理、不覆盖。
- 生产实现完成：`wave_timing_rules.csv`新增`dev_wave_preload_timeout_seconds=3`并定向生成；`debug_spawn_wave()`现进入`dev_preloading`，按目标波CSV archetype模型去重并通过`asset_preload_service`紧急排队，同时排队波次视觉。原型资源状态只用于3秒结束时诊断；即使全部READY也等待完整3秒，FAILED/RETIRED/模型未注册或超时在缓冲结束后失败开放。独立settled锁、generation token及命名scheduler任务共同防止迟到轮询二次出怪和旧命令覆盖新命令。
- Tiny路径修复从权威CSV落地：`monster_tiny`、`golem_gray_small`、`golem_gray_large`及同样引用旧路径的`rebirth_boss_09`统一改为`models/heroes/tiny/tiny_01/tiny_01.vmdl`，定向重建两个生成Lua并同步`asset_proxy_monster_tiny`。专项契约同时禁止恢复不存在的旧路径；最终自动验证结果见本节后续记录。
- 既有回归未通过且未越界修复：未跟踪`test_wave_timing_contract.ps1`硬编码要求基线`late_interval_seconds=150`，但任务前权威CSV/生成Lua均为90；未跟踪`test_n1_wave_config.lua`仍失败于既有“W5起领头怪必须排首位”断言。本任务未修改这两个业务数据或用户测试。
- 编码修复：本次必须修改的`wave_timing_rules.csv`在Git基线已含真实`U+FFFD`替换字符；已依据可正常读取的生成Lua字段语义恢复该文件4行中文并统一为严格UTF-8，没有改动既有波次计时数值。
- 当前状态：3秒门禁已有用户实机日志证明按时执行；无效Tiny路径修复的专项Lua 5.1行为、PowerShell契约、Lua 5.1语法、VPK索引、定向生成逐字节一致、严格UTF-8和限定`diff --check`均通过。下一步必须完全冷启动Workshop Tools后输入`monster19`，确认Tiny LV1主体正常显示而非红色`ERROR`；再快速连续输入`monster19`、`monster20`确认只出最后一波。

## 当前插入任务（2026-08-08）：Lua高水位与W13-W18客户端闪退调查

- 用户提供`出英雄5秒后闪退.txt`并于2026-08-08批准第二轮最小修复。完整日志约4.62 MB/41789行，共120次JS Exception：119次为`ability_tooltip.js`几何诊断错误引用未定义`active.engineSlot`，1次为`combat_stats.js`无效单位分支调用不存在的`refreshOfficialReturnHomeHotkey`。日志生成于17:05，早于17:20-17:30第一轮生命周期源码和产物，因此不能否定第一轮门禁；但两个错误仍存在于当前源码/编译产物，必须修复。
- 第二轮批准边界：修复两个确定性ReferenceError；把`inventory_tooltip.js`纳入同一generation/context门禁和有界计数；Panorama聚合在启动约1秒、5秒及之后每60秒输出，覆盖短时崩溃；默认关闭Tooltip逐次SHOW/CURSOR/HITBOX等高频长诊断和200次游标探针，只保留错误、必要状态及低频聚合。扩展契约并强制编译四份JS。不修改CSV、波次数量/模型、Lua GC策略或用户既有其他改动。
- 第二轮生产实现完成：几何诊断改用作用域内`binding.engineSlot`；无效单位分支改为已有`refreshOfficialUtilityHotkeys([])`并继续受保护递归。`inventory_tooltip.js`的全部延迟、hover、NetTable和GameEvent入口现验证HUD generation/context，并发布pending/peak/recovery固定计数。聚合新增`startup_1s/startup_5s/periodic_60s`及inventory/游标探针字段；Tooltip详细SHOW/CURSOR/HITBOX/GEOMETRY/MAP/BIND/RECOVERY和背包恢复日志默认关闭，且默认不启动200次游标探针。
- 第二轮自动验证通过：`MEMORY_LIFECYCLE_CONTRACT_PASS`、`ABILITY_INPUT_LIFECYCLE_CONTRACT_PASS`、`ABILITY_UTILITY_ORDER_CONTRACT_PASS`、`SCHEDULER_DIAGNOSTICS_LUA51_PASS`、目标Lua `luac5.1 -p`、严格UTF-8、编译产物静态契约及两仓限定`diff --check`。`ability_tooltip.js`、`combat_stats.js`、`survival_ui.js`、`inventory_tooltip.js`分别由Resource Compiler强制编译为`1 compiled, 0 failed, 0 skipped`。这些只证明静态契约、Lua模拟/语法和构建通过，不是Workshop Tools实机验证。
- 最终状态检查期间新出现`monster_archetypes.csv`及对应生成Lua的怪物速度修改，用户已明确确认是其有意修改；本轮完整保留且未触碰。`SESSION_LOG.md`历史未提交段落存在既有`U+FFFD`替换字符，不在本轮新增记录中；本轮目标源码与新增文档段落严格UTF-8通过，未越界重写历史日志。
- 用户报告N1第13至18波附近客户端闪退，并观察到`LUA Memory usage warning`首次跨过16 MiB。当前没有普通文本log，但已在`game/bin/win64`找到同时间的`dota2_2026_0808_033038_0_V8_hiting_max_memory_limit__512_MB.mdmp`及4秒后的breakpoint转储。
- 初步结论：直接闪退证据指向Panorama JavaScript所在V8 VM达到512 MiB，不得把Lua 16 MiB高水位、V8 512 MiB上限和模型/显存资源池混为一谈。权威`wave_definitions.csv`与`monster_archetypes.csv`确认N1 W13-W18每波仅8至10只、1至2种模型；新增组装视觉仅覆盖W1-W5，因此模型数量不是当前第一嫌疑。
- 用户已批准实施低开销诊断和生命周期门禁：Lua只在波次开始、生成完成和活怪归零时输出当前Lua KiB、活怪、scheduler任务和视觉状态计数，不强制Full GC、不保存历史；Panorama复用`ui_bootstrap.js`的HUD generation，使旧context的长期调度和事件入口失败关闭，并发布固定大小的当前计数。
- 修改边界：不降低CSV怪物数量、不替换W13-W18模型、不修改生成配置、不通过每波`collectgarbage("collect")`掩盖泄漏；保留批量升级及其他既有未提交修改。完成后需冷启动Workshop Tools连续运行至少到W20，比较每波后Lua基线与Panorama诊断，并确认不再生成V8 512 MiB转储。
- 生产实现完成：`scheduler.task_count()`和`monster_visual_service.active_state_count()`提供只读计数；`wave_system`在波次开始、生成完成和活怪归零时输出`[SURVIVAL_MEMORY][LUA]`，包含波次、游戏时间、Lua KiB、alive/pending、敌人表、scheduler和视觉状态。没有调用Full GC，也没有保存样本历史。
- Panorama的`survival_ui.js`、`combat_stats.js`和`ability_tooltip.js`统一以`SurvivalInputLifecycleGeneration + context Panel`校验当前HUD身份。所有原始`$.Schedule`集中到`scheduleActive()`；旧context回调到期后只退出，不再递归。高频NetTable/GameEvent入口同样失败关闭。固定计数包含pending/peak调度、通知Panel、选择事件、Tooltip恢复/Runtime事件和代理Panel；`survival_ui`每60秒输出一条聚合`[SURVIVAL_MEMORY][PANORAMA]`，不保留历史。
- 自动验证通过：`MEMORY_LIFECYCLE_CONTRACT_PASS`、`SCHEDULER_DIAGNOSTICS_LUA51_PASS`、`WAVE_TIMING_LUA51_PASS/CONTRACT_PASS`、`ABILITY_INPUT_LIFECYCLE_CONTRACT_PASS`、`BUILDING_BATCH_UPGRADE_CONTRACT_PASS`、目标Lua 5.1语法、严格UTF-8及game/content限定`diff --check`。三份Panorama JS均由Resource Compiler强制编译为`1 compiled, 0 failed, 0 skipped`。
- 无关失败：`test_n1_wave_config.lua`当前失败于既有“W5起领头怪必须排首位”断言，目标CSV/生成波次数据不在本轮diff中，未为内存任务改数据或测试。尚未完成Workshop Tools实机内存验证，也尚未证明V8泄漏根因完全消除。
- 下一步实机清单：完全停止并重新Run，先召唤英雄并观察至少10秒，确认不再出现`active is not defined`、`refreshOfficialReturnHomeHotkey is not defined`或立即退出，并保存`startup_1s/startup_5s`样本；再冷启动N1连续运行到至少W20，低选择活动跑一轮，高频切换英雄/建筑/怪物并反复悬停技能再跑一轮。逐波保存两类`SURVIVAL_MEMORY`日志，重点比较`wave_cleared`的Lua KiB基线、scheduler/visuals是否回落、Panorama pending/peak/proxies/inventory是否有界，并检查`game/bin/win64`是否新增`V8_hiting_max_memory_limit__512_MB`转储。

## 当前插入任务（2026-08-08）：多选箭塔跨路线批量升级

- 用户最终确认Q/W都需要批量：Q=`ability_upgrade_tower_lv01`按各塔下一等级费用；W=`ability_upgrade_tower_max`按各塔直升当前阶段最高级的累计费用。基础箭塔与不同转职路线可以混选，各塔沿自身路线升级。
- 箭塔候选只要求共同`survival_building_id == "arrow_tower"`，不得再按`survival_tower_class`排除跨路线候选。普通建筑仍按同一`building_id`匹配；转职、融合、金矿科技/自动升级、训练等非Q/W入口不参与。
- `ability_tooltip.js`与`combat_stats.js`现向`ui_ability_cast_request`附带最多64个去重选择候选。客户端列表不具权威性；服务端逐塔校验存活、owner、建筑ID、对应Q/W Ability及可施放状态。
- `building_upgrade_system`新增只读权威报价request：Q返回下一等级目标与费用，W返回当前阶段末目标与累计费用；报价不扣费、不启动升级、不修改冷却。协调器按木材升序、金币升序、entindex升序排列候选。
- 轮到每塔时重新校验并提交既有`BUILDING_UPGRADE_REQUEST`，由现有`RESOURCE_TRY_SPEND_REQUEST`原子扣费。失败只跳过并继续，已成功项目不回滚；仅正式升级成功受理后启动该塔对应Ability冷却。
- 自动验证通过：`BUILDING_BATCH_UPGRADE_LUA51_PASS`、`BUILDING_BATCH_UPGRADE_CONTRACT_PASS`、目标`luac5.1 -p`、升级流程/塔Runtime/人口配置回归、配置CheckOnly、严格UTF-8和两仓`diff --check`。两个Panorama JS均由Resource Compiler强制编译为`1 compiled, 0 failed, 0 skipped`。
- 既有`test_building_state_recovery.lua`在加载未修改的BOM版`building_system.lua`首字节时被裸Lua 5.1拒绝，未进入本任务代码；没有为迎合该无关编码问题改写生产文件。尚需Workshop Tools冷启动实测跨路线Q/W、部分资源、鼠标/快捷键与多人owner隔离。

## 当前插入任务（2026-08-08）：多选金矿Q/W/E与自动升级批量协调

- 用户最终要求：全选多座金矿时，Q按每矿权威下一等级费用逐矿升级；W/E是玩家共享科技，一次批量请求只购买1级；自动升级按钮按明确目标状态批量开启或停止，混合状态下已处于目标状态的金矿幂等跳过。
- 生产实现完成：新增`gold_mine_batch_upgrade_service.lua`。客户端沿用现有最多64个去重`selected_entindexes`载荷；服务端重新验证存活、owner、`gold_mine`身份、对应Ability、升级中和可施放状态。Q先读取`gold_mine_system`只读报价，按木材、金币、entindex升序逐矿调用原升级事务；失败继续，成功受理后才冷却。
- W/E只从请求发生前的有效候选中选择entindex最小金矿作为购买来源，调用一次现有`TECHNOLOGY_PURCHASE_NEXT_REQUEST`原子扣费/发放；成功后对全部有效候选同步对应Ability冷却，失败不冷却。批量服务只发一次汇总通知，商店请求使用显式静默标志避免重复提示。
- 自动升级底层兼容旧单矿toggle，同时接受`enabled=true/false`明确状态。批量开启/停止不会对已处于目标状态的矿反向切换；同一玩家全部自动矿中entindex最小者协调共享科技购买，其他自动矿继续独立升级本体并等待协调者，科技缓存只由权威`TECHNOLOGY_CHANGED`更新。
- 自动验证通过：`GOLD_MINE_BATCH_UPGRADE_LUA51_PASS`、`GOLD_MINE_AUTO_COORDINATOR_LUA51_PASS`、`GOLD_MINE_BATCH_UPGRADE_CONTRACT_PASS`、箭塔批量回归、四项商店/研究科技回归及目标Lua 5.1语法。Panorama协议未修改，因此未重新编译JS。尚需Workshop Tools冷启动实测鼠标按钮、Q/W/E快捷键、部分资源、混合自动状态和多人owner隔离。

## 当前插入任务（2026-08-08）：金矿升级后固定模型尺寸

- 用户实测金矿升级后模型尺寸恢复原状，要求直接固定模型大小。
- 根因确认：金矿升级由`gold_mine_system.lua`独立提交，`gold_mine_config.level_data()`只返回`building_levels.csv`等级行；各级虽有相同`model_name`，但没有`model_scale`，因此升级时`building_visual.apply()`拿不到权威`0.34`。
- 实施边界：继续以`building_visual_levels.csv`的金矿视觉行为权威，不向30行等级CSV重复写缩放；由`gold_mine_config`把固定视觉字段投影到所有等级，保证手动/自动升级每次提交都重新应用`radiant_ancient001.vmdl / 0.34`。不修改收益、费用、生命、护甲、技能或升级时序。
- 生产实现完成：`gold_mine_config.lua`读取生成的`building_visual_levels.lua`，选择启用的金矿LV1视觉行，并在`level_data()`中把`model_asset_id/model_name/model_scale/model_yaw`投影到每个金矿等级。既有手动/自动升级提交继续统一调用`building_visual.apply()`，每次完成后都会重新设置`radiant_ancient001.vmdl / 0.34`。
- 自动验证通过：`GOLD_MINE_FIXED_VISUAL_LUA51_PASS`、`SIX_GAMEPLAY_FIXES_LUA51_PASS/CONTRACT_PASS`、相关Lua 5.1语法、视觉CSV与生成Lua逐字节一致、严格UTF-8及限定`git diff --check`。
- 尚未Workshop Tools实机验收。需完全停止并重新Run后连续升级金矿，确认模型和0.34尺寸不再恢复，同时核对手动/自动升级、收益和技能无回归。

## 当前插入任务（2026-08-08）：金矿替换为可选中动态建筑模型

- 用户实测当前金矿无法通过鼠标选择。静态审计确认`building_gold_mine`运行配置已有`selectable=true`，没有金矿专属`MODIFIER_STATE_UNSELECTABLE`；问题集中在当前`tower_good4.vmdl`缺少可靠单位选择命中边界，而不是建筑Hull或业务选择开关。
- 用户已批准将金矿完工模型替换为项目已确认可选中的`models/props_structures/radiant_ancient001.vmdl`，模型缩放为`0.34`；施工视觉同步使用`0.34`，避免完工时尺寸跳变。
- 修改边界：保留金矿现有建筑ID、单位ID、技能、等级、收益、成本、人口占用、数量上限和存档身份；不引入选择代理，不通过修改Hull冒充选择修复。
- 权威源必须先修改`building_visual_levels.csv`和`building_construction_rules.csv`，再定向重建生成Lua；`npc_units_custom.txt`只同步首帧/异常回退模型与缩放。
- 生产实现完成：金矿视觉CSV与施工规则CSV均改为`radiant_ancient001.vmdl / 0.34`，两份生成Lua通过项目生成器定向重建；`npc_units_custom.txt`同步首帧/异常回退模型与缩放。金矿现有`selectable=true`及全部业务身份和数值保持不变。
- 自动验证通过：`SIX_GAMEPLAY_FIXES_CONTRACT_PASS`、`SIX_GAMEPLAY_FIXES_LUA51_PASS`、`UNIT_MODEL_CONFIG_LUA51_PASS`、两份生成Lua逐字节一致、相关Lua 5.1语法、严格UTF-8和限定`git diff --check`。`building_system.lua`保留既有UTF-8 BOM，使用临时去BOM副本完成语法检查，未重写生产编码。
- 全局单位模型旧契约在更新过时的`tower_good4`要求后，仍只失败于任务前已知的无关伐木工CSV缺项`creep_bad_melee_cavern_mega.vmdl`；本任务未修改无关伐木工数据迎合测试。
- 尚未Workshop Tools实机验收。必须完全停止并重新Run后，确认完工金矿可通过鼠标点击模型主体选中、五个技能正常显示，且施工/完工尺寸、收益、升级、血条、上限和人口占用无回归。

## 已完成待实机验收（2026-08-12）：死亡/闪电/激光/防空塔阶段饰品与凤凰激光

- CSV权威源已更新：死亡塔一阶段使用Templar Assassin `Darkblade Adept`四件套；闪电二阶段使用基础Leshrac，三阶段使用Razor `Voidstorm Asylum` Arcana主体与五件套；激光三阶段依次使用Keeper of the Light `Forgotten Renegade`、Outworld Destroyer `Blackgate Sentinel`、Phoenix基础主体加`Solar Forge`头和`Solar Gyre`翅膀；防空三阶段依次使用Gyrocopter `Swooping Elder`、Batrider `Empiric Incendiary`、Skywrath Mage至宝`The Devotions of Dragonus`第二分支“天怒一族尊主”。
- `items_schinese.txt`与`items_game.txt`交叉确认：劫烧狂客为`Empiric Incendiary` Bundle 21239；天怒目标为Bundle 22277“倾天之战：扎贡纳斯的献身”，核心翅膀物品18539负责替换`skywrath_arcana.vmdl`主体，Style Unlock 27601解锁style 1 / skin 1。空域霸主现使用至宝主体、18539-18544六件组件、第二分支常驻粒子与`skywrath_arcana_base_attack_v2.vpcf`弹道；旧版将其误判为单件`Empyrean`（物品6892）的结论已作废。
- 闪电链`lightning_strike_lv01-lv05.area`统一为500；雷暴`lightning_storm_lv01-lv05.area`统一为300，并同步描述。保留任务前已有的闪电塔全阶段`base_attack_speed=2`及其余物理伤害/技能链修改。
- `tower_laser_effects.csv`改用`effect_key`索引，保留五条技能默认Tinker Laser行，并增加`laser_lv05:tower_laser_phoenix_solar`；运行时按`skill_id + survival_model_asset_id`优先选择，找不到时回退技能默认，因此只有Phoenix阶段使用Solar Forge Sun Ray。
- Phoenix激光继续同步CP9/CP0源点与CP1目标点；本机资源定义没有要求额外控制点，因此未扩展未经验证的控制点逻辑。新增八个精确主体预载代理，组件和粒子继续由资源子表预载链负责。
- `tools/build_configs.py`成功生成84个Lua配置模块。自动验证通过：`ASSET_BUNDLE_CONFIG_PASS`、`TOWER_LIGHTNING_VISUAL_PASS`、`DEATH_TOWER_TEMPLAR_VISUAL_PASS`、`ANTI_AIR_TOWER_LUA51_PASS`、`TOWER_STAGE_VISUAL_ROUTES_PASS`、`TOWER_SKILL_GEOMETRY_PASS`、`ANTI_AIR_TOWER_CONTRACT_PASS`、`RESOURCE_PATH_CHECK_PASS`、`LIGHTNING_RANGE_CONTRACT_PASS`、`PHOENIX_LASER_CONTRACT_PASS`、相关Lua 5.1语法与`git diff --check`。
- 路线Gameplay列对比：死亡、激光、防空除模型字段外0差异；闪电仅保留任务开始前已有的20条攻速`1 -> 2`差异。本轮未修改其他塔数值、伤害、眩晕、光环、费用、人口或升级逻辑。
- 天怒至宝纠正专项验证通过：`ASSET_BUNDLE_CONFIG_PASS`、`TOWER_STAGE_VISUAL_ROUTES_PASS`、`ANTI_AIR_TOWER_LUA51_PASS`、`ANTI_AIR_SKYWRATH_CSV_CONTRACT_PASS`、`ANTI_AIR_GAMEPLAY_COLUMNS_UNCHANGED_PASS`、`SKYWRATH_ARCANA_STYLE1_RESOURCE_PATH_PASS`（主体、六件组件、四个粒子共11条VPK资源）、相关Lua 5.1语法及`git diff --check`。未跟踪的旧`tools/test_anti_air_tower_contract.ps1`在Windows PowerShell 5.1中因无BOM UTF-8中文路径被误解码，于`Import-Csv`前失败；其数值契约由Lua测试和独立CSV列对比覆盖，本次未修改该无关脚本。
- 尚未Workshop Tools冷启动实机验收。需要完全停止并重新Run，逐阶段确认组件骨骼合并、模型尺寸、动作、头像、升级换模，以及Phoenix Solar Forge Sun Ray的源点、目标点、持续重播和停止攻击/目标死亡时清理。

## 当前插入任务（2026-08-08）：城墙升级增加最大生命差值

- 用户确认新语义：升级完成时计算`最大生命增量=新最大生命-旧最大生命`，并令`新当前生命=旧当前生命+最大生命增量`。例如`100/200`升级到最大生命`400`，最终为`300/400`，不再保持旧生命百分比。
- 修改范围仅限城墙；主城、农场和防御塔继续保持既有升级行为。存活城墙结果夹紧到`1..新最大生命`，升级过程中的受伤必须计入提交瞬间的旧当前生命。
- 根因是上一版`building_health_projection.lua`按生命百分比投影。城墙提交路径现捕获即时当前/最大生命，并把等级数据与当前科技重算后的最终实际最大生命一并纳入增量计算；不修改`building_levels.csv`权威数值。
- 生产实现完成：`apply_maximum_health_increase()`以最终实际最大生命差值增加当前生命；其他建筑未接入该投影。专项行为测试和契约测试覆盖`100/200 -> 300/400`、满血、1血、无增量、合法夹紧、科技后最终上限及城墙专用边界。
- 自动验证通过：`WALL_UPGRADE_HEALTH_LUA51_PASS`、`WALL_UPGRADE_HEALTH_CONTRACT_PASS`、`WALL_UPGRADE_HEALTH_LUAC51_PASS`、全项目351个生产Lua的Lua 5.1语法检查、修理工百分比行为/契约回归、严格UTF-8及限定`git diff --check`。任务前未跟踪的旧`test_building_upgrade_contract.ps1`仍失败于其过时断言要求`local duration`，而当前HEAD一直使用等价的`state.duration`；升级流程生产文件与HEAD一致，本轮未修改该无关测试迎合。仍需Workshop Tools实机验收残血城墙升级后的实际血条数值。

## 已完成并经用户确认（2026-08-08）：人口训练按CSV阶段内次数顺序推进

- 用户确认`training_definitions.csv`原始人口训练数据正确：人口训练1至5各可成功使用5次，人口训练6可成功使用100次且保持启用；上一轮将前五阶段改为各1次并禁用第六阶段属于错误修改，必须恢复原始CSV并定向重建生成Lua。
- 已定位原始运行时根因：`train_population_auto`曾使用`math.max(2, farm_level + 1)`选择训练ID，导致人口训练1永远不加载，并错误地由农场等级直接跳选阶段。
- 目标行为：按启用CSV行的`level`顺序选择第一个未达到自身`max_count`的阶段；当前阶段达到上限后才加载下一阶段。计数按team共享、按`training_id`独立保存；农场等级只校验当前阶段前置条件，不负责跳阶段。
- 服务端扣费和Tooltip费用均使用`wood_cost/gold_cost + 当前阶段成功次数 * 对应increment`；扣费失败不得推进次数或增加人口。人口训练6达到100次后才进入全部完成状态。
- 实现及自动验证完成：CSV与生成Lua已恢复原始权威数据；`worker_system.lua`按阶段独立次数顺序推进，Tooltip投影阶段内进度和递增费用；专项Lua 5.1、PowerShell契约、相关回归、Lua语法和生成一致性均通过。
- 用户于2026-08-08明确反馈“问题已经解决了”，人口训练首次加载、阶段内次数和顺序推进修复记为用户实机验收通过；该人口训练问题不再作为活跃任务恢复。此确认不代表城墙锚点或其他组合项目已验收。

## 已纠正的旧结论（2026-08-08）：城墙固定锚点与人口训练阶段

- 已确认行为：城墙施工完成后固定在初始位置；碰撞或物理推移必须恢复；已有主动迁移继续可用，且每次成功迁移后以新位置作为固定锚点。
- 人口训练上一轮“全局五次、禁用阶段6”的结论已被用户明确纠正，不再有效；以本文顶部“按CSV阶段内次数顺序推进”为准。
- 原始CSV数据保持阶段1至5各5次、阶段6共100次且启用；运行时按阶段独立计数并满额后顺序推进。
- Tooltip Runtime动态发布当前阶段、阶段内进度、本次递增费用、人口增加、本次条件和下一阶段农场等级要求；所有CSV阶段完成后`available=0`、`can_afford=0`。Panorama继续使用已有托管白名单。
- 城墙完工和热恢复路径均设置`survival_fixed_position`并复用`modifier_building_stationary`周期恢复偏移；主动迁移在移动前更新该锚点，原有网格释放/占用和移动Ability保留。
- 自动验证通过：`POPULATION_TRAINING_LUA51_PASS`、`WALL_POSITION_ANCHOR_LUA51_PASS`、`POPULATION_WALL_CONTRACT_PASS`、`SIX_GAMEPLAY_FIXES_LUA51_PASS/CONTRACT_PASS`、修理工契约、Builder槽位回归、目标Lua 5.1语法、训练配置定向生成逐字节一致、严格UTF-8和限定`git diff --check`。`ability_tooltip.js`经Resource Compiler强制编译为`1 compiled, 0 failed, 0 skipped`。
- Node不在PATH，未执行`node --check`；正式Panorama Resource Compiler已完成语法/资源编译验证。生产建筑Lua原有UTF-8 BOM由测试临时内存去除后完成Lua 5.1行为/语法验证，没有重写既有文件编码。
- 人口训练已由用户确认解决。尚未Workshop Tools实机验收的范围仅保留：怪物或单位碰撞压力下城墙不漂移，以及主动迁移后固定在新位置。
- 无关阻断保持不变：单位模型旧契约仍引用缺失的`creep_bad_melee_cavern_mega.vmdl`，本任务未修改该数据。

## 插入活跃任务（2026-08-07）：城墙与怪物Hull调试、普通建筑原生模型尺寸

- 用户确认城墙基础Hull应直接为256；现有`scale`继续只调整选中己方城墙Hull，因此目标语义为`scale 1=256`，不改变模型。
- 已核对波次怪共用单位KV已有`BoundsHullName=DOTA_HULL_SIZE_SMALL`，当前并非无碰撞；怪物CSV没有Hull字段且生成链没有`SetHullRadius()`覆盖。新增`scalemonster <倍数>`只改变当前存活及之后生成波次怪的Hull，倍率1恢复每只怪首次读取到的原生Hull，禁止累计且不改变模型。
- 用户最新要求：研究所和人口农场的预建造模型、实际模型都与英雄祭坛相同，统一使用`radiant_ancient001.vmdl`和`ModelScale=0.34`；金矿保持上一要求的原生模型缩放1。
- 用户最新实测确认怪物碰撞体：普通小怪Hull 32，精英怪Hull 64，Boss无碰撞体。`scalemonster <倍数>`以这三个角色基准为准，不累计；Boss基准为0，任何正倍率仍无碰撞。
- 生产实现与自动验证已完成：城墙基础Hull为256；研究所/农场CSV施工视觉、运行视觉、生成Lua与KV回退均与英雄祭坛为0.34；新增角色Hull应用与`scalemonster`命令作用于当前及后续波次怪。
- 验证通过：`SIX_GAMEPLAY_FIXES_LUA51_PASS`、`SIX_GAMEPLAY_FIXES_CONTRACT_PASS`、`BUILDER_ABILITY_SLOTS_LUA51_PASS`、`UNIT_MODEL_CONFIG_LUA51_PASS`、`WAVE_TIMING_LUA51_PASS/WAVE_TIMING_CONTRACT_PASS`、`TASK_LUAC51_PASS count=6`、`BUILDING_VISUAL_BYTE_MATCH_PASS`、`TASK_STRICT_UTF8_PASS files=12`及限定`TASK_DIFF_CHECK_PASS`。
- 既有`test_unit_model_config_contract.ps1`仍只失败于本任务之前已知的无关伐木工模型CSV缺项`models/creeps/lane_creeps/creep_bad_melee/creep_bad_melee_cavern_mega.vmdl`，未修改无关数据迎合。
- 尚未Workshop Tools验收：确认默认城墙Hull 256的堵路效果；依次使用`scalemonster 1`及若干倍率观察怪物拥挤/穿行并记录通知中的原生/当前Hull；确认研究所、农场、金矿原生模型视觉尺寸。自动测试不能称为实机验证。

## 插入活跃任务（2026-08-07）：建筑、金矿反馈、城墙碰撞与波次首发规则

用户批准同时实施以下六项修复；本任务优先于下方多人阶段1待验收动作，但不得提前开展多人阶段4状态迁移：

1. 金矿模型缩放曾改为当前 `0.35` 的四分之一，即 `0.0875`；该历史目标已被上方用户最新“恢复模型原生缩放1”要求取代。
2. 金矿产出关闭原生金币飘字自带声音，但保留无声自定义金币飘字；普通与暴击均不得播放金币音效。
3. 农场最多建造1座；金矿最多建造5座；达到各自上限后从Builder移除对应建造技能，建筑销毁释放名额后允许恢复技能。
4. 聊天命令 `scale <number>` 调整当前选中的己方城墙Hull倍率；`1`为首次捕获的基础碰撞半径，`2`为两倍，模型外观不变。
5. 每波按 `assault_boss -> wave_leader -> normal` 生成；CSV `spawn_order` 为权威，不新增或删除任何成员，不改变数量、属性与时间字段。
6. 农场建造Tooltip显示权威首级成本：100木材、0金币，并移除“可重复建造”的错误说明。

### 已确认实现边界

- 当前金矿KV `ModelScale=0.35`，目标为 `0.0875`。
- 金矿产出声音来自 `SendOverheadEventMessage(... OVERHEAD_ALERT_GOLD ...)`，该接口无法单独静音；用户选择新增Panorama无声飘字。
- `building_definitions.csv`与当前生成Lua中的农场 `max_count` 已为1；错误仍存在于Builder阶段 `max_building_count=0`、旧说明及技能同步行为。
- 当前波次运行排序硬编码为 `wave_leader -> normal -> assault_boss`，必须停止覆盖CSV顺序。
- 当前多人建筑计数仍按team，本轮保持现状；不得借本任务扩大为未批准的多人阶段4重构。
- 工作区基线包含大量既有未跟踪 `tools/test_*` 文件，必须保留且不得清理、覆盖或纳入本轮修改。

### 验证要求

- 建筑/Builder/Tooltip/金矿飘字/城墙Hull/波次顺序专项PowerShell契约与Lua 5.1行为测试。
- CSV定向生成与生成Lua逐字节一致性；相关Lua `luac5.1`语法检查。
- Panorama JS/CSS与HUD XML强制编译，要求 `compiled > 0`、`failed=0`。
- 严格UTF-8、限定范围 `git diff --check`、最终文件复读与双仓库状态检查。
- 自动测试与资源编译不能称为Workshop Tools实机验证；金矿尺寸、无声飘字、技能移除、Hull碰撞和实际出怪顺序仍需冷启动实机验收。

### 实施状态（2026-08-07）

- 生产实现与自动验证已完成，尚未Workshop Tools实机验收。
- 金矿无声收入飘字实现保持不变；本段原有`tower_good4.vmdl / 0.0875`视觉结果已被上方最新原生缩放1要求取代。
- 农场运行上限和Builder阶段上限均为1，金矿为5；达到数量上限时移除对应Ability，`BUILDING_DESTROYED`释放名额后按原槽位恢复。等级不足等非数量条件继续使用原有置灰语义。
- `scale`的选择同步、服务端所有权验证与`0.25..4`范围保持不变；本段原有基准Hull 128已被上方最新基准256要求取代，仍不改变模型。
- 波次CSV共426个成员，仅335个`spawn_order`发生变化，按wave_id比较确认其他字段0变化；145个难度波次组均按`assault_boss -> wave_leader -> normal`。运行Builder停止按角色硬编码覆盖CSV。
- Tooltip生成器从建筑CSV映射建造技能，再从`building_levels.csv`投影首级成本；农场运行Tooltip与本地化均显示100木材、0金币。
- 自动验证通过：`SIX_GAMEPLAY_FIXES_LUA51_PASS`、`SIX_GAMEPLAY_FIXES_CONTRACT_PASS`、`BUILDER_ABILITY_SLOTS_LUA51_PASS`、`SIX_GAMEPLAY_FIXES_LUAC51_PASS count=8`、`WAVE_CSV_FIELDS_AND_ORDER_PASS rows=426 groups=145 changed_orders=335`、`TARGET_GENERATED_BYTE_MATCH_PASS count=4`、`TASK_STRICT_UTF8_PASS files=30`、`WAVE_TIMING_LUA51_PASS/WAVE_TIMING_CONTRACT_PASS`、Python工具语法、Tooltip幂等生成和双仓`diff --check`。
- Resource Compiler：新JS与CSS各`1 compiled, 0 failed, 0 skipped`，HUD XML链`9 compiled, 0 failed, 0 skipped`；依赖链自动改写的无关既有产物已按用户授权恢复，只保留本任务三个目标产物。
- 旧未跟踪N1/N2/N3/N4-N5波次测试仍断言leader首发或assault boss末发，与本轮批准需求直接冲突，未覆盖用户已有测试；本轮专项行为测试覆盖五个难度的新顺序。既有单位模型契约另失败于无关伐木工模型CSV缺失，本轮未修改无关配置。
- 待实机：金矿尺寸改按上方最新“模型原生缩放1”验收；普通/暴击产出有数字且完全无金币音效；第1农场/第5金矿后技能消失且销毁后恢复；选中己方墙执行`scale 1/2/0.5`的真实寻路碰撞且模型不变（当前基准256）；进攻Boss、领头、普通实际首发顺序；农场Tooltip视觉成本。

## 活跃任务（2026-08-06）：多人联机系统

### 用户确认的玩法

- 目标支持最多4名玩家；第一轮先做2人纵向切片，再扩展到4人。
- 所有玩家属于好人方，但每名玩家拥有独立的经济、人口、建筑、Builder、英雄、科技、成长状态和一套波次怪物。
- 战场空间共享，玩家初始区域按东南西北等固定槽位配置；区域只决定出生位置，不决定业务归属。
- 玩家可以把自己的城墙建到其他玩家区域，与其他城墙集中防守。这是允许的玩家策略，不应被区域限制阻止。
- 每批怪物绑定其所属玩家，并始终攻击该玩家自己的城墙实体；不得按最近城墙、固定区域或最后创建的城墙选目标。
- 英雄允许跨区域支援其他玩家并攻击其他玩家所属的波次怪。
- 玩家不能控制他人的英雄、Builder、工人、建筑、防御塔、召唤物或其他可控单位。
- 所有客户端只提交操作意图；资源、建造、波次、伤害、奖励和胜负由服务端权威结算。Dota 2引擎负责同步实体、位置、生命、Modifier、攻击和投射物，不另做客户端独立模拟或lockstep。

### 核心身份边界

- `player_id`：资源、建筑、单位、怪物、挑战和奖励的业务归属权威。
- `slot_id/lane_id`：玩家初始出生点和波次出生点，只表示地图槽位。
- `team`：仅表示Dota敌我阵营；不能继续作为玩家经济、建筑上限、Builder阶段或波次状态的唯一键。
- 单位归属和单位当前位置必须分离。移动到别人区域不会改变owner。
- 客户端payload中的`player_id`不可信；Custom Game Event必须从事件来源获得真实玩家身份，并校验caster、ability、target和业务状态归属。

## 多人联机任务清单

### 阶段1：多人配置、玩家上下文与身份基础（进行中）

#### 生产改造

- [x] 新增CSV权威多人规则，配置最大玩家数、初始实现人数、共享波次时钟、英雄跨区支援等长期规则。
- [x] 新增CSV权威玩家槽位，配置`player_id`、`slot_id`、Builder出生marker、波次出生marker、旧地图回退和启用状态。
- [x] 生成对应Lua配置，禁止直接手改生成文件。
- [x] 新增`player_context_service`，统一提供玩家槽位、marker解析、单位owner登记、owner查询和ownership校验。
- [x] `addoninfo.txt`和启动规则改为最多4名好人方玩家；保持坏人方玩家数为0。
- [x] Builder创建改为按玩家槽位解析出生点，并继续设置`SetPlayerID`、`SetOwner`、`SetControllableByPlayer`和`survival_player_id`。
- [x] 玩家0允许旧地图坐标兼容回退；玩家1至3缺少marker时必须失败关闭并输出明确日志，禁止全部叠在`(0,0)`。
- [x] 保持单人旧地图可启动，阶段1不宣称独立经济、独立波次或完整联机已完成。

#### 自动验证

- [x] PowerShell契约：CSV、生成Lua、最大玩家数、服务初始化和Builder接入一致。
- [x] Lua 5.1行为：4个槽位、marker优先、玩家0旧回退、非0玩家缺marker失败、owner登记和跨玩家拒绝。
- [x] `luac5.1`语法检查。
- [x] CSV与生成Lua逐字节一致性。
- [x] 严格UTF-8和限定`git diff --check`。

#### Workshop Tools验收

- [ ] 单人冷启动保持正常，玩家0 Builder仍能生成和建造。
- [ ] 地图加入玩家1 marker后，两客户端分别生成在自己的槽位。
- [ ] 日志能看到每名玩家的`player_id/slot_id/builder_spawn_marker/entindex`。

### 阶段2：两人纵向切片

- [ ] Hammer地图增加至少2套Builder出生marker和波次出生marker；最终预留4套。
- [ ] 两名玩家分别生成占位英雄、Builder和初始UI。
- [ ] 两人可同时建墙、主城和箭塔，状态不互相覆盖。
- [ ] 两人无法通过鼠标、快捷键、框选或原生命令控制对方单位。
- [ ] 双方资源显示与服务端状态一致。
- [ ] 完成两客户端Workshop Tools实机验收后再进入全面状态迁移。

### 阶段3：统一服务端命令权限

- [ ] 将现有树木攻击Order Filter迁入唯一组合`ExecuteOrderFilter`，避免多个模块互相覆盖。
- [ ] 对移动、攻击、停止、巡逻、施法、拾取、丢弃和多单位命令检查全部命令单位的owner。
- [ ] 审计全部Custom Game Event入口，统一从事件来源取得PlayerID。
- [ ] 校验客户端传入的entindex、ability、target、位置、session和请求顺序。
- [ ] 增加伪造他人单位、混合编队、迟到请求和重复请求测试。

### 阶段4：个人经济、建筑与成长状态

- [ ] 资源账户从`accounts[team]`迁为`accounts[player_id]`：金币、木材、人口和人口上限全部独立。
- [ ] Builder阶段从`state_by_team`迁为`state_by_player`。
- [ ] 建筑数量、城墙一次性状态、主城等级和建筑上限按玩家计算。
- [ ] 工人训练、金矿、科技等级和研究事务按玩家隔离。
- [ ] 塔升级、转职、科技加成和七塔融合只消费同一玩家的塔。
- [ ] 回城查找玩家自己的主城，不再使用`main_city_for_team()`。
- [ ] UI快照和NetTable key按玩家投影；客户端资源快照仍无服务端否决权。

### 阶段5：每玩家独立波次实例

- [ ] 全局单例`wave_system`拆为`state_by_player/enemies_by_player/wall_by_player/spawn_marker_by_player/generation_token_by_player`。
- [ ] 每名活跃玩家每波生成独立的一份怪物。
- [ ] 第一版使用全局统一难度和统一波次开始时钟，个人保存计划数、已生成、存活、击杀和失败状态。
- [ ] 每只怪保存`survival_wave_player_id`、波次号和目标城墙身份。
- [ ] 怪物只追踪所属玩家的城墙实体；城墙建在其他区域或与他人城墙重叠时仍保持正确目标。
- [ ] 城墙销毁、重建、移动和实体失效时更新该玩家怪物目标，不影响其他玩家。
- [ ] 波次UI展示本地玩家状态，并可按需求展示队友概要。

### 阶段6：失败、胜利、支援和奖励归属

- [ ] 某玩家城墙死亡后只淘汰该玩家、停止其后续波次并清理其波次怪；其他玩家继续。
- [ ] 所有玩家淘汰时失败；所有仍活跃玩家完成最终波次时胜利。
- [ ] 英雄可自由跨区域支援，不改变单位owner。
- [ ] 基础波次经济建议归怪物所属玩家，避免支援抢最后一击破坏其经济。
- [ ] 击杀成长、装备触发和支援奖励另行明确，必须通过CSV配置后实施。

### 阶段7：挑战、商店、装备与UI多人回归

- [ ] 审计转生、十戒、练功房、特殊挑战和同一挑战并发规则。
- [ ] 审计地面掉落、Claim、背包、装备实例、合成和成长归属。
- [ ] 审计英雄召唤、技能选择、商店购买、科技、通知、Tooltip和自定义NetTable。
- [ ] 同一`encounter_id`如允许多人同时开启，运行身份必须包含player/session，不能继续全局唯一覆盖。
- [ ] Custom Net Tables只用于客户端可读UI快照，不存放需要保密的数据或高频操作日志。

### 阶段8：四人、掉线重连、性能和最终回归

- [ ] 从2人扩展到4人并完成东南西北槽位。
- [ ] 玩家加载速度不同、掉线、重连和永久退出均有明确生命周期。
- [ ] 重连恢复自己的Builder、英雄、建筑、资源、波次和UI。
- [ ] 多人同帧建造、扣费、研究、挑战和奖励事务保持原子与幂等。
- [ ] 检查4份波次实体量、投射物、Modifier、NetTable和Panorama性能。
- [ ] 完成两台或多台真实客户端实机验收；Mock和单机多实例不能替代最终网络验收。

## 编辑器联机验收方案

- 不需要先发布Workshop。开发地图可以在Workshop Tools中由主机启动本地服务器/大厅，其他Steam客户端加入。
- 推荐使用两台电脑、两个Steam账号、同一局域网；两台机器都安装相同Dota 2 Workshop Tools和完全一致的addon内容/编译产物。
- 主机通过Workshop Tools启动addon和`template_map`；客户端使用Steam好友加入、开发大厅或控制台`connect <主机局域网IP>:27015`，具体可用入口以当前Dota版本实测为准。
- 主机防火墙需允许`dota2.exe`，必要时开放UDP/TCP 27015；不得把能进入地图误认为业务联机验收通过。
- 一台电脑多客户端只适合辅助检查，需要多Steam实例/账号且性能与输入焦点限制明显；最终验收仍建议两台电脑。
- 每轮联机测试必须确认两端使用相同文件版本，并分别保存服务端控制台日志和客户端截图/录像。

## 当前检查点

- 当前插入任务：区域生产实现与自动验证完成，真实Hammer边界坐标缺失导致CSV保持空业务行；运行时按批准策略失败关闭，尚不能Workshop Tools实机验收。
- 当前阶段：阶段1生产实现与自动验证完成，等待Workshop Tools单人冷启动验收。
- 当前地图源存在`template_map.vmap`和`survival_dev.vmap`，运行产物为`maps/template_map.vpk`。
- 已确认旧地图只有单个历史波次marker `monsterborn`；尚未确认4套玩家marker。
- 当前启动规则和`addoninfo.txt`已开放4名好人方玩家；后续玩家由`player_connect_full`分配到好人方。
- 旧`CURRENT_TASK.md`和旧`START_HERE.md`已完整归档到`docs/ai/archive/2026-08-06-pre-multiplayer-*.md`；旧任务全部暂停，不得自动恢复。
- 工作区已有大量未跟踪测试文件，属于用户既有内容，本任务不得覆盖、清理或纳入交付。

## 下一步唯一动作

先进行Workshop Tools冷启动区域实机验证，确认空配置下Grid显示和合法建造恢复、非法区域仍显示红格。Hammer真实边界取得后再更新权威CSV并定向生成，以启用严格白名单；多人阶段1保持暂停，等待当前插入任务实机结果。
## 阶段1自动验证记录（2026-08-06）

- `MULTIPLAYER_CONTEXT_CONTRACT_PASS`：CSV、生成Lua、服务接入和4人启动契约通过。
- `MULTIPLAYER_CONTEXT_LUA51_PASS`：4槽位、marker优先、玩家0旧回退、非0缺marker失败、owner冲突和跨玩家拒绝通过。
- `MULTIPLAYER_BUILDER_INTEGRATION_LUA51_PASS`：玩家0 Builder旧地图生成、CSV移速保持、owner登记和玩家1缺marker拒绝通过。
- `MULTIPLAYER_LUAC51_PASS`：本轮Lua生产文件、生成文件和专项测试语法通过。
- `MULTIPLAYER_GENERATED_CONFIG_MATCH_PASS`：两份CSV临时重生成结果与提交生成Lua逐字节一致。

- `MULTIPLAYER_STRICT_UTF8_PASS`和限定`git diff --check`通过。
- 未跟踪既有`test_builder_ownership.lua`失败于硬编码期望Builder移速600，而当前权威CSV和生成Lua均为300；本轮未修改移动速度逻辑。
- 未跟踪既有`test_builder_utility_contract.ps1`失败于`MONKEY_CSV_RANGE_1000_MISSING`；与本轮多人身份改造无关，未修改该测试或Monkey配置。
- 尚未执行Workshop Tools实机验证，不能称为联机或单人实机验收通过。

## 玩家档案实机诊断补充（2026-08-12）

- 玩家档案公开投影成功后打印`[Survival][INFO][PlayerProfile] public_profile_published ...`，字段包含Fixture `provider_id/player_id/account_id`、`revision`及公开白名单`title_id/achievement_score/vip_badge/highest_difficulty`；非Fixture Provider账号日志自动显示`<redacted>`。
- 玩家0预期`mock_account_10001/revision=3/veteran/120/true/N2`；玩家1预期`mock_account_10002/revision=1/rookie/0/false/N1`。
- 专项行为、契约、Lua 5.1语法、严格UTF-8和限定差异检查通过；仍需Workshop Tools冷启动及两客户端实机验收，不能称为实机通过。
- 双机档案隔离可先验收；玩家1 Builder仍因地图缺少`player_1_builder_spawn`按配置失败关闭，不属于档案Provider失败。

- 双机入口审计补充：生产代码当前只设置好人方容量4、坏人方0，未找到显式`SetCustomTeamAssignment()`或自定义`player_connect_full`分队实现；直连验收必须确认第二客户端取得活动`PlayerID=1`。若只进入观战，应使用Hidden/Friends Only大厅选择好人方槽位，或后续单独补充分队逻辑。

## 肉鸽奖励四表运行时检查点（2026-08-17）

- 四表已落地：31张卡、31个效果、38个强类型参数、21条生命周期规则；数值只从CSV生成配置读取。
- enum已覆盖effect type、execution mode、owner scope、target selector、stack policy、event type、predicate、rule role和transition。
- 生成器已增加四表唯一键、外键、enum、参数类型、必需参数、启用卡/效果和生命周期完整性校验，错误失败关闭。
- 通用运行时已实现`grant_id/effect_instance_id/phase_instance_id/target_binding_id`、玩家隔离、幂等、限时到期、事件计数、下一匹配事件、动态binding和多阶段转换。
- effect/event/predicate均通过Lua注册表白名单执行；CSV不接受自由Lua表达式。当前只启用并迁移`防御工事`、`璀璨树苗`、`财政补贴`三个已有准确handler，其余卡保持`enabled=0`。
- Boss奖励不再按最后一击者发放；每次权威Boss死亡遍历`player_context_service.active_player_ids()`，向所有有效好人方在局玩家分别排队。
- 自动验证通过：四表契约和行数、100个生成配置模块加载、Lua 5.1奖励回归、运行时六类机制、有效玩家筛选、相关Lua语法、Python静态编译、UTF-8和`git diff --check`。
- 尚未执行Workshop Tools实机验证，不能称为引擎或多客户端验收通过。下一步应冷启动验证三个启用效果，再以两客户端确认同一次Boss死亡为双方分别创建或排队一次奖励会话。

## 肉鸽指定三卡作弊命令（2026-08-17）

- 聊天输入`rogue <card_id1> <card_id2> <card_id3>`可为发言玩家直接创建指定三卡调试会话；示例：`rogue fiscal_subsidy radiant_sapling fortifications`。
- 三个参数必须是`rogue_reward_cards.csv`中存在且互不重复的`card_id`。指定顺序即UI显示顺序，调试会话不可重抽。
- 调试命令替换当前屏幕offer并使旧token失效，但不清空正式Boss/Builder奖励队列，不消费Builder一次性奖励。
- 调试会话允许重复选择已领取卡，点击仍走正式选择校验、`grant_id`和通用效果运行时，便于重复验证资源或属性效果。
- 31张卡均可强制显示；当前只有`fiscal_subsidy`、`radiant_sapling`、`fortifications`具有启用业务handler。点击其他卡会按运行时契约失败关闭并保留界面，不会伪造效果。

## 肉鸽第二批四卡实现（2026-08-17）

- 已确认实现`frozen_wall`、`recruit_training`、`ion_shield`、`internship_certificate`四张卡，继续以肉鸽四张CSV为业务数值和目标参数权威源。
- `frozen_wall`永久令正式波次怪和建筑挑战怪攻速降低15%（保留85%），覆盖领取时存量与后续生成单位。
- `recruit_training`永久令基础箭塔记录ID`arrow_tower_lv01`至`arrow_tower_lv04`攻击力提高100%；LV5和转职塔无效，升级离开目标集合后移除。
- `ion_shield`令所属城墙经过既有伤害规则后的单次最终伤害不超过最大生命值20%。
- `internship_certificate`通过普通修理工训练事务额外赠送2个`train_repairer_01`，不消耗木材或金币，只消耗每个1人口，并要求原子成功或回滚。
- 四张卡与效果已从CSV启用并生成Lua配置；新增统一怪物生成事件、两个可移除Modifier、城墙最终伤害上限状态查询，以及复用普通训练链路的双修理工原子事务。
- 正式选择的过期token、非法卡和效果执行失败均输出`player_id/source/card_id/token/effect_id/error`结构化服务端日志，失败不消费当前offer。
- 自动验证通过：CSV全量生成99个Lua配置模块、四卡handler专项测试、批量训练事务测试、肉鸽运行时/奖励服务回归、城墙最终伤害过滤测试、Lua 5.1语法、Python编译和`git diff --check`。
- 既有建筑挑战数值测试仍因工作区当前CSV与旧硬编码断言不一致而失败（`manual challenge health invalid`/`CHALLENGE_STATS_INVALID`），失败发生于本轮新增怪物事件之前，本任务未修改该无关数值。
- 尚未执行Workshop Tools实机冷启动，不能称为引擎或多人客户端验收通过。

## 肉鸽第三批五卡实现（2026-08-17）

- 已批准实现`weakening_orb`、`divine_wish`、`tower_growth`、`feast`、`boss_promise`，继续以肉鸽CSV为数值、目标优先级和持续时间权威源。
- `weakening_orb`领取时锁定下一次尚未开始的正式波次；该波优先作用第一个`assault_boss`，若无进攻Boss则作用第一个`wave_leader`，目标基础攻击永久降低50%，命中后消费且无时间到期。
- `divine_wish`立即从玩家当前可用启用卡池按权重无放回抽取3张（排除自身和已领取卡），分别直接授予各自独立效果；子授予使用确定性grant ID支持失败后幂等重试。
- `tower_growth`作用于所有箭塔路线，只在领取后成功完成升级时为对应塔永久累计10%攻击加成，建造、升级开始和科技刷新不计层数。
- `feast`首版只将玩家当前城墙最大生命和当前生命同时翻倍，不实现后续10%阶段。
- `boss_promise`令领取时在场及原始120秒窗口内新生成的所属伐木工获得100%攻速，全部在同一截止点清理；修理工、Builder及其他玩家单位不受影响。
- 已完成五卡CSV启用、生成Lua、运行时handler、怪物波次身份payload、工人增量payload、Modifier注册和奖励服务随机三卡事务。
- `divine_wish`首次执行固定三张抽取结果，子卡使用`parent_grant_id:child:index:card_id`确定性ID；中途失败保留已成功领取状态并在重试时继续原抽取，不会重抽或重复结算成功子卡。
- 新增`tools/test_rogue_five_card_handlers.lua`与`tools/test_rogue_divine_wish_transaction.lua`，覆盖目标波/角色过滤、精英回退、无放回与失败重试、塔升级原因过滤、城墙血量比例和伐木工存量/增量/清理。
- 自动验证通过：CSV生成99个Lua模块、五卡专项、神许愿事务、既有肉鸽运行时/奖励服务/四卡回归、工人批量事务、波次生成顺序、建筑与金矿批量升级契约、本批目标Lua 5.1语法、Python编译和`git diff --check`。
- 全`vscripts` Lua 5.1扫描被6个既有UTF-8 BOM文件阻断（`ability_building_blink.lua`、4个既有建筑Modifier/系统文件及`building_system.lua`）；均在首字节报`unexpected symbol near '�'`，本批未改其编码且未将该全量扫描记为通过。
- 尚未执行Workshop Tools冷启动、正式波次实机、多人客户端或UI验收；自动测试不能替代这些人工验证。

## `weakening_orb`纯普通波领取失败修复（2026-08-17）

- 实机反馈确认开局通过`rogue`调试选择`weakening_orb`时界面不关闭；根因为旧实现只检查紧邻下一波，而第1至第4波CSV均无`assault_boss`或`wave_leader`，handler返回`next_wave_special_target_missing`导致奖励事务失败关闭。
- 已批准改为从下一正式波向后跳过纯普通波，锁定首个含特殊角色的波次；同波仍优先`assault_boss`，否则选择`wave_leader`。开局应锁定第5波进攻Boss。
- 若已经没有后续特殊正式波，卡牌仍领取成功，效果实例立即完成为空效果，不留下永久等待状态。
- 已新增无状态`wave_special_target`查询并由`wave_system`返回独立的`next_special_wave_number/next_special_role`；保留原`next_wave_number`紧邻下一波语义，避免影响既有调用方。
- 新增真实生成波次配置测试：N1开局跳过第1至第4波并锁定第5波`assault_boss`；第5波后锁定第6波`wave_leader`；最终波后返回无目标。运行时测试确认无目标实例以指定原因立即完成且不再接收事件。
- 自动验证通过：真实波次特殊目标测试、五卡handler专项、肉鸽运行时、奖励服务、特殊混合波身份契约、目标Lua 5.1语法及`git diff --check`。

## `feast`城墙升级固定生命增量保留（2026-08-17）

- 实机反馈确认`feast`领取时翻倍正常，但城墙升级会由等级CSV和科技公式重写最大生命，覆盖领取时直接写入的增量。
- 用户明确语义不是后续等级继续翻倍：领取时按当前实际最大生命计算一次固定增加量；后续城墙升级和科技重算结果均为“等级与科技正常生命 + 该固定增加量”。
- 领取瞬间仍同时增加最大生命与当前生命并保持原生命百分比；固定增加量按玩家存入肉鸽状态，不修改城墙CSV基础生命。
- 已完成：`feast`领取时记录实际固定增加量；城墙等级/科技重算在正常生命结果上加回该固定值，不按后续等级重复乘2，也不会在重复重算时叠加。
- 新增`tools/test_feast_wall_health_projection.lua`，直接验证正常等级生命1500加固定1000得到2500、20%科技只乘等级基础生命得到2800、后续等级与重复重算均只携带原固定值一次，并验证玩家隔离。
- 自动验证通过：`FEAST_WALL_HEALTH_PROJECTION_LUA51_PASS`、五卡handler固定增量断言、肉鸽运行时/奖励服务回归、建筑批量升级契约、本批目标Lua 5.1语法和`git diff --check`；尚未执行Workshop Tools实机残血升级验收。
## 本轮实施（2026-08-23）：生产星之庇佑定义同步与一分钟 Tools 测试

- 新增 `D:\survival_database\supabase\migrations\202608230002_sync_star_blessing_v3.sql`，由权威 `star_blessing_reward_definitions.csv` 生成并同步 definition version `3`、26 条启用奖励，SHA-256 为 `4842c33bf94962584d11ddeab709c73e3053cacc499017e26ea8c6a18a16de3b`；若数据库已有冲突的 version `3`，事务失败并回滚，不覆盖不可变定义。
- 旧 definition version `9001` 保留为历史测试版本，不再尝试修改其 `test_hero_attack_flat` 数据。新增后端 `fishing_system_rules_60s.csv`，只在 `start_fishing_api.ps1 -Workshop60Seconds` 时使用生产奖励 CSV + 固定 60 秒奖励间隔；生产 `fishing_system_rules.csv` 仍保持最高 600 秒。
- Tools 命令 `survival_online_checkpoint_now 0` 现在允许 `survival_fishing_reward_fixture=production_60s`，但仍要求 Tools Mode、`http_fishing` 和 HERO_READY session。该 ConVar 值只放行调试命令；Lua 奖励校验继续读取生产生成定义。
- 后端 27 项单元测试通过。用户仍需在目标 Supabase 执行新 SQL、用 `-Workshop60Seconds` 重启 API，并在全新 Workshop Tools session 设置 `survival_fishing_reward_fixture production_60s` 后完成实机奖励、档案投影和公告验收。

## 当前总计划（2026-08-23）：单问题单门禁推进多人与数据库

用户已确认按“解决一个问题，再进入下一个问题”的顺序推进。当前不开发公网 HTTP 暴露，也不提前开发正式支付购买系统；每一阶段必须完成对应静态/自动/实机门禁后才能进入下一阶段。

### 推进顺序与门禁

1. **数据库迁移与生产状态核对**：核对独立仓库 `D:\survival_database` 的迁移依赖、执行顺序和目标 Supabase 远端状态，优先处理 `202608230006*.sql`、`202608230007*.sql` 及其前置迁移。门禁：远端函数、奖励定义版本和历史账本状态可核对；未完成前不作生产结论。
2. **主机 API 与 Dota 对局冷启动**：主机运行 Dota/Lua、Python API（`127.0.0.1:8765`）并访问 Supabase，确认生产模式可启动。门禁：无 fixture 参数时地图正常进入，API 可用性和失败策略有明确日志。
3. **双玩家房间加入**：使用两个不同 Steam 账号，在当前 Dota/Workshop Tools 版本实测主机创建对局、第二客户端加入的实际入口；不把 `connect` 或好友大厅假设当成已验证事实。门禁：两名玩家同时进入同一局，服务端分别识别玩家身份。
4. **双玩家数据库隔离**：验证首次建档、独立 `session`、在线累计、checkpoint、600 秒奖励、断线/结束结算、重连、重复 `request_id`/`grant_id`、API 重启和跨玩家隔离。门禁：两个账号档案、revision、奖励和永久效果互不串线。
5. **两人最小可玩切片**：逐项迁移仍按 team/global 保存的经济、Builder、建筑上限、英雄、城墙和波次状态；先完成两玩家而不是直接承诺四玩家。门禁：每名玩家可独立进行一轮核心玩法，空间共享、支援和 owner 规则符合既定设计。
6. **多人结算与异常恢复**：验证玩家失败、胜利、支援归属、掉线、重连、主机/API/数据库异常和对局结束清理。门禁：状态生命周期、奖励归属和恢复策略可重复验证。
7. **扩展到四玩家与性能回归**：在两人切片稳定后扩展东南西北四槽位，测试实体数量、网络同步、帧率和长局稳定性。门禁：四人局无跨玩家污染和不可接受性能退化。
8. **正式商品/支付系统**：最后再设计商品、订单幂等、权益账本、发货、退款、撤销、过期和客服审计；商品定义继续以 CSV 为权威源。门禁：后端验签和事务链完成前，客户端不得授予付费权益。

### 当前唯一动作

先完成第 1 项：只读核对 `D:\survival_database\supabase\migrations` 的迁移依赖、目标状态和当前凭据可用性；若远端状态无法确认，记录为外部阻塞，不跳到下一项。
## 第1项执行结果（2026-08-23）：远端 Supabase 状态暂无法确认

- 已由本地代理只读检查 `D:\survival_database\supabase\migrations`：目标文件 `202608230006_include_definition_version_in_online_grant_id.sql` 与 `202608230007_finalize_online_time_session.sql` 均存在；本地迁移依赖顺序为基础奖励/玩家属性/奖励账本/在线 checkpoint/奖励定义/清理/属性修复后，再执行 006、007。
- 已检查 `D:\survival_database\.env`：`SUPABASE_URL`、`SUPABASE_SECRET_KEY`、`FISHING_ACCOUNT_ID_PEPPER` 均已配置；只确认存在和格式前缀，未输出秘密值。
- 已对目标 Supabase REST 进行只读查询：奖励定义、`reward_grants`、`online_time_sessions`、`online_time_idempotency` 以及可能的迁移记录表均返回 HTTP `401 Unauthorized`。因此当前不能证明 006/007 已在目标项目执行，也不能读取真实函数定义或历史账本。
- 本地 `FISHING_REWARD_CONTRACT_PASS` 通过；Python 单元测试 29 项中 28 项通过，1 项因测试直接拼接中文目录路径后乱码，找不到已删除的旧 fixture `fishing_reward_definitions.csv`。该失败不代表远端数据库失败，也未修改测试迎合。
- 当前门禁状态：**第1项未通过，原因是远端凭据/项目授权阻塞**。不得进入主机冷启动或生产双玩家结论。

### 需要的外部动作

- 由项目所有者在 Supabase Dashboard 确认当前 Project URL 与 Secret key 属于同一个项目，并生成/提供一个当前有效的 `sb_secret_...` key；密钥不要发送到聊天中，可直接更新 `D:\survival_database\.env`。
- 或者由项目所有者在目标 Supabase SQL Editor 执行只读核对：确认 `public.checkpoint_online_time` 同时存在七参数和八参数签名，七参数函数定义包含 `:star:v` 与 `p_definition_version`，八参数函数定义包含 `p_final` 和删除对应 `online_time_sessions` 的逻辑；同时核对奖励定义版本和 migration 执行记录。
- 凭据修复后由本地代理重新执行只读 REST 探针；在确认远端状态前不执行 migration，避免重复或顺序错误。
## 第1项复核结论（2026-08-23）：跳过凭据配置动作，保留远端状态风险标记

- 用户确认此前数据库曾经成功连接，认为当前不应重复配置 `SUPABASE_URL` 与 `SUPABASE_SECRET_KEY`。第二轮只读探针验证：Supabase 根 URL 返回 HTTP 404（域名可达），REST 根路径和目标表在仅 `apikey`、`apikey + Authorization` 两种请求下均返回 HTTP 401。
- 结论：跳过“让用户重新配置 URL/key”的人工动作；但不能把远端 migration 状态记录为已确认。当前已完成本地 migration 文件、依赖、契约和 API 调用链核对，远端 006/007 仍标记为“未验证”。
- 进度策略：不让 REST 401 阻断后续 Dota 主机冷启动和房间加入验证；真正需要数据库读写时，使用本地 API 的实际请求结果作为下一处门禁。若生产 API 仍因 Supabase 认证失败，则回到数据库凭据/项目授权问题单独处理。
## 第1项实机结果（2026-08-23）：202608230007 已在远端生效

- 用户已在目标 Supabase SQL Editor 执行 `D:\survival_database\supabase\migrations\202608230007_finalize_online_time_session.sql`。
- 真实 API 日志确认 `FISHING_API_READY http://127.0.0.1:8765`，首次 checkpoint 返回 `200`、`elapsed_seconds=0`、`online_seconds_total=4163`、`grant_count=0`；同一 session 后续 checkpoint 返回 `200`、`elapsed_seconds=4`、`online_seconds_total=4167`、`grant_count=0`。
- 该结果证明带 `p_final` 的八参数 `checkpoint_online_time` RPC 已被 Supabase/PostgREST 发现并成功执行，之前的 `PGRST202` 已解决；首次不累计、同 session 只累计相邻在线差值均符合规则。
- `grant_count=0` 正常：当前正式奖励间隔为 600 秒，本次只累计约 4 秒，未达到奖励里程碑。
- 当前门禁状态：`202608230007` 远端执行和 API checkpoint 基础链路通过；`202608230006` 的 definition-version grant ID 逻辑仍需在奖励触发前或 SQL Editor 中单独确认，不能随 007 一起标记完成。