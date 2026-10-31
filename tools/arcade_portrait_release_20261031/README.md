# 头像／性能／英雄传送限定发行工具

基线为原不公开条目3824360109的已发布3102，官方manifest `2484609663754935010`，6917资源/184保护模块；原package报告SHA `fede692a9d442c7ae4dc24032300d9a4620f1646e963bb7aeb758ff2866dc555`。新sequence为2026110101，revision为WS4-PORTRAIT-PERF-TELEPORT-01。本工具不会上传、部署、安装、启动Dota或操作账号。

固定12项运行资源：renderer编译物、hero_teleport_access新模块及另外三个D相关Lua、commerce_actions编译物、resource/resource-localization/panorama-localization的中英六份文案。新增文件仅hero_teleport_access，预计资源数6918。原dirty HUD、Python缓存、current bundle、头像实验及审计报告均不参与。两个编译物及其Git源码必须匹配本轮已核对的官方编译SHA，不能靠工作区临时替换冒充不可变提交。

当前准备阶段只能运行只读scope；根提交源代码后再提供40位commit建立最终计划。不要将scope作为构建计划。

```powershell
& 'D:/Survival_安全工具/venv/Scripts/python.exe' -B -X utf8 tools/arcade_portrait_release_20261031/build_release.py --scope --report output/arcade_portrait_release_20261031/scope_v01.json
& 'D:/Survival_安全工具/venv/Scripts/python.exe' -B -X utf8 tools/arcade_portrait_release_20261031/build_release.py --source-revision <immutable40> --report output/arcade_portrait_release_20261031/plan_v01.json
& 'D:/Survival_安全工具/venv/Scripts/python.exe' -B -X utf8 tools/arcade_portrait_release_20261031/build_release.py --prepare --source-revision <same40> --reviewed-plan output/arcade_portrait_release_20261031/plan_v01.json --reviewed-plan-sha256 <planSHA> --report output/arcade_portrait_release_20261031/unsigned_v01.json
```

所有报告为NEW且限于本工具ignored输出目录。最终候选路径为外部 `D:/Survival_发布候选/20261101_ws4_portrait_perf_teleport_v01_*`，分卷路径为外部 `D:/Survival_工坊输出/20261101_ws4_portrait_perf_teleport_v01`。未签名review仅12个替换/新增文件、完整manifest及先写入的UNSIGNED_DO_NOT_INSTALL_OR_UPLOAD标记；没有签名，不是完整可运行安装，不得安装/上传。plan/unsigned不会接受key，不存在payload_changed=false或已认证payload的虚假宣称；dry_run=true、signature_valid=false、ready_for_upload=false。

未来--build分支仅已实现而未在准备阶段执行。根须先审阅具体候选并取得本次所需签名授权，再使用同一immutable40、明确reviewed-plan及其SHA、既有外部key和NEW输出。它不生成新key、不覆盖旧目录，也不修改冻结3101/3102工具或父包。成功构建才写payload_changed=false：该SDK字段只表示已签名运行payload经完整VIEW/VPK校验后未被打包过程改变。ready_for_upload仍false，原生、线上性能及具体游廊发行验收由后续独立步骤完成。

```powershell
# 仅后续明确授权后，由根执行；本轮不执行。
& 'D:/Survival_安全工具/venv/Scripts/python.exe' -B -X utf8 tools/arcade_portrait_release_20261031/build_release.py --build --source-revision <same40> --reviewed-plan output/arcade_portrait_release_20261031/plan_v01.json --reviewed-plan-sha256 <planSHA> --key <existing-external-key> --report output/arcade_portrait_release_20261031/package.json
```

manifest保留所有父字段和未知顶层/文件行字段，完整重算files/count/bytes/content及by_directory。原184保护模块及16项准入审阅逐字节保持，正式all_difficulties_unlocked=false、四账号、支付策略与d573保持；protected archive_http_bundle按其已签名的混淆字节验证，不能对混淆文件查找明文d573字符串。父trusted目录仅允许明确已存在的svt_s3102三份安装handoff额外记录。

完整构建的所有父/VIEW/VPK验证和最后父postcheck均包在同一头像scene_maps上下文，避免此前只在中间校验启用、最后遗漏的策略错误。`release_checks.validated_package(reportSHA,full=True)`在以后journal更新前后均可验证该冻结package，检查完整manifest/签名原始摘要、原16审阅、184保护模块沿用和全部五卷CRC/MD5/SHA；只读，不更新journal。最终签名验证和上传不能接受unsigned报告。

