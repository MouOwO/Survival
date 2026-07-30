# 炙热巨箭塔 LV1：原生线性穿透投射物技术复盘

## 1. 最终结果

用户已在 Workshop Tools 实机确认修复成功：同一条炙热巨箭视觉路径接触第一、第二及后续敌方单位时，每个单位都会分别受到一次路径伤害。技能行为等价于“维鲁斯 Q 式”的有宽度直线穿透弹道：命中第一个目标不会停止，路径上的后续目标继续命中。

## 2. 权威需求

- 特效路径碰到任何敌方单位都造成伤害。
- 碰撞宽度与可见特效宽度一致。
- 不因地形高低差漏判路径单位。
- 命中第一个单位后继续穿透第二、第三及后续单位。
- 每个单位使用同一份攻击伤害公式，最终伤害分别受各自物理护甲影响。
- 伤害以空间碰撞触发，不能把固定 `0.3s` 作为提前判定依据。
- 一支巨箭对同一单位最多结算一次。

## 3. 为什么旧方案实机失败

### 3.1 视觉粒子不是单位碰撞体

原始粒子文件：

`d:\steam\steamapps\common\dota 2 beta\content\dota\particles\econ\items\vengeful\vengeful_arcana\vengeful_arcana_wave_of_terror_v2.vpcf`

确认内容：

- 根粒子通过 `C_INIT_VelocityFromCP` 读取 CP1 作为视觉速度。
- 唯一碰撞相关操作器是 `C_OP_MovementPlaceOnGround`。
- `m_CollisionGroupName = "DEBRIS"` 用于场景/地面定位。

这些配置不会：

- 检测英雄或普通单位；
- 向 Lua 返回被接触单位；
- 调用 `OnProjectileHit`；
- 自动造成伤害。

结论：`ParticleManager:CreateParticle()` 只能播放视觉，不能把该 VPCF 当作可监听的单位伤害碰撞体。

### 3.2 手写定时扫描与视觉前缘不是同一个系统

失败实现使用：

- `scheduler.every()` 每隔固定时间推进逻辑距离；
- `tower_skill_geometry.enemies_in_path()` 扫描相邻逻辑线段；
- `hit[entindex]` 防止重复伤害。

这种实现把三个独立系统强行同步：共享调度器时间、Lua 数学前沿、粒子模型/子粒子视觉前缘。即使速度数值相同，也不能保证 Dota 实机中视觉接触单位时，Lua 扫描恰好找到同一单位；更不能证明第一个目标之后仍会持续获得真实引擎命中事件。

固定写成“提前 0.3 秒”也不是修复，因为攻击距离、速度、模型前伸和帧调度变化后会再次错位。

### 3.3 旧测试只能证明 Lua 循环，不能证明引擎穿透

旧 `test_tower_wave_of_terror_visual.lua` mock 了：

```lua
package.loaded["systems/tower_skill_geometry"] = {
    enemies_in_path = function(...)
        return { first, second, third }
    end,
}
```

测试通过只表示收到 `{ first, second, third }` 后，Lua 会循环三次。它没有验证：

- Dota 是否真的为第二、第三个单位触发命中；
- 命中第一个单位后投射物是否被删除；
- 共享能力回调是否能识别同一支投射物的后续命中；
- 视觉结束、塔销毁后状态是否正确失效。

这是“自动测试通过但实机仍失败”的直接教训。

## 4. 官方机制与本机证据

Dota 自带样例：

- `d:\steam\steamapps\common\dota 2 beta\game\dota_addons\conquest\scripts\vscripts\breathe_fire.lua`
- `d:\steam\steamapps\common\dota 2 beta\game\dota_addons\conquest\scripts\vscripts\breathe_poison.lua`
- `d:\steam\steamapps\common\dota 2 beta\game\dota_addons\overthrow\scripts\vscripts\breathe_fire.lua`
- `d:\steam\steamapps\common\dota 2 beta\game\dota_addons\overthrow\scripts\vscripts\breathe_poison.lua`

