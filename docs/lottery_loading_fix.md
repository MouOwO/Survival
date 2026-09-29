# 奖池详情空白排查（2026-09-29）

本次不是奖励被删除。CSV 共 89 条道具定义，88 条启用，缺少效果的“龙骑尖兵1型”仍保持禁用；4 个奖池均关联这 88 个启用奖励。

## 原因和修复

客户端 `scripts/vscripts/config/generated/archive_http_bundle.lua` 仍指向旧发布的 `4b28247f…`，云端 `20260923-mode02` 已使用 `4ff1629d…`。使用旧摘要实测返回 `archive_config_mismatch`，因此界面拿不到奖励列表。错误在详情窗口打开前到达时，窗口还会覆盖错误提示，显示“正在读取当前奖池”和空列表。

- 将客户端摘要对齐到正在部署的完整结算包：`4ff1629da141de10ea3702d87b830431e516fe2d15973f168f85ac3174e47e8a`。
- 保留各奖池的加载错误；重新打开详情仍显示原因，成功收到快照后恢复奖励列表。
- 无需改动线上数据库、抽奖物品、支付订单或奖励数量。

## 内容关联

`data/csv/抽奖系统/lottery_pool_definitions.csv` 定义奖池；`lottery_pool_items.csv` 定义奖池包含哪些道具（当前 `*` 表示全部启用道具）；`lottery_item_definitions.csv` 定义奖励效果和图片。后端结算包使用这些表生成快照，`lottery_http_service.lua` 下发，`lottery_ui_remaining_5d5c1152eb.js` 展示详情。

商城商品表是另一套配置。`sync_payment_shop.cmd` 同步商城商品，并不发布新的存档/抽奖结算包。修改抽奖结算 CSV 后，应按 `archive_server_integration.md` 完整构建和发布结算包，同时更新客户端摘要。只在本地重建摘要而不发布服务器会再次产生版本不一致。不能通过关闭摘要校验或填充假奖励解决。

当前本地 CSV 存在尚未发布的默认属性和挑战入口调整，此次没有借修复抽奖将它们覆盖到远端；使用已部署版本的摘要。`server/bundles` 是忽略的构建目录，本次也保存了对应远端包供本地核对。

## 游戏验收

退出当前地图，再进入一局常规模式，打开“抽奖 → 奖池详情”，分别切换 4 个奖池。每池应有 88 个奖励，可滚动查看，点击道具应显示名字、效果和拥有数量。查看详情不需要购买或抽奖；已经打开的旧局需要重开，Lua 配置不会随界面编译自动替换。

已验证：真实 HTTP 快照 4 × 88 项，通过 `LOTTERY_SNAPSHOT_FIXTURE=output/lottery_live_snapshot.json` 注入 `tools/test_lottery_updates.cjs`，详情列表全部渲染；加载失败/重开/恢复回归、Lua HTTP 缓存测试、商城及支付 UI 回归通过，客户端资源编译无失败。尚未在重新进入的实际游戏局中验收。

旧全量脚本 `tools/test_lottery_config_contract.ps1` 仍要求地图等级增加“1% 城墙生命”，与当前表格中的“城墙初始生命 +100、回血 +5”不一致而失败。本次未修改这一无关的玩法规则或为通过测试改写旧断言。
