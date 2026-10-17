# 四玩家实机帧率验证（2026-10-12）

当前四玩家战斗负载仍会严重卡顿。正式采样采用真实 Dota 渲染进程的 ETW Present 间隔，不采用离线模拟时钟或单张截图上的 FPS。

本机成功建立的是 **1 个真实渲染客户端 + 3 个原生引擎机器人**。机器人各有实际 Player、绑定英雄、建筑师及正式建筑归属，并开启 `sv_stressbots`。本地第二实例启动后没有游戏窗口，也没有第二条主机连接，已只结束该测试实例。因此本报告覆盖四玩家实体及机器人压力，**没有完成四个独立网络客户端、四端 FPS、真实网络延迟或丢包同步验收**。

## 有效实测

| 实机负载 | ETW 有效时长 | 平均 Present FPS | 最慢 1% FPS | P99 帧间隔 | 最大帧间隔 | ≥100 ms 次数 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| A：四方各 7 塔，空闲/采集，怪物 0→0 | 29.913 s | 59.44 | 28.57 | 29.98 ms | 48.12 ms | 0 |
| A：四方积怪后释放塔攻击，怪物 188→83 | 59.683 s | **6.35** | 4.14 | **226.95 ms** | 266.27 ms | 373 |
| B：一人守四墙，正式四通道出怪，怪物 0→199 | 59.929 s | **13.75** | 4.42 | **213.14 ms** | 251.39 ms | 277 |
| B：清场后，怪物 0→0 | 29.917 s | 60.00 | 50.06 | 18.71 ms | 22.43 ms | 0 |

B 出怪阶段的最后 10 秒约 5.28 FPS；13.75 的整段平均包含较轻的起始负载。A 峰值结束仍有怪，不能把整段称为清场后空闲。表中怪物数量是计时外围 BEFORE/AFTER 正式状态快照，不是每一帧同屏数量，也不是全程固定数量。

四段记录分别有 30、60、60、30 次每秒前台检查，全部为目标 Dota 进程且窗口未最小化；无暂停，`host_timescale=1`。同一 PID 54100、同一 DXGI SwapChain `0x000001b37d97d310`，没有混合不同窗口或进程的帧间隔。所有有效样本均有 CSV、SHA256、焦点记录和原生状态。

清场后恢复 60 FPS，支持低帧与活跃战斗、积怪负载相关；尚未定位具体 CPU、原生移动、特效或同步瓶颈。A/B 建筑数、工人数及地图局龄不同，不是单变量性能改善对比。未达到“最多特效时不卡顿”的性能目标。

## 测试条件与边界

- Windows CIM 读取：Intel Core i5-14600KF（14 核、20 线程），NVIDIA GeForce GTX 1050 Ti，驱动 32.0.15.8180；系统另有 ToDesk/GameViewer 虚拟显示适配器。记录见 [hardware.json](../../output/four_client_perf_20261012/hardware.json)。未从 ETW 单独核实哪个适配器承载所有 GPU 工作。
- 实际游戏窗口 1600×900；`fps_max=120`，有效呈现记录 `SyncInterval=1`，空闲呈现约 60 Hz。没有把该尺寸当成物理显示模式。
- `template_map`、常规模式、N2、第 15 波；正式模式/难度选择、建造队列、升级、训练和科研请求。仅准备阶段用 8 倍时间，测量恢复 1 倍。
- 四份内存档案的个人地图等级分别为 1、9、17、24。塔攻击、墙生命、工人攻速、英雄攻击档案加成有差异；只覆盖本场景配置，不替代所有科技作用域验收。人类玩家进入夹具前已累积的局内塔成长保留，不假称四人最终属性只由这四份档案决定。
- A 每人 7 塔、1 墙、主城/农场/研究所/高级研究所各 1 个、26 名普通工人，共 28 塔/104 工人。B 仅玩家 0 拥有相同的 7 塔配套与 26 工人，其余三人各只有 1 墙、0 工人、0 塔。正式归属查询与 player context 校验；非英雄建筑原生 `GetPlayerOwnerID=-1` 不单独判为归属错误。
- 为保留持续测试负载，选定测试塔加 Tools-only `MIN_HEALTH=1`，注册墙加测试护甲 100000/最低生命 1；保留正常攻击事件及特效。该保护改变战斗存续时间，结果属于有明确保护条件的压力测试。
- A 先停止测试塔攻击积怪，再释放；B 使用正常第 15 波四通道出怪。未把四个原生机器人称为四个外部网络连接。
- 真实账户读认证沿用已授权的测试流程。测试档案只在内存，HTTP/存档写入隔离，没有把模拟资源、奖励或地图等级写入真实存档。
- 实际截图在计时结束后拍摄。A/B 战斗截图出现肉鸽选择弹窗；未记录计时中每一时刻的弹窗覆盖，因此不宣称全程无遮挡的最高可见粒子场景。

## 计数方法与证据

