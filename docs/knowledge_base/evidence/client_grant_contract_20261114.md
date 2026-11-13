# client-v2 奖励字段合同修复（2026-11-14）

当前状态：仅本地更新，等待主代理提交并用新候选重新运行实际 40 人测试。本项只修正压测客户端对回包的校验，不修改业务 API、奖励计算或 SQL，不构成真实奖励流程或容量已验收的证明。

## 实际失败与原因

B40 的真实运行 `4476180c91e0f9ef372821e6702cbac1` 首次收到奖励后，压测客户端报 `grant_scope_mismatch` 并提前结束。该失败与完整采集证据保留，不能被修复后的本地回归覆盖。

同版冻结 `FishingApplication.online_checkpoint` 调用 `_compact_grant_response`，其中 `_compact_grant` 明确只返回 `grant_id`、`reward_id`、`amount`、`definition_version` 四个字段。应用源码 SHA256 为 `8d69cdde0a8f864c4319d7af97f91de8ce639ba3012074a60a1f98fac9f54919`。真实 Lua `scripts/vscripts/systems/online_time_service.lua` 的 `validated_grant` 检查本地 CSV 定义的 `effect_scope == "permanent"`，不要求回包携带该字段，并返回上述四字段。

原压测校验同时要求本地定义和回包均含 permanent scope。回包刻意省略了 scope，所以合法奖励也被拒绝。

## 最小修正与边界

`tools/loadtest_lab/workload_profiles.py` 的 `ClientProfile.grants` 改为只检查已绑定本地 CSV 定义的 scope。定义启用状态、奖励 ID、版本、数值有限性和范围、UUID 格式、128 项上限均保留。有效奖励后的真实 profile HTTP 刷新、重复回包刷新、最终完成流程计时、失败释放且不自动重试均未改变。

只有该条件发生 AST 变化；`workload.py`、`locustfile.py`、业务 API 和 SQL 均未修改。复杂度仍为初始化 O(D) 构建一次定义索引、每回包 O(K) 校验，K ≤ 128，无额外网络调用。

## 为什么原 19 项检查漏测

原 HTTP 测试的手写 `grant()` 额外放入 `effect_scope`。原真实 Lua 测试另建了不含 scope 的向量，但没有把同一个真实规范化返回送入 Python 校验。因此两个分开的测试都通过，未覆盖实际应用的四字段边界。这是测试夹具偏离实际合同，不能用此前 19 项通过推断真实奖励流程通过。

## 本轮验证与来源

树外候选：`D:/Survival_本地工具/runs/survival_capacity_autonomous_20261113_01/client_grant_contract_candidate_01/workload_profiles.py`。

- 16 项继承定向检查通过：使用冻结 B40 应用的 `online_checkpoint` 与受控 Fake RPC 生成四字段奖励，覆盖本机 port0 HTTP checkpoint → grant-followup profile → release、重复奖励、异常释放、身份、版本、金额和 UUID 检查。Fake RPC 不执行 SQL。
- 一项共同向量和旧版负对照通过：上述实际应用四字段输出送入源码提取的真实 Lua `validated_grant`，再把 Lua 实际输出的四字段 JSON 送入 Python 校验；修复版接受，冻结旧版必报 `grant_scope_mismatch`。本地 immediate 定义仍拒绝，非法版本、数值和 UUID 仍拒绝。
- 没有在此回归中访问 SSH、固定测试端口或 PostgreSQL。实际真实奖励及 40 人复测仍待新候选完成。

回执：

- `D:/Survival_本地工具/tests/loadtest_client_grant_contract_20261114_01/verification_receipt.json`（16 项）。
- `D:/Survival_本地工具/tests/loadtest_client_grant_contract_20261114_03/verification_receipt.json`（共同向量及旧版负对照）。
- `D:/Survival_本地工具/runs/survival_capacity_autonomous_20261113_01/client_grant_contract_candidate_01/implementation_freeze_receipt.json`，SHA256 `9d3266876d1a23d2fb8b3fd4cc9d191b295f4a17695bcf63addf1dc37959bd63`。

02 测试尝试因把工作区 CRLF 原始摘要误作冻结 LF 摘要而失败，证据保留；03 使用真正冻结的旧实现字节后通过，未修改候选。

父源规范 LF SHA256：`ed4a644935e8a17aa5cc4bf37051c37afe8495aa1ae5be910dc4dd045248c454`。

修复源规范 LF SHA256：`27f32d478da48135015a46fe4c35bd738e0a6defee01af4c93b20840d5f21f89`；本机候选与复制后的主文件原始字节 SHA256：`130b8a74ab4e5b354b0444894e482e990510700d335ac1153746a5062122a3b3`。
