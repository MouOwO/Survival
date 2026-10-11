# V10 存档图标适配审计

此文记录前一轮只读审计：重复瑞兽来自既有映射；非方图的问题需要按图源处理，不能把所有类别统一换成英雄头像。后续用户已授权按正式装备名称实际适配；新增35项原生装备绑定和一项缺失URI修正，详见 [ICON_IMPLEMENTATION.md](ICON_IMPLEMENTATION.md)。奖励、存档及装备属性保持原有配置，也未生成相似素材。

本文件其余分类建议属于前一轮审计，不代表全部分类重绘已获授权。前一轮实际修正范围为普通图标等比显示、称号／无尽复合图整体适配和 Tooltip 三层九宫格；后续35项装备绑定按新增授权实施。专属存档档位系列仍需单独设计、对照和确认，V10 已确认虚空之影图标保留原包。称号保留128:55比例，以120×51.5625舞台显示且不重置内部百分比；无尽保留72×56舞台，将整体放大1.666667倍且不覆盖左右子环的位置和尺寸。上述复合图适配保持原图和原映射，不属于换图。

## 已核实的图标调用链

`panorama/src/layout/custom_game/archive.xml` 依次加载 `reward_presentation.js`、`archive_handoff_180de7e38b.js`、`icons_remaining_5d5c1152eb.js`、`archive_v10.js` 和实际控制器。

- `archive_handoff_180de7e38b.js:180` 的基础 `Icon` 优先使用已配置的建筑物品图及 `item.icon`，随后用 `icon_style` 回退到旧包素材。回退 `seal` 对应 `art_01.png`。
- `icons_remaining_5d5c1152eb.js:3` 的内嵌目录覆盖上述 `Icon`。它按 `category_id:item_id` 查表；图像使用 `runtime_uri`，并设置 `stretch-to-fit-preserve-aspect`。建筑另走原生物品 URI；无尽条目另画 CSS 双环徽记，不能仅看目录路径推断实际画面。
- 当前内嵌目录与 `data/csv/存档系统/archive_item_icons.csv` 的路径完全一致，本次审计没有发现 CSV 与活动脚本漂移。重复图是两者共同的旧设计。
- 实际控制器 `archive_180de7e38b_titles_compact_v6.js:146` 调用被覆盖后的 `A.Icon`；V10 移动生成的 `ArchiveArt` 并将视觉容器设为 120×120。已明确设置等比的普通 Image 会留白，不会因容器变方而直接改变原图比例。旧回退图和未明确 scaling 的 Image 才存在拉伸风险；本轮父代理已补普通子 Image 的等比设置。
- `reward_presentation.js` 仅识别 `image`、`ability`、默认 `item`；不能把 `icon_type=hero` 当成已经支持的正式能力。要使用原生英雄图，明确使用 Image URI，或另行接入真正的英雄图像控件。

`archive_map_levels.csv` 本身没有图标列；`archive_online_rewards.lua:69` 只给地图等级条目 `icon_style=seal`。因此 V10 没有自行选出瑞兽：它继承了 UI 专用映射中的重复图片。

## 各分类的当前证据与修正分组

表中“映射数／不同图数”指活动 UI 图标目录，不等于玩家持有数或分类容量。正式条目数来自对应 CSV。