成本：仅显式运维阶段。N=6917父资源，K=12替换/新增；一次投影O(N)索引＋O(N log N)排序，O(N)空间；K项不可变Git blob在进程内复用，不反复读取工作区全场。只读scope不打包、读key、建立候选或启动Steam。完整构建顺序读取约3.79GB父/候选/分卷做必要完整性检查，复用未变只读硬链接，仅重打变化卷；这不是帧循环、预热或游戏定时器，不增加游戏稳定刷新成本，不据运维耗时宣称FPS。

测试入口：`python -B -m unittest discover -s tools/arcade_portrait_release_20261031 -p test_build_release.py`。覆盖未知manifest/行字段保留、目录计数、安全路径/大小写冲突、不可变commit、review SHA、未签名阶段禁签名、拒绝已存在review目录和父模块导入别名隔离；全部使用合成数据，无真实私钥、Steam或云端调用。

## 后续发布与官方下载适配器

新增的 `publish.py` 与 `verify_download.py` 不修改上述冻结构建器、validator、AUX清单或父工具。默认运行及显式 `--preflight` 只读本机，不初始化Steam，不写listing/journal，不签名、启动、安装或提交更新。只有以后另行明确执行 `publish.py --apply` 才经原SDK更新既有条目；只有 `verify_download.py --download` 才执行原官方订阅／下载。工具存在不代表本次已获准执行，也不代表候选已通过实机。

发布预检必须传入最终**已签名**package报告、真实开发等价功能证据及真实ETW证据的三个SHA。它完整认证五卷、6918资源、184保护模块、四账号、正式配置及d573；随后只核对12项对应的原始本机开发证据。`UNSIGNED`、GameSetup旧启动或合成测试数据不能用于实际准入。**目前没有经根审阅并固定SHA的更广依赖闭包等价报告，preflight只返回 `SCOPED_DEVELOPMENT_REVIEW_ONLY_BLOCKED_FOR_PUBLICATION`（exit2），apply在任何写入／SDK前硬拒绝。** 不可将开发功能局当签名生产包完整玩法通过。

```powershell
# 只读；下面的占位参数须由根替换为实际已审阅证据。
& 'D:/Survival_安全工具/venv/Scripts/python.exe' -B -X utf8 tools/arcade_portrait_release_20261031/publish.py --preflight --report-sha256 <completedPackageSHA> --native-proof output/arcade_portrait_release_20261031/native_acceptance_v01.json --native-proof-sha256 <nativeSHA> --frame-proof output/arcade_portrait_release_20261031/frame_acceptance_v01.json --frame-proof-sha256 <frameSHA>
& 'D:/Survival_安全工具/venv/Scripts/python.exe' -B -X utf8 tools/arcade_portrait_release_20261031/verify_download.py --preflight --report-sha256 <completedPackageSHA>
```

两份证据为schema1 JSON，所有引用均为 `{ "path": "...", "sha256": "..." }`，相对路径从所属JSON位置解析，必须是本仓库ignored `output/` 中的普通文件；不接受链接或越界。顶层共有 `synthetic=false`、`release_sequence=2026110101`、`content_sha256`、`package_report_sha256`、`online_fps_verified=false`。这些声明仅是入口，不能替代以下原始数据、真实原生行为及根的画面审阅。

开发等价证据的 `kind=DEVELOPMENT_SCOPED_EQUIVALENCE`、`status=PASS_SCOPED_DEVELOPMENT_FUNCTIONAL_ONLY`，字段为：

- `signed_startup`、`signed_startup_log`、`signed_startup_query`：同内容的新签名启动及其原始日志／原生cvar查询。启动单独要求cheats=false、正常HTTP=1、6918/184、五项原标记全部为true。查询须绑定该启动PID、addon `svt_ap1101`、原始回显及其SHA。签名启动可以只到GameSetup，但本身不能满足下面的功能局要求。

