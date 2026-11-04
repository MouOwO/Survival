# UI 同步优化：来源、复杂度与交付审查（2026-11-04）

**仅本地更新，后台本轮未部署。** 此处“本地”包括已提交、已 push 的工程和构建工具；不代表游廊已更新。正式版本仍为0104，Steam manifest `7025356658517360342`。186项真实Lua保护已通过；完整成包、签名、同源实机、SDK上传及官方完整下载核对仍待完成。

本文更新2026-11-03审查的阶段状态，旧文件和旧失败证据按历史保留。当前用户目标为高频自定义同步消息每条≤50B，其余路径按真实总流量优化；未知地图冷位图另有低频≤1KiB的授权范围。没有把所有事件改名为低频，也没有以拆成49B而总流量大增作为完成标准。

## 当前来源和门禁

| 项目 | 本次记录的真实状态 |
| --- | --- |
| S5 game | `a717903f6219086da17f72d872f63ef8de153160`，已 push |
| S5 content | `3700b2328007c157325cdf204dbe47dcf7c42a9e`，已 push |
| S4 operator | `27ea3dc0c0b2607f9baad89887a005db6a512093`；不能用operator提交替代双仓运行来源 |
| 当前生成目录 | 生成轮次gen5；schema `b9f73807866a690903c06bd22d0c47f950f30a30a239f9c09936a501d55d3039` |
| ID registry | 7935条记录、188字段、registry代际12；既有ID及tombstone保留，字段上限255 |
| 官方编译 | gen5主批148项与补批2项均实际官方编译/来源绑定PASS，累计150项覆盖；两批原回执分别保留，不是150项游戏功能验收 |
| 生产转换 | 186项实际Lua保护PASS；7个override逐值与RNG验证通过。它是Lua投影证明，不是完整candidate或签包 |
| 完整交付 | full unsigned、签名、最终同源native、SDK成功回执、官方下载逐文件验证均待 |
| 正式/后台 | 正式0104保持；本轮后台未部署；待发清单不能清零 |

186项保护来源为S5 game/content及S4 operator。准备回执`final_gen5_production/production_preparation.json` SHA256为`148bb493de8dedbaba501e50d8f0a59b0660a7d8bb69bc2989a0a13ffae2cfe7`；该PASS只覆盖实际Lua投影、7个override逐值及RNG，不能推断完整候选的资源闭包、签名或native已经通过。

gen5生成manifest记录的输入game/operator为S4 `27ea3dc0…`，content编译配对输入为`419c83c184bec1af33ba62b8607b534039946722`；S5提交承载生成结果及配套资源。生成来源、产物提交和未来签包来源是三个层次，不能互换。目录中的原型/连接状态标签也不是SDK或正式安装成功回执。

发行仍以实际正式签名manifest逐资源比对，覆盖两仓运行源、编译结果、素材、删除和全部历史未发布项。新候选须使用独立空目录与精确完整文件集；未编译、未知映射或未经验证的保护产物应阻断。不能回到旧固定少量payload、忽略延期项，或恢复0104后宣称新修复已发布。上传完成也只能先称“已上传，待官方下载验证”。

## 最终编译与完整待发的计数边界

最终gen5官方编译证明为`output/compact_delivery_scope_20261103/final_gen5_all148_proof/proof.json`，SHA256 `465e5506f47e52455ec9f314200df681f270b8e642a926d31327f64a15622c7a`；counts为148项`OFFICIALLY_COMPILED_AND_SOURCE_BOUND`，complete=true，但publication_ready=false、SDK=0。计划SHA256 `bbfec12a4b3ff45f92c42b1bf0e146f16bc27be3112275bd0f72142540615e99`，来源S5双仓/S4 operator。这里的148是编译产物/来源绑定数量，不是148项实机功能通过。

