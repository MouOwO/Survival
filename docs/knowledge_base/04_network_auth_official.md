# 04｜联网、Steam 身份与官方平台交互

事实截点：2026-10-28。本文接续 10/24 知识包，并纠正当时“只验证单人云档”的状态。原工坊条目为 `3824360109`，不公开列出，仅四个获准测试账号；当前已发布 `2026102802 / WS4-MAP-RESOURCES-01`。**2708 已通过原游廊双人自动入口、网页登录与逐人云档读回；2709 加入方手机扫码通过；2802 只完成作者账号完整下载与主机载图，未完成新版双人布局回归。** 收款与交付的证据单独见 [05](05_payments_commerce_delivery.md)，精确发行身份见 [06](06_build_release_ops.md)。

## 证据怎样使用

| 证据 | 能证明什么 | 不能替代什么 |
| --- | --- | --- |
| 源码与离线 mock | 分支、契约、校验和失败处理 | Steam 在线登录、两机同行、真实付款 |
| Valve 编译／原生资源读取 | 指定资源可以编译／被引擎读取 | 地图玩法、网络和身份正确 |
| 签名候选与官方完整下载 | 指定账号装到了指定资源集合 | 其他账号有权获得同版、两人能玩 |
| 原游廊实机日志和画面 | 对应版本、对应玩家、对应启动上下文的行为 | 新版或未测的断线、四人、长局场景 |
| 用户明确确认 | 用户实际操作到的结果 | 未记录的订单、金额、HTTP 次数与数据库变化 |

历史记录保留其日期和 scope；不把一次成功自动继承为后续版本的实机通过。

## 联网系统必须分层

Workshop 负责分发地图与资源；Dota 游戏进程负责战斗与同步；自有云业务负责认证、档案、商品、账本和受控发放。网站可以承载后两者，不能直接执行 Dota 帧同步或替代真正游戏进程。房主、游戏服务器、服务端 Lua 所在主机和云 API 是不同概念，不能仅凭 Lobby Owner 或 `127.0.0.1` 推定位置。

历史 Radmin 双机确实能进入同局，主机接收队列溢出曾导致进入即断开，主机恢复前台后用户确认稳定进入两人界面并能玩。但卡顿严重，当前主线已转为原生游廊多人。VPN 开着不等于加入同一私网；资源校验失败也不属于 VPN 故障。保留旧路径作维护知识，不要求当前玩家使用旧加入 CMD。

`Invalid_NotOnDedicatedServer` 属于旧 Valve dedicated 凭据路径：当前上下文没有有效凭据。输入 SteamID、增加数据库、把 Private 改为 Unlisted 或租普通业务云主机，都不会生成这个凭据。它不证明所有多人都必须租专服。网页授权是独立的玩家身份通道，不伪造 Valve 专服身份，也不保证本地主机战果可信。

## HTTP 阻塞与已验证的恢复路径

旧 `WS4-WEB-04/start/create/0` 的含义是**请求对象创建失败**，尚未进入 Send；0 不是后端 HTTP 状态。两种 Lua 原生 HTTP 工厂符号存在仍可能返回 nil。真实对照发现：同一签名包，在普通无 Tools、无 `-dev` 的直接启动上下文可返回 HTTP200，在原 GC 游廊房间上下文却不能创建请求。因此不能断言“所有非 Tools 禁止 HTTP”，也不能认定必须等正式战斗或付费才能联网。社区 issue 的白名单说法未经 Valve 正式确认。

Panorama 的旧 `AsyncWebRequest` 不是当前替代通道：本机官方 API 缓存标为 disabled，当前官方二进制有 removed 提示。第三方 `yhttp` 名字存在也不证明可用，不加载第三方 DLL、不借其凭据接入。

10/24 的单人入口采用每个客户端 `dota_launch_custom_game 3824360109 template_map`，只验证过单人。该命令让多客户端各自重开可能生成不同服务器，不能沿用作多人实现。当前 production 入口改成**服务端等待真实完整名单，统一换图**：

```text
changelevel template_map gamemode=15 customgamemode=3824360109 nomapvalidation=1
```

必须保留完整 addon 上下文。裸 `changelevel template_map` 已实测丢失挂载、报找不到地图并断开；不能再建议使用。完整命令中 `gamemode=15` 是引擎自定义游戏模式，其他选项采用本机官方启动格式；它不授予身份、发奖或作弊权限。换图会销毁原 GC 房间对象，不能用旧 Lobby ID 当仍存活的证据。

