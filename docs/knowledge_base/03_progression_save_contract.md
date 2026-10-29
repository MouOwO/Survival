# 03 账号成长、云存档与结算契约

事实截点：2026-10-29（北京时间）。10/28规则梳理来自只读源码审阅；本轮新增隔离PG17验证及d573配套部署，见第9节与发行证据。规则、源码实现、已部署版本及真实验收分别标注；未在活动库造余额、抽奖、兑换或付费。永久结算能力存在不代表离线开发局会写账户。

路径以 game 仓库为根；`core/`、`systems/`、`config/`、`combat/`、`research/` 均为 `scripts/vscripts/` 下的缩写。基础玩法见模块02，引擎及原生入口见模块10。

## 1. 身份、会话和档案形状

游戏身份来自引擎 `PlayerResource:GetSteamAccountID` 的十进制 **AccountID**，不是 SteamID64，也不是玩家手输账号。服务端把玩家、账号、`match_session_id` 和授权绑定；网页 Steam 登录及当局授权证明身份，前端昵称/PlayerID/手机号不能替代。后端 `_database_account_id()` 的固定 HMAC 映射属于持久身份契约，迁移不可随意换映射密钥，否则旧玩家会变成新账号。本文不存任何密钥、令牌或登录回调。

当前 `player_profile_rules.csv`：`provider_id=http_fishing`，`schema_version=1`，增量去重窗口128，禁止失败后自动回退本地模拟档案。基础档案字段为 `account_id/revision/entitlements/achievements/save/public`；`save` 含 `gameplay_stats/archive/content_inventory`，还可能含永久效果及已应用的叠加效果记录。缺失值只能按协议补默认；错误类型、非有限数值、身份/schema不符必须拒绝。`revision` 是权威账号版本，不能拿本地等级或时间戳替代。

| 存储职责 | 主要表/结构 |
| --- | --- |
| 账号版本与持久属性 | `survival_players`、`player_gameplay_stats` |
| 存档、库存、权益 | `player_archive_state`、`archive_entitlements` |
| 对局模式与不可变基线 | `match_profile_sessions` |
| 请求指纹、首次事件日期、完成回执 | `archive_operations` |
| 不可变配置、在线事件 | `archive_config_sets`、`archive_online_outbox` |

当前开发 `all_difficulties_unlocked=true` 会把验收局账户写入隔离到整局结束。测试中应明确该标记、provider、构建身份和冻结配置，不能把本局资源增长称为持久到账。离线只在本局内存中保存，不能把离线收益回灌云档。

源码：`scripts/vscripts/systems/player_profile_service.lua`、`systems/player_profile_providers/http_fishing_provider.lua`、`config/generated/player_profile_rules.lua`，以及 `data/csv/玩家档案系统/`。

## 2. 准入、选模式和不可变 baseline

顺序是 `/v1/session/authenticate` → 选择合法模式 → `/v1/session/login` → 后续 `/v1/profile`。authenticate 返回准入/持久进度，不能提前创建模式 baseline，也不是完整模式战斗档案加载完成。高阶模式权限由可信永久档案和数据库判断，按钮可用不是权限凭据。

`match_profile_login` 在锁住属性行/玩家版本行后捕获完整 baseline；`(account_id, match_session_id)` 唯一，重试、重连和服务重启复用原 baseline，同一 session 换模式拒绝 `match_mode_locked`。登录前先排空已接受但未完成的旧奖励，避免旧收益在基线之后被误算为本局新增。持久 `game_mode` 与用于战斗投影的 `profile mode` 分开：丰饶/极寒沿用 standard 战斗档案投影，但有各自进度身份；不要把底层投影函数只接收 pure/standard 误写成只支持两种玩法。

源码：`server/archive_backend/match_modes.py`、`server/fishing_api_overrides/match_profiles.py`、Lua `match_setup_service` 和 `player_profile_service`。

## 3. 纯净战斗视图与永久业务视图

标准模式使用真实账号档案。纯净不删除永久存档，而按“登录默认值 + 当前永久值相对不可变 baseline 的变化”构造战斗投影；历史属性、库存、权益不能直接灌入纯净战斗，本局新增的合法永久收益依规则进入本局。

