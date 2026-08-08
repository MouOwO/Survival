# 防御塔配置

## 文件说明

所有 CSV 的第一行是 Lua 使用的英文字段名，第二行是以 `#中文名:` 开头的策划中文字段说明，第三行是以 `#types:` 开头的类型行。生成器会跳过中文说明行，不会把策划说明写入 Lua。

- `arrow_tower_base.csv`：箭塔 LV1-LV5 的基础攻击力、攻速、暴击几率、暴击伤害和攻击减甲。
- `tower_class_death.csv`：死亡路线完整升级链，依次包含死亡之塔5级、碎骨重炮5级、死神榴弹炮10级。
- `tower_class_mystery.csv`、`tower_class_lightning.csv`、`tower_class_machine_gun.csv`、`tower_class_multi.csv`、`tower_class_frost.csv`、`tower_class_anti_air.csv`：其他转职塔的策划数据。
- `tower_skill_definitions.csv`：唯一的策划技能定义表。
- `buff_definitions.csv`：正负面状态、叠加规则、刷新规则和表现定义表。

## 技能表设计原则

`skill_id` 是程序和策划之间的稳定接口。技能的 Lua 修改器、特效、触发方式和具体实现由程序根据 `skill_id` 维护，不写入 CSV。

CSV 只填写策划可读的玩法数据：

- `skill_id`：技能 ID，等级写在 ID 中，例如 `critical_strike_lv05`；因此不再设置 `level` 字段。
- `skill_name`：技能名称。
- `description`：技能描述。
- `trigger_type`：被动触发类型，例如 `attack_chance` 攻击概率触发、`attack_counter` 攻击计数触发、`on_critical_hit` 暴击后触发。
- `trigger_chance_pct`：被动触发几率。
- `trigger_attack_count`：触发前所需攻击次数。
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
- `buff_id`：技能施加的状态 ID，具体叠加、驱散和特效规则由 Buff 表管理。
- `enabled`：是否启用。
- `notes`：策划备注。

技能表不直接保存特效或 Modifier 名称。状态类技能只引用 `buff_id`；特效、正负面类型、叠加和刷新规则统一放在 `buff_definitions.csv`。伤害实现模块和事件监听方式仍由 Lua 根据 `skill_id` 维护。

## 塔等级与技能继承

每一级塔在所属路线表中填写：`base_attack_damage`、`upgrade_gold`、`upgrade_wood`、`population_cost` 和 `skill_ids`。

- `base_attack_damage` 是升级完成后显示的基础攻击力。
- `upgrade_gold` / `upgrade_wood` 是升到本级实际支付的资源，不是从本级升到下一级的资源。
- `population_cost` 是成为该级塔后持续占用的人口，不是人口上限奖励。基础箭塔填写 `0`，所有转职塔等级填写 `1`；升级时 Lua 按新旧人口占有的差额结算，因此首次转职占用 1 人口，后续升级不重复占用，塔被移除时释放人口。
- 生成 Lua 将 `population_cost` 明确映射为 `population_occupied`，运行时禁止继续使用旧的 `population_delta` 增量语义。
- `skill_ids` 是本级最终生效的全部技能ID列表，以 `|` 分隔。
- 技能升级时，用新等级技能ID替换旧等级技能ID；技能继承时保留已有技能ID并追加新技能ID。
- 技能封顶后，后续塔等级继续引用同一个技能ID，不复制技能数据。

死亡路线示例：

- 死亡之塔LV4和LV5都使用 `critical_strike_lv05`。
- 碎骨重炮继承 `critical_strike_lv05`，并让自身 `bone_cannon` 技能随碎骨重炮等级成长，LV4后封顶为 `bone_cannon_lv05`。
- 死神榴弹炮LV1至LV10始终使用 `critical_strike_lv05|bone_cannon_lv05|death_grenade_lv01`，三个被动技能数值均不再变化。

## 修改流程

修改本目录 CSV 后，在项目根目录运行 `build_configs.bat`。不要直接修改 `scripts/vscripts/config/generated/*.lua`。
