# Player Profile Integration

## 目标与当前状态

本模块为付费权益、成就、长期存档和公开玩家信息提供可替换的数据接入层。运行时接口、JSON协议、校验、版本控制、权益投影和公开NetTable已经落地；真实HTTP与Supabase数据库的玩家档案纵向链路也已接入并完成本机真实联调。支付回调、正式商品发货、游戏结果写回和多电脑独立主机验收仍未完成。

当前首次登录协议是“查询并确保建档”而不是先查询再注册：Lua服务端在档案加载时从`PlayerResource:GetSteamAccountID(player_id)`取得稳定Steam Account ID，调用`POST /v1/profile`。Python边界将该身份转换为HMAC伪名后调用`ensure_player_gameplay_stats`；不存在的账号在数据库事务中创建，已存在的账号幂等跳过创建，随后返回同一份档案快照。客户端不能提交或决定账号身份。

真实信任链固定为：

```text
Dota服务端Lua -> 127.0.0.1 Python API -> HTTPS Supabase PostgreSQL
```

`D:\survival_database`中的API只监听loopback，因此第二台电脑作为加入者不需要运行API；若第二台电脑也独立主持游戏，则必须部署API并使用同一Supabase项目、同一个`FISHING_ACCOUNT_ID_PEPPER`，否则同一Steam账号会被计算成不同数据库身份。

当前权威源：

- `data/csv/玩家档案系统/player_profile_rules.csv`：Provider、schema和运行规则。
- `data/csv/玩家档案系统/mock_player_account_bindings.csv`：仅开发环境使用的`player_id -> account_id`映射。
- `data/csv/玩家档案系统/player_profile_public_fields.csv`：允许发布给同局客户端的唯一公开字段白名单。
- `data/csv/玩家档案系统/achievement_definitions.csv`：已知成就ID和目标。
- `data/csv/商店系统/entitlement_definitions.csv`：已知权益ID。付费权益默认必须关闭。
- `data/mock/player_profiles.json`：本地样本值，不是正式业务数据库。

运行时文件：

- `scripts/vscripts/systems/player_profile_service.lua`
- `scripts/vscripts/systems/player_profile_providers/local_fixture_provider.lua`
- `scripts/vscripts/core/json_decoder.lua`
- `scripts/vscripts/config/fixtures/player_profiles.lua`（由JSON生成，禁止手改）

## 身份边界

- `player_id`只表示当前比赛中的Dota玩家槽位，会随每局变化，禁止作为永久档案主键。
- `account_id`是Lua档案协议中的稳定键。正式HTTP Provider使用服务端解析的Steam Account ID字符串；Supabase内部的`player_id`则是该ID经过独立pepper计算的64位小写HMAC-SHA256文本。
- 数据库不保存原始Steam Account ID。`FISHING_ACCOUNT_ID_PEPPER`必须长期稳定、单独备份且只存在Python服务端环境；更换它会让所有现有玩家看起来像新账号。
- 无论采用哪一种，Lua只消费稳定字符串`account_id`；同一局中同一`account_id`不能绑定两个`player_id`。
- 客户端提交的`player_id/account_id`都不能作为身份凭证。正式Provider必须从服务器可信的玩家连接身份解析账号。

## Provider接口

Provider模块必须提供：

```lua
function provider.init()
end

function provider.resolve_account_id(player_id)
    -- 返回稳定account_id字符串，失败返回nil。
end

function provider.fetch_snapshot(account_id, on_success, on_error)
    -- 可以同步或异步。
    -- 成功调用on_success(snapshot_table)。
    -- 失败调用on_error(error_code)。
end
```

约束：

1. Provider只负责身份解析和传输，不复制schema校验、revision比较、权益投影或NetTable逻辑。
2. HTTP Provider将响应JSON交给`json_decoder.decode()`，然后调用`player_profile_service.apply_snapshot()`或`apply_incremental()`。
3. `fetch_snapshot()`抛异常会转成`provider_fetch_failed:*`；调用失败或验证失败时付费权益保持关闭。
4. 每玩家加载有递增generation。旧请求的迟到成功或失败回调会被忽略，不能覆盖新请求。
5. Provider返回的`account_id`必须与本次请求完全一致。

## 完整快照协议

```json
{
  "schema_version": 1,
  "account_id": "mock_account_10001",
  "revision": 3,
  "entitlements": {
    "vip": { "active": true }
  },
  "achievements": {
    "first_wave_clear": { "progress": 1, "unlocked": true }
  },
  "save": {
    "highest_difficulty": "N2",
    "total_wins": 5
  },
  "public": {
    "title_id": "veteran",
    "achievement_score": 120,
    "highest_difficulty": "N2"
  }
}
```

