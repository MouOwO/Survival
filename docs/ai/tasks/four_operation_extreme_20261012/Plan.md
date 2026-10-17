# 四玩家持续操作与战斗极限优化

最新恢复入口（2026-10-13，优先于下文历史）：技能槽横向跳动已修复并编译。共用首槽屏幕锚点，不按不同单位/技能数量或异步数据到达居中；队列在左侧空间不足时上置，小高度保留可滚动有界视口。新 topnav 热载时通过现有权威 hotkey writer 有界回放，最多4次/代，不制造被动快捷键，稳定期不强制调用。原生1600×900防御塔与伐木工首槽金边均x719，横向差0；主动键Q/D/G和worker Q正常，两被动槽为空。研究所同版本新快捷键、英雄、主城、小高度滚动和活跃队列的完整截图尚未拍成；前台验证拒绝的捕获不计通过。源/编译/真实截图与恢复说明见 `docs/validation/skill_slot_anchor_20261013.md`。

resource45 PID62740/HWND3086882的隔离四owner夹具保持ready、host1。正式单怪control2/lane2已各完成18次真实record/launch/land命中owner0原墙720，约30秒调用一次原生hero PerformAttack，约32秒实际死亡/四owner波怪人口0/session释放/own unit移除，89项独立复核通过。hero基础攻击652→686随对局成长，不能比较DPS，未完整记录BAT/速度/hull；不是FPS、全部奖励或四网络客户端验收。新的四消费者 registry view 兼容层只追加私有单case正式lane，16场景347断言/旧源25负对照及原业务回归通过；源已冻结但未加载到当前native世界，尸体modifier原生验证/批量准入仍待，正式默认class未改。

资源补证：实际VMDL LOD0完整Hoodwink+4饰品22478三角形、裸主体12730、Dire ranged5959、Radiant ranged3742；不同LOD并非始终候选更少，不将面数比例换算FPS。Q与商城resource45原生通过仍default-OFF；四owner商城initial/final完整数组均已UTF8安全只读导出并独立严格核对8组各660叶值全无差异，没有重跑mutation。外部进程高连接数/内存压力下默认本地socket出现ENOBUFS；仅测试helper改用显式空闲loopback源端口40011..40030恢复连接，无系统网络或其他app改动。前台会在工具间丢失，继续ETW前必须重新验证新PID/swapchain/焦点。整体30FPS目标仍未达到；清理/复用/模型/兼容层证据不是FPS通过。没有本轮提交请求。

最新恢复入口（2026-10-13）：resource45，PID62740/窗口3086882，正常组队/常规/N2实际截图入局；A四owner正式ready，104workers/52建筑/4VIP、wave0，host1。旧自动认证助手在重启后又运行、抢占console，已用官方Stop精确暂停，保留隧道；认证已正常应用且临时文件已删除。resource42客户端更新卸图、43/44恢复失败样本保留；Steam网络更新未完成，当前可用现有本地Tools，不绕过版本检查。

本世界最新：Q OFF64攻击/21crit/21原生本体施法、ON64/17crit/17本体施法，16次重复原生caster施放、池失败0，停止6/6旧引用失效；商城自然四owner各186–201资源事件/10.13s，ON309reuse/40full构建、四owner全商品字段一致/业务错误0，全部私有drawer关闭且cache恢复OFF。control正式单怪已出生且29组自然record/launch/land，60s自动清理/人口及session回零/基线恢复；迟到kill拒绝，尚未验证正式自然死亡。新惰性异步combat probe待冻结后跑control/lane，不能把旧时限错过当死亡通过。

用户追加技能槽切换左右跳动：已用实际全IIFE复现geometry按类型/数量居中与异步0→10两次移动，正在做共用第一槽锚点和空间不足时队列上置响应式；当前实际高研截图skill_switch_before_resource45.png已保存。先完成此修复与编译/截图，再继续native lane/极限FPS。不要继续移动用户鼠标/焦点；仅已授权exact自己actor/observer清理与自动native步骤。所有采样须新PID与swapchain身份；不能沿用63152旧地址。无提交请求。

已完成证据：resource39 同244原单位的236普通怪去饰品、8首领保留，对照5.37189→6.88144FPS，仍不满足30FPS；三次自然 launch/land、三次244全清及四owner资产保留。resource41 Q原生执行观察：OFF18主英雄暴击只有14次原生施法；ON22暴击22次施法、18次为复用实例，池失败0、停止5/5引用失效。新增 legacy SetOwner/idle-acquire/acquisition/Stop 和排队 NO_TARGET 修复需再 freshmap OFF/ON验证，59组纯测试不能代替实机。商城旧候选实机303次stack overflow、reuse=0，已保留失败样本；known-source native-unit身份比较修复已冻结，下一轮必须reuse>0、四owner payload正确且新错误0，才可接受。Q池、research缓存、native lane等仍为default-OFF，不写真实档案。当前无提交请求；收尾恢复Hammer助手和测试设置。后文恢复段落为历史。

