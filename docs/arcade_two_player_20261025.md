MP10 r2 已通过原条目、普通 Dota、非 Tools 的真实双人基本烟测：两名真实账号在同一局 N1 中活动，HUD 显示 2/4，并已观察推进到下一波 2、人口 4/10；第二台用户确认“移动和购买窗口都正常”。当前结论不是完整通关、长时间、四人或性能验收。游廊 HUD 的 HTTP 显示当前不可用，真实 HTTP 端到端、认证、云存档、付款及支付发奖均未通过；本局存档和现金支付保持关闭。

当前候选为 `D:/Survival_发布候选/20261025_ws4_arcade_two_player_v10r2`，版本标记 `WS4-MP-10`，签名序号 `2026102507`，运行文件 **6636**，内容 SHA256 为 `d76cffd911f1680922b2ed91e244ea2179f6527d71c89c9d13c920ba13967161`。以 [r2 最终候选核对](../output/arcade_two_player_20261025/candidate_build_r2_verified.json) 为准；较早构建尝试和 r1 记录保留，不能作为本版本成功结果。

| 验证项 | 当前事实 |
| --- | --- |
| 候选签名及完整包校验 | PASS；相同内容和序号，目录 VPK 加 4 个数据卷 |
| 本机普通 Dota 单人烟测 | PASS；1 名真实玩家，常规模式、N1，`svt_m10` 松散运行资源与签名候选完整核对一致 |
| HTTP 健康检查 | 本机 alias 三阶段曾有真实 200；本次双人游廊 HUD 为“当前不可用”，日志只证初始两 factory 返回 nil，后续阶段覆盖未知，端到端未通过 |
| 实际游戏内商品配置窗口 | 双人基本功能通过：月卡／特殊券 ¥25／充值 ¥1 可切换并关闭；有世界称号／星标遮价格左侧的未修复显示缺陷 |
| MP10 工坊更新及官方回下载 | PASS；第三次提交成功，同条目、同签名内容；官方 1313＋3406 回调及完整验签通过 |
| 原生游廊房间与对局 | 当前烟测为 Lobby `30075111792112899`、match `9061760618`，两名真实玩家；先前单人房留作历史 |
| 普通游廊双账号同局基本烟测 | PASS；两账号 FakeClient=0、N1 建造者、HUD 2/4、早期波次推进，第二台移动与窗口正常 |
| 完整通关／长时／四人／性能验收 | NOT_RUN／未完成，不能由基本烟测外推 |
| 云存档读写、真实结账、付款及支付发奖 | NOT_RUN；本候选不启用这些路径 |
| 正式商城结账及最终 VPK 完整读取覆盖 | 未通过／NOT_RUN；本次测试预览不证明正式结账，也未验证所有四卷的原生读取覆盖 |

实际提交时间为 `2026-10-25T15:22:58.328559+00:00`，同条目 `3824360109` 的新 Steam manifest 为字符串 `189575976105625615`。见 [第三次真实上传日志](../output/arcade_two_player_20261025/upload_after_route_repair.log) 和 [官方完整回下载证据](../output/arcade_two_player_20261025/download_evidence/20261025T152536Z_309af6c491f340d583d0df54984c6663/verification.json)：订阅刷新回调 1313、下载回调 3406 均成功，前后查询均禁用缓存，五个 VPK、6636 个运行文件、4 个数据卷的签名、CRC、双 hash 及 MD5 校验全部通过。

普通启动使用 Steam `-applaunch`，PID 37848，不含 Tools，cheats 关闭，见 [启动记录](../output/arcade_two_player_20261025/native_arcade_launch.json)。实际通过游廊库的原条目“更新→创建房间”，选择 `template_map`、Best location、未勾选 cheats，最初房间描述为 `WS4-MP10-2P`，Lobby 为 `30075111663150034`。[历史房间截图](../output/arcade_two_player_20261025/native_arcade_ui/room_state_12.png) 在 `2026-10-25T15:47:46Z` 显示一名真实玩家、1/4 和“本地房间”。这一历史阶段只证明原生建房；后续双人游戏与购买预览的新增证据见下，不能把旧截图当作本次双人通过。

前两次上传均发生 manifest timeout；原 pending、失败记录和完整证据保留，经过 fresh 官方核对及 CAS 后恢复原日志状态。第三次在现有 iKuuu 从规则模式临时改为全局后，HTTP／TLS HEAD 从断连变为可完成的 404 响应，随后提交成功；这不构成 child proxy 因果证明。上传后已恢复过规则模式；随后 Steam Cloud `login=false` 阻挡普通启动，取消启动后临时改为全局重新同步，Steam 库显示同步勾选才继续。未点击“仍启动”，未禁用 Steam Cloud。根在 `15:52:04Z` 完成规则模式恢复并切回 Dota 前台，见 [规则模式恢复截图](../output/arcade_two_player_20261025/vpn_rule_restored_after_cloud.png)。但日志实际在 `15:52:02Z` 记录 `SteamServersDisconnected(result=3)`，`15:52:25Z` 才重新登录 Steam；旧 Lobby 随之失效。[16:14:11Z 截图](../output/arcade_two_player_20261025/native_arcade_ui/waiting_peer_14.png) 已无房间。因此 `room_state_12.png` 和 `waiting_peer_13.png` 仅为历史画面，不能作为当前大厅仍存活的证据。