| 分类 | 实际来源与问题 | 可执行修正方向 |
| --- | --- | --- |
| 虚空之影 `shadow` | 正式 23 项；旧目录仅 4 项，但 V10 优先使用确认包内的 `virtual_01…23.png`，覆盖全部 23 项。 | 保留 V10 原组件与包内图标，不再重新生成；数量、名称保持独立。 |
| 通关存档 `clear` | 44／1，全部 `archive_portraits_v1/achievement_closeup.png`，实看是银色盾徽，不是逐关卡插画。正式 CSV 仅有 `icon_style`。 | 制作少量同风格通关等级徽章，按正式 `difficulty_id` 和 `achievement_id` 确定映射；次数继续用独立文本，不烘焙进图。 |
| 地图等级 `map_level` | 34／1，全部 `archive_portraits_v1/boss_map_head.png`，实看是青白瑞兽大头，正是截图重复源。 | 优先替换该类别的瑞兽映射。用 6–8 档地图／等级徽章，按正式 `map_01…34` 稳定映射；当前等级与目标等级保持现有独立文字。不要任意配 34 个不同英雄。 |
| 上班福利 `work` | 34／17，`archive_collection_v4/work_symbol_01…17.png` 每图复用两项；正式 CSV 无图标字段。 | 先保留已有明确不同的图；对攻速、伐木、采金等通用效果可用对应 Dota 方形技能图替换。按 `effect_ids` 建清单，不能仅按条目序号随机取图。 |
| 福利礼包 `gift` | 正式 36 项；UI 专用目录零映射，服务端统一 `seal`，实际回退 `art_01.png`。 | 需要补正式 ID 的显示映射。胜利奖励／共同胜利奖励各有独立系列徽章；通用属性可用方形技能图，但不能按“礼包”名称新增宝箱类业务。 |
| 神兵碎片 `fragment` | 12／12，已逐项使用本机 Valve 饰品原图；11 张为横向约 256×170，骨弓饰品为 256×256。 | 保留对应武器原图与身份；在方形槽内等比 contain。武器图可能带原灰色背景，若要与紫底更统一，应做有证据的逐项展示处理，不能直接裁掉刀尖或换成不对应的英雄。 |
| 秘法牢笼 `pet` | 54／54，`archive_items_v2/cage_*.png`。多数是牙、爪、沙漏、粉末等材料；CSV 没有英雄映射。 | 保留有识别度的材料图；通用材料可选原生物品 contain，独有材料再定制。不要把整个分类改成宠物英雄头像。 |
| BOSS存档 `boss` | 34／1，同地图等级瑞兽图；正式项目是累计进攻／波次 BOSS 击杀门槛，不是 34 个独立 BOSS 身份。 | 用统一 BOSS 成就徽章的少量档位变体，按 `boss_1…34` 映射。不能无依据把第 N 项配成某位 Dota 英雄。 |
| 积分道具 `points` | 100／100，原 `reward_art_v5` 独立图；正式可见内容由签到与抽奖库存共同投影。 | 装备／Dota 单位／技能类优先用已有准确的原生映射；非 Dota 奖励保留已有图。保留 N/R/SR/SSR/UR 独立品质标记，不改变奖励 ID 或数量。 |
| 商城道具 `shop` | 目录 10／10，但该存档分类原 `enabled=0`，页面是本地未启用空目录。 | 不为禁用分类制作新图或引入商品；未来启用时再按真实商品映射。与独立生存商店、商城兑换页面区分。 |
| 无尽存档 `endless` | 目录 82／1，但真实 wrapper 不显示银盾，而生成 CSS ∞ 双环。审计发现统一子元素尺寸会覆盖旧左右双环几何，本轮已改为保留72×56内部舞台、整体缩放1.666667倍，子环几何不再覆盖。 | 当前保留原 ∞ 组件与映射。后续可另设计少量无尽档位徽章，并区分正式 `progress_kind=score/wave`；该换图建议尚未确认。 |
| 钓鱼存档 `fishing` | 26／26，`archive_collection_v4/star_blessing_*.png`；是命名祝福／收藏物，不全是 Dota 单位。 | 保留已有逐项图片；对应原生物品的才换原图。缺失的独有收藏物再定制，不改真实名称或未知数量规则。 |
| 存档建筑 `building` | 9／9，原生玲珑心、圣剑、赤红甲、大剑、深渊之刃、板甲、秘法鞋、狂战斧、雷神之锤。原始图约 88×64。 | 保留准确原生物品身份，方槽内 contain；若想更饱满，可以在原图背后用统一紫色槽底，不能把横图拉成正方或切掉物品。 |
| 我的前男友 `friend` | 40／40，已有 `archive_portraits_v3/friend_*.png` 头肩像，1254×1254。名称包含哆啦A梦、孙悟空、路飞等。 | 保留逐角色头像，不批量换成 Dota 英雄。孙悟空等只有在项目确实指向 Dota 角色时才用其英雄图；名称相同不能自动视作同一角色。 |
| 我的前女友 `ex` | 40／40，已有 `archive_portraits_v3/ex_*.png`，包含胡桃、雷电将军等明确非 Dota 角色。 | 保留当前角色身份；只处理留白、主体大小和边缘，不能以 Dota 英雄图替换。 |
| 神兽 `beast` | 40／40，`archive_items_v2/beast_*.png`，包括钟、符等命名物，不是全为英雄。 | 保留逐项图；仅对有明确 Dota 对应的项目用原图。地图/BOSS的重复瑞兽问题不应通过删除整个神兽类别图标解决。 |
| 星悦积分 `starjoy_points` | 正式 24 项；无 UI 目录映射，但服务端明确给 `starjoy_v1/starjoy.vtex`，因此同一符号是项目自有积分标识。 | 保留积分符号，等级差异用现有独立文本或克制的档位装饰；不替换成英雄头像。 |
| 称号 `titles` | 正式 9 项，独立 `icon` 和既有分层／动态称号组件；不是物品目录。审计发现普通图标尺寸重置会破坏分层几何，本轮已保留128:55舞台比例，显示尺寸120×51.5625，内部百分比不再重置。 | 保留已确认称号外观、动画、原图与装备行为；实际分层和裁剪效果仍以原生游戏验收记录为准，不新增图标映射。 |

## 本机原图的实际像素与比例

本轮从 `../../dota/pak01_dir.vpk` 读取对应 `.vtex_c`，用已安装 `Source2Viewer-CLI.exe -b DATA` 读取原生纹理元数据；没有用 CSV 的显示尺寸推断原图尺寸。后续实施核对了纹理显示区：优先大于0的 `DisplayRectW/H`，缺失或为0回退 `Width/Height`，并与实际导出PNG核对。原生存储有填充时不能直接当作图像显示尺寸。

