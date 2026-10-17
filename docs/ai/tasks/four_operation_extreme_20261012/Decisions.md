# 测试和优化边界

- 技能栏以首槽屏幕位置固定，技能数量仅决定右侧容量/必要缩放；生产队列在侧面不足时上置，不通过左右推技能栏让位。原头像锚点、技能补位、科技升级/退款/tooltip/快捷键权威来源保留。新HUD热载恢复最多4次writer回放，稳定期不强制刷新；不因截图标签缺失自行给被动分配键。VM零写入是限定技能栏位置/宽度的操作证据，未称全部UI零更新或FPS收益。
- 原生塔/伐木工1600×900首槽横向差0已直接查看原PNG；英雄/主城/研究所最终新keys、小高度滚动和活跃队列只在VM覆盖。拒绝前台丢失的捕获，不捕桌面其他窗口；新的只读截图工具剔除输入/焦点功能，focus工具增加SkipCursorCenter并删除对SearchUI发送ESC，界面验证不再附带鼠标移动。
- 正式lane的18次自然攻击与真实死亡链证明仅限一个owner0普通怪；单刀英雄652→686的成长漂移不能用于DPS配对。四处旧creature扫描遗漏已制作严格私有registry兼容；dead-valid尸体须保留到native失效，不能偷偷改成alive-only。该兼容只服务现有单case，批量准入和原生尸体modifier仍待；不直接改正式BaseClass。
- VMDL面数交叉检查证明候选LOD0更轻，但Hoodwink裸body LOD1比Dire ranged LOD1更少，因此不概括为所有视距必然低面数；面数不换算FPS。系统socket/内存压力作为采样背景记录，不擅自关闭其他app；私有测试只绑定本地空闲源端口，目的地仍127.0.0.1:29000，无网络设置修改。

- 最新resource39同场完整远程身体/去饰品有效5.37→6.88FPS，GPU51.92→22.66ms，可作为视觉降负担证据；不把当前244怪无玩家活动的诊断称为30FPS验收，不把清掉944附件称为实际测出低面数。原模型和裸模型均以同244原单位、同455creature计数比较，保留8首领。换模原单位已通过三次自然record→launch→land，精确观察器与callback已恢复；没有修改原native攻击订单。下一阶段仅验证热点Q临时施法者的有界池，保留全部施法与伤害；不推广死亡NPC对象池。

- 使用正常资源扣费与生产API；不用使扣费no-op的debug资源模式冒充真实操作。
- 四个机器人活动是真实引擎所有者的模拟请求/命令，不冒充四个独立客户端UI或网络发送。
- 固定seed和有限duration，分开轻量典型操作与短爆发；有限统计、不逐操作刷console。
- profiler开启的测量用于定位，不直接算最终30FPS通过；最终使用无instrument原生ETW记录并验证每秒前台。
- 调用计时inclusive不相加；远程wave/近战queue分开；native回调hook为0不等于实际事件0。
- 保留业务语义、攻击次数、伤害与必要的命中/落地反馈；允许依据证据去掉重复计算、相同数据重复发布、冗余视觉叠加和不可见更新。

- 采用官方方法：CPU/GPU同时间轴诊断、独立采样与剖析、固定场景负载、持续和爆发操作分别记录。来源 https://www.intel.com/content/www/us/en/developer/articles/technical/locate-and-resolve-cpu-gpu-bottlenecks.html 和 https://github.com/GameTechDev/PresentMon 。当前NextBot/DamageImpact实际self成本促使优先原生战斗/重复订单调查，尚无依据声称只需GPU粒子降级。
- `r_always_render_all_windows=1` 属Tools实机采样设置，必须在样本记录且结束恢复。后台/焦点不合格、CSV缺失、native loop FPS等均不作30FPS验收；采样工具将对CSV、焦点覆盖及异常清理做严格校验。

- 对真实getter不可用的builder明确拒绝并继续其他owner；调查实际生产生命周期，不能重建测试actor后声称原bug不存在。
- 只对已知且原11属性均为0的hero技能精简native声明；unknown/native首声明信息不完整时保留原11项。每实例首声明固定，不能refresh迁移engine缓存，level/activation的业务getter继续实时读取。
- shared墙route已验证原生覆盖，但无匹配FPS提升证据，保持默认关闭候选。个人墙导致全局败退是独立实际功能bug，正式修复与FPS收益分开报告。
- GTX1050Ti的GPUActive已经约33ms/帧，后续独立v2 CPU/GPU时间轴测量；不要把native self、Lua inclusive、GPU busy与Present间隔随意相加或相减。
- 模型实验以native完整资源/身体/挂点/真实发射落地及业务数值共同验收；只读名义modelpath、播放gesture或截图身体完整均不足。已释放944附属模型的Ogre方案因attach_attack1缺失淘汰，最新版本不自动成为最佳。未测网格三角形，称“自包含/少组件”，不能冒称已经测出低面数。
- 资源池按实际生命周期与热点决定：稳态Lua API-slot观察没有NPC反复创建，不盲池化死亡/奖励/AI单位；native released particle ID不可回收再调用。预缓存READY去重、stable饰品复用、staged挑战checkout已存在，不能把全部资源称为未缓存。
- 4getter的bool参数以本机当前nativearity/readback为依据；保留原百分比/倍率/秒单位和业务fallback，不为测试绿用cached攻击率覆盖实际native。参数修复、owner过滤、UI缓存分别记录功能/调用减少，不从mock计数推导30FPS通过。

- ranged31兼容候选通过实际三次原生launch/land和逐体不变量，优于未验证Ogre；仅Tools default-off，正式CSV仍原样。实测6.16FPS不是30FPS通过。无饰品能降低GPU负载，但162ms CPU帧时间仍为关键问题；继续诊断AI/全局战斗回调，不把池化Released particle IDs、死亡NPC回收或降低攻击频率当捷径。
- 健康静止的snapshot不更新是正式服务正常行为；UI恢复必须依据显式缺数据/加载/等待，采用单pending与有界退避，不能用2秒无sequence无限全量重建。

- UI冗余刷新修复保留：已实机证明请求不反复增长而业务快照继续更新；6.17FPS与旧6.16没有改善证据，不能将VM调用下降宣传为FPS提升。
- stable acquire与v3候选实机射击/恢复有效，但同图30秒均帧没有提升；两者恢复OFF。继续研究实际高频属性跨VM与共享伤害回调，保留失败/边界样本。

- 共享装备仅在Tools new canonical注册；三个不同英雄实际吸血/法术/友军/移除均通过但缺配对FPS、native全局扇出计数，不能将测试guard实现强开到production。保留默认OFF。
- topnav同refresh只枚举一次NativeEntries已完整VM对照并真实加载；全局其它visibleEntries调用保持，104不能错误解读为仍有重复同轮扫描。native 3类null样式频繁写已定位，但第二缓存候选纯VM只省275writes且多3730父链reads，尚未证实净收益，不自动升为最佳。
- formal native range aliases是默认OFF的新出生实验；必须先真实预热及出生getter proof。native预热调用明确3参(name,callback,-1)，原纯fixture遗漏arity已纠正/negative证实；range36旧世界可能捕获旧helper，采用freshmap range37而不拆分闭包热补。


2026-10-13：原生射程候选range37实测5.221 FPS，未达到性能目标；不因去除244个范围modifier自动推广。topnav第二候选省275次写入却增加3730次父节点读取，已淘汰并恢复首候选。当前开始同世界正式清理与重生资源对照；不得热桥接旧wave闭包或重复debug_spawn累加单位。