这些样例使用 `ProjectileManager:CreateLinearProjectile(info)`，并在 `OnProjectileHit` 最后 `return false`。线性投射物提供真实单位碰撞宽度和逐单位命中回调；回调不请求删除时，可以继续穿透后续单位。

穿透必须同时满足两个条件：

```lua
bDeleteOnHit = false
```

以及：

```lua
function ability:OnProjectileHit_ExtraData(target, location, extra_data)
    -- 处理当前单位
    return false
end
```

只设置其中一项不应被视为完整穿透契约。

## 5. 最终实现结构

### 5.1 发射

生产文件：

`d:\steam\steamapps\common\dota 2 beta\game\dota_addons\survival\scripts\vscripts\systems\tower_special_skill_system.lua`

核心参数：

```lua
ProjectileManager:CreateLinearProjectile({
    Ability = ability,
    EffectName = WAVE_OF_TERROR_PARTICLE,
    Source = tower,
    vSpawnOrigin = start_pos,
    vVelocity = direction * 1200,
    fDistance = 1200,
    fStartRadius = 112,
    fEndRadius = 112,
    iUnitTargetTeam = DOTA_UNIT_TARGET_TEAM_ENEMY,
    iUnitTargetType = DOTA_UNIT_TARGET_HERO + DOTA_UNIT_TARGET_BASIC,
    iUnitTargetFlags = DOTA_UNIT_TARGET_FLAG_MAGIC_IMMUNE_ENEMIES,
    bDeleteOnHit = false,
    bProvidesVision = false,
    ExtraData = {
        burning_great_arrow = 1,
        burning_wave_id = wave_id,
    },
})
```

参数依据：

- 速度 `1200`：现有 Wave of Terror 视觉 CP1 速度。
- 距离 `1200`：视觉根粒子约一秒生命周期乘速度，保持既定特效持续长度。
- 半径 `112`：可见核心粒子的 `m_flConstantRadius`。
- 方向清零 Z：按俯视平面发射，不让塔与目标高度差改变水平速度。

### 5.2 每支投射物独立状态

每次发射创建唯一 `wave_id`，状态至少保存：

```lua
active_waves[wave_id] = {
    tower = tower,
    tower_entindex = tower:entindex(),
    ability = ability,
    damage = authoritative_attack_damage * multiplier,
    hit = {},
    projectile_id = projectile_id,
    cleanup_task_id = cleanup_task_id,
}
```

禁止把伤害放到共享能力实例的单个字段中，否则同一塔连续攻击或多座塔同时发射时会互相覆盖。

### 5.3 共享被动能力回调分流

生产文件：

`d:\steam\steamapps\common\dota 2 beta\game\dota_addons\survival\scripts\vscripts\abilities\ability_tower_passive.lua`

多个塔技能共用同一个 Lua 类，因此回调不能无条件处理所有投射物。能力回调只负责转交：

```lua
function M:OnProjectileHit_ExtraData(target, location, extra_data)
    return tower_special_skill_system.on_burning_wave_projectile_hit(
        self, target, location, extra_data
    )
end
```

系统侧必须验证：

- `extra_data.burning_great_arrow == 1`；
- `burning_wave_id` 对应活动状态；
- 回调 ability 与状态中的 ability 相同；
- 塔和目标仍有效；
- 当前目标 entindex 尚未命中。

每次单位回调处理完成后始终 `return false`，继续穿透。

### 5.4 伤害链

权威基础伤害来自普通攻击落地事件已经计算好的 `payload.damage`，只乘技能配置 `damage_multiplier`，不重新读取塔面板攻击力，也不创建第二套暴击/增伤公式。

伤害路径：

```text
OnProjectileHit_ExtraData
-> TOWER_SKILL_DAMAGE_REQUEST
-> tower_skill_effect_adapter
-> damage_service
-> dota_damage_adapter
-> ApplyDamage(DAMAGE_TYPE_PHYSICAL)
```

