# 存档系统：本地实现与服务器联调契约

## 已实现范围

左上角抽奖右侧为“存档”入口。左侧三个单选分页：通关存档、虚空之影、积分道具。
通关页展示全部 44 个常规里程碑；虚空和积分页只展示拥有数量大于零的物品。
小图标为项目自制的 Panorama 卷轴、晶片、印章图案，没有 DOTA 原生物品图标。
图标不接受点击操作；自制悬停框只有名字与效果。通关未完成图标点亮，完成置灰。

Excel 是初始数据来源，CSV 是后续业务配置权威入口。只导入常规 N1–N10；
特殊模式尚未有玩法接线，未把工作表中的模式解锁说明当作新的任务指令执行。
N10 的两行补齐名称中的次数，分别为 N10（5次）、N10（10次）。

## 配置

| CSV（`data/csv/存档系统/`） | 职责 |
| --- | --- |
| `archive_categories.csv` | 分页 ID、名称、展示器、排序、启用；其余七个入口默认关闭 |
| `archive_achievements.csv` | 成就 ID、精确难度、累计次数门槛、名称、效果、词条数组和数值数组 |
| `archive_shadow_items.csv` | 23 件虚空道具的稳定 ID、品质、数量上限和每件效果 |
| `archive_drop_rules.csv` | 服务端品质权重、2 件基础掉落、通行证额外 1 件 |

`effect_ids` / `effect_values` 一一对应 `player_gameplay_stats.csv`。
新增 `hero_attributes_per_level`，默认 0，按当前英雄等级计算额外全属性，1级也计一级。
数值中的百分比沿用档案约定：0.5 表示 0.5%，不除以 100 存储。
“墙每秒生命”映射生命上限成长 `wall_health_per_second`；
“伐木数量”映射 `lumberjack_attack_efficiency`，“伐木效率”映射 `lumberjack_efficiency`。
虚空道具“伐木工攻速+0.2”按现有攻速百分比字段记录为 0.2。
同档案现有奖励叠加；字段达到 schema 最大值时截断，避免整笔奖励因超过 100% 等上限失败。

根据用户补充，原来剩余的 30% 平均补到四种品质：白 27.5%，蓝/紫/绿各
24.1666667%，精确权重 33:29:29:29，品质内等概率、可重复抽取。
上述混合品质权重仅保留为历史配置，不再用于主线最终BOSS发奖。
虚空道具仅由虚空之影挑战BOSS死亡结算，按 `source_boss_difficulty` 选择对应物品池。
道具到达上限后额外副本丢弃，不重抽、不再增加属性。

```powershell
# 通常修改 CSV 后只构建，不要重导入覆盖手工修改。
& tools/build_archive_configs.ps1
# 从工作簿重导入两张奖励表并构建：
& tools/import_archive_workbook.ps1
# 主构建器 tools/build_configs.py 也会自动收集这些标准 CSV。
```

## 结算和状态机

- 通关：正式波次全部生成、无生成失败、待生成数及存活数为零 → 胜利结算 →
  当前活跃玩家各增加当前难度 1 次。不把高难度胜场算入低难度。
- 虚空之影：挑战服务登记的虚空BOSS死亡 → 所属玩家获得对应池的奖励。
  开局、档案加载、主线最终BOSS死亡、通关与通关作弊均不发虚空道具。
- 待结算 → 读取档案 → 校验权益/抽取 → 同一修订保存 `archive` 与 `gameplay_stats`
  → 公开更新事件刷新现有单位/资源 → 私有 UI 快照。
- 档案未加载、写入失败 → 保留服务端待处理命令，每 2 秒重试。
  抽取结果缓存在命令中，写入失败不重抽。完成标记、数量和属性一起提交。
- 每局唯一 ID 分别标记一次通关和各次挑战击杀；多人按 PlayerID 独立排队。
  重复死亡/胜利通知不重复结算。里程碑永久完成标记保证作弊和正常通关都只发一次奖励。

