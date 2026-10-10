# Project Context

Status: FACT
Last Verified: 2026-08-25

## Project Identity

- SurvivalContent 是 Dota 2 Arcade 生存塔防项目。
- 主要玩法包含英雄成长、防御塔、工人、资源、波次、挑战、奖励和永久玩家档案。
- 游戏运行层使用 Dota 2 Lua 与 Panorama；当前已验证的本地 Workshop 路径通过同机 Python HTTP API 接入 Supabase PostgreSQL。

## Current Architecture

```text
Dota client / Panorama
        |
        | Custom Game Event / NetTable
        v
Dota server Lua
        |
        | loopback HTTP
        v
Python: ThreadingHTTPServer + FishingApplication + SupabaseRpcClient
        |
        | HTTPS REST/RPC
        v
Supabase PostgreSQL
```

- Python API 位于独立 `D:\survival_database` 仓库，当前不是 FastAPI。
- 本地 Workshop/LAN 候选拓扑是同一主机运行 Dota 服务端 Lua、Python API 和 Supabase 访问；该结论不得外推为正常发布 Arcade 的事实。
- 正常发布 Arcade 中 Lobby Owner、Game Server、Lua 运行主机和 Python 主机的关系尚未证实，当前归类为 `MODEL-D`。见 `architecture/MULTIPLAYER_TOPOLOGY_REPORT.md`。
- Python API 保持绑定 `127.0.0.1:8765`；它只适用于 Lua 与 Python 同机的拓扑。不得为探测拓扑直接改绑 LAN 地址。

## Authority And Trust Boundaries

| Concern | Authority |
| --- | --- |
| 业务配置 | `data/csv/` |
| 生成 Lua | `scripts/vscripts/config/generated/`，禁止手改 |
| Gameplay 状态 | Dota server Lua |
| UI 表现 | Panorama，只消费服务端投影 |
| HTTP 与数据库凭据 | Python server environment |
| 永久数据 | Supabase RPC/PostgreSQL |
| 永久玩家身份 | 服务端 Steam Account ID，经 Python HMAC-SHA256 后入库 |

客户端不能决定身份、奖励、支付成功、价格、永久属性或数据库写入结果。

## Permanent Progression

- `/v1/profile` 负责首次幂等建档和已有档案读取。
- `/v1/online-time/checkpoint` 负责在线 checkpoint、累计和 final 请求。
- `player_gameplay_stats.csv` 是核心玩法属性默认值权威源；档案私有 `save.gameplay_stats` 不发布到公开 NetTable。
- 在线时长只累计同一 session、租约内相邻 checkpoint 的有效差值；首次、新 session、超租约和离线间隔累计 0。
- Session ID 必须包含每次运行唯一 nonce，避免跨 Workshop Run 重放历史幂等响应。
- `reward_grants` 是不可变发放记录，`player_effect_totals` 是永久效果当前投影。
- 已完工城墙毁坏通过 `finish("wall_destroyed")` 进入共享 final 状态机；验收服务端持久化以 Lua `final=true`、Python API HTTP 200 和 Supabase 返回最终在线累计为证据。终局后的本地 `session_closed` callback 可独立观测，不否定已成功提交的服务端 final。

详细契约见 `PLAYER_PROFILE_INTEGRATION.md` 与 `FISHING_REWARD_INTEGRATION.md`。

## Core Gameplay Engineering Rules

