# HTTP 恢复继续排查：原生房间换图前后对照与官方问题

本轮没有新运行代码或后台部署；游廊运行包保持 1806，manifest
`6295798134948076528`。用户要求尽力今天恢复，并核实是否官方问题。
仍未恢复登录；本轮没有把静态检查、草稿或工坊健康当成修复成功。

## 原生入口对照的实际结果

第一轮全新菜单客户端 PID 31820 被用户手动进入游戏打断，用户明确确认刚才操作过。
不将该轮跳转记为自动行为或受控原生建房结果；正常退出并保留日志。

第二轮使用全新普通客户端 PID 27036 / FILETIME 134394762796966363：
启动参数没有 Tools/dev/addon、作弊或直接启动地图命令。从原生游廊游戏库进入项目，
官方页面显示“将使用玩家电脑作为主机”；默认最佳地区创建房间仍标“本地房间”，1/4人。
原生地图下拉框只有 ws4_entry，未改变 maps、条目可见性或生产 roster 要求。
实际点击开始及接受，没有聊天、邀请、真实交易或假造账号。

45.008 秒外部只读采样共 411 次，只扫描模块一次、ReadProcessMemory 3032 次，
固定字段 O(1) 采样，仅记录状态变化，不调用游戏函数、不写内存或增加游戏计时器。
这是诊断调用数，不是原生 FPS 测试。

采样在尚未换图的 **ws4_entry** 捕获：脚本 VM 有效，GC 主房间有效，原生字段中的
游戏 ID 确实是 **3824360109**。该值不在已分析官方 Windows server.dll 的固定五项
允许表内。因此依据原生分支推导，即使保留房间、不执行 changelevel，当前 ID 条件
仍不满足；没有在这个入口 VM 主动执行新的 HTTP 请求，不能把字段采样写成入口 HTTP 实测。

同进程后续实际地图为 template_map，GC 主房间为空，备用集合仅有一分配槽、没有
工厂可选房间；界面再次显示 WS4-WEB-04/start/create/0/F:nn/H:l。
这与此前正式地图 GET 三轮全空、0 Send 的实际结果一致。
45秒采样本身没有连续覆盖后续换图，后者是另一次带同一进程身份的只读核对。

因此修正排查重点：**缺少 GC 房间不是唯一阻断，仅修换图不足以恢复当前接口。**
当前直接阻断属于官方引擎提供的联网能力/准入检查；是否有意限制、是否某次更新回归、
最早引入日期及官方独立服务器二进制的行为，仍须分别确认。

## 官方渠道与条目状态

通过官方 Steam SDK 对同一条目作精确只读查询：visibility=3、banned=false、
资源总大小3812564242字节，更新提交0。accepted_for_use字段为false，但该字段不能
单独证明自定义游戏专服或HTTP审批状态，没有把它当成根因。
独立验签工具再次返回 READY，所有探针通过、未重启中转。