本地使用现有 `local_fixture_provider`。允许文件 I/O 时写入
`data/mock/player_profiles.json`；Dota 禁止文件 I/O 时沿用现有同局内存存档回退，
日志会出现 `same-session memory persistence`。后者重开游戏不保留进度。
跨局云端持久化与真实支付尚未联调，不能据本地测试宣称上线可用。
本地写入失败时恢复 provider 缓存，避免下次读档读到未提交奖励。

## 作弊码

游戏聊天框输入，支持可选前缀 `-`，仅 Workshop Tools 或作弊模式有效：

```text
tongguan n1 20
tongguan clear_n1_1 20
tongguan n6 10
```

前两条含义相同：**增加** N1 累计通关 20 次，不是将总次数设置为 20。
成就 ID 是难度别名，仍按该难度的全部里程碑结算，不是直接领取单个成就。
累计次数增加不会重复发已完成奖励。次数只接受 1–100000 的整数。
通关作弊不模拟最终 BOSS 掉落，也不授予购买通行证。

## 数据协议和后续服务器接口

私有存档结构（示意）：

```json
{
  "archive": {
    "version": 1,
    "clear_counts": {"n1": 20},
    "completed": {"clear_n1_1": true, "clear_n1_3": true, "clear_n1_5": true},
    "shadow_counts": {"shadow_01": 2},
    "processed": {"match_nonce:clear": true, "match_nonce:boss": true}
  }
}
```

积分道具继续读取 `save.content_inventory` 中现有抽奖道具，不复制库存，不重复发属性。
分页请求为 `survival_archive_request { category_id }`；身份使用引擎注入的
`PlayerID`，忽略客户端 `player_id` / account。每玩家请求间隔至少 0.15 秒。
`survival_archive_snapshot` 只发给请求玩家；每包最多 12 行，带 `sequence/chunk/chunks`，
客户端收齐同一序号后展示。无概率、私有属性全量表、账号或可写数量接口。

`archive_service.set_provider({ submit = function(player_id, command, done) ... end })`
是后续服务端适配口。`command` 包括幂等 `id`、`kind=clear|challenge|promotion|endless`、`difficulty_id`、
通关增量 `count`；测试命令额外带 `test_only=true`。该接口只能从服务端模块调用。
适配器负责从服务端玩家身份解析账号、提交可信结算证据，后端重验难度、胜利、
权益和幂等号，完成数据库事务，返回权威完整档案或增量。
适配器必须先通过玩家档案服务应用返回数据，再 `done({ok=true})`。
失败 `done({ok=false,error=...})`；15秒超时后解除占用，使用同一幂等号重试。
后端必须持久保留发奖记录和处理重复/乱序返回；本地 `processed` 仅保留当前局记录。
未安装适配器且当前 profile provider 不支持 `persist_save` 时返回
`archive_provider_required`，保留待处理奖励，不假报云端写入成功。

建议后端新增结算接口 `POST /v1/archive/settle`，与既有 profile revision/CAS、
session nonce 和不可变 reward_grants 配套；这里只定义接线契约，没有修改数据库仓库。
后端自身还需迁移新属性 `hero_attributes_per_level` 与 `archive_pass` 权益定义。

通行证使用 `entitlements.archive_pass = {active=true, expires_at=<Unix秒>}`；
过期或 inactive 无额外掉落。也可由后端每次结算返回已计算有效期的 active 状态。
VScript 没有 `os.time` 时，适配器可用 `archive_service.set_clock(function() return unix_seconds end)`
注入可信服务端时钟；无法比较有效期时不授予额外掉落，不使用客户端时间。
只有购买后由支付后台验证订单发放，无客户端购买成功/直接授予接口。
本次未设定售价和有效期天数；这些值由后续支付产品和后端定义。

新分页：在 categories CSV 增加/启用行，并调用
`archive_service.register_category(category_id, function(profile, archive) return rows end)`。
输出同样的 ID/名称/说明/图标样式/数量结构即可；UI 按服务端分页列表生成 toggle。