新启动报告的 `native_process` 和原生query均须记录实际CIM `created_utc`，两者PID及创建代际一致；`started_utc`只能描述脚本启动时间，不能代替进程CreationDate。
- `process={pid,created_utc}`、`input_freeze_utc`：功能局是独立的development `survival` 入口，为冻结输入之后新建的Tools进程；不操作正在等登录的普通游廊局。功能局允许cheats=true，必须已进入真实、运行中的GAME_IN_PROGRESS，offline_logic_test=true、session_memory、云写／真实账号操作均0。签名production的svt_ap1101刻意拒绝offline逻辑；签名生产启动和开发功能局是两份不同配置／不同进程证据，不能把离线作弊设置带进正式包。
- `runtime_inputs`：恰好12项 `{runtime_path,raw:{path,sha256},normalization}`，保存该新进程实际启动前冻结的开发运行资源快照。与签名候选target_pins逐项比对；默认 `EXACT`。仅Lua／本地化文本可明确使用 `RUNTIME_CRLF_TO_GIT_LF_ONLY`，只接受CRLF→LF且转换后没有孤立CR；不接受任意文本归一。它不同于renderer编译源码的Git-LF／官方编译CRLF双摘要，运行vjs_c必须逐字节一致。ETW证据再独立提供同12项及相同原始摘要。
- `native_transport`：实际本地原生控制台捕获的 `{process,expected_output_received,raw_output}`。恰好一条 `[ARCADE_1101_NATIVE_PROOF] ` 后跟真实fixture JSON，包含同代际process、release_channel=development、addon=survival、web_auth_enabled=false、tools/offline_logic/gameplay_ready/in_progress=true、paused=false、storage=session_memory、cheats布尔值、cloud_writes=0、real_account_operations=0，以及五项 `d_checks`：`unowned_hidden_and_rejected`、`owned_cast_succeeds`、`shared_cooldown_10s`、`failed_cast_no_new_cd_and_refund`、`builder_d_unaffected`。这些须来自实际原生断言；适配器不执行或生成fixture。
- `portraits` 必须有 `bane_5`、`wave_equipped`、`hero_builder_switch`、`bane_5_after_eviction`。每项明确native_ui、visual_reviewed、no_stale_portrait及 `captures=[{png:引用,metadata:引用}]`。原始PNG与 `capture_live_ui_readonly.ps1` 的严格PID／前后HWND／四角／前台／代际元数据逐项绑定；根亲自审阅饰品、背景及切换画面。非切换项另有wearables_visible、background_visible、no_base_model_flash以及与实际不同PNG数量一致的reviewed_frame_count（至少3张）。切换项需hero_and_builder_correct、no_stale_qwer。Bane初次scene_key与返回returned_scene_key相同；返回项visited_other_scene_keys至少5个不同其他场景。离散截图仅证明已审阅帧，不能声称覆盖帧间全部瞬间。

返回项同时提供 `visited_scenes={scene_key:{visual_reviewed:true,capture:{png:引用,metadata:引用}}}`，键与visited_other_scene_keys一致，每个中间场景至少一张实际严格原生截图；只有五个名字的列表不能证明LRU压力已经真实发生。

证据另有 `equivalence`，comparison_basis固定为 `EXACT_SIGNED_TWELVE_RUNTIME_INPUTS_ONLY`、source_revision绑定package不可变提交，full_package_gameplay_verified及broader_dependency_closure_verified均false。production_entry必须明确addon=svt_ap1101、release_channel=production、web_auth_enabled=true、archive_http_enabled=1、offline_logic_test=false、cheats=false；development_entry明确addon=survival、release_channel=development、web_auth_enabled=false、archive_http_enabled=0、offline_logic_test=true、cheats=true。这里只证明12输入逐项对应及所观察功能；其余脚本依赖、保护字节／明文、引擎入口、准入和账号投影的等价性尚未完整证明，不能通过添加自报PASS来补齐。

ETW证据的 `kind=NATIVE_OFFLINE_ETW_ACCEPTANCE`、`status=PASS_NATIVE_OFFLINE_ETW`，process与runtime_inputs必须和功能局同代际、同原始输入。必需引用 `capture`、`collector_identity`、`frames_csv`、`focus`，以及 `screens={before,after}`、`gameplay_before`、`gameplay_after` 和 `visual_review`。capture使用现有采集字段pid/seconds/tools/read_only_etw/script_injection/account_operations/frame_csv_sha256；collector为实际进程代际及Intel签名PresentMon观察。frames_csv为原始PresentMon v2数据，必须有ProcessID、SwapChainAddress、CPUStartTime、FrameTime，单PID、单swapchain、时间单调；保守丢弃首行后至少120个正间隔。适配器独立重算平均FPS、线性插值P95、CPU时间覆盖和间隔总和，拒绝报告自填FPS。原始覆盖至少30秒（边界允许采集尾部1.5秒误差），且与本次请求／焦点观察长度一致。

