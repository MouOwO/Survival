# v02：查询头像锚点／饰品／性能／英雄传送限定候选

v01保持原文件、plan与unsigned全部字节，本目录独立版本化。唯一父仍是已发布并官方完整下载的3102：原不公开条目3824360109、package报告SHA `fede692a9d442c7ae4dc24032300d9a4620f1646e963bb7aeb758ff2866dc555`、manifest2484609663754935010、6917资源／184保护模块。未发布的v01不能当父，原canonical journal及其失败历史不重置或另开。

新sequence2026110102，revision `WS4-PORTRAIT-PERF-TELEPORT-02`，独立输出 `output/arcade_portrait_release_v02_20261101/`；外部前缀 `20261101_ws4_portrait_perf_teleport_v02` 的overlay/view/trusted_source/unsigned_review及工坊输出均为NEW，不能覆盖v01任何目录。native addon预留svt_ap1102，但本目录未fork或执行native／publisher／download动作。

固定13项为v01原12项加 `panorama/scripts/custom_game/combat_stats.vjs_c`；它替换已有资源，新增资源仍只有hero_teleport_access，因此目标总数仍6918。renderer、commerce_actions、六份本地化、D四Lua及其持有权益／共享10秒CD源码合同保留。所有184保护模块、原16份准入审阅、正式false配置、四账号和d573保持；没有商品价格／奖励或玩家数据变更。[公开商品审查](../../docs/reviews/commerce_feature_audit_20261031.md)和[D权益审查](../../docs/reviews/hero_teleport_entitlement_20261031.md)继续有效，不把报告打进runtime。

根已冻结combat_stats官方v04产物，确认六场景离线实机范围通过；本目录已核对实际源码／编译物并绑定三摘要。最终不可变源码提交仍待根双仓提交后提供，**本次不生成最终plan／unsigned，也不签名或发布**。开发离线视觉、完整签名生产启动、普通游廊及FPS／D技能验收仍分别记录，不能互相替代。

| combat_stats绑定 | SHA256 |
| --- | --- |
| Git规范LF源码 | `33e9060d8ba13c57beb6ed2776b2faaefd46daba97ebf8450046e3bd6223b79f` |
| 官方CRLF编译输入 | `679041e3b2734d29fdfe560ae7ba28a454d36db3735aaeb9e473074da77dded0` |
| 官方vjs_c，221818字节 | `1d0be37fe2e510e86179c64a6d904fc72bd6e59d777b3355a5f264e4dc2ba9fd` |

保留Git-LF／实际官方编译CRLF双摘要，仅允许明确LF→CRLF重建，不做任意文本归一；前两组官方SHA原样继承。缺失任一pin、旧combat产物、未经审阅的源码／编译物都会拒绝，缺pin负测使用合成缺失场景，不把真实配置写回PENDING。

默认及 `--static-plan` 仅打印静态说明，不读父包／journal／Git、不建报告、不读key、不初始化SDK、不安装或启动任何进程，也不会生成最终plan／unsigned：

```powershell
& 'D:/Survival_安全工具/venv/Scripts/python.exe' -B -X utf8 tools/arcade_portrait_release_v02_20261101/build_release.py
```

之后由根给出最终source commit和具体审阅，才可按v01原流程生成NEW plan／unsigned；**本次不运行**这些分支。未来build仍要求明确已审计划SHA、同一不可变commit、既有外部key及NEW输出，源范围／compiled绑定／journal变化均在读key前拒绝，旧v01计划不能驱动v02签名。12项旧范围的签名pending不自动授权新的13项候选。

对v01的限定差异：

- 新sequence/revision/namespace/output及所有权预留名；只追加combat，不改变原D位置索引。
- 第三组Git／编译输入／产物绑定；缺任一组或未获得真实官方摘要时fail closed。
- 默认纯静态plan；显式scope与最终plan保持分离。静态模式不能夹带source/report/key或其他动作。
- canonical journal额外要求实际成功3102的status／owner／app／VPK头与五卷清单；UNKNOWN、CREATE/SUBMIT pending及其他父版本均拒绝，不丢失败历史。完整validator在上传后的只读验证仍可使用 `require_current_journal=False` 认证冻结3102父字节。
- v01全部外部输出加入互不重叠保护；新validator要求恰好13目标及3份source_artifact_pins完整匹配。

其他完整签名／manifest未知字段及行字段／by_directory重算、16审阅、184保护、scene_maps全上下文、五VPK CRC/MD5/SHA、SDK payload_changed语义均保留。没有为本轮做大范围发行框架重构。

生产源码刻意拒绝offline_logic_test，不能override development_allowed或往签名包放测试Lua。后续原生开发视觉须明确 `DEVELOPMENT_SCOPED_EQUIVALENCE`，新13运行输入逐项绑定签名候选，并说明development survival和production svt_ap1102的入口／配置差异；实际修复须看Bane5、波次、英雄／建造者、五场景回切及连续原始画面，不能由缓存READY代替头像已挂接。根负责新进程内存provider／云写0真实断言、选怪／施法／截图／ETW。

