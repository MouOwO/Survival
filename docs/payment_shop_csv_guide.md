# 商城商品改表与一键同步

支付入口支持微信与支付宝，使用同一份商品 CSV、价格、限购和礼包奖励。游戏客户端读取支付服务器发布的同一份商品列表。当前上架原来的 5 件 +100 属性商品（每件 50 元），以及特殊抽奖券（每张 50 元）。支付宝接入与验收范围见 [双渠道支付说明](payments/alipay_integration_20260930.md)。

**特殊抽奖券购买入口**：特殊奖池的券数量旁“＋”按钮，或“商城 → 道具与材料 → 特殊抽奖券 ×1”。点击后先显示商品确认页，选择微信或支付宝，再点击对应的“购买 ¥50.00”。微信在游戏内显示付款码；支付宝当前需主动点击打开官方收银台，开通扫码权限并启用后也会在游戏内显示付款码，详见 [内置二维码说明](payments/alipay_native_qr_20260930.md)。每次支付获得 `special_lottery_ticket` ×1，可重复购买。商品 ID 为 `special_lottery_ticket_single`，商品表 `price_yuan=50.00`、`purchase_limit=0`，奖励表为 `item,special_lottery_ticket,1`。普通地图抽奖券仍由玩法产出。

**签到月卡配置（2026-10-14）**：签到面板的“开通20元／续费20元”进入 `archive_pass_monthly` 的确认页，价格 **20 元／30 天**。打开确认页不创建支付订单；玩家选择支付方式并点击购买后，既有支付服务才按服务端价格 **2000 分**下单。月卡权益为 `archive_pass`；实际付款验签、金额核对、发放及存档刷新继续走原支付链路。有效月卡续费保留剩余天数，再增加 30 个 24 小时；到期或撤销后重新开通从付款发放时起算。旧永久 VIP 和永久月卡不改写；永久月卡禁止重复购买。代码验证和目录发布不代表真实付款验收。

月卡上线必须先更新支付代码和时限发放函数，再发布商品。直接改客户端按钮、只同步 CSV 或重跑旧 `upgrade_csv_shop.sql` 都不能安装时限权益。按已有命名支付版本流程执行：

1. 本地运行 `python tools/build_payment_catalog.py --output output/payment_catalog.json`；运行月卡 CSV、发布门禁、Lua 和 Panorama 专项。用 `python tools/build_payment_release.py --release-id 20261014-payment01` 打包新的命名版本；该目录必须不存在。打包器自动包含本次 `.py`／`.sql` 和基础定义，不包含密钥。
2. 把已核对哈希的包放入 `/opt/goufayu/payments/20261014-payment01`，目录 JSON 放入临时路径。调用新版本 [upgrade_monthly_pass.py](../server/payment_backend/upgrade_monthly_pass.py) 的 `validate` 动作，并传目录文件、SHA256 和审阅时 `current` 指向的绝对版本路径。该动作校验命名版本清单与商品包，在**外层回滚事务**中按 `goufayu_owner` 应用 [SQL](../server/payment_backend/upgrade_monthly_pass.sql)、目录和 [数据库专项](../server/payment_backend/test_monthly_pass_database.py)，随后回滚；只使用随机合成账号，包含续费、到期、撤销、金额错误、重复回调、永久 VIP／月卡、订单创建后改价改时长及测试重置。失败时不会发布。
3. 审阅验证结果后，用相同参数运行 `activate`。它重新验证、运行回滚测试、调用既有 `deploy.backup()` 保存游戏与支付同一快照；随后在锁超时 5 秒的事务中应用 SQL 与目录，核对已有订单／玩家数据哈希未变，再切换命名版本、只重启 `goufayu-payment.service` 并检查健康。账号白名单、凭据、支付渠道配置和游戏服务保留。切换失败时按目录哈希恢复旧目录并恢复旧支付代码；增量时限发放函数保留，以继续正确处理切换期间可能产生的不可变月卡订单。不要运行初次安装 `deploy.activate()` 或旧 CSV 表结构升级。
4. 核对动作返回 `catalog_hash` 与本地一致。以后改商品可以继续执行 `sync_payment_shop.cmd` 或 `tools/sync_payment_shop.ps1`；新编译器核对完整目录和基础定义。发布门禁检查 `payments.entitlement_days(jsonb,text)` 已存在，缺少升级会在改写任何商品前拒绝发布。只在本地检查时加 `-CheckOnly`。
5. 同步生成的 `archive_daily_rules.lua`、游戏支付／存档 Lua 与两份 Panorama JS；新对局会注册月卡支付入口。实机核对签到按钮可用、“30天 · 20元”、确认页 `¥20.00`、真实服务器月卡目录和付款后到期日；实际付款由玩家单独执行。本地 UI 通过不代表远端版本已上线。

