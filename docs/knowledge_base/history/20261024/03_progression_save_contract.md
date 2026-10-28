# 03 账号成长、云存档与结算契约

核对日期：2026-10-24。本文以当前 Lua、Python、SQL 和已保存的验证记录为依据；“代码具备”“历史部署已验证”“本轮实机已验证”分别表述。本次整理未连接数据库或业务接口。文中的源文件路径均相对原项目 game 仓库，迁移新项目时应保留对应实现与测试，不能只搬说明。

当前开发配置 `all_difficulties_unlocked=true` 会把验收局账户写入隔离到整局结束；下述持久化契约描述正常服务路径，不表示验收局会写云端。冻结 v05 的现场云档证据独立见模块04，不能从当前工作区开关反推冻结包状态。

## 身份与档案边界

游戏由 `http_fishing_provider.resolve_account_id()` 从 `PlayerResource:GetSteamAccountID` 取得十进制字符串账号；它是 Steam AccountID，不能与 SteamID64 混用，也不接受前端填写账号作为可信身份。HTTP 除账号外必须绑定 `match_session_id`，在线授权还应校验当前玩家和本局绑定。数据库通过服务端 `_database_account_id()` 将账号映射为固定 HMAC 标识，避免业务表直接依赖明文 Steam 账号；迁移已有存档时不能随意更换映射密钥，否则会被识别为另一批玩家。

当前档案 `schema_version=1`，基本字段为 `account_id/revision/entitlements/achievements/save/public`。`save` 包括 `gameplay_stats`、`archive`、`content_inventory`，部分能力还包括 `permanent_effects`、叠加道具的已应用效果记录。`revision` 是账号的权威版本，不能用时间戳或本地等级替代。玩法默认值及属性类型、上下限来自玩家档案 CSV 和生成配置；缺失字段可以按协议补默认值，错误类型、非有限值、身份不符和不支持的 schema 必须拒绝。

主要表与职责：

| 表 | 权威内容 |
| --- | --- |
| `survival_players` | 账号、`profile_revision`、更新时间 |
| `player_gameplay_stats` | 持久化属性、累计成长数值 |
| `player_archive_state` | `archive` 状态与 `content_inventory` 库存 |
| `archive_entitlements` | 权益 ID、active、开始和到期时间 |
| `match_profile_sessions` | 账号与对局的 mode、不可变 baseline、defaults、创建时间 |
| `archive_operations` | operation ID、配置 hash、请求 fingerprint、command、首次 event_at、完成结果 |
| `archive_config_sets`、`archive_online_outbox` | 不可变结算配置；在线时长已接收事件 |

## 先准入，再选模式，最后捕获基线

`/v1/session/authenticate` 只核对准入、账号和对局，返回解锁进度等选择模式所需信息；不能提前建立模式 baseline，也不能把“认证通过”当作完整档案加载。选定模式后调用 `/v1/session/login`，后续读取使用 `/v1/profile`。provider 在同局登录成功后才切换读接口，并检查回包账号、session、mode，以及当前仍是同一局。

`match_profile_login()` 在锁住属性行和玩家版本行后取得当前完整档案。`(account_id,match_session_id)` 为唯一键，重试、重连或服务重启均读取原 baseline；同一 session 改 mode 返回 `match_mode_locked`。登录前先排空已接受但未完成的历史奖励，防止旧奖励在捕获基线后被误算为本局新奖励。高阶模式的准入最终也由数据库判断，不能只依赖按钮解锁；当前新建准入开放 pure、standard、rich、cold，其他模式即使数据库保留枚举也不等于已经发布。

## 纯净模式不是删除永久存档

标准模式以真实账号档案作为战斗视图。纯净模式保留永久档案，在服务端按“登录时默认值 + 当前永久值相对本局 baseline 的变化”生成战斗投影。因此历史属性、旧库存、旧权限不能直接灌入纯净战斗；本局新获得的永久奖励仍可写入账号，并按规则进入当前局。数字库存等使用非负差量，属性变化需保留有意义的正负差，不能全部做 `max(0,delta)`，否则减少冷却之类效果会失效。

服务器返回的 `account_profile` 是独立的永久业务档案，供商城余额、持有判断、成就、公开资料等使用；它不能反过来替换战斗 `save`。首次纯净登录响应刻意不带旧完整档案，后续刷新或结算响应才可附带独立视图。Lua `get_profile()` 与 `get_account_profile()` 必须分别使用，后者返回副本。若携带 `account_profile`，账号和 revision 必须与外层一致。叠加物品投影使用服务端标记 `stackable_projection_applied` 防止 Lua 再次从库存差重复叠属性，该标记不写回永久存档。

权益判定同时考虑 active、开始及到期时间。本局开始前已存在的权益不会因为刷新而被当作纯净模式新权益；新获得权益按投影规则处理。游戏服务端 Lua 的 `systems/archive_monthly_effects.lua` 用 `project(profile)` 派生工种/等级的额外月卡属性层，不写回永久属性；`permanent_reward_effect_service.lua` 应用、`archive_calendar.lua` 判断有效期。到期只移除这一层，正常已获得的在线/福利奖励仍可持久保存，不能反向扣除。这三者不是 Python 支付回调。结算后的战斗冻结另由玩法阶段守卫管理，永久到账不自动表示已生成单位必须立即全部改变。迁移时应复用投影函数和阶段规则，不能在收银成功回调里直接加战斗属性。

