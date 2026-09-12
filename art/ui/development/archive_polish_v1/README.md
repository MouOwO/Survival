# 存档图标与九宫格整理 / 2026-09-12

本轮沿用隔离测试地图 `survival_ui_handoff_v1`，当前构建 **d78a04addb**。新源图、CSV 和接入代码已保存到当前工程；正式 `survival` 编译 UI 没有覆盖。此前已确认的布局、奖励条件、价格、属性和发奖逻辑保留。

## 图标与表格

- 生成 **18 张**透明物品图：通关 / 无尽共用 1 张成就徽章，上班福利 17 张主题图。
- 通关 44 项、无尽 50 项均引用同一张 `achievement_shared.png`。34 项上班福利按配置名称对应 17 个主题；同名或同主题的后续等级复用同图。
- 新增 128 条条目映射，物品映射表目前共 463 条。此前 335 条映射保留。共用徽章只编译一组小 / 常规纹理，不为 94 条存档重复占用纹理。
- 18 张母图实际均为 **1254×1254 RGBA**，Alpha 范围 0–255。卡片继续使用 93×74 设计区域内等比显示；构建器生成带 mipmap 的 64 / 256 上限 BGRA8888 纹理。
- 新增 7 个原生 SVG 导航轮廓：通关奖杯、无尽环、地图、工作包、鱼、建筑、BOSS。修复 SVG 分组样式在原生管线不继承造成的黑色实心块。全部选中导航统一黑色图案，未选中为金色；其他已有分类继续使用自己的原图。

[图标对照页](gallery.html)仅用于检查源图和配色；不是游戏内截图。

| 文件 | 用途 |
| --- | --- |
| [archive_item_icons.csv](../../data/csv/存档系统/archive_item_icons.csv) | 按 category / source_key / item_id 更换物品图，不修改业务表 |
| [archive_navigation_icons.csv](../../data/csv/存档系统/archive_navigation_icons.csv) | 7 个导航图标的名称、路径与设计尺寸 |
| [源图目录](../../panorama/src/images/custom_game/archive_polish_v1/) | 18 张 PNG 与 nav 下的 7 张 SVG |
| [work_themes.json](work_themes.json) | 34 个 work ID 对应 17 张图 |
| [prompts.json](prompts.json) / [art_audit.json](art_audit.json) | 原始生成描述、真实尺寸、Alpha 和 SHA256 |

换图后运行 `map_art.py` 和 `node art/ui/development/remaining_ui_handoff_v1/prepare.cjs` 验证表格及生成资源。导航通过 `node art/ui/development/archive_polish_v1/create_nav.cjs` 重建，脚本自动展开每个 SVG 图元的绘制属性，重复运行不会叠加属性。运行 `gallery.cjs` 更新对照页。

## 九宫格审计与修改

`nine_slice.js` / `nine_slice.css` 提供一个公共组件：原图九个 UV 区域，固定四角、仅拉长四边的对应轴、中心填充。包括左右 / 上下不对称边距的准确采样。素材原文件不重新生成、不横纵拉伸边角。每个装饰节点禁止鼠标命中，无刷新轮询。

| 检查对象 | 处理 |
| --- | --- |
| 存档选中 Toggle | 209×54 原图，左右 31、上下 18 固定边角 |
| 存档筛选按钮 | 111×31，左右 16、上下 10 |
| 存档普通 / 悬停卡片 | 143×138，左 29、上 33、右下 12；普通、高度不同的福利 / 碎片卡共用 |
| 存档抽取 / 升级按钮 | 使用公共四状态按钮；按 142×36 / 88×29 小尺寸配置固定边角 |
| 公共确认 / 返回 / 购买 / 结果按钮 | 普通、悬停、按下、禁用均为九宫格；保留常驻底图，避免离开悬停时瞬间空白 |
| 抽奖单抽 / 十连 | 原确认素材 312×72，四角 36×24；图标与文字独立上层显示 |
| 奖池 / 记录页签 | 保留首、中、尾原图端头；九宫格底板，原选中光晕继续独立显示 |
| 奖池奖励卡 | 170×155，14 像素固定边角 |
| 每日奖励普通 / 第七天卡框 | 各自原图，18 像素边角；奖励内容与状态独立 |
| 商城单品 / 礼包 / 支付方式 / 二维码外框 | 通过公共图片工厂改为对应的九宫格配置；二维码内容本身不处理 |
| 公共窗口外框 | 原来已是九块分片，保留；不重复缩放 |
| 存档固定设计的主框、肉鸽卡面、物品插画、功能图标、徽记 | 保持原设计比例或等比显示；插画不作为可伸缩边框，不做九宫格切图 |

