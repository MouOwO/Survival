# 生存商店独立抽屉 · C25

本页依据用户最新要求更新：生存商店从存档等公共弹窗中移出，保留原 HUD 入口，从左侧平移展开。第二张商店参考图决定布局和 tooltip；仅将浅底、深灰底换为紫色。商城仍在公共弹窗中，与生存商店分别管理。

## 最终组装与实际截图

| 实机状态 | 截图 |
| --- | --- |
| 装备：实际四件商品、名称/类别/费用/效果详情 | [最终装备](work/native/c25_native_equipment_final.png) |
| 挑战：四列三行，金币与木材两项费用 | [最终挑战](work/native/c25_native_challenge_final.png) |
| 其他：实际六件商品、知识之书与自动购买入口 | [最终其他](work/native/c25_native_other_verified.png) |
| 鼠标从图标移入详情按钮，详情保持显示 | [按钮悬停](work/native/c25_native_tooltip_button_hover.png) |
| 商店关闭后点击原 HUD 入口重新打开 | [原入口重开](work/native/c25_native_entry_reopen_verified.png) |
| 存档公共导航已移除生存商店 | [独立存档](work/native/c25_native_archive_detached_shop.png) |
| 验收后菜单关闭、临时入口与引擎设置恢复 | [恢复状态](work/native/c25_native_final_restored_verified.png) |

[四尺寸前后对照图库](work/shop_reference_drawer/Comparison.html) 使用生产 XML/JS/CSS，比较用户否定的上一版与 C25 的同分类、同状态、同视口组装；样例资格与余额明确标注。四视口为 1280×720、1920×1080、2560×1440、2560×1080，合计十二种分类/尺寸与四十八张状态图。图标使用现有 Dota 2 资源。所有物品数来自实际目录，不填造商品来凑十二格。

实机只验证当次 1600×900。测试对局未召唤英雄，入口临时启用仅为展示检查；服务端英雄前置条件仍保留，所以截图购买按钮显示原条件未满足状态。没有购买、启用自动购买、扣资源、发物品或调整账号。可购买状态的红色按钮在真实控制器的独立预览中验证。

## 与参考图的对应

- 标题固定为“生存商店”，右上金色关闭叉号；装备、挑战、其他三个等宽页签，当前分类使用参考的红色选中底。
- 外框 680×600 逻辑像素，与参考约 592×521 保持比例；左侧展开到 x=16，关闭平移到屏外，过程中停止接收鼠标输入。
- 四列、三行可见区，136×132 图标单元；移除常驻名称、库存数字、重复锁定标记。更多项目沿原目录滚动，研究等级按原逻辑保留。
- 详情固定在窗口右侧，金色细框与四角、向左尖角；顶部图标/名称/类别/费用，中部“效果”和原完整说明，底部购买或挑战按钮。只有实际非零成本出现货币图标和数量。
- 原业务的双货币、科研前置与满级、库存、冷却、自动购买、悬停/固定详情、取消和购买路由均保留。特殊业务内容按实际数据延展详情，不挤入图标卡片。

## 候选与取舍

| 候选 | 改动与发现 | 取舍 |
| --- | --- | --- |
| C20 | 拆出独立左抽屉，固定参考比例、图标四列、右侧购买详情 | 方向保留；详情旧 CSS 覆盖宽度与类型，继续修正 |
| C21 | 修正详情选择器优先级、恢复类型/费用与字体层级 | 淘汰不等宽的其他页签，继续统一三页签 |
| C22 | 三等宽页签、轮廓和详情间距；浏览器通过 | 原生发现标题父容器裁掉页签，控制器重显库存；该图不计通过 |
| C23 | 标题容器包含页签，控制器明确隐藏库存 | 原生装饰受父 padding/裁切影响，负坐标箭头仍不可靠 |
| C24 | 透明详情外层加正坐标尖角空间、独立不透明内框 | 三分类原生布局通过；挑战标题仍变为“挑战”，不选为最终 |
| C25 | 非研究分类标题固定“生存商店” | 原生与四尺寸专项通过，选定；研究窗口标题保留原行为 |

几何只为兼容真实内容作必要延展：双成本采用两行，知识之书保留额外自动购买按钮，长效果可滚动。固定三行窗口在商品较少时留白，这是保留参考格局的代价。

## 源码、接入与恢复

控制器：[shop_remaining_5d5c1152eb.js](../../panorama/src/scripts/custom_game/shop_remaining_5d5c1152eb.js)。详情：[shop_tooltip_remaining_5d5c1152eb.js](../../panorama/src/scripts/custom_game/shop_tooltip_remaining_5d5c1152eb.js)。样式：[shop_purple.css](../../panorama/src/styles/custom_game/shop_purple.css)。真实结构：[survival_hud.xml](../../panorama/src/layout/custom_game/survival_hud.xml)。

继续复用 `UIComponents.ModalShell` 的输入层、关闭、缩放；使用 `SurvivalPurpleShell.Detach` 从公共页签系统脱离，旧 `RemainingHandoff.SurvivalShopWindow` 和 `ReferenceWindows.Apply` 对独立店增加保护。没有增加第二套商品或服务端接口，也没有改战斗底部 HUD。

详情外层宽 370、无 padding、透明，内部 `ShopTooltipFrame` 宽 348、左侧 22 空间。箭头放在透明空间中的正坐标，避开 Panorama 对父范围外负坐标子控件的裁切；购买/自动购买按钮属于内框。公共组件和普通商城保持自己的详情定位。

最终恢复点：[best_standalone_shop_c25/manifest.json](work/checkpoints/best_standalone_shop_c25/manifest.json)，包含三十五份源文件和三十五份匹配运行资源。恢复前保存当前目标，按 manifest 校验 SHA，只恢复所需文件，然后重新编译到 Content 与运行资源。具体安全恢复模板见 [Integration.md](Integration.md)，应将示例检查点改成 C25，不能用旧 C19 覆盖本版。

编译：[compile.json](work/compile.json)。独立配对核验：[shop_c25_integration_peer_report.json](work/qa/shop_c25_integration_peer_report.json)。业务与结构专项：[shop_standalone_d04_suite_report.json](work/qa/shop_standalone_d04_suite_report.json)。浏览器完整源链：[sourceproof.json](work/shop_reference_drawer/sourceproof.json)。实机范围：[native_shop_standalone_acceptance.json](work/native_shop_standalone_acceptance.json)。
