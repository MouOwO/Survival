# 地图抽奖UI 第三版：原图裁片、透明小图标与高亮状态

## 这版与前两版的区别

唯一裁切来源为05_reference/source.png，即本次指定的1672×941原图。01_exact_crops中的49张PNG按源图坐标直接裁出，没有重绘、缩放或改变源像素。原图截图是合成图，因此这些原始裁片自带截图背景；它们不等于独立透明组件。

02_rgba_icons 提供8个小图形的原图轮廓提取，每个包括normal、hover、pressed、disabled，共32张真正RGBA PNG。提取时估算背景并归一前景颜色，所以轮廓与边缘为近似提取，不是无损抠图。每个四周增加8px透明边距，详见manifest.json。

03_states 提供24种透明PNG状态及同名SVG源码：按钮白/金各四状态、票券四状态、勾选框四状态、卡边框四状态、卡选中框、页签选中线、页签悬停线、入口悬停线。这些是原图未完整展示时补做的同风格状态，不声称来自截图直接裁切。按钮为相同几何的无字底板；原图按钮细致材质以原始裁片参考，补做版本不能视为逐像素复刻。

04_slices 提供卡框8块边角切片及一个底色样本，可按12px边缘组合使用。边角保留原尺寸，边条仅沿对应方向延展；截图边缘带有原背景，不适合任意底色直接拼接，需在目标浅色卡底验收。

06_supplement/panel_blank_reconstructed.png 是用imagegen补做的无字面板底板。它是重建稿，比例和纹理可能与源图不同，不得拿它覆盖原图测量基准。

component_preview.png 是透明小图标和主要高亮状态的对照预览。

## 精确对应：小入口不再遗漏

| 界面位置 | 原图裁片 | 实装优先资源 |
|---|---|---|
| 奖池详情（用户所说的奖池记录） | pool_details_icon / pool_details_entry | 02_rgba_icons/pool_details_icon_状态.png |
| 抽奖记录 | history_icon / history_entry | 02_rgba_icons/history_icon_状态.png |
| 奖池弹窗关闭 | modal_close | 02_rgba_icons/modal_close_状态.png |
| 主界面关闭 | screen_close | 02_rgba_icons/screen_close_状态.png |
| 票券余额旁加号 | currency_plus | 02_rgba_icons/currency_plus_状态.png |
| 跳过动画未勾选 | skip_checkbox / skip_entry | 02_rgba_icons/skip_checkbox_状态.png |
| 跳过动画已勾选 | 原图没有展示 | 03_states/checkbox_checked_状态.png；对齐相同内容区域 |
| 单抽票券、十连票券、余额票券 | single_ticket / ten_ticket / currency_ticket | 03_states/ticket_状态.png，统一轮廓 |
| 单抽白按钮 | single_button | 03_states/button_ivory_状态.png + 独立票券 + 独立文字 |
| 十连金按钮 | ten_button | 03_states/button_gold_状态.png + 独立票券 + 独立文字 |
| 页签选中金线、菱形 | pool_tab_gold_line / pool_tab_diamond | 03_states/tab_selected_overlay.png |
| 页签悬停 | 原图没有展示 | 03_states/tab_hover_overlay.png |
| 奖励卡普通、悬停、按下、禁用 | card_cell | 03_states/card_outline_状态.png叠加实际奖励卡 |
| 奖励卡选中 | 此原图未明确展示独立选中卡样式 | 03_states/card_outline_selected.png |
| 奖池详情/抽奖记录入口悬停 | 原图没有展示 | 03_states/entry_hover_underline.png + 图标hover |
| 面板标题两侧装饰 | title_ornament_left/right | 02_rgba_icons/title_ornament_left/right_状态.png |
| 滚动轨道和滑块 | scroll_track / scroll_thumb | 原尺寸参考，控件代码绘制或按目标底色切片 |
| 保底说明条 | guarantee_pill | 原图文字已烘焙；正式文字独立，不能把SR画死 |
| 购买/首充入口 | purchase_link / promotion_link | 该原图是文字链接，无独立礼盒图标；保留文字控件，不凭空换进旧按钮 |

源图内顶部标识、公告、各页签、规则、文字说明和完整弹窗也已单独裁出，见manifest.json。四个legacy_sidebar裁片仅为完整存档，enabled=false；用户已删除该导航，严禁恢复。

## 显示尺寸：不要直接把带边距尺寸当图形大小

举例：pool_details_icon原始矩形32×39；透明版48×55，四周各8px。需要图形显示32×39时，透明图片控件应48×55，图形原点相对控件偏移8px。所有坐标、宽高应在同一个设计坐标系中计算，再整体缩放。

无字按钮设计尺寸312×72；页签高亮层201×24；卡边框167×157；票券48×48。不要给每个元素独立拉伸。未勾选与已勾选图片画布不同，必须按内容框对齐，而不是按文件左上角直接替换。

高亮只换状态资源与轻微过渡，不移动布局、不重复叠加原图已有金线。建议normal→hover 100ms，pressed 60ms，disabled禁止交互。状态PNG是视觉状态，不包含业务逻辑或光效动画。

## 必须知道的原图限制

- 原图是奖池弹窗已打开的截图，背景主界面的部分组件受到遮罩影响。直接裁片保留的是此亮度，不能冒充无遮挡正常状态。
- 原图没有按下、禁用、勾选、加载的完整截图，所以这些无法“无损裁出”。包内补做状态已与原图裁片分开。
- 顶部装饰/图标和卡框不全是同一种形状，不能全部用一个通用星形替代。
- 抽取按钮上的文字和票券已画在原图。raw按钮适合定位比对，不适合动态改字；无字状态底板是单独实现方案。
- 此原图包含旧麒麟背景和已取消侧栏，只用来提取组件。当前主界面仍以用户批准的宝箱背景、无侧栏布局为准。

## 给开发AI的完整替换指令

请使用第三版包，先读取本说明及manifest.json，再替换地图抽奖模块的小图标、按钮和高亮状态。

这次必须逐项实现奖池详情、抽奖记录、主界面/弹窗关闭、余额加号、票券、跳过复选框、单抽、十连、页签选中线、入口悬停线和卡片选中框。不能只替换大背景或按钮底色，不能继续引用旧紫色票券、旧功能图标、emoji或字体符号。

01_exact_crops是原图定位与外观基准，带背景且部分带字；02_rgba_icons才是透明小图标；03_states是无字按钮及补做状态。四状态资源必须一起更新，不能normal用了新图而hover/disabled回退旧图。检查布局文件、样式、脚本和动态控件的全部引用。

保留四池所有原抽奖数据和规则。标题、数字、名称、概率及状态文字由项目数据和代码显示。物品图片继续使用真实奖励资源，不用通用星形替代。奖池详情作为弹窗，打开时禁止穿透点击底层抽奖按钮。

以源图坐标为测量基准，根据manifest的native_size和padding定位，不把PNG透明边距误算成图标本体。弹窗统一等比缩放，固定标题/页签/底栏，奖励列表独立滚动。卡框边角不拉伸。

先做一个组件状态展示页，逐个展示normal/hover/pressed/disabled以及checked/selected。分别在浅底、深青底和游戏背景检查图标、边框和高亮。资源缺失或渲染失败必须修复并说明，不能以黑方块、黑圆点或其他旧图兜底。

对原图裁片与实现做同尺寸叠加对比。补做状态允许与原图未展示状态不同，但不得改变原有排版尺寸。交付替换前后截图、资源引用清单、状态图和运行验证。不得宣称本包素材已经在游戏里验证过。
