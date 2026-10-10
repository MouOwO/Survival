# VIP迭代记录

## V00：实际入口与旧版基线

- 活动VIP节点、JS/CSS在archive.xml同context，主HUD顶栏VIP经SurvivalVIP.Toggle进入。保留原vip_badge与指定Tools预览资格，不把未授权窗口打开为真实奖励状态。
- 原vip_window.js/css及现有VIP回归已具名备份到work/baseline/source；预览代理另将完整旧装配冻结到work/vip_before，旧四图保存在work/vip_baseline。
- 实看旧normal/packages：869×816青蓝Reference框，4列小卡、三类真实33奖励；条件与效果占据大块固定详情区，尚未统一紫色框与compact tooltip。

## V01：真实33项进入统一紫色框

- 使用原ModalShell，1280×800、reference1920×1080；共享PurpleShell采用id vip/title VIP特权且navId为空，不伪激活商城。内容从y132起，216侧栏保留原三分类。
- 普通奖励128×128格子，92图标、真实V级目标角标、下方原名称，7列；仅有level>0显示V角标，小棉袄level0不编造数量。既有vip.svg保持，不虚构专属图或新收藏数量。
- 完整条件、原价格、全部效果和永久说明放同context根级380紫金tooltip，用真实卡片测量夹入屏幕；原action按钮留底部选中名字旁，免费领取、付费币购买、礼包附送、余额不足/保存等待语义保持。
- 旧VIP事件/快照权威与会员资格逻辑不变；补实例Dispose、旧订阅/tooltip定时器/失效根护栏，分类切换关闭旧hover，避免热重载已删除节点异常。
- 现有回归仍覆盖Tools身份隔离、真实VIP标记、33项/三分类、claim/purchase价格/余额/busy、精确分档充值进度；新增完整9行效果tooltip、三档原生UI scale屏幕边界/锚点只缩放一次、小棉袄无假角标、重复领取防重、旧回调与严格deleted subtree检查，全部PASS。
- archive.xml唯一追加vip_purple.css，保留Root已有include；源码node语法、差异检查与Escape原回归PASS，原生VIP仍待独立验收。
- 已实看V01的1080 normal/hover/packages完整图：7列、V1–12真实目标、名字与原action按钮清晰，9行效果与永久说明完整位于屏幕内；crop仅按主window裁图会切到tooltip下沿，验收以完整截图为准。三组真实条目12/10/11，0errors/missing；本地fixture只view/选分类/选卡，不领取购买。
- 已实看720 max_hover、little_jacket、selected_hover与1440 normal：853×533/1706×1066窗口符合统一fit，格子名称在720仍12字，V12条件12500元/9行效果完整，小棉袄无假角标且19付费币/星悦积分68完整；无需改候选几何。1080前一轮使用合法VIP5/1000元样例，随后720/1440使用VIP5/1200元样例，都是本地显式状态。
- qa/vip_v01_report.json的36个四尺寸组件几何场景PASS，0errors/missing；其generic pending/disabled图片选中已获得V1，不能据此声称存档保存/余额不足语义截图验收，相关真实控制器行为由VIP回归证明并等待专门未拥有条目图。共享导航/物理hover独立补证据。
- 当前较佳具名源码保存在work/checkpoints/vip_V01/source，4文件含仅作装配参考的archive.xml；manifest明确组件候选/原生未验收、8张亲自复看的截图和旧脏源保留位置。只恢复自己拥有的VIP源与include，不能整份覆盖其它代理的archive.xml变更。
- 补齐专用语义证据：亲自复看captures_vip_v01_states的720未拥有V4/pending、余额0礼包与未同步三图，按钮分别“正在保存…”/“付费币不足”/“等待会员数据”；最终qa/1280x720_vip_insufficient.png已将顶栏实际样例币同步为0，与VIP钱包一致。qa/vip_v01_semantic_report.json三场景PASS、claim/purchase请求为0；不使用generic owned-V1图替代这些语义证据。
- qa/vip_v01_navigation_report.json已PASS：实际物理鼠标从HUD HandoffNav_vip打开，然后VIP→宝物/存档/抽奖/商城四目标，均只有目标窗可见且layer正确、无交易请求、旧VIP tooltip消失；第5项为真实SurvivalUILayers.HandleEscape('vip')的浏览器本地API退出，清理完整，但不能称作原生键盘ESC验收。后续证据追加日志，V01冻结源码manifest保持。
