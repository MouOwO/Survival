# 丰饶 N10 第 8 波飞行小怪血量修正

用户于 2026-10-26 确认：丰饶模式 N10，第 8 波的红翼飞行恶魔小怪，最终生命应为 **1,420,000（142 万）**。旧计算为轮换怪基础生命 1,105 × 丰饶 N10 生命倍率 356 = 393,380。

此次仅修正这一模式、难度、波次、轮换位置的小怪最终生命。共享基础值 1,105、其他难度和模式、首怪与地面小怪、攻击和护甲均保留。

权威配置在 `data/balance/human_spec_v3/human_spec.json` 的 `special_rotation_health_overrides`，与 Excel 工作表“轮换怪血量修正”严格交叉校验。运行 `tools/import_human_monster_spec.py` 后生成 `normalized.json` 和 `config/generated/human_monster_spec.lua`；正式波次构造时，在模式倍率计算后应用最终生命覆盖，避免再次乘以倍率。

验证包括双源导入与重建，以及正式波次构造、变体解析、出生设置和 UI 数值投影的离线集成检查。本次代码修正未自动发布工坊，也未通过正在进行的对局热更新。
