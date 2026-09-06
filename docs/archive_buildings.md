# 存档建筑

数据来自《通关存档效果.xlsx》的“存档建筑”页；后续以
`data/csv/存档系统/archive_building_items.csv` 和 `archive_building_rules.csv` 为准。

每次通关获得 400 信仰值，北京时间每天最多获取 4000；余额跨天累积，
通行证不加成。消费不恢复当日获取额度。旧通关记录不追溯补发。
本地 `tongguan` 测试指令按增加次数结算，也受每日获取上限约束。

聊天输入 `xinyang 3000`（也支持 `-xinyang 3000`）直接增加当前账号 3000 信仰值。
仅 Workshop Tools 或作弊模式可用；参数为 1–1000000000 的整数。
此测试赠送不受每日 4000 上限影响，也不占用或重置当日额度。
通过现有存档事务持久化，支持 HTTP 后端；后端需部署包含 `faith_cheat` 的版本及新配置包。

存档界面新增“存档建筑”：九项全部显示，0 级点击激活，随后逐级升级，
每级固定消耗 3000 信仰值，最多 5 级。全部升满共 135000，
每日拿满需 34 天。余额、每日已获取数量、等级与属性在同一存档事务提交。
服务器校验等级和余额；同一操作重试不会重复扣款，失败后可以重新购买。

玲珑心/秘法鞋接入既有科技费用减免，满级分别减少 25% 木材/金币费用；
界面标价与实际扣费共用 `research/research_cost_service.lua`。
沿用项目原有直接减免费用的语义，而非先扣全款再回款。
圣剑、赤红甲、大剑、板甲使用既有永久属性效果。
深渊之刃只作用于主线波次 BOSS 对其目标城墙的普通攻击，
每次命中施加 2 秒 × 等级的基础眩晕；普通怪与独立挑战 BOSS 不触发。
狂战斧和雷神之锤每 60 秒累加对应百分比，按局内有效计时，
通关后停止，成长数值不写入永久档案。通关后购买的建筑属性下局生效。

## 发布

1. 在已有存档迁移之后执行 `server/migrations/202609060003_archive_buildings.sql`。
2. 发布新 HTTP 后端及 `server/bundles/current.json` 指向的配置包。
   新后端增加 `building_upgrade` 命令校验；不可仅替换游戏端配置 hash。
3. 同步 Lua、生成配置及已编译的 `panorama/scripts/custom_game/archive.vjs_c`。

本次已生成配置包并编译 Panorama；未执行远程数据库迁移或远程发布。

## 验证

Lua：`test_archive_buildings.lua`、`test_archive_building_effects.lua`，
以及现有存档、实时效果、科技交易测试。
后端：`server/tests/test_archive_backend.py`，覆盖重试、信仰日限、服务器日期及非法升级请求。
界面：`node tools/test_archive_ui.js`，覆盖余额显示、升级事件、满级和双击限制。
实际 Dota 对局中的眩晕动画及界面显示仍需游戏内验收。
