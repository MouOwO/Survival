# 0804｜最新完整代码已同步封闭游廊（2026-11-08）

已同步游廊，后台本轮未部署。原条目 `3824360109` 现为 `2026110804`，Steam manifest `8362187116891559911`。7053 个运行资源、5 个 VPK 文件的官方完整下载逐文件核验通过；当前双仓运行待发、未知来源和延期项均为0。

用户本次明确授权“授权按线上测试版先上传，实机验收待测”。授权只绑定这一个实际签名包、父 journal 摘要和发行代际，不构成后续版本、后台部署、付费抽奖或兑换码消费授权。`ordinary_production_acceptance=false`、`native_acceptance_status=PENDING_USER_ONLINE_TEST` 原样写入完整来源检查点；默认普通发行仍要求真实同版普通客户端验收。新版本功能、多人、FPS、连续抽奖视频与兜底表现由后续线上实机确认。

## 完整来源与交付

以真正已发布0104签名 manifest 为父重新收集：675项来源全覆盖，其中242项历史待发；7053资源、449项变化、7项删除，未知/延期均0。删除的旧 onboarding 布局、脚本、样式及四项离线Lua已反映在新运行 manifest，未靠覆盖遗留旧资源。

- 运行与构建 operator：game `32ef4951041f3cc2e115fe2ad114b3d030acbf80`；content `e081389bfd0bfdd785cfb1572ab5bf95a3655c46`。
- 本次精确线上测试发行策略 operator：game `fb4f38ce646d41f01c2e0c047efd4fe42311954b`。发行工具绑定独立于已完成的签包构建，不重标旧生产证明。
- 新目录：原 producer game/operator `03ecf060b28b8c7212c77e88f2962a7e5423e9ae`、content `534c3c8a2c5ed0871d9d699a7b3dd9a4a7d78bb0`；7942记录/188字段，完整 ID 历史保留。
- 172项官方隔离编译：game/operator `563e21f11f2efc39484d2ba38e7f765ef06cb4ff`、content e081389b。新增两项 Keeper 粒子纳入严格双仓作者与依赖闭包，官方编译和逐字段DATA核验通过。
- 新生产保护原 producer game/operator `b16629222710c45c2e75441905fdf7b9b7c8c289`、content e081389b；853输入、186保护模块、7项正式策略转换及完整值/RNG核验通过。最终收集重验原始读集与当前输入等价，未复制或改写原证明。

本次最新的十戒连闯、科技/训练队列即时展开、生产 tooltip 前景层、原生错误横幅、金矿共享科技特效、武器成长中文名称、Keeper 弹道和全部历史未发布运行修改均由完整来源清单覆盖。具体资源与删除项以实际投影、签名 manifest 和机器摘要为准，不以本段举例作为固定 PAYLOADS。

## 实际签包、上传与官方下载

`output/complete_delivery_release_20261108_v04/package.json`：实际包大小3,811,715,196字节，4个数据分卷与1个索引，精确5文件集。签包位于树外 `D:/Survival_工坊输出/2026110804_network50_complete_v01`，运行 view、trusted、overlay 也均为新建独立树外目录。

单独完整审查实际74.665秒，通过全部来源、签名、运行资源和 VPK 校验。首轮审查器在成功加载完整包后将VPK文件误当目录，未记为通过；第二轮更正为索引父目录后通过。登记器拒绝非白名单的审查文件名，原失败保留；按原始字节另存白名单回执后已真实登记，未伪造日期或覆盖原记录。

统一 `tools/release_pipeline.py` 通过同一受校验 lease 向原条目实际提交一次 SDK 更新。generation 1、pending null，canonical journal 为真实 `SUBMITTED_UNLISTED_PENDING_DOWNLOAD_AND_NATIVE_TEST`。封闭可见性、五个获准账号、四人容量及原后台/收费规则保持。

组合 complete 在上传成功后未取得下载成功回执，原失败和上传状态完整保留；未再次调用 SubmitItemUpdate。只读元数据/完整上下文、真实进程查询和官方 fresh query 均通过后，独立新进程执行统一 download，取得真实3406/result1：请求 `2026-11-08T15:13:52.881747+00:00`，回调 `15:15:10.428748+00:00`。下载前后 fresh query 均 cached=false/max_cache_age=0；7053资源、186保护模块、全部分卷 CRC32/MD5/SHA256、签名与精确大小验证通过。没有手改ACF或拿内容句柄hFile充当Steam manifest。

真实回执：`output/complete_delivery_release_20261108_v04/download_evidence/20261108T151522Z_8670a153e05741189aa96080d9b89e7c/verification.json`，SHA256 `ad613893724971facfd33b16103fbb2eaff083197b8b2e5ce00758ff89ead4d3`。

通过固定 baseline_completion 模块重新实读官方完整安装后，已生成不可变检查点 `output/release_baselines/complete/2026110804_b1d27b3fcfb231f6036005c087836eee5dc2a24dc9419ac8ea747326a1b7f644.json` 并更新 complete_active.json。收口675来源，未额外上传或改写SDK journal；随后统一 delivery-status 返回 WORKSHOP_SYNCED、blockers[]、pending=0、dirty_runtime=0。

## 成本、验证与保留

发行工具只在显式操作时执行：按5个包文件、7053资源、675待发来源做 O(B+F+S) 流式哈希/索引核对，额外官方安装复验一次；游戏初始化、稳定刷新和状态变化均未增加帧循环、计时器、原生桥或网络调用。实际 CLI 全包审查74.665秒、最终安装/来源检查点111.938秒不代表游戏帧率。来源/工具检查124项、后续精确审查64项、测试发行策略78项相关回归通过，模拟检查不替代原生验收。

本轮所有签包、unsigned、官方编译、生产保护、导入前备份与观察回执已按真实回执登记树外清理记录；补登记明确为本次观察。早期外部驱动将命令结束后的记账时间误命名 started_utc，已另存字段语义更正观察，原回执保留；官方编译/签包/SDK时间不改写。

双仓均按唯一 stash → pull → 精确 pop → 按范围 commit → push 执行。Tools产生的78项运行字节已在迁回不可变来源前逐文件备份校验，随后172项配套正式编译产物已提交。原有 game 未提交内容完整保留：

- `server/archive_backend/__pycache__/match_modes.cpython-314.pyc`
- `server/bundles/current.json`
- `tools/monster_portrait_release_20261030/finalize_package.py`
- `tools/monster_portrait_release_20261030/verify_download.py`
- `tools/prepare_delivery_operator_20261103.py`

content工作区干净。最终文档提交与双仓上游检查以本轮树外 git_delivery_final.json 为准。旧0104父证明、当前0804与被回执引用的编译/恢复备份保留，未凭目录名删除旧产物。

现在使用普通Dota客户端进入原游廊测试。本次没有暂装、keeper、模拟实机或新耗券；旧本地0803/0104排演控制不是新版正式安装身份，后续不能拿旧恢复入口覆盖当前官方0804。下一轮发行须从真实0804官方检查点及新父journal重新建立绑定。

机器事实：[0804公开摘要](workshop_online0804_20261108.public.json)。完整本地执行、失败、备份与最后待发/交付状态位于 `D:/Survival_本地工具/runs/20261108_workshop_latest01`。
