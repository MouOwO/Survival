# 宝箱抽卡演出第一版 · 2026-09-29

已制作并接入四种主题，每段 7 秒、1280×720、30fps，使用原创立体声音轨。

| 宝箱 | 主题与表现 |
| --- | --- |
| 地图 | 星门缓开、天象宝库、星轨汇聚 |
| 修仙 | 金门开启、云海仙宫、金龙浮现与掠过 |
| 龙脊 | 龙骨大殿、熔火祭坛、火星汇聚 |
| 暑期 | 海底宫殿、明珠、水光与气泡 |

## 查看

[打开四主题预览](../output/lottery_cinematic_20260929/preview.html)。点击播放可听音效，四个按钮切换主题。

## 参考分析

已读取用户“视频”目录的六段视频，并提取联系表与音轨：原神、幻塔、卡牌游戏抽奖、诛仙世界、逆水寒 (2)、逆水寒。分别参考了蓄力与稀有度揭晓、机械门与镜头推进、卡牌翻转、云海飞龙、法阵与多奖励揭晓、兽门缓开与亮光爆发。

当前工具未能直接试听参考音轨；音效设计依据画面落点与音轨强弱包络分析，使用原创合成声音，没有截取参考游戏的音效。原始音轨、抽帧图、声强数据保存在 output/lottery_cinematic_20260929。

## 制作方式与素材

本版为分层原画、镜头缩放、门体分离、龙身分段运动、粒子与光效合成的 2.5D 演出，非实时 3D 场景。六张原画由内置 imagegen 生成。

[完整生成提示词与素材路径](../output/lottery_cinematic_20260929/promptset.json)

- 原画：panorama/src/images/custom_game/lottery_cinematic_v1/{gate,dragon,map,cultivation,dragon_knight,summer}.png
- 游戏影片：panorama/videos/custom_game/lottery_cinematic_v1/{map,cultivation,dragon_knight,summer}.webm
- 可分享预览：output/lottery_cinematic_20260929/previews/*.mp4
- 渲染：tools/lottery_cinematic_compositor.cjs、tools/render_lottery_cinematics.cjs
- 音轨：tools/build_lottery_cinematic_audio.py

## 接入行为

影片在服务器返回成功抽取结果后播放，随后揭晓真实奖励。按用户最新要求改为全屏场景与全屏演出，等比例铺满并自适应窗口尺寸。十连结果采用无卡片底板的 5×2 排列，四个奖池分别使用原画铺底。勾选跳过动画会直接展示结果；演出中的跳过按钮立即显示奖励；关闭窗口会停止声音和动画。没有调整价格、概率、奖池、物品发放或支付逻辑。

## 验证与边界

- 四段 WebM 完整解码通过，均含立体声 Vorbis 音轨。
- 新增脚本、样式和 HUD 布局已编译，四段影片与内容目录副本哈希一致。
- lottery_cinematic.test.cjs、lottery_cinematic_flow.test.cjs、test_lottery_updates.cjs、reference_windows.test.cjs 已通过。
- 覆盖跳过、取消、旧计时器隔离、解码 API 抛错回退、重复抽取按钮保护、真实奖励展示等流程。
- 本轮结束时 Dota 2 未运行，尚未核验引擎内实际视频解码、音量与帧率；需新开测试对局检查。浏览器预览用于评估影片本身。

## 全屏更新验证

新增 lottery_fullscreen_v2.css；背景与影片直接附着视口，交互控件保留 1600×900 安全区域，并随分辨率缩放。验证 720p、1080p、1440p、21:9、4:3 及竖屏的影片覆盖与比例保持，验证切换奖池的场景互斥、5×2 奖励布局及跳过/关闭流程。四段影片重新导出，移除了原有固定黑边。
