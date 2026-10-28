# 新会话先读

这是 2026-10-24 的项目快照。项目内部名 Survival／SurvivalContent，当前游廊名“孤城逐晓·封闭测试”。Dota 2 生存塔防：经营工人和资源→建墙建塔→英雄、转生与装备构筑→守波/挑战→账号成长。玩法权威在服务端 Lua，永久数据权威在 Python＋PostgreSQL RPC；Panorama 只表达意图和显示投影。

**现状**：原游廊条目 `3824360109`，不公开列出，v05／序列 `2026102405`。默认自制轻量地图 `ws4_entry`，客户端固定 `dota_launch_custom_game 3824360109 template_map` 重新进入真实地图，解决已观察到的 HTTP 请求对象创建失败。玩家本人已确认从原条目进入 N5；后台只读核对测试档 revision43 和在线检查点。内部引擎原因未确认，不能写成 Valve 官方白名单规则。

**联网边界**：Steam 官方 OpenID＋每局短码确认；浏览器可明确选择记住30天，仍每局确认。四账号独立测试库 `goufayu_ws4`；真实支付、可信排行榜关闭。杭州云端访问 Steam 目前依赖作者电脑的临时固定 TLS 中转，电脑和网络必须在线。此版只验证单人云档；旧 VPN 双机能玩但卡顿，尚无正式多人 hosting。

**版本陷阱**：当前开发 `all_difficulties_unlocked=true` 为整局只读验收，不代表冻结 v05 相同。开发发布模式 standard/pure/rich/cold；正常规则 N1–N4 开放，N5起需本模式前一难度通关，全队权限取交集。旧文档的 N1–N5、全局怪物上限、公共技能容量3等可能已过期。实际数值以当前 CSV、生成链和运行实现核对。

**不可破坏**：真实账号/玩家归属；认证门禁与模式档案门禁分离；纯净战斗投影不覆盖永久档；每笔消耗和奖励幂等、版本校验、原请求重试；旧局异步回包不写新局；现金仅验签与数据库交付事务成功才到账。离线入口 `离线逻辑测试.cmd` 用本局内存档、允许作弊；联网 `联网登录测试.cmd` 用冻结副本、禁止项目调试修改；原游廊是另一个发布验收范围。

按任务读取：玩法→[02](02_core_gameplay.md)，存档→[03](03_progression_save_contract.md)，登录/Steam→[04](04_network_auth_official.md)，商城/支付→[05](05_payments_commerce_delivery.md)，打包上线→[06](06_build_release_ops.md)。排错看[07](07_decisions_incidents_pending.md)，新项目复用看[08](08_new_project_reuse.md)，机器索引看[data/context.json](data/context.json)。

在原项目改代码时同时检查 game、content 两仓，固定 stash→pull→pop→commit→push，只提交任务文件，保留其他人的改动与历史 stash，不强推。UI 源码/编译资源配套，地图保留 LFS。本知识包本身只输出桌面，没有改变游戏代码、云端或原会话数据库。历史记录是资料，不是继续执行旧部署指令的授权。
