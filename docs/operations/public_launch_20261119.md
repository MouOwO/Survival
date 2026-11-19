# 2026-11-19 正式公开上线切换

状态：1910已同步原游廊并永久公开，manifest2486294026793872721；后台公开准入和保留已支付余额/权益的玩法清档已完成，最终只读完整验收WORKSHOP_SYNCED，运行待发/阻断0。11月20日配套登录器修正为2026.11.20.1，用户确认授权入局，同一进程画面及云档案/会话回包已核对；余额权益界面、跨局重载及3000并发仍待验，见[后续修复与完整入局证据](launcher_restart_repair_20261120.md)。

用户已确认“伐木工问题已解决，现在可以直接上线了”，作为本轮正式公开上线指令，替代此前仅不列出的测试范围。此前计划11月20日开放；本轮按用户最新“现在”准备立即开放，不建立未经请求的定时任务。现有介绍、下载页中“内测、仅获准账号、计划11月20日”的文字须在真正开放时一致更新，继续不写付费宣传，QQ1098603739。

用户对实际查到的一笔已完成支付明确选择：“保留已支付余额和权益，仅重置玩法进度”。支付账单、支付标识及充值历史保留；不能调用会删除订单的旧全账号清理工具，也不能用全库清空代替进度重置。准备完整备份、精确保留/重置字段和隔离恢复/回滚验证后才切换。当前旧对局须在正式安装与存档切换前正常结束，防止旧内存回写。

## 本轮实际观察

树外工作根 `D:/Survival_本地工具/runs/public_launch_20261119`。

- `preflight01/preflight_receipt.json` 为只读检查：正式WS4有5个身份、4份存档、5份属性、26条奖励、4次兑换领取、32个历史对局会话；支付共5单，其中4 closed、1 delivered，无未结单。API18765和web18767 health均200。没有修改任何账号行。
- 实际API为 `/opt/goufayu-ws4/releases/20261111-ws4-ur1-fifty-1497a268db9d/backend`，web为现役business-wire版本。两侧都只允许5账号，没有公开准入环境开关；Steam验签仍经开发机中转，web的 `ISOLATED_LOCAL_PROGRESS=1`。不得把一次入局写成独立云端验签、可信专服战果或3000在线通过。
- `source_before/source_backup_receipt.json` 已逐文件备份8份相关源码并登记到账本。原有8项用户改动继续保留，不混入上线提交。
- 公开准入源码新增显式模式，默认仍私测；合法原生Steam身份、Steam验签、同账号/同对局、CSRF、重放与期限约束保留。新模式不是关闭认证。正式服务与安装尚未切换。
- `admission_tests02`：42项网页登录/公开身份测试、新生产Lua1024断言，以及旧五账号514、换图7682、名单475、探针697断言通过。另有树外新公开换图/名单测试，用实际core policy验证第六身份和uint32上界、严格本局名单、私测拒绝；无真实HTTP/游戏调用。单次初始化遍历最多5个回退账号，稳定身份检查O(1)，1000次检查无重复名单遍历；web使用最长10/17位十进制身份解析，不建立无限账号缓存。
- 初次新增网页登录测试仅预期错误码写错，实际拒绝为 `player_session_identity_mismatch`；修正测试后42项全部通过，失败记录保留。`data_scope02` 只读查询误假设quantity列，事务只读失败，未改数据；`data_scope03`改读现役结构后完成。真实源分析保存在树外，不进入Git或知识库原始玩家数据。

## 待完成

公开生产转换及来源门禁、双仓提交与推送、签包与完整官方下载；后台公开身份初始化与进度重置的字段审计/备份/隔离验证/实际切换；新版本登录器与公开介绍；最后由统一发行lease执行原条目永久公开并官方回读。普通内测包上传器仍只授权不列出，不能借临时10分钟可见性实验或裸SDK写入绕过正式公开门禁。真实支付不由代理代付，价格与支付通道不因本轮准入调整改变。

## 保留规则与验证补充

