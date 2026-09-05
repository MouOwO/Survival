# 抽奖数据与联调约定

抽奖配置的主编辑入口是 `data/csv/抽奖系统`。配置修改后应运行
`build_configs.bat`，生成服务端 Lua，再完整重开测试局。
若本机尚未安装 Python，可只构建抽奖表：
`powershell -ExecutionPolicy Bypass -File tools/build_lottery_configs.ps1`。
从《通关存档效果.xlsx》的“积分道具”工作表同步时，先运行
`powershell -ExecutionPolicy Bypass -File tools/import_lottery_points_items.ps1`；
它会同步道具定义、四个奖池的通配成员表、内容目录及内容目录 Lua 投影。

## 表职责

- `lottery_currency_definitions.csv`：抽奖券身份、显示名、获取策略。
  `special_lottery_ticket`（特殊抽奖券）在此声明为
  `external_purchase_only`。它也是 `物品系统/content_catalog.csv` 中的
  逻辑内容资产，但不得加入使用木材/金币购买的 `shop_entries.csv`。
- `lottery_pool_definitions.csv`：奖池的公开名称、描述、使用哪种券及
  单抽/十连消耗。
- `lottery_quality_weights.csv`：品质权重。仅服务端加载，禁止加入
  Panorama 文件或快照协议。
- `lottery_pity_rules.csv`：批量抽取保底规则。`trigger_mode=batch_only`
  表示只有一次请求直接抽取指定数量时生效，不能由多次单抽累计触发。
- `lottery_item_definitions.csv`：道具显示、类型、期限、图标类型、品质、
  重复分解积分、积分兑换及对齐的 `effect_ids`/`effect_values` 数组。
  数组中的每个 ID 必须存在于 `player_gameplay_stats.csv`。图标内容与
  品质框独立配置，禁止把品质框烘焙成每件道具图标的数据依赖。
- `lottery_pool_items.csv`：奖池与道具的多对多关系，以及同品质内部权重。
  `item_id=*` 表示纳入全部启用道具，运行时仍按品质池分组后等权抽取。
- `玩家档案系统/map_level_effect_rules.csv`：地图等级的派生增益规则。
  道具只增加 `map_level`，城墙收益统一由该表计算，禁止复制到每件道具。

## 积分道具效果

- 当前工作簿共有 89 条积分道具定义，其中 88 条启用。“龙骑尖兵1型”没有
  效果文本，保留 ID 但不入池、不允许兑换，避免发出无效果奖励。
- 兑换积分严格反推品质：188=N、588=R、1288=SR、2388=SSR、5000=UR。
  “薪火余烬”的 `58/个、5000/100` 例外按 5000 档归为 UR。
- 首次获得时，内容库存、增量后的 `save.gameplay_stats` 与
  `save.lottery_applied_item_effects[item_id]` 在同一档案修订中提交。
  `PLAYER_PROFILE_CHANGED`、`PERMANENT_REWARD_EFFECTS_CHANGED` 和 `UI_DIRTY`
  会继续刷新英雄、箭塔、城墙、伐木工、金矿、资源及 HUD；重复抽取只分解
  积分，不再次写入属性。旧存档中已拥有但没有幂等标记的奖品会自动补写一次。
- `map_level` 是玩家永久基础信息，默认0级。当前有8件UR道具各提供1级；
  每级统一派生 `wall_health_bonus_pct +1` 和 `wall_health_per_second +5`。
  历史已拥有道具使用独立的 `:map_level:v1` 标记补发，不会重发旧属性。
- `effect_status=partial` 表示静态属性已经生效，但英雄/皮肤解锁、
  特殊建筑、按胜场/鱼数成长等复合机制尚缺权威数据或事件接口。具体缺口记录
  在每条道具的 `notes`，不得把这些机制误报为已完成。

## 当前临时数值

- 地图池：N 68.5%、R 25%、SR 4%、SSR 1.5%、UR 1%。新增的 UR 1%
  从原 N 69.5% 中扣除，避免改变 R/SR/SSR 公布概率。一次直接十连至少
  获得一件 SR 或更高品质；连续进行十次单抽完全按单抽概率，不触发保底。
- 修仙、龙骑、暑期：临时联调概率为 N 59.5%、R 25%、SR 4%、
  SSR 1.5%、UR 10%。一次直接十连至少获得一件 UR；连续进行十次单抽
  不触发十连保底。
  10% 是基础权重；仅统计直接十连时，叠加批次保底后的理论平均 UR
  产出约为 13.49%，正式上线前必须结合付费价格重新核定。
- 三个特殊池暂时共用全部已启用积分道具。正式主题道具到位后，只调整
  `lottery_pool_items.csv`。
- UR 重复分解暂定 1000 星悦积分；该经济数值仍需最终确认。

## 支付边界

客户端只能提交 `pool_id`、抽数和请求 ID。特殊抽奖券应由支付后台验证
订单后，以幂等订单号写入玩家内容背包；客户端不得直接提交“增加券”请求。
本地 `mock_account_10001` 配置了 1000 张特殊抽奖券，仅用于 Workshop
Tools 联调，不代表生产发放规则。

服务端 Lua 与 Panorama 分表可以阻止普通客户端通过 UI 事件直接读取概率，
但随 Workshop 包下发的资源仍可能被高级用户离线分析。若概率表、付费库存或
开奖结果需要达到真正的商业保密与防篡改等级，最终抽取、扣券和发奖必须迁移
到受控 HTTP 后台；Dota 服务端只提交幂等请求并展示后台签名结果。
