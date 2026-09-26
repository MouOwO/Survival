## 当前实施（2026-09-26）：局内图标统一润色

完成116张新图标：其余建筑、工人训练、升级箭头、英雄/防御塔技能、天赋、商店物品和局内导航。沿用用户认可的暗青背景、立体材质与柔和光影；256×256源图，80px/40px预览检查。52张天赋/宝物卡片复用对应语义图标。技能栏、训练/研究队列、Tooltip、商店与背包引用同步；47个原生物品壳保持原ID和路径。大小升级箭头保持明显差别。

明确排除存档、抽奖（含顶部入口、数据、资源）；1725个相关源文件及共用Tooltip表中90条相关记录校验未变。上一批22张满意图标、30张原生头像和超级知识之书共53张保护资源校验未变；加速手套包含于上一批22张。普通挑战继续使用已认可的对应怪物头像。未使用本轮范围确认前试制的存档/抽奖素材。

通过内置 image_gen 为每张图分别生成；不是实际游戏模型渲染。最终源图在 `panorama/src/images/spellicons/survival/native/`，背包兼容图在 `panorama/src/images/items/survival_shop_v2/` 和 `survival_unified/`。全部同步到content并编译：249张资源+依赖布局共250项、HUD13项，0失败。7项Node回归、1项Lua天赋状态回归、12份Lua5.1语法、6份JS语法及CSV逐列检查通过。KV仅更改贴图名，CSV仅更改图标列。补齐Lua Tooltip和可见状态图标的旧素材引用。

预览：`output/icon_unify_20260926/preview.html`（含80px和40px）及 `preview.jpg`；提示词：`docs/ai/validation/20260926/icon_unify_prompts.json`；验证：`docs/ai/validation/20260926/icon_unify.json`。备份与母图：`output/icon_unify_20260926/before/`、`masters/`。尚未进行Workshop新局实机验收，请重开对局检查显示与缓存。

## 2026-09-26 视觉追改（当前版本）

按用户反馈重做22张256×256图标：普通/高级研究所、农场、金矿4张建筑；伐木、金币、人口5张；普通/高级研究物品13张。使用内置image_gen，暗青背景、雕塑式体积、木纹/金属/皮革/宝石材质和柔和光影。保留技能含义，未修改建筑实际模型。建筑图像引用因本机fshelper异常无法直接交给生成工具读取，改按已检查的建筑造型描述重绘；这些是2D图标重绘，不是实际模型截图。目标文件在 `panorama/src/images/spellicons/survival/native/`；完整提示词与文件索引见 `docs/ai/validation/20260926/icon_polish_prompts.json`。

普通挑战11入口改为实际遭遇怪物的原生头像，新增8张纹理：木材=尸王，金币=斧王，属性=克林克兹，大属性/合成宝石=兽王，冰霜=水人，熔火1–3=灰烬之灵，熔火4=兽，冰烬=幽鬼，七宗罪=恐怖利刃，罪渊=首层瘟疫法师。罪渊入口是固定首层代表，不动态随层数更换。映射沿挑战CSV→遭遇成员→怪物原型/资源配置核对；挑战CSV只改icon_name并重新生成Lua。原挑战建筑五张头像保留。

复用现有图标路径，因此技能栏、研究队列和引用相同素材的商店入口自动同步。技能按钮和UI布局没有改动。附带纠正上轮普通/高级研究所本地化文本的PowerShell管道编码损失；四个中文键现为正确UTF-8。

预览：`output/icon_polish_20260926/preview.png`（资源图，非游戏截图）。22张生成母图、旧版备份、挑战映射证据位于同目录。114张图标资产及依赖共115项、HUD15项编译0失败；Node映射/旧库存图标回归、CSV字段范围、Lua5.1语法、源文件同步和48px浏览器预览检查通过。记录见 `docs/ai/validation/20260926/icon_polish.json`。尚未完成Workshop新局实机验收。

以下为前一轮实现记录，资源数量与材质来源以本节为准。

# 原生图标与天赋入口（2026-09-26）

状态：代码、资源同步和离线验证完成；尚未进行 Workshop Tools 新局实机验收。

