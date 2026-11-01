# 共享Boss、头像与统一发行入口（2026-11-01）

本次是**源码/工具与隔离审阅交接**：正式仍为五账号0104、四人容量，6917资源/184保护模块，
manifest`7025356658517360342`。当前新1107为17项/6919资源/184保护/22源码审阅的计划范围，
未生成新plan/unsigned，未签名、未新实机或发布；最终game/content/operator提交待根任务同步，
不能把当前HEAD或工具测试写成游廊已更新。详见[机器边界](shared_boss_release_pipeline_20261101.public.json)。

共享registry把世界单Boss身份/重生与个人session资格/奖励分离：05/08/09三个单体及11十戒10槽，
配置上限13。旧四人理论52→新13不是实机数量/FPS数据；十转不改，maintain_count练功房不改，
四玩家全练功房fixture仍296只。只给实际入场且阶段/存活资格有效的个人session走原奖励链，
不向全名单广播；索引复用、撤回、失败创建、1秒补位、旧回调、英雄替换/败退/reset已有真实
Lua模块+假引擎专项。真实双PC共享body、个人材料到账仍待普通候选验证。

稳定AI保留目标O(1)，失效只查本槽≤4参与者；每0.5秒不扫全场。20次真实modifier fixture
查询增量0、目标写入1，后19次不重写。模式/难度同值不刷新，真实变化只更新10成员。
HUD的31→0稳定根递归与LRU4是已审源码/模拟计数；不得因此声称新FPS已改善或GPU即时释放。
旧1105有限六场景头像通过，但mean100.31FPS/P95=19.99ms未过16.7ms，已恢复0104，失败保留。
用户最新敬神QOP问题须在新普通候选实看，不能只因旧相机map存在就判定修好/被覆盖。

统一入口`tools/release_pipeline.py`默认零SDK/写入；固定authority及两仓source/operator提交
绑定，plan/prepare/build/rehearsal/bootstrap/preflight/publish各阶段分开，Git同步不代表发布。
6917父资源逐项保留；baseline SHA`3a60ddab…219ee3`有220项明确延期，17项零重叠，
锚点后额外运行路径/延期项漂移均拒绝。源码锚点game20420efc/contentf8640121不是整树已发布。

签名/发布必须先拿具体17项unsigned审阅稿和用户明确范围授权。发布前普通实机须同包同代际：
Bane5、敬神QOP09、真实带饰品波次、免费英雄/建造者切换、≥5场景后冷回、双PC共享Boss，
以及≥30秒mean≥90/P95≤16.7ms、正常退出与完整恢复0104。index原始false不能伪装true；
四数据卷的Dota/keeper观察与已签索引持有分别检查。缺真实证据/只报READY或离线假引擎均不准入。
本轮不是完整工程重构，也未更改登录中转、玩家数据、后台或支付。

审查细节位于game `docs/reviews/shared_boss_release_pipeline_20261101.md`；操作契约位于
`tools/shared_boss_portrait_release_20261101/OPS_NATIVE.md`。保留[当前登录恢复证据](steam_login_relay_recovery_20261101.md)，
其他玩家无需运行作者电脑的验签中转工具。下一步为根任务Git同步后真实plan/unsigned、用户授权、
新普通局验收及官方下载核验；本记录无这些阶段的通过声明。