| 原生资源类型 | 实测原始纹理 | 在 120×120 方槽中的建议 |
| --- | --- | --- |
| 普通物品 `items/octarine_core` 等 | 88×64；赤红甲 86×64 | 等比 contain；88×64 放满宽后约 120×87。88px 原图放到120px会有轻微放大，不能承诺高分辨率细节。 |
| 饰品 `econ/items/sven/shattered_greatsword/...` | 256×171；其他多数显示256×170。骨弓该饰品存储256×256，显示区／原PNG256×170，已修正绑定。 | 横图 contain；256×170放满宽约120×80。保持完整武器，逐项审查灰底和主体占比。 |
| 普通英雄头像 `heroes/npc_dota_hero_axe` | 128×72，同样测得黑暗游侠、斯文、猴王、龙骑士为128×72 | 有明确英雄身份时可按主体裁成方形，逐英雄设置焦点；不能直接拉伸。当前本机图128px，裁方后有效区域更小，应实看清晰度。 |
| 小英雄头像 `heroes/icons/npc_dota_hero_axe` | 32×32，上述五个英雄均为32×32 | 不用于120px的大槽直接放大，放大会明显模糊。可用于小标记。 |
| 英雄选择图 `heroes/selection/npc_dota_hero_axe` | 142×188，上述五个英雄均为142×188 | 可作为较高主体分辨率的裁方候选，但其构图是竖图，仍需逐个检查脸部，不适合统一固定中心裁切。 |
| 原生技能 `spellicons/alchemist_chemical_rage` 等 | 实测七张代表技能均128×128；`attribute_bonus` 为64×64 | 优先128×128方形技能图，适合120px槽；旧通用属性图仅64px，不宜作为全部档位唯一大图。 |

可直接使用且本机已验证存在的方形技能 URI 示例：

- `file://{images}/spellicons/alchemist_goblins_greed.png`：采金／财富。
- `file://{images}/spellicons/alchemist_chemical_rage.png`：攻速。
- `file://{images}/spellicons/treant_living_armor.png`：生命恢复／建筑护甲。
- `file://{images}/spellicons/omniknight_guardian_angel.png`：防护。
- `file://{images}/spellicons/chen_holy_persuasion.png`：单位相关，仅有语义对应时使用。

这些是可用图源，不是本轮已确认的最终映射。多词条项目应按明确的主效果或专用系列标识选择，避免同一图表示完全不同奖励。

## 实物与复查方法

前一轮机器可读证据：`design_refs/archive_v10/work/icon_binding_audit.json`。其中记录全部18分类的活动目录、重复次数、源PNG真实尺寸、正式与活动路径比较；44张本机Valve资源的 `size` 是当时读取的存储尺寸，不能把有填充的存储尺寸当作最终显示比例。后续35项正式装备的权威显示尺寸见 `data/ui/archive_v10_icon_bindings.json`，原PNG核对见 `work/icon_binding_verification/manifest.json`，其中魔头之命已校正为256×170。历史审计可重复运行：

```powershell
node tools/archive_v10/audit_icon_bindings.cjs
```

本轮实际打开检查过的原图：

- 重复瑞兽：`panorama/src/images/custom_game/archive_portraits_v1/boss_map_head.png`。
- 重复银盾：`panorama/src/images/custom_game/archive_portraits_v1/achievement_closeup.png`。
- 旧回退印章：`panorama/src/images/custom_game/archive_handoff_v1/art_01.png`，真实130×95。
- 原生玲珑心导出：`design_refs/archive_v10/work/native_icons/octarine_core_png.png`。
- 原生英雄宽图导出：`design_refs/archive_v10/work/icon_audit_native/panorama__images__heroes__npc_dota_hero_axe_png.png`。
- 原生方形攻速技能导出：`design_refs/archive_v10/work/icon_audit_native/panorama__images__spellicons__alchemist_chemical_rage_png.png`。
- 原生神兵饰品导出：`design_refs/archive_v10/work/icon_audit_native/panorama__images__econ__items__sven__shattered_greatsword__shattered_greatsword_png.png`。

上述导出 PNG 保留原资源像素，未裁图、重绘或加工。原 `.vtex_c` 在同目录，尺寸可再次核实：

```powershell
& 'output/valley_decor_v2/source2viewer/Source2Viewer-CLI.exe' -i 'design_refs/archive_v10/work/icon_audit_native/panorama__images__spellicons__alchemist_chemical_rage_png.vtex_c' -b DATA
```

本轮审计没有宣称新的图标方案已游戏验收。普通 Image 等比显示和复合图内部几何风险已修；后续授权实施的35项装备原生绑定及本地组装验证单独记录在 `ICON_IMPLEMENTATION.md`。地图/BOSS错误题材、旧回退印章和独有材料／角色仍属于后续建议；共用外壳与已确认 V10 虚空之影保持固定。
