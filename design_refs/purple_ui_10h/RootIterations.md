# 整体组装迭代

| 组 | 改动目的 | 证据与选择 | 代价 / 后续 |
|---|---|---|---|
| C01 | 第一套共享紫色壳、紧凑存档/商店 | 浏览器真实组件可运行；原生缓存导致没有显示新子树，不作验收版 | 原生与浏览器不同，继续定位生命周期 |
| C02–C05 | 原生layout重载后重新创建共享壳及失效闭包 | 修复删除面板访问、共享余额订阅、ESC有效上下文复用；C05仅空壳，仍不作内容验收 | 每项有独立真实controller回归，不能用空框充当完成 |
| C06 | 组装全部紧凑菜单与基础壳 | 原生通关44条7×4、真实商城25条；商店名称不可见，淘汰该商店子版本 | 存档框后仍有旧难度弹窗，不作最终整体验收 |
| C07 | 商店原生名称锚点、抽奖消耗/正文/图标、生命周期 | 首次编译因漏checkoutCSS依赖失败，恢复Content与运行产物；三个稳定诊断文件随后编译 | 未把失败组标记成功，完整组重编 |
| C08 | 完整菜单含VIP/订单、补齐新增CSS依赖 | 33文件原生编译成功；实机四件商品名称、库存、页脚恢复 | 名称仍左对齐；旧难度visible残留；继续单变量修复 |
| C09 | 商品名称显式居中、原生旧难度可见性恢复 | setup/ESC/strict删除subtree/抽奖/商店回归通过；完整原生编译中 | 保留原生C08截图便于同状态复核；不触发交易 |
| C10 | 铜金上下框线、放大选中页签图标 | 实机中选中图标更容易辨识；已完成难度的旧弹窗清除。天空背景由镜头偏离战场造成，以实际相机坐标恢复，未修改玩法镜头代码 | C10 存档冷缓存空白、抽奖页脚仍裁切，未选为空白内容验收版 |
| C11 | 商品名称使用自身文本盒居中；保底文字取消旧缩放 | `c11_shop_textbox_battlefield.png` 四件真名居中，实际文本盒62/87/87/57像素。保底文字仍裁切，淘汰仅改字号/高度的方案 | 发现旧CSS仍有86px min-height，不把源文件修改当实机生效 |
| C12 | 清除保底旧min-height；存档同步生命周期与普通菜单嵌套关闭 | `c12_lottery_pity_corrected.png` 保底完整；`c12_archive_retry_second_context.png` 新API具备Dispose、真实44行/17分类与7×4网格；真实鼠标archive/shop tooltip已截取 | server暂停时快照可能被game-time throttle静默丢弃；区分响应等待与渲染故障，完成短暂恢复后自动暂停。商城重复水晶图/名称左对齐及商店详情透字留待下一组 |
| C13 | 商店不透明、商城真实科技图标与名称居中、规则/tooltip互斥、共享分类标题更新 | `c13_shop_opaque_hover.png` 无透字；`c13_commerce_distinct_icons.png` 真实25SKU各自Dota图且名称居中；`c13_daily_after_hover_rules.png` 真hover后无旧tooltip；`c13_lottery_history_caption.png` 两处标题一致。存档实际clear44/fragment12/friend40已查看 | 公共header青底露出、规则空白较多，继续最小修正；商城原生hover未显示，不能引用browser PASS代替 |
| C14 | 改header旧inline底材；规则按内容适应；抽奖元数据迁入tooltip | `c14_shop_header_purple.png` 青条消失；三实际商店分类已拍；`c14_daily_rules_compact.png` 完整真实规则高度收紧；`c14_lottery_full_metadata_tooltip.png` 实际SSR/0÷1/永久/重复400显示。各项controller检查通过 | 共用效果formatter会把数字后的空格单位拆行，已取消该处空格。商城tooltip原生诊断selected/shown/visible=true、屏内260×376却未绘制，指向浮层挂载/原生绘制链，A15单独修复验证 |
| C15 | 商城详情改专用窗口浮层，补原生分类只读检验 | `c15_commerce_loaded_layer_hover.png` 已实际绘制完整详情，Tools 只读诊断确认新 factory、source link、window detail layer 都已生效。存档实际称号9条、上班福利34条、存档神器9条、宠物空状态均已查看 | 初次 `c15_commerce_root_layer_hover.png` 仍实例化旧 factory，没有新 layer，保留为热重载未生效证据，不能当成新结构失败。浮层材质稍透，继续单变量比较 |
| C16 | 商城详情改全不透明；复验按钮悬停、ESC、重开及右边界；抽奖积分单位修正 | 首卡、详情按钮悬停、关闭、重开实机通过；`c16_lottery_metadata_unit_fixed.png` 的400积分不再拆行，真实品质/已有/期限完整 | `c16_commerce_edge_tooltip.png` 第五列详情被窗口裁切，判为失败。浏览器 viewport 边界通过不覆盖原生 window clip，A17调整窗口与屏幕交集边界后再验 |
| C17 | 商城详情位置使用窗口与屏幕安全区交集 | 真实右上左翻、右下上移、ESC、重开截图完整；严格模拟先复现前版窗口裁切，再验证21项 | `c17_commerce_effect_scrolled_end.png` 三次真实滚轮仍显示头部，判为滚轮失败。旧直接ScrollToBottom仅证明API，不证明物理输入 |
| C18 | 仅开启商城正文的hittest；单件奖励只显示真实期限并清旧底材/边距 | `c18_commerce_long_before_wheel.png`→`c18_commerce_long_after_wheel.png` 真实滚轮后星悦积分×68末行完整，6800U币与按钮保留；按钮hover、ESC、重开右下完整 | 单件已获奖励为浏览器/mock验证，未原生抽奖。L06将history脚注隐藏，独立peer指出后淘汰该谓词，保留失败范围 |
| C19 | 保留原抽奖记录范围与更新说明，更新日期避开共享header | `c19_lottery_history_scope_preserved.png` 实机原30次/跨局说明完整；history/update/已知期限/缺期限四尺寸16实际组件状态通过；当前map CSV未给更新日期，沿原奖池配置已更新提示，不伪造日期 | 最终35文件原生编译、70配对检查点与143源graph逐SHA一致。C18检查点保留历史，最终恢复用best_final_compact_purple_c19；普通窗口关闭、临时引擎参数恢复、对局仍暂停 |

实机诊断：一次只读日志工具的自动权限审查超时，按工具规则重试一次成功，无待审批事项。Tools-only inspector 的 `GetClasses` 在原生不可用，已移除该诊断字段；未影响业务入口。截图命名不可复用，失败或空白状态保留而不覆盖为成功图。

组件详细实验见 ArchiveIterations.md、ShopIterations.md、DailyIterations.md、TreasureIterations.md、CheckoutIterations.md 等实际现有文件。最终选择写入 BEST_VERSION.json，工作中源文件不等同自动最佳版。
