# 2026-11-21 无登录器原游廊验证

普通 Steam 客户端已从原游廊条目 3824360109 进入并载入玩法地图，仍未取得网页登录短码。当前公开版本为 2026112102，Steam manifest 为 5921921441403360983。测试使用更新后的 Dota build 26825343，由玩家电脑托管单人密码房。游戏依次载入 ws4_entry 与 template_map，客户端未安装本轮候选或启动登录器。

官方完整下载回执与运行版本对应。尝试期间首次授权反复失败，游戏日志有 3 条限频后的 start / http / 0、6 次失败状态及 6 次既有辅助通道未握手超时。HTTPS 健康接口同时返回 200。结论限于这一实际对局和当前可用托管方式。约一分钟后入口地图成功换至玩法地图，认证从玩法地图发起。测试进程正常关闭。证据在 D:/Survival_本地工具/runs/no_launcher_native_20261121_01/native_result_receipt.json，其过滤日志只保留地图、状态和超时计数。

本轮未单独向原生工厂注入探针。创建阶段的两个接口返回空值、没有 Send 的实测属于 [11 月18日匿名对照](http_environment_control_20261118.md)。本日的 http / 0 发生在自动尝试已有辅助通道后，不能写成服务端返回 HTTP 0。当前工厂已经优先调用原生 API，原生通道恢复后可沿用以前的逐人网页授权。游戏、后端和工坊没有提交运行改动。

- [Tower Feast 作者的工坊说明](https://steamcommunity.com/sharedfiles/filedetails/?id=2234335140)描述本地主机的 Steam 网页确认。本项目过去用自己的 OpenID 流程从原条目完成两人同局授权和云档读回。公开说明不提供后台传输协议或本日可用性证明。见[历史实测](../../native_arcade_cloud_20261027.md)。
- 梦之岛的参考价值是轻量入口图换到玩法图，本项目现有流程已经实现。保卫小塔展示独立大厅、组队和分配对局服，本项目现有大厅原型还缺真实可用的游戏服，网页服务器或业务 ECS 无法单独完成这一步。见[参考与既有实验](../../hosted_lobby_20261025.md)。
- [Steamworks 身份文档](https://partner.steamgames.com/doc/features/auth#website)支持浏览器 OpenID。独立游戏的会话票据还需要客户端取得票据并提交给后端。项目未找到开放给普通 Dota 游廊脚本的通用票据入口。即便网页已确认 Steam 身份，也需要一条对局到业务后台的通道，才能逐人授权、读取和写回云档。
- [Valve 问题 #35497](https://github.com/ValveSoftware/Dota2-Gameplay/issues/35497)官方接口于 11 月21日返回 open、14 条评论且均显示 NONE，未见维护者确认恢复的办法。已有本站报告，新增普通公开版复测材料留在本地。[官方专服接入功能建议 #36992](https://github.com/ValveSoftware/Dota2-Gameplay/issues/36992)仍 open，不能视为已上线服务。Valve 历史公告说明曾为自定义游戏提供专服和 V2 凭据，仍需本条目实际分配或平台确认。参见 [Reborn 公告](https://www.dota2.com/reborn/updates)与 [V2 公告](https://store.steampowered.com/oldnews/49093)。

下一步的可行性门槛是本条目普通、无辅助客户端从正式对局收到一次匿名 HTTPS 200。通过后沿现有 Steam OpenID，继续验证本人和队友分别批准、独立云档读取以及退出再进读回。平台没有提供对局 HTTP 或可信专服前，公开版本的联机流程仍使用现有登录器。
