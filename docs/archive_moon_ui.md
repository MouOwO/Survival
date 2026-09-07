# 蓝银月光存档主题

当前主题替换上一版哥特视觉，继续使用 `archive_gothic.css` 的加载入口，避免改变脚本与清单协议。
素材位于 `panorama/src/images/custom_game/archive_moon/`：

- `window.png`：1402×1122；顶部外侧透明，保留银色框、月亮、瀑布和蓝色废墟。
- `tab.png`：2172×724；银色普通态，外侧透明。
- `tab_selected.png`：2172×724；金色选中态，左侧蓝色宝石，外侧透明。

窗口为 1180×960 逻辑尺寸。分类按钮 184×64，直接以 100% 背景尺寸显示，选中时切换贴图，不绘制额外矩形边框或阴影。保留现有全部分类、升级、抽奖及信仰值逻辑。

使用内置 image_gen 编辑用户附件并导出素材；未使用 CLI。导出后检查 PNG 格式与外侧/内部 alpha。部分生成版本将棋盘格写入 RGB，未接入这些版本。采用的窗口版本具备真实 alpha，但顶部轮廓仍有少量杂边，需要进一步美术清理；尚未完成游戏内视觉验收。

最终使用的提示词：

窗口：Make the background transparent. Cut out this blue window interface from its checkerboard background. Return a transparent-background PNG sticker of the entire window. The small white and gray checks ABOVE the window and its top moon crest must disappear into real alpha transparency. Preserve opaque blue panel interior. Do not simulate transparency. Keep original layout and size.

银色按钮：Edit the user's NEW BLUE SILVER single unselected button asset (horizontal silver beveled octagonal border with blue stone interior, checkerboard exterior). Ignore the unrelated treasure reward screenshot and old gothic style. Extract ONLY that exact silver button as an individual transparent PNG: remove all checkerboard/outside pixels to true alpha=0. Preserve silver frame and blue textured interior precisely. Tight canvas around button, width 1536 height512, button occupies 98% width and 94% height, only 1-3% transparent margin, NO large padding. No text, no additional symbols, no gold, no redesign. Actual RGBA transparency, never draw a checkerboard. This is the normal state of a UI tab.

金色按钮：Background removal: turn the white/gray checkerboard OUTSIDE this blue-and-gold UI button into actual alpha-zero transparent pixels. Output real RGBA PNG with a transparent background, NOT a checkerboard painting. Preserve every part of blue stone, gold frame and blue diamond on left; keep same 2172x724 canvas and exact positions and sizes. No redesign, no zoom, no crop, no text. All exterior must have alpha=0, interior opaque. Transparent PNG cutout.

部署：`powershell -NoProfile -ExecutionPolicy Bypass -File tools/deploy_archive_panorama.ps1`。
回归：`node tools/test_archive_gothic_ui.js`。
