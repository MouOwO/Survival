# 2026-11-03 Dev07｜真实短消息和有效无遮挡FPS样本

**仅本地更新，后台未改。** 正式游廊仍为0104／Steam manifest `7025356658517360342`。本轮未签名、上传、替换正式安装或进行玩家交易；没有普通签名客户端、在线或四人通过结论，完整发行清单保持pending。

## 真实来源与Dev06纠正

Dev07使用独立树外副本，10830文件／5270958320 B，复制及来源二次摘要检查通过、硬链接0。来源HEAD为game `cf7bb4a2a76957e9920c9afc7eb47f48a676ef2a`、content `32f884dcb4e2c68aa7d669eec4eb17d0616e9f9d`，但准备回执明确`source_is_workspace_observation_not_immutable_release=true`：诊断和HUD末状态修复来自当时工作区观察，不能把这次副本冒称完全由这两个Git提交导出。原始manifest及其摘要由脱敏证据绑定，最终发行仍需重新冻结确切来源。

Dev06的原capture曾标记valid，但同局原生日志在采样区间内出现`2026-11-03T17:50:43+08:00 PLAYER_DEFEAT`；旧HUD缓存并不能证明引擎仍在游戏中。**Dev06现重新分类为无效FPS样本，不能参与有效性能结论。** 原始回执按历史保留，不改写成通过。后续诊断新增真实`Game.GameStateIs`与运行时枚举检查，并独立核对同owned进程日志的原生S/C状态及defeat区间，旧缓存只作上下文。

## Dev07短消息实际结果

已关闭日志SHA256为`c4de2667f6edf3a86d23a809c8b8596ecb1ff622564a3950cc1f3bf4f4dc9516`。可复现命令为`python -X utf8 -B tools/summarize_compact_native_log.py output/network50_dev_20261103/run07/engine.log`。公开脱敏聚合与FPS摘要在项目路径`data/ui/network50_dev07_evidence_20261103.json`，SHA256为`d29281eb9631bad6290b9e9f003661f55ff924c37235c21fbf0dff6528e8ddcf`；不提交原日志、KV、session、账户或认证内容。

真实`cw`94帧／4576 B，最大49 B、解码失败0，经过的视图为1、2、3、4、5、6、8。这里计量`CUserMsg_CustomGameEvent`，不含UDP／IP／Steam外层开销，也不是RTT。该局VIP、英雄旧大包、旧HUD／archive／selected及五种旧grid事件均为0；所有观察到的事件最大值都不超过1500 B。不能由未经过的view7或其他交互推断其已实机验收。

**严格全部≤50 B尚未达成。** 本局仍有以下实际残余：

| 事件 | 次数 | 最大原生B |
| --- | ---: | ---: |
| `survival_payment_capability` | 24 | 239 |
| `survival_public_beta_gift_snapshot` | 1 | 339 |
| `survival_loading_mode_result` | 1 | 191 |
| `ui_notification` | 1 | 149 |
| `ui_difficulty_select_result` | 1 | 102 |
| `ui_weapon_synthesis_snapshot` | 1 | 97 |
| `ui_shop_unlock_state` | 1 | 96 |
| `survival_select_unit` | 1 | 75 |
| `ui_combat_effects_state` | 1 | 55 |

## 有效无遮挡30秒FPS

有效样本路径为`output/network50_perf_20261103/run07/n1_hud_uncovered_2de110ce5fc84417b6398b37aaddbd15`。采样时间UTC10:28:36.362330～10:29:06.464128，wall30.101784秒，真实游戏时钟推进30.183411秒。前后fresh endpoint均active／Tools、未暂停、引擎in-progress且非post-game；同owned日志区间无拒绝事件。30次前台观察覆盖30.000966秒，最大间隔1.000955秒。前台间隔与端点检查仍不能证明每个中间帧均无瞬时遮挡。

两张实际截图`hud_uncovered_before_20261103_102833_216_b511ce46.png`和`hud_uncovered_after_20261103_102910_095_af29cdb9.png`均显示N1开局地图和原生HUD，没有gift弹窗；主操作者与证据代理已查看。截图摘要收录脱敏JSON，不把其他轮次或旧截图替代此样本。Dev07首个30秒有gift弹窗，只能记录为overlay场景，不能当成本无遮挡样本。

