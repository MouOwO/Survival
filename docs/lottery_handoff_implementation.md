# 地图抽奖拆分包接入（2026-09-07）

## 交付与运行

- 组件入口：`output/lottery_handoff_preview/index.html`，直接浏览器打开。包含按钮五态、十个 SVG 图标、卡背、奖励卡、长名称和奖池滚动弹窗。
- 同目录的 `components.png`、`home.png`、`pool.png`、`single.png`、`ten.png` 是浏览器预览截图。`single-preview.webm`、`ten-preview.webm` 是浏览器真实帧采集编码的预览录屏，**不是 Dota 游戏内录屏**。
- 原生实现：`panorama/src/layout/custom_game/lottery_window.xml`、`panorama/src/styles/custom_game/lottery_celestial.css`、`panorama/src/scripts/custom_game/lottery_ui.js`。
- 共用层级管理：`panorama/src/scripts/custom_game/ui_layers.js`，公开 `SurvivalUILayers.Open/Close/CloseTop/Top`。抽奖全屏窗使用 100000 起始层级（高于现有 32767 的 HUD 代理），提升祖先链，栈弹出时恢复之前的 zIndex；详情弹窗压入第二层。无需重挂节点，避免打断现有 ID 查询和回调上下文。Escape 关闭栈顶。当前只接入抽奖系统，其他窗口可逐步注册。
- `tools/deploy_lottery_panorama.ps1` 同步本地 content 源码、备份 HUD、只替换抽奖布局片段并编译。本轮属于用户明确授权的本地游戏接入，不包含发布 Workshop。

## 组件及动画

采用包内 scene_clean 静态场景、独立 card_back/card_front/pool_panel 纹理；遮罩、页签、品质边、文字和数量由代码叠加。按钮使用包内同轮廓 button_ivory/button_gold SVG。纹理是明确的不透明 RGB 背景，SVG 形状外无绘制内容，未使用带棋盘格的假透明图，也未对黑色纹理进行统一抠色。

SVG 按钮与关闭图标已由 Dota resourcecompiler 成功编译。正常、悬停、按下、不足/锁定、请求中状态使用同一几何。点击已揭晓卡片打开可滚动完整属性。品质颜色直接复用 `SurvivalRewardPresentation.NameColor`，数量默认 1 对应当前服务端每个结果一次授予，不从画面猜测。重复结果保留独立卡片，不擅加“新获得”标志。

结果成功返回后才启动动画；单抽约 2 秒、十连约 2.8 秒，十连两行五列。参数集中在 lottery_ui.js 的 motion 中，对齐包内 animation_spec.json。固定背景，汇光、卡背浮现、水平缩窄后换面；不播放不同宝箱图片交叉淡入。跳过取消延迟任务并立即去掉全部卡背与缩窄/入场状态，确认只关闭结果，只有再抽发送新请求。保留此前移除 locale 时间格式化调用的崩溃规避。

## 真实业务核对

四池 ID 为 map、cultivation、dragon_knight、summer。名称、余额、保底、奖励、消耗读取原快照；服务器配置目前均为单抽 1、十连 10。地图池十连保底 SR，特殊池十连至少 UR。三个特殊池共用奖品是现有配置，不在客户端人为拆分或复制。切池立即清空旧内容、锁定抽奖，拒绝其他池迟到快照。

现有服务端未提供条件免费、每日抽取限制、购买支付、首充权益和跨局历史接口，入口保留为明确的未开放提示。若服务端返回实际 single_cost=0，客户端正确显示免费且不因余额为零禁止点击；不依据尚不存在的 free_eligible 字段绕过扣券规则。历史保留本局最近 30 次，不伪造持久化记录。请求结果未知时维持锁定，关闭重开不自动重抽；跨客户端重连恢复结果的权威接口仍缺失。

## 验证与未完成项

`node tools/test_lottery_ui.js` 覆盖四池、旧快照、零消耗、余额不足、双击锁、单抽/十连时序、跳过/关闭、确认不发请求、重复响应、历史与层级恢复。`output/lottery_handoff_preview/verify.cjs` 使用本机 Chrome 检查并截图、录制；道具名称和属性来自 CSV，浏览器原生物品图标以明确占位显示，游戏复用 DOTAItemImage。

- 字体：本机未找到思源字体；浏览器实际检测标题为 SimSun，正文为 Microsoft YaHei，记录于 `fonts.json`。代码按要求优先声明思源宋体/黑体，但**尚未实现指定字体在游戏中真实加载**，需补充可供 Panorama 使用的字体资源与字体注册管线。
- 没有同模型/同分层的箱盖素材，真实箱盖开合未完成；无新音频素材，未添加来源不明音效。
- 当前没有可操控的 Dota 实测/录屏工具会话，游戏内全屏遮挡、鼠标命中、原生翻面帧、字体与缩放透明边缘尚需实测；浏览器截图不能替代原生验收，也不能据编译成功宣称原生崩溃已排除。
- 浏览器预览与 Panorama 分别实现展示层，动画节奏一致但不是像素等价的运行环境。购买/首充/恢复结果等缺失接口不在本轮编造。

额外检查：原有 `tools/test_lottery_config_contract.ps1` 在 PowerShell 7 下执行，失败于 `each map level must grant 1% wall health`，属于现有业务配置契约，未为让 UI 检查通过而修改其断言或数值。PowerShell 5.1 读取无 BOM 中文脚本还有编码解析问题。
