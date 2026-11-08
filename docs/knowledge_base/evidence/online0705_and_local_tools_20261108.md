# 0705 联网验收包与本地工具整理（2026-11-08）

仅本地更新。用户确认祭坛修复在线下正常后，要求生成联网包，并将独立测试与临时工具移出 Git。0705 已签名、独立核验，并完成真实安装/恢复检查及 PowerShell 启动入口只读检查；尚未启动本版普通客户端，原生玩法、联机、FPS 和发布准入仍待验收。没有调用工坊 SDK 或修改发行 journal，没有后台部署或自动抽奖。

游廊正式仍为 `3824360109` / `2026110104`，Steam manifest 为 `7025356658517360342`。后台保持 `20261106-ws4-daily-refs-ed532ea60d2b`。0705 的签名资源 manifest 不是 Steam 下载 manifest，不可称为已同步游廊。

## 完整候选与来源

- 运行 game / operator：`292da77bb0ff40ff9f9a90ba410d0aa4d8698f8e`。
- 运行 content：`64c2cbda869ee8a26b8abed432bc42a396d31234`。
- 入口依赖修复单独提交于 game `05734ba021439d0c29b4e186cc7e46fa64505e6b`，不改变签包内运行文件或 canonical 构建工具。
- 包回执：`output/complete_delivery_release_20261107_v05/package.json`，SHA256 `f07bfd0b72f43f810ccaf1feb02a0b25a9abe5a65da4825d3ef70adee57eea9e`。
- 运行内容 SHA256：`cfb6639376ce107fb109ae695b545d7f7f025e9f5e1550958410d4f796aabb58`。
- 签名资源 manifest SHA256：`e921ef4349c420b604511304190d0ec2c3650f6d2fdc2c7ed5f07c7f16a1f9ac`。
- 签包目录：`D:/Survival_工坊输出/2026110705_network50_complete_v01`；展开 view/trusted/overlay 均在 `D:/Survival_发布候选`，没有裸 VPK 放入 addon 树。

完整候选包含 7050 个运行文件、`3,806,677,959` 内容字节；相对真实正式基线有 432 个变化路径、7 个删除项。待发源清单 638 项全部覆盖，其中历史未发布源 242 项；延期和未知源均为 0。12 项非运行用途有明确审阅，478 项运行绑定保留。覆盖 ledger 本身不是签发授权，实际签名/生产核验依据最终 package 回执。

165 项官方编译、186 项保护模块与 7 项生产覆盖均按实际生产读集/来源核验，原 producer 提交没有重标。收口期间修正 registry 第 13 代真实父链绑定、完整文件名边界误匹配和 6 份本地化源到产物的受限投影。原失败尝试、原生成回执及各次诊断保留；最终成功使用 attempt03。签名、VPK 全资源 CRC/双摘要/分段及整包 MD5、生产运行校验均通过。独立复核五个实际包文件的大小/摘要、VPK v2 全部资源名、四个分卷及删除项，未发现混入旧包。

此前祭坛落点、单位快切、剑圣临时特效单位、十戒回城、分身手动驻守、圣殿入口及福利已领取光晕等未发布运行修复均纳入本候选。新包实际游戏行为仍需用户验收，不能用编译或模拟测试替代。启动参数默认关闭 `net_showmsg` 详细逐消息输出，未据此宣称 FPS 改善。

## 安装、恢复与缓存漂移

旧 `complete0704_user01` 已正常退出并完整恢复正式 0104。0705 的 `complete0705_stage_smoke01` 在所有 Dota 退出后实际执行 canonical stage 和 restore，两步均 exit 0；未启动游戏。

阶段回执位于上述 v05 输出目录：

- `install_smoke_stage20.json`：SHA256 `706bd6e3cfae94ae2ccc610bac33a3ea4c4f27c03495984fd96611e254c356a7`。
- `install_smoke_restore20.json`：SHA256 `78a09be4c2d1f7f5b86a18d4e9eb397dcb9d536dab6a5530afc32066849b53a2`。

树外事务位于 `D:/Survival_本地排演/complete_delivery_20261103/complete0705_stage_smoke01`；最终状态为 `ORIGINAL0104_COMPLETE_SET_FULLY_RESTORED`。用户后来开启的 Tools 再次引起 71 项缓存漂移，守卫在暂装前拒绝继续；用户确认退出后，全部原字节先保存在 `D:/Survival_本地工具/runs/20261108_online0705/late_compiled_cache01`，再精确恢复冻结的 165 项编译证明。漂移备份 manifest SHA256 为 `591b9804d456c875285468c2a3c92f61854e87078aefe258707752a8e5837ed8`。未强制结束 Dota，未覆盖运行中的正式包。

## 联网 CMD 入口与真实检查

使用项目根目录 `联网登录测试.cmd`。先保持 Steam 登录并退出其他 Dota；入口校验当前签包，完整暂装后启动普通客户端，游戏内正常完成 Steam 网页授权。保留 CMD 窗口，正常退出 Dota 后由原 canonical keeper 校验并完整恢复原安装。出现失败时保留事务和证据，不自动恢复不确定仍在使用的文件，也不会退回旧测试 addon。

