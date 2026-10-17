# 每日登录奖励四格月卡：现有业务复用映射

审计日期：2026-10-17。只读审计当前主工作区；本文件是临时证据，不是新增业务配置。

依据：`C:/Users/Administrator/Downloads/给代码AI的任务.md`。只替换视觉和布局，不增加签到、发奖、开通协议。第四格是空展示槽，不能变成第 28 次奖励。

## 实际入口和所有者

- `panorama/src/layout/custom_game/custom_ui_manifest.xml` 常驻加载 `archive.xml`。
- `archive.xml` 依次加载 `daily_gw2_data.js`、`daily_remaining_5d5c1152eb.js`，实际所有者是后者导出的 `cfg.SurvivalDaily`；`daily_rewards.js` 是旧实现，不是当前运行入口。
- 顶部福利入口调用 `SurvivalDaily.Open(false)`，旧月卡入口可调用 `Open(true)`；同一窗口，`true` 只聚焦已有月卡开通区，不授予权益。
- `DailyGW2Data` 是美术素材和画布元数据，当前 `canvas=[1200,900]`；不包含正式奖励数量或领取资格。
- 当前主工作区的 `daily_remaining_5d5c1152eb.js`、`daily_gw2.css`、`archive.xml` 均已有未提交变动。实现时应窄改，不覆盖这些现有改动。

## 请求与刷新：保持不变

| 动作 | 现有调用 | 参数与约束 |
| --- | --- | --- |
| 首次/打开/刷新 | `survival_daily_request` | `{}`；控制器加载 1 秒后读取，打开立即读取，窗口打开时每 3 秒轮询；`fetching` 防止并行读取；首次无数据时有 8 秒读取超时提示 |
| 领取今日 | `survival_daily_claim` | `{target_day:Number(data.today)}`；不能传格子索引或本机日期 |
| 补领 | `survival_daily_claim` | `{target_day:Number(array(data.missed)[0])}`；现有按钮只补最早一个遗漏日期，不创建新事件 |
| 开通/续费月卡 | `survival_pass_purchase` | `{}`；客户端不传 SKU、价格、时长或权益；服务端按规则选择 `archive_pass_monthly` |
| 服务端刷新 | `survival_daily_snapshot` | `life.Subscribe` 唯一业务快照入口；拒绝旧 sequence 和更早 today 的成功快照 |
| 支付确认 | `survival_payment_open` | 服务端发送 `{sku:rules.pass_sku}` 到已有 payment 控制器；点击开通只打开确认，不创建支付单 |

现有 `PassPurchase` 由 `U.ActionButton.Adopt` 绑定，`U.State.CanActivate` 在 `disabled` 或 `UIBusy` 时拦截；首次操作立即禁用按钮，服务端也有 3 秒节流。仍应保留现有 action 和 State 更新，不能把概念图按钮绑定成新的订单/发奖请求。

## 可直接绑定的快照字段

`systems/archive_daily_rewards.lua:snapshot()` 创建业务视图，`archive_service.lua:daily_snapshot()/send_daily()` 增补同步状态。

