# 五类挑战怪远程弹道｜2026-10-29

用户要求熔火核心概率掉落怪为远程300，火焰巨魔也用远程并放大火焰，冰烬挽歌用冰，合成宝石用星光，精华概率掉落怪用毒。本轮将五类统一为远程300、弹速1600；没有改血量/攻击/护甲/攻速、数量、掉落或模型。

| 怪物/成员 | 外观原型 | 弹道 |
| --- | --- | --- |
| 概率掉落熔火核心／challenge_07_molten_minion | challenge_07_ember_spirit | Lina原生火焰 |
| 火焰巨魔／challenge_08_boss | challenge_08_primal_beast_svarog | Lina火焰渲染半径×1.6的独立版本 |
| 冰烬挽歌／challenge_09_boss | challenge_09_spectre | Ancient Apparition原生冰弹 |
| 合成宝石／challenge_05_boss | challenge_05_beastmaster | Wisp原生星光能量弹 |
| 概率掉落精华／seven_sins_minion | challenge_10_terrorblade_fractal | Viper原生毒弹 |

主配置`data/csv/怪物与波次系统/monster_archetypes.csv`、生成Lua、五个named NPC的原生KV配套更新。新增可选列`native_attack_presentation_policy=ranged_v1`仅标记这五个原型；其他行为空。`challenge_monster_visual_service`在共享近战combat_archetype初始化之后，以已标记的远程外观配置设置真实射程和弹速，避免128射程覆盖。原有Morphling和其他近战、波次不启用此策略，保持原流程。

首次原生检查发现npc_dota_creature缺少Script_SetAttackRange/SetAttackRange及SetProjectileSpeed，单靠setter仍读到128；已沿用项目已验证的`modifier_survival_hero_attack_range`基础覆盖和`modifier_survival_hero_projectile_speed`差额加成，支持重复刷新不叠加弹速。相关modifier已在全局registry注册，未虚构新引擎API。

火焰巨魔放大版由`tools/build_challenge_projectiles.cjs`从本机官方pak读取完整Lina子粒子图，11份content源码和game编译资源；仅把13个renderer的半径乘1.6并重定向这组粒子引用，不改飞行控制点、生命周期或伤害。材料/贴图继续复用原生资源，没有复制大体积纹理。源码摘要按UTF-8/LF规范化，兼容content工作区的CRLF；遵守仓库.gitattributes。`tools/configure_challenge_projectiles.py`同步CSV、生成Lua与原生KV，两工具均支持只读`--check`。

验证通过：80次真实生产spawn闭包（五怪×四模式×setter有/无×两次出生），包括重复apply不叠加，实际数值与原profile一致；无setter和既有Morphling/近战隔离回归；开局预加载581项覆盖全部五个弹道；CSV结构及生成一致性检查；247条外观生成路径、873波次批次和231次城墙挑战既有回归通过。官方资源编译器11份均0 failed。

当前离线Tools原生临时实体验证五个均为ranged、Script_GetAttackRange=300、GetProjectileSpeed=1600，绑定正确弹道且ParticleManager成功创建；临时5实体及粒子均已清理，没有发攻击指令、发奖或改现有对局单位。未进行镜头下的最终视觉审阅、实际命中/伤害或多人验收；当前旧怪物没有热替换，重新开局加载新配置。此轮未上传游廊。

结构化结果：`validation/20261029/challenge_projectiles.json`；生成和来源摘要：`art/effects/challenge_projectiles/manifest.json`。本轮素材与源码在game/content两仓配套提交，其他会话正在修改的极寒地图路由、图标和本机运行文件保留。
