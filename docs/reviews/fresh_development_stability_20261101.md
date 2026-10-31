# 新鲜开发局稳定性有限复核（2026-11-01）

新鲜Tools/offline实例完成两段各约45秒游戏时间自然运行、五次新的受控VConsole连接、跨4场景容量后的冷重建及正常退出。这些有限步骤未复现旧开发实例的挂起；旧实例ETW后无响应与冷启动SnapshotError均继续保留为失败，原因未定。普通生产、长局和FPS不在本次通过范围。公开数据见[脱敏指标及原件SHA](../knowledge_base/evidence/fresh_development_stability_20261101.public.json)。本轮运行源码提交为game `048a2d6b675325cd511abb01c5a122343052b2f7`、content `b1ac328e4467510c89fdfd8c6d9f79947d7c820a`；操作工具另行固定，不以开发验证代替完整签名包。

## 自然运行与持续连接

观察器v02只建立一次连接，无自动重连；初始READY为传输就绪，runtime_gate_verified=false，不能当作签名/全部运行字节证明。后续6条Lua回执经过真实Tools、offline、当前session_memory provider、archive/web/HTTP关闭门禁，均ok=true。两组armed→auto_paused分别为UTC22:46:39.696→22:47:24.590和22:54:25.014→22:55:09.923，游戏时钟增量45.000000及44.999939秒。定时器绑定当前world/provider，自动暂停回执均paused=true。其余墙钟时间大多暂停和人工操作，不能写作持续21分钟或长局稳定。

UTC23:02:50.211取得paused=true的exit_status，23:02:50.216为TRANSPORT_CLOSED；这是退出观察器连接，Dota当时仍正常响应，并非游戏已退出。两段前后及后续关键图为同1600×900有效前台窗口、非hung；倒计时02:20→01:35→00:50，均首波前0/90。头像端点完整，不证明逐帧零闪烁或FPS。

## 七个实际场景与冷重建

最初只有Wisp建造者、Bane5、DragonKnight3、Sven4、LifeStealer6共5种READY；两轮Sven→LifeStealer→Bane是热切，当时仅覆盖一次容量淘汰。随后五次新连接均完成严格modeproof、相机命令标记及正常连接关闭；第一次/第二次用helper v01，后三次用v02，全程保持paused=true、gameTime约808.566711、offline内存provider/web=false/HTTP=false。相机操作回执本身camera_result_verified=false，视觉结果由单独选中截图核对。

| 实际资产 | 首次READY | 第二次READY | 目录预期组件 |
| --- | --- | --- | --- |
| Wisp建造者 | 183ms | — | 0 |
| Bane／转生5 | 114ms | 146ms | 4 |
| DragonKnight／转生3 | 144ms | 145ms | 6 |
| Sven／转生4 | 170ms | 171ms | 6 |
| LifeStealer／转生6 | 155ms | — | 4 |
| Undying／转生1 | 127ms | — | 3 |
| Bloodseeker／转生2 | 167ms | — | 7 |

最终原生日志共10条READY、7种资产，DragonKnight/Sven/Bane均明确出现第二次READY，补足实际跨容量后的冷重建证据。独立查看新增1/2/3/4/回Bane5五张选中原图及严格窗口元数据，头像饰品外观与背景均完整；所有截图均暂停在00:50，不能写成战斗中性能测试。组件数是目录预期，不是原生逐网格可见计数；应用淘汰与再次READY也不能证明GPU立即释放。加载ms是原生ScenePanel READY日志，不是整段相机/点击操作延迟。

## 正常退出与仍待验证

UTC23:15:59.9336605Z在窗口Responding=true时发出WM_CLOSE；请求回执明确exit_verified=false。Root随后于23:16:10.0028381Z通过CIM确认没有Dota进程，未强杀。这是独立的后续退出确认，不能以消息已排队代替。

本次没有新ETW、未形成只改变重连/ETW/缓存之一的严格A/B，不能把旧挂起归因VConsole、Tools、退出、原生缓存、ETW或头像代码。两段短自然运行、暂停期间五次重连及有限冷重建不能覆盖正常生产/普通游廊、多人与长战斗、高波次/全部197外观。后续仍需完整签名生产玩法、相同负载FPS、足够长自然运行与反复跨容量资源生命周期观测。原13文件运行源码、冻结README/plan及此前审查/回执保持，原始session/账号/完整日志不进入公共文件。
