# 共享Boss、头像与统一发行入口（2026-11-01）

**2026-11-02 实际进度**：用户已允许本次17项签名、受控排演及全部门禁通过后更新。
1107的plan/unsigned与签名构包已完成：17项/6919资源/184保护/22源码审阅；
report SHA`86c10bed…3878e3`、content`7a4c5af2…5221ce`，
game/operator`eaef4398383be211880423eb142eb0a1d723c69f`，
content仓库`eb281a1398466876575a5885e60a8dd207e5f556`。
正式游廊和canonical仍为五账号0104/四人、20条history，未调用SDK上传。
新签名及局部实机通过**不代表完整发布准入**。见[机器状态与精确数值](shared_boss_release_pipeline_20261101.public.json)。

run03普通客户端PID30424/创建UTC`2026-11-01T15:16:58.4949550Z`完成有限画面：
敬神QOP09三张近景红肤至宝/黑金衣饰头部/暗红背景，无QWER/沉默，原生137ms/5组件；
Bane初次98ms及1/2/3/4/6五个不同场景后96ms冷回，4组件，六张settled画面衣饰/紫背景正常。
这不是全转换帧无闪证明、197全覆盖或原生GPU已即时释放证明。

同代际实际30秒ETW独立CSV复算3389个间隔：mean113.2008925FPS、P95=11.16886ms、
P99=14.25142ms、真1%low60.982FPS（最慢34帧）、最大23.7336ms、0帧>25ms，30次焦点样本全部目标窗口。
strict前后PNG可见N4下一波2倒计时01:03→00:29、对局运行未暂停/结算、基地15只Meepo及完整Bane头像，
本样本90FPS/P95≤16.7ms门槛通过。不是与旧版同负载对比、性能因果或长局/全模式通过。

before inspection保留原始INCOMPLETE：四data卷均Dota+keeper使用，indexfalse/all5false未改写；
**缺after inspection**。用户只明确确认run01/02为手动退出；run03原进程结束后检测到新进程，
退出原因本轮未另确认，Root未发送WM_CLOSE或kill，不能判为crash或已确认手动quit。
run03在UTC15:59:21.987019取得OWNED_DOTA_EXITED_HOLDS_COMPLETED、keeper exit0和同handle退出；
但没有WM_CLOSE intent/close_requested完整链，也未restore0104。
随后检测到新PID33900，不属于原keeper，不能继承旧受控证据；本机候选五卷尚未恢复且有新进程占用。
远端0104/本机1107导致同局版本不匹配，正准备手动同签候选测试包；peer installer v01真实小文件
实验失败已阻止执行。v02 SHA`fdd669c0…16398dd`的真实同helper小文件10项通过，
receipt`bc396cba…87833f`明确0真实VPK字节、未调用完整Install/Restore；不代表3.8GB分发或客机安装成功。

仍缺：免费英雄/建造者切换、真实带饰品wave7 Axe、双PC共享Boss/用户确认、after inspection、
完整正常关闭和0104全恢复，随后才是发布及官方下载。已签VIEW实际查询确定前5波走neutral视觉，
第6波无default wearable，N4最早带饰品是第7波Axe（6组件）；正常免费英雄入口为主城Lv4后
建英雄祭坛、选祭坛第三个原生Axe按钮。上述后两项只是已签运行数据定位，尚未实际操作验收。


共享registry把世界单Boss身份/重生与个人session资格/奖励分离：05/08/09三个单体及11十戒10槽，
配置上限13。旧四人理论52→新13不是实机数量/FPS数据；十转不改，maintain_count练功房不改，
四玩家全练功房fixture仍296只。只给实际入场且阶段/存活资格有效的个人session走原奖励链，
不向全名单广播；索引复用、撤回、失败创建、1秒补位、旧回调、英雄替换/败退/reset已有真实
Lua模块+假引擎专项。真实双PC共享body、个人材料到账仍待普通候选验证。

稳定AI保留目标O(1)，失效只查本槽≤4参与者；每0.5秒不扫全场。20次真实modifier fixture
查询增量0、目标写入1，后19次不重写。模式/难度同值不刷新，真实变化只更新10成员。
HUD的31→0稳定根递归与LRU4是已审源码/模拟计数；不得因此声称新FPS已改善或GPU即时释放。
旧1105有限六场景头像通过，但mean100.31FPS/P95=19.99ms未过16.7ms；该旧样本失败保留，不能以新样本覆盖。
本次QOP已在普通1107有限近景样本实看正常；仍不能只因旧相机map存在就推断所有版本或个体均通过。

统一入口`tools/release_pipeline.py`默认零SDK/写入；固定authority及两仓source/operator提交
绑定，plan/prepare/build/rehearsal/bootstrap/preflight/publish各阶段分开，Git同步不代表发布。
6917父资源逐项保留；baseline SHA`3a60ddab…219ee3`有220项明确延期，17项零重叠，
锚点后额外运行路径/延期项漂移均拒绝。源码锚点game20420efc/contentf8640121不是整树已发布。

本次具体17项unsigned审阅和用户签名/排演授权已取得；发布仍必须先满足全部实机门槛。发布前普通实机须同包同代际：
Bane5、敬神QOP09、真实带饰品波次、免费英雄/建造者切换、≥5场景后冷回、双PC共享Boss，
以及≥30秒mean≥90/P95≤16.7ms、正常退出与完整恢复0104。index原始false不能伪装true；
四数据卷的Dota/keeper观察与已签索引持有分别检查。缺真实证据/只报READY或离线假引擎均不准入。
本轮不是完整工程重构，也未因此更改登录中转、玩家数据、后台或支付。

审查细节位于game `docs/reviews/shared_boss_release_pipeline_20261101.md`；操作契约位于
`tools/shared_boss_portrait_release_20261101/OPS_NATIVE.md`。保留[当前登录恢复证据](steam_login_relay_recovery_20261101.md)，
其他玩家无需运行作者电脑的验签中转工具。下一步补齐剩余普通/双PC验收与安全恢复，再按授权门禁决定发布及官方下载核验；本记录没有总体通过声明。
