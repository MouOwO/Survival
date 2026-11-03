# 2026-11-03 追加｜网格与选中单位短消息，本地未发行

**仅本地更新。** 用户要求继续完成未收口的消息优化后，追加网格视图与选中单位视图。正式游廊仍为 0104、Steam manifest `7025356658517360342`，本追加没有后台 WS4、SDK 上传或官方完整下载。前一阶段记录见[本地 UI 与完整发行阻断](network50_ui_local_handoff_20261103.md)，其中旧目录规模和 schema 作为历史保留。

core 阶段曾完成双仓 push：game `1f160c3a848e57db81f5b9498cc0d59b733fc501`、content `c04eb46dab7ecf0781ef2d618baebb0ce2758d6b`。**本追加不属于这两个提交**；本追加最终提交／编译／原生验收结果待主操作者另补，不能将 core 提交当作新目录的发行来源。

## 唯一注册表与两端 codec

目录当前为 **7,887 records、163 fields、generation 10**，字段允许上限从 127 扩至 255。旧 1,314 个记录及旧 127 个字段的编号和含义逐项保留，后续新增也只尾部追加。`data/ui/registry_history` 的十代完整链保留；当前 registry SHA 为 `e48c13b036086e5de6fb9c6c51c0bc87f693aa59b18b74c907feb35f03b9fd84`，父代为 `ab2bb9f63fe36d9e9ed16b3ba20e3f5a16693c8eccd52cf1918d9ae09942c4ec`。

当前 schema SHA 为 `004ce5aa7d05fadea5ad67259a28f4ce3c5f8e4aec8f24eb091eacc8e8f001a1`。公开生成配置仍绑定 game `0056e2bf88106a2045b0575011196d15b7ee2383`、content `cb2fa4eaa13f34ce2e566b61fef0e21926bff7c7` 的不可变内容。新 seed、selected schema 和本轮预算改动的代码摘要分别显式记录为需要最终 operator／source 提交的生成输入，没有冒称其属于旧来源提交。

Lua／JS codec 同时扩容；去重索引由 `record*128+field` 改为 `record*256+field`，避免 `(record1,field129)` 与 `(record2,field1)` 碰撞。255 仍用 varuint，分片后的 `d` 上限保持 24 ASCII 字节；既有 v1 golden 字节不变。未知或未注册 ID、256 字段、错 schema 仍拒绝。49 字节的本机原生校准证据继续仅适用已测引擎消息层，不是新增普通客户端验收。

新增字段包括 grid 128—155、selected 156—160、`grid_map` 161、`grid_atlas_base` 162、`selected_value_int` 163；实际消费者须使用 `ByKey`／`FieldIds`，不能由 ID 加减猜映射。社交概率的字段没有拿来伪装其他数值。selected 的一般整数、IEEE754 高低字、正零 mask、未知及负零各有明确表示，保留原数值精度。

## 本地目录与初始化

`common/ui_static_catalog.js` 在创建 4 MB 数据 literal 前检查共享同 schema 对象，同版本两个真实 XML 入口复用一次索引／冻结；新 schema 仍替换。公开只读索引为 `ById`、`ByKey`、`FieldIds`。初始化 O(N+F) 一次，相同 schema 再加载不重复建目录；各模型共享不可变索引，每个实例只保存自己的动态状态。

最终规范 LF 来源摘要：

| 文件 | SHA256 |
| --- | --- |
| `panorama/src/scripts/custom_game/common/ui_static_catalog.js` | `fb9ea4fc1814cc1250308c4331be92c40f11e6d95e9cfe4358073a6765dd0433` |
| `scripts/vscripts/config/generated/ui_static_catalog_lookup.lua` | `81797db6158948c012c074227e4b76b5613e0e8f72fe77542c58e214453cd8d5` |

JS 为 4,047,453 字节、Lua lookup 为 2,603,437 字节；这些是作者源摘要，**不是官方编译资源 SHA 或签包摘要**。生成 manifest 保留原型输出状态，实际 runtime 接入须以最终源码／编译／真实客户端证据为准。

两次实际生成脚本加载的 Node 计数：首次 `Object.keys=30061`、`Object.freeze=29011`、`Object.create=1055`；同 schema 第二次三项均为零、原生调用零。这是模拟调用计数，不能换算成 Dota CPU/FPS。

## 网格候选 atlas 与权威边界

`tools/extract_grid_static_atlas_20261103.py` 从已关闭 Dev04 日志提取两条完全一致的公共 v3 bitmap，只保留地图数值／bitmap／来源摘要，不提交原始 KV、scope、session 或 account。公开候选为 `data/ui/grid_static_atlas_candidate_20261103.json`，raw SHA `ba7df0ffa04e730825dd9393c0b1d48f9930b0dd183d0886fe06fd548db6f80b`。

Dev04 外部文件 manifest raw SHA `ac45847850e8d28abe8eb7b0cd039f8e00d5cbefd268de99356c99eaf6ca6d6c`；实际 `maps/template_map.vpk` SHA `59c5856b44a75a3db5659fb15dd2038480a102c450ae5a27141e890b201bcf33`。候选为 96×96、576 个 two-bit word，area 4,630 ASCII 字节，来源配置和算法六个文件都经过逐字节摘要核对。

