# 存档迭代记录

## A01：密集单元候选

- 用户最新要求优先：图标、右上实际数量/进度、下方名称；详细效果与条件留在tooltip。
- 基准窗口1280×800，内容从y=132开始，侧栏216，内容1064；列表1000宽、522高。
- 普通单元128×128，92方形图标，每单元右边与下方12间隔，目标每行7列。称号使用268宽以保留既有动态图层，社交抽奖页为底部动作栏让出60高度。
- 备份活动源与拟改测试到work/baseline/source，保留任务开始前的脏改。
- 当前候选尚未截图验收；接下来核对实际Panorama与浏览器的文字、布局、badge与tooltip边缘。

## A02：状态与测量回归

- 右上角保留服务端实际进度/数量，未知钓鱼库存为×—；神器/上班是等级进度；称号无无意义数字。
- 悬停金边在当前tooltip生命周期中更新，移出恢复紫边；社交头像viewport从96缩至92时只按比例重排一次，避免重复刷新累计裁切。
- tooltip改为测量真实卡片位置和尺寸，取消869窗宽与112卡片硬编码；保持原生字形大小，三个UI scale下均夹在屏幕边界。
- 条件/进度置于效果之前，费用、来源说明和称号点击语义仅在tooltip中保留；新增真实进度条。
- 已通过活动controller的购买/重试/pending/不足余额、分片/增量cache、184条fragment等级及锁定灰度、原生神器图标、紧凑格子/头像/tooltip尺度回归。截图视觉验收仍待预览同伴。
- 校对旧实机geometry.log与ability_tooltip坐标规则后，确认actuallayoutwidth/height已有原生UI缩放；仅补panel/root scale比率处理CSS fit，tooltip高度直接使用物理测量，避免小分辨率二次缩小。回归增加邻接位置的精确断言。

## A03：统一基准缩放与第一张实看

- 共享壳已接入，存档fit统一reference[1920,1080]：1080p窗口1280×800，720p约853×533；普通图标在720p约61px。
- 给存档补幂等Open接口，匹配共享顶导航；保持原Toggle入口。
- 实际查看浏览器截图work/captures/1920x1080_archive_normal_crop.png：普通格子7列成立、紫色分类与卡片匹配，但页标题挤入筛选、旧footer细线与左对齐未清除，第四行名称被切。

## A04：首图反馈，两组布局变量

- 固定新页头/筛选/列表/footer的设计坐标，消除legacy高specificity规则；页头与筛选分行，footer横跨1000且居中。
- 普通格子纵间隔12→2，522列表高可容纳完整4×7单元；横向12间隔与92图标不变。
- 汇总解锁计数与筛选共用A.Unlocked，避免unlocked投影已亮而摘要仍只计completed；不改变服务端解锁权威。
- 存档palette与字体适配局限在ArchiveBody，防止旧递归刷新把共享顶栏的金色品牌/字号覆盖为存档正文样式。
- 同轮hover图中tooltip只剩一条金线：frame已退役但旧tooltip flow:none使浏览器height:fit-children无法收录绝对body。tooltip改为down流、唯一body自然撑高，原生也沿同一布局语义。
- 等待hover及720/1440截图复看；浏览器截图仍不能作为本次Dota实机验收。

## A05：首轮正常版/悬停版实看后的留白收紧

- 实看A04的1080 normal/hover：7列×4完整行成立，tooltip完整展示条件、进度、进度条及灰色未解锁效果；shared金色品牌、book图标与金色关闭恢复。源码/测试已保存work/checkpoints/archive_A04/source与具名manifest。
- 旧pageHeader默认collapse，留下35px空档；筛选上移至y=12、列表上移至y=60，分类和筛选从同一内容顶沿起步。
- 将原Summary保留在列表下方页尾（y=606），只显示统计，隐藏重复分类大标题；社交抽奖页优先保留原动作栏。
- 普通格子大小、7列、纵pitch130及522列表高保持，避免再次切第四行名称。待A05三个分辨率复看后选最佳checkpoint。