Valve 官方问题仓库存在其他开发者的
[自定义游戏HTTP故障报告 #35497](https://github.com/ValveSoftware/Dota2-Gameplay/issues/35497)
及 [强制本地托管报告 #35302](https://github.com/ValveSoftware/Dota2-Gameplay/issues/35302)。
本轮读到35497的12条回复均为普通用户关联NONE，没有维护者确认或已发布修复。
这些是第三方作者在官方仓库的报告，不能称“Valve已承认此故障”。

另有 [33945](https://github.com/ValveSoftware/Dota2-Gameplay/issues/33945) 的作者确认
改公开后能开始载图；它不是 Valve 维护者说明，也不保证当前 unlisted 条目改公开后
能获得专服。没有据此擅自开放可见性或承诺可以当天通过平台限制。

检查当前二进制未发现新的 Server HTTP 创建接口：两个现有名称共用工厂；
CreateRemoteHTTPRequest的原生标识为BotVM，公开API目录也将其归入Bots，不能当成本
游戏服务器VM的替代接口。Panorama二进制则明确含AsyncWebRequest已移除提示。
没有修改引擎、冒用其他工坊 ID 或新增跨VM旁路。

## 对外复现草稿与证据

已准备英文最小复现和脱敏公开事实，保存在树外
`D:/Survival_本地工具/runs/login_create_failure_20261118/valve_http_report_20261118`。
评论草稿 SHA256为 `4b9462abd164f9ab1a30c50dd732a98d8cc2cb9fbff2318280c794abd07bc850`。
目标为官方问题35497的补充评论，问题包括当前条目如何恢复HTTP或取得合法托管支持。
草稿没有玩家认证、账号资料、原始日志/转储。用户明确授权后，以当前 GitHub 账号
yadongji 按上述摘要的原文提交一次，官方 API 返回201，随后通过无需认证的官方 API
逐字回读确认公开可见：[实际评论](https://github.com/ValveSoftware/Dota2-Gameplay/issues/35497#issuecomment-6978076614)。
提交及公开回读的真实回执均已登记；没有上传原始日志或转储。

## 国服对照及已授权临时公开实验

正常关闭上一客户端后，使用官方临时 -perfectworld 参数启动普通客户端 PID31244，
没有改持久启动项、填写实名或接受新的注册条款。原生地区列表显示华东/华北/华中/华南；
实际选择华东创建1/4房间并开始，仍为本地主机，template_map再次显示F:nn/H:l。
所以只更换全球区/国服地区尚未恢复 HTTP，没有把它当成独立服务器实测。

用户已在 call_06c1964f80c9482f927728908c92dbfe 回复“授权临时公开并恢复”。
原提案摘要3a53333eed71d26365bbef942c7b38fa926ac4a1287fba5d99f4bed521f402d3，
原提案的未授权历史状态保留。新增已提交授权文件与受限 visibility-test 入口，只允许
原条目可见性3→0→3；同一发行锁/受校验lease覆盖两次提交和测试窗口，不重写包journal。
按公开提交时刻起180秒发起恢复，用户授权上限600秒；回调未知先查询，不重试公开。
可提前恢复；查询或测试异常仍执行已授权的反向更新，最终回读中英文受保护字段。
正常发行仍拒绝公开，不能把此一次授权沿用为正式开放。

执行前7项隔离可见性/恢复测试和18项既有门禁测试通过；均无真实SDK或网络写入。
测试覆盖未知回调、查询异常、非本轮句柄、非可见性字段、过期父代际以及普通发行仍拒绝公开。
等待为树外单文件4Hz检查，至多180秒，O(1)空间；无游戏循环、场景扫描或游戏内原生调用。
第一窗口已实际完成3→0→3：公开/恢复两次SDK回调均result1，中英文官方受保护字段
均未变，包journal未变，公开提交至恢复回读156.466秒。实际回执位于树外
`public_visibility_hosting_test_actual01/verification.json`。

第一窗口的通用已发布启动入口因元数据pending而正确拒绝，没有修改其门禁。
另经请求/lease/包journal/正式回执核验后仅启动普通主菜单；Steam启动因SDK进程
占用app570未拉起，直接普通-steam启动虽进入菜单，但创建房间出现VAC无法验证机器。
这不是有效的公开专服对照，不能据此宣称公开仍无法恢复HTTP。已提前恢复并正常回读。

补测修正为**先正常启动Steam客户端，再切公开；观察等待期间SteamAPI_Shutdown，
同一发行lease/全局锁仍持有，恢复时重新初始化SDK**。公开时间按同一授权累计，
先扣除156.466秒；补测回执关闭本次授权，禁止反复复用。补测前8项可见性/累计时长
隔离测试与18项既有门禁通过，无真实SDK调用。

补测实际已完成，使用从Steam标准applaunch启动的普通客户端PID16288 / FILETIME
134394787318110308。公开回读确认且SDK释放后，原生创建1/4房间、开始、接受均正常，
未再出现VAC提示，但界面仍明确显示**本地房间**，没有分配到官方独立服务器。
45.026秒只读采样411次、模块扫描1次、ReadProcessMemory4041次；每次只看固定字段
和第一个备用槽，容量>1会标待人工复核，不全量扫描。游戏函数/内存写入/HTTP发送均0。
入口ws4_entry主房间及备用槽先后均有正确3824360109，仍不满足当前二进制允许表；
换到template_map后房间消失，实际界面再次显示WS4-WEB-04/start/create/0/F:nn/H:l。

确认结果后提前恢复。本轮公开提交到恢复官方回读114.915秒；两轮累计271.381秒
（约4分31秒），低于600秒。四次公开/恢复提交回调全部result1、legal=false；
中英文官方最终visibility均3，标题、完整介绍、资源字段、标签、封面均与各自之前一致。
补测回执authorization_closed=true，后续计划拒绝复用此临时授权。lineage代际29、
pending=null；canonical包journal逐字节未改。

因此目前只能结论为：**短时公开未解决本地托管或HTTP创建空值，登录仍未恢复**。
未取得Linux专服，不能写成“专服HTTP实测也失败”；长时间公开的缓存/审核影响未验证，
不擅自延长公开。当前官方Windows接口的阻断已确认，是否Valve回归或有意规则、
何时首次引入及支持的合法恢复方式，仍待官方确认；不保证当天可修复平台限制。

收口复核：1806、manifest6295798134948076528，完整pending_sources/dirty_runtime均空，
published_route恢复ok，实际安装ACF仍为同一manifest；后台验签check再次READY，
未重启中转或部署。原15项用户改动逐文件SHA256保持，真实交易0，五账号准入未改。
补测回执已登记e2bd3afd42474c367066eef245de3f1438562a959f4e7a2724c9a633ec1a10e6，
只读采样已登记20e0710a8dc3f56d76831024650cb042090cd36121fee43fcdf381edc9ac3415。
第一轮纯元数据verification缺少登记工具已知存储绑定，record明确拒绝；原始回执保留，
没有伪造生成日期、改名或补假字段规避，补测回执保留对它的原路径和SHA依赖。

实际回执根为 `D:/Survival_本地工具/runs/login_create_failure_20261118`：
`native1806_retention02_watch_receipt.json`、`native1806_retention02_after_handoff_gate_receipt.json`、
`current_readonly_ugc_status_receipt.json`、`valve_report_preparation_receipt.json`、
`valve_comment_submission_receipt.json`、`valve_public_comment_verification_receipt.json`、
`native1806_public_test02_receipt.json`及两轮public_visibility_hosting_test_actual*/verification.json。
当前客户端留在授权失败界面；采样已自然结束，无新的本机签包暂装/恢复事务。

## 用户收窄目标：只接受正式游廊完整联网

用户在call_a87ffac5dbca42fca1f7f178d1137c0c明确回复“只接受正式游廊完整联网”。
后续验收须从正式游廊进入、真实Steam授权并正常使用云端功能；离线Tools、当局内存档、
关闭授权放行和只验证后台health均不满足。未启动已做入口检查的离线模式，不扩大收费授权。

再次核对真实1806候选的addoninfo.txt：maps=ws4_entry、IsPlayable=1，入口和正式地图
MaxPlayers均为4。279字节、SHA256
fc4af019c3bd208e37566d8c0f68cdd38f34396bcb570ba9dae82d3e2a554c85，
与1806真实full_manifest的对应资源完全一致。工作区的旧入口人数1不是当前正式包内容，
不能把它当根因盲改重发；此次已检查配置未发现强制本地托管字段，不等于证明所有GC策略。

仅读安装的client/server/engine2三个官方二进制，候选配置名含
dota_play_custom_server、dota_play_custom_server_name、dota_server_allow_custom_games等。
仅出现字符串不构成可用的强制专服开关，未更改它们、执行未知控制台命令或改引擎。
本轮是一次约193MiB文件扫描，O(文件字节数)，无游戏定时器/场景扫描、SDK写入、
引擎函数或内存写入。实际回执formal_online_config_candidates_receipt.json已登记
d5f0a0241aa3a41f642286fe9f15bd32dd6ed972c99666c55b17a28b7f8a8299。

已向用户请求另一台现有测试电脑、已有获准测试账号从正常Steam/正式游廊进入一次，
只反馈是否仍为start/create/0及F:nn/H:l。此对照尚无结果，不能写成第二台机器已验证。
不因此购机、升级、额外公开或伪造名单；正式联网仍未恢复，尚无经过验证的新恢复方案。
