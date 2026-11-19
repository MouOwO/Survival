# 专用登录器 EXE、下载入口与游廊说明（2026-11-19）

## 原因与交付边界

用户再次确认从 Steam 直接进入，显示 F:nn/H:l；上轮开发机 Python 入口成功不等于原生 HTTP 工厂恢复。用户要求将联网入口封装为玩家可直接运行的 EXE，并在宣传介绍中加入下载与进入方式。仅保留已批准的五账号内测，不扩大准入，不把下载器当身份认证，也不包含付费相关宣传。

新增 tools/player_launcher/app.py、windows.py、build.py、README.txt、requirements-build.txt。build.py 从当前不可变 Git 提交导出五份精确源码，从实际已发布1905来源8d34511a4a5b3b7515c906f5752c0c811db3f92f导出原助手；仅封装标准库、Tcl/Tk和该助手。玩家侧不需要 Git、Python、开发仓库、authority、私钥或 PowerShell 7；按PID读取启动参数使用 Windows 自带 PowerShell 5.1。助手固定 HTTPS、五账号、真实 Steam 授权、内存凭据及业务检查保持，不加入监听、进程注入、任意URL或自动交易。

## 实际 EXE 与实机验证

源码70a42498d8f59d087d7f2508cf7e8279c9a1c1ab已推送dev；content仍23b9cc65101315ddfad02f469fda08bf42bc452d/master。build01生成GoufayuLauncher-20261119.1.exe，13,178,697字节，SHA256 bcae51e788e77242de288d991b366589a25255b144d5185e8ded064883d11138，版本2026.11.19.1。PyInstaller6.22.3及七项依赖锁定版本和wheel哈希，下载记录在build_dependencies.json；没有Windows代码签名，不声称所有Windows/安全软件均已验收。

12项定向回归与原助手9项回归通过。真实单文件复制到含中文、空格的新目录，PATH移除Python/Git/PowerShell7，Tcl/Tk窗口实际初始化、退出0，0.56秒。实际Steam库自动识别与5个正式VPK完整SHA256检查通过，读取3,812,591,710字节耗时2.61秒；不是以文件大小代替校验。受控隐藏窗口原生通知匹配真实子PID/FILETIME、注销完成、退出0，不将其当Dota启动证明。

随后用户正常退出旧Dota，实际安装EXE在D:/Survival_玩家登录器/2026.11.19.1，打开GUI后由用户点击启动。真实GUI进程27336，新Dota14408/FILETIME134395508531610651，consolelog=true；单次进程快照、9次窗口事件、2次按PID身份读取完成识别，助手ready才发布成功。用户确认“已完成授权并进入游戏”；同一新PID匿名日志approved、start200/240字节、poll200/293、session/authenticate200/22846、session/login200/39316、在线同步200/50576及50577均有游戏ACK。catalog返回只算传输，不算购买；本轮没有真实交易、跨局存档持久化、多人或3000在线验收。当前EXE、助手线程和游戏保留运行。

验收根D:/Survival_本地工具/runs/player_launcher_20261119，acceptance_receipt.json SHA256 aaa87a3317a0ccbc45ccab70d21e98a9a68321c885363c4d9769bbf4aa38ee58。原始授权码、nonce、账号、令牌和HTTP正文未加入回执或知识库。实际每局运行目录在用户LocalAppData/Goufayu/Launcher/sessions，原console.log仍由既有助手保护为当前用户/SYSTEM可读；只向玩家展示安全错误码和诊断目录。

## 成本、生命周期与兼容边界

| 阶段 | 工作与成本 | 实测/限制 |
| --- | --- | --- |
| 初始化 | O(P+L+B)，P为一次系统进程快照，L为Steam库数，B为完整5包字节；1MiB分块、工作线程，进度仅整数变化入队 | 当前5包约3.8GB，2.61秒；不每次UI刷新重扫 |
| 等待Dota | 最长180秒的out-of-context窗口通知，按PID缓存，最多4096个相关PID；固定Windows消息泵与截止计时器 | 当前9事件/2身份读/1进程快照；不用需管理员的Win32_ProcessStartTrace订阅 |
| 稳定GUI | 每100ms只取最多32条状态变化，O(k)，空闲O(1)，不遍历场景/进程/包文件 | UI写入只发生于状态变化；没有FPS改进宣称 |
| 助手 | 沿用已发布协议2的增量日志/ID索引、四线程和原有上限 | 不是新性能或容量验收 |
| 结束与失败 | 游戏退出后由原助手清理所属文件；异常写安全失败回执，GUI不强杀Dota，运行期间关闭窗口只最小化 | 现有客户端拒绝接管，需正常退出重开；不覆盖未知遗留cfg |

