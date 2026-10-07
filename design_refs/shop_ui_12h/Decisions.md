# 视觉决策

参考观察：01暖象牙留白及轻青玉边缘；02/03偏冷、下缘阴影较重，hover按钮较厚；顶部云雾已经优于历史硬金线；导航光晕和底线独立。

生产现状：commerce_remaining_5d5c1152eb.js使用1210×810窗口、顶端六类别和225×273商品卡，与新layout合同有差异。基线需要独立保存，后续仅重组展示。支付/兑换函数保持原样。

原有服务端类别是武器装备/道具材料/科技服务/挑战/转职/礼包，未发现英雄皮肤商城类别；不编造上架。皮肤卡片仅做公共组件兼容样例，明确区分验证范围。

## 01_junction · 保留 J02

- J01：淘汰；改善：减弱标题下方横带；代价/淘汰依据：背景过渡仍是窄带，侧栏深浅关系未改善。截图：work/candidates/J01/normal.png、hover.png及100%局部。
- J02：保留；改善：暖雾衔接象牙标题与商品底，顶部接缝更连贯；代价/淘汰依据：比原版少一点青灰层次，仍保留山水细节。截图：work/candidates/J02/normal.png、hover.png及100%局部。

## 02_sidebar · 保留 J04

- J03：淘汰；改善：接缝更克制；代价/淘汰依据：仅降低透明度导致原直线边缘仍显硬。截图：work/candidates/J03/normal.png、hover.png及100%局部。
- J04：保留；改善：薄雾与细线替换宽亮边，选中行光晕保持完整；代价/淘汰依据：深色侧栏边界仍可见，属于必要分区。截图：work/candidates/J04/normal.png、hover.png及100%局部。

## 03_card_material · 保留 C07

- C05：淘汰；改善：象牙更暖，卡体保留玉石雕刻感；代价/淘汰依据：原厚边框与底部双线仍过重。截图：work/candidates/C05/normal.png、hover.png及100%局部。
- C06：淘汰；改善：明显扁平化，减少外边与高光；代价/淘汰依据：浅色物品与底板层次过弱，失去浅玉质感。截图：work/candidates/C06/normal.png、hover.png及100%局部。
- C07：保留；改善：细边框与较浅浮雕平衡商品轮廓，接近风格锚点；代价/淘汰依据：仍有微弱云纹，非纯白平面。截图：work/candidates/C07/normal.png、hover.png及100%局部。

## 04_card_shadow · 保留 C09

- C08：淘汰；改善：投影显著减弱，网格留白更干净；代价/淘汰依据：卡体与窗口几乎贴平，hover层级不易察觉。截图：work/candidates/C08/normal.png、hover.png及100%局部。
- C09：保留；改善：中等投影保留浅浮起，消除原版偏脏底边；代价/淘汰依据：卡片仍有轻微实体边界。截图：work/candidates/C09/normal.png、hover.png及100%局部。

## 06_name_price · 保留 N13

- N13：保留；改善：名称重量减轻、字距收紧，名称和价格形成清晰层次；代价/淘汰依据：中文标题雕刻感比粗字稍弱。截图：work/candidates/N13/normal.png、hover.png及100%局部。
- N14：淘汰；改善：柔软价格带减少下半部边缘；代价/淘汰依据：价格与卡体辨识不足，保留原内嵌信息底。截图：work/candidates/N14/normal.png、hover.png及100%局部。

## 07_hover · 保留 H16

- H15：淘汰；改善：遮罩横向铺开，文字更稳；代价/淘汰依据：边缘仍是一块深色矩形，压过物品细节。截图：work/candidates/H15/normal.png、hover.png及100%局部。
- H16：保留；改善：较轻遮罩与四边渐变让物品仍可见，价格不遮挡；代价/淘汰依据：极亮物品须复查长描述对比度。截图：work/candidates/H16/normal.png、hover.png及100%局部。

## 08_buy_button · 保留 B17

