# 2026-11-03｜本地 UI 短消息、完整待发盘点与发行阻断

交付状态：**仅本地更新**。本轮没有上传原游廊条目，没有部署后台 WS4。正式客户端仍为 0104，Steam manifest 为 `7025356658517360342`。源码、编译、Tools 探针、签名、普通客户端验收及官方下载是不同阶段；不能将下述局部通过合并为“已同步游廊”。本记录保留之前已发布后台补丁的历史，不重新认证或覆盖它。

## 已落实的开发路径

HUD、每日、存档和抽奖共用 `cw` 事件、单 key `d` 的 typed 整数协议；名称、图标、固定目标及奖励说明来自本地公开目录。目录为 append-only 注册表，1,314 条记录、127 字段，schema SHA 为 `0d4f78609761442e356310a7531a7a9c6f8037ad1397e3b4f8236be131245bac`。规范 LF 注册表 SHA 为 `49d5933002dd7280fdc35b75893f9d6e5dfd7e8bbb16ef07737e5c94f8134538`；工作树换行转换后的 raw SHA 不能冒充同一字节值。

公开配置来源绑定 game `0056e2bf88106a2045b0575011196d15b7ee2383`、content `cb2fa4eaa13f34ce2e566b61fef0e21926bff7c7`；这两个值是目录生成来源，不是本轮最终双仓提交号。生成时 manifest 保留 `PROTOTYPE_NOT_CONNECTED` 标识，不能把它作为当前运行接入或验收报告。实际加载顺序、控制器及两端模型另在源码和专项测试中核对。

完整 schema SHA 通过八个 uint32 校验后才绑定短 token；多片全部收齐并校验后原子提交，失败只触发一次重同步。未知字段、记录、枚举和 schema 拒绝猜测；服务端真实来源已知且显式授权的稀疏零基线才能把缺省计数解释为零。原扣券、奖励、概率、存档及资格规则仍由既有服务器逻辑负责。

存档只打开当前分类，关闭旧分类，不再启动时预取全部 20 页。当前页初始化 O(R)，真实已知变化 O(K)；无精确变化键的完整来源替换仍显式重建当前 R，不能声称其为 O(K)。普通卡片变化走身份索引，不重建整棵树。关闭或重复相同状态的抽奖展示不克隆全目录、不写原生属性。每日不再每秒或每三秒完整投影目录，倒计时依据权威截止值本地计算。详细范围及旁路限制在 `docs/reviews/network50_ui_20261103.md`；不声称项目全部网络通道均已小于 50 字节。

## 原生实测与未验边界

公开证据为 `data/ui/ui_compact_wire_native_evidence_20261103.json`，引擎 build `10938`／revision `11175759`，测量层分别为 `CUserMsg_CustomGameEvent` 和 `CClientMsg_CustomGameEvent`。`d` 为 24 个 ASCII 字节时，S2C 为 386 bits、C2S 为 390 bits，两者向上取整均为 **49 字节**；实测固定向上取整开销为 25 字节，因此 value 硬限 24。这里不包含 UDP/IP/Steam 传输头。

C2S 实际 actor 校验结果全部为 true。该证明是双向 Tools 消息预算校准，原证据明确 `ordinary_production_acceptance:false`，没有玩家交易、没有正式安装写入。它不证明普通客户端全玩法、新版电影连续播放、四人同局、FPS 或游廊验收通过。

Dev01 的新源码 Tools 副本因 content CSS 依赖不完整发生 OnDemand 加载失败，**未完成 UI 验收**；已正常关闭并退休。记录本条时 Dev02 正在补全 content 依赖，尚无通过结论。没有本轮真实 FPS 样本，不能将模拟调用计数当成 FPS 或原生 CPU 耗时。

## 编译证据与完整发行缺口

历史与当前全范围官方编译盘点有 111 次实际编译：109 成功、2 失败，另有 6 项在执行前阻断。绑定文件 `output/compact_delivery_scope_20261103/bindings_run01.json` raw SHA 为 `9030b91e8aabf0331e4c596ad0ded114f7842458b9c4461a9fb1de8af8f41782`；其编译 proof raw SHA 为 `8b19144d7b079ea979ee4864044609c7fdd404605cd92f2052169127a7f46299`。109 项作者输入、产物和 exit0 日志逐项复核过；失败及阻断项没有伪造绑定。该 proof 使用当时观察到的 Git 来源，不代替本轮最终冻结后的完整来源证明。

两项 compiler exit1 为 `custom_ui_manifest.vxml_c`、`archive.vcss_c`。六项 BLOCKED 为 `archive_180de7e38b_titles_compact_v6.vjs_c`、`archive_v10.vjs_c`、`collection_gw2.vjs_c`、`lottery_ui_remaining_5d5c1152eb.vjs_c`、`shop_tooltip_remaining_5d5c1152eb.vjs_c`、`survival_ui.vjs_c`，原因都是实际作者源已不同于该旧不可变 Git 来源。这六项不能称为编译器失败；本轮新源的独立编译与最终提交绑定仍须另外核对。