## A06：特殊类别、原规则迁入tooltip

- 实看A05旧几何快照的720/1440 normal/hover：四行名称完整，720普通图标约61px、名称约12px，1440约123px、24px，悬停说明完整且在屏幕内。
- 实看A06 work/titles：新筛选y12、列表y60、统计页尾y606已生效；上班7列×4行，称号保留3列×3行的真实动态图层，已穿戴名称与底部统计正常。
- 预览特殊类别缺图确认为adapter未遍历panorama/src/images中的archive_gpu_regular recipe；A06_fixed实看34个上班符号均恢复。神兵两行旧图的260px行距为浏览器flexwrap align-content stretch，预览同伴改flex-start；生产卡片128高/130pitch没有改变。
- currency说明改读源__archivePlainText，保留换行；星悦说明改为“右上数字”；上班来源短句避免末字单独换行。原clear/endless/shadow/fragment/pet/social/boss/fishing/map_level/gift隐藏Hint规则进入tooltip，保留获取方式/每日上限。
- 晋升帮助改用既有ShowEffectOnly，不显示虚构“状态待同步”或无意义库存。五项相关回归通过，包含184条fragment效果、来源换行、隐藏类别规则和辅助帮助显示语义。
- 仍待最新源的fragment晋升按钮、720/1440新版几何和全部分类scroll/filter/tooltip复抓；浏览器结果仍仅是生产组件预览。

## A07：神兵原生资产修正

- 官方VPK核对定义5810为Blades of Voth Domosh；真实image_inventory为econ/items/legion_commander/blades_voth_domosh/blades_voth_domosh。旧demon_sword路径不存在，不使用2026新增定义37140的同目录sword。
- CSV archive_item_icons与活动icons_remaining catalog三处URI/icon_path统一修正；原生路径s2r://panorama/images/econ/items/legion_commander/blades_voth_domosh/blades_voth_domosh_png.vtex。
- 原CSV和任务前活动catalog具名备份保留；原生资源不复制/编译，由官方VPK解析，浏览器aliases由商店同伴导出。
- 回归新增5810定义、活动URI与CSV源路径一致检查，原神器/导航动作检查保持通过。

## A08：完整神兵tooltip与辅助说明实看

- 实看captures_a06_fragment_mapped full hover：获取/每日限制及LV1–10完整留在屏幕内；窗口crop截去悬停框窗口外部分属于裁切，不是屏幕越界。神兵两行130px pitch成立；最新fragment10映射待重建图。
- 实看captures_a06_final clear normal：筛选/分类顶沿齐平，7×4完整名字、页尾已完成3/44统计可读，较旧A04留白收紧。
- 晋升帮助截图暴露旧内部目标ID fragment_05，改为当前真实rows中的目标名（示例狂战斧），缺失目标数据使用“下一阶神兵”；不推断ID到玩家名。
- effectOnly辅助说明隐藏空divider，章节名用“说明”；主存档效果heading与状态/进度保留。回归增加真实晋升事件的目标名/内部ID不泄漏检查，全部通过。

## A09：720边界状态实看

- 实看QA的720 empty/long和1080 scroll：长名称在单元省略、tooltip显示完整名字；满进度条/解锁色正确，滚动后第四行名称与数字仍随图标一起裁切。
- 空的通关页沿用旧默认文案“尚未拥有积分道具”，修改为按points专用、其他分类通用“当前分类暂无存档”；筛选空结果提示保持。几何不变。

## A10：tooltip分隔线宽度

- 对比真实fragment/clear悬停与参考图，效果章节label的fit-children宽度使上边界线只覆盖标题文字。
- 只改章节heading宽度为100%，让条件/进度与效果之间的分隔横跨说明区，接近参考图；tooltip380宽、字号与行高不变，待新hover图复看。
- T02晋升帮助已实看横线完整、狂战斧玩家名称正确、无额外同步/库存行；较佳源码存work/checkpoints/archive_A10/source与具名manifest，保持A04可回看。

