# 0802｜资源不足、训练失败与商店售罄 tip（2026-11-08）

仅本地更新，功能源码及回归已收口，0802 的实际目录生成、官方编译、生产转换、签名与新原生视觉仍待后续回执。后台保持 `20261106-ws4-daily-refs-ed532ea60d2b`，正式游廊仍 `3824360109` / `2026110104`，Steam manifest `7025356658517360342`。0801 签包、绑定和真实回执保留，不把源码或测试称为游廊同步。

用户要求：农场 W 和其他技能、训练在木材/金币不足时均提示；购买英雄物品失败或售罄用 tip，不在商店底部留下失败文字。资源、价格、库存、训练接受条件、扣款/退款和奖励规则不变。本轮没有后台部署、游戏操作、自动购买或抽奖。

## 原因与修复边界

农场 W 实际为 `ability_train_population`，Q 才是农场升级。原人口训练分支扣款失败直接返回，原生能力只结束冷却，0 条通知；resource_system 本来只返错误码，不应全局补通知。本轮在 worker_system 的人口扣款失败分支补一条既有私有 UI_NOTIFICATION。若来源为服务端固定的 main_city_training_ui，仍由已有外层服务负责，避免叠加。

原生伐木工能力的队列拒绝也只结束冷却；本轮只在原生 OnSpellStart 失败时发通知，不改 enqueue、自动重试或队列算法。普通修理工原生失败已有一条；手工旧 UI 入口也可合法传修理工定义，原来内外两处会发两条，因此仅对该固定 UI 来源让外层独占通知，保留原生一条及原接受规则。

客户端所有私有 error 通知改用共享 ShowActionTip，保留原资源/队列码中文归一化；非 error、全体广播及正常排队等待展示不变。production_progress 的旧回包只更新本地状态，由另发的 UI_NOTIFICATION 显示一次；紧凑回包和本地拒绝没有第二通知方，自己显示一次。重放 token、旧选择和已销毁控制器不能重复提示。

商店实际加载 shop_remaining_5d5c1152eb.js，旧 shop_ui.js 同步修复防止回退。两者本地预判失败直接显示 tip 并清除 ShopStatus/error 状态；服务器购买失败回包只清状态，提示由唯一 UI_NOTIFICATION 所有者负责。shop_system 三条已有通知失败返回内部 error_notified 标记，router 对其余购买失败补一条通知；该标记不增加到请求、回包或 wire schema。现有 compact 协议不捕获 shop/ui_notification，已用真实 compact bound=true 条件验证。

木材、金币、售罄、购买上限、背包满和商品配置更新均使用可读文字；inventory_full 映射“背包已满”，shop_entry_invalid 映射“商品信息已更新，请重新打开商店”。商店卡片的真实价格、库存和可购买状态仍由原模型控制，失败文字不再留在底部。

## 共享 tip 与性能

`SurvivalTooltipPosition.ShowActionTip(sourcePanel, message)` 使用一个根层 Label。它不接管鼠标、不建商店内嵌提示、不调用旧 ShowNativeError 的限时层级扫描。首次或真实 HUD/Label 失效时才沿源面板祖先找到根层；后续保留直接引用。单个可取消 3 秒任务隐藏最新文字，serial 防旧回调隐藏新消息；每次用户点击仍重置时间，不用时间窗吞掉第二次点击。模块 Dispose 设置永久 disposed 标记并销毁自己的节点，旧 API 不会复活。

| 路径 | 成本 | 调用边界 |
| --- | --- | --- |
| 首次/真实 HUD 重建 | O(D)，D 为祖先深度；创建一个 Label | 无场景集合遍历，固定样式一次写入 |
| 后续失败 | O(M) 文本归一化与 O(1) 状态，M 为提示长度 | 常数次有效性/属性检查，至多取消一个任务并新建一个隐藏任务 |
| 同一文字重复点击 | 不创建节点，不查树，不重写文字/样式 | 仍重置单任务，不吞点击 |
| 无新失败的稳定帧 | 0 新周期工作 | 无界面扫描、原生错误层轮询、网络消息；仅到期一次隐藏回调 |
| 服务端拒绝 | O(1) 通知所有权判断 | 每次失败至多一条原有 UI_NOTIFICATION，无新回包字段 |