`account_profile` 是独立永久业务档案，供商城余额/拥有判断、成就和公开资料使用；它不能覆盖纯净战斗 `save`。首次纯净登录刻意不附旧完整档案；后续刷新/结算可携带独立视图。Lua `get_profile()` 和 `get_account_profile()` 分开使用，后者返回副本；外层与内层账号/revision必须一致。

数字库存差量采用非负规则，但属性/永久效果差值必须保留有意义的负值，例如减少冷却；不能统一 `max(0, delta)`。服务端 `stackable_projection_applied` 标记防止 Lua 再从库存差重复叠属性，它不写回永久档案。权益既要 active，也检查有效时段；旧权益不能因刷新被算作纯净模式新权益。

月卡额外战斗层由 `systems/archive_monthly_effects.lua` 派生，`permanent_reward_effect_service.lua` 应用，`archive_calendar.lua` 判断有效期；它不直接覆写永久基础属性。到期移除该临时层，已获得的签到/在线奖励仍保留。支付到账也不自动表示已生成单位必须绕过阶段冻结全部重算。

## 4. 所有永久变更都需幂等事务

`/v1/archive/command` 绑定账号、session、`config_hash`、白名单 command。客户端不能上传最终余额、奖励数量、价格或抽中结果。核心是 `archive_prepare` → 可信 reducer → `archive_commit`；库存、抽奖、兑换、福利通过 `archive_commit_lottery` 同一事务提交库存和结果。本次新增挑战专用 `archive_commit_challenge` 包装原提交，在同一事务保存真实奖励明细，重试返回原回执；须与SQL／hardening／transport／service配套部署，已于2026-10-29随d573 bundle部署，现役37项ledger／19个应用RPC；保留既有排行榜授权。隔离PG17实际事务与线上配置健康验证通过，真实玩家击杀到账仍待验，详见[配套发行证据](evidence/archive_all_release_20261029.md)。

prepare 固定首次配置、fingerprint 和 event_at；同 operation ID 同请求返回旧凭据，改内容或 hash 冲突。响应丢失重试原 ID，不换 ID 再发一次。commit 使用预计 revision，在一次事务中写属性、库存、档案、回执及版本。付款、通关、领取共用既有锁顺序，避免半份收益混入 baseline。当前 Python revision 冲突会 resume 后基于新快照重算，最多4轮，仍冲突返回 `archive_busy_retry`。

完成凭据不可随配置更新改写；旧未完成请求只按精确兼容规则升级 reducer。纯净/常规/派生模式的 clear ID 和 session绑定，兼容查找旧 ID 不重写历史。数据库不可用不是“没有旧记录”，不能继续重发。合作挑战共享可信基础随机事件，但每个账号独立提交、独立月卡和限额；不允许复用队友身份。

当前仓库 `server/archive_backend/service.py` 对 `commerce_purchase` 的 `shop_gold` 仍有显式 `shop_gold_not_open`，旧积分确认遇价格变化返回 `commerce_price_changed` 并要求新确认。此处是源码状态，不是本次云部署审计；不能只看目录有 G币、积分或人民币商品就宣称全部收款/兑换通道开放。局内金币、商城钱包和积分保持不同含义。真实收款和已交付状态只能来自权威回执及后续档案刷新，不能由扫码页面、付款按钮或客户端动画推断。

主要入口：`server/archive_backend/service.py`、`clear_receipts.py`、`match_modes.py`、`stackable_effects.py`；Lua `systems/archive_service.lua`、`inventory_transaction_service.lua`、`lottery_http_service.lua`。

## 5. 日期、上限和月卡决定

服务器时间决定签到、在线时长、胜场、每日/每周奖励。当前北京时间05:00日切：`floor((unix_seconds + 10800) / 86400)`。客户端 `today/day_key` 不可信；跨日重试沿用首次数据库接受日期。在线时间跨边界拆分归各自周期，迟到 outbox 更新原周期，不能清掉更新的日桶。每日上限是账号累计**获取**额度，消费、换房或换模式不会返还额度。

**用户已决定保留当前月卡加成配置。** 不再把“VIP/月卡不提高最终上限”的历史备注当待定规则。本次 CSV 与 Lua/Python读取路径共同核对如下：

