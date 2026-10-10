# Hammer 重开后认证助手无法连接

## 2026-10-07：反复提示 Setup，控制台已经打开仍不能入场

本次实测游戏和 SSH 隧道均在运行，ECS 健康/就绪检查通过，但助手持续
`waiting_for_workshop`。VConsole 直连 29000，同时保存了启用的 relay 设备
`Localhost:29001`；更关键的是 `Devices/size=1`，而设备子键有 1 和 2。
VConsole 使用 Qt 设置数组，第二个设备超出 size 后根本不会加载，因此上次
单独修改自动连接选项仍不足以保证重开后恢复。CMD/VConsole 窗口存在不能证明
助手拿到了本局服务端连接。

现在 `setup_hammer_backend.cmd` 的 Install 和 `-Action Start` 会先执行
`tools/repair_hammer_console.ps1`，登录启动的助手也会检查并修复：

- 检测现有 MCP relay 的认证控制握手。有 relay 时启用它的 GUI 端口，缺少设备则新增；
  禁用本机 29000 GUI 自动直连，修复 Qt 设备数组 size，保留远端设备和其他端口。
- 没有 MCP 时，助手继续通过既有协议客户端直连；GUI 默认不抢 29000。
  新电脑不需要安装 Codex/MCP，VConsole 窗口也不是认证的必要条件。
  此模式下不要手动把 GUI 连接到 29000；需要恢复时重新执行 Setup。
- 需要修改且 GUI 已打开时只正常关闭对应 Dota 安装的 VConsole，再保存设置并恢复窗口。
  有阻塞对话框时停止修复，不强杀任何进程，不重启游戏。
- 只备份受影响的自动连接值和数组 size 到忽略目录
  `output/hammer_backend/console_backups/`，不读取或保存令牌、控制台历史。
- Install/Start 会展示助手实际状态；`INSTALLED` / `START_REQUESTED` 只是任务操作结果，
  不再用于判断游戏认证已经完成。

只读检查：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\repair_hammer_console.ps1 -Action Check
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\setup_hammer_backend.ps1 -Action Status
```

正常控制台配置为 `console_configuration_ready`、`direct_gui_connected=false`。
本次修复保留 Dota PID 11000；共享 relay 恢复连接，助手为 `connected`，
`players=1, authenticated_players=1`。服务端快照为 `phase=ready`、
`admission_complete=true`、`all_ready=true`；尚未选择模式，
`profiles_ready=false, gameplay_ready=false`，不能把这个阶段的 `loaded_profiles=0`
直接判为存档加载故障。

公共工具包补齐 `backend_python.ps1` 和控制台修复依赖，路径按本机 addon 位置计算。
另一台开房主机仍需自己的 Python/Node、后端凭据和 SSH 配置；加入者不运行主机助手。
Windows 隔离测试覆盖无 MCP 的新配置、遗漏的数组项、缺失设备、String/DWORD 设置、
幂等修复、远端设备保留及 Setup 顺序；它们不替代另一台实体电脑的实际联机验收。

最终验证：18 项 Node 控制台测试、5 项真实 PowerShell Setup 隔离测试、23 项助手测试、
18 项认证测试通过；解释器发现和控制台注册表隔离测试各 24 个检查通过。
37 文件公共工具包已完整解压到独立临时路径，再运行 Setup 与控制台测试通过。
新版 Install 实际接替旧手动助手，计划任务为 Running、认证人数仍为 1/1，
服务端再次确认 `phase=ready, admission_complete=true, all_ready=true`。

本次 Git 同步遇到正在运行的游戏锁定 `maps/template_map.vpk`。保留当前文件，
完成远端同步后它作为一项未提交地图差异留在工作区；没有为了同步强杀游戏。
用户原有 118 项资源的内容哈希及 39 个历史 stash 均核对保留。

## 2026-09-26 排查记录

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

## 常驻轮询与性能采样

常驻助手现在使用 `hammer_console_transport.py` 管理一个隐藏的 Node 子进程，
通过 `map_c6/hammer-console-worker.cjs` 保持单条本地 VConsole 连接。
健康轮询仍每 5 秒检查一次，但不再每次启动 `console.cjs`、重新连接并重放整份引擎历史。
新连接必须收到历史结束后的独立随机 echo 回执并等待 350 毫秒才发送检查。
历史和闲时控制台文本不保存；单次待处理输出最多保留 32KB。子进程只返回
白名单状态、会话哈希、人数和连接计数，不返回原始日志、会话名或认证令牌。

重新开图或丢失认证时，先关闭轮询连接，再调用原有认证注入流程；认证临时文件的
权限检查和 `finally` 清理保持不变。`once` 也保留原来的单次连接/现有 relay 兼容路径。
常驻检查直接连接 `127.0.0.1:29000`；若入口不可用，会退避等待，不会启动新 relay。
官方 `stop` 仍等待实例锁，常驻子进程及其连接关闭后才释放锁并确认停止。

`bridge_status.json` 的 `console_transport=persistent_v1` 表示使用新常驻传输；
`console_connections_total` 是该子进程的连接尝试数，子进程重建由
`console_worker_generation` 区分。稳定对局中这两个值都应保持不变。
进行严格性能对照时，先使用官方 `stop` 并确认 `stop_confirmed=true`。
`capture_extreme_scene.cjs` 只读检查助手状态及采样窗口中的额外连接日志；发现外部
重连、旧助手或无法验证的状态会将采样标为无效，不会擅自停止或认证助手。
