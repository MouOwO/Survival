# 2026-11-12｜数字业务回包与加密本地配置

## 任务与当前边界

用户要求先制定规则，再将业务回包改为数字ID、动态值与稀疏状态，更多静态配置放本地并加密。规则见[业务回包与本地配置规则](../../business_wire_rules.md)。下列数字来自已完成的隔离验证；后台与游廊交付状态以本文最后追加的真实回执为准，不能以Git推送代替上线。

实现源码先后提交`a37be4f1318759133bd3b8ae81e18c6f24585d79`和`7be45c5a071b55e78ed751183267324d625cc888`，game/dev已推送；content/master本轮无作者资源修改，核对到`ebe6fa24eac453b3c1ea809fd78b2c4d5129634b`。其他窗口的Steam修复、发行辅助文件和既有改动保留。

## 协议与本地表

- PWA在成功业务响应之后压缩，不修改数据库、资格、发奖、结算RPC、命令ID或幂等指纹。客户端请求头`X-Survival-Wire`精确协商schema摘要；旧客户端、旧服务、版本不匹配、失败或包变大都返回原正文。
- 固定402个字段ID、3412个公开配置ID、66个完整对象模板：40普通额度、21月卡额度、3状态、2属性类型版本。103个属性默认值来自公开CSV，不以真人存档为模板来源。数字ID只追加，已提交前缀和默认值类型严格校验。
- 仅完整对象的确定默认值可省略；解码恢复false/0/null，再交给现有完整快照逻辑。它不是增量patch，不会通过缺字段沿用旧VIP状态。未知字段和额外字段原样保留，动态库存键也可用本地配置ID。
- 同响应引用有明确遍历顺序、独立副本和深度/节点/8MiB上限，无跨请求基线。坏命令回包不重发扣费命令，沿用只读恢复；无尽批次保留原有幂等队列契约，不伪造确认。
- 本地表为真正ChaCha20密文，仅JSON数据，禁止解密后执行代码；schema规范JSON为86,723B，密文模块约174KB。公开本地读密钥不等于服务端秘密，真实性依赖发行签名；未改成“所有资源AES加密”。
- 最终schema SHA256：`e7911bcfc0a8f406393552e4de003b1b5e36923d161f827eefc636e8a99d440c`。