根随后在稳定规则网络下重新创建同一条目的 `template_map` 房间，选择 Best location、公开无密码、未勾选 cheats，描述为 `ws4-mp10-2p`。日志 `16:19:23Z` 记录 GC 7038 创建请求，`16:19:24Z` 返回新 Lobby `30075111711572277`；[16:19:51Z 新房间截图](../output/arcade_two_player_20261025/native_arcade_ui/recreated_room_19.png) 已目视核对 1/4、本地房间，PID 仍为 37848。这一阶段仍只有单人、未开局；该房间和截图现保留为历史，后续实际双人对局使用另一个新 Lobby。

任何加速器模式切换都应先完成，再创建房间。若 Steam 发生断线重连，按旧大厅已失效处理，必须实机核对并重建，再提供新的 Lobby 身份和房间证据；不能沿用旧截图认定大厅仍有效。

真实双人局为 Lobby `30075111792112899`、match `9061760618`，PID 37848。日志审阅确认房主 `76561198845461206` 与第二台 `76561198974301984` 注册，二者 `FakeClient=0`，见 [日志审阅](../output/arcade_two_player_20261025/two_player_native_log_review.json)。该日志快照停在 `17:15:47Z`，不能单独证明之后完整过程；[17:16:37Z N1 建造者／在线 2/4](../output/arcade_two_player_20261025/native_arcade_ui/party_room_transition_20261026_12.png) 与 [17:19:17Z 下一波 2、人口 4/10、在线 2/4](../output/arcade_two_player_20261025/native_arcade_ui/two_player_live_20261026_14.png) 由根目视核对。用户在第二台明确答复“移动和购买窗口都正常”。

原搜索／密码找房路径曾未找到房间；[截图 10](../output/arcade_two_player_20261025/native_arcade_ui/party_joined_20261026_10.png) 显示队伍 2 人而旧大厅仍为 1 人，[截图 11](../output/arcade_two_player_20261025/native_arcade_ui/leave_single_lobby_keep_party_20261026_11.png) 显示退出旧单人大厅后保留双人队伍。后续进入新局、开始与选择 N1 的每次点击没有逐一归因，不能写成根已完整操作“建房→开始”。可复现建议是先在 Dota 组队，再从原条目进入一局，并以实际游戏 HUD 两人为准；这不是完整导航自动化认证。失败搜索和旧大厅证据均保留。

根已目视核对原生双人局的 [月卡窗口打开（15）](../output/arcade_two_player_20261025/native_arcade_ui/two_player_purchase_open_20261026_15.png)、[特殊券 ¥25（16）](../output/arcade_two_player_20261025/native_arcade_ui/two_player_purchase_ticket_20261026_16.png)、[充值 ¥1（17）](../output/arcade_two_player_20261025/native_arcade_ui/two_player_purchase_recharge_20261026_17.png) 与 [窗口关闭、游戏画面恢复（18）](../output/arcade_two_player_20261025/native_arcade_ui/two_player_purchase_closed_20261026_18.png)。打开、切换、关闭功能通过，但 15 中世界称号和星标压住价格行左侧文字，数值 ¥58.00 仍可辨，功能按钮正常。这是非阻断基本烟测的确定显示缺陷，真实收费前必须修复；当前没有修改代码、重新编译或上传修复，不宣称 UI 全面通过。18 显示比赛正在暂停，根未自行恢复。证据已保存，本局不保存，Steam 可保留运行。一次只读 CIM 查询已于 `2026-10-25T17:33:40Z`（本地 26 日 01:33:40）确认本机 `dota2.exe=0`，本机已正常退出，见 [退出后审阅证据](../output/arcade_two_player_20261025/two_player_native_log_after_exit.json)；第二台是否退出未独立确认。

双人游戏内 HUD 显示 HTTP“当前不可用”。日志仅记录初始 sample 1、phase other/state 0 的 ScriptVM 和 legacy 两个 factory 调用成功但 request=nil，未发出请求；这不是 HTTP 状态码 0 响应，也不是后端拒绝。后续日志截止原因、后续探针是否执行均为 UNKNOWN，不能声称 setup／pregame／ingame 各阶段全部失败。没有已验证的真实 HTTP 回调、认证／云存档／付款／奖励端到端成功；[退出后只读审阅](../output/arcade_two_player_20261025/two_player_native_log_after_exit.json) 确认 console 仍为同一份 148761 字节快照，未发生可见补写，也没有新增 probe／status／phase／callback 记录。后续执行仍为 `UNKNOWN_NOT_LOGGED`，不能把退出后无补写解释成游戏内没有执行；原快照及其边界继续保留。

