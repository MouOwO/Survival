# 最佳版接入与恢复

初始工程已按 stash → pull → pop → commit → push 提交并同步：`ab6c3070`，`origin/dev`。本轮 UI 新改动留在工作区供验收；之后提交也应执行同一流程。

## 已接入文件

- `survival_hud.xml` 与 `archive.xml` 引入共享 `common/jade_ui.css`、`common/jade_components.js`；存档再加载 `archive_jade.js`。后者位于旧导航/图标适配器之后、存档控制器之前，避免旧 inline 样式覆盖材质。
- `production_progress.js/css` 继续绑定原有训练快照与事件，生产默认 A；Tools/预览的 `SurvivalQueueLayout="B"` 仅用于候选比较。四个未满额等级与服务端保持一致，训练完成后递补后续等级。
- 存档的浅底、标题、侧栏、独立光晕和底部金线复用已有商城素材；真实奖励图标、进度和文字仍来自服务端。
- 每日奖励领取/返回，以及抽奖辅助确认按钮复用 JadeAction；旧 RHActionArt 只在 JadeAction 内隐藏。确认按钮的 callback、支付与抽奖状态机没有变化。每日奖励每周最后一天的高级装备规则保持原样。
- 共享 Tooltip 用深青玉底，存档和抽奖效果说明继续复用已有 ArchiveHandoff tooltip；原生技能 tooltip 仍由 Dota 提供。

## 尺寸、锚点与层级

| 组件 | UI 设计尺寸/字号 | 锚点与缩放 |
|---|---|---|
| 训练 A | 宽至少600，高252；普通卡126高，双成本134高 | 现有 HUD 上方，右边对齐技能区域；panelScale=max(g.scale,0.5)×1.15，再乘原生 UIScale |
| 训练 B | 单成本240高、卡116高；双成本回到252高 | 同一数据和锚点；未选作默认 |
| 训练选项 | 头像76方形；成本28，双成本24 | 当前四个未满额等级；成本下置，名额和等级小标记 |
| 活动/等待 | 活动头像50，进度50×4；等待48，步长56 | 一排最多六个等待项；总容量读取快照7；空槽隐藏 |
| 存档 | 869×713，侧栏214×589，四列143×138 | 继续使用原有 ModalShell/Fit；标题块上移防副标题裁切 |
| 存档文字 | 主标题38、页标题30、名称18、进度13 | 名称原生 shrink + tooltip；浏览器用省略近似 |
| 导航选择 | 光晕221×64、opacity .55；金线209×2 | 金线在52 UI 单位底部，独立于连续侧栏底图 |
| 底部 HUD | 原有264头像、116方形槽、六属性竖排 | 几何源码保持与初始提交一致；英雄/建筑扩展规则不变 |
| 公共按钮 | 保留每个视图原尺寸；正常/悬停/按下 PNG | 装饰层不接收鼠标；事件由已有 ActionButton 管理 |

具体颜色和尺寸在 `../UI_TOKENS.json`；材质源文件、编译资源、尺寸及 SHA 在 `resources.json`。生产样式使用已编译的 Panorama 支持属性；实验中的 browser filter/box-shadow 不会部署成浏览器 CSS。

## 验证范围

实机 1280×720：两种训练布局、开始与等待、完成与满额递补、英雄/建筑、存档44个真实条目及 tooltip、每日奖励、奖池详情与空记录。

组件预览四种分辨率：40个状态/窗口案例；另16个 A/B 成本边界案例及训练事件、禁用保护、属性更新保留队列、满额递补、研究当前/中间项取消事件。预览使用真实生产 JS/XML/CSS、1080 UI 坐标缩放和显式样例；ScenePanel/技能节点为替代节点，原生缩字以省略近似。

原生 `mat_setvideomode` 不支持，较高分辨率请求的实际图片仍是720p，已在 native/captures.json标记为未通过。满队列/不同类型/研究取消实机状态没有通过篡改服务器数据来制造。伐木工原逻辑没有逐项取消接口，保持不可取消；研究既有取消事件、退款与顺序不变。未运行 Lua 单测；未领取奖励、抽奖或接入真实支付。

