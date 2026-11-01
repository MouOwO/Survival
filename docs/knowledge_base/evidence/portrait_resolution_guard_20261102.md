# 1107分辨率阻断、新源码编译与双PC阶段收口（2026-11-02）

正式仍为原条目0104（五账号、四人容量、20条canonical history）。1107虽然已签且有局部头像/FPS证据，因双PC高分辨率实证失败，明确不得发布。本次没有SDK上传；本机已完整恢复官方0104，备份全部保留。

## 分辨率实证与新源码

第二位玩家1600×1000时多个Boss头像落回残缺的原生画面；“安息”世界模型饰品完整，头像只见手/裤腿及原生蓝底。原图仅保留ignored路径`output/shared_boss_portrait_release_20261101/peer_boss_portrait_report_20261102.jpg`及本证据JSON中的SHA，不复制图片字节、玩家名或原会话参数进知识库。Root请玩家在同局改1600×900，切另一Boss后再选安息；用户确认恢复正常。未据此认定资源被覆盖或回滚。

正式原生leaf为264逻辑px，旧combat两处却硬拒物理height>240。生产函数在player0/1均复现220px通过、244.444px拒绝，原生单位身份完全相等也无法进入custom scene。900p的220px先前有原生观测；peer1000p的244.444px是264×1000/1080的推导值，未直接采到该电脑layout/scale或具体拒绝日志。现场确认分辨率相关故障，生产函数机制支持此解释。

新修复已真正应用game canonical与content镜像，统一按leaf→root原生scale归一，仅scale缺失时用viewport/1080；显式坏scale、巨大placeholder、隐藏/错误身份仍拒绝。missing-main保留确切叶和最多32层祖先身份链，尺寸或真实重挂时失效一次，稳定不扫全HUD/197身份/188场景目录。game/content raw均`2947af1a6143f8c6df18f98b6fdc35dbf95c40c8309cb8c45a5ad1101b8884f1`（232772字节、4415CRLF），Git规范LF `1af65125378603ff72040c5b27651d308c1d73a603c62e2974032bcd6e10bfca`（228357字节）。官方编译exit0，1 compiled/0 failed；新vjs_c `5f3d0fc3ba8639d438cd973af7bdea5369004e5d65e202dd22830624a3c09b93`，233620字节。

72例布局回放、计数回归及3套既有回归均对默认生产源通过，独立复审覆盖存活旧叶、直接parent不变但祖先重挂及同数量替换。稳定300/10000次root查找0、重复写0；完整更新比旧fixture增加2次IsValid和20次固定layout读取，既有overlay局部访问12节点/次。它们是生产函数的模拟桥计数，不是新修复的原生耗时或FPS。新尺寸普通双人局画面/FPS尚未验收，源提交待统一Git同步。

## 双PC、手动attach与旧1107性能

Root已实际看见普通Local Host/status：loopback主机、2 humans、template_map，用户确认两台同局。一幅QOP世界body及头像完整只能证明该次视觉；不是全部13共享槽位、重生、个人挑战资格或多人击杀/材料奖励均通过。

手动局不是受控owned launch。collector于18:27:02.983357Z附着，before18:27:03.715184Z、after19:23:56.477112Z均观察四个data卷由同代际Dota使用、keeper持有五卷；index-Dota及all-five-open原始false保留。`owned_launch=false`、`pre_attach_continuity=UNPROVEN`、`release_admission=false`，不能补成启动前五卷连续hold。

| 已有样本 | 结果 | 能证明的边界 |
| --- | --- | --- |
| 1107 run03 / 900p | mean113.20 FPS，P95 11.17ms | 原候选单机局部样本，保留；不是新尺寸修复 |
| 1107手动双PC / 本机900p | mean111.07946，P95 10.958275ms，P99 15.00295ms，真实1%低帧56.05497；3326有效间隔、30focus、最大47.6518ms、0个>50ms | N1 next1/00:19→next2/01:14自然跨首波；两张严格截图QOP饰品完整，无暂停/结算；不是同负载前后比较或新修复FPS |

原safe_summary顶层没有source_kind，capture metadata明确`manual_start_not_owned_launch`；没有改写原summary补字段。1Hz focus和两张截图不证明中间每一帧；旧样本不替代新0201的原生门禁。

## 正常退出、恢复与peer操作教训

Root于19:32:53Z正常WM_CLOSE；collector end19:32:53.812030Z以同一retained native handle证明进程结束并释放holds，collector没有请求停止进程。随后restore04真实exit0，19:40:16.033811Z回执`ORIGINAL0104_FIVE_FILES_FULLY_RESTORED`，原五文件完整恢复、备份保留、未写ACF/canonical journal、未发布。Root确认无Dota，不使用强杀。

peer v01的NUL/rename错误真实失败，保留源码和失败记录但不得执行。v02在实际完整LAB完成Install→Restore；但默认Bundle参数存在问题，必须显式传`-Bundle`的绝对路径，不能把默认Plan/参数路径猜测当成功。peer后续staged中断保留，仅在精确识别该目录后隔离，再新run02安装，用户已确认成功；全部backup保留。最终peer恢复需与新包测试安排协调，当前不得擅自清理或覆盖backup。LAB完整往返与客机用户确认是不同证据，均不是SDK发布。

## 下一步与授权边界

0201新recipe及受控原生主菜单GC route正在开发：启动普通客户端时不自动`+entry`，由正常UI建/入原条目Local Host，两人到齐后再开局，实际route/owned进程/日志/holds必须绑定。它不是采用现成手动进程或开启Tools/cheats的替代路线。

当前没有0201 plan、unsigned、签名、原生验收或发布。先完成两仓源码/operator同步和具体候选审阅；变化后的新包需要相应签名批准，不能沿用1107批准扩大范围。还需实际peer900/1000矩阵、免费英雄、真实带饰品波次、五场景淘汰冷回、共享Boss个人结果、有效新FPS，以及inspect/正常退出/holds/完整恢复，最后才允许发布与官方下载核验。220项历史差异仍明确延期，不是全HEAD发布或完整工程重构。

机器事实与原始证据摘要见[本次脱敏证据](portrait_resolution_guard_20261102.public.json)。此前1107构造、run01/02用户确认手动退出及run03退出原因未另确认的历史仍保留于[上一阶段记录](shared_boss_release_pipeline_20261101.md)，不能用本次正常退出改写旧失败或缺失证据。