`tower_skill_effect_adapter.lua` 必须继续传递 ability 句柄。所有目标获得相同基础伤害请求，Dota 再按每个目标自己的物理护甲分别结算最终扣血。

## 6. 生命周期规则

- 命中单位：只记录该单位 entindex，不删除投射物。
- 同单位重复回调：返回 `false`，但不再次提交伤害。
- `target == nil` 的终点回调：清理 `wave_id` 状态。
- 兜底清理：使用 `distance / speed + grace`，仅释放状态，不参与碰撞判断。
- 塔被摧毁：调用 `DestroyLinearProjectile(projectile_id)` 并清理该塔所有活动波。
- 系统重新初始化：销毁旧活动投射物，避免 Workshop Tools 热重载残留。

## 7. 正确测试模板

测试必须捕获 `CreateLinearProjectile(info)`，至少断言：

- `bDeleteOnHit == false`；
- `fStartRadius` 与 `fEndRadius` 正确；
- 距离、速度、目标队伍和单位类型正确；
- `ExtraData` 包含唯一投射物 ID。

然后使用同一份 `ExtraData` 顺序模拟：

```lua
ability:OnProjectileHit_ExtraData(first, first_pos, extra)
ability:OnProjectileHit_ExtraData(second, second_pos, extra)
ability:OnProjectileHit_ExtraData(third, third_pos, extra)
```

必须断言：

1. 三次回调全部返回 `false`。
2. 三个单位各产生一次伤害请求。
3. 三次请求基础伤害、伤害类型和能力归因一致。
4. 对第二个单位重复回调不会产生第四次伤害。
5. 主目标已被普通攻击击杀时，路径上的其他存活单位仍可命中。
6. 终点清理后旧 `ExtraData` 不再造成伤害。
7. 塔销毁后活动投射物被销毁，旧状态失效。

本项目测试文件：

`d:\steam\steamapps\common\dota 2 beta\game\dota_addons\survival\scripts\vscripts\tests\test_tower_wave_of_terror_visual.lua`

注意：当前 `.gitignore` 忽略 `scripts/vscripts/tests`，测试文件存在并会被本地 Lua 执行，但默认不会出现在 Git 变更列表。后续若需要将该测试纳入版本控制，应单独调整仓库测试目录策略，不要误判为测试未修改。

## 8. 验证结果

通过：

- `TOWER_WAVE_OF_TERROR_VISUAL_PASS`
- `TOWER_SKILL_GEOMETRY_PASS`
- `TOWER_MULTI_VISUAL_CONFIG_PASS`
- `SCHEDULER_RESTART_PASS`
- 相关 Lua 文件语法检查。
- Workshop Tools 用户实机验收：成功命中路径上的后续单位。

全量 Lua 循环中本功能测试通过；当时另有三项既有无关失败：英雄攻速投影、召唤英雄血条、树 LV1～LV30 配置。不得把这些失败归因于线性投射物修复。

## 9. 后续开发检查清单

开发任何“移动视觉覆盖一条路径并逐单位触发”的技能时：

1. 先读取原始 VPCF，区分视觉速度、寿命、半径与场景操作器。
2. 明确 VPCF 是否只是视觉；不要假设粒子场景碰撞能产生单位命中。
3. 优先使用引擎 `CreateLinearProjectile` 提供单位碰撞。
4. 穿透同时设置 `bDeleteOnHit=false` 和回调 `return false`。
5. 用唯一 projectile/wave ID 保存每发状态，不使用共享单字段。
6. 保存事件产生时的权威伤害快照，逐目标提交既有伤害服务。
7. 用 entindex 单波去重。
8. 时间任务只做清理，不做命中或固定提前补偿。
9. 测试必须模拟同一投射物的连续单位回调，而不是只 mock 一个多单位数组。
10. 自动测试后必须进行至少三个排成直线的单位实机验收。