签名生产startup独立认证同具体包，仅启动通过不等于完整玩法。没有更广依赖闭包审阅时，不得给任何publisher填假的APPROVED_CLOSURE。v01发布适配器仍受原None门禁保护；不能将其直接指向v02或仅改12→13绕过新审阅。实际普通游廊新包登录、头像和开局FPS仍必须在正式上传及官方下载之后另验，开发Tools数据不冒充线上验收。

复杂度：仅显式运维。静态默认O(13+3)，无native/API/网络；最终投影保留O(N)索引／O(N log N)排序和O(N)空间，N=6917、K=13；不可变Git输入每次收集恰好K+3=16个blob。184保护／完整五卷认证为必要顺序运维校验；不会增加游戏初始化、稳定刷新或状态变化的任何循环／桥调用。COMPILED三组校验O(3)，journal身份检查不改或遍历失败历史。

```powershell
& 'D:/Survival_安全工具/venv/Scripts/python.exe' -B -X utf8 -m unittest discover -s tools/arcade_portrait_release_v02_20261101 -p test_v02.py -v
```

隔离测试使用合成临时数据及当前冻结编译物只读核对，不读私钥、不执行SDK／native，也不产出实际plan／unsigned。覆盖静态零效果、13范围及3绑定、合成缺pin阻断、真实v04源码／221818字节产物绑定、Git／compiler LF约束、D源码合同、manifest字段保留、旧v01计划拒绝、未知journal保全及12文件报告拒绝。

## 原条目本地签名候选排演工具（尚未执行）

`rehearsal.py` 是独立的 `LOCAL_SIGNED_CANDIDATE_REHEARSAL` 工具。它不属于发行builder的固定输入，不修改v01、冻结builder／checks或publisher门槛，也不表示候选已获签名／发布许可。当前仅准备代码和合成隔离测试，尚无本工具的真实安装、客户端、Restart Manager、OAuth或FPS验收。

Tools中的生产代码明确拒绝native roster，且ws4_entry换图固定原条目3824360109，因此不能用svt_ap1102开发alias代替普通生产入口。排演仅在签名获批且真实signed package报告存在后，将完整签名候选五VPK临时放到原条目当前安装位置，通过普通non-Tools原入口实际验证。它不是官方下载，不改变Steam记录的3102 manifest，不能生成官方1313／3406回执。

默认命令只打印静态计划，不读包／journal、不查OS、不建目录、不初始化SDK、不启动进程：

```powershell
python tools/arcade_portrait_release_v02_20261101/rehearsal.py
```

下列是未来逐阶段接口示例，**不是本次执行记录**。必须先获得具体候选操作许可，并提供已完成签名包的真实报告SHA；没有报告、unsigned review、源revision／签名／13文件scope不匹配时，所有动作（包括restore）在写入前拒绝。工具不读取或使用私钥。

```powershell
python tools/arcade_portrait_release_v02_20261101/rehearsal.py stage --transaction reviewed_trial --report-sha256 <SIGNED_PACKAGE_REPORT_SHA256>
python tools/arcade_portrait_release_v02_20261101/rehearsal.py launch --transaction reviewed_trial --report-sha256 <SIGNED_PACKAGE_REPORT_SHA256>
# launch是持续keeper，需保留该终端或exec session。另开终端执行下一阶段。
python tools/arcade_portrait_release_v02_20261101/rehearsal.py inspect --transaction reviewed_trial --report-sha256 <SIGNED_PACKAGE_REPORT_SHA256> --label after_normal_login
python tools/arcade_portrait_release_v02_20261101/rehearsal.py close --transaction reviewed_trial --report-sha256 <SIGNED_PACKAGE_REPORT_SHA256>
# 等自建Dota正常退出、keeper结束并释放句柄后，才能restore。
python tools/arcade_portrait_release_v02_20261101/rehearsal.py restore --transaction reviewed_trial --report-sha256 <SIGNED_PACKAGE_REPORT_SHA256>
```