入口绑定为 `output/test_entry_runtime/online_signed_candidate.json`，SHA256 `57b0cf4812795efd65a1347b5a2f50b926d855f2f944d4ced0119f2d4d5421e7`；每次通过固定 canonical authority 重新验证，不以工作区 HEAD 或手工 READY 标志代替不可变运行来源。后续纯文档/入口提交不改变签包来源。

实际 PowerShell 检查最初选择了旧 backend venv，因缺少 `cryptography` 失败。修复后 Online 使用独立的发行 Python 选择器：显式 `SURVIVAL_RELEASE_PYTHON` 优先，其次现成的 `D:/Survival_安全工具/venv/Scripts/python.exe`，必要时去重检查已有解释器；无自动安装。探针实际验证公开 Ed25519 测试向量，每个子进程有既有的 5 秒超时；fallback 整体不承诺 5 秒上限。Offline 仍使用原标准库选择器。缺依赖只输出受控说明，不回显任意异常文本。

66 项 PowerShell 检查、38 项入口测试以及 Windows PowerShell 5.1 独立 AST/mock 审阅通过。提交入口修复后，实际执行与 CMD 相同的系统 PowerShell 命令 `tools/workshop_test/launch_test.ps1 -Mode Online -CheckOnly`，exit 0，返回 `SIGNED_ONLINE_ENTRY_CHECKED`、版本 `2026110705`、`cloud_login_required=true`、`cheats_allowed=false`、`game_started=false`。耗时 26.398 秒为本地发行来源/包校验耗时，不能解释为游戏网络请求延迟。

真实检查回执：`D:/Survival_本地工具/runs/20261108_online0705/launcher_check01.receipt.json`，SHA256 `a12409544829c51d34d4f695cc9ac4e3b7399b7d847801a4ba82f94a95f0419c`。没有本版新游戏启动、网页登录、领奖、抽奖或 SDK 操作。

## 独立测试迁出 Git

新增永久小入口 `tools/local_tools_workspace.py`，独立测试、临时文本、日志及截图统一放在 `D:/Survival_本地工具`，按 `tests/game`、`tests/content`、`runs`、`logs`、`screenshots`、`scratch`、`archives`、`vpk_lab` 分类。规则已写入根 `AGENTS.md`，树外使用说明也已更新。

核查实际运行、构建、恢复和测试互相引用后，迁出 **192 个 Git 跟踪的独立测试脚本，共 1,854,626 字节**。每个文件先做双份复制和 SHA256 校验，所有备份通过后才移除仓库原件。删除跟踪及工具入口已在 game `86f0124237d032bc5ca67cada91e9294cb6305c3` 提交推送。677 个可能涉及真实运行、正式工具、网络写操作或依赖不明确的候选继续保留；既有 `output` 中的跟踪素材和历史证据没有批量取消跟踪。

完整迁移清单位于 `D:/Survival_本地工具/archives/migrations/53aaae68faa49f0bcfd6c40cadfce57a5f4a7eef202bb4a46686c7af55dfe050/manifest.json`，SHA256 `2cacfdb65b746acbb38743e95591b62572ba090b4e656e083be6044c695b0764`。实际迁移 operator 原字节一并归档，SHA256 `ed3c79b71e59e28f47412c8f69fa68c238e794da6109e0b2499adde5e28a8aa4`。另有 1 个从未加入 Git 的新投影回归放到树外并单独归档，不计入 192。

10 项工具守卫检查和迁出后的 3 个明确选择的网格回归通过，新投影回归迁出后 10 项通过。不自动运行整目录或可能消费/发奖的脚本。管理器按需单次扫描建立索引，规划 O(N+B)、迁移 O(所选字节)，单脚本执行一个子进程；无 watcher、定时任务或游戏帧内工作，不产生网络消息。默认 stdout 只读规划，`plan --out next.json` 仅能写入树外的 `runs/test_migrations`，旧固定发行回执路径继续保留。

## 继续验收与发布

用户可用上述 CMD 验收本版线上授权、祭坛英雄移动、快速切换单位，以及尚未实测的历史修复。实测帧率、连续抽奖和多人状态更新需按真实操作另记；旧 30 券自动测试授权已耗尽，不得复用。

验收通过后仍需同源原生准入、SDK 上传成功回执及该版官方完整下载逐文件一致。当前没有新 Steam manifest，正式待发清单未因签包而清空。不能标记已同步游廊。

按用户本会话覆盖流程执行 commit → push，未 stash/pull。game/dev 与 content/master 均已核对；content 没有新改动，不创建空提交。原有 5 项无关脏/未跟踪文件保留：backend pyc、`server/bundles/current.json`、monster portrait 的两个工具以及 `tools/prepare_delivery_operator_20261103.py`，不混入本轮提交或运行包。