候选**不是建造权限**。服务器每局仍真实扫描 terrain／tree／region，完成后比对全部实际 word；只有地图、范围、模式、算法兼容元数据匹配，才能发送 `known=1`、base1 和真实 K 个覆盖 word。显式 word0 会覆盖非零候选，缺失 word 才复用已确认的对应基线。未知地图、未完成扫描、元数据不匹配时保持 unknown 或走有界完整路径，不假定可建，不改变原 validate／commit 判定。

为每格检查真实耗时，原 static scan 的 `count>=8` 改为 `count>=1`。旧候选来源 SHA `94083fff2eadff49ee3024d83eaa3c9bbefcaa0bd9404eee220b1b9274429542` 保留；新规范 LF SHA 为 `c485492c5b96c4ede51d4e8a2b2fa8b57a54a3197526715ac1e1998873c5482a`。兼容工具只接受这一条完整表达式的精确替换，另五个公共文件也必须逐字节一致。结果明确 `binding_matches_source=false`、`runtime_source_compatible=true`，附新旧摘要和单 hunk 证明；不伪造旧源等于新源。真实扫描及逐 word 比对依然必须执行。

4,390 个 grid records 包含 4,352 个 word 容量身份和 11 个真实 profile 等元数据，不会初始化每玩家 4,352 个待发 payload。初始化索引共享一次；稳定零读／发送，真实变化 O(K)。未知地图完整 fallback 的总字节仍可能高于旧单包，不能只用“每包49”掩盖这项限制；新地图应补独立、可验证的候选并重做真实客户端检查。

## 选中单位来源与精度

selected 视图复用原真实 `unit_combat_snapshot`；静态 unit／model／wearable／武器／显示名来自不可变公开配置与 NPC 根的 `#base` 递归。生成器只提供 Git 中 8 个 tracked `scripts/npc/**/*.txt` 的虚拟只读文件，最多 512 文件、64 MiB 总量、每文本 8 MiB；不读取未跟踪文件或真实私有文件。递归 seed 规范化路径、拒绝根外访问并防环，未知字符串不走大文本网络回退。

当前 126 numeric paths、27 text paths、2,024 个本地静态 text 值。资源字典 key 使用 UTF8 内容 SHA，保留实际文本值；所有新 ID 只尾部追加。真实未知资源只标记该子字段 unknown，已验证战斗数值继续显示，旧单位／旧 token 不得冒充新单位。玩家姓名仍使用本地玩家 API，不复制进公共目录。

关键首屏和辅助 tooltip 分事务发送，精确保留整数、float、正零、未知、大整数及负零。同 entindex 的 A→B→A 切换也以 selection token 防止旧回包复活。稳定的源版本变化不产生显示变化时，1,000 次更新为零 op。

## 复现结果及剩余待办

以下均是实际 Lua／JS 模块的离线 fixture／调用计数；不是新增原生耗时、FPS、普通客户端或真实交易结论。

| 命令 | 结果 |
| --- | --- |
| `python -X utf8 -B tools/test_ui_static_catalog.py` | 18 通过；历史链、255 扩容、双入口 guard、候选 mismatch、单 hunk 兼容、真实配置 |
| `python -X utf8 -B tools/test_extract_grid_static_atlas_20261103.py` | 3 通过；只留公共 bitmap、不同区域拒并、open／错误状态拒绝 |
| `node tools/test_compact_wire.cjs` | 15 通过；实际 Lua golden 对照、129／255 边界、碰撞与 unknown／256 拒绝 |
| `node tools/test_compact_grid.cjs` | 7 通过；真实 geometry、候选 live 确认、显式0、共享索引及实际控制器 |
| `node tools/test_compact_selected.cjs` | 8 通过；真实 DTO／wearable、A-B-A、首屏／tooltip、数值与 unknown 子字段 |

当前目录 `--check`、JS 语法检查及十代 registry history 均通过。grid fixture 的 full 为 29 帧／估算 1,415 B；普通 Kdelta 为 1 帧／49 B。同候选 static K0 为 6 帧／285 B，对比旧 area 4,630 ASCII B／旧 native 4,813 B；K1 为 1 帧／48 B。仍真实检查 576 words；K0 客户端不读取动态 word records，本地恢复的 9,216 cells 与候选逐项一致。100 次模型 Create 共享 capacity 索引，ByKey 读取不超过 500 次。

selected fixture 62 full ops：production 首 header 45 帧／估算 2,195 B，最后 epoch 50 帧／2,446 B，codec 最大 header 67 帧／3,277 B；关键首屏 27／30 帧，辅助 19／21 帧。四人共用 160 packets/s 下，关键队列理论值 0.675／0.75 秒，不代表真实 RTT 或保证响应时间。

