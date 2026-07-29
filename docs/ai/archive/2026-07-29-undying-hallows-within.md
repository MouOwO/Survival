# Current Task

## 2026-07-29 当前活跃任务：开局 Undying 建造者使用 The Hallows Within

### 用户需求

- 只替换玩家开局的 `npc_dota_hero_undying` 建造者外观。
- 使用 Undying Immortal 捆绑包 `The Hallows Within Bundle`。
- 本轮实现角色本体模型、环境特效和能够安全恢复的轻微姿势/动画调整。
- 墓碑、墓碑粒子和专属僵尸只调查并记录资源，不接入运行时。
- 不影响修理工、波次怪、普通僵尸、Boss 或祭坛召唤英雄。

### 已确认物品定义

- Bundle：`The Hallows Within Bundle`，defindex `21800`。
- 英雄饰品：`The Hallows Within`，defindex `14963`，`Head` 槽。
- 墓碑饰品：`The Hallows Within Tombstone`，defindex `14994`，`Tombstone` 槽。
- 该 Bundle 不是常规多身体槽套装；英雄外观主要由一个大型 Head wearable 提供。

### 当前代码事实

- `addon_game_mode.lua` 强制开局英雄为 `npc_dota_hero_undying`，并在 `initialize_survival_hero()` 中清除原版技能后发布 `HERO_READY`。
- `hero_cosmetic_service.lua` 已支持隐藏默认 wearable、创建 `prop_dynamic`、设置 Owner、`FollowEntity` 和模型预缓存。
- 祭坛英雄继续调用该服务；开局建造者现已在 `HERO_READY` 前应用独立 `builder_undying` 配置。
- 服务现已支持命名组件、重复应用清理、粒子预缓存/创建/释放和独立定向测试。

### 实施范围

1. 从本机 Dota VPK/物品定义定位 defindex `14963` 的模型、环境粒子、attachment 和动画资源。
2. 记录 defindex `14994` 的墓碑/僵尸资产，但不运行。
3. 在 `hero_cosmetics_config.lua` 增加独立 `builder_undying` 配置。
4. 增强 `hero_cosmetic_service.lua` 的命名组件、重复应用清理、粒子预缓存/创建/释放和失败关闭。
5. 在开局 Undying 初始化且发布 `HERO_READY` 前应用 `builder_undying`。
6. 新增定向测试并运行全部 Lua 回归、语法与限定差异检查。

### 安全边界

- 不改变建造者技能、属性、Owner、控制权、碰撞体、出生点或显示名。
- 动画 modifier 无法安全恢复时保留原版 Undying 动画，不替换主体骨骼模型。
- 不把本配置按单位名自动应用给任何普通 Undying 怪物。
- 不清理、不回退、不提交工作区其他既有修改。

### 当前阶段

**用户实机确认部件饰品上线成功；角色 wearable 主目标验收完成。**

### 实施结果

- 英雄模型：`models/items/undying/undying_fall20_immortal_head/undying_fall20_immortal_head.vmdl`。
- 英雄环境粒子：`particles/econ/items/undying/fall20_undying_head/fall20_undying_head_ambient.vpcf`。
- 粒子绑定到命名的 `hallows_head` wearable；重复应用会先销毁旧粒子、释放索引并删除旧 wearable。
- `npc_spawned` 只对已经完成初始化的同一开局建造者 entindex 重建外观，覆盖死亡/重生且不命中普通 Undying 怪物。
- 墓碑模型、专属僵尸模型和墓碑环境粒子仅在配置注释与取证记录中保存，没有进入运行时配置。
- 官方资料只说明存在轻微姿势调整，未找到可安全调用的独立 Lua 动画 modifier；实现保留原版 Undying 动画和 wearable 自身骨骼跟随，不强行替换主体模型。
- 已新增 `test_hero_cosmetic_service.lua`，覆盖预缓存、默认 wearable 隐藏、Owner/FollowEntity、命名粒子绑定、重复应用清理和显式清理。
- `.cline_tmp/test_hallows_within_contract.ps1` 返回 `HALLOWS_WITHIN_CONTRACT_PASS`，并验证模型/粒子真实存在于本机 VPK、开局接入限定和 `HERO_READY` 顺序。
- 目标 `git diff --check` 返回 `TARGET_DIFF_CHECK_PASS`。
- 当前 Shell 没有 `lua`、`luac` 或 `luajit`，WSL 探测超时，因此未把 Lua 测试/语法执行伪记为通过；当前仓库快照可见测试也只有原有 `test_hero_health_guard.lua` 与本轮新增测试。
- 用户实机结论：`The Hallows Within` 部件饰品已在开局 Undying 建造者上成功显示，证明模型资源路径、`prop_dynamic` 创建、Owner、`FollowEntity` 骨骼跟随和开局应用时机均有效。
- 未扩大实机结论：用户本次没有分别确认环境粒子、死亡/重生和第二次 Run，因此这些生命周期细节仍保留为后续防回归检查项。

### 下一步唯一动作

- 本任务归档；后续若继续扩展饰品，复用本轮已验证的 VPK 取证、命名 wearable、粒子 owner 和严格单位身份守卫方案。