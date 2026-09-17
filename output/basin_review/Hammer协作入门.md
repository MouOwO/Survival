# 我们的分工

我负责地形、台阶、城墙入口、主要材质、基础光照和导航检查；你负责草丛、碎石、落叶、水渍与小景组合。先确认主体的视觉效果，再开始手工点缀。

用于手工编辑的地图：

`D:\steam\steamapps\common\dota 2 beta\content\dota_addons\survival\maps\survival_basin_edit.vmap`

`survival_basin_review.vmap` 是自动生成的实机检查文件，后续会重建。请把手工工作保存在 `survival_basin_edit.vmap`。

## 第一步：打开可编辑地图

1. 启动 Dota 2 Workshop Tools，在插件列表中选择 `survival`。
2. 从工具界面打开 Hammer。
3. 通过 `File → Open` 打开上面的 `survival_basin_edit.vmap`。
4. 先找到 `USER_90_DETAILS` 分组。第一次正式练习时，我会根据你当前的 Hammer 窗口，带你找到对象列表、资源面板与属性面板。

这一步先完成“打开正确文件”。不要为了找按钮反复切换不熟悉的工具；界面布局或语言不同，我们按实际窗口继续。

## 地图分组

| 名称 | 内容 | 我们怎样使用 |
|---|---|---|
| AI_01_TERRAIN | 地形、台阶、平台地面 | 主体调整由我处理；已锁定组变换，避免整体移动 |
| AI_02_BASE_PROPS | 主体自带的树、岩石和入口标记 | 后续主体更新会替换这一组 |
| AI_03_LIGHT_AND_MARKERS | 灯光、边界与出生标记 | 由我维护 |
| USER_90_DETAILS | 你的手工装饰 | 更新脚本保留整组内容 |

你的装饰放进 `USER_90_DETAILS`。这四个分组名保持不变，里面的装饰对象可以自由命名。更新脚本也会保留组外新增的普通对象，但不要把手工作品放进 `AI_` 组。更新前先在 Hammer 保存，备份位置为项目 `output/basin_review/handoff_backups`；没有保存到磁盘的修改无法由文件更新脚本保留。

## 第一课：先放一个草丛

我们先在西侧松林平台边缘练习，保持中央建造区域和阶梯口开阔。

1. 在资源面板的模型分类中搜索 `fern002`，核对完整模型路径为 `models/props_nature/fern002.vmdl`。
2. 将它放到平台靠边的位置。先只放一个。
3. 选中这个对象，在属性中核对模型路径、位置和缩放。西侧平台的平坦地面高度是 **640**；模型原点应落在地面，必要时稍微埋入根部。
4. 使用移动、旋转、缩放工具调整，观察根部是否悬空、叶片是否挡住入口。
5. 将对象加入 `USER_90_DETAILS` 后保存。分组与落地工具的具体按钮，在你打开窗口后逐步演示。

第一课的目标只有：**一个草丛正确落地、没有挡路、保存后仍然存在。** 然后再学复制和小范围组合。

## 模型、地面材质、贴花是三种操作

| 想做的事 | 对应操作 |
|---|---|
| 把草丛换成小石头 | 选中模型实体，在属性的模型资源字段中换 `.vmdl` |
| 把一块地面换成另一种石材 | 在面选择模式选中地面面片，再指定 `.vmat` |
| 在已有石板上添加水渍、落叶或污迹 | 添加经过验证的贴花/覆盖组件，再调尺寸、方向和透明边缘 |

新制作的北侧石地使用整座平台专用 UV。普通的可重复材质可以调整缩放；这套整岛图案不能随意平铺、旋转或用到另一块任意尺寸地面，否则石缝和构图会错位。我们会在副本上练习材质切换。

水渍课会单独准备并测试资源；请先不要把整张水面材质铺成矩形放在石板上。普通模型的材质能否直接替换也取决于模型是否提供材质变体，不等同于地面的面材质切换。

## 先使用的素材清单

| 搜索词 | 完整资源路径 | 用途 |
|---|---|---|
| fern002 | models/props_nature/fern002.vmdl | 林地边缘蕨类 |
| chipped_rocks002 | models/props_nature/chipped_rocks002.vmdl | 少量碎石 |
| river_rocks001 | models/props_nature/river_rocks001.vmdl | 较大的边缘岩石 |
| v03_grass | models/xianxia_kit/v03_grass.vmdl | 已有自制草簇 |
| snow_authored | materials/basin_review/snow_authored.vmat | 北侧专用石地与积雪混合材质 |

素材不能只凭文件名判断效果。第一轮每种先放一个，确认尺寸、朝向和材质正常，再复制使用。

## 我们怎样逐步教学

第一课放置一个草丛；第二课复制、旋转并替换成碎石；第三课在练习副本中切换地面材质；第四课添加水渍贴花；最后学习编译并到正常游戏镜头下检查。每一课都根据你的实际窗口讲解按钮位置，不要求你先掌握整个 Hammer。

Valve 的入门教程说明了从 Workshop Tools 打开插件、在 Hammer 使用资源面板与预制件的基本流程：
https://developer.valvesoftware.com/w/index.php?title=Dota_2_Workshop_Tools%2FLevel_Design%2FCreating_A_Dota-Style_Map&uselang=en
