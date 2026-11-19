# 临时联网传输适配：普通引擎真实往返成功，正式授权仍待

用户只接受正式游廊完整联网，并已接受临时联网辅助程序。原生工厂nn故障仍在，
不是靠增加服务器配置解决。本轮实现受限文件传输，保留原Steam/PWA、账号/会话、
云档案及支付检查；原生对象成功时优先使用，不自动重发任何业务写入。

## 已实现和真实验证

新增core/file_http_bridge.lua、config/file_http_bridge.lua和独立Python助手，
只在原五账号生产配置、非Tools、非专服、template_map使用。固定后台和现有路由，
拒绝任意URL/控制台/Lua执行。按请求ID、nonce、world/epoch和截止时间处理回包；
助手只在内存保存真实设备码/访问令牌，按账号/会话替换为临时代号，不伪造登录。
原生请求工厂新增创建失败后的适配入口，既有调用方保留一次Send及原校验。

完整适配层真实匿名测试：普通客户端PID37568 / FILETIME134394909049799684，
实际Tools=false、sv_cheats=0，原生nn但返回适配对象；助手一次HTTPS GET，
Lua收到200/119字节，health_ok=true，并ack结束。无云端业务变更。
这是本地未签名开发诊断，不是正式游廊或真实授权通过。
执行桥接源码SHA733af7c6e00a1ab6cb2e16c5d9cb7e0c6589d8250a45799415dc88fa13a190e8，
助手SHA33e5e3c36215a0d15629e608109fe7908bc104dea0f01ab8d74d14c18d9354b3。

先前三次尝试保留：助手遇日志截断退出；请求对象成功但握手未通过；握手成功但
Lua空table编码成[]导致空headers被拒。已修正增量日志截断跟随、固定协议数值兼容/
本机承载者命令来源及空headers协议，第四轮真实成功。不能把前三轮算作通过。

7项Python永久无网络回归、24项Lua传输断言、原工厂43项及原PWA/在线支付授权
回归通过；模拟包括令牌代号/账号会话隔离、过期/上限、重复/旧回包、畸形路由/块、
10000次索引截止堆变更、16KiB多块字节还原和控制台行长。未真实购买、用券或清档。
复杂度、调用预算和使用限制见tools/workshop_test/FILE_HTTP_BRIDGE.md。
实机没有FPS基准，不能以模拟计数代替。助手不提供响应数字签名；nonce只是关联。

## 恢复与待办

真实证据根D:/Survival_本地工具/runs/login_create_failure_20261118/full_file_bridge_control01。
正常退出后，原addon_game_mode.lua按原SHA6c4b2b57…恢复；助手生成cfg均已自行按
所属摘要清理，正式安装/游廊/后台未改。原15项用户改动继续保留。
初始prepared回执登记因无已知存储字段被拒，原回执保留；补充backup_receipt后
成功登记6016339b…，真实往返8e4c1d86…，恢复5c6e163b…。

Steam验签只读检查READY，无重启；正式包仍1806/manifest6295798134948076528。
下一步提交双仓绑定、全量待发核对、正式签包/普通客户端验收、原条目上传和官方
完整下载，随后由玩家完成真实浏览器Steam授权，验证云档案读取与正常退出保存。
这些完成前不称正式联网恢复或已同步游廊；不开放公众准入或临时公开。

## 11月19日零点后续构建

进一步补齐助手每局一次的新随机bootstrap challenge：DoUniqueString在新VM可能
重用，不能单独区分局。新握手消耗预置nonce并生成下一局nonce，重复ready不会重置
最高请求ID；旧nonce即使epoch相同也拒绝。第8项Python回归覆盖相同epoch的换局、
重复ready和旧请求拒绝。Lua累计24项覆盖12KiB/4块还原和工厂fallback整合。

