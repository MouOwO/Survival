# Current Task

## 当前任务

替换箭塔机枪路线的建模与技能视觉：

1. 机枪塔 LV1～5 使用 Sniper `Occultist's Pursuit` 五件套。
2. 赏金机枪 LV1～5 使用 Bounty Hunter `Heartless Hunt` 六件套。
3. 爆矢加特林 LV1～10 使用 Windranger `Compass of the Rising Gale` Arcana 主体和五件套。
4. 赏金金币成功到账时播放 Jinada/Cutpurse 反馈。
5. 爆矢加特林第五次同目标攻击或击杀触发攻速 Buff 时播放 Focus Fire 反馈；不改变原有 20%、3 秒、不可叠加可刷新的数值语义。

## 当前状态

**配置、运行时接线、生成一致性和自动回归审计已经完成；等待 Workshop Tools 实机视觉验收。**

## 已确认结果

- 三段路线分别映射到 `tower_machine_gun_sniper_occultist`、`tower_machine_gun_bounty_heartless`、`tower_machine_gun_windranger_rising_gale`。
- 旧 `tower_gyro`、`tower_tinker` 及代理单位已不再被生产配置引用。
- Jinada 粒子只在资源增加请求成功时播放在受击目标上。
- Focus Fire 起手粒子在 Buff 成功应用/刷新时播放在塔上；持续粒子由 Buff 配置管理。
- 机枪和相邻箭塔路线定向测试全部通过；限定 `git diff --check` 通过。
- 全量 60 项 Lua 测试为 57 通过、3 个既有英雄测试失败；失败文件与本任务无文件交集。
- 五个权威 CSV 定向生成后的 Lua 与正式生成文件逐字节一致。
- 共享攻击文件的死亡塔动画、选择、Templar 视觉和死亡榴弹回归测试全部通过。

## 下一步唯一动作

- 完全停止并重新 Run，实机创建三阶段塔，检查完整套装、骨骼跟随、弹道、Jinada 和 Focus Fire 表现。