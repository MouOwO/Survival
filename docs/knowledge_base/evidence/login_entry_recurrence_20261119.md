# 2026-11-19 授权前start/http/0再次出现：启动入口缺少助手

## 本次直接证据

用户在1905内测后再次报告WS4-WEB-04/start/http/0/F:nn/H:l。当前普通Dota PID1888，原生创建FILETIME134395465265071904，启动时间2026-11-19 15:22:06 CST；启动参数无console、consolelog或condebug。系统没有file_http_bridge.py助手进程，三个桥接cfg路径也不存在。最近的真实助手回执仍为12:48启动的1904/PID14804；console.log最后写入13:39，内容属于上一局，不能把其中ready/approved当作新客户端成功。

当前pay.xiaofengnet.com/ws4-web/health匿名GET实际200/119字节，既有repair_steam_login.py --check返回READY，云端监听、Steam官方传输和无效断言拒绝均true，未重启中转。本次故障发生于请求发出前，没有证据归因于刚才的历史磁盘清理。主站/health一次HTTPError只代表该路径检查未通过，未将它当作WS4后台故障。

原生两工厂仍为nn，上次成功依赖受用户接受的本机协议2助手。旧桌面入口在客户端已启动时直接拒绝；并且只等待35秒，启动助手后没有检查ready就记录成功，stdout经短命PowerShell重定向。当前证据能证明这次没有助手，不能据此声称本次一定触发了上述某个旧入口内部缺陷。

## 新入口与验证范围

新增tools/workshop_test/online_helper_entry.py与online_helper_client.ps1作为本机封闭内测入口。启动前核对当前已正式上传/官方下载验证的完整包及精确安装文件集、已发布版本中的助手Git字节；入口自身及PowerShell代码必须与当前不可变Git HEAD匹配。没有新授权、候选暂装、安装切换或鉴权绕过。

已有客户端保持并提示正常退出；并发双击由跨进程文件锁拒绝。启动先订阅Windows原生进程事件再从Steam正常启动，最多三个有界进程清单和按PID读取，最长等180秒；不每0.5秒全量扫描进程。仅接受预期exe、原生FILETIME和普通参数，强制启动consolelog。

助手由真实基础Python解释器以-u启动，stdout/stderr直接继承文件句柄，不依赖PowerShell异步管道消费者。必须同时观察真实ready、助手未退出及客户端仍存活，才写成功回执。随后入口只以两个原生进程句柄等待；助手在客户端存活时退出会主动报错，正常游戏退出允许助手最多40秒完成原有HTTPS和所属cfg清理，不强杀客户端。异常和失败均有安全代码，不记录授权码、令牌、账号或HTTP正文。

13项离线回归通过：错误PID/FILETIME/普通模式/日志条件、源码LF规范化与代码差异拒绝、真实基础解释器命令、无ready不能报成功、已退出助手的旧ready拒绝、客户端提前退出、助手先退出主动失败、正常/同时退出和原生等待失败、已有客户端保持且写失败回执。一次夹具对全局Popen过宽mock拦住whoami初始化，修正为只mock临时目录ACL后通过，原失败日志保留。这些夹具不是新真实登录通过证明。

实际Windows启动事件已观察到隐藏立即退出cmd的同一PID，未启动游戏或输入命令；首次探针末尾空事件清理使进程退出码1，不能写成完整脚本退出0。实现采用微软文档的Register-CimIndicationEvent/Wait-Event队列方式，当前开发机需具备事件订阅权限，未据此验收普通Windows用户/所有玩家环境。参考：[微软原生进程事件](https://learn.microsoft.com/en-us/powershell/module/cimcmdlets/register-cimindicationevent)。

初始化成本为固定3次以内清单和必要源码/5个包文件大小检查；助手就绪等待为按新增日志字节读取及O(1)两个存活检查，10Hz/最多30秒；稳定阶段WaitForMultipleObjects阻塞，不增加定时扫描、游戏帧逻辑或HTTP请求。原助手的固定端点、准入、真实授权和内存凭据规则保持。没有全局Windows启动任务或驻守发现器。

## 当前交付状态与待验收

当前游戏/后台代码未更换，游廊仍1905/manifest6306865332807022551；新增内容是本机启动工具。需要将桌面入口切到新工具，再正常结束当前未带日志的客户端，从新入口启动并实际核对助手ready、正式房间start/poll及用户Steam确认。直接从Steam启动仍不包含外部助手；不能称官方HTTP工厂已修好，也不能据此批准公开3000在线发行。

证据在D:/Survival_本地工具/runs/login_recurrence_20261119；临时夹具在树外tests，旧入口和回执保持原路径。后续实际启动/授权结果必须另记，不能用上面上一局日志代替。
