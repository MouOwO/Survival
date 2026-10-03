# 存档神器、货币来源、角色头像与左上角导航

## 改动

- 存档建筑改为存档神器，侧栏图标由房屋改为神器晶石；持久化分类 ID building、项目 ID、奖励与升级规则保持不变。
- 9 个神器直接读取本机 Dota 原版商店物品图，优先于旧自制图标映射；三列展示并放大图标，名称、等级进度、信仰消耗独立对齐。原版资源已逐一读取 VPK 并记录 SHA-256。
- 神器页显示信仰值来源：通关每次获得当前规则指定的数量，当前为 400；每日上限 4000，显示今日已获，余额永久累积，通行证不加成。
- 上班福利页显示软妹币来源：实际在线每满一分钟获得 1 枚，不足一分钟累计计算，用于激活福利，通行证不翻倍。说明独立于旧隐藏标题区域，切页时隐藏，数字使用存档金色。
- 好基友/前女友共 80 张头像逐张重绘，改为角色近景，保留发型、服装、面部与标志特征；增大头像展示区域。两份同名唐三保持不同原 ID，并用少年与海神形象区分。
- 左上角返回、宝物、存档、抽奖、福利、商城、生存商店、特效开关使用统一的饱满深青底、暖金矢量图标、浅白无阴影文字。保留入口顺序、动作和权限判定；右上角资源图标不增加底片。

## 美术与复现

头像使用内置 image_gen（imagegen 技能），每个角色独立提示词、独立生成。原图保持字节不变，位于 panorama/src/images/custom_game/archive_portraits_v3/。全部最终提示词、角色 ID、源文件路径与 SHA-256 保存在 data/ui/archive_portraits_v3.json。原始提示词集由该文件中的 prompt 字段组成。

游戏使用独立 256px BGRA 纹理，位于 panorama/images/custom_game/archive_gpu_regular/head_v3_*.vtex_c，共 80 个，总大小 31,532,400 字节。80 张源图均有透明背景且主体近乎不透明；部分源图最大 alpha 为 253/254，保留生成结果，不强行改图。

新导航 SVG 源图在 panorama/src/images/custom_game/topnav_v2/；均已生成对应 vsvg_c。

构建命令：powershell -NoProfile -ExecutionPolicy Bypass -File tools/build_archive_ui_v3.ps1。主题更改先运行 tools/build_archive_theme.py。

## 验证

- tools/test_archive_compact.cjs：通过，含来源说明、数字角色、分类切换、既有字体与弹窗回归。
- tools/test_archive_ui.js：通过，含神器升级、福利和社交抽取交互。
- tools/test_archive_artifacts_navigation.cjs：通过，9 个原版图优先级、8 个 SVG 依赖与原动作保留。
- scripts/vscripts/tests/test_archive_buildings.lua 与 test_archive_building_effects.lua：通过。
- 80 张原图 SHA-256 唯一且与记录一致，角色到纹理映射一致，80 个运行纹理存在。
- 全部 80 个纹理编译通过；存档布局 3 compiled / 0 failed，HUD 14 compiled / 0 failed。
- 已审阅 output/archive_friend_portraits_v3_review.jpg 与 output/archive_ex_portraits_v3_review.jpg。这两张是带角色名称的美术检查图，不是实机截图。
- 实机检查时 dota2 进程已关闭；尚未验证这版实际游戏布局，不宣称已完成实机视觉确认。
