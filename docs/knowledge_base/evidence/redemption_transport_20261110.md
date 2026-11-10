# 四档金色券登记后的真实领取协议排查（2026-11-10）

用户最终确认：输入完整码后既无成功提示，也无失败提示。之前选择“显示成功但券没增加”的回答已被更正，不据此认定服务器成功发过奖。

线上只读核对四档定义：100/500/1000/2000 数量、哈希、启用、开始时间、无期限与无限全服次数均正确，总定义 136。四档 reserved_count 均为 0、领取记录均为空；线上最后一条兑换记录为 11 月 2 日，近两小时仍有其他玩法交易。没有重试生产 apply、重新生成码或补发玩家库存。

在实际现役 `/opt/goufayu-ws4/releases/20261106-ws4-daily-refs-ed532ea60d2b`，用不连接数据库的合成请求复现：`response_capabilities={archive_profile_refs_v1=true,archive_profile_refs_v2=true}` 被 `redemption_codes.command` 的旧顶层字段白名单拒绝，报 `redeem_request_invalid`；真实 HTTP 适配器将该错误返回 400。这解释请求在进入限领和发奖事务前中断，不将未观察到的提示行为推断为客户端已经修复。

最小运行修复仅为 `server/archive_backend/redemption_codes.py`：允许三个既有布尔传输能力、最多三项，拒绝非法类型、未知字段和客户端奖励输入；能力字段不进入 RPC、真实码、账号或冻结奖励。原 normalize/settle/finish 以及 command 的身份和奖励流程保持。客户端源码、编译包和发行配置无变化；沿用已同步游廊 2026110902 / manifest `6445398778833066003`。

新增正式入口 `tools/ws4_redemption_transport_20261110/deploy.py`，复用摘要固定的现役 daily-refs 部署控制器及其 drain/watchdog/recovery。不可变源码和 operator 提交后，按 audit/prepare/probe/activate/verify 部署，只更新一个后台 Python 文件；旧完整版本、原始 unit 与回执保留，不改 SQL 或重启支付/认证。

成本：新增能力校验最多 3 项，时间/空间 O(1)，初始化/稳定刷新无新工作，真实交易仍 prepare+commit 两次 RPC，既有冲突恢复上限不变。没有新增循环刷新、游戏原生调用或网络请求；合成精确数量验证不代表真人到账或 FPS。

诊断和回归均在 `D:/Survival_本地工具/runs/20261110_gold_ticket_delivery_diag01`：`live_diagnostic_v01.json`、`activity_v02.json`、`http_contract_v03.json`，均无真实码明文、身份或凭据。首个隔离探针因独立 Python 模块的相对导入失败；修正探针包身份后 53 项通过，前次失败证据保留。正式部署与独立核验结果在实际完成后补记。

## 实际部署完成

- 源码/operator：`80e0eb4e301d10713317583e5556b365bcc8280f`，content `151c77f5a7580151a2553efa330fa76c1ef10240`，双仓按 stash/pull/pop/commit/push 同步。唯一实际运行更新的 Python SHA256 `ad57165cadc9d798c7717ed07ea27350b435bfd02f754488ca2ca6bcfc45fd47`。
- 53 项协议/排空/恢复检查与原有 48 项金色券回归通过，共 101 项。回归使用已有带 openpyxl 的 Python；首次误用不带此依赖的安全工具 venv 导致 10 个测试环境错误，未安装依赖或改生产环境，失败记录保留。
- 实际服务器候选探针：16 个真实 Linux Python/Lua 四档精确数量、普通券保持和重试单次提交向量，以及 11 个非法输入，通过。RPC 均为合成内存替身，实际生产 RPC/真人兑换为 0，未以该探针冒充真人到账。
- 已部署现役版本 `/opt/goufayu-ws4/releases/20261110-ws4-redemption-transport-ae3e77c24300`，manifest SHA256 `25d4ea97b6c1a91ba868a978a975873c87ea65a616ffc9ff088db420fbda5cd4`，API PID `1183895`。独立 verify：`ACTUAL_WS4_REDEMPTION_TRANSPORT_ACTIVE_VERIFIED`。API 实际 `POSTGRES_DSN` 仍是 loopback `15432/goufayu_ws4`。
- `output/ws4_redemption_transport_20261110_v01/prepare.json` SHA256 `984ceaf97e612940e6d62ac84a17f667f58fa442a76334d51792bf140d27e40f`；真实生成回执以树外 `candidate_storage_receipt.json` 登记，记录仅登记本机控制回执与远端版本引用，不冒充远端磁盘扫描。
- 同目录 `probe.json` SHA256 `46b8c41f3374a5dfbcfa6f7d603b55e6d8aeb206dd27ffc31111ec933ddf5e72`；`activate.json` SHA256 `110f2264d0a43c1f3d38806fbf215ba864c7d46404a59a6333769c30c98ddee1`；`verify.json` SHA256 `6fa2ddc3d470b8e3635cded0afe13af69c1b97a60e916f4b286b8c896698c141`。旧版本、完整源码、副本、unit 备份、watchdog/排空回执保留，未删除或清理。
- `postdeploy_inventory_v01.json` 独立只读复核：136 项、原132项定义摘要保持、四档奖励与原登记完全一致；此时四档领取仍 0。两支付 PID `5427/240881` 与其他受保留服务不变，只有 WS4 API 正常排空重启。沿用既有启动同步策略，不宣称服务启动绝对零数据库写入。

当时已请用户使用原码重试；用户遇到旧本机签名入口版本失配，后续修复正式入口并获“已经没问题了”确认，见[最新入口与反馈](published_online_entry_20261110.md)。没有提供具体档位/数量或代兑真人码，不把独立部署核验写成完整真人发券审计。服务器核验时客户端为已同步0902 / Steam manifest `6445398778833066003`，另一个光效任务随后发布1001；本轮没有游戏编译、签名或 SDK 上传。
