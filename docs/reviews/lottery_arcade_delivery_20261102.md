# 2026-11-02 抽奖动画的正式包交付修复

## 快速定位结果

本次用户截图为普通联网客户端的“星门寻宝／播放时发生错误”。单抽、十连、再次抽取及四种宝箱均经过当前HUD加载的`lottery_ui_remaining_5d5c1152eb.js`，成功ACK后调用同一`LotteryCinematic.Play`。无需分别改抽奖、库存或服务器发奖逻辑。

实际安装索引SHA256为`84b5645f1b1e7c8892630555b17f8deecf5d6abe13fe5144a55ef500a09f8cdb`。四段WebM均存在，与开发资源逐字节一致；播放器JS为6041字节、SHA256 `a90d37b5ebefac4261fe49eafddf53401f56a3597216b2d154155f0e6c20a78c`，CSS为3509字节、SHA256 `5e322c0a140dd510579357ad7714678dd5d9ab59acd11f2fcf8bd6c03ce8595c`。两者均无新`LCFallbackActive`标记：正式0104仍使用旧播放器，之前d71开发修复及0201候选没有发布。具体读包回执为`output/lottery_arcade_delivery_20261102/installed_v01.safe.json`。

原生异步Movie失败是已观察事实，但具体底层读取／解码原因尚未证明。Valve自带intro片是松散WebM，URI alias与我方一致、同为VP9/Vorbis；本机官方pak中没有WebM是读取路径线索，不足以断言所有VPK均不能播放视频。Tools中原夏季片能播放，也不能证明普通游廊压包可播放。不得将“视频在包里”“头信息合法”“Tools播放成功”写成普通游廊成功。

## 运行改动与边界

保留原视频为首选，`MovieError`或同步异常转为同宝箱主题的原生CSS演出，随后展示已经收到的结果。错误文字由样式隐藏，最多100ms后的当前Movie状态检查触发回退。新增固定四种pool的失败索引；某pool本局首次失败后，再次播放该pool直接走主题演出，不重复创建已失败的原生解码器。其他pool仍各自尝试原视频；取消／替换不清空本局失败索引，模块Dispose／重载／换局丢弃旧索引。无通用场景遍历或长期失败轮询。

普通客户端已有的无消耗`lottery_film_<pool>_<stamp>`预览命令新增有限阶段日志：`stage=preview`、`stage=fallback`和`stage=complete`，仅包含pool、失败种类和preview标志，不包含账号、认证、结果或存档。每次预览最多3条，真实抽奖不新增这些阶段日志。

正式热修复以已发布0104为认证父，只替换4项既有运行资源：

1. `panorama/scripts/custom_game/lottery_cinematic_v1.vjs_c`
2. `panorama/styles/custom_game/lottery_cinematic_v1.vcss_c`
3. `scripts/vscripts/ui/production_ui_service.lua`
4. `scripts/vscripts/ui/ui_request_router.lua`

后两项承接用户前次要求的训练容量中文提示。JS/CSS两作者源与content镜像单独绑定，不作为额外运行项；视频和四主题图复用已验证0104字节。未发布0201的头像、共享Boss等17项保留在其原候选和Git，不能把本轮仅4项热修复说成全部开发HEAD已经发布；后续合并0201须叠加本轮4项，不能以旧候选覆盖本轮修复。旧recipe／native门槛不修改。

首次真实计划发现父包18项可信源审查已包含`ui_request_router.lua`，不能当作两个全新审查追加。正确投影为完整认证原18项、原17项逐字保持、受控替换router并唯一新增production UI，总共19项；两份训练源仍分别审查。第一份计划在签名和换包前拒绝，没有产出可用计划；新builder、原生与下载门禁都采用这份精确集合，原18保护没有放宽。

## 复杂度与可复现计数

N=四个固定pool，R≤10个已确认抽奖结果；没有新增按玩家、单位或全场集合的循环。

| 阶段 | 时间／空间 | 原生／网络调用 |
| --- | --- | --- |
| 模块初始化 | 空失败索引O(1)，最多4个键 | 0新增网络调用，无预热视频或纹理 |
| 无演出稳定刷新 | O(1)，无新计时器 | 0新增Movie、原生状态检查或网络调用 |
| 健康视频一次播放 | 既有O(R)，最多70个O(1)状态检查，至多2个活动计时器 | 1个Movie；无新抽奖／领奖请求 |
| 首次失败的pool | 索引写入O(1)；首次备用层固定5节点、1张当前主题图 | 释放失败Movie；同主题不重复SetImage |
| 同pool失败后再次播放 | O(1)索引查询，备用层复用，至多2个计时器 | 0个新Movie、0次MovieError检查；同主题0次SetImage |
| 切换／销毁／换局 | 最多2个计时器代际失效，固定节点和4键索引回收 | 不保留旧回调或跨局失败状态 |

可复现命令：`node tools/test_lottery_cinematic_fallback.cjs`（9个生产模块模拟场景）、`node tools/test_lottery_reward_feedback.cjs`（真实ACK consumer）、`node tools/tests/lottery_cinematic_flow.test.cjs`（单抽／十连／跳过与结果流程）。上述均通过；模拟计数不是实际原生FPS。

最终官方编译回执`output/lottery_arcade_delivery_20261102/compile_v02/compile.safe.json`：game/content作者源逐字节一致，JS/CSS两项成功、0失败。最终JS compiled为11246字节、SHA256 `f0b89bcb3c8abb82b962c5e1e2e6b944e5ea7d85749397429f95d117a3d20d23`；CSS compiled为7823字节、SHA256 `691c18f7f061ea6c04d56a1984d6ebe39043c1cf05e01402a826ce8611b50024`。

## 本轮实际验收口径

四种宝箱的普通客户端预览需要同签包、同进程日志及早／晚画面，实际Movie失败应看到对应pool的fallback日志和主题演出；正常结束回抽奖窗口，不以模拟像素或Tools截图代替。预览不消耗券、不调用真人抽奖，不证明真人已到账；消费、单／十连及结果映射以真实consumer回归为辅。本轮没有原生FPS提升结论。新签包／安装／发布／官方下载以最终机器回执为准，本文不是PASS开关。

为保证完整新排演备份空间，将已经完成原3102恢复、未发布的旧`v03/run01_candidate14`整棵33文件归档到`C:/Survival_排演归档/20261102/completed_candidate14_v03`，7576239101字节逐项SHA256核对并保留ACL；D盘原位置留`ARCHIVED_TO_C_20261102.json`指针。正式五包、0104认证父、0201待验与所有旧签包未动。不能在未找回原归档的情况下直接重跑旧v03恢复入口。