当前自动入口在 `ws4_entry` 等待原生加载阶段及实际账号名单稳定，以固定地图选项 `ws4_native_roster` 将真实账号32名单传到 `template_map`。名单不是 token，也不能替代网页授权。目标图等待全部名单到齐、正确分队、逐人认证、资源与 UI 就绪，才开放模式；选模式后再等待全部档案载入，才启动玩法。慢玩家导致倒计时取消，而不是静默缩成单人。production 的 `native_cloud_roster_required=true` 缺失、非法或运行中被移除都应拒绝放行。

2708 的真实验收包括：普通 Steam 启动、无 Tools／`-dev`、`sv_cheats=0`；两名原玩家换图后均进入同一目标图、均为 team2、均有原生英雄就绪记录；两个 HTTP 接口各 7 次真实200，覆盖 setup、pregame、ingame；两人的 `http_fishing` 档案独立读回。主机 revision223→230，加入方7→10。用户确认“可以了，登录没问题”。这些次数只属于2708，不能写成2709／2802重新测得。

2709 只改 QR 编译资源，主机观察原房间2/4并进入 N1，用户确认加入方手机扫码商品与金额正确。本轮没有重新采集逐人 HTTP 计数或云档，不虚构这些记录。

## 引擎接口的真实陷阱

- 当前引擎 `GameRules.GetCustomGamePlayerCount` 为 nil；旧候选07错误要求它存在，曾阻断入口。应使用实际存在的 `PlayerResource:GetPlayerCount()`，并结合加载人数高水位、真实账号实体与原生 SETUP 屏障，不能只凭声明槽位。
- `GameRules:GetGameSessionConfigValue(key, default)` 必须带默认值；同名全局函数不存在。把两人的账号写进选项只证明选项传递成功，不证明两名玩家已连接或授权。
- `GetMapName()` 可能给出 `ws4_entry` 或 `maps/ws4_entry.vpk`，入口只接受精确允许形式。固定路由不读玩家提供的目标或命令文本。
- 引擎 `Precache/Activate` 必须在 `addon_game_mode.lua` 根作用域定义；require 内的同名函数不自动成为引擎入口。轻量地图应尽早返回，不启动完整玩法和云业务。
- 初始化日志按 match 分流；主日志与 `native_arcade.<match>.log` 要一起看，不能因分流日志没出现 Steam 初始化就认定未初始化。

## Steam 官方网页登录协议

游戏服务端使用引擎确认的账号与本局标识调用 `POST /v1/player-auth/start`，得到私有 device code、公开短码、固定 HTTPS 地址与截止时间，再用 `/poll` 等待批准。公开短码待确认10分钟；批准后的游戏令牌有效4小时，绑定同账号、同对局；新批准撤销该账号旧授权。批准后轮询可安全重试，不因丢包重复授权。

Panorama 只收到本人的公开短码、固定授权地址和安全状态。私有 device code、本局令牌留在服务端 Lua；内部业务 Bearer 和签名密钥只在私有云环境。网络表、广播、URL、截图、日志及异常中都不能带这些值。四账号名单是访问范围，不是身份凭证。不能让玩家输入 SteamID 就获得读档或发奖权限；游戏和自有网页不收集 Steam 密码。

浏览器跳转 Steam 官方 OpenID。服务校验绑定浏览器的 state、精确 return_to、identity 与 claimed_id、一致的固定 endpoint、必签字段、nonce 时效和去重，再向固定官方 HTTPS 地址执行 `check_authentication`，限制响应大小并禁重定向。随后玩家还需对当前短码做精确 Origin 与 CSRF 保护的“确认授权本次对局”。同局账号不一致必须拒绝。

浏览器身份默认4小时；用户明确勾选后记住30天，免重复 Steam 登录，**每局仍要确认新短码**。浏览器期限和本局令牌分别计时。退出网页登录只撤销该浏览器及其流程，不删除云档，也不自动撤销已批准游戏令牌的原有效期；不要误写成退出即清空全部档案／游戏授权。Cookie 为 Secure、HttpOnly、SameSite=Lax、限定路径，数据库只保存摘要。