## 验证与 UI 源码

游戏仓库保留源码 `panorama/src/`，`tools/deploy_archive_panorama.ps1` 同步四个文件到
对应 content addon，向最新 manifest 增加一个 HUD，向主 HUD 增加难度换行样式，并用 Valve 编译器生成资源。
部署脚本不会用旧 manifest 覆盖其他 HUD 入口；content 目录位于另一个仓库，需要一起提交。

```powershell
& 'C:\Program Files\lua\bin\lua5.1.exe' scripts/vscripts/tests/test_archive_service.lua
& 'C:\Program Files\lua\bin\lua5.1.exe' scripts/vscripts/tests/test_wave_early_final.lua
node tools/test_archive_ui.js
& tools/deploy_archive_panorama.ps1 -CheckOnly
```

已验证配置引用、44/23条数据、原子奖励、重复事件、失败重试、持有上限、通行证过期、
多人隔离、作弊限制、私有分包，以及 UI 切页/图标状态/tooltip/过期回包处理。
已完成 Valve Panorama 编译。仍需完全重开 Workshop 测试局确认实际显示与最终 BOSS
玩法结算；自动测试和编译不等于实机验收，也不等于云端持久化验收。
新增服务和涉及的运行模块通过 Lua 5.1 语法检查；主入口 `addon_game_mode.lua`
在原 HEAD 已超出标准 luac 5.1 的 60 upvalue 限制，本次只增加一行初始化，
未把这个既有检查限制计为通过。

## 存档挑战（本地实现）

N3 及以上清空最终波后先记录通关，再进入存档挑战阶段；N1/N2 维持直接胜利。
清空最终波不会先调用天辉胜利；如果挑战服务或出生点暂未就绪，N3及以上会每秒重试，
避免结算界面抢先结束游戏导致建筑无法生成。通关后本局进入数值冻结状态：资源及秒收入、
英雄三围/攻击成长、武器成长、塔/城墙成长停止；挑战Boss经验和金币赏金均为0。
挑战掉落仍原子写入存档，但新永久效果到下一局再投影，不改变当前挑战阶段数值。
每位通关玩家的出怪口旁并排生成三栋归属该玩家的无敌建筑。挑战1有11个技能，
虚空之影1～4分别要求N1～N4，神兽狩猎1～4要求N5～N8，秘法牢笼1～3要求N7～N9。
建筑整体要求N3，因此N3首次出现时虚空之影1～3已解锁。
每位玩家同时最多一只挑战BOSS，每个技能每局仅可发起一次，成功生成后立即置灰。
挑战2开放神兽狩猎5～8，分别要求N8、N9、N10、N10；挑战3开放神兽狩猎9～12及秘法牢笼4～6，全部要求N10。
狩猎按序号掉落对应神兵碎片，牢笼4～6分别使用绿龙、蓝龙、青铜龙的九件材料池。
挑战3保留“结束存档挑战”，全部玩家结束后才胜利退出。
主动结束移除存活BOSS不发奖励；奖励仍待保存时禁止主动结束。

配置入口均在 `data/csv/存档系统/`：

| 表 | 用途 |
| --- | --- |
| archive_challenge_definitions.csv | 建筑、技能顺序、解锁难度、模型、奖励池、冷却、启用 |
| archive_challenge_stats.csv | 每项挑战每个难度的生命、攻击、魔兽护甲、攻速、移速、距离、魔抗 |
| archive_challenge_rules.csv | 建筑位置/模型、开放难度、牢笼每日上限、日切时区 |
| archive_fragment_definitions.csv | 12种神兵碎片、持有上限、每日上限和兑换关系 |
| archive_fragment_levels.csv | 184条逐级效果，复用 player_gameplay_stats 属性ID |
| archive_cage_items.csv | 六组牢笼的54项材料与效果 |

