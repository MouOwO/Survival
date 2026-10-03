# 抽奖界面质感、字体、品质与 SSR 保底（2026-09-29）

本次按参考图重绘单抽、十连、返回、再次开启的象牙白/金色牌匾。云纹、细边框使用已检查的透明 PNG，避免游戏对 SVG 线条继承的解析差异。按钮维持原操作范围、抽奖券图标及扣券逻辑。

抽奖正文改为清晰无衬线字，标题保留衬线风格；收紧文字阴影。结果名称去掉旧浅色底板，改深色渐隐底；N/R/SR/SSR/UR 使用深色独立品质牌和亮色粗体字，分别为浅绿白、蓝、紫、金、粉紫。结果仍为五列两行。

存档积分道具的品质来自服务端 quality 字段，显示在每个图标右下角，随图标一起滚动。正式图标适配器和回退图标路径均支持，主题更新和未解锁置灰不会覆盖品质色。

## 真实抽奖规则

- 地图、修仙宝箱：普通抽奖券，十连保底 SSR。自然抽到 UR 也满足保底，不降级。
- 龙脊尖兵、暑期宝箱：金色抽奖券，十连保底 UR。
- 单抽不触发十连保底；修仙宝箱仍需地图宝箱累计 100 次开启。
- 自然概率、库存、价格、道具属性均未更改。
- 后台和本地包已同步：35ed1ff77970e9ade51a8f28ce0463f821a47d5521a9cb0b7229e8f939dd5945

## 验证与范围

- 8 项服务器抽奖测试通过，包括强制自然抽取全部为 N 时，每个奖池一次十连第十件准确补为 SSR/UR；单抽不触发。测试使用隔离内存数据库，未消费玩家余额。
- archive_rarity.test.cjs 通过：生产图标适配器中所有五个品质都显示，并通过锁定卡片主题刷新。
- lottery_ticket_rules.test.cjs、lottery_cinematic_flow.test.cjs、test_lottery_updates.cjs、test_archive_cache.cjs 通过。
- 10 项资源源文件与 content 镜像一致，CSS、JS、XML、按钮纹理编译完成。
- 现有 test_archive_compact.cjs 包含过期 mock：缺少实际接口 CardProgress，后续还有已移除 cardTextRect 的断言。未修改运行时代码去迎合旧测试；本次品质角标已用正式适配器单独测试。
- 游戏未运行，尚未实机验收字体与质感；重新进入测试对局加载。

[按钮素材预览](../output/lottery_polish_20260929/button_preview.png)（素材合成预览，并非游戏截图）

## 道具品质清单

共 101 项（抽奖道具 89、每日积分道具 12）；按原始配置记录，未凭图标外观推测品质。

N 11, R 13, SR 5, SSR 33, UR 39。