补批另有2项`lottery_cinematic_v1.vjs_c`与`lottery_cinematic_v1.vcss_c`实际官方编译PASS；证明`output/compact_delivery_scope_20261103/final_gen5_additional2_proof/proof.json` SHA256 `9ec411d4e91c988c805a46c294cbde0beb019e4680b2df03b010ead9177fde7a`。它与主批保持相同S5双仓/S4 operator，runtime源未再修改，累计编译覆盖为150项。补批complete=true但publication_ready=false；演出JS/CSS编译不能替代连续视频/兜底/结果的实机观察。

item资源严格不可变重建证明为`output/compact_delivery_scope_20261103/final_gen5_item_generator_strict.json`，SHA256 `c803a5b93d9f9c9662ddfb93070c19a0d14ab11ac86a2c1481ed9c04854b4e8e`。generator exit=0、immutable_rebuild_equals_target=true；它本身compiled=false、protected=false、publication_ready=false，不代替其他编译、保护或发行门禁。

主操作者报告：186项保护产物中有146项相对实际父包字节不同，真实derived变化中95项未出现在源Git diff内，原因包含EOL/确定性重建。collector将把这些资源按实际产物摘要补入scope，不能因为源Git未变就漏发。完整待发总数仍待最终collector/ledger归并；不能把150项编译覆盖与186项保护直接相加当完整运行变更数，也不能用146代表全部待发。其他源/素材/删除/历史未发布项继续保留，未知计数不填0，完整unsigned/sign尚未完成。

## 复杂度与实际调用计数

N为真实容器/目录规模，K为本次变化项，F为触发频率，B为位图字节，C为位图格数。下列计数来自真实生产函数的Lua/Node夹具，属于模拟/API调用计数，不能直接转写为native耗时或FPS。这些专项API计数与148项官方编译是不同证据；最终同源实机仍是独立待办。

| 路径 | 旧成本 | 初始化/容器重建 | 稳定状态 | 真实变化、预算与失效 |
| --- | --- | --- | --- | --- |
| 武器展示快照 | growth每0.1s flush：4个getter、tooltip实例O(N)投影、5次NetTable写及97B无用wake | 仅真实结构变化读取4来源，O(N)重建一次combined元数据 | 两owner、每owner N=10001，40000个growth事件加1000次重复publish：getter/build/timer/NetTable/wake均0 | 四种结构通知合并为1build、4getter、1combined写；重复相同容器burst仍会真实读取一次但0重复写。hero替换/移除、重入与init取消旧工作 |
| 武器实际玩法 | 攻击/杀怪进度和原生charges仍是权威路径 | 原规则和原setter保留 | 不通过停止玩法更新制造0展示成本 | 真实函数10次攻击：charges200→190、10setter；10次击杀：215→205、10setter。展示查询移除不改变这些次数 |
| 可见物品tooltip | 不能每tick扫6个slot或重建全部字段/美术 | hover时绑定当前slot、实体和缓存行 | 1000次visible tick：1000次当前slot读，文字/visible/art/native-hide/position写0，重绑0；关闭后slot读0 | 仅当前物品、固定至多5行中真实变化的值写桥；kill计数仅明确的native-charge路径读取，MAX/icon-only例外保持。换selection、移除、spectator、Dispose使旧回调失效 |
| 公共目录/transport | 完整名称/图标/规则随重复快照发送 | O(N)建立共享ID/字段索引；同build/schema的多XML复用 | 同状态0发送、0全目录clone；空队列0timer | 只编码K；session/epoch/view/revision严格绑定，C2S独立完整命令仍单调revision、不自动重放消费。全局16ms窗口至多8urgent/2background且累计native工作2ms预算 |
| 网格真实静态扫描 | 同步扫整图后再分网络片，不能解决首帧CPU峰值 | 真实地形/区域扫描按有限工作量和真实耗时钟分批；非本地候选的假权限 | 同scope重复来源不重扫、不重发 | native判断仍是权威；用户当前≤16格footprint优先，scope/owner/world/close取消旧批次。elapsed测试即使游戏时钟固定也继续分批 |
| 模板地图本地候选 | 旧area约4813B；强拆小包曾约27633B/577帧 | 只在当前局真实扫描、逐word比对成功后发候选ID和K覆盖；候选不是永久可建权限 | K=0不发送576个word | 旧专项校准K0约292/293B、K1为48B；精确值依协议头/场景，不冒称新的gen5实机总量 |
| 未知地图bulk | 577小帧/约27.6KB，超过旧单area约4.8KB | 真正2bit位图O(B+C)，两阶段先校验再应用；每Step≤512格、检查真实2ms | 1000次相同Apply：word访问增加0；稀疏索引初始O(1)、0格读取 | 每个local patch≤16格，耗时检查可能最多超出一个16格quantum；不是严格单步绝不超过2.000ms。K变化只修触碰的8格block，不重扫长列。全量/epoch/scope更换清旧assembly和旧geometry |
| 稀疏网格索引 | 1×65536长列若重扫整列，K1仍O(C) | 空bulk index O(1)，四实例独立 | 1×65536和256×256各1000稳定调用：0格读/0block访问 | 一个格改变只读8格；跨3个block的16格patch读24格；16个分散格访问16block/128格。真实configure单格覆盖读8dynamic和16static采样，保留块外旧几何 |
| Beta启动/换局 | 独立XML若先加载，controller仅首次尝试compact，之后可能永久没有view10 | 自己XML显式加载目录→codec→bulk→runtime→model→controller；一次创建view | 1000个相同loading事件不重建、不重复Open，不新增依赖探测timer | late依赖仅由startup/真实loading或原admission/一次失败状态读转接；退legacy listener和旧view，旧queued回调失效。保留原奖励/nonce/ACK与profile确认规则 |