1807候选已过编译、生产转换、全部运行审查，但签包plan拒绝来源摘要不一致。
实查仅coverage inventory/scope/ledger及派生projection四摘要不同，运行资源行无差异、
blockers为空。原因是我在收集/签包之间修改了上述助手文件，触发严格来源门禁。
失败任务pack_2026111807_52398505及树外projection_diff.json保留，没有上传或签成包。
先提交完整助手改动，再建新独立候选，之后所有源文件冻结至发行完成。

## 1901实际交付与正式测试失败

pack_2026111901_8654b693已通过统一流水线，7065资源/5个VPK，官方完整下载
一致、完整待发0，manifest3846809716394046984。运行来源game=a95d3cc6906ef0e5415a5b7002f2ecb16f74b5e3，
content=50453eb597c35fba774486afb81ccb70126e662a；发布operator954f95ba3ce375e5f2fdb496cde700a2d028ee99。
真实下载回执为output/packager/pack_2026111901_8654b693/download_evidence/
20261118T161756Z_259eb244f0314e949709abb613b1078b/verification.json。

正式Steam普通客户端PID32208/FILETIME134394924232055597，从原游廊条目创建房间，
默认ws4_entry/4人、无Tools/dev/addon参数。首次接受窗口超时，第二次正常进入。
真实授权仍未恢复：界面start/http/0/F:nn/H:l，证明适配对象已返回，但助手无请求，
该局日志没有SFB帧、bootstrap文件执行或Lua运行错误；不能算登录成功。
已正常关闭此客户端，助手自身cfg清理。后台未部署、真实授权/云档案/购买均未验证。
证据根formal_file_bridge_1901_attempt01，结果登记04700b9b…。

实际候选模块在树外runner执行原24项Lua回归也通过，没有据此把故障归咎于混淆。
随后将初始化改为与startup_loading_service相同的模式：同步执行第一次有预算的
握手步骤，再用正延迟设置Think，避免把首步交给启动阶段零延迟计时。新增每world
一次started及仅超时时ticks/execs/armed/秒数的稀疏无凭据诊断；不添加全量扫描。
这是针对调度差异的待验修正，尚不能断言已证明根因。

新增首步同步/正延迟断言后Lua25项、原工厂43项、Python8项通过。新代码在普通
非Tools/cheats0匿名实际测试再次一次GET200/119字节/health_ok=true，真实业务0。
证据根full_file_bridge_control02，桥接源码df185e60ca2d8bf34900980f8b747c49d5f045aacafded33f461f5ec39a72ac4。
正常退出后入口按原摘要恢复，cfg清理；准备/往返/恢复登记6f6fb7ad…/6c4d499f…/4a4319ae…。
下一候选继续保持正式真实授权验证门禁，不能以这次匿名成功代替正式登录。

## 1902计数定位与协议2原生KV替换

1902/manifest1711223426355843111已完整同步，7065资源，待发0；任务
pack_2026111902_dc2057bd。正式普通客户端PID37540/FILETIME134394956248934929
实际每10秒51次Think、5次控制台尝试、armed=false，仍start/http/0/F:nn/H:l。
这排除了“计时器未运行”的推断。未确认命令失效的具体引擎机制；不能宣称已证明某
官方策略变化。已正常退出，结果回执formal_file_bridge_1902_attempt01，登记926b1264…。

