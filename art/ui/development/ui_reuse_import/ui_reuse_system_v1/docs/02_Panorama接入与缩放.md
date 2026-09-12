# Panorama 接入与缩放

## 可行性与Unity对应

用户提出的组件复用方向可以用于Dota 2自定义UI。Panorama提供面板布局、样式和JavaScript接口，文档列有BLoadLayoutSnippet等布局片段接口；可据此组织共享组件，不必为每个页面复制整套XML。使用项目已有封装时优先沿用，不强行换框架。[Panorama概览](https://developer.valvesoftware.com/wiki/Panorama/Overview)、[面板API](https://developer.valvesoftware.com/wiki/Panorama/Overview/Javascript/API)

|Unity中的组织概念|本项目的Panorama组织方式|
|---|---|
|可复用预制体|共享布局文件/布局片段及组件创建封装|
|统一样式|共享样式文件与主题参数|
|Sprite资源引用|资源ID解析到同一个项目图片路径|
|Sliced边框|验证过的border-image配置或显式分角/边面板|
|Canvas与缩放|Panorama逻辑坐标、根面板与引擎自动缩放|
|事件/数据绑定|项目现有JavaScript与游戏业务接口|

以上是组织方式类比，不表示Unity组件或浏览器代码可直接搬进Dota。[Unity Canvas Scaler](https://docs.unity3d.com/Packages/com.unity.ugui@1.0/manual/script-CanvasScaler.html)

## 实施结构

建议将布局、样式、脚本分为common和pages两层，图片集中在一处shared目录。resource_registry.json中的ID稳定不变；工程接入时只在资源解析层将相对文件路径转换为项目支持的资源路径。不要把本包相对路径直接当成已验证的Panorama运行路径。

common维护：ModalManager、ModalShell、FullscreenShell、IconButton、ActionButton、TabBar、NavToggle、CardShell、Tooltip、状态处理。

pages维护：存档字段绑定、商城商品与价格、抽奖池与服务端结果、肉鸽候选与结算。组件应接收数据，不能自行生成业务概率或奖励。

列表可用流式布局并让内容区域独立滚动，固定标题栏与底栏。默认流式排列由flow-children等属性组织，具体规则按项目调试器确认。[Panorama Flow Layouts](https://developer.valvesoftware.com/wiki/Panorama/Overview/Layout)

## 缩放必须只处理一次

既有截图大多为1672×941，这是源图测量空间，不是自动等同于游戏运行逻辑坐标。Panorama布局文档描述了基于1080高度的自动缩放；项目根节点或自定义样式可能再施加缩放，应先在调试器确认现状。

若项目采用1080逻辑设计高度，可把旧源坐标换算为：逻辑坐标=源坐标×1080/941，约乘1.147715。这个换算只作用于布局数据，PNG文件不因此批量放大。1672源宽对应约1919.4逻辑宽，剩余微小误差通过居中与锚点处理。

例如1002×758的存档源框对应约1150×870的逻辑框。引擎已经按屏幕高度缩放后，不要再在每个组件乘一次“当前屏幕高度/1080”，否则会二次放大。

宽屏适配：弹窗限制最大宽度并居中；全屏背景可保持比例裁切，导航和底栏锚定安全区；顶部HUD、右侧榜单和底部操作区分别锚定。不能把整体界面在X、Y方向独立拉伸来填满屏幕。

SetNativeSize类思路只能让图片回到其资源尺寸，不能解决父级缩放、透明留白、锚点、文本或整体布局问题。Unity同样需要参考分辨率与Canvas布局控制，不能仅靠原生尺寸完成适配。

## 九宫格与黑边

Panorama CSS文档列出border-image-slice及相关边框属性，具有九区域切片概念。具体语法、图像导入与渲染需在当前Workshop Tools中验证；本次未提供未验证的硬编码slice数值。[Panorama CSS Properties](https://developer.valvesoftware.com/wiki/Panorama/Overview/CSS_Properties)

现有02_frames边缘裁片带有邻接场景像素，不能直接宣称是干净九宫格。先对选定窗口母版一次性精修出干净边框，再记录四边切片内距、最小尺寸与内容内边距。若引擎border-image效果与预期不符，可以用固定四角、四条边和中部填充分面板组合，仍然只维护一套纹理。

透明边缘检查需在深、浅背景各做一次。不要填黑RGB背景冒充透明，不要把预览棋盘格导入游戏。导入后的过滤、缩放和可能的图集边缘外扩也需在真实运行环境检查，不能只看PNG alpha存在就宣称没有黑边。

## 生命周期与事件

ModalManager维护层级、打开/关闭与遮罩策略。遮罩在窗口后方，窗口内交互不触发外部关闭；嵌套确认框只关闭最上层，避免穿透到底层购买或抽奖按钮。重复打开页面应更新或聚焦，避免重复订阅。

关闭时取消延时任务、动画回调与页面订阅。组件可以按需缓存，但不能假设隐藏的面板不耗内存；大主题背景和长期不用的页面按实际运行情况卸载。共用图片路径通常有利于避免重复维护，但实际纹理缓存、显存与绘制开销需运行测量，不能用旧包去重字节数代替。

本次依据上述官方开发文档的可检索内容核对能力范围；部分网页直连返回403，因此未据此宣称所有API细节已在当前引擎验证。本包的资源引用与哈希已验证，Panorama导入、运行布局、输入行为还需项目侧执行。