| 道具 | 品质 | ID |
|---|---|---|
| 属性结晶 | N | lottery_attribute_crystal |
| 炮击结晶 | N | lottery_bombardment_crystal |
| 膨胀结晶 | N | lottery_expansion_crystal |
| 伐木结晶 | N | lottery_lumber_crystal |
| 自然结晶 | N | lottery_nature_crystal |
| 防护结晶 | N | lottery_protection_crystal |
| 回复结晶 | N | lottery_recovery_crystal |
| 回复精神 | N | lottery_recovery_spirit |
| 抵抗结晶 | N | lottery_resistance_crystal |
| 射击结晶 | N | lottery_shooting_crystal |
| 财富结晶 | N | lottery_wealth_crystal |
| 攻击碎片 | R | daily_attack_shard |
| 攻击宝石 | R | daily_attribute_gem |
| 属性碎片 | R | daily_attribute_shard |
| 格挡碎片 | R | daily_block_shard |
| 金币宝石 | R | daily_gold_gem |
| 成长宝石 | R | daily_growth_gem |
| 生命宝石 | R | daily_health_gem |
| 回血碎片 | R | daily_regen_shard |
| 木材宝石 | R | daily_wood_gem |
| 神赐精神 | R | lottery_divine_spirit |
| 生命精神 | R | lottery_life_spirit |
| 自然精神 | R | lottery_nature_spirit |
| 锋锐精神 | R | lottery_sharp_spirit |
| 疾风弓 | SR | lottery_gale_bow |
| 速干水泥 | SR | lottery_quick_dry_cement |
| 快速纹章 | SR | lottery_swift_emblem |
| 万能工具 | SR | lottery_universal_tool |
| 风速弓弦 | SR | lottery_windspeed_bowstring |
| 古树眷顾 | SSR | daily_ancient_tree |
| 森罗本源 | SSR | daily_forest_origin |
| 聚财古符 | SSR | daily_wealth_talisman |
| 亚伦巨炮 | SSR | lottery_aaron_cannon |
| 苍松固城 | SSR | lottery_ancient_pine_fortification |
| 晶态护甲 | SSR | lottery_crystalline_armor |
| 义体插件 | SSR | lottery_cybernetic_implant |
| 玄铁城墙 | SSR | lottery_darksteel_wall |
| 数据单元 | SSR | lottery_data_unit |
| 翠木归元 | SSR | lottery_emerald_wood_origin |
| 林铸千矢 | SSR | lottery_forestcast_thousand_bolts |
| 采集神典 | SSR | lottery_gathering_divine_codex |
| 采集秘典 | SSR | lottery_gathering_grimoire |
| 青林涅槃 | SSR | lottery_greenwood_nirvana |
| 青林筑垣 | SSR | lottery_greenwood_rampart |
| 英雄勋章 | SSR | lottery_hero_medal |
| 角鹰魔攻 | SSR | lottery_hippogryph_onslaught |
| 伐木高手 | SSR | lottery_lumber_expert |
| 伐木传承 | SSR | lottery_lumber_legacy |
| 磁扰炮台 | SSR | lottery_magnetic_disruption_turret |
| 氮化合金护墙 | SSR | lottery_nitride_alloy_wall |
| 橡木壁垒 | SSR | lottery_oak_bulwark |
| 脉冲传导炮台 | SSR | lottery_pulse_conduction_turret |
| 裂痕插件 | SSR | lottery_rift_implant |
| 万木之种 | SSR | lottery_seed_of_all_wood |
| 锐木塔源 | SSR | lottery_sharpwood_tower_core |
| 信号枢纽 | SSR | lottery_signal_hub |
| 噬魂灵剑 | SSR | lottery_soul_devouring_blade |
| 钢铁城墙 | SSR | lottery_steel_wall |
| 泰坦巨盾 | SSR | lottery_titan_shield |
| 箭塔改造 | SSR | lottery_tower_retrofit |
| 研木宗师 | SSR | lottery_woodcraft_grandmaster |
| 木筑万锋 | SSR | lottery_woodforged_thousand_arrows |
| 丰饶赐福 | UR | lottery_abundance_blessing |
| 烛龙之翼 | UR | lottery_candle_dragon_wing |
| 主神赐福 | UR | lottery_chief_god_blessing |
| 神选英雄 | UR | lottery_chosen_hero |
| 赛博主宰 | UR | lottery_cyber_overlord |
| 次元屏障 | UR | lottery_dimensional_barrier |
| 神塔赐福 | UR | lottery_divine_tower_blessing |
| 龙骑尖兵1型 | UR | lottery_dragon_knight_vanguard_mk1 |
| 薪火余烬 | UR | lottery_ember_of_legacy |
| 无尽年轮 | UR | lottery_endless_growth_ring |
| 堕落天矿 | UR | lottery_fallen_sky_mine |
| 烈焰城墙 | UR | lottery_flame_wall |
| 焚林之锋 | UR | lottery_forest_burning_edge |
| 万噬通天丹 | UR | lottery_heaven_devouring_pill |
| 通天塔印 | UR | lottery_heaven_reaching_tower_seal |
| 天道傀儡 | UR | lottery_heavenly_puppet |
| 不灭涅槃 | UR | lottery_immortal_nirvana |
| 诛仙剑阵 | UR | lottery_immortal_slaying_sword_array |
| 封神榜 | UR | lottery_investiture_of_gods |
| 玉清剑仙 | UR | lottery_jade_purity_sword_immortal |
| 伐木之怒 | UR | lottery_lumber_fury |
| 伐木仙人 | UR | lottery_lumber_immortal |
| 魔法少女（剑圣） | UR | lottery_magical_girl_juggernaut |
| 齐天大圣 | UR | lottery_monkey_king |
| 山海鲲鹏 | UR | lottery_mountain_sea_kunpeng |
| 纳米集群 | UR | lottery_nano_cluster |
| 神经重构模块 | UR | lottery_neural_reconstruction_module |
| 全知赐福 | UR | lottery_omniscience_blessing |
| 轨道炮核心 | UR | lottery_orbital_cannon_core |
| 轮回仙碑 | UR | lottery_reincarnation_immortal_stele |
| 轮回宝珠 | UR | lottery_reincarnation_orb |
| 焕天印 | UR | lottery_sky_turning_seal |
| 锁魂匣 | UR | lottery_soul_lock_box |
| 君临天下 | UR | lottery_sovereign_under_heaven |
| 奋斗日记 | UR | lottery_struggle_diary |
| 极品钓鱼杆 | UR | lottery_supreme_fishing_rod |
| 时间宝珠 | UR | lottery_time_orb |
| 不破要塞 | UR | lottery_unbreakable_fortress |
| 虚空信号终端 | UR | lottery_void_signal_terminal |