环境沿用现有配置：游戏服务器仅从 `survival_fishing_api_token` ConVar 取 Bearer token；已有 `tools/aliyun_game_test_auth.py` 注入工具负责本地测试凭据。支付代码由 `/opt/goufayu/payments/current` 提供，服务为 `goufayu-payment.service`；支付渠道和账号许可由 `/etc/goufayu-payment/config.json` 管理，数据库连接沿用 `deploy.connection()` 的 PostgreSQL service/passfile。以上路径来自项目源码／说明，本次没有读取或修改其中的密钥。启用月卡入口不会放宽白名单、支付鉴权或测试重置权限。

部署端命令形式如下（使用新命名目录的 Python 路径；`EXPECTED_CURRENT` 来自审阅过的 `readlink -f /opt/goufayu/payments/current`，不接受运行过程中自动更新该预期）：

```sh
NEW_RELEASE=/opt/goufayu/payments/20261014-payment01
"$NEW_RELEASE/.venv/bin/python" "$NEW_RELEASE/payment_backend/upgrade_monthly_pass.py" \
  validate "$CATALOG_PATH" "$CATALOG_SHA256" "$EXPECTED_CURRENT"
"$NEW_RELEASE/.venv/bin/python" "$NEW_RELEASE/payment_backend/upgrade_monthly_pass.py" \
  activate "$CATALOG_PATH" "$CATALOG_SHA256" "$EXPECTED_CURRENT"
```

新目录的 `.venv` 沿用既有命名版本环境，不能链接经过 `current`。脚本不会调用支付网关建单；`gateway_orders_created=0`。目录激活会启用可购买商品，实际付款仍必须由玩家点击购买并付款。

## 最简单的操作

1. 用 Excel/WPS 打开 `data/csv/商城支付系统/payment_products.csv`，修改商品名、价格或上下架。
2. 如需改实际奖励，再修改同目录的 `payment_rewards.csv`。**只改商品名或说明，不会改变发奖内容。**
3. 保存为 **CSV UTF-8（逗号分隔）**，关闭表格文件。保留首行英文表头和以 `#` 开头的说明行；不要另存成 `.xlsx` 覆盖 CSV。
4. 双击项目根目录 **`sync_payment_shop.cmd`**。它会检查表格、编译商城及所用图标，再同步服务端。看到 **`SHOP_SYNC_PASS`** 才表示同步成功；出现错误时保留窗口中的报错。
5. 回到游戏，打开顶部“商城”，或右侧“商品商城”。窗口立即显示本局已有列表；打开期间约每 20 秒核对一次服务端数据，更新后自动显示。刚同步完表格时最多等待约 20 秒，不需要反复开关窗口。

本次更新涉及游戏脚本和商城 UI，首次请重新进入一局。以后只修改这三张商品表，正常情况下不用重开客户端。脚本使用本机已有的 SSH 部署密钥，不需要输入微信私钥。

## 商品缓存与版本校验

当前完整的已发布商品表在支付数据库中；同步 Lua 不等于把这张表和个人购买状态打包到了客户端。每局首次成功获取商品后，HUD 保留本局缓存，关闭商城不会删除它。20 秒内重复打开或从商城进入收银页，会直接复用缓存；相同的进行中请求会合并。商城与收银页都关闭时停止常规商品轮询，付款到账或测试重置后仍会主动刷新一次。

校验分两部分：`catalog_hash` 对应商品配置，持有数量、限购和可购买状态对应当前账号。同一个配置版本也必须接收新的购买状态。服务端返回不同的商品内容或状态时覆盖本局缓存；内容相同时保留现有卡片，不重新创建 UI。临时忙碌、网络失败、超时只显示提示并自动重试，不清空已有列表；登录会话失效则清除缓存，防止使用上一会话的数据。

游戏 Lua 同样按账号及对局隔离缓存，合并进行中的商品请求，并在 2 秒内复用成功结果，避免快速重开触发限频。创建订单、查询／关闭订单、测试重置会使这个短缓存失效。下单只提交商品 ID 和支付渠道，价格、限购与完整发奖仍由支付服务器校验；已有订单保留创建时的价格和奖励。

## 三张表分别管什么

| 文件 | 一行表示什么 | 常改内容 |
| --- | --- | --- |
| [payment_products.csv](../data/csv/商城支付系统/payment_products.csv) | 一个商品 | 商品名、分类、价格、限购、上架 |
| [payment_rewards.csv](../data/csv/商城支付系统/payment_rewards.csv) | 商品包含的一项奖励 | 属性 ID、增加多少、道具数量、权限 |
| [payment_categories.csv](../data/csv/商城支付系统/payment_categories.csv) | 一个商城分类 | 分类名称、顺序、显示 |