同时保留悬停星饰的上层裁片，设置卡名父容器层级，避免新卡框盖住文字。侧栏分隔线仍跟随各 Toggle 滚动。

## 实机检查

Dota Tools 隔离地图，客户端 **1768×992**。以下都是实际游戏截图，未用静态预览替代。

| 状态 | 证据 |
| --- | --- |
| 通关统一徽章、黑色选中奖杯 | [最终通关](../remaining_ui_handoff_v1/evidence/polish_final_clear.png) |
| 无尽同一徽章、实际进度 | [无尽](../remaining_ui_handoff_v1/evidence/polish_art_endless.png) |
| 上班福利新图、真实名称及消耗 | [最终首屏](../remaining_ui_handoff_v1/evidence/polish_final_work.png) / [滚动](../remaining_ui_handoff_v1/evidence/polish_work_scroll.png) |
| 悬停星饰在图片上层、真实 Tooltip | [最终悬停](../remaining_ui_handoff_v1/evidence/polish_final_work_hover.png) |
| 新导航图案和黑色选中 | [下半导航](../remaining_ui_handoff_v1/evidence/polish_nav_lower.png) / [建筑选中](../remaining_ui_handoff_v1/evidence/polish_building_selected.png) |
| 每日七天框、已领取按钮 | [每日奖励](../remaining_ui_handoff_v1/evidence/polish_daily_fixed.png) |
| 抽奖按钮正常 / 悬停 | [正常](../remaining_ui_handoff_v1/evidence/polish_lottery.png) / [单抽悬停](../remaining_ui_handoff_v1/evidence/polish_lottery_single_hover.png) / [十连悬停](../remaining_ui_handoff_v1/evidence/polish_lottery_ten_hover.png) |
| 奖池页签、四列两行卡框、底层按钮禁用 | [奖池详情](../remaining_ui_handoff_v1/evidence/polish_pool_nine.png) |

`polish_final_*` 为最终 d78a04addb 构建；其余记录为同轮 093895fd43 / fa8cac0a47 的分项检查。早期 `polish_nine_archive.png`、`polish_daily.png`、`polish_daily_ready.png`、`polish_daily_live.png` 为故障排查截图，不能作为通过证据。

跨页检查另外定位并修复了每日加载中断：原生热重载时公共组件保存的旧注册表缺少 `daily.icon.spinner`。每日适配器现从已交付资源生成并校验稳定映射，不依赖另一布局是否重新注册。增加旧注册表场景的回归测试。七天奖励已恢复实机显示。

## 验证范围与继续位置

- `test_nine_slice.cjs`：四种尺寸配置 × 四种目标尺寸；固定边角、完整 UV、不对称边距、不拦截点击通过。
- `test_archive_icons.cjs`：463 条映射、分类隔离、等比显示、实际数量、旧业务函数保持通过。
- `test_daily.cjs`：旧资源表场景、七天卡、领取资格、重复请求、失败重试与关闭清理通过。
- 抽奖和商城原有行为测试通过。原生编译 0 失败；部署校验见 [deployment_verification.json](../remaining_ui_handoff_v1/deployment_verification.json)。
- 商城真实商品目录 / 支付接口仍未具备实机验收条件，九宫格组件已接入并通过静态 / 行为检查；没有进行真实付款。
- 本轮实际截图分辨率为 1768×992，其他分辨率未记录为本轮实机通过。
- 当前每日第七天高级装备仍由原数据标记“待配置”，不伪造奖励。
- 其他原有未完成项沿用前阶段记录；本轮未改动抽奖跳过勾选框旧样式等无关页面细节。

本轮修改前源文件在 `before/`，每次部署的回退目录由 `deployment_verification.json` 记录。主要接入文件为 `remaining_ui_handoff_v1/prepare.cjs`、`common.js`、`archive_navigation.js`、`deploy_test.ps1`、两个验证脚本与 `tools/read_archive_icons.py`；新公共切片组件和资源维护脚本在本目录。