- Lua 生产代码兼容 Lua 5.1。
- 齐天大圣分身攻击用engine_attack及装备独立flat继承，native值限幅1e8，普通攻击经共享filter还原完整伤害，降低后清倍率；仅投影攻击、不覆写生命scale。addattack完整override含0时不重复加装备，主宰/末日/小游侠既有投影规则保留；模型边界/HP fixture通过，实际Dota待验证（2026-10-09）。
- 暴击/死亡路线class_1的R/SR/SSR真实影魔body沿用原生普攻动画；critical_strike_不再额外叠加默认速度的StartGesture，连续攻击保留当前目标、原生CD与伤害，雷电/机枪专用动作保留。源码/模拟回归通过，实际画面待游戏验证（2026-10-09）。
- 防御塔最终路线满级后移除全部升级技能，显示合成终极塔按钮；七种路线各至少一座最终满级塔且无存活终极塔时亮起，否则置灰。同一能力沿建筑/材料变化事件更新激活，不加轮询；R5/SR5等仍有下一行时继续升级。合成消耗七路各1座材料，每玩家终极塔上限1（2026-10-09）。
- 原生技能等级点复用LevelPanel与亮暗状态：多级点宽度铺满104px图标、高12，五点各18.4px并间隔3px，放在按钮下方。沿用square缓存刷新，单级/无点恢复完整旧样式，原生面板重建清除失效快照（2026-10-09）。
- 英雄技能说明的LVn行使用52px紧凑等级列与剩余宽度换行；当前等级金色，其余灰色，LV1同规则。等级刷新重算高亮，复用行清除旧class；通用建筑/科技属性布局沿用既有规则（2026-10-09）。
- 英雄公共技能上限3：二至四转各三选一新技能，五至十转各+1公共技能点，仅升级已拥有且未满级的公共技能；专属技能沿原解锁规则。五转奖励、挑战说明和选择规则已统一，HUD加号消费服务端skill_points/can_upgrade，不受转生等级单独限制（2026-10-09）。
- 建造者/修理工右键城墙支持单位目标及墙占地落点，后者用服务端格子身份O(1)解析并校验所有权。修理每0.1秒执行，靠近和治疗缓存实际句柄；血量>98%不启动新修理，已有修理持续到满血，手动健康目标保留待命并跳过搜索/路径，原每秒修复量不变（2026-10-08）。
- 抽奖四个宝箱背景在同一横向strip内原生滑动，跨页固定0.2秒linear，前景文字/按钮同步0.2秒opacity淡入；连点转向最新目标、同池快照不重启动画，视口适配复用既有fit，无新增动画轮询（2026-10-08）。
- 左上导航图标与下方文字使用同一中心线：文字按实际宽度在既有captionHost居中，适配普通入口、长标题和完整/简化特效入口（2026-10-08）。
- 合成伐木工保留一个配置性格被动（LV1–LV7），技能栏允许ability_lumberjack_personality_*并复用已有tooltip；就地合成仍可沿用普通实体名，不能只显示已消费的合成按钮。LV8仍按配置无性格（2026-10-08）。
- 英雄召唤跟随本人祭坛建造解锁：已完工活祭坛、肉鸽免费祭坛次数或建造配置主城门槛均可授予阶段资格，独立快照summon_unlocked用于原生入口与按钮。召唤保留VIP/付费和单英雄限制，无本人主城时可在本人活祭坛/建筑师附近安全生成；已有主城始终优先，F2回城仍要求本人主城（2026-10-08）。
- 建造者头像由服务端builder身份显式映射到原生艾欧ScenePanel；建造开工只播放一次约1秒的原生attack，结束恢复idle，持续红色充能已移除。头像与世界至宝外观独立，复用原有选中/多选生命周期（2026-10-08）。
- 建造者外观由 builder_definitions.csv + asset_catalog.csv 配置，默认可拾取艾欧本体+仁爱之友至宝9235；至宝用可渲染prop_dynamic父子挂载和独立骨架序列，常驻粒子显式绑定原生卡片挂点，失败回退预载的原版光球。raw dota_item_wearable虽有服务端实体但在此creature上不显示，禁止再用它或无hitbox饰品替代主体。独立 builder_presentation_service 管理常驻/施工反馈和生命周期；主体仍是每玩家私有 npc_survival_builder_proxy，地面寻路/相位/修理身份不随外观变化，实机已确认显示恢复（2026-10-08）。
- 英雄逻辑三维通过项目战斗属性快照获取，不以原生 `GetStrength()` 等为权威。
- 技能伤害复用现有伤害服务、事件总线和事务。
- 真实逐单位碰撞的穿透直线技能使用 `ProjectileManager:CreateLinearProjectile()`。
- 攻击射程复用项目现有回退辅助函数。
- 定时逻辑优先使用项目 scheduler，并明确结束与清理路径。
- 防御塔底座缓存包含XYZ，成功移动后通过既有事件回收并重建完整粒子组；防空原生陷阱圆环使用WORLDORIGIN与服务器CP0避开客户端位置同步延迟，终极单体/编队移动发布相同投影事件；不增加位置轮询（2026-10-06）。
- 防御塔弹道保留global_rules.csv的0.5倍率规则；当前class_1暴击、class_2激光、class_4机枪、class_5多重、class_6寒冰、class_7防空豁免。暴击/多重/寒冰/防空四路线各阶等级弹速已由500统一为1500（逐风弩手原有效速度×3），其他路线不变。基础速度缓存不重复缩放，自建箭命中延迟匹配飞行时间（2026-10-08）。
- 原生防御塔无SetProjectileSpeed接口；生效弹速缓存必须独立写入，实际原生速度通过modifier_tower_projectile_speed的PROJECTILE_SPEED_BONUS及原生基础缓存设置。已修复多重分裂箭回退500、其他原生塔仍5000的真实接口差异，私有原生实体确认目标1500（2026-10-08）。
- 防空炮普攻三阶采用同族原生灼热箭：R与多重SR同源，SR为克林克兹马拉克斯之怒，SSR为其红色余烬黯灭变体；权威CSV、资产/预载代理和A/B/C生成政策同步，工程师外观与战斗数值保留（2026-10-08）。
- 防御塔跨攻击周期保持当前合法战斗目标，死亡/失效/出射程或移动重置后才按塔自身二维距离平方选最近敌人；保留空闲发现、训练靶让位、手动命令和原生订单恢复。此规则替代此前按城墙距离周期重选（2026-10-06）。
- 多人 Builder progression、建筑数量、普通波次通道、怪物城墙目标和断线生命周期均以数字 `player_id` 隔离；同属 `DOTA_TEAM_GOODGUYS` 不能作为共享或所有权依据。正式波次怪物上限与HUD数量为全场共享，持续超限时全员判负。
- 玩家命令统一经过唯一 ExecuteOrderFilter；真实玩家命令的全部单位必须解析为该玩家 owner，系统/AI issuer `-1` 保持放行。服务端注册身份和 `survival_player_id` 优先于普通 creature 不可靠的引擎 owner getter。
- 四个物理波次出生点由 `player_slots.csv::wave_spawn_marker` 配置。已完工城墙相对四点中心的右上/左上/左下/右下区域分别选择北/西/南/东；同侧玩家并排出生，未完工时使用初始槽位通道。玩家断线后该槽位本局不再生成波次怪，其他玩家通道继续运行。全场正式波次上限90、连续超限宽限10游戏秒，不按人数扩大（2026-10-06）。
- 小地图快捷入口复用统一输入分发：空格取本人服务器建造师身份并选中；F2 经服务器正式英雄校验，使用本人活主城附近的共享安全落点解析器，不能按队伍选城。见 `../MINIMAP_SHORTCUTS.md`。

