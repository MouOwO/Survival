# 2026-11-03 phase3｜生产界面恢复及剩余旧消息收敛

**仅本地更新，后台未改。** 正式游廊仍为0104，Steam manifest `7025356658517360342`。本节没有签名、SDK上传、官方完整下载或新增普通客户端／FPS通过结果。

phase2最终双仓已提交并push：game `173fb251b64c087f6a3a3200cc3704016b3d5852`、content `9f8be070deb3defb097357cf5d2e6fd8544dd569`。当前实际runtime目录仍是schema `fe171856112a688beca04f89951cac8c81df69d238ffa02be38758f9741a3748`、7887 records／163 fields／generation10。以下phase3代码已冻结、等待新双仓source提交，不能把工作区原型当成上述旧提交内容。

## 生产与VIP

修复selected compact接入后丢失生产展示的回归：生产单独使用私有view7，复用原训练／研究／取消／自动研究服务，保持真实价格、前置条件、队列和退款逻辑。选中对象与selection token配对，A→B→A旧包不能覆盖当前对象；消费请求使用独立nonce，八槽回执环保留快速连续操作结果。时间使用精确binary64高低字、本地重建进度，不逐秒广播整张生产表。

只读seed执行真实配置和描述函数：8训练、19研究、420正等级及19个等级0显示行。累计效果、跨级reserved目标说明、字段和成本原值来自同一配置；17位数字导出保留binary64低位，不把实际玩家折扣或资格冻结成本地常量。计划追加44条production记录与字段164～186，另加仅known/count的`vip:state`一条记录，合计计划7932 records／186 fields。唯一ID历史只追加；本阶段尚未生成实际新目录，须先冻结seed/helper和双仓source，再严格从Git重生成、官方编译并再次提交产物。

VIP只保留现有被动等级徽章活消费者所需的known与level(count)，使用view8。原充值等级算法与奖励逻辑不变；仅真实充值总额变化时重新计算等级，未知profile不能假定等级0。旧VIP大snapshot仅兼容实际订阅的player handle，旧owner／world与关闭后的回包退役。

## 触发、稳定成本与其他旧旁路

生产本地索引初始化为O(8+19+439+7+8)，共享同schema元数据；真实生产快照只走当前对象与其有界队列，变化按K字段编码。1000次相同生产模型更新不新增record访问；1000次实际controller稳定刷新零原生写入。工人商业容量bonus缓存按player建立，仅bonus实际变化才修改tracker并发`WORKER_CHANGED`，reset时清理，修复容量变化后生产HUD不更新的问题，不增加轮询。

175份UI作者源码审计未发现`ui_hero_summon_state`活消费者，旧英雄大包改为显式订阅后才发送；保留六个原生祭坛召唤能力及三处实际付费权限检查。真实商店解锁消费者仍连接，重复解锁状态去重。这不是删除英雄召唤逻辑，也不声明所有旧旁路均已迁移。

公测好礼去掉profile未就绪时每5秒重复快照请求：入场首次请求、权威profile／ACK push驱动，显式领取超时10秒最多查询一次状态，不自动重发领取。其本地可见性／超时检查仍保留。**这只去掉重复请求，原legacy好礼payload及付款能力、模式结果、通知等剩余大包尚不能标为全部≤50 B。**

## 本阶段验证与限制

以下为实际模块的离线／模拟测试，不是新native或FPS结果：

| 命令 | 结果 |
| --- | --- |
| `python -X utf8 -B tools/test_ui_static_catalog.py` | 24通过；计划ID／字段、真实8／19／439、跨级描述、binary64、不可变来源、双root同schema零重复初始化 |
| `node tools/test_compact_production.cjs` | 5通过；显式draft metadata，最终不可变目录须重测 |
| `lua scripts/vscripts/tests/test_compact_production.lua` | 原队列／私有装饰、1000稳定、nonce／ABA／取消／owner边界通过 |
| `lua scripts/vscripts/tests/test_compact_vip.lua` | 四owner、1000稳定零发送／等级扫描、unknown／close／reset／world通过 |
| `node tools/test_compact_vip.cjs` | 实际徽章controller、旧回调／reload退役、零legacy请求／claim通过 |
| `node tools/test_hero_ui_consumers.cjs` | 175作者文件审计通过，六原生能力／三权限guard保留 |
| `node --test tools/test_public_beta_gift_ui.cjs` | 22通过；无profile不反复请求、领取nonce／ACK／超时／退役等 |
| `lua scripts/vscripts/tests/test_worker_capacity_change.lua` | 主操作者报告真实容量变化与reset触发通过 |