两个历史问题必须保留回归：已消费 state 不能反复验签；首次失败保存固定安全枚举，原浏览器刷新只显示首因。成功回调刷新提示已使用，不重放授权。授权 HTML 全局 no-referrer 曾使同源 form POST 带 `Origin:null`；只把成功 GET `/authorize` HTML 调为 same-origin，其他响应仍 no-referrer，null／外域／缺失 Origin 即便有正确 CSRF 也拒绝。

请求诊断只允许固定阶段、API/create/send/http/json/fields/timeout 与状态数字，禁止正文、账号、对局、授权码、Cookie 和原生异常。`Send()==false` 是失败，nil 兼容原生 void；超时后的旧 generation 回调失效，同错限频。

## 云服务职责与尚存依赖

| 组件 | 已记录位置 | 职责 |
| --- | --- | --- |
| HTTPS 授权入口 | `https://pay.xiaofengnet.com/ws4-web` | Nginx 剥前缀转发，不以不可信 Host/forwarded headers 决定授权地址 |
| 网页 sidecar | loopback18767，`goufayu-ws4-web.service` | OpenID、浏览器、短期批准、限定业务／支付代理 |
| WS4 业务 API | loopback18765，`goufayu-ws4.service` | 独立测试档案与业务校验 |
| WS4 数据库 | loopback15432，`goufayu-ws4-db.service` | `goufayu_ws4`，与原玩家、余额和订单隔离 |
| WS4 支付 | loopback18769，公网前缀 `/ws4-payments` | 单独支付能力和回调；参见05 |
| 临时 Steam TLS 通路 | ECS loopback18768 | 仅官方 Steam443验签出站，不传游戏同步 |

杭州 ECS 对 Steam TLS 曾被重置，根因未定位。经用户批准的临时固定 TCP 中转依赖作者电脑现有可用网络；TLS 仍由 ECS 检查官方证书、主机名和 SNI，不关闭校验。该通路不是游戏联机代理，也不是生产高可用方案。公开上线前必须解决稳定云出站，不能从健康接口200推断该依赖已消失。

`ISOLATED_LOCAL_PROGRESS=1` 只增加 archive/command、archive/endless-batch、online-time/checkpoint 三类独立测试变更；不会自动开放通用 rewards/grant、支付或可信排行。支付需要另一组显式权限和独立凭据。Steam 身份只证明谁在操作，不证明本机战斗结果未被篡改。

## 独立大厅、VG 与参考游戏的复用边界

DoDoTD Defence《保卫小塔》`2637453327` 可读客户端展示单人 launch→后端房间／准备→服务器分配→连接的分层思路。Survival 已独立实现 `ws4_lobby` 地图、界面、`server/lobby_backend`、租约、60秒账号绑定单次票据、固定地址/build校验和重连适配；当前默认关闭、没有生产 ready worker、没有部署为当前工坊主线。

本机 dedicated 探针能启动核心 dota 地图并监听 UDP，但自定义 Survival 挂载失败，Steam服务器连接未完成，也没有两机进同一独立服的验收。后端建房或端口监听不等于 Dota worker就绪；测试夹具的 ready 回调不得用于部署。真实 worker还须按引擎 Steam 身份核对该房间冻结名单，不能仅检查全局四账号白名单。

VG／散夜尚无已验收的作者接入、租服或部署接口。啊哈利姆、Tower Feast、梦之岛及保卫小塔只提供已观察到的路由／体验参考；第三方受保护核心和后台未解密、未执行、未复制，未使用其凭据或请求其业务接口。不能把参考包里的字符串当本项目可用的托管协议。网站本身不能解决游戏服调度。

## 维护入口与下一轮验收

主要源码：`scripts/vscripts/systems/player_web_auth.lua`、`systems/workshop_entry.lua`、`systems/native_setup_auto_start.lua`、`server/player_web_auth/{service.py,http_api.py}`、`server/lobby_backend/`。领域记录：原生云链路（项目来源：`docs/native_arcade_cloud_20261027.md`）、授权说明（项目来源：`docs/player_web_auth.md`）、独立大厅（项目来源：`docs/hosted_lobby_20261025.md`）。旧说明可能仍保留当时单人／现金关闭的历史段落，当前状态优先看本文与最新 publishing JSON。

后续必须单独验证：第二台获取2802→两人同行和布局→错账号／过期／撤销／旧回包→断线重连及后加入→四人跨网长局→稳定云端 Steam 出站。登录、云档、支付分别验收，不以一个总 PASS 掩盖剩余工作。