- 新工具 `tools/public_launch/progress_reset.py` 保留全部当前货币余额（包括充值货币、U币钱包、星悦余额及已获得计数）、实际已付永久物品与属性权益、已付VIP及充值累计、限时权益原始到期时间、金融账单、充值入账历史及恢复备份。排行榜身份映射属于身份，也保留；排行榜成绩、关卡、成长、奖励和兑换领取等玩法进度重置。旧测试重置权限关闭。当前已审阅的已付产品为伐木斧永久权益；若出现新产品订单则阻断复核，不能猜测消耗品如何恢复。
- `postgres_lab07/sql_test_receipt.json`：真实PostgreSQL、与现役完全相同的结构和103项初始默认值，2个合成账号通过10项检查；完整事务回滚及不可变触发器恢复、共享兑换名额释放、支付余额/道具/VIP/账单保留、初始进度、全量dump恢复后指纹完全一致。正式行写入0、真实玩家行复制0、应用源码上传0。独立容器已正常停止，数据和失败尝试保留。
- 初轮实验遇到Podman裸镜像ID、public初始schema及合成标识约束不匹配，均发生在隔离库。真实演练发现archive插入会自动生成排行榜身份行，现将不属于玩法的身份映射纳入保留，并验证逐行摘要不变。未对正式库执行试错。
- 支付HTTP服务另有4账号门禁；公开模式仅限隔离WS4命名空间，旧非WS4配置不能启用。5项新支付准入及59项原有支付检查通过，没有下单或扣款。
- `launcher_projection_tests01`：8项公开助手/适配器检查、9项原助手、12项原登录器、42项网页登录及8项纯保留规则通过。公开助手仍仅访问固定HTTPS路由，凭据别名仍绑定账号/对局；私测默认模式仍拒绝陌生账号。
- 新发行适配器只处理新生成family，绑定已审阅core policy及严格的5账号回退配置语法；原四个生产常量、签名、保护、地图及源证明门禁保留。已通过8项生产投影检查及新增适配器异常恢复/配置篡改拒绝检查。源码公开开关现已置true，但尚未编包、安装或上线。
- `tools/public_launch/backend_candidate.py` 从已提交源码生成5文件精确补丁，再投影到只读现役快照，保留其他线上差异；不传输密钥、不自行上传或切服务。实际web有SQLite索引差异、支付有已关闭的旧重置路径，不能直接用主仓全文件覆盖。
- 新永久公开入口为统一 `release_pipeline.py public-launch`，使用同一全局lease，仅能改变原条目可见性。要求官方完整新包、完整待发0、后台公开/保留式清档证明、匹配EXE实机及公开HTTPS证明、双语言正式介绍均就绪。临时10分钟实验不能代用。上线后旧不列出包上传路径会在写意图前明确拒绝，避免后续误降回不列出；后续公开更新需配套公开发行配方。
- 自动审批曾拒绝上传包含内部应用源码的隔离测试包，理由是外传范围未明确；改为本机隔离venv与独立SQL实验后完成测试，未换通道执行被拒的源码测试包。实际后台部署包须先具体生成审阅，再按现役47.111.16.128目标授权处理；如仍被拒须单独说明并请求用户对该具体包的授权。

当前线上仍为1907不列出/5账号、v2登录器和原测试数据。正式维护、清档、公开开关、新游廊包、新EXE及永久公开均未执行，不得宣称上线完成。

`public_lease_tests02`新增7项永久公开门禁通过；原lineage18项、临时公开8项回归通过。初轮新fixture因未mock合成Git来源而失败，修正fixture后通过，原失败保留。`production_projection_tests02`以最终公开配置重验8项通过。相关源码备份与9份验证回执已登记，见树外ledger_registration01。正式Dota PID16940仍在运行，已按AGENTS请求用户正常退出，未强制关闭。


## 已提交与已暂存（尚未切换）