| 字段 | 当前语义 / UI 用法 |
| --- | --- |
| `ok`, `error` | 读取成功或失败。失败保留已有快照，显示现有错误/重试状态 |
| `sequence` | 每玩家递增快照序号；旧序号不覆盖新状态 |
| `pending` | 玩家任意存档事务仍在队列，不仅限签到；与本地 `waiting` 一起禁用领取、补签、开通按钮 |
| `today` | 服务端 UTC+8 自然日编号，只用于现有领取目标 |
| `claimed`, `ordinary_status` | 今日是否已领取；`ordinary_status` 为 `claimable/claimed`，不要按概念稿固定勾选前四格 |
| `count` | 历史累计成功签到/补签次数，续费和断签不会重置 |
| `period_id`, `current_day`, `cycle` | 七次循环兼容视图。不要把 period_id 当月份、把 current_day 当系统星期 |
| `calendar28` | 按累计顺序返回的 28 行，左侧 7 列×4 排直接使用此数组 |
| `calendar_start_count` | 当前 28 次展示窗口的累计起点，例如 0、28、56 |
| `calendar_current_day` | 当前展示窗口中的位置 1～28；用于当前格和领取反馈锚点 |
| `calendar28[i].day/absolute_count` | 当前窗口序号/真实累计次序 |
| `calendar28[i].status/is_today` | `claimed/claimable/not_open`，及当前位置标记；分别更新勾选、可领/未来外观 |
| `calendar28[i].rewards[]` | 每格实际奖励列表，元素 `{id,name,count,description,quality}`。名称、图标 ID、数量、说明均从此读取 |
| `has_pass`, `expires_at` | 服务端有效月卡判断与到期时间。UI 不得由付款按钮、购买弹窗打开或本地时间推导已开通 |
| `specials[]` | 当前三项累计奖励，元素 `{id,day,name,description,owned}`，没有 `count`/可领取数量字段 |
| `missed[]`, `makeup_days` | 可补签范围内遗漏自然日；只有有效月卡可补签，服务端再次检查 |
| `price`, `duration_days`, `purchase_enabled` | 正式开通提示和是否可打开付款；当前为 20 元/30 天。`purchase_enabled` 已与支付 provider 可用性相与 |
| `rule_text` | 现有规则说明，可保留规则入口。`subtitle` 无业务判断依赖，新版不显示 |
| `premium` | 旧“周末高级装备”配置明确 `status='unconfigured'`；不得挪成第四项奖励 |
| `claim_result` | `{target_day,ok,pending,error}`，与当前 waiting.target 对应；由它解除拒绝/完成状态 |

## 28 格顺序和真实数量

服务端以累计领取次数取七次循环，`schedule[(absolute_count-1)%7+1]`；28 格只是把该循环展开四轮，周一至周日仅列标题。UI 行列为 `col=i%7,row=floor(i/7)`，不能按今天星期重排、空出未登录日期或重置进度。

每轮实际配置：

1. 成长宝石 `daily_growth_gem` ×3。
2. 回血碎片 `daily_regen_shard` ×3。
3. 攻击宝石 `daily_attribute_gem` ×3。
4. 攻击碎片 `daily_attack_shard` ×3。
5. 生命宝石 `daily_health_gem` ×3，及木材宝石 `daily_wood_gem` ×3。
6. 格挡碎片 `daily_block_shard` ×3，及属性碎片 `daily_attribute_shard` ×3。
7. 金币宝石 `daily_gold_gem` ×3。

`3` 是当前 CSV 的真实值，仍必须绑定 `item.count`，不可把示例数量写死。第五、六列两个真实奖励都应保留；图标优先沿用当前 `SurvivalItemArt.Create` / `SurvivalRewardPresentation.FillIcon`，不换成概念稿图标。

## 月卡三项和第四格冲突

`data/csv/存档系统/archive_daily_rules.csv` 配置 `pass_milestones=7|14|21`，只对应以下三项：

| 顺序 | ID | 名称 | 条件 |
| --- | --- | --- | --- |
| 1 | `daily_wealth_talisman` | 聚财古符 | 有效月卡，累计签到至少 7 次，在成功签到时自动发放 |
| 2 | `daily_ancient_tree` | 古树眷顾 | 同上，累计至少 14 次 |
| 3 | `daily_forest_origin` | 森罗本源 | 同上，累计至少 21 次 |
| 4 | 无 | 无实际权益 | 只保留与左侧第四排一致的空槽；不显示伪造图标、数量、领取勾或锁，不安装领取/发奖动作 |

三项 `max_owned=1`，每次成功签到时会补发已达到门槛但尚未拥有的项；开通月卡本身不会立即触发领取。`owned>0` 是永久已拥有状态，不能当成本次可领取数量，也不应因为月卡到期抹去已拥有勾。

当前 `renderSpecials()` 第 178 行自行构造 `count:1`，不是快照字段。视觉替换时应删除该默认数量，只显示快照确实提供的数量；当前三项快照没有 `count`，因此数量层隐藏。不能把设计中的“1”写进正式状态。第四槽也不能使用 `premium.unconfigured` 或复制第三项填满。

## 保留防重复、拒绝与反馈