`tools/review_delivery_scope_20261103.py` 的早期只读盘点观察到 257 个不可变待发来源项、242 个候选资源和 192 个阻断项，其中 119 个编译未绑定、56 个生产转换、8 个作者绑定未编译、7 个运行删除、1 个生成绑定、1 个 SVG 映射缺口。这是 source freeze 之前的观察，之后已有 109 项官方编译证据；不能把旧数量当成最终剩余数量，也不能仅因生成了绑定文件就自动清空旧 ledger。历史未发布项和删除项必须在最终不可变来源下重新全量核对。

新完整族 `tools/complete_delivery_release_20261103/` 当前只有只读 `production_plan.py`。它要求明确双仓 40 位提交，检查保护策略、Prometheus 工具树和七项正式覆盖配置，但**尚无完整可执行 recipe、ledger、authority 或签名包**。旧固定 9 项 recipe 不能代替全范围交付。原七项正式准入／连接配置必须保持实际 0104 限制，不能将开发配置直接上传。48 张历史生成表加 `content_id_aliases`，以及新增目录和预算配置，仍需实际生产转换及逐值／行为验证；不能用临时明文 overlay 绕过。

下一步必须先完成双仓最终来源绑定、全部编译／生产转换／删除的完整覆盖，再经统一 `tools/release_pipeline.py` lease、签名与真实普通客户端准入、SDK 成功回执及官方完整下载逐文件验证。完整目标待发清单归零之前，不得写“已同步游廊”。原 0301 冻结资料及真实回滚基线保持，不用本轮未签族覆盖它。

## 可复现测试与复杂度证据

以下是实际测试程序的模拟／离线计数，不是普通客户端或 FPS 结论。Node 命令为 `node tools/<文件名>`；Lua 命令为 `lua5.1 scripts/vscripts/tests/<文件名>`；Python 命令使用 `python -X utf8 -B tools/<文件名>`。

| 测试 | 本轮结果与范围 |
| --- | --- |
| `test_release_pending_inventory.py` | 27 通过；已加至真实固定 0104 的有界祖先链验证，最多 32 代，cycle／缺失 proof 拒绝 |
| `test_review_delivery_scope_20261103.py` | 4 通过；精确资源摘要、作者映射、预算与拒绝覆盖证据 |
| `test_complete_production_plan.py` | 5 通过；只读、明确不可变提交、七覆盖取正式父字节、缺新配置阻断 |
| `test_compact_wire.cjs`、`test_compact_ui_runtime.cjs` | 分别 14、13 通过；Lua 对照、原子事务、旧回包失效及重同步 |
| `test_compact_daily_model.cjs`、`test_compact_hud.cjs` | 各 8 通过 |
| `test_compact_lottery_model.cjs`、`test_compact_lottery_cache.cjs` | 分别 6、5 通过；真实数据形状与重复缓存路径 |
| `test_compact_ui_transport.lua`、`test_compact_archive_views.lua` | 通过；关窗／稳定零发送、分类索引及异步 ACK |
| `test_archive_compact_controller.cjs`、`test_archive_compact_v10.cjs`、`test_collection_compact.cjs` | 通过；176 实际存档行 K1 更新一张卡，V10 不新建 Panel／不扫根，限定变更卡内部 18 次 Children；40 项收藏 K1 不建删／全树遍历 |

本轮 19 个 Node／Lua 专项测试中的目录／lookup／registry／budget 引用已改为实际 tracked runtime 路径，避免依赖被忽略的 `output/ui_static_catalog_20261103` 产物。存档真实 fixture 通过 Lua 投影实时生成，不依赖遗留 `archive_seed.json`。旧 `tools/tests/collection_gw2.test.cjs` 的“我的老婆”名称断言、`tools/tests/archive_lifecycle.test.cjs` 的旧 unsubscribe 数量断言与原 HEAD 已不一致，仍按旧 fixture 失败保留，未修改预期伪造通过。

20 类 945 初始行的 compact 投影离线统计为 128 片、按本机原生固定开销估算 6,201 字节；稳定为零 op，商品 K1 为一次 `project_one`、零 full snapshot。实际包数会随动态状态和 header 长度变化。协议单片预算有实测支撑，整页总量和前后台时间预算仍需在最终实际客户端观察。

## 操作中断与交接

本轮自动审批曾因 `workspace requirements permission denied` 中断约 2 小时 20 分钟。这是工作区前置检查故障，不能写成 unsafe 动作被拒绝。主操作者按 cwd 限定的 `safe.directory` 处理后恢复，game/content 两仓 stash → pull → pop 正常完成，本轮 stash 精确恢复、原历史 stash 保留。没有破坏性 reset、强推或覆盖旧候选。

最终双仓提交／推送编号尚待主操作者补入本记录；此前用于只读盘点的 game `725dc0be4ca4149f616e7096494481901030f470` 只是观察来源，不能当最终发行 source pin。当前待办保留：完整生产构建与绑定、Dev02 实际 UI、普通客户端及 FPS、实际抽奖连续演出／交易验收、签名、SDK、官方完整下载。后台 WS4 本轮未更改。
