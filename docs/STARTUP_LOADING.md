# 开局认证与资源加载

## 玩家看到的流程

1. 原生地图加载使用统一背景；后续阶段共享入场完成状态，完成后不再显示背景。
2. 服务器调用 `POST /v1/session/authenticate`，认证当前 Steam 玩家和本局会话，并验证真实数据库访问。此阶段只返回认证状态与难度权限，不向游戏返回旧存档，也不选择模式或建立纯净模式基线；失败时保持加载页。
3. 预加载全部已启用野外/挑战怪物，以及每个可选难度前 10 波怪物的模型、附件、粒子和音效。当前配置去重后为 357 项；以后从配置重新生成清单。
4. 个人进度为资源实际完成比例的 60%、本人入场认证的 20%、背景加载及服务器确认客户端握手的 20%。进度条 CSS 以 `0.1s` 线性过渡显示新值；实际进度不按时间自动增长。
5. 本人准备完毕显示“等待其他玩家”。百分比和状态文字都位于蓝色进度条内部，进度框宽 1080px（最大占屏幕宽度的 82%）、高 58px。引擎进入选队阶段、所有本局真人认证成功、资源完成、客户端就绪后，服务器置 `admission_complete=true`，永久完成本局入场；没有额外固定等待 60 秒。
6. 进入游戏 HUD 后，由房主在选择面板确认模式；同一面板立即切换到难度选择。后台此时才调用 `/v1/session/login` 读取所选模式的档案。读取期间可预选难度，不能确认，不应回到加载背景。
7. 全员本局模式档案就绪后，`profiles_ready=true`，`gameplay_gate` 放行玩法初始化和难度确认。确认难度才开始原有倒计时。认证成功与档案加载成功是两个独立状态，不能互相替代。

`admission_complete` 在同一局内不会因档案读取、失败重试或后续阶段新建面板而回退；新一局重新认证和加载。界面跨阶段沿用服务器已确认的完成状态。加载背景退出后的绘制清理及实际录帧验收范围见文末。

这里的资源完成指引擎 Precache / 异步单位预加载 API 已完成；不会为了预加载提前生成十波怪物。

## 失败与重连

- 入场认证失败或认证缺失：5 秒间隔重试；按钮也可重试，未通过前不能入场。
- 选模式后的档案读取失败：保留难度面板，显示错误并允许重试，禁用难度确认及玩法指令；不撤销入场状态，不创建空档案覆盖存档。已加载档案不会被重新置空。
- 单次认证或档案请求超时为 45 秒，资源等待超时为 90 秒，均使用实际时间，暂停游戏时间不影响这些检查。
- 资源重试保留成功项，拒绝旧请求回调。需要重新进入引擎 Precache 的静态资源失败会明确提示重开地图。
- 入场前已登记真人断线仍留在名单内，等待重连及新的客户端握手；不会靠删除未完成玩家提前放行。入场后的模式档案准备仍要求全员账号一致、在线且档案就绪。
- 开局后只接受原名单同账号重连；新玩家会看到“本局已开始，请重新加入下一局”。

## 开发和本地联调

双击仓库根目录 `launch_aliyun_test_game.cmd`，建立本地 SSH 隧道并向当前 Workshop 测试服注入既有测试认证。密钥不进入源码或 Panorama。若已经开着游戏，脚本只连接本局，不会重开。

直接启动 Workshop Tools 后出现 `fishing_api_token_missing` 表示本地游戏服还没有测试 API 认证配置。加载界面应保持关闭开局门禁；先运行上述启动器，不要改用空档案或本地假档案绕过。

UI 源文件在 `panorama/src`，背景原稿在 `art/ui/sources/custom_game/loading`。运行：

```powershell
./tools/build_startup_loading.ps1
```

仅同步本功能的文件到相邻 `content/dota_addons/survival` 并增量编译。修改开局 Panorama JS 后，应完整退出并重启 Dota，再开新一局验收；实测只重载地图可能继续使用旧 JS，不能据此判断新代码效果。启动器在游戏已运行时不会代替执行完整重启。

若自动联调脚本连接 `29000` 成功却收不到任何响应，先检查 VConsole 是否占用连接。仅断开 VConsole 的连接即可继续自动诊断，无需因此重启游戏或编辑器。

## 代码入口

