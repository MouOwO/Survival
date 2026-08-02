# Current Task

## 最新任务（2026-08-02）

修复召唤战斗英雄的初始最大生命，使其最终采用`hero_definitions.csv`的`base_health × max_health_multiplier × hero_meta_max_health_multiplier`；新增`blood +/-数值|+/-百分比%`聊天作弊码。百分比按当前最大生命计算，加血封顶，减血最低保留1点，只作用于当前玩家召唤英雄。

## 最新状态

**直接设置最大生命的第一版已被实机判定失败；隐藏永久生命Modifier第二版已通过自动验证，并由用户在 Workshop Tools 中确认英雄血量正常。** 原元气弹/毒云任务保持既有可靠基线，本轮未修改其行为。

## 最新验证结果

- `HERO_CONFIGURED_HEALTH_LUA51_PASS`
- `HEALTH_CHEAT_LUA51_PASS`
- `HERO_HEALTH_CONTRACT_PASS`
- 6个本任务生产/测试Lua通过Lua 5.1语法检查；12个相关文件通过严格UTF-8；限定`git diff --check`通过。
- `ADDSKILL_CONTRACT_PASS`、元气弹和毒云专项契约/Lua 5.1回归通过。
- 第一版实机结果：直接调用`SetBaseMaxHealth/SetMaxHealth/SetHealth`后英雄仍为原生120生命，方案已废弃。
- 第二版实现：`modifier_survival_hero_base_health`使用`MODIFIER_PROPERTY_HEALTH_BONUS`把原生生命动态补足到CSV目标；普通英雄原生120时补2880，VIP同理补足到11000；真实装备生命继续额外叠加。
- 用户实机验收：隐藏永久生命Modifier生效，召唤英雄血量现在正常。
- 未扩大验收范围：用户本次未分别确认普通英雄3000、VIP英雄11000、装备生命叠加、死亡重生和`blood`四种输入；这些仅保留为按需回归项，不影响生命修复完成结论。

## 当前任务

将公共技能 `proto_holy_pulse`（原“圣光震荡·被动”）重做为五级“元气弹·被动”，保留 Ability ID `ability_survival_holy_pulse` 和公共池成员 `public_10`；同时让同一英雄的毒云在活动期间禁止再次触发，直到毒云结束。

## 当前状态

**代码、配置、生成结果和自动测试已完成，等待 Workshop Tools 实机验证和用户验收。上一项龙卷风保持阶段性可靠基线，本轮未改变其行为。**

## 验证结果

- `SPIRIT_BOMB_STATE_LUA51_PASS` / `SPIRIT_BOMB_CONTRACT_PASS`
- `POISON_CLOUD_STATE_LUA51_PASS` / `POISON_CLOUD_CONTRACT_PASS`
- 奥术弹幕、魔法弹弓、爆炎弹、移动冰球、寒冰锥、脉冲激射和龙卷风相关回归通过。
- 8个相关Lua文件通过 `luac5.1 -p`；12个相关源/生成/测试文件通过严格UTF-8检查；CSV与生成Lua的元气弹字段一致；限定范围 `git diff --check` 通过。
- 完整生成器在本任务无关的 `item_definitions.csv` 历史列错位处失败；已使用同一生成模块定向重建英雄技能，并使用Tooltip专用生成器重建Tooltip。生成内容差异仅包含本任务两份目标Lua。

## 剩余动作

- 完全重启 Workshop Tools Run，实机验证追踪视觉、5/7/9目标数量、每颗命中伤害与治疗、LV5独立爆炸及毒云活动期间不重触发。
- 自动测试、契约检查和Lua模拟不能替代实机验证；只有用户明确确认后才能记录为完成验收。

## 元气弹已确认边界

- LV1主攻击命中12%概率触发，在英雄普攻范围内选择最近最多5个敌人并分别发射追踪投射物；每颗真实命中造成触发时逻辑全属性×4纯粹伤害。
- LV2每颗真实命中恢复英雄5%最大生命值；按实际命中数累计并不超过最大生命值。
- LV3基础目标上限提高到7，每次触发另有10%概率提高到9；LV4完整继承LV3，无新增效果。
- LV5每颗命中独立20%概率在目标位置产生250范围爆炸，范围内所有敌人受到该颗基础伤害60%的额外纯粹伤害；原命中目标重复计算爆炸伤害。
- 攻击射程复用现有运行缓存、Script API、引擎API和英雄生成配置回退；投射物使用 `CreateTrackingProjectile` 和真实命中回调。

