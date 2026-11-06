# 0603 实际诊断、恢复与后台 v2 上线

状态：**仅本地更新**。0603 未通过视频准入，SDK 上传 0；正式游廊仍为 2026110104，Steam manifest `7025356658517360342`。0603 已正常退出，完整恢复正式包，允许继续源码修改。

## 已完成的实际构建与部署

- 0603 来源：game `eff9c494dce8c62055c177f4f2a054b171d6653d`、content `51c75d2046cc62d74ab94633d0fc9baad6ea9a25`；独立 operator `8f78221d0a51f6765316bd70b13a4d2506cbb4e5`。两仓已 push；原有五项 game 工作区内容保留。
- gen14 官方编译 154/154、186 Lua 保护及 7 override、完整 collector、签名和暂装均实际完成。7038 资源，3,806,536,764 字节；相对正式基线 270 替换、128 新增、7 删除。未知/延期转换 0；569 项待发来源覆盖仍不能视为已发布。
- 报告 `output/complete_delivery_release_20261106_v03/package.json` SHA256 `5e537635a1a15cc026f08f0189568088f132d20e03533dd90398778a52edb81b`；签名 manifest `e8c448f2f61b2e4fffc2da0fb5a3a935619a1406635c3723b00c3dfc0435efa8`。
- WS4 实际部署并 verify：`20261106-ws4-daily-refs-ed532ea60d2b`，manifest `839fa42cf775453bf90807b5b4eeb5d714a7a821f4cbfddd0046e015a927f106`，API PID 975520。仅更新 `backend/archive_backend/http_profile_wire.py`，保留父版本、配置及启动同步策略；支付/PWA/网关未更新。
- 后台回执 `output/ws4_daily_refs_20261106_v02/verify.json` SHA256 `5cde888851ac28380c33ccdbca2a53312b25d0c94da3636a88089ccc4e31a7cd`。实际 Linux Python→Lua 探针共 18 向量（含 4 异常）；标准/月卡合成回包分别减少 5822/5823 字节。这里是序列化容量，不是实测 HTTP 延迟改善。
- 初次 v01 探针因错误 `/usr/bin/lua5.1` 路径失败，未激活；保留其失败候选/回执。v02 使用实际 `/usr/bin/lua`，未将失败记录改成成功。

## 0603 原生观察与明确失败

事务 `complete0603_run01`，普通客户端 PID 25264，创建时间 `2026-11-06T12:50:28.1969223Z`，实际 argv 包含 `-vconsole -vconport 29072`，cheats=0。完整安装核验和首尾分卷使用核验通过，但没有 29072 监听。因此初次快速暂停没有发送回执，不能声称暂停执行；增加启动参数也不能保证普通客户端开放 TCP 控制台。

模式弹窗和抽奖 modal 会挡住原生控制台输入。第一局选 N1 后未及时建墙，21:03:25 正常进入失败；`find "paus"` 到达控制台时已是失败界面，实际列出 `sv_pausable 0`、`setpause/pause/unpause`。第二局仅同进程重新进入模式选择，未做付费交易，随后正常关闭。未执行新的 F8 绑定，未将 F9 相机快捷键当作暂停。

更重要的是代码核对发现：A/B 和 decoder probe 都依赖 `LotteryRefreshButton` 存在且启用，真实加载的布局和源码根本没有创建这个节点。旧模拟测试却凭空创建了该按钮。这是诊断入口缺陷，0603 没有 A/B 播放成功证据。必须移除此错误依赖，按控制器真实状态准入，补实际 DOM 缺少按钮的测试。不能注入假按钮或把普通兜底动画视为视频播放成功。

下一候选的本地预览入口须跳过普通 `Open()` 中的 `cache.Open`、强制刷新和访问标记，零 HTTP、零抽奖、零奖励，并在结束/取消/重建时释放预览锁；已进行中的交易不得被预览打断。生产视频加载方式仍待三路实际帧对比后决定。

## 奖池前置请求与延迟边界

0603 模式选择前出现 20 次目录失败，约每 30 秒一次，median 1094ms、max 4008ms；档案加载后连续 6 次成功，配置和 MD5 均匹配。`config_match=false/md5_match=false` 是失败结果缺少哈希，不能据此认定哈希错误。

静态调用链：客户端允许未选模式目录请求，但后台在目录路由之前要求本局档案上下文；授权本身不创建该持久会话。隔离执行现役上下文函数证明缺失会话返回 409 `match_session_missing`；当前现场日志没有记录该次具体状态/错误码，因此不能冒称已经在线观测到此 409。