## A11：紧凑动作的可见状态

- 隐藏称号原actionLabel后，其原“正在切换…”反馈不可见；提交时同步到页尾ArchiveStatus。点击请求/防重/权威快照路径保持。
- 晋升按钮按原enabled显式使用紫色金边或灰紫禁用配色，提交立即更新颜色并显示页尾“正在兑换神兵碎片…”，不新增服务器请求。
- 回归确认称号重复点击只发送一次、pending页尾可见，晋升禁用/可用配色切换；work请求及fragment184行效果/帮助回归保持通过。待下一轮状态截图审阅，A10 checkpoint保留。
- 已实看captures_final_style的titles/fragment activate：页脚pending反馈完整，碎片晋升按钮变灰且图标/数字/名称未跳动；触发仅为浏览器本地mock，不代表实际发起兑换。该版较A10补足紧凑模式动作反馈。
- 最新qa/final_primary_report.json为96个场景及16次物理鼠标检查，PASS_BROWSER_COMPONENTS且无errors/missing；覆盖720/1080/1440/超宽、空列表/长文/未知进度/悬停边界与禁用动作。实机Panorama和交易API仍须另外验收。

## A12：社交收藏总数位置

- 社交页需要保留抽奖券与抽取按钮，原页尾Summary在紧凑布局中隐藏；单元数量与筛选拥有种数保留，但原social.total总件数缺少可见位置。
- 将服务端social.total显示到筛选行右侧闲置的ArchiveContext，显示“收藏 N 件”，不推断或合并库存；其余类别context不变。
- 待社交页真实fixture截图复看头像裁切、总数、抽奖按钮与tooltip；A10较佳checkpoint保留。
- 已实看captures_final_style的friend normal/hover：实际40头像、真实样例总数24件、券余额/按钮/完整tooltip正确；发现社交grid496高切掉第四行名字，进入A14。

## A13：实机筛选文字盒

- 只读实看work/native/c05_archive.png：1600×900的1067×667窗口符合统一fit；All文字正常而匿名已解锁/未解锁仅约7px。该差异未在浏览器复现，实机暴露原生RadioButton默认Label盒/padding/shrink与旧高specificity规则。
- 显式三筛选button宽178/124、高35；Label满宽、高35、19字、零padding/margin、nowrap/clip，并隐藏RadioBox，防止原生默认Label盒压缩文字；既有筛选事件保持。
- 真实wrapper回归以14×9默认shrink盒验证重置；等待父代理编译后的原生截图。

## A14：社交页第四行完整名称

- friend截图中的第四行图标完整，但名字被496高grid裁去；现有668内容区可容纳完整4行与动作栏。
- 仅调整社交三变量：grid496→522高，DrawBar y566→588，footer y635→642；普通分类几何不变。grid结束582、动作栏588–638、footer642–666互不覆盖，保持7×4密度。
- 等待1080/720 friend截图复看后保存新较佳checkpoint；不将浏览器视图作为原生交易验收。
- 已实看captures_final_archive_a14的720 friend normal和1080 hover：第四行7个名称完整，真实总数与券余额/抽奖按钮/底部规则无覆盖，0errors/0missing；A13 clear normal也完整显示19px筛选。A14为当前较佳候选，原生已解锁/未解锁字号仍待编译后的独立实看。
- 随后只读实看Root抓取的work/native/c06_archive.png：真实服务端44条通关记录已到达，1600×900中7列×4行图标/名称/实际0进度完整，All/已解锁/未解锁三筛选原生文字盒均恢复可读；A13原生缺陷已消除。该图仍有开局旧难度框白底叠在后方，Root负责上下文/开局框处理；不将此独立背景问题记为存档源码问题。原生其它存档分类、悬停与领取操作仍需独立证据。

