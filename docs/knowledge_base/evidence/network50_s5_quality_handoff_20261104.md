# 2026-11-04 S5｜质量、复杂度与发行待办

**仅本地更新，后台本轮未部署。** 正式0104／Steam manifest `7025356658517360342`保持。双仓push、编译和目录生成不等于游廊同步；186项实际Lua保护已通过；完整成包、签名、同源实机、SDK和官方完整下载验证尚待。

## 当前冻结来源

- S5 game：`a717903f6219086da17f72d872f63ef8de153160`，已push。
- S5 content：`3700b2328007c157325cdf204dbe47dcf7c42a9e`，已push。
- S4 operator：`27ea3dc0c0b2607f9baad89887a005db6a512093`。
- gen5 schema：`b9f73807866a690903c06bd22d0c47f950f30a30a239f9c09936a501d55d3039`；7935记录／188字段／registry代际12。
- gen5生成manifest输入为S4 game/operator及content编译配对`419c83c184bec1af33ba62b8607b534039946722`，S5承载生成产物；不可互换生成输入、最终产物提交及未来签包来源。

**最终gen5全部148项实际官方编译及来源绑定已PASS。** 旧gen4 v2回执按历史保留，不替代本次最终回执；148是编译数量，不是148项实机功能验收。 186项实际Lua保护已PASS，来源S5双仓/S4 operator，7个override逐值与RNG验证通过；它是Lua投影证明，不是完整candidate。准备回执`final_gen5_production/production_preparation.json` SHA256为`148bb493de8dedbaba501e50d8f0a59b0660a7d8bb69bc2989a0a13ffae2cfe7`。full unsigned、sign、最终同源native、SDK成功回执与官方下载逐文件核对仍待。完整运行改动、删除和历史未发布项不得静默延期，不能回退固定几项payload配方；新候选仍须独立空目录、精确完整文件集和实际签名manifest父基线。

最终编译证明`output/compact_delivery_scope_20261103/final_gen5_all148_proof/proof.json` SHA256 `465e5506f47e52455ec9f314200df681f270b8e642a926d31327f64a15622c7a`，计划SHA256 `bbfec12a4b3ff45f92c42b1bf0e146f16bc27be3112275bd0f72142540615e99`；148项OFFICIALLY_COMPILED_AND_SOURCE_BOUND、complete=true、publication_ready=false、SDK0。补批2项演出JS/CSS也已实际官方编译PASS，证明`final_gen5_additional2_proof/proof.json` SHA256 `9ec411d4e91c988c805a46c294cbde0beb019e4680b2df03b010ead9177fde7a`；与主批同S5双仓/S4 operator，runtime源没有后续修改，累计150项编译覆盖。补批publication_ready=false，演出资源编译不等于连续视频实机验收。item严格不可变重建证明`final_gen5_item_generator_strict.json` SHA256 `c803a5b93d9f9c9662ddfb93070c19a0d14ab11ac86a2c1481ed9c04854b4e8e`，generator exit0且重建等于目标；该证明本身未编译/保护、publication_ready=false。

保护186项中，主操作者报告146项产物与实际父包字节不同，95项真实derived变化没有源Git diff（包含EOL/确定性重建），collector仍要将其补入scope，不能按Git未改而漏发。完整pending总数尚待collector/ledger归并，未知不填0；150项编译覆盖/186项保护不是可直接相加的全运行变更数，146也不是全部待发。unsigned、签名和发行准入尚未完成。

## 复杂度与可复现调用计数

完整审查文档在项目路径`docs/reviews/network50_ui_20261104_final.md`。它是当前阶段审查，旧审查和旧失败证据按历史保留。当前范围为高频同步≤50B、其他按总流量优化；不是全部自定义消息都≤50B。

武器旧growth每0.1s flush包含4个getter、实例O(N)投影、5次NetTable写和无用wake。真实函数夹具以每owner N10001、两个owner，40000growth加1000重复publish验证展示getter/build/timer/NetTable/wake均0；真实容器变化仍O(N)，四结构通知合并1build/4getter/1combined写。实际攻击和击杀charges规则及setter次数保持，0展示网络不等于停止玩法更新。

tooltip visible的1000稳定tick仍有1000当前slot读，但文字、visible、美术、native-hide、position及重绑写0；不扫六slot。变化只写当前物品固定至多5缓存行中的差异，关闭后slot读0；MAX、明确native-charge计数、spectator和Dispose边界保留。

