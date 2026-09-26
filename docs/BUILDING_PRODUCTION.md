# 建筑训练、科技队列与建造者

更新：2026-09-26。计时、费用、队列与所有权由 Dota 服务端维护；Panorama 展示状态并发送操作意图。

## 主基地伐木工

- 初始显示 LV1、LV2、LV3、LV4 四个训练入口。始终筛选未完成累计上限的等级，再按等级升序显示前四项。
- 某级实际训练完成达到上限后，立即移除并补位，无须重选主基地。例如 LV1、LV2 满额后自动变成 LV3、LV4、LV5、LV6。
- 正在训练及排队数量占用名额，但不提前视作完成；只预留满额时保留入口并禁用。主城等级不足的入口仍显示条件。
- 每个主基地一条 FIFO 队列，总容量 7：1 项训练中、6 项等待（用户已明确确认六个等待格，当前任务另计）。入队时扣除并预留资源、人口，完成才生成工人并增加实际完成计数。
- 时间源是 `data/csv/建筑与工人系统/training_definitions.csv::training_duration_seconds`，当前 8 档均为 1 秒。生成 Lua 来自现有 CSV 流程，技能冷却不控制训练完成。
- 同一玩家所有主基地共用各等级累计上限及名额预约，不能通过连点或多基地超售；不同玩家隔离。
- 基地失效、玩家断线或判负时取消任务，退还实际支出的资源与人口；出兵失败同样退款，重复清理不重复退款。道具奖励训练保留原来的即时奖励方式。
- 原 `ability_train_lumberjack` 保留实体但隐藏，面板承担四入口；修理工与人口升级保持原流程。

## 科技研究

- 左键科技或对应热键加入该研究所队列：1 项研究中、6 项等待。连续点击同科技预订下一级、再下一级，达到最高等级或容量后拒绝继续排队。
- 每项研究 2 秒。等待项不扣费，轮到开始时重新验证前置与实际费用，扣费一次；完成后下一手动任务立即开始自己的完整 2 秒。
- 队首缺资源或前置条件时保持顺序，当前格显示等待原因，后六格继续显示后续任务。满足条件后自动继续；后项不会越过队首。
- 右键某科技切换自动研究。关闭自动不会取消正在进行的研究或手动队列。手动队列优先，自动续研在完成后等待完整 1 秒再开始下一级。
- 资源不足或前置条件不足时保留自动标记，每秒重试；满级关闭该项自动。重复右键、资源刷新及跨公共研究所不能绕过同玩家同科技的自动等待。
- 每位玩家在每个研究建筑拥有独立队列。相同玩家同一科技不能跨研究建筑同时预约，避免目标等级冲突。等级与效果缓存按玩家隔离。
- 普通研究所限所有者，高级研究所保留同队共享访问。共享建筑的详情、价格、队列、自动标记均取当前查看者私有快照，不使用建筑所有者的数据代替。
- 建筑销毁、断线、判负取消研究并退款；等待任务未扣费，无重复退款。

## 界面和升级图标

- 训练、研究采用一致的当前任务图标、进度条和六个等待图标位，显示对应等级。本次在前版基础上将屏幕实际字号再提高约 22–25%，面板最小显示比例为 0.575；取消自动缩字，任务名称允许两行且可悬停查看全文，成本按万/亿简写并在悬停时显示原值。普通研究与高级研究共用布局，后者标题为“高级科技研究”。
- 进度根据游戏时间绘制，暂停不继续走墙钟；buff 按实际面板高度上移。血条遮罩使用缩放后的真实宽高，隐藏面板后恢复。
- 升级图标为深青底、柔和金边、双金色向上箭头。普通升级主体宽约 37%；用户确认箭塔大小区别后，要求大箭头在 v4 基础上缩小约 20%，边框不变。箭塔大升级和城墙第二个升级按钮共用该大图标，合计 8 个小图标引用、2 个大图标引用。城墙此前两个按钮同为小图标引用，本次已修正第二项；升级效果、费用与冷却未变。
- PNG 位于 `panorama/src/images/spellicons/survival/building_upgrade_one_v4.png` 和 `building_upgrade_large_v5.png`，来源为 imagegen；提示词、尺寸测量与哈希随验证记录保存；本次大箭头与城墙同步见 `docs/ai/validation/20260926/upgrade_large_wall.json`。

