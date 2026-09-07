# 存档界面：暗黑哥特主题

参考：本次会话用户提供的存档界面图。整体为旧铜铁框、青黑城堡、侧边旗帜、暖金文字。

实现入口：`panorama/src/layout/custom_game/archive.xml`；主题：`panorama/src/styles/custom_game/archive_gothic.css`。
源图片在 `panorama/src/images/custom_game/archive_gothic/`，编译贴图在 `panorama/images/custom_game/archive_gothic/`。

窗口按 1320×880 Panorama 逻辑尺寸排布。背景图与窗口保持 3:2 比例；标题和侧栏、内容区对齐底图预留位置。
侧栏保留全部服务端分类并支持滚动，物品列表支持滚动。所有文字、数值、物品和交互均为实时控件。
建筑图标按现有 `building_01` 至 `building_09` 对应实际物品，不改变 CSV 名称、价格、等级、效果或服务器协议。
新增未映射建筑使用原有字符图标兜底。满级建筑显示金框，未激活建筑图标置灰。

运行 `node tools/test_archive_gothic_ui.js` 可复用现有存档测试并验证图标、满级/未激活状态、零余额和切页清理。
运行 `powershell -NoProfile -ExecutionPolicy Bypass -File tools/deploy_archive_panorama.ps1` 同步 content 源文件并编译。
部署脚本在检查模式下不写文件：添加 `-CheckOnly`。

验收：游戏内打开存档，检查分类滚动、卡片提示、建筑激活/升级、满级状态、信仰值刷新和社交抽奖栏；在不同画面比例下检查窗口边缘。
自动化脚本验证数据与交互，资源编译器验证资源编译；这些不代替游戏内视觉验收。

## 素材生成记录

窗口外围去黑边：`window.png` 已用内置 image_gen 改为带 alpha 的 PNG，窗口样式移除底色和矩形阴影。画布仍为 1536×1024，金属装饰和城堡内容保留。透明通道抽检确认外角、顶部及底部为 alpha 0。

窗口透明化最终提示词：Background removal / transparent PNG cutout required. Remove the visible white and gray checkerboard pixels surrounding this game UI frame and replace them with REAL RGBA alpha transparency (alpha=0). The input erroneously has checkerboard painted as RGB. Do NOT paint any new checkerboard, black, white or other background. Output must have an actual transparent alpha channel like a sticker PNG. Keep all dark castle interior, wood sidebar, candle, metal frame and title plaque opaque, unmodified and in precisely the same position. Keep 1536x1024 size. Remove ONLY checkerboard outside and in the narrow gap below top crossbar. No redraw, no text, no new objects. Transparent background.

使用内置 image_gen 工具。未使用 API/CLI。两张图片单独生成，未从完整 UI 图中切割。
按钮图片的上下留白由主题的背景缩放与居中处理，不修改原始图片。

后续修正：使用内置 image_gen 将 `tab.png` 外侧改为真实透明背景，保留内部深色石面。
分类按钮去除矩形背景、边框和阴影；悬停与选中使用图片自身的 brightness 和文字颜色。

透明化提示词：Use case: background-extraction. Edit this existing game UI nameplate asset. Remove ONLY the near-black exterior background OUTSIDE the outer bronze metal silhouette and replace it with genuine alpha transparency. Preserve the opaque dark stone INSIDE the metal frame, all metal edges, gold diamond on left, original colors and details. Keep exactly the same canvas aspect ratio and object position/size: plate spans roughly x1%-99%, y25%-75%, do not zoom, do not crop, do not redraw or change its design. Exterior top/bottom and corner areas must be truly transparent alpha zero, not a checkerboard drawn into pixels, not black. No shadow or glow outside silhouette. No text. Production transparent PNG cutout.

### window.png：最终提示词

Use case: style-transfer. Asset type: production game UI background skin, ONE image, landscape 1536x1024. Use the user's attached archive UI solely as a visual style reference. Create an EMPTY dark gothic fantasy archive window skin with weathered bronze and black iron architectural border, restrained antique gold edges, tiny cyan diamond at top center and bottom center, black stone title plaque centered along top, deep blue-green misty ruined gothic castle in bottom-right of interior and a candle on far bottom-left. Flat front-facing orthographic UI artwork, high craft material detail like the reference. Exact layout: outer thin ornate frame occupies outer 3 percent; top header occupies y=0..14 percent with blank centered plaque x=34..66 percent; left sidebar x=3..19 percent y=15..94 percent has dark wood and a faded teal hanging banner lower down, EMPTY with NO buttons; main inner recessed panel x=20..97 percent y=15..94 percent, its upper 55 percent nearly black low contrast empty space for live item cards, castle concentrated lower right with subtle teal haze. Very dark unobtrusive background for readability. All interior surfaces opaque. NO text, NO letters, NO numbers, NO icons, NO item cards, NO buttons, NO fake interface controls, NO watermark. This asset will be stretched as one background behind real interactive controls; do not draw any grid. Match reference ornate medieval bronze/iron style closely, not modern clean sci-fi.

### tab.png：最终提示词

Use case: stylized-concept. Asset type: one reusable game UI button background. Generate a single horizontal medieval gothic dark iron nameplate, 1536x512 aspect 3:1. Centered full button occupying 96 percent width 86 percent height, angular clipped pointed ends, thin layered weathered antique bronze bevels, subtle scratches, almost black charcoal stone inset, a small faceted antique gold diamond at left end, tiny engraved corners. Front facing flat orthographic. Premium dark fantasy RTS interface art, realistic hand painted metal, subdued warm gold edges, dark teal-black inset. Interior 75 percent completely empty for live text. Background solid near-black #080d0f, no shadow beyond edges. NO text, NO runes, NO letters, NO symbols in center, NO gems, NO glow, NO multiple variants or sprite sheet. This is an individual UI asset, no scenery.
