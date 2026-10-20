已发布并验证：`20261020-mode-chain-b3c342e1de0d-v1`。operator tar SHA 为 `109190b5bb0dbd4aa4ca40e965c472a7ba8327aeefe4ab8a2e51823d1602ba9f`；实际加载 bundle、数据库就绪、进程目录和支付健康均通过。游戏端指针已在后端验证后接入，正式记录见 `validation/20261020/mode_release.json`。下文保留本次准备与执行流程。

当前工具只对应 `20261020-archive-caps-v1` 基线：manifest `30b3400c…`、父 bundle `ecf55dd6…`。旧 lottery-catalog 基线、`f13898…` 候选及旧 `operator_review` 包已作废。新 sealed 候选为 `3271354e33297ee4da9c25713037a8049fdd2be5548bed324f0911e095aaf4c3`，新 bundle 为 `b3c342e1de0de5d8c5b21471eb87a6af288a177e88d1875e43d9fcae24c3af93`。

工具准备阶段只运行本地检查和只读 SSH；正式发布由 root 在预检通过后依次执行。两次新现场 SSH 当时返回 255 且没有记录，表示连接不可用，不能据此判断现场漂移。最新实时状态保存在 `output/mode_progression_release_20261020/operator_caps_review/preflight_status.json`。

可直接审阅的具体范围在 `operator_caps_review/local_scope_preview.json`。本地 `preview` 已验证 sealed tar、完整清单、基线文件与差异：只覆盖 `backend/archive_backend/match_modes.py` 的父链 gate，以及 `unique_points.py` 对新 hash 的等价抽奖 pairs；新 bundle 只改 welfare 四种胜场合计和已接受的临时难度继承。全部 configs、CSV、worker、其余 Lua、每日额度、商城、catalog 缓存、传输、旧 hash 都保留现场版本。

数据库只新增 `202610200004_mode_unlock_chain.sql`（SHA `da1b05ef…`），替换 login 父链函数并保持 ACL。已执行的 17rich、002（`70a8ddb2…`）和 003（`52289172…`）仅作为必须保留的 ledger，绝不重跑或改写。新 registration guard 只插入一个精确新 hash 分支；删掉此段后必须逐字节等于 caps guard（SHA `4b7f47f6…`）。004、其 ledger、新 guard 和新配置注册共用一个数据库事务。

本地命令（不连接服务器）：

```powershell
$modePython = (Resolve-Path output/ecs_backend_work/.venv/Scripts/python.exe).Path
& $modePython -B tools/mode_progression_release_20261020/test_mode_release_operator.py
& $modePython -B tools/mode_progression_release_20261020/mode_release_operator.py preview
& $modePython -B tools/mode_progression_release_20261020/mode_release_operator.py check
```

15 项本地测试已通过，包括实际 driver 拼接 STAGE/MODE 并经 SSH 外层 try 包装后的完整脚本编译；测试拦截 subprocess，不执行 SSH。无最终 plan 时，`check` 只报告 sealed 候选已校验、仍待实时 preflight，不生成虚假的可执行包。`preview` 是具体范围审阅计划，`deployable` 固定为 false。

连接恢复后的两个准备命令：

```powershell
& $modePython -B tools/mode_progression_release_20261020/mode_release_operator.py preflight
& $modePython -B tools/mode_progression_release_20261020/mode_release_operator.py plan
```

`preflight` 只读，固定 release/manifest/bundle 和已执行002/003，记录完整 ledger、旧配置 hash、全部应用 SQL 函数定义与 ACL、公共约束、16 RPC、最小权限及支付指纹。还用已有 token 在服务器内部读取 `/ready` 和 `/v1/archive/config`，核对实际加载 hash 与 MainPID 的 cwd 精确为 release 根目录（与已核对的现场 unit 一致）；不登录、不建账户、不打印或导出 token。`plan` 只在本地封包，将精确现场 pins 固定到 `operator_caps_review/plans/<SHA>/mode_release.tar.gz`，并输出 `checked_mode_release.json`。再次执行 `check` 检查该包和工具 selfhash；变更工具后必须重封包。

以下为审阅通过后由 root 显式执行的发布顺序。`$reviewedModePlanSha` 必须来自已独立审阅的 `checked_mode_release.json`，不可使用候选 tar SHA 或旧包 SHA：

```powershell
$reviewedModePlanSha = '<完整已审阅operator tar SHA>'
& $modePython -B tools/mode_progression_release_20261020/mode_release_operator.py upload --execute-reviewed-plan $reviewedModePlanSha
& $modePython -B tools/mode_progression_release_20261020/mode_release_operator.py backup --execute-reviewed-plan $reviewedModePlanSha
& $modePython -B tools/mode_progression_release_20261020/mode_release_operator.py prepare --execute-reviewed-plan $reviewedModePlanSha
& $modePython -B tools/mode_progression_release_20261020/mode_release_operator.py validate --execute-reviewed-plan $reviewedModePlanSha
& $modePython -B tools/mode_progression_release_20261020/mode_release_operator.py activate --execute-reviewed-plan $reviewedModePlanSha
& $modePython -B tools/mode_progression_release_20261020/mode_release_operator.py verify
```

五个写阶段均要求最近一次 preflight 的完整摘要与已审 plan 完全一致。工具先校验白名单 tar，核对私有 DB dump/source tar SHA，然后从现场 manifest 复制全部旧文件到新的 immutable release `20261020-mode-chain-b3c342e1de0d-v1`，仅覆盖精确白名单。激活前再次核对现场；成功后验证实际数据库 ready、加载新 hash、服务进程目录、全部函数/约束/ledger、旧配置及支付指纹。支付服务不切换，本机游戏 hash 由 root 在后端 verify 成功后另行接入。

失败恢复及显式 rollback 只恢复 archive 服务指针，保留新增004、guard、配置、ledger和所有已获进度，不把旧 DB dump 覆盖到已付费或已获奖励的数据上。COMMIT 结果无法由新只读连接明确判定时，archive 保持停止，记录恢复状态。显式 rollback 同样要求完整已审 plan SHA：

```powershell
& $modePython -B tools/mode_progression_release_20261020/mode_release_operator.py rollback --execute-reviewed-plan $reviewedModePlanSha
```

正式工具仅六个：`mode_release_operator.py`、`mode_release_preflight.py`、`mode_release_remote.py`、`mode_release_upload.py`、`test_mode_release_operator.py`、本文件。候选、快照、封包及验证输出留在 ignored output 中。