| 指标 | 实测 |
| --- | ---: |
| v1接受间隔 | 1792 |
| v1平均present FPS | 60.005967 |
| v1 P95／P99 | 16.947880／18.928211 ms |
| v1最大间隔 | 30.327800 ms |
| v1间隔≥33.33／50／100 ms | 0／0／0 |
| v2接受帧数 | 1792 |
| v2平均FPS | 60.000356 |
| v2 P95 | 16.799335 ms |

这是**有效测量，不是工程阈值通过**：原capture的`engineering_gate=false`，P95仍高于16.7 ms。两只读ETW collector同时运行有测量开销，present cadence也不是实际displayed cadence或服务器tick。场景为单Tools N1、原地建造者和无遮挡HUD；不代表四人战斗、生产交互、全部窗口或普通签名包表现。

Dev07已正常关闭并retire挂载，日志closed，回执保留。下一阶段由delivery负责payment view9/action12，release负责Beta view10/action13，唯一registry／seed由catalog owner维护，root负责共享transport/runtime；先审真实字段、保留授权和奖励逻辑，新seed源码冻结后才能严格Git生成。完整pending／保护／recipe／authority及新ordinary／online／四人验收仍未完成，不能写“已同步游廊”。

## phase4静态计划追加，尚未生成新运行目录

真实消费者审计后，payment仅计划新增`payment:capability`一条记录，复用known／enabled／request_token；不增加支付地址、账户或长session静态数据。Beta计划新增`public_beta:state`与`public_beta:receipt`，字段187`source_revision_hi`精确保留安全整数revision的高32位，字段188`public_beta_flags`保存active／eligible／claimed／claim_pending／read_only五个实际布尔。两字段默认unknown，既有字段和ID不改；记录／字段总量计划7935／188，当前实际运行目录仍为前阶段gen3的7932／186。

`tools/public_beta_ui_static_seed.lua`实际执行原`archive_benefit_rewards.public_beta_snapshot`，并交叉核对真实配置的票种、数量和无额外月卡奖励；真实DTO仍写2但配置改3时，生成测试明确拒绝，不继续展示错误固定奖励。只保留票名／数量／原配置／原UI失败提示等静态元数据，动态active／领取资格、day、revision不从空profile原型冻结。真实day是`(timestamp+3h)//86400`的十进制字符串，按server整数可逆传输，不猜客户端日期。Beta通用失败码只有原UI所需的`claim_failed`，不把内部错误长文发到客户端。

27项catalog测试通过，包括实际配置漂移拒绝、尾追加字段／unknown默认和同schema双root零重复工作；这是明确的UNIT_TEST输入原型，不是新运行目录、实机或发行验收。Beta初稿首full7帧／校准331 B接近旧state339 B；实际五布尔打包后首full为5帧／239 B，成功delta239 B、含ACK恢复full431 B，均最大49 B。后三项仍是离线校准量，ACK恢复包与旧初始state含义不同，不能混作同场景流量对比。后续必须等新的明确source／operator冻结，严格Git生成后用真实ID复测；本节没有直接覆盖catalog／lookup／registry产物。

## 最新用户范围决定：高频≤50 B，其他以总流量优化

用户随后明确调整目标：**高频同步消息≤50 B；其他路径按总流量优化。** 本决定取代之前要求所有启动、通知和偶发事件均拆到50 B的广泛目标；前文真实数据、原目标和未通过边界按历史保留，不改写原证据。`strict_all_events_at_most_50_bytes=false`仍是Dev07的真实计量结果，不再单独作为新目标的全局失败判据。

当前继续收口payment高频能力同步和Beta静态本地化，完成gen4、同源native及完整发行；不继续无界迁移所有rare启动／通知事件。是否高频必须依据实际触发和调用计数，不能为绕过限制任意给事件改名。低频路径同样保留去重复、增量、实际预算、取消和当前操作优先要求。

常见template地图的已验证候选baseline加K覆盖继续优先，根操作者报告当前静态子路径约293 B。未知地图首冷fallback约27 KB、旧单包约4.8 KB的问题明确保留，后续作为专门的大数据路径按总流量改进，不再以强制49 B碎片替代总字节优化；不能由单包小就宣称该路径优化完成。这项后续性能工作不允许静默遗漏当前或历史运行文件，完整动态build／ledger／validators／authority、保护、签名、ordinary／SDK及官方下载待办仍须全部收口，不能回用固定9文件配方。
