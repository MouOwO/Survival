# 防御塔配置

## 文件说明

所有 CSV 的第一行是 Lua 使用的英文字段名，第二行是以 `#中文名:` 开头的策划中文字段说明，第三行是 `#types:` 类型行。生成器会跳过 `#中文名:` 行，不会把中文字段说明写入 Lua。

- `arrow_tower_base.csv`：箭塔转职前的基础等级属性。
- `tower_class_death.csv`：死亡之塔。
- `tower_class_mystery.csv`：神秘之塔。
- `tower_class_lightning.csv`：闪电塔。
- `tower_class_machine_gun.csv`：机枪塔。
- `tower_class_multi.csv`：多重塔。
- `tower_class_frost.csv`：冰霜之塔。
- `tower_class_anti_air.csv`：防空炮。

## 转职塔表填写规则

每种转职塔使用相同宽表结构：

- `record_type=class_change`：箭塔转职选择 Tooltip 数据，包括转职金币、木材、人口和描述。
- `record_type=level`：该职业某一级的属性、被动技能和升级按钮 Tooltip 数据。
- 每增加一级，就复制一行 `level`，修改 `record_id`、`tower_id`、`name`、`level`、基础属性和升级信息。
- `attack_speed` 表示每秒攻击次数。
- `critical_chance_pct` 使用百分数，例如 `13` 表示 13%。
- `critical_damage_multiplier` 使用倍率，例如 `5` 表示 5 倍伤害。
- `attack_armor_reduction` 表示攻击造成的减甲数值。
- 未完成的数据保持空白，禁止用 0 代替未知值；未完成职业保持 `enabled=0`。

修改后运行项目根目录的 `build_configs.bat`。不要直接修改 `scripts/vscripts/config/generated/*.lua`。
