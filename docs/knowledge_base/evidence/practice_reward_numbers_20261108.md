# 练功房逐怪奖励改为怪物头顶飘字（2026-11-08）

仅本地更新，后台未改。本轮三项运行Lua源码已修改和回归；没有重签、安装或上传游廊，没有新增Panorama或自定义美术资源。当前实际进程8276为Tools离线局，不能把该旧局视为新版本验收。正式游廊状态沿用既有0104记录，本轮没有刷新SDK远端查询。

## 用户决定与行为

移除练功房每次成功击杀后的“获得奖励：击杀每个怪物获得……”通知。在死去的怪物上方显示本次实际发放数值：木材沿用伐木工砍树的绿色原生数字；金币使用原生金色数字。用户明确选择全属性分成力量红、敏捷绿、智力蓝三个数字，不使用一个紫色数字。三色RGB分别沿用英雄HUD的228/91/79、111/201/92、73/169/222。

当前真实效果表的普通属性奖励为每项+100，高阶为每项+1000；不能从历史profile ID里的10/100或旧文案推算。高阶额外1000金币效果enabled=false，不发放也不展示。继续按原奖励服务完成资源/成长结算、幂等标记和MONSTER_REWARD_GRANTED；转职和其他挑战完成通知保持。失败仍走既有错误通知，绝不飘成功数值；重复事务不重复结算或飘字。

## 实现与生命周期

`systems/monster_reward_service.lua`只在成功的practice_room/on_each_kill分支替换展示，传递已有victim和成功结算后的effects/resources，发奖逻辑保持。索引在init重建，避免每次死亡全扫奖励效果表并排序。展示在奖励回调之前执行，防回调提前移除尸体；可选特效异常用pcall隔离，不中断已经提交的发奖或后续事件。

新增`ui/monster_reward_numbers.lua`。木材直接调用既有core/particle_manager.show_green_number，金币使用OVERHEAD_ALERT_GOLD；都只发给奖励所属玩家。三色属性使用本机官方`particles/msg_fx/msg_heal.vpcf`：resourceinfo实读确认CP2.x控制寿命、CP2.y控制位数、CP3控制RGB。创建三个私有原生粒子，快照死亡坐标并按38世界单位分层，保留加号与完整位数；每个粒子设置完控制点立即ReleaseParticleIndex，由原生1.2秒寿命/衰减收尾，没有新Lua计时器。控制设置失败时Destroy+Release，玩家缺失不降级广播，实体已移除则跳过可选表现，不生成载体单位。

`addon_game_mode.lua`的既有precache阶段仅增加这个官方数字粒子的一次预载。未改伐木工、金矿客户端、货币值、全属性倍率、挑战资格或后台。实际原生三色位置/加号/消失/多人私有性仍待新局观察；本轮没有以参数检查或替身当作真实截图。

## 成本和可复现验证

真实配置为19个profile、66个effect、每组最多6项；四种练功房各1项有效effect。旧每次奖励选择为O(E+KlogK)并创建列表，新初始化一次O(E+ΣKlogK)、空间O(E)，之后按profile O(1)查找并仅处理本组K项。没有新的场景、单位或面板集合扫描。换局/init重建索引；没有旧异步回包、额外单位索引或永久粒子表需要清理。

无奖励时新增周期工作0。每次属性怪击杀固定三个数字：玩家查询1、死亡位置查询1、CreateParticleForPlayer3、SetParticleControl12、ReleaseParticleIndex3（另有原实体有效性判断），不增加CustomGameEvent或NetTable写入。木材与金币各复用一条原生头顶事件。原生引擎仍需绘制有限寿命数字，这些API计数不是FPS或网络字节测量。

树外唯一脚本：`D:/Survival_本地工具/runs/20261108_practice_reward_numbers/test_practice_reward_numbers.lua`，固定项目工作目录运行：

```powershell
& 'C:/Program Files/lua/bin/lua5.1.exe' 'D:/Survival_本地工具/runs/20261108_practice_reward_numbers/test_practice_reward_numbers.lua'
```

7083项真实模块断言通过，覆盖实际四profile/颜色/层次/数值、已停用金币、幂等、失败、缺玩家、移除实体、特效创建/控制失败释放、非练功房通知和换局重建。连续1000次属性奖励实际记录player1000/origin1000/create3000/control12000/release3000；在初始化后给全局effects尾部放置访问即报错的哨兵仍通过，证明没有稳定期全表遍历。以HEAD修改前奖励服务运行同一脚本，按预期在“木材结算与原树木飘字”断言失败，负对照日志保留。三项Lua通过Lua5.1语法检查。

## 交付与保留项

本轮运行待发：新增`ui/monster_reward_numbers.lua`；替换`systems/monster_reward_service.lua`和`addon_game_mode.lua`，删除0。全部为Lua，没有新的content作者源或编译资源，因此content不创建空提交。待完整候选重新对实际已发布签名manifest收集：本轮三Lua、光法弹道、原生错误tip及全部历史未发/素材/删除项均不能遗漏。当前0803签包不含这些后续修改，不能冒用旧绑定启动或发布。

当前离线Tools仍在运行，其他工作同时修改金矿研究、生产UI和知识条目；本轮不暂存或覆盖它们，不弹出其他任务的stash，不将暂存了原有改动的历史对象当作本轮stash。game在工作区干净窗口已pull确认最新；content本轮只读核对其master/上游及其他任务改动。源码提交/推送不等于普通签包、新版原生画面或已同步游廊。还需当前局正常结束后的来源/缓存核对、新不可变完整候选、对应原生/多人验收、SDK成功回执及官方完整下载逐文件核验。