验证规则：

- `schema_version`必须等于CSV当前版本。
- `account_id`必须是非空字符串并与请求账号一致。
- `revision`必须是非负整数。
- 权益ID必须存在于`entitlement_definitions.csv`，状态必须包含boolean `active`。
- 成就ID必须存在于`achievement_definitions.csv`，`progress`必须是非负整数，`unlocked`必须是boolean。
- `save`与`public`必须是对象；具体存档字段将在接入真实业务写回前继续收紧schema。
- 同账号低于当前revision的快照以`snapshot_revision_stale`拒绝；相同或更高revision可用于幂等重拉或缺口恢复。

## 增量协议

```json
{
  "schema_version": 1,
  "account_id": "mock_account_10002",
  "update_id": "backend-event-uuid",
  "base_revision": 7,
  "revision": 8,
  "changes": {
    "entitlements": {
      "vip": { "active": true }
    },
    "achievements": {
      "first_wave_clear": { "progress": 1, "unlocked": true }
    },
    "save": {
      "total_wins": 6
    },
    "public": {
      "achievement_score": 130
    }
  }
}
```

规则：

- `update_id`是后端全局或账号内唯一的幂等ID。服务当前按玩家保留最近128个，数量由CSV配置。
- 已处理`update_id`直接返回`duplicate=true`，不得再次应用。
- `base_revision`必须等于当前revision。
- `revision`必须严格等于`base_revision + 1`。
- 只允许`entitlements/achievements/save/public`四个分区；拼错分区会失败，不能静默推进revision。
- JSON `null`表示删除分区内对应字段；整个分区不能为`null`。
- 任何校验失败都不能改变档案、权益或公开投影。
- `base_revision_mismatch`和`revision_gap`都返回`reload_required=true`；HTTP层应重拉完整快照，不要自行猜测缺失增量。

## 服务接口与事件

- `player_profile_service.load_player(player_id, reason)`：按Provider加载；同步Provider直接返回结果，异步Provider返回`pending=true`。
- `player_profile_service.apply_snapshot(player_id, snapshot, reason)`：统一完整快照校验和提交入口。
- `player_profile_service.apply_incremental(update_or_json)`：统一增量入口。
- `player_profile_service.get_profile(player_id)`：服务端完整档案副本。
- `player_profile_service.get_public_profile(player_id)`：服务端公开投影副本。
- `PLAYER_PROFILE_GET_REQUEST`：服务端事件总线只读查询；不要直接暴露给客户端Custom Game Event。
- `PLAYER_PROFILE_CHANGED`：只发布`player_id/account_id/revision/reason`元数据，供内容库存、成就UI或存档适配器刷新；不携带完整私有内容。

## 权益投影与支付安全

- `player_entitlement_service`仍是商城和英雄召唤等现有业务的权益查询边界。
- 档案加载开始时，Provider管理权益整体置为false；只有验证通过的快照或增量可以原子替换。
- `entitlement_definitions.csv`中的VIP默认值为false。`setvip`仅是开发作弊入口，不是支付入口。
- 正式支付链必须是：平台/支付服务通知后端 -> 后端验签、校验订单金额/商品/幂等 -> 后端写入权益和新revision -> 游戏服务器重拉或接收后端增量。
- Panorama、Custom Game Event和Lua客户端参数都不能声明“支付成功”或直接授予权益。
- Lua服务端也不保存支付密钥、订单签名、银行卡、金额明细或鉴权token。

## 私密与公开数据边界

完整档案只存在Lua服务端内存。HTTP返回的完整档案不能直接发布到客户端；当前唯一公开表是：

- NetTable：`survival_player_public_profiles`
- Key：当前局`player_id`
- 白名单：完全来自`player_profile_public_fields.csv`

首版字段只有：

- `title_id`
- `achievement_score`
- `vip_badge`
- `highest_difficulty`

禁止发布：

- `account_id`和Steam身份；
- 完整`entitlements/achievements/save`；
- 内容库存和装备明细；
- 订单、金额、支付渠道、签名、token、邮箱或IP；
- 后端错误堆栈和内部数据库ID。

## 本地Fixture工作流

1. 修改业务schema或白名单时先改对应CSV。
2. 运行`tools/build_configs.py`生成CSV Lua。
3. 修改样本值时改`data/mock/player_profiles.json`。
4. 运行`tools/build_player_profile_fixture.py`生成`config/fixtures/player_profiles.lua`。
5. 运行`tools/build_player_profile_fixture.py --check`验证逐字节一致。
6. 运行`tools/test_player_profile_service.lua`和`tools/test_player_profile_contract.ps1`。

