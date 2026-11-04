# 2026-11-04｜0401普通实测、后台上线与0402收尾

当前仍仅本地更新，游廊正式版本仍为2026110104，Steam manifest `7025356658517360342`。0401已签但未准入、未上传，两轮本机事务都已实际完整恢复0104。后台缓存优化已独立部署验证，不能把后台上线写成游廊已同步。Root实际普通抽奖券消耗仍为0/30。

## 来源与真实构建

0401绑定game/operator `8034c5d5a379bbd7882102f4752d16b9c73525f7`、content `062203c2d2d143b5984ee6b8dfc7a6264df1d1ff`，均已推送。Gen6r2来自game/operator `69ec12d48314a18035ae8b8db7584fac9ef0acf7`及content `55c24266092430704aa26e9f1ba61d10eca001c0`；schema `a0eb341e0fc2e0ad8c4b90101d8de45b191b124b7ddf1535a18e893b8746e8a0`，7935记录/188字段/12代注册表。

150项真实官方编译与186项Lua保护的原producer为game/operator `c071aa9c7b07180e643ab09548871ef2a822e941`、content `062203c2d2d143b5984ee6b8dfc7a6264df1d1ff`。编译字节已真实配套提交到8034；没有重写原回执来源。完整7031资源/7删除项，签名包报告SHA `3924f61fd1ee12fcded05aef07aae74630737714634b0668c6482da67bd81326`，内容SHA `0a8096ee164e0a8a7efa4591c55a217f3199b96918db50c0c5ab7c4979d1ac19`，索引加四数据卷。控制目录 `output/complete_delivery_release_20261103_v02` 保留，不覆盖。

## 后台已上线

用户重新明确授权核查及受控部署后，WS4已激活 `20261104-ws4-worker-cache-3f53908aaea0`，recipe `normalized-parity-v2`，API PID680348。manifest SHA `39851557ce5d9c268c2deaa48b4be4697d8e3c04b10a52262566f371882481c2`。只有原service的settle方法及两个新helper变化；其余父service字节、环境、bundle、数据库及其他7服务保留。

真实Linux无玩家/无数据库合成对照：snapshot 691.46ms→首次冷348.72ms；可领取claim 703.85ms→138.96ms；ten draw 697.86ms→132.36ms。完整规范化结果均相等，实际probe RPC0/数据库写0。旧v1预检因raw空数组与原service规范化空对象比较而误判，v2已按原返回边界修正，独立新候选/回执保留；不是修改结算语义。逐文件及受鉴权health验证通过；这些计时仍不能代替真实游戏付费请求的端到端耗时。

## 本机事务与隔离

run01普通PID23488实际显示过141普通券，奖池不再error6，未抽奖。因未建墙触发败局，后续正常退出请求来源未确认；没有Root成功WM_CLOSE证明，不归因用户或崩溃。实际完整恢复成功。

run02准备期间出现独立PID31036，实际argv为工具版、`-noassetbrowser -addon survival`、离线测试及HTTP关闭，不能当普通游廊验收。其出现后63项文本编译产物的RED2从隔离编译目录变为正式survival挂载；17项DATA差异仅换行，作者文本没有业务差异。启动检查正确拒绝dirty source，未把该轮误作普通启动。Root完整保留7,214,122字节及逐文件摘要到树外 `D:/Survival_本地排演/compiled_source_drift_20261104/run02_tools31036`，正常关闭该无assetbrowser测试客户端，无强制终止；逐SHA确认后只恢复63项冻结HEAD编译字节，用户原有5项改动保留。不能把此事误说成collector重放写盘，静态调用链没有发现该写路径。

run02随后普通PID32000、创建时间 `2026-11-04T11:23:00.3068050Z`、HWND6360788，五文件及进程句柄由keeper持续持有。第一world未建墙失败后，通过官方普通入口在同一进程重新进入地图；没有Lua/Panorama脚本注入、未开启作弊、未消费券。最终Root canonical WM_CLOSE实际发出、keeper观察到退出且exit0，随后canonical restore实际为 `ORIGINAL0104_COMPLETE_SET_FULLY_RESTORED`。

## 实测网络与帧率

run01闭合日志SHA `65e8491934f06f278a195c2d16299de3865770cd0dbb730d3f3b0a10380f6b82`：386个CW、最大49B、总18548B，重复帧/重复字段值/解码错误0，实际Hello与Gen6r2相同。不要把跨world相同协议数字当作同world重传，也不能只统计CW就声称所有高频流量通过。

run02的20:21:48日志截面显示两个world的CW分别459/826个，均最大49B。其他冷事件各world各一次，包括约88.6KB商城/二维码结果，按用户低频总流量策略单独统计。真实发现授权等待状态遗漏：11/16条完整auth状态中，除有效期倒计时外共21次语义重复，单条最大376B，约5秒一次，审批后停止。发送源为启动认证的既有5秒resolve重试；客户端可用首次期限本地倒计时，不需重复发完整码/URI。原始认证正文、用户码、URI、身份或其指纹不进入知识库。

同一普通进程无叠层、未暂停的开局N1，30秒真实ETW得到3335有效帧：平均111.435 FPS，帧时间P95 12.549ms/P99 16.641ms/最大26.894ms。30个前台采样覆盖30.000秒、最大间隔1.0013秒；1Hz采样不能证明每个子秒始终前台。该区间是未到首波的静态营地，不能称重战斗验收或与旧60FPS样本的同条件因果提升。证据 `output/complete_delivery_release_20261103_v02/perf_catalog_warmup_run02`。

## 真实遗漏与下一候选

第二world档案已发布online checkpoint，但奖池目录仍nil，实际CW为known0/enabled0/error2，UI误写“档案尚未载入”。启动目录请求可能先于有效档案，后续仅30秒游戏时间轮询；暂停阻止恢复。38秒无交易推进后截图仍未知，不能追认该次恢复成功。正在将真实profile/auth ready边沿立即接入原catalog请求/校验，合并inflight与重复边沿，拒绝旧world回包；不跳过远端MD5/版本保护。需要最终普通客户端复验。

授权状态另作固定字段语义去重，不因expires_in变化重复跨桥；初次状态、真实变化及有界真实UI恢复保留，原HTTP授权轮询和身份约束不变。全事件验收也会覆盖授权前、协议就绪前及未知大包循环，不能继续只查CW。

独立下一候选版本2026110402、控制目录 `output/complete_delivery_release_20261103_v03`。另外准备零消费原生解码故障预览：将实际存在的非视频CSS资源交给真实Movie.SetMovie，只有真实native错误或同步异常才能走原兜底；不手动加MovieError、不直接调用fallback、不把mock当实测。正常4池和3次真实十连要求不减少；若引擎没报真实错误则此探针未通过。

当前仍需冻结本轮新源码/工具、重生成目录、官方编译/保护、配套提交真实编译字节、完整签名与普通UI/连续抽奖/端到端耗时、SDK及官方完整下载、待发清单清空。源码/工具草稿测试通过不等于已同步游廊。
