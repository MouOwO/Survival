# 光之守卫普攻光球半途消失（2026-11-08）

仅本地更新。已修正表现粒子的追踪加速度，配套源资源和两项官方编译完成；当前离线局缓存旧资源，新版原生画面、完整签包、联机和发行均未通过。本轮后台未部署、SDK上传0；正式游廊仍沿用0104 / manifest `7025356658517360342`，本轮没有刷新远端查询。

## 现场事实与原因边界

用户报告光之守卫普通攻击的弹道飞到一半消失。当前实际进程25700为Tools离线局，HTTP关闭，没有联网keeper。当前原生日志的HeroProjectile记录确认实体973是`npc_dota_hero_keeper_of_the_light`，配置和实际弹速均为3000，原生基础900、modifier加2100、没有setter回退。内部历史ID是`hero_shadow_fiend`，不是影魔。

本机官方pak01的原生粒子经resourceinfo实际读取：外层只挂载`keeper_base_attack.vpcf`；内层从零初速以常量9999吸向CP1，CP2限制最大速度，CP3驱动可见子粒子。小黑原生同类追踪使用1000000加速度。光法原有9个视觉子资源和全部依赖存在，未发现主光球普通飞行阶段的定时销毁；不能把尾迹0.2至0.3秒寿命误认成整个光球寿命。

800距离、实际速度3000的直线静止目标连续模型中，真实弹道用时约0.2667秒，旧视觉仅移动`0.5*9999*t²≈355.52`，与约半程的报告吻合。这是参数推导，不是帧截图测量；尚未用新资源实机A/B确认因果及命中表现，也没有声称本轮已证明伤害正常。

## 本地修复与核验

- 创建独立`particles/survival/heroes/keeper/`下的外层和运动层两项资源。外层仅重定向子资源，运动层仅将9999改为1000000；原生光球、颜色、九个视觉子项、命中endcap、CP1目标、CP2速度上限全部保留，不覆盖Valve原资源。
- 真实CSV、两份生成Lua、npc代理预载共五处引用改为新外层。弹速仍3000、射程仍800，攻击/伤害/技能逻辑Lua没有改动。
- `tools/build_keeper_attack_particles.cjs --build/--check/--verify`提供可重建来源与精确DATA比较。官方编译器对旧schema进行了三项明确迁移：sphere Transform、CP2.x类型输入、CP1 Transform含`PT_TYPE_CONTROL_POINT`；验证器只接受这些实际已核字段，未屏蔽整个operator。
- 两项官方resourcecompiler实际各`1 compiled, 0 failed`；`--verify`逐字段检查新编译DATA与原生期望一致。第一轮验证遗漏编译器明确输出的Transform类型，按实际字段补齐验证期望后通过，不改粒子取绿。
- content两源与game的art作者源逐字节一致；五处引用各唯一，原有83份未提交文件SHA完整保留。Git stash还原曾对两项原有untracked Python发生autocrlf转换，已从本次stash的原始blob按事前SHA恢复，两边pull完成，未使用历史stash。
- 既有`test_keeper_blinding_light.lua`通过，覆盖250范围/层数/到期/致死残留和特效失败隔离；真实生成配置Lua确认光法弹速和远程能力保持。`test_hero_summon_flow.lua:248`失败，用HEAD的两份原配置通过stdin预载重跑也同点失败、stdout一致，保留为既有失败，不把它写成通过。

诊断原生数据、原文件摘要及两项编译日志位于树外`D:/Survival_本地工具/runs/20261108_kotl_projectile/`。inspect01/02因resourceinfo的mod识别及中文绝对路径处理失败，inspect03以树外目录为cwd、ASCII相对文件名完成18个原生依赖读取；失败保留。永久builder直接使用官方VPK逻辑资源路径，不依赖这些诊断导出文件。

## 复杂度与成本

初始化仍使用既有CSV by_id索引及现有预载/召唤路径，替换两项图节点，没有增加图节点总数。稳定阶段新增Lua轮询、计时器、场景查询和网络请求均为0；每次普攻仍由原生完成相同固定规模粒子图，时间/空间O(1)每枚，活动总量随原有在途攻击数P为O(P)。只改常量，不引入逐帧Lua追踪。新表现层最多约0.003秒达到3000；这个估算及上述检查计数不是FPS或原生位移测量。

## 待发清单与阻断

本轮新增运行资源为两个`.vpcf_c`；替换运行资源为`hero_attack_projectiles.lua`、`asset_catalog.lua`及`npc_units_custom.txt`；运行删除0。两张CSV、两项content源、art源/manifest及builder是配套来源。没有改变0803冻结目录、authority、绑定或旧回执。

当前完整0803清单中的7050项资源、659项来源和7删除仍按其独立事实保留，不能把它称作含本轮修复的新包。下一完整候选必须对0104实际签名manifest重新收集双仓全部运行差异，吸收本轮两新增/三替换及历史未发布项，核对目录/编译/生产工具来源的新读集，不能只拼这五项或沿用旧延期清单。

使用既有发行Python环境重新执行`online_signed_entry.prepare()`，只读、未stage，实际16.318秒返回`dirty_or_unclassified_runtime_source`。离线Tools正在运行且已有编译缓存漂移，旧0803不含新粒子；不绕过门禁、不覆盖当前游戏、不伪造新的签名/准入。需用户正常结束当前离线局后，按摘要保存和核对编译漂移、完成新的不可变完整候选与源证明，再作新局近/中/远距离、移动目标/连续普攻/命中、正常退出恢复及必要多人验收，随后SDK上传和官方完整下载逐文件核验。后台本轮保持原状。