目标：在当前i5-14600KF/GTX1050Ti、1600×900实机环境，四人不同档案/钱包/英雄、持续建造升级科研与英雄控制时，将高负载提升至约30FPS。不能以降低攻击次数、伤害、正常出怪人数、奖励或关闭必要特效代替优化。

当前只有一个渲染客户端及三个原生机器人；模拟四玩家生产请求与原生命令，不能称为四端真实网络同步验收。第二实例未连接的边界继续记录，先推进可完成的生产热点优化。

1. 保存当前源文件检查点；记录官方CPU/GPU瓶颈分析、固定种子/负载、递增压力、爆发与持续测试方法。
2. 构建惰性Tools-only活动夹具：4份不同档案、正常扣费、每人1–2秒操作、短0.25秒burst、有界trace、正式三选一卡牌消费；不写真实存档。
3. 复现N2第15波极限并做独立原生VProf/轻量Lua调用剖析。剖析有额外成本，与无instrument验收分开。
4. 根据实际热点做1–3变量的候选优化，保存修改前后负载与行为校验；无依据不删功能或改变游戏频率。
5. 以相同seed、相同英雄/攻击/单位数量和正常游戏速度复跑A分区与B同区、持续操作与短爆发；保存实际CSV、焦点及调用/行为摘要。目标关注平均、滚动低帧及P99，不能仅用平均遮住低帧尾部。
6. 恢复测试设置、清除夹具及模拟数据，交付源码/证据/可复跑入口；未解决性能或真实4网络客户端限制明确保留。

检查点：`output/four_operation_extreme_20261012/baseline/manifest.json`（当前1212个Lua/JS/CSS源码，包含原有工作区改动）。本任务没有提交推送请求，不动其他工作区修改。

恢复入口（当前任务未完成）：PID63152/实际Dota窗口8657488，A隔离四owner夹具ready，104工人/28塔/4墙/244波怪；host_timescale=1、边缘移动0、墙镜头1280/4992。准备期曾host8，不算真实性能阶段。Ogre因缺attach_attack1淘汰；同236普通怪已换为原生lane_dire_ranged.vmdl，无饰品与ambient。root preview3378对owned target3381实际完成3个精确record发射/命中，已detach短观察器、回收两actor、停止spawn hook；正式CSV未改，freshmap恢复原视觉。ranged31_no_accessories有效30秒测得6.162FPS/CPUBusy162.211ms/GPUBusy24.707ms，原同批基线4.963FPS/201.412ms/51.585ms；仍无玩家活动的diagnostic-only，不是30FPS通过，也未测三角面数。

后续先查实NextBot/伤害全局回调与资源池边界，完成静止UI轮询窄修复；停止诊断后120秒持续操作。之后freshmap验证布尔getter、个人伤害producer过滤、工人败退人口和builder生命周期，再复验匹配极限负载。尚需5A+5B同口径原生强测、正常N2奖励流程；52,681条离线数据检查10轮通过，但四个独立网络客户端和30FPS目标仍未满足。Hammer助手收尾恢复；清理仅自己测试actor/观察器、模拟资料及测试设置，不清用户数据。

更新恢复入口：已主动 freshmap `equip35`，同 PID63152；前述旧世界 v3/idle-acquire 全部恢复并关闭，裸模型替换随卸图消失。新世界经实际队伍就绪、常规模式、N2按钮正常入局，A夹具已正式ready，104工人/28塔/4墙/4祭坛，四份map_level=1/9/17/24内存资料。装备共享实验在新英雄首次声明前开启；实际4实例精确注册成功、owns=true、失败/拒绝0，原生bool版BAT/AS/SPA/APS读取成功；吸血和FPS仍待测。已恢复host1，当前第15波正式四通道出怪中，28塔暂持有原有Tools攻击hold。正在并行制作default-OFF正式波怪native范围候选及topnav同轮枚举复用；不得将其候选代码或回调计数称为30FPS通过。


最新恢复步骤：当前PID63152，已发freshmap resource38；上一range37世界的实验上下文将随卸图销毁。正常就绪/常规/N2后isolate，出生前打开shared equipment与native-range并预载19别名，prepareactive A/hold/wave15，host1固定镜头。禁止重复spawn而不先debug_clear_wave_for_comparison；清理后核对244旧引用失效、正式波怪0、resource session0、profile/建筑保持。计划同世界原饰品native范围ON/OFF/ON及裸模型对照；30FPS与5A+5B原生操作仍未完成。