Fixture Lua不能放入`config/generated/`，因为CSV全量生成器会清理该目录中的非CSV模块。

## 首次登录与字段语义

- `POST /v1/profile`同时承担首次建档和已有账号读取，成功响应必须包含`schema_version`、`account_id`、`revision`以及协议要求的分区。
- `player_gameplay_stats`是局内启动数值，当前由`player_gameplay_stats.csv`提供完整默认值，数据库列为非空字段；首次建档会返回36个玩法字段，不是稀疏字段集合。
- 可选业务分区（例如成就、库存、外观和非核心资料）可以采用稀疏JSON：只有有内容的字段才返回。`0`、`false`和空字符串若是有效业务值，不能因为“看起来为空”而省略。
- 客户端必须把“字段不存在”与数值`0`、布尔值`false`区分处理。`null`是否表示删除或未配置必须由具体分区协议声明；核心玩法字段不使用`null`代替默认值。
- 账号根记录、档案revision、商品权益、订单和库存不应合并成一个不可审计JSON blob。商品系统应使用订单幂等、权益账本和当前投影。

## 商品与账号后续边界

- 商品购买请求必须由服务端校验Steam身份对应的账号、商品定义、价格和订单幂等键；客户端不能声明“支付成功”或直接授予商品。
- 推荐将永久权益、可消耗库存、限时订阅和一次性礼包分开建模，并明确退款、撤销、过期和重复回调语义。
- 游戏结果写回应使用`match_completed`、`achievement_progressed`或`save_checkpoint`等语义事件，由后端计算最终档案；禁止接受客户端任意JSON Patch。

## Mock HTTP与正式后端迁移顺序

### 阶段A：只读Mock HTTP

- 新增`http_player_profile_provider.lua`，保持Provider三函数接口。
- 配置URL、超时、重试上限和环境开关必须来自CSV或安全服务器配置。
- 只实现GET完整快照；网络失败保持权益关闭并给出有限诊断。
- 用本地Mock服务器覆盖200、404、500、超时、非法JSON、账号错配、schema不支持和低revision。

### 阶段B：HTTP增量

- 后端返回或推送当前快照revision后的增量。
- 缺口、乱序、未知版本统一触发GET快照。
- `update_id`必须由后端生成，不能由客户端生成。

### 阶段C：游戏结果写回

- 先定义结果命令schema和服务端幂等事务，不直接上传任意档案patch。
- 建议命令为语义事件，如`match_completed/achievement_progressed/save_checkpoint`，由后端计算最终档案和revision。
- 写回请求需要`match_id/request_id/base_revision`，重复提交必须返回同一结果。
- 多人奖励归属和挑战并发规则确认前，不实现相关写回。

### 阶段D：正式数据库和支付

- 账号表、档案快照、权益账本、成就进度、存档、支付订单和幂等事件应分层建模；不要把完整档案只存成一个不可审计JSON blob。
- 权益建议使用不可变账本/来源记录加当前投影，支持退款、撤销、到期和客服审计。
- 数据库revision必须在同一事务中递增，并与事件/更新ID唯一约束绑定。
- 当前正式身份决策已确定：Lua协议使用服务端Steam Account ID字符串，数据库使用`FISHING_ACCOUNT_ID_PEPPER`计算的HMAC伪名；后续商品系统不得另造第二套身份键。

## 当前限制与实机验证

- 真实Supabase/Python API联调已通过：首次`/v1/profile`会创建账号并返回36个CSV玩法字段；已有账号会读取同一档案。已覆盖初始化、在线时长、幂等和公开数据隔离。
- Workshop Tools已实际确认HTTP Provider能够通过Lua、Python API和Supabase返回在线检查点grant；但完整账号冷启动、断线重连、API重启、多Steam账号并发首次建档和第二台电脑独立主机仍需专项验收。
- `mock_player_account_bindings.csv`只是本地Fixture映射，不验证真实Steam身份；使用`local_fixture`时不能把它描述为正式账号登录。
- 当前尚无正式支付回调、订单发货、游戏结果写回或库存长期投影。
- `save`首版只读保留，未覆盖现有单局`hero_progression_system`或内容库存，避免把外围长期存档错误注入局内状态。
- 自动测试证明Lua 5.1模拟和静态契约，不等于Workshop Tools引擎验证。
- Workshop Tools下一轮需确认：真实Steam账号首次建档、同账号二次登录读取原revision、两个Steam账号互不串档、API不可用时的失败策略、`survival_player_public_profiles`只有白名单字段，以及控制台没有Lua异常。