普通权限兼容只允许依据真实探针判断：当前运行令牌无UAC关联令牌（错误1312），随后受限令牌探针遇到访问拒绝5，均未启动游戏，不能当普通Windows用户已通过。玩家需Steam与登录器同一Windows用户和权限、可写NTFS游戏目录；其他电脑完整入局待内测反馈。窗口事件本身不要求使用进程StartTrace管理员订阅，参考[微软SetWinEventHook](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setwineventhook)。单文件和无控制台打包按[PyInstaller官方文档](https://pyinstaller.org/en/latest/usage.html)，避免把sys.stdout=None当可用输出。

## 下载与介绍待发布

下载页及发布器为tools/player_launcher/download.html与publish_download.py，计划地址https://xiaofengnet.com/launcher/。只写既有nginx静态目录下全新launcher子目录，按固定版本、完整哈希与已验收EXE绑定，拒绝覆盖未知旧目录；不改API、数据库、证书或重启服务。游廊正文顶部增加“先运行登录器，等待联网完成再进游廊”、下载链接、运行期间保留窗口和当前测试资格说明，保留原玩法介绍、11月20日计划、测试档不继承及QQ群1098603739，不含付费/问题反馈文字。

此节是准备状态，实际HTTPS下载和Steam SDK语言回读完成后另补证据。当前资源仍1905/manifest6306865332807022551；没有新的运行包上传。旧8项工作区改动逐字节保留，git_code01在提交前因新增文本CRLF规范化停止，stash已恢复；git_code02只对新增文本规范化LF，原8项仍按原始SHA检查，两仓成功推送。

## 下载和双语言介绍已正式完成

https://xiaofengnet.com/launcher/已上线，既有nginx静态目录全新launcher子目录含精确EXE、ZIP、使用说明、SHA256和version.json；未改业务API、数据库、证书或重启服务。公网HTTPS完整下载13,178,697字节EXE耗时8.933秒，SHA256与本机实机验收完全一致；下载页全文摘要和版本元数据也一致，public_https_verification_receipt.json保留。桌面三个入口已备份并统一指向独立EXE，运行中的客户端未被快捷方式操作干扰。

简体中文SDK提交后，官方回读发现默认语言仍为旧正文。为避免默认页遗漏入口，统一description plan增加schinese/english二选一，lease只允许请求绑定的精确语言，不允许未审语言或跨语言setter；10项说明定向及18项既有发行门禁通过。19682de571974790eaef62314a46b59fdac2d41d已推送dev，随后独立默认语言请求只提交一次并收口。两个语言的最新官方无缓存回读均为标题“我在dota2苟发育”、正文SHA256 d2beb158179d257ef4ba7f0e37197b7af46f065a41f3c6937881bdec35b7c4ea、visibility3，正文含下载链接与QQ群；lineage pending为null，游戏包journal原始字节保持。

完整发行检查首次未指定官方下载回执，报告缺少验证输入；保留该失败，不当漏发或通过。显式给定1905真实官方完整下载回执后，delivery_status_with_official1905.stdout.json返回WORKSHOP_SYNCED、完整待发/历史/阻断/dirty runtime均0。该观察发生于语言工具修正前，后续资源发行需重新检查，不能把它视作未来版本验收。

build、真实入局、桌面备份、静态发布、公网下载和双语言回读回执均已登记，清单在ledger_registration01.json。安装启动回执gui_launch_receipt.json指向D:/Survival_玩家登录器而被账本拒绝，原回执完整保留；不伪造已登记或改写真实路径。

随后用户新增“合成伐木工动作仍重置，修改并发布”要求，并同意正常退出当前Dota做隔离动画对照。该EXE严格绑定1905；下次运行包更新后，必须同时准备并验收匹配的新EXE、更新下载页和桌面入口，不能让1905下载入口成为新包的登录阻断。当前下载与介绍完成不等于新伐木工修复已交付。