上述0计数的含义必须保留：武器0的是展示全量getter/网络，不是攻击或charges停止；tooltip稳定仍有当前slot的O(1)读取；真实结构重建仍为O(N)；位图首次仍为O(B+C)，预算与取消并未使它变成O(1)。2ms预算由真实时钟检查实现，Node模拟时钟与原生单次API的不可抢占耗时不能混为一谈。

## 可复现专项

以下命令不启动Dota、不消费券、不调用SDK；需在game根目录运行。它们重现上述调用计数和生命周期约束，并不替代已单独完成的148项官方编译证明，也不替代实际客户端验收。

```powershell
& 'C:/Program Files/lua/bin/lua5.1.exe' tools/test_weapon_snapshot_growth_batch.lua
& 'C:/Program Files/lua/bin/lua5.1.exe' tools/test_weapon_max_progress.lua
node tools/test_compact_selected.cjs
node tools/test_inventory_tooltip_broadcast_scope.cjs
node tools/test_inventory_tooltip_stability.cjs
node --test tools/tests/inventory_tooltip_dismiss.test.cjs
node tools/test_compact_grid_bulk.cjs
node tools/test_grid_bulk_index.cjs
& 'C:/Program Files/lua/bin/lua5.1.exe' tools/test_grid_elapsed_budget.lua
node tools/test_public_beta_startup.cjs
node tools/test_compact_public_beta.cjs
node --test tools/test_public_beta_gift_ui.cjs
python -X utf8 -B tools/test_network50_process_query.py
```

武器hot-path夹具输出40000growth/1000publish的0计数和结构重建计数；tooltip夹具输出1000visible tick、单slot/closed0；bulk model5组、block index7组、Beta启动5组/原compact4组/原UI22组与process query4组的历史结果均须保持其各自来源，不能用命令清单代替实际执行回执。

## 原生与FPS证据的边界