工具为签名有效的 Intel PresentMon 2.6.0，SHA256 `B2A706BC6AD475749E3B7E3409263AA1E6906D45BDCF993F6DBC0F660188F1AF`。[官方发行版](https://github.com/GameTechDev/PresentMon/releases/tag/v2.6.0)。每次使用独立 ETW session，未停止已有 NVIDIA FrameView session。

平均 FPS = 有效帧间隔数 / 有效间隔秒数；排除第一行没有对应前帧的间隔。P99 对原生 Present 间隔使用线性百分位；“最慢 1% FPS”是最慢 `ceil(N×0.01)` 个间隔均值的倒数，和 P99 的倒数不同。Present 节奏不是服务器 tick、GPU 渲染耗时或显示器实际显示帧率；`Dropped=0` 不表示不卡顿。

正式证据每组含 `presents.csv`、`analysis.json`、`capture.json`、`focus.json`、`before.log`、`after.log`、`settings.log`、`native_fps.log`：

- [A 空闲采集](../../output/four_client_perf_20261012/a_live_front/analysis.json)
- [A 积怪释放](../../output/four_client_perf_20261012/a_final_peak/analysis.json)
- [B 四通道出怪](../../output/four_client_perf_20261012/b_final_wave/analysis.json)
- [B 清场后](../../output/four_client_perf_20261012/b_after_clear/analysis.json)
- [机器汇总](../../validation/20261012/four_player_live_fps.json)

实际组装截图：

- [B：四墙同区、仅一人七塔的准备状态](../../output/map_build_c6/four_player_B_ready.png)
- [A：峰值测量结束后的游戏页面](../../output/map_build_c6/four_player_A_final.png)
- [B：出怪测量结束后的游戏页面](../../output/map_build_c6/four_player_B_wave_final.png)

后两张保留了实际肉鸽弹窗，不裁掉遮挡来冒充计时中的完整战场。

原生 `cl_printfps` 只作交叉线索：包含预热、延迟及采样尾部，范围与 ETW 不同。A 峰值总计只有 458 帧，不能把其标为“1000 frames”的输出当满 1000 帧统计。游戏时间快照覆盖更长工具包络，不用于反推 60 秒 ETW 区间的 tick rate。

## 排除的旧记录

`a_idle`、`a_wave15`、`a_fixed_wave15` 没有全过程前台检查，不能作为正式前台帧率结论；旧 20.9 FPS 结果撤出正式表。`a_wave15` 还处于两个 modifier 绑定缺失的阶段，不能和正式修复后样本做性能前后比较。

`a_fixed_backlog_release` 无可用 Present CSV；`a_fixed_peak_verified` 无 CSV 且 60 次前台检查均失败；`prepare_fourowners` 原采集工具退出 1，场景也未完成。均保留故障证据、不计为成功测试。初期单实例 10 秒工具验证约 60 FPS 只验证测量链路，不属于四人战斗结果。

游戏启用失焦自动最小化曾污染测试。正式流程改为先启动测量子进程、延迟 8 秒、恢复游戏前台，测量期间只观察焦点；临时关闭失焦最小化。计时内不截图、不执行其他游戏命令、不写入游戏热加载源文件。测量后恢复设置。

## 本轮修复与回归

实际启动缺少 `modifier_tower_projectile_speed`、`modifier_tower_fixed_facing` 的重新绑定，导致原生 `AddNewModifier` 失败。已加入 `core/modifier_registry.lua`，现有注册测试增加对应检查；新地图注册 63 项，实际塔原生 projectile speed 与配置匹配。

这是原生绑定正确性修复，**不是已验证的 FPS 优化**。高负载低帧仍保留为未解决问题。

本轮修改：

- `scripts/vscripts/core/modifier_registry.lua`：补两个注册项。
- `scripts/vscripts/tests/test_modifier_registry.lua`：覆盖重新绑定。
- `scripts/vscripts/tests/manual_four_player_live_perf.lua`、`modifier_manual_four_player_live_perf_tower.lua`：显式 Tools-only 四玩家夹具与保护。
- `tools/run_four_player_live_perf.cjs`、`observe_live_perf_focus.py`、`focus_live_perf_window.ps1`：可复跑采样入口与前台检查。
- `tools/analyze_presentmon_capture.py`、`test_four_player_live_perf_wrapper.lua`：原生 CSV 分析和夹具归属/生命周期回归。

注册、弹道速度、固定朝向、四玩家夹具回归，以及相关 Lua/JS/Python 语法检查通过；检查日志见 `output/four_client_perf_20261012/checks/`。不宣称全仓所有回归通过。

## 清理与复跑

测试停止后恢复内存档案读钩子、移除确切塔保护句柄及墙保护，再重载同一地图清除模拟资产和写入隔离。新地图确认当前夹具/写入 guard 均不存在。恢复 `host_timescale=1`、`cl_showfps=0`、`sv_stressbots=false`、`engine_no_focus_sleep=20`、失焦最小化=1；镜头回到默认距离 1200（原镜头距离未单独留档，不称精确恢复原视角）。[清理证据](../../output/four_client_perf_20261012/cleanup.log)。

Dota 客户端保持打开，在组队等待页。原有 Hammer 后端辅助服务恢复为 `waiting_for_party`、console connected；此状态不等同完成新对局认证。本轮没有 Git 提交或推送，其他原有工作区修改保留。

复跑入口只用于独立 Tools 测试地图：先正常开始并完成常规模式/N2难度选择，再 `isolate`、原生 bot populate/bind、`prepare A` 或新地图 `prepare B`；等待 `status=ready`，恢复 `host_timescale=1` 后采样。机器人、档案和建造的详细入口在脚本注释中；不要在实际玩家对局运行夹具。

```powershell
$env:LIVE_PERF_PID = '<当前 Dota 进程 PID>'
node tools/run_four_player_live_perf.cjs sample my_case 60 wave
& 'C:\Users\Administrator\AppData\Local\Programs\Python\Python314\python.exe' -B tools/analyze_presentmon_capture.py output/four_client_perf_20261012/my_case/presents.csv --process-id $env:LIVE_PERF_PID --output output/four_client_perf_20261012/my_case/analysis.json
```

仍待独立验收：四个可渲染且各有独立网络连接的客户端；各端视角/帧率；真实网络延迟与丢包；高负载性能根因及修复后同条件复测。
