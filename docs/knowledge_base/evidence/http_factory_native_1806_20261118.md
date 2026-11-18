# 1806 HTTP 工厂兼容、普通客户端诊断及崩溃保留

## 交付与当前结论

2026111806 已同步原游廊 `3824360109`，Steam manifest
`6295798134948076528`。7063 项资源、187 个保护模块及 5 个安装文件官方完整下载
一致，完整待发/阻断为 0。上传不是登录恢复：实际普通客户端仍显示
`WS4-WEB-04 / start / create / 0 / F:nn / H:l`。

`F:nn` 表示两个官方工厂均返回空值；`H:l` 表示实际是玩家本地主机。
错误发生在请求对象创建阶段，尚未 Send，0 不是后台 HTTP 状态码。
新后台与 Steam 验签中转另行检查为 READY，不能把这些健康检查当成游戏登录成功。
目前未证实压测、欠费、域名解析、Valve 白名单或特定引擎限制是根因。

## 本次修改与验证

新增共享 `core/http_request_factory.lua`，先用 CreateHTTPRequestScriptVM；仅当没有
得到 table/userdata 请求对象时尝试 CreateHTTPRequest。原生调用置于非尾调用 Lua
保护帧，兼容继承的 VM 全局。四个调用方为网页登录、档案 HTTP provider、托管大厅和
支付；原 URL、请求正文、授权、超时、串号、回调及业务 Send 保持。Send 失败、超时或
未知交易结果不重发，不降级身份认证。

只在当前玩家失败提示中加入有界工厂与主机枚举，不发送 URL、账号、短码、令牌或正文；
成功/等待路径不携带该诊断。双仓 Panorama 源一致，非法枚举和尾部换行被拒绝。

实际 Lua 5.1 工厂 43 项及网页登录、UI、去重 45 项、托管 18 项、在线支付授权、支付、
档案时序共八组检查通过；实际编译 DATA 和实际签名 Lua 再验通过。检查没有真实交易。
这些是隔离与实际产物回归，不是原生 HTTP 成功或 FPS 结论。

成本为初始化 0 次原生创建、0 计时器；正常请求 1 次工厂调用，失败最多 2 次，始终由
原调用方 Send 一次。无集合扫描、额外网络重试或后台轮询。稳定去重 1000 次不重复发包。

## 已完成的原生对照

- 默认入口普通 Steam 客户端：F:nn / H:l。
- Steam 与 Dota 正常退出后重新启动，Steam 客户端组件实际更新；同版本仍为 F:nn / H:l。
- 额外显式 -steam 仍失败；后来核实普通 Steam 启动本来就自动注入此参数，故不把此项当成独立功能对照。
- 原生游廊页面显示“将使用玩家电脑作为主机”；创建房间明确选择新加坡，实际仍是本地房间，进入后 F:nn / H:l。没有取得 H:d 的独立服务器样本。
- 直接 template_map 的启动曾停在准备队伍，没有登录请求，不能算作 HTTP 成功。后续日志同时出现 template_map 和 ws4_entry，不能宣称已完成无换图对照。未伪造 roster 或绕过签名生产门禁。

早先无回显的键盘操作不能当成命令已执行。随后从原生主菜单打开控制台并点击真实输入框，
固定命令已有可见回显。随后另启干净默认入口客户端 PID 35652、创建 FILETIME
134394741185082800，在隐藏但已取得焦点的控制台成功启动匿名探针。正式地图 template_map、
原生 state=10/ingame、非 Tools、本地主机，0/5/30 秒三轮各调用两套官方 GET 工厂；
6 次均 factory=ok、request=nil、send=not_attempted。没有网络 Send，不是后台返回错误。
其 HTTP 方法/地址范围仅覆盖当前登录 POST 与固定匿名健康 GET，不泛化至所有网络 API。
采样后明确设置开关 0，实际 stop/boundary 事件确认探针结束；临时 F10 已 unbind。
新进程采样结束仍在，未复现上一进程的崩溃。控制台已关闭，没有继续多次换图。

## 19:11:52 自行退出

用户明确确认本次为游戏自行退出。两份官方转储的实际 PID 都是 19964，与启动回执
的创建时间一致；原件保留，树外副本逐字节摘要一致。异常码 `0xe24c4a04`，抛出地址
KERNELBASE.dll+0x43fa9；原始栈扫描含 vscript.dll+0x6ead8，但扫描不是符号展开调用栈。

LuaJIT 上游 [异常编码源码](https://github.com/LuaJIT/LuaJIT/blob/v2.1/src/lj_err.c)
将 0xe24c4a00 与错误码合并，[lua.h](https://github.com/LuaJIT/LuaJIT/blob/v2.1/src/lua.h)
定义 4 为 LUA_ERRMEM。这支持内存错误方向的推断，尚未证实 Dota 定制实现、具体分配
失败或与原 create/0 同源，不能直接归咎服务器内存不足。没有重复触发多次换图路径。

证据根为 `D:/Survival_本地工具/runs/login_create_failure_20261118`：
`http_factory_compatibility_checks_receipt.json`、`compiled_auth_ui_1806_verification_receipt.json`、
`signed_http_factory_1806_verification_receipt.json`、`native1806_crash_preservation_receipt.json`、
`native1806_health_probe_receipt.json`。
后者登记号 `3590eefcb8ce2877d994b1cfbf41cdf6e19ad69a8337fb21a1822f26abab2959`。
原生截图和日志均在同主题树外目录，转储不上传、不进 Git。

## 后台与保留

本次没有部署后台；全部正式业务在 47.111.16.128，验签中转仍依赖作者电脑与可用网络。
历史 8.3GB 压测归档已完成加密异地传输及解密 SHA 核验，见迁移记录；自动异地备份仍未配置。
原有 15 项改动摘要保持，没有真人券消耗、兑换、支付或清档。本次没有本机候选暂装，
没有待恢复 keeper。新的普通客户端留在原授权失败界面，探针已关闭。
下一步应调查普通游廊本地托管为何不给 HTTP 请求对象，及如何获得真实独立服务器对照；
现有新加坡区域选择不足以提供该对照。没有修改已批准的封闭可见性或向外部自动发报告。
