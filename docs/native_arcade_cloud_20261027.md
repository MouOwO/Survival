# 原游廊登录与商城通信排查（2026-10-27）

原工坊条目 `3824360109` 的历史08已通过原生双人自动入口、网页登录和独立测试云档读回验收。修复加入方二维码的09已真实封包、上传并通过官方完整下载校验；2026-10-28加入方手机扫码后，用户明确确认“可以识别，商品和金额正确”，当前二维码状态为 `VERIFIED_NATIVE_GUEST_SCAN`。实际付款、到账和权益刷新仍未验收。

## 当前09：官方下载和加入方手机扫码已通过

`WS4-NATIVE-CLOUD-03`／`2026102709` 的内容摘要为 `1262cbe5905d760c6c15400e4051038613c6a78bffb99b64d9d2d5d609d3cf40`，索引摘要 `b09f36be87db6dc3c8f055e06a9c18438236437d0167c7634effba6707b37278`，总字节数3767362385、6658份资源。仅替换二维码UI编译文件，180份受保护模块和入口／认证核心保持原字节。

真实封包报告 `output/native_arcade_cloud_20261027/native_cloud_v03_package.json` 的原始SHA256为 `041b7b4fd90500ef15e48e7fa475731455cafbe8da132499d38d6e520004fff8`。`native_cloud_v03_upload.log` 已实际返回 `SUBMITTED_UNLISTED_PENDING_DOWNLOAD_AND_NATIVE_TEST`、`uploaded=true`、`legal_agreement_required=false`。

09的 `download_verified=true`：2026-10-28 07:05:07（UTC+08）完成新鲜官方查询、订阅回调 `1313 / result=1`、下载回调 `3406 / result=1`、安装manifest和完整签名资源核验，manifest为字符串 `3869894305253699960`。6658份资源、180份受保护模块、5个VPK及签名校验通过；下载器未改写发布日志。08的manifest和完整下载／登录证据只保存在 `verified_native08` 历史对象，不能沿用为09实机结果。

新09下载日志为 `output/native_arcade_cloud_20261027/native_cloud_v03_official_download_20261028.log`，实际退出码0；回执为 `output/native_arcade_cloud_20261027/download_evidence_v03/20261027T230507Z_68b94b8d9b024315b779eca43305e5e3/verification.json`，原始SHA256为 `15177b4c943afa61619ea8be892b431fa8bbf6c50a4a2a7e480c5bd84d212f45`。

本轮主机实际观察到原工坊房间2/4，两名玩家为“是无话吖”和“天才琪露诺”；随后同一普通Dota进程35164已进入N1正式游戏并打开商城。加入方手机扫码由用户确认通过，且商品和金额正确，安全摘要为 `output/native_cloud_v03_native_20261028/native09_guest_scan_acceptance.json`。该进程由用户重开、没有本轮原生日志，自动入口执行次数、HTTP计数和逐人云档未重新审计；本轮不得复制08的这些计数。代理未创建订单、未操作支付，用户是否创建新订单及订单总数未知，支付和到账继续保持未验收。

## 历史08真实验收（PASS）

普通 Steam 进程5688，无 `-dev`／Tools，`sv_cheats=0`。2026-10-27 22:01:43（UTC+08）载入 `ws4_entry`；22:01:59服务端确认真实名单为2人后自动换图，仅执行一次，22:02:04载入同工坊的 `template_map`。原 GC 房间对象随换图销毁，两名原玩家均进入同一目标地图。

- 两个获准账号885195478、1014036256均真实连接。加入方22:02:16在 SETUP 阶段分配成功；两人均为team2，随后均有原生英雄就绪记录，已解决旧team5分配问题。
- 两种原生 HTTP 接口各7次真实 `200`，覆盖setup、pregame、ingame；不是模拟回调。
- 22:06:13加载服务记录 `authentication_and_assets_ready=true`，启动界面准入完成。两人均通过真实 `http_fishing` 供应器读回云档：主机版本223→230，加入方7→10，后续仍有各自的档案刷新记录。
- 用户明确确认“可以了，登录没问题”，同时报告加入方购买二维码错位。用户确认与日志证据分开保存；没有虚构逐人PWA数据库授权时间，也没有据此认定支付到账。

