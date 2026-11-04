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

## 后续交付

先完成服务端优化及目录生成guard、冻结双仓作者源，生成新静态目录及官方编译/保护产物，配套提交真正运行的编译字节，保留原producer与新target的独立绑定。新候选控制目录使用独立v02，不能覆盖S9包报告。之后仍需真实普通客户端界面/连续抽奖/耗时/FPS、canonical SDK及官方完整下载、完整待发清单收口。未完成这些步骤继续报告仅本地更新，并单独说明后台状态。