生产draft校准估算：训练首full30帧／1469 B、研究full69帧／3369 B、一次训练变化13帧／625 B，最大单帧49 B；这些是复用已测消息开销的模拟计数，**不是新native实测**，总量也不能由单帧上限替代。主操作者报告本阶段32个运行文件官方编译通过，来源及新产物提交尚待；现有测试不证明最终新schema、生产／VIP实机交互或FPS合格。

Dev05的93帧／最大49 B及73批静态扫描是真实旧phase2范围，详见[前阶段原生证据及失败边界](network50_grid_selected_handoff_20261103.md)。本阶段生产、VIP、英雄gate、Beta和容量触发尚未进行新同源native验收。有效FPS样本仍为零。

## 历史编译工具修复

历史manifest缺12个layout依赖、archive CSS缺9个图片依赖，以及shop JS物理mixed-EOL误挡，已在树外完整609输入闭包重编三项成功，未覆盖runtime或正式包。原临时工具未绑定operator commit的proof只作诊断，不冒充发行authority。

通用`tools/release_compile_scope.py`已补XML src/layoutfile、CSS图片URL/import及VTEX像素闭包；仅从不可变Git导出CRLF，工作区物理EOL不再参与构建。plan必须指定operator commit，实际加载tool及inventory源码也核对该commit；编译结果验证v12块边界和JS DATA实际字节。12专项测试通过。新operator冻结后须标准CLI重新规划，必要时fresh stage重编；不能给旧proof改标签。完整历史pending、生产保护转换、recipe／ledger／authority、签名／普通准入／SDK及官方下载仍阻断，待发不清零。

## 后续追加：S1严格Git gen3已生成，最终产物提交及新native待办

本节追加发生在上方draft阶段之后；原draft测试及旧fe1718范围保留为历史。**仍仅本地更新，后台未改。** phase3 source／operator已冻结并push为game `8a48c567e5121ff946f1ce6f9ebbb6dc855fd4c8`，content `14c562b9139bba820decc885132f38095b8a4d93`；历史atlas显式绑定game `0056e2bf88106a2045b0575011196d15b7ee2383`。seed、运行schema、公开配置及历史全部从声明Git blob读取，无工作区回退。

strict gen3 schema为 `26f900989a7546e089e0b0c28521723ee8e338ccd2e2a46d6d921ece7b54f75e`，registry为 `aac87becdf165a71c78938f52ee359d60c88f6ca45d8d0a9a7cebceb6e546863`。generation11、7932 records／186 fields；全部7887个旧ID和163个旧字段逐项不变，只尾部追加45条记录和23字段，十个祖先均校验通过。220个game、4个operator、6个atlas参考源的摘要完整列入生成manifest；content revision仅是配套编译来源，生成器没有读取content blob，不能当作编译／美术绑定证明。

| gen3 game产物 | 规范LF SHA256 |
| --- | --- |
| `panorama/src/scripts/custom_game/common/ui_static_catalog.js`（4798146 B） | `a82e78dae5d92f967ad07f3b0fad7611eb36f960a3b59a78f230206154203606` |
| `scripts/vscripts/config/generated/ui_static_catalog_lookup.lua`（3383461 B） | `5c9fa3e6ce9cd8c117da0302a22596a22fa0c0c083e43534562ec7c2a9974037` |
| `data/ui/ui_static_catalog_manifest.json` | `1470bfb5171b741370ba4a06ec868102cc125a3b1aea5ca78fa532c4782daa1f` |

输出均LF、无CR；content镜像及官方编译由主操作者单独处理。严格同参数`--check`已复现所有字节，JS语法通过。实际runtime registry的production Lua及Node5重新通过，Node明确输出`actual runtime registry`，不再augment draft metadata；wire15、runtime16、VIP Lua与实际controller、工人容量真实tracker也重跑通过。上述均为离线真实模块／调用计数，不是新native／FPS或普通客户端验收。

S1/C1为生成输入冻结，不是包含新gen3输出的最终artifact提交。下一步由主操作者完成同源官方编译、两仓产物提交，再fresh独立Dev06验证生产／VIP与余下legacy及FPS；整个待发／保护／发行链仍按前文阻断，不据此标“已同步游廊”。
