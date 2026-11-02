# 2026-11-02 抽卡交付移交：0202因快照错误拒发，0203源码就绪

**0202明确不得发布，不能把画面通过当作整体验收。** 普通owned客户端已完成四奖池16张真实图，39券保持，四池均实际走native_error→同主题动画→正常回窗；但完整原生日志在冷启动12:14:35／12:15:05累计10次`Failed to serialize CUserMsg_CustomGameEvent [148]`，触发保留的否决门槛。owned19776已正常关闭、keeper真实exit0并完整恢复0104（实际exit0）。正式远端仍0104，manifest `7025356658517360342`，没有Submit或新官方下载。

当前新增0203薄适配仅源码就绪：0104父上原四项加已审`archive_service.lua`，尚未完成本轮新Git／plan／签名／原生验证。Root正在准备五项新候选；0202全部源码、签包、16图、日志与备份保留，旧视觉不能替代0203验收。

## 已确认的原因与交付范围

实际0104内四段WebM均存在，且与开发片逐字节相同；安装的旧播放器JS/CSS没有新fallback。此前d71开发修复没有发布，已签未发0201也不包含它，因此不能把开发Tools演出成功当成用户当前游廊已修好。原生MovieError是已观察事实，底层读包或解码的具体原因尚未证明；官方intro为松散文件、同为VP9/Vorbis，只是待对照线索，不构成统一结论。

独立热修复`2026110202 / WS4-LOTTERY-HOTFIX-02`以认证0104为父，仅替换四项既有运行文件：抽卡`lottery_cinematic_v1.vjs_c/.vcss_c`、`ui/production_ui_service.lua`、`ui/ui_request_router.lua`。JS/CSS作者源及content镜像另作两组官方编译绑定；视频与主题图继承父包。维持6917资源、184保护模块、原五账号／四人容量及后台配置。

0202没有搭车0201未发布的17项，23个源域精确延期。0203仅晋升其中已审archive UI-wire一项（Git-LF SHA `6a50c80d15ba98374d8a7df31aa664112070a8ffb4e8b71867a0fd1ae2cddec4`），其余16运行资源＋3game作者源＋3content镜像共22域继续延期，旧220项历史延期不动。0201的头像／共享Boss等产物和原门槛保持；不宣称完整HEAD已发布，未来合并不能用旧播放器覆盖本轮修复。

先完整认证0104原18份可信审查，再仅替换其中已有router并新增production UI，最终19份、原17份逐字保持；两个训练源分别审查。直接对实际父源归一CRLF比较，production UI仅提升错误表为模块常量并增加训练中文映射，router仅修改注释及中文映射，未夹带认证、交易或发奖改动。第一次计划因错误的“父审阅与payload必须完全不交”假设在签名／换包前拒绝；修复不是放宽原18份保护。

## 不可变源码与实际产物

运行源game `d611d7c7e27d2d0f0722bad9cce04fb8c3d862eb`、content `ef3f6ad1343ceb327a9932cd8317eafd7dd54874`；operator `0a82ff5e13bf63cbe58c98b3f5056d50482e5e11`，均已推送。

| 产物 | SHA256 |
| --- | --- |
| `plan_v02.json` | `d24f0440a98a21c1e8e3868c5325d5ac12dbafca594db5c9be4b0954b6709a62` |
| `unsigned_v02.json` | `201cae68824581108919f9c8ec8434c35d1b7ed025ba051c3237e30c9d39e806` |
| 已签`package.json` | `3a59fd1528b99554d989685293ae29a2116b401db94ae7c3c354ad32cdc111a4` |
| content身份 | `852e07b74d3bf289dc22ddf8691929a6e698a474606164d82681d34a59d4d307` |

报告位于`output/lottery_hotfix_release_20261102/`。独立unsigned审阅实核四个物理payload与计划一致，manifest严格等父包四行投影：6913未变行、184保护行均保持；unsigned仅六个文件且没有签名。随后Root实际签包成功；这些证据仍不替代普通原生验收。

0202的64项发行隔离测试、9个生产模块模拟场景及两条consumer流程回归通过，JS/CSS官方编译两项成功；这没有阻止上述真实网络失败。0203新family26项＋common28项共54项隔离回归通过，仍不是原生验收。没有新增FPS结论。失败索引仅四个固定pool：初始化O(1)，稳定演出外0新计时器／原生状态查询；首错后该pool后续0新Movie、0错误轮询，至多五个复用节点／一张当前主题图、两个活动计时器。真实抽奖仍使用原ACK结果，不增加抽卡、购买、领取或兑换请求。

## 0202实机结果、退出与实际恢复

事务`run01_lottery_preview`位于`D:/Survival_本地排演/20261102_ws4_lottery_hotfix_v09/`，原owned普通PID19776、创建UTC`2026-11-02T03:58:42.2287750Z`、端口29062、direct路线，非Tools／离线逻辑测试。四池各早晚演出与窗前／返回共16张图，Root实际核对全部主题与回窗，39券不变；并非真人抽卡或结果卡片消费验证。

全日志10次序列化失败使0202拒发。Root于UTC04:57:13正常WM_CLOSE，04:57:15.265260的同retained handle证明`OWNED_DOTA_EXITED_HOLDS_COMPLETED`，keeper执行会话59744实际exit0；05:27:30.067788恢复回执为`ORIGINAL0104_FIVE_FILES_FULLY_RESTORED`，恢复命令真实exit0，保留备份，未写ACF或canonical journal。没有强杀、没有上传0202。

## 0203源码与接手边界

NEW `tools/lottery_snapshot_release_20261102`通过私有哈希钉死的薄适配复用0202构建／操作／下载，不改旧文件；独立v10输出与STORE、端口29064。五运行项、6917资源／184保护、20可信审查、两组compiled绑定；原18先完整认证，原17保持、router替换、production及archive新增，Training2和UIWire1分列。

真实只读已推d611源码读取确认五项范围、archive等于已审6a50源码、剩19game＋3content域延期；这不是新plan或签包。当前尚未做0203新Git、plan、unsigned、签名、换包或原生测试。Root接续双仓同步、新具体候选及排演；普通冷N1开档与四pool新证据、完整日志零序列化／Snapshot错误、正常退出和0104恢复均须重新取得，之后才能preflight／原条目更新／官方下载。旧0202视觉、Tools或模拟回归都不能冒充新包通过。用户已准许重开，执行仍由Root负责；不在知识库保留授权页截图、nonce或原始认证日志。

lineage bootstrap已真实完成：head为认证0104、generation0、pending为空，0 SDK调用、0 canonical journal写入。其CAS用于拒绝过期发布覆盖；bootstrap不等于候选已上传。

为腾出完整备份空间，Root将已完成旧正式恢复的v03归档33文件、7576239101字节，迁至`C:/Survival_排演归档/20261102/completed_candidate14_v03`并逐项核SHA／保留ACL，D盘原位置仅留`ARCHIVED_TO_C_20261102.json`指针。正式包、认证0104父、0201待验及旧签包均保留，不改旧history；旧v03恢复入口不能在未找回归档时直接重跑。 另旧v04的31文件、7576239932字节已完整SHA／ACL核验后归档到`C:/Survival_排演归档/20261102/completed_candidate14_v04`，D盘原位置保留归档指针；同样不能在未找回归档时重跑其恢复入口。

安全哈希、已发生与待发生字段见[配套机器摘要](lottery_arcade_delivery_20261102.public.json)。最终阶段由Root按后续实际回执更新，本记录不得被当作READY开关。