## 毒云新增边界

- 同一英雄已有活动毒云时，不再进行该技能的再次触发判定，也不替换旧毒云；仅在旧毒云自然结束或清理后允许再次触发。

## 已确认边界

- LV1主攻击命中15%概率触发；主龙卷从攻击者位置出发，以500速度实时追踪原攻击目标当前位置。
- 主龙卷第一次到达目标后附着跟随：目标移动时龙卷中心直接同步目标当前位置，不再产生500速度追赶距离。
- 原攻击目标在到达前死亡时，主龙卷继续移动到目标最后存活位置；在附着后死亡时，龙卷固定在死亡位置。两种情况均静止等待3秒结束。
- 主龙卷在t=0/1/2结算三次；每次实时读取攻击者当前逻辑力量、敏捷、智力总和，对中心300范围内每个敌人最多造成一次全属性×2纯粹伤害。
- 龙卷影响范围为中心600。LV3起范围内敌人降低20%移动速度；被主龙卷命中的敌人在仍处于600范围时额外降低15%，总计35%；离开范围立即移除对应效果。
- LV2仅完整继承当前速度500与LV1效果；LV4完整继承LV3，无新增效果。
- LV5主龙卷结束时统计仍存活且曾被主龙卷命中的不同目标。每个目标对应一个无上限小龙卷，从主龙卷结束位置朝随机目标方向移动。
- 小龙卷持续2秒，速度500、影响范围600、命中范围300、t=0/1结算；每次实时属性伤害为主龙卷的60%，即全属性×1.2纯粹伤害。
- 小龙卷只施加范围20%减速，不施加主龙卷命中额外15%减速，也不继续分裂。
- “随机目标方向”使用主龙卷结束时仍存活的已命中目标作为方向候选。

## 验证结果

- `TORNADO_STATE_LUA51_PASS`
- `TORNADO_CONTRACT_PASS`
- `FLAME_BURST_STATE_LUA51_PASS` / `FLAME_BURST_CONTRACT_PASS`
- `POISON_CLOUD_STATE_LUA51_PASS` / `POISON_CLOUD_CONTRACT_PASS`
- `MOVING_ICE_BALL_MATH_LUA51_PASS` / `MOVING_ICE_BALL_CONTRACT_PASS`
- `MAGIC_SLINGSHOT_TARGETS_LUA51_PASS` / `MAGIC_SLINGSHOT_CONTRACT_PASS`
- `ICE_CONE_CONTRACT_PASS`
- `BLADE_PULSE_STATE_LUA51_PASS` / `BLADE_PULSE_CONTRACT_PASS`
- 相关生产、配置和测试 Lua 均通过 `luac5.1 -p`；严格 UTF-8 检查通过；限定范围 `git diff --check` 通过；CSV与生成Lua关键字段一致。

## 后续优化与剩余确认

- 后续继续本任务时，再按用户指定重点优化龙卷视觉、追踪手感或其他表现；不得在没有明确需求时主动改变当前行为和数值。
- 尚未记录为最终用户验收的项目包括：完全重启Workshop Tools Run后的龙卷追踪、到达后附着、目标死亡后的最后位置、范围减速、实时属性伤害和LV5分裂方向。
- 若仍异常，收集同一龙卷ID的`[HeroTornado] event=spawn/attached/target_dead/finish`日志；普通`[CombatDamage]`日志只能证明伤害事务，不能证明视觉位置。

## 恢复规则

- 当前任务处于“阶段性完成/暂停优化”状态，不是活跃编码任务。
- 新会话不得自动继续修改；只有用户明确要求继续优化该技能时，才恢复为活跃任务。
- 恢复时以本文件中的已确认边界和`PROJECT_CONTEXT.md`中的稳定粒子架构为基线。

## 工作区保护

- 工作区已有大量用户未提交修改，且本任务涉及的CSV、生成配置、公共被动服务、Ability KV、Tooltip和文档均已处于修改状态。
- 只在当前内容基础上追加本任务改动，不回滚、覆盖或顺带清理其他修改。