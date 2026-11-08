# 选中科技建筑与主城立即显示队列（2026-11-08）

仅本地更新。用户明确“伐木工的建造序列”指主城里的伐木工训练队列。本轮作者源已双仓提交推送，两个官方编译资源已验证并导入开发目录；普通客户端新版本实机显示、整体签包、SDK上传与官方下载仍待。后台本轮未改，SDK0；正式游廊仍0104 / Steam manifest `7025356658517360342`。

## 原因与行为

旧 production_progress.js 同时等待建筑私有快照、主 HUD 的原生节点 ready 以及选中事件后的 Schedule(0)。冷选中时没有 training.options/research 就不显示；原生能力栏重建也会让已有面板再次隐藏。

现在本地玩家真正切换到普通科技建筑、高级科技建筑或主城时，生产面板在选中/查询事件内立即取得当前建筑与视口的数值布局并展开。数据未到时明确显示“同步中”和队列占位，不将未知队列画成空队列，不使用上一栋建筑的任务、图标、取消按钮或训练操作。真实私有快照到达后填入同一面板；训练、取消、费用和服务端授权沿用既有协议。

实际生效的 topnav_remaining_5d5c1152eb.js 在依赖 Valve 子节点前保存本次选中实体的纯数值布局，生产面板使用这个当前布局，无需等待原生节点就绪。整套原生 HUD 的下一帧合并刷新仍保留。切换到非生产单位立即隐藏；旧玩家通知、销毁和旧代回调拒绝工作。紧凑协议的玩家/世界/会话变化及 ready 丢失会清理私有快照、训练占额与展示代际，即使实体 ID 相同也不会留用上一局队列。A→B→A 继续使用独立选择序号拒绝旧回包。

“立即”指事件处理内完成展示状态和样式赋值，不承诺引擎停顿时的固定毫秒数；实际服务端队列仍受正常网络同步影响。

## 成本与可复现验证

令 A 为当前一栋建筑的技能数、T 为8个训练等级、Q 为最多7个任务、M 为当前科技标记数。初始化只创建既有固定生产控件；每次真正进入生产建筑额外调用一次既有 Entries 读取器，成本 O(A)，不查询场景单位集合。读取器优先现有能力数量绑定，冷路径最多24槽探测，再枚举本单位技能；不能将它宣称为零原生读取。数值布局 O(1)，变化绘制 O(T+Q+M)，空间为已有控件/当前单位快照。主 HUD 自己的正常刷新枚举保持原来的合并规则。

相同单位、布局和展示版本下，生产展示稳定路径 O(1)，只推进活动任务的已有时钟；未知队列不运行进度时钟。既有选中解析器的选中集读取不在“零调用”范围内。新增路径没有场景遍历、网络轮询或 Schedule；重复选中不重复枚举技能、创建控件、请求队列或改样式。

树外复现目录：`D:/Survival_本地工具/runs/20261108_production_immediate`，固定项目工作目录后运行单条 `node D:/Survival_本地工具/runs/20261108_production_immediate/test_immediate.cjs`。

- 作者源与官方编译 DATA 同一专项测试各117检查通过：两套协议、三种建筑冷选中、不先执行定时器/回包、占位不可操作、快速切换、迟到回包、A→B→A、ready丢失/世界/会话、销毁、四组物理视口/缩放和完整真实模块联合的原生节点重建。
- 专项累计12000次重复通知，生产读取器、面板搜索/创建、展示写入和私有请求计数均不增长。
- 两个旧文件负对照分别复现“冷选中仍隐藏”和“原生子节点重建后再次隐藏”，不是只检查新代码包含某个字符串。
- test_compact_production.cjs、test_production_dock_selection.cjs、test_production_shortcut_spacing.cjs、test_topnav_refresh_context.cjs、test_topnav_selection_coalescing.cjs 均通过。后者202通知/101身份切换仍只有一次排队的完整 HUD 刷新/一次原生枚举；这是整套 HUD 的计数，不含每次真正进入生产建筑的新增即时初始化。
- 现有 test_production_hud.cjs 的旧夹具缺少 ProductionResearchAuto0 绑定，修改前与修改后都在读取 visible 处失败；未把它算作通过，也未改动无关夹具。源码语法与差异空白检查通过。

上述为真实生产模块的受控 VM/接口调用计数，不是原生 FPS、在线响应时间或新实机视觉验收。

## 不可变来源、官方编译与登记

作者源 game/dev `38afa716dc6542feb2baff7909c91db23a308fb8`，content/master `988394a8592341d2c4292070515fd9de07126efb`；operator 为同一 game 提交。两仓均按 stash→pull→精确pop→检查→commit→push 完成；对象ID和完整原有工作区状态见 source_git_sync.json。

官方编译使用 tools/release_compile_scope.py，独立空目录 `D:/Survival_本地排演/compile_scope_20261103/production_immediate_20261108_v01`。proof：`output/production_immediate_compile_20261108_v01/proof.json`，SHA256 `b1861e2439e47379d342e5f92675a2593a22df7abaa5119623c17793bc17a197`。两项 exit0，DATA逐字节匹配绑定输入；临时挂载已移除。

| 编译资源 | 字节 | SHA256 |
| --- | ---: | --- |
| panorama/scripts/custom_game/production_progress.vjs_c | 61411 | e123c529c95566ff1ede2c56309fff2c26bb656ef6880420ebff56566746d1ee |
| panorama/scripts/custom_game/topnav_remaining_5d5c1152eb.vjs_c | 145716 | f989f817fc2b9c5249ef882ec362b7b22cc2253c80c5de4bda8886df94a0f91b |

第一次完成隔离编译时发现 Dota/Tools 再次运行，未导入运行目录。用户再次正常退出后逐文件备份、核对目标原摘要，再导入以上两项。编译后脚本验证、导入摘要与备份路径见 compiled_verification_receipt.json / compile_import_receipt.json；没有切换正式签包。

按新增规则使用实际原始回执登记，不进行全盘扫描或清理：编译 proof 记录ID `d8590ca990dfb92c1e8ae301bc99a7d861d76d8331ac8d1293e975eaba467a5a`，导入/原资源备份记录ID `55e18c4219e2dea3da21d286ff5113b6819b1f266d31741b6b92d5f7540a579f`，均位于 `D:/Survival_清理记录/records`。登记是本次观察，不冒称此前历史产物已完成登记。

## 完整交付边界与保留改动

这两个资源的局部编译不是完整发行清单。全量待发以实际已发布0104签名manifest为父，覆盖当前双仓作者源、全部编译产物/素材/运行删除与历史未发布项；树外 pending_inventory_before_final.json 记录537项、413阻断、7项运行删除。最终同步后重新生成 pending_inventory.json；并行任务可能继续改变数目，以报告内 target_commits 和 dirty rows 为准。

尚有未映射源码、待编译绑定及未验证生产转换，完整发布被阻断，不能绕过源码门禁启动旧0803。后台本轮未改、未执行SDK写调用、未声称同步游廊。整体生产来源、全量编译/签包、同源原生验收、原条目上传及官方完整下载核验保留为待交付。

并行任务对 production_progress.js / tooltip_position.js 的后续提示定位修改和其他 Lua/生成配置保留在原工作区，不混入本轮作者提交或编译来源；其未来编译需使用它们自己的新不可变绑定。其他 Panorama 缓存漂移、backend pyc/current.json、未跟踪发行工具及历史stash均保留。精确最终状态见 artifact_git_sync.json，不能把本轮编译产物冒称覆盖这些更新。
