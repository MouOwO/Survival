# Current Task

## 当前任务

完成并实机验收公共技能 `proto_poison_cloud` 五级“毒云”：

1. 等级1/2主攻击命中12%概率在目标触发位置生成固定400范围毒云，持续5秒；第1至第5秒各造成触发时全属性×1纯粹伤害。
2. 等级2起每次整秒伤害命中增加一层实时总护甲降低，1/2/3层分别降低20%/40%/60%；离开毒云、毒云替换或到期时立即恢复毒云部分。
3. 等级3触发率提高至20%、持续时间提高至7秒，共7次伤害；等级4完整继承等级3。
4. 等级5毒云中的敌人死亡时，以死亡位置为中心对300范围造成触发时全属性×3纯粹伤害；允许毒云内敌人连锁爆炸，每个死亡单位只触发一次。
5. 同一英雄同时只保留一个毒云；再次触发立即替换旧云并重置完整时序。

## 当前状态

**配置、运行逻辑、动态减甲Modifier、生成文件、Tooltip和自动测试已完成；LV2减甲已从实机不可靠的总百分比属性改为基于排除毒云自身后实时护甲动态重算的平坦减甲，并同步项目自定义护甲UI，等待Workshop Tools冷启动复验。同期已修复 `researcher_hero_armor_reduction_19` 被普通怪默认护甲下限阻断、同帧UI读取旧值及英雄权威快照隐藏临时减甲的问题，等待一并实机验收。**

## 已确认边界

- 保留 `proto_poison_cloud`、`ability_survival_poison_cloud`和原公共池身份，不创建新技能ID。
- 毒云中心固定为触发瞬间目标位置；目标之后移动不改变区域中心。
- 减甲使用实时总护甲百分比，不保存进入时护甲快照；科技、平A减甲、装备和其他Buff变化会实时参与结算。
- 多名英雄的毒云覆盖同一敌人时，减甲取最高有效效果而不相加超过60%；每名英雄各自仍只有一个毒云。
- LV5死亡判定使用死亡瞬间位置重新检查有效毒云，不依赖0.05秒成员缓存。

## 自动验证

- `FLAME_BURST_STATE_LUA51_PASS`
- `FLAME_BURST_CONTRACT_PASS`
- `POISON_CLOUD_STATE_LUA51_PASS`
- `POISON_CLOUD_CONTRACT_PASS`
- `RESEARCH_ARMOR_REDUCTION_STATE_LUA51_PASS`
- `RESEARCH_ARMOR_REDUCTION_CONTRACT_PASS`
- `MOVING_ICE_BALL_MATH_LUA51_PASS`
- `MOVING_ICE_BALL_CONTRACT_PASS`
- `MAGIC_SLINGSHOT_TARGETS_LUA51_PASS`
- `MAGIC_SLINGSHOT_CONTRACT_PASS`
- `ICE_CONE_CONTRACT_PASS`
- `ARCANE_BARRAGE_CONTRACT_PASS`
- `ADDSKILL_CONTRACT_PASS`
- 相关生产与测试文件严格 UTF-8 解码通过，无替换字符。
- `git diff --check` 通过。
- `C:\msys64\mingw64\bin\luac5.1.exe`语法检查通过；`C:\msys64\mingw64\bin\lua5.1.exe`已实际执行目标选择与单目标投射物创建测试。

## 下一步唯一动作

- 完全关闭并重新Run Workshop Tools，逐级确认12%/20%触发、400固定范围、第1秒开始的5/7次×1伤害、第三次命中达到60%动态减甲、离开/替换/到期恢复护甲，以及LV5的300范围×3连锁爆炸。重点确认项目自定义护甲UI在100护甲示例下依次显示80/60/40，并确认其他护甲变化会参与下一次0.05秒动态重算。
- 同次冷启动用普通波次怪或`addmonster`验收英雄攻击减甲：`researcher_hero_armor_reduction_19`每次普攻应降低9.5点自定义显示护甲，实际物理伤害同步提高，允许普通怪降到负护甲；只有显式配置`minimum_armor`的敌人才在下限停止。