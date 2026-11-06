# 0601 已签完整候选与 WS4 紧凑回执部署

2026-11-06，**仅本地更新（客户端）；后台已部署并验证**。新客户端版本 `2026110601` 已完成完整构建和签名，但没有安装、普通客户端准入或 SDK 上传。正式游廊仍为 `2026110104`，Steam manifest `7025356658517360342`，不能称已同步游廊。

## 客户端来源与完整构建

S29 两仓已按用户最新的 commit → push 顺序推送并核对远端：game `b4c2d904b6e520c2e1c62656cd2c05772b38e3f6` → `dev`；content `001bfa9973c8d03e70bb9f5773203dec5a35851e` → `master`。package operator 为 `b4c2d904b6e520c2e1c62656cd2c05772b38e3f6`。这是当前候选的不可变来源，后续文档提交不替代该绑定。

本轮 152 项同源官方编译资源、186 个 Lua 保护模块和 7035 个完整运行资源均进入新构建。构建回执确认签名、完整资源 CRC 及双摘要校验通过，候选包含一个索引和四个数据卷；没有继承旧版本的原生验收结论。

- 内容摘要：`55d71de710b8cd33223dd55d8a5fa8d739783111326c6fdb7821de020740699b`。
- 签名 manifest：`3848f8f57d730480ef3ac5e41afeb89b2a400eb1c36087e3a42c4915b16c6d70`。
- 新 `package.json` 摘要：`ff0bca274e1c970a301819677352c26da756e028b4823d35c3ce851879f0b901`。
- 构建状态：`BUILT_SIGNED_COMPLETE_CANDIDATE_PENDING_NATIVE_ADMISSION`；`native_admission_verified=false`、`installed=false`、`workshop_upload_performed=false`、SDK 调用 0。

完整待发工作仍保留。签包、双仓 push 和后台上线都不等于客户端已发到原游廊条目。

## 后台已完成的实际动作

WS4 已依次执行实际 audit、prepare、隔离 probe、activate、verify，并完成额外只读 postcheck。当前发行 `20261106-ws4-compact-receipt-d15b405cfb16`，manifest `5ae22761341595aa94731e6f226f598ad6665dc8c18c8db03fe857e254d8ba1c`，API PID `956554`。后台业务来源为 `be527d27f939979d803a03cbb8d04423fffc54cd`，operator 为 `b4c2d904b6e520c2e1c62656cd2c05772b38e3f6`；在已验证父版本上只应用三个本轮文件的精确变更，保留原有 onboarding 路由。

部署前控制逻辑及失败补偿通过 54 项本地测试。实际切换获得两次排空样本：单一主线程、无子进程、无活动连接；仅切换 WS4 API。原父版本保留，相关其他服务 PID 不变，部署回执数据库写入 0，未进行真实玩家交易。postcheck 再次确认唯一精确规则已移除、看护已完成且退出、目标 unit 与原记录一致；没有追加网页登录或认证请求。

## 优化收益的准确边界

三轮真实 Linux Lua、隔离内存回执探针中，旧兼容路径为 98,670 字节、均值 275.556 毫秒；紧凑路径为 9,154 字节、均值 137.645 毫秒，worker 从两次减为一次，奖励、随机数和最终存档结果一致。这些数值不包含真实 PostgreSQL、HTTP、认证和网络往返，不能当作实际领取奖励已低于 1 秒的证明。

当前游廊 0104 客户端没有 `lottery_committed_profile_v1` 能力标记，仍使用兼容完整投影。紧凑回包收益需要新客户端实际运行并发送能力标记，不能把后台部署直接解释为所有现有客户端已获得相同收益。分段耗时记录已上线，旧客户端也可产生记录；阶段有嵌套，不能简单相加，也不能以没有日志断定没有请求。

## 实机与发布仍待

用户再次明确允许继续后，GUI 排演操作仍被工具返回 `rejected by user`；没有改用其他输入通道绕过拒绝。两轮独立视频 LAB 已正常关闭并移除自有目录链接，未完成 A/B/C/D 实际播放。0503 观察到的是原生 Movie 失败后的备用动画，不能沿用为 0601 视频播放通过。

0601 尚无新的普通客户端视频、网络封套、FPS 或真实小于 1 秒耗时结论；完整 UI、连续播放与失败恢复仍待验收。0503 已用完此前授权的 30 张普通券，剩余授权 0 张，本轮没有新增消耗；不得自动再抽。之后仍须原游廊 SDK 成功回执、该版本官方下载逐文件一致以及待发清单收口，才可称已同步游廊。共享支付目录/PWA按用户决定另案处理。

## 保留改动与证据入口

S29 回执中 game 原有五项未提交改动均保留，content 工作区无未提交改动：

- `M server/archive_backend/__pycache__/match_modes.cpython-314.pyc`
- `M server/bundles/current.json`
- `?? tools/monster_portrait_release_20261030/finalize_package.py`
- `?? tools/monster_portrait_release_20261030/verify_download.py`
- `?? tools/prepare_delivery_operator_20261103.py`

私有证据仅在本地引用，不把令牌、原始 session、密钥位置或完整日志复制到知识库：

- `output/complete_delivery_release_20261106_v01/package.json`、`canonical_build_runner_receipt.json`：新完整构建及签名回执。
- 同目录 `source_pins_s29.json`、`s29_git_receipt.json`、`gen10_compiled_import_receipt.json`：双仓来源、推送与编译范围。
- `output/ws4_compact_receipt_20261106_v01/{audit,prepare,probe,activate,verify}.json`：实际后台阶段。
- `output/complete_delivery_release_20261105_v03/backend_draft/ws4_active_postcheck01.json`：独立只读收口，SHA256 `ff5fd545f955125e605f97e34d1fdd854740f8998a6cafebc9599b52663b51f3`。
- 同目录 `actual_ws4_deployment_handoff01.json`、`ws4_active_readonly_ready.py`：部署边界及后续只读耗时检查；检查脚本本身不代表已取得真实交易耗时。
