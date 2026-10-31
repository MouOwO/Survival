# 游廊头像饰品与渲染职责审计｜2026-10-31

这是定位阶段记录，不是此次故障已经修复的声明。真实游廊画面、帧率与错误采样由主任务继续完成；本审计不操作客户端、不修改运行资源或云端。

## 已核实的发布链

用户截图标题“挑战5转”对应祸乱之源Bane，不是幽鬼9转。真实配置为`monster_boss_rebirth_05_lucid_torment`：基础Bane身体，以及头、手臂、背部、肩部四个独立骨骼合并组件，场景`portraits/monster_326b73b164e21d7f1a07_v1`。裸身体缺头饰时不能据此改成另一模型。

对已发布3102的冻结VIEW和Steam实际安装VPK做了关键输入逐字节/CRC检查：五份JS、正式HUD布局、Bane场景及服务端头像元数据均一致。VIEW的这些文件也符合其发布清单。它不代替签名认证和完整包验收；此前发行已保存完整6917资源/184保护模块认证回执。

五份编译JS的DATA与开发源码一致，包括性能版renderer、combat_stats、presentation、scenes和正式topnav；没有发现“性能优化把饰品从场景删掉”。正式HUD编译资源与原有dirty开发HUD raw hash不同，但解码后XML语义完全相同，均按scenes→renderer→combat_stats加载，不是漏打入口或脚本顺序错误。两个dirty字节版本均未改动。

旧Source2Viewer不支持新版RED2编辑元数据。只在ignored output中生成去掉RED2的解码器副本，保留RERL/DATA/LaCo等运行内容并修正副本表偏移后，成功读取两份布局；没有修改原运行文件、候选、签名或工坊包。此处理用于静态语义核对，不能作为编辑后运行的资源。

服务端开发`portrait_metadata.lua`相对3102仅新增展示专用角色的权威标记投影；资产ID解析链保留monster默认饰品、建筑资产、builder定义和英雄资产。该差异本身没有证实为此次饰品丢失原因。

## 仍需现场证据的两个具体风险

1. renderer会最终创建并永久保留188个DOTAScenePanel世界。JS稳定操作已经O(1)，但visibility=collapse不能由JS模拟证明原生世界的动画、显存和资源成本归零。每个场景平均加载耗时及当前帧率需真正采样，不能把桥调用减少写成FPS提高。
2. 某个加载超过10秒即设置`failed[key]=true`，之后整个控制器生命周期内永不重试。当前资源繁忙时若命中这一分支，后续点击直接走原生裸身体回退；这是可复现的设计行为，但尚不能在没有LOAD_FAILED现场记录时断言它就是用户当前截图的原因。

应先从同一个实际游廊局记录READY/LOAD_FAILED、SCENE_SET/HIDE/anchor_state及JS错误，核对选中实体的权威asset与overlay显示层。现有portrait缓存/层级探针只在Tools注册，不能把离线探针结果冒充正式游廊证据。

## 解耦评价

已有领域分离是有效的：世界装配由model_appearance/monster_hero_visual负责；portrait_metadata只投影身份；生成器用权威组件及官方镜头生成静态目录/地图；renderer维护身份索引、加载与缓存。问题不能简单归因为“文件多”或“没有解耦”。

仍有明确职责交叉：

| 边界 | 当前具体交叉 | 后果与限域修正方向 |
| --- | --- | --- |
| combat_stats与头像 | 同一大模块拥有战斗数值、技能格、原生节点发现/几何、选择过渡、头像overlay及加载调用 | 错误容易沿同一同步调用栈阻断后续UI。将原生头像anchor/挂载/几何和显示生命周期集中到头像适配器；stats只传身份与选择事件 |
| renderer与预热策略 | 197身份目录索引与188个原生渲染世界生命周期绑在同一模块，全目录预热默认等于永久驻留 | 目录覆盖范围不应决定原生世界数量。保留O(N)身份索引，渲染世界缓存上限可独立管理；只有实测支持时改为有限热门预热/有界LRU，不删除组件 |
| presentation与combat_stats | 两者分别保存当前snapshot/身份，重复读取选中实体，分别处理背景、遮罩和native层 | 使用同一实体+身份版本作为头像输入契约，过期回包和换选中只从一个入口失效；不增加跨模块全量轮询 |
| 原生HUD布局所有权 | 正式topnav和combat_stats都接触原生容器、可见性及技能显示 | 明确“布局由topnav，头像视觉由adapter，输入由原生层”的单一属性所有者，保留重建时失效 |
| 发行验证 | 完整资源认证/启动验证没有覆盖正式模式中选中已装配怪物的画面 | 新版需补真实signed生产链/游廊选中样本。只到GameSetup的layout_ready不能证明头像功能已触发 |

以上为可定位的维护边界，不是已测得的FPS因果。应优先修复已证明的问题并做限域调整，避免借解耦名义全项目改写。

## 有界原生世界候选（尚待实机对照）

主任务批准实施限域候选：仅修改renderer及content镜像，不修改combat_stats、世界组件、目录或188份地图。原目录197身份继续可用；首次只建立身份/模型/别名索引，不再把整个目录自动变成188个原生世界。