- `systems/startup_asset_preload_service.lua`：读取实际怪物配置，生成资源清单和完成状态。
- `systems/startup_loading_service.lua`：入场认证、固定本局名单、客户端握手、单向入场状态与独立模式档案门禁。
- `systems/player_profile_service.lua`：分别缓存本局入场认证和模式档案；`is_authenticated_for_account` 不代表 `is_loaded_for_account`。
- `addon_game_mode.lua`：入场门禁控制结束选队，`gameplay_gate` 控制 `HERO_READY`、`GAME_STARTED` 等玩法初始化。
- `tree_attack_order_filter.lua`、`ui/ui_request_router.lua`：档案就绪前阻止玩法指令，保留模式选择和必要的重试请求。
- `survival_loading/state` 网络表只发布进度和就绪状态，不包含帐号、私有存档、API token。
- 客户端只确认背景与界面已准备，不可自行确认服务端认证或资源加载。

## 回归检查

```text
lua scripts/vscripts/tests/test_startup_asset_preload_service.lua
lua scripts/vscripts/tests/test_startup_loading_service.lua
lua scripts/vscripts/tests/test_startup_order_gate.lua
lua scripts/vscripts/tests/test_startup_ui_request_gate.lua
lua scripts/vscripts/tests/test_player_profile_load_retry.lua
lua scripts/vscripts/tests/test_player_entry_authentication.lua
node tools/test_startup_loading_ui.js
node tools/test_match_setup_ui.cjs
```

实际引擎验收需分别检查：认证失败停留加载页；真实认证、资源与全员握手完成后进入游戏；HUD 模式确认立即切换难度；档案较慢时可预选、不可确认；档案失败可重试且不返回加载背景；两名真人中一人较慢时另一人继续等待。

2026-09-22 验证：引擎实测资源 `357/357`、客户端握手成功；故意不提供测试 token 时保持选队阶段，认证失败未放行。恢复测试认证后的真实档案读取、在线时间保存和开局日志已确认。曾出现全员就绪后 HUD 加载容器 `hiddenClass=true`、`visible=true`，导致界面一直显示“等待其他玩家”；现在直接设置容器 `visible=false` 和 `visibility=collapse`，并增加不解释 CSS 类的引擎容器模拟回归。热更新后的实际截图确认加载遮罩消失，地图和 HUD 正常显示。

双真人联网等待、慢加载和断线重连仍未完成实机验收；对应门禁与新会话隔离已经过模拟回归。

2026-09-23 当前流程已拆分为入场认证与模式档案加载。服务端完成入场后保持 `admission_complete=true`，模式选择和档案重试不再改变它。客户端跨阶段按会话及玩家身份保留完成显示状态；新会话或不同玩家不能继承，客户端缓存也不能代替服务端认证、资源回调或首次图片握手。对应认证、门禁和 UI 回归已通过，相关资源已编译。

同日实际游戏已验证纯净模式和常规模式确认后进入难度面板。最初纯净 run2 的第 41、85 帧确实出现加载背景闪回，虽然诊断日志未再次记录 `visible=true`，因此不能只依据显隐日志判断结果。随后将自有绘制面板隐藏并清除背景纹理，正式入场后不再更新该背景或接受晚到图片回调。

重新编译并完整重启 Dota 后，run4 的 120 秒、1097 帧和纯净 run5 的 150 秒、1369 帧均完成逐帧像素比对与关键帧目视核查。run4 在第 164 帧进入游戏，随后 933 帧未发现加载背景重现；run5 在第 47 帧进入游戏，随后 1322 帧未发现重现。比对同时检查原色及亮度变化后的背景；两轮诊断均记录入场后绘制面板透明度为 0、背景已退役。真实模式选择、N1 确认及后续 HUD 画面已覆盖，未使用脚本伪造门禁通过。

这些是约 109 毫秒间隔的屏幕录帧，最大采样间隔分别为 126、129 毫秒，不能排除完全发生在采样间隙内的单帧闪现，也不代表双真人验收已完成。run3 的录制在认证完成前结束，不计作无闪回通过。另有建造者首次定位后镜头仍停在海面的独立问题，本次加载页验收不将其标为已修复。

可跟踪脱敏摘要见 [match_entry_flow_20260923.json](../server/aliyun/validation/match_entry_flow_20260923.json)；本地详细像素指标、关键录帧和仅含 `STARTUP_VISIBILITY` 的白名单日志保留在忽略目录 `output/ecs_backend_work/mode_deploy`。测试后端为 `20260923-mode02`，部署与 HTTP 验收范围见 [模式、难度与纯净档案](MATCH_SETUP_AND_MODES.md)。