## A15：真实热重载后缺失增量基线与迟到回调

- 只读实看work/native/c10_archive_battlefield.png：真实战场已恢复，存档外壳/筛选正常但分类、卡片、统计全空；不是“零记录”状态。C06真实44条记录仍是既有正常证据。未访问原生控制台，编译/截图由Root独占。
- engine_history.log中lottery archive_lottery_read发布资料后17条category_id clear/prefetch1。代码定位：archive_service每次profilechanged发送17分类；新controller缓存为{}，每个delta缺失base时都调用request(true)，该函数category固定为当前clear。完整生产controller在strict mock中先复现旧源码一次17delta→17个clear请求，失败断言为17 != 1；该数量可以来自单个实例，不能只凭日志认定存在17个订阅。
- 分类缺失基线合并为一个0.2秒full resync；窗口打开但完整基线尚未到齐时只维持一个0.75秒重试。服务器节流使用游戏时间，暂停期间时间不前进，请求可被静默忽略；客户端保留重试直到真实full snapshot到达，各分类baseline收齐后停止重试。关闭窗口不持续后台重试。
- 生命周期增加原生child marker、CustomUIConfig中的API实例身份、Dispose、三个GameEvents退订及计时器取消；查询绑定自己的context FindChildTraverse。旧订阅、旧按钮、旧API和迟到timer不再访问替换后的树或发请求。仅重执行controller时清旧grid子树；删除整棵布局后可重新初始化。Tooltip测量补deleted-root/tip保护。视觉几何和数据/账户权限不变。
- tools/tests/archive_lifecycle.test.cjs直接运行完整生产controller：17分类缺base合并、静默节流后重试、本地权威事件fixture44条恢复、随后delta修改、收齐17真实分类baseline后停止请求、同树重载旧回调隔离、整树删除后两次Dispose和替换子树。此为本地mock回归，不是实机账户记录或真实交易。
- 相关cache、work点击、compact样式、184行神兵tooltip、神器导航、ESC七项检查均通过，活动脚本syntax与差异空白检查通过。旧slice测试只补新的active/subscribe/later环境依赖，原业务断言保留。
- 具名改前源保留work/baseline/source/archive_a15_before；最新源码冻结并交Root编译，work/checkpoints/archive_A15保存源码哈希及回归证据。首轮legacy API没有Dispose/订阅token，只能尽力Close，历史未知订阅不能凭空退订；如实机仍有历史回调，需要整context重建。A15实机复核待Root，不将本地通过写为native通过。
- 最后审查补上共享SnapshotCache.Warm延后factory的active/hostvalid保护。完整controller回归在补前明确复现deleted ArchiveGrid异常，补后通过；另覆盖root仍存活、全部children/marker已重建时，旧API/事件无权操作替换树。最终冻结保存archive_A15_final；archive_A15保留首次候选，不覆盖具名记录。Root确认尚未读取/编译旧候选后才补最终一行。
- C12全资源编译后首图仍空，不能直接断言A15运行失败：编译资产与原生JavaScript闭包实际重执行需要分别核验。A15独有Dispose；没有公开IsAlive，不能以IsAlive缺失判旧。Root随后通过真实Tools inspect确认Archive API Dispose=function、ArchiveHandoff.snapshot类别clear/rows44/categories17，并完成二次真实数据回补。
- 已只读实际查看work/native/c12_archive_retry_second_context.png（2026-10-09 18:27:25 UTC）：真实战场作为底图，分类栏、7×4可见图标/名称/实际0进度、全部(0/44)、已完成0/44和页尾效果自动生效全部恢复；三筛选原生字号正常。确认当前A15运行及真实基础数据展示成功，不把“二次回补后有44条”扩大成所有17页/tooltip/反复重载/交易已实机通过。原生合并请求次数与重试具体触发仍须独立日志，现有Node证据保留。两生产源哈希保持最终冻结值，immutable checkpoint不回写native标记。
