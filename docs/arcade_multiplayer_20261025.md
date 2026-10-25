# 游廊多人诊断与 v08 单人入口恢复（2026-10-25）

**当前已退回 v08 单人入口；直接四人联机尚未打通。** 原不公开列出条目 `3824360109` 已成功重新提交既有签名 v08，官方重新下载的 6630 份资源、四卷及五份 VPK 全部校验通过。新 manifest 下已观察到原入口跳转、`GAME_IN_PROGRESS` 和单人 N1 玩法；网页登录各次点击归因未记录，具体云存档数值未重新审计。

本轮记录见 [多人诊断及恢复记录](../publishing/workshop/multiplayer_entry_20261025.json)。标题、说明、封面、可见性、四个测试账号和独立存档环境保持不变；本页不提供四人可玩操作流程。

## 当前正式版本

| 项目 | 实际状态 |
| --- | --- |
| 当前版本 | 已签 v08，发布序号 `2026102503` |
| 内容 SHA-256 | `88611d026e49c52b5bce7324818f36a11a60059a2844b8f646b884ba15debaa9` |
| 当前官方 manifest | `3443060898060848239` |
| 默认入口 | `ws4_entry`，1 人；按既有代码重开同条目的 `template_map` |
| 资源与包 | 6630 份资源、四卷、五份 VPK；包总大小 3,767,020,414 字节 |
| 恢复提交 | 成功，原条目、不公开列出，子进程退出码 0 |
| 恢复后官方完整下载 | `PASS`，真实 1313 订阅刷新与 3406 下载回调、零缓存查询及全签名 CRC/hash 校验 |
| 本次新 manifest 原生入口 | `SINGLE_PLAYER_N1_OBSERVED`：原入口跳转、进入游戏日志及 N1／建造者／波次倒计时已观察；进程 `33636` 保留运行 |
| 直接四人联机 | 未打通；无真实双人验收 |

恢复提交证据为 `output/arcade_multiplayer_20261025/rollback_v08_apply_once/result.json`；官方完整下载证据为 `output/arcade_multiplayer_20261025/v08_restored_download_evidence/20261025T050330Z_ece7de941c5f4d83ab8e1509fb2ed074/verification.json`。本次原生结果见 [恢复后原入口 N1 观察记录](../output/arcade_multiplayer_20261025/ordinary_restored_v08/result.json)：新 manifest 下日志记录原入口跳转和服务端／客户端进入 `GAME_IN_PROGRESS`，画面显示 N1、建造者与波次倒计时。这是本次新的恢复验收，不改写原 v08 曾经上传失败的历史记录，也不继承旧 v05／v08 的原生登录 PASS；未记录每次网页登录点击归因，不宣称由执行者本人完成批准，也未重新审计具体云存档数值。

## v09 直接四人诊断结果

v09 状态为 `FAILED_ARCADE_AUTH_ROLLED_BACK_TO_V08`。其签名候选、源码及全部证据保留，不作为当前可玩的多人版本交付。

| 项目 | v09 事实 |
| --- | --- |
| 诊断版本 | `WS4-MP-09`，序号 `2026102504`，SHA `839fd6edb8373af2967d0cd7de93370fb737ed0e79200a9ae622624a27a6402d` |
| 发布与官方包 | 曾成功发布，manifest `1268500595793419792`；6630 份资源、四卷及五份 VPK 完整验签通过 |
| 本机 Tools 有限冒烟 | `PASS_FOUR_SLOTS_AUTH_CHALLENGE_ONLY`：1 真人、3 空槽，cheats 关闭，公开健康请求 200，出现真实短码；未批准、未读档 |
| 普通无 Tools 游廊 | 确实创建四槽原生房间；只有 1 名真实玩家，正常开始后认证失败 |
| 认证失败 | `WS4-WEB-04 / start / create / 0`，手动刷新仍失败，没有后台 HTTP 响应 |
| 真正双人 | `NOT_RUN_AUTH_BLOCKED`，没有第二名真实玩家 |
| 裸 `changelevel template_map` | `NETWORK_DISCONNECT_CLIENT_NO_MAP`，作者 Dota 退出；不能作为保留多人连接方案 |

普通游廊证据见 `output/arcade_multiplayer_20261025/ordinary_arcade_steam/result.json`。原生状态画面确认 `sv_cheats=false`、`GAME_IN_PROGRESS`、GCMatchID `9060692846` 及 CustomGame `3824360109`，所以不能再将错误解释为尚未正常开始。最初两种 HTTP API 的工厂调用未抛错，但请求对象均为 nil；后续阶段探针日志未观察到，**不宣称完成全阶段采样**。短码创建失败发生在发送 HTTP 前，不是后台返回拒绝。