证据：`output/native_cloud_v02_native_20261027/native08_transport_auth_acceptance.json`，SHA256 `daf5e2db2ec345f35779ad30ef6d4ba2c0ffc56c0163a2addf6cc3ef3b9519f2`。活跃原始日志仅记录读取时的前缀长度与摘要，导出的验收文件不包含授权链接、短码、令牌或订单正文。

[二维码修复记录](guest_payment_qr_20261027.md)已记录本地编译及46项检查通过，以及09官方下载和加入方手机扫码通过。08发行摘要及历史实机记录保持不变，09的扫码通过不代表已完成真实付款或权益到账验证。

## 固定对照基线（历史05）

- 此前用于对照并已重新完整校验的工坊包：`WS4-REFRESH-NATIVE-02`，序号 `2026102705`；历史08下载结果见下文。
- 内容摘要：`8a01a5b66603804c683b879043c220e4f9496d7cca75f304ac5d9da210794cf6`。
- 5 个 VPK、6655 份资源，签名及资源 CRC/MD5/SHA256 校验通过。不存在同数字 ID 的本地 addon 覆盖。
- 四测试账号限制及 `sv_cheats=0` 保持不变。历史05对照测试未创建订单、未付款、未修改云存档。

## 已完成的实机对照

| 路径 | 实际结果 | 结论边界 |
| --- | --- | --- |
| 同 ID 普通直接启动，无 `-dev`、Tools、insecure 或本地 addon 参数 | 两种原生 HTTP 接口均得到真实 `200`，覆盖 setup、pregame、ingame | 已排除必须使用 Tools / `-dev` 的假设；只验证本机单人 |
| 普通 Steam → 原游廊 → GC 本地主机房间 | 两种接口各 7 次返回 `nil`，无法发送 HTTP | 相同包在不同启动上下文中行为不同，不能靠显示登录按钮解决 |
| 菜单加 `-dev` 后创建原游廊房间 | 引擎明确阻止匹配／创建房间 | 不能作为原生多人修复方案 |
| GC 房间只读查询 | `sv_lan=false`；日志同时为 `ActivateServerFromLobby IsLan:YES` | 两个 LAN 标记不同，不能归因于 `sv_lan=1` |
| `changelevel template_map` | addon 挂载丢失、地图找不到、房间销毁、Dota 异常退出 | 禁止采用这一不完整命令 |
| 带完整工坊上下文的多人换图命令 | addon 保留，新地图载入；引擎重新激活原客户端；本机玩家保留；两 HTTP 接口各 6 次真实 `200` | 原 GC 房间对象销毁，仍须验证第二台实际玩家同行 |
| 实际双人手动换图 | 两个真实账号重连；同一加入方 P2P 连接跨图持续；每接口 7 次真实 `200` | 加入方晚到时已错过队伍分配窗口；用户提前退出，未观察换图后操作，因此玩家端验收未完成 |

已验证的完整换图命令为：

```text
changelevel template_map gamemode=15 customgamemode=3824360109 nomapvalidation=1
```

`gamemode=15` 是引擎的自定义游戏模式；`customgamemode`、`nomapvalidation` 来自当前官方客户端／服务器的自定义地图启动格式。该命令不修改作弊开关，也不提供身份或支付权限。不能把它替换成每名客户端各自执行 `dota_launch_custom_game`，后者可能分别创建单人服务器。

初始化日志会按 match 分流：必须一起审阅主日志与 `native_arcade.<match>.log`。旧 GC 对局的 `SteamGameServer_Init() OK` 和 API 激活记录实际在主日志，不能因分流日志没记录就推断未初始化。

## 证据位置

运行日志和截图保留在忽略的 `output` 下，不打进客户端或 Git：