## 重跑与恢复

从项目根目录运行：

```powershell
node tools/ui_20h/dependencies.cjs
node tools/ui_20h/preview.cjs
node tools/ui_20h/qa.cjs
node tools/ui_20h/actions-qa.cjs
node tools/ui_20h/audit.cjs
node tools/ui_20h/checkpoint.cjs verify best
& tools/ui_20h/restore.ps1 -Version best
# 先看替换清单，再明确执行：
& tools/ui_20h/restore.ps1 -Version best -Apply
& tools/ui_20h/compile.ps1
```

`baseline_full` 可恢复初始已提交 UI；新模块会保留在磁盘，但原布局不引用它们，不参与旧界面。恢复脚本不删除文件；检测到后续编辑会停止，必须审阅后才可明确使用 `-AllowChanged`。检查点按 SHA 对象去重，四组最终冻结清单都指向同一完整最佳版，避免单独恢复共享 CSS 造成不一致。这些最终组冻结不是历史捕获时刻的源码快照；旧候选原图与1–3变量配方仍保留。

原生编译会先备份外部 Workshop content 中的不同源文件，再编译当前 XML 引用链。临时 Tools observer 的源和运行文件已还原；已有原工程诊断命令未改。游戏重开后载入本轮编译资源；预算中断恢复可从上述 audit 命令开始，无需重做候选。


资源补齐另已提交并推送 `2a190652` 到 origin/dev：74组现有 PNG/纹理定义及对应编译资源，使用 art/ui/sources 为唯一新资源提交路径，避免 NTFS junction 重复收集。恢复了所有本轮UI改动，保留原18条stash。

重建奖励资源：先运行 `& tools/ui_20h/compile-assets.ps1`，再运行 `& tools/ui_20h/compile.ps1`。原生纹理输入 PNG 没有修改；vtex 使用项目规定的 LF，已逐个编译74个定义。

## 追加十轮的当前版本

当前入口为 `archive_180de7e38b_titles_compact_v6.js`，来自 content 合并167407a2，保留称号/VIP与原事件。Jade样式放在该XML样式链末尾，组件装饰脚本在控制器之前加载。不要恢复整套旧入口覆盖称号能力。

最终训练保留分行成本，普通256、双币278单位高。工人仍无逐项取消API；研究悬停取消与退款规则不变。底部HUD几何、Lua、CSV和地图未改。本次没有支付、抽奖或领取奖励。

最终组装图为真实控制器/组件预览；真实720p44条存档照片摄于最后兼容修正之前。客户端随后要求更新，重载后0玩家，未将最后行高/成本宿主/称号图层修正以及R08训练状态计作实机通过。Steam更新完成后，通过原有组队开始、模式、难度确认流程进入本地Tools地图，再验证这些状态。

恢复与继续：

```powershell
node tools/ui_20h/checkpoint.cjs verify best
node tools/ui_20h/preview.cjs
node tools/ui_20h/qa.cjs
node tools/ui_20h/actions-qa.cjs
node tools/ui_20h/feedback-category-qa.cjs
node tools/ui_20h/audit.cjs
& tools/ui_20h/restore.ps1 -Version best
# 检查替换列表后恢复：
& tools/ui_20h/restore.ps1 -Version best -Apply
& tools/ui_20h/feedback-compile.ps1
```

四个当前任务源由feedback-compile.ps1编译，先备份，再写入对应content位置，不覆盖称号XML或其他上游功能。所有101个依赖的源和运行资源均在best检查点；按整套检查点恢复，避免共享组件与入口分离。原29轮交付页面及manifest存于previous_v029.html和work/feedback10/baseline。逐轮源码在R01–R10/source，最终一致版本另见best。

临时native-probe已恢复，不需要它运行游戏。若再次安装以截图，必须在结束时执行 `& tools/ui_20h/native-probe.ps1 restore`；重复安装前先恢复，避免备份中套入观察器。15项同步恢复计划带哈希并保留源备份，不能用它覆盖后续用户编辑。