capture还必须保留真实采集的 `started_utc`、`delay`、`wall_seconds`；focus的delay_seconds须相同。原始CSV首末CPUStartTime加上该capture启动时间，与实际focus两端分别在1.25秒范围内对应，capture墙钟必须覆盖焦点与after截图，before截图必须早于capture启动。这个容差与既有3102真实采集的约43ms启动差相容，用来拒绝同PID早先CSV搭配后续focus／截图；它不是绝对ETW墙钟同步认证，报告明确保留该限制。

本轮上传前工程门槛固定为平均**至少90 FPS、P95至多16.7ms**，未达标即拒绝，不根据无数据判断放宽。focus原始报告须与同PID、唯一可见主HWND及截图尺寸一致，每秒样本／间隔／实际墙钟和单调时钟均重新核对。前后原始截图及带实际计时推进的GAME_IN_PROGRESS需根审阅；`visual_review` 的performed/before_game_in_progress/after_game_in_progress/timer_advanced均true并绑定两张PNG摘要。原生前后查询引用使用同process捕获的 `[ARCADE_1101_GAMEPLAY_SAMPLE] `，载荷含process、in_progress/gameplay_ready=true、paused=false、host_timescale=1、game_time及utc；画面／查询必须夹住真实ETW观察窗口，游戏时间确实推进至少本次时长减1.5秒。每秒焦点采样无法证明采样间始终前台，报告保留这一限制。

此门槛仅是**本机受控离线Tools候选预检**，不替代普通游廊开局帧率。预检和以后上传均明确 `online_fps_verified=false`；真正的普通游廊修复后FPS必须在新包官方下载、新开正常局后另验，不能提前写成通过。

目前 `APPROVED_CLOSURE_REVIEW_SHA=None`，没有可直接执行的生产apply路径。未来若根取得更广依赖闭包的实际等价证据，须先独立审阅具体报告、固定其不可变SHA并审阅新准入决定，不能仅把 `--preflight` 换成 `--apply`。闭包审阅还须绑定kind `PRODUCTION_DEVELOPMENT_DEPENDENCY_CLOSURE_EQUIVALENCE`、新sequence/content/package报告/source_revision和full_dependency_closure_verified；仅JSON数据自行写reviewed/PASS不能解锁。即使以后解锁，也只允许从成功3102父journal或本次同字节成功journal继续；未知status、CREATE/SUBMIT pending、不同条目／账号／可见性／同sequence内容都拒绝，绝不清pending或自动重试。listing保持原四账号和Unlisted，在原publication_lock内重新绑定package报告、SDK事实、全部证据与journal摘要后才可调用原SDK `publish(...apply=True,update_existing=True)`。任何新失败由原SDK在不可逆提交前记录恢复journal。

官方下载必须在真实同版上传成功后另行获准，显式加 `--download`。wrapper按LF摘要固定导入**未修改**的 `tools/arcade_cleanup_20261027/verify_download.py`：真实fresh query、一次1313订阅回调、一次3406下载回调、实际ACF manifest、全部五卷CRC/MD5/SHA和签名资源都由该冻结协议检查；它要求关闭Dota、保留Steam。没有猜测新版manifest、改journal或自动重试。保留协议原来终端摘要中的历史180常数；权威 `verification.json` 从本wrapper输入写 `protected_modules_verified=184`、`signed_resources_verified=6918`，验收只能以其实际签名／全部字节验证和回执为准，不能拿终端历史常数代替。

成本只在显式运维命令发生：K=12输入按路径建索引一次、O(K)比较；证据按文件路径缓存首次SHA与JSON，不重复解析相同引用，退出／提交前顺序复核摘要。原始ETW最多200000帧、CSV至多64MiB，统计O(F log F)排序、O(F)内存；其他结构／源快照单文件至多8MiB，PNG引用至多512MiB。完整候选认证仍有6918项及约3.79GB五卷的必要顺序校验，apply由原SDK再作完整上传前认证；它不增加游戏初始化、稳定刷新或状态变化的任何循环／原生桥调用，无法据此声称FPS提升。

可复跑隔离测试（使用带cryptography的既有安全venv）：

```powershell
& 'D:/Survival_安全工具/venv/Scripts/python.exe' -B -X utf8 -m unittest discover -s tools/arcade_portrait_release_20261031 -p test_publish_download.py -v
```