狩猎1～12、牢笼1～6的生命、攻击、护甲已全部同步工作簿数据，其他属性为每秒攻击1次、移速280、距离160、魔抗0。
狩猎9～12攻击严格按原表“5500002亿”换算为550000200000000，不再使用此前暂定的5500002。超大属性的挑战BOSS复用无尽数值缩放和UI还原流程。
`tools/sync_archive_boss_stats.ps1` 仅同步上述18个BOSS的血量、攻击、护甲及来源备注，共180个难度条目，再生成Lua配置。重新运行旧版初始/扩展导入脚本后，应再运行此同步脚本以恢复最新属性。
新增龙魂“英雄攻击全属性+1”映射为hero_attribute_growth，沿用挑战奖励下一局生效规则。
主线N6～N10各89行波次复制N5；挑战N5～N10属性一致，后续可以逐行调数值。
修改CSV后执行 `tools/build_archive_configs.ps1` 同时生成Lua、技能/建筑KV和中文本地化。
`tools/import_archive_challenges.ps1` 从桌面工作簿重建初始数据，会覆盖这些挑战CSV；
已手动调数值后仅运行build，不要重新import。
`tools/extend_archive_challenges.ps1` 可重建本次挑战2、3扩展数据；同样会覆盖所涉及条目，手动调表后不应重新运行。

虚空之影1～3分别严格读取工作簿来源难度N1/N2/N3的物品池，每次进行两次独立等概率随机，
允许重复且最终固定2件，通行证不增加这三项挑战的数量。规则位于
`archive_shadow_challenge_drop_rules.csv`，不再按池中每项100%发放。虚空之影4暂沿用基础2件、
通行证3件的既有规则，并对应工作簿N4池。
主线最终BOSS混合品质掉落入口、事件及结算分支已移除，旧开关不再能启用发奖。已有存档数量不追溯删除，以免误删合法挑战所得。神兽狩猎每次1片，
每种神兵每日20片、通行证40片；每累计20片提升一级并自动追加该级永久效果。
晋升暂按累计超过200片后，消耗10片兑换表中下一阶神兵1片实现；兑换不降低已解锁等级。
此解释来自工作簿的文字规则，已向用户发出澄清，尚未收到进一步修改意见。
牢笼每组9项等概率，单次1件、通行证2件，三组合计每日30件、通行证90件；单项上限149。
存档启用神兵碎片和秘法牢笼页，碎片展示全部12种和等级，材料仅展示已拥有项。
碎片图标无点击行为，兑换使用独立按钮。

新增存档字段：`fragment_counts`（可用库存）、`fragment_totals`（累计）、
`fragment_levels`（已发等级）、`cage_counts`、`daily[day_key][fragment_id|cage_total]`。
库存、等级、属性、日限额和幂等记录在同一个档案revision写入。
`challenge`命令带服务端生成的`challenge_id/kill_sequence/difficulty_id/day_key`，
`promotion`命令带`fragment_id/day_key`；后端必须重验挑战解锁、归属、击杀证据、
支付权益、日切时钟、库存和兑换门槛，并使用同一事务去重发奖。
客户端新增 `survival_archive_promote {fragment_id, request_id}`，仅表示兑换意图，
身份取引擎PlayerID，不能上传数量/奖励/权益，0.3秒节流。日切配置为UTC+8，
生产环境应注入可信时钟并由后端校验，不能信任客户端日期。

新增验证命令：

```powershell
& 'C:\Program Files\lua\bin\lua5.1.exe' scripts/vscripts/tests/test_archive_challenge_rewards.lua
& 'C:\Program Files\lua\bin\lua5.1.exe' scripts/vscripts/tests/test_archive_challenge_service.lua
& 'C:\Program Files\lua\bin\lua5.1.exe' scripts/vscripts/tests/test_wave_early_final.lua archive
```