## Current Development Phase

Backend Integration Phase：当前 P0 是 Player Session、在线 checkpoint、终局 finalization 和生产双玩家联调。

动态状态只记录在 `CURRENT_TASK.md`、对应 Task 文件和 `KNOWN_ISSUES.md`。

## Context Map

| Topic | Source |
| --- | --- |
| 当前调度 | `CURRENT_TASK.md`, `CURRENT_SPRINT.md`, `tasks/` |
| API / DB / Event / Attribute 索引 | `registry/` |
| 玩家档案 | `PLAYER_PROFILE_INTEGRATION.md` |
| 在线奖励 | `FISHING_REWARD_INTEGRATION.md` |
| 肉鸽奖励 | `ROGUE_REWARD_INTEGRATION.md` |
| 波次模型 | `WAVE_MODEL_RESOURCE_LIFECYCLE.md` |
| 故障排查 | `WAVE_MODEL_LOADING_TROUBLESHOOTING.md`, `KNOWN_ISSUES.md` |
| 历史证据 | `SESSION_LOG.md`, `archive/`，仅按需读取 |

## History

重构前的完整稳定知识与历史混合文档保存在 `archive/2026-08-25-pre-knowledge-refactor/PROJECT_CONTEXT.md`。


## 防御塔选敌更新（2026-10-07）

自动攻击重选采用射程内首领/大头兵优先，同档离塔最近，无优先怪时最近普通怪；使用出生时缓存的boss/角色标记与二维距离平方。合法目标跨攻击周期锁定，新怪不抢占。死亡/升级清除旧manual/forced/windup立即重选，移动沿用原即时刷新；下一帧恢复失去的订单或再次失效的目标。系统订单不建立手动锁，明确玩家指定仍可覆盖。无新增轮询/全局死亡监听、CD重置或伤害改动。私有Tools交接通过且实体零残留，正式塔升级仍待新局画面确认。详见CURRENT_TASK与validation/20261007/tower_target_priority.json。
## 无尽外观设计入口（2026-10-09）

用户确认的待接入方案见[50怪与四轮饰品设计](../endless_monster_visual_design_20261009.md)及docs/design下Excel/JSON/CSV。50主体每50波换饰品、200波重复；201之后固定基础体型1.5倍。当前运行入口仍使用archive_endless_rules固定模型，设计文件不是运行配置；实现及目测状态看CURRENT_TASK/KNOWN_ISSUES。