修复范围为按玩家 ID/会话维护就绪索引、首次就绪触发一次、重复 revision 零原生身份读取、请求和回包同时验证会话代际。未就绪稳定检查 O(1)、零 HTTP；多人失效淘汰最多 O(P)，P≤4；不新增计时器。稳定成功后的 30 秒条件校验暂保留，因为现有后端没有目录版本推送，不能直接删除而遗漏本局热更新。相同 MD5 的后台目录响应只有四个元数据字段，未重发完整目录。

0603 没有新的业务 `ARCHIVE_HTTP_TIMING` 交易样本，不能声称已低于 1 秒。0602 的实际免费公测礼包领取成功一次（2 金券、总 947.941ms、19,445B）仍是有效旧样本，不能改标为 v2 测量。原 30 普通券授权已用完，本次没有新的付费抽奖；最终连续十连验收须另获具体授权。

## 恢复与后续

`D:/Survival_本地排演/complete_delivery_20261103/complete0603_run01/restored.json` 返回 `ORIGINAL0104_COMPLETE_SET_FULLY_RESTORED`，SHA256 `b712a9b27589815287057031fc0579e9d4b0eb6ea742a61daca8b78053ed3b7e`。原包、回滚备份和失败候选证据保留；没有写正式发行 journal 或 Workshop 元数据。

继续：修复诊断入口和目录就绪契约→双仓源码提交推送→新不可变候选/完整编译与保护→真实普通客户端视频和业务延迟验收→SDK 上传→官方完整下载逐文件验证。任何一步缺失均不能称“已同步游廊”。

## 恢复后源码修复与本地验证

0604 源码已补真实控制器预览准入/本地预览租约，移除不存在按钮依赖；闭页展开不调用正常打开路径的缓存订阅、读取或访问确认。被动缓存更新仅置脏标记，原开页结束最多一次无 ReadAck 的本地渲染，原闭页恢复关闭；交易、未确认结果和其他 modal 不可打断。取消、关闭、销毁、重载和换局均释放。9 套 Node 检查通过，包括真实 HUD XML + GW2 + controller + compact cache 联合测试。生产 Movie 路径尚未修改，不能将此记为视频故障已解决。

目录客户端两份 Lua 修复和安全 `http_status/response_bytes` 日志已落源；指标来自内部 HTTP 回调，正文同名字段无法伪造。固定 22 项真实 Lua 回归全部通过，另有实际 compact codec 的 bulk 变体通过。`output/http_profile_refs_20261106/catalog_admission0603/production_tests.json` SHA256 `5e9757b0b4184da748e5b2f5c182f3685b58ee7d986593ac64ba400fe2e3bb10`。

支付回归旧 fixture 曾在双 HEAD runtime 上同样失败：它传入空服务端 actor，且每次 GetPlayer 返回不同对象，被现有安全门禁正确拒绝。只修 fixture 的稳定真实实体索引，新增拒绝空 actor 和伪造 PlayerID 的断言，原支付生产源完全未改；修后在双 HEAD 与新源码均通过。原失败证据保留，补充 `payment_fixture_validation.json` SHA256 `2c57b2dab5258ae44d0df1cfa7a6551fa1d629544b1babb45c9fc0e11cf27200`。

预览初始化/主动起止成本 O(1) 状态检查加现有 modal 栈 O(L)，稳定新增零定时器/HTTP；A/B 固定 6 次 O(1) 样本和 1 次清理，最多 7 个计时器。上述均为代码/模拟计数，不是原生 FPS 或实播验收。新编译、签包和普通实测按实际结果另记。

0604 源码和 operator 已实际提交推送：game `bda269713e612207e7737d49aa24ac4577bed2bd`、content `73a290a2ae57cac24e64a16657b3c1405f428f9b`。gen15 官方 154/154 编译通过，累计 65.927972 秒，原始 proof SHA256 `170d94a04a5d1894161dfed2c5dbdc54a13d3149602c41e8d228e0839a7458c1`；186 保护 + 7 override 实际通过，生产回执 `3ca0cf6bc55182b17519beedf78d22eada3ef1a4143dd45aa28bba4a77cbb0ca`，保护报告 `1d97be89dbcbb2d81cb4fb7f491f0a5e82ad8a87b459af6ba77dda6da8cb71b7`。Root 按精确 154 行清单完成导入并逐文件校验，临时编译挂载已退挂；全新 collector/签包/实测/SDK 仍待实际执行。