以上以及存档服务/UI测试通过，涵盖日限额、升级兑换、失败回滚与重试、多人归属、
重复击杀、解锁条件、最终波到挑战阶段、N5复制一致性。旧的
`test_wave_difficulty_builder.lua` 仍断言过时的N1末波批次数以及N3未配置，当前不通过；
本次生成表仅追加N6～N10，未修改既有N1～N5数据。实机仍需重开测试局验证模型、
11技能面板、出怪口位置和客户端交互；云端存储及支付未联调。

## 无尽模式

入口仅在存档挑战2，沿用通关后N3及以上生成挑战建筑的规则。每位玩家每局成功开启一次；与其他存档挑战互斥。所有难度使用同一组1000波属性，每波5只普通怪、60秒击杀时间、每秒攻击一次，统一模型。全灭后下一调度帧立即出下一波；超时清除剩余怪物并保留已完成波次积分，断线/结束存档挑战同时清理。

`archive_endless_waves.csv` 对应工作簿“无尽存档”的无尽波次、血量、攻击、防御；`archive_endless_groups.csv` 将N1～N20映射至同一属性组。`archive_endless_rules.csv` 管理数量、时间、模型和攻速。每波积分 `7 * (floor((波次-1)/10)+1) - 6`：1/11/91波分别1/8/64分，1000波合计347500分。

成功开启过无尽的玩家，城墙被摧毁不再判负：立即停止该玩家无尽、清除存活怪物和待出波任务，保留已完成波次积分，未完成波不计分。无尽入口仍消耗，其他未使用挑战恢复可用。城墙允许按正常建造流程免费重建（基础等级），同时仍最多一座，不改变通关冻结的资源；此后重建城墙再次被毁同样不判负。未成功开启无尽的玩家仍沿用原判负与建造次数规则，正常断线清理不受影响。初始未建墙检查排除已开启无尽者，避免提前通关测试时错误判负。

`archive_endless_achievements.csv` 导入50档累计积分奖励，存档页新增“无尽存档”。永久累计积分 `archive.endless_score`、最高完成波次 `archive.endless_best_wave`、已领奖标识和属性增量同事务落盘，失败通过现有队列重试；通关后的属性冻结规则不变，奖励下一局生效。仅服务端击杀事件可提交 `endless` 命令，字段为 `wave/difficulty`，幂等ID由局标识和波次组成。生产后端必须核验玩家、局、难度、完成波次及击杀证明，并自行按表计算积分，不能信任客户端分数。

后段属性超过引擎原生生命整数及伤害浮点范围，Lua保留表内逻辑值，原生生命/攻击按比例缩放，伤害过滤器按比例换算并限制原生浮点溢出。自定义血条数据和选中面板还原逻辑生命、攻击，超大值通过字符串传输；选中面板使用实时原生血量乘服务端倍率，避免静态快照造成剩余生命不更新。原生API仍返回缩放值；实机需重点验证高波次伤害及读取原生最大生命的百分比技能兼容性。`node tools/test_endless_health_ui.js` 验证80亿满血、半血、跨单位切换及超大值显示。

调表后执行 `tools/build_archive_configs.ps1`；`tools/import_archive_endless.ps1` 从工作簿重导并覆盖上述波次和奖励CSV，手动调表后勿重导。验证：`test_archive_endless_service.lua`、`test_archive_service.lua`、`test_archive_challenge_service.lua`、`test_custom_monster_armor.lua`，以及 `node tools/test_archive_ui.js`。云端接口仍待联调。

## 好基友与前女友

`archive_social_items.csv` 从“我的好基友”“我的前女友”各导入40项，序号作为ID（同名唐三为不同条目），C列为持有上限。每次抽取按 max_owned-owned 的剩余数量加权，全部集满不扣券；E列静态概率不用于结算。属性逐件叠加，遵守player_gameplay_stats字段上限和通关后冻结、下局生效规则。