- game/dev `3e21e38528793694993e1591745215c602cebb41` 已push；content/master `03195789d4dca2798fd1e364f748bff924297868` 已核对push一致，无空提交。固定stash→pull→pop→commit→push已执行，原8项用户改动逐字保留。
- 5文件后台候选112640字节，SHA256 `aae340af8bcde223df5f00641819b5bc94c5374d3807417cf0e3c21a3647ac0e`，manifest `25f827601a30bd61ab35ac4a3fb6d0040989b90220a1a31ad88883e901025b4c`；已登记。用户先前明确迁移全部后台到本机并授权本轮上线，具体非密钥生产补丁的暂存通过审批；先前被拒的隔离测试源码包没有上传。
- `backend_stage01/stage_receipt.json`：候选已暂存 `/root/goufayu_upload/public_launch/candidate_3e21e385_03628864b0`；5份源字节、现役父文件及Python语法全部验证。没有改服务、支付配置或数据库。
- 已建立不可变双仓来源任务 `pack_2026111908_c7aef399`，版本1908，runtime game绑定3e21e385、content03195789。状态created，尚未构建/安装/上传；Dota仍运行，按固定打包工具的require_idle等待正常退出，未绕过。
- 维护编排 `tools/public_launch/maintenance.py` prepare只生成独立硬链接副本和未激活服务片段，替换源码使用新inode，禁止写穿父硬链接；父发行继续保留。apply要求精确prepare摘要和用户确认正常退出的独立回执，先停写、完整备份、事务清档，再激活服务。
- `maintenance_tests02`六种隔离故障注入通过：正常切换、COMMIT回执丢失但已成功只读确认、未知事务保持停写、清档异常回滚、提交后启动失败只恢复服务、缺少正常退出不能停服。这里的服务/SQL为模拟，真实金融保留另由postgres_lab07证明。首次fixture缺少服务片段并暴露SQLite连接未显式关闭，已补齐fixture并在生产工具中显式关闭连接，失败证据保留。
- 一次维护最多5账号，逐账号扫描已审阅35表、每账号最多10万行/100MB的既有安全预算；103初始属性只在本次状态重建时校验。正常运行无后台扫描、轮询或新增游戏帧工作。健康验证最多30次固定回环请求，仅在切换时执行；公开身份稳定校验O(1)，名单初始化最多5项。上述上限和fixture计数属于代码/模拟成本，不能写成原生FPS或3000并发验收。

维护operator已提交047f9f55并push双仓；`maintenance_candidate01`的92160字节正式维护输入（不含测试脚本/密钥/玩家数据）已暂存。三个独立后台candidate已创建，使用实际服务解释器导入成功，prepared SHA `9df2276368195ca43a86aaf60eda2d7983168d381fdba0aef2ece1e76d525c7a`。当前服务和数据库均未切换。后续编译/operator提交可改变game提交号，公开门禁对此要求已部署提交为祖先且5份后台源逐字节相同，不用相同标签冒充相同源码；已验证同字节通过/旧后台字节拒绝。

## 保留的用户原有8项改动

本轮提交没有包含以下game工作区文件：

- `docs/knowledge_base/00_START_HERE.md`
- `docs/knowledge_base/evidence/ice_cone_hail_20261113.md`
- `server/archive_backend/__pycache__/match_modes.cpython-314.pyc`
- `server/bundles/current.json`
- `server/player_web_auth/README.txt`
- `tools/monster_portrait_release_20261030/finalize_package.py`
- `tools/monster_portrait_release_20261030/verify_download.py`
- `tools/prepare_delivery_operator_20261103.py`

content/master无未提交改动。财务与正常退出的用户回答、真实发行/应用回执继续作为实际切换依据；本记录不代替服务激活、官方完整下载或新EXE入局验收。


最终界面核对发现game/content两份授权UI仍写“独立测试存档”，已配套改为“云存档”，仅一条文字，Node语法及双份源码一致性通过；对应JS官方编译仍待，不能把旧编译资源当成交付。此前1908任务在构建前建立，UI补充改变运行指纹，后续须新建来源绑定任务并在1908状态中标注替代关系，保留原job.json；实际任务以树外package_job.json为准，不改旧不可变源。

`final_preparation_checks01` 的旧1907 full pending检查返回 `reviewed_projection_differs_from_fresh_collection`，退出2，未生成“完整待发0”证明。原7项公开lease复验通过。新候选必须完成新的全量收集/审计，不能修改旧投影或直接复用旧通过回执。当前正式版本仍1907、不列出、5账号；未清档、未停服、未换正式包。


## 正常退出后实际构建

用户在call_a27e5da355874e8a989aecaefa4707b9确认“我会正常退出，继续上线”。本机已检查Dota进程0，旧v2状态为game_exited_helper_cleaned；真实退出回执见树外client_exit01。1909开始后两项官方编译已通过，生产导出发生Git进程等待超时，尚未签包或改正式数据。

archive_pipe_diagnostic01实测相同17f1efbb不可变提交：Git正常导出21975040字节/1306个tar成员只需0.145秒，tar读取器留下10240字节全0结束填充，超过Windows管道容量。旧代码先wait而未排空，导致实际30秒超时。只为新family在结束处先communicate排空再检查退出码；保留所有blob OID、路径/大小、名单与总预算。archive_export_fix_tests01真实导出1283个Lua并全部OID一致，约0.614秒；3种非零/超长尾部及超量stderr负例拒绝。旧1909family、失败源码导出和编译证据保留，不改旧回执。