| 项目 | 本次结果 |
| --- | --- |
| 人口训练 | 与资源栏一致的鸡腿图标 |
| 建造师建筑入口 | 9 种建筑使用对应模型缩略图；自定义建筑复用工程模型预览，箭塔取实际模型渲染 |
| 主城工人入口 | 修理工、高级修理工和伐木工 LV1–8 对应模型/原生头像；训练四入口、进行中及六等待格同步 |
| 伐木工名称 | 普通工人“伐木工LV1～LV8”，合成工人“超级伐木工LV1～LV8”；出生与合成注册时写入展示名 |
| 建造师天赋 | 入口名称为“天赋”；未选问号闪烁；选择成功后保留所选卡牌缩略图，不因后续 BOSS 历史轮转消失 |
| 普通研究 | 木头、三木头、加速手套、振奋宝石、高射火炮、灼热之箭、活力之球、掠夺者之斧、水晶剑 |
| 高级研究 | 标枪、暗灭、龙心、冰甲、暗杀、瞄准、代达罗斯、盛势闪光、迅捷闪光、秘奥闪光 |
| 农场前置 | LV1→2/2→3/3→4/4→5 分别要求本人主城 LV2/3/4/5；修复同队高等级主城提前解锁的问题；提示显示前置 |
| 英雄祭坛 | 末日、影魔、斧王、小黑、大圣、剑圣各自的原生 2D 头像 |
| 金矿 | 采金效率用三枚金币，暴击用更大的金币堆 |
| 商店 | 武器、装备、材料入口使用 Dota 原生物品图；保留现有物品ID、购买逻辑和存档图集数据 |
| 商店挑战 | 替换为相应资源、物品和英雄/怪物原生图，不再使用原传送门插画 |
| 挑战建筑 | 山岭巨人、树人、Visage 龙形、剑圣、炼金术士分别使用其实际模型对应原生头像 |
| 英雄脚下 ERROR | 召唤前增加按玩家 ID 加载其原生英雄及账号饰品的异步屏障，覆盖全部六英雄 |
| 范围拾取 | 使用 Dota 原生迈达斯之手图标 |

## 天赋状态与兼容

复用 `survival_rogue_reward` NetTable 和 `ROGUE_REWARD_CHANGED` 事件；新增 `builder_talent`（card_id/name/description/icon_name）与 `talent_pending`。独立保存所选开局卡，不依赖最多20条奖励历史。

开局三选一只产生一次。重复打开未领取的天赋复用原 token，不额外排队；已选后点击展示天赋说明，不重复发奖。原生按钮及鼠标事件不被替换，只增加不接收点击的图标层。切换单位/复用技能槽会隐藏旧图层，失效句柄可以重建。

## 英雄资源修复依据

本机 `game/dota/console.log` 的 2026-09-26 16:40:22～23 记录：当前指定的 Doom 七件外观已加载成功，但账号原生装备 `doom_2021_immortal_weapon` 和 `eternal_fire_*` 请求了未驻留模型。原预加载走地图代理单位且 PlayerID=-1，未包含玩家账号饰品。

