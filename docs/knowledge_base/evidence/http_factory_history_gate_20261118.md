# HTTP 创建失败：历史签包对比与当前引擎门禁

## 本轮结论

本轮只读诊断，没有改运行源码、后台或工坊资源。游廊仍为已核验的 2026111806，
Steam manifest `6295798134948076528`。当前普通客户端的直接失败条件已定位为：
**HTTP 工厂要求 GC 服务器房间对象，而该进程的房间对象及备用房间集合均为空。**
这是创建函数内部返回 null，不是网络 Send、DNS、TLS、服务器欠费或后台 HTTP 状态。

同一工厂后续还检查固定游戏 ID 表；本机这份官方 Windows 引擎中的表不包含我们的
`3824360109`。这说明即使补足前一房间条件，也不能直接认定当前路径已可联网。
此结论限定当前分析的官方客户端二进制，不扩展为所有地区/平台/官方独立服务器政策。

## 为什么以前能：先核对真实历史

11 月 11 日有用户明确确认登录恢复的记录，见
[当日实际验签恢复与用户确认](steam_proxy_dynamic_repair_20261111.md)。
10 月 27 日还有普通双人自动换图、两账号 HTTP 200、http_fishing 读档就绪的实际记录，
保存在 `publishing/workshop/native_arcade_cloud_20261027.json` 的 native08_acceptance 中。
这不是用 Tools 离线测试推断历史正常。

用户随后补充：最近一次正常是在“压测之前”，没有确认具体日期或当时启动入口。
因此故障时间窗口应记为压测前最后正常至当前，不能因 11 月 17 日恰有更新就锁定当天。
此补充不改变当前原生返回分支的实际证据，但限制历史因果归因。

对压测残留补查：当前 PID 35652 无 Tools/dev/addon、离线测试1或 HTTP关闭0启动开关；
该用户 Steam app570 没有持久 LaunchOptions，指定 convars 文件没有对应残留项，
用户/系统 SteamAppId、SteamGameId 均未设置。已查 tools/loadtest_lab 没有写入 Steam
启动选项、Dota 配置或本机离线/HTTP开关的入口；其身份入口/业务/数据库固定隔离回环
29567/29565/25432。Git 中压测前至首次故障的正式认证配置、release_profile、
workshop_connection 和 native_cloud_handoff 也没有差异。以上没有发现直接改写正式
客户端的路径，不把源码检查当成已证明所有历史机器状态或完全排除压测间接影响。

逐字节核对 1106、1607、1803、1806 四份真实发行候选中的 24 个文件，并与各自不可变
签包 manifest SHA256 对上。前三版下面六个文件**全部一致**：

- addoninfo.txt
- config/player_web_auth.lua
- config/release_profile.lua
- config/test_access.lua
- systems/native_cloud_handoff.lua
- systems/player_web_auth.lua

因此最后有用户成功记录之后，到首次故障时的 1803，登录/准入配置、保护后的登录模块
以及换图入口都没有被近期文本、UI 或后台迁移修改。1806 只在登录模块等位置增加了
已说明的工厂兼容和诊断，不能将该后续尝试当作故障最初原因。旧三版登录模块 SHA256
为 `9cf89d0992f5a573f836c4a03a609ee39105047891541d58e6643846790fd397`。

## Dota 引擎确实发生更新，但不伪造引入日期

本机 Steam 原始 content_log 记录：11 月 13 日安装 BuildID 26632873，
**11 月 17 日 17:07:12 CST 安装 BuildID 26718111**。
当前 server.dll 的 PE 编译时间为 11 月 17 日 08:21:21 CST，SHA256
`dc9004cd01101948487f556578e41fc401287c30e8cc46fdd878e41a79e9de54`。
11 月 14 日实际转储中的 server.dll PE 时间为 11 月 13 日，确实不是当前模块；
engine2.dll/vscript.dll 的 PE 时间则与当前一致。

这支持“游戏登录链路未变，而引擎环境在成功与失败之间变化”的方向。
**尚未取得旧 server.dll，不能声称已证明某条检查就是 11 月 17 日新增。**
旧版匿名 CDN 下载尝试被 Steam 明确拒绝 depot 373301 权限，实际下载 depot 字节为 0。
没有提取 Steam 登录凭据、冒用其他账号、回滚引擎或覆盖正式安装；官方符号镜像也未取到。
因此“当前拦截分支已确认”和“该分支首次出现的构建尚未确认”分别记录。