## 建造者通行与脚下建造

- 建造者保留零碰撞半径，并永久挂载不可驱散 `modifier_survival_builder_phase`，启用 `MODIFIER_STATE_NO_UNIT_COLLISION` 穿过动态建筑与墙体代理单位；仍使用地面移动，不开启飞行。
- 预览和接近阶段，只忽略服务端验证属于请求者的那个建造者。客户端不能自行传忽略列表，其他单位、建筑、地形与已占格子仍参与检查。
- 允许建筑覆盖建造者当前脚下位置，自动寻找最近的安全可达施工点，发出实际走路指令。候选点检查地面高度、岸边、地图边界、占位、附近单位和可达性；没有安全点则拒绝，不使用传送或未验证备用点。
- 到达施工点并离开目标占地后，再完整检查目标位置（此时也不忽略建造者），通过后才扣费并开始建造。
- 走位期间取消、死亡、判负、归属变化或超时不会扣费；重复请求只创建一次，创建失败仅退款一次。

## 接口

| 接口 | 契约 |
| --- | --- |
| `ui_worker_train_request` | 客户端发送 `source_entindex, training_id, request_id`；可信 `PlayerID` 鉴权，只允许自己的主基地，忽略伪造费用、数量、免费标记及奖励来源 |
| `WORKER_TRAINING_GET_REQUEST` | `{player_id, source_entindex}` 返回 `options, active_job, queued, queue_count, queue_capacity`；当前任务含 `started_at, finish_at, duration` |
| `ui_research_queue_request` | 客户端发送 `source_entindex, technology_group, request_id`；验证准入、存活、来源与访问权限后派发 `TECHNOLOGY_PURCHASE_NEXT_REQUEST`，返回 `ui_operation_result.operation=research_queue` |
| `ui_shop_auto_research_toggle_request` | `{technology_group, source_entindex}`，切换该玩家该来源科技自动状态 |
| `TECHNOLOGY_STATE_GET_REQUEST` | `{player_id, source_entindex}` 返回 `research`，含当前研究时间、`queued, blocked_head, blocked_reason, queue_count, queue_capacity, reserved_levels, auto_research, next_start_at` |
| `ui_selected_unit_stats_snapshot.training/research` | 当前选择建筑私有生产投影；`research.abilities_by_name` 包含查看者各科技的等级、费用、排队状态与详情 |
| `ui_grid_placement_validate` | 使用可信 `PlayerID`，验证建造者与技能后，服务端给 `GRID_CAN_PLACE_REQUEST` 添加本人 `ignore_entindex` |

`WORKER_CHANGED`、`RESOURCE_CHANGED`、`TECHNOLOGY_RESEARCH_STATE_CHANGED`、科技等级与转生变化经既有合并刷新推送。非生产统计更新不得清空客户端已缓存的生产字段。服务端保留旧科技入口，但统一经过同一队列容量检查。

## 验证边界

验证记录：`docs/ai/validation/20260926/building_production.json`；中间版总容量 6 的验证见 `docs/ai/validation/20260926/production_queue_capacity_6.json`；用户随后明确六个等待格加一项当前任务，最终验证见 `docs/ai/validation/20260926/production_six_waiting.json`。覆盖计时、预约、退款、去重、玩家隔离、实时排序、研究队列、自动间隔、可信路由及自动让位；编译记录以最终清单为准。

本轮为 STATIC / CONTRACT / SIMULATION 与资源编译，未宣称 Workshop 实机验收。请在 Workshop Tools 重新开局检查最新 Lua：训练等级实时补位、研究队列与右键自动、字体、升级图标，以及实际建筑穿透和脚下建造。地图自身静态障碍仍由地面寻路处理。
