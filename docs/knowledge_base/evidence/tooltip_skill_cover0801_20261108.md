# 0801｜物品提示、锁定技能及进入游戏封面（2026-11-08）

仅本地更新，后台保持 `20261106-ws4-daily-refs-ed532ea60d2b`。新运行源码已应用、纯回归及独立审阅通过；0801 的官方编译、完整签名、新版普通客户端及游廊发布仍待后续实际回执。正式仍 `3824360109` / `2026110104`，Steam manifest `7025356658517360342`。不能把本轮源码或 Git push 称为已同步游廊。

## 0705 启动失败的实际原因和恢复

用户自助联网入口失败后，实际只读复现到 `ValueError: dirty_or_unclassified_runtime_source`。当时本轮五份封面源码正在修改，严格 collector 检查拒绝了未完成的运行改动；`test_entry.py` 又将 canonical ValueError 泛化成 `test_entry_failed`。没有证据表明该次失败发生在游戏网络连接阶段。

封面五项新字节先双份备份并核验，随后精确恢复 0705 源状态；未绕过签包门禁。备份为 `D:/Survival_本地工具/runs/20261108_loading_cover_pending01`，manifest SHA256 `6e518612bda40be66e66658cd6c66ff519b883e192aaff7bdd0603f8e8758e2f`。入口受控错误说明和敏感文本负例已在 game `4d66ed8c8cb31d3482ad67af702408d7350825d3` 提交推送，22 项检查通过。

随后实际执行完整 Online 入口，Steam 临时登录通道启动成功；canonical 事务 `online_2026110705_20261108_024931_355604` 于 `2026-11-08T02:54:27.0910680Z` 启动 owned Dota PID 4660。日志实际出现 `phase=ready/admission_complete=true`，不据此宣称所有玩法、多人或 FPS 验收通过。`online_latest.json` 的 STARTING/game_started=false 在进程存活期间未更新，不能当作仍未启动或死锁。

用户于本轮确认退出所有 Dota；keeper 正常完成 `OWNED_DOTA_EXITED_HOLDS_COMPLETED`，入口 session 73705 最终 exit 0。`2026-11-08T07:39:48.567587+00:00` 回执为 `SIGNED_ONLINE_EXITED_ORIGINAL_RESTORED` / `ORIGINAL0104_COMPLETE_SET_FULLY_RESTORED`，`restoration_required=false`。没有强杀进程、自动领取或抽奖。恢复完成前，新 UI 和发行工具只在树外准备候选；恢复后才统一应用主工作区。

## 物品 tooltip

用户截图指定删除装备栏物品提示顶部“生存防守 · 物品详情”和底部“项目物品 · 实例数据已同步”。已删除 Category 节点及专属样式，移除同步/背包装饰脚注；数量超过 1 时仍展示真实持有数量，否则状态节点初始和运行时均折叠。图标、名称、类型、等级、完整描述、属性、合成材料不变，没有新增延迟或定时器。

双仓三个源文件为 survival_hud.xml、inventory_tooltip.js、inventory_tooltip.css。候选与原字节位于 `D:/Survival_本地工具/runs/20261108_tooltip_skill_ui/tooltip_candidate`；manifest SHA256 `0ffa2024aaef3c2f6f3c4e6c148ac29f933e1611b0b2142b38ddee05ae005001`，validation SHA256 `0640badc0d03f2cca68198d65eae5cbe60d6e507256b01767ace383093f1ec4c`。实际 render 覆盖映射物品、原生物品和堆叠到单件切换；1000 次稳定成长刷新新增文字/图片/隐藏原生提示/重新绑定写入均为 0。固定六项旧回归及双 XML 解析通过，新游戏视觉仍待。

## 英雄未解锁技能置灰

`hero_skill_system` 为保留未解锁专属技能图标，将原生等级设置为 1 并禁用实际施放；真实快照是 `locked=1/level=0`。原 runtime publisher 丢失这一逻辑状态，通用 builder 又返回 available=1，导致技能栏及悬停恢复亮色。

修复仅在 `scripts/vscripts/ui/ability_runtime_service.lua`：现有 HERO_SKILL_CHANGED 边沿核对当前权威快照的 player/unit/hero/version，以及实际单位句柄和归属，再按 ability_name 建索引。通用发布路径从匹配缓存 O(1) 读取，在原生激活处理之后投影已有 `prerequisite_met/current_level/available/status_text` 字段。保留原解锁、技能等级、原生激活和消耗规则；缺真实数据不由原生 1 级伪造解锁状态。

首次初始化中，ability runtime 服务先于 hero skill 系统订阅；后者先写 NetTable 再发送真实事件，因此初始锁定也在首次发布时投影。相同版本不重扫技能，旧英雄/版本事件不能覆盖当前索引；hero_ready=0、单位移除及服务初始化清理缓存。没有新事件类型、协议字段或轮询。

| 路径 | 新增成本 | 原生/API/网络边界 |
| --- | --- | --- |
| 真实技能/英雄版本变化 | O(S) 建索引，S 为本英雄实际装配技能数；空间 O(P×S) | 每技能事件 1 次当前快照核对、1 次归属查询；沿用原发布 |
| 同版本技能事件 | O(1)，不重扫 S | 保留事件身份核对，不新建调度 |
| 通用重复发布/属性刷新 | 既有每技能迭代内增加 O(1) 索引读取 | 0 新快照读取、0 新归属查询、0 新技能扫描 |
| 稳定无变化/空闲 | 无新增任务 | 0 新计时器、0 新消息 |

