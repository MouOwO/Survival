# Current Task

## 活跃任务（2026-08-06）：多人联机系统

### 用户确认的玩法

- 目标支持最多4名玩家；第一轮先做2人纵向切片，再扩展到4人。
- 所有玩家属于好人方，但每名玩家拥有独立的经济、人口、建筑、Builder、英雄、科技、成长状态和一套波次怪物。
- 战场空间共享，玩家初始区域按东南西北等固定槽位配置；区域只决定出生位置，不决定业务归属。
- 玩家可以把自己的城墙建到其他玩家区域，与其他城墙集中防守。这是允许的玩家策略，不应被区域限制阻止。
- 每批怪物绑定其所属玩家，并始终攻击该玩家自己的城墙实体；不得按最近城墙、固定区域或最后创建的城墙选目标。
- 英雄允许跨区域支援其他玩家并攻击其他玩家所属的波次怪。
- 玩家不能控制他人的英雄、Builder、工人、建筑、防御塔、召唤物或其他可控单位。
- 所有客户端只提交操作意图；资源、建造、波次、伤害、奖励和胜负由服务端权威结算。Dota 2引擎负责同步实体、位置、生命、Modifier、攻击和投射物，不另做客户端独立模拟或lockstep。

### 核心身份边界

- `player_id`：资源、建筑、单位、怪物、挑战和奖励的业务归属权威。
- `slot_id/lane_id`：玩家初始出生点和波次出生点，只表示地图槽位。
- `team`：仅表示Dota敌我阵营；不能继续作为玩家经济、建筑上限、Builder阶段或波次状态的唯一键。
- 单位归属和单位当前位置必须分离。移动到别人区域不会改变owner。
- 客户端payload中的`player_id`不可信；Custom Game Event必须从事件来源获得真实玩家身份，并校验caster、ability、target和业务状态归属。

## 多人联机任务清单

### 阶段1：多人配置、玩家上下文与身份基础（进行中）

#### 生产改造

- [x] 新增CSV权威多人规则，配置最大玩家数、初始实现人数、共享波次时钟、英雄跨区支援等长期规则。
- [x] 新增CSV权威玩家槽位，配置`player_id`、`slot_id`、Builder出生marker、波次出生marker、旧地图回退和启用状态。
- [x] 生成对应Lua配置，禁止直接手改生成文件。
- [x] 新增`player_context_service`，统一提供玩家槽位、marker解析、单位owner登记、owner查询和ownership校验。
- [x] `addoninfo.txt`和启动规则改为最多4名好人方玩家；保持坏人方玩家数为0。
- [x] Builder创建改为按玩家槽位解析出生点，并继续设置`SetPlayerID`、`SetOwner`、`SetControllableByPlayer`和`survival_player_id`。
- [x] 玩家0允许旧地图坐标兼容回退；玩家1至3缺少marker时必须失败关闭并输出明确日志，禁止全部叠在`(0,0)`。
- [x] 保持单人旧地图可启动，阶段1不宣称独立经济、独立波次或完整联机已完成。

#### 自动验证

- [x] PowerShell契约：CSV、生成Lua、最大玩家数、服务初始化和Builder接入一致。
- [x] Lua 5.1行为：4个槽位、marker优先、玩家0旧回退、非0玩家缺marker失败、owner登记和跨玩家拒绝。
- [x] `luac5.1`语法检查。
- [x] CSV与生成Lua逐字节一致性。
- [x] 严格UTF-8和限定`git diff --check`。

#### Workshop Tools验收

- [ ] 单人冷启动保持正常，玩家0 Builder仍能生成和建造。
- [ ] 地图加入玩家1 marker后，两客户端分别生成在自己的槽位。
- [ ] 日志能看到每名玩家的`player_id/slot_id/builder_spawn_marker/entindex`。

### 阶段2：两人纵向切片