| 额度 | 普通 | 有效月卡 | 当前 implemented |
| --- | ---: | ---: | --- |
| 全模式通关 | 20 | 20 | 是 |
| 丰饶/极寒独立通关 | 20 / 10 | 20 / 10 | 是 |
| 神兵碎片01–16（各自，13–16为10/29开发新增） | 20 | 40 | 是 |
| 秘法牢笼 | 30 | 90 | 是 |
| 瑞兽福签、邀请函、义帖、玫瑰（各自） | 10 | 20 | 是 |
| 虚空之影/软妹币获取/BOSS击杀 | 80 / 8000 / 300 | 相同 | 是 |
| 无尽积分/钓鱼/信仰 | 50000 / 80 / 3000 | 相同 | 是 |

`archive_daily_limits.csv` 的部分 notes 仍写“VIP与月卡不提高”，与 `pass_daily_limit` 数值冲突；服务端 `archive_daily_limits.lua` 与 Python `daily_limits.snapshot()` 会依据有效月卡选该字段。应保留用户已确认的数值，不为对齐旧文案去改经济，也不因此新增 VIP 倍率。`implemented=false` 的宠物、永恒/永夜秘法、带薪积分等额度仍只是预留，不能把其他来源硬映射进去。2026-10-29开发接入绿茵、工资、西瓜独立额度，具体见第9节；此开发状态不代表线上部署。

额度与发奖计数在同一变更中提交；faith兼容历史 `buildings.earned_by_day`。钓鱼的权威日计数有独立数据库来源，Lua快照需要读回对应 `save.daily_limits`，不能靠本地计数证明还有名额。日桶字段、显示名和钱包名字不是可互换的货币 ID。

依据：`data/csv/存档系统/archive_daily_limits.csv`、`scripts/vscripts/systems/archive_daily_limits.lua`、`archive_calendar.lua`、`server/archive_backend/daily_limits.py`，以及 `docs/validation/UI_DATA_QA_20261025.md` 的用户决定。3099项历史检查不等于本次重跑或云端新规则已经部署。

## 6. 签到、月卡、唯一与叠加物品

当前 `archive_daily_rules.csv` 的 `archive_pass_monthly` 为58元、30天，补签窗口30天，里程碑7/14/21次。续期从尚未过期的旧到期日追加，重复 delivered 不能再延期；开通本身不等于自动达到签到累计门槛。`archive_benefit_rewards.csv` 的 `daily_time_0` 为有效月卡专属、0分钟、手动领1张金色券，`auto_claim=false`；无月卡拒绝不得占用领取资格。其他档位按配置读取。

永久唯一道具跨抽奖/兑换/付费和别名共用身份，数据库约束和 reducer双重校验。重复唯一品转积分，不可将永久属性累计与持有数量混算。当前明确叠加例外：

- `lottery_ember_of_legacy` 薪火余烬可叠加、无游戏数量上限、不会因重复转积分；基础每份普攻成长+0.1。
- `welfare_zongzi` 粽子可叠加，上限150；基础每份普攻成长+0.05，满额只接收剩余额度，超额不转积分。
- 门槛效果按**严格大于** threshold 生效，同属性只取已达最高档，不把各档值累加，也不擅自把配置改成单调公式。

出处 `archive_stackable_items.csv`、`server/archive_backend/stackable_effects.py`。历史总属性不能反推出该扣多少重复收益；修复历史贡献必须走专用维护预览、备份、事务和迁移标记。

## 7. 抽奖契约与未确认配置

当前四个池为地图、修仙、龙骑、暑期。地图使用普通券，后三者使用金色券；单抽消耗1、一次十连消耗10。修仙按地图累计开启100次解锁，单抽计1/十连计10；龙骑和暑期当前没有前置抽数要求。

保底是**一次十连请求**的批次规则，连续十次单抽不等于一次十连。地图/修仙十连保底SSR，龙骑/暑期十连保底UR。随机结果及唯一持有处理在可信服务结算，客户端不上传抽中清单、价格、随机种子或奖励数量；一批扣券、库存、保底、历史和回执共同提交，重试不能再扣/再抽。

地图权重当前已确认：N 69.5%、R 25%、SR 4%、SSR 1.5%，无UR。特殊池的 `lottery_quality_weights.csv` 仍标 `needs_confirmation`，R84.5%/SR4%/SSR1.5%/UR10%是临时联调值；`enabled=1` 或界面能打开不表示正式概率已经获批。移植新项目不可把这组临时值冒充已确认运营规则。

