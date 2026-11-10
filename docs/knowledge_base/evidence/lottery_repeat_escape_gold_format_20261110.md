# 十连结果页继续抽奖时Esc退出及金矿提示取整（2026-11-10）

状态：已同步原游廊3824360109，版本2026111009，Steam manifest `7460464180809387257`；本轮后台未改。普通客户端新版本的实际点击仍待用户确认。

用户明确复现为：第一轮十连已显示奖励→点击继续十连→第二轮仍显示请求中→Esc退出→其他UI无法点击。使用真实现行控制器、GW2渲染器、层管理和结果处理路径复现：旧版在 `ESC must retire the viewport result sibling` 断言失败。

根因是全屏结果 `LotteryGW2Fullscreen` 与缩放菜单 `LotteryGW2Root` 是同级面板。渲染器Close只隐藏菜单，保留了结果层的visible和输入；Apply又只依据旧结果类判断是否显示，没有结合渲染器是否已关闭。继续十连期间旧结果类仍在，因此退出和晚到更新会留下全屏输入面板。

修复先禁止LotteryWindow输入并关闭渲染器的菜单/全屏结果输入，再释放层管理和演出定时器，最后关闭缓存视图、清理其余展示。结果层显示和输入必须同时满足窗口已开、存在结果且没有详情子页；关闭后Apply不能再次激活。演出Cancel也明确关闭surface的输入，下一次播放恢复。没有清除待确认交易ID、伪造结果、自动重抽或改写奖品，晚到/重复回包仍沿原服务处理，显式重开能看到已确认结果。

“每秒金币”字段显示时四舍五入到整数，例如6565.4722222222显示6565；仍按未舍入数值比较是否有真实变化。百分比、秒数、普通小数属性及已有15.0w等缩写规则保持原口径。这只是显示格式，未修改金矿实际收益、消耗或升级交易。

## 成本与验证

- 不新增场景/物品扫描、面板、计时器或请求。窗口、菜单、全屏结果和演出surface均通过直接引用处理，O(1)时间/空间；每次Apply只额外读固定两面板的输入标记，值相同不跨原生桥重复写入。关闭/重新打开只有真实输入状态变化才写入。
- 金币字段在原有字符串解析基础上增加O(1)的数值取整；原字段长度L的解析成本仍O(L)，不改变服务端数据精度或网络负载。
- 树外证据：`D:/Survival_本地工具/runs/20261110_lottery_escape_gold_format01`。旧格式负对照原样显示长小数；旧退出路径保留全屏结果层。修改后7项格式检查及精确操作顺序（继续十连→请求中→Esc→晚到/重复回包→显式重开）通过，不重放付费请求，保留实际返回的10个结果。
- 现有 `ability_tooltip_compact`、`lottery_gw2`、`lottery_preview_controller`、`lottery_buffered_controller` 四套通过；均为合成桥/原生事件模拟，未自动抽取真人券。普通客户端本轮Esc后的实际点击和电影帧仍待用户实机确认。

## 编译与真实交付

- 专用打包任务 `pack_2026111009_814969f8` 已完成全部阶段。不可变运行来源：game `f5f80dd7ee1c10983b60e0869bca53205bc665d6`，content `23ab62a9b47ae3c86a2ac79c743b28709e49bffd`；构建operator为同一game提交。最终知识记录提交不改变运行来源。
- 5份官方隔离编译资源逐项核对proof摘要及实际DATA；对实际DATA重跑金币格式、继续十连请求中Esc/晚到和重复结果/重开、演出输入关闭、紧凑tooltip检查，全部通过。证据 `D:/Survival_本地工具/runs/20261110_lottery_escape_gold_format01/official_data_verification.json`，含编译DATA和测试日志路径。
- 签名、SDK上传、Steam强制完整下载、来源全量收口均通过；7056个签名资源、5个包文件一致。最终 `delivery_status_1.stdout` 为 `WORKSHOP_SYNCED`，pending/blocking/historical_sources/dirty_runtime/pending_resources均0；保留5份原有非运行修改，不纳入本轮提交。未部署后台、未自动使用真实券或兑换码。
- 包报告：`output/packager/pack_2026111009_814969f8/package.json`，SHA256 `1c1d3f6a858501bbe1b03b8c727faedad624690f7042e37148f0161b39870d59`。签名manifest SHA256 `b3aba155baab5cff4b5dfbb2785bdde66fd4ac4e1adc3641dd1b3832023a973e`。
- 官方完整下载回执：`output/packager/pack_2026111009_814969f8/download_evidence/20261110T103620Z_29f617b0d1af4110a040cf2d4228d16f/verification.json`，SHA256 `9b8588be8f14500cec90f6ae4f3af654463b47812d2c17bf35c18ea145b09491`。其 `native_test` 与 `multiplayer_acceptance` 均为 `NOT_RUN`；文件和模型回归不代替新普通客户端观察。
- 双仓按stash→pull→本次stash pop→commit→push同步；最终Git HEAD、保留状态和回执摘要在树外 `D:/Survival_本地工具/runs/20261110_lottery_escape_gold_format01/final_delivery_receipt.json` 登记，不创建content空提交。
