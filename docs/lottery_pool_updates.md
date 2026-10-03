# 宝箱更新红点

每次打开抽奖页面或点击宝箱，服务端记录该宝箱的访问版本。更新仅在“奖池详情”按钮显示当前宝箱的红点，不弹出公告，宝箱标签不显示红点；打开对应奖池详情才记录详情已读版本并清除红点。

记录沿用 `save.lottery_state.pools[pool_id]`，字段为 `visited_revision`、`notice_revision`、`details_revision`。当前本地档案提供器负责持久化。HTTP 权威档案模式禁止本地写入，正式远程上线时需要后台提供对应已读事务，不能把本地已读当成远程保存成功。

## 配置入口

- `data/csv/抽奖系统/lottery_pool_items.csv`：每行填写唯一 membership_id、宝箱 pool_id、道具 item_id、同品质权重 item_weight 和 enabled。自由增删各宝箱成员；精确配置前先删除该宝箱的 `item_id=*` 通配行，避免重复成员。地图宝箱按2026-09-29截图限定30种，修仙宝箱按2026-09-30截图限定26种；第三宝箱按截图登记27种（龙骑尖兵01型待补效果，暂禁用），前三池均使用显式成员。第四宝箱24种已登记到data/lottery草案，但因10种新增物品（含全部UR）效果缺失，暂不替换运行成员表。
- `lottery_item_definitions.csv`：道具名称、品质、图标、效果等定义。
- `lottery_pool_updates.csv`：更新元数据及公开公告。`single_draw_probabilities`存放用户确认的单次抽奖概率文案，“开奖公告”读取当前奖池快照中的该字段；空值显示尚未公布。此字段不包含十连保底，保底说明单独展示。不提供定时生效功能。
- `lottery_pool_definitions.csv`、`lottery_quality_weights.csv`、`lottery_pity_rules.csv`：宝箱名称、消耗、概率和保底。

修改后运行 `pwsh -NoProfile -File tools/build_lottery_configs.ps1`，完整重开测试局加载服务端配置。服务端自动计算各宝箱配置指纹，成员、道具、概率、保底或公告变化都会再次提示；无需手动维护版本号。概率与权重仍留在服务端。

奖池详情固定按 UR、SSR、SR、R、N 排序，同品质按道具 ID 稳定排序。

验证：`node tools/test_lottery_updates.cjs`。资源编译：`pwsh -NoProfile -File tools/compile_lottery_updates.ps1`。