## 1910真实同步与清档后的服务恢复

1910完整候选已同步原游廊（仍不列出），manifest `2486294026793872721`，content SHA `fe49da8d6b64603726786fd56e0557de2c2540aa7e0d22a6997dc130027abe36`；5包3812492764字节、完整新下载和新全量待发0均通过。1907旧投影的fresh检查失败没有被重写；新候选从头收集后已正常收口。签包source game205e3837/content34a43d74，最终推送以任务git回执为准。

1910匹配EXE2026.11.19.3已构建并自检公开模式，13179037字节，SHA `fe7b2c119cd0f8a37a40039d065ce88fc75e98f15dacbf09bec5e371b9bd8054`。安装至独立v3目录，旧版本保留，尚未新实机入局/发布下载。

自动审批拒绝完整生产PostgreSQL和授权SQLite导出本机，理由是可能含玩家、支付和认证数据、未取得具体目的地导出授权；命令未执行，没有绕行导出。改为同一服务器root私有目录完整备份，server_private_backup01已确认dump1370169字节与auth98304字节、摘要与目录表可读；全部数据留在服务器。正式维护还单独在事务前生成完整备份。

backend_activation01：实际5账号玩法重置已提交，保留校验全部通过；after fingerprint `b5ba021398a775aefa6e9802f52100474055cf75aae8d8a96f5729c15a410e7b`。随后服务健康校验失败，维护工具明确记录commit_known/reset_committed为true并仅恢复原服务；不能重跑清档或还原旧金融库。当前支付订单/余额/权益仍保留，后续只激活服务。

activation_failure_readonly02定位支付服务为200/CHDIR：copytree复制了目录0750模式但未复制原服务用户属主，root创建的新目录不允许服务用户进入。另只读核对发现支付runtime_binding严格要求原`/etc/goufayu-ws4-payment/config.json`，候选私有配置文件名只能用于暂存；激活须保持该固定路径，不能放宽命名空间门禁。新增activate.py只做目录元数据恢复、固定配置路径单字段准入更新及服务选择；SQL始终READ ONLY核对原清档计划，源码没有再次清档调用。6项合成检查验证目录恢复不碰硬链接文件、原配置价格/密钥/namespace不变及旧公开状态不能重放。实际恢复结果仍待执行。


## 激活恢复与实际v3正式游廊验证

88c4d5ff提交的activate.py已在服务器执行成功：API/web/payment全部public准入，3项健康和实际cwd/配置再次验证，支付继续使用固定WS4_CONFIG。恢复遍历API166/web3/payment434个目录，仅支付233个目录恢复原属主；硬链接文件写入0。原5账号余额、已付库存、限时权益、订单/入账账本再次逐摘要核对一致，gameplay_reset_repeated=false。正式清档只执行一次；私有备份和真实失败事务均保留，原旧服务/候选仍保留依赖。

实际v3 GUI PID32088，Dota PID23176/Filetime134395691888883251；真实5包全SHA启动校验通过，单次启动进程快照1、初始PID身份读1、窗口事件1。已更新3个桌面入口，旧EXE保留。Dota存在一个可见但零尺寸代理窗口，不能用其GetWindowRect当真实游戏窗口；另一个实际可见窗口7735192已按同PID确认，临时UI入口额外绑定进程创建时间且不抢其他应用焦点。

已从正式Dota游廊的已订阅库选择原游戏、默认ws4_entry创建房间，作弊未开、没有邀请或发送聊天。首轮就绪确认超时被移出队列，重新创建并即时接受后正常加载，未称其为游戏崩溃。游戏标注使用玩家电脑主机；没有宣称Valve专服恢复。Native item_state=5，needs_update=false，安装与详情manifest均2486294026793872721；因此没有触碰详情页看似“更新”的按钮或改动运行包。

本次新助手已出现真实HTTP200响应（至少10条），当前有效授权码已在实际游戏显示，正式UI底部已是“云存档”；此时只完成auth start/poll，不能冒充已完成Steam批准、档案加载或存档成功。本人Steam授权仍在等用户完成，已打开本局网页登录。actual_v3_ready01中的live授权图已加私有ACL，原始认证/session凭据不加入Git。