- `output/native_direct_no_dev_20261027/b_no_dev_acceptance.json`
- `output/native_arcade_cloud_20261027/arcade_dev_acceptance.json`
- `output/native_arcade_no_dev_20261027/arcade_no_dev_acceptance.json`
- `output/native_arcade_no_dev_20261027/console_readonly_queries.json`
- `output/native_arcade_changelevel_20261027/changelevel_acceptance.json`
- `output/native_arcade_changelevel_addon_20261027/changelevel_addon_acceptance.json`
- `output/native_arcade_changelevel_two_player_20261027/two_player_changelevel_acceptance.json`
- `output/native_arcade_changelevel_two_player_20261027/user_observation.json`
- `output/native_engine_api_20261027/root_actual_result.json`
- `output/native_engine_api_20261027/root_after_changelevel_result.json`

用户最初选择了“掉线或停在旧图”，随后明确说明提前退出、没有观察到。以后引用这一轮时，应写“未观察、不能判定通过或掉线”，不得把最初选项当作确证断线。

## 自动入口修复与未通过项

服务端入口等待原生加载阶段完成和真实完整名单稳定后换图，客户端不再分别裸启动本地服务器。原名单通过固定 `ws4_native_roster` 地图选项传给目标地图；值只能来自服务器实际绑定账号32名单，不含 token 或会话凭据，也不提供任何身份／支付权限。

目标地图的原生自动准备和启动加载服务都增加完整名单屏障：慢玩家未到齐时取消倒计时；所有人到齐、逐人网页授权、客户端／资源就绪后才开放模式；选择模式后又须等全部档案载入才能启动玩法。原本的分队窗口和身份检查保持严格。

候选07暴露了测试夹具缺陷：`GameRules.GetCustomGamePlayerCount` 在当前引擎中不存在，旧的自动准备代码仅可选读取它，新入口却错误将其设为必需。该候选不得认定可用。修正使用真实的 `PlayerResource:GetPlayerCount`、原生 SETUP 屏障、加载期观察到的人数高水位及完整真实账号实体复核；修正后的08已完成上述production自动入口和双人实机验收。

候选07的工坊提交返回 `3404 / EResult=2`，没有成功回执。其pending已在新鲜官方查询、下载回调及原05完整签名资源核验后，于锁内恢复本地发布状态；没有将失败07记为成功。07的签名资源、工具字节快照和失败记录保持原样，修正候选使用新序号08与独立目录。

## 实际引擎 API 验证的范围

2026-10-27 12:02—12:07 UTC，root在实际Dota进程29380中验证后正常退出。该进程为 **Tools、离线、1名实际玩家、作弊开启**；这些结果只证明当前引擎的API调用形式和选项传递，不能记作production、普通游廊双人或支付验收通过。

- `PlayerResource:GetPlayerCount()` 实际返回数字 `1`；`GameRules.GetCustomGamePlayerCount` 实际为 `nil`。
- 配置读取是方法 `GameRules:GetGameSessionConfigValue(key, default)`，必须同时传入key和默认值；只传key报“expected 3”（包含self），同名全局函数为 `nil`。
- 启动参数中的 `ws4_native_roster=885195478` 可读回原字符串。完整 `changelevel` 后，`ws4_native_roster=885195478_1014036256` 和探针值 `changelevel_verified` 均被准确读回。
- 换图后实际玩家数仍为 `1`。选项含两个账号值不等于两名玩家已经连接，更不等于两人已经通过网页授权或进入同一局。

## 已验证历史08的明确名单要求

历史已验证版本为 `WS4-NATIVE-CLOUD-02`／`2026102708`，内容摘要为 `55d9e63ea1c95bed2456c739c0cf0e3148030e91a43f3a0d72aeaf64ab540e26`，共6658份文件，180份受保护模块保持原字节。已完成真实签名封包、原条目上传和官方完整下载校验；production自动入口、双人同行、登录和云档读回已实机通过，商城支付仍受加入方二维码问题限制，不能标记通过。

候选的冻结production配置只增加 `native_cloud_roster_required=true`，开发配置不变。该标志为true时，首次缺失／空的名单选项也会阻断倒计时、准入和玩法放行；配置异常、非法标志、非法选项，以及同一地图运行中删除／关闭已观察到的标志均不能降级为单人继续。普通旧helper／开发配置没有该字段或明确为false时，保留原来的准入条件。共同发布检查要求新entry4配置必须明确为production且该标志为true，不能用现金或其他云端开关猜测是否需要名单。

