# 04｜联网、身份与官方平台边界

本模块以 2026-10-24 的 WS4-ENTRY-05 为事实截点。玩家已从正常 Steam 启动的原游廊条目进入 N5；只读云端汇总确认读档、在线检查点及测试档 revision 43。当前是四账号、单人云存档测试，尚未完成公开上线、多人托管或降低延迟。最终证据以 `publishing/workshop/workshop_entry_release_20261024.json` 为准。

## 1. 先分清五件事

| 层次 | 本项目的含义 | 不能据此推导 |
| --- | --- | --- |
| Workshop | Steam 分发地图和运行资源、提供原游廊入口 | 已获得 Valve 专用服或可靠多人承载 |
| Tools | 编辑器／开发运行环境，可使用显式离线调试 | 普通玩家从游廊启动也完全相同 |
| 本机游戏主机 | 玩家电脑运行游戏逻辑，其他人可经 LAN／VPN 连接 | 本地战果不能篡改、云端可直接相信 |
| 自有云业务 | 玩家认证、存档、目录、规则与数据隔离 | 云业务服务器也承载 Dota 帧同步 |
| 多人 hosting | 房间分配、游戏进程、网络质量、断线重连和运维 | 输入账号密码或完成 Steam 登录便已解决 |

历史双机 VPN 测试确实进入同局；主机后台运行出现接收队列溢出，恢复前台后连接稳定，但卡顿严重。这证明一条本机联机路径可行，不能作为多人上线方案。VG／其他平台仍需作者接入和实测，当前没有已完成租服的结论。网页登录只替换玩家身份通道，不提供游戏承载。

## 2. 两类错误应在不同层排查

`Invalid_NotOnDedicatedServer` 来自原 Valve dedicated key 路径：当前上下文拿不到有效专用服凭据。增加数据库、填写 SteamID、把条目改成不公开列出，都不会生成这一凭据。旧流程见 `docs/workshop_isolated_test.md`；当前网页登录候选不依赖该 key。它不是“必须购买任意一台云服务器”的证明。

玩家实际看到的 `WS4-WEB-04/start/create/0` 则表示请求创建阶段失败：API 名存在，但调用失败或没有返回请求对象；尚未进入设置请求体与发送阶段。这里的 0 不是后台 HTTP 状态，更新云 API 或刷新网页不能直接修复。诊断只允许固定版本、`start/poll`、`API/create/send/http/json/fields/timeout` 和 0–599 数字；禁止正文、账号、对局、设备码、Bearer、Cookie 和原生异常进入客户端或日志。`Send()` 明确 false 按失败处理，nil 兼容原生 void；超时后的旧回调失效，同错日志限频。实现见 `scripts/vscripts/systems/player_web_auth.lua`。