| 证据 | 可以证明 | 不能证明 |
| --- | --- | --- |
| Dev06 | 留有原始capture和日志，可复核失败原因 | 采样区间实际PLAYER_DEFEAT，已作无效FPS样本；旧HUD缓存不能把它重新变成游戏中样本 |
| Dev07无遮挡N1开局30s | 两ETW collector实际数据；v2平均60.000356FPS，P95 16.799335ms；v1 P95 16.947880ms，最大30.3278ms；engineering_gate=false | 不是combat、高负载、四人、普通签包或最终gen5性能。1Hz前台样本/前后截图不能保证每个中间帧均无瞬时遮挡；gift覆盖首段另算overlay |
| Native08闭合日志 | gen4 Hello八个uint32精确重建schema9e5d7b6e…；cw698帧/33427B/最大49B、解码失败0、Lua/JS运行错误0。出现view7与9的真实短包 | 后期mode/N1输入来源未知，root和本代理均未确认来源，不当作视觉或交易验收。view10缺席不能称Beta通过；该运行也不含之后的Beta独立加载修复或gen5最终目录 |
| bulk02独立最小Tools探针 | gb/d五档64/128/256/512/896 ASCII原生89/155/283/539/923B；最大923<1024。Client10938:11198969，正常闭合 | 不是实际整张网格的四片/metadata/K/重同步总量，不是FPS或普通客户端验收；不把大payload的27B封装当成旧小包25B |

Native08闭合日志SHA为`673ca35b24437835a05fd686fdfd99cf9ac5ea1631dcc41752813ae9913a4cb4`。其mode/difficulty结果出现在11/04 07:12:08和07:12:09；此前代理截图只观察到模式页。该局抽奖view201实际known0/error2，无request-token或receipt字段；日志内draw/exchange/claim字样只对应listener注册，未见抽奖结果或HTTP/ledger/ACK标记。S2C日志不能单独证明任意外部C2S输入从未发生；只确认本代理没有发起消费、兑换或礼包领取。

Native08已由错误即终止的宿主CIM核对原PID/创建时间，正常WM_CLOSE，可靠确认所有Dota进程为零后退役两个exact-owned junction；快照与证据保留。不能沿用旧查询非终止错误造成的“ALREADY_EXITED”假空结果。安全数值原件在`output/network50_dev_20261103/run08`及项目`data/ui/ui_compact_native08_observation_20261104.json`，后者SHA `f2599f2b2a254ad0d24ad36da864fda39d6169a629ba35c7100405beba4fd8c1`；不复制raw身份、session或网络字串。

bulk02日志SHA `ce05e75e1373de45e37d10a9232b387d6ac49ad15089f79a9f32c0c54ff9ceac`；公开证据`data/ui/ui_grid_bulk_native_evidence_20261103.json`。相同`networksystem.dll` SHA `7acebae0…`并不意味着Client revision相同：旧cw标定是10938:11175759，本次bulk是10938:11198969。独立bulk实验挂载亦已正常退役，LAB和回执保留。

用户30张普通券授权仍须按真实账目累计。未观察到结果不等于可自行补券、代用码、重放消费或宣称交易验收；新普通客户端同池连续演出仍须单独核对实际视频/兜底/错误文本/结果。

## 权限、网络与后续工作

本机Git经飞鸟主端口19613的local Git proxy与OpenSSL配置恢复小步访问，TLS证书校验保留开启；凭据、认证代理细节不进入文档。此处仅说明Git通路：此前自动权限审批确有超时，部分外部挂载写入也被sandbox拒绝；旧CIM非终止错误又造成伪空进程列表。这些是不同边界，不能用“Git网络错误”解释全部权限失败，也不能因后来网络恢复就追认先前审批超时动作已执行。

下一步基于已通过的gen5主批148+补批2项官方编译、186项真实保护及逐产物回执，先收口完整待发账本并构建全scope精确unsigned候选，再签名并按其来源进行实际验收。保持全部当前/历史待发项和运行删除项可见；在统一发行lease与父manifest校验下上传，取得SDK成功回执后完整官方下载逐文件对齐。普通实机、全网格/生产/支付/Beta、在线/四人、连续抽奖演出及最终性能边界按实际完成范围记录，未测项不推断通过。只有目标待发为空且官方验证闭环完成，才能改称“已同步游廊”。