- [ ] Hammer地图增加至少2套Builder出生marker和波次出生marker；最终预留4套。
- [ ] 两名玩家分别生成占位英雄、Builder和初始UI。
- [ ] 两人可同时建墙、主城和箭塔，状态不互相覆盖。
- [ ] 两人无法通过鼠标、快捷键、框选或原生命令控制对方单位。
- [ ] 双方资源显示与服务端状态一致。
- [ ] 完成两客户端Workshop Tools实机验收后再进入全面状态迁移。

### 阶段3：统一服务端命令权限

- [ ] 将现有树木攻击Order Filter迁入唯一组合`ExecuteOrderFilter`，避免多个模块互相覆盖。
- [ ] 对移动、攻击、停止、巡逻、施法、拾取、丢弃和多单位命令检查全部命令单位的owner。
- [ ] 审计全部Custom Game Event入口，统一从事件来源取得PlayerID。
- [ ] 校验客户端传入的entindex、ability、target、位置、session和请求顺序。
- [ ] 增加伪造他人单位、混合编队、迟到请求和重复请求测试。

### 阶段4：个人经济、建筑与成长状态

- [ ] 资源账户从`accounts[team]`迁为`accounts[player_id]`：金币、木材、人口和人口上限全部独立。
- [ ] Builder阶段从`state_by_team`迁为`state_by_player`。
- [ ] 建筑数量、城墙一次性状态、主城等级和建筑上限按玩家计算。
- [ ] 工人训练、金矿、科技等级和研究事务按玩家隔离。
- [ ] 塔升级、转职、科技加成和七塔融合只消费同一玩家的塔。
- [ ] 回城查找玩家自己的主城，不再使用`main_city_for_team()`。
- [ ] UI快照和NetTable key按玩家投影；客户端资源快照仍无服务端否决权。

### 阶段5：每玩家独立波次实例

- [ ] 全局单例`wave_system`拆为`state_by_player/enemies_by_player/wall_by_player/spawn_marker_by_player/generation_token_by_player`。
- [ ] 每名活跃玩家每波生成独立的一份怪物。
- [ ] 第一版使用全局统一难度和统一波次开始时钟，个人保存计划数、已生成、存活、击杀和失败状态。
- [ ] 每只怪保存`survival_wave_player_id`、波次号和目标城墙身份。
- [ ] 怪物只追踪所属玩家的城墙实体；城墙建在其他区域或与他人城墙重叠时仍保持正确目标。
- [ ] 城墙销毁、重建、移动和实体失效时更新该玩家怪物目标，不影响其他玩家。
- [ ] 波次UI展示本地玩家状态，并可按需求展示队友概要。

### 阶段6：失败、胜利、支援和奖励归属

- [ ] 某玩家城墙死亡后只淘汰该玩家、停止其后续波次并清理其波次怪；其他玩家继续。
- [ ] 所有玩家淘汰时失败；所有仍活跃玩家完成最终波次时胜利。
- [ ] 英雄可自由跨区域支援，不改变单位owner。
- [ ] 基础波次经济建议归怪物所属玩家，避免支援抢最后一击破坏其经济。
- [ ] 击杀成长、装备触发和支援奖励另行明确，必须通过CSV配置后实施。

### 阶段7：挑战、商店、装备与UI多人回归

- [ ] 审计转生、十戒、练功房、特殊挑战和同一挑战并发规则。
- [ ] 审计地面掉落、Claim、背包、装备实例、合成和成长归属。
- [ ] 审计英雄召唤、技能选择、商店购买、科技、通知、Tooltip和自定义NetTable。
- [ ] 同一`encounter_id`如允许多人同时开启，运行身份必须包含player/session，不能继续全局唯一覆盖。
- [ ] Custom Net Tables只用于客户端可读UI快照，不存放需要保密的数据或高频操作日志。

### 阶段8：四人、掉线重连、性能和最终回归

