# V10 存档数据与交互接入说明

本文说明本轮接入采用的数据语义和已有交互，不替代正式配置，也不把组件包的示例数字写入玩家档案。视觉目标来自 V10；名称、数量、条件、等级、效果和动作仍来自项目的正式 CSV、服务端投影及运行快照。

## 正式数据链

- 分类定义：`data/csv/存档系统/archive_categories.csv`。
- 服务端快照：`scripts/vscripts/systems/archive_service.lua` 的 `snapshot_profile()`、各分类投影器和 `survival_archive_snapshot` 事件。
- 原业务控制器：`panorama/src/scripts/custom_game/archive_180de7e38b_titles_compact_v6.js`。分片组装、快照版本检查、增量合并、缓存及业务请求继续由它负责。
- V10 展示语义：`panorama/src/scripts/custom_game/archive_v10_semantics.js`。
- V10 固定外壳和共享组件：`panorama/src/scripts/custom_game/archive_v10.js`，由当前 `archive.xml` 加载。

正式分类有 18 个，其中商城道具原本未启用。V10 参考图中的 16 个侧栏位置按已确认文字显示；另外保留项目已有的星悦积分与称号入口。显示名称调整不更改存档分类 ID、角色 ID、奖池 ID 或已保存的数据。

## 分类映射及数量语义

| V10 显示名称 | 正式 ID／原分类名 | 正式数据及展示规则 |
| --- | --- | --- |
| 通关存档 | `clear`／通关存档 | `archive_achievements.csv`；对应难度累计通关次数／该成就目标次数。累计值可超过较低目标，不截为目标值；是否激活采用服务端 `completed`。 |
| 虚空之影 | `shadow`／虚空之影 | `archive_shadow_items.csv`；当前持有数量，有真实 `max_owned` 才显示分母。数量大于 0 已拥有，数量等于 0 未拥有；上限不作为解锁门槛。 |
| 地图等级 | `map_level`／地图等级 | `archive_map_levels.csv`；角标采用快照 `online.level`／条目配置的等级里程碑，显示 `LV当前/目标`。原行 `count/target` 是在线分钟，保留供 Tooltip 展示在线时长，不误写成物品数量。 |
| 上班福利 | `work`／上班福利 | `archive_work_items.csv`；实际等级、激活状态和成本分开处理。项目现有一次激活条目的 `max_level=1`，显示 0/1 或 1/1，不套用参考图的多级升级示例；消耗仍为软妹币。 |
| 福利礼包 | `gift`／福利礼包 | `archive_welfare_rewards.csv`；项目当前是累计胜利及共同胜利成就，采用原条目的次数、门槛、`progress_kind` 和效果。没有把参考图的礼包、宝箱或宝石示例新增为真实奖励。 |
| 神兵碎片 | `fragment`／神兵碎片 | `archive_fragment_definitions.csv`、`archive_fragment_levels.csv`；角标是当前持有碎片／真实持有上限。神兵等级单独保留在 Tooltip，不能按剩余碎片重新推算等级或历史累计。晋升规则采用原配置。 |
| 秘法牢笼 | `pet`／秘法牢笼 | `archive_cage_items.csv`；当前持有材料数量及真实上限。服务端当前返回已有材料，保持原投影结果，不从预览补出新的正式物品。 |
| BOSS存档 | `boss`／boss存档 | `archive_boss_achievements.csv`；主线进攻／波次 BOSS 累计击杀次数／当前门槛，采用原通行证门槛及激活规则。不会把其他挑战击杀合并进指标。 |
| 积分道具 | `points`／积分道具 | 原签到道具与抽奖库存投影；按每条目的持有数量和真实上限展示。栏目名称不代表新增积分兑换或购买动作。 |
| 商城道具 | `shop`／商城道具 | CSV 原为 `enabled=0`、`renderer=placeholder`，没有正式服务端条目投影。V10 固定侧栏保留此入口；点击、关闭后重开和显式刷新均显示本地未启用空目录，不向服务端提交该禁用分类请求，也不启动无效重试。不能编造商品、价格或购买入口。 |
| 无尽存档 | `endless`／无尽存档 | `archive_endless_achievements.csv`；原配置同时包含无尽积分门槛与历史最高通关层数门槛，依据 `progress_kind=score/wave` 区分，条件及目标逐条读取，不能全部改成积分或波次。 |
| 钓鱼存档 | `fishing`／钓鱼存档 | `archive_fishing_items.csv` 与 `profile.save.fishing_inventory`；持有数量／真实上限。库存未同步时 `count_known=0`，显示未知，不能把服务端占位 0 显示为已确认未拥有。 |
| 存档建筑 | `building`／存档神器 | `archive_building_items.csv`、`archive_building_rules.csv`；建筑当前等级／配置等级上限，显示 `LV当前/上限`。激活与满级状态不同；每项成本及信仰值仍采用原配置。 |
| 我的前男友 | `friend`／我的好基友 | `archive_social_items.csv` 的 `friend` 奖池；原角色名称、持有数量、上限、效果和奖池规则保持不变。侧栏采用 V10 名称，原业务 ID 不更改。 |
| 我的前女友 | `ex`／我的前女友 | `archive_social_items.csv` 的 `ex` 奖池；角色持有数量、真实上限和叠加效果来自原数据，保留邀请函及原抽奖入口。 |
| 神兽 | `beast`／瑞兽赐福 | `archive_social_items.csv` 的 `beast` 奖池；原神兽数量、上限、效果和奖池规则保持不变，消耗原福签。 |
| 星悦积分（原有额外分类） | `starjoy_points`／星悦积分 | `archive_starjoy_levels.csv` 与服务端 `starjoy`；累计获得积分／各条目门槛，等级和可用余额单独保留。累计积分与可花余额不同，兑换不把累计进度清零。 |
| 称号（原有额外分类） | `titles`／称号 | `archive_titles.csv`、原称号投影与装备状态；显示原称号和 Tooltip，角标不伪造物品数量。是否解锁、是否穿戴分别读取。 |

