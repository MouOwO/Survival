# v02 生产排演准入与官方更新适配

本轮操作代码独立于冻结的048运行提交、13路径／3编译绑定、builder／checks、旧README、AUX和f484计划。仅用已有用户授权：同签名候选普通客户端所测画面、帧率与稳定性通过，完成3102恢复后，更新原3824360109条目；四账号、Unlisted、d573及不领取／购买／兑换保持。工具不会签名、启动游戏、审批OAuth或生成假通过证明。

`publish_v02.py` 无参数只打印静态计划。`--preflight`完整核签名包与实际证据，0 SDK、0更新；`--apply`重新执行全部准入，才调用既有`sdk.publish(...update_existing=True)`和原canonical journal。3102当前journal须与本次signed package记录的canonical SHA完全相同，保留previous_release及全部19条history；未知／pending状态直接拒绝，不清历史、不换journal、不自动重试。若同1102已成功记录，拒绝重复apply，转官方下载。旧v01的DEVELOPMENT准入及`APPROVED_CLOSURE_REVIEW_SHA=None`保持原样，本适配不调用其development/native/apply函数，只复用私有实例的纯证据／CSV／journal校验。

```powershell
python tools/arcade_portrait_release_v02_20261101/publish_v02.py
python tools/arcade_portrait_release_v02_20261101/publish_v02.py --preflight --report-sha256 <SIGNED_PACKAGE_REPORT_SHA> --review <ROOT_REVIEW_JSON> --reviewed-evidence-sha256 <ROOT_REVIEW_SHA>
# 仅在根审阅同一JSON原始证据后执行，同一参数改为--apply。
```

Root实际审阅JSON的固定顶层合同（下列是字段说明，不能直接当通过报告使用）：

| 字段 | 实际值／要求 |
| --- | --- |
| schema/kind/status | 1 / `LOCAL_SIGNED_CANDIDATE_PRODUCTION_REVIEW` / `ROOT_REVIEWED_TESTED_PATHS_PASS` |
| scope | `SAME_SIGNED_CANDIDATE_OBSERVED_FOR_TESTED_PATHS` |
| synthetic | false，必须是真实普通客户端 |
| release_sequence/source_revision | 2026110102 / `048a2d6b675325cd511abb01c5a122343052b2f7` |
| content_sha256/package_report_sha256 | 真实signed package对应值；运行资源6918／保护模块184／精确13路径 |
| runtime_paths | `sorted(build_release.PAYLOADS)`，不是开发12文件证明 |
| tools/offline_logic_test/cheats/http_enabled | false / false / false / true |
| official_download/all_gameplay_paths_verified | false / false，排演不宣称官方下载或全部玩法闭包 |
| process | 原`process.json`中的pid、created_utc、native_created_filetime；需与排演同代际 |
| root_review | 以下9项由root核对实际证据后为true |

`root_review`九项：`production_entry_roster_oauth_reviewed`、`normal_oauth_approved`、`no_synthetic_profile`、`no_business_claim_buy_redeem`、`no_runtime_script_injection`、`no_crash_or_hang`、`normal_exit_without_force`、`keeper_held_continuously_reviewed`、`no_observer_hashing_during_etw`。正常会话／在线时间可触发原有云流程，不把这些字段解释为云写0。

所有文件引用格式均为`{"path":"实际文件路径","sha256":"实际SHA256"}`；结构化证据最多8MiB、单文件最多512MiB。证据只可位于本项目private output或固定外部rehearsal store；不可引用密钥、任意磁盘路径或credential。JSON由root在审阅原始图像／数据后整理，工具不自动填PASS。

`rehearsal`对象须包含真实引用：`transaction`、`process`、`inspections`（至少前后2项）、`close_intent`、`close_requested`、`hold_end`、`restored`、`engine_log_final`。须来自同一固定外部事务。候选五文件完整SHA／FileID／代码pin相同，真实owned Dota和keeper至少打开候选index；未使用卷可未被打开，不把五卷打开当全部脚本执行。inspections须夹住所测像素及ETW；随后才WM_CLOSE、同native handle确认真实退出、完整恢复3102。close请求不是退出证明，hold_failed存在即拒绝。外部完整6918／184认证与原生观察分开；不要求不存在的“引擎原生验签日志”。最后还会重新全量核对当前Steam安装五文件确为3102，不能仅信restored布尔。