本轮直接使用 Dota 原生房间的 `template_map` 四人槽位，仍保留原四账号许可；实际双人验收至少需要两个真实账号处于同一原生对局。玩法载入 `systems/session_multiplayer_test.lua` 的本局内存 provider：身份来自引擎 Steam 账号，档案按账号、模式和本局 session 隔离，只提供本局默认属性及内存更新，`archive_enabled()` 固定返回 false。生产标记保持 `production`，引擎 cheats 必须关闭；网页认证配置在该专用候选中关闭，不依赖本轮旧网页授权、云存档或后端大厅分配服务器。

候选基于已签 v08 精确修改 6 项、新增 7 项，并仅从新候选移除 `maps/ws4_entry.vpk`；原 v08、仓库地图资源和 180 份保护模块保留。main 与 profile 的最小集成可逆，trusted snapshot 同步绑定二者。候选 UI manifest 从历史 v08 源仅增加一个测试 HUD include，不引入开发版的 onboarding 或独立 lobby。具体差异及包身份见上述候选记录和 [包构建校验](../output/arcade_two_player_20261025/package_build.json)。

右侧小卡片和购买遮层都有独立的 XML/CSS 默认 `collapse`，外层不绘制背景、不截获普通 HUD 点击。只在 `Game.GetMapInfo().map_name` 精确为 `template_map` 或 `maps/template_map.vpk`、布局齐备并收到本次服务端专用 NetTable 状态后显示。服务端每秒更新 `survival_arcade_multiplayer_test.state`，严格包含八项：`schema_version=1`、`enabled`、`session_only`、`online_players`、`capacity=4`、`host_player_id`、`http_phase`、`sequence`。序号为 1 至 2147483647 的整数，用于让重复状态仍产生新通知。真实在线人数来自引擎连接状态及非机器人检查；房主只采用原生宿主权限结果，未识别时显示“尚未识别”。坏状态、地图切换或地图 API 错误会隐藏组件，服务端诊断错误也会撤销启用状态。一次性 UI 日志只记录固定阶段、清洗后的地图名和固定字段类型。

HTTP 探针只向固定的 `https://pay.xiaofengnet.com/ws4-web/health` 发无参数匿名 GET，最多 8 组采样、300 秒；不携带账号、凭据、存档或支付数据。HUD 的“已收到响应”只表示探针观察到健康响应，不代表网页认证、云存档、支付接口或游廊服务器上的 HTTP 已通过。本机 smoke 的实际客户端地图名已确认是 `maps/template_map.vpk`；r2 修复了先前只接受短地图名而隐藏卡片的问题。

购买窗口中的三个 SKU 来自 `payment_backend.csv_catalog.build` 对正式 CSV 的公开投影：月卡 `archive_pass_monthly` 为 ¥58.00／30 天，特殊券 `special_lottery_ticket_single` 为 ¥25.00／张，充值 `u_coin_recharge` 为 ¥1.00／100 G币。完整目录配置指纹为 `76bf5409b90ed58f6061745302411bf38c71a3c8eb52645364235a2a2a31f1b6`；该投影随本候选编译资源受签名清单绑定。窗口明确显示“商品配置预览；尚未连接支付后台，本局不可支付”及“并非实时云报价”。它不读取或编造余额、个人持有／限购状态、订单、二维码、收银网址或支付成功状态，也不改变 `payment_test.js` 和服务端原现金门禁。实际游戏窗口通过与真实结账通过是两项独立验收。

本机证据以 [native_smoke_verified.json](../output/arcade_two_player_20261025/native_smoke_verified.json) 为准，包含 6636 项 alias 对照、真实人数、模式难度、HTTP 阶段及五张已目视核对的截图：`native_alias_ui/r2_mode.png`、`r2_purchase.png`、`purchase_ticket.png`、`purchase_recharge.png`、`purchase_closed.png`。启动参数记录在 [native_alias_launch.json](../output/arcade_two_player_20261025/native_alias_launch.json)，不含 `-tools`。松散 alias 通过不证明最终多卷 VPK 的原生读取，也不证明普通游廊房间能保留第二名玩家。

已有 64 项 UI 模拟回归与定向原生编译记录分别保存在 [UI 验证](../output/arcade_multiplayer_test_20261025/verification.json) 和 [四资源编译 receipt](../output/arcade_two_player_20261025/ui_compile.json)。模拟回归用于边界检查，实际游戏窗口观察单独以上述 smoke 记录为证。本轮上传、完整回下载与原生一人建房分别记录在 [当前发布记录](../publishing/workshop/arcade_two_player_20261025.json)。双人基本烟测已通过；完整通关、长时、四人、性能、游廊 HTTP 端到端、真实结账及完整原生 VPK 读取覆盖仍未通过，后续只按新增真实证据更新。旧 v05／v08／v09 的成功、失败和历史验收保留在原记录及完整 listing 备份中，不作为 MP10 当前验收。

本轮代码已分别提交并推送：game `8ecb4a2699de8418cb921ae939ffcd092e1758f6`（`dev`）、content `70a5aa88e4852221fd79d58ddc30d7ccdc5ad802`（`master`），根核对两仓远端与本地一致、相关 7 套检查通过、原有 107 份文件字节完整保留。本次仅补正文档，尚不属于这两个已推送提交；跟进提交由根处理。