## 数量、筛选与 Tooltip

- 数量缺失、`null`、无效数字、负数或显式 `count_known=0` 都作为未知，显示「—」；存在真实上限时可显示「—/上限」。未知不会进入已拥有或未解锁筛选。
- 持有类没有真实上限时只显示当前数量。成就目标和等级上限采用各自正式字段，不套用持有类容量规则。
- 虚空之影采用生成的正式 CSV 目录合并服务端快照。完整成功快照未包含的正式条目可确认当前数量为 0；加载中、失败、缺少列表或未组装的增量数据不会被补成 0。
- 正式配置及快照中的新增条目不会受参考图 23 项限制。组件包的可见图标数不是分类容量；没有对应图标时记录缺失并显示明确占位，不借用其他条目图标。
- 所有分类采用同一个方形图标、图内右上角独立数量文字、下方名称组件。数字没有数量底板，名称和数值不写入图片。
- Tooltip 继续显示条目实际效果、条件、等级、成本及来源说明；数量说明与右对齐数量是两个独立文本组件。神兵分级效果保留原等级着色逻辑。
- 类别切换清空旧 Tooltip，更新右侧内容和左侧选中态；外壳背景、导航、资源位置、关闭按钮、上下横线和金属挂钩保持同一套组件。
- 资源栏读取既有 `SurvivalCommerceWallet.GetCatalog().balances`，初次未知时保持「—」。首次开窗和关闭后重开各调用一次既有只读目录刷新，正式钱包模块对进行中的请求去重；切分类、快照更新和存档显式刷新不会追加目录刷新。真实目录结果到达后更新独立数字，不触发购买，也不把未知余额填成 0。

## 保留的动作

V10 改动展示层；原业务按钮及事件继续由原控制器负责，没有接入真实支付或新增奖励行为。