`portraits`精确包含4例：`bane_5`、`wave_equipped`、`hero_builder_switch`、`bane_5_after_eviction`。每例包含`reviewed/native_ui/no_stale_qwer=true`及`captures`数组（至少3张不同真实PNG+metadata引用）。Bane／波次／返回例另有`wearables_visible/background_visible/no_base_model_flash=true`、`scene_key`；英雄／建造者有`hero_and_builder_correct=true`。返回例的`scene_key`须等于初次Bane，其`visited_other_scenes`须有至少5个不同其他scene_key，每项`reviewed=true,capture={png,metadata}`，实际时间顺序初次Bane→5个其他场景→返回Bane。此为root审阅的采样序列，不宣称绝对覆盖所有未来帧。

`frames`对象包含`capture`、`collector_identity`、`frames_csv`、`focus`、`screens:{before,after}`、`visual_review`。capture沿用真实采集字段pid/tools=false/seconds/delay/started_utc/wall_seconds/read_only_etw/script_injection/account_operations/frame_csv_sha256；collector_identity是同游戏pid/created_utc/tools=false及实际Intel签名验证记录。真实CSV至少30秒／120帧、同PID／swapchain、时间单调；直接复算mean>=90FPS、P95<=16.7ms，保持当前工程门槛。capture起点／delay、CSV的CPUStartTime首末、1Hz focus窗口以1.25秒界限绑定，不能旧CSV配新画面；间隔总量与CPU跨度须一致。

`frames.visual_review`由root实际看前后PNG后填写：`performed,before_game_in_progress,after_game_in_progress,timer_advanced=true`、`before_paused,after_paused=false`、两张`before_png_sha256/after_png_sha256`，以及`gameplay_timer_advanced_seconds`（**前后截图之间**可见游戏计时推进量，不只是30秒CSV长度；包含capture延迟）。它须与前后截图实际UTC跨度约一致（2秒以内），防止暂停或加速误报。截图须使用普通`capture_arcade_readonly.ps1`元数据、同创建代际／主窗口／尺寸／四角归属，前后包围完整capture。focus保留最多1.75秒采样间隙，承认1Hz采样及1.25秒时间对齐局限，不声称连续焦点的绝对证明。

操作顺序：普通排演真实登录与画面／ETW完成→WM_CLOSE正常确认→keeper实际退出释锁→restore并核3102→root审核上述JSON并取SHA→preflight→授权apply→官方download→新游廊实际再验。不能在ETW里同时跑inspect全量hash、VPK认证或SDK上传。成功排演仅放行原条目更新，不预写正式下载或最终新游廊已通过。

`verify_download_v02.py`只绑定精确successful2026110102发布回执，再复用冻结官方1313／3406、完整五VPK CRC／MD5／SHA和签名认证。协议文件及其历史终端180字样不改，权威verification receipt须184。官方下载会使用原Steam管理机制，不手写ACF，不以本地rehearsal冒充下载。默认静态，preflight强制full本地校验；download锁内再次full检查，只接受当前成功的同版本journal。13项隔离mock测试已通过，包含冻结download_once回执构造实际输出184、终端仍180；没有真实SDK或下载。

```powershell
python tools/arcade_portrait_release_v02_20261101/verify_download_v02.py
python tools/arcade_portrait_release_v02_20261101/verify_download_v02.py --preflight --report-sha256 <SIGNED_PACKAGE_REPORT_SHA>
# 仅本轮真实发布成功后，Dota关闭、Steam在线时执行：
python tools/arcade_portrait_release_v02_20261101/verify_download_v02.py --download --report-sha256 <SIGNED_PACKAGE_REPORT_SHA>
```

正式下载的权威结果在`output/arcade_portrait_release_v02_20261101/download_evidence/<NEW>/verification.json`，须核实际1313／3406及6918／184／五文件／签名／新Steam manifest。之后仍需新游廊实际启动、所测画面与FPS验收；下载器不会把`native_test=NOT_RUN`改为通过。

复杂度仅显式运维：预检必要完整VPK认证为O(B)流式读取，资源索引N=6918；证据按路径／SHA索引后首次hash，结束再复核。CSV限64MiB／200000帧，复算O(F log F)、O(F)空间；截图及RM元数据只访问所列证据。无游戏帧循环、新计时器、原生UI动作或服务端业务写入。