现在 `hero_asset_preload_service.request` 先等待地图外观，再调用 `PrecacheUnitByNameAsync(真实英雄名, callback, player_id)`；只有两部分均完成才允许 ReplaceHeroWith。状态按玩家与英雄隔离，重复请求合并，失败可重试，旧局回调不能污染新局。[API 类型声明](https://github.com/TypeScriptToLua/Dota2Declarations/blob/master/dota-api-functions.d.ts)说明 PlayerID 用于加载玩家饰品。

这说明并修复了日志中的缺失资源加载路径；ERROR 的实际消失仍需新局实机观察。

## 资源来源与构建

Dota 原生图取本机 `dota/pak01_dir.vpk`；建筑来自 `output/unique_buildings/previews`、`output/reference_walls/previews`。LV1 伐木工使用同模型的原生头像；其他工人从训练 CSV 中声明的模型导出后渲染为2D，未修改游戏内模型。

金币与木头按当前资源栏形状制作；鸡腿及21张已选天赋缩略图复用项目已有素材。106张128×128 PNG位于 `panorama/src/images/spellicons/survival/native`，编译版本位于 `panorama/images/spellicons/survival/native`。

构建：`powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/build_native_hud_icons.ps1`。脚本备份并同步相关文件到 content，编译图标依赖 XML 和 HUD；本次分别107项、15项，均0失败。

CSV为配置权威源。此次研究表仅修改 icon_name；训练表仅修改名称；天赋规则/建造阶段/Tooltip仅修改展示字段。逐列对比确认480条科技的多行描述、价格、等级和效果数值保持一致。生成 Lua 通过 `tools/build_configs.py` 针对对应 CSV 生成。

## 验证

9项 Lua 5.1 回归：英雄召唤、四玩家隔离、账号饰品异步预加载、天赋选择/失败/重复领取/历史轮转、天赋保留、工人生成/训练队列、农场本人主城门槛、研究投影。

4项 Node 回归：训练队列、原生HUD回调及天赋闪烁、选择恢复、原物品图映射兼容。另检查47个技能图标引用、106个编译纹理、Lua语法、CSV字段范围及原存档图集数据。

资源预览：`output/native_hud_refresh_20260926/icon_contact_sheet.jpg`。详细证据：`docs/ai/validation/20260926/native_hud_icons.json`。

实机验收请重开 Workshop Tools 对局（NPC KV 和 Lua 不以 Panorama 热更新作为验收依据）。重点查看：G键未选/已选两种状态、模型缩略图识别度、农场本人主城门槛、英雄ERROR是否消失。

## 技能图标索引

| 技能 | Texture |
| --- | --- |
| `ability_build_advanced_research_lab` | `survival/native/building_advanced_research_lab` |
| `ability_build_arrow_tower` | `survival/native/building_arrow_tower` |
| `ability_build_challenge` | `survival/native/building_challenge` |
| `ability_build_farm` | `survival/native/building_farm` |
| `ability_build_gold_mine` | `survival/native/building_gold_mine` |
| `ability_build_hero_altar` | `survival/native/building_hero_altar` |
| `ability_build_main_city` | `survival/native/building_main_city` |
| `ability_build_research_lab` | `survival/native/building_research_lab` |
| `ability_build_wall` | `survival/native/building_wall` |
| `ability_challenge_monster_01` | `survival/native/portrait_tiny` |
| `ability_challenge_monster_02` | `survival/native/portrait_treant` |
| `ability_challenge_monster_03` | `survival/native/portrait_visage` |
| `ability_challenge_monster_04` | `survival/native/portrait_juggernaut` |
| `ability_challenge_monster_05` | `survival/native/portrait_alchemist` |
| `ability_research_advanced_lumberjack_efficiency` | `survival/native/wood_stack` |
| `ability_research_advanced_lumberjack_speed` | `survival/native/hyperstone` |
| `ability_research_advanced_tower_attack` | `clinkz_searing_arrows` |
| `ability_research_advanced_wall_health` | `survival/native/reaver` |
| `ability_research_ars_01` | `survival/native/javelin` |
| `ability_research_ars_02` | `survival/native/desolator` |
| `ability_research_ars_03` | `survival/native/heart` |
| `ability_research_ars_04` | `survival/native/shivas_guard` |
| `ability_research_ars_05` | `sniper_assassinate` |
| `ability_research_ars_06` | `sniper_take_aim` |
| `ability_research_ars_07` | `survival/native/greater_crit` |
| `ability_research_ars_08` | `survival/native/overwhelming_blink` |
| `ability_research_ars_09` | `survival/native/swift_blink` |
| `ability_research_ars_10` | `survival/native/arcane_blink` |
| `ability_research_lumberjack_crit` | `survival/native/lesser_crit` |
| `ability_research_lumberjack_efficiency` | `survival/native/wood` |
| `ability_research_lumberjack_speed` | `survival/native/gloves` |
| `ability_research_tower_attack` | `gyrocopter_flak_cannon` |
| `ability_research_wall_health` | `survival/native/vitality_booster` |
| `ability_summon_axe` | `survival/native/portrait_axe` |
| `ability_summon_blademaster` | `survival/native/portrait_juggernaut` |
| `ability_summon_doom` | `survival/native/portrait_doom_bringer` |
| `ability_summon_drow_ranger` | `survival/native/portrait_drow_ranger` |
| `ability_summon_monkey_king` | `survival/native/portrait_monkey_king` |
| `ability_summon_shadow_fiend` | `survival/native/portrait_nevermore` |
| `ability_survival_pickup_materials` | `survival/native/hand_of_midas` |
| `ability_survival_rogue_reward` | `survival/native/talent_question` |
| `ability_train_advanced_repairer` | `survival/native/train_repairer_02` |
| `ability_train_lumberjack` | `survival/native/train_lumberjack_01` |
| `ability_train_population` | `survival/native/population` |
| `ability_train_repairer` | `survival/native/train_repairer_01` |
| `ability_upgrade_gold_mine_crit` | `survival/native/gold_stack` |
| `ability_upgrade_gold_mine_efficiency` | `survival/native/gold` |