设计参考[Protobuf字段存在性](https://protobuf.dev/programming-guides/field_presence/)与[兼容性规则](https://protobuf.dev/programming-guides/dos-donts/)，密码向量参考[RFC8439 §2.4.2](https://www.rfc-editor.org/rfc/rfc8439#section-2.4.2)。没有适用于所有游戏的统一HTTP字节标准；本文工程预算不冒充行业认证。

## 真实业务字节与验证

树外工作根：`D:/Survival_本地工具/runs/business_wire_20261112_01`。冻结当前WS4公开代码/配置与结构，未复制玩家行。第一轮与追加属性本地模板后的第二轮均为新建PostgreSQL容器、两个合成身份、31次真实HTTP；实际API/SQL/Lua执行，结束后测试API正常退出、数据库停止。没有使用真实兑换码、账号、券或支付。

第二轮`7ab3eef54643d4d3dd1dec34c4b93428`使用已提交`7be45c5a…`，配置摘要如上，真实后端来源为既有`20261111-ws4-ur1-fifty-1497a268db9d`。无尽32条批次及十连沿相同操作ID显式重读，回执和持久状态一致，未重复扣券或加奖。

| 路径/场景 | 旧完整JSON表示 | 本轮真实紧凑正文 | 备注 |
| --- | ---: | ---: | --- |
| 初始分钟结算，pure/standard | 40,806 / 41,109B | 2,365 / 2,373B | 约减少94.2% |
| 抽奖及无尽后结算，本轮最大 | 42,807B | 4,160B | 状态增长仍需考虑 |
| 福利写回，pure/standard | 13,462 / 10,166B | 2,320 / 2,156B | 原有profile引用先后语义保持 |
| 现有紧凑十连 | 18,930B | 6,317B | 没有拿旧124KB路径充当当前基线 |
| 32波无尽批次 | 45,877B | 6,959B | 取代前轮仅36KB假设 |
| 目录MD5命中 | 158B | 158B | 小回包不被新envelope撑大 |
| 完整目录失配 | 102,435B | 102,435B | 保留已有MD5/本地seed和完整同步退路 |
| 旧式整池snapshot | 76,965B | 36,406B | 仍较大，不能声称所有业务都低于4KB |

旧大小由同一紧凑回包精确重建后的紧凑UTF-8 JSON计算；逐值/类型校验通过，不是公网TLS抓包。无协商的十连和批次同操作重读实际仍返回原JSON，验证旧客户端退路。没有启用gzip或降低结算频率。

1462项Python断言、额外536项独立模板类型/属性变更检查、111项Lua协议/适配器边界及既有3组相关回归通过；最终真实29个非认证正文逐个用实际密文表Lua解码，与完整正文比较通过。2000库存键的纯wire增长例80,681→26,050B，仅验证增长/无损，不是真实老账号或数据库容量样本。认证/支付边界77项通过。发布绑定34项不可变Git重放/篡改反例及3×22模板输出编译通过。

本地Lua5.1纯位运算fallback冷载入约288～291ms，只在require初始化执行一次；第二轮29回包的Lua解码合计CPU约69ms。两者均非Dota原生FPS。服务器实采重编码CPU约6～23ms/次，本轮共享2核主机上观察，不可用本地合成6.76ms中位数承诺生产容量。新增SQL/网络调用为0，CPU成本仍须纳入压测。

复杂度：静态索引初始化O(S)，空闲与请求头读摘要O(1)，每响应O(B+ΣKlogK)预期时间/O(B+N)空间；模板trie最多4个值选择和1个类型选择，当前所有模板实测最多2次值索引。没有每帧扫描、计时器、4000账号全遍历或重复解密。

## 交付保护

新family加入精确不可变生成绑定：收集与签名前分别执行已提交生成器，利用已提交公开key/nonce真正重加密，逐字节核对完整Lua，绑定schema/catalog/loader及operator完整readset。保留原保护、签名、三类语义门禁及未知路径阻断，不改旧冻结family。

独立PWA工具`tools/business_wire_deploy.py`以现役8份Python文件为父，保留`game_diagnostics`和现役`service.py`原字节；只覆盖本轮HTTP适配，新增codec/schema。Inactive预检、父unit/PID/源码CAS、仅web服务切换、私有备份与受保护回滚；不改环境、SQLite会话、支付或数据库。首次只读plan发现unit合法前导空格与严格解析不符，未切换服务；已补兼容并验证只改单行值，不能把这次拒绝写为后台上线。

候选、生成、备份、隔离采集与交付回执保留在树外；登记结果及最终交付事实后续追加，不删除失败或旧版证据。

## 1201签包与首次后台回滚

1201任务`pack_2026111201_238c2c6c`已完成完整保护、签名及整包核验，7061资源、187保护模块，尚未上传。构建固定game/dev `3b5ed0c75fb1e1f325aa98aad5ca47c62a3e115d`、content/master `779cdbd1b85fb255e9433b07c9a3e0488ede30e0`。当前正式游廊仍1106 / manifest `6291919402900133473`；1201不是已上线版本。

首次后台候选已通过inactive导入与真实编解码自检，但激活返回`ACTIVATION_FAILED / rolled_back=true`。保留`web_release/deploy_plan.json`及`activate_390f647e14c4390e_receipt.json`，计划SHA256 `0f2a6ec183d433e6496badf37d374da6a741f9204dc5629e5a499e594c29400a`。旧工具未记录失败检查码，不能补写为已确定的某个线上异常。

暂停后用户要求继续；只读复核确认父unit、环境摘要、8份源码和其余7个服务PID/状态均未变化，旧版web正常运行。实际unit为`Type=simple`，失败窗口日志仅两次正常start/stop，没有采到启动异常。实际`verify_active`替身复现新PID尚未chdir时立刻失败、health等待调用0；因此修复这个可证实的验收竞态，但不将其写成本次唯一根因。

部署工具现用12秒单调截止时间统一等待新PID、候选cwd和health，健康成功后重读PID/cwd，并复核unit、环境、保留服务和源文件；超时最多49轮、O(1)状态，每轮最多2次服务属性读取、2次cwd读取、1次回环health，无玩家或SQL调用。此轮询只发生在显式部署/回滚，不进入游戏或稳定服务刷新。回滚也核对父cwd与health。失败回执新增固定阶段/错误码及标量就绪状态，保留旧pending，不输出unit、环境或原始错误文字。另外固定ledger子进程UTF-8，避免Windows中文树外路径回执解析失败。新工具提交后必须创建独立新计划；不会重放旧pending。

回滚写入前另核环境与旧父8份源码摘要；发现并行修改则保留pending并停止回切。每次服务/health子调用均使用剩余时间预算，成功返回前重验截止时间。进程检查的准确范围是health前后同PID、同cwd，不声称绑定了进程启动代际。

树外`tests/business_wire_20261112/test_web_deploy_readiness.py`执行原12项边界及15项新回归共27项通过，覆盖延迟PID/cwd/health、health期间换PID、短时缺失proc、永久错误cwd、健康与子进程超时、跨过deadline不得成功、错误字段脱敏、UTF-8子进程，以及环境/旧源变化禁止回滚写入；不将替身测试称为线上激活成功。

## 4000在线的更新后流量预算

按本轮较大正文取结算4160B、命令6317B、profile4083B、目录命中158B、32波批次6959B。普通场景分别为66.67、66.67、13.33、33.33请求/秒，共180RPS；活跃高峰将命令提高至200、profile提高至66.67，共366.67RPS。极端场景在活跃高峰基础上再叠加800批次/秒，共1166.67RPS。这些是显式假设，不是观测到4000真人行为。

出口预算公式为`(Σ正文B×RPS + 总RPS×2048B)×1.10×8/1000000`，额外2048B/请求及10%作为头部/传输余量。结果普通约9.92Mbps、活跃约22.61Mbps、极端叠加约86.02Mbps。仅每天4小时、每月30天的峰段对应约535/1221/4645GB；低峰、重试和其他业务另加，不作为云账单或购买承诺。完整目录失配、2000库存键增长案例仍可能超出所用正文大小；未启用gzip。

当前共享2核与已有全局限流、认证存储不因包体变小就获得4000并发准入。需要后续分级容量压测来验证CPU、数据库、延迟及失败率；本轮只完成两个合成身份的真实业务功能验证。

## 1202签包、后台上线及Steam连接门禁

部署修复`a2645e38292ec0ebb08281899d952d9f42c375f9`已推送game/dev，content/master同期核对同步。按固定入口重新建立`pack_2026111202_27b5573e`，保留旧1201。1202已完成7061资源、187保护模块、完整签名和整包核验；运行来源game `b842a8d6509e36088507cdde83927ac9259d453a` / content `342bb10f6035918e83a0ba9d17d0d8626e235b3d`，均已推送。发布授权提交game `2499d16aefe3dd160a7053d26cea74f00ce73cd7`。

新后台计划`web_release_v2/deploy_plan.json` SHA256 `4e1435fdd1583b81731d2a93868f18a96c6af13eb420d5ffd6ce760cbc83264c`，候选`/opt/goufayu-ws4-web/releases/business-wire-195f682a8fbf89673c29d131d16dae7b1c797dbfa4d9815934f2cbfe47f1e3bd`已激活，进程1364654。`activate_1bcabeaed7c6ba59_receipt.json`和独立`verify_40cc66b9352ebc8f_receipt.json`均`ACTIVE_VERIFIED`；首次就绪2轮、复验1轮，环境及其他7服务未变。候选实际selftest 4769→472B，生产账号业务请求0；真实业务无损证明沿用隔离31请求/29正文，普通客户端仍待用户实测。

1202首次publish在`sdk.Steam.__enter__`在线身份检查处拒绝，`publish_1.execution_receipt.json`/stdout/stderr完整保留；账号及AppID均正确，单独只读探针确认`BLoggedOn=false`、UGC写调用0。正式journal仍1106，lineage保留1202原始pending，未清除、重放或改写成成功。用户确认Steam已在线后，独立协调查询仍在同一只读初始化门禁停止；Steam连接日志仅按状态分类读取，观察到连接超时。已请求完全重启并恢复网络，后续必须新鲜官方查询确认1106父包未变化，再在全局锁内显式协调已知上传前失败，之后才可继续同包发布。当前游廊仍1106 / manifest `6291919402900133473`，1202没有SDK成功或官方下载证据。

本轮Git原配置指向已关闭本地代理；直连GitHub实际成功，后续仅在本轮命令进程覆盖http/https proxy为空，未修改永久配置。本轮stash `8390149d87cbbc7288927230358b0f712ea687b4`已精确pop；其他窗口的Steam桥接修复、README、bundle指针、pycache及5项发行辅助未跟踪文件均保留，content工作区干净。待交付结束再提交本节收口文档，避免改变1202任务严格HEAD绑定。

## 最终交付：已同步游廊1202，后台已部署

截至2026-11-12 17:45，固定任务`pack_2026111202_27b5573e`返回`WORKSHOP_SYNCED`，原条目3824360109、Steam manifest **`503273922170155206`**。7061签名资源、187保护模块、5个包文件官方完整下载逐文件一致，发行generation 13、pending为空；完整来源检查点已收口，待发和阻断均0。运行来源仍为game `b842a8d6509e36088507cdde83927ac9259d453a` / content `342bb10f6035918e83a0ba9d17d0d8626e235b3d`，发布operator `2499d16aefe3dd160a7053d26cea74f00ce73cd7`。收口文档另行提交，不改已发运行绑定。游廊维持封闭测试可见性3，普通实机验收`PENDING_USER_ONLINE_TEST`；本轮没有真人券、兑换或支付操作，4000并发容量尚未测试。

正式官方回执：`output/packager/pack_2026111202_27b5573e/download_evidence/20261112T094401Z_015ae09ac45d42d884be2f6ce136b3d1/verification.json`，SHA256 `39781ec29bfb629f999f0d1c0ef598bc37dba0fef864929b6f66bc4ec3f9f59e`。任务交付回执：`D:/Survival_本地工具/runs/packaging_jobs/pack_2026111202_27b5573e/delivery_receipt.json`。后台仍为上节已独立验证的`business-wire-195f682a…`及schema `e7911bcf…`，没有再次切换数据库、支付或环境。

### Steam连接恢复及已知失败协调

官方商店、社区和两个客户端节点的DNS/TLS探针均通过，但客户端SDK仍离线。确认RunningAppID=0且无Dota后，正常退出Steam PID19468，临时以`-tcp -silent`重启为PID18840；随后SDK真实在线检查及无缓存官方查询成功。未强制结束进程、清除登录资料或改永久网络配置；不能据此断言UDP是唯一原因。[Steam官方TCP启动参数说明](https://help.steampowered.com/en/faqs/view/0188-6BB7-D467-08E1)。已有OpenID桥接器只处理社区验签，未把桥接READY误当客户端在线。

当时官方1106条目更新时间从1794405279变为1794405668，大小3811766367及可见性3相同，因此协调v3拒绝旧时间参照，未清意图。先用当前正式recipe的`baseline(full=True,require_current_journal=True)`及固定下载协议重新核验完整父包；新回执确认manifest仍`6291919402900133473`、7058资源和5文件字节全部一致。旧recipe独立重跑因当前保护policy已升级而拒绝，未改旧门禁；该失败脚本一并保留。

树外`pre_sdk_reconciliation/reconcile_pre_sdk_failure_v4.py`固定新旧官方回执和refresh helper摘要，review与apply各独立执行非缓存官方查询，精确核对owner/AppID/条目、完整新鲜父包结果和当前控制摘要。在同一全局锁内先保存lineage/journal原字节并登记备份，写前CAS，再仅恢复已证明未到SDK写调用的pending；generation/head/journal保持。最终review SHA `0d74c9595fb58f37762e8028743b952eb0ed7325c21f51e1ad8069101d3f7b66`，协调operator SHA `af931e64191d5daad281cd3e4cbdb0c08cb59b7248f489b711233500d93aa9a6`；已知失败、备份、登记及应用回执均保留。不能将此方法用于SDK提交结果未知的情况。实际query的成功、缓存结果、多结果、错误owner与AppID共5项替身检查通过。

### 签包后文档审计漂移及修正

第二次publish在SDK调用前拒绝`reviewed_projection_differs_from_fresh_collection`。逐字段诊断确认运行绑定一致，但签包后追加的本篇与知识库README使dirty清单多出两个非运行路径，改变inventory/scope/ledger摘要。完整保留诊断和两文档原字节备份并登记，再把本人后续文档修改推迟到树外，主工作区恢复已签提交的原文；未改其他窗口文件或放宽collector检查。新鲜投影随后逐字节等于原签包投影，SHA256 `3b86dfcaf3d9b33d8529492ac75c3810dd238219d8d18484e508a8787837bdea`，第三次固定publish完成唯一一次实际SDK上传，之后官方下载及全部待发收口成功。两文档在任务done后才合回并记录最终事实。

本轮3次publish入口的结果分别是SDK初始化在线门禁失败、来源投影审计失败、成功提交；前两次没有实际UGC发布。未自动重传未知提交、伪造普通实机通过或删掉失败意图证据。后续从签包审计冻结到交付完成，文档也先放树外候选，完整交付后再合入，避免重复这一错误。
