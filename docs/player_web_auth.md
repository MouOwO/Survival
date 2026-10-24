# 四账号网页授权测试

本轮参考 Tower Feast 的“网页确认 Steam 身份，再返回游戏继续”的体验，自行实现网页登录和游戏认证，不复用对方受保护的服务端业务。

玩家在游戏加载界面点击“打开网页登录”，核对网页与游戏中的短码，在 Steam 官方页面登录当前游玩的同一账号，再点击“确认授权本次对局”。返回游戏后自动继续原入场认证、模式选择和读档。游戏里不要求 Steam 密码，也不要求长期游戏密码。

## 当前范围

- 继续使用现有四个测试账号和 `goufayu_ws4` 独立测试库，原存档和支付服务不迁移。
- 独立入口为 `https://pay.xiaofengnet.com/ws4-web`，只读健康检查为 `/health`。
- 当前仅支持本人、本局的短期授权；重新开局需要确认新的短码。新批准会撤销该账号旧授权，服务器重启保留授权和防重放状态。
- 本地进度只写独立测试存档，不作为可信战果。真实支付、排行榜和通用发货接口保持关闭。
- 授权不改变游戏的联机承载方式；公网托管与多人性能仍需单独验证。

## 源码与运行边界

开发配置 `scripts/vscripts/config/player_web_auth.lua` 默认关闭。本次单独签名候选才启用，不改变开发目录原有 Workshop 凭据连接方式。游戏凭据只留在服务器 Lua，客户端只收到本人的公开短码和固定 HTTPS 授权链接。

`server/player_web_auth` 是标准库独立服务，监听 `127.0.0.1:18767`。Nginx 只增加 `/ws4-web/`，原 `/ws4/` 和支付路由保留。该服务先确认 Steam 身份和明确授权，再将限定账号、对局及路由的请求转发给原独立测试 API；内部服务端密钥不进入游戏包。

服务端源码与测试说明见 `server/player_web_auth/README.txt`。部署工具为 `tools/workshop_test/deploy_web_auth.py`，提供 `audit → prepare → activate → verify`，以及失败回滚。它核对原服务 PID、发布指针和文件摘要，并保留私有回滚记录。对同一已回滚候选重试时，仍先检查环境、端口、Nginx 和凭据状态。

## 冻结候选

`tools/workshop_test/build_web_auth_candidate.py` 默认只读验证。显式构建以已签名 `20261023_ws4_auth_v03` 为基准，只允许七个登录相关路径变化，新增四份运行文件，保留其余资源及180份受保护模块，重新生成完整清单和签名。工坊上传和真实 Steam 登录不由构建成功替代。

补丁比较基线固定为 `641e836c1a2b82f03f300e53dd567bd6a06ede81`，与当前 HEAD 分开记录，因此提交代码后仍能复现同一补丁。构建期间仍核对 HEAD 与输入源码未变化。

Tower Feast 的本地只读核对记录为 `publishing/workshop/tower_feast_login_review_20261024.json`；检查工具只读取包目录、校验选定资源 CRC 并检查可读界面，不解密或执行第三方模块。

## 验证要求

自动化验证覆盖官方回调验签、防重放、明确网页批准、跨账号与跨局拒绝、会话过期、限流、受限代理、游戏事件身份和加载门禁。原生验证还需确认：普通玩家看到授权卡、真实 Steam 登录成功、网页批准后游戏完成认证和读档、退出重开仍读取同一测试档案。未完成的原生步骤必须按实际状态记录。

2026-10-24 已部署并验证独立服务，核对原服务未变化、正式数据复制为零。原生测试副本 `svt_w24` 的 v02 已完成真实 Steam 登录、玩家网页批准、云端认证、模式选择及读档，并进入地图。游戏日志确认 `admission_complete=true`、`phase=ready`，HTTP 档案发布及在线进度写入有成功回执，版本从21推进到22；云端批准会话与已验证浏览器各1份。v01 的可选 `PanelDeleted` 事件导致界面脚本中断，v02 已兼容该原生差异。当前未将这份网页登录候选上传到原工坊条目；普通工坊启动、重开同档和多人仍需分别验收。

## Steam 回调出站排查

本轮真实登录返回后出现 `steam_state_invalid`。服务器记录显示首次回调已经匹配浏览器和有效 state，但在后续验证阶段未完成；再次打开已消费的回调网址会掩盖首因。现在只持久保存固定的失败枚举，同一有效浏览器刷新时返回首因而不重复验签。旧的已消费流程不能重放，需要从游戏重新打开公开授权页。

对杭州 ECS 的无用户数据探测发现系统域名解析异常。使用经 HTTPS DNS 查询得到的两个外部地址、保留 Steam 官方 Host/SNI 后，TCP 可达但 TLS 握手仍被重置；不能据此确定具体重置来源。本机向同一官方接口发送无效测试请求可正常收到 OpenID `is_valid:false`。验签网络失败现在独立显示 `steam_verification_unavailable`，不会认证玩家。

临时测试传输默认关闭，唯一开关为 `PLAYER_WEB_AUTH_STEAM_TLS_RELAY=0|1`。启用时只将 Steam 验签的 TCP 连接送至 ECS `127.0.0.1:18768`，由固定目的的 SSH 反向转发经过本机连接到 `steamcommunity.com:443`。TLS 仍在 ECS 校验官方证书、主机名和 SNI；不允许任意代理地址、跳转或关闭证书验证。测试期间本机和其现有可用网络必须在线，这不是可独立运行的上线方案。

`tools/workshop_test/steam_tls_relay.py` 默认仅显示计划；显式 `--start` 启动隐藏的固定目的 SSH，`--stop` 仅停止身份与创建时间均匹配的本工具进程。PID 记录保存在忽略的 `output/`。正式部署应使用能访问官方 Steam OpenID 的稳定云端出站节点。

服务配置顺序为 `rollback → prepare → configure-transport --steam-tls-relay 0|1 → activate → verify`。配置步骤只允许在成功回滚、服务停止、输入摘要与权限均符合预期时修改这一项，并私有备份原环境与计划。其他密钥、原服务和测试存档继续保留。启用前必须使用无用户数据的真实 TLS 请求验证通路，构建或单元测试不替代该验证。

本次临时传输已经实测：从 ECS 经固定回环端口调用生产 Steam 验签函数，对无效测试断言得到官方 HTTP 200、正确 namespace 和 `is_valid:false`；仅回环监听已经核对。随后显式启用并恢复服务，公网健康和原五项服务基线通过，真实玩家 Steam 回调成功。保持本机在线的限制仍然适用。

## 原生浏览器表单回归

真实授权表单曾因全局 `Referrer-Policy: no-referrer` 使浏览器提交 `Origin:null` 而被拒绝。修复仅将成功的授权 HTML 响应改为 `same-origin`；回调、重定向和 JSON 继续 `no-referrer`，Origin 精确检查和 CSRF 校验不变。有效会话与正确 CSRF 下的 `Origin:null` 仍被拒绝。

`node tools/workshop_test/test_web_auth_browser.cjs` 使用隔离 Chrome profile 和回环测试页面，以原生 form 导航验证：旧策略产生空来源，新策略保留同源 Origin，跨源导航不发送 Referer。该测试已通过，不使用真实 Steam 登录。行为依据见 [WHATWG Fetch](https://fetch.spec.whatwg.org/#append-a-request-origin-header) 和 [W3C Referrer Policy](https://www.w3.org/TR/referrer-policy/#referrer-policy-same-origin)。