`archive_social_rules.csv` 配置奖池、券种、每天挑战奖励上限、单抽费用和100件解锁门槛。当前按待确认默认方案：两页直接开放，共用义帖，两种挑战各每日最多10张。前女友sheet中的邀请函及100个赐福道具解锁条件尚未接入（赐福来源未定义）。好基友累计持有100件保存 `social_unlocks.friend_100`，显示“我的大基巴已解锁（入口预留）”，后续玩法尚未定义。

两种挑战仅在存档挑战3，每局各一次，每次1只怪，N1-N10统一32000000血量、1980002攻击、7992护甲，每秒1刀。建筑沿用N3通关后生成门槛。击杀得到1张义帖，日限按各挑战分别计算，不受通行证增量影响。`yitie <0..1000000>` 增加义帖，仅工具/作弊模式，正式客户端没有发券接口。

存档字段：social_counts、social_tickets、social_unlocks、social_last_draw、daily[day].social_friend/social_ex。发券沿用challenge服务端击杀命令；抽奖为social_draw，字段pool_id和幂等请求ID；作弊为social_ticket_cheat，仅可信测试环境接受。客户端事件survival_archive_social_draw只发奖池和请求ID，身份取引擎PlayerID，0.3秒节流。后端适配器必须按库存重算权重、服务端抽奖、校验券余额、每日额度及挑战击杀证据，并同事务保存券/物品/效果/解锁/幂等结果。云端尚待联调。

`tools/import_archive_social.ps1` 只重导80项物品；`tools/build_archive_social_challenges.ps1` 重建两种挑战、20条属性及两页入口后生成配置。手调挑战属性后只运行build_archive_configs。界面使用现有自绘字符图标、名字/效果tooltip，不使用原生物品图标。

### 三页抽奖更新

本节替代上文“两页共用义帖”的默认方案：好基友消耗义帖(yitie)，前女友消耗邀请函(invitation)，瑞兽赐福消耗福签(blessing_ticket，名称暂定)。原有义帖余额保留，不自动转换为其他券。三个页面均直接开放，各40项，共120项；瑞兽来自“怪兽纳福”sheet，包含英雄攻击间隔-0.015的正向减间隔字段映射。瑞兽挑战同样位于挑战3、每局一次、每天最多10张福签。累计100件瑞兽保存前女友解锁标记，当前页面仍直接开放以便测试。

抽奖操作栏固定于内容区右下角，显示当前券名、余额、抽奖按钮和最近结果。服务端原子扣1券、加1物品并累计效果，库存改变后权重重新计算。缺券、集满、保存失败不扣券。成功保存时记录social_last_draw.effects（实际属性增量），通关冻结期间仅将这次抽奖的属性增量刷新到本局永久属性投影，重复通知按draw ID去重；其他奖励及自动成长继续冻结，初始资源类字段仍遵循现有资源初始化规则。

测试命令：yitie 100（义帖）；yitie 100 ex（邀请函）；yitie 100 beast（福签）。第三方存档提供方联调时，必须保留social_draw结算原因及实际增量，以支持客户端结果反馈和本局效果刷新。

## BOSS存档、每日签到与月卡

BOSS存档仅监听主线wave_system内部已登记的is_boss死亡事件，在移出活怪表后发出archive.wave_boss_killed；第五波等进攻BOSS每只记1次，重复死亡不重复记录，挑战怪/无尽怪不在该登记表。存档archive.boss_kills永久累计，34档奖励来自BOSS存档sheet，archive_boss_achievements.csv配置常规阈值与月卡阈值。用户明确要求减半，因此4500/5500的阈值使用2250/2750，不采用原表近似2300/2800。

月卡采用archive_pass权益，权威expires_at为Unix秒，按服务器时钟到点失效；BOSS效果为独立动态投影，不写入永久gameplay_stats。当前默认：月卡过期且击杀未到常规门槛时暂停对应效果，续费或达到门槛恢复；保留全部击杀记录。在线服务每秒检查权益变化，客户端无需主动打开面板也会刷新已跟踪玩家效果。购买价格和到期暂停策略已询问用户，未答复时使用此默认。

