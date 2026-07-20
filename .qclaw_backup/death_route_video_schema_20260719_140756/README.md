# 防御塔配置

## 文件说明

所有 CSV 的第一行是 Lua 使用的英文字段名，第二行是以 `#中文名:` 开头的策划中文字段说明，第三行是以 `#types:` 开头的类型行。生成器会跳过中文说明行，不会把策划说明写入 Lua。

- `arrow_tower_base.csv`：箭塔 LV1-LV5 的基础攻击力、攻速、暴击几率、暴击伤害和攻击减甲。
- `tower_class_death.csv`、`tower_class_mystery.csv`、`tower_class_lightning.csv`、`tower_class_machine_gun.csv`、`tower_class_multi.csv`、`tower_class_frost.csv`、`tower_class_anti_air.csv`：各转职塔的策划数据。
- `tower_skill_definitions.csv`：唯一的策划技能定义表。

## 技能表设计原则

`skill_id` 是程序和策划之间的稳定接口。技能的 Lua 修改器、特效、触发方式和具体实现由程序根据 `skill_id` 维护，不写入 CSV。

CSV 只填写策划可读的玩法数据：

- `skill_id`：技能 ID，等级写在 ID 中，例如 `critical_strike_lv01`；因此不再设置 `level` 字段。
- `skill_name`：技能名称。
- `description`：技能描述。
- `target_scope`：`single` 单体，`multi` 多目标。
- `area_shape`：`none` 无范围，`circle` 圆形，`rectangle` 矩形或剑形路径。
- `area`：统一范围列表字段。
  - 圆形只填一个数，例如 `600`，表示半径 600。
  - 矩形填两个数，例如 `"200,900"`，表示宽度 200、长度 900。
- `damage_timing`：`instant` 瞬时伤害，`damage_over_time` 持续伤害。
- `duration`：持续伤害总时长。
- `damage_interval`：持续伤害跳伤间隔。
- `damage_multiplier`：伤害倍率。统一以普通攻击伤害作为基础伤害。
- `max_targets`：最多目标数。
- `attack_armor_reduction`：攻击减甲数值。
- `enabled`：是否启用。
- `notes`：策划备注。

特效、粒子、修改器名称、伤害实现模块、事件监听方式等程序字段均不放入技能表，由 Lua 根据 `skill_id` 自动对应维护。

## 修改流程

修改本目录 CSV 后，在项目根目录运行 `build_configs.bat`。不要直接修改 `scripts/vscripts/config/generated/*.lua`。
