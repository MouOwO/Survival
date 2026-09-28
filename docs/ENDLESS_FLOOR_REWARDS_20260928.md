# 无尽层数存档图片识别与接入

原 1—50 项累计积分奖励保持；新增 51—82 项按历史最高已通关层数判定。图片写“大于”，因此所需通关层数为门槛 + 1。

| 编号 | 图片条件 | 实际通关要求 | 效果 | 字段 |
|---|---|---|---|---|
| 51 | 无尽层数大于10 | 11 | 伐木效率+1 | `lumberjack_efficiency` |
| 52 | 无尽层数大于20 | 21 | 伐木工攻速+5% | `lumberjack_attack_speed_bonus_pct` |
| 53 | 无尽层数大于30 | 31 | 英雄攻击属性成长+2 | `hero_attribute_growth` |
| 54 | 无尽层数大于40 | 41 | 英雄造成伤害加木+2 | `hero_damage_wood_flat` |
| 55 | 无尽层数大于50 | 51 | 英雄三围加成+10% | `hero_attribute_bonus_pct` |
| 56 | 无尽层数大于60 | 61 | 英雄攻击减甲+3 | `hero_attack_armor_reduction` |
| 57 | 无尽层数大于70 | 71 | 金矿效率+20% | `gold_mine_yield_bonus_pct` |
| 58 | 无尽层数大于80 | 81 | 墙生命加成+12% | `wall_health_bonus_pct` |
| 59 | 无尽层数大于90 | 91 | 箭塔最终伤害+12% | `tower_final_damage_bonus_pct` |
| 60 | 无尽层数大于100 | 101 | 英雄最终伤害+12% | `hero_final_damage_bonus_pct` |
| 61 | 无尽层数大于110 | 111 | 练功房收益+20% | `training_room_income_bonus_pct` |
| 62 | 无尽层数大于120 | 121 | 箭塔攻击加成+12% | `tower_attack_bonus_pct` |
| 63 | 无尽层数大于130 | 131 | 箭塔暴击几率+5% | `tower_critical_chance_pct` |
| 64 | 无尽层数大于140 | 141 | 箭塔暴击伤害+10% | `tower_critical_damage_bonus_pct` |
| 65 | 无尽层数大于150 | 151 | 英雄暴击几率+5% | `hero_critical_chance_pct` |
| 66 | 无尽层数大于160 | 161 | 英雄暴击伤害+10% | `hero_critical_damage_bonus_pct` |
| 67 | 无尽层数大于170 | 171 | 墙减伤+5% | `wall_damage_reduction_pct` |
| 68 | 无尽层数大于180 | 181 | 英雄造成伤害属性+5 | `hero_attributes_per_damage` |
| 69 | 无尽层数大于200 | 201 | 英雄攻击减甲+8 | `hero_attack_armor_reduction` |
| 70 | 无尽层数大于220 | 221 | 英雄最终伤害+12% | `hero_final_damage_bonus_pct` |
| 71 | 无尽层数大于240 | 241 | 箭塔攻击加成+12% | `tower_attack_bonus_pct` |
| 72 | 无尽层数大于260 | 261 | 英雄造成伤害属性+8 | `hero_attributes_per_damage` |
| 73 | 无尽层数大于280 | 281 | 英雄全属性加成+12% | `hero_attribute_bonus_pct` |
| 74 | 无尽层数大于300 | 301 | 英雄攻击加成+15% | `hero_attack_bonus_pct` |
| 75 | 无尽层数大于320 | 321 | 英雄最终伤害+15% | `hero_final_damage_bonus_pct` |
| 76 | 无尽层数大于340 | 341 | 英雄攻击减甲+10 | `hero_attack_armor_reduction` |
| 77 | 无尽层数大于360 | 361 | 英雄造成伤害+20 | `hero_damage_bonus_flat` |
| 78 | 无尽层数大于380 | 381 | 英雄三围加成+15% | `hero_attribute_bonus_pct` |
| 79 | 无尽层数大于400 | 401 | 墙生命加成+30% | `wall_health_bonus_pct` |
| 80 | 无尽层数大于420 | 421 | 英雄攻击减甲+15 | `hero_attack_armor_reduction` |
| 81 | 无尽层数大于440 | 441 | 英雄三围加成+15% | `hero_attribute_bonus_pct` |
| 82 | 无尽层数大于460 | 461 | 英雄最终伤害+15% | `hero_final_damage_bonus_pct` |

## 实现与验证

- 原 50 项累计积分奖励保留；新增 32 项使用 required_wave（图片门槛 + 1）与存档 endless_best_wave，累计积分不会代替层数。
- 达成、效果写入、完成标记与去重一起提交；旧档由无参数服务端补领命令核对已保存的最高层数，不接受客户端提交层数。
- 标准模式复用既有存档属性投影。实际伤害回调验证加木材 +2、三围成长 +13；其他攻击者不触发英雄奖励。纯净模式既有规则回归通过。
- 两份图标目录与 CSV 映射增加 32 个统一青灰盾牌，新增卡片显示“超过 N 层”，计数目标为 N+1；弹窗显示完整解锁条件。
- 旧工作簿导入保留图片新增的层数行，不会重新导入时截回 50 项。
- 测试通过：32 个临界条件、全量效果合计、积分/层数隔离、旧档补领与去重；本地存档失败/重试；真实 HTTP/Lua 后端 21 项；属性投影与伤害事件；纯净模式；82 项 UI 图标及缓存。5 个 UI 资源编译 0 failed。

## 云端同步状态

云端与当前游戏仍指向旧包 4ff1629d…；新候选包 1bfa4497… 已完成，尚未激活，等待用户选择同步时间。切换后需要重新进入对局加载新的 Lua 和规则哈希。没有修改任何真实玩家档案或消费资源。

候选包与可回滚部署脚本：output/endless_floor_rewards_20260928。部署会先核对当前服务、包版本及文件哈希，保留旧包与备份；健康检查失败自动回滚。候选包另含本会话早先已授权的挑战建筑模型、30 分钟配置及伐木工成长说明，与当前工作区一致。