- 领取前本地 `waiting` 立即记录 target/day/period/count 与反馈锚点，`waiting || data.pending` 禁用按钮；关闭窗口只把 `waiting.present=false`，不丢弃待定请求，避免重开重复发单/重复庆祝。
- 快照 pending 时不判断成功；匹配 claim_result 的成功或正式 count/ordinary_status 进展才确认；匹配拒绝解除 waiting 并显示服务端 error。进入新 today/period 时清除旧 waiting。
- 现有读取超时只处理“首次无数据”，领取没有单独前端超时；不要为换皮自行改变重试/确认语义。窗口关闭后取消轮询，生命周期 dispose 取消计时器并退订。
- `RewardFX` 必须仍在确认领取成功后才触发，不在点击或付款确认打开时触发；已关闭/跨页的回包不在旧格子播放。
- 服务端按真实 PlayerID、服务端日、首登日、整数/未来日期、已领日期、有效月卡和最近 30 天检查；claim 0.3 秒节流，固定 session+target 命令 ID 防重。
- 存档队列串行执行，复制 save/stats 后结算；processed 命令去重，失败不写入奖励，远端超时/重试有 attempt token 防晚回调。UI 不需要新增发奖接口。
- verified 月卡支付后才更新 `entitlements.archive_pass`；续期从未过期的旧到期日追加 30 天，重复 delivered 回执不再次发权益。

## 必要视觉修复边界

1. `DailySubtitle` 当前仍创建并占 24px，render 还写“今日登录奖励已领取”；新版应移除/折叠并回收间距，而非仅将文字清空。不得删除 `ordinary_status` 判断本身。
2. 周奖励和月卡采用同一份 CELL_W/CELL_H/PADDING/ROW_STEP；只循环四个可视槽，前三槽绑定 specials，第四槽为空。不要改服务端 specials 长度或规则。
3. 每个图标、边框、勾、锁、数量保持独立层，以真实 status/has_pass/owned 更新；不把准稿示例状态烘焙进背景。
4. 保留现有按钮 IDs/action、规则/错误提示和 ESC/outside/reload 生命周期，即使布局移动到新容器。

## 可用验证入口（本次审计未执行）

- `node tools/test_daily_reward_feedback.cjs`：当前真实控制器的 pending、拒绝、重复和成功反馈。
- `node tools/tests/daily_tooltip_dismiss.test.cjs`：奖励 hover、标题无 hover、tooltip 生命周期。
- `node tools/test_monthly_pass_checkout.cjs`：月卡仅进入原付款确认、正式 SKU/价格、待付单重复打开和续费；文件末尾有当前按钮文案断言，布局/文案更新应窄适配。
- `C:/Program Files/lua/bin/lua5.1.exe scripts/vscripts/tests/test_daily_ui_snapshot.lua`：28 格顺序/边界/补签、前三项真实奖励、第四项不得伪造、快照只读。
- `scripts/vscripts/tests/test_archive_service.lua`、`test_payment_service.lua`：原队列和开通路径。
- `server/payment_backend/test_monthly_pass_database.py`、`server/tests/test_archive_backend.py`：真实权益/事务验证；本次没有运行数据库测试。
- `tools/test_daily_ui.js` 仍加载旧 `daily_rewards.js`，不能作为当前 28 格新版完整验收。
- HTML 预览和静态检查不等于 Dota 2 实际运行；准稿要求游戏内 16:9、16:10、宽屏和操作状态验证，必须分别记录实际完成与尚未完成。

## 本次实现与验证（2026-10-17）

以上为修改前的接口记录；本节记录本次交付结果。

文件清单（54 个，未修改服务端或存档规则）：

| 范围 | 文件 |
| --- | --- |
| Panorama 源文件 4 个 | `panorama/src/scripts/custom_game/daily_remaining_5d5c1152eb.js`、`daily_gw2_data.js`；`panorama/src/styles/custom_game/daily_gw2.css`；`panorama/src/layout/custom_game/daily_gw2_assets.xml` |
| 原生配套 4 个 | 上述文件在 `panorama/scripts`、`styles`、`layout` 下的 `.vjs_c`、`.vcss_c`、`.vxml_c` |
| 素材 36 个 | `daily_accepted_v1` 目录的 `window_edge`、`header_rule`、`divider`、`reward_frame`、`button`、`close_base`、`close`、`lock`、`check`、`window_background`、`tooltip_background`、`tooltip_frame`；各含 `panorama/src/images/custom_game/` 下的 `.png`、`_v10.vtex` 和 `panorama/images/custom_game/` 下的 `_v10.vtex_c` |
| 数据和说明 2 个 | `data/ui/daily_accepted_layers.json`；本文 |
| 工具 4 个 | `tools/daily_accepted_20261017/` 下 `import_assets.py`、`compile_assets.py`、`compile_panorama.ps1`、`README.md` |
| 回归 4 个 | `tools/tests/daily_accepted_layout.test.cjs`、`menus_v10_archive_pages.test.cjs`、`fixtures/menus_v10_harness.cjs`；`tools/test_monthly_pass_checkout.cjs` |