所有fixture临时生成后清理；Windows原生输入、真实SDK初始化和网络均0，不读取私钥、不产出可用于实际发布的实机通过证据。测试覆盖只读零写／零SDK、生产与离线cheats边界、原始查询／PID代际／12输入／LF绑定、Bane及五场景回切、UI残留、焦点／计时／原始CSV复算与性能拒绝、journal不明状态保护，以及未来apply/download调用只在mock内的限定契约。

## 签名生产原生启动工具

`native.py` 默认plan是纯静态计划，不扫描CIM、不初始化Steam、不创建文件或启动进程。所有有副作用动作均须显式指定；本次只写工具及隔离测试，未实际安装、启动、查询控制台、关闭或操作UI。固定addon `svt_ap1101`、端口29026，任何动作都不能修改当前用户PID28324。

```powershell
& 'D:/Survival_安全工具/venv/Scripts/python.exe' -B -X utf8 tools/arcade_portrait_release_20261031/native.py
# 以下仅示意后续明确审阅／授权后的操作，本次不执行：
# native.py install --report-sha256 <completedPackageSHA>
# native.py launch-smoke --report-sha256 <sameSHA> --run-id v01
# native.py query --run-id v01
# native.py collect-smoke --report-sha256 <sameSHA> --run-id v01
# native.py close --run-id v01
```

install先验证具体已签名package SHA、全部VIEW／五卷，检查无任何Dota和29026占用、正常Steam以及只读SDK owner/app/BLoggedOn，再通过既有受审handoff只复制签名清单至新隔离addon，不覆盖旧目录。launch-smoke重新验证安装的6918资源／签名元数据和具体package报告，重新检查无其他Dota／端口空闲／Steam在线，以生产源码sv_cheats=0、HTTP=1、host_timescale=1启动；不带offline flag，也不改正式配置。先写NEW launch_intent，再由Popen启动，随后只采用实际CIM CreationDate作为created_utc；无法确认所有权时保留诊断，不自动重试或强杀。启动收据只表示进程开始，不是加载或玩法通过。

所有控制操作核对自建收据的PID、精确CIM创建时间、实际exe、命令行SHA及完整固定argv、addon、29026监听者；query另外拒绝任何其他Dota。控制台复用既有ConsoleSession帧协议／历史屏障；只发送sv_cheats、survival_archive_http_enabled及随机echo，不写／加载Lua。Node子助手在连接／新屏障及发送固定命令批次前再次通过只读CIM验证同代际／完整命令行／端口所有权，query返回后Python再核对一次；查询收据包含实际代际和原始回显摘要。

collect-smoke再次全量认证已安装字节及模式默认、核对实际查询与engine日志五标记、冻结日志并生成 `PASS_NATIVE_SIGNED_PRODUCTION_STARTUP_ONLY`。它明确full_package_gameplay_verified=false、online_fps_verified=false，不自动生成玩法／视觉／D技能或性能PASS。close只向严格绑定的自建进程端口发送引擎正常quit，再有限检查该同代际进程退出；可在另有用户客户端时只关闭自己的客户端，不对用户PID发命令。失败没有terminate/kill/Stop-Process补救，也不清理、覆盖或重放旧收据。

`launch-offline` 在任何安装／进程／SDK动作前明确拒绝 `SIGNED_PRODUCTION_OFFLINE_NOT_SUPPORTED`。真实边界来自production release_policy.development_allowed=false、offline_logic_test.configure的Tools/development断言和web auth冲突；生产清单也不携带可用的开发离线provider。不能override门禁或给签名源码补测试Lua。另一个development survival入口可在用户关闭普通局后，按原开发启动流程做内存provider一次性真实断言、云写0，再收集同12输入的开发等价功能数据；这个工具不启动该独立入口，也不称它为签名包完整玩法证明。根负责实际fixture、选怪／施法／截图／ETW和最终普通游廊登录后验收。

此工具只在显式操作时工作：进程／端口扫描O(P+L)，通常P为0或1客户端，命令前后各一次以及控制台子助手的有限保护检查；关闭最多8次、单次OS读取有20秒超时，绝无稳定帧循环。安装／启动前必要的6918资源完整认证是运维成本，不新增游戏循环调用或据此宣称FPS。`test_native.py`覆盖默认零效果、未签名拒绝、保护PID／重用代际／错误端口／其他客户端／argv改变、真实CIM时间收据、正常关闭仅自有PID；全部原生操作和SDK由mock替代。
