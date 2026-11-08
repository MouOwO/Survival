# 长青轮纹圣殿目标血量与15倍成长（2026-11-08）

仅本地更新；后台未改，SDK上传0。运行中的离线Tools局未操作、未换包；新局原生存活/血条/回血和普通签包验收仍待。统一发行入口只读状态仍为LOCAL_ONLY：候选0803绑定旧game bf4c5bbf/content c5baf452，不含本次修改；已上传记录仍0104 / Steam manifest 7025356658517360342，未进行本轮远端查询或官方下载。

## 数值与修复

用户指定目标生命10000亿（1000000000000）、护甲10亿（1000000000）、恢复1000亿/秒（100000000000）。旧配置实际为生命10亿、护甲10万、恢复1亿/秒；NPC另有1亿/秒基础恢复，与modifier叠加。旧生成服务没有大血量投影，伤害过滤虽限制到1e30，仍能将超出原生整数范围的伤害传给训练目标。没有捕获用户当次消失的原生诊断，不能仅凭旧10亿配置认定是创建时血量已超上限；本次补齐创建、受伤和恢复三个边界。

CSV为作者源，使用build_configs.build单表重生成altar_actions.lua。NPC初始血量改为安全的1亿、基础恢复0；服务沿用combat/endless_stat_projection，逻辑1万亿映射到原生1亿（倍率10000），三处原生血量setter均使用投影值。modifier接收原生每秒1000万，对应逻辑每秒1000亿；无额外回血轮询。原有血条和选中详情自动使用同一倍率展示逻辑值。护甲直接设置10亿，不改变原有抗性或收费。

训练目标在伤害投影之后额外将原生伤害限制到当前血量减1，保留原MIN_HEALTH，并防止巨量伤害进入原生整数扣血。普通敌人不应用此限制；树木原有保护保持。现有处决服务已排除训练目标。

武器五系列（growth_sword、frost_blade、ice_blade、epic_icefire、legend_abyss）及转生每击三围原本已有训练倍率；永久奖励的hero_basic_attack_growth、hero_attribute_growth、hero_damage_attack_growth、hero_attributes_per_damage此前漏乘，现在使用同一个所有者/房间状态倍率。仅当前活跃房间攻击自己的目标生效，别人的目标、普通敌人、退出后为1；已有永久练功收益加成继续乘算，例如23%使15变18.45。长青轮纹原武器成长加倍、每击三围效率等在室内外同样保留，因此相同权益下比较仍为15倍。训练倍率不放大金币/木材、武器进化攻击次数或每秒被动收益。

## 成本与验证

新增生命投影为每次生成O(1)时间/空间，三个原生血量setter和一个护甲setter，modifier增加仍1次；不新增调度、网络或全场查询。伤害过滤每次O(1)，训练目标新增GetHealth一次，其他单位新增原生调用0。既有每秒收费任务未改。

成长计算每次O(1)，仅有正成长时查询倍率；非训练或非本人目标不请求永久投影。本次倍率读取直接按玩家索引取runtime，避免建立完整科技snapshot；永久奖励请求新增training_room_only投影，只返回一个字段，避免每击复制全部效果。N为场景实体、E为永久字段、F为命中频率：新增稳定刷新0；命中工作O(F)，不随N/E增长，缓存/销毁生命周期沿用原服务；真实权益变更仍由既有投影刷新处理一次O(E)。没有新增场景索引、缓存、事件订阅或定时器。

可复现测试与日志位于树外D:/Survival_本地工具/runs/20261108_sanctum_health；固定项目工作目录，单条运行verify.py。全部为Lua模拟API，不是新局原生存活、FPS或网络耗时证明：

- 真实training_room_service/event_bus/配置/resolver的23场景1058断言，核对三处安全血量、逻辑显示值、护甲、modifier回血、入场费用/失败回滚/旧状态/退出；旧服务负对照失败。原入口回归亦通过。
- 真实damage_filter_service覆盖物理/魔法/纯粹伤害、1e12/1e30/1e100、1血/2血、正常敌人可击杀及逻辑伤害只缩放一次；10000次命中恰好10000次目标GetHealth、0扫描/新定时器/网络。旧过滤器负对照失败。
- 真实永久奖励、科技、转生、武器服务联合事件回归，五类武器、攻击与伤害事件、权益有无、练功加成0/23%、他人目标、普通目标、退出、通关冻结，280项非零收益倍率比较通过；旧永久奖励源码以攻击收益8而非120明确失败。
- 20与1000个永久字段两种规模各10000次倍率读取，均10000次单字段请求；他人目标另10000次请求0；每个返回仅1字段，0场景扫描/新计时器/网络。
- 已有武器输入、处决、树生命投影回归通过。已有test_pure_permanent_rewards的前半永久投影通过，塔成长部分仍在第53行回调断言失败；同一测试对旧永久奖励源码具有相同失败。执行器显式检测EventBus吞错并保留两份日志，不将exit0当整套通过，不改弱原断言。

## 同步与待发

game修改前按stash→pull→精确pop操作，stash对象507c6fec8ab4828dc887f3a3cb14be3bbc6fd8de已恢复；原有编译漂移、后端本机文件及未跟踪发行工具保留。content修改前干净并pull，无本次对应Lua/CSV/NPC源，不创建空提交。工作期间其他会话的生产队列/武器提示提交不混入本次文件。精确提交、最终双仓同步和未提交列表以同目录外git_sync.json为准。

本轮运行待发为game七文件：data/csv/商店系统/altar_actions.csv、scripts/vscripts/config/generated/altar_actions.lua、scripts/npc/npc_units_custom.txt、scripts/vscripts/systems/training_room_service.lua、scripts/vscripts/combat/damage_filter_service.lua、scripts/vscripts/systems/permanent_reward_effect_service.lua、scripts/vscripts/systems/technology_stat_manager.lua。CSV需生成、受保护运行源码需生产转换，不可直接覆盖旧签包。本记录和树外测试不进入运行包。

已执行完整release_pending_inventory，覆盖双仓源、编译、素材、运行删除、历史延期；预提交观察537项、365个资源、413项阻断、7项运行删除，不能把七个修改文件当作完整发行清单。提交后完整快照保存在pending_inventory.json；过程中其他会话可能推进HEAD，计数以各快照真实绑定为准。

当前authority仍旧0803绑定，且完整清单存在未编译、无生产来源、未映射和脏运行资源，不能绕过门禁用旧绑定签包上传。本次无新候选/编译/签包产物，无恢复或安装事务。后续需全量清单按新的不可变双仓源收口所有生产转换、重新签包、原生准入，再由tools/release_pipeline.py执行SDK成功上传及官方完整下载逐资源核验；所有待发与实际阻断保留。
