# V10 正式装备图标接入

本轮按用户新增授权实际实现了35项原生图标绑定：12件神兵碎片、9件存档神器、14件积分装备。已确认的23件虚空之影继续使用V10组件包；其他没有合适原生对应的条目保留项目原图。正式ID、名称、属性、数量、升级及抽奖接口均未改变。

## 匹配与来源

所有URI均从本机 `../../dota/pak01_dir.vpk` 找到实际 `.vtex_c`，读取真实显示尺寸并导出原始PNG供浏览器验证。尺寸优先使用大于0的 `DisplayRectW/H`，缺失或为0时回退 `Width/Height`；存储纹理尺寸另外保留为证据。魔头之命的存储是256×256，实际显示区及导出PNG是256×170，已修正元数据以避免错误方形缩放。预览工具逐项读取PNG的IHDR与绑定尺寸核对。没有重绘、补图、生成相似原图或把图片裁成方形。统一返回 `fit: contain`，宽幅武器保留完整轮廓，数量牌和独立名称由现有V10单元继续显示。

神兵碎片按正式CSV的来源英雄及Valve饰品定义核对，保留已经精准匹配的饰品图。其中 `fragment_10` 旧URI `econ/items/legion_commander/demon_sword.png` 在当前本机VPK不存在；新模块改为同一饰品定义5810实际存在的 `econ/items/legion_commander/blades_voth_domosh/blades_voth_domosh.png`。原始缺失路径及修正理由完整记录在映射JSON，未改原业务配置。

| 正式ID | 正式名称 | 保留的原生饰品／来源英雄 |
| --- | --- | --- |
| fragment_01 | 神兵-破碎大剑 | Shattered Greatsword／斯温 |
| fragment_02 | 神兵-始祖之祸 | Mars TI9 Immortal Weapon／玛尔斯 |
| fragment_03 | 神兵-焚焰 | Pyre／末日使者 |
| fragment_04 | 神兵-净魂之刃 | Spectre Diffusal／幽鬼 |
| fragment_05 | 神兵-狂战斧 | Battlefury／虚空假面 |
| fragment_06 | 神兵-碎颅锤 | Skullbasher／敌法师 |
| fragment_07 | 神兵-影刃 | Kunkka Shadow Blade／昆卡 |
| fragment_08 | 神兵-龙爪弯钩 | Dragonclaw Hook／帕吉 |
| fragment_09 | 神兵-纯金之触 | Golden Cyrridae／编织者；保留对应金色饰品 |
| fragment_10 | 神兵-战鬼双刃 | Blades of Voth Domosh／军团指挥官；修正实际缺失URI |
| fragment_11 | 神兵-魔头之命 | Clinkz TI9 Immortal Weapon／克林克兹 |
| fragment_12 | 神兵-魔导师密钥 | Magus Cypher／拉比克 |

存档神器使用Dota同名物品。完整路径以前缀 `file://{images}/items/` 组成。

| 正式ID | 正式名称 | 原图文件 |
| --- | --- | --- |
| building_01 | 玲珑心 | octarine_core.png |
| building_02 | 圣剑 | rapier.png |
| building_03 | 赤红甲 | crimson_guard.png |
| building_04 | 大剑 | claymore.png |
| building_05 | 深渊之刃 | abyssal_blade.png |
| building_06 | 板甲 | platemail.png |
| building_07 | 秘法鞋 | arcane_boots.png |
| building_08 | 狂战斧 | bfury.png |
| building_09 | 雷神之锤 | mjollnir.png |

积分装备按正式名称的武器或装备形状匹配。自创名称使用的是外观适配，不表示其属性等同于被选中的Dota物品。

