# Attribute Registry

Status: FACT
Last Reviewed: 2026-08-25

| Key / Group | Type | Meaning | Source |
| --- | --- | --- | --- |
| `player_gameplay_stats.*` | Mixed numeric | 玩家核心经济、英雄、防御塔、城墙、伐木工和在线累计属性 | `data/csv/玩家档案系统/player_gameplay_stats.csv` |
| `online_seconds_total` | Integer seconds | 玩家永久累计有效在线秒数 | `player_gameplay_stats.csv` / `player_gameplay_stats` |
| `hero_all_attributes_flat` | Integer | 永久英雄全属性固定加成 | `star_blessing_reward_definitions.csv` |
| `hero_attack_flat` | Integer | 永久英雄攻击固定加成 | `star_blessing_reward_definitions.csv` |
| `lumberjack_attack_speed_pct` | Percentage points | 永久伐木工攻速百分比加成 | `star_blessing_reward_definitions.csv` |
| `gold_mine_income_pct` | Percentage points | 永久金矿收益百分比加成 | `star_blessing_reward_definitions.csv` |

完整字段、类型、范围和默认值必须直接读取权威 CSV；本索引不复制全部字段，避免双重维护。