v04 已每5秒跨游戏阶段重试。普通无 Tools 的独立副本及直接启动原 Workshop ID，都真实完成过批准、读档和开局，因此不能说“所有非 Tools 禁止 HTTP”。[Steamworks HTTP 文档](https://partner.steamgames.com/doc/api/ISteamHTTP#CreateHTTPRequest)描述创建、配置、发送，并未规定 Dota 的选英雄或正式战斗阶段；原生 SDK 初始化和回调要求也不能直接映射成游戏阶段。[Valve issue 35497](https://github.com/ValveSoftware/Dota2-Gameplay/issues/35497)是玩家报告，作者将白名单称为未经确认的传闻，检索时未发现 Valve 的正式规则或申请入口。内部原因仍未知，不能把“必须 GAME_IN_PROGRESS”或“已被白名单限制”写成官方结论。

## 3. v05 用自己的轻量入口恢复可用启动上下文

原条目 `3824360109` 保持不公开列出，默认地图变为自制 `ws4_entry`，入口容量1人。客户端仅在该地图执行固定标准命令：

```text
dota_launch_custom_game 3824360109 template_map
```

真实地图仍属于同一条目，并保留自己的认证、加载和玩法门禁。玩家随后按原生界面开始、核对短码、网页批准，再选择模式和难度。`template_map` 的声明容量4不表示当前已提供四人托管；当前发布模式明确为单人云存档。

原生细节不可省略：客户端 `GetMapName()` 可能返回 `ws4_entry` 或 `maps/ws4_entry.vpk`，仅接受这两个精确值；命令目标固定，不读取玩家提供的目标。VM 内先设置一次性标记再发命令，避免重入循环。主入口的 `Precache/Activate` 必须在 `addon_game_mode.lua` 根作用域定义，不能假设 require 模块内部回调会成为引擎入口；模块只提供 `activate()`。轻量分支尽早返回，不初始化云业务与完整玩法。对应文件为主入口、`addon_game_mode_client.lua` 和 `systems/workshop_entry.lua`。

Tower Feast 提供了本机运行、外部授权站与游戏密码 UI 的体验参考，其后台身份协议未验证；Steam 官方 OpenID 是本项目独立实现，不能归因于其受保护核心。梦之岛可读客户端提供了同条目重开真实地图的路由参考。只读取明确选定的 VPK 资源并校验 CRC，不解密、执行或复制其受保护认证和业务核心。自己的入口地图来自本项目骨架。证据见 `tower_feast_login_review_20261024.json`、`dream_island_entry_review_20261024.json`（均在 `publishing/workshop/`）。

## 4. 玩家网页授权的可复用协议

服务端 Lua 用引擎确认的账号和本局标识调用 `POST /v1/player-auth/start`；服务返回私有 device_code、公开短码、固定 HTTPS 授权地址与截止时间。Lua 调用 `/poll` 等待批准；批准令牌严格绑定同一账号、同一局，过期或撤销后拒绝使用。短码待确认10分钟，本局令牌4小时，新批准撤销该账号旧授权；批准后的轮询可安全重试，不因丢包重复授权。

Panorama 只接收自己的公开短码、固定地址和安全状态；私有设备码、本局令牌留在服务端 Lua，内部业务 Bearer 只在云服务私有环境中。URL、网络表、UI、日志和异常都不携带这些凭据。四账号名单限制访问范围，但名单本身不能替代身份验证。

网页把玩家送到 Steam 官方 OpenID 页面，不收集 Steam 密码。校验包含绑定浏览器的 state、精确 return_to、身份与 claimed_id 一致、固定 endpoint、必签字段、nonce 新鲜度和去重，最后向固定官方 HTTPS 地址执行 `check_authentication`，禁跳转并限制响应大小。随后还需精确 Origin 与 CSRF 保护的“批准本次对局”。账号不一致不得批准。

浏览器身份默认4小时；明确勾选后可记住30天，减少重复 Steam 登录，但每局仍要核对短码并确认。浏览器身份与本局4小时令牌分别计时；退出网页登录撤销该浏览器，不删除云档。Cookie 为 Secure、HttpOnly、SameSite=Lax，限定路径，服务端只保存摘要。实现与协议见 `server/player_web_auth/README.txt`、`service.py`、`http_api.py`。

两次真实浏览器问题留下了必要回归：首次回调失败后，固定错误枚举持久保存，原浏览器刷新已消费 state 只显示首因，不重复验签或授权；错误 Cookie／过期仍拒绝。成功回调刷新明确提示已使用。授权 HTML 的全局 `no-referrer` 曾导致原生 form POST 出现 `Origin:null`；只把成功 GET `/authorize` HTML 改为 `same-origin`，其他响应仍 no-referrer，Origin:null 即使有正确 CSRF 也拒绝。依据为 [Fetch](https://fetch.spec.whatwg.org/#append-a-request-origin-header) 和 [Referrer Policy](https://www.w3.org/TR/referrer-policy/#referrer-policy-same-origin)，原生浏览器回归为 `tools/workshop_test/test_web_auth_browser.cjs`。

## 5. 云服务职责、依赖与维护入口

| 组件 | 地址／服务 | 职责 |
| --- | --- | --- |
| 公共授权入口 | `https://pay.xiaofengnet.com/ws4-web` | Nginx 剥前缀转发，外部只访问 HTTPS |
| 网页 sidecar | `127.0.0.1:18767`，`goufayu-ws4-web.service` | OpenID、浏览器、短期授权、受限代理；私有 SQLite 状态 |
| WS4 业务 API | `127.0.0.1:18765`，`goufayu-ws4.service` | 原有业务校验与存档；旧外部入口 `/ws4` |
| 独立数据库 | `127.0.0.1:15432`，`goufayu-ws4-db.service` | `goufayu_ws4`，不复制原玩家、订单或余额 |
| 临时验签 TCP 中转 | ECS `127.0.0.1:18768` | 只连接官方 Steam 443；不承载游戏联机 |

杭州 ECS 到官方 Steam 的 TLS 曾被重置，来源未确定。临时 `PLAYER_WEB_AUTH_STEAM_TLS_RELAY=1` 通过固定 SSH 反向 TCP 通路使用作者电脑的现有可用网络；TLS 仍由 ECS 校验官方证书、主机名和 SNI，不关闭验证、不允许任意代理。默认0；当前测试已启用，作者电脑与网络必须在线。公开上线前需替换为稳定云端出站，不能把此中转称为生产可用性方案。

最小只读检查：本机 `Invoke-RestMethod https://pay.xiaofengnet.com/ws4-web/health`；云端 `systemctl is-active goufayu-ws4-web.service goufayu-ws4.service goufayu-ws4-db.service`；运维工具 `deploy_web_auth.py audit` 与 `verify`。Python 路径按本机已配置解释器选择，不直接使用 Windows 商店 shim。不要打印私有环境、pin 或完整回调 URL；完整部署顺序见下一模块与原工具帮助。

用户鉴权可支持本人读档、目录、按后端规则领取礼品或创建订单的身份基础；本测试只开放已列明读接口和受控测试进度。`ISOLATED_LOCAL_PROGRESS=1` 仅增加 archive/command、archive/endless-batch、online-time/checkpoint，通用 rewards/grant、真实支付和可信排行保持关闭。Steam 登录不证明战果，本地主机仍可改进程；联网禁作弊只是项目规则，不能承诺可信托管。正式付费、排名或高价值奖励需另行设计可信来源与审计。