新增视图／首屏／atlas 还须在最终同源编译后的实际客户端观察、检查所有剩余 legacy 大包旁路和真实 FPS。完整生产构建、所有历史未发布项／运行删除／保护转换、完整0302 recipe／ledger／authority、签名、普通准入、SDK 与官方完整下载依旧没有因上述测试自动完成；待发清单不能清零，不能标“已同步游廊”。

## 后续追加：严格 Git gen2，最终产物提交仍待

本节是后续阶段，前文 `004ce5aa…` 及其工作区原型来源按历史保留。**仍仅本地更新**，本节没有 SDK、签名、后台或官方下载结果，也没有新增普通客户端／FPS通过结论。

phase2 输入源码及 operator 已冻结并双仓 push：game／operator `c8722ee2d2e21fdbfaf23d4b7b0fdff952a6fcb4`，content `5bdd96279a6cd05d6ee513dc90fad6891479ae0e`。严格 gen2 使用这些明确 Git 提交，历史 atlas 另明确指定 game `0056e2bf88106a2045b0575011196d15b7ee2383`。协议 schema、原生候选、六个当前 grid 源、NPC、registry 和全部 history 均从所选 Git blob 读取；seed 从 operator Git blob 读取；执行生成器／helper 也须与 operator 的规范 LF 字节一致。不存在读取临时工作区后冒称新 source 的回退。

生成结果：schema `fe171856112a688beca04f89951cac8c81df69d238ffa02be38758f9741a3748`。registry 保持 `e48c13b036086e5de6fb9c6c51c0bc87f693aa59b18b74c907feb35f03b9fd84`，仍为 7,887 records／163 fields／generation10；旧 ID、字段和十代历史未变。生成输入有 208 个 game blob、3 个 operator blob、6 个历史 atlas 参考源。`ui_static_catalog_lookup.lua` 自身及预算生成文件不作为旧投影的依赖载入，避免目录自引用。

`data/ui/ui_static_catalog_manifest.json` 包含全部来源摘要，当前 raw SHA 为 `c2f087dc78b7f0da20c828d9456f5846832484f95962ceb033a547515748ea93`。content revision 在此仅标示配套编译来源，生成器没有读取 content blob；纹理／编译资源仍必须单独绑定，不能把这个 revision 字段当成美术或编译证明。

| gen2 文件 | 规范 LF SHA256 |
| --- | --- |
| `panorama/src/scripts/custom_game/common/ui_static_catalog.js` | `0e3a82ef1c81a6bedf872d2a2f63b6bc78c3684814cc8d3a768a449b27039467` |
| `scripts/vscripts/config/generated/ui_static_catalog_lookup.lua` | `43955e5e4a9d82468bf25e6e62271c99a172d0ebc0453f8cf2ffbf1c918a4031` |
| operator `tools/build_ui_static_catalog.py` | `9e3a522044189926d7cd627543e9faa58f774717665cb1dec3c1bfce3bc9bb7a` |
| operator `tools/extract_grid_static_atlas_20261103.py` | `a07f3374ba40e92b34d0a9f81339ec996615b5db4e94636b24010ae9da2cff69` |
| operator `tools/selected_stats_static_seed.lua` | `5dadf55d43d6e44f7bb99530ec31f62d83084aeefa2d48838f3f9caabd4c4e8d` |

gen2 CLI `--check` 已复现同一输出。真实模块边界复跑：wire15、runtime15、grid9、selected8通过。runtime 新增独立 full C2S 丢片恢复；grid 包含四 owner 隔离、模式 scope 退役和迟到 word 拒绝。当前静态 K0 在 fixture 为6帧／估算292 B，K1为48 B，full29帧／1,415 B，C2S输入10帧／488 B。前文285 B属于之前阶段；这些仍是模拟校准字节，不能写成新的 native 实测。

主操作者报告同源官方28文件编译完成，gen2 catalog `.vjs_c` artifact SHA 为 `07d0d453c5aa7ea9bac2fc3adf1793dd7accbf4d56c1cc6f39c947f2e04c1e10`。生成后的 game／content 最终产物提交尚待，因此上方 c872／5bdd 是**生成输入冻结**，不是已包含新 gen2 产物的最终发行 source pin。后续实际 Tools／普通客户端、FPS、签名、SDK及官方完整下载均另记，不能从这条编译回执推定通过。

生产变换准备也已落 `tools/complete_delivery_release_20261103/production.py`：四个纯配置取真实0104已审字节；addoninfo保留新 lobby并恢复正式入口／四人容量，client入口保留 hosted lobby 初始化，admission保留当前去 onboarding 的逻辑。旧只读 plan 已将这三项旧 parent target 清空并指向明确变换，避免重新覆盖丢逻辑或复活已删 helper。production8、plan6测试通过；真实0104／不可变源的五账号与拒绝相邻第六账号、四配置常量、lobby／原入口均做了纯逻辑探针，未做实际 Steam 登录。

只读复核当前保护选择为186项，仍需实际固定 Prometheus 全值／RNG验证。真正保护导出应等待包含新 lookup 的最终 game 第二提交；以 c872 导出会拿到原型旧 lookup，不能与新 JS 混包。完整 recipe／ledger／authority及发行验收仍阻断，不造 ready。