改用原生LoadKeyValues直接回读固定cfg/*.txt，移除exec和四个Convars命令；不增加
任意文件路径或执行能力。保持HTTPS单次转发、真实凭据内存代号和原有玩家认证。
协议2使用带n前缀随机nonce、固定字段/带b前缀base64分块KV，拒绝引号/换行/反斜杠
注入。每Think最多一个原生KV读，回复16×192字节，空闲读0；完整成本见工具说明。

真实普通引擎能力验证native_kv_control01：cfg和scripts两路径均读到marker7，树外
工具按摘要改为8后下一次Think即读到8；Tools=false/cheats0、HTTP0，不能算授权。
正常退出恢复原入口并删除两份所属测试值；往返/恢复登记53ecab19…/37225133…。

协议2完整HTTPS匿名实证full_file_bridge_control03：PID37060/
FILETIME134394970002519557，Tools=false/cheats0，两原生HTTP工厂nn；实际固定GET
一次，Lua原生KV收到200/119字节/health_ok=true并ack，控制台命令0、云业务0。
桥接源码e4f0c2c0fbf68ddd62719166eedff9fedc8a60e45c4fcefd6c2940452a19a043；助手
21646d7110b01dd8e3db13805ea68e3ab7daf62c12b8fe333fe77c9859d63676。
正常退出后原入口按原SHA恢复，所属KV文件清理。准备/往返/恢复登记
dea65b6c…/1f3265b4…/e4303f40…；Lua25项、Python9项与原工厂43项通过。
正式签包、真实Steam授权和云档案仍待，不能把本地匿名实证称为已修复正式登录。

## 1903正式游廊传输通过；等待玩家Steam网页确认

1903已完整同步：任务pack_2026111903_9c093551，7065资源/5个VPK，官方完整下载
逐文件一致、完整待发0，Steam manifest5892770527169450733。运行来源game=
f778a51f67d6895a2cd373bf217e8af8b9c007bc、content=903da853570c6076da0ff2a86a9abf48e0580da1；
发布operator=3e1e729952d10b01fb23efc435bf67312d56fbfe，双仓已推送。后台本轮未部署。

正式普通客户端PID27496/FILETIME134394980788961131，无Tools/dev/addon参数；
从原游廊条目默认ws4_entry房间进入。协议2在真实房间完成ready、POST
/v1/player-auth/start实际200/240字节、后续poll持续200/48字节，并有游戏ack。
界面已显示有效授权码并等待网页确认，原生工厂仍nn，传输由已获用户接受的本机
助手承担。助手当前源码与签包Git来源匹配，SHA6a497514fa0120afde2c30a82a347f4c13ea8d2991f4fc946f737edc07b40da7。
这是正式传输通过；尚未观察到Steam approved，云档案读取/保存和多人验收不能算通过。
已向用户请求在当前客户端完成网页Steam确认，客户端与助手保持运行；不要自动代兑、
购买、清档或用虚构凭据放行。原生HTTP限制的具体官方变更仍未获确认。

真实脱敏回执formal_file_bridge_1903_attempt01/transport_verified_auth_pending_receipt.json，
登记7598da1d…；不把授权码、真实设备码/访问令牌或业务原文加入Git。
桌面“我在dota2苟发育-联网助手.lnk”已建立，当前指向树外
D:/Survival_本地工具/runs/online_helper_entry_20261119_v2/start_online.ps1。
先正常退出Dota再双击；入口核对当前已验证正式版本和助手Git字节后，启动普通Steam
客户端与助手，仍由玩家从原游廊进入。入口跟随当前已验证版本，避免固定旧版陷阱。
v1及快捷方式原备份保留；v2登记a108f5a2…，安装动作没有另开游戏或打断当前局。

当前验收使用已发布官方下载包，没有候选暂装、keeper或待恢复事务；安装未切换。
本节只记录已发生的正式传输结果，运行资源和助手不改；后续收到用户Steam确认后
继续观察approved、session/authenticate与云档案，不能将“已同步游廊”当作完整登录验收。

## 2026-11-19 用户完成正式授权并进入游戏

用户确认“已完成授权并进入游戏”。随后脱敏原生日志确认状态approved；协议2助手
收到批准poll200/292字节，session/authenticate200/22841、session/login200/38759、
archive/command200/14468均由游戏ack，真实http_fishing公开档案投影发布。
本轮未重打包、上传、切换安装或部署后台代码。1903及manifest5892770527169450733保持；
助手和Steam固定中转需要继续在线，原生工厂nn没有因此修复。
Steam DNS和中转恢复另见steam_verification_dns_recovery_20261119.md；
真实脱敏回执位于树外login_web_error_20261119/player_login_confirmed01，已登记3beca941…。
本次确认登录/入局和档案加载；未验证跨局保存、多人或3000在线，不自动执行真人购买和抽奖。
