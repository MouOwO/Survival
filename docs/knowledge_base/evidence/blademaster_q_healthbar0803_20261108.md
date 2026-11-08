# 0803｜剑圣一转Q临时血条闪现（2026-11-08）

仅本地更新。两Lua修复、真实模块回归、完整收集、0803签包与独立全包核验均通过；新版本原生显示、多人、FPS与原游廊发布仍待。后台保持 `20261106-ws4-daily-refs-ed532ea60d2b`，正式条目 `3824360109` 仍为 `2026110104` / Steam manifest `7025356658517360342`。本轮没有自动购买、抽奖、后台部署或SDK上传。

## 根因与修复范围

用户报告剑圣一转后短暂出现血条再消失。一转解锁Q，正式Q使用透明非英雄 `npc_survival_blademaster_q_visual`；血条服务原排除表没有这个名字，npc_spawned可在调用方设置标记之前给它附加modifier_single_health_bar。该modifier的OnCreated立即发布一条alive=1、1HP、62px的自定义血条；Q专用NO_HEALTH_BAR状态仅抑制原生血条，不阻止自定义NetTable发布。调用方最后AddNoDraw之后，下一次原0.1秒采样才发布removed，所以出现瞬闪窗口。

真实生产模块配合仅引擎IO替身，模拟出生回调先到的顺序，复现旧源码1可见条/1附着/1采样器，随后removed。没有将此称作真实引擎出生时序或复制耗时测量；新包原生画面仍待验收。本地官方pak01单位KV已核实HealthBarOffset=-1是使用模型默认位置，不是隐藏开关，未加入猜测的KV字段。

- unit_health_bar_service的固定名字排除表增加Q载体，出生时不再附加自定义血条。
- modifier_single_health_bar在首次状态发布前按相同固定名字短路，防旧附着或误调用重新显示；复用原有的一次GetUnitName读取，不增加普通单位每次采样的原生查询。
- 不泛化排除所有visual标记，Q伤害、技能解锁、载体KV、对象池、W分身与E风暴行为不变；未更改客户端、价格、奖励或玩家数据。

新鲜Q出生只保留原公共exclude的removed清理，不发布可见条、不附加modifier、不启动其10Hz采样。防御性旧附着publisher连续100次采样加Destroy只发布1条removed。旧公共exclude组合RemoveModifier→OnDestroy后本来还会自己发一条removed，这是既有两墓碑边界，本轮未扩大修改通用清理，也不把publisher去重宣称为所有组合调用都只写一次。

## 成本与验证

| 路径 | 初始化/稳定/变化成本 | 调用计数与边界 |
| --- | --- | --- |
| 初始化 | 原3类单位一次O(N)扫描保持 | 不新增扫描、缓存或预热 |
| 每次出生 | 原直接名称查询及O(1)固定集合判断 | Q不再创建bar modifier/采样器；普通单位不增API |
| 普通血条10Hz采样 | 原O(1)状态与变化缓存保持 | 六类普通单位每100次仍100次名称读取、0重复网络写 |
| 已附着Q的防御路径 | 固定名字O(1)短路 | 原采样器未新增；不读生命/投影，不重复发布可见条 |
| 网络/调度 | 无新schema、周期任务或场景集合查询 | Q可见记录/附着/采样器由1/1/1变0/0/0；模拟计数不等于实机FPS |

树外 `D:/Survival_本地工具/runs/20261108_blademaster_healthbar/handoff01.json` SHA256 `04ea51eecd3b5ec2504932db4accb81dfb5444a8365755dc97e0f569af8cc231`；229项完整真实模块检查和两套既有visual_carrier/health_cleanup回归通过，旧源码使用同断言按预期失败。独立代理复跑6组验证通过。tests01 SHA256 `9f5004d534ec6c74737f9fcad3910f2d6dc32144c850120ab4d7f7e6db2ca477`。Root按原/新SHA严格导入后语法和差异检查通过。

## 来源与最小正确构建

