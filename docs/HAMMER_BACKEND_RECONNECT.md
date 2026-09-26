# 2026-09-26：Hammer 重开后认证助手无法连接

现象：主机强退后从 Hammer 重开，加载界面提示后端未就绪。`setup_hammer_backend.ps1 -Action Start` 返回 `HAMMER_BACKEND_START_REQUESTED`，但助手持续显示 `waiting_for_workshop`，偶尔显示 `waiting_for_map`。

此次实际排查发现两个条件叠加：LAN 启动流程曾禁用助手；恢复助手之后，Dota 的 29000 控制台入口已有 VConsole2 和 dota2-mcp relay 连接，新的直连被拒绝。游戏实际已经运行 `template_map`，通过现有 relay 可以正常执行只读 Lua。助手旧实现与认证预检均要求另外直连 29000，因此新进程的后端认证没有执行。这不是云端拒绝旧账号会话，也不是缺少退出事件导致的认证错误。

修复：

- `tools/map_c6/console.cjs` 自动识别当前用户已经运行的 relay，使用其已认证的控制接口共享游戏连接；没有 relay 时继续直连。显式指定其他端口时保持原目标。
- `console-relay.cjs` 只读取现有 relay 状态，不启动、关闭或改配 VConsole/MCP。每次连接重新发现，不保存旧游戏连接。发出本次随机 echo 标记后才收集结果，恢复 relay v1 去掉的消息换行，避免旧消息或粘连文本被当成本次认证回执。
- relay 握手或发送命令前失败可回退直连；真实命令已经发送后失败不自动重放，避免重复执行。
- 认证预检去掉单独的 29000 TCP 探测，继续要求当前正式 Tools 地图的唯一 Lua 回执以及现有隧道健康检查。令牌仍通过原有受限临时 KV 传入，不进入命令行或日志。
- 公共测试工具包白名单加入新适配器。

随后检测到新的 Dota 进程，追踪到本机 VConsole 还保存了两个自动连接设备：
`Localhost`（直连 29000）和 `Localhost:29001`（relay）。两个设备均为
`connectAtStartup=true`，重开时会再次抢占入口，relay 日志反复出现无响应重连。
已正常关闭控制台、将直连设备自动连接改为 `false`、保留 relay 设备的 `true`，
并恢复控制台窗口。仅该项设置的备份在
`output/hammer_reconnect_20260926/vconsole_direct_connection.before.json`。
这是当前 Windows 用户的控制台设置，不是云端后端或游戏脚本。

验证：12 项 Node 控制台/relay 测试、17 项认证测试、23 项助手测试、10 项 LAN 探针测试、5 项真实 PowerShell 隔离启动测试，共 67 项通过。

实机恢复：保持当时的 Dota 进程和地图，认证探针返回 `tools_server_and_tunnel_ready`，助手随后返回 `connected`、2 位玩家均认证成功；游戏服务端快照最终为 `phase=ready`、`admission_complete=true`、`profiles_ready=true`、`gameplay_ready=true`。未在恢复后的双人对局上再次强杀主机，因而不声称完成了真实强退重开循环测试；自动测试覆盖独立连接重建、拒连回退、发送后断线和禁止命令重放。

最后一次检查时 Dota 进程已不存在，助手保持运行并等待 Workshop；因此修正上述
重复自动连接之后的新一次 Hammer 启动仍需实测，不能把上一局恢复当作这次验证完成。

`START_REQUESTED` 只代表启动请求已发送。诊断应继续检查：

```powershell
.\tools\setup_hammer_backend.ps1 -Action Status
```

正常为 `connected`；组队尚未开始时 `waiting_for_party` 属于预期等待。强制终止主机进程无法保证发送退出回调，不能通过增加一个退出监听器代替连接恢复和后端租约机制。
