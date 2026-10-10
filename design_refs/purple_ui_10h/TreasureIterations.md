# 宝物历史迭代记录

## T01：真实历史进入统一弹窗

- 先具名备份treasure_history.js，SHA256 0395A498B320C1668B191CBE12A2EEBC921486D628E0E02849E36A567D945E50；archive.xml备份为archive_pre_treasure_C01.xml，保留共享壳同伴先前修改。
- 接入现有ModalShell生命周期与SurvivalPurpleShell装饰，id treasure，1280×800，fit reference[1920,1080]；内容从y132开始，不跨context搬家。
- 单元128×128，92图标，下方18字号名称，横12/纵2间隔；无分类的真实本局历史用1120宽居中8列。不增加20个空槽，历史为空显示明确提示。
- 服务端最近20条权威上限、排序与玩家隔离保持；每条记录独立展示，不合并或推断库存数，仅quantity/qty/count明示时显示实际角标。
- 原图标来源Image/DOTAItemImage/DOTAAbilityImage保持。tooltip留同context根级，380紫底金边，用真实卡片位置/尺寸夹入屏幕，关闭时终止定位generation。
- 新回归通过空状态、20上限、玩家隔离、实际可选quantity、原图标路径、tooltip边界与关闭生命周期；Escape中央dispatcher回归通过。
- 待实际组件预览normal/hover/empty与720截图自查，尚未作为原生Dota视觉验收。

## T02：首张normal/hover实看与作用域修正

- 实看captures_tertiary_a01的1080宝物normal：20个真实官方技能图完整、8+8+4排列、下方名称及最近20条提示/统计正确，无虚假quantity角标。
- 首hover虽展示完整实际效果，标题仍21px、章节名呈默认黑色；定位到tooltip直接SetParent(GetContextPanel)在浏览器wrapper上脱离.ArchiveRoot样式作用域。
- 只改变tooltip parent为窗口原GetParent（同context真实ArchiveRoot），保持测量/尺寸/定位不变；新嵌套root测试确认tooltip在原UI作用域、且仍在fit窗口裁切之外。
- 待T02 hover/empty/few及720图再选较佳checkpoint；不把浏览器结果表述为Dota原生完成。
- T02实看确认标题24px、紫金章节/正文与满宽分隔线恢复；720 empty提示和0/20完整，0errors/0missing。较佳源码存work/checkpoints/treasure_T02/source与具名manifest，尚待few720/1440图。
- T02补看1280x720_treasure_few_crop.png：只显示3条真实宝物、3/20统计，61px图标与约12px名字完整，未画其余17个空槽；仍待1440正常图。
- 补看captures_final_style/2560x1440_treasure_hover_crop.png：8×3图标/名字与完整紫金效果说明可读；final_treasure_report.json四尺寸normal/hover/few/empty共16场景PASS_BROWSER_COMPONENTS，无errors/missing，原生验收仍独立。

## T03：原生热重载的失效节点保护

- 父代理实机共享壳/商城已经遇到deleted panel异常；自有Treasure旧controller缺少Dispose，旧NetTable回调和tooltip定位可在窗口删后访问原panel。以同类已见风险补轻量保护，不改视觉/数据/权限。
- 新控制器先Dispose前一实例；关闭/定位/NetTable/tools回调检查原context与window有效性，可用时退订NetTable，保持ModalShell原生命周期；原空状态/quantity/heading动态节点复用，避免同树脚本重执行重复标签。
- 严格mock拒绝访问已删除panel，覆盖同树重执行、删除整棵subtree后的旧hover回调/旧listener/Close/重复Dispose，以及新树正常启动，全部PASS。T02视觉checkpoint保持，等待编译与新快照复核。
- 实看最新captures_final_archive_a14/1920x1080_treasure_normal_crop.png：T03仍为20真实记录8+8+4，提示、名称、数量统计和页尾完整，0errors/0missing；只增加生命周期保护。保存新T03候选，同时保留T02原始视觉checkpoint。