改源前只读核实无Dota/keeper/launcher、无pending发行lease；正式精确5文件实际SHA与0104完全相同。旧0801的STAGING指向不存在的事务目录，不据此恢复任何包。源码、必要8项版本元数据已提交推送：game/runtime/operator `bf4c5bbf64706fdfef759fdc201c54ecde329982` / dev；content `c5baf452920276ff41051bbb8ede4970c62ff12d` / master未新增提交，实际上游一致。提交后的25项真实Git工具闭包全部通过，预提交一次闭包拒绝日志保留，不伪造通过。

两Lua不在catalog22的227源码读集或gen22编译的796内容/782 game作者读集。逐文件与工具/二进制核对完全相等，因此合法复用目录原producer `7f9efe9553db7853d4a26d8196df6ad87143b033` / content `385a2cd2b9fe42e60dc194233af22f2d30137f22`，及170项官方编译原producer game/operator `5159ba40dc1f31657f51a326d0dea47b506f2802` / content c5ba。不重标旧证明，不重复编译Panorama或目录生成，不降低永久门禁。

fresh production23真实执行36.614秒、exit0：853输入、186保护产物、7覆盖以及工具/二进制/Prometheus依赖、值、随机数和语法全部验证。两新Lua按原策略属于plain identity，production与新final来源单独绑定bf4c。导出的Git LF SHA：service `4d0f345db6c33ef668a35c42b3a51f6e87ca566a6e984af8faa2ea5092b4e5fe`，publisher `698acd915bde4c1f23d8e7bdad4b77923ec2247f81c14615ac12a63cf0b3bffe`。

完整full scope/exact和collector对实际0104覆盖659项来源，其中242历史待发，unknown/deferred为0；7050资源、3,811,256,517字节，140新增、441变化、7删除。与0802逐资源比较只有这两Lua变化，其余7048原字节完全相同；总-5字节来自旧父CRLF与本轮Git LF规范，不是遗漏。659来源/7删除全部保留，新控制显式分开旧catalog、旧compiler和新production。全阶段回执位于 `output/complete_delivery_release_20261108_v03`，collection handoff SHA256 `c9dcb0a63c556fcba5049f116ede50548bf3190e293206cc72d2e4fe0d7426c1`。

## 签包、入口与待交付

统一tools/release_pipeline.py的plan→prepare→build实际均exit0；签名前认证原0104父包后创建独立0803树外候选。报告 `output/complete_delivery_release_20261108_v03/package.json` SHA256 `fdc80a466ac746a02894a9946b43e03d95f166fb292302a2ec37a4577f6d7b34`，状态BUILT_SIGNED_COMPLETE_CANDIDATE_PENDING_NATIVE_ADMISSION。signed manifest `6321027b0f75f9bab25afd261d4ae7001ec7285965a5fa29f3d8ca20826adcee`，content `0a0c6d95116e3a2a61cc712fc56a9e8be74f33e4397cde7b93d16ff8cff993cf`。

独立全包审查实际34.496秒，5文件/4分卷精确、无旧包混入；7050资源全部CRC32/MD5/SHA256、170编译资源和本轮两Lua实际字节重核通过。回执 `D:/Survival_本地工具/runs/20261108_release_audit/0803/signed0803_full_audit02.json` SHA256 `e3a1487cf1e9417ea2b8e2fb6ce76b4c88bf56937c61b38d1f77944ab5448438`。审查器首轮漏改3个树外路径，读取控制时即失败、未验包；原失败保留，修正仅审查器后第二次通过，不认定成包失败或覆盖旧证据。

知识记录先提交，再切换固定0803联网绑定。同一CMD链实际PowerShell CheckOnly以 `D:/Survival_本地工具/runs/20261108_online0803/launcher_check01.receipt.json` 为准；不启动游戏、不安装、不消费。上一轮0802绑定与签包保留，正式0104未切换。

待发继续保留：新版原生Q连续普攻/暴击无临时自定义血条、正常目标血条及Q效果/伤害验收，以及完整累计原生/多人/FPS/演出准入；随后原游廊SDK成功回执及官方完整下载逐文件核验。缺新版原生准入，尚未上传，不能称为已同步游廊。原5项无关工作区文件原SHA完整保留：server/archive_backend/__pycache__/match_modes.cpython-314.pyc、server/bundles/current.json、tools/monster_portrait_release_20261030/finalize_package.py、同目录verify_download.py、tools/prepare_delivery_operator_20261103.py；content工作区干净。
