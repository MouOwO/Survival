# 普通游廊授权请求创建失败与中转恢复（2026-11-18）

用户截图显示 `WS4-WEB-04 / start / create / 0`，没有短码。实际源码 `systems/player_web_auth.lua` 中这是 `pcall(CreateHTTPRequestScriptVM,...)` 抛错或返回空请求对象，发生在设置请求和 Send 之前；不能把 0 当作后台 HTTP 状态，也不能把后续 Steam 验签通路修好当作已解决该引擎错误。

## 本轮核实与操作

- 本机是普通 Steam 启动的 Dota，无 Tools、无诊断控制台端口；未用 Tools 专用界面脚本操作该普通进程，没有关闭或重载用户房间。
- 实际 Workshop ACF 的 installed/latest manifest 均为 `5596135512120850642`，与已官方下载完整验证的 2026111803 基线一致。无需等待本次介绍更新或包继续下载，未清订阅、缓存或改写 ACF。
- 固定中转原进程回执 stale，云端 18768 监听缺失；web health 正常，但 Steam 传输和官方无效断言拒绝均失败。通过已有 `repair_steam_login.py --repair` 恢复一次，结果 `RELAY_RESTORED`；监听、web health、官方 Steam TLS 和无效断言拒绝均通过。
- 对现役授权 SQLite 只做一次 readonly 聚合：8 条挑战记录，最近创建距采样约 436032 秒，最近 10 分钟创建数为 0。未读取账号、短码、令牌或正文。该证据支持截图错误在游戏发出请求前，不证明当前房间引擎上下文已经恢复。
- 已请用户刷新授权状态。若仍为 create/0，应先退出未开局房间，从游廊重新创建；仍失败时需对该普通启动路径采集引擎诊断。历史有 GC 房间 HTTP 工厂不可用、完整 addon 上下文换图后恢复的实际证据，但不把历史恢复自动算成本轮成功。

用户本轮新短码、网页登录、读档和成功进入游戏均尚未确认。后台代码、认证规则、测试名单、档案与订单保持；没有重新打包、上传或触发真实交易。

树外脱敏证据：`D:/Survival_本地工具/runs/login_create_failure_20261118/{relay_restored.json,auth_start_counts.json}`。本轮没有修改运行源码或既有修复工具，不需要为此重发游廊。旧 15 项工作区改动保持，双仓先按 stash → pull → pop 同步，只提交故障记录。