- 唯一目标是 `D:/SteamLibrary/steamapps/workshop/content/570/3824360109` 的原五文件；外部NEW事务固定在 `D:/Survival_本地排演/20261101_ws4_portrait_perf_teleport_v02/<transaction>`。不在安装目录添加marker／临时文件，不写ACF、subscription、cache、下载状态、canonical journal或旧发行文件。事务里保留完整物理old备份、candidate staging、逐步意图和恢复记录，不使用hardlink／move消耗备份。
- stage先完整验证实际3102五文件及签名候选，再分别复制完整五文件并核SHA／大小／VPK CRC／MD5。空间预算为old备份总量＋candidate staging总量＋两组中最大的前向／恢复临时文件＋512MiB，不以13个变更文件大小代替。每次替换前复核无Dota、精确preimage及原item的ACF未变，卷优先、index最后。`hash→os.replace`是乐观CAS，**不是与Steam updater的原子事务**；发现变化即停止并保留`RECOVERY_REQUIRED`，不自动重试／恢复。
- launch须无其他Dota、固定29028端口空闲、正常Steam在线且账号／AppID正确。普通argv只含原3824360109/ws4_entry、sv_cheats0及HTTP1；无Tools／dev／addon／insecure／offline参数。CIM实际创建时间、exe及完整argv绑定自建PID；正常OAuth必须由根agent／用户完成，工具不生成名单、不注入Lua、不替玩家批准授权，也不构造synthetic profile。
- keeper对候选五个真实路径持有`CreateFileW(GENERIC_READ, FILE_SHARE_READ, OPEN_EXISTING)`，不授WRITE／DELETE共享、不继承句柄；启动前持有期间全量核SHA与FileID。如果共享方式不兼容，拒绝，不放宽。另以`SYNCHRONIZE|PROCESS_QUERY_LIMITED_INFORMATION`只读权限持有自建Dota进程对象，GetProcessTimes与QueryFullProcessImageName核实际创建时间／exe。CIM_DATETIME只有六位微秒，ToString('o')补出的第七位0并非真实100ns：初始native FILETIME必须落在实际CIM微秒bucket，再把精确GetProcessTimes值独立绑定Dota／keeper回执；连续lifetime及RM之后都精确比native pin，不用时间容差代替。稳定期只做2秒超时的WaitForSingleObject，不启动PowerShell、不查CIM、不hash或扫描；PID复用也不能替换此原进程对象。CIM完整argv／port仍在启动、inspect／close起止核对，自建进程退出后再做一次无Dota／端口观察并核handle代际。keeper被中断／身份变化会留下失败记录，**不得把此前截图升级为连续锁定证据**。close另持有同native pin只读process handle，再仅向同代际／argv／port的自建进程发送一次固定quit；失败不强杀、不自动重放。当前已有Dota不会被关闭。
- inspect显式执行全五文件SHA与FileID检查，须放在ETW采样之外。Restart Manager按**每文件独立session**登记固定完整路径，再GetList，避免五路径聚合列表只能说明其中一个被打开。仅使用`RmStartSession/RegisterResources/GetList/EndSession`；不枚举全process handles、不调用shutdown／restart。每文件最多3次GetList、上限64进程，匹配实际Dota PID＋FILETIME创建时间及keeper代际，只保存匹配布尔值，不保存其他应用名／命令行。`index_owned_dota_use_observed`与`all_five_open_verified`分开报告；未用卷可能没有被原生打开，缺项保留`INCOMPLETE_NATIVE_FILE_USE_EVIDENCE`，不盲放宽，也不把打开五卷说成执行过全部脚本。外部完整6918／184认证与原生已观察路径是不同证据；未来目标仅为同签名候选所测路径及像素／ETW，并非所有玩法全闭包。
- 当前runtime没有原生signed manifest sequence／content hash启动日志。工具明确分开外部签名完整验证和真实启动marker，`native_signed_manifest_sequence_hash_log_available=false`；不把工具输出当成引擎打印。即使五文件使用均观察到，inspect也只报`FILE_USE_OBSERVED_NOT_GAMEPLAY_ACCEPTANCE`，`production_gameplay_verified/online_fps_verified/ready_for_upload`始终false。OAuth、roster、地图推进、Bane／波次／英雄／建造者／>4场景后返回、连续选择帧和真实ETW仍需独立原始证据及根审阅。正常生产会话／在线计时可能触发已有云流程，不能声称全程云写0；工具不主动领取／购买／兑换。
- restore首先确认无Dota、原item的ACF未变、keeper退出、全部old备份完整且当前五文件每一项均为本事务已知old或new，任一未知内容则**整次恢复在首次写入前拒绝**。只从备份物理复制临时文件，再CAS恢复、index最后，最后完整核3102并再次比较ACF。备份永久保留，ACF不写。随后正常官方upload／full download／新游廊实际验收仍不可省略；本工具没有任何SDK上传或发布入口。

API依据：[CreateFileW共享契约](https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-createfilew)、[RmGetList](https://learn.microsoft.com/en-us/windows/win32/api/restartmanager/nf-restartmanager-rmgetlist)、[RM_UNIQUE_PROCESS代际](https://learn.microsoft.com/en-us/windows/win32/api/restartmanager/ns-restartmanager-rm_unique_process)、[CIM微秒格式](https://learn.microsoft.com/en-us/windows/win32/wmisdk/cim-datetime)、[WaitForSingleObject](https://learn.microsoft.com/en-us/windows/win32/api/synchapi/nf-synchapi-waitforsingleobject)。仅在显式运维调用：stage／restore／inspect的hash与复制O(B)、4MiB分块的O(chunk)空间；5个FileID与RM查询O(5×64)、固定上限；keeper稳定期每2秒至多一次kernel wait、0 CIM／PowerShell／hash，无游戏帧循环、资源扫描、网络业务调用。原子共享句柄的真实兼容性和RM结果尚未在客户端验证，隔离计数不能冒充实机耗时。