本地检查覆盖丢失选项、慢玩家、逐人认证和档案屏障；真实roster与auto模块在host-only资源下连续12秒保持倒计时关闭。共同production解析器保留原单字段语法，仅增加精确的production＋true双字段形状，拒绝重复、false、动态和未知字段。这些均为本地代码／夹具检查，不能替代原游廊实机验证。旧的08草稿摘要 `ea5f…` 已被上述显式名单版本取代，07失败记录保留。

08真实封包报告为 `output/native_arcade_cloud_20261027/native_cloud_v02_package.json`，总字节数 `3767360950`，索引摘要 `a2d87c0daf0100af0fecce2b9056a20041ce84a38b53af62ae00f7a9bca31e91`。`native_cloud_v02_upload.log` 实际退出码为0，最终返回 `SUBMITTED_UNLISTED_PENDING_DOWNLOAD_AND_NATIVE_TEST`、`uploaded=true`、无需补签法律协议。

`native_cloud_v02_official_download.log` 实际退出码为0；2026-10-27 13:12:26 UTC的新鲜官方回调 `3406 / result=1` 对应manifest `976725920376391555`。下载后的6658份签名资源、180份受保护模块、5个VPK、14份受审可信文件和签名校验均通过。完整证据为 `output/native_arcade_cloud_20261027/download_evidence_v02/20261027T131226Z_47475f709b284ebfa099237868d7e53a/verification.json`。下载证据本身只证明安装版本正确；原生自动换图、双人登录及云档读回的独立实机证据见本文开头。

历史08版本自动入口和双人登录／云档读回状态为 `PASS`，不自动转移为09实机结果。08当时未通过加入方扫码验收，后续09已单独完成手机扫码及商品、金额核对；实际支付与购买到账仍未验收，不以已显示商城或二维码代替支付成功。本地代码检查记录仍为 `native_cloud_v02_plan.json` 与 `native_cloud_v02_required_flag_tests.json`。

## 开局前认证的边界

网页授权可以放在加载／入口阶段，完成后才允许模式选择、读档和购买。它仍需安全地把本局逐人授权结果传回真正对局。原生游廊“开始”按钮以前的 Steam 界面不能由地图脚本直接接管，需要外部大厅或启动器。

目前杭州后端的 Steam 官方验证出站仍使用已授权的临时 TLS 中转，测试时本机需保持在线；这不是游戏数据传输代理。正式部署应独立解决稳定出站，不能因健康接口 `200` 就宣称已摆脱该依赖。本记录未核验支付订单或到账。

## 后续验收要求

1. 加入方手机扫码、商品及金额核对已通过；继续覆盖其他分辨率和界面缩放，必要时补充实际像素几何检查。
2. 单独验证实际支付、云端到账、权益刷新与重启读回；不能从HTTP、登录或档案版本递增推断付款完成。
3. 继续验证断线重连、后加入和不同网络。原 GC 房间对象销毁已知，现有双人同行结果不能代替这些场景。

## 独立诊断模块

新增的 `native_transport_probe.js`、`native_transport_probe.lua` 和 `native_transport_client_probe.lua` 提供有界、匿名的健康请求和私有事件回显。目前尚未接入任何入口或 XML，加载模块本身不发送网络请求。它们不具有登录、读档、修改余额、确认订单或发放奖励的权限。

默认不读取或调用第三方 `yhttp` 嵌套工厂；显式诊断可观察 `yhttp.CreateHTTPRequestScriptVM` 的表形态。不能仅凭存在同名符号就认定原生 HTTP 已恢复，也不加载第三方 DLL。

Valve 官方问题库存在[其他作者的 HTTP 失效报告](https://github.com/ValveSoftware/Dota2-Gameplay/issues/35497)，其中的白名单说法尚未获得官方确认。本项目以上述同包实测为依据，不将社区推测当作平台政策。
