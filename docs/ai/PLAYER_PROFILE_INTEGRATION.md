# Player Profile Integration

## 目标与当前状态

本模块为付费权益、成就、长期存档和公开玩家信息提供可替换的数据接入层。当前完成的是本地Fixture纵向切片：运行时接口、JSON协议、校验、版本控制、权益投影和公开NetTable均已落地；尚未实现真实HTTP、数据库、支付回调或游戏结果写回。

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
- `account_id`是档案协议中的永久键。当前Fixture使用`mock_account_*`。
- 正式环境仍需选择：直接使用Steam Account ID，或由后端把Steam Account ID映射为自有账号ID。
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

完整档案只存在Lua服务端内存。当前唯一公开表是：

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
- 正式上线前必须确定Steam Account ID直用还是映射自有账号ID。

## 当前限制与实机验证

- 当前没有真实HTTP、数据库、支付或写回。
- `mock_player_account_bindings.csv`只是开发映射，不验证Steam身份。
- `save`首版只读保留，未覆盖现有单局`hero_progression_system`或内容库存，避免把外围长期存档错误注入局内状态。
- 自动测试证明Lua 5.1模拟和静态契约，不等于Workshop Tools引擎验证。
- Workshop Tools冷启动需确认：玩家0加载`mock_account_10001`后VIP商城链有效；玩家1加载`mock_account_10002`后VIP入口保持锁定；`survival_player_public_profiles`只有白名单字段；控制台没有Lua异常。