- 实际替换控制器 `panorama/src/scripts/custom_game/daily_remaining_5d5c1152eb.js`，配套 `daily_gw2.css`、`daily_gw2_data.js`、`daily_gw2_assets.xml` 和对应原生资源。现有 `archive.xml` 已包含这些入口，不需要更改它或服务端。
- 设计画布裁去场景外缘，使用 1382×784 的独立居中窗口。周奖励和月卡均由同一份 layout 定义 118×119、5px 内容内边距和四排坐标。保留实际领取、补签和规则按钮，放在周奖励下方；月卡按钮在第四槽下方。
- 独立导入九张已审阅组件：窗口边缘、标题分隔线、月卡分隔线、共享格框、按钮、关闭底/叉、锁和勾。其他三张是项目已有的无字背景和 tooltip 材质。所有 PNG 保留来源字节，显式 BGRA8888/no LOD/no mip 原生纹理逐像素及 alpha 核对通过。道具图标继续走当前真实 ID 映射，兼容主区的新共享图标表及原提交中的正式图标映射。
- 素材包的 window_substrate、header_base 和各格 base 有明显三角形修补/残字瑕疵，未接入。背景复用原有无字纹理并在背景层调成深棕色；没有降低整个窗口透明度。所有文字和数量为 Label，未接入准稿截图、概念道具或栅格文案。包内 PSD 的图层名称/位置及 155 张 PNG 尺寸已与 manifest、CSV 核对。
- 缺少 hover/pressed 美术，按钮和格子采用 CSS brightness 的轻量反馈，没有虚构额外素材。没有新增第四项业务权益；第四槽仅显示空格框，完全不显示图标、数量、勾、锁或交互。
- 自动回归：`daily_accepted_layout`、`menus_v10_archive_pages::daily`、`monthly_pass_checkout`、`daily_reward_feedback`、`daily_tooltip_dismiss` 五组通过。覆盖真实图标 ID、动态 17/123/7 等数量、28+4 对齐、双奖励、空第四槽、pending、拒绝/重试、旧快照、成功反馈、关闭重开和模拟视口缩放。Lua `test_daily_ui_snapshot.lua` 通过，核对原始 7/28 奖励、补签边界和只读快照。模拟 Panel 测试不代表原生渲染。
- Dota 2 Tools 实际运行：1600×900、DPI 96。真实服务器快照累计 4 次、月卡未开通；确认 28 格、四月卡槽、前三真实锁定、已领取勾和第四纯空槽，副文不出现；关闭重开后布局与数据仍正确。实际激活原 PassPurchase，原服务端接口打开“签到月卡（30天）”付款确认，再用原关闭按钮关闭，未点击购买/支付、未创建订单或授予权益。服务端拒绝、防重复和支付参数由上述真实控制器回归验证，不能称为实机发奖/付款完成。
- 原生多比例验证：初次 Win32 调整被引擎还原；使用 `SWP_NOSENDCHANGING` 后完成 1600×900（16:9）、1440×900（16:10）和 1720×720（超宽屏）真实引擎 TGA/PNG 截图，图像像素尺寸和 UI 根尺寸均核对。三种比例保持居中、边距和四排对齐，无裁切/重叠。截图位于本机 `tmp/daily_accepted_20261017/native/final_*.png`。原生发现固定宽 Label 的 text-align 未正确移动数字，改为独立数量容器内按文字实际宽度锚定右下、32px 字号，重新编译及截图确认修复。真实有效月卡、真实领取/拒绝后的业务过程仍未实机发单验证，由控制器/服务端回归覆盖；勿把模拟测试当作实际发奖结果。