| 正式ID | 正式名称 | 原图文件／适配理由 |
| --- | --- | --- |
| lottery_gale_bow | 疾风弓 | grove_bow.png／长弓 |
| lottery_swift_emblem | 快速纹盘 | medallion_of_courage.png／金属纹盘 |
| lottery_soul_devouring_blade | 噬魂灵剑 | diffusal_blade.png／灵能刀刃 |
| lottery_gathering_grimoire | 采集秘典 | tome_of_knowledge.png／典籍 |
| lottery_gathering_divine_codex | 采集神典 | necronomicon_3.png／高级魔法典籍 |
| lottery_aaron_cannon | 亚伦巨炮 | greater_crit.png／大炮装备 |
| lottery_titan_shield | 泰坦巨盾 | vanguard.png／厚重盾牌 |
| lottery_reincarnation_orb | 轮回宝珠 | refresher.png／循环宝珠 |
| lottery_crystalline_armor | 晶态护甲 | shivas_guard.png／冰晶防护装备 |
| lottery_muramasa | 妖刀村正 | yasha.png／东方长刀 |
| lottery_sword_of_promise | 誓约之剑 | rapier.png／金色长剑 |
| lottery_spear_of_longinus | 朗基努斯枪 | dragon_lance.png／赤红长枪 |
| lottery_magic_book | 魔法书 | book_of_shadows.png／魔法书 |
| lottery_raven_eye | 渡鸦之眼 | eye_of_the_vizier.png／眼状秘宝 |

正式抽奖目录的其他83项保留项目图，逐项理由见JSON的 `retained`。每日积分奖励不属于此次装备替换范围，继续使用原图。亲友、瑞兽、宠物、钓鱼、称号等独有题材未借用不相关的原生武器图；地图／通关／无尽档位系列不在此次装备换图范围。

## 源文件及接入口

- `data/ui/archive_v10_icon_bindings.json`：正式配置文件哈希、35条映射、图源SHA256、实际显示尺寸、原生存储尺寸／显示区域、匹配理由及保留条目。
- `panorama/src/scripts/custom_game/archive_v10_icons.js`：独立只读模块 `GameUI.CustomUIConfig().ArchiveV10Icons`。
- `tools/archive_v10/build_icons.cjs`：从正式CSV、本机VPK和饰品定义生成绑定；`--check` 验证生成文件未漂移。
- `tools/archive_v10/native_binding_previews.cjs`：从原始纹理导出PNG，并生成浏览器别名及组装预览。
- `tools/archive_v10/capture_icon_montage.cjs`：独立无头浏览器检查图片解码、等比显示并截图。
- `tools/tests/archive_v10_icons.test.cjs`：验证配置身份、本机资源、类别隔离、只读行为、路径修正、显示区优先／安全回退及虚空之影保留。

Renderer加载模块后调用 `ArchiveV10Icons.Resolve(item, category)`。命中返回 `{uri, fit, sourceSize, iconKey, name}`；未命中返回 `null`，继续既有 `A.Icon`。使用真实正式ID与category匹配，不能按列表位置或模糊名称覆盖。把 `iconKey` 纳入既有视觉缓存键，确保切换目录和重载时不会留下旧图。该模块没有游戏事件、购买、保存或属性写入。

浏览器预览桥接文件为 `design_refs/archive_v10/work/icon_map_v11/native_aliases.json`，读取它的 `.aliases` 后合并现有别名。别名指向原资源导出的PNG，仅用于本地预览；正式游戏URI继续引用原生 `{images}`，不把机器绝对路径写入正式UI。

## 验证与截图范围

已经通过：

```powershell
node tools/archive_v10/build_icons.cjs
node tools/archive_v10/native_binding_previews.cjs
node tools/tests/archive_v10_icons.test.cjs
node tools/archive_v10/capture_icon_montage.cjs
```

验证结果为35条正式绑定、34张不同的真实原生纹理；全部完成解码、导出PNG与显示尺寸一致性检查和 `contain` 等比显示，没有缺图。显示区优先、0值回退和字段缺失回退均已通过回归测试，魔头之命固定为256×170。12件神兵还核对了来源英雄与Valve饰品定义。14件积分装备均实际打开原图后选定；朗基努斯枪最终使用赤红长枪，替换了预选但轮廓不适合的锁链法杖候选。

实际本地组装图：`design_refs/archive_v10/work/icon_map_v11/montage.png`；可运行预览：同目录 `montage.html`，浏览器直接打开。验收记录：`montage_validation.json`，标记 `notGameScreenshot: true`。完整原图证据及哈希见 `work/icon_binding_verification/manifest.json`。

这张截图来自35项原图的本地组件组装，不是游戏截图；正式V10页面的入口加载、Tooltip及游戏内整体效果由主集成任务统一编译和验收。原生物品多数88×64，放入120×120槽有留白和轻微放大，这是保持原图比例的正常结果，不承诺新增高分辨率细节。
