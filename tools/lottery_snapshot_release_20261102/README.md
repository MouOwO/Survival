# 0203：四项演出／训练热修复与已审存档分包

0202已签普通客户端四池16张画面通过、39券未变，但原生日志仍出现10次`Failed to serialize CUserMsg_CustomGameEvent [148]`，因此禁止发布。0203不覆盖0202源码、签包、日志或备份；仅从正式0104父包构造五项替换：0202原四项加`systems/archive_service.lua`。资源仍6917、保护184、原五账号／四人准入不变，作者源编译绑定仍两组。

存档源码绑定Git-LF `6a50c80d15ba98374d8a7df31aa664112070a8ffb4e8b71867a0fd1ae2cddec4`，精确等0201已审UI-wire修复，不重写奖励或RPC。先完整认证原18可信审查，原17保持、router替换、production UI及archive新增，最终20；Training2与UIWire1分开声明。0201只晋升archive这一项，剩16运行资源＋3game作者源＋3content镜像共22域继续精确延期，旧220延期不动。

本目录为薄适配：`adapt.py`先核旧0202工具完整SHA，执行捕获的原字节；每个私有函数定点转换须恰好匹配一次，任一依赖／形状变化即拒绝，不在旧文件写入，也不共享旧模块对象。新builder/checks/ops/download沿用经过验证的完整认证、旋转分卷、五包物理备份、CAS、index-last、同handle退出及0104恢复。固定NEW前缀`20261102_ws4_lottery_snapshot_v10`、REPORT `output/lottery_snapshot_release_20261102`、STORE同前缀、端口29064、挂载日志`output/lottery_snapshot_rehearsal_20261102`。

默认或`--static-plan`零写／零key／零SDK／零原生动作。实际source plan仍由唯一`tools/release_pipeline.py`委托受审authority；**0202正常关闭并完整恢复0104之前，不得激活0203 common authority/hook**。Root完成双仓固定Git流程后提供新的不可变game/content/operator提交，先plan再unsigned，具体SHA审阅后才签名／排演。不会自动领用旧0202画面、手动新进程或未确认的READY结果。

本轮native保留普通同签包四pool无消耗预览、真实错误→主题动画→回窗、票数不变、同PID／CIM创建／native FILETIME、前后卷使用、同handle正常退出和完整0104恢复；另需本轮冷首个archive同步及真实开档画面，原生日志任何`CUserMsg_CustomGameEvent`序列化／快照错误继续拒绝。旧0202的画面只证明其有限视觉，不证明0203稳定性。没有Boss／双PC／无关FPS门槛，没有真人花券或发奖测试。Root根据实际新回执决定是否可发布及官方完整下载。

初始化／显式运营阶段按6917父行、不可变源树及五个绑定O(M+S+B)；额外只读一组旧工具源码，每个不超过128KiB，无游戏帧循环。wire沿用已审分包预算／快照兼容修复；测试计数不等于native网络或FPS通过。keeper稳定等待仍为2000ms kernel wait，无周期CIM或全包hash。

```powershell
python -B tools/lottery_snapshot_release_20261102/build_release.py --static-plan
python -B -X utf8 -m unittest discover -s tools/lottery_snapshot_release_20261102 -p "test_*.py" -v
```

隔离测试只用合成证据／函数和系统临时文本文件，不调用签名、VPK构建、进程、GUI或Steam。真实范围读取另核已推`d611d7c7e27d2d0f0722bad9cce04fb8c3d862eb`的五个Git blob与实际父18审查、archive SHA及19＋3延期边界；它不是新plan／签包或普通客户端通过。