原商城的六个分类保留：武器与装备 `weapon`、道具与材料 `item`、科技与服务 `technology`、挑战商店 `challenge`、转职挑战 `rebirth`、礼包 `bundles`。当前五件属性商品在“科技与服务”。没有上架商品的分类会显示“暂无上架商品”。分类名称只控制展示，不会自动获得对应武器或挑战权限。

## 商品表怎么填

| 列名 | 填写方式 |
| --- | --- |
| `sku` | 唯一商品编号，4～64 位小写英文字母、数字、下划线，以字母开头。已售商品不要修改；新增商品使用新编号。 |
| `display_name` | 游戏里显示的商品名。 |
| `category_id` | 从分类表复制英文分类 ID，如 `bundles`。 |
| `product_type` | `single` 普通商品；`bundle` 礼包。两者都支持多项奖励；礼包分类使用宽卡片展示各项内容。 |
| `price_yuan` | **单位是元**，例如 `50.00`。最多两位小数，目前范围 0.01～10000 元。 |
| `purchase_limit` | `1` 为限购一次；`0` 为不限次数；也可填写其他正整数。永久道具和权限仍受自身持有上限约束。 |
| `enabled` | `1` 上架，`0` 下架。 |
| `sort_order` | 数字越小越靠前。 |
| `icon` | 已存在的图片路径，例如 `custom_game/archive_items_v2/lottery_attribute_crystal.png`。不要写硬盘绝对路径。 |
| `description` | 商品说明，需要与奖励表一致。 |
| `ownership_id` | 唯一持有标记，沿用示例格式。**已发布商品不要修改**；服务端会拦截修改。 |

改价格或奖励只影响之后新建的订单。已经生成的二维码订单按创建时的价格、奖励结算；已经买过的奖励也不会因改表自动增加或减少。如果要售卖一个新的版本，建议新增 `sku` 和 `ownership_id`。

正式模式会同时检查购买历史与持有数量。测试账号通过 `refreshmoney` 清除购买内容后可以重新购买，但历史支付记录保留；`refreshdata` 会把测试账号恢复为新号默认状态。这两个入口仍有 `TODO(PAYMENT_TEST_ONLY)` 标记，并受 Tools 模式、账号白名单和服务端开关限制。发布正式服前要关闭测试重置及测试重复购买。

## 奖励表怎么填

每一项奖励独占一行；用相同 `sku` 关联到同一个商品。所有启用行会一起发放。

| 列名 | 填写方式 |
| --- | --- |
| `reward_id` | 唯一奖励行编号，不能重复。 |
| `sku` | 复制商品表的商品编号。 |
| `reward_type` | `stat` 属性；`item` 存档道具／付费抽奖券；`entitlement` 已登记权限。 |
| `target_id` | 对应的属性、道具或权限英文 ID。 |
| `amount` | 属性增加值或物品数量；权限固定填 `1`。必须大于 0。 |
| `display_name` | 奖励清单显示名称，如“初始木材”。 |
| `enabled` | `1` 发放这行奖励；`0` 停用这行。商品必须至少有一项启用奖励。 |
| `duration_days` | 仅 `entitlement,archive_pass` 可填写整数 `1`～`365`；月卡填 `30`。空值保持原永久权限语义，属性／道具／VIP 权限不得填写。时长随订单奖励快照保存，后续改表不改变已下单权益。 |

目前五个属性的 ID：

| 奖励 | `reward_type` | `target_id` | `amount` 示例 |
| --- | --- | --- | --- |
| 初始木材 +100 | `stat` | `initial_wood` | 100 |
| 初始金币 +100 | `stat` | `initial_gold` | 100 |
| 城墙初始护甲 +100 | `stat` | `wall_armor` | 100 |
| 城墙初始血量 +100 | `stat` | `wall_initial_health` | 100 |
| 箭塔固定攻击力 +100 | `stat` | `tower_attack_flat` | 100 |
| VIP 英雄召唤权限 | `entitlement` | `vip` | 1 |
| 虚空之影通行证（永久） | `entitlement` | `archive_pass` | 1 |
| 特殊抽奖券 ×10 | `item` | `special_lottery_ticket` | 10 |
| 氮化合金护墙 ×1 | `item` | `lottery_nitride_alloy_wall` | 1 |

**礼包现成样例**：`starter_bundle_v4`（启程礼包）已经配好“五项属性各 +100、VIP 权限、特殊抽奖券 ×10”，价格 50 元，默认 `enabled=0` 下架。想测试它，先按需调整奖励，把商品表这一行 `enabled` 改为 `1`，再运行同步即可。通行证可另加一行 `entitlement,archive_pass,1`。这里只写奖励表中的这三列示意，完整一行仍需保留其余列。

## 哪些效果能完整到账