共享组件 raw SHA256 `876230475c4e456f235bd12e40a4fbe6a8de807276addcd42bf7036037ceeb6f`，双仓精确镜像。真实完整模块 10,000 次重复错误：新增祖先读取、场景查询、样式/文字写入、节点创建和原生错误事件均为 0，活跃隐藏任务最多 1；根重建、旧回调、旧 API/Dispose 检查通过。常数次 IsValid 和取消/调度调用不计作“0 API”，也不把这些模拟计数称为实测 FPS。

## 回归与独立复核

所有新临时测试/向量/日志位于 `D:/Survival_本地工具/runs/20261108_resource_tips`，不加入 Git。只有原 Git 跟踪的商店永久回归中两条旧内嵌错误断言改为新契约，其钱包增量、库存、请求、DOM 和业务断言保持。

- `action_tip_lifecycle01.receipt.json`：完整共享模块压力与生命周期检查。
- `skill_training_handoff03.json`，SHA256 `ed8283b90ca178115e32cb5c5449d15df34ac87bc1168f90a60674e7959771e5`：76 项人口、53 项原生/旧 UI 通知所有权、153 项真实 Lua/紧凑模型到完整客户端联端检查；8 套相关回归通过，4 个原源码负对照均按预期失败。01/02 为旧阶段，不能覆盖最终 worker 源。
- `shop/shop_final_manifest.json`，SHA256 `f70f6e5b83b34be8f5bae8ffe04cee02122a971c1985e9c2a397dd7c5783e159`：64 项真实 shop/catalog/router，145 项真实向量到新旧完整商店/共享 tip，27 项既有增量/钱包回归通过；研究 FIFO/退款/幂等、语法和费用/库存守恒通过。

相互独立审阅已核实际调用链、双仓源摘要和通知次数。既有 production HUD fixture 在未改 HEAD 也缺节点而失败，未伪称该旧 fixture 通过，也未以其屏幕模拟代替新 Dota 视觉。

## 新候选与来源门禁

0802 使用新 `output/complete_delivery_release_20261108_v02`、gen22 控制及树外候选目录，0705/0801 和旧失败证明不覆盖。worker/shop 源属于旧 catalog 生成读集，必须按本轮真实不可变提交重新生成 catalog22，再编译和生产转换，不能重标旧 catalog20 的来源。

注册表是否换代取决于实际 records/fields/enums：允许输出第13代且完整字节与源输入一致，或真实第14代且父13摘要/全链正确；同代变字节、跳代、缺失/多余历史节点均拒绝。没有为“新版本”强造新代。新 inspector/控制13项纯回归通过；实际 Git 工具闭包检查须在提交后再运行。

正式待发仍以实际签名0104为父，包含全部历史未发布项及删除项；不能只发布本次几份 UI 文件。新的源码、编译、保护、完整收集、签包、入口检查和原生验收各阶段另据真实回执追加。原五项无关文件继续保留，不混入本轮提交或运行包。

## catalog22 实际生成与精确导入

真实目录生产来源为 game/operator `7f9efe9553db7853d4a26d8196df6ad87143b033`、content `385a2cd2b9fe42e60dc194233af22f2d30137f22`，双仓已提交推送，25 项实际 Git 工具绑定回归全通过。新 manifest SHA256 `e0ed5f4c442bf0cc7e9655103d0b732827da25026f2a0436d16579aad86d2a9b`，真实读集227 source/5 operator/1 binary；原 atlas 来源保留。

实际 registry 保持13，完整字节及所有历史节点未变，SHA256 `fbc489aef4f7ea16da4c121f907d68fbdab114eac6b21e569869271d89ea1fce`。7941 records/188 fields/全部 enum ID 完全相同；definitions 逐值相同，auxiliary 只有6个已核实的来源 revision 字段改变，其他业务结构和值不变。来源/readset 与这些 revision 更新使 schema SHA256 成为 `cfd97a4783f97c8fac4d87a55f9660370ebae19938867758e7b1aea0b4f9d683`，不是价格、概率或奖励变化。

独立只读 Git/全输出审核通过后，严格核18项目标的原/新字节，只导入4项真实变化：game manifest、catalogJS、lookupLua 以及 content 同一 JS；其余13代 registry/history 原件不写入。计划 SHA256 `f25b1ec20635cef06d4ad571374a15416c7b9d6b419a8a6f78c9202fec7af6ca`，导入回执 `output/complete_delivery_release_20261108_v02/catalog22_import_receipt01.json` SHA256 `76c35c254e7846cb50f3d3c5a25ad4d728547e2fdb91d7f5422b58379526ff42`。后续编译/保护必须绑定这次导入后的真实 source22；不得把7f生产来源重标为后续提交。
