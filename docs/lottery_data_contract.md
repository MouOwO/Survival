# 抽奖数据与联调约定

抽奖配置的主编辑入口是 `data/csv/抽奖系统`。配置修改后应运行
`build_configs.bat`，生成服务端 Lua，再完整重开测试局。
若本机尚未安装 Python，可只构建抽奖表：
`powershell -ExecutionPolicy Bypass -File tools/build_lottery_configs.ps1`。
从《通关存档效果.xlsx》的“积分道具”工作表同步时，先运行
`powershell -ExecutionPolicy Bypass -File tools/import_lottery_points_items.ps1`；
它会同步道具定义、内容目录及内容目录 Lua 投影，保留已配置的宝箱成员表；各宝箱截图名称与品质覆盖旧工作簿。

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
  重复分解积分、积分兑换、`max_owned` 最多持有量及对齐的
  `effect_ids`/`effect_values` 数组。
  数组中的每个 ID 必须存在于 `player_gameplay_stats.csv`。图标内容与
  品质框独立配置，禁止把品质框烘焙成每件道具图标的数据依赖。
- `lottery_pool_items.csv`：奖池与道具的多对多关系，以及同品质内部权重。
  `item_id=*` 表示纳入全部启用道具，运行时仍按品质池分组后等权抽取。
- `玩家档案系统/map_level_effect_rules.csv`：地图等级的派生增益规则。
  道具只增加 `map_level`，城墙收益统一由该表计算，禁止复制到每件道具。

## 积分道具效果

- 当前工作簿共有 89 条积分道具定义，其中 88 条启用。“龙骑尖兵01型”没有
  效果文本，按用户要求登记在第三宝箱清单中但保持禁用，不抽取、不兑换，等待后续补充。
- 旧工作簿按兑换积分反推品质：188=N、588=R、1288=SR、2388=SSR、5000=UR。
  2026-09-29 用户截图优先：回复精粹为 R、极品钓鱼杆为 SSR；暂保留其原兑换价格和重复分解积分，等待用户提供经济数值。
  “薪火余烬”的 `58/个、5000/100` 例外按 5000 档归为 UR。
- 首次获得时，内容库存、增量后的 `save.gameplay_stats` 与
  `save.lottery_applied_item_effects[item_id]` 在同一档案修订中提交。
  `PLAYER_PROFILE_CHANGED`、`PERMANENT_REWARD_EFFECTS_CHANGED` 和 `UI_DIRTY`
  会继续刷新英雄、箭塔、城墙、伐木工、金矿、资源及 HUD；重复抽取只分解
  积分，不再次写入属性。旧存档中已拥有但没有幂等标记的奖品会自动补写一次。
- 当前所有积分道具的 `max_owned=1`。抽取或积分兑换时，服务端按实际库存数量
  与该字段比较：未达到上限则入库并生效，达到上限后再次抽到才按品质分解积分；
  同一次十连也会逐件更新数量。将来若某件改为可持有多件，只需提高该行的
  `max_owned`，每个允许持有的副本使用独立幂等标记叠加效果，超过上限才分解。
- `map_level` 是玩家永久基础信息，默认0级。当前有8件道具各提供1级（其中极品钓鱼杆按截图为SSR）；
  每级统一派生 `wall_health_bonus_pct +1` 和 `wall_health_per_second +5`。
  历史已拥有道具使用独立的 `:map_level:v1` 标记补发，不会重发旧属性。
- `effect_status=partial` 表示静态属性已经生效，但英雄/皮肤解锁、
  特殊建筑、按胜场/鱼数成长等复合机制尚缺权威数据或事件接口。具体缺口记录
  在每条道具的 `notes`，不得把这些机制误报为已完成。

## 当前临时数值

- 地图池按用户确认的两张截图限定 30 种：N 10、R 5、SR 5、SSR 10，无 UR。
  清单见 `data/lottery/map_pool_reference_20260929.json`。使用显式成员，新增其他道具不会自动进入地图池。
- 地图池单次抽奖概率已由用户2026-09-30截图确认：N69.5%、R25%、SR4%、SSR1.5%，合计100%，无UR。
  公告公开文本存放在 `lottery_pool_updates.single_draw_probabilities`，客户端从所选奖池的服务器快照读取，不硬编码或复用其他宝箱概率。
  其余三个宝箱的正式概率仍待用户提供。
  地图与修仙一次直接十连至少获得一件 SSR；连续十次单抽不触发批次保底。
- 修仙池按2026-09-30截图限定26种：UR 7、SSR 9、SR 5、R 5，无N；清单见 `data/lottery/cultivation_pool_reference_20260930.json`。
  正式概率待用户提供；仅本地联调暂将原N权重并入R，得到R 84.5%、SR 4%、SSR 1.5%、UR 10%，不代表发布数值。
- 第三宝箱按2026-09-30截图登记27种：UR 7、SSR 10、SR 5、R 5，无N。
  `data/lottery/dragon_knight_pool_reference_20260930.json`记录完整清单；其中龙骑尖兵01型经用户确认先登记待补，成员与道具均禁用，目前可抽26种。
  仅本地联调暂将原N权重并入R：R84.5%、SR4%、SSR1.5%、UR10%；正式概率等待用户提供。
  第三宝箱仍使用金色券，无前置解锁条件，十连至少UR。
- 第四宝箱已按2026-09-30截图登记24种：UR6、SSR8、SR5、R5。
  `data/lottery/summer_pool_reference_20260930.json`为完整草案，`data/lottery/drafts/`存放成员表与10种新增道具定义草案。
  10种新增物品尚无效果，其中包含全部6种UR；因此暂不替换运行奖池，仍保留旧运行配置。
  草案保留金色券与十连保底UR的目标规则；效果及正式概率补齐后才能启用并统一发布。
- 仅名称、品质与前三个宝箱成员按截图对齐；原属性效果、持有上限、兑换价格和重复分解积分均保留。
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
