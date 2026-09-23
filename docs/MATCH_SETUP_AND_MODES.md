# 模式、难度与纯净档案

## 开局流程

1. 初始加载阶段调用 `POST /v1/session/authenticate` 完成真实账号与数据库认证，只返回认证状态和难度权限，不向游戏返回旧档案，不选择模式或创建模式基线。
2. 所有本局真人认证成功、实际资源预加载完成、界面握手经服务器确认后，`admission_complete=true`，进入游戏 HUD。本局入场状态随后不再回退。
3. 房主在 HUD 面板选择「纯净模式」或「常规模式」并确认。面板没有关闭按钮，点击遮罩或 Escape 不跳过选择。
4. 模式确认后，同一面板立即显示 N1–N10 难度；后台同时调用 `/v1/session/login` 加载所选模式的档案。读取期间可以预选已解锁难度，但不能确认，不返回加载背景。
5. 全员所选模式档案就绪，服务器置 `profiles_ready=true` 并通过 `gameplay_gate` 完成玩法初始化后，才允许「确认选择」。点击确认向服务器提交难度，成功后开始原有倒计时；只点选难度不会提前开局。

多人模式和难度统一使用房主选择。房主由引擎权限确定，不假定 PlayerID=0；Workshop 本地没有大厅房主时使用首位真人。普通大厅没有可确认的房主时保持等待。

## 难度权限

- 新账号可选 N1–N5。
- 通关 N5 后可选 N6，通关 N6 后可选 N7，以此类推，通关 N9 后可选 N10。
- 选择权限使用房主经过认证的永久通关计数 `save.archive.clear_counts`，由服务端校验；客户端的解锁标志、伪造计数和另一位玩家的存档不能代替。
- 终波真实胜利沿用已有 `archive.final_wave_cleared → archive clear` 幂等事务。只有远端确认后的通关记录用于解锁；失败或待确认的保存不提前开放。
- 纯净模式也保留难度权限，它属于账号资格，不是战斗属性加成。
- N6–N10 的战斗数值仍沿用项目已有的 N5 测试配置；此次调整选择与解锁规则，没有重新平衡怪物数值。

## 两种模式的数据

常规模式读取完整永久档案，与原有玩法一致。

入场认证与模式档案读取分开。`/v1/session/authenticate` 可在后台初始化账号、完成既有待处理事务，但响应仅含 `authenticated`、`account_id`、`match_session_id` 和 `progression`；不返回 `save`、`entitlements` 或 `account_profile`，也不锁定模式。认证通过不代表战斗档案已加载。

选定纯净模式后的首次档案请求为 `/v1/session/login`，游戏收到默认战斗档案及难度权限，不收到旧存档加成。后台在此时为账号和本局保存不可变的基线；后续心跳、档案刷新和奖励返回默认值加模式登录后的变化，因此不会刚进游戏就恢复旧属性。入场认证前后、但模式登录前已有的奖励纳入基线，不误算成本局新加成。同一局重复登录不重置基线，Python 进程重启后基线仍由 PostgreSQL 保存。

所有奖励、消耗、领取资格和永久物品变更仍由服务器针对真实永久档案结算，继续使用原有事务和请求去重。纯净视图不作为保存请求写回数据库。后续交互得到的业务档案独立供档案页面和领取资格展示使用；战斗属性读取纯净视图，避免混入历史加成。

模式在本局确认后锁定。玩家身份、会话和模式不匹配的旧请求/回调不会用于认证新局。模式档案失败时停留在难度面板并支持重试，不能用入场认证或默认空档案替代档案就绪。API token、数据库密码不传给 Panorama。

## 主要入口

- `systems/match_setup_service.lua`：房主、模式锁定和本局设置。
- `systems/startup_loading_service.lua`：先完成认证、资源和界面入场门禁，再独立等待模式档案；`gate` 与 `gameplay_gate` 分别控制两个阶段。
- `config/difficulty_config.lua`、`systems/wave_system.lua`：N1–N10 权限与提交校验。
- `systems/player_profile_service.lua`、`player_profile_providers/http_fishing_provider.lua`：独立的入场认证缓存、本局模式档案、登录与后续请求的会话绑定。档案未加载时，难度权限可读本局已认证的 `progression`。
- `panorama/src` 的 `startup_loading`、`survival_ui`、`survival_hud`、`archive_difficulty`：强制模式/难度面板，复用现有组件与纹理。
- Python 后端的 `fishing_api/match_profiles.py`：真实永久档案与纯净战斗视图分离。
- `server/aliyun/database/target/202609230001_match_profile_sessions.sql`：新增会话基线表及有限 RPC，不重建现有数据库。

## 构建与验收

```powershell
./tools/build_match_setup_ui.ps1
```

此脚本限定同步和编译本功能文件到相邻 content/game 目录。开局进度条宽度使用 `0.1s` CSS 过渡，数值仍来自真实完成状态。修改 Panorama JS 后应完整退出并重启 Dota，再开新一局验收；实测单独重载地图仍可能使用旧 JS。不应在正在进行的对局中切换模式。

自动化检查包括服务器模式权限、开局认证门禁、难度解锁、通关保存确认、纯净档案与会话隔离，以及 UI 选中/确认/锁定行为。HTTP 验收工具为 `server/aliyun/tests/match_mode_http_acceptance.py`；仅用于 loopback 测试服务，凭据从受限文件读取，写模式只使用新生成的合成测试账号。