- B17：保留；改善：减少金边及高光，青玉按钮有清楚但克制的购买反馈；代价/淘汰依据：比原版立体感较低。截图：work/candidates/B17/normal.png、hover.png及100%局部。
- B18：淘汰；改善：亮釉提高购买按钮可见性；代价/淘汰依据：亮边抢商品主体，背离极简方向。截图：work/candidates/B18/normal.png、hover.png及100%局部。

## 05_item_display · 保留 I10

- I10：保留；改善：独立投影减弱至55%，浮空物品底部不再显脏；代价/淘汰依据：接触感略轻，仍能辨认投影。截图：work/candidates/I10/normal.png、hover.png及100%局部。
- I11：淘汰；改善：缩小6%增加留白；代价/淘汰依据：缩放使示例物品细节发软，宽大物品原比例更清楚。截图：work/candidates/I11/normal.png、hover.png及100%局部。
- I12：淘汰；改善：展示底改成暖色柔雾；代价/淘汰依据：与卡体形成额外亮色块，原环纹更自然。截图：work/candidates/I12/normal.png、hover.png及100%局部。

## 09_navigation · 保留 B17

- V19：淘汰；改善：选中象牙材质稍暖；代价/淘汰依据：全图对比收益很小，原导航材质已符合参考，不叠加修改。截图：work/candidates/V19/normal.png、hover.png及100%局部。
- V20：淘汰；改善：选中光晕减半，边缘更克制；代价/淘汰依据：底部金线与选中态弱化，保留原光晕与金线。截图：work/candidates/V20/normal.png、hover.png及100%局部。

## 10_production_adaptation · 保留 B17 + L21 + T23

- L21：保留；改善：长说明改用全展示区软边遮罩，消除额外硬矩形；仍看得到商品；代价：长说明覆盖更多商品，只有长说明启用。证据 work/candidates/L21/normal.png、hover.png、card_hover.png。
- L22：淘汰；改善：文字对比度更强；代价：94%深色遮挡明显压过商品，84%已足够。证据 work/candidates/L22/normal.png、hover.png、card_hover.png。
- T23：保留；改善：53x48原券图内嵌96px，减少放大模糊，保持原图映射；独立投影跟随实际展示比例；代价：该旧图仍有自带背景，需将来提供高分辨率透明原资源。证据 work/candidates/T23/normal.png、hover.png、card_hover.png。
- T24：淘汰；改善：128px券图轮廓更大；代价：模糊和自带矩形更明显。证据 work/candidates/T24/normal.png、hover.png、card_hover.png。

确认的264×224展示区和256×192标准图区域不变。仅低清历史缩略图使用其内部96×96 inset。共24个实质候选，最新T24淘汰。

## 原生接入修正与冻结

真实游戏暴露两处浏览器预览无法证明的偏差：顶部雾化图低于 header，单行名称在固定宽 Label 中仍偏左。将 header / mist 分别设为 3 / 4；名称改为独立 272×34 区域内 fit-children Label 实际字串居中。随后悬停截图发现父容器低于 hover 背景，补齐 CJNameRegion 层级 3。最终 shot_0030/0031 已查看，默认和悬停名称均居中可见。这些是实现修正，不增加材质候选计数。

礼包原 272px 单元在滚动条出现时退成一列。改为 262px、保留 12px 间距和 568px 内容区，实际预览恢复 2×2 四单元首屏，七项内容滚动且价格购买区不移动。窗口、标准商品卡、网格合同不变。

实际服务器目录与本地 CSV 不完全相同，保留服务器权威结果：真实两类、108 条；本地六类、114 条仅作预览回归。没有新增商品、放开账号或改价格让截图更完整。重复水晶原图映射保留；原装备、皮肤图和券图只作公共工厂辨识度与比例检查，不替换真实目录。

停止实质改动：衔接、卡体、投影、信息和交互已有可观察改善及必要检查；额外高光或导航装饰没有比较收益。冻结 B17 + L21 + T23，记录后续需要高分辨率透明券原图的具体缺口，没有为用满预算追加候选。
