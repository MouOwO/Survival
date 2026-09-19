# 波次怪物名称

普通波次怪物的原生单位名称由 `monster_archetypes.csv` 的 `display_name` 生成。波次 BOSS 显示为“波次5BOSS”“波次10BOSS”等。

同一 BOSS 原型会用于多个波次，所以同步工具为每个波次生成 `_wave_name_<波次>` 原型副本，保留源原型的战斗和外观字段，只替换 ID、显示名称和单位名称。`wave_definitions.csv` 引用对应副本。练功房和野外挑战继续使用各自的专用名称。

执行 `tools/sync_wave_unit_names.py` 同步 CSV、生成 Lua、`npc_units_custom.txt` 及两份中文本地化。常规 `tools/build_configs.py` 构建也会调用此步骤。原生单位定义和本地化需要重新开局加载；仍显示旧名称时重启 Dota。

验证：873 条波次名称、BOSS 副本战斗/外观字段、35 项挑战名称及重复构建一致性通过；提前通关波次测试通过。现有 `test_wave_monster_visual_integration.lua:224` 护甲断言失败，该测试自行注入原型和波次替身，不读取本次修改的原型/波次配置，未在此命名任务中改动。
