# 2026-11-04｜S9完整候选、目录漂移与WS4耗时

当前仍仅本地更新，原游廊为2026110104，Steam manifest `7025356658517360342`。本轮未上传、未部署后台；不能把以下签名或暂装结果称为游廊同步。

## 已完成的真实构建

- 作者来源game `a717903f6219086da17f72d872f63ef8de153160`、content `3700b2328007c157325cdf204dbe47dcf7c42a9e`；收集工具 `e4c4341f8bd29cf0f0f70139dcf79cf5bbe079f9`，S9构建工具 `d0987cc6f2f66f721b033ca194c789c4f32f158d`，均已推送。
- 150项真实官方编译、186项保护、7项生产转换及原始生成回执已核对。三个未变化的VJS按父签名、完整字节、真实生成源码及DATA换行约定重新绑定，未冒称新编译；四个准入文件保留父CRLF字节，并非保护输出。
- S9完整签名候选7031文件、3,806,249,954字节、385项更新、7项删除，索引加四卷；全部签名/CRC/双哈希通过。内容摘要 `6e484114147edfb903eeceaffd79a4049d506cc14ce4932193363e09345a49f5`，包报告原始SHA `3b4c6235b1cb7ca4c7a9cfaa5747507e8716eff741c0ed999a13d41f707e29c2`。
- 逐编译产物核对另发现：候选150项均匹配原回执，但与game Git已存编译文件150项均不同，尚未配套提交。多数是RED2及换行差异；不能据此声称Git产物相同或已完成交付。后续应提交最终真实编译产物，再以真实双端Git读集证明producer到target的等价，不重写原回执来源。

## 普通客户端的有限观察与恢复

事务 `D:/Survival_本地排演/complete_delivery_20261103/complete_s9_run01` 已实际暂装。窗口看到了暂停的N1和抽奖页，未作有效FPS或完整普通验收。日志570个cw、最大49B、零解码/运行错误；Hello八字还原为gen5 `b9f73807866a690903c06bd22d0c47f950f30a30a239f9c09936a501d55d3039`。闭合日志SHA `c11ce3a43e6612c30c242b85b2b3a09cabf2086daf8ace9ccba33171262afdae`，不把原始身份或认证字段写入知识库。

Root的WM_CLOSE准入前原进程已退出，退出触发来源未确认；有真实retained-handle `hold_end.json`，没有Root成功WM_CLOSE回执，不追认受控正常退出。随后canonical restore实际exit0，`restored.json` 为 `ORIGINAL0104_COMPLETE_SET_FULLY_RESTORED`；原备份、候选和回执均保留。Root自动消耗仍为0/30普通券。

抽奖页显示“奖池版本已更新，请重新进入”、券数量为横线。服务端view201/202实际发known=0、enabled=0、error=6；不是丢包或客户端误解码。S9不得作为正式验收通过候选。

## 公开目录的实证差异

实际bundle为 `d573588b64d2ea6d1431c856d52e0515b5ed471cfdf6af4456ff618d0f568488`；其当前WS4公开catalog MD5为 `b47064df86927bf54f83e2397d7f7341`。本地旧seed的config为0032开头、MD5为 `ef2bc54920be9ec413a8c489811ef997`。

105项ID及四池数量30/26/26/23相同，196处差异仅name105、description71、revision20，概率、数量等其他公开字段未变。既有工具是 `tools/build_lottery_catalog.py`，应从实际声明bundle生成三个公开输出并check；同时增加bundle/manifest/seed的生成期一致性检查，再严格Git生成下一版静态目录。不得删除版本保护或伪造MD5一致。

## 领取慢的真实后端计时

只读核对WS4仍为 `20261103-ws4-lottery-receipt-d2c7c2e85920`；此为本次现场核对，后续部署须另记。

- 本机archive/config HTTP约1.75–4.71ms，lottery/catalog约3.08–3.35ms。
- 无数据库、无真实玩家的Lua snapshot三次为687.6/697.4/717.8ms。每次settle重复传完整configs 1,618,929字节、56表4546行；Python编码约37.6–38.2ms。
- 实际域名health冷连接约441.8ms，其中DNS约296.8ms；热DNS新TLS约144.3ms，同连接后续两次约33.3/34.7ms。没有修改用户代理设置。

因此固定主要耗时是静态配置反复编码/解码/初始化，不能归因于49B游戏短包。准备保留每笔独立Lua VM、原worker/RNG/沙箱，以实际immutable bundle绑定私有预编译配置缓存；尚未部署或证明真实交易低于1秒。原始安全摘要位于 `output/ws4_latency_20261104/actual_ws4_audit.json`。