源：`data/csv/抽奖系统/lottery_pool_definitions.csv`、`lottery_pool_items.csv`、`lottery_quality_weights.csv`、`lottery_pity_rules.csv`、`lottery_item_definitions.csv`；执行 `systems/lottery_service.lua`、`lottery_http_service.lua` 和 archive 后端。

## 8. 回包顺序、权限与继续维护

Lua验证账号、session、mode、load generation和账号 revision高水位；旧回包即使HTTP200也不能覆盖新局。增量要求 `update_id` 去重、`base_revision` 等于当前版本、`revision=base_revision+1`，有缺口请求全量读取。支付、奖励与UI刷新分别记录pending/delivered/readback，不能“支付返回成功”就假定当前玩法档案也完成刷新。

运行角色应保留最小 RPC 权限、无直接表DML/owner/BYPASSRLS，业务表RLS与 SECURITY DEFINER固定 search_path。旧知识包的“12个RPC”等数量不应照搬，应按当前追加迁移审计。历史SQL、ledger hash、完成回执不重写；新增字段追加迁移。恢复同时覆盖支付账本和游戏档案，不能只恢复部分业务表。

维护定位：`server/aliyun/database/dbtool.py`、`server/maintenance/reconcile_unique_points.py`、`server/aliyun/database/target/` 追加迁移；新项目需连同权限、事务和测试迁移，不只复制Markdown。现有回归包括 `scripts/vscripts/tests/test_player_profile_modes.lua`、档案重试/纯净永久收益/叠加投影、archive receipt与模式范围、每日上限、数据库福利与最小权限专项。最初10/28规则梳理没有重跑这些测试或连接远端；后续10/29配套上线与隔离PG17验证按第9节及独立发行证据记录。

## 9. 四座视频存档挑战（2026-10-29开发）

源视频摘要与数值出处见[专门证据](evidence/archive_video_challenges_20261029.md)。36项怪物挑战均按固定终值生成，每个模式使用实际怪物出生点，未增加帕鲁入口或奖励。用户随后要求改为紧凑单行、删除返回／空格／快捷键，当前39项按钮为36挑战+3模式控制，四楼11／10／9／9；挑战按ID独立并发。当前交互见[后续修复](evidence/archive_layout_independent_20261029.md)。视频看不到生命／护甲／攻速，因此这些字段沿用v3或原有项目基线，不得声称已逐帧提取。

前女友、好基友、老婆／侍妾的奖励分别要求前一池累计成功抽取严格>100次；持有余额无效，历史抽取计数采用单调兼容。条件不足仍允许打怪，按账号返回已完成但0奖励及中文原因，不会卡保存屏障。绿茵每日100点、西瓜每日10点、侍妾工资每日10份各自记账；工资用于侍妾收藏抽取，月卡不额外增加此新额度。16种神器的旧ID不变，新增13—16解锁N10；九组龙材料每组九种，新材料使用项目自定同类效果。

普通无尽和单人塔可依次各开启一次；塔结束即结束本人的存档阶段。跳关按1→2→5→10→20，仅实打层得积分／装备；普通每20层、塔每15层跨档至多一件装备，跳多档不补发。装备按对局+variant保留幂等游标，满收藏仍正常终态。塔准入仅当前极寒／天灾N10以上，实际允许难度来自不可变模式表；预留未来模式不会因此开放。

后台新高难度／塔 operation 在prepare前绑定可信启动match session，不能用游戏存档阶段runtime ID查错局；旧已接受高难度操作按原不可变bundle和原ID恢复，低难度旧回执身份不改。首次commit和重试都保留reducer的逐账号结果，失败与0奖励可读。获胜后准入暂时失败最多重试30秒，再走合作奖励与通关保存屏障；个人阵亡不能取消已经获胜的保存流程。开发阶段本地真实Lua worker与模拟RPC事务证据保留；本轮另已用线上备份的隔离PG17克隆验证真实worker、事务回滚、丢ACK重试与精确RPC权限，并部署d573配置及新回执RPC。尚无真实玩家击杀到账验收，边界见[配套发行证据](evidence/archive_all_release_20261029.md)。