签到使用UTC+8午夜日号，不信任客户端日期。首次请求（UI加载自动发送）建立first_day；每日最多领取一次，累计成功签到/补签次数决定7天循环，不按连续签到计算。有效月卡可免费补签首次记录之后、含今天最近30天内最早漏签日。基础宝石/碎片各3件，逐件叠加；累计7/14/21次且月卡有效时赠送聚财古符/古树眷顾/森罗本源，各最多1件。先前已达累计次数的玩家开通后，在下次有效签到时补发尚未获得的专属礼。古树眷顾采用通行证相关sheet（伐木效率+3），森罗本源按该表引用的商城道具定义。

签到物品定义在archive_daily_items.csv，作为仅签到可得的积分道具展示在存档积分道具页，未加入任何抽奖池。库存保存在archive.daily_rewards.item_counts；claimed、count、first_day与奖励gameplay_stats同一个revision原子保存，失败重试，跨局claimed仍可去重。通关后新增签到效果延续既有冻结规则，下局生效。

配置：archive_daily_schedule.csv、archive_daily_rules.csv；工具import_archive_daily.ps1生成34档BOSS和12项签到道具，再运行build_archive_configs.ps1。工具内签到映射按已核对的G/H/I数据定义，源表变化时需同步检查映射。

客户端新增survival_daily_request、survival_daily_claim(target_day)、survival_pass_purchase；身份仅取引擎PlayerID，签到0.3秒节流，购买3秒节流。本地可测试签到、补签及月卡有效期，但没有实际支付。月卡默认30天、价格待配置、purchase_enabled=0；购买UI明确显示未开放。archive_service.set_purchase_provider接收create_order(player_id,{sku,request_id},callback)，订单ID和SKU来自服务端，不接收客户端价格或权益。支付后台验签/幂等回调后更新权威玩家档案权益并触发profile事件；不得把客户端点击或订单创建当作付款成功。生产上线还需配置价格和安全支付适配器。

后端存档适配器需支持boss_kill、daily_init、daily_claim，验证击杀证据、服务器日期、月卡有效期、补签窗口和领取幂等，重算奖励并同事务写入。在线时长/胜场奖励不在本次签到任务范围，未读取为签到奖励。

### 钓鱼存档展示

`archive_fishing_items.csv` 从“钓鱼存档”sheet导入26项，使用已联调的 `star_blessing_001`～`star_blessing_026` 永久奖励ID，独立于局内 `fishing_reward_definitions` 奖池。名称及展示上限按工作簿；重复映射不新增ID，不改在线checkpoint、掉率、定义版本、发奖或效果投影。品质原表未定义，展示统一N白色名字，自制鱼字图标。所有项目均显示，已拥有点亮、未拥有置灰，不提供抽奖/领取按钮。

展示读取 `save.fishing_inventory = {reward_id: granted_count}`。数量必须来自 `reward_grants` 成功发奖记录的count，不是amount之和，不从永久属性倒推，不统计未结算在线奖励。字段缺失显示“库存待同步”，空对象才代表确实没有物品；超过表格上限的既有数量照实显示。此次只展示上限，不更改后端物品限制。

本地后端源码现有 `fishing_profile_json` 未返回库存，需在原Supabase项目执行 `tools/sql/202609060001_archive_fishing_inventory.sql`。该脚本从现有成功发奖表按账户和物品聚合，在原函数save中增加字段，保留其他函数正文与所有原字段；重复执行无修改。它不新增发奖，也不修改历史属性。`POST /v1/profile` 的Python转发和Lua profile保存已有透传能力，因此无需重写已联调接口。脚本在本次任务中仅准备，未执行到远端数据库；执行后重新载入玩家档案即可显示历史数量，后续现有profile刷新事件自动更新界面。

两处旧服配置与工作簿效果不同：`star_blessing_015` 清晏旧服为墙护甲加成+2%，工作簿为墙护甲+2；`star_blessing_025` 霍云旧服为箭塔造成伤害攻击+1，工作簿为英雄造成伤害攻击+1。展示description按现有实际配置，workbook_description保留原文。由于本次只要求显示，未修改已联调的不可变奖励定义或追溯结算。