- `stat`：现有 [player_gameplay_stats.csv](../data/csv/玩家档案系统/player_gameplay_stats.csv) 已启用的数值字段，在线时长不出售。整数属性必须填整数；百分比字段填 `10` 表示 10 个百分点。`map_level` 会按现有规则同时发放地图等级派生属性。
- `item`：现有 [lottery_item_definitions.csv](../data/csv/抽奖系统/lottery_item_definitions.csv) 中已启用、永久、`effect_status=implemented` 的道具。会同时写入道具数量和它的**全部 `effect_ids/effect_values`**，不需要再在奖励表重复写一遍，否则会叠加。
- 付费抽奖券：`special_lottery_ticket` 可以购买；普通 `lottery_ticket` 是玩法产出，不能放进付费礼包。
- `entitlement`：目前接通 `vip` 和 `archive_pass` 的永久权益，到账后通过存档刷新进入现有权限系统。VIP 仍遵守城等级、祭坛、每局英雄数量等玩法条件。

**不能仅靠填表实现**：尚未实现的组合 Buff、开局技能、任意武器装备、任意挑战解锁、未登记权限，以及限时／续期权益。同步工具会报错，不会跳过不认识的奖励。比如齐天大圣旧订单和已有召唤权限继续保留，但它原道具说明还包含未完成的组合效果，当前 `effect_status=partial`，新通用礼包暂不能把它当成“全部效果已实现”的道具出售。

这三张商城表负责组合已有功能。增加全新效果或改动基础属性／道具定义，需要对应游戏逻辑和存档服务一起更新，不能用商城同步代替。

## 付款后怎样核对

1. 打开商品，原版浅色金边的订单确认页显示商品图、价格和全部奖励，多属性礼包可滚动查看。每单固定 1 件，选择微信或支付宝后点击购买才会创建真实订单；随后在同一原版窗口显示二维码或官方收银台入口。关闭再打开商品可继续查看已有订单；需要更换支付方式时先取消当前订单。
2. 微信付款后，服务端验证通知并在同一事务中更新属性、道具、权限和订单。
3. 页面逐项显示本单存档“原值 → 新值”，同时显示本局属性。权限显示到账及本局生效状态。
4. 初始金币／木材在常规模式当前局补加对应差额；新对局继续享受永久加成。城墙和箭塔通过现有属性刷新机制生效；生命上限增加时受伤城墙保持血量比例。面板还会叠加科技、百分比和其他存档加成。
5. 纯净模式、对局结算冻结等模式规则继续有效。已结算时新奖励写入远端，下局生效。

同一订单重复回调不会重复发奖。一项奖励失败时整笔发奖回滚。礼包内若有已达上限的道具、已有权限或将超上限的属性，付款前会禁止购买；若创建订单后玩家状态变化造成冲突，订单转入待人工核对，不能部分发放后当作整单成功。

## 同步出现错误时

- `SHOP_CSV_ERROR`：按提示检查 ID、数值、列数和奖励类型，修好后重新双击。
- “基础定义不同”：本地基础道具／属性表和已部署游戏服务不一致。先完成基础功能的同步；不要修改服务器数据库来绕过校验。
- `SSH key missing` / 连接失败：这台电脑需要已有部署密钥及网络权限，路径默认 `%USERPROFILE%\.ssh\goufayu_ecs_ed25519_v2`。脚本支持 `-SshKey "完整路径"`；不要把密钥正文填进 CSV。
- 编译失败：查看 `PAYMENT_UI_BUILD` 前的错误，客户端编译未完成时不会发布新的商品配置。
- 发布后网络回包丢失：重新运行相同 CSV 即可，商品发布可重复执行，不会新增订单或重发奖励。

只检查本地表格可运行：`powershell -NoProfile -ExecutionPolicy Bypass -File tools/sync_payment_shop.ps1 -CheckOnly`。

## 本次验证记录（2026-09-29）

支付后端已更新为 `20260929-payment12`。已完成 26 项本地 CSV／支付测试、真实 PostgreSQL 回滚测试、游戏脚本与界面行为测试，并实际运行完整同步。实机已检查原版分类卡片、50 元价格和已拥有状态；六个商品图标（含下架样例）已编译。数据库验证覆盖五件单属性商品、组合属性＋道具＋双权限、重复回调、失败整单回滚、测试清空再购买、属性上限与购买冲突、下单后改价改奖励保持原单，以及旧订单和玩家数据保留。

HTTPS 已确认返回 6 个分类和 5 件 50 元商品；测试账号已购初始木材数量仍为 1，原齐天大圣道具与旧付款单保留。此次验证没有新增真实付款，也未清空真实账号。微信支付此前已由实际付款验证；新礼包此次使用数据库回滚测试，不把它记为新的真实付款验收。支付宝仍未开放。