## 每个奖励必须有可重放的事务凭据

`/v1/archive/command` 请求包含账号、本局 session、`config_hash` 和 `command`。命令必须落在服务端字段白名单，不能提交任意余额、属性或奖励数量。核心路径是 `archive_prepare → 服务端 reducer → archive_commit`；涉及库存、兑换和福利时使用 `archive_commit_lottery`。prepare 保存首次配置、fingerprint 和 event_at，相同 operation ID 的相同请求返回旧凭据，改变内容或 hash 则冲突。响应丢失后重试原 ID，不能换 ID“再领一次”。

commit 使用预计 revision 检查，并在同一事务内写库存、属性、档案、结果及版本增长。并发付款、通关和领取奖励共用属性行→玩家行的锁顺序，避免半份奖励进入 baseline。Python 遇 `archive_revision_conflict` 会 resume 并基于新快照重算，最多四轮，仍冲突返回 `archive_busy_retry`。完成凭据不能因配置更新被重写；旧未完成操作是否允许使用新 reducer，只能通过明确兼容表决定。

通关 ID 需绑定持久化 session 与模式，例如 pure 的 `session:clear`、标准的 `session:standard_clear`。`clear_receipts.lookup()` 兼容标准模式早期旧 ID，但不改写历史凭据；数据库不可用不能按“没有旧记录”继续发。无尽批量接口只是传输优化，每波仍保留独立凭据。随机奖励也由可信服务按已记录操作生成与复现，不能让客户端上传抽中结果。

## 日期、上限和领取记录

签到、每日时长、胜场、每周奖励使用服务器时间，当前日切为北京时间 05:00；日编号公式是 `floor((unix_seconds+10800)/86400)`。命令里的客户端 `today/day_key` 被移除，跨日重试沿用数据库首次接受的日期。在线时长跨边界拆分计入各自周期，迟到 outbox 更新原周期，不能清掉较新周期。每日获取上限是账号级累计获取量，不因换房、消费或换模式而重置。

福利记录存于 `archive.benefits.days/weeks`，每档 claimed 与发奖同一事务落库。当前本地 `daily_time_0` 为有效月卡专属、零分钟、手动领取一张金色券，`auto_claim=false`；无月卡请求不能占用该日领取资格。它的历史本地验证记录仍标记普通服务发布待完成，不能仅凭本地 CSV 宣称所有生产环境已经更新。每日、每周其他档位按当前配置读取，不在新项目代码里硬编码一份数量。

永久唯一道具需要跨抽奖、兑换、付费及别名共用身份。数据库唯一约束和 reducer 双重校验；每日唯一奖励只由自己的 archive 计数承担效果，不能同时再在库存保存第二份正数。当前可叠加例外包括传承余烬和福利粽子，粽子上限 150，不能把全部道具都改成可叠加。重复唯一物品转积分和历史贡献修复应走已有维护预览、备份、事务与专用迁移标记，禁止凭当前总属性猜测并批量扣减。

## 游戏回包、权限和维护

`player_profile_service` 检查当前账号、session、mode、load generation 和 revision 高水位；旧请求回包即使 HTTP 200，也不能覆盖新局或新账号。增量协议要求 `update_id` 去重、`base_revision` 等于当前版本、`revision=base_revision+1`，缺口要求重新读取。在线失败不自动回退本地模拟存档；离线逻辑入口只使用本局内存，不能把离线结果写回云端。

运行账号 `goufayu_app` 仅调用已审阅 RPC，无表级 DML、owner 成员或 BYPASSRLS；支付使用另一个最小权限角色。所有业务表启用 RLS，SECURITY DEFINER 固定 search_path。旧 README 的“12 个 RPC”是历史数量，新增 session、排行榜等能力后应按当前迁移逐项审计，不能照旧数字授予整库执行权限。

维护入口是 `server/aliyun/database/dbtool.py` 的计划、迁移、校验、备份恢复流程，以及 `server/maintenance/reconcile_unique_points.py` 等专用工具。历史 SQL 与 ledger hash 不改写；新字段用追加迁移，在隔离合成数据上验证后再发布。恢复必须同时校验支付凭据和游戏档案；有真实付款后不能只恢复 public 表而遗漏 payments。

代码定位：`systems/player_profile_service.lua`、`systems/player_profile_providers/http_fishing_provider.lua`、`server/fishing_api_overrides/match_profiles.py`、`server/archive_backend/{service,match_modes,clear_receipts,daily_limits,stackable_effects}.py`、`server/aliyun/database/{harden,harden_match_sessions}.sql` 及 `target/202609230001`、`202610200003`、`202610210001`、`202610210002`、`202610220001` SQL。

已有专项测试包括 profile modes/load retry、pure permanent rewards、stackable pure projection、archive receipts/mode scope、daily caps、福利数据库与权限测试。本次是知识整理，没有重跑这些测试；既有通过记录不是对未来移植代码的自动背书。
