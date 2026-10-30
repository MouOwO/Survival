# 新手引导移除（2026-10-30）

用户明确要求直接删除新手引导。当前开发源码已移除整套教程运行路径，并非只关闭显示开关。普通开局、登录准入、账号云档、公测登录礼和正常离线逻辑测试继续保留。

## 已删除和解除的入口

- 删除 Lua `onboarding_service`、`onboarding_persistence`、`onboarding_targets` 与专用 `offline_onboarding_test`；移除初始化、教学建造位置门禁、教学免失败和自动暂停波次分支。
- 移除 HTTP／离线档案 provider 的教学状态与完成接口、教学临时身份、任意账号教学预览旁路。正常 Steam 身份校验、登录与存档读写合同不变。
- 删除 game 三份教程 UI 源及三份编译资源、content 三份源；manifest 不再挂载教程 HUD，因而不再注册教程遮罩、镜头引导、鼠标／键盘拦截。公测礼不再等待 `SurvivalOnboarding`。
- 删除根目录离线新手引导启动器、其 PowerShell 包装及普通测试启动器中的专用参数和29008端口；保留离线29006／联网29005两入口。
- 删除 Python 活跃教程处理模块及专用命令分流。旧 `onboarding_state`／`onboarding_finish` 按无效命令拒绝，不返回虚假的完成结果，不调用教程RPC。
- 删除专用教程测试，用退役、正常开局／建造、档案与登录回归替代；共享测试的显式模块加载表不再引用已删模块。

## 保留的历史与数据

不改写已部署的 SQL migration、hardening 或 ledger，不删除教程历史表、旧回执或真实玩家数据。旧 transport／数据库验证与历史发布工具保留兼容和追溯用途；旧发布目录中的 DPAPI helper 仍被普通后端发布工具复用，不能整目录删除。当前游戏和API已不再调用教程路径。

本轮不部署服务器、不上传游廊、不修改现役后端 bundle hash／运行指针。未来发行应同批更新 Lua／UI 与 Python 服务；现有旧局不会自动卸载已加载的脚本，需要重新开局或正常重建 HUD。

## 验证记录

活跃 `scripts/vscripts` 与 `panorama/src` 中没有教程生产路径残留，退役回归中的负向断言保留旧名字。运行资源选择器不再选中教程模块；当前受保护模块集合为184项，未修改保护或认证策略。

前端两组源码与content配套，Valve编译零失败；公测礼21项、模态／ESC13项及加载／快捷键各1项通过。后端退役5、公测礼14、通用后台44和会话／认证10项，共73项通过。普通测试启动入口9项通过。Lua开局、建造、离线档案、公测礼与双人入口等10套关键回归及11份改动Lua语法检查通过。

扩大Lua验证中的四个旧夹具失败（profile_modes:43、load_retry:45、startup_ui_request_gate:113、offline_payment_isolation:82）已用HEAD原代码预载负对照复现相同退出码、断言行和错误，未修改其门禁或断言。另一个旧前端测试缺历史 design_refs fixture；完整旧发行测试的当前 Python 环境缺 cryptography，未为清理任务安装新依赖。只读运行清单及必要功能回归单独验证，不把未运行项写成通过。

原始记录位于 `output/onboarding_removal_20261030/` 与 `output/remove_onboarding_20261030/`。头像任务的既有及并发未提交源码／编译／测试、发布工具、运行指针和Python缓存均不纳入本次引导清理提交。两仓按stash→pull→pop→验证→commit→push交付，最终编号以实际报告为准。
