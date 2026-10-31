# 侏儒传送器／英雄 D 权益与解耦审查

2026-10-31 开发修复；未自行签名、部署后台或发布游廊。商品是 `video_p026`，持有库存 `commerce_p026`；只需拥有，不要求装备。商城原介绍已冻结为指向可通行且已解锁位置、10秒冷却、失败不进入冷却，本轮没有改价格、奖励、限购、玩家数据或建造者移动规则。

## 原因与本轮边界

原商城 `commerce_runtime.action('blink')` 检查库存且单独记录10秒冷却；英雄 `hero_skill_system` 却无条件把 `ability_survival_hero_ball_lightning` 显示/激活，技能本体不检查库存、静态声明0秒冷却。这是两条入口各自掌握部分业务规则造成的语义耦合，不能用“商城有门禁”证明英雄D也受控。仅修改一次显示还会漏掉施法绕过、迟到档案和已在场英雄。

新增 `systems/hero_teleport_access.lua`：一处持有检查，一份按玩家索引、按世界/事件代际失效的10秒冷却。原生英雄D和商城入口都使用它；原生 `GetCooldown` 返回同一常量，并在真正落点成功后才提交共享冷却。失败返还已消耗魔法、清除本次启动的原生冷却，但保留先前仍有效的共享冷却。原生引擎已经启动相同冷却时，不重复写 `StartCooldown`。

英雄技能系统只负责生命周期和调用 `synchronize`；它收到真实档案变化时通过 `state_by_player[player_id]` 仅访问一个英雄的一个D技能，按实际值变化写等级/隐藏/激活。没有重建其他技能或遍历所有英雄。新订阅有独立token，重初始化时取消旧token；旧事件总线代际的token不能删除新局订阅。施法时再次验证当前英雄句柄、owner及实时match库存，旧英雄或旧账号回包不会获得能力。

`commerce_runtime` 保留原传输、目标位置验证及其他商品行为，仅共享该能力的权益和冷却，并对八字段动作快照做固定字段去重。稳定状态不重复跨NetTable写相同数据；无新轮询或定时器。

真实档案变化及成功传送的独立冷却事件立即更新动作快照，不必等待原1秒tick；同状态事件仍为0次NetTable写。客户端 `commerce_actions.js` 增加本人英雄entindex缓存（初始化读一个NetTable键，后续按该玩家提交事件更新）；仅选中本人英雄才接管D。否则让建造者或其他单位原有D处理器继续，修复原代码持有传送器后无条件吞掉所有选中单位D键的问题。缓存随HUD重建恢复，旧回调有active身份检查并Dispose退订；不扫描场景、选中集合或技能列表，不加后台选中轮询。

## 仍待产品确认的既有差异

原生D继续保持800距离、20魔法及球状闪电视觉；原商城快捷入口继续指向可行走且已解锁地图位置、不消耗魔法。商品介绍没有承诺这两个数值，本轮只按用户要求补持有门禁和已冻结10秒CD，未擅自统一范围/魔法消耗。该差异交由商品全面审计清单列出，需用户决定最终体验。

原模块 `commerce_runtime` 仍聚合轨道炮、铜斧、炸弹、研究、光环等多项商品，原1秒循环及空间敌人查询没有在本轮整体拆分；不能宣称一个权益模块已解决全项目解耦或帧率问题。中英技能说明的game/content三处镜像均只更新该技能一个键；重复本地化来源也是后续项目应改为单一权威生成的维护风险。

## 成本与证据

令P为本局玩家数（生产最多4），I为库存条目数，A为该英雄能力数。初始化沿用原英雄建栏成本O(A)，本轮额外只检查一个能力O(1)，冷却索引空间O(P)。稳定的权益/施法检查各O(1)，不依赖I、场景数或单位总数；库存读取走真实 `get_content_inventory_count`，不复制整份档案。原商城1秒tick仍是O(P)及它原有商品查询，本轮新增固定字段比较O(1)/玩家；无变化NetTable写入由原1次/玩家/tick降为0。档案变化只查该玩家一个技能O(1)，最常见所有权翻转为2个setter（隐藏/激活），同状态为0。施法边界一次HERO_SUMMON_GET索引请求、标量库存读和常数次引擎调用，失败/成功才触发相应原生动作。

真实Lua生产模块与真实profile服务的可复现测试：

```powershell
& 'C:/Program Files/lua/bin/lua5.1.exe' scripts/vscripts/tests/test_hero_teleport_entitlement.lua
& 'C:/Program Files/lua/bin/lua5.1.exe' scripts/vscripts/tests/test_hero_instant_blink.lua
& 'C:/Program Files/lua/bin/lua5.1.exe' scripts/vscripts/tests/test_commerce_runtime.lua
& 'C:/Program Files/lua/bin/lua5.1.exe' scripts/vscripts/tests/test_hero_skill_point_upgrade.lua
& 'C:/Program Files/lua/bin/lua5.1.exe' scripts/vscripts/tests/test_profile_commerce_reads.lua
node tools/test_commerce_actions_lifecycle.cjs
```

新专项覆盖免费英雄无持有、库存增量解锁/撤销、两入口交替共享CD、失败返魔法与不新增CD、建造者不误伤、保留旧英雄句柄/迟到移除、账号/会话变更与旧回包、纯净combat库存隔离、世界/事件代际重建。模拟引擎预先启动CD/扣魔法后运行真实OnSpellStart以验证回滚边界；这不等于已做原生施法实机验收。

可复现计数：1和10001条库存，各1000次拥有检查都是1000次标量读、0完整profile读；50次同状态档案事件0原生setter；10次稳定商城tick新增NetTable写入0。计数为受控Lua模拟，不是实际网络、引擎耗时或FPS；线上帧率交由主任务的真实游廊测试。

客户端回归还验证持有者选择建造者/其他玩家英雄时不发送商城传送、本人英雄替换/移除后索引立即更新、HUD重建恰好保留三份本模块订阅、旧回调不可写新UI，以及300秒稳定期0次头像单位查询/新增全表读取。单个D按键只做一次GetLocalPlayerPortraitUnit读取；初始化新增一个键读取和一份订阅，变化O(1)，空间O(1)。game/content该JS源字节一致，官方单文件编译通过（13861字节；SHA256 `8415bee0e577baa4df96212434647c7f9a430105f622ce633cfe107ad95cf85e`）。

旧技能与商城回归保留原断言，仅补真实服务当前需要的engine stub：能力GetLevel/IsHidden、FindAbilityByName、合成账号测试关闭四账号入场门禁，以及商城orbital的damage-service边界adapter。没有删除失败断言或改变生产入场/伤害逻辑。