实际客户端已分别验证纯净和常规模式确认后进入难度面板。最初纯净 run2 逐帧发现 2 次加载背景闪现，显隐日志却没有记录再次显示；此后修复自有绘制面板的退役、透明度和背景纹理清理，并完整重启 Dota 复验。修复后的 run4（120 秒、1097 帧）及纯净 run5（150 秒、1369 帧）中，首次进入游戏后的 933、1322 帧均未再发现加载背景；关键帧已目视确认，并覆盖真实模式选择、N1 确认和 HUD。

录帧平均间隔约 109 毫秒，不能排除采样间隙中的每个单帧闪现。双真人联网等待、慢加载和断线重连仍未实机验证；建造者首次镜头定位仍在另行检查，不属于已通过项目。run3 未录到认证完成后的画面，不计作通过。详细范围见 [开局认证与资源加载](STARTUP_LOADING.md)，可跟踪脱敏摘要见 [match_entry_flow_20260923.json](../server/aliyun/validation/match_entry_flow_20260923.json)。

本轮后台执行者报告 77 项后端回归通过；`mode02` 的真实 HTTP 输出确认 10 项通过。最终本地复验记录确认入场门禁、入场认证、单位指令门禁、UI 请求门禁 4 个 Lua 脚本及模式/加载 UI 的 Node 套件退出码均为 0，限定 UI 构建通过。摘要分别标明执行记录、执行者报告及独立验帧来源，不将它们当作双真人实机结果。

## 2026-09-23 测试后端实测

- ECS 当前版本：`/opt/goufayu/releases/20260923-mode02`；`/opt/goufayu/releases/current` 已指向它。此版增加独立入场认证接口，与 `mode01` 使用相同数据库迁移清单，仅更新代码，没有新增数据库迁移或 RPC 权限。
- `goufayu-api.service` 仍由 `goufayu` 用户运行，已启用开机启动；API 仅监听 `127.0.0.1:8765`，数据库仍仅监听 `127.0.0.1:5432`。
- `mode02` 的 10 项真实 HTTP 验收通过，覆盖独立入场认证及既有模式档案链路。认证只返回约定元数据，模式登录仍承担默认档案、权限、基线及后续奖励投影。
- 以下数据库升级和重启记录来自先前的 `mode01` 验收，保留为历史证据，不代表已对 `mode02` 重做重启持久化验收。
  - 升级前一致性备份：`/var/backups/goufayu/pre_mode_20260923`。较早的演练备份已恢复到独立库 `goufayu_restore_mode_20260923`，16 张原业务表的数据、函数、触发器及约束核对通过。
  - 新增 1 个会话迁移；原 11 条玩家记录和历史记录保持不变。重复迁移通过；应用仅具有 14 个允许的 RPC 权限，没有表直写、DDL 或角色继承权限。
  - 真实 HTTP 验收使用两个新合成账号，验证了未认证请求拒绝、纯净默认开局、解锁资格保留、模式锁定、账号隔离、本局新奖励、通关请求去重、心跳不恢复旧加成、常规全档案读取。
  - 实际重启 API 并核对进程 PID 改变后，重新登录验证会话基线、奖励及解锁仍保留。
- 游戏端 8 组相关 Lua 回归与模式/难度 UI 交互回归通过；加载跨阶段不重现的既有回归保留。限定 UI 构建已完成，相关 XML、JS、CSS 和共享组件已同步至相邻 content 目录，Workshop 编译无失败。
- `mode01` 脱敏验证记录：`server/aliyun/validation/match_modes_20260923.json`。该版本原始受限报告保留在服务器 `/var/lib/goufayu/mode-20260923`，不要把它标为 `mode02` 的报告。
- 尚未完成本次新备份的异地下载：自动审批要求单独确认完整业务数据导出及本地目的地，已向用户请求；未将数据库备份纳入仓库。
- 未改 Supabase、当前游戏连接目标、支付模式或归档配置哈希。需要重新开局测试新界面，当前运行中的旧对局不会自动切换模式。

### 回退

#### 回退到 mode01

保留 `/opt/goufayu/releases/20260923-mode01`。`mode02 → mode01` 只需配套回退后端代码和游戏端入场流程：`mode01` 没有 `/v1/session/authenticate`，不能继续配合新版入场客户端。停止服务后，以既有部署工具激活该版本，并核对权限、健康检查与旧版流程。两版数据库清单和 RPC 白名单相同，不撤销会话 RPC，不回退数据库或覆盖玩家数据。

#### 回退到 test05

保留更早版本 `/opt/goufayu/releases/20260920-test05`。后端回退必须与游戏端模式代码回退配套：该后端既没有 `/v1/session/login`，也没有 `/v1/session/authenticate`。

在服务器先停止 `goufayu-api.service`，使用既有迁移账号、`goufayu_test` 和新版本数据库工具执行 `database/rollback_match_session_privileges.sql`，只撤销新增两个会话 RPC 对应用账号的执行权限，再调用旧版本 `deploy/manage.py activate --release /opt/goufayu/releases/20260920-test05`。旧后端严格校验 RPC 白名单，不能只切换目录就启动。会话表、玩家记录和迁移台账均保留，不恢复旧数据库备份覆盖新增奖励。

从 `test05` 重新启用 `mode01` 或 `mode02` 时，需要以迁移账号执行 `database/harden_match_sessions.sql` 恢复两个 RPC 的权限，再运行对应版本的权限、健康检查并激活服务；仅有迁移台账记录不会自动恢复被撤销的权限。`mode01` 与 `mode02` 之间切换不需要此撤权、恢复步骤。