未知地图位图首次仍O(bytes+cells)，先整体验证再有界应用；每Step最多512格，按真实2ms检查，可能超出至多一个16格quantum。稳定1000次Apply的word访问增加0。单格K只访问8格block；16分散格为16block/128格，不扫65536长列。四实例索引独立，新full/epoch/scope/owner/close取消旧组包和geometry。真实地形扫描亦按耗时钟分批，权威validate不由旧bitmap取代。

可复现命令（game根目录；均不是native/FPS）：

```powershell
& 'C:/Program Files/lua/bin/lua5.1.exe' tools/test_weapon_snapshot_growth_batch.lua
& 'C:/Program Files/lua/bin/lua5.1.exe' tools/test_weapon_max_progress.lua
node tools/test_inventory_tooltip_broadcast_scope.cjs
node tools/test_compact_grid_bulk.cjs
node tools/test_grid_bulk_index.cjs
& 'C:/Program Files/lua/bin/lua5.1.exe' tools/test_grid_elapsed_budget.lua
node tools/test_public_beta_startup.cjs
node tools/test_compact_public_beta.cjs
node --test tools/test_public_beta_gift_ui.cjs
python -X utf8 -B tools/test_network50_process_query.py
```

命令用于重现专项成本；148项官方编译有独立真实回执，不由这份命令清单代替。本轮文档工作没有启动Dota、采集新FPS或执行SDK。

## 原生/FPS的真实范围

- **Dev06无效**：采样期间原生日志出现PLAYER_DEFEAT；旧缓存不能把它重新认作游戏中性能样本。
- **Dev07有效的开局无遮挡30s**：v2平均60.000356FPS／P95 16.799335ms；v1 P95 16.947880ms／最大30.3278ms，engineering_gate=false。不是战斗、高负载、四人或gen5最终性能；gift覆盖首段另算overlay，1Hz前台采样不保证每个中间帧无遮挡。原证据见[Dev07来源与限制](network50_dev07_native_fps_20261103.md)。
- **Native08只收数值**：最终闭合日志SHA `673ca35b24437835a05fd686fdfd99cf9ac5ea1631dcc41752813ae9913a4cb4`，gen4 Hello八字精确匹配9e5d7b6e…，cw698帧／33427B／最大49B、解码失败0／Lua/JS运行错误0。后期mode/N1输入来源未知，不认视觉或交易验收。view7/9实际短包可计数，view10缺席不认Beta通过；之后的Beta独立XML依赖/late-runtime修复和gen5均不在这轮实机内。
- **bulk02为独立尺寸探针**：gb/d 64/128/256/512/896 ASCII实测89/155/283/539/923B，最大923<1KiB。大载荷封装27B，不沿用小包25B；不是实际完整网格传输总量或FPS。Client10938:11198969与旧cw的11175759不同，即使networksystem.dll摘要相同也不冒称同revision。见[闭合原生证据](network50_grid_bulk_native_20261103.md)。

Native08的抽奖view201实际known0/error2，没有request-token/receipt字段；draw/exchange/claim字样仅注册行，无抽奖结果或HTTP/ledger/ACK标记。S2C日志不足以排除任意未知外部C2S输入，本代理没有发起消费/兑换/礼包领取。授权30券须按实际账目管理，不能因日志缺结果就补券或重放。

Native08现已正常WM_CLOSE、严格宿主CIM确认所有Dota为零，并retire确切两实验junction，树外快照与证据保留。旧CIM查询的非终止错误会伪空，现改为ErrorAction Stop且JSON须显式数组，查询失败不能授权close/retire；4专项通过。

## 本机连接、审批与下一步

飞鸟主19613的local Git proxy配合OpenSSL已恢复小步Git通路，TLS校验保留开启，不在文档存认证参数。Git网络问题、自动权限审批超时、sandbox外部写入拒绝和旧CIM伪空是不同边界；不能把一次网络修复写成全部权限失败的解释，也不追认超时动作实际执行。

Beta根治独立CustomUIElement加载顺序：自己XML先加载catalog/codec/bulk/runtime/model，controller仅在startup及真实loading/admission/原失败状态读事件转接，无新增依赖轮询。1000相同事件0重建/重复Open；退旧legacy listener，runtime/world换代Dispose旧view，queued旧回调失效；5启动专项与原compact4/UI22通过，最终同源实机仍待。

接手顺序：归并最终collector/ledger完整待发 → 使用已过的gen5官方编译主批148+补批2项与186实际保护及逐产物回执构建全scope unsigned/签包 → 最终来源实机及各未测交互 → 统一lease与父manifest门禁下SDK上传 → 官方完整下载逐文件一致。只有完整目标待发为空且所有交付证据闭环，才能改称“已同步游廊”；本条待办保持。