| 动作 | 继续使用的事件／约束 |
| --- | --- |
| 上班福利激活／升级 | `survival_archive_work_upgrade`；保留正式软妹币成本、`can_upgrade`、当前 `expected_level`、保存中状态及重复点击拦截。项目当前一次激活条目不编造额外等级。 |
| 存档建筑激活／升级 | `survival_archive_building_upgrade`；保留信仰值、每项成本、等级上限、`expected_level`、保存中状态及服务端拒绝后重试。 |
| 三种角色／神兽抽奖 | `survival_archive_social_draw`；保留原奖池、券数量、成本、剩余库存、请求 ID、保存中状态和重复点击拦截。义帖、邀请函、福签不会互相替换。 |
| 神兵碎片晋升 | `survival_archive_promote`；保留原 `fragment_id`、配置成本、资格和请求 ID。Tooltip 使用真实晋升目标名称，不能把内部 ID 当名称显示。 |
| 称号穿戴／卸下 | `survival_archive_title_equip`；保留原解锁、当前穿戴、提交状态、拒绝恢复及原试穿行为。 |

三种社会收集奖池在 `archive_social_rules.csv` 的正式配置为：`friend` 消耗义帖、`ex` 消耗邀请函、`beast` 消耗福签；当前每次成本均为该配置中的 1 张。实际显示读取运行快照的 `currency_name`、`tickets`、`draw_cost`，不把该数值硬编码为新增业务规则。

## 本轮自动检查结果

以下检查已通过；它们验证组件数据和交互，不替代原生游戏画面的视觉验收。

| 检查 | 通过的主要内容 |
| --- | --- |
| `node tools/tests/archive_v10_semantics.test.cjs` | 正式目录合并；零／未知／真实上限；成就累计超过目标；新增条目容量；激活与等级分离；地图等级及无尽层数／积分；不修改输入快照。 |
| `node tools/tests/archive_open_profile_refresh.test.cjs` | 当前 V10 脚本链；1,000 次相同显示数据的修订不重建／重写样式／重算适配；增量更新、卡片及数量 Label 复用、悬停实时刷新；未知筛选；钱包首开只刷新一次、切分类／快照不额外刷新、重开可刷新、真实结果前显示未知；升级、抽奖、晋升的重复／拒绝／保存中保护；100 次闭窗更新；独立 Tooltip 数值右对齐；服务端不含禁用商城分类时，点击／重开／显式刷新均为本地空态、零禁用分类请求，返回后恢复原缓存。 |
| `node tools/tests/archive_v10_lifecycle.test.cjs` | 唯一固定外壳；分类切换不更换背景及横线；未知筛选；旧视觉缓存复建；重开不累加订阅；控制器重载、完整重载、子树替换；旧按钮／订阅／计时器隔离；释放后不能复活；旧紫色样式不能覆盖 V10 几何。 |
| `node tools/tests/archive_purple.test.cjs` | 原数量语义、紧凑单元、称号、头像尺寸及 Tooltip 边界保持可用。 |
| `node tools/tests/archive_fragment_tooltip.test.cjs` | 原 184 条神兵等级效果、锁定着色、条件、晋升名称及数量／等级区分。 |
| `node tools/tests/archive_lifecycle.test.cjs` | 原分片／增量基线恢复、请求合并与重试、旧订阅／API／计时器及失效上下文隔离。 |
| `node tools/tests/archive_endless_refresh.test.cjs` | 无尽更新不反复重建存档；闭窗缓存、即时切换／重开及请求去重。 |
| `node tools/tests/archive_callback_probe.test.cjs` | 原 Tools 回调探针、动态视图 API、热重载及非 Tools 环境隔离。 |
| `node tools/tests/archive_rarity.test.cjs` | 原五档正式品质图标不被锁定状态及样式刷新破坏。 |

## 预览与验收范围

`tools/archive_v10/preview.cjs` 从当前启用的 Panorama XML、脚本和样式组装可运行浏览器预览，正式名称、描述、图标和上限读取项目配置。浏览器状态中的数量、进度、钱包及动作模拟是显式的只读验收样例，不向真实游戏服务端发送事件、不连接账号或支付、不写真实存档。

多分类组合、数量边界、长列表和多分辨率可在组件预览中检查，但浏览器对原生 Panorama 布局、字体栅格化及 DOTA 图标控件的模拟不等于游戏内验证。原生截图及各分类的实机覆盖以总交付的验收记录为准；未取得对应实机画面的项目不能标记为已游戏验收。

本轮数据文档没有修改 CSV、服务端结算规则或玩家存档。组件包的 `data_preview.json`、Tooltip 示例、23 项可见布局及示例资源数字均不作为正式奖励配置。