v09 最初曾收到下载成功回调却仍安装旧 v05，严格校验当时正确拒绝。对既有条目执行一次 `SubscribeItem` 刷新、收到官方 1313 成功回调后，状态由 5 变为 13，Steam 随后识别新 manifest，3406 下载及完整校验通过；没有 unsubscribe。v09 完整下载证据为 `output/arcade_multiplayer_20261025/download_evidence/20261025T035953Z_01b105738ff940aaa70668dadd40f615/verification.json`，订阅刷新证据为 `output/arcade_multiplayer_20261025/subscription_refresh.json`。之后的普通游廊认证失败与资源未更新无关。

## 保留的构建与验收边界

相对 v08，v09 只修改默认地图值，在冻结主 Lua 的精确末尾 `return M` 前插入审阅过的 549 字节包装，新增公开健康探针，并从新候选省略旧 `maps/ws4_entry.vpk`。180 份保护模块原样保留；移除包装即可逐字节恢复冻结主 Lua。旧签名候选及仓库地图资源未删除。

本地包目录 VPK 的 SHA-256 为 `51c2894e7bfe0c62d6525a2f11406d317f50cb48bfdf81a6185ca60c0f449f26`；本地包校验及官方完整下载是资源完整性事实，不代表授权、读档或多人玩法成功。松散临时别名加载也不计为原生 VPK 专项或大于 2 GiB 专项读取验收。

临时 v09 冒烟进程 `28108` 正常关闭后，事务 `a5a06221df45445d9dd5dbdb76243c90` 记录 `RESTORED / full_after_verification=true`，本机原签名 v08 别名完整恢复。此前进程 `11912` 阻塞替换的 `changed=false` 仅保留为历史。

只读上传预检曾在 `output/arcade_multiplayer_20261025/upload_preflight_absolute/result.json` 以退出码 0、`VERIFIED_NO_PUBLICATION` 通过，预检本身提交次数为 0；之后 v09 实际上传与本次 v08 恢复是分别记录的操作。Python 安全回归共 85 例通过，包括上传器 20 例和此前三套 65 例；探针 Lua 1332 项、旧入口 Lua 87 项和 3 份 Lua 5.1 语法检查通过。上传器的新版本原生及普通游廊验收从 `NOT_RUN` 开始，旧证据归档历史。

旧 v07 的五份派生 VPK 已清理，回收 3,767,018,374 字节，签名源候选保留，见 `output/arcade_multiplayer_20261025/v07_cleanup_result.json`。原 [v05 发布回执](../publishing/workshop/workshop_entry_release_20261024.json)、[v08 失败记录](../publishing/workshop/ui_data_qa_release_20261025.json)、原 pending journal 和全部原始备份均未改写。原 listing 的独占备份仍为 `output/arcade_multiplayer_20261025/test_listing.before_v09.original.json`，SHA-256 `919f5c664efa779a66c24c7fbb2b6724adea1dab61e573f3476b6c1873a891fb`。

联网禁作弊、四账号限制、独立测试存档、真实付费和可信排行榜关闭的约束继续保持。临时 Steam 验签出站仍依赖作者电脑与现有网络在线。恢复后已新观察到单人 N1，双人仍未验证；当前不提供退休 VPN/CMD 入口或已失败的换图操作作为玩家联机方案。

## 冻结版本的多人边界

对签名 v09 的静态复核未发现两名正常到齐并分别批准的玩家必然无法开局的错误；账号、本局及存档响应身份均有核对，未发现串档路径。这不能替代真实双人测试。

准备服务保留已经发现的成员并等待全部准备完成；有人在准备阶段永久离开，剩余玩家会继续等待，需要原玩家回来或重新建房。准入完成后名单冻结，不支持新增玩家中途加入。本次先按所有人到齐再开始的流程验收，不将上述行为描述为已支持自由进出。

断线重连还须检查：若引擎更换玩家实体，认证可能重新进入等待，而准入后的请求入口及授权界面已经关闭。普通游廊的原生房主权限也必须实测，不能以 Tools 的选择者回退验证替代。验收时需验证准备期重连、原生房主可选模式且其他玩家不可选，以及各玩家分别保存到自己的档案。