验证：`test_archive_service.lua`覆盖库存缺失/空库存、玩家隔离、数量更新、超过上限照实显示、读取不写档；`tools/test_archive_ui.js`覆盖已拥有状态、无点击行为、tooltip及待同步提示。

### 地图等级与上班福利（实现细节）

新增 `archive_map_levels.csv`（34级，累计门槛1H～1112H）及 `archive_work_items.csv`（34个独立项目，各激活一次，消耗600～24000软妹币），由 `tools/import_archive_online.ps1` 读取工作簿同名sheet生成。同名福利保留独立ID。地图等级基础效果修正为每级城墙初始生命+100、每秒回血+5，由 `map_level_effect_rules.csv` 派生；逐级奖励只结算一次并叠加。H按3600秒解释，不重算或累加表内“所需总时间”。

按本次用户要求，实际连接在线60秒获得1软妹币，通行证不增加软妹币；通行证有效期间地图等级时长加倍，到期后的时间按正常倍率，新购买不追溯旧时间。旧表内“10分钟10币/通行证15币”不用于本次实现。档案加载后即开始观察，无需打开UI。服务端每秒采样连接状态，正常相邻样本才计时；掉线、时钟倒退及超过5秒的采样间隔不补计，暂停/服务器停顿不补发。每60秒及断线保存，未满一分钟的已保存余秒跨局累计；进程异常退出最多丢失当前未保存的一分钟。原HTTP在线奖励系统的 `online_seconds_total` 及既有收益保持独立，不按不明历史通行证状态补算新系统时间。

持久化在 `save.archive.online`：`actual_seconds` 实际在线秒、`map_seconds` 加权秒、`coins` 未消费软妹币、`map_level` 此系统已解锁等级、`work_levels` 激活次数和 `cursors[session]` 累计计时游标。原有其他来源的gameplay_stats.map_level保留；本系统新增等级按增量叠加。计时与升级复用archive原子事务，和gameplay_stats一并保存，失败进重试队列。在线命令不逐分钟积累processed记录，由游标去重。成功后的UI随存档刷新，沿用原有通关后属性冻结规则，通关后新增属性下局生效。

客户端仅新增 `survival_archive_work_upgrade {item_id, expected_level}`，身份使用引擎PlayerID；不接收价格、余额、时长或奖励数值。服务端校验余额、配置上限和目标等级，0.3秒节流，重复点击不能重复扣币。两页snapshot附带 `online` 展示数据，地图等级自动解锁、福利点击小格激活，已激活格置灰。无客户端计时上报接口。

远端archive适配器需实现 `online_checkpoint {session,actual_seconds,map_seconds}` 和 `work_upgrade {item_id,expected_level}`，仅接受可信游戏服务器身份，使用在线租约、通行证有效期重算时间，维护持久化session游标防跨服重放；余额、激活次数及永久奖励必须同事务写入。不得将公开客户端的累计秒数直接记账。本地实现已接入现有persist_save和set_provider接口，真实后端仍需按该契约联调。

验证：`test_archive_online.lua`覆盖双倍及到期、断线重连、跨局余秒、乱序重试、扣币失败回滚和最高34级；`test_archive_live_effects.lua`覆盖每级生命/回血及通关冻结；`tools/test_archive_ui.js`覆盖余额、激活点击和等级时长展示。

验证：test_archive_service.lua（21次循环、扣重、失败回滚、补签、月卡过期、UTC+8零点）；test_archive_live_effects.lua（到期撤销BOSS层且不改冻结的其他属性）；test_wave_early_final.lua archive（波次事件归属与重复死亡）；node tools/test_daily_ui.js（宝箱状态、签到补签意图、购买禁用与午夜刷新）。游戏界面已强制编译，尚需实机交互和支付联调。