采用4项原生世界缓存和双向LRU；当前显示与正在加载两项受保护，淘汰最多跳过2个保护节点。待加载请求仅保存最新一项，真实选择立即抢占旧的非当前加载；旧请求不自动回填。无明确资产的Prewarm仅建立渲染舞台，不调度计时器、不查询移动位置、不新建ScenePanel。被淘汰后的冷选择重新加载完整地图，继续复用现有官方背景遮罩及100ms稳定窗口；不再承诺全197项首次点击都零分配。

保留10秒实际加载超时后的原生错误退路，避免永远空白遮罩；这只是明确失败后的退路，正常加载/复用仍遮住裸原图。失败不再永久黑名单：2秒→10秒→30秒封顶退避，只有本地真实selected/query事件的新epoch、资产切换或显式Retry才可获准再试。同一epoch即使过很久、每tick刷新或收到别人的选择，也不会重建；无资格的失败请求不持续调度warmup任务。预热先于Prepare的epoch交接已有回归，避免意外自动重试。成功清理该失败记录。

控制器恰有两项选择订阅，Shutdown解绑；旧事件、image回调和计时器失效。逻辑缓存上限4不等于已证明原生GPU瞬时分配上限4，DeleteAsync释放时机仍须实机观察。95FPS或CPU P95约23ms的启动样本波动尚未证明由188世界导致，本候选不能在实机对照前写为FPS根因修复。

| 路径 | 旧版 | 本候选 | 调用/失效 |
| --- | --- | --- | --- |
| 初始化 | O(N)目录索引+O(N log N)全目录排队，最终188世界 | O(N)目录索引，0个自动ScenePanel | N=197，空间O(N)元数据；真实控制器重建重新索引 |
| 稳定选择/显隐 | O(1) JS，最多188世界驻留 | O(1) JS，最多4逻辑驻留；300次零枚举/零样式写 | 197和1970目录实测同为1800次模拟GetParent；不是原生耗时/FPS |
| 资产变化/淘汰 | 冷场景建立后长期保留 | O(1)查找/LRU，最多2次保护节点跳转，至多1次创建/淘汰 | 原生模型加载耗时随资源而定，不能称O(1)原生耗时 |
| 默认后台任务 | 20Hz检查移动/冷却并最终加载188世界 | 没有待请求或实际加载时0调度/0位置查询 | 仅单个实际加载任务以50ms检查就绪/超时 |
| 失败重试 | 生命周期永久failed | O(1)epoch/退避判定；每个获准请求一次尝试 | 真实选择或显式请求触发，2/10/30秒，成功清理 |
| 销毁 | O(188)世界释放 | O(M)，M≤4；解绑2事件 | stopped+owner使旧异步回调无效 |

专项`test_monster_portrait_prewarm_budget.cjs`已改为新驻留策略验证：197身份全映射、188不同地图、Bane4组件spec保持、LRU和两项保护、最新请求/旧选择取消、冷加载100ms遮罩、2/10/30秒重试、远端事件拒绝、预热先于选择的失败epoch、销毁/旧回调、197对1970目录稳定成本。`test_monster_portraits.cjs`保留全197身份、六英雄、未知/晚到身份、多选、场景重建及裸SetUnit调用为0的断言；与旧全目录预热相关的期望改为4世界与冷选择遮罩，没有删除这些行为保护。

私有逻辑计数：output/portrait_recovery_20261031/bounded_pool/logical_report.json。原生对照、正式游廊饰品画面、帧率与冷首选耗时仍由主任务验收，候选尚未编译/签名/上传。

## 复杂度及复现

只读审计工具：`tools/portrait_recovery_20261031/audit_runtime_inputs.py`。VPK目录N=6919左右（含发行元数据）只解析一次并建立path索引O(N)、空间O(N)；之后K=8项读取/CRC/hash为O(对应文件字节)，无N×K搜索。解码只有两份明确布局，各最多60秒；不加入任何运行时循环、原生桥或网络调用。CLI报告刻意保持rendered_cosmetics_verified=false、FPS_measured=false。

```powershell
& 'D:/Survival_安全工具/venv/Scripts/python.exe' -B -X utf8 tools/portrait_recovery_20261031/audit_runtime_inputs.py --view 'D:/Survival_发布候选/20261031_ws4_shop_recovery_v01_view' --installed 'D:/SteamLibrary/steamapps/workshop/content/570/3824360109/3824360109.vpk' --decoder 'D:/SteamLibrary/steamapps/common/dota 2 beta/game/dota_addons/survival/output/valley_decor_v2/source2viewer/Source2Viewer-CLI.exe' --report output/portrait_recovery_20261031/NEW_input_audit.json
```

现有生产函数专项在定位阶段通过：test_monster_portraits.cjs、test_monster_portrait_prewarm_budget.cjs、test_portrait_selection_transition.cjs、test_portrait_anchor_identity_cache.cjs、test_portrait_metadata_sync.lua。它们覆盖逻辑与模拟原生边界，当前均未复现用户线上缺件；不能因此跳过现场检查或宣称修好。私有只读结果为output/portrait_recovery_20261031/input_audit.json，content为318491d5f839653d888c350dcaa7fb639189ec427779004879819d3ac9b45352。