后续源码已双仓冻结推送：game `5a93e17c3b6e575fae701d2dc99827d273afe139`、content `55c24266092430704aa26e9f1ba61d10eca001c0`。Linux真实无DB合成对照中，snapshot约682–698ms降至暖139.9/148.6ms，首次冷cache345.8ms；有效daily claim约676–680ms降至138–141ms，十连约677–696ms降至132–133ms。每次输入1.619MB降至3.33–3.55KB，新旧完整输出相同。另以已解锁合成配置验证16次四池抽奖均成功且结果一致；没有读取或修改真实玩家。这仍不是实际API交易或端到端领取验收。见 `output/ws4_latency_20261104/actual_linux_cache_benchmark.json`。

一次额外只读SSH源码核对被工具返回 `rejected by user`，没有其他原因，动作未执行、未重试。部署工具已本地准备，须先核实实际父文件；当前生产service与game源码在settle之外存在历史差异，不能整文件替换。受控方案仅从已提交源码提取唯一settle方法，保留实际父service其他字节，并增加runner与worker_fast两个文件；部署仍未执行。

## 后续交付

先完成服务端优化及目录生成guard、冻结双仓作者源，生成新静态目录及官方编译/保护产物，配套提交真正运行的编译字节，保留原producer与新target的独立绑定。新候选控制目录使用独立v02，不能覆盖S9包报告。之后仍需真实普通客户端界面/连续抽奖/耗时/FPS、canonical SDK及官方完整下载、完整待发清单收口。未完成这些步骤继续报告仅本地更新，并单独说明后台状态。

后续候选改用独立版本号 `2026110401`，旧0302/S9及其未通过准入的证据保持不变。新动态编译范围工具从完整待发审查逐资源选择所有支持的官方编译类型，保留每项原始决定与原始审查摘要；旧范围真实动态覆盖150项，新S10观察中原有选择器又漏了commerce_actions和monster_portrait_renderer，不能固定148/150或复用旧列表。12项离线及真实Git树选择测试通过，尚未执行本轮新编译。

奖池额外发现四池revision同样来自旧本地配置；详情/公告的已读提交会被实际生产版本拒绝。修复从同一公开catalog生成四池revision映射，投影与read命令均读取该映射，不增加HTTP或网络字段。测试的静态字段改为独立对照实际b470公开JSON，动态字段继续对照原Lua结算投影；不删除版本检查或改动原始公开元数据。展示规范化后仍有一个既存三字内嵌别名“封神榜”未转为“英灵录卷”，单独列为文案边缘问题，不影响此次协议版本修复。

领取链路另发现真实排队缺口：已有请求busy时新领取入队，完成回调没有唤醒非无尽队列，可能等待两秒archive_retry。新增按账号/命令ID的待发链表，在完成后下一帧只发送从未尝试的队头；失败或结果不明的旧receipt继续由原恢复策略负责，不立即重放。新增/删除/取头及唤醒O(1)，空间O(账号+未结命令)，每账号最多一个零延迟调度；无尽批处理规则不变。真实生产模块测试128个领取得到128次发送/128次唤醒/pending遍历0，重复回调、失败购买不重放、购买优先级、账号隔离、terminal拒绝及换局失效通过；S10旧代码运行该回归在首次唤醒处失败。旧archive_service大总测在第155行积分条目断言失败，独立S10基线同样失败，未降低断言或当本轮通过。

S11源码 `69ec12d48314a18035ae8b8db7584fac9ef0acf7` 已推送；据此及content `55c24266092430704aa26e9f1ba61d10eca001c0`严格生成Gen6r2，schema `a0eb341e0fc2e0ad8c4b90101d8de45b191b124b7ddf1535a18e893b8746e8a0`，7935记录/188字段/registry代际12保持。生成产物及双仓镜像已推送为game `c071aa9c7b07180e643ab09548871ef2a822e941`、content `062203c2d2d143b5984ee6b8dfc7a6264df1d1ff`。150项实际官方编译完成，proof原始SHA `e8494b9d1ad7f14bf608d219112a4c4f6f0a733cecdcb85e2c8aad63f4eae3ff`；真正编译字节12,823,801已逐hash复制回game，全部150相对旧Git不同，须配套提交后再构建。同期7项生产override及186项Lua保护已真实验证；尚非新签名或实机通过。

用户已明确重新授权服务器核查及受控部署。真实audit确认旧WS4父版/manifest/service/unit及7个保留服务身份，v1只prepare未激活。probe发现旧raw Lua返回与原service.object_maps返回层级不同导致空列表/字典误判；窄合成诊断证明snapshot、claim、draw全部ok且在相同规范化边界结果相等，RPC/数据库写0。v2仅修验收比较、9离线测试通过，使用独立recipe `normalized-parity-v2`、candidate `20261104-ws4-worker-cache-3f53908aaea0`及新回执目录，旧准备目录保留；截至此记录仍未激活后台。
