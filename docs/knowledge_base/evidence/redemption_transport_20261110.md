# 四档金色券登记后的真实领取协议排查（2026-11-10）

用户最终确认：输入完整码后既无成功提示，也无失败提示。之前选择“显示成功但券没增加”的回答已被更正，不据此认定服务器成功发过奖。

线上只读核对四档定义：100/500/1000/2000 数量、哈希、启用、开始时间、无期限与无限全服次数均正确，总定义 136。四档 reserved_count 均为 0、领取记录均为空；线上最后一条兑换记录为 11 月 2 日，近两小时仍有其他玩法交易。没有重试生产 apply、重新生成码或补发玩家库存。

在实际现役 `/opt/goufayu-ws4/releases/20261106-ws4-daily-refs-ed532ea60d2b`，用不连接数据库的合成请求复现：`response_capabilities={archive_profile_refs_v1=true,archive_profile_refs_v2=true}` 被 `redemption_codes.command` 的旧顶层字段白名单拒绝，报 `redeem_request_invalid`；真实 HTTP 适配器将该错误返回 400。这解释请求在进入限领和发奖事务前中断，不将未观察到的提示行为推断为客户端已经修复。

最小运行修复仅为 `server/archive_backend/redemption_codes.py`：允许三个既有布尔传输能力、最多三项，拒绝非法类型、未知字段和客户端奖励输入；能力字段不进入 RPC、真实码、账号或冻结奖励。原 normalize/settle/finish 以及 command 的身份和奖励流程保持。客户端源码、编译包和发行配置无变化；沿用已同步游廊 2026110902 / manifest `6445398778833066003`。

新增正式入口 `tools/ws4_redemption_transport_20261110/deploy.py`，复用摘要固定的现役 daily-refs 部署控制器及其 drain/watchdog/recovery。不可变源码和 operator 提交后，按 audit/prepare/probe/activate/verify 部署，只更新一个后台 Python 文件；旧完整版本、原始 unit 与回执保留，不改 SQL 或重启支付/认证。

成本：新增能力校验最多 3 项，时间/空间 O(1)，初始化/稳定刷新无新工作，真实交易仍 prepare+commit 两次 RPC，既有冲突恢复上限不变。没有新增循环刷新、游戏原生调用或网络请求；合成精确数量验证不代表真人到账或 FPS。

诊断和回归均在 `D:/Survival_本地工具/runs/20261110_gold_ticket_delivery_diag01`：`live_diagnostic_v01.json`、`activity_v02.json`、`http_contract_v03.json`，均无真实码明文、身份或凭据。首个隔离探针因独立 Python 模块的相对导入失败；修正探针包身份后 53 项通过，前次失败证据保留。正式部署与独立核验结果在实际完成后补记。