- [ ] 从2人扩展到4人并完成东南西北槽位。
- [ ] 玩家加载速度不同、掉线、重连和永久退出均有明确生命周期。
- [ ] 重连恢复自己的Builder、英雄、建筑、资源、波次和UI。
- [ ] 多人同帧建造、扣费、研究、挑战和奖励事务保持原子与幂等。
- [ ] 检查4份波次实体量、投射物、Modifier、NetTable和Panorama性能。
- [ ] 完成两台或多台真实客户端实机验收；Mock和单机多实例不能替代最终网络验收。

## 编辑器联机验收方案

- 不需要先发布Workshop。开发地图可以在Workshop Tools中由主机启动本地服务器/大厅，其他Steam客户端加入。
- 推荐使用两台电脑、两个Steam账号、同一局域网；两台机器都安装相同Dota 2 Workshop Tools和完全一致的addon内容/编译产物。
- 主机通过Workshop Tools启动addon和`template_map`；客户端使用Steam好友加入、开发大厅或控制台`connect <主机局域网IP>:27015`，具体可用入口以当前Dota版本实测为准。
- 主机防火墙需允许`dota2.exe`，必要时开放UDP/TCP 27015；不得把能进入地图误认为业务联机验收通过。
- 一台电脑多客户端只适合辅助检查，需要多Steam实例/账号且性能与输入焦点限制明显；最终验收仍建议两台电脑。
- 每轮联机测试必须确认两端使用相同文件版本，并分别保存服务端控制台日志和客户端截图/录像。

## 当前检查点

- 当前阶段：阶段1生产实现与自动验证完成，等待Workshop Tools单人冷启动验收。
- 当前地图源存在`template_map.vmap`和`survival_dev.vmap`，运行产物为`maps/template_map.vpk`。
- 已确认旧地图只有单个历史波次marker `monsterborn`；尚未确认4套玩家marker。
- 当前启动规则和`addoninfo.txt`已开放4名好人方玩家；后续玩家由`player_connect_full`分配到好人方。
- 旧`CURRENT_TASK.md`和旧`START_HERE.md`已完整归档到`docs/ai/archive/2026-08-06-pre-multiplayer-*.md`；旧任务全部暂停，不得自动恢复。
- 工作区已有大量未跟踪测试文件，属于用户既有内容，本任务不得覆盖、清理或纳入交付。

## 下一步唯一动作

用户在Workshop Tools冷启动`template_map`做阶段1单人兼容验收：确认玩家0 Builder正常生成、可选择并可建造，日志包含`[MULTIPLAYER_CONTEXT]`与`[BUILDER_READY] player=0 slot=east ... source=legacy_coordinates`。通过后进入Hammer双槽位和两客户端联机测试。
## 阶段1自动验证记录（2026-08-06）

- `MULTIPLAYER_CONTEXT_CONTRACT_PASS`：CSV、生成Lua、服务接入和4人启动契约通过。
- `MULTIPLAYER_CONTEXT_LUA51_PASS`：4槽位、marker优先、玩家0旧回退、非0缺marker失败、owner冲突和跨玩家拒绝通过。
- `MULTIPLAYER_BUILDER_INTEGRATION_LUA51_PASS`：玩家0 Builder旧地图生成、CSV移速保持、owner登记和玩家1缺marker拒绝通过。
- `MULTIPLAYER_LUAC51_PASS`：本轮Lua生产文件、生成文件和专项测试语法通过。
- `MULTIPLAYER_GENERATED_CONFIG_MATCH_PASS`：两份CSV临时重生成结果与提交生成Lua逐字节一致。
- `MULTIPLAYER_STRICT_UTF8_PASS`和限定`git diff --check`通过。
- 未跟踪既有`test_builder_ownership.lua`失败于硬编码期望Builder移速600，而当前权威CSV和生成Lua均为300；本轮未修改移动速度逻辑。
- 未跟踪既有`test_builder_utility_contract.ps1`失败于`MONKEY_CSV_RANGE_1000_MISSING`；与本轮多人身份改造无关，未修改该测试或Monkey配置。
- 尚未执行Workshop Tools实机验证，不能称为联机或单人实机验收通过。