树外 v2 候选 SHA256 `af7d738b5d8681eef1c02f4701fc125178b5c7236faa7f726305c05df7b7d564`，validation SHA256 `a9557ebd1563a737da72d55e9e97d64359fa5a54e9226e22d6def6d9f7b983cd`。原 publisher 首次锁定用例红，新候选 31 项真实服务端和 267 项真实 Lua 输出到现有技能栏/hover 检查通过；覆盖解锁、换英雄、重生、旧事件、玩家及实体复用隔离。100 次通用重复刷新新增三个调用计数全 0，40 次稳定显示/悬停色彩写入 0。另三套技能/升级/闪烁回归通过，独立窄审无阻断。这些是调用计数与功能证据，不是原生 FPS 结论。

## 宣传封面与明确编译来源

用户确认的原宣传 PNG `publishing/workshop/gou_fayu_cover_master.png` 为 1672×941，SHA256 `7d4bbd0865782c8469b964b75a9c299b8f150d95ac59246511e3c49b65b8c351`。原字节复用到既有 loading 背景 URI，原生载入、组队准备及网页登录等待三个上下文均改为完整等比显示，保留深色边界。隐藏叠加的旧装饰标题，图内已有宣传标题；进度、重试、授权和完成后退出遮罩逻辑保留。

旧图曾仅随 XML 隐式编译，没有该图片的独立不可变编译映射。本轮补唯一明确的 `dawnward_citadel_background_png.vtex` 描述及双仓 PNG/descriptor 作者，BGRA8888/sRGB，输出继续为同一个 `_png.vtex_c`。仅此确切路径建立 typed 映射，不放宽任意 PNG、相似路径或不一致双仓字节。planner、ledger 和原作者缺失/不一致负例已验证；实际官方编译仍必须成功后才进入新签包。

## 0801 构建门禁与后续

新版本 `2026110801` 使用独立 `output/complete_delivery_release_20261108_v01` 和树外 gen21/candidate 目录，0705 及旧证据不覆盖。catalog20 只有全部真实输入与原 operator 一致时可复用；本轮修改的 runtime Lua 以及编译映射工具属于 production plain 读集，所以必须重新生成真实 production21，不能给旧 production20 重标来源。

待完成双仓真实 source21 提交推送、全量待发范围/官方编译、生产转换、final21 来源冻结、严格 collector、完整签名、普通客户端及官方发布/完整下载。不要把这份文档中的候选回归当作新签包或游廊成功。17 项 UI/封面源应用回执 `D:/Survival_本地工具/runs/20261108_tooltip_skill_ui/applied_sources01.json` SHA256 `7543760f66f2cb9ddc9d37a041eb1e01c7994436f61728e319f9a9bdd983ef0c`。

原五项无关改动继续保留：backend pyc、server/bundles/current.json、monster portrait 两工具和 prepare_delivery_operator_20261103.py；不混入本轮源码或运行包。按用户本会话覆盖流程 commit → push，不执行 stash/pull。

## 首次正式编译后的产物覆盖拦截

首轮真实 source21 已双仓提交推送：game/operator `f9f928577034cc5659bff4f252b5d9c75edd282c`，content `24f26689e60d0fb2f48fe9c410ae5e1f8be0ce14`。25 项真实 Git 绑定回归通过；全量计划选中 170 项，四份封面 PNG/descriptor 作者均绑定。production21 实际生成并逐文件复核 853 plain、186 保护、7 override，报告 SHA256 `081b71c3fe7dccbefe50d7987d6d358f85ddb5c8b1d77469fc62cf4bcee233d9`，保护报告 SHA256 `4915b811e50217902b0a29ea2e1bc583e71b8253dc827cc19517b3f893f246dd`。

170 个官方命令退出码均为 0，但严格 handoff 拒绝了产物，不是完整编译验收通过。显式封面命令中间生成 BGRA8888 `6,295,572` 字节、SHA256 `c808cee9cbef830c364c39f2ff39328d5708bd9bba21b15536401a964718d8de`；随后原生 XML 的 PNG 依赖编译改写同一 `_png.vtex_c` 为 DXT5 `1,580,532` 字节、SHA256 `39f8c2934f27a58ca9f2aa93f409a60149222af491695b9800ac614447df3904`。源 descriptor 没有变化，问题是两个原生编译入口共用输出名。其余 169 项一致，临时挂载已清理，主仓未导入本轮失败产物。旧 proof（`1617e42c25662d098a4c77b826b206bb86e38dc730ac9d4372f77ba39554dbf4`）、日志及 `post_compile_artifact_audit01.json` 均保留。

编译工具修复只将这一个明确的封面目标排在最后实际执行，其他资源相对顺序保持；证明结果仍恢复为原计划顺序。所有命令完成后再逐产物验证大小/SHA256/MD5，任何后续覆盖或删除都会阻止写成功 proof。8 项实际调用 compile_plan 的隔离回归及独立审阅通过，不能代替新官方编译。额外成本仅一次构建 O(N) 排序分区及 O(全部编译产物字节) 读取，不进入游戏循环。

下一次使用新 operator 提交和独立 gen21a3 计划、编译目录、proof 及生产目录；为保持既有简单合约，production 实际重新生成，不重标旧 production21。新 source21a3/final21a3 控制保留全部真实来源，catalog20 继续原来源和完整读集核验。此前把 tooltip 的 JS 误写为 XML 的控制遗漏清单也已在新 attempt 中纠正，旧失败控制/回执不覆盖。