本轮上线指令已明确授权立即公开，不能把额外的本人Steam点击确认误当成新的公开授权要求。发行工具增加明确的AUTHORIZATION_READY证据阶段：绑定真实冷启动EXE、5包完整SHA、实际游戏进程/创建时间、有效授权码画面，以及同一epoch的请求/HTTP200/游戏ACK交集；不冒称已完成本人Steam授权或加载档案。authorization_ready_evidence01实际观察start 3次、poll 320次均200且已ACK，读取上限16MiB，一次性离线O(B+R)分析，无游戏循环或新增网络调用。10项验证通过，错误版本、错误进程、截图摘要变化、伪本人确认和缺少start ACK均拒绝。公开下载与可见性发布可使用这个真实阶段，post_authorization_gameplay_verified和user_confirmed_entered_game明确为false；本人后续入局、余额/权益显示仍保留待验。

两语言正式介绍已从Steam新鲜回读一致，下载链接及QQ1098603739正确，无收费描述。v3下载页候选已生成，旧公开v2首页SHA仍1ac9e006...；没有用虚假的EXE验收记录提前发布v3。最终公开提交另绑定正式开放更新说明，避免最新更新页继续只显示历史Restricted four-account test说明；这只是新元数据说明，不改历史回执或旧更新记录。

## 最终公开与完整验收

download_publication03已在原静态站点发布2026.11.19.3，旧首页按CAS摘要备份、旧版本保留。download_https03从公网直接HTTPS完整读取6项文件，共26180698字节，EXE/ZIP/说明/版本/摘要/首页均匹配，TLS校验开启，未使用环境代理。稳定入口https://xiaofengnet.com/launcher/。

public_visibility01通过release_pipeline.py public-launch同一全局lease正式公开原条目3824360109；SDK结果1、legal=false，双语言新鲜回读visibility=0，标题、介绍与5包内容保持。新提交说明为正式开放及专用登录器提示，QQ群1098603739，无付费宣传。公开回执SHA5849cffa6a911795103e55c3534317374d0837bfcd5c4013d17045d140af5489，lineage generation40/pending=null。正式后台API、web、payment最终均/health 200/ok=true。

final_delivery01旧命令先因Windows LF检出形成3个非运行dirty记录而拒绝；只恢复原CRLF检出形式后，final_delivery02继续明确拒绝complete_baseline_pending_or_changed_generation。原因是旧检查把包发行generation38固定为当前代际，而正式英文介绍和公开可见性分别通过合法lease推进39/40；canonical包journal和签名资源没有变化。两份失败与projection_diagnostic01均保留，没有把旧命令标成通过或重写检查点。

树外一次性verify_public_delivery_20261119.py完成独立只读最终审核，final_public_audit01真实返回WORKSHOP_SYNCED：验证两次元数据请求/SDK回执/前后保护字段和38→39→40连续代际；3个错误代际/未收口/摘要负例拒绝。调用原builder.load_package(full=True)复验全部源码、原编译证据、签名树及VPK，使用原advance逻辑重现原不可变完整源码检查点；再次流式SHA核对实际官方安装5文件3812492764字节。随后使用原完整分类器重新索引当前双仓，pending/dirty_runtime/blocking/pending_resources均0，原有dirty_total8原样保留；原delivery_status使用这份真实完整清单返回WORKSHOP_SYNCED。最后再向Steam新鲜查询两语言公开状态、保护字段和介绍，并核对journal/lineage操作期间未变。后台数据库、安装包、SDK修改次数均0。旧通用delivery-status的代际限制仍保留，后续应使用明确的元数据连续性审核，不能简单放宽generation。

旧英文verification.json本身缺少存储绑定，ledger_registration04如实记录首次登记拒绝；新增verification_storage_receipt.json只登记本次观察，引用原路径和原始SHA，原件保持。其余本轮真实回执均登记到树外清理账本，失败记录和备份继续保留。

验收边界：本轮新EXE达到有效授权码且start/poll真实200/ACK，尚未取得本人Steam确认后的新游戏档案画面；未自动购买、兑换或消耗福利。3000同时在线未验收，Steam官方验签仍依赖现有中转，ISOLATED_LOCAL_PROGRESS=1仍限制不可信主机进度进入公共排名。公开不代表这些范围已通过。