## 当前二进制和实际进程交叉核对

只读分析官方 server.dll 的脚本绑定：CreateHTTPRequest 与 CreateHTTPRequestScriptVM
均指向同一个入口 RVA 0x18d32c0，再进入工厂 RVA 0x18d3110。
所以这两个名字在当前引擎里不是两个独立联网通道，1806 的创建前兼容回退不能绕开共同门禁。

工厂的实际顺序为脚本 VM、GC 房间对象、非零游戏 ID、固定五项 ID 表、SteamHTTP
接口、方法解析、创建请求。GC 房间和 ID 条件失败都直接返回 null，发生在处理 URL 及
调用 Steam HTTP 之前。固定表位于 RVA 0x3bb7790，内容为：

| 工坊 ID | 官方工坊页 |
| --- | --- |
| 469311655 | [Roshpit Champions](https://steamcommunity.com/sharedfiles/filedetails/?id=469311655) |
| 626780182 | [Element TD](https://steamcommunity.com/sharedfiles/filedetails/?id=626780182) |
| 520323982 | [荒神罪](https://steamcommunity.com/sharedfiles/filedetails/?id=520323982) |
| 473718711 | [Crumbling Island Arena](https://steamcommunity.com/sharedfiles/filedetails/?id=473718711) |
| 1613886175 | [DOTA AUTO CHESS](https://steamcommunity.com/sharedfiles/filedetails/?id=1613886175) |

工坊页只核实这些数值确实是游戏条目，不是名单政策的官方公告。
社区在 Valve 问题仓库的 [HTTP 故障报告](https://github.com/ValveSoftware/Dota2-Gameplay/issues/35497)
只能作为背景，报告者自己的名单传闻也标为未确认。本轮直接门禁结论来自本机官方字节，
不是将社区推测写成 Valve 已确认政策。

对 PID 35652 / FILETIME 134394741185082800 再做受身份保护的有限只读核对：

- 进程加载的 server.dll 路径、SHA256 和静态表与分析对象一致。
- 脚本 VM 非空；被查询对象的 RTTI 实际类型为 CDOTAGCServerSystem。
- 主房间指针为空，备用房间集合槽数为 0，首次返回空值的位置为 GC 房间条件。
- 只开 QUERY_LIMITED_INFORMATION | VM_READ，不附加调试器、不注入代码、不写进程内存；
  仅读这些原生控制字段及公开 RTTI/ID 表，不读认证、账号或会话内存。

此前同一进程 0/5/30 秒的匿名 GET 两接口全部 nil、0 Send，与这个直接分支一致。
历史入口确实在换图后离开原 GC 大厅，但没有把历史客户端大厅销毁等同于已证明旧引擎
服务器 GC 对象也为空；后者没有旧进程快照证据。

## 实际范围、代价和下一步

这是一次本机离线 O(二进制字节数) 分析、24 次指定文件 SHA 核对和有限字段只读采样，
没有游戏计时器、帧循环、场景扫描或 HTTP 重试；不能据此声称 FPS 或 3000 人容量改善。
后台保持新机，运行代码与正式安装保持，没有新 SDK 调用、交易或清档。

不为验证而伪造别的工坊 ID 或改写引擎名单。恢复应取得 Valve 对当前条目的联网/托管
准入说明，或合法独立服务器环境的实际对照；仅选择新加坡但仍 H:l 不算独立服务器验证。
重新上传相同登录脚本、重启后台和更换 ECS IP 都不会改变已定位的客户端分支。

树外实际回执：`D:/Survival_本地工具/runs/login_create_failure_20261118/`
`native1806_http_history_analysis_receipt.json`，登记号
`15cdca110f7f2d4f46daa5494a2289e0051d5a7f5c3e6c846ab8460c64bbb641`；
两份原生字段回执为 `native1806_readonly_http_gate_receipt.json` 和
`native1806_readonly_http_gate_rtti_receipt.json`。反汇编工具/结果、下载器和 0 字节 depot
尝试留在 `D:/Survival_本地工具/scratch/http_engine_history_20261118`，不进 Git。
